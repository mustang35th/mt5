//+------------------------------------------------------------------+
//|                           CurrencyStrengthResultDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH
#define MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH

#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 通貨単位の通貨強弱集計結果をSQLiteへ保存するDAO。
 */
class CurrencyStrengthResultDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    CurrencyStrengthResultDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 通貨別集計結果テーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_results (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "currency_name TEXT NOT NULL,";
        sql += "mn1_score INTEGER NOT NULL,";
        sql += "w1_score INTEGER NOT NULL,";
        sql += "d1_score INTEGER NOT NULL,";
        sql += "h4_score INTEGER NOT NULL,";
        sql += "h1_score INTEGER NOT NULL,";
        sql += "m15_score INTEGER NOT NULL,";
        sql += "total_score INTEGER NOT NULL,";
        sql += "mn1_sample_count INTEGER NOT NULL,";
        sql += "w1_sample_count INTEGER NOT NULL,";
        sql += "d1_sample_count INTEGER NOT NULL,";
        sql += "h4_sample_count INTEGER NOT NULL,";
        sql += "h1_sample_count INTEGER NOT NULL,";
        sql += "m15_sample_count INTEGER NOT NULL,";
        sql += "total_sample_count INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "updated_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, currency_name)";
        sql += ")";

        if (!this.executeSql(sql, "currency_strength_results table")) {
            return false;
        }

        if (!this.migrateTimeFrameColumns()) {
            return false;
        }

        if (!this.migrateUpdatedAtColumns()) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_results_run_currency ";
        sql += "ON currency_strength_results(run_id, currency_name)";

        if (!this.executeSql(sql, "currency strength result index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "currency_strength_results table and index are ready."
        );

        return true;
    }

    /**
     * 通貨別集計結果レコードを1つの準備済みリクエストで保存する。
     *
     * @param fromEntities 保存対象エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool insertAll(CurrencyStrengthResultEntity &fromEntities[]) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        int entityCount = ArraySize(fromEntities);

        if (entityCount == 0) {
            return true;
        }

        string sql = "INSERT INTO currency_strength_results (";
        sql += "run_id, currency_name, mn1_score, w1_score, d1_score, h4_score,";
        sql += " h1_score, m15_score, total_score, mn1_sample_count,";
        sql += " w1_sample_count, d1_sample_count, h4_sample_count,";
        sql += " h1_sample_count, m15_sample_count, total_sample_count,";
        sql += " updated_at, updated_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,";
        sql += " ?13, ?14, ?15, ?16, ?17, ?18";
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

            if (!this.bindEntity(requestHandle, fromEntities[i])) {
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
                StringFormat("insert result index=%d", i)
            )) {
                DatabaseFinalize(requestHandle);

                return false;
            }
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 既存の通貨別集計結果テーブルへMN1・W1列を追加する。
     *
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool migrateTimeFrameColumns() {
        if (!this.ensureColumn("mn1_score", "INTEGER NOT NULL DEFAULT 0")) {
            return false;
        }

        if (!this.ensureColumn("w1_score", "INTEGER NOT NULL DEFAULT 0")) {
            return false;
        }

        if (!this.ensureColumn(
            "mn1_sample_count",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        return this.ensureColumn(
            "w1_sample_count",
            "INTEGER NOT NULL DEFAULT 0"
        );
    }

    /**
     * 既存の通貨別集計結果テーブルへレコード更新時刻列を追加して値を補完する。
     *
     * @return 列追加と既存値の補完に成功した場合はtrue。
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

        string sql = "UPDATE currency_strength_results ";
        sql += "SET updated_at = COALESCE((";
        sql += "SELECT updated_at FROM currency_strength_runs ";
        sql += "WHERE currency_strength_runs.id = ";
        sql += "currency_strength_results.run_id";
        sql += "), CAST(strftime('%s', 'now') AS INTEGER)) ";
        sql += "WHERE updated_at = 0";

        if (!this.executeSql(sql, "currency strength result updated at migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_results ";
        sql += "SET updated_at_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', updated_at, 'unixepoch') ";
        sql += "WHERE updated_at_text = ''";

        return this.executeSql(
            sql,
            "currency strength result updated at text migration"
        );
    }

    /**
     * 通貨別集計結果テーブルに指定列が存在することを保証する。
     *
     * @param fromColumnName 確認・追加する列名。
     * @param fromColumnDefinition 追加する列の定義。
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool ensureColumn(
        const string fromColumnName,
        const string fromColumnDefinition
    ) {
        bool hasColumnValue = false;

        if (!this.hasColumn(fromColumnName, hasColumnValue)) {
            return false;
        }

        if (hasColumnValue) {
            return true;
        }

        string sql = "ALTER TABLE currency_strength_results ADD COLUMN ";
        sql += fromColumnName;
        sql += " ";
        sql += fromColumnDefinition;

        return this.executeSql(
            sql,
            StringFormat("currency strength result column %s", fromColumnName)
        );
    }

    /**
     * 通貨別集計結果テーブルに指定列が存在するか確認する。
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
            "PRAGMA table_info(currency_strength_results)"
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
     * 通貨別集計結果レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bindEntity(
        const int fromRequestHandle,
        CurrencyStrengthResultEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 1, fromEntity.currencyName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 2, fromEntity.mn1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 3, fromEntity.w1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 4, fromEntity.d1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 5, fromEntity.h4Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 6, fromEntity.h1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 7, fromEntity.m15Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 8, fromEntity.totalScore);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                9,
                fromEntity.mn1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                10,
                fromEntity.w1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                11,
                fromEntity.d1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                12,
                fromEntity.h4SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                13,
                fromEntity.h1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                14,
                fromEntity.m15SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                15,
                fromEntity.totalSampleCount
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

#endif // MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH
