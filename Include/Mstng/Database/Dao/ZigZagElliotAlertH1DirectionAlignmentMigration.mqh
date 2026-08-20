//+------------------------------------------------------------------+
//|               ZigZagElliotAlertH1DirectionAlignmentMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_ALERT_H1_DIRECTION_ALIGNMENT_MIGRATION_MQH
#define MSTNG_ZZE_ALERT_H1_DIRECTION_ALIGNMENT_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存アラートテーブルのH1方向一致診断スキーマを移行するクラス。
 *
 * 診断列の追加とCHECK制約の拡張を非破壊で行い、
 * 既存行に対して推測による補完を行わない。
 */
class ZigZagElliotAlertH1DirectionAlignmentMigration {
public:
    /**
     * H1方向一致診断列と現行CHECK制約の存在を保証する。
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
            bool hasCurrentConstraintsValue = false;

            if (!hasCurrentConstraints(
                    fromDatabaseHandle,
                    hasCurrentConstraintsValue,
                    logger
                )) {
                return false;
            }

            if (hasCurrentConstraintsValue) {
                return true;
            }
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
                "H1 direction alignment migration write lock",
                logger
            )
                || !ensureColumns(fromDatabaseHandle, logger)
                || !ensureCurrentConstraints(fromDatabaseHandle, logger)) {
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
     * H1方向一致モード列の現行定義を生成する。
     *
     * @param fromColumnName 定義へ使用する列名。
     * @return 列定義。
     */
    static string createModeColumnDefinition(const string fromColumnName) {
        string definition = "TEXT NOT NULL DEFAULT 'D1_TO_H1' CHECK(";
        definition += fromColumnName + " IN (";
        definition += "'D1_TO_H1', 'MN1_TO_H1_OBSERVE', ";
        definition += "'MN1_TO_H1_REQUIRED', ";
        definition += "'W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED', ";
        definition += "'INVALID'))";

        return definition;
    }

    /**
     * H1方向一致状態列の現行定義を生成する。
     *
     * @param fromColumnName 定義へ使用する列名。
     * @return 列定義。
     */
    static string createStateColumnDefinition(const string fromColumnName) {
        string definition = "TEXT NOT NULL DEFAULT 'NOT_EVALUATED' CHECK(";
        definition += fromColumnName + " IN (";
        definition += "'NOT_EVALUATED', 'NOT_APPLICABLE', 'D1_TO_H1', ";
        definition += "'FULL_BUY', 'FULL_SELL', 'MN1_MISMATCH', ";
        definition += "'W1_MISMATCH', 'MN1_W1_MISMATCH', ";
        definition += "'EMA200_FALLBACK_BUY', 'EMA200_FALLBACK_SELL', ";
        definition += "'MN1_EMA200_MISMATCH', 'UNAVAILABLE', 'INVALID'))";

        return definition;
    }

    /**
     * H1方向一致診断列を追加する。
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
                "h1_direction_alignment_mode",
                createModeColumnDefinition(
                    "h1_direction_alignment_mode"
                ),
                fromLogger
            )) {
            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "h1_direction_alignment_state",
                createStateColumnDefinition(
                    "h1_direction_alignment_state"
                ),
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_h1_direction_alignment_available",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_h1_direction_alignment_valid",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureColumn(
                fromDatabaseHandle,
                "h1_direction_alignment_direction",
                "TEXT NOT NULL DEFAULT 'NONE' "
                    + "CHECK(h1_direction_alignment_direction IN ("
                    + "'BUY', 'SELL', 'NONE'))",
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_h1_mn1_direction_matched",
                0,
                fromLogger
            )) {
            return false;
        }

        if (!ensureBooleanColumn(
                fromDatabaseHandle,
                "is_h1_w1_direction_matched",
                0,
                fromLogger
            )) {
            return false;
        }

        return ensureBooleanColumn(
            fromDatabaseHandle,
            "is_h1_direction_alignment_passed",
            0,
            fromLogger
        );
    }

    /**
     * H1方向一致モードと状態のCHECK制約を現行定義へ移行する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromLogger ロガー。
     * @return 移行または存在確認に成功した場合true。
     */
    static bool ensureCurrentConstraints(
        const int fromDatabaseHandle,
        Logger &fromLogger
    ) {
        string tableSql = "";

        if (!readTableSql(fromDatabaseHandle, tableSql, fromLogger)) {
            return false;
        }

        if (StringFind(
                tableSql,
                "'W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED'"
            ) < 0
                && !replaceConstraintColumn(
                    fromDatabaseHandle,
                    "h1_direction_alignment_mode",
                    "h1_direction_alignment_mode_v5",
                    createModeColumnDefinition(
                        "h1_direction_alignment_mode_v5"
                    ),
                    fromLogger
                )) {
            return false;
        }

        bool isStateCurrent = StringFind(
            tableSql,
            "'EMA200_FALLBACK_BUY'"
        ) >= 0 && StringFind(
            tableSql,
            "'EMA200_FALLBACK_SELL'"
        ) >= 0 && StringFind(
            tableSql,
            "'MN1_EMA200_MISMATCH'"
        ) >= 0;

        if (!isStateCurrent
                && !replaceConstraintColumn(
                    fromDatabaseHandle,
                    "h1_direction_alignment_state",
                    "h1_direction_alignment_state_v5",
                    createStateColumnDefinition(
                        "h1_direction_alignment_state_v5"
                    ),
                    fromLogger
                )) {
            return false;
        }

        bool hasCurrentConstraintsValue = false;

        return hasCurrentConstraints(
            fromDatabaseHandle,
            hasCurrentConstraintsValue,
            fromLogger
        ) && hasCurrentConstraintsValue;
    }

    /**
     * CHECK制約を保持する列を現行定義の列へ非破壊で置き換える。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 置換対象列名。
     * @param fromTemporaryColumnName 移行用一時列名。
     * @param fromTemporaryColumnDefinition 一時列定義。
     * @param fromLogger ロガー。
     * @return 置換に成功した場合true。
     */
    static bool replaceConstraintColumn(
        const int fromDatabaseHandle,
        const string fromColumnName,
        const string fromTemporaryColumnName,
        const string fromTemporaryColumnDefinition,
        Logger &fromLogger
    ) {
        bool hasTemporaryColumn = false;

        if (!hasColumn(
                fromDatabaseHandle,
                fromTemporaryColumnName,
                hasTemporaryColumn,
                fromLogger
            )) {
            return false;
        }

        if (hasTemporaryColumn) {
            fromLogger.error(
                __FUNCTION__,
                "Temporary migration column already exists. column="
                    + fromTemporaryColumnName
            );

            return false;
        }

        string sql = "ALTER TABLE zigzag_elliot_alerts ADD COLUMN ";
        sql += fromTemporaryColumnName + " ";
        sql += fromTemporaryColumnDefinition;

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "H1 direction alignment constraint column add",
                fromLogger
            )) {
            return false;
        }

        sql = "UPDATE zigzag_elliot_alerts SET ";
        sql += fromTemporaryColumnName + " = " + fromColumnName;

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "H1 direction alignment constraint value copy",
                fromLogger
            )) {
            return false;
        }

        sql = "ALTER TABLE zigzag_elliot_alerts DROP COLUMN ";
        sql += fromColumnName;

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "H1 direction alignment old constraint column drop",
                fromLogger
            )) {
            return false;
        }

        sql = "ALTER TABLE zigzag_elliot_alerts RENAME COLUMN ";
        sql += fromTemporaryColumnName + " TO " + fromColumnName;

        if (!executeSql(
                fromDatabaseHandle,
                sql,
                "H1 direction alignment constraint column rename",
                fromLogger
            )) {
            return false;
        }

        fromLogger.info(
            __FUNCTION__,
            "Alert H1 direction alignment CHECK expanded. column="
                + fromColumnName
        );

        return true;
    }

    /**
     * H1方向一致モードと状態のCHECK制約が現行定義か確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromHasCurrentConstraints 現行定義の場合trueを設定する。
     * @param fromLogger ロガー。
     * @return 確認処理に成功した場合true。
     */
    static bool hasCurrentConstraints(
        const int fromDatabaseHandle,
        bool &fromHasCurrentConstraints,
        Logger &fromLogger
    ) {
        fromHasCurrentConstraints = false;
        string tableSql = "";

        if (!readTableSql(fromDatabaseHandle, tableSql, fromLogger)) {
            return false;
        }

        fromHasCurrentConstraints = StringFind(
            tableSql,
            "'W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED'"
        ) >= 0 && StringFind(
            tableSql,
            "'EMA200_FALLBACK_BUY'"
        ) >= 0 && StringFind(
            tableSql,
            "'EMA200_FALLBACK_SELL'"
        ) >= 0 && StringFind(
            tableSql,
            "'MN1_EMA200_MISMATCH'"
        ) >= 0;

        return true;
    }

    /**
     * sqlite_masterからアラートテーブル定義を取得する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableSql テーブル定義SQLの格納先。
     * @param fromLogger ロガー。
     * @return 取得に成功した場合true。
     */
    static bool readTableSql(
        const int fromDatabaseHandle,
        string &fromTableSql,
        Logger &fromLogger
    ) {
        fromTableSql = "";
        string sql = "SELECT sql FROM sqlite_master ";
        sql += "WHERE type = 'table' ";
        sql += "AND name = 'zigzag_elliot_alerts'";
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
                StringFormat(
                    "DatabaseRead failed. error=%d",
                    readErrorCode
                )
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnText(requestHandle, 0, fromTableSql)) {
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

        DatabaseFinalize(requestHandle);

        return true;
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
                "Alert H1 direction alignment column added. column="
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
     * 全H1方向一致診断列が存在するか判定する。
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
            "h1_direction_alignment_mode",
            "h1_direction_alignment_state",
            "is_h1_direction_alignment_available",
            "is_h1_direction_alignment_valid",
            "h1_direction_alignment_direction",
            "is_h1_mn1_direction_matched",
            "is_h1_w1_direction_matched",
            "is_h1_direction_alignment_passed"
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

#endif // MSTNG_ZZE_ALERT_H1_DIRECTION_ALIGNMENT_MIGRATION_MQH
