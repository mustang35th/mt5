//+------------------------------------------------------------------+
//|                          DrawCurrencyStrengthRankDeltaRibbon.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_RIBBON_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_RIBBON_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotRankDeltaBandHistory.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * チャート足の順位差増減を、メインチャート下部の同じ時系列に上下2段で描画する。
 * 上段は長中期、下段は中短期。各足の開始位置から次の足の手前までをその足の色にする。
 */
class DrawCurrencyStrengthRankDeltaRibbon {
public:
    /**
     * インスタンス固有のCanvas名とマウス説明に使用する通貨名を設定する。
     */
    DrawCurrencyStrengthRankDeltaRibbon(const long fromChartId, const string fromSuffix,
            const string fromBaseCurrency, const string fromQuoteCurrency) {
        this.chartId = fromChartId;
        string prefix = Constant::PREFIX_FIXED + "RankDeltaBand_";
        this.objectName = prefix + StringSubstr(fromSuffix, 0, 63 - StringLen(prefix));
        this.baseCurrency = fromBaseCurrency;
        this.quoteCurrency = fromQuoteCurrency;
        this.setupRibbonName = "";
        this.created = false;
        this.canvasTop = -1;
        this.mouseX = -1;
        this.mouseY = -1;
        this.hoverIndex = -1;
        this.hoverRow = -1;
        this.renderedRevision = -1;
        this.viewKey = "";
    }

    /**
     * 自分の帯を解放する。
     */
    ~DrawCurrencyStrengthRankDeltaRibbon() {
        this.clear();
    }

    /**
     * 表示範囲の足だけを描画する。足と画面が同じ場合は画像更新を省く。
     * @param fromHistory チャート足の古い順に確定した順位差・増減の履歴。
     * @return 描画または消去に成功した場合true。
     */
    bool draw(const ZigZagElliotRankDeltaBandHistory &fromHistory) {
        int count = ArraySize(fromHistory.bars);
        int width = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int height = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        // 日本時間軸の上に配置し、準備／成立帯がある場合だけその高さも空ける。
        int top = height - 32 - CanvasHeight;
        if (count > 0 && top >= 0 && this.hasSetupRibbon()) {
            top -= 34;
        }

        if (count <= 0 || top < 0 || width <= 0) {
            this.clear();

            return true;
        }

        string symbol = ChartSymbol(this.chartId);
        ENUM_TIMEFRAMES period = ChartPeriod(this.chartId);
        int firstVisible = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS);
        int lastShift = iBarShift(symbol, period, fromHistory.bars[count - 1].time, true);
        if (firstVisible < 0 || visibleBars <= 0 || lastShift < 0) {
            this.clear();

            return false;
        }

        int oldest = MathMax(0, count - 1 + lastShift - firstVisible - 1);
        int newest = MathMin(count - 1, count - 1 + lastShift - MathMax(0, firstVisible - visibleBars - 1));
        if (oldest > newest) {
            this.clear();

            return true;
        }

        // 同じ横縮尺でもスクロール・右余白でX位置が変わるため、実際の足位置を使う。
        double price = ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0);
        int firstX = 0;
        int ignoredY = 0;
        if (!ChartTimePriceToXY(this.chartId, 0, fromHistory.bars[oldest].time, price, firstX, ignoredY)) {
            this.clear();

            return false;
        }

        double barWidth = 0.0;
        int otherX = 0;
        if (oldest < newest) {
            if (ChartTimePriceToXY(this.chartId, 0, fromHistory.bars[newest].time, price, otherX, ignoredY)) {
                barWidth = (double)(otherX - firstX) / (newest - oldest);
            }
        } else {
            datetime previousTime = iTime(symbol, period, lastShift + count - oldest);
            if (previousTime > 0 && ChartTimePriceToXY(this.chartId, 0, previousTime, price, otherX, ignoredY)) {
                barWidth = firstX - otherX;
            }
        }

        if (barWidth <= 0.0) {
            this.clear();

            return false;
        }

        color foreground = (color)ChartGetInteger(this.chartId, CHART_COLOR_FOREGROUND);
        string key = StringFormat("%d/%d/%d/%d/%d/%.12f/%d", width, top, oldest, newest,
            firstX, barWidth, (int)foreground);
        bool ready = this.created && ObjectFind(this.chartId, this.objectName) == 0;
        if (ready && this.viewKey == key && this.renderedRevision == fromHistory.getRevision()) {
            return this.handleMouseMove(this.mouseX, this.mouseY, fromHistory);
        }

        if (!this.prepareCanvas(width, top, ready) || ArrayResize(this.barAtPixel, width) != width) {
            this.clear();

            return false;
        }

        this.canvas.Erase(0);
        ArrayInitialize(this.barAtPixel, -1);
        for (int i = oldest; i <= newest; i++) {
            int left = MathMax(0, firstX + (int)MathRound((i - oldest) * barWidth));
            int right = MathMin(width, firstX + (int)MathRound((i + 1 - oldest) * barWidth));
            if (right <= left) {
                continue;
            }

            ArrayFill(this.barAtPixel, left, right - left, i);
            this.paintRow(left, right, UpperRow, fromHistory.bars[i].longMedium);
            this.paintRow(left, right, LowerRow, fromHistory.bars[i].mediumShort);
        }

        this.canvas.TextOut(6, 0, "上 長中期Δ ／ 下 中短期Δ", ColorToARGB(foreground));
        ResetLastError();
        this.canvas.Update(false);
        if (GetLastError() != 0) {
            this.clear();

            return false;
        }

        this.viewKey = key;
        this.renderedRevision = fromHistory.getRevision();
        this.hoverIndex = -2;
        DrawChartRedrawBatch::request(this.chartId);

        return this.handleMouseMove(this.mouseX, this.mouseY, fromHistory);
    }

    /**
     * 描画に使用したピクセルから足・期間を特定し、対象が変わった場合だけ説明を更新する。
     */
    bool handleMouseMove(const int fromX, const int fromY, const ZigZagElliotRankDeltaBandHistory &fromHistory) {
        this.mouseX = fromX;
        this.mouseY = fromY;
        if (!this.created) {
            return true;
        }

        int row = -1;
        int index = -1;
        int localY = fromY - this.canvasTop;
        if (fromX >= 0 && fromX < ArraySize(this.barAtPixel)
                && this.renderedRevision == fromHistory.getRevision()) {
            if (localY >= UpperRow && localY < UpperRow + RowHeight) {
                row = 0;
            } else if (localY >= LowerRow && localY < LowerRow + RowHeight) {
                row = 1;
            }

            if (row >= 0) {
                index = this.barAtPixel[fromX];
            }
        }

        if (index == this.hoverIndex && row == this.hoverRow) {
            return true;
        }

        string tooltip = "\n";
        if (index >= 0 && index < ArraySize(fromHistory.bars)) {
            if (row == 0) {
                tooltip = this.getTooltip("長中期", fromHistory.bars[index].time, fromHistory.bars[index].longMedium);
            } else {
                tooltip = this.getTooltip("中短期", fromHistory.bars[index].time, fromHistory.bars[index].mediumShort);
            }
        }

        if (!ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, tooltip)) {
            return false;
        }

        this.hoverIndex = index;
        this.hoverRow = row;

        return true;
    }

    /**
     * Canvasとマウス参照位置を解放する。別インスタンスの帯には触れない。
     */
    void clear() {
        bool hadCanvas = this.created;
        this.canvas.Destroy();
        ArrayFree(this.barAtPixel);
        this.created = false;
        this.canvasTop = -1;
        this.renderedRevision = -1;
        this.viewKey = "";
        this.hoverIndex = -1;
        this.hoverRow = -1;
        if (hadCanvas) {
            DrawChartRedrawBatch::request(this.chartId);
        }
    }

private:
    /** 描画対象のチャート。 */
    long chartId;

    /** 所有する画像オブジェクト名。 */
    string objectName;

    /** 基軸通貨名。 */
    string baseCurrency;

    /** メイン画面で確認したCurrencyStrengthRankHistoryの準備／成立帯のオブジェクト名。 */
    string setupRibbonName;

    /** 決済通貨名。 */
    string quoteCurrency;

    /** 2段の帯と凡例を描く透過画像。 */
    CCanvas canvas;

    /** Canvas生成済みの場合true。 */
    bool created;

    /** 凡例と上下の帯で共有するCanvas内のピクセル寸法。 */
    enum RibbonLayout {
        UpperRow = 16,
        RowHeight = 10,
        LowerRow = UpperRow + RowHeight + 2,
        CanvasHeight = LowerRow + RowHeight
    };

    /** 描画済み画像の上端。 */
    int canvasTop;

    /** 各ピクセルを塗ったチャート足の履歴添字。余白は−1。 */
    int barAtPixel[];

    /** 最後のマウスX座標。 */
    int mouseX;

    /** 最後のマウスY座標。 */
    int mouseY;

    /** マウス説明を反映した足。 */
    int hoverIndex;

    /** マウス説明を反映した行。 */
    int hoverRow;

    /** 最後に描画済みの履歴版。 */
    int renderedRevision;

    /** 最後に描画済みの可視範囲・座標・文字色。 */
    string viewKey;

    /**
     * メイン画面の準備／成立帯を、順位履歴が生成するビットマップ名で確認する。
     */
    bool hasSetupRibbon() {
        if (this.setupRibbonName != "" && ObjectFind(this.chartId, this.setupRibbonName) == 0) {
            return true;
        }

        this.setupRibbonName = "";
        string prefix = Constant::PREFIX_FIXED + "CurrencyStrengthRankAndRibbon_";
        int count = ObjectsTotal(this.chartId, 0, OBJ_BITMAP_LABEL);
        for (int i = 0; i < count; i++) {
            string name = ObjectName(this.chartId, i, 0, OBJ_BITMAP_LABEL);
            if (StringFind(name, prefix) == 0) {
                this.setupRibbonName = name;

                return true;
            }
        }

        return false;
    }

    /**
     * 透過画像をメインウィンドウに生成し、画面サイズの変更に追従させる。
     */
    bool prepareCanvas(const int fromWidth, const int fromTop, const bool fromReady) {
        if (!fromReady) {
            this.clear();
            if (!this.canvas.CreateBitmapLabel(this.chartId, 0, this.objectName, 0, fromTop,
                    fromWidth, CanvasHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
                ObjectDelete(this.chartId, this.objectName);

                return false;
            }

            this.created = true;
            if (!ObjectSetInteger(this.chartId, this.objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_BACK, false)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_HIDDEN, true)
                    || !ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, "\n")
                    || !this.canvas.FontSet("MS Gothic", 12)) {
                return false;
            }
        } else if (this.canvas.Width() != fromWidth && !this.canvas.Resize(fromWidth, CanvasHeight)) {
            return false;
        }

        if (this.canvasTop != fromTop && !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_YDISTANCE, fromTop)) {
            return false;
        }

        this.canvasTop = fromTop;

        return true;
    }

    /**
     * 変化足を明色、横ばいの引き継ぎを暗色で塗る。比較できない足は背景を透過させる。
     */
    void paintRow(const int fromLeft, const int fromRight, const int fromTop, const RankDeltaBandPeriod &fromPeriod) {
        if (!fromPeriod.valid || !fromPeriod.comparable) {
            return;
        }

        color fillColor = clrDimGray;
        if (fromPeriod.delta > 0) {
            fillColor = clrLightSeaGreen;
        } else if (fromPeriod.delta < 0) {
            fillColor = clrHotPink;
        } else if (fromPeriod.direction > 0) {
            fillColor = C'0,82,82';
        } else if (fromPeriod.direction < 0) {
            fillColor = C'100,38,65';
        }

        this.canvas.FillRectangle(fromLeft, fromTop, fromRight - 1, fromTop + RowHeight - 1, ColorToARGB(fillColor));
    }

    /**
     * 指定足・期間の両順位と符号付き前足差をサーバー足時刻とともに返す。
     */
    string getTooltip(const string fromTitle, const datetime fromTime, const RankDeltaBandPeriod &fromPeriod) {
        string tooltip = fromTitle + "｜" + TimeUtil::formatYyyymmddhhmiss(fromTime) + " SRV\n";
        if (!fromPeriod.valid) {
            return tooltip + "順位データなし";
        }

        tooltip += StringFormat("%s %d位・%s %d位｜", this.baseCurrency, fromPeriod.baseRank,
            this.quoteCurrency, fromPeriod.quoteRank);
        if (!fromPeriod.comparable) {
            return tooltip + StringFormat("差 %+d（前足データなし）", fromPeriod.gap);
        }

        return tooltip + StringFormat("差 %+d → %+d（Δ%+d）", fromPeriod.gap - fromPeriod.delta,
            fromPeriod.gap, fromPeriod.delta);
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_RIBBON_MQH
