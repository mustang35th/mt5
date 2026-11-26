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
#include <Mstng\Common\UpdateTimingStats.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartMouseMoveSubscription.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankDeltaRibbon.mqh>
#include <Mstng\Draw\DrawElliotPanel.mqh>
#include <Mstng\Draw\DrawZigZagElliotEntryLines.mqh>
#include <Mstng\Draw\ElliotPanelLiveAdapter.mqh>
#include <Mstng\Indicator\ZigZagElliot\CurrencyStrengthPairRankController.mqh>
#include <Mstng\Indicator\ZigZagElliot\DatabaseAlertDisplayController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ElliotAnalysisController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ElliotChartController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ElliotHistoryReadiness.mqh>
#include <Mstng\Indicator\ZigZagElliot\M5ObservationDisplayController.mqh>
#include <Mstng\Indicator\ZigZagElliot\Mtf3In3AlertController.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotRankDeltaBandHistory.mqh>
#include <Mstng\Log\LogUtil.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 一つのイベントで発生したパネル更新とチャート再描画を、終了時に順番に反映する。
 */
class ZigZagElliotDrawBatch {
public:
    /**
     * パネルの描画要求を保留する。チャート再描画はメンバーのスコープで保留する。
     *
     * @param fromPanel 共有パネル。未初期化の場合はNULL。
     */
    ZigZagElliotDrawBatch(DrawElliotPanel *fromPanel) {
        this.panel = fromPanel;
        if (this.panel != NULL) {
            this.panel.beginDrawBatch();
        }
    }

    /**
     * 早期returnでもパネルを先に描画し、最後にチャートへ一度だけ反映する。
     */
    ~ZigZagElliotDrawBatch() {
        this.finish();
    }

    /**
     * 計測終了前に保留中の描画を反映する。複数回呼ばれても再描画しない。
     */
    void finish() {
        if (this.panel != NULL) {
            this.panel.endDrawBatch();
            this.panel = NULL;
        }

        this.redrawBatch.finish();
    }

private:
    /** イベント中だけ参照する共有パネル。 */
    DrawElliotPanel *panel;

    /** パネルの反映が済むまでチャート再描画を保留する。 */
    DrawChartRedrawBatch redrawBatch;
};

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
        this.rankDeltaBandHistory = NULL;
        this.rankDeltaRibbon = NULL;
        this.lastRankDeltaBandCheck = 0;
        this.databaseAlertDisplayController = NULL;
        this.m5ObservationDisplayController = NULL;
        this.elliotPanel = NULL;
        this.databaseAlertCleanupPending = true;
        this.analysisController = NULL;
        this.chartController = NULL;
        this.alertController = NULL;
        this.timerMode = true;
        this.timerSeconds = 30;
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.updateTimingStats.reset();
        this.timingLogRecorded = false;
        this.lastTimingLogTick = 0;
        this.lastProcessedBarTime = 0;
        this.gapWaitingChartBarTime = 0;
        this.gapWaitingM5BarTime = 0;
        this.historyReadiness.reset();
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
        DrawChartRedrawBatch redrawBatch;
        this.destroy();

        this.marketContext = fromMarketContext;
        this.config = fromConfig;
        if (this.marketContext.timeFrame == PERIOD_H1) {
            this.config.applyH1EntryPolicy();
        }
        this.timerMode = !Util::isStrategyTester();
        this.timerSeconds = 30;
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.updateTimingStats.reset();
        this.timingLogRecorded = false;
        this.lastTimingLogTick = 0;
        this.lastProcessedBarTime = 0;
        this.gapWaitingChartBarTime = 0;
        this.gapWaitingM5BarTime = 0;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        if (this.logger.isDebugOutputEnabled()) {
            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "timerMode = %s",
                    (string)this.timerMode
                )
            );
        }

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

        if (!isElliotHigherTimeFrameDisplayCountValid(
                this.config.elliotHigherTimeFrameDisplayCount
        )) {
            this.logger.error(
                __FUNCTION__,
                "Elliott higher timeframe display count is invalid."
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

        if (Util::isStrategyTester()
                && this.config.mtf3In3AlertDatabaseEnabled
                && this.config.mtf3In3AlertTesterSaveStartTime < 0) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot tester database save start time is invalid."
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

        if (!this.historyReadiness.initialize(this.marketContext, this.timerMode)) {
            this.logger.error(
                __FUNCTION__,
                "failed to build analysis timeframe range"
            );

            return INIT_PARAMETERS_INCORRECT;
        }

        if (this.config.databaseAlertDisplayEnabled
                && (this.marketContext.timeFrame == PERIOD_M5 || this.marketContext.timeFrame == PERIOD_M15
                    || this.marketContext.timeFrame == PERIOD_H1)) {
            this.databaseAlertDisplayController = new DatabaseAlertDisplayController();
            if (this.databaseAlertDisplayController == NULL
                    || !this.databaseAlertDisplayController.initialize(this.marketContext, this.config)) {
                return INIT_PARAMETERS_INCORRECT;
            }
        }

        if (this.config.m5ObservationDisplayEnabled
                && (this.marketContext.timeFrame == PERIOD_M1 || this.marketContext.timeFrame == PERIOD_M5)) {
            this.m5ObservationDisplayController = new M5ObservationDisplayController();
            if (this.m5ObservationDisplayController == NULL
                    || !this.m5ObservationDisplayController.initialize(this.marketContext, this.config)) {
                this.logger.error(__FUNCTION__, "M5 observation display settings are invalid");
                return INIT_PARAMETERS_INCORRECT;
            }
        }

        SymbolSelect(this.marketContext.symbolName, true);

        if (this.timerMode) {
            this.timerSeconds = 1;
            EventSetTimer(this.timerSeconds);
        }

        this.historyReadiness.requestHistory();

        if (!this.createControllers()) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot controller initialization failed"
            );

            return INIT_FAILED;
        }

        this.elliotPanel = new DrawElliotPanel(0,
            "ZzePanel-" + IntegerToString((long)GetMicrosecondCount()) + "-");
        if (this.elliotPanel == NULL) {
            return INIT_FAILED;
        }

        ZigZagElliotDrawBatch drawBatch(this.elliotPanel);
        this.chartController.setElliotPanel(this.elliotPanel);
        if (this.m5ObservationDisplayController != NULL) {
            this.m5ObservationDisplayController.setPanel(this.elliotPanel);
        }

        ElliotPanelData waitingPanel;
        waitingPanel.symbolName = this.marketContext.symbolName;
        waitingPanel.digits = this.marketContext.digits;
        waitingPanel.status = "分析データの準備待ち";
        this.elliotPanel.updateLive(waitingPanel);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return INIT_SUCCEEDED;
    }

    /**
     * チャートイベントを処理する。
     *
     * @param fromId イベントID
     * @param fromObjectName オブジェクト名
     * @param fromMouseX マウス移動時のチャート内の横位置。
     * @param fromMouseY マウス移動時のチャート内の縦位置。
     */
    void onChartEvent(
        const int fromId,
        const string fromObjectName,
        const int fromMouseX = 0,
        const int fromMouseY = 0
    ) {
        ZigZagElliotDrawBatch drawBatch(this.elliotPanel);
        if (fromId == CHARTEVENT_MOUSE_MOVE) {
            if (this.rankDeltaRibbon != NULL) {
                this.rankDeltaRibbon.handleMouseMove(fromMouseX, fromMouseY, this.rankDeltaBandHistory);
            }

            if (this.m5ObservationDisplayController != NULL) {
                this.m5ObservationDisplayController.onMouseMove(fromMouseX, fromMouseY);
            }

            return;
        }

        if (fromId == CHARTEVENT_OBJECT_CLICK && this.elliotPanel != NULL) {
            ENUM_ELLIOT_PANEL_ACTION action = this.elliotPanel.onObjectClick(fromObjectName);
            if (action != ELLIOT_PANEL_ACTION_NONE) {
                if (this.m5ObservationDisplayController != NULL) {
                    if (action == ELLIOT_PANEL_ACTION_PREVIOUS) {
                        this.m5ObservationDisplayController.navigatePanel(-1);
                    } else if (action == ELLIOT_PANEL_ACTION_NEXT) {
                        this.m5ObservationDisplayController.navigatePanel(1);
                    } else {
                        this.m5ObservationDisplayController.redraw();
                    }
                }

                if (this.chartController != NULL) {
                    this.chartController.syncElliotPanelState();
                }

                this.elliotPanel.draw();
                DrawChartRedrawBatch::request(0);

                return;
            }
        }

        if (this.m5ObservationDisplayController != NULL) {
            if (fromId == CHARTEVENT_CHART_CHANGE) {
                this.m5ObservationDisplayController.update(true);
            } else if (fromId == CHARTEVENT_OBJECT_CLICK
                    && this.m5ObservationDisplayController.onObjectClick(fromObjectName)) {
                this.m5ObservationDisplayController.redraw();
                if (this.chartController != NULL) {
                    this.chartController.syncElliotPanelState();
                }

                DrawChartRedrawBatch::request(0);
                return;
            }
        }

        this.prepareDatabaseAlertDisplay();
        if (this.chartController == NULL
                || this.analysisController == NULL) {
            return;
        }

        ElliotAll *elliotAll =
            this.analysisController.getElliotAll();
        bool isRedrawn = false;

        if (fromId == CHARTEVENT_CHART_CHANGE) {
            ulong startMicroseconds = this.chartController.startSlowOperation();
            this.beginCurrencyStrengthRedrawBatch();
            this.drawRankDeltaBand();

            if (this.currencyStrengthController != NULL) {
                this.currencyStrengthController.reposition();
            }

            isRedrawn =
                this.chartController.onChartChange(elliotAll);

            if (isRedrawn || this.databaseAlertDisplayController != NULL || this.elliotPanel != NULL) {
                this.completeRedraw();
            }

            this.endCurrencyStrengthRedrawBatch();
            this.chartController.completeSlowOperation(stageChartEvent, startMicroseconds);

            return;
        }

        if (fromId != CHARTEVENT_OBJECT_CLICK) {
            return;
        }

        ulong startMicroseconds = this.chartController.startSlowOperation();
        isRedrawn = this.chartController.onObjectClick(
            fromObjectName,
            elliotAll
        );

        if (isRedrawn) {
            this.completeRedraw();
        }

        this.chartController.completeSlowOperation(stageChartEvent, startMicroseconds);
    }

    /**
     * チャート足の時刻から帯を更新し、波動分析の待機中も順位の変化を反映する。
     */
    void updateRankDeltaBand(const int fromRatesTotal, const int fromPrevCalculated, const datetime &fromTime[]) {
        if (this.rankDeltaBandHistory == NULL || this.rankDeltaRibbon == NULL) {
            return;
        }

        int revision = this.rankDeltaBandHistory.getRevision();
        if (!this.rankDeltaBandHistory.update(fromRatesTotal, fromPrevCalculated, fromTime, TimeCurrent())) {
            return;
        }

        if (revision != this.rankDeltaBandHistory.getRevision() || this.lastRankDeltaBandCheck == 0
                || GetTickCount64() - this.lastRankDeltaBandCheck >= 10000) {
            this.drawRankDeltaBand();
        }
    }

    /**
     * OnCalculateイベントを処理する。
     *
     * @param fromRatesTotal 全バー数
     * @param fromPrevCalculated OnCalculateの前回計算済みバー数
     * @param fromCurrentBarTime OnCalculateの最新足時刻。0の場合は各表示側で取得する
     * @return 次回計算用の処理済みバー数
     */
    int onCalculate(const int fromRatesTotal, const int fromPrevCalculated = 0,
            const datetime fromCurrentBarTime = 0) {
        ZigZagElliotDrawBatch drawBatch(this.elliotPanel);
        if (this.m5ObservationDisplayController != NULL) {
            this.m5ObservationDisplayController.update();
        }

        this.prepareDatabaseAlertDisplay();
        if (this.chartController == NULL) {
            return fromRatesTotal;
        }

        ulong calculateStartMicroseconds = this.chartController.startSlowOperation();
        this.chartController.beginProcessingTimeUpdateBatch();

        bool isAnalysisDataReady = false;

        if (this.historyReadiness.isWarmingUp()) {
            isAnalysisDataReady = this.isAnalysisDataReady();

            if (!isAnalysisDataReady) {
                this.chartController.endProcessingTimeUpdateBatch();

                // 表示バッファが未計算の間は処理済みとして返さない。
                return 0;
            }
        }

        this.chartController.updateOnCalculate(
            this.timerMode, fromPrevCalculated, fromRatesTotal, fromCurrentBarTime);

        if (this.timerMode) {
            this.chartController.drawBidAsk();
            this.chartController.endProcessingTimeUpdateBatch();
            this.chartController.completeSlowOperation(stageCalculate, calculateStartMicroseconds);

            return fromRatesTotal;
        }

        this.execute(isAnalysisDataReady);

        if (this.analysisController != NULL
                && this.chartController.syncVerticalFitButtonState(
                    this.analysisController.getElliotAll()
                )) {
            this.completeRedraw();
        }

        this.chartController.endProcessingTimeUpdateBatch();

        return fromRatesTotal;
    }

    /**
     * OnTimerイベントを処理する。
     */
    void onTimer() {
        ZigZagElliotDrawBatch drawBatch(this.elliotPanel);
        ulong timerStartMicroseconds = GetMicrosecondCount();
        ulong timerEntryTick = GetTickCount64();

        if (this.m5ObservationDisplayController != NULL) {
            this.m5ObservationDisplayController.update();
        }

        this.prepareDatabaseAlertDisplay();
        if (this.chartController == NULL) {
            return;
        }

        this.chartController.beginProcessingTimeUpdateBatch();
        ulong auxiliaryStartMicroseconds = GetMicrosecondCount();
        this.chartController.updateOnTimer(this.timerMode);
        if (this.rankDeltaRibbon != NULL && timerEntryTick - this.lastRankDeltaBandCheck >= 10000) {
            this.drawRankDeltaBand();
        }

        ulong auxiliaryMicroseconds = GetMicrosecondCount() - auxiliaryStartMicroseconds;

        if (!this.timerInitialized) {
            this.updateTimerSeconds();
            this.timerInitialized = true;
        }

        if (!this.isExecuteTimerElapsed()) {
            ulong labelStartMicroseconds = GetMicrosecondCount();
            this.chartController.updateTimingStatus(
                this.updateTimingStats, this.timerSeconds, GetTickCount64());
            ulong labelMicroseconds = GetMicrosecondCount() - labelStartMicroseconds;

            if (this.analysisController != NULL
                    && this.chartController.updateIdle(
                        this.analysisController.getElliotAll()
                    )) {
                this.completeRedraw();
            }

            drawBatch.finish();
            this.completeTimerTiming(
                timerEntryTick, timerStartMicroseconds, labelMicroseconds, false);

            return;
        }

        this.lastExecuteTickCount = GetTickCount64();
        this.updateTimingStats.beginAttempt(
            timerEntryTick, this.lastExecuteTickCount, this.timerSeconds, auxiliaryMicroseconds);
        this.execute();
        ulong labelStartMicroseconds = GetMicrosecondCount();
        this.chartController.updateTimingStatus(
            this.updateTimingStats, this.timerSeconds, GetTickCount64());
        ulong labelMicroseconds = GetMicrosecondCount() - labelStartMicroseconds;
        drawBatch.finish();
        this.completeTimerTiming(
            timerEntryTick, timerStartMicroseconds, labelMicroseconds, true);
    }

    /**
     * タイマーと全Controllerを解放する。
     */
    void destroy() {
        EventKillTimer();

        this.rankDeltaBandMouseMove.release();
        if (this.rankDeltaRibbon != NULL) {
            delete this.rankDeltaRibbon;
            this.rankDeltaRibbon = NULL;
        }

        if (this.rankDeltaBandHistory != NULL) {
            delete this.rankDeltaBandHistory;
            this.rankDeltaBandHistory = NULL;
        }

        this.lastRankDeltaBandCheck = 0;

        if (this.m5ObservationDisplayController != NULL) {
            delete this.m5ObservationDisplayController;
            this.m5ObservationDisplayController = NULL;
        }

        if (this.databaseAlertDisplayController != NULL) {
            delete this.databaseAlertDisplayController;
            this.databaseAlertDisplayController = NULL;
        }

        if (this.alertController != NULL) {
            delete this.alertController;
            this.alertController = NULL;
        }

        if (this.chartController != NULL) {
            delete this.chartController;
            this.chartController = NULL;
        }

        if (this.elliotPanel != NULL) {
            delete this.elliotPanel;
            this.elliotPanel = NULL;
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

        this.databaseAlertCleanupPending = true;
        this.timerInitialized = false;
        this.lastExecuteTickCount = 0;
        this.updateTimingStats.reset();
        this.timingLogRecorded = false;
        this.lastTimingLogTick = 0;
        this.lastProcessedBarTime = 0;
        this.gapWaitingChartBarTime = 0;
        this.gapWaitingM5BarTime = 0;
        this.historyReadiness.reset();
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;

    /** インジケータ設定。 */
    ZigZagElliotConfig config;

    /** ロガー。 */
    Logger logger;

    /** 通貨強弱制御。 */
    CurrencyStrengthPairRankController *currencyStrengthController;

    /** 長中期・中短期をまとめたチャート足ごとの順位差履歴。 */
    ZigZagElliotRankDeltaBandHistory *rankDeltaBandHistory;

    /** メインチャートの2段の順位差増減帯。 */
    DrawCurrencyStrengthRankDeltaRibbon *rankDeltaRibbon;

    /** 同一チャート内で共有するツールチップ用のマウス移動通知。 */
    ChartMouseMoveSubscription rankDeltaBandMouseMove;

    /** 最後に帯の表示位置とマウス通知を確認した時刻（ミリ秒）。 */
    ulong lastRankDeltaBandCheck;

    /** Elliott分析制御。 */
    ElliotAnalysisController *analysisController;

    /** 分析履歴の同期・必要本数・再要求状態。 */
    ElliotHistoryReadiness historyReadiness;

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

    /** 前回分析実行時の単調増加時刻。単位: ミリ秒。 */
    ulong lastExecuteTickCount;

    /** 通常チャートの分析試行間隔・成功間隔・遅延を保持する診断値。 */
    UpdateTimingStats updateTimingStats;

    /** 更新診断を一度でもログへ出力した場合true。 */
    bool timingLogRecorded;

    /** 更新診断ログを最後に出力した単調増加ミリ秒。 */
    ulong lastTimingLogTick;

    /** テスター分析およびアラート処理済みの最新バー時刻。 */
    datetime lastProcessedBarTime;

    /** 増減判定のデータ到着を待っているチャート足。 */
    datetime gapWaitingChartBarTime;

    /** 同じチャート足でも、取得待ちを次のM5枠へ持ち越さないための対象時刻。 */
    datetime gapWaitingM5BarTime;

    /** 通常版の保存済みアラート表示。M5で有効時だけ保持する。 */
    DatabaseAlertDisplayController *databaseAlertDisplayController;

    /** 通常版M1・M5の保存済みM5観測表示。有効時だけ保持する。 */
    M5ObservationDisplayController *m5ObservationDisplayController;

    /** 現在値と保存値を切り替える、単一のエリオットパネル。 */
    DrawElliotPanel *elliotPanel;

    /** 初回の稼働中イベントで旧世代のDB描画を回収する場合true。 */
    bool databaseAlertCleanupPending;

    /**
     * 既存の処理時間表示を反映し、完了Timerの計測を保存する。
     * 診断表示は次のTimerへ反映し、自己計測のための二重描画は行わない。
     *
     * @param fromEntryTick Timer入口の単調増加ミリ秒
     * @param fromStartMicroseconds Timer入口の単調増加マイクロ秒
     * @param fromLabelMicroseconds 先に実行した更新診断ラベルの反映マイクロ秒
     * @param fromAnalysisExecuted 分析試行を含む場合true
     */
    void completeTimerTiming(ulong fromEntryTick, ulong fromStartMicroseconds,
            ulong fromLabelMicroseconds, bool fromAnalysisExecuted) {
        ulong labelStartMicroseconds = GetMicrosecondCount();
        this.chartController.endProcessingTimeUpdateBatch();
        ulong endMicroseconds = GetMicrosecondCount();
        ulong endTick = GetTickCount64();
        ulong labelMicroseconds = fromLabelMicroseconds
            + endMicroseconds - labelStartMicroseconds;
        this.updateTimingStats.recordTimer(fromEntryTick, endTick,
            endMicroseconds - fromStartMicroseconds, labelMicroseconds, fromAnalysisExecuted);
        if (this.updateTimingStats.hasTimerGap()) {
            this.chartController.recordSlowOperation(stageTimerGap,
                this.updateTimingStats.getTimerGapMilliseconds() * 1000);
        }

        this.logTimingDiagnostics(endTick);
        this.chartController.flushSlowOperationDiagnostics();
    }

    /**
     * 完了Timerの診断を最大60秒に1回だけINFOへ記録する。
     * gapは通常のタイマー待ち・診断ログ出力なども含み、純粋な他処理待ちとは区別する。
     *
     * @param fromCurrentTick 今回Timerの計測終了時刻
     */
    void logTimingDiagnostics(ulong fromCurrentTick) {
        if (!this.timerMode || (this.timingLogRecorded
                && fromCurrentTick >= this.lastTimingLogTick
                && fromCurrentTick - this.lastTimingLogTick < 60000)) {
            return;
        }

        ulong logStartMicroseconds = this.chartController.startSlowOperation();
        this.timingLogRecorded = true;
        this.lastTimingLogTick = fromCurrentTick;
        string mode = "idle";
        if (this.updateTimingStats.wasTimerAnalysisExecuted()) {
            mode = "analysis";
        }

        string gap = "--";
        if (this.updateTimingStats.hasTimerGap()) {
            gap = StringFormat("%I64d", (long)this.updateTimingStats.getTimerGapMilliseconds());
        }

        string attemptInterval = "--";
        string timerDelay = "--";
        if (this.updateTimingStats.hasAttemptInterval()) {
            attemptInterval = StringFormat("%I64d",
                (long)this.updateTimingStats.getAttemptIntervalMilliseconds());
            timerDelay = StringFormat("%I64d",
                (long)this.updateTimingStats.getTimerDelayMilliseconds());
        }

        this.logger.info(__FUNCTION__, StringFormat(
            "TIMING timerMs=%.1f labelsMs=%.1f maxTimerMs=%.1f maxLabelsMs=%.1f gapMs=%s mode=%s attemptIntervalMs=%s timerDelayMs=%s state=%s",
            this.updateTimingStats.getTimerMilliseconds(),
            this.updateTimingStats.getTimerLabelMilliseconds(),
            this.updateTimingStats.getMaximumTimerMilliseconds(),
            this.updateTimingStats.getMaximumTimerLabelMilliseconds(), gap, mode,
            attemptInterval, timerDelay,
            this.updateTimingStats.getLastState()));
        this.chartController.completeSlowOperation(stageLogOutput, logStartMicroseconds);
    }

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
                    this.analysisController.getOscillatorHandlePool(),
                    (int)this.config.elliotHigherTimeFrameDisplayCount,
                    this.config.currencyStrengthRankPanelXDistance
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

        return this.initializeRankDeltaBand() && this.analysisController.initializeOutput();
    }

    /**
     * 通常チャートとビジュアルテスターの表示に限り、順位差帯の履歴と描画を用意する。
     */
    bool initializeRankDeltaBand() {
        if (!this.config.currencyStrengthEnabled || !this.config.currencyStrengthRankDeltaBandVisible
                || (!this.timerMode && !MQLInfoInteger(MQL_VISUAL_MODE))) {
            return true;
        }

        string baseCurrency = SymbolInfoString(this.marketContext.symbolName, SYMBOL_CURRENCY_BASE);
        string quoteCurrency = SymbolInfoString(this.marketContext.symbolName, SYMBOL_CURRENCY_PROFIT);
        if (baseCurrency == "" || quoteCurrency == "" || baseCurrency == quoteCurrency) {
            return true;
        }

        this.rankDeltaBandHistory = new ZigZagElliotRankDeltaBandHistory(
            this.config.currencyStrengthDatabaseFileName, this.config.currencyStrengthDatabaseSplitByYear,
            this.config.currencyStrengthDatabaseUseCommonFolder, this.config.currencyStrengthDatabaseProfile,
            this.config.currencyStrengthVoteWeightMode, !this.timerMode, baseCurrency, quoteCurrency,
            this.config.currencyStrengthRefreshSeconds);
        string suffix = StringFormat("%I64u", GetMicrosecondCount());
        this.rankDeltaRibbon = new DrawCurrencyStrengthRankDeltaRibbon(ChartID(), suffix, baseCurrency, quoteCurrency);

        return this.rankDeltaBandHistory != NULL && this.rankDeltaRibbon != NULL;
    }

    /**
     * 表示範囲の変更や描画失敗を確認する。履歴のDB取得は行わない。
     */
    void drawRankDeltaBand() {
        if (this.rankDeltaRibbon == NULL || this.rankDeltaBandHistory == NULL) {
            return;
        }

        this.lastRankDeltaBandCheck = GetTickCount64();
        this.rankDeltaBandMouseMove.acquire(ChartID());
        this.rankDeltaRibbon.draw(this.rankDeltaBandHistory);
    }

    /**
     * 分析対象の価格系列が準備済みか判定する。
     *
     * 未同期の時間足だけ価格系列の取得を再要求し、次回実行へ持ち越す。
     *
     * @return 分析データが準備済みの場合true
     */
    bool isAnalysisDataReady() {
        return this.historyReadiness.isReady(this.logger);
    }

    /**
     * 通貨強弱パネルの再描画要求を処理終了まで保留する。
     */
    void beginCurrencyStrengthRedrawBatch() {
        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.beginRedrawBatch();
        }
    }

    /**
     * 通貨強弱パネルとチャートの再描画要求をまとめて反映する。
     *
     * @param fromForceRedraw パネル以外の変更でも再描画する場合true。
     */
    void endCurrencyStrengthRedrawBatch(bool fromForceRedraw = false) {
        ulong startMicroseconds = 0;
        if (this.chartController != NULL) {
            startMicroseconds = this.chartController.startSlowOperation();
        }

        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.endRedrawBatch(fromForceRedraw);
        } else if (fromForceRedraw) {
            DrawChartRedrawBatch::request(0);
        }

        if (this.chartController != NULL) {
            this.chartController.completeSlowOperation(stageRedraw, startMicroseconds);
        }
    }

    /**
     * 分析・アラート描画後にDBラベルを更新し、固定パネルを最後に一度だけ手前へ戻す。
     * 分析開始時から保留した再描画要求もここでまとめて反映する。
     */
    void completeAnalysisDraw(const datetime fromBarTime) {
        if (this.databaseAlertDisplayController != NULL) {
            this.databaseAlertDisplayController.update(fromBarTime, TimeCurrent(), AccountInfoString(ACCOUNT_SERVER));
        }

        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.redrawOnTop();
        }

        if (this.m5ObservationDisplayController != NULL) {
            this.m5ObservationDisplayController.redraw();
        }

        if (this.elliotPanel != NULL) {
            this.elliotPanel.requestBringToFront();
        }

        this.updateElliotPanelLive();
        if (this.elliotPanel != NULL && this.elliotPanel.isSavedMode()) {
            this.elliotPanel.draw();
        }

        this.endCurrencyStrengthRedrawBatch(!Util::isStrategyTester());
    }

    /**
     * 計算済みの最新値をパネルの現在用キャッシュへ渡す。保存表示は変更しない。
     */
    void updateElliotPanelLive() {
        if (this.elliotPanel == NULL || this.analysisController == NULL
                || this.currencyStrengthController == NULL) {
            return;
        }

        CurrencyStrengthExecutionInfo strength = this.currencyStrengthController.getExecutionInfo();
        string weightLabel = "均等";
        if (this.config.currencyStrengthVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED) {
            weightLabel = "加重";
        }

        ElliotPanelData data;
        if (ElliotPanelLiveAdapter::build(this.analysisController.getElliotAll(), strength,
                this.config.currencyStrengthEnabled, weightLabel, data)) {
            this.elliotPanel.updateLive(data);
        }
    }

    /**
     * 固定パネルを最前面へ戻してチャートを再描画する。
     */
    void completeRedraw() {
        this.beginCurrencyStrengthRedrawBatch();

        if (this.databaseAlertDisplayController != NULL) {
            this.databaseAlertDisplayController.redraw(TimeCurrent());
        }

        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.redrawOnTop();
        }

        if (this.elliotPanel != NULL) {
            this.elliotPanel.requestBringToFront();
        }

        this.endCurrencyStrengthRedrawBatch(true);
    }

    /**
     * DB表示の設定・履歴準備によらず、単独稼働を確認して旧世代の表示を回収する。
     */
    void prepareDatabaseAlertDisplay() {
        if (!this.databaseAlertCleanupPending) {
            return;
        }

        string keepPrefix = "";
        if (this.databaseAlertDisplayController != NULL) {
            keepPrefix = this.databaseAlertDisplayController.getObjectPrefix();
        }

        if (DatabaseAlertDisplayController::cleanupOrphanedObjects(true, keepPrefix)) {
            this.databaseAlertCleanupPending = false;
        }
    }

    /**
     * 初期化失敗や異常終了で残った所有オブジェクトを最終削除する。
     */
    void cleanupOrphanedObjects() {
        DatabaseAlertDisplayController::cleanupOrphanedObjects(false);
        DrawZigZagElliotEntryLines::clear();
        ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "ZigZagElliotRound",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "ZigZagElliotInfo",
            0,
            -1
        );
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
            Constant::PREFIX_FIXED + "ZigZagElliotProcessingTime",
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

        DrawChartRedrawBatch::request();
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

        ulong elapsedMilliseconds =
            GetTickCount64() - this.lastExecuteTickCount;
        ulong intervalMilliseconds =
            (ulong)this.timerSeconds * 1000;

        if (elapsedMilliseconds >= intervalMilliseconds) {
            return true;
        }

        return false;
    }

    /**
     * 更新処理の所要時間と終了状態をチャートへ通知する。
     * 通知後の統計・ラベル更新時間は計測に含めない。
     *
     * @param fromStartMicroseconds 更新開始時の経過マイクロ秒
     * @param fromSucceeded 正常終了として集計する場合true
     * @param fromState 更新内容または再試行状態
     */
    void recordUpdateProcessingTime(ulong fromStartMicroseconds, bool fromSucceeded, string fromState) {
        ulong elapsedMicroseconds = GetMicrosecondCount() - fromStartMicroseconds;

        if (this.timerMode) {
            this.updateTimingStats.finishAttempt(
                GetTickCount64(), elapsedMicroseconds, fromSucceeded, fromState);
        }

        if (this.chartController != NULL) {
            this.chartController.recordProcessingTime(0, elapsedMicroseconds, fromSucceeded, fromState);
        }
    }

    /**
     * 通貨強弱更新、Elliott分析、描画および新規バー処理を実行する。
     *
     * テスターでは表示足の処理済みバーをスキップする。データ準備または
     * 分析に失敗した場合は処理済み時刻を更新せず、同一バーで再試行する。
     *
     * @param fromAnalysisDataReady 同じイベント内でデータ準備確認済みの場合true
     */
    void execute(bool fromAnalysisDataReady = false) {
        ulong processingStartMicroseconds = GetMicrosecondCount();
        datetime analysisStartBarTime = iTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            0
        );

        if (analysisStartBarTime == 0) {
            this.recordUpdateProcessingTime(processingStartMicroseconds, false, "準備中");

            return;
        }

        if (!this.timerMode && this.lastProcessedBarTime == analysisStartBarTime) {
            return;
        }

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.beginCurrencyStrengthRedrawBatch();

        if (this.currencyStrengthController != NULL) {
            this.currencyStrengthController.update();
        }

        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();
        long startTime = 0;

        if (isDebugOutputEnabled) {
            startTime = GetTickCount();
            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "▼▼▼▼▼　Start Time: %s (MS: %d)",
                    TimeToString(TimeCurrent(), TIME_SECONDS),
                    startTime
                )
            );
        }

        if (this.analysisController == NULL
                || this.currencyStrengthController == NULL) {
            this.endCurrencyStrengthRedrawBatch();
            this.recordUpdateProcessingTime(processingStartMicroseconds, false, "準備中");

            return;
        }

        if (!fromAnalysisDataReady && !this.isAnalysisDataReady()) {
            this.endCurrencyStrengthRedrawBatch();
            this.recordUpdateProcessingTime(processingStartMicroseconds, false, "準備中");

            return;
        }

        CurrencyStrengthExecutionInfo executionInfo =
            this.currencyStrengthController.getExecutionInfo();

        // 初回の対象M5を分析前に固定し、分析中に枠を跨いでも判定時刻をずらさない。
        if (this.config.isGapDirectionEnabled(this.marketContext.timeFrame)
                && this.lastProcessedBarTime != analysisStartBarTime
                && this.gapWaitingChartBarTime != analysisStartBarTime) {
            datetime targetTime = executionInfo.targetM5BarTime;
            if (targetTime <= 0) {
                targetTime = TimeCurrent();
            }

            if (targetTime <= 0) {
                targetTime = analysisStartBarTime;
            }

            this.gapWaitingChartBarTime = analysisStartBarTime;
            this.gapWaitingM5BarTime = (datetime)((long)targetTime - (long)targetTime % 300);
        }

        if (!this.analysisController.analyze(
                executionInfo,
                this.timerSeconds)) {
            this.logger.info(
                __FUNCTION__,
                "Elliott analysis is not ready. retry on next execution."
            );
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            this.endCurrencyStrengthRedrawBatch();
            this.recordUpdateProcessingTime(processingStartMicroseconds, false, "再試行");

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
            this.endCurrencyStrengthRedrawBatch();
            this.recordUpdateProcessingTime(processingStartMicroseconds, false, "再試行");

            return;
        }

        if (this.chartController != NULL) {
            this.chartController.drawAll(elliotAll);
        }

        if (isDebugOutputEnabled) {
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
        }

        datetime currentBarTime = analysisEndBarTime;

        if (this.lastProcessedBarTime == currentBarTime) {
            this.completeAnalysisDraw(currentBarTime);
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
            this.recordUpdateProcessingTime(processingStartMicroseconds, true, "通常更新");

            return;
        }

        if (this.config.isGapDirectionEnabled(this.marketContext.timeFrame)) {
            datetime evaluationTime = TimeCurrent();
            if (evaluationTime <= 0) {
                evaluationTime = currentBarTime;
            }

            datetime evaluationM5Time = (datetime)((long)evaluationTime - (long)evaluationTime % 300);
            if (analysisStartBarTime != currentBarTime
                    || (executionInfo.targetM5BarTime > 0
                        && executionInfo.targetM5BarTime != evaluationM5Time)) {
                this.completeAnalysisDraw(currentBarTime);
                this.recordUpdateProcessingTime(processingStartMicroseconds, false, "順位更新待ち");
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                return;
            }

            if (this.deferGapDirectionAlert(currentBarTime, evaluationM5Time, executionInfo)) {
                this.completeAnalysisDraw(currentBarTime);
                string state = "順位データ待ち";
                if (this.lastProcessedBarTime == currentBarTime) {
                    state = "順位待機期限終了";
                }

                this.recordUpdateProcessingTime(processingStartMicroseconds, false, state);
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                return;
            }
        }

        if (!this.timerMode) {
            this.analysisController.writeCsv();
        }

        this.logger.debug(__FUNCTION__, "exec EA!!!");

        if (this.alertController != NULL) {
            bool showM1Background = this.chartController != NULL && this.chartController.isM1EntryBackgroundEnabled();
            M1EntryBackgroundResult background = this.alertController.execute(elliotAll, showM1Background);
            if (showM1Background && elliotAll != NULL && elliotAll.elliotCurrent != NULL) {
                this.chartController.updateM1EntryBackground(elliotAll.elliotCurrent.currentOhlcBarTime,
                    background.isBuy, background.isPreparing, background.isEntry);
            }
        }

        this.lastProcessedBarTime = currentBarTime;
        this.completeAnalysisDraw(currentBarTime);
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        this.recordUpdateProcessingTime(processingStartMicroseconds, true, "新しい足");
    }

    /**
     * 必要な期間のデータ待ちだけを同じM5枠内で再確認し、M15の途中枠へ判定をずらさない。
     * 方向不明や不一致は判定済みとして通常のアラート経路へ渡す。
     *
     * @return データ待ち、または待機枠を過ぎて今回の足を見送った場合true。
     */
    bool deferGapDirectionAlert(const datetime fromChartBarTime, const datetime fromM5BarTime,
            const CurrencyStrengthExecutionInfo &fromExecutionInfo) {
        if (this.gapWaitingChartBarTime != fromChartBarTime) {
            this.gapWaitingChartBarTime = 0;
            this.gapWaitingM5BarTime = 0;
        }

        if (this.gapWaitingChartBarTime == fromChartBarTime
                && this.gapWaitingM5BarTime != fromM5BarTime) {
            this.lastProcessedBarTime = fromChartBarTime;
            this.gapWaitingChartBarTime = 0;
            this.gapWaitingM5BarTime = 0;

            return true;
        }

        bool isLongMediumReady = true;
        if (this.config.isLongMediumGapDirectionEnabled(this.marketContext.timeFrame)) {
            isLongMediumReady = fromExecutionInfo.longMediumGapDirection.enabled
                && fromExecutionInfo.longMediumGapDirection.targetM5BarTime == fromM5BarTime
                && !fromExecutionInfo.longMediumGapDirection.waiting;
        }

        bool isMediumShortReady = true;
        if (this.config.isMediumShortGapDirectionEnabled(this.marketContext.timeFrame)) {
            isMediumShortReady = fromExecutionInfo.mediumShortGapDirection.enabled
                && fromExecutionInfo.mediumShortGapDirection.targetM5BarTime == fromM5BarTime
                && !fromExecutionInfo.mediumShortGapDirection.waiting;
        }

        if (fromExecutionInfo.targetM5BarTime == fromM5BarTime
                && isLongMediumReady && isMediumShortReady) {
            this.gapWaitingChartBarTime = 0;
            this.gapWaitingM5BarTime = 0;

            return false;
        }

        this.gapWaitingChartBarTime = fromChartBarTime;
        this.gapWaitingM5BarTime = fromM5BarTime;

        return true;
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONTROLLER_MQH
