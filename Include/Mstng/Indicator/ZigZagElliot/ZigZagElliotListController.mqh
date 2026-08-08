//+------------------------------------------------------------------+
//|                              ZigZagElliotListController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_LIST_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_LIST_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Draw\DrawAlignedElliotAllList.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>
#include <Mstng\Elliot\ElliotListSortType.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Log\LogUtil.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 複数通貨Elliott一覧のライフサイクルと実行順序を管理するクラス。
 *
 * 全対象通貨を更新基準足の新規バーでMN1から分析し、指定開始足から
 * 表示足まで売買方向が一致した通貨をBUY、SELL別に描画する。
 */
class ZigZagElliotListController {
public:
    /**
     * 保持ポインタと実行状態を初期化する。
     */
    ZigZagElliotListController() {
        this.symbolNameInfoAll = NULL;
        this.oscillatorHandleManager = NULL;
        this.alignmentDecision = NULL;
        this.drawer = NULL;
        this.initialized = false;
        this.executing = false;
        this.timerEnabled = false;
        this.isTester = false;
        this.testerHistoryWarmUpEnabled = false;
        this.hasPendingAnalysis = false;
        this.updateTimeFrame = PERIOD_M5;
        this.lastProcessedBarTime = 0;
        this.lastTesterWarmUpCheckBarTime = 0;
        this.testerWarmUpCheckCount = 0;
        this.lastAnalysisWarmUpProgress = -1;
        this.pendingRetryCount = 0;
        this.maxPendingRetryCount = 3;
        this.retrySeconds = 2;
        ArrayResize(this.analysisTimeFrames, 0);
        ArrayResize(this.historyWarmUpTimeFrames, 0);
    }

    /**
     * 保持リソースを解放する。
     */
    ~ZigZagElliotListController() {
        this.destroy();
    }

    /**
     * 一覧基準の市場情報で複数通貨一覧を初期化する。
     *
     * @param fromMarketContext 一覧基準の市場コンテキスト
     * @param fromSortType 一覧の並び替え基準
     * @param fromAlignmentStartTimeFrame 一致判定の開始時間足
     * @param fromTesterHistoryWarmUpEnabled テスター履歴ゲートを使用する場合true
     * @return 初期化結果
     */
    int initialize(
        MarketContext &fromMarketContext,
        ElliotListSortType fromSortType = ELLIOT_LIST_SORT_ENTRY_PRIORITY,
        ENUM_TIMEFRAMES fromAlignmentStartTimeFrame = PERIOD_D1,
        bool fromTesterHistoryWarmUpEnabled = false
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.isTester = (bool)MQLInfoInteger(MQL_TESTER);
        this.testerHistoryWarmUpEnabled =
            fromTesterHistoryWarmUpEnabled && this.isTester;
        this.updateTimeFrame = PERIOD_M5;

        if (this.isTester
                && PeriodSeconds(this.marketContext.timeFrame)
                    > PeriodSeconds(PERIOD_M5)) {
            this.updateTimeFrame = this.marketContext.timeFrame;
        }

        this.lastProcessedBarTime = 0;
        this.lastTesterWarmUpCheckBarTime = 0;
        this.testerWarmUpCheckCount = 0;
        this.lastAnalysisWarmUpProgress = -1;
        this.pendingRetryCount = 0;
        this.hasPendingAnalysis = false;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.alignmentDecision = new ElliotDirectionAlignmentDecision(
            fromAlignmentStartTimeFrame
        );

        if (this.alignmentDecision == NULL) {
            this.logger.error(__FUNCTION__, "failed to create alignment decision");
            this.destroy();

            return INIT_FAILED;
        }

        ENUM_TIMEFRAMES alignmentTimeFrames[];

        if (!this.alignmentDecision.buildTargetTimeFrames(
            this.marketContext.timeFrame,
            alignmentTimeFrames
        )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "failed to build alignment timeframe range start=%s current=%s",
                    TimeUtil::convertTimeFrameToString(
                        fromAlignmentStartTimeFrame
                    ),
                    this.marketContext.timeFrameLabel
                )
            );
            this.destroy();

            return INIT_PARAMETERS_INCORRECT;
        }

        if (!ElliotTimeFrameRange::build(
            PERIOD_MN1,
            this.marketContext.timeFrame,
            this.analysisTimeFrames
        )) {
            this.logger.error(
                __FUNCTION__,
                "failed to build MN1 analysis timeframe range"
            );
            this.destroy();

            return INIT_PARAMETERS_INCORRECT;
        }

        this.buildHistoryWarmUpTimeFrames();

        this.symbolNameInfoAll = new SymbolNameInfoAll();

        if (this.symbolNameInfoAll == NULL) {
            this.logger.error(__FUNCTION__, "failed to create symbol list");
            this.destroy();

            return INIT_FAILED;
        }

        this.symbolNameInfoAll.setAll();

        if (this.getTargetSymbolCount() == 0) {
            this.logger.error(__FUNCTION__, "target symbol list is empty");
            this.destroy();

            return INIT_FAILED;
        }

        this.warmUpTargetSymbols(this.historyWarmUpTimeFrames);

        this.oscillatorHandleManager =
            new OscillatorHandleManager(this.marketContext.timeFrame);

        if (this.oscillatorHandleManager == NULL) {
            this.logger.error(__FUNCTION__, "failed to create handle manager");
            this.destroy();

            return INIT_FAILED;
        }

        if (!this.oscillatorHandleManager.setSymbolNameInfoAll(
            this.symbolNameInfoAll
        )) {
            this.logger.error(__FUNCTION__, "failed to configure handle pools");
            this.destroy();

            return INIT_FAILED;
        }

        this.oscillatorHandleManager.setTimeframesFromMn1ToAll();
        this.drawer = new DrawAlignedElliotAllList(0, 0, fromSortType);

        if (this.drawer == NULL) {
            this.logger.error(__FUNCTION__, "failed to create list drawer");
            this.destroy();

            return INIT_FAILED;
        }

        if (!this.isTester) {
            this.timerEnabled = EventSetTimer(this.retrySeconds);

            if (!this.timerEnabled) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "EventSetTimer failed seconds=%d error=%d",
                        this.retrySeconds,
                        GetLastError()
                    )
                );
            }
        }

        this.initialized = true;
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return INIT_SUCCEEDED;
    }

    /**
     * OnCalculateイベントを処理する。
     *
     * @param fromRatesTotal 全バー数
     * @return 次回計算用の処理済みバー数
     */
    int onCalculate(const int fromRatesTotal) {
        if (!this.initialized) {
            return fromRatesTotal;
        }

        this.execute(this.isTester);

        return fromRatesTotal;
    }

    /**
     * OnTimerイベントでM5新規バー確認と分析失敗時の再試行を行う。
     */
    void onTimer() {
        if (!this.initialized || this.isTester) {
            return;
        }

        this.execute(true);
    }

private:
    enum AnalysisWarmUpBarCount {
        /** MN1のEMA60現在値と前値を取得するための必要本数。 */
        monthlyAnalysisWarmUpBars = 61,
        /** W1以下のEMA200最大shiftに安全余裕を加えた必要本数。 */
        standardAnalysisWarmUpBars = 206
    };

    /** 一覧基準の市場コンテキスト。 */
    MarketContext marketContext;

    /** 全対象シンボル一覧。 */
    SymbolNameInfoAll *symbolNameInfoAll;

    /** 対象シンボル別オシレーターハンドル管理。 */
    OscillatorHandleManager *oscillatorHandleManager;

    /** 指定開始足から表示足までの方向一致判定。 */
    ElliotDirectionAlignmentDecision *alignmentDecision;

    /** BUY、SELL別一覧描画。 */
    DrawAlignedElliotAllList *drawer;

    /** ロガー。 */
    Logger logger;

    /** 初期化済みの場合true。 */
    bool initialized;

    /** 分析実行中の場合true。 */
    bool executing;

    /** 再試行用タイマーを開始した場合true。 */
    bool timerEnabled;

    /** ストラテジーテスターの場合true。 */
    bool isTester;

    /** テスター履歴ウォームアップゲートを使用する場合true。 */
    bool testerHistoryWarmUpEnabled;

    /** 分析未完了の対象が存在する場合true。 */
    bool hasPendingAnalysis;

    /** 分析更新の基準時間足。ライブではM5。 */
    ENUM_TIMEFRAMES updateTimeFrame;

    /** 最後に分析した更新基準足のバー時刻。 */
    datetime lastProcessedBarTime;

    /** 最後にテスター履歴本数を確認した更新基準足のバー時刻。 */
    datetime lastTesterWarmUpCheckBarTime;

    /** テスター履歴を確認した更新基準足の本数。 */
    int testerWarmUpCheckCount;

    /** 最後に通知したテスター分析履歴の進捗率。 */
    int lastAnalysisWarmUpProgress;

    /** MN1から一覧基準足までの分析対象時間足。 */
    ENUM_TIMEFRAMES analysisTimeFrames[];

    /** 価格系列を取得要求する安全な参照順の時間足。 */
    ENUM_TIMEFRAMES historyWarmUpTimeFrames[];

    /** 現在バーで実行した分析再試行回数。 */
    int pendingRetryCount;

    /** 1バー内の最大分析再試行回数。 */
    int maxPendingRetryCount;

    /** 分析再試行タイマー秒数。 */
    int retrySeconds;

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
     * 価格系列を取得要求する時間足順を構築する。
     *
     * Open Pricesテスターでは一覧基準足を最初に参照し、そこから
     * 上位足へ進める。その他の実行では既存の分析順を維持する。
     */
    void buildHistoryWarmUpTimeFrames() {
        int total = ArraySize(this.analysisTimeFrames);
        ArrayResize(this.historyWarmUpTimeFrames, total);

        for (int i = 0; i < total; i++) {
            if (this.testerHistoryWarmUpEnabled) {
                this.historyWarmUpTimeFrames[i] =
                    this.analysisTimeFrames[total - i - 1];
            } else {
                this.historyWarmUpTimeFrames[i] =
                    this.analysisTimeFrames[i];
            }
        }
    }

    /**
     * 全対象シンボルのテスター分析履歴が準備済みか判定する。
     *
     * 価格系列を同期した後、全シンボル・全分析時間足のうち最も低い
     * 達成率を進捗率として、変化した場合だけINFOへ出力する。
     * インジケーターハンドルの計算完了は既存CopyBuffer再試行へ委ねる。
     *
     * @param fromCurrentBarTime 現在の更新基準足バー時刻
     * @return 全対象シンボルの価格履歴が十分な場合true
     */
    bool isTesterAnalysisHistoryReady(datetime fromCurrentBarTime) {
        if (!this.testerHistoryWarmUpEnabled) {
            return true;
        }

        if (this.lastAnalysisWarmUpProgress == 100) {
            return true;
        }

        if (this.lastTesterWarmUpCheckBarTime == fromCurrentBarTime) {
            return false;
        }

        if (this.symbolNameInfoAll == NULL
                || ArraySize(this.analysisTimeFrames) == 0
                || ArraySize(this.historyWarmUpTimeFrames)
                    != ArraySize(this.analysisTimeFrames)) {
            return false;
        }

        this.testerWarmUpCheckCount++;
        bool heartbeatRequired =
            this.testerWarmUpCheckCount % 30 == 0;

        bool isSeriesReady = true;
        string firstPendingSymbol = "";
        ENUM_TIMEFRAMES firstPendingTimeFrame = PERIOD_CURRENT;
        int symbolTotal = this.symbolNameInfoAll.size();
        int warmUpTimeFrameTotal =
            ArraySize(this.historyWarmUpTimeFrames);
        int synchronizedSeries = 0;
        int synchronizationSeriesTotal = 0;

        for (int i = 0; i < symbolTotal; i++) {
            SymbolNameInfo *info =
                this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (info == NULL || !info.isTarget) {
                continue;
            }

            ENUM_TIMEFRAMES pendingTimeFrames[];
            ArrayResize(pendingTimeFrames, 0);

            for (int j = 0; j < warmUpTimeFrameTotal; j++) {
                ENUM_TIMEFRAMES timeFrame =
                    this.historyWarmUpTimeFrames[j];
                synchronizationSeriesTotal++;

                if (WarmUpSeriesUtil::isSeriesSynchronized(
                    info.symbolName,
                    timeFrame
                )) {
                    synchronizedSeries++;
                    continue;
                }

                isSeriesReady = false;
                int pendingTotal = ArraySize(pendingTimeFrames);
                ArrayResize(pendingTimeFrames, pendingTotal + 1);
                pendingTimeFrames[pendingTotal] = timeFrame;

                if (firstPendingSymbol == "") {
                    firstPendingSymbol = info.symbolName;
                    firstPendingTimeFrame = timeFrame;
                }
            }

            if (ArraySize(pendingTimeFrames) > 0) {
                MarketContext symbolContext(
                    info.symbolName,
                    this.marketContext.timeFrame
                );
                WarmUpSeriesUtil::warmUp(
                    symbolContext,
                    pendingTimeFrames,
                    500
                );
            }
        }

        if (!isSeriesReady) {
            this.lastTesterWarmUpCheckBarTime = fromCurrentBarTime;

            if (this.lastAnalysisWarmUpProgress != -2
                    || heartbeatRequired) {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "tester list history synchronization is in progress. simulatedTime=%s synchronizedSeries=%d/%d firstPending=%s,%s",
                        TimeToString(
                            fromCurrentBarTime,
                            TIME_DATE | TIME_MINUTES
                        ),
                        synchronizedSeries,
                        synchronizationSeriesTotal,
                        firstPendingSymbol,
                        TimeUtil::convertTimeFrameToString(
                            firstPendingTimeFrame
                        )
                    )
                );
                this.lastAnalysisWarmUpProgress = -2;
            }

            return false;
        }

        bool isReady = true;
        int overallProgress = 100;
        int totalSeries = 0;
        int readySeries = 0;
        string bottleneckSymbol = "";
        ENUM_TIMEFRAMES bottleneckTimeFrame = PERIOD_CURRENT;
        int bottleneckProgressBars = 0;
        int bottleneckAvailableBars = 0;
        int bottleneckRequiredBars = 1;

        for (int i = 0; i < symbolTotal; i++) {
            SymbolNameInfo *info =
                this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (info == NULL || !info.isTarget) {
                continue;
            }

            for (int j = 0; j < warmUpTimeFrameTotal; j++) {
                ENUM_TIMEFRAMES timeFrame =
                    this.historyWarmUpTimeFrames[j];
                int requiredBars = this.getRequiredAnalysisBars(timeFrame);
                int availableBars = Bars(info.symbolName, timeFrame);
                int progressBars = availableBars;

                if (progressBars < 0) {
                    progressBars = 0;
                }

                if (progressBars > requiredBars) {
                    progressBars = requiredBars;
                }

                int timeFrameProgress = progressBars * 100 / requiredBars;
                totalSeries++;

                if (availableBars >= requiredBars) {
                    readySeries++;
                } else {
                    isReady = false;
                }

                if (bottleneckSymbol == ""
                        || (long)progressBars * bottleneckRequiredBars
                            < (long)bottleneckProgressBars * requiredBars) {
                    bottleneckSymbol = info.symbolName;
                    bottleneckTimeFrame = timeFrame;
                    bottleneckProgressBars = progressBars;
                    bottleneckAvailableBars = availableBars;
                    bottleneckRequiredBars = requiredBars;
                }

                if (timeFrameProgress < overallProgress) {
                    overallProgress = timeFrameProgress;
                }
            }
        }

        if (totalSeries == 0) {
            return false;
        }

        this.lastTesterWarmUpCheckBarTime = fromCurrentBarTime;

        if (overallProgress != this.lastAnalysisWarmUpProgress
                || heartbeatRequired) {
            if (isReady) {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "tester list history warm-up completed. simulatedTime=%s progress=100%% readySeries=%d/%d",
                        TimeToString(
                            fromCurrentBarTime,
                            TIME_DATE | TIME_MINUTES
                        ),
                        readySeries,
                        totalSeries
                    )
                );
            } else {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "tester list history warm-up progress. simulatedTime=%s progress=%d%% readySeries=%d/%d bottleneck=%s,%s bars=%d/%d",
                        TimeToString(
                            fromCurrentBarTime,
                            TIME_DATE | TIME_MINUTES
                        ),
                        overallProgress,
                        readySeries,
                        totalSeries,
                        bottleneckSymbol,
                        TimeUtil::convertTimeFrameToString(
                            bottleneckTimeFrame
                        ),
                        bottleneckAvailableBars,
                        bottleneckRequiredBars
                    )
                );
            }

            this.lastAnalysisWarmUpProgress = overallProgress;
        }

        return isReady;
    }

    /**
     * 更新基準足の新規バーまたは未完了時に全対象通貨を分析する。
     *
     * @param fromAllowPendingRetry 同一更新基準足の未完了分析を再試行する場合true
     */
    void execute(bool fromAllowPendingRetry) {
        if (!this.initialized || this.executing) {
            return;
        }

        datetime currentBarTime = iTime(
            this.marketContext.symbolName,
            this.updateTimeFrame,
            0
        );

        if (currentBarTime == 0) {
            return;
        }

        bool isNewBar = currentBarTime != this.lastProcessedBarTime;

        if (!isNewBar) {
            if (!fromAllowPendingRetry
                    || !this.hasPendingAnalysis
                    || this.pendingRetryCount >= this.maxPendingRetryCount) {
                return;
            }

            this.pendingRetryCount++;
        } else {
            this.pendingRetryCount = 0;
        }

        if (!this.isTesterAnalysisHistoryReady(currentBarTime)) {
            return;
        }

        this.executing = true;
        ElliotAllList *elliotAllList = new ElliotAllList(
            this.marketContext.timeFrame,
            false
        );

        if (elliotAllList == NULL) {
            this.logger.error(__FUNCTION__, "failed to create ElliotAllList");
            this.hasPendingAnalysis = true;
            this.executing = false;

            return;
        }

        elliotAllList.setAnalysisStartTimeFrame(PERIOD_MN1);

        elliotAllList.setList(
            this.oscillatorHandleManager,
            this.symbolNameInfoAll
        );

        this.hasPendingAnalysis = this.containsPendingAnalysis(elliotAllList);

        if (!this.drawer.draw(elliotAllList, this.alignmentDecision)) {
            this.logger.error(__FUNCTION__, "failed to draw aligned Elliot list");
            this.hasPendingAnalysis = true;
        }

        delete elliotAllList;

        this.lastProcessedBarTime = currentBarTime;
        this.executing = false;
    }

    /**
     * 対象シンボル数を取得する。
     *
     * @return isTargetがtrueのシンボル数
     */
    int getTargetSymbolCount() {
        if (this.symbolNameInfoAll == NULL) {
            return 0;
        }

        int count = 0;
        int total = this.symbolNameInfoAll.size();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info = this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (info != NULL && info.isTarget) {
                count++;
            }
        }

        return count;
    }

    /**
     * 対象シンボルの価格系列を非同期取得対象へ登録する。
     *
     * @param fromTimeFrames MN1から表示足までの対象時間足一覧
     */
    void warmUpTargetSymbols(const ENUM_TIMEFRAMES &fromTimeFrames[]) {
        int total = this.symbolNameInfoAll.size();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info = this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (info == NULL || !info.isTarget) {
                continue;
            }

            if (!SymbolSelect(info.symbolName, true)) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "SymbolSelect failed symbol=%s error=%d",
                        info.symbolName,
                        GetLastError()
                    )
                );
            }

            MarketContext symbolContext(
                info.symbolName,
                this.marketContext.timeFrame
            );
            WarmUpSeriesUtil::warmUp(
                symbolContext,
                fromTimeFrames,
                500
            );
        }
    }

    /**
     * 一致判定に必要な分析結果が欠けた対象があるか判定する。
     *
     * @param fromElliotAllList 複数シンボル分析結果
     * @return 分析未完了の対象が存在する場合true
     */
    bool containsPendingAnalysis(ElliotAllList *fromElliotAllList) {
        if (fromElliotAllList == NULL) {
            return true;
        }

        int total = fromElliotAllList.elliotAllList.Total();

        if (total != fromElliotAllList.targetCount) {
            return true;
        }

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(i);

            if (!this.alignmentDecision.isReady(
                elliotAll,
                this.marketContext.timeFrame
            )) {
                return true;
            }
        }

        return false;
    }

    /**
     * 保持している描画、判定、ハンドル、シンボル一覧を解放する。
     */
    void destroy() {
        if (this.timerEnabled) {
            EventKillTimer();
            this.timerEnabled = false;
        }

        if (this.drawer != NULL) {
            this.drawer.clear();
            delete this.drawer;
            this.drawer = NULL;
        }

        if (this.alignmentDecision != NULL) {
            delete this.alignmentDecision;
            this.alignmentDecision = NULL;
        }

        if (this.oscillatorHandleManager != NULL) {
            delete this.oscillatorHandleManager;
            this.oscillatorHandleManager = NULL;
        }

        if (this.symbolNameInfoAll != NULL) {
            delete this.symbolNameInfoAll;
            this.symbolNameInfoAll = NULL;
        }

        this.initialized = false;
        this.executing = false;
        this.testerHistoryWarmUpEnabled = false;
        this.hasPendingAnalysis = false;
        this.updateTimeFrame = PERIOD_M5;
        this.lastProcessedBarTime = 0;
        this.lastTesterWarmUpCheckBarTime = 0;
        this.testerWarmUpCheckCount = 0;
        this.lastAnalysisWarmUpProgress = -1;
        this.pendingRetryCount = 0;
        ArrayResize(this.analysisTimeFrames, 0);
        ArrayResize(this.historyWarmUpTimeFrames, 0);
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_LIST_CONTROLLER_MQH
