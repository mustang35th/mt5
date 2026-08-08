//+------------------------------------------------------------------+
//|                          ZigZagElliotAlertPointDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_POINT_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_POINT_DAO_MQH

#include <Mstng\Database\Entity\ZigZagElliotAlertPointEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliotアラートのWave構成ポイントをSQLiteへ保存するDAO。
 */
class ZigZagElliotAlertPointDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    ZigZagElliotAlertPointDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * Wave構成ポイントテーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_alert_points (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "alert_timeframe_id INTEGER NOT NULL,";
        sql += "point_order INTEGER NOT NULL,";
        sql += "is_latest INTEGER NOT NULL CHECK(is_latest IN (0, 1)),";
        sql += "is_signal_reference INTEGER NOT NULL ";
        sql += "CHECK(is_signal_reference IN (0, 1)),";
        sql += "rate REAL NOT NULL,";
        sql += "bar_index INTEGER NOT NULL,";
        sql += "bar_time INTEGER NOT NULL,";
        sql += "bar_time_text TEXT NOT NULL,";
        sql += "is_bar_time_next_available INTEGER NOT NULL ";
        sql += "CHECK(is_bar_time_next_available IN (0, 1)),";
        sql += "bar_time_next INTEGER NOT NULL,";
        sql += "bar_time_next_text TEXT NOT NULL,";
        sql += "wave_bars_from_start INTEGER NOT NULL,";
        sql += "is_peak INTEGER NOT NULL CHECK(is_peak IN (0, 1)),";
        sql += "is_added_point INTEGER NOT NULL CHECK(is_added_point IN (0, 1)),";
        sql += "pips_diff REAL NOT NULL,";
        sql += "is_fibonacci_available INTEGER NOT NULL ";
        sql += "CHECK(is_fibonacci_available IN (0, 1)),";
        sql += "fibonacci_percent REAL NOT NULL,";
        sql += "fibo_depth_zone INTEGER NOT NULL,";
        sql += "fibo_depth_zone_label TEXT NOT NULL,";
        sql += "is_fibonacci_expansion_available INTEGER NOT NULL ";
        sql += "CHECK(is_fibonacci_expansion_available IN (0, 1)),";
        sql += "fibonacci_expansion_percent REAL NOT NULL,";
        sql += "is_elliot_alphabet INTEGER NOT NULL ";
        sql += "CHECK(is_elliot_alphabet IN (0, 1)),";
        sql += "elliot_index INTEGER NOT NULL,";
        sql += "elliot_label TEXT NOT NULL,";
        sql += "is_sub_elliot_available INTEGER NOT NULL ";
        sql += "CHECK(is_sub_elliot_available IN (0, 1)),";
        sql += "sub_elliot_index INTEGER NOT NULL,";
        sql += "sub_elliot_label TEXT NOT NULL,";
        sql += "is_original_elliot_available INTEGER NOT NULL ";
        sql += "CHECK(is_original_elliot_available IN (0, 1)),";
        sql += "org_elliot_index INTEGER NOT NULL,";
        sql += "org_elliot_label TEXT NOT NULL,";
        sql += "is_correct INTEGER NOT NULL CHECK(is_correct IN (0, 1)),";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(alert_timeframe_id) REFERENCES ";
        sql += "zigzag_elliot_alert_timeframes(id) ON DELETE CASCADE,";
        sql += "UNIQUE(alert_timeframe_id, point_order)";
        sql += ")";

        if (!this.executeSql(sql, "zigzag_elliot_alert_points table")) {
            return false;
        }

        sql = "CREATE UNIQUE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alert_points_latest ";
        sql += "ON zigzag_elliot_alert_points(alert_timeframe_id) ";
        sql += "WHERE is_latest = 1";

        if (!this.executeSql(sql, "zigzag elliot latest point index")) {
            return false;
        }

        sql = "CREATE UNIQUE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alert_points_signal_reference ";
        sql += "ON zigzag_elliot_alert_points(alert_timeframe_id) ";
        sql += "WHERE is_signal_reference = 1";

        if (!this.executeSql(sql, "zigzag elliot signal reference index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alert_points_wave_lookup ";
        sql += "ON zigzag_elliot_alert_points(";
        sql += "elliot_label, sub_elliot_label, bar_time)";

        if (!this.executeSql(sql, "zigzag elliot point wave index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "zigzag_elliot_alert_points table and indexes are ready."
        );

        return true;
    }

    /**
     * Wave構成ポイントを保存する。
     *
     * timeFrameは親ID割り当て用の論理項目であり保存しない。
     * 保存成功時はポイントIDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insert(ZigZagElliotAlertPointEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromEntity.id = 0;
        string sql = this.buildInsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        if (!this.bindEntity(requestHandle, fromEntity)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "insert alert point"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        return this.getLastInsertId(fromEntity.id);
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * Wave構成ポイントINSERT文を生成する。
     *
     * @return パラメーター化したINSERT文。
     */
    string buildInsertSql() {
        string sql = "INSERT INTO zigzag_elliot_alert_points (";
        sql += "alert_timeframe_id, point_order, is_latest,";
        sql += " is_signal_reference, rate, bar_index, bar_time, bar_time_text,";
        sql += " is_bar_time_next_available, bar_time_next, bar_time_next_text,";
        sql += " wave_bars_from_start, is_peak, is_added_point, pips_diff,";
        sql += " is_fibonacci_available, fibonacci_percent, fibo_depth_zone,";
        sql += " fibo_depth_zone_label, is_fibonacci_expansion_available,";
        sql += " fibonacci_expansion_percent, is_elliot_alphabet, elliot_index,";
        sql += " elliot_label, is_sub_elliot_available, sub_elliot_index,";
        sql += " sub_elliot_label, is_original_elliot_available,";
        sql += " org_elliot_index, org_elliot_label, is_correct,";
        sql += " created_at, created_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,";
        sql += " ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23,";
        sql += " ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33";
        sql += ")";

        return sql;
    }

    /**
     * Wave構成ポイントINSERTパラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象エンティティ。
     * @return 全パラメーターを設定できた場合はtrue。
     */
    bool bindEntity(
        const int fromRequestHandle,
        ZigZagElliotAlertPointEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(
            fromRequestHandle,
            index++,
            fromEntity.alertTimeFrameId
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.pointOrder);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isLatest);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isSignalReference
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.rate);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barIndex);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barTimeText);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isBarTimeNextAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barTimeNext);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barTimeNextText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.waveBarsFromStart);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isPeak);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isAddedPoint);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.pipsDiff);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isFibonacciAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fibonacciPercent);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fiboDepthZone);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fiboDepthZoneLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isFibonacciExpansionAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.fibonacciExpansionPercent
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isElliotAlphabet);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.elliotIndex);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.elliotLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isSubElliotAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.subElliotIndex);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.subElliotLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isOriginalElliotAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.orgElliotIndex);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.orgElliotLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isCorrect);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAtText);
        }

        return isBound && index == 33;
    }

    /**
     * 直前に追加したレコードIDを取得する。
     *
     * @param fromInsertId 取得したIDの格納先。
     * @return IDを取得できた場合はtrue。
     */
    bool getLastInsertId(long &fromInsertId) {
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "SELECT last_insert_rowid()"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromInsertId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (fromInsertId <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("Invalid insert id. id=%I64d", fromInsertId)
            );

            return false;
        }

        return true;
    }

    /**
     * 結果行を返さない準備済みリクエストを実行する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合はtrue。
     */
    bool executeRequest(
        const int fromRequestHandle,
        const string fromMethodName,
        const string fromOperationName
    ) {
        ResetLastError();
        bool isRead = DatabaseRead(fromRequestHandle);
        int errorCode = GetLastError();

        if (!isRead && errorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseRead failed. operation=%s error=%d",
                    fromOperationName,
                    errorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * SQLを直接実行する。
     *
     * @param fromSql SQL文字列。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合はtrue。
     */
    bool executeSql(
        const string fromSql,
        const string fromOperationName
    ) {
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, fromSql)) {
            this.logger.error(
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
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合はtrue。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_POINT_DAO_MQH
