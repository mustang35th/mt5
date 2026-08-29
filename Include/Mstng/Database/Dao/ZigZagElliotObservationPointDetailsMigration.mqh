//+------------------------------------------------------------------+
//|              ZigZagElliotObservationPointDetailsMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_OBSERVATION_POINT_DETAILS_MIGRATION_MQH
#define MSTNG_ZZE_OBSERVATION_POINT_DETAILS_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 既存の時間足別Observationテーブルへ最新ポイント詳細列を追加するクラス。
 *
 * 既存行はNULLの未記録データとして保持し、推測による補完を行わない。
 */
class ZigZagElliotObservationPointDetailsMigration {
public:
    /**
     * 最新ポイント詳細列の存在を保証する。
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

        string columnNames[];
        string columnDefinitions[];
        initializeColumns(columnNames, columnDefinitions);
        bool hasAllColumnsValue = false;

        if (!hasAllColumns(
                fromDatabaseHandle,
                columnNames,
                hasAllColumnsValue,
                logger
            )) {
            return false;
        }

        if (hasAllColumnsValue) {
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
                "observation point details migration write lock",
                logger
            )) {
            rollback(fromDatabaseHandle, logger);

            return false;
        }

        for (int i = 0; i < ArraySize(columnNames); i++) {
            if (!ensureColumn(
                    fromDatabaseHandle,
                    columnNames[i],
                    columnDefinitions[i],
                    logger
                )) {
                rollback(fromDatabaseHandle, logger);

                return false;
            }
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
     * 追加対象の列名と列定義を初期化する。
     *
     * @param fromColumnNames 列名配列。
     * @param fromColumnDefinitions 列定義配列。
     */
    static void initializeColumns(
        string &fromColumnNames[],
        string &fromColumnDefinitions[]
    ) {
        ArrayResize(fromColumnNames, 13);
        ArrayResize(fromColumnDefinitions, 13);
        fromColumnNames[0] = "latest_point_bar_index";
        fromColumnDefinitions[0] = "latest_point_bar_index INTEGER";
        fromColumnNames[1] = "latest_point_time_next";
        fromColumnDefinitions[1] = "latest_point_time_next INTEGER";
        fromColumnNames[2] = "latest_point_wave_bars_from_start";
        fromColumnDefinitions[2] =
            "latest_point_wave_bars_from_start INTEGER";
        fromColumnNames[3] = "latest_point_is_peak";
        fromColumnDefinitions[3] =
            "latest_point_is_peak INTEGER "
            + "CHECK(latest_point_is_peak IS NULL "
            + "OR latest_point_is_peak IN (0, 1))";
        fromColumnNames[4] = "latest_point_pips_diff";
        fromColumnDefinitions[4] = "latest_point_pips_diff REAL";
        fromColumnNames[5] = "latest_point_fibonacci_percent";
        fromColumnDefinitions[5] =
            "latest_point_fibonacci_percent REAL";
        fromColumnNames[6] = "latest_point_fibo_depth_zone";
        fromColumnDefinitions[6] = "latest_point_fibo_depth_zone INTEGER";
        fromColumnNames[7] = "latest_point_fibo_depth_zone_label";
        fromColumnDefinitions[7] =
            "latest_point_fibo_depth_zone_label TEXT";
        fromColumnNames[8] = "latest_point_fibonacci_expansion_percent";
        fromColumnDefinitions[8] =
            "latest_point_fibonacci_expansion_percent REAL";
        fromColumnNames[9] = "latest_point_is_elliot_alphabet";
        fromColumnDefinitions[9] =
            "latest_point_is_elliot_alphabet INTEGER "
            + "CHECK(latest_point_is_elliot_alphabet IS NULL "
            + "OR latest_point_is_elliot_alphabet IN (0, 1))";
        fromColumnNames[10] = "latest_point_org_elliot_index";
        fromColumnDefinitions[10] =
            "latest_point_org_elliot_index INTEGER";
        fromColumnNames[11] = "latest_point_org_elliot_label";
        fromColumnDefinitions[11] =
            "latest_point_org_elliot_label TEXT";
        fromColumnNames[12] = "latest_point_is_correct";
        fromColumnDefinitions[12] =
            "latest_point_is_correct INTEGER "
            + "CHECK(latest_point_is_correct IS NULL "
            + "OR latest_point_is_correct IN (0, 1))";
    }

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
     * 全対象列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnNames 確認対象列名配列。
     * @param fromHasAllColumns 全列が存在する場合trueを設定する。
     * @param fromLogger ロガー。
     * @return テーブル情報の取得に成功した場合true。
     */
    static bool hasAllColumns(
        const int fromDatabaseHandle,
        string &fromColumnNames[],
        bool &fromHasAllColumns,
        Logger &fromLogger
    ) {
        fromHasAllColumns = true;

        for (int i = 0; i < ArraySize(fromColumnNames); i++) {
            bool hasColumnValue = false;

            if (!hasColumn(
                    fromDatabaseHandle,
                    fromColumnNames[i],
                    hasColumnValue,
                    fromLogger
                )) {
                return false;
            }

            if (!hasColumnValue) {
                fromHasAllColumns = false;

                return true;
            }
        }

        return true;
    }

    /**
     * 指定列が存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromColumnName 列名。
     * @param fromColumnDefinition ALTER TABLE用列定義。
     * @param fromLogger ロガー。
     * @return 列の存在確認または追加に成功した場合true。
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

        string sql = "ALTER TABLE zigzag_elliot_observation_timeframes ";
        sql += "ADD COLUMN " + fromColumnDefinition;
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Observation point detail column added. column="
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
     * 時間足別Observationテーブルに指定列が存在するか確認する。
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

            if (columnName == fromColumnName) {
                DatabaseFinalize(requestHandle);
                fromHasColumn = true;

                return true;
            }
        }

        return false;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_POINT_DETAILS_MIGRATION_MQH
