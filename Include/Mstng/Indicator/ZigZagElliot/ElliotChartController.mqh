//+------------------------------------------------------------------+
//|                                        ElliotChartController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_CHART_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_CHART_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Common\ProcessingTimeStats.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\Draw.mqh>
#include <Mstng\Draw\DrawElliotVerticalFit.mqh>
#include <Mstng\Draw\DrawProcessingTime.mqh>
#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Draw\DrawZigZagElliotInfoLayout.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Indicator\Ema200Indicator.mqh>
#include <Mstng\Indicator\GmmaIndicator.mqh>
#include <Mstng\Indicator\JapanTimeAxisView.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * ZigZagElliotのチャート描画、補助表示、操作ボタンおよび上下FITを管理するクラス。
 */
class ElliotChartController {
public:
    /**
     * 表示状態と保持ポインタを初期化する。
     */
    ElliotChartController() {
        this.gmmaIndicator = NULL;
        this.ema200Indicator = NULL;
        this.japanTimeAxisView = NULL;
        this.timeAxisFullUpdatePending = false;
        this.lastTimeAxisFullUpdateTick = 0;
        this.drawElliotVerticalFit = NULL;
        this.elliotHigherTimeFrameDisplayCount = 2;
        this.elliotInfoVisible = true;
        this.elliotInfoSimple = true;
        this.initialVerticalFitPending = true;
        this.infoRightDistance = DrawZigZagElliotInfoLayout::getMinimumRightDistance();
        this.lastHorizontalViewKey = "";
    }

    /**
     * 表示リソースを解放する。
     */
    ~ElliotChartController() {
        this.destroy();
    }

    /**
     * 補助表示、上下FITおよび操作ボタンを作成する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromOscillatorHandlePool オシレーターハンドルプール
     * @param fromElliotHigherTimeFrameDisplayCount 波動ラベルを表示する上位時間足数
     * @param fromInfoRightDistance 右側情報欄の右余白。
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        OscillatorHandlePool *fromOscillatorHandlePool,
        int fromElliotHigherTimeFrameDisplayCount = 2,
        int fromInfoRightDistance = 10
    ) {
        this.destroy();

        if (fromOscillatorHandlePool == NULL) {
            return false;
        }

        this.marketContext = fromMarketContext;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.elliotHigherTimeFrameDisplayCount =
            fromElliotHigherTimeFrameDisplayCount;
        this.elliotInfoVisible = true;
        this.elliotInfoSimple = true;
        this.initialVerticalFitPending = true;
        this.infoRightDistance = fromInfoRightDistance;
        if (this.infoRightDistance < DrawZigZagElliotInfoLayout::getMinimumRightDistance()) {
            this.infoRightDistance = DrawZigZagElliotInfoLayout::getMinimumRightDistance();
        }

        this.draw.setInfoRightDistance(this.infoRightDistance);
        this.lastHorizontalViewKey = "";

        this.gmmaIndicator = new GmmaIndicator(this.marketContext);

        if (this.gmmaIndicator == NULL) {
            return false;
        }

        this.gmmaIndicator.init(fromOscillatorHandlePool);
        this.ema200Indicator = new Ema200Indicator(this.marketContext);

        if (this.ema200Indicator == NULL) {
            return false;
        }

        this.ema200Indicator.init(fromOscillatorHandlePool);
        this.ema200Indicator.setReservedRightWidth(
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance) + 12
        );
        this.japanTimeAxisView =
            new JapanTimeAxisView(this.marketContext);

        if (this.japanTimeAxisView == NULL) {
            return false;
        }

        this.japanTimeAxisView.setRemainingXDistance(
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance)
        );
        this.japanTimeAxisView.create();
        this.timeAxisFullUpdatePending = false;
        this.lastTimeAxisFullUpdateTick = GetTickCount64();
        this.drawElliotVerticalFit = new DrawElliotVerticalFit(
            this.isVerticalFitLabelClampMode(),
            this.elliotHigherTimeFrameDisplayCount
        );

        if (this.drawElliotVerticalFit == NULL) {
            return false;
        }

        this.createElliotInfoButton();
        this.createElliotInfoModeButton();
        this.createElliotVerticalFitButton();

        DrawProperties displayProperties;
        this.processingTimeDraw.initialize(
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance),
            displayProperties.elliotFontFace
        );

        return true;
    }

    /**
     * OnCalculateで更新する補助表示を処理する。
     * 通常チャートの履歴再計算では、次のタイマーで日本時間軸を強制更新する。
     * EMA200は履歴再計算時に全バッファを初期化して再取得する。
     *
     * @param fromTimerMode タイマー実行の場合true
     * @param fromPrevCalculated OnCalculateの前回計算済みバー数
     * @param fromRatesTotal OnCalculateの全バー数。0の場合はGMMA側で取得する
     * @param fromCurrentBarTime OnCalculateの最新足時刻。0の場合はGMMA側で取得する
     */
    void updateOnCalculate(bool fromTimerMode, int fromPrevCalculated = 0,
            int fromRatesTotal = 0, datetime fromCurrentBarTime = 0) {
        if (fromTimerMode && fromPrevCalculated == 0) {
            this.timeAxisFullUpdatePending = true;
        }

        if (this.gmmaIndicator != NULL) {
            ulong startMicroseconds = GetMicrosecondCount();
            bool isSucceeded = this.gmmaIndicator.update(
                fromPrevCalculated, fromRatesTotal, fromCurrentBarTime);
            ulong elapsedMicroseconds = GetMicrosecondCount() - startMicroseconds;

            if (this.gmmaIndicator.wasUpdatePerformed()) {
                string updateMode = this.gmmaIndicator.getLastUpdateMode();
                if (!isSucceeded && updateMode != "準備中") {
                    updateMode = "再試行";
                }

                this.recordProcessingTime(2, elapsedMicroseconds, isSucceeded, updateMode);
            }
        }

        this.updateEma200Indicator(fromTimerMode, fromPrevCalculated == 0);
    }

    /**
     * OnTimerで更新する補助表示を処理する。
     * 同じ画面の日本時間軸は再利用し、残り時間は毎回更新する。
     * 上位足だけの履歴更新も拾うため、60秒ごとに時間軸を強制確認する。
     *
     * @param fromTimerMode タイマー実行の場合true
     */
    void updateOnTimer(bool fromTimerMode) {
        if (this.japanTimeAxisView != NULL) {
            const ulong fullUpdateIntervalMilliseconds = 60000;
            ulong currentTick = GetTickCount64();
            bool forceTimeAxisUpdate = this.timeAxisFullUpdatePending
                || currentTick - this.lastTimeAxisFullUpdateTick >= fullUpdateIntervalMilliseconds;

            ulong startMicroseconds = GetMicrosecondCount();
            this.japanTimeAxisView.updateTimeAxis(forceTimeAxisUpdate);
            this.japanTimeAxisView.updateRemainingTime();
            ulong elapsedMicroseconds = GetMicrosecondCount() - startMicroseconds;
            bool isSucceeded = this.japanTimeAxisView.isTimeAxisUpdateSucceeded()
                && this.japanTimeAxisView.isRemainingTimeUpdateSucceeded();
            string updateMode = this.japanTimeAxisView.getLastUpdateMode();
            if (!isSucceeded) {
                updateMode = "再試行";
            }

            this.recordProcessingTime(3, elapsedMicroseconds, isSucceeded, updateMode);

            if (forceTimeAxisUpdate) {
                // 取得・描画失敗後の再試行待ちはView側が保持する。
                this.timeAxisFullUpdatePending = false;
                this.lastTimeAxisFullUpdateTick = currentTick;
            }
        }

        this.updateEma200Indicator(fromTimerMode);
    }

    /**
     * BidおよびAskを描画する。
     */
    void drawBidAsk() {
        this.draw.drawBidAsk(this.marketContext);
    }

    /**
     * イベント内の処理時間ラベル更新をまとめる。
     */
    void beginProcessingTimeUpdateBatch() {
        this.processingTimeDraw.beginUpdateBatch();
    }

    /**
     * イベント内で保持した集計を反映し、前回の描画失敗も再試行する。
     */
    void endProcessingTimeUpdateBatch() {
        this.processingTimeDraw.endUpdateBatch();
    }

    /**
     * 処理時間を集計して表示内容を保持し、まとめ更新中はイベント終了時に反映する。
     *
     * @param fromIndex 更新処理・EMA200・GMMA・日本時間軸に対応する行番号
     * @param fromElapsedMicroseconds 今回の処理時間。単位はマイクロ秒
     * @param fromSucceeded 正常終了として集計する場合true
     * @param fromState 更新内容または再試行状態
     */
    void recordProcessingTime(int fromIndex, ulong fromElapsedMicroseconds, bool fromSucceeded, string fromState) {
        if (fromIndex < 0 || fromIndex >= 4) {
            return;
        }

        this.processingTimes[fromIndex].record(fromElapsedMicroseconds, fromSucceeded, fromState);
        this.processingTimeDraw.updateRow(fromIndex, this.processingTimes[fromIndex]);
    }

    /**
     * 分析結果に合わせて上下FITを更新し、チャート全体を描画する。
     *
     * @param fromElliotAll Elliott分析結果
     */
    void drawAll(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return;
        }

        this.updateVerticalFit(fromElliotAll, true);
        this.applyInitialVerticalFit(fromElliotAll);

        this.draw.drawAll(
            fromElliotAll,
            this.elliotInfoVisible,
            this.isVerticalFitLabelClampEnabled(),
            this.elliotInfoSimple,
            this.elliotHigherTimeFrameDisplayCount
        );
        this.updateHorizontalView(this.getHorizontalViewKey());
    }

    /**
     * 表示範囲変更時に上下FITと描画を更新する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 全体を再描画した場合true
     */
    bool onChartChange(ElliotAll *fromElliotAll) {
        string viewKey = this.getHorizontalViewKey();
        bool horizontalChanged = viewKey != "" && viewKey != this.lastHorizontalViewKey;
        bool verticalChanged = this.updateVerticalFit(fromElliotAll, false);
        if (!horizontalChanged && !verticalChanged) {
            return false;
        }

        if (horizontalChanged) {
            this.updateHorizontalView(viewKey);
        }

        this.redraw(fromElliotAll);

        return true;
    }

    /**
     * 操作ボタンのクリックを処理する。
     *
     * @param fromObjectName クリックされたオブジェクト名
     * @param fromElliotAll Elliott分析結果
     * @return 全体を再描画した場合true
     */
    bool onObjectClick(
        const string fromObjectName,
        ElliotAll *fromElliotAll
    ) {
        if (fromObjectName == this.getElliotVerticalFitButtonName()) {
            return this.syncVerticalFitButtonState(fromElliotAll);
        }

        if (fromObjectName == this.getElliotInfoModeButtonName()) {
            this.elliotInfoSimple = !this.elliotInfoSimple;
            this.updateElliotInfoModeButton();
            this.redraw(fromElliotAll);

            return true;
        }

        if (fromObjectName == this.getElliotInfoButtonName()) {
            this.elliotInfoVisible = !this.elliotInfoVisible;
            this.updateElliotInfoButton();
            this.redraw(fromElliotAll);

            return true;
        }

        return false;
    }

    /**
     * タイマー待機中に上下FITを更新する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 全体を再描画した場合true
     */
    bool updateIdle(ElliotAll *fromElliotAll) {
        if (this.applyInitialVerticalFit(fromElliotAll)) {
            this.redraw(fromElliotAll);

            return true;
        }

        if (!this.updateVerticalFit(fromElliotAll, false)) {
            return false;
        }

        this.redraw(fromElliotAll);

        return true;
    }

    /**
     * ボタン状態をElliott上下FITへ反映する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 全体を再描画した場合true
     */
    bool syncVerticalFitButtonState(ElliotAll *fromElliotAll) {
        if (this.drawElliotVerticalFit == NULL
                || fromElliotAll == NULL) {
            return false;
        }

        string objectName = this.getElliotVerticalFitButtonName();

        if (ObjectFind(0, objectName) < 0) {
            return false;
        }

        long buttonStateValue = 0;

        ResetLastError();

        if (!ObjectGetInteger(
                0,
                objectName,
                OBJPROP_STATE,
                0,
                buttonStateValue)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "ObjectGetInteger OBJPROP_STATE failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        bool buttonState = (bool)buttonStateValue;
        bool fitState = this.drawElliotVerticalFit.isEnabled();

        if (buttonState == fitState) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "buttonState=%s fitState=%s",
                (string)buttonState,
                (string)fitState
            )
        );

        return this.toggleVerticalFit(fromElliotAll);
    }

    /**
     * 表示オブジェクト、補助表示および上下FITを解放する。
     */
    void destroy() {
        this.draw.clearInfoLabels();
        this.draw.clearRoundLines();
        this.processingTimeDraw.clear();

        for (int i = 0; i < 4; i++) {
            this.processingTimes[i].reset();
        }

        if (this.gmmaIndicator != NULL) {
            this.gmmaIndicator.deinit();
            delete this.gmmaIndicator;
            this.gmmaIndicator = NULL;
        }

        if (this.ema200Indicator != NULL) {
            this.ema200Indicator.deinit();
            delete this.ema200Indicator;
            this.ema200Indicator = NULL;
        }

        if (this.japanTimeAxisView != NULL) {
            this.japanTimeAxisView.destroy();
            delete this.japanTimeAxisView;
            this.japanTimeAxisView = NULL;
        }

        this.timeAxisFullUpdatePending = false;
        this.lastTimeAxisFullUpdateTick = 0;

        if (this.drawElliotVerticalFit != NULL) {
            this.drawElliotVerticalFit.restore();
            delete this.drawElliotVerticalFit;
            this.drawElliotVerticalFit = NULL;
        }

        ObjectDelete(0, this.getElliotInfoButtonName());
        ObjectDelete(0, this.getElliotInfoModeButtonName());
        ObjectDelete(0, this.getElliotVerticalFitButtonName());
        ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
        this.draw.invalidateBidAskLabels();
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;

    /** ロガー。 */
    Logger logger;

    /** 全体描画。 */
    Draw draw;

    /** 更新処理・EMA200・GMMA・日本時間軸の独立した処理時間集計。 */
    ProcessingTimeStats processingTimes[4];

    /** 時計の下の処理時間表示。 */
    DrawProcessingTime processingTimeDraw;

    /** 右側情報欄に共用するチャート右端からの余白。 */
    int infoRightDistance;

    /** 波動ラベルを最後に配置した横方向の表示条件。 */
    string lastHorizontalViewKey;

    /** GMMA表示。 */
    GmmaIndicator *gmmaIndicator;

    /** EMA200表示。 */
    Ema200Indicator *ema200Indicator;

    /** 日本時間軸表示。 */
    JapanTimeAxisView *japanTimeAxisView;

    /** 通常チャートの履歴再計算後、日本時間軸の強制更新待ちの場合true。 */
    bool timeAxisFullUpdatePending;

    /** 日本時間軸の強制更新を最後に試行した経過ミリ秒。 */
    ulong lastTimeAxisFullUpdateTick;

    /** Elliott上下FIT。 */
    DrawElliotVerticalFit *drawElliotVerticalFit;

    /** 波動ラベルを表示する上位時間足数。 */
    int elliotHigherTimeFrameDisplayCount;

    /** Elliott情報表を表示する場合true。 */
    bool elliotInfoVisible;

    /** Elliott情報を簡易表示する場合true。 */
    bool elliotInfoSimple;

    /** 初回上下FITの適用待ちの場合true。 */
    bool initialVerticalFitPending;

    /**
     * 横方向の表示条件が変わった場合だけ、取得済みEMAの文字位置を更新する。
     * 通常の全描画と画面変更のどちらが先でも、ラベルの再配置を省略しない。
     *
     * @param fromViewKey 今回の横方向の表示条件。
     */
    void updateHorizontalView(const string fromViewKey) {
        if (fromViewKey == "" || this.lastHorizontalViewKey == fromViewKey) {
            return;
        }

        if (this.ema200Indicator != NULL) {
            this.ema200Indicator.refreshLabels();
        }

        this.lastHorizontalViewKey = fromViewKey;
    }

    /**
     * 波動文字の横位置に影響する表示範囲・縮尺・右余白を取得する。
     * 特殊縮尺の場合だけ、高さと価格範囲の変化も横方向の変更として扱う。
     *
     * @return 表示条件の識別子。取得できない場合は空文字。
     */
    string getHorizontalViewKey() {
        long width = 0;
        long firstVisibleBar = 0;
        long visibleBars = 0;
        long scale = 0;
        long chartShift = 0;
        long scaleFix11 = 0;
        long scalePointsPerBar = 0;
        double shiftSize = 0.0;
        if (!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, width)
                || !ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0, firstVisibleBar)
                || !ChartGetInteger(0, CHART_VISIBLE_BARS, 0, visibleBars)
                || !ChartGetInteger(0, CHART_SCALE, 0, scale)
                || !ChartGetInteger(0, CHART_SHIFT, 0, chartShift)
                || !ChartGetInteger(0, CHART_SCALEFIX_11, 0, scaleFix11)
                || !ChartGetInteger(0, CHART_SCALE_PT_PER_BAR, 0, scalePointsPerBar)
                || width <= 0 || firstVisibleBar < 0 || visibleBars <= 0) {
            return "";
        }

        if (chartShift != 0 && !ChartGetDouble(0, CHART_SHIFT_SIZE, 0, shiftSize)) {
            return "";
        }

        long height = 0;
        double minimumPrice = 0.0;
        double maximumPrice = 0.0;
        if ((scaleFix11 != 0 || scalePointsPerBar != 0)
                && (!ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, height)
                    || !ChartGetDouble(0, CHART_PRICE_MIN, 0, minimumPrice)
                    || !ChartGetDouble(0, CHART_PRICE_MAX, 0, maximumPrice))) {
            return "";
        }

        datetime latestBarTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);

        return StringFormat("%I64d/%I64d/%I64d/%I64d/%I64d/%.17g/%I64d/%I64d/%I64d/%.17g/%.17g/%I64d",
            width, firstVisibleBar, visibleBars, scale, chartShift, shiftSize,
            scaleFix11, scalePointsPerBar, height, minimumPrice, maximumPrice, (long)latestBarTime);
    }

    /**
     * エリオット情報表示ボタン名を取得する。
     *
     * @return ボタン名
     */
    string getElliotInfoButtonName() {
        return Constant::PREFIX_FIXED + "ElliotInfoButton";
    }

    /**
     * Elliott情報表示モード切替ボタン名を取得する。
     *
     * @return ボタン名
     */
    string getElliotInfoModeButtonName() {
        return Constant::PREFIX_FIXED + "ElliotInfoModeButton";
    }

    /**
     * Elliott上下FITボタン名を取得する。
     *
     * @return ボタン名
     */
    string getElliotVerticalFitButtonName() {
        return Constant::PREFIX_FIXED + "ElliotVerticalFitButton";
    }

    /**
     * エリオット情報表の表示切替ボタンを作成する。
     */
    void createElliotInfoButton() {
        string objectName = this.getElliotInfoButtonName();

        ObjectDelete(0, objectName);

        if (!ObjectCreate(0, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_CORNER,
            CORNER_RIGHT_LOWER
        );
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE,
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance,
                2 * (DrawZigZagElliotInfoLayout::getButtonWidth()
                    + DrawZigZagElliotInfoLayout::getButtonGap())));
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, DrawZigZagElliotInfoLayout::getButtonWidth());
        ObjectSetInteger(0, objectName, OBJPROP_YSIZE, 24);
        ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objectName, OBJPROP_ZORDER, 1000);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BORDER_COLOR,
            clrWhite
        );
        ObjectSetString(0, objectName, OBJPROP_FONT, "Meiryo UI");

        this.updateElliotInfoButton();
    }

    /**
     * Elliott情報の詳細・簡易表示切替ボタンを作成する。
     */
    void createElliotInfoModeButton() {
        string objectName = this.getElliotInfoModeButtonName();

        ObjectDelete(0, objectName);

        if (!ObjectCreate(0, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_CORNER,
            CORNER_RIGHT_LOWER
        );
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE,
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance));
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, DrawZigZagElliotInfoLayout::getButtonWidth());
        ObjectSetInteger(0, objectName, OBJPROP_YSIZE, 24);
        ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objectName, OBJPROP_ZORDER, 1000);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BORDER_COLOR,
            clrWhite
        );
        ObjectSetString(0, objectName, OBJPROP_FONT, "Meiryo UI");

        this.updateElliotInfoModeButton();
    }

    /**
     * Elliott波動ラベルの上下FIT切替ボタンを作成する。
     */
    void createElliotVerticalFitButton() {
        string objectName = this.getElliotVerticalFitButtonName();

        ObjectDelete(0, objectName);

        if (!ObjectCreate(0, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_CORNER,
            CORNER_RIGHT_LOWER
        );
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE,
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance,
                DrawZigZagElliotInfoLayout::getButtonWidth()
                    + DrawZigZagElliotInfoLayout::getButtonGap()));
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, DrawZigZagElliotInfoLayout::getButtonWidth());
        ObjectSetInteger(0, objectName, OBJPROP_YSIZE, 24);
        ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objectName, OBJPROP_ZORDER, 1000);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BORDER_COLOR,
            clrWhite
        );
        ObjectSetString(0, objectName, OBJPROP_FONT, "Meiryo UI");

        this.updateElliotVerticalFitButton();
    }

    /**
     * エリオット情報表の表示状態をボタンへ反映する。
     */
    void updateElliotInfoButton() {
        string objectName = this.getElliotInfoButtonName();

        if (ObjectFind(0, objectName) < 0) {
            return;
        }

        string text = "波動情報:ON";
        color backgroundColor = clrDarkGreen;

        if (!this.elliotInfoVisible) {
            text = "波動情報:OFF";
            backgroundColor = clrDimGray;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_STATE,
            this.elliotInfoVisible
        );
        ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BGCOLOR,
            backgroundColor
        );
        ObjectSetString(0, objectName, OBJPROP_TEXT, text);
    }

    /**
     * Elliott情報表示モードをボタンへ反映する。
     */
    void updateElliotInfoModeButton() {
        string objectName = this.getElliotInfoModeButtonName();

        if (ObjectFind(0, objectName) < 0) {
            return;
        }

        string text = "表示: 詳細";
        color backgroundColor = clrNavy;

        if (this.elliotInfoSimple) {
            text = "表示: 簡易";
            backgroundColor = clrDarkGreen;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_STATE,
            this.elliotInfoSimple
        );
        ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BGCOLOR,
            backgroundColor
        );
        ObjectSetString(0, objectName, OBJPROP_TEXT, text);
    }

    /**
     * Elliott上下FIT状態をボタンへ反映する。
     */
    void updateElliotVerticalFitButton() {
        string objectName = this.getElliotVerticalFitButtonName();

        if (ObjectFind(0, objectName) < 0) {
            return;
        }

        bool isEnabled = false;

        if (this.drawElliotVerticalFit != NULL) {
            isEnabled = this.drawElliotVerticalFit.isEnabled();
        }

        string text = "波動上下FIT";
        color backgroundColor = clrDimGray;

        if (isEnabled) {
            text = "上下FIT解除";
            backgroundColor = clrDarkGreen;
        }

        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_STATE,
            isEnabled
        );
        ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(
            0,
            objectName,
            OBJPROP_BGCOLOR,
            backgroundColor
        );
        ObjectSetString(0, objectName, OBJPROP_TEXT, text);
    }

    /**
     * Elliott情報表の表示状態を反映して再描画する。
     *
     * @param fromElliotAll Elliott分析結果
     */
    void redraw(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return;
        }

        this.draw.drawAll(
            fromElliotAll,
            this.elliotInfoVisible,
            this.isVerticalFitLabelClampEnabled(),
            this.elliotInfoSimple,
            this.elliotHigherTimeFrameDisplayCount
        );
        this.updateHorizontalView(this.getHorizontalViewKey());
    }

    /**
     * Visual Testerでラベルを上下端へ収めるか判定する。
     *
     * @return ラベルクランプを使用する場合true
     */
    bool isVerticalFitLabelClampMode() {
        return Util::isStrategyTester()
            && MQLInfoInteger(MQL_VISUAL_MODE);
    }

    /**
     * Elliottラベルの上下端クランプが有効か判定する。
     *
     * @return 有効な場合true
     */
    bool isVerticalFitLabelClampEnabled() {
        if (!this.isVerticalFitLabelClampMode()
                || this.drawElliotVerticalFit == NULL) {
            return false;
        }

        return this.drawElliotVerticalFit.isEnabled();
    }

    /**
     * 初回のElliott分析成功後に上下FITを有効化する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 初回上下FITを適用した場合true
     */
    bool applyInitialVerticalFit(ElliotAll *fromElliotAll) {
        if (!this.initialVerticalFitPending
                || this.drawElliotVerticalFit == NULL
                || fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded) {
            return false;
        }

        if (!this.drawElliotVerticalFit.isEnabled()) {
            if (!this.drawElliotVerticalFit.enable(fromElliotAll)) {
                this.logger.debug(
                    __FUNCTION__,
                    "initial Elliott vertical fit is not ready. retry on next timer."
                );

                return false;
            }
        }

        this.initialVerticalFitPending = false;
        this.updateElliotVerticalFitButton();

        return true;
    }

    /**
     * Elliott上下FITの有効・無効を切り替える。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 再描画した場合true
     */
    bool toggleVerticalFit(ElliotAll *fromElliotAll) {
        if (this.drawElliotVerticalFit == NULL
                || fromElliotAll == NULL) {
            this.updateElliotVerticalFitButton();

            return false;
        }

        if (this.drawElliotVerticalFit.isEnabled()) {
            if (!this.drawElliotVerticalFit.restore()) {
                this.logger.error(
                    __FUNCTION__,
                    "Elliott vertical fit restore failed"
                );
                this.updateElliotVerticalFitButton();

                return false;
            }
        } else {
            if (!this.drawElliotVerticalFit.enable(fromElliotAll)) {
                this.logger.error(
                    __FUNCTION__,
                    "Elliott vertical fit enable failed"
                );
                this.updateElliotVerticalFitButton();

                return false;
            }
        }

        this.updateElliotVerticalFitButton();
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "enabled=%s labelClampMode=%s",
                (string)this.drawElliotVerticalFit.isEnabled(),
                (string)this.isVerticalFitLabelClampMode()
            )
        );
        this.redraw(fromElliotAll);

        return true;
    }

    /**
     * 表示範囲または分析結果に合わせて上下FITを更新する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromForce 表示範囲が同じでも再計算する場合true
     * @return 価格軸を更新した場合true
     */
    bool updateVerticalFit(
        ElliotAll *fromElliotAll,
        bool fromForce
    ) {
        if (this.drawElliotVerticalFit == NULL
                || fromElliotAll == NULL) {
            return false;
        }

        return this.drawElliotVerticalFit.update(
            fromElliotAll,
            fromForce
        );
    }

    /**
     * EMA200表示を更新する。
     *
     * @param fromTimerMode タイマー実行の場合true
     * @param fromResetBuffers 履歴再計算に伴い全バッファを初期化する場合true
     */
    void updateEma200Indicator(bool fromTimerMode, bool fromResetBuffers = false) {
        if (this.ema200Indicator != NULL) {
            ulong startMicroseconds = GetMicrosecondCount();
            bool isSucceeded = this.ema200Indicator.update(fromTimerMode, fromResetBuffers);
            ulong elapsedMicroseconds = GetMicrosecondCount() - startMicroseconds;

            if (this.ema200Indicator.wasUpdatePerformed()) {
                string updateMode = this.ema200Indicator.getLastUpdateMode();
                if (!isSucceeded && updateMode != "準備中") {
                    updateMode = "再試行";
                }

                this.recordProcessingTime(1, elapsedMicroseconds, isSucceeded, updateMode);
            }
        }
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_CHART_CONTROLLER_MQH
