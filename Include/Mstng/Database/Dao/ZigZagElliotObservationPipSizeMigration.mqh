//+------------------------------------------------------------------+
//|                      ZigZagElliotObservationPipSizeMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_OBSERVATION_PIP_SIZE_MIGRATION_MQH
#define MSTNG_ZZE_OBSERVATION_PIP_SIZE_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存Observationテーブルへpip size列を非破壊で追加するクラス。
 *
 * 既存の28通貨ペアはシンボル名からJPYペアを判定し、
 * JPYペアを0.01、それ以外を0.0001で補完する。
 */
class ZigZagElliotObservationPipSizeMigration {
public:
    /**
     * 1pip相当の価格幅列の存在と既存行の補完を保証する。
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

        bool hasPipSizeColumn = false;

        if (!hasColumn(fromDatabaseHandle, hasPipSizeColumn, logger)) {
            return false;
        }

        bool isBackfillComplete = false;

        if (hasPipSizeColumn
                && !getBackfillStatus(
                    fromDatabaseHandle,
                    isBackfillComplete,
                    logger
                )) {
            return false;
        }

        if (hasPipSizeColumn && isBackfillComplete) {
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
                "UPDATE zigzag_elliot_observations SET id = id WHERE 0",
                "observation pip size migration write lock",
                logger
            )
                || !ensureColumn(fromDatabaseHandle, logger)
                || !backfill(fromDatabaseHandle, logger)
                || !validate(fromDatabaseHandle, logger)) {
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
    /**
     * SQLを直接実行する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromSql 実行SQL。
     * @param fromOperationName 操作名。
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

    /**
     * 移行トランザクションをロールバックする。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     */
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
     * pip size列が存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 列の存在確認または追加に成功した場合true。
     */
    static bool ensureColumn(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        bool hasPipSizeColumn = false;

        if (!hasColumn(fromDatabaseHandle, hasPipSizeColumn, fromLogger)) {
            return false;
        }

        if (hasPipSizeColumn) {
            return true;
        }

        string sql = "ALTER TABLE zigzag_elliot_observations ";
        sql += "ADD COLUMN pip_size REAL ";
        sql += "CHECK(pip_size IS NULL OR pip_size > 0)";
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Observation pip size column added."
            );

            return true;
        }

        int alterErrorCode = GetLastError();
        bool hasColumnAfterFailure = false;

        if (hasColumn(
                fromDatabaseHandle,
                hasColumnAfterFailure,
                fromLogger
            ) && hasColumnAfterFailure) {
            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "ALTER TABLE failed. column=pip_size error=%d",
                alterErrorCode
            )
        );

        return false;
    }

    /**
     * 既存28通貨ペアのpip sizeをシンボル名から補完する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 補完に成功した場合true。
     */
    static bool backfill(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        string sql = "UPDATE zigzag_elliot_observations ";
        sql += "SET pip_size = CASE ";
        sql += "WHEN UPPER(symbol_name) LIKE '%JPY%' THEN 0.01 ";
        sql += "ELSE 0.0001 END ";
        sql += "WHERE pip_size IS NULL";

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "observation pip size backfill",
                fromLogger
            )) {
            return false;
        }

        fromLogger.info(
            __FUNCTION__,
            "Observation pip size backfill completed."
        );

        return true;
    }

    /**
     * 補完後にNULLまたは非正数が残っていないことを確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 全行が有効な場合true。
     */
    static bool validate(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        bool isBackfillComplete = false;

        if (!getBackfillStatus(
                fromDatabaseHandle,
                isBackfillComplete,
                fromLogger
            )) {
            return false;
        }

        if (isBackfillComplete) {
            return true;
        }

        fromLogger.error(
            __FUNCTION__,
            "Observation pip size backfill validation failed."
        );

        return false;
    }

    /**
     * 全Observation行のpip sizeが有効か確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromIsComplete 全行が有効な場合trueを設定する。
     * @param fromLogger ロガー。
     * @return 件数取得に成功した場合true。
     */
    static bool getBackfillStatus(
        const int fromDatabaseHandle,
        bool &fromIsComplete,
        Logger &fromLogger
    ) {
        fromIsComplete = false;
        string sql = "SELECT COUNT(*) FROM zigzag_elliot_observations ";
        sql += "WHERE pip_size IS NULL OR pip_size <= 0";
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

        long invalidCount = 0;
        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, invalidCount)) {
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
        fromIsComplete = invalidCount == 0;

        return true;
    }

    /**
     * Observationテーブルにpip size列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromHasColumn 存在する場合trueを設定する。
     * @param fromLogger ロガー。
     * @return テーブル情報の取得に成功した場合true。
     */
    static bool hasColumn(
        const int fromDatabaseHandle,
        bool &fromHasColumn,
        Logger &fromLogger
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            fromDatabaseHandle,
            "PRAGMA table_info(zigzag_elliot_observations)"
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

            if (columnName == "pip_size") {
                DatabaseFinalize(requestHandle);
                fromHasColumn = true;

                return true;
            }
        }

        return false;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_PIP_SIZE_MIGRATION_MQH
