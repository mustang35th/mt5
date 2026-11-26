#ifndef MSTNG_INDICATOR_ELLIOT_HISTORY_READINESS_MQH
#define MSTNG_INDICATOR_ELLIOT_HISTORY_READINESS_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 通常版ZigZagElliotの分析履歴の同期・必要本数・取得要求を管理する。
 * 分析や処理済み時刻は扱わず、ログの識別名と出力条件は従来のController形式を維持する。
 */
class ElliotHistoryReadiness {
public:
    /**
     * 履歴取得前の状態で初期化する。
     */
    ElliotHistoryReadiness() {
        this.reset();
    }

    /**
     * 対象時間足と取得状態を初期化する。履歴の取得要求は別途行う。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromTimerMode 通常チャートのタイマー実行の場合true。
     * @return 分析対象時間足を構築できた場合true。
     */
    bool initialize(MarketContext &fromMarketContext, const bool fromTimerMode) {
        this.reset();
        this.marketContext = fromMarketContext;
        this.timerMode = fromTimerMode;
        if (!ElliotTimeFrameRange::build(
                ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame(),
                this.marketContext.timeFrame,
                this.analysisTimeFrames
            )) {
            return false;
        }

        int analysisTimeFrameCount = ArraySize(this.analysisTimeFrames);
        ArrayResize(this.seriesWarmUpRequested, analysisTimeFrameCount);
        ArrayResize(this.seriesWarmUpRequestBarTimes, analysisTimeFrameCount);
        ArrayInitialize(this.seriesWarmUpRequested, false);
        ArrayInitialize(this.seriesWarmUpRequestBarTimes, 0);
        this.initialized = true;

        return true;
    }

    /**
     * 終了・再初期化時に進捗と履歴の再要求状態を破棄する。
     */
    void reset() {
        this.initialized = false;
        this.timerMode = true;
        this.lastAnalysisWarmUpProgress = -1;
        ArrayResize(this.analysisTimeFrames, 0);
        ArrayResize(this.seriesWarmUpRequested, 0);
        ArrayResize(this.seriesWarmUpRequestBarTimes, 0);
    }

    /**
     * 初期化済みの全分析対象時間足に、従来と同じ500本の履歴を要求する。
     */
    void requestHistory() {
        if (!this.initialized) {
            return;
        }

        WarmUpSeriesUtil::warmUp(
            this.marketContext,
            this.analysisTimeFrames,
            500
        );
    }

    /**
     * テスターの初回履歴準備がまだ完了していない場合trueを返す。
     */
    bool isWarmingUp() const {
        return !this.timerMode && this.lastAnalysisWarmUpProgress < 100;
    }

    /**
     * 分析対象の価格系列が準備済みか判定する。
     *
     * 未同期の時間足だけ価格系列の取得を再要求し、次回実行へ持ち越す。
     *
     * @param fromLogger 呼び出し元のロガー。既存のログ設定を引き継ぐ。
     * @return 分析データが準備済みの場合true
     */
    bool isReady(Logger &fromLogger) {
        if (!this.initialized) {
            return false;
        }

        int total = ArraySize(this.analysisTimeFrames);
        bool isTesterWarmUp = this.isWarmingUp();
        bool isSynchronized = true;
        datetime currentBarTime = 0;

        if (isTesterWarmUp) {
            currentBarTime = this.getSeriesWarmUpRequestBarTime();
        }

        for (int i = 0; i < total; i++) {
            ENUM_TIMEFRAMES timeFrame = this.analysisTimeFrames[i];

            if (WarmUpSeriesUtil::isSeriesSynchronized(
                    this.marketContext.symbolName,
                    timeFrame
                )) {
                if (isTesterWarmUp) {
                    this.seriesWarmUpRequested[i] = false;
                }

                continue;
            }

            bool shouldLogNotReady = isTesterWarmUp || isSynchronized;
            isSynchronized = false;

            if (isTesterWarmUp && this.seriesWarmUpRequested[i]
                    && this.seriesWarmUpRequestBarTimes[i] == currentBarTime) {
                continue;
            }

            ENUM_TIMEFRAMES timeFrames[1];
            timeFrames[0] = timeFrame;
            WarmUpSeriesUtil::warmUp(
                this.marketContext,
                timeFrames,
                500
            );

            if (isTesterWarmUp) {
                this.seriesWarmUpRequested[i] = true;
                this.seriesWarmUpRequestBarTimes[i] = currentBarTime;
            }

            if (shouldLogNotReady) {
                fromLogger.info(
                    "ZigZagElliotController::isAnalysisDataReady",
                    StringFormat(
                        "price series is not ready. symbol=%s timeframe=%s",
                        this.marketContext.symbolName,
                        EnumToString(timeFrame)
                    )
                );
            }
        }

        if (!isSynchronized) {
            return false;
        }

        if (!this.isTesterAnalysisHistoryReady(fromLogger)) {
            return false;
        }

        return true;
    }

private:
    enum AnalysisWarmUpBarCount {
        /** MN1のEMA60現在値と前値を取得するための必要本数。 */
        monthlyAnalysisWarmUpBars = 61,
        /** W1以下のEMA200最大shiftに安全余裕を加えた必要本数。 */
        standardAnalysisWarmUpBars = 206
    };

    /** 分析対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 対象時間足と取得状態を初期化済みの場合true。 */
    bool initialized;

    /** 通常チャートのタイマー実行の場合true。 */
    bool timerMode;

    /** 最後に通知したテスター分析履歴の進捗率。 */
    int lastAnalysisWarmUpProgress;

    /** MN1から表示足までの分析対象時間足。 */
    ENUM_TIMEFRAMES analysisTimeFrames[];

    /** 分析対象足ごとに未同期系列を再要求済みの場合true。 */
    bool seriesWarmUpRequested[];

    /** 分析対象足ごとの未同期系列を再要求した表示足バー時刻。 */
    datetime seriesWarmUpRequestBarTimes[];

    /**
     * 時間足ごとのテスター分析開始に必要な価格バー数を取得する。
     *
     * @param fromTimeFrame 判定対象の時間足
     * @return 分析開始に必要な価格バー数
     */
    int getRequiredAnalysisBars(ENUM_TIMEFRAMES fromTimeFrame) {
        if (fromTimeFrame == PERIOD_MN1) {
            return monthlyAnalysisWarmUpBars;
        }

        return standardAnalysisWarmUpBars;
    }

    /**
     * テスターの全分析対象時間足に必要な価格バー数があるか判定する。
     *
     * 全時間足で最も低い達成率を進捗率とし、変化した場合だけINFOへ
     * 出力する。インジケーターハンドルの計算完了は判定せず、必要本数
     * 到達後のCopyBufferと既存再試行へ委ねる。
     *
     * @param fromLogger 呼び出し元のロガー。
     * @return 全分析対象時間足の価格バー数が十分な場合true
     */
    bool isTesterAnalysisHistoryReady(Logger &fromLogger) {
        if (this.timerMode) {
            return true;
        }

        int total = ArraySize(this.analysisTimeFrames);
        bool isReady = true;
        int overallProgress = 100;
        ENUM_TIMEFRAMES bottleneckTimeFrame = PERIOD_CURRENT;
        int bottleneckProgressBars = 0;
        int bottleneckAvailableBars = 0;
        int bottleneckRequiredBars = 0;
        int availableBarsByTimeFrame[];
        ArrayResize(availableBarsByTimeFrame, total);

        for (int i = 0; i < total; i++) {
            ENUM_TIMEFRAMES timeFrame = this.analysisTimeFrames[i];
            int requiredBars = this.getRequiredAnalysisBars(timeFrame);
            int availableBars = Bars(
                this.marketContext.symbolName,
                timeFrame
            );
            availableBarsByTimeFrame[i] = availableBars;
            int progressBars = availableBars;

            if (progressBars < 0) {
                progressBars = 0;
            }

            if (progressBars > requiredBars) {
                progressBars = requiredBars;
            }

            int timeFrameProgress = progressBars * 100 / requiredBars;

            if (bottleneckTimeFrame == PERIOD_CURRENT
                    || (long)progressBars * bottleneckRequiredBars
                        < (long)bottleneckProgressBars * requiredBars) {
                bottleneckTimeFrame = timeFrame;
                bottleneckProgressBars = progressBars;
                bottleneckAvailableBars = availableBars;
                bottleneckRequiredBars = requiredBars;
            }

            if (timeFrameProgress < overallProgress) {
                overallProgress = timeFrameProgress;
            }

            if (availableBars < requiredBars) {
                isReady = false;
            }
        }

        if (overallProgress != this.lastAnalysisWarmUpProgress) {
            string insufficientDetails = "";
            string allBarDetails = "";

            for (int i = 0; i < total; i++) {
                ENUM_TIMEFRAMES timeFrame = this.analysisTimeFrames[i];
                int requiredBars = this.getRequiredAnalysisBars(timeFrame);
                int availableBars = availableBarsByTimeFrame[i];
                string barDetails = StringFormat(
                    "%s:%d/%d",
                    TimeUtil::convertTimeFrameToString(timeFrame),
                    availableBars,
                    requiredBars
                );

                if (allBarDetails != "") {
                    allBarDetails += ", ";
                }

                allBarDetails += barDetails;

                if (availableBars < requiredBars) {
                    if (insufficientDetails != "") {
                        insufficientDetails += ", ";
                    }

                    insufficientDetails += barDetails;
                }
            }

            if (isReady) {
                fromLogger.info(
                    "ZigZagElliotController::isTesterAnalysisHistoryReady",
                    StringFormat(
                        "tester analysis history warm-up completed. simulatedTime=%s progress=100%% bars=%s",
                        TimeToString(
                            TimeCurrent(),
                            TIME_DATE | TIME_MINUTES
                        ),
                        allBarDetails
                    )
                );
            } else {
                fromLogger.info(
                    "ZigZagElliotController::isTesterAnalysisHistoryReady",
                    StringFormat(
                        "tester analysis history warm-up progress. simulatedTime=%s progress=%d%% bottleneck=%s bars=%d/%d insufficient=%s",
                        TimeToString(
                            TimeCurrent(),
                            TIME_DATE | TIME_MINUTES
                        ),
                        overallProgress,
                        TimeUtil::convertTimeFrameToString(
                            bottleneckTimeFrame
                        ),
                        bottleneckAvailableBars,
                        bottleneckRequiredBars,
                        insufficientDetails
                    )
                );
            }

            this.lastAnalysisWarmUpProgress = overallProgress;
        }

        return isReady;
    }

    /**
     * 未同期系列の再要求をまとめる表示足バー時刻を取得する。
     *
     * 表示足系列が未準備の場合はテスター時刻を表示足単位へ丸める。
     * どちらも未取得の場合は0を返し、初回要求後は同期または時刻更新を待つ。
     *
     * @return 再要求をまとめるバー時刻
     */
    datetime getSeriesWarmUpRequestBarTime() {
        datetime currentBarTime = iTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            0
        );

        if (currentBarTime > 0) {
            return currentBarTime;
        }

        currentBarTime = TimeCurrent();
        int periodSeconds = PeriodSeconds(this.marketContext.timeFrame);

        if (currentBarTime > 0 && periodSeconds > 0) {
            currentBarTime -= currentBarTime % periodSeconds;
        }

        return currentBarTime;
    }
};

#endif // MSTNG_INDICATOR_ELLIOT_HISTORY_READINESS_MQH
