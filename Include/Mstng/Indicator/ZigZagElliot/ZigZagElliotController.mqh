//+------------------------------------------------------------------+
//|                                       ZigZagElliotController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Indicator\ZigZagElliot\CurrencyStrengthPairRankController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ElliotAnalysisController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ElliotChartController.mqh>
#include <Mstng\Indicator\ZigZagElliot\Mtf3In3AlertController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Log\LogUtil.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * ZigZagElliotインジケータのライフサイクルと実行順序を管理するクラス。
 */
class ZigZagElliotController {
public:
    /**
     * 実行状態と保持ポインタを初期化する。
     */
    ZigZagElliotController() {
        this.currencyStrengthController = NULL;
        this.analysisController = NULL;
        this.chartController = NULL;
        this.alertController = NULL;
        this.timerMode = true;
        this.timerSeconds = 30;
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.lastProcessedBarTime = 0;
        this.lastAnalysisWarmUpProgress = -1;
        ArrayResize(this.analysisTimeFrames, 0);
    }

    /**
     * 保持リソースを解放する。
     */
    ~ZigZagElliotController() {
        this.destroy();
    }

    /**
     * 市場コンテキストと設定を使用して初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromConfig インジケータ設定
     * @return 初期化結果
     */
    int initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotConfig &fromConfig
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.config = fromConfig;
        this.timerMode = !Util::isStrategyTester();
        this.timerSeconds = 30;
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.lastProcessedBarTime = 0;
        this.lastAnalysisWarmUpProgress = -1;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "timerMode = %s",
                (string)this.timerMode
            )
        );

        if (!isH1W1ConfirmationModeValid(
                this.config.h1W1ConfirmationMode
        )) {
            this.logger.error(
                __FUNCTION__,
                "H1 W1 confirmation mode is invalid."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (!isH1DirectionAlignmentModeValid(
                this.config.h1DirectionAlignmentMode
        )) {
            this.logger.error(
                __FUNCTION__,
                "H1 direction alignment mode is invalid."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (!isH1Ema200ConfirmationModeValid(
                this.config.h1Ema200ConfirmationMode
        )) {
            this.logger.error(
                __FUNCTION__,
                "H1 EMA200 confirmation mode is invalid."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (this.config.currencyStrengthEnabled
                && !CurrencyStrengthCalculationProfile
                    ::isVoteWeightModeValid(
                        this.config.currencyStrengthVoteWeightMode
                    )) {
            this.logger.error(
                __FUNCTION__,
                "currency strength vote weight mode is invalid."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (this.config.mtf3In3AlertDatabaseEnabled
                && this.config.mtf3In3AlertDatabaseFileName == "") {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot database file name is empty."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (!this.timerMode
                && this.config.mtf3In3AlertDatabaseEnabled
                && !MQLInfoInteger(MQL_OPTIMIZATION)
                && !this.config.mtf3In3AlertDatabaseUseCommonFolder) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot database requires Common folder in Strategy Tester."
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (!ElliotTimeFrameRange::build(
                ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame(),
                this.marketContext.timeFrame,
                this.analysisTimeFrames
            )) {
            this.logger.error(
                __FUNCTION__,
                "failed to build analysis timeframe range"
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        SymbolSelect(this.marketContext.symbolName, true);

        if (this.timerMode) {
            this.timerSeconds = 1;
            EventSetTimer(this.timerSeconds);
        }

        WarmUpSeriesUtil::warmUp(
            this.marketContext,
            this.analysisTimeFrames,
            500
        );

        if (!this.createControllers()) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot controller initialization failed"
            );

            return INIT_FAILED;
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return INIT_SUCCEEDED;
    }

    /**
     * チャートイベントを処理する。
     *
     * @param fromId イベントID
     * @param fromObjectName オブジェクト名
     */
    void onChartEvent(
        const int fromId,
        const string fromObjectName
    ) {
        if (this.chartController == NULL
                || this.analysisController == NULL) {
            return;
        }

        ElliotAll *elliotAll =
            this.analysisController.getElliotAll();
        bool isRedrawn = false;

        if (fromId == CHARTEVENT_CHART_CHANGE) {
            if (this.currencyStrengthController != NULL) {
                this.currencyStrengthController.reposition();
            }

            isRedrawn =
                this.chartController.onChartChange(elliotAll);

            if (isRedrawn) {
                this.completeRedraw();
            }

            return;
        }

        if (fromId != CHARTEVENT_OBJECT_CLICK) {
            return;
        }

        isRedrawn = this.chartController.onObjectClick(
            fromObjectName,
            elliotAll
        );

        if (isRedrawn) {
            this.completeRedraw();
        }
    }

    /**
     * OnCalculateイベントを処理する。
     *
     * @param fromRatesTotal 全バー数
     * @return 次回計算用の処理済みバー数
     */
    int onCalculate(const int fromRatesTotal) {
        if (this.chartController == NULL) {
            return fromRatesTotal;
        }

        this.chartController.updateOnCalculate(this.timerMode);

        if (this.timerMode) {
            this.chartController.drawBidAsk();

            return fromRatesTotal;
        }

        this.execute();

        if (this.analysisController != NULL
                && this.chartController.syncVerticalFitButtonState(
                    this.analysisController.getElliotAll()
                )) {
            this.completeRedraw();
        }

        return fromRatesTotal;
    }

    /**
     * OnTimerイベントを処理する。
     */
    void onTimer() {
        if (this.chartController == NULL) {
            return;
        }

        this.chartController.updateOnTimer(this.timerMode);

        if (!this.timerInitialized) {
            this.updateTimerSeconds();
            this.timerInitialized = true;
        }

        if (!this.isExecuteTimerElapsed()) {
            if (this.analysisController != NULL
                    && this.chartController.updateIdle(
                        this.analysisController.getElliotAll()
                    )) {
                this.completeRedraw();
            }

            return;
        }

        this.lastExecuteTickCount = GetTickCount();
        this.execute();
    }

    /**
     * タイマーと全Controllerを解放する。
     */
    void destroy() {
        EventKillTimer();

        if (this.alertController != NULL) {
            delete this.alertController;
            this.alertController = NULL;
        }

        if (this.chartController != NULL) {
            delete this.chartController;
            this.chartController = NULL;
        }

        if (this.currencyStrengthController != NULL) {
            delete this.currencyStrengthController;
            this.currencyStrengthController = NULL;
        }

        if (this.analysisController != NULL) {
            delete this.analysisController;
            this.analysisController = NULL;
        }

        this.cleanupOrphanedObjects();
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.lastProcessedBarTime = 0;
        this.lastAnalysisWarmUpProgress = -1;
        ArrayResize(this.analysisTimeFrames, 0);
    }

private:
    enum AnalysisWarmUpBarCount {
        /** MN1のEMA60現在値と前値を取得するための必要本数。 */
        monthlyAnalysisWarmUpBars = 61,
        /** W1以下のEMA200最大shiftに安全余裕を加えた必要本数。 */
        standardAnalysisWarmUpBars = 206
    };

    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** インジケータ設定。 */
    ZigZagElliotConfig config;
    /** ロガー。 */
    Logger logger;
    /** 通貨強弱制御。 */
    CurrencyStrengthPairRankController *currencyStrengthController;
    /** Elliott分析制御。 */
    ElliotAnalysisController *analysisController;
    /** チャート表示制御。 */
    ElliotChartController *chartController;
    /** MTF_3in3アラート制御。 */
    Mtf3In3AlertController *alertController;
    /** タイマー実行の場合true。 */
    bool timerMode;
    /** 分析実行間隔秒。 */
    int timerSeconds;
    /** 時間足別の実行間隔を設定済みの場合true。 */
    bool timerInitialized;
    /** 前回分析実行時のTickCount。 */
    long lastExecuteTickCount;
    /** テスター分析およびアラート処理済みの最新バー時刻。 */
    datetime lastProcessedBarTime;
    /** 最後に通知したテスター分析履歴の進捗率。 */
    int lastAnalysisWarmUpProgress;
    /** MN1から表示足までの分析対象時間足。 */
    ENUM_TIMEFRAMES analysisTimeFrames[];

    /**
     * 各責務のControllerを作成する。
     *
     * @return すべて初期化できた場合true
     */
    bool createControllers() {
        this.analysisController = new ElliotAnalysisController();

        if (this.analysisController == NULL
                || !this.analysisController.initialize(
                    this.marketContext,
                    this.config,
                    this.timerMode
                )) {
            return false;
        }

        this.alertController = new Mtf3In3AlertController();

        if (this.alertController == NULL
                || !this.alertController.initialize(
                    this.marketContext,
                    this.config
                )) {
            return false;
        }

        this.chartController = new ElliotChartController();

        if (this.chartController == NULL
                || !this.chartController.initialize(
                    this.marketContext,
                    this.analysisController.getOscillatorHandlePool()
                )) {
            return false;
        }

        this.currencyStrengthController =
            new CurrencyStrengthPairRankController();

        if (this.currencyStrengthController == NULL) {
            return false;
        }

        this.currencyStrengthController.initialize(
            this.marketContext,
            this.config
        );

        return this.analysisController.initializeOutput();
    }

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
     * @return 全分析対象時間足の価格バー数が十分な場合true
     */
    bool isTesterAnalysisHistoryReady() {
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
        string insufficientDetails = "";
        string allBarDetails = "";

        for (int i = 0; i < total; i++) {
            ENUM_TIMEFRAMES timeFrame = this.analysisTimeFrames[i];
            int requiredBars = this.getRequiredAnalysisBars(timeFrame);
            int availableBars = Bars(
                this.marketContext.symbolName,
                timeFrame
            );
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

            if (allBarDetails != "") {
                allBarDetails += ", ";
            }

            allBarDetails += StringFormat(
                "%s:%d/%d",
                TimeUtil::convertTimeFrameToString(timeFrame),
                availableBars,
                requiredBars
            );

            if (availableBars >= requiredBars) {
                continue;
            }

            isReady = false;

            if (insufficientDetails != "") {
                insufficientDetails += ", ";
            }

            insufficientDetails += StringFormat(
                "%s:%d/%d",
                TimeUtil::convertTimeFrameToString(timeFrame),
                availableBars,
                requiredBars
            );
        }

        if (overallProgress != this.lastAnalysisWarmUpProgress) {
            if (isReady) {
                this.logger.info(
                    __FUNCTION__,
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
                this.logger.info(
                    __FUNCTION__,
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
     * 分析対象の価格系列が準備済みか判定する。
     *
     * 準備不足の場合は価格系列の取得を再要求し、次回実行へ持ち越す。
     *
     * @return 分析データが準備済みの場合true
     */
    bool isAnalysisDataReady() {
        int total = ArraySize(this.analysisTimeFrames);

        for (int i = 0; i < total; i++) {
            ENUM_TIMEFRAMES timeFrame = this.analysisTimeFrames[i];

            if (!WarmUpSeriesUtil::isSeriesSynchronized(
                    this.marketContext.symbolName,
                    timeFrame
                )) {
                WarmUpSeriesUtil::warmUp(
                    this.marketContext,
                    this.analysisTimeFrames,
                    500
                );
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "price series is not ready. symbol=%s timeframe=%s",
                        this.marketContext.symbolName,
                        EnumToString(timeFrame)
                    )
                );

                return false;
            }
        }

        if (!this.isTesterAnalysisHistoryReady()) {
            return false;
        }

        return true;
    }

    /**
     * 固定パネルを最前面へ戻してチャートを再描画する。
     */
    void completeRedraw() {
        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.redrawOnTop();
        }

        ChartRedraw(0);
    }

    /**
     * 初期化失敗や異常終了で残った所有オブジェクトを最終削除する。
     */
    void cleanupOrphanedObjects() {
        ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "ArrowMTF_3in3",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "CurrencyStrengthPairRank",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "Ema200Label",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "JapanTimeAxis",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "TextMTF_3in3",
            0,
            -1
        );
        ObjectDelete(
            0,
            Constant::PREFIX_FIXED + "ElliotInfoButton"
        );
        ObjectDelete(
            0,
            Constant::PREFIX_FIXED + "ElliotInfoModeButton"
        );
        ObjectDelete(
            0,
            Constant::PREFIX_FIXED + "ElliotVerticalFitButton"
        );
    }

    /**
     * 時間足に応じて分析実行間隔秒を設定する。
     */
    void updateTimerSeconds() {
        this.timerSeconds = 30;

        switch (this.marketContext.timeFrame) {
            case PERIOD_M15:
                this.timerSeconds = 25;
                break;
            case PERIOD_M5:
                this.timerSeconds = 20;
                break;
            case PERIOD_M1:
                this.timerSeconds = 15;
                break;
        }
    }

    /**
     * 前回実行から設定秒数が経過したか判定する。
     *
     * @return 実行間隔を経過した場合true
     */
    bool isExecuteTimerElapsed() {
        if (this.lastExecuteTickCount <= 0) {
            return true;
        }

        long elapsedMilliseconds =
            GetTickCount() - this.lastExecuteTickCount;
        long intervalMilliseconds =
            (long)this.timerSeconds * 1000;

        if (elapsedMilliseconds >= intervalMilliseconds) {
            return true;
        }

        return false;
    }

    /**
     * 通貨強弱更新、Elliott分析、描画および新規バー処理を実行する。
     *
     * テスターでは表示足の処理済みバーをスキップする。データ準備または
     * 分析に失敗した場合は処理済み時刻を更新せず、同一バーで再試行する。
     */
    void execute() {
        datetime analysisStartBarTime = iTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            0
        );

        if (analysisStartBarTime == 0
                || (!this.timerMode
                    && this.lastProcessedBarTime
                        == analysisStartBarTime)) {
            return;
        }

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.update();
        }

        long startTime = GetTickCount();
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "▼▼▼▼▼　Start Time: %s (MS: %d)",
                TimeToString(TimeCurrent(), TIME_SECONDS),
                startTime
            )
        );

        if (this.analysisController == NULL
                || this.currencyStrengthController == NULL) {
            return;
        }

        if (!this.isAnalysisDataReady()) {
            return;
        }

        CurrencyStrengthExecutionInfo executionInfo =
            this.currencyStrengthController.getExecutionInfo();

        if (!this.analysisController.analyze(
                executionInfo,
                this.timerSeconds)) {
            this.logger.info(
                __FUNCTION__,
                "Elliott analysis is not ready. retry on next execution."
            );
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return;
        }

        ElliotAll *elliotAll =
            this.analysisController.getElliotAll();

        datetime analysisEndBarTime = iTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            0
        );

        if (analysisEndBarTime == 0) {
            return;
        }

        if (this.chartController != NULL) {
            this.chartController.drawAll(elliotAll);
        }

        this.currencyStrengthController.redrawOnTop();

        if (!Util::isStrategyTester()) {
            ChartRedraw(0);
        }

        long endTime = GetTickCount();
        long elapsedTime = endTime - startTime;
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "　　　　　　　End Time: %s (MS: %d)",
                TimeToString(TimeCurrent(), TIME_SECONDS),
                endTime
            )
        );
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "▲▲▲▲▲　Total Elapsed Time: %d ms (%.3f seconds)",
                elapsedTime,
                (double)elapsedTime / 1000.0
            )
        );

        datetime currentBarTime = analysisEndBarTime;

        if (this.lastProcessedBarTime == currentBarTime) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

            return;
        }

        if (!this.timerMode) {
            this.analysisController.writeCsv();
        }

        this.logger.debug(__FUNCTION__, "exec EA!!!");

        if (this.alertController != NULL) {
            this.alertController.execute(elliotAll);
        }

        this.lastProcessedBarTime = currentBarTime;
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONTROLLER_MQH
