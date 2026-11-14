//+------------------------------------------------------------------+
//|                           DrawCurrencyStrengthRankGapFill.mqh    |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_FILL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_FILL_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

/**
 * 順位差とゼロの間を、直近の変化方向を引き継いで塗り分ける。
 * 可視範囲の隣接足だけを描き、欠損を接続せず、ゼロ交差も線に沿わせる。
 */
class DrawCurrencyStrengthRankGapFill {
public:
    /**
     * このインスタンス専用の描画先と再描画要求先を保持する。
     */
    DrawCurrencyStrengthRankGapFill(const long fromChartId, const string fromObjectSuffix,
            ChartRedrawRequest *fromRedrawRequest) {
        this.chartId = fromChartId;
        string prefix = Constant::PREFIX_FIXED + "RankGapFill_";
        this.objectName = prefix + StringSubstr(fromObjectSuffix, 0, 63 - StringLen(prefix));
        this.redrawRequest = fromRedrawRequest;
        this.created = false;
        this.windowIndex = -1;
        this.lastViewKey = "";
    }

    /**
     * 所有する画像とオブジェクトを解放する。
     */
    ~DrawCurrencyStrengthRankGapFill() {
        this.clear();
    }

    /**
     * データまたは画面が変わった場合だけ、可視範囲の塗りを更新する。
     *
     * @param fromSubWindow 描画先のサブウィンドウ。
     * @param fromGap 最新足が添字0の順位差バッファ。欠損はEMPTY_VALUE。
     * @param fromBarTime 同じ添字に対応するチャート足時刻。欠損は0。
     * @param fromDataChanged 前回描画後にバッファが変更された場合true。
     * @return 描画済み、または変更不要の場合true。失敗時は再試行が必要。
     */
    bool draw(const int fromSubWindow, const double &fromGap[], const double &fromBarTime[],
            const bool fromDataChanged) {
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

        int count = MathMin(ArraySize(fromGap), ArraySize(fromBarTime));
        string viewKey = StringFormat("%d:%d:%d:%d:%d:%d:%d:%d:%.12f:%.12f:%.8f:%d",
            fromSubWindow, width, height, offset, firstVisible, visibleBars, scale, count,
            minimum, maximum, shiftSize, (int)shifted);
        bool objectReady = this.created && this.windowIndex == fromSubWindow
            && ObjectFind(this.chartId, this.objectName) == fromSubWindow;
        if (objectReady && !fromDataChanged && this.lastViewKey == viewKey) {
            return true;
        }

        if (!this.prepareCanvas(fromSubWindow, width, height, objectReady)) {
            this.lastViewKey = "";

            return false;
        }

        this.canvas.Erase(0);
        bool rendered = this.renderSegments(fromGap, fromBarTime, count, firstVisible,
            visibleBars, fromSubWindow, offset, width, height);
        ResetLastError();
        this.canvas.Update(false);
        bool updated = GetLastError() == 0;
        this.requestRedraw();
        if (!rendered || !updated) {
            this.lastViewKey = "";

            return false;
        }

        this.lastViewKey = viewKey;

        return true;
    }

    /**
     * このインスタンスの画像とオブジェクトだけを削除する。
     */
    void clear() {
        bool hadCanvas = this.created;
        this.canvas.Destroy();
        this.created = false;
        this.windowIndex = -1;
        this.lastViewKey = "";
        if (hadCanvas) {
            this.requestRedraw();
        }
    }

private:
    /** 描画対象チャート。 */
    long chartId;

    /** このインスタンス専用の画像オブジェクト名。 */
    string objectName;

    /** イベント内の再描画要求先。 */
    ChartRedrawRequest *redrawRequest;

    /** 可視範囲だけを塗る透過Canvas。 */
    CCanvas canvas;

    /** Canvasの作成完了状態。 */
    bool created;

    /** Canvasを配置したサブウィンドウ番号。 */
    int windowIndex;

    /** 最後に正常描画した画面の構成。 */
    string lastViewKey;

    /**
     * サブウィンドウの背景に、操作を受けない画像を作成または再配置する。
     */
    bool prepareCanvas(const int fromSubWindow, const int fromWidth, const int fromHeight,
            const bool fromObjectReady) {
        if (!fromObjectReady) {
            this.clear();
            if (!this.canvas.CreateBitmapLabel(this.chartId, fromSubWindow, this.objectName,
                    0, 0, fromWidth, fromHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
                this.canvas.Destroy();
                ObjectDelete(this.chartId, this.objectName);

                return false;
            }

            this.created = true;
            this.windowIndex = fromSubWindow;
            if (!ObjectSetInteger(this.chartId, this.objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_BACK, true)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_SELECTED, false)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_HIDDEN, true)
                    || !ObjectSetInteger(this.chartId, this.objectName, OBJPROP_ZORDER, 0)
                    || !ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, "\n")) {
                this.clear();

                return false;
            }
        } else if (this.canvas.Width() != fromWidth || this.canvas.Height() != fromHeight) {
            if (!this.canvas.Resize(fromWidth, fromHeight)) {
                this.clear();

                return false;
            }
        }

        return true;
    }

    /**
     * 各区間を画面座標へ変換し、比較できる隣接足の間だけを塗る。
     * 同値では直前の色を維持し、欠損区間では方向をリセットする。
     */
    bool renderSegments(const double &fromGap[], const double &fromBarTime[],
            const int fromCount, const int fromFirstVisible, const int fromVisibleBars,
            const int fromSubWindow, const int fromOffset, const int fromWidth, const int fromHeight) {
        int oldest = MathMin(fromCount - 1, fromFirstVisible + 1);
        int newest = MathMax(0, fromFirstVisible - fromVisibleBars - 1);
        bool result = true;
        bool zeroReady = false;
        int zeroY = 0;
        color fillColor = this.getPreviousFillColor(fromGap, fromBarTime, fromCount, oldest);
        for (int i = oldest - 1; i >= newest; i--) {
            if (!this.isSegmentAvailable(fromGap, fromBarTime, i)) {
                fillColor = C'38,38,38';
                continue;
            }

            if (fromGap[i] > fromGap[i + 1]) {
                fillColor = C'0,51,51';
            } else if (fromGap[i] < fromGap[i + 1]) {
                fillColor = C'51,21,36';
            }

            int olderX = 0;
            int olderY = 0;
            int newerX = 0;
            int newerY = 0;
            if (!ChartTimePriceToXY(this.chartId, fromSubWindow,
                    (datetime)fromBarTime[i + 1], fromGap[i + 1], olderX, olderY)
                    || !ChartTimePriceToXY(this.chartId, fromSubWindow,
                        (datetime)fromBarTime[i], fromGap[i], newerX, newerY)) {
                result = false;
                continue;
            }

            if (!zeroReady) {
                int ignoredX = 0;
                if (!ChartTimePriceToXY(this.chartId, fromSubWindow,
                        (datetime)fromBarTime[i], 0.0, ignoredX, zeroY)) {
                    result = false;
                    continue;
                }

                zeroY -= fromOffset;
                zeroReady = true;
            }

            this.fillSegment(olderX, olderY - fromOffset, newerX, newerY - fromOffset,
                zeroY, fromWidth, fromHeight, ColorToARGB(fillColor));
        }

        return result;
    }

    /**
     * 可視範囲の左端へ引き継ぐ色を、保持済みの古い隣接足から求める。
     * 最初の変化または欠損で探索を止め、方向不明なら灰色を返す。
     */
    color getPreviousFillColor(const double &fromGap[], const double &fromBarTime[],
            const int fromCount, const int fromIndex) {
        if (fromIndex < 0) {
            return C'38,38,38';
        }

        for (int i = fromIndex; i < fromCount - 1; i++) {
            if (!this.isSegmentAvailable(fromGap, fromBarTime, i)) {
                break;
            }

            if (fromGap[i] > fromGap[i + 1]) {
                return C'0,51,51';
            }

            if (fromGap[i] < fromGap[i + 1]) {
                return C'51,21,36';
            }
        }

        return C'38,38,38';
    }

    /**
     * 配列範囲内の隣接2足が、順位差と時刻を比較できる状態か判定する。
     */
    bool isSegmentAvailable(const double &fromGap[], const double &fromBarTime[],
            const int fromIndex) {
        return fromGap[fromIndex] != EMPTY_VALUE && fromGap[fromIndex + 1] != EMPTY_VALUE
            && fromBarTime[fromIndex] > 0 && fromBarTime[fromIndex + 1] > 0
            && fromBarTime[fromIndex] > fromBarTime[fromIndex + 1];
    }

    /**
     * 折れ線を横1pxずつ補間し、ゼロとの間だけを塗る。
     * 線の境界とゼロの1pxを空け、明るい線と基準線を覆わない。
     */
    void fillSegment(const int fromOlderX, const int fromOlderY, const int fromNewerX,
            const int fromNewerY, const int fromZeroY, const int fromWidth,
            const int fromHeight, const uint fromColor) {
        if (fromNewerX <= fromOlderX) {
            return;
        }

        int left = MathMax(0, fromOlderX);
        int right = MathMin(fromWidth - 1, fromNewerX - 1);
        for (int i = left; i <= right; i++) {
            double fraction = (double)(i - fromOlderX) / (fromNewerX - fromOlderX);
            double lineY = fromOlderY + (fromNewerY - fromOlderY) * fraction;
            int top = fromZeroY + 1;
            int bottom = (int)MathFloor(lineY) - 1;
            if (lineY < fromZeroY) {
                top = (int)MathCeil(lineY) + 1;
                bottom = fromZeroY - 1;
            }

            top = MathMax(0, top);
            bottom = MathMin(fromHeight - 1, bottom);
            if (top <= bottom) {
                this.canvas.LineVertical(i, top, bottom, fromColor);
            }
        }
    }

    /**
     * 画像の更新または削除をイベント末尾の再描画へ集約する。
     */
    void requestRedraw() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        } else {
            ChartRedraw(this.chartId);
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_GAP_FILL_MQH
