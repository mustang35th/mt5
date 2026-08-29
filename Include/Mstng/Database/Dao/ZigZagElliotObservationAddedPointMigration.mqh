//+------------------------------------------------------------------+
//|                ZigZagElliotObservationAddedPointMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_OBSERVATION_ADDED_POINT_MIGRATION_MQH
#define MSTNG_ZZE_OBSERVATION_ADDED_POINT_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存の時間足別Observationテーブルへ最新補完ポイント列を追加するクラス。
 *
 * 既存行はNULLの未記録データとして保持し、推測による補完を行わない。
 */
class ZigZagElliotObservationAddedPointMigration {
public:
    /**
     * 最新ポイントの補完ポイント列の存在を保証する。
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

        bool hasAddedPointColumn = false;

        if (!hasColumn(fromDatabaseHandle, hasAddedPointColumn, logger)) {
            return false;
        }

        if (hasAddedPointColumn) {
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
                "UPDATE zigzag_elliot_observation_timeframes "
                    + "SET id = id WHERE 0",
                "observation added point migration write lock",
                logger
            ) || !ensureColumn(fromDatabaseHandle, logger)) {
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
     * 最新補完ポイント列が存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 列の存在確認または追加に成功した場合true。
     */
    static bool ensureColumn(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        bool hasAddedPointColumn = false;

        if (!hasColumn(
                fromDatabaseHandle,
                hasAddedPointColumn,
                fromLogger
            )) {
            return false;
        }

        if (hasAddedPointColumn) {
            return true;
        }

        string sql = "ALTER TABLE zigzag_elliot_observation_timeframes ";
        sql += "ADD COLUMN latest_point_is_added INTEGER ";
        sql += "CHECK(latest_point_is_added IS NULL ";
        sql += "OR latest_point_is_added IN (0, 1))";
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Observation latest point is-added column added."
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
                "ALTER TABLE failed. column=latest_point_is_added error=%d",
                alterErrorCode
            )
        );

        return false;
    }

    /**
     * 時間足別Observationテーブルに最新補完ポイント列が存在するか確認する。
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
            "PRAGMA table_info(zigzag_elliot_observation_timeframes)"
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

            if (columnName == "latest_point_is_added") {
                DatabaseFinalize(requestHandle);
                fromHasColumn = true;

                return true;
            }
        }

        return false;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_ADDED_POINT_MIGRATION_MQH
