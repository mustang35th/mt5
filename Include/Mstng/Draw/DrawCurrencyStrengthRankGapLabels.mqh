//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthRankGapLabels.mqh    |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_LABELS_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_LABELS_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 変化点に配置した順位ラベル3個の反映状態と占有位置。
 */
struct CurrencyStrengthRankGapLabelState {
    /** 固定設定まで完了した基軸・区切り・決済ラベル。 */
    bool created[3];

    /** 位置・文字・説明まで反映済みの場合true。 */
    bool valuesReady;

    /** 反映済みの各文字。 */
    string texts[3];

    /** 反映済みの説明。 */
    string tooltip;

    /** 反映済みの左位置。 */
    int lastLeft;

    /** 反映済みの上位置。 */
    int lastTop;

    /** 反映済みの数字1文字分の実測幅。 */
    int lastDigitWidth;

    /** 反映済みの区切り文字の実測幅。 */
    int lastSeparatorWidth;

    /** 今回の配置判定に使う左位置。 */
    int left;

    /** 今回の配置判定に使う上位置。 */
    int top;
};

/**
 * 順位差が変化した可視点に、通貨色の基軸順位 / 決済順位を表示する。
 * 保持済みバッファだけを参照し、同一画面・同一データの再配置を省く。
 */
class DrawCurrencyStrengthRankGapLabels {
public:
    /**
     * インスタンス固有の描画名と、通貨色・再描画要求先を保持する。
     */
    DrawCurrencyStrengthRankGapLabels(const long fromChartId, const string fromObjectSuffix,
            const string fromBaseCurrency, const string fromQuoteCurrency,
            ChartRedrawRequest *fromRedrawRequest) {
        this.chartId = fromChartId;
        this.prefix = Constant::PREFIX_FIXED + "GapRanks_" + StringSubstr(fromObjectSuffix, 0, 30) + "_";
        this.baseCurrency = fromBaseCurrency;
        this.quoteCurrency = fromQuoteCurrency;
        this.colors[0] = ConstantCurrency::getColor(fromBaseCurrency);
        this.colors[1] = clrSilver;
        this.colors[2] = ConstantCurrency::getColor(fromQuoteCurrency);
        this.redrawRequest = fromRedrawRequest;
        this.lastViewKey = "";
    }

    /**
     * 所有する順位ラベルだけを解放する。
     */
    ~DrawCurrencyStrengthRankGapLabels() {
        this.clear();
    }

    /**
     * 変更時だけ可視変化点を再配置する。欠けた自分のラベルも復旧する。
     *
     * @param fromGap 最新足が添字0の順位差。欠損はEMPTY_VALUE。
     * @param fromBaseRank 同じ添字の基軸通貨順位。
     * @param fromQuoteRank 同じ添字の決済通貨順位。
     * @param fromBarTime 同じ添字のチャート足時刻。
     * @param fromDataChanged 前回描画後にバッファが変更された場合true。
     * @return 全ラベルを反映済み、または変更不要の場合true。
     */
    bool draw(const int fromSubWindow, const double &fromGap[], const double &fromBaseRank[],
            const double &fromQuoteRank[], const double &fromBarTime[], const bool fromDataChanged) {
        if (fromSubWindow < 1) {
            return false;
        }

        int width = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int height = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, fromSubWindow);
        int offset = (int)ChartGetInteger(this.chartId, CHART_WINDOW_YDISTANCE, fromSubWindow);
        int firstVisible = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS);
        int scale = (int)ChartGetInteger(this.chartId, CHART_SCALE);
        double minimum = ChartGetDouble(this.chartId, CHART_PRICE_MIN, fromSubWindow);
        double maximum = ChartGetDouble(this.chartId, CHART_PRICE_MAX, fromSubWindow);
        double shiftSize = ChartGetDouble(this.chartId, CHART_SHIFT_SIZE);
        bool shifted = (bool)ChartGetInteger(this.chartId, CHART_SHIFT);
        if (width <= 0 || height <= 0 || offset < 0 || firstVisible < 0 || visibleBars <= 0
                || maximum <= minimum) {
            return false;
        }

        int count = MathMin(MathMin(ArraySize(fromGap), ArraySize(fromBarTime)),
            MathMin(ArraySize(fromBaseRank), ArraySize(fromQuoteRank)));
        string viewKey = StringFormat("%d:%d:%d:%d:%d:%d:%d:%d:%.12f:%.12f:%.8f:%d",
            fromSubWindow, width, height, offset, firstVisible, visibleBars, scale, count,
            minimum, maximum, shiftSize, (int)shifted);
        if (!fromDataChanged && this.lastViewKey == viewKey && this.objectsReady(fromSubWindow)) {
            return true;
        }

        uint digitWidth = 0;
        uint textHeight = 0;
        uint separatorWidth = 0;
        uint separatorHeight = 0;
        if (!TextSetFont("MS Gothic", -90) || !TextGetSize("8", digitWidth, textHeight)
                || !TextGetSize(" / ", separatorWidth, separatorHeight)
                || digitWidth == 0 || textHeight == 0 || separatorWidth == 0) {
            this.lastViewKey = "";

            return false;
        }

        int labelWidth = (int)(digitWidth * 2 + separatorWidth);
        int labelHeight = (int)MathMax(textHeight, separatorHeight);
        int newest = MathMax(0, firstVisible - visibleBars - 1);
        int oldest = MathMin(count - 2, firstVisible + 1);
        int used = 0;
        bool succeeded = true;
        for (int i = newest; i <= oldest; i++) {
            if (!this.isChangedPoint(fromGap, fromBaseRank, fromQuoteRank, fromBarTime, i)) {
                continue;
            }

            int pointX = 0;
            int pointY = 0;
            if (!ChartTimePriceToXY(this.chartId, fromSubWindow,
                    (datetime)fromBarTime[i], fromGap[i], pointX, pointY)) {
                succeeded = false;
                continue;
            }

            pointY -= offset;
            // 画面外の点を端へ寄せない。可視点の文字だけを枠内へ収める。
            if (pointX < 0 || pointX >= width || pointY < 0 || pointY > height
                    || width < labelWidth + 8) {
                continue;
            }

            int left = MathMax(4, MathMin(width - labelWidth - 4, pointX - labelWidth / 2));
            int top = this.findTop(left, pointY, labelWidth, labelHeight, width, height, used);
            if (top < 0) {
                continue;
            }

            if (!this.ensureItem(used)) {
                succeeded = false;
                break;
            }

            this.items[used].left = left;
            this.items[used].top = top;
            datetime rankTime = (datetime)((long)fromBarTime[i] / 300 * 300);
            string tooltip = StringFormat("%s %d位 / %s %d位｜順位差 %+d\n%s SRV",
                this.baseCurrency, (int)fromBaseRank[i], this.quoteCurrency,
                (int)fromQuoteRank[i], (int)fromGap[i], TimeUtil::formatYyyymmddhhmiss(rankTime));
            succeeded = this.updateItem(used, fromSubWindow, left, top, (int)digitWidth,
                (int)separatorWidth, (int)fromBaseRank[i], (int)fromQuoteRank[i], tooltip) && succeeded;
            used++;
        }

        succeeded = this.trimItems(used) && succeeded;
        this.lastViewKey = "";
        if (succeeded) {
            this.lastViewKey = viewKey;
        }

        return succeeded;
    }

    /**
     * このインスタンスが所有するラベルだけを削除する。
     */
    void clear() {
        this.trimItems(0);
        this.lastViewKey = "";
    }

private:
    /** 描画対象のチャート。 */
    long chartId;

    /** このインスタンス専用のオブジェクト名接頭辞。 */
    string prefix;

    /** 左側の順位に対応する通貨名。 */
    string baseCurrency;

    /** 右側の順位に対応する通貨名。 */
    string quoteCurrency;

    /** 基軸・区切り・決済の固定色。 */
    color colors[3];

    /** 所有ラベルの設定と今回の配置位置。 */
    CurrencyStrengthRankGapLabelState items[];

    /** 最後に正常配置した画面構成。 */
    string lastViewKey;

    /** イベント末尾でまとめる再描画要求先。 */
    ChartRedrawRequest *redrawRequest;

    /**
     * 比較可能な隣接足で順位差が変わったか確認する。同じM5枠は重複表示しない。
     */
    bool isChangedPoint(const double &fromGap[], const double &fromBaseRank[],
            const double &fromQuoteRank[], const double &fromBarTime[], const int fromIndex) {
        return fromGap[fromIndex] != EMPTY_VALUE && fromGap[fromIndex + 1] != EMPTY_VALUE
            && fromGap[fromIndex] != fromGap[fromIndex + 1]
            && fromBaseRank[fromIndex] >= 1 && fromBaseRank[fromIndex] <= 8
            && fromQuoteRank[fromIndex] >= 1 && fromQuoteRank[fromIndex] <= 8
            && fromBarTime[fromIndex + 1] > 0 && fromBarTime[fromIndex] > fromBarTime[fromIndex + 1]
            && (long)fromBarTime[fromIndex] / 300 != (long)fromBarTime[fromIndex + 1] / 300;
    }

    /**
     * 線の上下の候補を順に調べる。右上の状態欄と先に配置した順位を避ける。
     */
    int findTop(const int fromLeft, const int fromPointY, const int fromLabelWidth,
            const int fromLabelHeight, const int fromWidth, const int fromHeight, const int fromUsed) {
        for (int i = 0; i < 7; i++) {
            int distance = 5 + (i / 2) * (fromLabelHeight + 4);
            int top = fromPointY - distance - fromLabelHeight;
            if (i % 2 == 1) {
                top = fromPointY + distance;
            }

            if (i == 6) {
                if (fromPointY >= 66 || fromLeft + fromLabelWidth <= fromWidth - 428) {
                    continue;
                }

                top = 68;
            }

            // 左上のインジケーター名と右上の3行・再読込ボタンを避ける。
            if (top < 18 || top + fromLabelHeight > fromHeight - 4
                    || (fromLeft + fromLabelWidth > fromWidth - 428 && top < 66)) {
                continue;
            }

            bool overlaps = false;
            for (int j = 0; j < fromUsed; j++) {
                if (fromLeft < this.items[j].left + fromLabelWidth + 3
                        && fromLeft + fromLabelWidth + 3 > this.items[j].left
                        && top < this.items[j].top + fromLabelHeight + 3
                        && top + fromLabelHeight + 3 > this.items[j].top) {
                    overlaps = true;
                    break;
                }
            }

            if (!overlaps) {
                return top;
            }
        }

        return -1;
    }

    /**
     * 必要な表示枠だけを確保し、初期状態にする。
     */
    bool ensureItem(const int fromIndex) {
        if (fromIndex < ArraySize(this.items)) {
            return true;
        }

        if (ArrayResize(this.items, fromIndex + 1, 32) != fromIndex + 1) {
            return false;
        }

        ZeroMemory(this.items[fromIndex]);

        return true;
    }

    /**
     * 描画名を、表示枠と基軸・区切り・決済の番号から生成する。
     */
    string getObjectName(const int fromIndex, const int fromPart) {
        return this.prefix + IntegerToString(fromIndex * 3 + fromPart);
    }

    /**
     * 同じ画面でも、外部操作で消去されたラベルがあれば再配置する。
     */
    bool objectsReady(const int fromSubWindow) {
        for (int i = 0; i < ArraySize(this.items); i++) {
            for (int j = 0; j < 3; j++) {
                if (!this.items[i].created[j]
                        || ObjectFind(this.chartId, this.getObjectName(i, j)) != fromSubWindow) {
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * フォント・通貨色・操作可否など、固定項目を作成時だけ設定する。
     */
    bool configureItem(const string fromName, const int fromPart) {
        bool configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_FONTSIZE, 9) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_COLOR, this.colors[fromPart]) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_BACK, false) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTABLE, false) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTED, false) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_HIDDEN, true) && configured;
        configured = ObjectSetInteger(this.chartId, fromName, OBJPROP_ZORDER, 1) && configured;
        configured = ObjectSetString(this.chartId, fromName, OBJPROP_FONT, "MS Gothic") && configured;

        return configured;
    }

    /**
     * 1変化点の3ラベルを作成または再利用し、変更項目だけ反映する。
     */
    bool updateItem(const int fromIndex, const int fromSubWindow, const int fromLeft,
            const int fromTop, const int fromDigitWidth, const int fromSeparatorWidth,
            const int fromBaseRank, const int fromQuoteRank, const string fromTooltip) {
        string texts[3];
        texts[0] = IntegerToString(fromBaseRank);
        texts[1] = " / ";
        texts[2] = IntegerToString(fromQuoteRank);
        int left = fromLeft;
        bool succeeded = true;
        for (int i = 0; i < 3; i++) {
            string objectName = this.getObjectName(fromIndex, i);
            int objectWindow = ObjectFind(this.chartId, objectName);
            if (objectWindow != fromSubWindow || !this.items[fromIndex].created[i]) {
                this.items[fromIndex].valuesReady = false;
                this.items[fromIndex].created[i] = false;
                if (objectWindow >= 0 && objectWindow != fromSubWindow) {
                    if (!ObjectDelete(this.chartId, objectName)) {
                        return false;
                    }

                    objectWindow = -1;
                }

                if (objectWindow < 0
                        && !ObjectCreate(this.chartId, objectName, OBJ_LABEL, fromSubWindow, 0, 0)) {
                    return false;
                }

                this.requestRedraw();
                if (!this.configureItem(objectName, i)) {
                    return false;
                }

                this.items[fromIndex].created[i] = true;
            }

            if (!this.items[fromIndex].valuesReady || this.items[fromIndex].lastLeft != fromLeft
                    || this.items[fromIndex].lastDigitWidth != fromDigitWidth
                    || this.items[fromIndex].lastSeparatorWidth != fromSeparatorWidth) {
                succeeded = ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, left) && succeeded;
                this.requestRedraw();
            }

            if (!this.items[fromIndex].valuesReady || this.items[fromIndex].lastTop != fromTop) {
                succeeded = ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, fromTop) && succeeded;
                this.requestRedraw();
            }

            if (!this.items[fromIndex].valuesReady || this.items[fromIndex].texts[i] != texts[i]) {
                succeeded = ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, texts[i]) && succeeded;
                this.requestRedraw();
            }

            if (!this.items[fromIndex].valuesReady || this.items[fromIndex].tooltip != fromTooltip) {
                succeeded = ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, fromTooltip) && succeeded;
                this.requestRedraw();
            }

            left += fromDigitWidth;
            if (i == 1) {
                left += fromSeparatorWidth - fromDigitWidth;
            }
        }

        this.items[fromIndex].valuesReady = succeeded;
        if (succeeded) {
            this.items[fromIndex].lastLeft = fromLeft;
            this.items[fromIndex].lastTop = fromTop;
            this.items[fromIndex].lastDigitWidth = fromDigitWidth;
            this.items[fromIndex].lastSeparatorWidth = fromSeparatorWidth;
            this.items[fromIndex].tooltip = fromTooltip;
            for (int i = 0; i < 3; i++) {
                this.items[fromIndex].texts[i] = texts[i];
            }
        }

        return succeeded;
    }

    /**
     * 今回不要になったラベルを削除する。失敗した枠は再試行用に保持する。
     */
    bool trimItems(const int fromUsed) {
        bool succeeded = true;
        for (int i = fromUsed; i < ArraySize(this.items); i++) {
            for (int j = 0; j < 3; j++) {
                string objectName = this.getObjectName(i, j);
                if (ObjectFind(this.chartId, objectName) >= 0) {
                    if (!ObjectDelete(this.chartId, objectName)) {
                        succeeded = false;
                        continue;
                    }

                    this.requestRedraw();
                }

                this.items[i].created[j] = false;
                this.items[i].valuesReady = false;
            }
        }

        if (succeeded) {
            ArrayResize(this.items, fromUsed);
        }

        return succeeded;
    }

    /**
     * 表示変更の再描画を呼び出し元のイベント末尾へまとめる。
     */
    void requestRedraw() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        } else {
            ChartRedraw(this.chartId);
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_LABELS_MQH
