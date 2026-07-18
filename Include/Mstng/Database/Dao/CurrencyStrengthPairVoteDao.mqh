//+------------------------------------------------------------------+
//|                            CurrencyStrengthPairVoteDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_PAIR_VOTE_DAO_MQH
#define MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_PAIR_VOTE_DAO_MQH

#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 通貨ペア・時間足単位の通貨強弱票をSQLiteへ保存するDAO。
 */
class CurrencyStrengthPairVoteDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    CurrencyStrengthPairVoteDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 票内訳テーブル、表示用文字列列、インデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_pair_votes (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "pair_order INTEGER NOT NULL,";
        sql += "time_frame_order INTEGER NOT NULL,";
        sql += "canonical_symbol_name TEXT NOT NULL,";
        sql += "resolved_symbol_name TEXT NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "time_frame_text TEXT NOT NULL,";
        sql += "bar_time INTEGER NOT NULL,";
        sql += "bar_time_text TEXT NOT NULL,";
        sql += "base_currency TEXT NOT NULL,";
        sql += "quote_currency TEXT NOT NULL,";
        sql += "is_buy INTEGER NOT NULL CHECK(is_buy IN (0, 1)),";
        sql += "oscillator_count INTEGER NOT NULL,";
        sql += "base_score INTEGER NOT NULL CHECK(base_score IN (-1, 1)),";
        sql += "base_score_after INTEGER NOT NULL,";
        sql += "quote_score_after INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "updated_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, pair_order, time_frame_order)";
        sql += ")";

        if (!this.executeSql(sql, "currency_strength_pair_votes table")) {
            return false;
        }

        if (!this.migrateTextColumns()) {
            return false;
        }

        if (!this.migrateTimeFrameOrder()) {
            return false;
        }

        if (!this.migrateUpdatedAtColumns()) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_votes_run_order ";
        sql += "ON currency_strength_pair_votes(";
        sql += "run_id, pair_order, time_frame_order";
        sql += ")";

        if (!this.executeSql(sql, "currency strength vote index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "currency_strength_pair_votes table is ready."
        );

        return true;
    }

    /**
     * 票内訳レコードを1つの準備済みリクエストで保存する。
     *
     * @param fromEntities 保存対象エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool insertAll(CurrencyStrengthPairVoteEntity &fromEntities[]) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        int entityCount = ArraySize(fromEntities);

        if (entityCount == 0) {
            return true;
        }

        string sql = "INSERT INTO currency_strength_pair_votes (";
        sql += "run_id, pair_order, time_frame_order, canonical_symbol_name,";
        sql += " resolved_symbol_name, time_frame, time_frame_text, bar_time,";
        sql += " bar_time_text, base_currency, quote_currency, is_buy,";
        sql += " oscillator_count, base_score, base_score_after,";
        sql += " quote_score_after, updated_at, updated_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,";
        sql += " ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18";
        sql += ")";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        for (int i = 0; i < entityCount; i++) {
            if (i > 0) {
                ResetLastError();

                if (!DatabaseReset(requestHandle)) {
                    int resetErrorCode = GetLastError();
                    DatabaseFinalize(requestHandle);
                    this.logger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseReset failed. index=%d error=%d",
                            i,
                            resetErrorCode
                        )
                    );

                    return false;
                }
            }

            ResetLastError();

            if (!this.bind(requestHandle, fromEntities[i])) {
                int bindErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseBind failed. index=%d error=%d",
                        i,
                        bindErrorCode
                    )
                );

                return false;
            }

            if (!this.executeRequest(
                requestHandle,
                __FUNCTION__,
                StringFormat("insert pair vote index=%d", i)
            )) {
                DatabaseFinalize(requestHandle);

                return false;
            }
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 基軸・決済通貨の票を1通貨1行へ展開する確認用ビューを作成する。
     *
     * @return 作成または再作成に成功した場合はtrue。
     */
    bool createContributionsView() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.executeSql(
            "DROP VIEW IF EXISTS currency_strength_contributions",
            "drop currency_strength_contributions view"
        )) {
            return false;
        }

        string sql = "CREATE VIEW currency_strength_contributions AS ";
        sql += "SELECT v.id AS vote_id,";
        sql += "v.run_id AS run_id,";
        sql += "r.calculated_at AS calculated_at,";
        sql += "r.m15_bar_time AS m15_bar_time,";
        sql += "v.pair_order AS pair_order,";
        sql += "v.time_frame_order AS time_frame_order,";
        sql += "v.canonical_symbol_name AS canonical_symbol_name,";
        sql += "v.resolved_symbol_name AS resolved_symbol_name,";
        sql += "v.time_frame AS time_frame,";
        sql += "v.time_frame_text AS time_frame_text,";
        sql += "v.bar_time AS bar_time,";
        sql += "v.bar_time_text AS bar_time_text,";
        sql += "v.updated_at AS updated_at,";
        sql += "v.updated_at_text AS updated_at_text,";
        sql += "'BASE' AS currency_side,";
        sql += "v.base_currency AS currency_name,";
        sql += "v.base_score AS score,";
        sql += "v.base_score_after AS score_after,";
        sql += "v.is_buy AS is_buy,";
        sql += "v.oscillator_count AS oscillator_count ";
        sql += "FROM currency_strength_pair_votes v ";
        sql += "INNER JOIN currency_strength_runs r ON r.id = v.run_id ";
        sql += "UNION ALL ";
        sql += "SELECT v.id AS vote_id,";
        sql += "v.run_id AS run_id,";
        sql += "r.calculated_at AS calculated_at,";
        sql += "r.m15_bar_time AS m15_bar_time,";
        sql += "v.pair_order AS pair_order,";
        sql += "v.time_frame_order AS time_frame_order,";
        sql += "v.canonical_symbol_name AS canonical_symbol_name,";
        sql += "v.resolved_symbol_name AS resolved_symbol_name,";
        sql += "v.time_frame AS time_frame,";
        sql += "v.time_frame_text AS time_frame_text,";
        sql += "v.bar_time AS bar_time,";
        sql += "v.bar_time_text AS bar_time_text,";
        sql += "v.updated_at AS updated_at,";
        sql += "v.updated_at_text AS updated_at_text,";
        sql += "'QUOTE' AS currency_side,";
        sql += "v.quote_currency AS currency_name,";
        sql += "(0 - v.base_score) AS score,";
        sql += "v.quote_score_after AS score_after,";
        sql += "v.is_buy AS is_buy,";
        sql += "v.oscillator_count AS oscillator_count ";
        sql += "FROM currency_strength_pair_votes v ";
        sql += "INNER JOIN currency_strength_runs r ON r.id = v.run_id";

        return this.executeSql(sql, "currency_strength_contributions view");
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 既存の票内訳テーブルへ更新時刻列を追加して値を補完する。
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

        string sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET updated_at = COALESCE((";
        sql += "SELECT updated_at FROM currency_strength_runs ";
        sql += "WHERE id = currency_strength_pair_votes.run_id";
        sql += "), NULLIF(bar_time, 0), ";
        sql += "CAST(strftime('%s', 'now') AS INTEGER)) ";
        sql += "WHERE updated_at = 0";

        if (!this.executeSql(sql, "pair vote updated at migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET updated_at_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', updated_at, 'unixepoch') ";
        sql += "WHERE updated_at_text = ''";

        return this.executeSql(sql, "pair vote updated at text migration");
    }

    /**
     * 票内訳テーブルに指定列が存在することを保証する。
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

        string sql = "ALTER TABLE currency_strength_pair_votes ADD COLUMN ";
        sql += fromColumnName + " " + fromColumnDefinition;

        return this.executeSql(
            sql,
            StringFormat("currency strength pair vote column %s", fromColumnName)
        );
    }

    /**
     * 既存の票内訳テーブルへ表示用文字列列を追加して値を補完する。
     *
     * @return 列追加と既存値の補完に成功した場合はtrue。
     */
    bool migrateTextColumns() {
        if (!this.ensureTextColumn("time_frame_text")) {
            return false;
        }

        if (!this.ensureTextColumn("bar_time_text")) {
            return false;
        }

        string sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET time_frame_text = CASE time_frame ";
        sql += StringFormat("WHEN %d THEN 'MN1' ", (int)PERIOD_MN1);
        sql += StringFormat("WHEN %d THEN 'W1' ", (int)PERIOD_W1);
        sql += StringFormat("WHEN %d THEN 'D1' ", (int)PERIOD_D1);
        sql += StringFormat("WHEN %d THEN 'H4' ", (int)PERIOD_H4);
        sql += StringFormat("WHEN %d THEN 'H1' ", (int)PERIOD_H1);
        sql += StringFormat("WHEN %d THEN 'M15' ", (int)PERIOD_M15);
        sql += "ELSE CAST(time_frame AS TEXT) END ";
        sql += "WHERE time_frame_text = ''";

        if (!this.executeSql(sql, "pair vote time frame text migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET bar_time_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', bar_time, 'unixepoch') ";
        sql += "WHERE bar_time_text = ''";

        return this.executeSql(sql, "pair vote bar time text migration");
    }

    /**
     * 既存4時間足データの集計順を6時間足の共通順へ移行する。
     *
     * UNIQUE制約との衝突を避けるため一時的な負数へ退避してから、
     * D1、H4、H1、M15を2、3、4、5へ移動する。
     *
     * @return 移行に成功した場合はtrue。
     */
    bool migrateTimeFrameOrder() {
        ResetLastError();

        if (!DatabaseTransactionBegin(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionBegin failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        string sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET time_frame_order = -100 - time_frame_order WHERE ";
        sql += StringFormat(
            "(time_frame_order = 0 AND time_frame = %d) ",
            (int)PERIOD_D1
        );
        sql += StringFormat(
            "OR (time_frame_order = 1 AND time_frame = %d) ",
            (int)PERIOD_H4
        );
        sql += StringFormat(
            "OR (time_frame_order = 2 AND time_frame = %d) ",
            (int)PERIOD_H1
        );
        sql += StringFormat(
            "OR (time_frame_order = 3 AND time_frame = %d)",
            (int)PERIOD_M15
        );

        if (!this.executeSql(sql, "pair vote time frame order staging")) {
            this.rollbackTimeFrameOrderMigration();

            return false;
        }

        sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET time_frame_order = CASE time_frame ";
        sql += StringFormat("WHEN %d THEN 2 ", (int)PERIOD_D1);
        sql += StringFormat("WHEN %d THEN 3 ", (int)PERIOD_H4);
        sql += StringFormat("WHEN %d THEN 4 ", (int)PERIOD_H1);
        sql += StringFormat("WHEN %d THEN 5 ", (int)PERIOD_M15);
        sql += "ELSE time_frame_order END WHERE ";
        sql += StringFormat(
            "(time_frame_order = -100 AND time_frame = %d) ",
            (int)PERIOD_D1
        );
        sql += StringFormat(
            "OR (time_frame_order = -101 AND time_frame = %d) ",
            (int)PERIOD_H4
        );
        sql += StringFormat(
            "OR (time_frame_order = -102 AND time_frame = %d) ",
            (int)PERIOD_H1
        );
        sql += StringFormat(
            "OR (time_frame_order = -103 AND time_frame = %d)",
            (int)PERIOD_M15
        );

        if (!this.executeSql(sql, "pair vote time frame order migration")) {
            this.rollbackTimeFrameOrderMigration();

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(this.databaseHandle)) {
            int commitErrorCode = GetLastError();
            this.rollbackTimeFrameOrderMigration();
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionCommit failed. error=%d",
                    commitErrorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * 時間足順移行トランザクションをロールバックする。
     */
    void rollbackTimeFrameOrderMigration() {
        ResetLastError();

        if (!DatabaseTransactionRollback(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionRollback failed. error=%d",
                    GetLastError()
                )
            );
        }
    }

    /**
     * 票内訳テーブルに表示用文字列列が存在することを保証する。
     *
     * @param fromColumnName 確認・追加する列名。
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool ensureTextColumn(const string fromColumnName) {
        bool hasColumn = false;

        if (!this.hasColumn(fromColumnName, hasColumn)) {
            return false;
        }

        if (hasColumn) {
            return true;
        }

        string sql = "ALTER TABLE currency_strength_pair_votes ADD COLUMN ";
        sql += fromColumnName;
        sql += " TEXT NOT NULL DEFAULT ''";

        return this.executeSql(
            sql,
            StringFormat("currency strength pair vote column %s", fromColumnName)
        );
    }

    /**
     * 票内訳テーブルに指定列が存在するか確認する。
     *
     * @param fromColumnName 確認する列名。
     * @param fromHasColumn 列が存在する場合にtrueを設定する。
     * @return テーブル情報の取得に成功した場合はtrue。
     */
    bool hasColumn(
        const string fromColumnName,
        bool &fromHasColumn
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(currency_strength_pair_votes)"
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
     * 票内訳レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bind(
        const int fromRequestHandle,
        CurrencyStrengthPairVoteEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 1, fromEntity.pairOrder);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                2,
                fromEntity.timeFrameOrder
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                3,
                fromEntity.canonicalSymbolName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                4,
                fromEntity.resolvedSymbolName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 5, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                6,
                fromEntity.timeFrameText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 7, fromEntity.barTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                8,
                fromEntity.barTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 9, fromEntity.baseCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 10, fromEntity.quoteCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 11, fromEntity.isBuy);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                12,
                fromEntity.oscillatorCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 13, fromEntity.baseScore);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                14,
                fromEntity.baseScoreAfter
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                15,
                fromEntity.quoteScoreAfter
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 16, fromEntity.updatedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                17,
                fromEntity.updatedAtText
            );
        }

        return isBound;
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

        // INSERTは結果行を返さないため正常時もNO_MORE_DATAとなる
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

#endif // MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_PAIR_VOTE_DAO_MQH
