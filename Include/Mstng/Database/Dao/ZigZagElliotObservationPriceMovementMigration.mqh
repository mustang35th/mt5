//+------------------------------------------------------------------+
//|                    ZigZagElliotObservationPriceMovementMigration.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_OBSERVATION_PRICE_MOVEMENT_MIGRATION_MQH
#define MSTNG_ZZE_OBSERVATION_PRICE_MOVEMENT_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * M5観測の時間足テーブルへ値動き列を非破壊で追加するクラス。
 *
 * 既存行は判定未取得の0値として保持し、価格履歴からの補完を行わない。
 * 呼び出し元のスキーマ準備トランザクション内で実行する。
 */
class ZigZagElliotObservationPriceMovementMigration {
public:
    /**
     * M5観測の時間足テーブルに値動き8列が存在することを保証する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @return 移行または存在確認に成功した場合true。
     */
    static bool execute(
        const int fromDatabaseHandle
    ) {
        Logger logger;
        logger.setLevel(LOG_INFO);

        if (fromDatabaseHandle == INVALID_HANDLE) {
            logger.error(__FUNCTION__, "databaseHandle is INVALID_HANDLE.");

            return false;
        }

        string tableName = "zigzag_elliot_observation_timeframes";
        string columnNames[] = {
            "is_price_movement_valid",
            "price_movement_level",
            "price_movement_average_range_pips",
            "price_movement_reference_atr_pips",
            "price_movement_activity_ratio",
            "is_price_movement_spread_valid",
            "price_movement_range_spread_ratio",
            "price_movement_reference_bar_time"
        };
        string columnDefinitions[] = {
            "INTEGER NOT NULL DEFAULT 0 CHECK(is_price_movement_valid IN (0, 1))",
            "INTEGER NOT NULL DEFAULT 0 CHECK(price_movement_level IN (0, 1, 2, 3))",
            "REAL NOT NULL DEFAULT 0",
            "REAL NOT NULL DEFAULT 0",
            "REAL NOT NULL DEFAULT 0",
            "INTEGER NOT NULL DEFAULT 0 CHECK(is_price_movement_spread_valid IN (0, 1))",
            "REAL NOT NULL DEFAULT 0",
            "INTEGER NOT NULL DEFAULT 0"
        };
        for (int i = 0; i < ArraySize(columnNames); i++) {
            if (!ensureColumn(
                    fromDatabaseHandle,
                    tableName,
                    columnNames[i],
                    columnDefinitions[i],
                    logger)) {
                return false;
            }
        }

        return true;
    }

private:
    /**
     * 列を確認し、存在しない場合だけ追加する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 移行対象の固定テーブル名。
     * @param fromColumnName 追加対象列名。
     * @param fromColumnDefinition 型・既定値・制約のSQL定義。
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
                fromLogger)) {
            return false;
        }

        if (hasColumnValue) {
            return true;
        }

        string sql = "ALTER TABLE " + fromTableName + " ADD COLUMN ";
        sql += fromColumnName + " " + fromColumnDefinition;
        ResetLastError();

        if (DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.info(
                __FUNCTION__,
                "Observation price movement column added. table=" + fromTableName
                    + " column=" + fromColumnName
            );

            return true;
        }

        int alterErrorCode = GetLastError();
        bool hasColumnAfterFailure = false;

        if (hasColumn(
                fromDatabaseHandle,
                fromTableName,
                fromColumnName,
                hasColumnAfterFailure,
                fromLogger) && hasColumnAfterFailure) {
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
     * 時間足テーブルに指定列が存在するか確認する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromTableName 確認対象の固定テーブル名。
     * @param fromColumnName 確認対象列名。
     * @param fromHasColumn 存在する場合trueを設定する。
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
                    StringFormat("DatabaseRead failed. error=%d", readErrorCode)
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

#endif // MSTNG_ZZE_OBSERVATION_PRICE_MOVEMENT_MIGRATION_MQH
