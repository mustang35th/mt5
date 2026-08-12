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
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\Draw.mqh>
#include <Mstng\Draw\DrawElliotVerticalFit.mqh>
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
        this.drawElliotVerticalFit = NULL;
        this.elliotInfoVisible = true;
        this.elliotInfoSimple = true;
        this.initialVerticalFitPending = true;
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
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        OscillatorHandlePool *fromOscillatorHandlePool
    ) {
        this.destroy();

        if (fromOscillatorHandlePool == NULL) {
            return false;
        }

        this.marketContext = fromMarketContext;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.elliotInfoVisible = true;
        this.elliotInfoSimple = true;
        this.initialVerticalFitPending = true;

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
        this.japanTimeAxisView =
            new JapanTimeAxisView(this.marketContext);

        if (this.japanTimeAxisView == NULL) {
            return false;
        }

        this.japanTimeAxisView.create();
        this.drawElliotVerticalFit = new DrawElliotVerticalFit(
            this.isVerticalFitLabelClampMode()
        );

        if (this.drawElliotVerticalFit == NULL) {
            return false;
        }

        this.createElliotInfoButton();
        this.createElliotInfoModeButton();
        this.createElliotVerticalFitButton();

        return true;
    }

    /**
     * OnCalculateで更新する補助表示を処理する。
     *
     * @param fromTimerMode タイマー実行の場合true
     */
    void updateOnCalculate(bool fromTimerMode) {
        if (this.gmmaIndicator != NULL) {
            this.gmmaIndicator.update();
        }

        this.updateEma200Indicator(fromTimerMode);
    }

    /**
     * OnTimerで更新する補助表示を処理する。
     *
     * @param fromTimerMode タイマー実行の場合true
     */
    void updateOnTimer(bool fromTimerMode) {
        if (this.japanTimeAxisView != NULL) {
            this.japanTimeAxisView.update();
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
            this.elliotInfoSimple
        );
    }

    /**
     * 表示範囲変更時に上下FITと描画を更新する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 全体を再描画した場合true
     */
    bool onChartChange(ElliotAll *fromElliotAll) {
        if (!this.updateVerticalFit(fromElliotAll, false)) {
            return false;
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

        if (this.drawElliotVerticalFit != NULL) {
            this.drawElliotVerticalFit.restore();
            delete this.drawElliotVerticalFit;
            this.drawElliotVerticalFit = NULL;
        }

        ObjectDelete(0, this.getElliotInfoButtonName());
        ObjectDelete(0, this.getElliotInfoModeButtonName());
        ObjectDelete(0, this.getElliotVerticalFitButtonName());
        ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** ロガー。 */
    Logger logger;
    /** 全体描画。 */
    Draw draw;
    /** GMMA表示。 */
    GmmaIndicator *gmmaIndicator;
    /** EMA200表示。 */
    Ema200Indicator *ema200Indicator;
    /** 日本時間軸表示。 */
    JapanTimeAxisView *japanTimeAxisView;
    /** Elliott上下FIT。 */
    DrawElliotVerticalFit *drawElliotVerticalFit;
    /** Elliott情報表を表示する場合true。 */
    bool elliotInfoVisible;
    /** Elliott情報を簡易表示する場合true。 */
    bool elliotInfoSimple;
    /** 初回上下FITの適用待ちの場合true。 */
    bool initialVerticalFitPending;

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
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 140);
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, 130);
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
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 140);
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 75);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, 130);
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
        ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 280);
        ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
        ObjectSetInteger(0, objectName, OBJPROP_XSIZE, 130);
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

        string text = "波動情報: ON";
        color backgroundColor = clrDarkGreen;

        if (!this.elliotInfoVisible) {
            text = "波動情報: OFF";
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
            this.elliotInfoSimple
        );
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
     */
    void updateEma200Indicator(bool fromTimerMode) {
        if (this.ema200Indicator != NULL) {
            this.ema200Indicator.update(fromTimerMode);
        }
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_CHART_CONTROLLER_MQH
