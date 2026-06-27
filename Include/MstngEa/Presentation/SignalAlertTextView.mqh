/**
 * Package: MstngEa.Presentation
 * File: SignalAlertTextView.mqh
 */

#ifndef MSTNGEA_PRESENTATION_SIGNALALERTTEXTVIEW_MQH
#define MSTNGEA_PRESENTATION_SIGNALALERTTEXTVIEW_MQH

/**
 * シグナル表示
 */
class SignalAlertTextView {
public:
    /** チャートID */
    long chartId;

    /** オブジェクト名接頭辞 */
    string objectPrefix;

    /** 買い色 */
    color buyColor;

    /** 売り色 */
    color sellColor;

    /** フォントサイズ */
    int fontSize;

    /** フォント名 */
    string fontName;

    /** コンストラクタ */
    SignalAlertTextView(long chartIdValue, string objectPrefixValue) {
        this.chartId = chartIdValue;
        this.objectPrefix = objectPrefixValue;
        this.buyColor = clrDodgerBlue;
        this.sellColor = clrMagenta;
        this.fontSize = 20;
        this.fontName = "Consolas";
    }

    /**
     * アラート描画
     *
     * @param signalTimeValue シグナル時刻
     * @param openPriceValue 始値
     * @param alertTextValue 表示文字列
     * @param isBuyValue true: 買い
     */
    void draw(
        datetime signalTimeValue,
        double openPriceValue,
        string alertTextValue,
        bool isBuyValue
    ) {
        string objectName = this.buildObjectName(signalTimeValue, isBuyValue);
        color textColor = this.sellColor;
        ENUM_ANCHOR_POINT anchorPoint = ANCHOR_LEFT_UPPER;

        if (alertTextValue == "") {
            return;
        }

        if (isBuyValue) {
            textColor = this.buyColor;
            anchorPoint = ANCHOR_LEFT_LOWER;
        }

        if (ObjectFind(this.chartId, objectName) >= 0) {
            ObjectDelete(this.chartId, objectName);
        }

        ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, signalTimeValue, openPriceValue);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, alertTextValue);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.fontSize);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, anchorPoint);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ChartRedraw(this.chartId);
    }

private:
    /**
     * オブジェクト名生成
     *
     * @param signalTimeValue シグナル時刻
     * @param isBuyValue true: 買い
     * @return オブジェクト名
     */
    string buildObjectName(datetime signalTimeValue, bool isBuyValue) {
        string sideText = "SELL";

        if (isBuyValue) {
            sideText = "BUY";
        }

        return this.objectPrefix + "_" + sideText + "_" + IntegerToString((int)signalTimeValue);
    }
};

#endif
