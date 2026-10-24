//+------------------------------------------------------------------+
//|                        DrawCurrencyStrengthRankAndRibbon.mqh      |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_AND_RIBBON_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_AND_RIBBON_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankAndSignal.mqh>

/**
 * 長中期と中短期のAND成立区間をメインチャート下端へ描画する。
 * 既存の順位履歴線と同じチャート足頭のM5順位を使用する。
 */
class DrawCurrencyStrengthRankAndRibbon {
public:
    /**
     * 描画対象とインスタンス固有のオブジェクト名を保持する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix インスタンス識別子。
     */
    DrawCurrencyStrengthRankAndRibbon(
        const long fromChartId,
        const string fromObjectSuffix
    ) {
        this.chartId = fromChartId;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankAndRibbon_" + fromObjectSuffix;
        this.created = false;
        this.lastViewKey = "";
        this.canvasHeight = 34;
    }

    /**
     * このインスタンスのCanvasとオブジェクトを解放する。
     */
    ~DrawCurrencyStrengthRankAndRibbon() {
        this.clear();
    }

    /**
     * 表示中のチャート足に対応するAND帯を描画する。
     *
     * @param fromPoints M5時刻の昇順で保持した順位履歴。
     * @param fromTargetM5BarTime 使用可能なM5時刻の上限。
     * @param fromMinimumDifference 両期間に必要な順位差の絶対値。
     * @param fromForce 履歴更新時など、同じ表示範囲でも描き直す場合true。
     * @return 描画または変更なしの確認に成功した場合true。
     */
    bool draw(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const bool fromForce = false
    ) {
        int firstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS);
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS) - 60;
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        string symbolName = ChartSymbol(this.chartId);
        ENUM_TIMEFRAMES chartPeriod = ChartPeriod(this.chartId);
        datetime latestBarTime = iTime(symbolName, chartPeriod, 0);
        color backgroundColor = (color)ChartGetInteger(this.chartId, CHART_COLOR_BACKGROUND);
        color foregroundColor = (color)ChartGetInteger(this.chartId, CHART_COLOR_FOREGROUND);

        if (chartWidth < 180 || chartHeight < this.canvasHeight + 40
                || firstVisibleBar < 0 || visibleBars <= 0 || latestBarTime <= 0
                || fromTargetM5BarTime <= 0 || fromMinimumDifference < 1) {
            this.clear();

            return true;
        }

        string viewKey = StringFormat(
            "%s/%d/%d/%d/%d/%d/%I64d/%I64d/%d/%d/%d/%d/%d",
            symbolName, (int)chartPeriod, firstVisibleBar, visibleBars,
            chartWidth, chartHeight, (long)latestBarTime, (long)fromTargetM5BarTime,
            fromMinimumDifference, ArraySize(fromPoints), (int)backgroundColor,
            (int)foregroundColor, (int)ChartGetInteger(this.chartId, CHART_SCALE)
        );
        if (!fromForce && this.created && this.lastViewKey == viewKey
                && ObjectFind(this.chartId, this.objectName) == 0) {
            return true;
        }

        // 左端の直前足も取得し、画面の切れ目を成立開始として扱わない。
        int newestBar = (int)MathMax(0, firstVisibleBar - visibleBars + 1);
        int requestedBars = firstVisibleBar - newestBar + 2;
        datetime barTimes[];
        int copiedBars = CopyTime(symbolName, chartPeriod, newestBar, requestedBars, barTimes);
        if (copiedBars < 2) {
            this.clear();

            return false;
        }

        ArraySetAsSeries(barTimes, true);
        double referencePrice = (ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0)
            + ChartGetDouble(this.chartId, CHART_PRICE_MAX, 0)) / 2.0;
        int newestX = 0;
        int previousX = 0;
        int ignoredY = 0;
        if (!ChartTimePriceToXY(this.chartId, 0, barTimes[0], referencePrice, newestX, ignoredY)
                || !ChartTimePriceToXY(this.chartId, 0, barTimes[1], referencePrice,
                    previousX, ignoredY)) {
            this.clear();

            return false;
        }

        int barWidth = newestX - previousX;
        if (barWidth <= 0 || !this.prepareCanvas(chartWidth, chartHeight)) {
            this.clear();

            return false;
        }

        this.canvas.Erase(0);
        if (!this.canvas.FontSet("MS Gothic", -100)) {
            this.clear();

            return false;
        }

        this.canvas.TextOut(8, 1, "長中期 AND 中短期", ColorToARGB(foregroundColor));
        this.renderBars(fromPoints, barTimes, fromTargetM5BarTime, fromMinimumDifference,
            PeriodSeconds(chartPeriod), referencePrice, barWidth, chartWidth);
        this.canvas.Update(false);
        this.lastViewKey = viewKey;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * このインスタンスの帯だけを削除する。
     */
    void clear() {
        bool hadCanvas = this.created;
        this.canvas.Destroy();
        if (ObjectFind(this.chartId, this.objectName) >= 0) {
            ObjectDelete(this.chartId, this.objectName);
            hadCanvas = true;
        }

        this.created = false;
        this.lastViewKey = "";
        if (hadCanvas) {
            ChartRedraw(this.chartId);
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** このインスタンスのCanvasオブジェクト名。 */
    string objectName;

    /** AND帯用のCanvas。 */
    CCanvas canvas;

    /** Canvasを生成済みの場合true。 */
    bool created;

    /** 前回描画した表示範囲とデータ上限の識別子。 */
    string lastViewKey;

    /** タイトルと帯を含む描画高さ。 */
    int canvasHeight;

    /**
     * メインチャート下端にCanvasを作成または再配置する。
     */
    bool prepareCanvas(const int fromWidth, const int fromChartHeight) {
        if (this.created && ObjectFind(this.chartId, this.objectName) != 0) {
            this.clear();
        }

        // チャート下端にある既存の時刻ラベル用に32px空ける。
        int top = fromChartHeight - this.canvasHeight - 32;
        if (!this.created) {
            if (!this.canvas.CreateBitmapLabel(this.chartId, 0, this.objectName,
                    0, top, fromWidth, this.canvasHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
                return false;
            }

            this.created = true;
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_BACK, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTED, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ZORDER, 0);
            ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP,
                "長中期・中短期が同方向で順位差4以上。帯の左端の白色は確認できた成立開始。");
        } else if (this.canvas.Width() != fromWidth
                && !this.canvas.Resize(fromWidth, this.canvasHeight)) {
            return false;
        }

        return ObjectSetInteger(this.chartId, this.objectName, OBJPROP_YDISTANCE, top);
    }

    /**
     * 可視足を古い順に判定し、同じ方向の連続区間をまとめる。
     */
    void renderBars(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime &fromBarTimes[],
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const int fromPeriodSeconds,
        const double fromReferencePrice,
        const int fromBarWidth,
        const int fromCanvasWidth
    ) {
        int runDirection = 0;
        int runLeft = 0;
        int runRight = 0;
        int runStartX = -1;
        int previousDirection = 0;
        bool previousKnown = false;
        datetime previousTime = 0;

        for (int i = ArraySize(fromBarTimes) - 1; i >= 0; i--) {
            int pointX = 0;
            int ignoredY = 0;
            int direction = 0;
            bool known = this.getDirection(fromPoints, fromBarTimes[i],
                fromTargetM5BarTime, fromMinimumDifference, direction);
            bool positionKnown = ChartTimePriceToXY(this.chartId, 0, fromBarTimes[i],
                fromReferencePrice, pointX, ignoredY);
            int left = pointX - fromBarWidth / 2;
            int right = left + fromBarWidth - 1;
            bool timeContinuous = previousTime > 0
                && fromBarTimes[i] - previousTime == fromPeriodSeconds;
            if (!timeContinuous) {
                previousKnown = false;
            }

            if (runDirection != 0 && (!known || !positionKnown || !timeContinuous
                    || direction != runDirection || left > runRight + 1)) {
                this.drawRun(runDirection, runLeft, runRight, runStartX, fromCanvasWidth);
                runDirection = 0;
            }

            if (known && positionKnown && direction != 0) {
                if (runDirection == 0) {
                    runDirection = direction;
                    runLeft = left;
                    runStartX = -1;
                    if (previousKnown && previousDirection != direction) {
                        runStartX = pointX;
                    }
                }

                runRight = right;
            }

            previousDirection = direction;
            previousKnown = known && positionKnown;
            previousTime = fromBarTimes[i];
        }

        if (runDirection != 0) {
            this.drawRun(runDirection, runLeft, runRight, runStartX, fromCanvasWidth);
        }
    }

    /**
     * 足頭に一致する有効なM5順位から方向を取得する。欠損はfalse。
     */
    bool getDirection(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromBarTime,
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        int &fromDirection
    ) {
        fromDirection = 0;
        int m5Seconds = PeriodSeconds(PERIOD_M5);
        datetime pointTime = (datetime)((long)fromBarTime - (long)fromBarTime % m5Seconds);
        if (pointTime <= 0 || pointTime > fromTargetM5BarTime) {
            return false;
        }

        int left = 0;
        int right = ArraySize(fromPoints) - 1;
        while (left <= right) {
            int middle = left + (right - left) / 2;
            if (fromPoints[middle].m5BarTime == pointTime) {
                CurrencyStrengthPairRankPoint point = fromPoints[middle];
                if (point.baseLongMediumTermAverageRank < 1 || point.baseLongMediumTermAverageRank > 8
                        || point.quoteLongMediumTermAverageRank < 1 || point.quoteLongMediumTermAverageRank > 8
                        || point.baseMediumShortTermAverageRank < 1 || point.baseMediumShortTermAverageRank > 8
                        || point.quoteMediumShortTermAverageRank < 1 || point.quoteMediumShortTermAverageRank > 8) {
                    return false;
                }

                fromDirection = CurrencyStrengthRankAndSignal::getDirection(point, fromMinimumDifference);

                return true;
            }

            if (fromPoints[middle].m5BarTime < pointTime) {
                left = middle + 1;
            } else {
                right = middle - 1;
            }
        }

        return false;
    }

    /**
     * 1つの成立区間を描画し、確認できた成立開始の左端だけ白くする。
     */
    void drawRun(const int fromDirection, const int fromLeft, const int fromRight,
            const int fromStartX, const int fromCanvasWidth) {
        int left = (int)MathMax(0, fromLeft);
        int right = (int)MathMin(fromCanvasWidth - 1, fromRight);
        if (right < left) {
            return;
        }

        color signalColor = clrAqua;
        string signalText = "BUY";
        if (fromDirection < 0) {
            signalColor = clrHotPink;
            signalText = "SELL";
        }

        uint drawColor = ColorToARGB(signalColor);
        this.canvas.FillRectangle(left, 20, right, 29, drawColor);
        if (fromStartX >= 0 && fromLeft >= 0 && fromLeft < fromCanvasWidth) {
            int startRight = (int)MathMin(right, fromLeft + 1);
            this.canvas.FillRectangle(fromLeft, 20, startRight, 29, ColorToARGB(clrWhite));
        }

        this.canvas.FontSet("MS Gothic", -80);
        int textWidth = this.canvas.TextWidth(signalText);
        if (right - left >= textWidth + 18) {
            this.canvas.TextOut(left + (right - left - textWidth) / 2, 19,
                signalText, ColorToARGB(clrBlack));
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_AND_RIBBON_MQH
