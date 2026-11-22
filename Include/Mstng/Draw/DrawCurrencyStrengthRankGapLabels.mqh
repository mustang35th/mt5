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
#include <Mstng\Draw\DrawCurrencyStrengthRankDeltaPanel.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 文字との重なり判定に使う、可視範囲とその隣の折れ線頂点。
 */
struct CurrencyStrengthRankGapLinePoint {
    /** 順位差と画面座標が有効な場合true。 */
    bool valid;

    /** この頂点のチャート足時刻。 */
    datetime time;

    /** チャート内の横座標。画面外の端点も保持する。 */
    int left;

    /** サブ画面内の縦座標。 */
    int top;
};

/**
 * 変化点に配置した順位・差分ラベル1個の反映状態と占有位置。
 */
struct CurrencyStrengthRankGapLabelState {
    /** 固定設定まで完了した場合true。 */
    bool created;

    /** 位置・文字・説明まで反映済みの場合true。 */
    bool valuesReady;

    /** 反映済みの文字。 */
    string text;

    /** 反映済みの表示種別。0は基軸、1は決済、2は買い方向の差分、3は売り方向の差分。 */
    int lastPart;

    /** 反映済みの説明。 */
    string tooltip;

    /** 反映済みの左位置。 */
    int lastLeft;

    /** 反映済みの上位置。 */
    int lastTop;

    /** 今回の配置判定に使う左位置。 */
    int left;

    /** 今回の配置判定に使う上位置。 */
    int top;

    /** 今回の配置判定に使う文字の実測幅。 */
    int width;

    /** 今回の配置判定に使う文字の実測高さ。 */
    int height;
};

/**
 * 変化点で0ラインと順位差線に挟まれた領域の上に基軸順位、下に決済順位を表示する。
 * 順位文字の横に現在の順位差と前足比を表示し、前足比の増減で色分けする。
 * 保持済みバッファだけを参照し、同一画面・同一データの再配置を省く。
 */
class DrawCurrencyStrengthRankGapLabels {
public:
    /**
     * インスタンス固有の描画名と、表示色・再描画要求先・目盛り単位の間隔を保持する。
     */
    DrawCurrencyStrengthRankGapLabels(const long fromChartId, const string fromObjectSuffix,
            const string fromBaseCurrency, const string fromQuoteCurrency,
            ChartRedrawRequest *fromRedrawRequest, const double fromLineGapUnits = 0.5,
            DrawCurrencyStrengthRankDeltaPanel *fromPanel = NULL, const string fromShortName = "") {
        this.chartId = fromChartId;
        this.prefix = Constant::PREFIX_FIXED + "GapRanks_" + StringSubstr(fromObjectSuffix, 0, 30) + "_";
        this.baseCurrency = fromBaseCurrency;
        this.quoteCurrency = fromQuoteCurrency;
        this.colors[0] = ConstantCurrency::getColor(fromBaseCurrency);
        this.colors[1] = ConstantCurrency::getColor(fromQuoteCurrency);
        this.colors[2] = clrAqua;
        this.colors[3] = clrHotPink;
        this.lineGapUnits = MathMax(0.0, fromLineGapUnits);
        this.redrawRequest = fromRedrawRequest;
        this.panel = fromPanel;
        this.shortName = fromShortName;
        this.lastViewKey = "";
        for (int i = 0; i < ArraySize(this.obstacles); i++) {
            this.obstacles[i].SetBound(0, 0, 0, 0);
        }
    }

    /**
     * 所有する順位ラベルだけを解放する。
     */
    ~DrawCurrencyStrengthRankGapLabels() {
        this.clear();
    }

    /**
     * 順位文字の余白を含む固定の表示範囲±11を返す。
     *
     * @param fromHeight サブ画面の高さ。
     * @param toMinimum 縦軸の最小値−11。
     * @param toMaximum 縦軸の最大値＋11。
     * @return 有効な画面の高さの場合true。
     */
    bool getDisplayRange(const int fromHeight, double &toMinimum, double &toMaximum) {
        if (fromHeight <= 0) {
            return false;
        }

        toMinimum = -11.0;
        toMaximum = 11.0;

        return true;
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
                || !MathIsValidNumber(minimum) || !MathIsValidNumber(maximum) || maximum <= minimum) {
            return false;
        }

        int count = MathMin(MathMin(ArraySize(fromGap), ArraySize(fromBarTime)),
            MathMin(ArraySize(fromBaseRank), ArraySize(fromQuoteRank)));
        string viewKey = StringFormat("%d:%d:%d:%d:%d:%d:%d:%d:%.12f:%.12f:%.8f:%d",
            fromSubWindow, width, height, offset, firstVisible, visibleBars, scale, count,
            minimum, maximum, shiftSize, (int)shifted);
        if (!TextSetFont("MS Gothic", -90) || !this.prepareObstacles(fromSubWindow, width, viewKey)) {
            this.lastViewKey = "";

            return false;
        }

        if (!fromDataChanged && this.lastViewKey == viewKey && this.objectsReady(fromSubWindow)) {
            return true;
        }

        int newest = MathMax(0, firstVisible - visibleBars - 1);
        int oldest = MathMin(count - 2, firstVisible + 1);
        CurrencyStrengthRankGapLinePoint linePoints[];
        if (!this.prepareLinePoints(fromSubWindow, fromGap, fromBarTime,
                newest, MathMin(count - 1, oldest + 1), offset, linePoints)) {
            this.lastViewKey = "";

            return false;
        }

        int labelIndexes[];
        int visibleCount = MathMax(0, oldest - newest + 1);
        if (ArrayResize(labelIndexes, visibleCount) != visibleCount) {
            this.lastViewKey = "";

            return false;
        }

        int used = 0;
        bool succeeded = true;
        int zeroY = 0;
        bool zeroReady = false;
        for (int i = newest; i <= oldest; i++) {
            if (!this.isChangedPoint(fromGap, fromBaseRank, fromQuoteRank, fromBarTime, i)) {
                continue;
            }

            int pointIndex = i - newest;
            if (!linePoints[pointIndex].valid) {
                continue;
            }

            int pointX = linePoints[pointIndex].left;
            int pointY = linePoints[pointIndex].top;
            // 画面外の変化点自体は表示対象にしない。
            if (pointX < 0 || pointX >= width || pointY < 0 || pointY > height) {
                continue;
            }

            if (!zeroReady) {
                int ignoredX = 0;
                if (!ChartTimePriceToXY(this.chartId, fromSubWindow, linePoints[pointIndex].time,
                        0.0, ignoredX, zeroY)) {
                    this.lastViewKey = "";

                    return false;
                }

                zeroY -= offset;
                zeroReady = true;
            }

            datetime rankTime = (datetime)((long)fromBarTime[i] / 300 * 300);
            string tooltip = StringFormat("%s（基軸）%d→%d位 / %s（決済）%d→%d位｜順位差 %+d｜前足比 %+d\n%s SRV",
                this.baseCurrency, (int)fromBaseRank[i + 1], (int)fromBaseRank[i],
                this.quoteCurrency, (int)fromQuoteRank[i + 1], (int)fromQuoteRank[i],
                (int)fromGap[i], (int)fromGap[i] - (int)fromGap[i + 1],
                TimeUtil::formatYyyymmddhhmiss(rankTime));
            string texts[2];
            texts[0] = this.formatRank((int)fromBaseRank[i], (int)fromBaseRank[i + 1]);
            texts[1] = this.formatRank((int)fromQuoteRank[i], (int)fromQuoteRank[i + 1]);
            int labelLefts[2];
            int labelTops[2];
            int labelWidths[2];
            int labelHeights[2];
            bool pairReady = true;
            for (int j = 0; j < 2; j++) {
                uint labelWidth = 0;
                uint labelHeight = 0;
                if (!TextGetSize(texts[j], labelWidth, labelHeight) || labelWidth == 0 || labelHeight == 0) {
                    succeeded = false;
                    pairReady = false;
                    break;
                }

                if (width < (int)labelWidth + 8) {
                    pairReady = false;
                    break;
                }

                int left = MathMax(4, MathMin(width - (int)labelWidth - 4, pointX - (int)labelWidth / 2));
                int lineTop = pointY;
                int lineBottom = pointY;
                // 線幅2の縁も含め、実際の文字位置の左右2pxまで確認する。
                this.findLineBounds(linePoints, left - 2, left + (int)labelWidth + 2,
                    pointY, lineTop, lineBottom);
                if (!this.findRankTop(left, lineTop, lineBottom, zeroY, (int)labelWidth,
                        (int)labelHeight, height, maximum - minimum, used, j == 0, labelTops[j])) {
                    pairReady = false;
                    break;
                }

                labelLefts[j] = left;
                labelWidths[j] = (int)labelWidth;
                labelHeights[j] = (int)labelHeight;
            }

            // 片方だけを残さず、上下の配置を確保できた変化点を一組で反映する。
            if (!pairReady) {
                continue;
            }

            if (!this.ensureItem(used) || !this.ensureItem(used + 1)) {
                succeeded = false;
                break;
            }

            labelIndexes[used / 2] = i;
            for (int j = 0; j < 2; j++) {
                this.items[used].left = labelLefts[j];
                this.items[used].top = labelTops[j];
                this.items[used].width = labelWidths[j];
                this.items[used].height = labelHeights[j];
                succeeded = this.updateItem(used, fromSubWindow, j, labelLefts[j],
                    labelTops[j], texts[j], tooltip) && succeeded;
                used++;
            }
        }

        // 全通貨順位の位置を先に確保し、追加文字によって順位の組を減らさない。
        int pairCount = used / 2;
        for (int i = 0; i < pairCount; i++) {
            int baseIndex = i * 2;
            if (!this.items[baseIndex].valuesReady || !this.items[baseIndex + 1].valuesReady) {
                continue;
            }

            int dataIndex = labelIndexes[i];
            int gap = (int)fromGap[dataIndex];
            int delta = gap - (int)fromGap[dataIndex + 1];
            string text = StringFormat("差 %+d（Δ%+d）", gap, delta);
            int gapPart = 2;
            if (delta < 0) {
                gapPart = 3;
            }

            uint labelWidth = 0;
            uint labelHeight = 0;
            if (!TextGetSize(text, labelWidth, labelHeight) || labelWidth == 0 || labelHeight == 0) {
                succeeded = false;
                continue;
            }

            int left = 0;
            int top = 0;
            if (!this.findGapPosition(linePoints, linePoints[dataIndex - newest].top,
                    baseIndex, (int)labelWidth, (int)labelHeight, width, height,
                    maximum - minimum, used, left, top)) {
                continue;
            }

            if (!this.ensureItem(used)) {
                succeeded = false;
                break;
            }

            this.items[used].left = left;
            this.items[used].top = top;
            this.items[used].width = (int)labelWidth;
            this.items[used].height = (int)labelHeight;
            succeeded = this.updateItem(used, fromSubWindow, gapPart, left, top,
                text, this.items[baseIndex].tooltip) && succeeded;
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
        ResetLastError();
        int removedCount = ObjectsDeleteAll(this.chartId, this.prefix, -1, OBJ_LABEL);
        if (GetLastError() == 0) {
            ArrayFree(this.items);
        }

        this.lastViewKey = "";
        if (removedCount > 0) {
            this.requestRedraw();
        }
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

    /** 基軸・決済・買い方向の差分・売り方向の差分の固定色。 */
    color colors[4];

    /** 線と文字の距離。順位差1を1目盛りとする上下共通の値。 */
    double lineGapUnits;

    /** 所有ラベルの設定と今回の配置位置。 */
    CurrencyStrengthRankGapLabelState items[];

    /** 右上の状態欄と再読込ボタンを描画するパネル。 */
    DrawCurrencyStrengthRankDeltaPanel *panel;

    /** MT5が左上の見出しに表示する短縮名。 */
    string shortName;

    /** 右上の3行、再読込ボタン、左上の見出しの順の占有矩形。 */
    CRect obstacles[5];

    /** 最後に正常配置した画面構成。 */
    string lastViewKey;

    /** イベント末尾でまとめる再描画要求先。 */
    ChartRedrawRequest *redrawRequest;

    /**
     * パネルと標準見出しの領域を求め、領域が変化した場合だけ再配置できるようにする。
     */
    bool prepareObstacles(const int fromSubWindow, const int fromWidth, string &toViewKey) {
        if (this.panel != NULL && !this.panel.getOccupiedBounds(fromSubWindow, fromWidth, this.obstacles)) {
            return false;
        }

        // MT5の標準見出しはオブジェクトではないため、短縮名と末尾の順位差・両順位の幅を見積もる。
        if (this.shortName != "") {
            uint textWidth = 0;
            uint textHeight = 0;
            if (!TextGetSize(this.shortName + "  -7  8  8", textWidth, textHeight)) {
                return false;
            }

            this.obstacles[4].SetBound(0, 0, 6 + (int)textWidth, 2 + (int)textHeight);
        }

        for (int i = 0; i < ArraySize(this.obstacles); i++) {
            toViewKey += StringFormat(":%d,%d,%d,%d", this.obstacles[i].left, this.obstacles[i].top,
                this.obstacles[i].right, this.obstacles[i].bottom);
        }

        return true;
    }

    /**
     * 候補となる文字の矩形が、表示中の見出し・パネルの項目と3pxの余白内で交わるか調べる。
     */
    bool overlapsObstacle(const int fromLeft, const int fromTop, const int fromWidth,
            const int fromHeight, const CRect &fromArea) {
        return fromArea.right > fromArea.left && fromArea.bottom > fromArea.top
            && fromLeft < fromArea.right + 3 && fromLeft + fromWidth + 3 > fromArea.left
            && fromTop < fromArea.bottom + 3 && fromTop + fromHeight + 3 > fromArea.top;
    }

    /**
     * 可視範囲の頂点を一度だけ座標化し、欠損は無効な頂点として残す。
     */
    bool prepareLinePoints(const int fromSubWindow, const double &fromGap[],
            const double &fromBarTime[], const int fromNewest, const int fromOldest,
            const int fromOffset, CurrencyStrengthRankGapLinePoint &toPoints[]) {
        int count = MathMax(0, fromOldest - fromNewest + 1);
        if (ArrayResize(toPoints, count) != count) {
            return false;
        }

        for (int i = 0; i < count; i++) {
            ZeroMemory(toPoints[i]);
            int bufferIndex = fromNewest + i;
            if (fromGap[bufferIndex] == EMPTY_VALUE || !MathIsValidNumber(fromGap[bufferIndex])
                    || !MathIsValidNumber(fromBarTime[bufferIndex]) || fromBarTime[bufferIndex] <= 0) {
                continue;
            }

            int left = 0;
            int top = 0;
            datetime barTime = (datetime)fromBarTime[bufferIndex];
            if (!ChartTimePriceToXY(this.chartId, fromSubWindow, barTime,
                    fromGap[bufferIndex], left, top)) {
                return false;
            }

            toPoints[i].valid = true;
            toPoints[i].time = barTime;
            toPoints[i].left = left;
            toPoints[i].top = top - fromOffset;
        }

        return true;
    }

    /**
     * 文字幅にかかる全線分を横方向で切り取り、その範囲の上下端を求める。
     * 欠損を跨いで接続せず、折り返し・同じ横座標の頂点も含める。
     */
    void findLineBounds(const CurrencyStrengthRankGapLinePoint &fromPoints[],
            const int fromLeft, const int fromRight, const int fromPointY,
            int &toTop, int &toBottom) {
        double top = fromPointY;
        double bottom = fromPointY;
        for (int i = 0; i < ArraySize(fromPoints) - 1; i++) {
            double segmentTop = 0.0;
            double segmentBottom = 0.0;
            if (!this.getSegmentBounds(fromPoints[i], fromPoints[i + 1], fromLeft, fromRight,
                    segmentTop, segmentBottom)) {
                continue;
            }

            top = MathMin(top, segmentTop);
            bottom = MathMax(bottom, segmentBottom);
        }

        toTop = (int)MathFloor(top);
        toBottom = (int)MathCeil(bottom);
    }

    /**
     * 1線分のうち文字幅にかかる部分だけを切り出し、縦座標の範囲を返す。
     */
    bool getSegmentBounds(const CurrencyStrengthRankGapLinePoint &fromNewer,
            const CurrencyStrengthRankGapLinePoint &fromOlder, const int fromLeft,
            const int fromRight, double &toTop, double &toBottom) {
        if (!fromNewer.valid || !fromOlder.valid || fromNewer.time <= fromOlder.time) {
            return false;
        }

        int left = MathMax(fromLeft, MathMin(fromOlder.left, fromNewer.left));
        int right = MathMin(fromRight, MathMax(fromOlder.left, fromNewer.left));
        if (left > right) {
            return false;
        }

        double leftY = fromOlder.top;
        double rightY = fromNewer.top;
        if (fromNewer.left != fromOlder.left) {
            double slope = (double)(fromNewer.top - fromOlder.top) / (fromNewer.left - fromOlder.left);
            leftY = fromOlder.top + (left - fromOlder.left) * slope;
            rightY = fromOlder.top + (right - fromOlder.left) * slope;
        }

        toTop = MathMin(leftY, rightY);
        toBottom = MathMax(leftY, rightY);

        return true;
    }

    /**
     * 比較可能な隣接足で順位差が変わったか確認する。同じM5枠は重複表示しない。
     */
    bool isChangedPoint(const double &fromGap[], const double &fromBaseRank[],
            const double &fromQuoteRank[], const double &fromBarTime[], const int fromIndex) {
        return fromGap[fromIndex] != EMPTY_VALUE && fromGap[fromIndex + 1] != EMPTY_VALUE
            && MathIsValidNumber(fromGap[fromIndex]) && MathIsValidNumber(fromGap[fromIndex + 1])
            && fromGap[fromIndex] != fromGap[fromIndex + 1]
            && fromBaseRank[fromIndex] >= 1 && fromBaseRank[fromIndex] <= 8
            && fromQuoteRank[fromIndex] >= 1 && fromQuoteRank[fromIndex] <= 8
            && fromBaseRank[fromIndex + 1] >= 1 && fromBaseRank[fromIndex + 1] <= 8
            && fromQuoteRank[fromIndex + 1] >= 1 && fromQuoteRank[fromIndex + 1] <= 8
            && fromBarTime[fromIndex + 1] > 0 && fromBarTime[fromIndex] > fromBarTime[fromIndex + 1]
            && (long)fromBarTime[fromIndex] / 300 != (long)fromBarTime[fromIndex + 1] / 300;
    }

    /**
     * 小さい順位への変化を上昇、大きい順位への変化を下降として付記する。
     */
    string formatRank(const int fromRank, const int fromPreviousRank) {
        string text = IntegerToString(fromRank);
        if (fromRank < fromPreviousRank) {
            return text + "↑";
        }

        if (fromRank > fromPreviousRank) {
            return text + "↓";
        }

        return text;
    }

    /**
     * 文字幅の塗り上端または下端から、既に配置した順位文字と重ならない最も近い位置を探す。
     * @param fromAbove 基軸順位を塗りの上側に置く場合true、決済順位を下側に置く場合false。
     * @param toTop 文字の上端のサブ画面内座標。
     * @return 指定側の画面内に文字が収まる場合true。
     */
    bool findRankTop(const int fromLeft, const int fromLineTop, const int fromLineBottom,
            const int fromZeroY, const int fromLabelWidth,
            const int fromLabelHeight, const int fromHeight,
            const double fromValueRange, const int fromUsed, const bool fromAbove, int &toTop) {
        if (this.lineGapUnits > fromValueRange) {
            return false;
        }

        // 縦軸の表示範囲に合わせて換算し、狭い画面でも文字高さの半分を空ける。
        double scaledGap = fromHeight * (this.lineGapUnits / fromValueRange);
        int lineGap = (int)MathCeil(MathMax(scaledGap, fromLabelHeight / 2.0));
        if (lineGap > fromHeight) {
            return false;
        }

        const int minimumTop = 4;
        int maximumTop = fromHeight - 4 - fromLabelHeight;
        int top = MathMax(minimumTop, MathMax(fromLineBottom, fromZeroY) + lineGap);
        if (fromAbove) {
            top = MathMin(maximumTop, MathMin(fromLineTop, fromZeroY) - lineGap - fromLabelHeight);
        }

        while (top >= minimumTop && top <= maximumTop) {
            int nextTop = top;
            for (int i = 0; i < ArraySize(this.obstacles); i++) {
                if (!this.overlapsObstacle(fromLeft, top, fromLabelWidth, fromLabelHeight, this.obstacles[i])) {
                    continue;
                }

                if (fromAbove) {
                    nextTop = MathMin(nextTop, this.obstacles[i].top - 3 - fromLabelHeight);
                } else {
                    nextTop = MathMax(nextTop, this.obstacles[i].bottom + 3);
                }
            }

            for (int i = 0; i < fromUsed; i++) {
                if (!this.overlapsLabel(fromLeft, top, fromLabelWidth, fromLabelHeight, this.items[i])) {
                    continue;
                }

                if (fromAbove) {
                    nextTop = MathMin(nextTop, this.items[i].top - 3 - fromLabelHeight);
                } else {
                    nextTop = MathMax(nextTop, this.items[i].top + this.items[i].height + 3);
                }
            }

            if (nextTop == top) {
                toTop = top;

                return true;
            }

            top = nextTop;
        }

        return false;
    }

    /**
     * 順位の組の右側を優先し、置けなければ左側で線に近い空き位置を探す。
     * 縦位置は変化点の高さ・線の上下・その近傍を候補とする。
     */
    bool findGapPosition(const CurrencyStrengthRankGapLinePoint &fromPoints[], const int fromPointY,
            const int fromBaseIndex, const int fromLabelWidth, const int fromLabelHeight,
            const int fromWidth, const int fromHeight, const double fromValueRange,
            const int fromUsed, int &toLeft, int &toTop) {
        if (this.lineGapUnits > fromValueRange || fromWidth < fromLabelWidth + 8) {
            return false;
        }

        double scaledGap = fromHeight * (this.lineGapUnits / fromValueRange);
        int lineGap = (int)MathCeil(MathMax(scaledGap, fromLabelHeight / 2.0));
        int textGap = (int)MathCeil(fromLabelHeight / 2.0);
        const int minimumTop = 4;
        int maximumTop = fromHeight - 4 - fromLabelHeight;
        if (maximumTop < minimumTop) {
            return false;
        }

        for (int i = 0; i < 2; i++) {
            int left = MathMax(this.items[fromBaseIndex].left + this.items[fromBaseIndex].width,
                this.items[fromBaseIndex + 1].left + this.items[fromBaseIndex + 1].width) + textGap;
            if (i == 1) {
                left = MathMin(this.items[fromBaseIndex].left, this.items[fromBaseIndex + 1].left)
                    - textGap - fromLabelWidth;
            }

            if (left < 4 || left + fromLabelWidth > fromWidth - 4) {
                continue;
            }

            int lineTop = fromPointY;
            int lineBottom = fromPointY;
            this.findLineBounds(fromPoints, left - 2, left + fromLabelWidth + 2,
                fromPointY, lineTop, lineBottom);
            int centerTop = MathMax(minimumTop, MathMin(maximumTop, fromPointY - fromLabelHeight / 2));
            int tops[11];
            tops[0] = centerTop;
            tops[1] = lineTop - lineGap - fromLabelHeight;
            tops[2] = lineBottom + lineGap;
            for (int j = 0; j < 4; j++) {
                int distance = (j + 1) * (fromLabelHeight + 4);
                tops[3 + j * 2] = centerTop - distance;
                tops[4 + j * 2] = centerTop + distance;
            }

            int bestDistance = fromHeight + 1;
            for (int j = 0; j < ArraySize(tops); j++) {
                int top = MathMax(minimumTop, MathMin(maximumTop, tops[j]));
                int distance = MathAbs(top - centerTop);
                if (distance >= bestDistance || !this.isTopFree(fromPoints, left, top,
                        fromLabelWidth, fromLabelHeight, lineGap, fromUsed)) {
                    continue;
                }

                bestDistance = distance;
                toLeft = left;
                toTop = top;
            }

            if (bestDistance <= fromHeight) {
                return true;
            }
        }

        return false;
    }

    /**
     * 文字の実矩形と余白が既存文字や有効線分に重ならないか調べる。
     */
    bool isTopFree(const CurrencyStrengthRankGapLinePoint &fromPoints[], const int fromLeft,
            const int fromTop, const int fromWidth, const int fromHeight,
            const int fromLineGap, const int fromUsed) {
        for (int i = 0; i < ArraySize(this.obstacles); i++) {
            if (this.overlapsObstacle(fromLeft, fromTop, fromWidth, fromHeight, this.obstacles[i])) {
                return false;
            }
        }

        for (int i = 0; i < fromUsed; i++) {
            if (this.overlapsLabel(fromLeft, fromTop, fromWidth, fromHeight, this.items[i])) {
                return false;
            }
        }

        for (int i = 0; i < ArraySize(fromPoints) - 1; i++) {
            double segmentTop = 0.0;
            double segmentBottom = 0.0;
            if (this.getSegmentBounds(fromPoints[i], fromPoints[i + 1], fromLeft - 2,
                    fromLeft + fromWidth + 2, segmentTop, segmentBottom)
                    && segmentBottom > fromTop - fromLineGap
                    && segmentTop < fromTop + fromHeight + fromLineGap) {
                return false;
            }
        }

        return true;
    }

    /**
     * 配置済み文字の矩形と3pxの余白が重なるか判定する。
     */
    bool overlapsLabel(const int fromLeft, const int fromTop, const int fromWidth,
            const int fromHeight, const CurrencyStrengthRankGapLabelState &fromItem) {
        return fromLeft < fromItem.left + fromItem.width + 3 && fromLeft + fromWidth + 3 > fromItem.left
            && fromTop < fromItem.top + fromItem.height + 3 && fromTop + fromHeight + 3 > fromItem.top;
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
     * 描画名をラベルの表示枠から生成する。
     */
    string getObjectName(const int fromIndex) {
        return this.prefix + IntegerToString(fromIndex);
    }

    /**
     * 同じ画面でも、外部操作で消去されたラベルがあれば再配置する。
     */
    bool objectsReady(const int fromSubWindow) {
        for (int i = 0; i < ArraySize(this.items); i++) {
            if (!this.items[i].created || !this.items[i].valuesReady
                    || ObjectFind(this.chartId, this.getObjectName(i)) != fromSubWindow) {
                return false;
            }
        }

        return true;
    }

    /**
     * フォント・表示色・操作可否など、固定項目を作成時だけ設定する。
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
     * 順位・差分ラベルを作成または再利用し、変更項目だけ反映する。
     */
    bool updateItem(const int fromIndex, const int fromSubWindow, const int fromPart,
            const int fromLeft, const int fromTop, const string fromText, const string fromTooltip) {
        string objectName = this.getObjectName(fromIndex);
        int objectWindow = ObjectFind(this.chartId, objectName);
        if (objectWindow != fromSubWindow || !this.items[fromIndex].created) {
            this.items[fromIndex].valuesReady = false;
            this.items[fromIndex].created = false;
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
            if (!this.configureItem(objectName, fromPart)) {
                return false;
            }

            this.items[fromIndex].created = true;
        }

        bool succeeded = true;
        if (!this.items[fromIndex].valuesReady || this.items[fromIndex].lastPart != fromPart) {
            succeeded = ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.colors[fromPart]) && succeeded;
            this.requestRedraw();
        }

        if (!this.items[fromIndex].valuesReady || this.items[fromIndex].lastLeft != fromLeft) {
            succeeded = ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, fromLeft) && succeeded;
            this.requestRedraw();
        }

        if (!this.items[fromIndex].valuesReady || this.items[fromIndex].lastTop != fromTop) {
            succeeded = ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, fromTop) && succeeded;
            this.requestRedraw();
        }

        if (!this.items[fromIndex].valuesReady || this.items[fromIndex].text != fromText) {
            succeeded = ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText) && succeeded;
            this.requestRedraw();
        }

        if (!this.items[fromIndex].valuesReady || this.items[fromIndex].tooltip != fromTooltip) {
            succeeded = ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, fromTooltip) && succeeded;
            this.requestRedraw();
        }

        this.items[fromIndex].valuesReady = succeeded;
        if (succeeded) {
            this.items[fromIndex].lastPart = fromPart;
            this.items[fromIndex].lastLeft = fromLeft;
            this.items[fromIndex].lastTop = fromTop;
            this.items[fromIndex].text = fromText;
            this.items[fromIndex].tooltip = fromTooltip;
        }

        return succeeded;
    }

    /**
     * 今回不要になったラベルを削除する。失敗した枠は再試行用に保持する。
     */
    bool trimItems(const int fromUsed) {
        bool succeeded = true;
        for (int i = fromUsed; i < ArraySize(this.items); i++) {
            string objectName = this.getObjectName(i);
            if (ObjectFind(this.chartId, objectName) >= 0) {
                if (!ObjectDelete(this.chartId, objectName)) {
                    succeeded = false;
                    continue;
                }

                this.requestRedraw();
            }

            this.items[i].created = false;
            this.items[i].valuesReady = false;
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
