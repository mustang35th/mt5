/**
 * Package: MstngEa.App
 * File: EaController.mqh
 */

#ifndef MSTNGEA_APP_EACONTROLLER_MQH
#define MSTNGEA_APP_EACONTROLLER_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <MstngEa\App\EaContext.mqh>
#include <MstngEa\Domain\ExitDecision.mqh>
#include <MstngEa\Domain\PositionSnapshot.mqh>
#include <MstngEa\Domain\SignalDecision.mqh>

/**
 * EA制御
 */
class EaController {
public:
    /** コンテキスト */
    EaContext *eaContext;

    /**
     * コンストラクタ
     *
     * @param eaContextValue コンテキスト
     */
    EaController(EaContext *eaContextValue) {
        // 依存を保持
        this.eaContext = eaContextValue;
        this.pendingCurrencyStrengthElliotAll = NULL;
        this.pendingCurrencyStrengthEntryChartBarTime = 0;
        this.pendingCurrencyStrengthM5BarTime = 0;
    }

    /**
     * デストラクタ
     */
    ~EaController() {
        this.clearCurrencyStrengthEntryRetry();
    }

    /**
     * ティック処理
     */
    void onTick() {

        if (!this.validateRequiredObjects()) {
            return;
        }

        this.eaContext.positionService.refresh();

        if (this.pendingCurrencyStrengthElliotAll != NULL
                && this.eaContext.positionService.hasPosition()) {
            this.clearCurrencyStrengthEntryRetry();
        }

        // 建値移動前の初期リスク幅を保持
        this.refreshProfitRetracementState();

        this.tryBreakEven();
        this.eaContext.positionService.refresh();

        if (this.tryProfitRetracementExit()) {
            this.renderStatus();
            return;
        }

        if (!this.eaContext.newBarDetector.isNewBar()) {
            this.retryPendingCurrencyStrengthEntry();
            return;
        }

        // 新規バー処理を実行
        this.onNewBar();
    }

    /**
     * パネル表示更新
     */
    void refreshStatusPanel() {

        if (!this.validateRequiredObjects()) {
            return;
        }

        if (this.eaContext.positionService != NULL) {
            this.eaContext.positionService.refresh();
        }

        // 稼働状況を再描画
        this.renderStatus();
        ChartRedraw();
    }

    /**
     * 新規バー処理
     */
    void onNewBar() {
        this.clearCurrencyStrengthEntryRetry();

        ElliotAll *elliotAll = new ElliotAll(
            this.eaContext.marketContext.symbolName,
            this.eaContext.marketContext.timeFrame
        );

        if (elliotAll == NULL) {
            this.updateLastError("ElliotAll create failed");
            this.renderStatus();
            return;
        }

        // 分析条件を初期化
        this.initializeElliotAll(elliotAll);

        // 外部分析を実行
        elliotAll.analyze();

        // 実行時点の通貨強弱を保持
        this.loadCurrencyStrengthExecutionInfo(elliotAll);

        // 決済判定を実行
        this.tryExit(elliotAll);

        // 決済後の状態を再取得
        this.eaContext.positionService.refresh();

        // エントリー判定を実行
        this.tryEntry(elliotAll);

        // DB保存待ちの場合は同一M5内の再試行対象とする
        bool isCurrencyStrengthRetryScheduled =
            this.scheduleCurrencyStrengthEntryRetry(elliotAll);

        // 稼働状況を反映
        this.renderStatus();
        this.renderElliottInfo();

        if (!isCurrencyStrengthRetryScheduled) {
            delete elliotAll;
        }
    }

    /**
     * ステータス描画
     */
    void renderStatus() {

        if (this.eaContext == NULL) {
            return;
        }

        if (this.eaContext.statusLabelView == NULL) {
            return;
        }

        // 稼働状況を表示
        this.eaContext.statusLabelView.update(this.buildStatusText());
    }

    /**
     * エリオット情報描画
     */
    void renderElliottInfo() {
        string elliottInfoText = "-";

        if (this.eaContext == NULL) {
            return;
        }

        if (this.eaContext.elliottInfoPanelView == NULL) {
            return;
        }

        if (this.eaContext.strategyAdapter != NULL) {
            elliottInfoText = this.eaContext.strategyAdapter.getElliottInfoText();

            if (elliottInfoText == "") {
                elliottInfoText = "-";
            }
        }

        this.eaContext.elliottInfoPanelView.update(elliottInfoText);
    }

private:
    /** DB保存待ちの新規バー時Elliott分析結果。 */
    ElliotAll *pendingCurrencyStrengthElliotAll;

    /** DB保存待ちとなっているエントリー判定のチャートバー開始時刻。 */
    datetime pendingCurrencyStrengthEntryChartBarTime;

    /** DB保存待ちとなっている通貨強弱のM5バー開始時刻。 */
    datetime pendingCurrencyStrengthM5BarTime;

    /**
     * 必須依存確認
     *
     * @return true: 使用可能
     */
    bool validateRequiredObjects() {

        if (this.eaContext == NULL) {
            return false;
        }

        if (this.eaContext.newBarDetector == NULL) {
            this.updateLastError("newBarDetector is null");
            this.renderStatus();
            return false;
        }

        if (this.eaContext.positionService == NULL) {
            this.updateLastError("positionService is null");
            this.renderStatus();
            return false;
        }

        if (this.eaContext.tradeExecutor == NULL) {
            this.updateLastError("tradeExecutor is null");
            this.renderStatus();
            return false;
        }

        if (this.eaContext.strategyAdapter == NULL) {
            this.updateLastError("strategyAdapter is null");
            this.renderStatus();
            return false;
        }

        if (this.eaContext.oscillatorHandlePool == NULL) {
            this.updateLastError("oscillatorHandlePool is null");
            this.renderStatus();
            return false;
        }

        return true;
    }

    /**
     * ElliotAll初期化
     *
     * @param elliotAllValue Elliott分析オブジェクト
     */
    void initializeElliotAll(ElliotAll *elliotAllValue) {
        // タイマー実行フラグを設定
        elliotAllValue.isTimer = false;

        // オシレータハンドルプールを設定
        elliotAllValue.setOscillatorHandlePool(this.eaContext.oscillatorHandlePool);

        if (this.eaContext.eaConfig != NULL) {
            elliotAllValue.isCurrencyStrengthEntryFilterEnabled =
                this.eaContext.eaConfig.useCurrencyStrength;
        }
    }

    /**
     * 実行時点の通貨強弱情報を設定する。
     *
     * @param elliotAllValue Elliott分析オブジェクト
     */
    void loadCurrencyStrengthExecutionInfo(ElliotAll *elliotAllValue) {
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo.reset();

        if (this.eaContext.eaConfig == NULL) {
            elliotAllValue.setCurrencyStrengthExecutionInfo(executionInfo);
            return;
        }

        if (!this.eaContext.eaConfig.useCurrencyStrength) {
            elliotAllValue.setCurrencyStrengthExecutionInfo(executionInfo);
            return;
        }

        if (this.eaContext.currencyStrengthExecutionInfoProvider == NULL) {
            elliotAllValue.setCurrencyStrengthExecutionInfo(executionInfo);
            return;
        }

        datetime executionTime = elliotAllValue.tradeTimeInfo.serverTime;

        if (executionTime <= 0) {
            executionTime = TimeCurrent();
        }

        this.eaContext.currencyStrengthExecutionInfoProvider.load(
            elliotAllValue.marketContext,
            executionTime,
            executionInfo
        );
        elliotAllValue.setCurrencyStrengthExecutionInfo(executionInfo);
    }

    /**
     * 通貨強弱レコードが未保存の場合に同一M5内の再試行を予約する。
     *
     * @param elliotAllValue Elliott分析オブジェクト
     * @return 再試行を予約し、分析結果の所有権を保持した場合true
     */
    bool scheduleCurrencyStrengthEntryRetry(ElliotAll *elliotAllValue) {
        if ((bool)MQLInfoInteger(MQL_TESTER)) {
            return false;
        }

        if (this.eaContext.eaConfig == NULL
                || !this.eaContext.eaConfig.useCurrencyStrength
                || this.eaContext.currencyStrengthExecutionInfoProvider == NULL) {
            return false;
        }

        this.eaContext.positionService.refresh();

        if (this.eaContext.positionService.hasPosition()) {
            return false;
        }

        if (!elliotAllValue.isAnalysisSucceeded) {
            return false;
        }

        CurrencyStrengthExecutionInfo executionInfo =
            elliotAllValue.currencyStrengthExecutionInfo;

        if (executionInfo.isExactM5Bar()) {
            return false;
        }

        datetime chartBarTime = this.eaContext.newBarDetector.getLastBarTime();

        if (chartBarTime <= 0 || executionInfo.targetM5BarTime <= 0) {
            return false;
        }

        this.pendingCurrencyStrengthElliotAll = elliotAllValue;
        this.pendingCurrencyStrengthEntryChartBarTime = chartBarTime;
        this.pendingCurrencyStrengthM5BarTime = executionInfo.targetM5BarTime;

        return true;
    }

    /**
     * DB保存待ちの通貨強弱を再取得し、取得できた場合のみエントリーを再判定する。
     */
    void retryPendingCurrencyStrengthEntry() {
        if (this.pendingCurrencyStrengthM5BarTime <= 0) {
            return;
        }

        if ((bool)MQLInfoInteger(MQL_TESTER)
                || this.eaContext.eaConfig == NULL
                || !this.eaContext.eaConfig.useCurrencyStrength
                || this.eaContext.currencyStrengthExecutionInfoProvider == NULL) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        this.eaContext.positionService.refresh();

        if (this.eaContext.positionService.hasPosition()) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        if (this.eaContext.newBarDetector.getLastBarTime()
                != this.pendingCurrencyStrengthEntryChartBarTime) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        datetime currentM5BarTime = this.getM5BarTime(TimeCurrent());

        if (currentM5BarTime <= 0) {
            return;
        }

        if (currentM5BarTime != this.pendingCurrencyStrengthM5BarTime) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo.reset();
        this.eaContext.currencyStrengthExecutionInfoProvider.load(
            this.eaContext.marketContext,
            this.pendingCurrencyStrengthM5BarTime,
            executionInfo
        );

        if (!executionInfo.isExactM5Bar()) {
            return;
        }

        if (this.pendingCurrencyStrengthElliotAll == NULL) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        ElliotAll *elliotAll = this.pendingCurrencyStrengthElliotAll;
        elliotAll.setCurrencyStrengthExecutionInfo(executionInfo);

        if (this.getM5BarTime(TimeCurrent())
                != this.pendingCurrencyStrengthM5BarTime) {
            this.clearCurrencyStrengthEntryRetry();
            return;
        }

        this.pendingCurrencyStrengthElliotAll = NULL;
        this.pendingCurrencyStrengthEntryChartBarTime = 0;
        this.pendingCurrencyStrengthM5BarTime = 0;
        this.tryEntry(elliotAll);
        this.renderStatus();
        this.renderElliottInfo();

        delete elliotAll;
    }

    /**
     * 通貨強弱レコード待ちのエントリー再試行を解除する。
     */
    void clearCurrencyStrengthEntryRetry() {
        if (this.pendingCurrencyStrengthElliotAll != NULL) {
            delete this.pendingCurrencyStrengthElliotAll;
            this.pendingCurrencyStrengthElliotAll = NULL;
        }

        this.pendingCurrencyStrengthEntryChartBarTime = 0;
        this.pendingCurrencyStrengthM5BarTime = 0;
    }

    /**
     * 指定時刻をM5バー開始時刻へ切り下げる。
     *
     * @param fromTime 対象時刻
     * @return M5バー開始時刻。変換できない場合0
     */
    datetime getM5BarTime(const datetime fromTime) {
        int m5Seconds = PeriodSeconds(PERIOD_M5);

        if (fromTime <= 0 || m5Seconds <= 0) {
            return 0;
        }

        long timeSeconds = (long)fromTime;

        return (datetime)(timeSeconds - (timeSeconds % m5Seconds));
    }


    /**
     * 建値移動判定
     */
    void tryBreakEven() {

        if (this.eaContext.eaConfig == NULL) {
            return;
        }

        if (!this.eaContext.eaConfig.useBreakEven) {
            return;
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return;
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();

        if (positionSnapshot.stopLoss <= 0.0) {
            return;
        }

        double riskDistance = this.calculateBreakEvenRiskDistance(positionSnapshot);

        if (riskDistance <= 0.0) {
            return;
        }

        double triggerPrice = this.calculateBreakEvenTriggerPrice(positionSnapshot, riskDistance);
        double currentPrice = this.getCurrentBreakEvenJudgePrice(positionSnapshot);

        if (currentPrice <= 0.0) {
            return;
        }

        if (!this.isBreakEvenTriggered(positionSnapshot, currentPrice, triggerPrice)) {
            return;
        }

        double breakEvenPrice = this.calculateBreakEvenPrice(positionSnapshot);

        if (!this.shouldMoveBreakEven(positionSnapshot, breakEvenPrice)) {
            return;
        }

        bool isModified = this.eaContext.tradeExecutor.modifyPositionStopLoss(
            this.eaContext.strategyAdapter.getStrategyName(),
            breakEvenPrice,
            "BREAK_EVEN"
        );

        if (!isModified) {
            string errorMessage = this.eaContext.tradeExecutor.getLastErrorMessage();

            if (errorMessage == "") {
                errorMessage = "Break even modify failed";
            }

            this.updateLastError(errorMessage);
            return;
        }

        this.eaContext.lastAction = "BREAK EVEN";
        this.eaContext.lastError = "";

        if (this.eaContext.operationLogger != NULL) {
            this.eaContext.operationLogger.info(
                "EaController",
                "Break even stop loss modified"
            );
        }
    }

    /**
     * 建値移動リスク幅計算
     *
     * @param positionSnapshotValue ポジション状態
     * @return リスク幅
     */
    double calculateBreakEvenRiskDistance(PositionSnapshot &positionSnapshotValue) {

        if (positionSnapshotValue.isBuy) {
            return positionSnapshotValue.openPrice - positionSnapshotValue.stopLoss;
        }

        return positionSnapshotValue.stopLoss - positionSnapshotValue.openPrice;
    }

    /**
     * 建値移動発動価格計算
     *
     * @param positionSnapshotValue ポジション状態
     * @param riskDistanceValue リスク幅
     * @return 発動価格
     */
    double calculateBreakEvenTriggerPrice(
        PositionSnapshot &positionSnapshotValue,
        double riskDistanceValue
    ) {
        double triggerDistance = riskDistanceValue * this.eaContext.eaConfig.breakEvenTriggerR;

        if (positionSnapshotValue.isBuy) {
            return positionSnapshotValue.openPrice + triggerDistance;
        }

        return positionSnapshotValue.openPrice - triggerDistance;
    }

    /**
     * 建値移動価格計算
     *
     * @param positionSnapshotValue ポジション状態
     * @return 建値移動価格
     */
    double calculateBreakEvenPrice(PositionSnapshot &positionSnapshotValue) {
        double breakEvenAdjustment = this.eaContext.eaConfig.breakEvenPlusPips * this.getPipSize();

        if (positionSnapshotValue.isBuy) {
            return positionSnapshotValue.openPrice + breakEvenAdjustment;
        }

        return positionSnapshotValue.openPrice - breakEvenAdjustment;
    }

    /**
     * 建値移動発火判定
     *
     * @param positionSnapshotValue ポジション状態
     * @param currentPriceValue 現在価格
     * @param triggerPriceValue 発動価格
     * @return true: 発火
     */
    bool isBreakEvenTriggered(
        PositionSnapshot &positionSnapshotValue,
        double currentPriceValue,
        double triggerPriceValue
    ) {

        if (positionSnapshotValue.isBuy) {
            return currentPriceValue >= triggerPriceValue;
        }

        return currentPriceValue <= triggerPriceValue;
    }

    /**
     * 建値移動要否判定
     *
     * @param positionSnapshotValue ポジション状態
     * @param breakEvenPriceValue 建値移動価格
     * @return true: 移動必要
     */
    bool shouldMoveBreakEven(
        PositionSnapshot &positionSnapshotValue,
        double breakEvenPriceValue
    ) {

        if (positionSnapshotValue.isBuy) {
            return positionSnapshotValue.stopLoss < breakEvenPriceValue;
        }

        return positionSnapshotValue.stopLoss > breakEvenPriceValue;
    }

    /**
     * 建値移動判定用現在価格取得
     *
     * @param positionSnapshotValue ポジション状態
     * @return 現在価格
     */
    double getCurrentBreakEvenJudgePrice(PositionSnapshot &positionSnapshotValue) {
        MqlTick mqlTick;
        ZeroMemory(mqlTick);

        if (!SymbolInfoTick(this.eaContext.marketContext.symbolName, mqlTick)) {
            return 0.0;
        }

        if (positionSnapshotValue.isBuy) {
            return mqlTick.bid;
        }

        return mqlTick.ask;
    }

    /**
     * pips値取得
     *
     * @return pips値
     */
    double getPipSize() {
        int digits = (int)SymbolInfoInteger(this.eaContext.marketContext.symbolName, SYMBOL_DIGITS);
        double pointValue = SymbolInfoDouble(this.eaContext.marketContext.symbolName, SYMBOL_POINT);

        if (digits == 3 || digits == 5) {
            return pointValue * 10.0;
        }

        return pointValue;
    }

    /**
     * 利益戻し決済状態を現在ポジションで更新する。
     *
     * 建値移動で初期ストップロスが失われる前に、初期リスク幅を保持する。
     */
    void refreshProfitRetracementState() {
        if (this.eaContext.eaConfig == NULL) {
            return;
        }

        if (!this.eaContext.eaConfig.useProfitRetracementExit) {
            return;
        }

        if (this.eaContext.profitRetracementState == NULL) {
            return;
        }

        if (!this.eaContext.positionService.hasPosition()) {
            this.eaContext.profitRetracementState.reset();
            return;
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();
        this.updateProfitRetracementState(positionSnapshot);
    }

    /**
     * 利益戻し決済判定
     *
     * @return true: 決済実行
     */
    bool tryProfitRetracementExit() {

        if (this.eaContext.eaConfig == NULL) {
            return false;
        }

        if (!this.eaContext.eaConfig.useProfitRetracementExit) {
            return false;
        }

        if (this.eaContext.profitRetracementState == NULL) {
            return false;
        }

        if (!this.eaContext.positionService.hasPosition()) {
            this.eaContext.profitRetracementState.reset();
            return false;
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();
        this.updateProfitRetracementState(positionSnapshot);

        if (!this.eaContext.profitRetracementState.activated) {
            return false;
        }

        if (!this.isProfitRetracementTriggered(positionSnapshot)) {
            return false;
        }

        bool isClosed = this.eaContext.tradeExecutor.closePosition(
            this.eaContext.strategyAdapter.getStrategyName(),
            "PROFIT_RETRACEMENT"
        );

        if (!isClosed) {
            string errorMessage = this.eaContext.tradeExecutor.getLastErrorMessage();

            if (errorMessage == "") {
                errorMessage = "Profit retracement close failed";
            }

            this.updateLastError(errorMessage);
            return false;
        }

        this.eaContext.profitRetracementState.reset();
        this.eaContext.lastAction = "PROFIT RETRACEMENT EXIT";
        this.eaContext.lastError = "";

        if (this.eaContext.operationLogger != NULL) {
            this.eaContext.operationLogger.info(
                "EaController",
                "Profit retracement exit executed"
            );
        }

        return true;
    }

    /**
     * 利益戻し決済状態更新
     *
     * @param positionSnapshotValue ポジション状態
     */
    void updateProfitRetracementState(PositionSnapshot &positionSnapshotValue) {

        if (this.eaContext.profitRetracementState.positionTicket != positionSnapshotValue.ticket) {
            this.eaContext.profitRetracementState.reset();
            this.eaContext.profitRetracementState.positionTicket = positionSnapshotValue.ticket;
            this.eaContext.profitRetracementState.maxFloatingProfit = positionSnapshotValue.floatingProfit;

            if (positionSnapshotValue.stopLoss > 0.0) {
                this.eaContext.profitRetracementState.initialRiskDistance =
                    this.calculateBreakEvenRiskDistance(positionSnapshotValue);
            }
        }

        if (positionSnapshotValue.floatingProfit
            > this.eaContext.profitRetracementState.maxFloatingProfit) {
            this.eaContext.profitRetracementState.maxFloatingProfit = positionSnapshotValue.floatingProfit;
        }

        if (this.eaContext.profitRetracementState.activated) {
            return;
        }

        if (!this.isProfitRetracementStartTriggered(positionSnapshotValue)) {
            return;
        }

        this.eaContext.profitRetracementState.activated = true;
    }

    /**
     * 初期リスク幅に対して利益戻し決済の開始R倍率へ到達したか判定する。
     *
     * @param fromPositionSnapshot ポジション状態。
     * @return 開始価格へ到達した場合true。
     */
    bool isProfitRetracementStartTriggered(PositionSnapshot &fromPositionSnapshot) {
        if (this.eaContext.eaConfig.profitRetracementStartR <= 0.0) {
            return false;
        }

        double initialRiskDistance = this.eaContext.profitRetracementState.initialRiskDistance;

        if (initialRiskDistance <= 0.0) {
            return false;
        }

        double currentPrice = this.getCurrentBreakEvenJudgePrice(fromPositionSnapshot);

        if (currentPrice <= 0.0) {
            return false;
        }

        double triggerDistance = initialRiskDistance
            * this.eaContext.eaConfig.profitRetracementStartR;
        double triggerPrice = fromPositionSnapshot.openPrice;

        if (fromPositionSnapshot.isBuy) {
            triggerPrice += triggerDistance;
            return currentPrice >= triggerPrice;
        }

        triggerPrice -= triggerDistance;
        return currentPrice <= triggerPrice;
    }

    /**
     * 利益戻し決済発火判定
     *
     * @param positionSnapshotValue ポジション状態
     * @return true: 発火
     */
    bool isProfitRetracementTriggered(PositionSnapshot &positionSnapshotValue) {

        if (this.eaContext.eaConfig.profitRetracementRate <= 0.0) {
            return false;
        }

        double maxFloatingProfit = this.eaContext.profitRetracementState.maxFloatingProfit;
        double currentFloatingProfit = positionSnapshotValue.floatingProfit;
        double retracementAmount = maxFloatingProfit - currentFloatingProfit;
        double triggerAmount = maxFloatingProfit * this.eaContext.eaConfig.profitRetracementRate;

        if (retracementAmount < triggerAmount) {
            return false;
        }

        return true;
    }

    /**
     * 決済判定
     *
     * @param elliotAllValue 分析結果
     */
    void tryExit(ElliotAll *elliotAllValue) {
        // ポジション状態を更新
        this.eaContext.positionService.refresh();

        if (!this.eaContext.positionService.hasPosition()) {
            return;
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();
        ExitDecision exitDecision = this.eaContext.strategyAdapter.analyzeExit(
            elliotAllValue,
            positionSnapshot.isBuy
        );

        if (!exitDecision.isExit) {
            return;
        }

        bool isClosed = this.eaContext.tradeExecutor.closePosition(
            this.eaContext.strategyAdapter.getStrategyName(),
            exitDecision.reason
        );

        if (!isClosed) {
            string errorMessage = this.eaContext.tradeExecutor.getLastErrorMessage();

            if (errorMessage == "") {
                errorMessage = "Close position failed";
            }

            this.updateLastError(errorMessage);
            return;
        }

        // 最終状態を更新
        this.eaContext.lastAction = "CLOSE";
        this.eaContext.lastError = "";

        if (this.eaContext.operationLogger != NULL) {
            this.eaContext.operationLogger.info("EaController", "Position closed");
        }
    }

    /**
     * エントリー判定
     *
     * @param elliotAllValue 分析結果
     */
    void tryEntry(ElliotAll *elliotAllValue) {
        // ポジション状態を更新
        this.eaContext.positionService.refresh();

        if (this.eaContext.positionService.hasPosition()) {
            return;
        }

        SignalDecision signalDecision = this.eaContext.strategyAdapter.analyzeEntry(elliotAllValue);

        if (!signalDecision.isEntry) {
            return;
        }

        // シグナル表示を描画
        this.drawSignalAlert(signalDecision);

        bool isOpened = false;

        if (signalDecision.isBuy) {
            isOpened = this.eaContext.tradeExecutor.openBuy(
                this.eaContext.strategyAdapter.getStrategyName(),
                signalDecision.reason,
                signalDecision.stopLoss,
                signalDecision.csvText
            );
        } else {
            isOpened = this.eaContext.tradeExecutor.openSell(
                this.eaContext.strategyAdapter.getStrategyName(),
                signalDecision.reason,
                signalDecision.stopLoss,
                signalDecision.csvText
            );
        }

        if (!isOpened) {
            string errorMessage = this.eaContext.tradeExecutor.getLastErrorMessage();

            if (errorMessage == "") {
                errorMessage = "Open position failed";
            }

            this.updateLastError(errorMessage);
            return;
        }

        // 最終状態を更新
        this.eaContext.lastAction = "ENTRY";
        this.eaContext.lastError = "";

        if (this.eaContext.operationLogger != NULL) {
            this.eaContext.operationLogger.info("EaController", "Position opened");
        }
    }

    /**
     * シグナル表示描画
     *
     * @param signalDecisionValue シグナル判定結果
     */
    void drawSignalAlert(SignalDecision &signalDecisionValue) {

        if (this.eaContext == NULL) {
            return;
        }

        if (this.eaContext.signalAlertTextView == NULL) {
            return;
        }

        if (signalDecisionValue.alertText == "") {
            return;
        }

        datetime signalTime = iTime(
            this.eaContext.marketContext.symbolName,
            this.eaContext.marketContext.timeFrame,
            0
        );
        double openPrice = iOpen(
            this.eaContext.marketContext.symbolName,
            this.eaContext.marketContext.timeFrame,
            0
        );

        if (signalTime <= 0) {
            return;
        }

        if (openPrice <= 0.0) {
            return;
        }

        this.eaContext.signalAlertTextView.draw(
            signalTime,
            openPrice,
            signalDecisionValue.alertText,
            signalDecisionValue.isBuy
        );
    }
    /**
     * ステータス文字列生成
     *
     * @return ステータス文字列
     */
    string buildStatusText() {
        // 表示文字列を組み立て
        string statusText = "State      : RUNNING\n";
        statusText += "Symbol     : " + this.eaContext.marketContext.symbolName + "\n";
        statusText += "Timeframe  : " + this.getTimeFrameText() + "\n";
        statusText += "Strategy   : " + this.getStrategyNameText() + "\n";
        statusText += "Lot        : " + DoubleToString(this.eaContext.eaConfig.lotSize, 2) + "\n";
        statusText += "Spread     : " + this.getSpreadText() + "\n";
        statusText += "Magic      : " + (string)this.eaContext.magicNumber + "\n";
        statusText += "Position   : " + this.getPositionText() + "\n";
        statusText += "StopLoss   : " + this.getStopLossText() + "\n";
        statusText += "Profit     : " + this.getFloatingProfitText() + "\n";
        statusText += "JstTime    : " + this.getJstTimeText() + "\n";
        statusText += "ServerTime : " + this.getServerTimeText() + "\n";
        statusText += "BreakEven  : " + this.getBreakEvenSettingText() + "\n";
        statusText += "TrailExit  : " + this.getTrailExitSettingText() + "\n";
        statusText += "Action     : " + this.getLastActionText() + "\n";
        statusText += "Error      : " + this.getLastErrorText();

        return statusText;
    }

    /**
     * 時間足文字列取得
     *
     * @return 時間足文字列
     */
    string getTimeFrameText() {

        if (this.eaContext.marketContext.timeFrame == PERIOD_M1) {
            return "M1";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_M5) {
            return "M5";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_M15) {
            return "M15";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_M30) {
            return "M30";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_H1) {
            return "H1";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_H4) {
            return "H4";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_D1) {
            return "D1";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_W1) {
            return "W1";
        }

        if (this.eaContext.marketContext.timeFrame == PERIOD_MN1) {
            return "MN1";
        }

        return IntegerToString((int)this.eaContext.marketContext.timeFrame);
    }

    /**
     * 戦略名文字列取得
     *
     * @return 戦略名
     */
    string getStrategyNameText() {

        if (this.eaContext.strategyAdapter == NULL) {
            return "-";
        }

        return this.eaContext.strategyAdapter.getStrategyName();
    }

    /**
     * ポジション文字列取得
     *
     * @return ポジション文字列
     */
    string getPositionText() {

        if (this.eaContext.positionService == NULL) {
            return "-";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "NONE";
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();
        string positionText = "SELL";

        if (positionSnapshot.isBuy) {
            positionText = "BUY";
        }

        positionText += " ";
        positionText += DoubleToString(positionSnapshot.volume, 2);
        positionText += " @ ";
        positionText += DoubleToString(positionSnapshot.openPrice, _Digits);

        return positionText;
    }

    /**
     * ストップロス文字列取得
     *
     * @return ストップロス
     */
    string getStopLossText() {

        if (this.eaContext.positionService == NULL) {
            return "-";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "NONE";
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();

        if (positionSnapshot.stopLoss <= 0.0) {
            return "NONE";
        }

        return DoubleToString(positionSnapshot.stopLoss, _Digits);
    }

    /**
     * 評価損益文字列取得
     *
     * @return 評価損益
     */
    string getFloatingProfitText() {

        if (this.eaContext.positionService == NULL) {
            return "-";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "NONE";
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();

        return DoubleToString(positionSnapshot.floatingProfit, 2);
    }


    /**
     * スプレッド文字列取得
     *
     * @return スプレッド
     */
    string getSpreadText() {
        MqlTick currentTick;
        double pointValue = SymbolInfoDouble(this.eaContext.marketContext.symbolName, SYMBOL_POINT);

        if (pointValue <= 0.0) {
            return "-";
        }

        double spreadPoints = 0.0;

        if (SymbolInfoTick(this.eaContext.marketContext.symbolName, currentTick)) {
            spreadPoints = (currentTick.ask - currentTick.bid) / pointValue;
        } else {
            spreadPoints = (double)SymbolInfoInteger(this.eaContext.marketContext.symbolName, SYMBOL_SPREAD);
        }

        if (spreadPoints < 0.0) {
            spreadPoints = 0.0;
        }

        double pipSize = this.getPipSize();
        double spreadPips = 0.0;

        if (pipSize > 0.0) {
            spreadPips = (spreadPoints * pointValue) / pipSize;
        }

        return DoubleToString(spreadPips, 1) + " pips / " + DoubleToString(spreadPoints, 1) + " pt";
    }

    /**
     * 日本時刻文字列取得
     *
     * @return 日本時刻
     */
    string getJstTimeText() {
        datetime serverTime = TimeCurrent();
        datetime jstTime = this.toJstTime(serverTime);

        return this.formatDateTime(jstTime);
    }

    /**
     * サーバ時刻文字列取得
     *
     * @return サーバ時刻
     */
    string getServerTimeText() {
        datetime serverTime = TimeCurrent();

        return this.formatDateTime(serverTime);
    }

    /**
     * 建値移動設定文字列取得
     *
     * @return 建値移動設定文字列
     */
    string getBreakEvenSettingText() {

        if (this.eaContext.eaConfig == NULL) {
            return "-";
        }

        string enabledText = "OFF";

        if (this.eaContext.eaConfig.useBreakEven) {
            enabledText = "ON";
        }

        string stateText = this.getBreakEvenStateText();
        string text = enabledText;
        text += " / ";
        text += DoubleToString(this.eaContext.eaConfig.breakEvenTriggerR, 1);
        text += "R / +";
        text += DoubleToString(this.eaContext.eaConfig.breakEvenPlusPips, 1);
        text += "p / ";
        text += stateText;

        return text;
    }

    /**
     * 利益戻し決済設定文字列取得
     *
     * @return 利益戻し決済設定文字列
     */
    string getTrailExitSettingText() {

        if (this.eaContext.eaConfig == NULL) {
            return "-";
        }

        string enabledText = "OFF";

        if (this.eaContext.eaConfig.useProfitRetracementExit) {
            enabledText = "ON";
        }

        string stateText = this.getTrailExitStateText();
        string text = enabledText;
        text += " / ";
        text += DoubleToString(this.eaContext.eaConfig.profitRetracementStartR, 1);
        text += "R / ";
        text += DoubleToString(this.eaContext.eaConfig.profitRetracementRate * 100.0, 0);
        text += "% / ";
        text += stateText;
        text += " / Max ";
        text += this.getTrailExitMaxProfitText();
        text += " / Now ";
        text += this.getTrailExitCurrentProfitText();

        return text;
    }

    /**
     * 建値移動状態文字列取得
     *
     * @return 建値移動状態
     */
    string getBreakEvenStateText() {

        if (this.eaContext.eaConfig == NULL) {
            return "-";
        }

        if (!this.eaContext.eaConfig.useBreakEven) {
            return "OFF";
        }

        if (this.eaContext.positionService == NULL) {
            return "READY";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "READY";
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();
        double breakEvenPrice = this.calculateBreakEvenPrice(positionSnapshot);

        if (this.isBreakEvenMoved(positionSnapshot, breakEvenPrice)) {
            return "DONE";
        }

        return "READY";
    }

    /**
     * 利益戻し決済状態文字列取得
     *
     * @return 利益戻し決済状態
     */
    /**
     * 利益戻し決済最大含み益文字列取得
     *
     * @return 最大含み益文字列
     */
    string getTrailExitMaxProfitText() {

        if (this.eaContext == NULL) {
            return "-";
        }

        if (this.eaContext.profitRetracementState == NULL) {
            return "-";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "-";
        }

        return DoubleToString(this.eaContext.profitRetracementState.maxFloatingProfit, 2);
    }

    /**
     * 利益戻し決済現在評価損益文字列取得
     *
     * @return 現在評価損益文字列
     */
    string getTrailExitCurrentProfitText() {

        if (this.eaContext == NULL) {
            return "-";
        }

        if (this.eaContext.positionService == NULL) {
            return "-";
        }

        if (!this.eaContext.positionService.hasPosition()) {
            return "-";
        }

        PositionSnapshot positionSnapshot = this.eaContext.positionService.getSnapshot();

        return DoubleToString(positionSnapshot.floatingProfit, 2);
    }

    string getTrailExitStateText() {

        if (this.eaContext.eaConfig == NULL) {
            return "-";
        }

        if (!this.eaContext.eaConfig.useProfitRetracementExit) {
            return "OFF";
        }

        if (this.eaContext.profitRetracementState == NULL) {
            return "READY";
        }

        if (this.eaContext.profitRetracementState.activated) {
            return "ACTIVE";
        }

        return "READY";
    }

    /**
     * 建値移動済み判定
     *
     * @param positionSnapshotValue ポジション状態
     * @param breakEvenPriceValue 建値移動価格
     * @return true: 建値移動済み
     */
    bool isBreakEvenMoved(
        PositionSnapshot &positionSnapshotValue,
        double breakEvenPriceValue
    ) {

        if (positionSnapshotValue.stopLoss <= 0.0) {
            return false;
        }

        double tolerance = SymbolInfoDouble(this.eaContext.marketContext.symbolName, SYMBOL_POINT) * 2.0;

        if (positionSnapshotValue.isBuy) {
            return positionSnapshotValue.stopLoss >= (breakEvenPriceValue - tolerance);
        }

        return positionSnapshotValue.stopLoss <= (breakEvenPriceValue + tolerance);
    }

    /**
     * 日本時刻変換
     *
     * @param serverTimeValue サーバ時刻
     * @return 日本時刻
     */
    datetime toJstTime(datetime serverTimeValue) {
        int serverUtcOffsetHours = this.getOandaServerUtcOffsetHours(serverTimeValue);
        int differenceHours = 9 - serverUtcOffsetHours;

        return serverTimeValue + (differenceHours * 60 * 60);
    }

    /**
     * OANDAサーバUTCオフセット取得
     *
     * @param serverTimeValue サーバ時刻
     * @return UTCオフセット時間
     */
    int getOandaServerUtcOffsetHours(datetime serverTimeValue) {

        if (this.isOandaDstByServerTime(serverTimeValue)) {
            return 3;
        }

        return 2;
    }

    /**
     * OANDA夏時間判定
     *
     * @param serverTimeValue サーバ時刻
     * @return true: 夏時間
     */
    bool isOandaDstByServerTime(datetime serverTimeValue) {
        MqlDateTime serverDateTime;
        TimeToStruct(serverTimeValue, serverDateTime);

        int yearValue = serverDateTime.year;
        datetime dstStart = this.getNthWeekdayOfMonth(yearValue, 3, 0, 2);
        datetime dstEnd = this.getNthWeekdayOfMonth(yearValue, 11, 0, 1);

        return serverTimeValue >= dstStart && serverTimeValue < dstEnd;
    }

    /**
     * 第n曜日取得
     *
     * @param yearValue 年
     * @param monthValue 月
     * @param dayOfWeekValue 曜日 0=日曜
     * @param nthValue 第n
     * @return 対象日時
     */
    datetime getNthWeekdayOfMonth(
        int yearValue,
        int monthValue,
        int dayOfWeekValue,
        int nthValue
    ) {
        MqlDateTime dateTime;
        dateTime.year = yearValue;
        dateTime.mon = monthValue;
        dateTime.day = 1;
        dateTime.hour = 0;
        dateTime.min = 0;
        dateTime.sec = 0;
        datetime firstDay = StructToTime(dateTime);
        MqlDateTime firstDayStruct;
        TimeToStruct(firstDay, firstDayStruct);
        int firstWeekDay = firstDayStruct.day_of_week;
        int offsetDays = dayOfWeekValue - firstWeekDay;

        if (offsetDays < 0) {
            offsetDays += 7;
        }

        int dayValue = 1 + offsetDays + ((nthValue - 1) * 7);
        dateTime.day = dayValue;

        return StructToTime(dateTime);
    }

    /**
     * 日時文字列整形
     *
     * @param dateTimeValue 日時
     * @return 整形日時
     */
    string formatDateTime(datetime dateTimeValue) {
        MqlDateTime dateTime;
        TimeToStruct(dateTimeValue, dateTime);
        string text = IntegerToString(dateTime.year);
        text += "." + this.padLeft(dateTime.mon);
        text += "." + this.padLeft(dateTime.day);
        text += " " + this.padLeft(dateTime.hour);
        text += ":" + this.padLeft(dateTime.min);
        text += ":" + this.padLeft(dateTime.sec);

        return text;
    }

    /**
     * 2桁ゼロ埋め
     *
     * @param numberValue 数値
     * @return 2桁文字列
     */
    string padLeft(int numberValue) {

        if (numberValue < 10) {
            return "0" + IntegerToString(numberValue);
        }

        return IntegerToString(numberValue);
    }


    /**
     * 最終アクション文字列取得
     *
     * @return 最終アクション
     */
    string getLastActionText() {

        if (this.eaContext.lastAction == "") {
            return "-";
        }

        return this.eaContext.lastAction;
    }

    /**
     * 最終エラー文字列取得
     *
     * @return 最終エラー
     */
    string getLastErrorText() {

        if (this.eaContext.lastError == "") {
            return "-";
        }

        return this.eaContext.lastError;
    }

    /**
     * 最終エラー更新
     *
     * @param errorMessageValue エラーメッセージ
     */
    void updateLastError(string errorMessageValue) {
        // 最終エラーを更新
        this.eaContext.lastError = errorMessageValue;

        if (this.eaContext.operationLogger == NULL) {
            return;
        }

        // エラーログを出力
        this.eaContext.operationLogger.error("EaController", errorMessageValue);
    }
};

#endif
