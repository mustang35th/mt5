#ifndef MSTNG_DATABASE_DAO_ALERT_CORRECTION_TIME_FRAME_MIGRATION_MQH
#define MSTNG_DATABASE_DAO_ALERT_CORRECTION_TIME_FRAME_MIGRATION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 補正時間足のCHECK制約へD1を追加する。
 * 既存行・子テーブル・索引・トリガーを保持し、失敗時はトランザクションを戻す。
 */
class ZigZagElliotAlertCorrectionTimeFrameMigration {
public:
    /**
     * schema 7のH4/H1制約をschema 8のD1/H4/H1制約へ移行する。
     *
     * @param fromDatabaseHandle トランザクション外の書込接続。
     * @return 現行制約の確認または移行に成功した場合true。
     */
    static bool execute(const int fromDatabaseHandle) {
        Logger logger;
        logger.setLevel(LOG_INFO);

        string tableSql = "";
        if (!readTableSql(fromDatabaseHandle, tableSql, logger)) {
            return false;
        }

        if (hasCurrentConstraints(tableSql)) {
            return true;
        }

        StringReplace(tableSql, "correction_time_frame IN (0, 16385, 16388)",
            "correction_time_frame IN (0, 16385, 16388, 16408)");
        StringReplace(tableSql, "correction_time_frame IN (16385, 16388)",
            "correction_time_frame IN (16385, 16388, 16408)");
        if (!hasCurrentConstraints(tableSql)) {
            logger.error(__FUNCTION__, "unsupported correction time frame constraints.");
            return false;
        }

        int foreignKeys = 0;
        if (!readForeignKeys(fromDatabaseHandle, foreignKeys, logger)
                || !executeSql(fromDatabaseHandle, "PRAGMA foreign_keys=OFF", logger)) {
            return false;
        }

        int disabledForeignKeys = -1;
        if (!readForeignKeys(fromDatabaseHandle, disabledForeignKeys, logger) || disabledForeignKeys != 0) {
            restoreForeignKeys(fromDatabaseHandle, foreignKeys, logger);
            logger.error(__FUNCTION__, "correction migration requires a connection outside a transaction.");
            return false;
        }

        ResetLastError();
        if (!DatabaseTransactionBegin(fromDatabaseHandle)) {
            logger.error(__FUNCTION__, StringFormat("migration begin failed. error=%d", GetLastError()));
            restoreForeignKeys(fromDatabaseHandle, foreignKeys, logger);
            return false;
        }

        bool succeeded = executeSql(fromDatabaseHandle,
            "UPDATE zigzag_elliot_alert_corrections SET alert_id=alert_id WHERE 0", logger)
            && rebuildTable(fromDatabaseHandle, tableSql, logger);

        if (succeeded) {
            ResetLastError();
            succeeded = DatabaseTransactionCommit(fromDatabaseHandle);
            if (!succeeded) {
                logger.error(__FUNCTION__, StringFormat("migration commit failed. error=%d", GetLastError()));
            }
        }
        if (!succeeded) {
            DatabaseTransactionRollback(fromDatabaseHandle);
        }

        bool restored = restoreForeignKeys(fromDatabaseHandle, foreignKeys, logger);
        if (succeeded && restored) {
            logger.info(__FUNCTION__, "Alert correction time frame CHECK expanded to D1/H4/H1.");
        }

        return succeeded && restored;
    }

private:
    /**
     * 列制約と行制約がともにD1を許可しているか確認する。
     */
    static bool hasCurrentConstraints(const string fromTableSql) {
        return StringFind(fromTableSql, "correction_time_frame IN (0, 16385, 16388, 16408)") >= 0
            && StringFind(fromTableSql, "correction_time_frame IN (16385, 16388, 16408)") >= 0;
    }

    /**
     * SQLを実行し、失敗した操作を記録する。
     */
    static bool executeSql(const int fromDatabaseHandle, const string fromSql, Logger &fromLogger) {
        ResetLastError();
        if (DatabaseExecute(fromDatabaseHandle, fromSql)) {
            return true;
        }

        fromLogger.error(__FUNCTION__, StringFormat("correction migration failed. error=%d sql=%s",
            GetLastError(), fromSql));

        return false;
    }

    /**
     * 既存テーブル定義を読み取り、追加列もそのまま保持する。
     */
    static bool readTableSql(const int fromDatabaseHandle, string &fromSql, Logger &fromLogger) {
        ResetLastError();
        int request = DatabasePrepare(fromDatabaseHandle,
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='zigzag_elliot_alert_corrections'");
        if (request == INVALID_HANDLE) {
            fromLogger.error(__FUNCTION__, StringFormat("table definition prepare failed. error=%d", GetLastError()));
            return false;
        }

        bool succeeded = DatabaseRead(request) && DatabaseColumnText(request, 0, fromSql) && fromSql != "";
        DatabaseFinalize(request);
        if (!succeeded) {
            fromLogger.error(__FUNCTION__, "correction table definition is unavailable.");
        }

        return succeeded;
    }

    /**
     * 呼出元接続の外部キー設定を取得する。
     */
    static bool readForeignKeys(const int fromDatabaseHandle, int &fromValue, Logger &fromLogger) {
        int request = DatabasePrepare(fromDatabaseHandle, "PRAGMA foreign_keys");
        if (request == INVALID_HANDLE) {
            fromLogger.error(__FUNCTION__, "foreign_keys prepare failed.");
            return false;
        }

        bool succeeded = DatabaseRead(request) && DatabaseColumnInteger(request, 0, fromValue);
        DatabaseFinalize(request);

        return succeeded;
    }

    /**
     * 移行前の外部キー設定へ戻し、実際の設定値も確認する。
     */
    static bool restoreForeignKeys(const int fromDatabaseHandle, const int fromValue, Logger &fromLogger) {
        if (!executeSql(fromDatabaseHandle, "PRAGMA foreign_keys=" + IntegerToString(fromValue), fromLogger)) {
            return false;
        }

        int actual = -1;

        return readForeignKeys(fromDatabaseHandle, actual, fromLogger) && actual == fromValue;
    }

    /**
     * 自動索引以外の索引とトリガーの定義を保存する。
     */
    static bool readObjects(const int fromDatabaseHandle, string &fromSql[], Logger &fromLogger) {
        ArrayFree(fromSql);

        int request = DatabasePrepare(fromDatabaseHandle,
            "SELECT sql FROM sqlite_master WHERE tbl_name='zigzag_elliot_alert_corrections' "
            + "AND type IN ('index','trigger') AND sql IS NOT NULL ORDER BY type,name");
        if (request == INVALID_HANDLE) {
            fromLogger.error(__FUNCTION__, "correction objects prepare failed.");
            return false;
        }

        bool succeeded = true;
        while (true) {
            ResetLastError();
            if (!DatabaseRead(request)) {
                succeeded = GetLastError() == ERR_DATABASE_NO_MORE_DATA;
                break;
            }

            string sql = "";
            int count = ArraySize(fromSql);
            if (!DatabaseColumnText(request, 0, sql) || sql == ""
                    || ArrayResize(fromSql, count + 1) != count + 1) {
                succeeded = false;
                break;
            }

            fromSql[count] = sql;
        }

        DatabaseFinalize(request);

        return succeeded;
    }

    /**
     * 既存の親子参照を変えず、制約だけを変更した新表へ全列・全行をコピーする。
     */
    static bool rebuildTable(const int fromDatabaseHandle, const string fromTableSql, Logger &fromLogger) {
        string objects[];
        if (!readObjects(fromDatabaseHandle, objects, fromLogger)) {
            return false;
        }

        string tableName = "zigzag_elliot_alert_corrections";
        int nameIndex = StringFind(fromTableSql, tableName);
        if (nameIndex < 0 || nameIndex > StringFind(fromTableSql, "(")) {
            fromLogger.error(__FUNCTION__, "correction table name is unavailable.");
            return false;
        }

        string createSql = StringSubstr(fromTableSql, 0, nameIndex) + tableName + "_v8"
            + StringSubstr(fromTableSql, nameIndex + StringLen(tableName));

        if (!executeSql(fromDatabaseHandle, createSql, fromLogger)
                || !executeSql(fromDatabaseHandle,
                    "INSERT INTO zigzag_elliot_alert_corrections_v8 SELECT * FROM zigzag_elliot_alert_corrections", fromLogger)
                || !executeSql(fromDatabaseHandle, "DROP TABLE zigzag_elliot_alert_corrections", fromLogger)
                || !executeSql(fromDatabaseHandle,
                    "ALTER TABLE zigzag_elliot_alert_corrections_v8 RENAME TO zigzag_elliot_alert_corrections", fromLogger)) {
            return false;
        }

        for (int i = 0; i < ArraySize(objects); i++) {
            if (!executeSql(fromDatabaseHandle, objects[i], fromLogger)) {
                return false;
            }
        }

        int request = DatabasePrepare(fromDatabaseHandle, "PRAGMA foreign_key_check");
        if (request == INVALID_HANDLE) {
            return false;
        }

        ResetLastError();
        bool succeeded = !DatabaseRead(request) && GetLastError() == ERR_DATABASE_NO_MORE_DATA;
        DatabaseFinalize(request);
        if (!succeeded) {
            fromLogger.error(__FUNCTION__, "foreign key violation after correction migration.");
        }

        return succeeded;
    }
};

#endif
