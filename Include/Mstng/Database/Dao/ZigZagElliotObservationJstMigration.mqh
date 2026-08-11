//+------------------------------------------------------------------+
//|              ZigZagElliotObservationJstMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_JST_MIGRATION_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_JST_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliot観測テーブルへ日本時刻列を追加し、既存値を補完するクラス。
 */
class ZigZagElliotObservationJstMigration {
public:
    /**
     * 日本時刻列を追加し、未補完行をサーバー時刻から一括変換する。
     *
     * 移行中だけbusy_timeoutを60秒へ延長し、処理後は呼出し前の値へ戻す。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromServerTimeColumnName 変換元サーバー時刻列名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @return 列追加と既存値の補完に成功した場合true。
     */
    static bool execute(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromServerTimeColumnName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName
    ) {
        Logger logger;
        logger.setLevel(LOG_INFO);

        if (fromDatabaseHandle == INVALID_HANDLE
                || fromTableName == ""
                || fromServerTimeColumnName == ""
                || fromJstTimeColumnName == ""
                || fromJstTimeTextColumnName == "") {
            logger.error(__FUNCTION__, "JST migration argument is invalid.");

            return false;
        }

        if (isFastPathComplete(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                logger
            )) {
            return true;
        }

        long originalBusyTimeout = 0;

        if (!readBusyTimeout(
                fromDatabaseHandle,
                originalBusyTimeout,
                logger
            )) {
            return false;
        }

        int originalBusyTimeoutMilliseconds = (int)originalBusyTimeout;

        if (!setBusyTimeout(fromDatabaseHandle, 60000, logger)) {
            setBusyTimeout(
                fromDatabaseHandle,
                originalBusyTimeoutMilliseconds,
                logger
            );

            return false;
        }

        bool isSucceeded = executeTransaction(
            fromDatabaseHandle,
            fromTableName,
            fromServerTimeColumnName,
            fromJstTimeColumnName,
            fromJstTimeTextColumnName,
            logger
        );
        bool isTimeoutRestored = setBusyTimeout(
            fromDatabaseHandle,
            originalBusyTimeoutMilliseconds,
            logger
        );

        if (!isTimeoutRestored) {
            return false;
        }

        return isSucceeded;
    }

private:
    /**
     * 列追加、既存値補完、検証を1トランザクションで実行する。
     *
     * BEGIN直後の更新でwrite lockを取得してからスキーマを確認するため、
     * 後続接続は先行移行のコミット後に最新状態を参照する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromServerTimeColumnName 変換元サーバー時刻列名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromLogger ロガー。
     * @return 移行に成功した場合true。
     */
    static bool executeTransaction(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromServerTimeColumnName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        Logger &fromLogger
    ) {
        ResetLastError();

        if (!DatabaseTransactionBegin(fromDatabaseHandle)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionBegin failed. table=%s error=%d",
                    fromTableName,
                    GetLastError()
                )
            );

            return false;
        }

        string lockSql = "UPDATE " + fromTableName + " SET id = id WHERE 0";

        if (!executeSql(
                fromDatabaseHandle,
                lockSql,
                "JST migration write lock",
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                "INTEGER NOT NULL DEFAULT 0",
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeTextColumnName,
                "TEXT NOT NULL DEFAULT ''",
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        if (!backfillRows(
                fromDatabaseHandle,
                fromTableName,
                fromServerTimeColumnName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        if (!ensureMissingIndex(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        if (!isBackfillComplete(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                fromLogger
            )) {
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(fromDatabaseHandle)) {
            int commitErrorCode = GetLastError();
            rollbackMigration(fromDatabaseHandle, fromTableName, fromLogger);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionCommit failed. table=%s error=%d",
                    fromTableName,
                    commitErrorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * 指定列が存在することを保証する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromColumnName 確認・追加する列名。
     * @param fromColumnDefinition 追加する列定義。
     * @param fromLogger ロガー。
     * @return 列の存在確認または追加に成功した場合true。
     */
    static bool ensureColumn(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromColumnName,
        const string fromColumnDefinition,
        Logger &fromLogger
    ) {
        bool hasColumnValue = false;

        if (!hasColumn(
                fromDatabaseHandle,
                fromTableName,
                fromColumnName,
                hasColumnValue,
                fromLogger
            )) {
            return false;
        }

        if (hasColumnValue) {
            return true;
        }

        string sql = "ALTER TABLE " + fromTableName + " ADD COLUMN ";
        sql += fromColumnName + " " + fromColumnDefinition;
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            return true;
        }

        int alterErrorCode = GetLastError();
        bool hasColumnAfterFailure = false;

        if (hasColumn(
                fromDatabaseHandle,
                fromTableName,
                fromColumnName,
                hasColumnAfterFailure,
                fromLogger
            ) && hasColumnAfterFailure) {
            fromLogger.info(
                __FUNCTION__,
                StringFormat(
                    "Column was added by another connection. table=%s column=%s",
                    fromTableName,
                    fromColumnName
                )
            );

            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "ALTER TABLE failed. table=%s column=%s error=%d",
                fromTableName,
                fromColumnName,
                alterErrorCode
            )
        );

        return false;
    }

    /**
     * 対象テーブルに指定列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromColumnName 確認する列名。
     * @param fromHasColumn 列が存在する場合trueを設定する。
     * @param fromLogger ロガー。
     * @return テーブル情報の取得に成功した場合true。
     */
    static bool hasColumn(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromColumnName,
        bool &fromHasColumn,
        Logger &fromLogger
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            fromDatabaseHandle,
            "PRAGMA table_info(" + fromTableName + ")"
        );

        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabasePrepare failed. table=%s error=%d",
                    fromTableName,
                    GetLastError()
                )
            );

            return false;
        }

        while (true) {
            ResetLastError();

            if (!DatabaseRead(requestHandle)) {
                int readErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);

                if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                    fromLogger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseRead failed. table=%s error=%d",
                            fromTableName,
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
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseColumnText failed. table=%s error=%d",
                        fromTableName,
                        columnErrorCode
                    )
                );

                return false;
            }

            if (columnName == fromColumnName) {
                DatabaseFinalize(requestHandle);
                fromHasColumn = true;

                return true;
            }
        }

        return false;
    }

    /**
     * 読み取りだけで移行済みか確認する。
     *
     * 日本時刻列、未補完部分インデックス、未補完0件が揃う場合は、
     * write transactionを開始せず通常初期化を完了する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromLogger ロガー。
     * @return 移行済みの場合true。
     */
    static bool isFastPathComplete(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        Logger &fromLogger
    ) {
        bool hasJstTimeColumn = false;
        bool hasJstTimeTextColumn = false;

        if (!hasColumn(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                hasJstTimeColumn,
                fromLogger
            ) || !hasJstTimeColumn) {
            return false;
        }

        if (!hasColumn(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeTextColumnName,
                hasJstTimeTextColumn,
                fromLogger
            ) || !hasJstTimeTextColumn) {
            return false;
        }

        string indexName = "idx_" + fromTableName + "_jst_missing";
        bool hasMissingIndex = false;

        if (!hasIndex(
                fromDatabaseHandle,
                indexName,
                hasMissingIndex,
                fromLogger
            ) || !hasMissingIndex) {
            return false;
        }

        long missingCount = 0;

        if (!readMissingCount(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                missingCount,
                fromLogger
            )) {
            return false;
        }

        return missingCount == 0;
    }

    /**
     * 指定インデックスが存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromIndexName 確認するインデックス名。
     * @param fromHasIndex インデックスが存在する場合trueを設定する。
     * @param fromLogger ロガー。
     * @return 確認に成功した場合true。
     */
    static bool hasIndex(
        const int fromDatabaseHandle,
        const string fromIndexName,
        bool &fromHasIndex,
        Logger &fromLogger
    ) {
        fromHasIndex = false;
        string sql = "SELECT COUNT(*) FROM sqlite_master ";
        sql += "WHERE type = 'index' AND name = '" + fromIndexName + "'";
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        long indexCount = 0;
        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, indexCount)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);
        fromHasIndex = indexCount == 1;

        return true;
    }

    /**
     * 未補完行だけを保持する部分インデックスを作成する。
     *
     * 初回移行後は空インデックスとなり、各接続の移行済み確認を軽量化する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromLogger ロガー。
     * @return インデックス作成に成功した場合true。
     */
    static bool ensureMissingIndex(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        Logger &fromLogger
    ) {
        string sql = "CREATE INDEX IF NOT EXISTS idx_";
        sql += fromTableName + "_jst_missing ON " + fromTableName + "(id)";
        sql += " WHERE " + fromJstTimeColumnName + " <= 0";
        sql += " OR " + fromJstTimeTextColumnName + " = ''";

        return executeSql(
            fromDatabaseHandle,
            sql,
            "JST missing partial index",
            fromLogger
        );
    }

    /**
     * 未補完行の日本時刻と表示文字列をSQLiteで一括更新する。
     *
     * 夏時間は3月第2日曜から11月第1日曜までを日単位で両端含有とし、
     * 夏は6時間、冬は7時間をサーバー時刻へ加算する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromServerTimeColumnName 変換元サーバー時刻列名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromLogger ロガー。
     * @return 一括更新に成功した場合true。
     */
    static bool backfillRows(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromServerTimeColumnName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        Logger &fromLogger
    ) {
        string offsetSql = buildJstOffsetSql(fromServerTimeColumnName);
        string jstTimeSql = "(" + fromServerTimeColumnName;
        jstTimeSql += " + " + offsetSql + ")";
        string sql = "UPDATE " + fromTableName;
        sql += " SET " + fromJstTimeColumnName + " = " + jstTimeSql;
        sql += ", " + fromJstTimeTextColumnName;
        sql += " = strftime('%Y.%m.%d %H:%M:%S', ";
        sql += jstTimeSql + ", 'unixepoch')";
        sql += " WHERE " + fromJstTimeColumnName + " <= 0";
        sql += " OR " + fromJstTimeTextColumnName + " = ''";

        return executeSql(
            fromDatabaseHandle,
            sql,
            "JST bulk backfill",
            fromLogger
        );
    }

    /**
     * 未補完行が残っていないことを確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromLogger ロガー。
     * @return 未補完行が0件の場合true。
     */
    static bool isBackfillComplete(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        Logger &fromLogger
    ) {
        long missingCount = 0;

        if (!readMissingCount(
                fromDatabaseHandle,
                fromTableName,
                fromJstTimeColumnName,
                fromJstTimeTextColumnName,
                missingCount,
                fromLogger
            )) {
            return false;
        }

        if (missingCount == 0) {
            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "JST backfill remains. table=%s count=%I64d",
                fromTableName,
                missingCount
            )
        );

        return false;
    }

    /**
     * 未補完行数を取得する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromJstTimeColumnName 日本時刻列名。
     * @param fromJstTimeTextColumnName 日本時刻表示文字列列名。
     * @param fromMissingCount 未補完行数の格納先。
     * @param fromLogger ロガー。
     * @return 取得に成功した場合true。
     */
    static bool readMissingCount(
        const int fromDatabaseHandle,
        const string fromTableName,
        const string fromJstTimeColumnName,
        const string fromJstTimeTextColumnName,
        long &fromMissingCount,
        Logger &fromLogger
    ) {
        fromMissingCount = 0;
        string sql = "SELECT COUNT(*) FROM " + fromTableName;
        sql += " WHERE " + fromJstTimeColumnName + " <= 0";
        sql += " OR " + fromJstTimeTextColumnName + " = ''";
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabasePrepare failed. table=%s error=%d",
                    fromTableName,
                    GetLastError()
                )
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseRead failed. table=%s error=%d",
                    fromTableName,
                    readErrorCode
                )
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromMissingCount)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. table=%s error=%d",
                    fromTableName,
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * SQLite接続のbusy_timeoutを設定して値を確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTimeoutMilliseconds タイムアウト時間（ミリ秒）。
     * @param fromLogger ロガー。
     * @return 設定値が一致した場合true。
     */
    static bool setBusyTimeout(
        const int fromDatabaseHandle,
        const int fromTimeoutMilliseconds,
        Logger &fromLogger
    ) {
        string sql = "PRAGMA busy_timeout = ";
        sql += IntegerToString(fromTimeoutMilliseconds);

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "JST migration busy timeout",
                fromLogger
            )) {
            return false;
        }

        long actualTimeout = 0;

        if (!readBusyTimeout(
                fromDatabaseHandle,
                actualTimeout,
                fromLogger
            )) {
            return false;
        }

        if (actualTimeout == fromTimeoutMilliseconds) {
            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "busy_timeout verification failed. actual=%I64d expected=%d",
                actualTimeout,
                fromTimeoutMilliseconds
            )
        );

        return false;
    }

    /**
     * SQLite接続のbusy_timeoutを取得する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTimeoutMilliseconds 取得値の格納先。
     * @param fromLogger ロガー。
     * @return 取得に成功した場合true。
     */
    static bool readBusyTimeout(
        const int fromDatabaseHandle,
        long &fromTimeoutMilliseconds,
        Logger &fromLogger
    ) {
        fromTimeoutMilliseconds = 0;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            fromDatabaseHandle,
            "PRAGMA busy_timeout"
        );

        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(
                requestHandle,
                0,
                fromTimeoutMilliseconds
            )) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
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
     * SQLを直接実行する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromSql SQL文字列。
     * @param fromOperationName 処理名。
     * @param fromLogger ロガー。
     * @return 実行に成功した場合true。
     */
    static bool executeSql(
        const int fromDatabaseHandle,
        const string fromSql,
        const string fromOperationName,
        Logger &fromLogger
    ) {
        ResetLastError();

        if (!DatabaseExecute(fromDatabaseHandle, fromSql)) {
            fromLogger.error(
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
     * 日本時刻補完トランザクションをロールバックする。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 対象テーブル名。
     * @param fromLogger ロガー。
     */
    static void rollbackMigration(
        const int fromDatabaseHandle,
        const string fromTableName,
        Logger &fromLogger
    ) {
        ResetLastError();

        if (!DatabaseTransactionRollback(fromDatabaseHandle)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionRollback failed. table=%s error=%d",
                    fromTableName,
                    GetLastError()
                )
            );
        }
    }

    /**
     * TimeJapanUtilと同じ夏時間判定を行うSQLite CASE式を生成する。
     *
     * @param fromServerTimeColumnName 変換元サーバー時刻列名。
     * @return 夏時間は21600秒、冬時間は25200秒を返すCASE式。
     */
    static string buildJstOffsetSql(
        const string fromServerTimeColumnName
    ) {
        string yearSql = "strftime('%Y', ";
        yearSql += fromServerTimeColumnName + ", 'unixepoch')";
        string sql = "CASE WHEN date(" + fromServerTimeColumnName;
        sql += ", 'unixepoch') BETWEEN date(" + yearSql;
        sql += " || '-03-01', 'weekday 0', '+7 days') AND date(";
        sql += yearSql + " || '-11-01', 'weekday 0') ";
        sql += "THEN 21600 ELSE 25200 END";

        return sql;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_JST_MIGRATION_MQH
