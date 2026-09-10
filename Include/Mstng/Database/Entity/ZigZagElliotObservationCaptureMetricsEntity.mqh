#ifndef MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_ENTITY_MQH
#define MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_ENTITY_MQH

/**
 * M5観測Snapshotへ固定する取得品質。
 *
 * 利用可否フラグによりSQLのNULLと有効な0ミリ秒を区別する。
 */
struct ZigZagElliotObservationCaptureMetricsEntity {
    /** 観測ID。Snapshot生成時は0、親INSERT後に設定する。 */
    long observationId;

    /** 採用した気配時刻の利用可否。 */
    bool hasQuoteTickTimeMsc;

    /** 採用した同一気配の更新時刻（ミリ秒）。 */
    long quoteTickTimeMsc;

    /** Snapshot確定時の市場時刻の利用可否。 */
    bool hasCaptureMarketTime;

    /** Snapshot確定時のTimeCurrent（秒）。 */
    long captureMarketTime;

    /** 最終成功解析の実経過時間の利用可否。 */
    bool hasAnalysisElapsedMs;

    /** 最終成功解析の実経過ミリ秒。 */
    long analysisElapsedMs;

    /** 当該バー初検出からの実経過時間の利用可否。 */
    bool hasCaptureElapsedMs;

    /** 当該バー初検出からSnapshot確定までの実経過ミリ秒。 */
    long captureElapsedMs;

    /** 観測用実解析回数の利用可否。 */
    bool hasAnalysisAttemptCount;

    /** 当該バーの観測用実解析回数。 */
    long analysisAttemptCount;

    /**
     * 取得済み品質値が保存範囲内か検証する。
     *
     * 未採番の観測IDは許可し、親INSERT後の正数検証はDAOで行う。
     * 市場時計と実経過時計の大小関係は比較しない。
     *
     * @return 各取得済み値が仕様範囲内の場合true。
     */
    bool isValid() const {
        if (observationId < 0) {
            return false;
        }
        if (hasQuoteTickTimeMsc && quoteTickTimeMsc <= 0) {
            return false;
        }
        if (hasCaptureMarketTime && captureMarketTime <= 0) {
            return false;
        }
        if (hasAnalysisElapsedMs && analysisElapsedMs < 0) {
            return false;
        }
        if (hasCaptureElapsedMs && captureElapsedMs < 0) {
            return false;
        }
        if (hasAnalysisAttemptCount && analysisAttemptCount < 1) {
            return false;
        }
        return true;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_CAPTURE_METRICS_ENTITY_MQH
