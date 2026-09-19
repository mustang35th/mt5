#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_MARKERS_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_MARKERS_MQH

#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>

/**
 * 保存ラベルを表示領域に配置する。全件の保存座標は変更せず、リサイズ時に再配置する。
 */
class DrawZigZagElliotAlertMarkers {
public:
    /**
     * この履歴インスタンスの接頭辞を保持する。
     */
    DrawZigZagElliotAlertMarkers(const long fromChartId, const string fromPrefix) {
        this.chartId = fromChartId;
        this.prefix = fromPrefix;
    }

    /**
     * 一覧ラベルとその引出線だけを削除する。
     */
    void clear() {
        ObjectsDeleteAll(this.chartId, this.prefix + "Marker-");
        ObjectsDeleteAll(this.chartId, this.prefix + "MarkerLink-");
    }

    /**
     * 表示範囲内の全ラベルを描画する。範囲外の記録もスクロール時に再評価する。
     */
    void draw(const ZigZagElliotAlertHistoryMarker &fromMarkers[]) {
        this.clear();
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        if (chartWidth <= 20 || chartHeight <= 40) {
            return;
        }
        ArrayFree(this.occupied);
        this.reservePanel(this.prefix + "Wave-Panel");
        this.reservePanel(this.prefix + "Ui-Background");
        TextSetFont("MS Gothic", -200);
        for (int i = 0; i < ArraySize(fromMarkers); i++) {
            if (!fromMarkers[i].available) {
                continue;
            }
            int pointX = 0;
            int pointY = 0;
            if (!ChartTimePriceToXY(this.chartId, 0, fromMarkers[i].barTime, fromMarkers[i].price, pointX, pointY)
                    || pointX < 0 || pointX >= chartWidth || pointY < 0 || pointY >= chartHeight) {
                continue;
            }
            uint textWidth = 0;
            uint textHeight = 0;
            if (!TextGetSize(fromMarkers[i].text, textWidth, textHeight)) {
                continue;
            }
            int width = (int)textWidth + 8;
            int height = (int)textHeight + 6;
            int textX = (int)MathMax(4, MathMin(pointX - width / 2, chartWidth - width - 4));
            int textY = (int)MathMax(4, MathMin(pointY - height / 2, chartHeight - height - 4));
            int initialY = textY;
            int steps = chartHeight / height + 1;
            for (int j = 0; j < steps * 2; j++) {
                int offset = ((j + 1) / 2) * height;
                if (j % 2 == 1) {
                    offset = -offset;
                }
                int candidateY = initialY + offset;
                if (candidateY < 4 || candidateY + height > chartHeight - 4) {
                    continue;
                }
                if (!this.overlaps(textX, candidateY, width, height)) {
                    textY = candidateY;
                    break;
                }
            }
            this.reserve(textX, textY, width, height);
            string name = this.prefix + "Marker-" + IntegerToString(fromMarkers[i].alertId);
            if (!ObjectCreate(this.chartId, name, OBJ_LABEL, 0, 0, 0)) {
                continue;
            }
            ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, textX);
            ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, textY);
            ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 20);
            ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, this.textColor(fromMarkers[i]));
            ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 10);
            ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic");
            ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromMarkers[i].text);
            ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, this.tooltip(fromMarkers[i]));
            if (textY != initialY) {
                this.drawLink(fromMarkers[i], textX + width / 2, textY + height / 2);
            }
        }
    }

private:
    /** 表示先チャート。 */
    long chartId;
    /** 履歴インスタンスの接頭辞。 */
    string prefix;
    /** 配置済み領域の左・上・幅・高さ。 */
    int occupied[][4];

    /**
     * パネルと既存ラベルの占有領域を追加する。
     */
    void reserve(const int fromX, const int fromY, const int fromWidth, const int fromHeight) {
        int count = ArrayRange(this.occupied, 0);
        if (ArrayResize(this.occupied, count + 1, 128) < 0) {
            return;
        }
        this.occupied[count][0] = fromX;
        this.occupied[count][1] = fromY;
        this.occupied[count][2] = fromWidth;
        this.occupied[count][3] = fromHeight;
    }

    /**
     * 保存情報と操作欄をラベル配置から除外する。
     */
    void reservePanel(const string fromName) {
        if (ObjectFind(this.chartId, fromName) < 0) {
            return;
        }
        this.reserve((int)ObjectGetInteger(this.chartId, fromName, OBJPROP_XDISTANCE),
            (int)ObjectGetInteger(this.chartId, fromName, OBJPROP_YDISTANCE),
            (int)ObjectGetInteger(this.chartId, fromName, OBJPROP_XSIZE),
            (int)ObjectGetInteger(this.chartId, fromName, OBJPROP_YSIZE));
    }

    /**
     * 確保済みの領域との重なりを調べる。
     */
    bool overlaps(const int fromX, const int fromY, const int fromWidth, const int fromHeight) {
        for (int i = 0; i < ArrayRange(this.occupied, 0); i++) {
            if (fromX < this.occupied[i][0] + this.occupied[i][2]
                    && fromX + fromWidth > this.occupied[i][0]
                    && fromY < this.occupied[i][1] + this.occupied[i][3]
                    && fromY + fromHeight > this.occupied[i][1]) {
                return true;
            }
        }
        return false;
    }

    /**
     * 通常版と同じ保存方向・ENTRY成立色を返す。
     */
    color textColor(const ZigZagElliotAlertHistoryMarker &fromMarker) {
        if (fromMarker.side == "BUY") {
            if (fromMarker.isEntry == 1) {
                return clrDodgerBlue;
            }
            return clrBlue;
        }
        if (fromMarker.isEntry == 1) {
            return clrMagenta;
        }
        return clrRed;
    }

    /**
     * 未記録日時を現在の時差で補完しない。
     */
    string timeText(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }
        return TimeToString(fromTime, TIME_DATE | TIME_SECONDS);
    }

    /**
     * 159文字内で保存日時・ENTRY・補正情報を優先する。
     */
    string tooltip(const ZigZagElliotAlertHistoryMarker &fromMarker) {
        string text = "Alert " + IntegerToString(fromMarker.alertId)
            + "\n発生Server " + this.timeText(fromMarker.barTime)
            + "\n判定Server " + this.timeText(fromMarker.serverTime)
            + "\n判定JST " + this.timeText(fromMarker.jstTime)
            + "\n" + fromMarker.entryResult + " / " + fromMarker.side
            + "\n" + fromMarker.correctionText;
        return StringSubstr(text, 0, 159);
    }

    /**
     * 表示文字をずらした場合だけ、保存座標から文字へ引出線を描く。
     */
    void drawLink(const ZigZagElliotAlertHistoryMarker &fromMarker, const int fromX, const int fromY) {
        int subWindow = 0;
        datetime displayTime = 0;
        double displayPrice = 0;
        if (!ChartXYToTimePrice(this.chartId, fromX, fromY, subWindow, displayTime, displayPrice)
                || subWindow != 0) {
            return;
        }
        string name = this.prefix + "MarkerLink-" + IntegerToString(fromMarker.alertId);
        if (!ObjectCreate(this.chartId, name, OBJ_TREND, 0,
                fromMarker.barTime, fromMarker.price, displayTime, displayPrice)) {
            return;
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrDimGray);
        ObjectSetInteger(this.chartId, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(this.chartId, name, OBJPROP_RAY_LEFT, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, name, OBJPROP_BACK, true);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, "\n");
    }
};

#endif
