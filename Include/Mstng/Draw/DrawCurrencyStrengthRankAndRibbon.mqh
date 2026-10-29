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
#include <Mstng\Draw\ChartRedrawRequest.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankAndSignal.mqh>

/**
 * H1未満は長中期と中短期の準備・成立、H1以上は長中期の成立区間を下端へ描画する。
 * 既存の順位履歴線と同じチャート足頭のM5順位を使用する。
 */
class DrawCurrencyStrengthRankAndRibbon {
public:
    /**
     * 描画対象とインスタンス固有のオブジェクト名を保持する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix インスタンス識別子。
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は従来どおり即時に要求する。
     */
    DrawCurrencyStrengthRankAndRibbon(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankAndRibbon_" + fromObjectSuffix;
        this.created = false;
        this.cleared = false;
        this.lastViewKey = "";
        this.lastTop = -1;
        this.lastTooltip = "";
        this.canvasHeight = 34;
    }

    /**
     * このインスタンスのCanvasとオブジェクトを解放する。
     */
    ~DrawCurrencyStrengthRankAndRibbon() {
        this.clear();
    }

    /**
     * 表示中のチャート足に対応する通貨強弱の準備・成立帯を描画する。
     *
     * @param fromPoints M5時刻の昇順で保持した順位履歴。
     * @param fromTargetM5BarTime 使用可能なM5時刻の上限。
     * @param fromMinimumDifference 準備・成立の基準となる順位差の絶対値。
     * @param fromForce 履歴更新時など、同じ表示範囲でも描き直す場合true。
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     * @return 描画または変更なしの確認に成功した場合true。
     */
    bool draw(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const bool fromForce = false,
        const int fromPointStartIndex = 0
    ) {
        int pointCount = ArraySize(fromPoints);
        if (fromPointStartIndex < 0 || fromPointStartIndex > pointCount) {
            this.clear();

            return false;
        }

        int activePointCount = pointCount - fromPointStartIndex;
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
            "%s/%d/%d/%d/%d/%d/%I64d/%I64d/%d/%d/%d/%d/%d/%d",
            symbolName, (int)chartPeriod, firstVisibleBar, visibleBars,
            chartWidth, chartHeight, (long)latestBarTime, (long)fromTargetM5BarTime,
            fromMinimumDifference, activePointCount, fromPointStartIndex, (int)backgroundColor,
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

        int periodSeconds = PeriodSeconds(chartPeriod);
        bool longMediumOnly = periodSeconds >= PeriodSeconds(PERIOD_H1);
        string periodTitle = "長中期・中短期 準備/成立";
        string tooltip = "両期間が同方向：片方だけ順位差" + (string)fromMinimumDifference
            + "以上は暗い準備色、両方は明るい成立色。";
        if (longMediumOnly) {
            periodTitle = "長中期";
            tooltip = "長中期：順位差" + (string)fromMinimumDifference + "以上。";
        }

        tooltip += "帯の左端の白色は確認できた開始。準備・成立の切り替え時には追加しません。";
        this.canvas.TextOut(8, 1, periodTitle, ColorToARGB(foregroundColor));
        if (this.lastTooltip != tooltip) {
            if (!ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, tooltip)) {
                this.clear();

                return false;
            }

            this.lastTooltip = tooltip;
        }

        if (!this.canvas.FontSet("MS Gothic", -80)) {
            this.clear();

            return false;
        }

        int buyTextWidth = this.canvas.TextWidth("BUY");
        int sellTextWidth = this.canvas.TextWidth("SELL");
        if (buyTextWidth <= 0 || sellTextWidth <= 0) {
            this.clear();

            return false;
        }

        this.renderBars(fromPoints, barTimes, fromTargetM5BarTime, fromMinimumDifference,
            periodSeconds, longMediumOnly, newestX, barWidth, chartWidth,
            buyTextWidth, sellTextWidth, fromPointStartIndex);
        this.canvas.Update(false);
        this.lastViewKey = viewKey;

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

        return true;
    }

    /**
     * このインスタンスの帯だけを削除する。
     * オブジェクトの不在を確認済みの場合は、再作成を試すまで探索と解放を省く。
     */
    void clear() {
        if (this.cleared) {
            return;
        }

        bool hadCanvas = this.created;
        this.canvas.Destroy();
        this.cleared = ObjectFind(this.chartId, this.objectName) < 0;
        if (!this.cleared) {
            ObjectDelete(this.chartId, this.objectName);
            hadCanvas = true;
        }

        this.created = false;
        this.lastViewKey = "";
        this.lastTop = -1;
        this.lastTooltip = "";
        if (hadCanvas) {
            if (this.redrawRequest != NULL) {
                this.redrawRequest.request();
            } else {
                ChartRedraw(this.chartId);
            }
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。NULLの場合は即時要求。 */
    ChartRedrawRequest *redrawRequest;

    /** このインスタンスのCanvasオブジェクト名。 */
    string objectName;

    /** 通貨強弱帯用のCanvas。 */
    CCanvas canvas;

    /** Canvasを生成済みの場合true。 */
    bool created;

    /** Canvas解放後にオブジェクトの不在を確認済みの場合true。 */
    bool cleared;

    /** 前回描画した表示範囲とデータ上限の識別子。 */
    string lastViewKey;

    /** 前回設定に成功した帯のY座標。未設定の場合は-1。 */
    int lastTop;

    /** 前回設定に成功した帯の説明文。 */
    string lastTooltip;

    /** タイトルと帯を含む描画高さ。 */
    int canvasHeight;

    /**
     * メインチャート下端にCanvasを作成または再配置する。
     * 設定済みのY座標が変わらない場合は再設定を省く。
     */
    bool prepareCanvas(const int fromWidth, const int fromChartHeight) {
        if (this.created && ObjectFind(this.chartId, this.objectName) != 0) {
            this.clear();
        }

        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        // チャート下端にある既存の時刻ラベル用に32px空ける。
        int top = fromChartHeight - this.canvasHeight - 32;
        if (!this.created) {
            this.cleared = false;
            this.lastTop = -1;
            this.lastTooltip = "";
            if (!this.canvas.CreateBitmapLabel(this.chartId, 0, this.objectName,
                    0, top, fromWidth, this.canvasHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
                return false;
            }

            this.created = true;
            this.lastTop = top;
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_BACK, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTED, false);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ZORDER, 0);
        } else if (this.canvas.Width() != fromWidth
                && !this.canvas.Resize(fromWidth, this.canvasHeight)) {
            return false;
        }

        if (this.lastTop != top) {
            if (!ObjectSetInteger(this.chartId, this.objectName, OBJPROP_YDISTANCE, top)) {
                return false;
            }

            this.lastTop = top;
        }

        return true;
    }

    /**
     * 可視足を古い順に判定し、同じ準備・成立状態の連続区間をまとめる。
     * series配列の足番号と共通の足幅から座標を求め、足ごとの座標変換を省く。
     * BUY/SELLの文字幅は描画開始時の計測値を全区間で共用する。
     * 同じM5時刻の順位検索と判定は、この描画内でだけ結果を再利用する。
     * 色が変わっても同方向なら開始の白色を追加しない。
     *
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     */
    void renderBars(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime &fromBarTimes[],
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const int fromPeriodSeconds,
        const bool fromLongMediumOnly,
        const int fromNewestX,
        const int fromBarWidth,
        const int fromCanvasWidth,
        const int fromBuyTextWidth,
        const int fromSellTextWidth,
        const int fromPointStartIndex
    ) {
        int runState = 0;
        int runLeft = 0;
        int runRight = 0;
        int runStartX = -1;
        int previousDirection = 0;
        bool previousKnown = false;
        datetime previousTime = 0;

        int m5Seconds = PeriodSeconds(PERIOD_M5);
        bool signalCached = false;
        datetime cachedM5BarTime = 0;
        bool cachedKnown = false;
        int cachedState = 0;

        for (int i = ArraySize(fromBarTimes) - 1; i >= 0; i--) {
            // 週末や欠損があっても、時間差ではなく取得した足の並びで位置を求める。
            int pointX = fromNewestX - i * fromBarWidth;
            datetime pointM5BarTime = (datetime)((long)fromBarTimes[i]
                - (long)fromBarTimes[i] % m5Seconds);
            if (!signalCached || cachedM5BarTime != pointM5BarTime) {
                cachedKnown = this.getSignalState(fromPoints, pointM5BarTime,
                    fromTargetM5BarTime, fromMinimumDifference, fromLongMediumOnly,
                    cachedState, fromPointStartIndex);
                cachedM5BarTime = pointM5BarTime;
                signalCached = true;
            }

            int state = cachedState;
            bool known = cachedKnown;
            int direction = 0;
            if (state > 0) {
                direction = 1;
            } else if (state < 0) {
                direction = -1;
            }

            int left = pointX - fromBarWidth / 2;
            int right = left + fromBarWidth - 1;
            bool timeContinuous = previousTime > 0
                && fromBarTimes[i] - previousTime == fromPeriodSeconds;
            if (!timeContinuous) {
                previousKnown = false;
            }

            if (runState != 0 && (!known || !timeContinuous
                    || state != runState || left > runRight + 1)) {
                this.drawRun(runState, runLeft, runRight, runStartX, fromCanvasWidth,
                    fromBuyTextWidth, fromSellTextWidth);
                runState = 0;
            }

            if (known && state != 0) {
                if (runState == 0) {
                    runState = state;
                    runLeft = left;
                    runStartX = -1;
                    if (previousKnown && previousDirection != direction) {
                        runStartX = pointX;
                    }
                }

                runRight = right;
            }

            previousDirection = direction;
            previousKnown = known;
            previousTime = fromBarTimes[i];
        }

        if (runState != 0) {
            this.drawRun(runState, runLeft, runRight, runStartX, fromCanvasWidth,
                fromBuyTextWidth, fromSellTextWidth);
        }
    }

    /**
     * 指定M5時刻に一致する有効な順位から準備・成立状態を取得する。欠損はfalse。
     * 呼び出し元でチャート足の開始時刻をM5境界へ切り下げて渡す。
     *
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     */
    bool getSignalState(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromM5BarTime,
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const bool fromLongMediumOnly,
        int &fromState,
        const int fromPointStartIndex
    ) {
        fromState = 0;
        if (fromM5BarTime <= 0 || fromM5BarTime > fromTargetM5BarTime) {
            return false;
        }

        int left = fromPointStartIndex;
        int right = ArraySize(fromPoints) - 1;
        while (left <= right) {
            int middle = left + (right - left) / 2;
            if (fromPoints[middle].m5BarTime == fromM5BarTime) {
                if (fromPoints[middle].baseLongMediumTermAverageRank < 1
                        || fromPoints[middle].baseLongMediumTermAverageRank > 8
                        || fromPoints[middle].quoteLongMediumTermAverageRank < 1
                        || fromPoints[middle].quoteLongMediumTermAverageRank > 8) {
                    return false;
                }

                if (!fromLongMediumOnly && (fromPoints[middle].baseMediumShortTermAverageRank < 1
                        || fromPoints[middle].baseMediumShortTermAverageRank > 8
                        || fromPoints[middle].quoteMediumShortTermAverageRank < 1
                        || fromPoints[middle].quoteMediumShortTermAverageRank > 8)) {
                    return false;
                }

                fromState = CurrencyStrengthRankAndSignal::getRibbonState(
                    fromPoints[middle], fromMinimumDifference, fromLongMediumOnly);

                return true;
            }

            if (fromPoints[middle].m5BarTime < fromM5BarTime) {
                left = middle + 1;
            } else {
                right = middle - 1;
            }
        }

        return false;
    }

    /**
     * 同じ準備・成立色の区間を描画し、確認できた帯の開始の左端だけ白くする。
     * 事前に計測した文字幅で、表示可否と中央配置を決める。
     */
    void drawRun(const int fromState, const int fromLeft, const int fromRight,
            const int fromStartX, const int fromCanvasWidth,
            const int fromBuyTextWidth, const int fromSellTextWidth) {
        int left = (int)MathMax(0, fromLeft);
        int right = (int)MathMin(fromCanvasWidth - 1, fromRight);
        if (right < left) {
            return;
        }

        color signalColor = clrAqua;
        string signalText = "BUY";
        int textWidth = fromBuyTextWidth;
        if (fromState < 0) {
            signalColor = clrHotPink;
            signalText = "SELL";
            textWidth = fromSellTextWidth;
        }

        color textColor = clrBlack;
        if (MathAbs(fromState) == 1) {
            signalColor = clrTeal;
            if (fromState < 0) {
                signalColor = C'128,50,90';
            }

            textColor = clrWhite;
        }

        uint drawColor = ColorToARGB(signalColor);
        this.canvas.FillRectangle(left, 20, right, 29, drawColor);
        if (fromStartX >= 0 && fromLeft >= 0 && fromLeft < fromCanvasWidth) {
            int startRight = (int)MathMin(right, fromLeft + 1);
            this.canvas.FillRectangle(fromLeft, 20, startRight, 29, ColorToARGB(clrWhite));
        }

        if (right - left >= textWidth + 18) {
            this.canvas.TextOut(left + (right - left - textWidth) / 2, 19,
                signalText, ColorToARGB(textColor));
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_AND_RIBBON_MQH
