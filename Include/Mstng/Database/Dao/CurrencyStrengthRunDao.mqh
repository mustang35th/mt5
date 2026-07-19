//+------------------------------------------------------------------+
//|                                      CurrencyStrengthRunDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RUN_DAO_MQH
#define MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RUN_DAO_MQH

#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 通貨強弱の集計履歴をSQLiteへ保存するDAO。
 */
class CurrencyStrengthRunDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    CurrencyStrengthRunDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.hasLegacyM15BarTimeColumn = false;
        this.isLegacySchemaInspected = false;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 通貨強弱の集計履歴テーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "m5_bar_time INTEGER NOT NULL DEFAULT 0,";
        sql += "m5_bar_time_text TEXT NOT NULL DEFAULT '',";
        sql += "calculated_at INTEGER NOT NULL,";
        sql += "source_mode TEXT NOT NULL DEFAULT 'LEGACY',";
        sql += "calculation_version TEXT NOT NULL,";
        sql += "is_complete INTEGER NOT NULL,";
        sql += "valid_pair_count INTEGER NOT NULL,";
        sql += "expected_pair_count INTEGER NOT NULL,";
        sql += "vote_count INTEGER NOT NULL,";
        sql += "source_server TEXT NOT NULL,";
        sql += "source_login INTEGER NOT NULL,";
        sql += "source_chart_id INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "updated_at_text TEXT NOT NULL";
        sql += ")";

        if (!this.executeSql(sql, "currency_strength_runs table")) {
            return false;
        }

        if (!this.migrateM5BarTimeColumns()) {
            return false;
        }

        if (!this.migrateSourceModeColumn()) {
            return false;
        }

        if (!this.migrateUpdatedAtColumns()) {
            return false;
        }

        if (!this.inspectLegacyM15BarTimeColumn()) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_runs_calculated_at ";
        sql += "ON currency_strength_runs(calculated_at)";

        if (!this.executeSql(sql, "currency strength run index")) {
            return false;
        }

        sql = "CREATE UNIQUE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_runs_snapshot_mode_key ";
        sql += "ON currency_strength_runs(";
        sql += "m5_bar_time, calculation_version, source_mode,";
        sql += " source_server, source_login";
        sql += ") WHERE m5_bar_time > 0";

        if (!this.executeSql(sql, "currency strength run snapshot key index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_runs_rank_lookup ";
        sql += "ON currency_strength_runs(";
        sql += "calculation_version, source_mode, source_server,";
        sql += " source_login, m5_bar_time DESC";
        sql += ") WHERE is_complete = 1 AND m5_bar_time > 0";

        if (!this.executeSql(sql, "currency strength run rank lookup index")) {
            return false;
        }

        if (!this.executeSql(
            "DROP INDEX IF EXISTS idx_currency_strength_runs_snapshot_key",
            "drop legacy currency strength run snapshot key index"
        )) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_runs_source_mode_calculated_at ";
        sql += "ON currency_strength_runs(source_mode, calculated_at)";

        if (!this.executeSql(sql, "currency strength run source mode index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "currency_strength_runs table is ready."
        );

        return true;
    }

    /**
     * 通貨強弱の集計履歴を保存する。
     *
     * 保存成功時は集計IDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insert(CurrencyStrengthRunEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.ensureLegacySchemaInspected()) {
            return false;
        }

        fromEntity.id = 0;
        string sql = this.buildInsertSql();

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        int nextParameterIndex = 0;

        if (!this.bind(requestHandle, fromEntity, nextParameterIndex)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "insert run"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        long insertId = 0;

        if (!this.getLastInsertId(insertId)) {
            return false;
        }

        fromEntity.id = insertId;

        return true;
    }

    /**
     * M5バー時刻と集計元が一致する集計IDを取得する。
     *
     * 該当レコードが存在しない場合はfromRunIdへ0を設定してtrueを返す。
     *
     * @param fromM5BarTime 集計基準となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromRunId 取得した集計IDの格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findIdBySnapshotKey(
        const datetime fromM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        long &fromRunId
    ) {
        fromRunId = 0;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromM5BarTime <= 0) {
            return true;
        }

        string sql = "SELECT id FROM currency_strength_runs ";
        sql += "WHERE m5_bar_time = ?1 ";
        sql += "AND calculation_version = ?2 ";
        sql += "AND source_mode = ?3 ";
        sql += "AND source_server = ?4 ";
        sql += "AND source_login = ?5 ";
        sql += "ORDER BY id DESC LIMIT 1";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();
        bool isBound = DatabaseBind(requestHandle, 0, fromM5BarTime);

        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                1,
                fromCalculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromSourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 3, fromSourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 4, fromSourceLogin);
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromRunId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 既存の通貨強弱集計履歴を更新する。
     *
     * @param fromEntity 更新対象エンティティ。
     * @return 更新処理に成功した場合true。
     */
    bool update(CurrencyStrengthRunEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.ensureLegacySchemaInspected()) {
            return false;
        }

        if (fromEntity.id <= 0) {
            this.logger.error(__FUNCTION__, "fromEntity.id is invalid.");

            return false;
        }

        string sql = this.buildUpdateSql();

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();
        int nextParameterIndex = 0;
        bool isBound = this.bind(
            requestHandle,
            fromEntity,
            nextParameterIndex
        );

        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                nextParameterIndex,
                fromEntity.id
            );
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "update run"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

    /**
     * 指定時刻より古い集計履歴を削除する。
     *
     * 外部キーのCASCADEが有効な場合は関連レコードも削除される。
     *
     * @param fromCalculatedAt 削除対象を判定する集計時刻。
     * @param fromSourceMode 削除対象の集計実行モード。
     * @return 削除処理に成功した場合はtrue。
     */
    bool deleteBefore(
        const datetime fromCalculatedAt,
        const string fromSourceMode
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "DELETE FROM currency_strength_runs ";
        sql += "WHERE calculated_at < ?1 AND source_mode = ?2";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        bool isBound = DatabaseBind(requestHandle, 0, fromCalculatedAt);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromSourceMode);
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "delete old runs"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** 旧M15バー時刻列の存在有無。 */
    bool hasLegacyM15BarTimeColumn;

    /** 旧スキーマ確認済みフラグ。 */
    bool isLegacySchemaInspected;

    /** ロガー。 */
    Logger logger;

    /**
     * 新旧スキーマに対応するINSERT文を生成する。
     *
     * @return INSERT文。
     */
    string buildInsertSql() {
        string sql = "INSERT INTO currency_strength_runs (";
        sql += "m5_bar_time, m5_bar_time_text, calculated_at";

        if (this.hasLegacyM15BarTimeColumn) {
            sql += ", m15_bar_time";
        }

        sql += ", source_mode, calculation_version, is_complete";
        sql += ", valid_pair_count, expected_pair_count, vote_count";
        sql += ", source_server, source_login, source_chart_id";
        sql += ", updated_at, updated_at_text) VALUES (";
        int parameterCount = 14;

        if (this.hasLegacyM15BarTimeColumn) {
            parameterCount = 15;
        }

        for (int i = 1; i <= parameterCount; i++) {
            if (i > 1) {
                sql += ", ";
            }

            sql += StringFormat("?%d", i);
        }

        sql += ")";

        return sql;
    }

    /**
     * 新旧スキーマに対応するUPDATE文を生成する。
     *
     * @return UPDATE文。
     */
    string buildUpdateSql() {
        string sql = "UPDATE currency_strength_runs SET ";
        sql += "m5_bar_time = ?1, m5_bar_time_text = ?2, ";
        sql += "calculated_at = ?3";
        int parameterNumber = 4;

        if (this.hasLegacyM15BarTimeColumn) {
            sql += StringFormat(", m15_bar_time = ?%d", parameterNumber);
            parameterNumber++;
        }

        sql += StringFormat(", source_mode = ?%d", parameterNumber++);
        sql += StringFormat(", calculation_version = ?%d", parameterNumber++);
        sql += StringFormat(", is_complete = ?%d", parameterNumber++);
        sql += StringFormat(", valid_pair_count = ?%d", parameterNumber++);
        sql += StringFormat(", expected_pair_count = ?%d", parameterNumber++);
        sql += StringFormat(", vote_count = ?%d", parameterNumber++);
        sql += StringFormat(", source_server = ?%d", parameterNumber++);
        sql += StringFormat(", source_login = ?%d", parameterNumber++);
        sql += StringFormat(", source_chart_id = ?%d", parameterNumber++);
        sql += StringFormat(", updated_at = ?%d", parameterNumber++);
        sql += StringFormat(", updated_at_text = ?%d", parameterNumber++);
        sql += StringFormat(" WHERE id = ?%d", parameterNumber);

        return sql;
    }

    /**
     * 旧M15バー時刻列の存在有無を確認する。
     *
     * @return 確認に成功した場合true。
     */
    bool inspectLegacyM15BarTimeColumn() {
        bool hasColumnValue = false;

        if (!this.hasColumn("m15_bar_time", hasColumnValue)) {
            return false;
        }

        this.hasLegacyM15BarTimeColumn = hasColumnValue;
        this.isLegacySchemaInspected = true;

        return true;
    }

    /**
     * 旧スキーマが確認済みであることを保証する。
     *
     * @return 確認済みまたは確認に成功した場合true。
     */
    bool ensureLegacySchemaInspected() {
        if (this.isLegacySchemaInspected) {
            return true;
        }

        return this.inspectLegacyM15BarTimeColumn();
    }

    /**
     * 既存の集計履歴テーブルへM5バー時刻列を追加する。
     *
     * 旧レコードは時刻を推測せず0と空文字のまま保持する。
     *
     * @return 列追加または存在確認に成功した場合true。
     */
    bool migrateM5BarTimeColumns() {
        if (!this.ensureColumn(
            "m5_bar_time",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        return this.ensureColumn(
            "m5_bar_time_text",
            "TEXT NOT NULL DEFAULT ''"
        );
    }

    /**
     * 既存の集計履歴テーブルへ集計実行モード列を追加する。
     *
     * 移行前レコードはライブまたはテスターを判別できないためLEGACYとする。
     *
     * @return 列追加または存在確認に成功した場合true。
     */
    bool migrateSourceModeColumn() {
        return this.ensureColumn(
            "source_mode",
            "TEXT NOT NULL DEFAULT 'LEGACY'"
        );
    }

    /**
     * 既存の集計履歴テーブルへ更新時刻列を追加して値を補完する。
     *
     * @return 列追加と既存値の補完に成功した場合true。
     */
    bool migrateUpdatedAtColumns() {
        if (!this.ensureColumn(
            "updated_at",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "updated_at_text",
            "TEXT NOT NULL DEFAULT ''"
        )) {
            return false;
        }

        string sql = "UPDATE currency_strength_runs ";
        sql += "SET updated_at = CASE ";
        sql += "WHEN calculated_at > 0 THEN calculated_at ";
        sql += "ELSE CAST(strftime('%s', 'now') AS INTEGER) END ";
        sql += "WHERE updated_at = 0";

        if (!this.executeSql(sql, "currency strength run updated at migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_runs ";
        sql += "SET updated_at_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', updated_at, 'unixepoch', 'localtime') ";
        sql += "WHERE updated_at_text = ''";

        return this.executeSql(
            sql,
            "currency strength run updated at text migration"
        );
    }

    /**
     * 集計履歴テーブルに指定列が存在することを保証する。
     *
     * @param fromColumnName 確認・追加する列名。
     * @param fromColumnDefinition 追加する列定義。
     * @return 列の存在確認または追加に成功した場合true。
     */
    bool ensureColumn(
        const string fromColumnName,
        const string fromColumnDefinition
    ) {
        bool hasColumn = false;

        if (!this.hasColumn(fromColumnName, hasColumn)) {
            return false;
        }

        if (hasColumn) {
            return true;
        }

        string sql = "ALTER TABLE currency_strength_runs ADD COLUMN ";
        sql += fromColumnName + " " + fromColumnDefinition;

        return this.executeSql(
            sql,
            StringFormat("currency strength run column %s", fromColumnName)
        );
    }

    /**
     * 集計履歴テーブルに指定列が存在するか確認する。
     *
     * @param fromColumnName 確認する列名。
     * @param fromHasColumn 列が存在する場合にtrueを設定する。
     * @return テーブル情報の取得に成功した場合true。
     */
    bool hasColumn(
        const string fromColumnName,
        bool &fromHasColumn
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(currency_strength_runs)"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        while (true) {
            ResetLastError();

            if (!DatabaseRead(requestHandle)) {
                int readErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);

                if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                    this.logger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseRead failed. error=%d",
                            readErrorCode
                        )
                    );

                    return false;
                }

                return true;
            }

            string columnName = "";
            ResetLastError();

            if (!DatabaseColumnText(requestHandle, 1, columnName)) {
                int columnErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseColumnText failed. error=%d",
                        columnErrorCode
                    )
                );

                return false;
            }

            if (columnName == fromColumnName) {
                fromHasColumn = true;
                DatabaseFinalize(requestHandle);

                return true;
            }
        }
    }

    /**
     * 集計履歴のパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @param fromNextParameterIndex 次に使用するパラメーター位置の格納先。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bind(
        const int fromRequestHandle,
        CurrencyStrengthRunEntity &fromEntity,
        int &fromNextParameterIndex
    ) {
        fromNextParameterIndex = 0;
        bool isBound = DatabaseBind(
            fromRequestHandle,
            fromNextParameterIndex++,
            fromEntity.m5BarTime
        );

        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.m5BarTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.calculatedAt
            );
        }

        if (isBound && this.hasLegacyM15BarTimeColumn) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                this.calculateLegacyM15BarTime(fromEntity.m5BarTime)
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.sourceMode
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.calculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.isComplete
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.validPairCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.expectedPairCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.voteCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.sourceServer
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.sourceLogin
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.sourceChartId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.updatedAt
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromNextParameterIndex++,
                fromEntity.updatedAtText
            );
        }

        return isBound;
    }

    /**
     * 旧DB互換用のM15バー時刻をM5バー時刻から算出する。
     *
     * @param fromM5BarTime M5バー時刻。
     * @return 対応するM15バー開始時刻。
     */
    datetime calculateLegacyM15BarTime(const datetime fromM5BarTime) {
        long m5BarTimeValue = (long)fromM5BarTime;
        int m15PeriodSeconds = PeriodSeconds(PERIOD_M15);

        if (m5BarTimeValue <= 0 || m15PeriodSeconds <= 0) {
            return 0;
        }

        return (datetime)(
            m5BarTimeValue - m5BarTimeValue % m15PeriodSeconds
        );
    }

    /**
     * 直前に追加したレコードIDを取得する。
     *
     * @param fromInsertId 取得したIDの格納先。
     * @return IDを取得できた場合はtrue。
     */
    bool getLastInsertId(long &fromInsertId) {
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "SELECT last_insert_rowid()"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromInsertId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (fromInsertId <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("Invalid insert id. id=%I64d", fromInsertId)
            );

            return false;
        }

        return true;
    }

    /**
     * 結果行を返さない準備済みリクエストを実行する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合はtrue。
     */
    bool executeRequest(
        const int fromRequestHandle,
        const string fromMethodName,
        const string fromOperationName
    ) {
        ResetLastError();
        bool isRead = DatabaseRead(fromRequestHandle);
        int errorCode = GetLastError();

        // INSERTとDELETEは結果行を返さないため正常時もNO_MORE_DATAとなる
        if (!isRead && errorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseRead failed. operation=%s error=%d",
                    fromOperationName,
                    errorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * SQLを直接実行する。
     *
     * @param fromSql SQL文字列。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合はtrue。
     */
    bool executeSql(
        const string fromSql,
        const string fromOperationName
    ) {
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, fromSql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. operation=%s error=%d",
                    fromOperationName,
                    GetLastError()
                )
            );

            return false;
        }

        return true;
    }

    /**
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合はtrue。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RUN_DAO_MQH
