#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_HISTORY_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_ALERT_HISTORY_MQH

#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * Alert DBへ保存された最新Waveと判定値だけを描画する。
 * 相場の再取得・波動再分析・上位足ポイント時刻の再配置は行わない。
 */
class DrawZigZagElliotAlertHistory {
public:
    /**
     * このインスタンス専用の描画先とオブジェクト接頭辞を指定する。
     *
     * @param fromChartId 描画先チャート。
     * @param fromPrefix 他の描画と重複しない接頭辞。
     */
    DrawZigZagElliotAlertHistory(const long fromChartId, const string fromPrefix) {
        this.chartId = fromChartId;
        this.prefix = fromPrefix;
        if (this.prefix == "") {
            this.prefix = "ZigZagElliotAlertHistoryDraw" + IntegerToString(fromChartId) + ":";
        }
        this.logger.setLevel(LOG_INFO);
        this.hasDrawingError = false;
    }

    /**
     * 自分の描画だけを解放する。
     */
    ~DrawZigZagElliotAlertHistory() {
        this.clear();
    }

    /**
     * 指定された接頭辞に属するオブジェクトだけを削除する。
     */
    void clear() {
        if (this.prefix != "") {
            ObjectsDeleteAll(this.chartId, this.prefix, 0, -1);
        }
    }

    /**
     * 保存済み分析を指定モードで描画する。
     *
     * 番号の表示位置だけ画面座標でずらすため、チャート変更時は再度呼び出す。
     * 線の始終点とツールチップの時刻・価格は保存値のまま使用する。
     *
     * @param fromSnapshot 保存された元分析・補正分析。
     * @param fromView 補正後、補正前、前後比較の表示モード。
     * @param fromHigherCount 表示する上位足数。2または3。
     * @param fromShowPrices 参照価格・SL候補・M5 FE価格線の表示有無。
     * @param fromShowTable 7足の情報表の表示有無。
     * @param fromPanelTop 保存情報パネルの上端座標。
     */
    void draw(
        ZigZagElliotAlertHistorySnapshot &fromSnapshot,
        const ZigZagElliotAlertHistoryView fromView,
        const int fromHigherCount,
        const bool fromShowPrices,
        const bool fromShowTable,
        const int fromPanelTop = 8
    ) {
        this.clear();
        this.hasDrawingError = false;
        int higherCount = 2;
        if (fromHigherCount == 3) {
            higherCount = 3;
        }
        bool isApplied = fromSnapshot.originalAvailable
            && fromSnapshot.correctionStatus == "APPLIED";
        bool isComparison = isApplied && fromView == ALERT_HISTORY_COMPARISON;
        bool showCorrected = isApplied && fromView != ALERT_HISTORY_ORIGINAL;
        bool showOriginal = !showCorrected || isComparison;

        this.drawEventLine(fromSnapshot);
        if (fromSnapshot.originalAvailable) {
            if (showOriginal) {
                this.drawAnalysis(
                    fromSnapshot.originalTimeFrames, fromSnapshot.originalPoints,
                    false, isComparison, higherCount, fromShowPrices,
                    this.originalModeLabel(fromSnapshot.correctionStatus),
                    fromSnapshot.alert.currentBarTime
                );
            }
            if (showCorrected) {
                this.drawAnalysis(
                    fromSnapshot.correctedTimeFrames, fromSnapshot.correctedPoints,
                    true, isComparison, higherCount, fromShowPrices,
                    "補正後（採用）", fromSnapshot.alert.currentBarTime
                );
            }
        }
        if (fromShowPrices) {
            this.drawFixedPrices(fromSnapshot);
        }
        this.drawAlertLabels(fromSnapshot, showOriginal, showCorrected);
        this.drawPanel(fromSnapshot, showOriginal, showCorrected, fromShowTable, fromPanelTop);
        ChartRedraw(this.chartId);
    }

private:
    /** 描画先チャートID。 */
    long chartId;
    /** このインスタンスだけが管理するオブジェクト接頭辞。 */
    string prefix;
    /** 描画失敗を記録するロガー。 */
    Logger logger;
    /** 同じ描画中のエラーを重複出力しないための状態。 */
    bool hasDrawingError;

    /**
     * 元分析を採用済みと推測しない表示名を返す。
     */
    string originalModeLabel(const string fromStatus) {
        if (fromStatus == "NONE") {
            return "元分析（採用）";
        }
        if (fromStatus == "APPLIED") {
            return "補正前（比較用）";
        }
        return "元の保存分析（参考）";
    }

    /**
     * 保存価格として表示できる有限の正数かを確認する。
     */
    bool isPriceValid(const double fromPrice) {
        return MathIsValidNumber(fromPrice) && fromPrice != EMPTY_VALUE && fromPrice > 0.0;
    }

    /**
     * 保存値を表示用の価格文字列にする。
     */
    string priceText(const double fromPrice) {
        if (!this.isPriceValid(fromPrice)) {
            return "—";
        }
        return DoubleToString(fromPrice, this.priceDigits());
    }

    /**
     * 表示チャートの価格桁数を取得し、取得不能時は5桁にする。
     */
    int priceDigits() {
        long symbolDigits = 0;
        if (SymbolInfoInteger(ChartSymbol(this.chartId), SYMBOL_DIGITS, symbolDigits)
                && symbolDigits >= 0 && symbolDigits <= 16) {
            return (int)symbolDigits;
        }
        return 5;
    }

    /**
     * 有効な保存pips値へ単位と正負の符号を付ける。
     */
    string pipsText(const double fromPips) {
        if (!MathIsValidNumber(fromPips) || fromPips == EMPTY_VALUE) {
            return "—";
        }
        string text = DoubleToString(fromPips, 1);
        if (fromPips > 0.0) {
            text = "+" + text;
        }
        return text + " pips";
    }

    /**
     * 符号付きCount文字列を返す。
     */
    string signedCount(const int fromCount) {
        string text = IntegerToString(fromCount);
        if (fromCount > 0) {
            text = "+" + text;
        }
        return text;
    }

    /**
     * 保存された方向・確定状態に応じた通常版相当の色を返す。
     */
    color directionColor(const int fromIsBuy, const bool fromConfirmed = true) {
        if (fromIsBuy == 1) {
            if (!fromConfirmed) {
                return clrDodgerBlue;
            }
            return clrAqua;
        }
        if (fromIsBuy == 0) {
            if (!fromConfirmed) {
                return clrMagenta;
            }
            return clrHotPink;
        }
        return clrSilver;
    }

    /**
     * 通常版と同じく区間の価格上下と上位足の区別から線色を返す。
     */
    color segmentColor(const bool fromIsUptrend, const bool fromIsHigher) {
        if (fromIsUptrend) {
            if (fromIsHigher) {
                return clrBlue;
            }
            return clrDodgerBlue;
        }
        if (fromIsHigher) {
            return clrRed;
        }
        return clrMagenta;
    }

    /**
     * Countの正負を売買色へ変換する。
     */
    color countColor(const int fromCount) {
        if (fromCount > 0) {
            return clrAqua;
        }
        if (fromCount < 0) {
            return clrHotPink;
        }
        return clrSilver;
    }

    /**
     * 保存日時をServer時刻として表示する。
     */
    string timeText(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }
        return TimeToString(fromTime, TIME_DATE | TIME_SECONDS);
    }

    /**
     * オブジェクトを作成し、失敗時は描画1回につき1件だけ記録する。
     */
    bool createObject(
        const string fromName,
        const ENUM_OBJECT fromType,
        const datetime fromTime = 0,
        const double fromPrice = 0.0,
        const datetime fromNextTime = 0,
        const double fromNextPrice = 0.0
    ) {
        bool created = false;
        if (fromType == OBJ_TREND) {
            created = ObjectCreate(this.chartId, fromName, fromType, 0,
                fromTime, fromPrice, fromNextTime, fromNextPrice);
        } else {
            created = ObjectCreate(this.chartId, fromName, fromType, 0, fromTime, fromPrice);
        }
        if (!created) {
            if (!this.hasDrawingError) {
                this.logger.error(__FUNCTION__, StringFormat(
                    "history object creation failed. name=%s error=%d", fromName, GetLastError()
                ));
                this.hasDrawingError = true;
            }
            return false;
        }
        ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromName, OBJPROP_HIDDEN, true);
        return true;
    }

    /**
     * 専用接頭辞の固定座標文字を描画する。
     */
    void drawLabel(
        const string fromKey,
        const string fromText,
        const int fromX,
        const int fromY,
        const int fromSize,
        const color fromColor,
        const string fromTooltip,
        const ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER
    ) {
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        if (fromY < 0 || fromY + fromSize + 4 > chartHeight) {
            return;
        }
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_LABEL)) {
            return;
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, fromAnchor);
        ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX);
        ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, fromSize);
        ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 5);
        ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic");
        ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromTooltip);
    }

    /**
     * 保存アラートの発生足に縦線を描画する。
     */
    void drawEventLine(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        if (fromSnapshot.alert.currentBarTime <= 0) {
            return;
        }
        string name = this.prefix + "Event";
        if (!this.createObject(name, OBJ_VLINE, fromSnapshot.alert.currentBarTime)) {
            return;
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrGold);
        ObjectSetInteger(this.chartId, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(this.chartId, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, name, OBJPROP_BACK, true);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, this.eventTooltip(fromSnapshot));
    }

    /**
     * 発生位置とアラート文字で共用する保存判定の説明を返す。
     */
    string eventTooltip(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        string correctionText = "補正情報未記録 / 採用分析不明";
        if (fromSnapshot.correctionStatus == "NONE") {
            correctionText = "補正なし / 元分析採用";
        } else if (fromSnapshot.correctionStatus == "INCOMPLETE") {
            correctionText = "補正データ不完全 / " + fromSnapshot.correctionReason;
        } else if (fromSnapshot.correctionStatus == "APPLIED") {
            string frame = "H1";
            if (fromSnapshot.correction.correctionTimeFrame == PERIOD_H4) {
                frame = "H4";
            }
            correctionText = frame + " " + fromSnapshot.correction.originalDirection
                + " → " + fromSnapshot.correction.correctedDirection + " / 補正後採用";
        }
        string selectedSL = "—";
        if (fromSnapshot.originalAvailable
                && (fromSnapshot.correctionStatus == "APPLIED" || fromSnapshot.correctionStatus == "NONE")
                && fromSnapshot.correction.isSelectedStopLossAvailable == 1) {
            selectedSL = this.priceText(fromSnapshot.correction.selectedStopLoss)
                + " / " + this.pipsText(fromSnapshot.correction.selectedRiskPips);
        }
        string tooltip = "アラート発生足 Server " + this.timeText(fromSnapshot.alert.currentBarTime)
            + "\n判定日時 Server " + this.timeText(fromSnapshot.alert.serverTime)
            + "\n保存判定 " + fromSnapshot.alert.entryResult + " / " + fromSnapshot.alert.side
            + "\n補正内容 " + correctionText
            + "\n参照価格 " + this.priceText(fromSnapshot.alert.referencePrice)
            + "\n採用SL候補 " + selectedSL + "（実SLではありません）"
            + "\nAlert " + IntegerToString(fromSnapshot.alert.id)
            + " / Run " + IntegerToString(fromSnapshot.alert.runId);
        return tooltip;
    }

    /**
     * 通常版と同じ売買方向・ENTRY成立状態からアラート文字色を返す。
     */
    color alertTextColor(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        if (fromSnapshot.alert.side == "BUY") {
            if (fromSnapshot.alert.isEntry == 1) {
                return clrDodgerBlue;
            }
            return clrBlue;
        }
        if (fromSnapshot.alert.side == "SELL") {
            if (fromSnapshot.alert.isEntry == 1) {
                return clrMagenta;
            }
            return clrRed;
        }
        return clrLightGray;
    }

    /**
     * 保存済みの短いアラート文字を表示モードに合わせて発生足へ配置する。
     * 比較時は採用分析を始値の上、補正前を下へ並べる。
     */
    void drawAlertLabels(
        ZigZagElliotAlertHistorySnapshot &fromSnapshot,
        const bool fromShowOriginal,
        const bool fromShowCorrected
    ) {
        if (!fromSnapshot.originalAvailable || fromSnapshot.alert.currentBarTime <= 0) {
            return;
        }
        int m5Index = this.findTimeFrame(fromSnapshot.originalTimeFrames, PERIOD_M5);
        if (m5Index < 0 || !this.isPriceValid(fromSnapshot.originalTimeFrames[m5Index].currentOpen)) {
            return;
        }
        double alertPrice = fromSnapshot.originalTimeFrames[m5Index].currentOpen;
        bool isComparison = fromShowCorrected && fromShowOriginal;
        if (fromShowCorrected || fromSnapshot.correctionStatus == "NONE") {
            ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER;
            if (isComparison) {
                anchor = ANCHOR_LOWER;
            }
            string modeLabel = "元分析（採用）";
            if (fromShowCorrected) {
                modeLabel = "補正後（採用）";
            }
            this.drawAlertLabel(fromSnapshot, "AlertTextC", fromSnapshot.correction.selectedAlertText,
                modeLabel, alertPrice, anchor);
        }
        if (fromShowOriginal && fromSnapshot.correctionStatus != "NONE") {
            string text = fromSnapshot.alert.alertText;
            if (text != "" && fromSnapshot.correctionStatus == "APPLIED") {
                text += " [補正前]";
            }
            ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER;
            if (isComparison) {
                anchor = ANCHOR_UPPER;
            }
            this.drawAlertLabel(fromSnapshot, "AlertTextO", text,
                this.originalModeLabel(fromSnapshot.correctionStatus), alertPrice, anchor);
        }
    }

    /**
     * 保存されたM5始値・発生時刻に通常版と同じ文字列を描く。
     * 矢印や波動番号を現在の相場・売買方向から再生成しない。
     */
    void drawAlertLabel(
        ZigZagElliotAlertHistorySnapshot &fromSnapshot,
        const string fromKey,
        const string fromText,
        const string fromModeLabel,
        const double fromPrice,
        const ENUM_ANCHOR_POINT fromAnchor
    ) {
        if (fromText == "") {
            return;
        }
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_TEXT, fromSnapshot.alert.currentBarTime, fromPrice)) {
            return;
        }
        ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText);
        ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic");
        ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, this.alertTextColor(fromSnapshot));
        ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, fromAnchor);
        ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 5);
        string correctionText = "補正情報未記録";
        if (fromSnapshot.correctionStatus == "APPLIED") {
            string frame = "H1";
            if (fromSnapshot.correction.correctionTimeFrame == PERIOD_H4) {
                frame = "H4";
            }
            correctionText = frame + " " + fromSnapshot.correction.originalDirection
                + "→" + fromSnapshot.correction.correctedDirection;
        } else if (fromSnapshot.correctionStatus == "NONE") {
            correctionText = "補正なし";
        } else if (fromSnapshot.correctionStatus == "INCOMPLETE") {
            correctionText = "補正データ不完全";
        }
        string details = "\n" + correctionText
            + "\n発生Server " + this.timeText(fromSnapshot.alert.currentBarTime)
            + "\n判定Server " + this.timeText(fromSnapshot.alert.serverTime)
            + "\n判定JST " + this.timeText(fromSnapshot.alert.jstTime)
            + "\n" + fromSnapshot.alert.entryResult + " / " + fromSnapshot.alert.side
            + "\n始値 " + this.priceText(fromPrice);
        string tooltip = fromModeLabel + "\n▲▼=H1方向 / H1主.副-M15-M5" + details;
        // MT5の159文字制限を超える場合は説明を短縮し、保存日時と判定値を優先する。
        if (StringLen(tooltip) > 159) {
            tooltip = fromModeLabel + "\nH1主.副-M15-M5" + details;
        }
        if (StringLen(tooltip) > 159) {
            tooltip = fromModeLabel + details;
        }
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, tooltip);
    }

    /**
     * 指定時間足の保存行を検索する。
     */
    int findTimeFrame(ZigZagElliotAlertTimeFrameEntity &fromRows[], const int fromTimeFrame) {
        for (int i = 0; i < ArraySize(fromRows); i++) {
            if (fromRows[i].timeFrame == fromTimeFrame) {
                return i;
            }
        }
        return -1;
    }

    /**
     * 同じ分析配列から時間足とWave内順序が一致するポイントを探す。
     */
    int findPoint(
        ZigZagElliotAlertPointEntity &fromRows[],
        const int fromTimeFrame,
        const int fromPointOrder
    ) {
        for (int i = 0; i < ArraySize(fromRows); i++) {
            if (fromRows[i].timeFrame == fromTimeFrame && fromRows[i].pointOrder == fromPointOrder) {
                return i;
            }
        }
        return -1;
    }

    /**
     * 現在M5と指定された上位足の最新Waveを描画する。
     */
    void drawAnalysis(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
        ZigZagElliotAlertPointEntity &fromPoints[],
        const bool fromCorrected,
        const bool fromComparison,
        const int fromHigherCount,
        const bool fromShowPrices,
        const string fromModeLabel,
        const datetime fromEventTime
    ) {
        int timeFrames[] = { PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4 };
        for (int i = fromHigherCount; i >= 0; i--) {
            int rowIndex = this.findTimeFrame(fromTimeFrames, timeFrames[i]);
            if (rowIndex < 0) {
                continue;
            }
            this.drawWave(
                fromTimeFrames[rowIndex], fromPoints, fromCorrected,
                fromComparison, i, fromHigherCount, fromModeLabel
            );
        }
        if (fromShowPrices) {
            int m5Index = this.findTimeFrame(fromTimeFrames, PERIOD_M5);
            if (m5Index >= 0) {
                this.drawFiboPrices(
                    fromTimeFrames[m5Index], fromCorrected, fromComparison,
                    fromModeLabel, fromEventTime
                );
            }
        }
    }

    /**
     * 保存主波・副次波を表示文字列へまとめる。
     */
    string pointWaveLabel(ZigZagElliotAlertPointEntity &fromPoint) {
        string text = fromPoint.elliotLabel;
        if (text == "") {
            text = "—";
        }
        if (fromPoint.isSubElliotAvailable == 1 && fromPoint.subElliotLabel != "") {
            text += "." + fromPoint.subElliotLabel;
        }
        return text;
    }

    /**
     * 波動ポイントの保存値を改行したツールチップへまとめる。
     */
    string pointTooltip(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        ZigZagElliotAlertPointEntity &fromPoint,
        const string fromModeLabel
    ) {
        string state = "未確定";
        if (fromTimeFrame.isWaveConfirmed == 1) {
            state = "確定";
        }
        string text = fromTimeFrame.timeFrameText + " / " + fromModeLabel
            + "\n分析方向 " + fromTimeFrame.buySellLabel
            + "\n主波・副次波 " + this.pointWaveLabel(fromPoint)
            + "\nWave状態 " + state
            + "\nServer " + this.timeText(fromPoint.barTime)
            + "\n価格 " + this.priceText(fromPoint.rate);
        string fibo = "—";
        if (fromPoint.isFibonacciAvailable == 1) {
            fibo = DoubleToString(fromPoint.fibonacciPercent, 1) + "%";
        }
        string expansion = "—";
        if (fromPoint.isFibonacciExpansionAvailable == 1) {
            expansion = DoubleToString(fromPoint.fibonacciExpansionPercent, 1) + "%";
        }
        string originalLabel = "—";
        if (fromPoint.isOriginalElliotAvailable == 1 && fromPoint.orgElliotLabel != "") {
            originalLabel = fromPoint.orgElliotLabel;
        }
        text += "\nF " + fibo + " / FE " + expansion
            + "\n元番号 " + originalLabel
            + "\npips差 " + this.pipsText(fromPoint.pipsDiff);
        if (fromPoint.isAddedPoint == 1) {
            text += "\n取得種別 補完";
        } else {
            text += "\n取得種別 通常";
        }
        return text;
    }

    /**
     * 最新Waveの線と番号を保存順序で描画する。
     */
    void drawWave(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        ZigZagElliotAlertPointEntity &fromPoints[],
        const bool fromCorrected,
        const bool fromComparison,
        const int fromHigherIndex,
        const int fromHigherCount,
        const string fromModeLabel
    ) {
        string mode = "O";
        string modeText = "前";
        if (fromCorrected) {
            mode = "C";
            modeText = "後";
        }
        string key = "W" + mode + IntegerToString(fromTimeFrame.timeFrame);
        int lineStyle = STYLE_SOLID;
        int lineWidth = 2;
        if (fromComparison && !fromCorrected) {
            lineStyle = STYLE_DASH;
            lineWidth = 1;
        }
        for (int i = 1; i < fromTimeFrame.pointCount; i++) {
            int pointIndex = this.findPoint(fromPoints, fromTimeFrame.timeFrame, i);
            if (pointIndex < 0 || fromPoints[pointIndex].barTime <= 0
                    || !this.isPriceValid(fromPoints[pointIndex].rate)) {
                continue;
            }
            if (i > 0) {
                int previousIndex = this.findPoint(fromPoints, fromTimeFrame.timeFrame, i - 1);
                if (previousIndex >= 0 && fromPoints[previousIndex].barTime > 0
                        && this.isPriceValid(fromPoints[previousIndex].rate)) {
                    color lineColor = this.segmentColor(
                        fromPoints[previousIndex].rate < fromPoints[pointIndex].rate,
                        fromHigherIndex > 0
                    );
                    this.drawSegment(
                        key + "L" + IntegerToString(i), fromTimeFrame,
                        fromPoints[previousIndex], fromPoints[pointIndex],
                        lineColor, lineStyle, lineWidth, fromModeLabel
                    );
                }
            }
            string label = fromTimeFrame.timeFrameText + " " + this.pointWaveLabel(fromPoints[pointIndex]);
            if (fromComparison) {
                label = modeText + " " + label;
            }
            bool isLatestUnconfirmed = fromTimeFrame.isWaveConfirmed != 1
                && i == fromTimeFrame.pointCount - 1;
            if (isLatestUnconfirmed) {
                label = "[未] " + label;
            }
            color labelColor = this.directionColor(fromPoints[pointIndex].isPeak, !isLatestUnconfirmed);
            this.drawPointLabel(
                key + "P" + IntegerToString(i), label, fromTimeFrame, fromPoints[pointIndex],
                fromCorrected, fromComparison, fromHigherIndex, fromHigherCount,
                labelColor, fromModeLabel
            );
        }
    }

    /**
     * DBの始終点を動かさずに波動線を描画する。
     */
    void drawSegment(
        const string fromKey,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        ZigZagElliotAlertPointEntity &fromFirst,
        ZigZagElliotAlertPointEntity &fromLast,
        const color fromColor,
        const int fromStyle,
        const int fromWidth,
        const string fromModeLabel
    ) {
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_TREND, fromFirst.barTime, fromFirst.rate, fromLast.barTime, fromLast.rate)) {
            return;
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_RAY_LEFT, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, name, OBJPROP_STYLE, fromStyle);
        ObjectSetInteger(this.chartId, name, OBJPROP_WIDTH, fromWidth);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP,
            fromTimeFrame.timeFrameText + " / " + fromModeLabel
            + "\n始点 " + this.timeText(fromFirst.barTime) + " / " + this.priceText(fromFirst.rate)
            + "\n終点 " + this.timeText(fromLast.barTime) + " / " + this.priceText(fromLast.rate)
            + "\n価格差 " + DoubleToString(MathAbs(fromLast.rate - fromFirst.rate), this.priceDigits())
            + "\n保存pips差 " + this.pipsText(fromLast.pipsDiff)
        );
    }

    /**
     * 時刻を動かさず、番号だけ上位足・前後別の上下レーンへ配置する。
     */
    void drawPointLabel(
        const string fromKey,
        const string fromLabel,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        ZigZagElliotAlertPointEntity &fromPoint,
        const bool fromCorrected,
        const bool fromComparison,
        const int fromHigherIndex,
        const int fromHigherCount,
        const color fromColor,
        const string fromModeLabel
    ) {
        int pointX = 0;
        int pointY = 0;
        if (!ChartTimePriceToXY(this.chartId, 0, fromPoint.barTime, fromPoint.rate, pointX, pointY)) {
            return;
        }
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        if (pointX < 0 || pointX > chartWidth) {
            return;
        }
        int fontSize = 12 + fromHigherIndex * 2;
        int lane = 0;
        if (fromComparison && !fromCorrected) {
            lane = 1;
        }
        int offset = 15 + fromHigherIndex * 48 + lane * 24;
        if (fromPoint.isPeak == 1) {
            pointY -= offset;
        } else {
            pointY += offset;
        }
        int edgeOffset = (fromHigherCount - fromHigherIndex) * 42 + lane * 20;
        int topLimit = 115 + fontSize;
        if (pointY < topLimit) {
            pointY = topLimit + edgeOffset;
        }
        if (pointY > chartHeight - 24) {
            pointY = chartHeight - 24 - edgeOffset;
        }
        if (pointY < topLimit || pointY > chartHeight - 10) {
            return;
        }
        this.drawLabel(
            fromKey, fromLabel, pointX, pointY, fontSize, fromColor,
            this.pointTooltip(fromTimeFrame, fromPoint, fromModeLabel), ANCHOR_CENTER
        );
    }

    /**
     * 保存価格に水平線と画面左側の説明を描画する。
     */
    void drawPrice(
        const string fromKey,
        const double fromPrice,
        const string fromLabel,
        const color fromColor,
        const int fromStyle,
        const int fromWidth,
        const datetime fromEventTime,
        const int fromLabelLane = 0
    ) {
        if (!this.isPriceValid(fromPrice)) {
            return;
        }
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_HLINE, 0, fromPrice)) {
            return;
        }
        string text = fromLabel + " " + this.priceText(fromPrice);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, name, OBJPROP_STYLE, fromStyle);
        ObjectSetInteger(this.chartId, name, OBJPROP_WIDTH, fromWidth);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, text + "\nAlert DBの保存値");
        int pointX = 0;
        int pointY = 0;
        if (ChartTimePriceToXY(this.chartId, 0, fromEventTime, fromPrice, pointX, pointY)) {
            int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
            pointY += fromLabelLane * 14;
            if (pointY >= 112 && pointY < chartHeight - 18) {
                this.drawLabel(fromKey + "Text", text, 10, pointY, 9, fromColor, text);
            }
        }
    }

    /**
     * モード切替で変わらない判定時価格と採用SL候補を描画する。
     */
    void drawFixedPrices(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        this.drawPrice("Reference", fromSnapshot.alert.referencePrice, "判定時価格", clrSilver,
            STYLE_DOT, 1, fromSnapshot.alert.currentBarTime);
        bool selectedAvailable = fromSnapshot.originalAvailable
            && (fromSnapshot.correctionStatus == "APPLIED" || fromSnapshot.correctionStatus == "NONE")
            && fromSnapshot.correction.isSelectedStopLossAvailable == 1;
        if (selectedAvailable) {
            this.drawPrice("SelectedSL", fromSnapshot.correction.selectedStopLoss,
                "採用SL候補（実SLではありません）", clrGold, STYLE_SOLID, 2,
                fromSnapshot.alert.currentBarTime);
        }
        if (fromSnapshot.alert.isStopLossAvailable == 1
                && (!selectedAvailable || fromSnapshot.alert.stopLoss != fromSnapshot.correction.selectedStopLoss)) {
            this.drawPrice("OriginalSL", fromSnapshot.alert.stopLoss, "元SL候補（比較用）",
                clrDarkGray, STYLE_DASH, 1, fromSnapshot.alert.currentBarTime, 1);
        }
    }

    /**
     * 表示中のM5分析に保存されたFE価格だけを描画する。
     */
    void drawFiboPrices(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        const bool fromCorrected,
        const bool fromComparison,
        const string fromModeLabel,
        const datetime fromEventTime
    ) {
        if (fromTimeFrame.isFiboExpansionAvailable != 1) {
            return;
        }
        double prices[] = {
            fromTimeFrame.fe618Price, fromTimeFrame.fe1000Price, fromTimeFrame.fe1272Price,
            fromTimeFrame.fe1618Price, fromTimeFrame.fe2000Price
        };
        string levels[] = { "61.8", "100.0", "127.2", "161.8", "200.0" };
        string mode = "O";
        int lineStyle = STYLE_SOLID;
        int lineWidth = 1;
        int labelLane = 0;
        if (fromCorrected) {
            mode = "C";
        } else if (fromComparison) {
            lineStyle = STYLE_DASH;
            labelLane = 1;
        }
        for (int i = 0; i < ArraySize(prices); i++) {
            this.drawPrice("FE" + mode + IntegerToString(i), prices[i],
                "M5 " + fromModeLabel + " FE" + levels[i] + "%",
                this.directionColor(fromTimeFrame.isBuy), lineStyle, lineWidth, fromEventTime, labelLane);
        }
    }

    /**
     * 保存EMA200の方向を返す。MN1は対象外として表示する。
     */
    string emaDirection(ZigZagElliotAlertTimeFrameEntity &fromTimeFrame) {
        if (fromTimeFrame.timeFrame == PERIOD_MN1) {
            return "対象外";
        }
        if (fromTimeFrame.isEma200Buy == 1 && fromTimeFrame.isEma200Sell == 0) {
            return "BUY";
        }
        if (fromTimeFrame.isEma200Buy == 0 && fromTimeFrame.isEma200Sell == 1) {
            return "SELL";
        }
        if (fromTimeFrame.isEma200Buy == 0 && fromTimeFrame.isEma200Sell == 0) {
            return "—";
        }
        return "—";
    }

    /**
     * 情報表用に最新波動ラベルを整形する。
     */
    string timeFrameWave(ZigZagElliotAlertTimeFrameEntity &fromTimeFrame) {
        string wave = fromTimeFrame.latestElliotLabel;
        if (fromTimeFrame.latestSubElliotIndex > 0 && fromTimeFrame.latestSubElliotLabel != "") {
            wave += "." + fromTimeFrame.latestSubElliotLabel;
        }
        if (fromTimeFrame.isWaveUptrend == 1) {
            wave = "▲" + wave;
        } else {
            wave = "▼" + wave;
        }
        return wave;
    }

    /**
     * 情報表と保存判定を左側に配置する。狭いチャートでは1足を2段表示する。
     */
    void drawPanel(
        ZigZagElliotAlertHistorySnapshot &fromSnapshot,
        const bool fromShowOriginal,
        const bool fromShowCorrected,
        const bool fromShowTable,
        const int fromPanelTop
    ) {
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        bool compact = chartWidth < 720;
        int panelWidth = 680;
        if (compact) {
            panelWidth = (int)MathMax(280, chartWidth - 20);
        }
        int panelX = 10;
        int rowCount = 7;
        if (fromShowCorrected && fromShowOriginal) {
            rowCount = 14;
        }
        int rowHeight = 22;
        if (compact) {
            rowHeight = 34;
        }
        bool shortTable = fromShowTable && fromSnapshot.originalAvailable
            && fromPanelTop + 90 + rowCount * rowHeight > chartHeight - 10;
        bool summaryFits = chartHeight >= fromPanelTop + 69 + 7 * 18 + 10;
        int panelHeight = 68;
        if (fromShowTable && fromSnapshot.originalAvailable) {
            if (shortTable) {
                panelHeight = 90;
                if (summaryFits) {
                    panelHeight = 203;
                }
            } else {
                panelHeight += 25 + rowCount * rowHeight;
            }
        }
        string panelName = this.prefix + "Panel";
        if (this.createObject(panelName, OBJ_RECTANGLE_LABEL)) {
            ObjectSetInteger(this.chartId, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_XDISTANCE, panelX - 5);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_YDISTANCE, fromPanelTop);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_XSIZE, panelWidth + 5);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_YSIZE, (int)MathMax(40, MathMin(panelHeight, chartHeight - fromPanelTop - 10)));
            ObjectSetInteger(this.chartId, panelName, OBJPROP_BGCOLOR, clrBlack);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(this.chartId, panelName, OBJPROP_COLOR, clrDimGray);
        }
        if (shortTable && chartHeight < fromPanelTop + 90) {
            this.drawLabel("ResizeNotice", "チャートを縦に拡大してください", panelX, fromPanelTop + 5, 9, clrOrange,
                "7時間足の表示に必要な高さが不足しています。");
            return;
        }
        string decision = "保存判定 " + fromSnapshot.alert.entryResult + " / " + fromSnapshot.alert.side
            + " / Count " + IntegerToString(fromSnapshot.alert.signalCount);
        this.drawLabel("Decision", decision, panelX, fromPanelTop + 5, 10, clrWhite, decision + "\n表示モードで再判定しません。");
        string selectedSL = "採用SL候補 —";
        if (fromSnapshot.correctionStatus == "INCOMPLETE" || !fromSnapshot.originalAvailable) {
            selectedSL = "採用SL候補 表示不可（保存データ不完全）";
        } else if (fromSnapshot.correctionStatus == "APPLIED" || fromSnapshot.correctionStatus == "NONE") {
            if (fromSnapshot.correction.isSelectedStopLossAvailable == 1) {
                selectedSL = "採用SL候補 " + this.priceText(fromSnapshot.correction.selectedStopLoss)
                    + " / " + this.pipsText(fromSnapshot.correction.selectedRiskPips);
            }
        }
        this.drawLabel("SL", selectedSL, panelX, fromPanelTop + 25, 9, clrGold,
            selectedSL + "\n判定時の分析値です。注文・ポジションの実SLではありません。"
            + "\n元SL候補（参考） " + this.priceText(fromSnapshot.alert.stopLoss)
            + " / " + this.pipsText(fromSnapshot.alert.riskPips));
        string legend = "DB保存時刻・価格 / 最新Waveのみ";
        if (fromShowCorrected && fromShowOriginal) {
            legend += " / 後:実線  前:破線";
        }
        if (!fromSnapshot.originalAvailable) {
            legend = "元分析が不完全なため波動を描画しません。";
        } else if (shortTable && summaryFits) {
            legend = "7足要約 / 指標・確定状態は行ツールチップ";
        }
        this.drawLabel("Legend", legend, panelX, fromPanelTop + 45, 8, clrSilver,
            legend + "\n" + fromSnapshot.originalReason + "\n" + fromSnapshot.correctionReason);
        if (!fromShowTable || !fromSnapshot.originalAvailable) {
            return;
        }
        if (shortTable) {
            if (summaryFits) {
                this.drawSummaryTable(fromSnapshot, fromShowOriginal, fromShowCorrected, panelX, panelWidth, fromPanelTop + 69);
            } else {
                this.drawLabel("ResizeNotice", "チャートを縦に拡大してください", panelX, fromPanelTop + 69, 9, clrOrange,
                    "7時間足の表示に必要な高さが不足しています。");
            }
            return;
        }
        this.drawTableHeader(panelX, fromPanelTop + 69, compact);
        int timeFrames[] = { PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5 };
        int rowY = fromPanelTop + 90;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            if (fromShowCorrected) {
                int rowIndex = this.findTimeFrame(fromSnapshot.correctedTimeFrames, timeFrames[i]);
                if (rowIndex >= 0) {
                    this.drawTableRow(fromSnapshot.correctedTimeFrames[rowIndex], true,
                        panelX, rowY, compact, fromSnapshot.correction.correctionTimeFrame, true);
                }
                rowY += rowHeight;
            }
            if (fromShowOriginal) {
                int rowIndex = this.findTimeFrame(fromSnapshot.originalTimeFrames, timeFrames[i]);
                if (rowIndex >= 0) {
                    this.drawTableRow(fromSnapshot.originalTimeFrames[rowIndex], false,
                        panelX, rowY, compact, 0, fromSnapshot.correctionStatus == "APPLIED");
                }
                rowY += rowHeight;
            }
        }
    }

    /**
     * 高さが不足する場合、各時間足を1行にまとめて全保存値をツールチップに残す。
     */
    void drawSummaryTable(
        ZigZagElliotAlertHistorySnapshot &fromSnapshot,
        const bool fromShowOriginal,
        const bool fromShowCorrected,
        const int fromX,
        const int fromWidth,
        const int fromY
    ) {
        int timeFrames[] = { PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5 };
        string labels[] = { "MN1", "W1", "D1", "H4", "H1", "M15", "M5" };
        string originalMode = "元";
        if (fromSnapshot.correctionStatus == "APPLIED") {
            originalMode = "前";
        }
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            int correctedIndex = this.findTimeFrame(fromSnapshot.correctedTimeFrames, timeFrames[i]);
            int originalIndex = this.findTimeFrame(fromSnapshot.originalTimeFrames, timeFrames[i]);
            string tooltip = "";
            if (fromShowCorrected && correctedIndex >= 0) {
                tooltip = this.timeFrameTooltip(fromSnapshot.correctedTimeFrames[correctedIndex],
                    "後（採用）", fromSnapshot.correction.correctionTimeFrame);
            }
            if (fromShowOriginal && originalIndex >= 0) {
                if (tooltip != "") {
                    tooltip += "\n\n";
                }
                tooltip += this.timeFrameTooltip(fromSnapshot.originalTimeFrames[originalIndex],
                    this.originalModeLabel(fromSnapshot.correctionStatus), 0);
            }
            string key = "Summary" + IntegerToString(timeFrames[i]);
            string frameLabel = labels[i];
            if (fromShowCorrected && timeFrames[i] == fromSnapshot.correction.correctionTimeFrame) {
                frameLabel += "*";
            }
            int rowY = fromY + i * 18;
            this.drawLabel(key, frameLabel, fromX, rowY, 9, clrSilver, tooltip);
            if (fromShowCorrected && correctedIndex >= 0) {
                this.drawLabel(key + "C", "後 " + fromSnapshot.correctedTimeFrames[correctedIndex].buySellLabel
                    + " " + this.timeFrameWave(fromSnapshot.correctedTimeFrames[correctedIndex]),
                    fromX + 45, rowY, 9, this.directionColor(fromSnapshot.correctedTimeFrames[correctedIndex].isBuy), tooltip);
            }
            if (fromShowOriginal && originalIndex >= 0) {
                int originalX = fromX + 45;
                if (fromShowCorrected) {
                    originalX += (fromWidth - 45) / 2;
                }
                this.drawLabel(key + "O", originalMode + " " + fromSnapshot.originalTimeFrames[originalIndex].buySellLabel
                    + " " + this.timeFrameWave(fromSnapshot.originalTimeFrames[originalIndex]),
                    originalX, rowY, 9, this.directionColor(fromSnapshot.originalTimeFrames[originalIndex].isBuy), tooltip);
            }
        }
    }

    /**
     * 通常表と高さを抑えた要約表で共通の保存値ツールチップを作成する。
     */
    string timeFrameTooltip(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        const string fromMode,
        const int fromCorrectionTimeFrame
    ) {
        string state = "未確定";
        if (fromTimeFrame.isWaveConfirmed == 1) {
            state = "確定";
        }
        string ema = this.emaDirection(fromTimeFrame);
        string tooltip = fromTimeFrame.timeFrameText + " / " + fromMode
            + "\n分析方向 " + fromTimeFrame.buySellLabel + "\nEMA200 " + ema
            + "\nElliott " + this.timeFrameWave(fromTimeFrame) + " / " + state
            + "\nOscillator " + this.signedCount(fromTimeFrame.oscillatorCount)
            + "\nStochastic S / M / L " + this.signedCount(fromTimeFrame.stochasticShortCount)
            + " / " + this.signedCount(fromTimeFrame.stochasticMiddleCount)
            + " / " + this.signedCount(fromTimeFrame.stochasticLongCount)
            + "\nGMMA Trend / Cross " + this.signedCount(fromTimeFrame.gmmaTrendCount)
            + " / " + this.signedCount(fromTimeFrame.gmmaCrossCount);
        if (fromTimeFrame.timeFrame == fromCorrectionTimeFrame) {
            tooltip += "\n* 分析方向の補正対象足";
        }
        if (ema == "—") {
            tooltip += "\nEMA200 —: 有効方向なし、または未記録";
        }
        return tooltip;
    }

    /**
     * 7足情報表の列見出しを描画する。
     */
    void drawTableHeader(const int fromX, const int fromY, const bool fromCompact) {
        string labels[] = { "TF", "前後", "方向", "EMA200", "O", "S", "M", "L", "GT", "GC", "Elliott", "状態" };
        int positions[] = { 0, 45, 78, 138, 208, 250, 290, 330, 370, 415, 460, 595 };
        if (fromCompact) {
            this.drawLabel("TH", "TF / 前後 / 方向 / EMA200 / Elliott / 状態", fromX, fromY, 8, clrSilver,
                "2段目: Oscillator / Stochastic短・中・長 / GMMA Trend・Cross");
            return;
        }
        for (int i = 0; i < ArraySize(labels); i++) {
            this.drawLabel("TH" + IntegerToString(i), labels[i], fromX + positions[i], fromY, 9, clrSilver, labels[i]);
        }
    }

    /**
     * 保存された1時間足の指標・方向・波動を情報表へ描画する。
     */
    void drawTableRow(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrame,
        const bool fromCorrected,
        const int fromX,
        const int fromY,
        const bool fromCompact,
        const int fromCorrectionTimeFrame,
        const bool fromApplied
    ) {
        string mode = "前";
        string key = "TO";
        if (!fromApplied) {
            mode = "元";
        }
        if (fromCorrected) {
            mode = "後";
            key = "TC";
        }
        key += IntegerToString(fromTimeFrame.timeFrame);
        string state = "未確定";
        if (fromTimeFrame.isWaveConfirmed == 1) {
            state = "確定";
        }
        string frameLabel = fromTimeFrame.timeFrameText;
        if (fromTimeFrame.timeFrame == fromCorrectionTimeFrame) {
            frameLabel += "*";
        }
        string ema = this.emaDirection(fromTimeFrame);
        string wave = this.timeFrameWave(fromTimeFrame);
        string tooltip = this.timeFrameTooltip(fromTimeFrame, mode, fromCorrectionTimeFrame);
        color rowColor = this.directionColor(fromTimeFrame.isBuy);
        if (fromCompact) {
            string first = frameLabel + " " + mode + " " + fromTimeFrame.buySellLabel + " " + ema + " " + wave + " " + state;
            this.drawLabel(key, first, fromX, fromY, 9, rowColor, tooltip);
            string second = " O:" + this.signedCount(fromTimeFrame.oscillatorCount)
                + " S:" + this.signedCount(fromTimeFrame.stochasticShortCount)
                + " M:" + this.signedCount(fromTimeFrame.stochasticMiddleCount)
                + " L:" + this.signedCount(fromTimeFrame.stochasticLongCount)
                + " GT:" + this.signedCount(fromTimeFrame.gmmaTrendCount)
                + " GC:" + this.signedCount(fromTimeFrame.gmmaCrossCount);
            this.drawLabel(key + "Counts", second, fromX, fromY + 16, 8, clrSilver, tooltip);
            return;
        }
        string values[] = {
            frameLabel, mode, fromTimeFrame.buySellLabel, ema,
            this.signedCount(fromTimeFrame.oscillatorCount),
            this.signedCount(fromTimeFrame.stochasticShortCount),
            this.signedCount(fromTimeFrame.stochasticMiddleCount),
            this.signedCount(fromTimeFrame.stochasticLongCount),
            this.signedCount(fromTimeFrame.gmmaTrendCount),
            this.signedCount(fromTimeFrame.gmmaCrossCount), wave, state
        };
        int positions[] = { 0, 45, 78, 138, 208, 250, 290, 330, 370, 415, 460, 595 };
        int counts[] = {
            fromTimeFrame.oscillatorCount, fromTimeFrame.stochasticShortCount,
            fromTimeFrame.stochasticMiddleCount, fromTimeFrame.stochasticLongCount,
            fromTimeFrame.gmmaTrendCount, fromTimeFrame.gmmaCrossCount
        };
        for (int i = 0; i < ArraySize(values); i++) {
            color textColor = rowColor;
            if (i >= 4 && i <= 9) {
                textColor = this.countColor(counts[i - 4]);
            } else if (i == 3) {
                textColor = clrSilver;
                if (ema == "BUY") {
                    textColor = clrAqua;
                } else if (ema == "SELL") {
                    textColor = clrHotPink;
                }
            } else if (i == 11) {
                textColor = clrSilver;
                if (fromTimeFrame.isWaveConfirmed != 1) {
                    textColor = clrOrange;
                }
            }
            this.drawLabel(key + IntegerToString(i), values[i], fromX + positions[i], fromY, 10, textColor, tooltip);
        }
    }
};

#endif
