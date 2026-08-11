//+------------------------------------------------------------------+
//|      ZigZagElliotAlertRunAnalysisProfileMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_RUN_PROFILE_MIGRATION_MQH
#define MSTNG_ZZE_RUN_PROFILE_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存Runテーブルへ分析Profile列を非破壊で追加するクラス。
 *
 * 既存行は空文字のLegacyデータとして保持し、推測による補完を行わない。
 */
class ZigZagElliotAlertRunAnalysisProfileMigration {
public:
    /**
     * 分析Profile文字列列とSHA-256列の存在を保証する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @return 移行または存在確認に成功した場合true。
     */
    static bool execute(const int fromDatabaseHandle) {
        Logger logger;
        logger.setLevel(LOG_INFO);

        if (fromDatabaseHandle == INVALID_HANDLE) {
            logger.error(__FUNCTION__, "databaseHandle is INVALID_HANDLE.");

            return false;
        }

        bool hasTextColumn = false;
        bool hasHashColumn = false;

        if (!hasColumn(
                fromDatabaseHandle,
                "analysis_input_text",
                hasTextColumn,
                logger
            ) || !hasColumn(
                fromDatabaseHandle,
                "analysis_input_hash",
                hasHashColumn,
                logger
            )) {
            return false;
        }

        if (hasTextColumn && hasHashColumn) {
            return true;
        }

        ResetLastError();

        if (!DatabaseTransactionBegin(fromDatabaseHandle)) {
            logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionBegin failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        if (!executeSql(
                fromDatabaseHandle,
                "UPDATE zigzag_elliot_alert_runs SET id = id WHERE 0",
                "analysis profile migration write lock",
                logger
            )) {
            rollback(fromDatabaseHandle, logger);

            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "analysis_input_text",
                logger
            )) {
            rollback(fromDatabaseHandle, logger);

            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "analysis_input_hash",
                logger
            )) {
            rollback(fromDatabaseHandle, logger);

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(fromDatabaseHandle)) {
            int commitErrorCode = GetLastError();
            rollback(fromDatabaseHandle, logger);
            logger.error(
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

private:
    /** SQLを直接実行する。 */
    static bool executeSql(
        const int fromDatabaseHandle,
        const string fromSql,
        const string fromOperationName,
        Logger &fromLogger
    ) {
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, fromSql)) {
            return true;
        }

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

    /** 移行トランザクションをロールバックする。 */
    static void rollback(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        ResetLastError();

        if (!DatabaseTransactionRollback(fromDatabaseHandle)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionRollback failed. error=%d",
                    GetLastError()
                )
            );
        }
    }

    /**
     * 指定列が存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 追加対象列名。
     * @param fromLogger ロガー。
     * @return 列の存在確認または追加に成功した場合true。
     */
    static bool ensureColumn(
        const int fromDatabaseHandle,
        const string fromColumnName,
        Logger &fromLogger
    ) {
        bool hasColumnValue = false;

        if (!hasColumn(
                fromDatabaseHandle,
                fromColumnName,
                hasColumnValue,
                fromLogger
            )) {
            return false;
        }

        if (hasColumnValue) {
            return true;
        }

        string sql = "ALTER TABLE zigzag_elliot_alert_runs ADD COLUMN ";
        sql += fromColumnName + " TEXT NOT NULL DEFAULT ''";
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Run analysis profile column added. column=" + fromColumnName
            );

            return true;
        }

        int alterErrorCode = GetLastError();
        bool hasColumnAfterFailure = false;

        if (hasColumn(
                fromDatabaseHandle,
                fromColumnName,
                hasColumnAfterFailure,
                fromLogger
            ) && hasColumnAfterFailure) {
            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "ALTER TABLE failed. column=%s error=%d",
                fromColumnName,
                alterErrorCode
            )
        );

        return false;
    }

    /**
     * Runテーブルに指定列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 確認対象列名。
     * @param fromHasColumn 存在する場合trueを設定する。
     * @param fromLogger ロガー。
     * @return テーブル情報の取得に成功した場合true。
     */
    static bool hasColumn(
        const int fromDatabaseHandle,
        const string fromColumnName,
        bool &fromHasColumn,
        Logger &fromLogger
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            fromDatabaseHandle,
            "PRAGMA table_info(zigzag_elliot_alert_runs)"
        );

        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(
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

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            string columnName = "";
            ResetLastError();

            if (!DatabaseColumnText(requestHandle, 1, columnName)) {
                int columnErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseColumnText failed. error=%d",
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
};

#endif // MSTNG_ZZE_RUN_PROFILE_MIGRATION_MQH
