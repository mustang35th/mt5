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
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Log\LogUtil.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 複数通貨Elliott一覧のライフサイクルと実行順序を管理するクラス。
 *
 * 全対象通貨をM5の新規バーでMN1から分析し、D1から
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
        this.hasPendingAnalysis = false;
        this.updateTimeFrame = PERIOD_M5;
        this.lastProcessedBarTime = 0;
        this.pendingRetryCount = 0;
        this.maxPendingRetryCount = 3;
        this.retrySeconds = 2;
    }

    /**
     * 保持リソースを解放する。
     */
    ~ZigZagElliotListController() {
        this.destroy();
    }

    /**
     * 表示チャートの市場情報で複数通貨一覧を初期化する。
     *
     * @param fromMarketContext 表示チャートの市場コンテキスト
     * @return 初期化結果
     */
    int initialize(MarketContext &fromMarketContext) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.isTester = (bool)MQLInfoInteger(MQL_TESTER);
        this.updateTimeFrame = PERIOD_M5;

        if (this.isTester
                && PeriodSeconds(this.marketContext.timeFrame)
                    > PeriodSeconds(PERIOD_M5)) {
            this.updateTimeFrame = this.marketContext.timeFrame;
        }

        this.lastProcessedBarTime = 0;
        this.pendingRetryCount = 0;
        this.hasPendingAnalysis = false;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.alignmentDecision = new ElliotDirectionAlignmentDecision();

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
                "unsupported chart timeframe: "
                    + this.marketContext.timeFrameLabel
            );
            this.destroy();

            return INIT_PARAMETERS_INCORRECT;
        }

        ENUM_TIMEFRAMES analysisTimeFrames[];

        if (!ElliotTimeFrameRange::build(
            PERIOD_MN1,
            this.marketContext.timeFrame,
            analysisTimeFrames
        )) {
            this.logger.error(
                __FUNCTION__,
                "failed to build MN1 analysis timeframe range"
            );
            this.destroy();

            return INIT_PARAMETERS_INCORRECT;
        }

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

        this.warmUpTargetSymbols(analysisTimeFrames);

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
        this.drawer = new DrawAlignedElliotAllList(0);

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
    /** 表示チャートの市場コンテキスト。 */
    MarketContext marketContext;

    /** 全対象シンボル一覧。 */
    SymbolNameInfoAll *symbolNameInfoAll;

    /** 対象シンボル別オシレーターハンドル管理。 */
    OscillatorHandleManager *oscillatorHandleManager;

    /** D1から表示足までの方向一致判定。 */
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

    /** 分析未完了の対象が存在する場合true。 */
    bool hasPendingAnalysis;

    /** 分析更新の基準時間足。ライブではM5。 */
    ENUM_TIMEFRAMES updateTimeFrame;

    /** 最後に分析した更新基準足のバー時刻。 */
    datetime lastProcessedBarTime;

    /** 現在バーで実行した分析再試行回数。 */
    int pendingRetryCount;

    /** 1バー内の最大分析再試行回数。 */
    int maxPendingRetryCount;

    /** 分析再試行タイマー秒数。 */
    int retrySeconds;

    /**
     * M5新規バーまたは未完了分析の再試行時に全対象通貨を分析する。
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
        this.hasPendingAnalysis = false;
        this.updateTimeFrame = PERIOD_M5;
        this.lastProcessedBarTime = 0;
        this.pendingRetryCount = 0;
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_LIST_CONTROLLER_MQH
