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
        this.lastRenderKey = "";
        this.dataDirty = true;
        this.lastStartM5BarTime = 0;
        this.lastEndM5BarTime = 0;
        this.lastTargetM5BarTime = 0;
        this.lastTop = -1;
        this.lastTooltip = "";
        this.standardTooltip = "";
        this.mousePositionKnown = false;
        this.lastMouseX = 0;
        this.lastMouseY = 0;
        this.hoverBaseCurrency = "";
        this.hoverQuoteCurrency = "";
        this.hoverBarIndex = -1;
        this.hoverReady = false;
        this.renderedMinimumDifference = 0;
        this.renderedChartPeriod = PERIOD_CURRENT;
        this.renderedLongMediumOnly = false;
        this.cachedBuyTextWidth = 0;
        this.cachedSellTextWidth = 0;
        this.canvasHeight = 34;
        ArraySetAsSeries(this.barTimes, false);
        this.invalidateViewCache();
    }

    /**
     * このインスタンスのCanvas・オブジェクト・足時刻の作業配列を解放する。
     */
    ~DrawCurrencyStrengthRankAndRibbon() {
        this.clear();
        ArrayFree(this.barTimes);
    }

    /**
     * 変更された履歴範囲が前回描画の参照範囲と重なる場合、次の描画を更新待ちにする。
     * 参照範囲には、帯の開始判定に使う可視範囲の左隣1足も含める。
     *
     * @param fromStartM5BarTime 変更範囲の開始M5時刻。
     * @param fromEndM5BarTime 変更範囲の終了M5時刻。
     */
    void invalidateDataRange(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime
    ) {
        if (fromStartM5BarTime <= 0 || fromEndM5BarTime < fromStartM5BarTime
                || this.lastStartM5BarTime <= 0
                || this.lastEndM5BarTime < this.lastStartM5BarTime) {
            this.dataDirty = true;

            return;
        }

        if (fromStartM5BarTime <= this.lastEndM5BarTime
                && fromEndM5BarTime >= this.lastStartM5BarTime) {
            this.dataDirty = true;
        }
    }

    /**
     * 画面変更時に足時刻と横座標の再利用を無効化する。
     * 作業配列のメモリと描画済みの帯は保持する。
     */
    void invalidateViewCache() {
        this.barGeometryKey = "";
        this.cachedBarCount = 0;
        this.cachedNewestX = 0;
        this.cachedBarWidth = 0;
        this.renderedBarCount = 0;
        this.renderedNewestX = 0;
        this.renderedBarWidth = 0;
        this.renderedCanvasWidth = 0;
        this.invalidateHoverData();
    }

    /**
     * 順位履歴の変更後、同じ表示足でもマウス位置の説明を再評価する。
     * 足時刻と描画済み画像は保持し、順位配列への参照は保存しない。
     */
    void invalidateHoverData() {
        this.hoverReady = false;
    }

    /**
     * 帯の実矩形内では該当するチャート足の順位と判定理由を表示する。
     * 同じ足の説明を設定済みなら順位の検索と文字列生成を省く。
     *
     * @param fromX チャート左端からのマウスX座標。
     * @param fromY チャート上端からのマウスY座標。
     * @param fromPoints M5時刻の昇順で保持した順位履歴。
     * @param fromBaseCurrency 基軸通貨名。
     * @param fromQuoteCurrency 決済通貨名。
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     * @return 説明の設定または変更なしの確認に成功した場合true。
     */
    bool handleMouseMove(const int fromX, const int fromY,
            const CurrencyStrengthPairRankPoint &fromPoints[],
            const string fromBaseCurrency, const string fromQuoteCurrency,
            const int fromPointStartIndex = 0) {
        this.lastMouseX = fromX;
        this.lastMouseY = fromY;
        this.mousePositionKnown = true;
        if (this.hoverBaseCurrency != fromBaseCurrency
                || this.hoverQuoteCurrency != fromQuoteCurrency) {
            this.hoverBaseCurrency = fromBaseCurrency;
            this.hoverQuoteCurrency = fromQuoteCurrency;
            this.invalidateHoverData();
        }

        return this.refreshHoverTooltip(fromPoints, fromPointStartIndex);
    }

    /**
     * 表示中のチャート足に対応する通貨強弱の準備・成立帯を描画する。
     *
     * @param fromPoints M5時刻の昇順で保持した順位履歴。
     * @param fromTargetM5BarTime 使用可能なM5時刻の上限。
     * @param fromMinimumDifference 準備・成立の基準となる順位差の絶対値。
     * @param fromForce 全再構築時など、同じ表示範囲でも描き直す場合true。
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

        int firstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS);
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS) - 60;
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        string symbolName = ChartSymbol(this.chartId);
        ENUM_TIMEFRAMES chartPeriod = ChartPeriod(this.chartId);
        datetime latestBarTime = iTime(symbolName, chartPeriod, 0);
        color backgroundColor = (color)ChartGetInteger(this.chartId, CHART_COLOR_BACKGROUND);
        color foregroundColor = (color)ChartGetInteger(this.chartId, CHART_COLOR_FOREGROUND);
        int chartScale = (int)ChartGetInteger(this.chartId, CHART_SCALE);

        if (chartWidth < 180 || chartHeight < this.canvasHeight + 40
                || firstVisibleBar < 0 || visibleBars <= 0 || latestBarTime <= 0
                || fromTargetM5BarTime <= 0 || fromMinimumDifference < 1) {
            this.clear();

            return true;
        }

        string viewKey = StringFormat(
            "%s/%d/%d/%d/%d/%d/%I64d/%d/%d/%d/%d",
            symbolName, (int)chartPeriod, firstVisibleBar, visibleBars,
            chartWidth, chartHeight, (long)latestBarTime,
            fromMinimumDifference, (int)backgroundColor, (int)foregroundColor, chartScale
        );
        if (this.lastTargetM5BarTime != fromTargetM5BarTime) {
            this.invalidateHoverData();
        }

        bool targetChangedInView = this.isTargetChangeVisible(fromTargetM5BarTime);
        if (!fromForce && !this.dataDirty && !targetChangedInView
                && this.created && this.lastViewKey == viewKey
                && this.renderedBarCount >= 2
                && ObjectFind(this.chartId, this.objectName) == 0) {
            this.lastTargetM5BarTime = fromTargetM5BarTime;

            return this.refreshHoverTooltip(fromPoints, fromPointStartIndex);
        }

        string nextBarGeometryKey = this.getBarGeometryKey(viewKey);
        bool reuseBarGeometry = !fromForce && this.created
            && nextBarGeometryKey != "" && this.barGeometryKey == nextBarGeometryKey
            && this.cachedBarCount >= 2 && ArraySize(this.barTimes) >= this.cachedBarCount;
        int copiedBars = this.cachedBarCount;
        int newestX = this.cachedNewestX;
        int barWidth = this.cachedBarWidth;
        if (!reuseBarGeometry) {
            // CopyTimeが作業配列を書き換える前に、以前の件数と座標を無効にする。
            this.invalidateViewCache();

            // 左端の直前足も取得し、画面の切れ目を成立開始として扱わない。
            int newestBar = (int)MathMax(0, firstVisibleBar - visibleBars + 1);
            int requestedBars = firstVisibleBar - newestBar + 2;
            copiedBars = CopyTime(
                symbolName, chartPeriod, newestBar, requestedBars, this.barTimes);
            if (copiedBars < 2) {
                this.clear();

                return false;
            }

            // CopyTimeは物理先頭から古い順に格納するため、取得件数から最新位置を求める。
            datetime newestTime = this.barTimes[copiedBars - 1];
            datetime previousTime = this.barTimes[copiedBars - 2];
            double referencePrice = (ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0)
                + ChartGetDouble(this.chartId, CHART_PRICE_MAX, 0)) / 2.0;
            int previousX = 0;
            int ignoredY = 0;
            if (!ChartTimePriceToXY(this.chartId, 0, newestTime, referencePrice, newestX, ignoredY)
                    || !ChartTimePriceToXY(this.chartId, 0, previousTime, referencePrice,
                        previousX, ignoredY)) {
                this.clear();

                return false;
            }

            barWidth = newestX - previousX;
            if (barWidth <= 0) {
                this.clear();

                return false;
            }

            // 部分取得した足時刻は当回の描画だけに使用し、次回の再描画では取り直す。
            if (copiedBars == requestedBars && nextBarGeometryKey != "") {
                this.barGeometryKey = nextBarGeometryKey;
                this.cachedBarCount = copiedBars;
                this.cachedNewestX = newestX;
                this.cachedBarWidth = barWidth;
            }
        }

        datetime newestBarTime = this.barTimes[copiedBars - 1];
        datetime oldestBarTime = this.barTimes[0];
        int m5Seconds = PeriodSeconds(PERIOD_M5);
        if (barWidth <= 0 || m5Seconds <= 0) {
            this.clear();

            return false;
        }

        // 画像内容の比較から画面の高さを除き、高さだけの変更はY座標へ反映する。
        string renderKey = StringFormat(
            "%s/%d/%d/%d/%d/%d/%d/%d/%I64d/%I64d/%d/%d",
            symbolName, (int)chartPeriod, chartWidth,
            fromMinimumDifference, (int)backgroundColor, (int)foregroundColor, chartScale,
            copiedBars, (long)newestBarTime, (long)oldestBarTime, newestX, barWidth
        );
        if (!fromForce && !this.dataDirty && !targetChangedInView
                && this.created && this.lastRenderKey == renderKey
                && ObjectFind(this.chartId, this.objectName) == 0) {
            int previousTop = this.lastTop;
            if (!this.moveCanvas(chartHeight)) {
                this.clear();

                return false;
            }

            if (this.lastTop != previousTop) {
                if (this.redrawRequest != NULL) {
                    this.redrawRequest.request();
                } else {
                    ChartRedraw(this.chartId);
                }
            }

            this.lastViewKey = viewKey;
            this.lastTargetM5BarTime = fromTargetM5BarTime;
            this.rememberRenderedGeometry(copiedBars, newestX, barWidth,
                chartWidth, chartPeriod, fromMinimumDifference);

            return this.refreshHoverTooltip(fromPoints, fromPointStartIndex);
        }

        if (!this.prepareCanvas(chartWidth, chartHeight)) {
            this.clear();

            return false;
        }

        this.canvas.Erase(0);
        if (!this.canvas.FontSet("MS Gothic", -100)) {
            this.clear();

            return false;
        }

        int periodSeconds = PeriodSeconds(chartPeriod);
        bool longMediumOnly = CurrencyStrengthRankAndSignal::isLongMediumOnlyChartPeriod(chartPeriod);
        string periodTitle = "長中期・中短期 準備/成立";
        string tooltip = "両期間が同方向：長中期・中短期はそれぞれ順位差" + (string)fromMinimumDifference
            + "以上またはBUY基軸1位/決済8位・SELL基軸8位/決済1位。"
            + "片方だけ達成は暗い準備色、両方は明るい成立色。";
        if (chartPeriod == PERIOD_M15) {
            periodTitle = "長中期 差2以上or端順位 / 中短期は参考";
            tooltip = "M15：長中期の順位差2以上、または買う通貨が1位、または売る通貨が8位で成立。"
                + "同順位は対象外。中短期は参考表示で判定しません。"
                + "準備は設けず、成立色だけを表示。";
        } else if (longMediumOnly) {
            periodTitle = "長中期";
            tooltip = "長中期：順位差" + (string)fromMinimumDifference
                + "以上、または強い通貨が1位、または弱い通貨が8位。"
                + "同順位は対象外。中短期は判定せず、成立色だけを表示。";
        }

        tooltip += "帯の左端の白色は確認できた開始。";
        if (chartPeriod != PERIOD_M15) {
            tooltip += "準備・成立の切り替え時には追加しません。";
        }

        this.canvas.TextOut(8, 1, periodTitle, ColorToARGB(foregroundColor));
        this.standardTooltip = tooltip;

        if (!this.canvas.FontSet("MS Gothic", -80)) {
            this.clear();

            return false;
        }

        if (this.cachedBuyTextWidth <= 0 || this.cachedSellTextWidth <= 0) {
            int buyTextWidth = this.canvas.TextWidth("BUY");
            int sellTextWidth = this.canvas.TextWidth("SELL");
            if (buyTextWidth <= 0 || sellTextWidth <= 0) {
                this.clear();

                return false;
            }

            this.cachedBuyTextWidth = buyTextWidth;
            this.cachedSellTextWidth = sellTextWidth;
        }

        this.renderBars(fromPoints, this.barTimes, copiedBars,
            fromTargetM5BarTime, fromMinimumDifference,
            periodSeconds, chartPeriod, newestX, barWidth, chartWidth,
            this.cachedBuyTextWidth, this.cachedSellTextWidth, fromPointStartIndex);
        this.canvas.Update(false);
        this.lastViewKey = viewKey;
        this.lastRenderKey = renderKey;
        this.lastStartM5BarTime = (datetime)((long)oldestBarTime
            - (long)oldestBarTime % m5Seconds);
        this.lastEndM5BarTime = (datetime)((long)newestBarTime
            - (long)newestBarTime % m5Seconds);
        this.lastTargetM5BarTime = fromTargetM5BarTime;
        this.dataDirty = false;
        this.rememberRenderedGeometry(copiedBars, newestX, barWidth,
            chartWidth, chartPeriod, fromMinimumDifference);

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

        return this.refreshHoverTooltip(fromPoints, fromPointStartIndex);
    }

    /**
     * このインスタンスの帯だけを削除する。
     * オブジェクトの不在を確認済みの場合は、再作成を試すまで探索と解放を省く。
     * 足時刻の作業配列は次の描画で再利用するため保持する。
     */
    void clear() {
        this.invalidateViewCache();
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
        this.lastRenderKey = "";
        this.dataDirty = true;
        this.lastStartM5BarTime = 0;
        this.lastEndM5BarTime = 0;
        this.lastTargetM5BarTime = 0;
        this.lastTop = -1;
        this.lastTooltip = "";
        this.standardTooltip = "";
        this.cachedBuyTextWidth = 0;
        this.cachedSellTextWidth = 0;

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

    /** CopyTimeの取得先として再利用する足時刻の作業配列。物理先頭から古い順。 */
    datetime barTimes[];

    /** 足時刻と横座標を再利用できる画面条件。再利用できない場合は空。 */
    string barGeometryKey;

    /** 必要本数を取得できた足時刻配列の有効件数。 */
    int cachedBarCount;

    /** 足時刻配列の最新足に対応するX座標。 */
    int cachedNewestX;

    /** 足時刻配列の最新2足から求めた横方向の足幅。 */
    int cachedBarWidth;

    /** Canvasを生成済みの場合true。 */
    bool created;

    /** Canvas解放後にオブジェクトの不在を確認済みの場合true。 */
    bool cleared;

    /** 前回確認した画面設定と足番号の識別子。 */
    string lastViewKey;

    /** 前回描画した参照足・座標・配色の識別子。 */
    string lastRenderKey;

    /** 前回描画の参照範囲内に履歴変更があり、描き直しが必要な場合true。 */
    bool dataDirty;

    /** 前回描画で参照した最古のM5時刻。可視範囲の左隣1足を含む。 */
    datetime lastStartM5BarTime;

    /** 前回描画で参照した最新のM5時刻。 */
    datetime lastEndM5BarTime;

    /** 前回描画または変更なしの確認に成功した使用可能M5時刻の上限。 */
    datetime lastTargetM5BarTime;

    /** 前回設定に成功した帯のY座標。未設定の場合は-1。 */
    int lastTop;

    /** 前回設定に成功した帯の説明文。 */
    string lastTooltip;

    /** 帯の外・タイトル・右余白で表示する標準説明。 */
    string standardTooltip;

    /** 実際に描画した足時刻の件数。部分取得時も有効な描画件数を保持する。 */
    int renderedBarCount;

    /** 描画済み最新足のX座標。 */
    int renderedNewestX;

    /** 描画済みの横方向の足幅。 */
    int renderedBarWidth;

    /** 描画済みCanvasの横幅。 */
    int renderedCanvasWidth;

    /** 描画済み帯の順位差基準。 */
    int renderedMinimumDifference;

    /** 描画済み帯のチャート時間足。 */
    ENUM_TIMEFRAMES renderedChartPeriod;

    /** 描画済み帯が長中期だけで判定する場合true。 */
    bool renderedLongMediumOnly;

    /** 最後のマウス位置を受け取っている場合true。 */
    bool mousePositionKnown;

    /** 最後に通知されたマウスX座標。 */
    int lastMouseX;

    /** 最後に通知されたマウスY座標。 */
    int lastMouseY;

    /** マウス説明で表示する基軸通貨名。 */
    string hoverBaseCurrency;

    /** マウス説明で表示する決済通貨名。 */
    string hoverQuoteCurrency;

    /** 説明を最後に設定した足配列位置。帯の外では-1。 */
    int hoverBarIndex;

    /** 現在の順位とマウス位置に対応する説明を正常に設定済みの場合true。 */
    bool hoverReady;

    /** 帯の固定フォントMS Gothic・-80で計測したBUYの幅。未計測の場合は0。 */
    int cachedBuyTextWidth;

    /** 帯の固定フォントMS Gothic・-80で計測したSELLの幅。未計測の場合は0。 */
    int cachedSellTextWidth;

    /** タイトルと帯を含む描画高さ。 */
    int canvasHeight;

    /**
     * 成功した描画の座標と判定条件をマウス説明用に保持する。
     * CopyTimeの次回再利用可否とは分離し、部分取得した配列にも対応する。
     */
    void rememberRenderedGeometry(const int fromBarCount, const int fromNewestX,
            const int fromBarWidth, const int fromCanvasWidth,
            const ENUM_TIMEFRAMES fromChartPeriod, const int fromMinimumDifference) {
        this.renderedBarCount = fromBarCount;
        this.renderedNewestX = fromNewestX;
        this.renderedBarWidth = fromBarWidth;
        this.renderedCanvasWidth = fromCanvasWidth;
        this.renderedChartPeriod = fromChartPeriod;
        this.renderedMinimumDifference = fromMinimumDifference;
        this.renderedLongMediumOnly =
            CurrencyStrengthRankAndSignal::isLongMediumOnlyChartPeriod(fromChartPeriod);
        this.invalidateHoverData();
    }

    /**
     * 描画時と同じセル境界からマウス位置に対応する足配列位置を取得する。
     *
     * @return 帯の実矩形内にある足の配列位置。それ以外は-1。
     */
    int getHoveredBarIndex() {
        if (!this.mousePositionKnown || !this.created || this.lastTop < 0
                || this.renderedBarCount < 2 || this.renderedBarWidth <= 0
                || ArraySize(this.barTimes) < this.renderedBarCount
                || this.lastMouseX < 0 || this.lastMouseX >= this.renderedCanvasWidth
                || this.lastMouseY < this.lastTop + 20
                || this.lastMouseY > this.lastTop + 29) {
            return -1;
        }

        long firstLeft = (long)this.renderedNewestX
            - (long)(this.renderedBarCount - 1) * this.renderedBarWidth
            - this.renderedBarWidth / 2;
        long relativeX = (long)this.lastMouseX - firstLeft;
        if (relativeX < 0) {
            return -1;
        }

        long barIndex = relativeX / this.renderedBarWidth;
        if (barIndex >= this.renderedBarCount) {
            return -1;
        }

        return (int)barIndex;
    }

    /**
     * 最後のマウス位置の説明を、現在渡された順位配列から更新する。
     * 説明の更新ではCanvasの再描画や再描画要求を発生させない。
     */
    bool refreshHoverTooltip(const CurrencyStrengthPairRankPoint &fromPoints[],
            const int fromPointStartIndex) {
        if (!this.created) {
            return false;
        }

        int barIndex = this.getHoveredBarIndex();
        if (this.hoverReady && this.hoverBarIndex == barIndex) {
            return true;
        }

        string tooltip = this.standardTooltip;
        if (barIndex >= 0) {
            tooltip = this.getBarTooltip(fromPoints, barIndex, fromPointStartIndex);
        }

        if (tooltip == "") {
            tooltip = "\n";
        }

        this.hoverReady = false;
        if (this.lastTooltip != tooltip) {
            if (!ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, tooltip)) {
                return false;
            }

            this.lastTooltip = tooltip;
        }

        this.hoverBarIndex = barIndex;
        this.hoverReady = true;

        return true;
    }

    /**
     * チャート足と完全一致する参照M5の順位・取得元・判定理由をまとめる。
     */
    string getBarTooltip(const CurrencyStrengthPairRankPoint &fromPoints[],
            const int fromBarIndex, const int fromPointStartIndex) {
        datetime barTime = this.barTimes[fromBarIndex];
        string periodText = EnumToString(this.renderedChartPeriod);
        StringReplace(periodText, "PERIOD_", "");
        string tooltip = periodText + "足 "
            + TimeToString(barTime, TIME_DATE | TIME_MINUTES) + " SERVER";
        int m5Seconds = PeriodSeconds(PERIOD_M5);
        if (barTime <= 0 || m5Seconds <= 0) {
            return tooltip + "\n待機：足時刻が未取得";
        }

        datetime m5BarTime = (datetime)((long)barTime - (long)barTime % m5Seconds);
        tooltip += "\n参照M5 " + TimeToString(m5BarTime, TIME_DATE | TIME_MINUTES);
        if (m5BarTime > this.lastTargetM5BarTime || this.lastTargetM5BarTime <= 0) {
            return tooltip + "\n取得元 —\n待機：使用可能なM5時刻より先";
        }

        if (fromPointStartIndex < 0 || fromPointStartIndex > ArraySize(fromPoints)) {
            return tooltip + "\n取得元 —\n待機：順位履歴が未準備";
        }

        int pointIndex = this.findRankPointIndex(fromPoints, m5BarTime, fromPointStartIndex, -1);
        if (pointIndex < 0) {
            return tooltip + "\n取得元 —\n待機：同時刻のM5順位が欠損";
        }

        string sourceMode = fromPoints[pointIndex].sourceMode;
        if (sourceMode == "") {
            sourceMode = "未記録";
        }

        tooltip += " / " + sourceMode
            + "\n" + this.formatHoverRanks("長中期",
                fromPoints[pointIndex].baseLongMediumTermAverageRank,
                fromPoints[pointIndex].quoteLongMediumTermAverageRank);
        string mediumShortTitle = "中短期";
        if (this.renderedLongMediumOnly) {
            mediumShortTitle += "(参考・判定外)";
        }

        tooltip += "\n" + this.formatHoverRanks(mediumShortTitle,
            fromPoints[pointIndex].baseMediumShortTermAverageRank,
            fromPoints[pointIndex].quoteMediumShortTermAverageRank);
        if (!CurrencyStrengthRankAndSignal::hasValidRibbonRanks(
                fromPoints[pointIndex], this.renderedLongMediumOnly)) {
            return tooltip + "\n待機：判定対象の順位が無効";
        }

        int state = CurrencyStrengthRankAndSignal::getRibbonState(fromPoints[pointIndex],
            this.renderedMinimumDifference, this.renderedLongMediumOnly, this.renderedChartPeriod);

        return tooltip + "\n" + this.getHoverReason(fromPoints[pointIndex], state);
    }

    /**
     * 通貨名・順位と決済順位から基軸順位を引いた符号付き順位差を表示する。
     * 無効順位を含む場合は差を計算せず、未取得の目印を表示する。
     */
    string formatHoverRanks(const string fromTitle, const int fromBaseRank,
            const int fromQuoteRank) {
        string baseRank = "—";
        string quoteRank = "—";
        string difference = "—";
        bool baseValid = fromBaseRank >= 1 && fromBaseRank <= 8;
        bool quoteValid = fromQuoteRank >= 1 && fromQuoteRank <= 8;
        if (baseValid) {
            baseRank = (string)fromBaseRank;
        }

        if (quoteValid) {
            quoteRank = (string)fromQuoteRank;
        }

        if (baseValid && quoteValid) {
            difference = StringFormat("%+d", fromQuoteRank - fromBaseRank);
        }

        return fromTitle + " " + this.hoverBaseCurrency + baseRank
            + "/" + this.hoverQuoteCurrency + quoteRank + " 差" + difference;
    }

    /**
     * 共通の帯判定に対応する成立状態と未達理由を短い日本語へ変換する。
     */
    string getHoverReason(const CurrencyStrengthPairRankPoint &fromPoint, const int fromState) {
        string direction = "BUY";
        if (fromState < 0) {
            direction = "SELL";
        }

        if (this.renderedChartPeriod == PERIOD_M15) {
            if (MathAbs(fromState) == 2) {
                int difference = fromPoint.quoteLongMediumTermAverageRank
                    - fromPoint.baseLongMediumTermAverageRank;
                if (MathAbs(difference) >= 2) {
                    return direction + "成立：長中期の順位差2以上（中短期は参考）";
                }

                string strongCurrency = this.hoverBaseCurrency;
                string weakCurrency = this.hoverQuoteCurrency;
                int strongRank = fromPoint.baseLongMediumTermAverageRank;
                if (fromState < 0) {
                    strongCurrency = this.hoverQuoteCurrency;
                    weakCurrency = this.hoverBaseCurrency;
                    strongRank = fromPoint.quoteLongMediumTermAverageRank;
                }

                if (strongRank == 1) {
                    return direction + "成立：長中期で買う通貨" + strongCurrency + "が1位（中短期は参考）";
                }

                return direction + "成立：長中期で売る通貨" + weakCurrency + "が8位（中短期は参考）";
            }

            if (fromPoint.baseLongMediumTermAverageRank == fromPoint.quoteLongMediumTermAverageRank) {
                return "未成立：長中期が同順位（中短期は参考）";
            }

            return "未成立：長中期の差2未満で、買う通貨1位・売る通貨8位にも該当しません（中短期は参考）";
        }

        if (MathAbs(fromState) == 2) {
            if (this.renderedLongMediumOnly) {
                return direction + "成立：長中期条件を達成";
            }

            return direction + "成立：両期間の条件を達成";
        }

        if (MathAbs(fromState) == 1) {
            int longMediumDirection = CurrencyStrengthRankAndSignal::getLongMediumDirection(
                fromPoint.baseLongMediumTermAverageRank,
                fromPoint.quoteLongMediumTermAverageRank, this.renderedMinimumDifference);
            if (longMediumDirection != 0) {
                return direction + "準備：中短期の順位条件待ち";
            }

            return direction + "準備：長中期の順位条件待ち";
        }

        int longMediumDifference = fromPoint.quoteLongMediumTermAverageRank
            - fromPoint.baseLongMediumTermAverageRank;
        if (this.renderedLongMediumOnly) {
            if (longMediumDifference == 0) {
                return "待機：長中期が同順位";
            }

            return "待機：長中期の順位差・端順位が未達";
        }

        int mediumShortDifference = fromPoint.quoteMediumShortTermAverageRank
            - fromPoint.baseMediumShortTermAverageRank;
        if (longMediumDifference == 0 || mediumShortDifference == 0) {
            return "待機：同順位の期間あり";
        }

        if ((longMediumDifference > 0 && mediumShortDifference < 0)
                || (longMediumDifference < 0 && mediumShortDifference > 0)) {
            return "待機：両期間が逆方向";
        }

        return "待機：両期間の順位条件が未達";
    }

    /**
     * 足時刻と横座標を再利用できる通常の横縮尺・右端余白の条件を取得する。
     * 特殊縮尺や設定取得の失敗時は、従来どおり取得と座標変換を行う。
     *
     * @param fromViewKey 表示範囲・最新足・画面設定の識別子。
     * @return 再利用条件の識別子。再利用対象外の場合は空。
     */
    string getBarGeometryKey(const string fromViewKey) {
        long scaleFix11 = 0;
        long scalePointsPerBar = 0;
        long chartShift = 0;
        double shiftSize = 0.0;
        if (!ChartGetInteger(this.chartId, CHART_SCALEFIX_11, 0, scaleFix11)
                || !ChartGetInteger(this.chartId, CHART_SCALE_PT_PER_BAR, 0, scalePointsPerBar)
                || scaleFix11 != 0 || scalePointsPerBar != 0
                || !ChartGetInteger(this.chartId, CHART_SHIFT, 0, chartShift)) {
            return "";
        }

        if (chartShift != 0 && (!ChartGetDouble(this.chartId, CHART_SHIFT_SIZE, 0, shiftSize)
                || !MathIsValidNumber(shiftSize))) {
            return "";
        }

        return StringFormat("%s/%I64d/%.17g", fromViewKey, chartShift, shiftSize);
    }

    /**
     * 使用可能なM5時刻の上限変更が、前回描画の参照範囲へ影響するか判定する。
     *
     * @param fromTargetM5BarTime 今回の使用可能M5時刻の上限。
     * @return 上限変更によって参照範囲内の使用可否が変わり得る場合true。
     */
    bool isTargetChangeVisible(const datetime fromTargetM5BarTime) {
        if (fromTargetM5BarTime == this.lastTargetM5BarTime) {
            return false;
        }

        if (this.lastTargetM5BarTime <= 0 || this.lastStartM5BarTime <= 0
                || this.lastEndM5BarTime < this.lastStartM5BarTime) {
            return true;
        }

        datetime changeStart = this.lastTargetM5BarTime;
        datetime changeEnd = fromTargetM5BarTime;
        if (changeStart > changeEnd) {
            changeStart = fromTargetM5BarTime;
            changeEnd = this.lastTargetM5BarTime;
        }

        // 小さい方の上限と同じ時刻は、変更前後のどちらでも使用できる。
        return changeStart < this.lastEndM5BarTime
            && changeEnd >= this.lastStartM5BarTime;
    }

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
            this.cachedBuyTextWidth = 0;
            this.cachedSellTextWidth = 0;

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
        } else if (this.canvas.Width() != fromWidth) {
            this.cachedBuyTextWidth = 0;
            this.cachedSellTextWidth = 0;

            if (!this.canvas.Resize(fromWidth, this.canvasHeight)) {
                return false;
            }
        }

        return this.moveCanvas(fromChartHeight);
    }

    /**
     * 画像内容を変更せず、チャート下端に合わせてCanvasのY座標だけを更新する。
     * 再描画要求は呼び出し元で行い、成功した位置だけを保持する。
     *
     * @param fromChartHeight メインチャートの高さ。
     * @return 位置が同じ、または位置設定に成功した場合true。
     */
    bool moveCanvas(const int fromChartHeight) {
        int top = fromChartHeight - this.canvasHeight - 32;
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
     * 取得件数から求める足番号と共通の足幅で座標を求め、足ごとの座標変換を省く。
     * BUY/SELLの文字幅はCanvas作成・サイズ変更後の計測値を再描画でも共用する。
     * 同じM5時刻の順位検索と判定は、この描画内でだけ結果を再利用する。
     * 次のM5時刻が隣接する履歴点に一致する場合は、前回の検索位置を再利用する。
     * 色が変わっても同方向なら開始の白色を追加しない。
     *
     * @param fromBarTimes 非seriesで物理先頭から古い順に格納した足時刻。
     * @param fromBarCount 今回取得した有効な足時刻の件数。配列の残りは参照しない。
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     */
    void renderBars(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime &fromBarTimes[],
        const int fromBarCount,
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const int fromPeriodSeconds,
        const ENUM_TIMEFRAMES fromChartPeriod,
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
        int cachedPointIndex = -1;
        bool longMediumOnly = CurrencyStrengthRankAndSignal::isLongMediumOnlyChartPeriod(fromChartPeriod);

        for (int i = 0; i < fromBarCount; i++) {
            // 週末や欠損があっても、時間差ではなく取得した足の並びで位置を求める。
            int seriesIndex = fromBarCount - 1 - i;
            int pointX = fromNewestX - seriesIndex * fromBarWidth;
            datetime barTime = fromBarTimes[i];
            datetime pointM5BarTime = (datetime)((long)barTime
                - (long)barTime % m5Seconds);
            if (!signalCached || cachedM5BarTime != pointM5BarTime) {
                cachedKnown = this.getSignalState(fromPoints, pointM5BarTime,
                    fromTargetM5BarTime, fromMinimumDifference, longMediumOnly, fromChartPeriod,
                    cachedState, fromPointStartIndex, cachedPointIndex);
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
                && barTime - previousTime == fromPeriodSeconds;
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
            previousTime = barTime;
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
     * @param fromCachedPointIndex 同じ描画内で前回見つかった履歴位置。欠損時は-1。
     */
    bool getSignalState(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromM5BarTime,
        const datetime fromTargetM5BarTime,
        const int fromMinimumDifference,
        const bool fromLongMediumOnly,
        const ENUM_TIMEFRAMES fromChartPeriod,
        int &fromState,
        const int fromPointStartIndex,
        int &fromCachedPointIndex
    ) {
        fromState = 0;
        if (fromM5BarTime <= 0 || fromM5BarTime > fromTargetM5BarTime) {
            fromCachedPointIndex = -1;

            return false;
        }

        fromCachedPointIndex = this.findRankPointIndex(
            fromPoints, fromM5BarTime, fromPointStartIndex, fromCachedPointIndex);
        if (fromCachedPointIndex < 0) {
            return false;
        }

        if (!CurrencyStrengthRankAndSignal::hasValidRibbonRanks(
            fromPoints[fromCachedPointIndex], fromLongMediumOnly
        )) {
            return false;
        }

        fromState = CurrencyStrengthRankAndSignal::getRibbonState(
            fromPoints[fromCachedPointIndex], fromMinimumDifference, fromLongMediumOnly, fromChartPeriod);

        return true;
    }

    /**
     * 前回位置の次の履歴点が対象時刻に一致すれば再利用し、それ以外は二分検索する。
     *
     * @param fromPoints M5時刻の昇順で保持した順位履歴。
     * @param fromM5BarTime 検索対象M5時刻。
     * @param fromPointStartIndex 有効な順位履歴の先頭位置。
     * @param fromPreviousPointIndex 同じ描画内で前回見つかった履歴位置。初回は-1。
     * @return 時刻が完全一致する配列位置。存在しない場合は-1。
     */
    int findRankPointIndex(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const datetime fromM5BarTime,
        const int fromPointStartIndex,
        const int fromPreviousPointIndex
    ) {
        int left = fromPointStartIndex;
        int right = ArraySize(fromPoints) - 1;

        if (fromPreviousPointIndex >= left && fromPreviousPointIndex < right
                && fromPoints[fromPreviousPointIndex + 1].m5BarTime == fromM5BarTime) {
            return fromPreviousPointIndex + 1;
        }

        while (left <= right) {
            int middle = left + (right - left) / 2;
            if (fromPoints[middle].m5BarTime == fromM5BarTime) {
                return middle;
            }

            if (fromPoints[middle].m5BarTime < fromM5BarTime) {
                left = middle + 1;
            } else {
                right = middle - 1;
            }
        }

        return -1;
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
