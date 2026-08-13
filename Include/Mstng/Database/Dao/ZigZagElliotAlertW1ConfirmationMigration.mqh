//+------------------------------------------------------------------+
//|                     ZigZagElliotAlertW1ConfirmationMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_ALERT_W1_CONFIRMATION_MIGRATION_MQH
#define MSTNG_ZZE_ALERT_W1_CONFIRMATION_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存アラートテーブルへW1確認診断列を非破壊で追加するクラス。
 *
 * 既存行はW1確認導入前のデータとして保持し、推測による補完を行わない。
 */
class ZigZagElliotAlertW1ConfirmationMigration {
public:
    /**
     * W1確認診断列の存在を保証する。
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

        if (hasAllColumns(fromDatabaseHandle, logger)) {
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
                "UPDATE zigzag_elliot_alerts SET id = id WHERE 0",
                "W1 confirmation migration write lock",
                logger
            )
                || !ensureColumns(fromDatabaseHandle, logger)) {
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
     * @param fromSql 実行するSQL。
     * @param fromOperationName ログ用の操作名。
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
     * W1確認診断列を追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 全列の追加または存在確認に成功した場合true。
     */
    static bool ensureColumns(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        if (!ensureColumn(
                fromDatabaseHandle,
                "w1_confirmation_mode",
                "TEXT NOT NULL DEFAULT 'OFF' CHECK(w1_confirmation_mode IN ("
                    + "'OFF', 'OBSERVE_ONLY', 'DIRECTION_OR_EMA200', "
                    + "'DIRECTION_AND_EMA200'))",
                fromLogger
            )) {
            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "w1_confirmation_state",
                "TEXT NOT NULL DEFAULT 'NOT_EVALUATED' "
                    + "CHECK(w1_confirmation_state IN ("
                    + "'NOT_EVALUATED', 'NOT_APPLICABLE', 'OFF', "
                    + "'UNAVAILABLE', 'INVALID', 'STRONG', "
                    + "'DIRECTION_ONLY', 'EMA_CONFLICT', 'EMA_ONLY', "
                    + "'REJECT_NONE', 'REJECT'))",
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_w1_confirmation_available",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_w1_confirmation_valid",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_w1_direction_matched",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "w1_ema200_direction",
                "TEXT NOT NULL DEFAULT 'NONE' "
                    + "CHECK(w1_ema200_direction IN ('BUY', 'SELL', 'NONE'))",
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_w1_ema200_matched",
                0,
                fromLogger
            )) {
            return false;
        }

        return ensureBooleanColumn(
            fromDatabaseHandle,
            "is_w1_confirmation_passed",
            1,
            fromLogger
        );
    }

    /**
     * 指定した真偽値列を追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 列名。
     * @param fromDefaultValue 既定値。
     * @param fromLogger ロガー。
     * @return 追加または存在確認に成功した場合true。
     */
    static bool ensureBooleanColumn(
        const int fromDatabaseHandle,
        const string fromColumnName,
        const int fromDefaultValue,
        Logger &fromLogger
    ) {
        string definition = "INTEGER NOT NULL DEFAULT ";
        definition += IntegerToString(fromDefaultValue);
        definition += " CHECK(" + fromColumnName + " IN (0, 1))";

        return ensureColumn(
            fromDatabaseHandle,
            fromColumnName,
            definition,
            fromLogger
        );
    }

    /**
     * 指定列が存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 列名。
     * @param fromColumnDefinition 列定義。
     * @param fromLogger ロガー。
     * @return 追加または存在確認に成功した場合true。
     */
    static bool ensureColumn(
        const int fromDatabaseHandle,
        const string fromColumnName,
        const string fromColumnDefinition,
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

        string sql = "ALTER TABLE zigzag_elliot_alerts ADD COLUMN ";
        sql += fromColumnName + " " + fromColumnDefinition;
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Alert W1 confirmation column added. column="
                    + fromColumnName
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
     * 全W1確認診断列が存在するか判定する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 全列が存在する場合true。
     */
    static bool hasAllColumns(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        string columns[8] = {
            "w1_confirmation_mode",
            "w1_confirmation_state",
            "is_w1_confirmation_available",
            "is_w1_confirmation_valid",
            "is_w1_direction_matched",
            "w1_ema200_direction",
            "is_w1_ema200_matched",
            "is_w1_confirmation_passed"
        };

        for (int i = 0; i < ArraySize(columns); i++) {
            bool hasColumnValue = false;

            if (!hasColumn(
                    fromDatabaseHandle,
                    columns[i],
                    hasColumnValue,
                    fromLogger
                ) || !hasColumnValue) {
                return false;
            }
        }

        return true;
    }

    /**
     * アラートテーブルに指定列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 列名。
     * @param fromHasColumn 存在する場合trueを設定する出力値。
     * @param fromLogger ロガー。
     * @return 確認処理に成功した場合true。
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
            "PRAGMA table_info(zigzag_elliot_alerts)"
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

#endif // MSTNG_ZZE_ALERT_W1_CONFIRMATION_MIGRATION_MQH
