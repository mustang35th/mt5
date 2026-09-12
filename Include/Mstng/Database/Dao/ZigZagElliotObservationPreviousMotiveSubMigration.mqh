#ifndef MSTNG_ZZE_OBSERVATION_PREVIOUS_MOTIVE_SUB_MIGRATION_MQH
#define MSTNG_ZZE_OBSERVATION_PREVIOUS_MOTIVE_SUB_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * M5時間足別観測へ直前推進波の副次波番号を追加する。
 *
 * 呼出元のスキーマ準備トランザクション内で実行し、既存行はNULLのまま保持する。
 */
class ZigZagElliotObservationPreviousMotiveSubMigration {
public:
    /**
     * 列が存在しない場合だけ追加する。独自のトランザクションは開始しない。
     *
     * @param fromDatabaseHandle 用途検査済みのM5データベースハンドル。
     * @return 列の存在確認または追加に成功した場合true。
     */
    static bool execute(const int fromDatabaseHandle) {
        Logger logger;
        logger.setLevel(LOG_INFO);
        if (fromDatabaseHandle == INVALID_HANDLE) {
            logger.error(__FUNCTION__, "databaseHandle is INVALID_HANDLE.");
            return false;
        }

        bool hasColumn = false;
        if (!readColumn(fromDatabaseHandle, hasColumn, logger)) {
            return false;
        }
        if (hasColumn) {
            return true;
        }

        string sql = "ALTER TABLE zigzag_elliot_observation_timeframes ";
        sql += "ADD COLUMN previous_motive_sub_elliot_index INTEGER ";
        sql += "CHECK(previous_motive_sub_elliot_index IS NULL ";
        sql += "OR previous_motive_sub_elliot_index IN (0, 1, 3))";
        ResetLastError();
        if (!DatabaseExecute(fromDatabaseHandle, sql)) {
            logger.error(__FUNCTION__, StringFormat("previous motive sub migration failed. error=%d", GetLastError()));
            return false;
        }
        logger.info(__FUNCTION__, "M5 previous motive sub Elliott column added; historical rows remain NULL.");
        return true;
    }

private:
    /**
     * 対象列の存在を読み取りだけで検査する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     * @param fromHasColumn 列がある場合trueを設定する。
     * @param fromLogger ロガー。
     * @return 検査に成功した場合true。
     */
    static bool readColumn(const int fromDatabaseHandle, bool &fromHasColumn, Logger &fromLogger) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, "PRAGMA table_info(zigzag_elliot_observation_timeframes)");
        if (requestHandle == INVALID_HANDLE) {
            fromLogger.error(__FUNCTION__, StringFormat("DatabasePrepare failed. error=%d", GetLastError()));
            return false;
        }
        while (true) {
            ResetLastError();
            if (!DatabaseRead(requestHandle)) {
                int readError = GetLastError();
                DatabaseFinalize(requestHandle);
                if (readError == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }
                fromLogger.error(__FUNCTION__, StringFormat("DatabaseRead failed. error=%d", readError));
                return false;
            }
            string columnName = "";
            ResetLastError();
            if (!DatabaseColumnText(requestHandle, 1, columnName)) {
                int columnError = GetLastError();
                DatabaseFinalize(requestHandle);
                fromLogger.error(__FUNCTION__, StringFormat("DatabaseColumnText failed. error=%d", columnError));
                return false;
            }
            if (columnName == "previous_motive_sub_elliot_index") {
                fromHasColumn = true;
                DatabaseFinalize(requestHandle);
                return true;
            }
        }
        return false;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_PREVIOUS_MOTIVE_SUB_MIGRATION_MQH
