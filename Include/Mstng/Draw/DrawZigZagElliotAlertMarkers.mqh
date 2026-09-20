#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_MARKERS_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_MARKERS_MQH

#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>

/**
 * 通常ラベルへ設定したツールチップの所有情報。
 */
struct ZigZagElliotAlertTooltipOverride {
    string objectName;
    string originalTooltip;
    string appliedTooltip;
};

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
     * 一覧ラベルと引出線を削除し、通常ラベルのツールチップを戻す。
     */
    void clear() {
        for (int i = 0; i < ArraySize(this.tooltipOverrides); i++) {
            if (ObjectFind(this.chartId, this.tooltipOverrides[i].objectName) >= 0
                    && ObjectGetString(this.chartId, this.tooltipOverrides[i].objectName, OBJPROP_TOOLTIP)
                        == this.tooltipOverrides[i].appliedTooltip) {
                ObjectSetString(this.chartId, this.tooltipOverrides[i].objectName, OBJPROP_TOOLTIP,
                    this.tooltipOverrides[i].originalTooltip);
            }
        }
        ArrayFree(this.tooltipOverrides);
        ObjectsDeleteAll(this.chartId, this.prefix + "Marker-");
        ObjectsDeleteAll(this.chartId, this.prefix + "MarkerLink-");
    }

    /**
     * 表示範囲内の全ラベルを描画する。範囲外の記録もスクロール時に再評価する。
     *
     * @param fromExistingTextPrefix 重複を避ける通常ラベルの接頭辞。空は重複検査なし。
     * @param fromKnownTime 表示してよい判定時刻の上限。0は制限なし。
     */
    void draw(const ZigZagElliotAlertHistoryMarker &fromMarkers[],
            const string fromExistingTextPrefix = "", const datetime fromKnownTime = 0) {
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
            if (fromKnownTime > 0 && (fromMarkers[i].barTime > fromKnownTime
                    || fromMarkers[i].serverTime > fromKnownTime)) {
                continue;
            }
            if (fromExistingTextPrefix != "") {
                string existingName = fromExistingTextPrefix + IntegerToString((long)fromMarkers[i].barTime);
                if (ObjectFind(this.chartId, existingName) >= 0
                        && ObjectGetString(this.chartId, existingName, OBJPROP_TEXT) == fromMarkers[i].text
                        && ObjectGetInteger(this.chartId, existingName, OBJPROP_COLOR) == this.textColor(fromMarkers[i])) {
                    this.overrideTooltip(existingName, this.tooltip(fromMarkers[i]));
                    continue;
                }
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
    /** 通常ラベルへ設定したツールチップ。 */
    ZigZagElliotAlertTooltipOverride tooltipOverrides[];

    /**
     * 元のツールチップを一度だけ保持して、保存時点の情報へ切り替える。
     */
    void overrideTooltip(const string fromName, const string fromTooltip) {
        int index = -1;
        for (int i = 0; i < ArraySize(this.tooltipOverrides); i++) {
            if (this.tooltipOverrides[i].objectName == fromName) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            index = ArraySize(this.tooltipOverrides);
            if (ArrayResize(this.tooltipOverrides, index + 1) != index + 1) {
                return;
            }
            this.tooltipOverrides[index].objectName = fromName;
            this.tooltipOverrides[index].originalTooltip = ObjectGetString(this.chartId, fromName, OBJPROP_TOOLTIP);
        }
        this.tooltipOverrides[index].appliedTooltip = fromTooltip;
        ObjectSetString(this.chartId, fromName, OBJPROP_TOOLTIP, fromTooltip);
    }

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
     * 保存された判定日時を月日・時分に短縮する。現在の時差では補完しない。
     */
    string timeText(const datetime fromTime) {
        MqlDateTime parts;
        if (fromTime <= 0 || !TimeToStruct(fromTime, parts)) {
            return "—";
        }
        return StringFormat("%02d/%02d %02d:%02d", parts.mon, parts.day, parts.hour, parts.min);
    }

    /**
     * セル内の改行を取り除く。極端に長い値は省略を明示する。
     */
    string cellText(string fromText, const int fromLimit = 0) {
        StringReplace(fromText, "\r", " ");
        StringReplace(fromText, "\n", " ");
        StringReplace(fromText, "\t", " ");
        StringTrimLeft(fromText);
        StringTrimRight(fromText);
        if (StringLen(fromText) == 0) {
            return "—";
        }
        if (fromLimit > 0 && StringLen(fromText) > fromLimit) {
            return StringSubstr(fromText, 0, fromLimit - 1) + "…";
        }
        return fromText;
    }

    /**
     * 有効な保存方向のみを表示する。
     */
    string directionText(const string fromDirection) {
        if (fromDirection == "B" || fromDirection == "S") {
            return fromDirection;
        }
        return "—";
    }

    /**
     * 採用分析のM5は7時間足、H1は5時間足を作る。欠損値は他の分析から補完しない。
     */
    string waveRows(const ZigZagElliotAlertHistoryMarker &fromMarker, const bool fromIncludeSub,
            const int fromMainLimit = 0) {
        string frames[] = {"MN1", "W1", "D1", "H4", "H1", "M15", "M5"};
        string text = "\n足 分析/EMA 波動";
        int frameCount = ArraySize(frames);
        if (fromMarker.timeFrame == PERIOD_H1) {
            frameCount = 5;
        }
        for (int i = 0; i < frameCount; i++) {
            string wave = this.cellText(fromMarker.waves[i].wave, fromMainLimit);
            if (fromIncludeSub && wave != "—" && StringLen(fromMarker.waves[i].subWave) > 0) {
                wave += "." + this.cellText(fromMarker.waves[i].subWave);
            }
            string state = "—";
            if (fromMarker.waves[i].state == "確" || fromMarker.waves[i].state == "未") {
                state = fromMarker.waves[i].state;
            }
            string ema = "—";
            if (i > 0) {
                ema = this.directionText(fromMarker.waves[i].emaDirection);
            }
            text += "\n" + frames[i] + " " + this.directionText(fromMarker.waves[i].direction)
                + "/" + ema + " " + wave + state;
        }
        return text;
    }

    /**
     * 159文字を超える場合はServer行、副次波の順で省く。全時間足とJSTは残す。
     */
    string tooltip(const ZigZagElliotAlertHistoryMarker &fromMarker) {
        string header = "採用 ";
        if (fromMarker.correctionStatus != "NONE" && fromMarker.correctionStatus != "APPLIED") {
            header = "元分析(未記録) ";
        }
        string entry = this.cellText(fromMarker.entryResult);
        if (StringLen(entry) > 12) {
            entry = "非ENTRY";
            if (fromMarker.isEntry == 1) {
                entry = "ENTRY";
            }
        }
        header += this.cellText(fromMarker.side, 4) + "/" + entry;
        string correction = "";
        if (fromMarker.correctionStatus == "APPLIED") {
            correction = fromMarker.correctionText;
            StringReplace(correction, "BUY", "B");
            StringReplace(correction, "SELL", "S");
            StringReplace(correction, "H1 ", "H1補正 ");
            StringReplace(correction, "H4 ", "H4補正 ");
            correction = "\n" + this.cellText(correction, 12);
        }
        string tail = correction + "\nJST " + this.timeText(fromMarker.jstTime);
        string text = header + this.waveRows(fromMarker, true) + tail
            + "\nSV " + this.timeText(fromMarker.serverTime);
        if (StringLen(text) <= 159) {
            return text;
        }
        text = header + this.waveRows(fromMarker, true) + tail;
        if (StringLen(text) <= 159) {
            return text;
        }
        text = header + this.waveRows(fromMarker, false) + tail;
        for (int i = 4; StringLen(text) > 159 && i >= 1; i--) {
            text = header + this.waveRows(fromMarker, false, i) + tail;
        }
        return text;
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
