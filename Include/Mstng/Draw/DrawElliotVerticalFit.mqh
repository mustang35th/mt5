//+------------------------------------------------------------------+
//|                                      DrawElliotVerticalFit.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef __DRAW_ELLIOT_VERTICAL_FIT_MQH__
#define __DRAW_ELLIOT_VERTICAL_FIT_MQH__

#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * 画面内のElliott波動ラベルが上下へ収まるよう価格軸を調整するクラス。
 *
 * 現在表示中のローソク足と、DrawElliotが描画する現在足および上位2足の
 * ZigZagポイントから価格範囲を算出し、ラベル用の上下余白を加えて固定する。
 * FIT解除時は、変更前の価格軸設定を復元する。
 */
class DrawElliotVerticalFit {
public:
    /**
     * 価格軸設定と表示範囲の初期値を設定する。
     */
    DrawElliotVerticalFit() {
        this.logger.setLevel(LOG_INFO);
        this.chartId = 0;
        this.isEnabledValue = false;
        this.isOriginalScaleSaved = false;
        this.originalScaleFix = false;
        this.originalScaleFix11 = false;
        this.originalScalePointsPerBar = false;
        this.originalFixedMax = 0;
        this.originalFixedMin = 0;
        this.originalPointsPerBar = 0;
        this.lastFirstVisibleBar = -1;
        this.lastVisibleBars = -1;
        this.lastChartHeight = -1;
        this.lastPriceMin = 0;
        this.lastPriceMax = 0;
        this.lastPoint = 0;
    }

    /**
     * デストラクタ。
     */
    ~DrawElliotVerticalFit() {
    }

    /**
     * 上下FITを有効化する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return FITを適用できた場合true
     */
    bool enable(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return false;
        }

        if (this.isEnabledValue) {
            return this.update(fromElliotAll, true);
        }

        this.logger.setMarketContext(fromElliotAll.marketContext);

        double fixedMin = 0;
        double fixedMax = 0;
        int firstVisibleBar = 0;
        int visibleBars = 0;
        int chartHeight = 0;

        if (!this.calculateFixedRange(
                fromElliotAll,
                fixedMin,
                fixedMax,
                firstVisibleBar,
                visibleBars,
                chartHeight
        )) {
            return false;
        }

        if (!this.saveOriginalScale()) {
            return false;
        }

        if (!this.applyFixedRange(fixedMin, fixedMax)) {
            this.restore();

            return false;
        }

        this.isEnabledValue = true;
        this.saveChartView(fromElliotAll, firstVisibleBar, visibleBars, chartHeight);

        return true;
    }

    /**
     * 表示範囲または分析結果の変更に合わせて上下FITを更新する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromForce trueの場合、表示範囲が同じでも再計算する
     * @return 価格軸を更新した場合true
     */
    bool update(ElliotAll *fromElliotAll, bool fromForce = false) {
        if (!this.isEnabledValue || fromElliotAll == NULL) {
            return false;
        }

        if (!fromForce && !this.isChartViewChanged()) {
            return false;
        }

        double fixedMin = 0;
        double fixedMax = 0;
        int firstVisibleBar = 0;
        int visibleBars = 0;
        int chartHeight = 0;

        if (!this.calculateFixedRange(
                fromElliotAll,
                fixedMin,
                fixedMax,
                firstVisibleBar,
                visibleBars,
                chartHeight
        )) {
            return false;
        }

        if (!this.applyFixedRange(fixedMin, fixedMax)) {
            return false;
        }

        this.saveChartView(fromElliotAll, firstVisibleBar, visibleBars, chartHeight);

        return true;
    }

    /**
     * 上下FIT適用前の価格軸設定を復元する。
     *
     * @return 復元できた場合true
     */
    bool restore() {
        if (!this.isOriginalScaleSaved) {
            this.isEnabledValue = false;
            this.clearChartView();

            return true;
        }

        bool isRestored = true;

        if (!ChartSetInteger(this.chartId, CHART_SCALEFIX, false)) {
            this.logger.error(__FUNCTION__, "restore CHART_SCALEFIX false failed");
            isRestored = false;
        }

        if (!ChartSetInteger(this.chartId, CHART_SCALEFIX_11, false)) {
            this.logger.error(__FUNCTION__, "restore CHART_SCALEFIX_11 false failed");
            isRestored = false;
        }

        if (!ChartSetInteger(this.chartId, CHART_SCALE_PT_PER_BAR, false)) {
            this.logger.error(__FUNCTION__, "restore CHART_SCALE_PT_PER_BAR false failed");
            isRestored = false;
        }

        if (this.originalScaleFix) {
            if (!this.applyFixedRange(this.originalFixedMin, this.originalFixedMax)) {
                this.logger.error(__FUNCTION__, "restore fixed range failed");
                isRestored = false;
            }
        }

        if (this.originalScaleFix11) {
            if (!ChartSetInteger(this.chartId, CHART_SCALEFIX_11, true)) {
                this.logger.error(__FUNCTION__, "restore CHART_SCALEFIX_11 true failed");
                isRestored = false;
            }
        }

        if (this.originalScalePointsPerBar) {
            if (!ChartSetInteger(this.chartId, CHART_SCALE_PT_PER_BAR, true)) {
                this.logger.error(__FUNCTION__, "restore CHART_SCALE_PT_PER_BAR true failed");
                isRestored = false;
            }

            if (!ChartSetDouble(this.chartId, CHART_POINTS_PER_BAR, this.originalPointsPerBar)) {
                this.logger.error(__FUNCTION__, "restore CHART_POINTS_PER_BAR failed");
                isRestored = false;
            }
        }

        ChartRedraw(this.chartId);

        if (!isRestored) {
            return false;
        }

        this.isEnabledValue = false;
        this.isOriginalScaleSaved = false;
        this.clearChartView();

        return true;
    }

    /**
     * 上下FITが有効か判定する。
     *
     * @return 有効な場合true
     */
    bool isEnabled() {
        return this.isEnabledValue;
    }

private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /** Elliottラベルのフォントおよびピクセル間隔設定。 */
    DrawProperties drawProperties;

    /** 操作対象チャートID。 */
    long chartId;

    /** 上下FITが有効な場合true。 */
    bool isEnabledValue;

    /** 変更前の価格軸設定を保存済みの場合true。 */
    bool isOriginalScaleSaved;

    /** 変更前の固定価格軸設定。 */
    bool originalScaleFix;

    /** 変更前の1:1固定価格軸設定。 */
    bool originalScaleFix11;

    /** 変更前のpoints-per-bar価格軸設定。 */
    bool originalScalePointsPerBar;

    /** 変更前の固定上限価格。 */
    double originalFixedMax;

    /** 変更前の固定下限価格。 */
    double originalFixedMin;

    /** 変更前の1バー当たりポイント数。 */
    double originalPointsPerBar;

    /** 前回更新時の左端表示バー。 */
    int lastFirstVisibleBar;

    /** 前回更新時の表示バー数。 */
    int lastVisibleBars;

    /** 前回更新時のチャート高さ。 */
    int lastChartHeight;

    /** 前回更新時の表示下限価格。 */
    double lastPriceMin;

    /** 前回更新時の表示上限価格。 */
    double lastPriceMax;

    /** 価格変更比較用の最小価格単位。 */
    double lastPoint;

    /**
     * 上下FIT適用前の価格軸設定を保存する。
     *
     * @return 保存できた場合true
     */
    bool saveOriginalScale() {
        if (this.isOriginalScaleSaved) {
            return true;
        }

        long scaleFix = 0;
        long scaleFix11 = 0;
        long scalePointsPerBar = 0;

        if (!ChartGetInteger(this.chartId, CHART_SCALEFIX, 0, scaleFix)) {
            this.logger.error(__FUNCTION__, "ChartGetInteger CHART_SCALEFIX failed");

            return false;
        }

        if (!ChartGetInteger(this.chartId, CHART_SCALEFIX_11, 0, scaleFix11)) {
            this.logger.error(__FUNCTION__, "ChartGetInteger CHART_SCALEFIX_11 failed");

            return false;
        }

        if (!ChartGetInteger(this.chartId, CHART_SCALE_PT_PER_BAR, 0, scalePointsPerBar)) {
            this.logger.error(__FUNCTION__, "ChartGetInteger CHART_SCALE_PT_PER_BAR failed");

            return false;
        }

        if (!ChartGetDouble(this.chartId, CHART_FIXED_MAX, 0, this.originalFixedMax)) {
            this.logger.error(__FUNCTION__, "ChartGetDouble CHART_FIXED_MAX failed");

            return false;
        }

        if (!ChartGetDouble(this.chartId, CHART_FIXED_MIN, 0, this.originalFixedMin)) {
            this.logger.error(__FUNCTION__, "ChartGetDouble CHART_FIXED_MIN failed");

            return false;
        }

        if (!ChartGetDouble(this.chartId, CHART_POINTS_PER_BAR, 0, this.originalPointsPerBar)) {
            this.logger.error(__FUNCTION__, "ChartGetDouble CHART_POINTS_PER_BAR failed");

            return false;
        }

        this.originalScaleFix = (bool)scaleFix;
        this.originalScaleFix11 = (bool)scaleFix11;
        this.originalScalePointsPerBar = (bool)scalePointsPerBar;
        this.isOriginalScaleSaved = true;

        return true;
    }

    /**
     * 表示対象から固定価格範囲を算出する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param toFixedMin 固定下限価格
     * @param toFixedMax 固定上限価格
     * @param toFirstVisibleBar 左端表示バー
     * @param toVisibleBars 表示バー数
     * @param toChartHeight チャート高さ
     * @return 算出できた場合true
     */
    bool calculateFixedRange(
            ElliotAll *fromElliotAll,
            double &toFixedMin,
            double &toFixedMax,
            int &toFirstVisibleBar,
            int &toVisibleBars,
            int &toChartHeight
    ) {
        toFirstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR, 0);
        toVisibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS, 0);
        toChartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);

        if (toFirstVisibleBar < 0 || toVisibleBars <= 0 || toChartHeight <= 0) {
            return false;
        }

        int rightVisibleBar = toFirstVisibleBar - toVisibleBars + 1;

        if (rightVisibleBar < 0) {
            rightVisibleBar = 0;
        }

        double priceMin = 0;
        double priceMax = 0;

        if (!this.getVisibleRateRange(
                fromElliotAll.marketContext,
                rightVisibleBar,
                toFirstVisibleBar,
                priceMin,
                priceMax
        )) {
            return false;
        }

        this.addVisibleElliotRange(
            fromElliotAll,
            rightVisibleBar,
            toFirstVisibleBar,
            priceMin,
            priceMax
        );

        double fontHeight = (double)this.drawProperties.fontPixelHeight;

        if (fontHeight <= 0) {
            fontHeight = (double)this.drawProperties.elliotFontSize;
        }

        double maxFontHeight = fontHeight
            * (double)(this.drawProperties.elliotFontSize + 4)
            / (double)this.drawProperties.elliotFontSize;
        double labelDistance = (double)this.drawProperties.elliotPixelDistance;
        int topPadding = (int)MathCeil(
            (3.0 * (fontHeight + labelDistance))
            + (maxFontHeight / 2.0)
            + labelDistance
        );
        int bottomPadding = (int)MathCeil(
            (3.5 * fontHeight)
            + (4.5 * labelDistance)
            + (maxFontHeight / 2.0)
            + labelDistance
        );
        int usableHeight = toChartHeight - topPadding - bottomPadding;

        if (usableHeight <= 0 || priceMax <= priceMin) {
            return false;
        }

        double pricePerPixel = (priceMax - priceMin) / (double)usableHeight;

        toFixedMax = priceMax + ((double)topPadding * pricePerPixel);
        toFixedMin = priceMin - ((double)bottomPadding * pricePerPixel);

        if (!MathIsValidNumber(toFixedMin) || !MathIsValidNumber(toFixedMax)) {
            return false;
        }

        if (toFixedMax <= toFixedMin) {
            return false;
        }

        return true;
    }

    /**
     * 画面内ローソク足の高値・安値を取得する。
     *
     * @param fromMarketContext 対象市場コンテキスト
     * @param fromRightVisibleBar 右端表示バー
     * @param fromFirstVisibleBar 左端表示バー
     * @param toPriceMin 最安値
     * @param toPriceMax 最高値
     * @return 取得できた場合true
     */
    bool getVisibleRateRange(
            MarketContext &fromMarketContext,
            int fromRightVisibleBar,
            int fromFirstVisibleBar,
            double &toPriceMin,
            double &toPriceMax
    ) {
        int count = fromFirstVisibleBar - fromRightVisibleBar + 1;

        if (count <= 0) {
            return false;
        }

        MqlRates rates[];
        int copiedCount = CopyRates(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            fromRightVisibleBar,
            count,
            rates
        );

        if (copiedCount <= 0) {
            this.logger.error(__FUNCTION__, "CopyRates failed");

            return false;
        }

        bool isRateFound = false;

        for (int i = 0; i < copiedCount; i++) {
            if (!MathIsValidNumber(rates[i].low) || !MathIsValidNumber(rates[i].high)) {
                continue;
            }

            if (rates[i].low <= 0 || rates[i].high < rates[i].low) {
                continue;
            }

            if (!isRateFound) {
                toPriceMin = rates[i].low;
                toPriceMax = rates[i].high;
                isRateFound = true;

                continue;
            }

            toPriceMin = MathMin(toPriceMin, rates[i].low);
            toPriceMax = MathMax(toPriceMax, rates[i].high);
        }

        return isRateFound;
    }

    /**
     * 画面内に描画するElliottポイントを価格範囲へ追加する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromRightVisibleBar 右端表示バー
     * @param fromFirstVisibleBar 左端表示バー
     * @param toPriceMin 最安値
     * @param toPriceMax 最高値
     */
    void addVisibleElliotRange(
            ElliotAll *fromElliotAll,
            int fromRightVisibleBar,
            int fromFirstVisibleBar,
            double &toPriceMin,
            double &toPriceMax
    ) {
        for (int i = 0; i <= 2; i++) {
            Elliot *elliot = NULL;

            if (i == 0) {
                elliot = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame);
            } else {
                elliot = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame, i);
            }

            if (elliot == NULL) {
                continue;
            }

            for (int j = 0; j < elliot.waveList.Total(); j++) {
                Wave *wave = elliot.waveList.At(j);

                if (wave == NULL) {
                    continue;
                }

                for (int k = 1; k < wave.zigZagPointList.Total(); k++) {
                    ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(k);

                    if (zigZagPoint == NULL || zigZagPoint.barTime <= 0) {
                        continue;
                    }

                    if (!MathIsValidNumber(zigZagPoint.rate)
                            || zigZagPoint.rate == EMPTY_VALUE
                            || zigZagPoint.rate <= 0) {
                        continue;
                    }

                    int barIndex = iBarShift(
                        fromElliotAll.marketContext.symbolName,
                        fromElliotAll.marketContext.timeFrame,
                        zigZagPoint.barTime,
                        false
                    );

                    if (barIndex < fromRightVisibleBar || barIndex > fromFirstVisibleBar) {
                        continue;
                    }

                    toPriceMin = MathMin(toPriceMin, zigZagPoint.rate);
                    toPriceMax = MathMax(toPriceMax, zigZagPoint.rate);
                }
            }
        }
    }

    /**
     * 固定価格範囲をチャートへ適用する。
     *
     * @param fromFixedMin 固定下限価格
     * @param fromFixedMax 固定上限価格
     * @return 適用できた場合true
     */
    bool applyFixedRange(double fromFixedMin, double fromFixedMax) {
        if (!MathIsValidNumber(fromFixedMin)
                || !MathIsValidNumber(fromFixedMax)
                || fromFixedMax <= fromFixedMin) {
            return false;
        }

        double currentMin = ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0);

        if (!ChartSetInteger(this.chartId, CHART_SCALEFIX_11, false)) {
            this.logger.error(__FUNCTION__, "ChartSetInteger CHART_SCALEFIX_11 failed");

            return false;
        }

        if (!ChartSetInteger(this.chartId, CHART_SCALE_PT_PER_BAR, false)) {
            this.logger.error(__FUNCTION__, "ChartSetInteger CHART_SCALE_PT_PER_BAR failed");

            return false;
        }

        if (!ChartSetInteger(this.chartId, CHART_SCALEFIX, true)) {
            this.logger.error(__FUNCTION__, "ChartSetInteger CHART_SCALEFIX failed");

            return false;
        }

        // 現在レンジより下側へ大きく移動する場合は、下限から設定する。
        if (fromFixedMax <= currentMin) {
            if (!ChartSetDouble(this.chartId, CHART_FIXED_MIN, fromFixedMin)) {
                this.logger.error(__FUNCTION__, "ChartSetDouble CHART_FIXED_MIN failed");

                return false;
            }

            if (!ChartSetDouble(this.chartId, CHART_FIXED_MAX, fromFixedMax)) {
                this.logger.error(__FUNCTION__, "ChartSetDouble CHART_FIXED_MAX failed");

                return false;
            }
        } else {
            if (!ChartSetDouble(this.chartId, CHART_FIXED_MAX, fromFixedMax)) {
                this.logger.error(__FUNCTION__, "ChartSetDouble CHART_FIXED_MAX failed");

                return false;
            }

            if (!ChartSetDouble(this.chartId, CHART_FIXED_MIN, fromFixedMin)) {
                this.logger.error(__FUNCTION__, "ChartSetDouble CHART_FIXED_MIN failed");

                return false;
            }
        }

        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 前回更新後に表示範囲が変化したか判定する。
     *
     * @return 変化した場合true
     */
    bool isChartViewChanged() {
        int firstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR, 0);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS, 0);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        double priceMin = ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0);
        double priceMax = ChartGetDouble(this.chartId, CHART_PRICE_MAX, 0);

        if (firstVisibleBar != this.lastFirstVisibleBar
                || visibleBars != this.lastVisibleBars
                || chartHeight != this.lastChartHeight) {
            return true;
        }

        double tolerance = this.lastPoint;

        if (tolerance <= 0) {
            tolerance = 0.00000001;
        }

        if (MathAbs(priceMin - this.lastPriceMin) > tolerance
                || MathAbs(priceMax - this.lastPriceMax) > tolerance) {
            return true;
        }

        return false;
    }

    /**
     * 更新後のチャート表示状態を保存する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromFirstVisibleBar 左端表示バー
     * @param fromVisibleBars 表示バー数
     * @param fromChartHeight チャート高さ
     */
    void saveChartView(
            ElliotAll *fromElliotAll,
            int fromFirstVisibleBar,
            int fromVisibleBars,
            int fromChartHeight
    ) {
        this.lastFirstVisibleBar = fromFirstVisibleBar;
        this.lastVisibleBars = fromVisibleBars;
        this.lastChartHeight = fromChartHeight;
        this.lastPriceMin = ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0);
        this.lastPriceMax = ChartGetDouble(this.chartId, CHART_PRICE_MAX, 0);
        this.lastPoint = SymbolInfoDouble(fromElliotAll.marketContext.symbolName, SYMBOL_POINT);
    }

    /**
     * 保存しているチャート表示状態をクリアする。
     */
    void clearChartView() {
        this.lastFirstVisibleBar = -1;
        this.lastVisibleBars = -1;
        this.lastChartHeight = -1;
        this.lastPriceMin = 0;
        this.lastPriceMax = 0;
        this.lastPoint = 0;
    }
};

#endif
