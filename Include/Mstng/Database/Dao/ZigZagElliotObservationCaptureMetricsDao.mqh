#ifndef MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_DAO_MQH
#define MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_DAO_MQH

#include <Mstng\Database\Entity\ZigZagElliotObservationCaptureMetricsEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * M5観測の取得品質を親と1対1で保存するDAO。
 *
 * トランザクションは観測保存サービスが親・7時間足とまとめて管理する。
 */
class ZigZagElliotObservationCaptureMetricsDao {
public:
    /**
     * 保存先ハンドルを指定する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     */
    ZigZagElliotObservationCaptureMetricsDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * M5専用DBに取得品質テーブルを作成する。
     *
     * @return 作成または存在確認に成功した場合true。
     */
    bool createTable() {
        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_observation_capture_metrics (";
        sql += "observation_id INTEGER PRIMARY KEY CHECK(observation_id > 0),";
        sql += "quote_tick_time_msc INTEGER ";
        sql += "CHECK(quote_tick_time_msc IS NULL OR quote_tick_time_msc > 0),";
        sql += "capture_market_time INTEGER ";
        sql += "CHECK(capture_market_time IS NULL OR capture_market_time > 0),";
        sql += "analysis_elapsed_ms INTEGER ";
        sql += "CHECK(analysis_elapsed_ms IS NULL OR analysis_elapsed_ms >= 0),";
        sql += "capture_elapsed_ms INTEGER ";
        sql += "CHECK(capture_elapsed_ms IS NULL OR capture_elapsed_ms >= 0),";
        sql += "analysis_attempt_count INTEGER ";
        sql += "CHECK(analysis_attempt_count IS NULL OR analysis_attempt_count >= 1),";
        sql += "FOREIGN KEY(observation_id) REFERENCES ";
        sql += "zigzag_elliot_observations(id) ON DELETE CASCADE";
        sql += ")";
        return this.executeSql(sql, "create observation capture metrics");
    }

    /**
     * 採番済み親観測に取得品質を1行保存する。
     *
     * 重複を無視・更新しない。重複観測は呼出元が親保存時点で判定する。
     *
     * @param fromEntity Snapshot確定時に固定した品質値。
     * @return 保存に成功した場合true。
     */
    bool insert(ZigZagElliotObservationCaptureMetricsEntity &fromEntity) {
        if (fromEntity.observationId <= 0 || !fromEntity.isValid()) {
            this.logger.error(__FUNCTION__, "Capture metrics entity is invalid.");
            return false;
        }

        string sql = "INSERT INTO zigzag_elliot_observation_capture_metrics (";
        sql += "observation_id, quote_tick_time_msc, capture_market_time,";
        sql += " analysis_elapsed_ms, capture_elapsed_ms, analysis_attempt_count";
        sql += ") VALUES (";
        sql += IntegerToString(fromEntity.observationId);
        sql += "," + this.optionalLong(
            fromEntity.hasQuoteTickTimeMsc, fromEntity.quoteTickTimeMsc
        );
        sql += "," + this.optionalLong(
            fromEntity.hasCaptureMarketTime, fromEntity.captureMarketTime
        );
        sql += "," + this.optionalLong(
            fromEntity.hasAnalysisElapsedMs, fromEntity.analysisElapsedMs
        );
        sql += "," + this.optionalLong(
            fromEntity.hasCaptureElapsedMs, fromEntity.captureElapsedMs
        );
        sql += "," + this.optionalLong(
            fromEntity.hasAnalysisAttemptCount, fromEntity.analysisAttemptCount
        );
        sql += ")";
        return this.executeSql(sql, "insert observation capture metrics");
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 利用可否を明示した整数をSQLへ変換する。
     *
     * @param fromIsAvailable 値が取得済みの場合true。
     * @param fromNumber 取得済み整数。
     * @return 整数リテラルまたはSQL NULL。
     */
    string optionalLong(const bool fromIsAvailable, const long fromNumber) {
        if (!fromIsAvailable) {
            return "NULL";
        }
        return IntegerToString(fromNumber);
    }

    /**
     * SQLを実行する。
     *
     * @param fromSql 実行SQL。
     * @param fromOperationName ログ用の操作名。
     * @return 成功時true。
     */
    bool executeSql(const string fromSql, const string fromOperationName) {
        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, "databaseHandle is INVALID_HANDLE.");
            return false;
        }
        ResetLastError();
        if (!DatabaseExecute(this.databaseHandle, fromSql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. operation=%s error=%d",
                    fromOperationName, GetLastError()
                )
            );
            return false;
        }
        return true;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_DAO_MQH
