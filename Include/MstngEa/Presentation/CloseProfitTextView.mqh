/**
 * Package: MstngEa.Presentation
 * File: CloseProfitTextView.mqh
 */

#ifndef MSTNGEA_PRESENTATION_CLOSEPROFITTEXTVIEW_MQH
#define MSTNGEA_PRESENTATION_CLOSEPROFITTEXTVIEW_MQH

/**
 * 決済損益表示
 */
class CloseProfitTextView {
public:
    /** チャートID */
    long chartId;

    /** オブジェクト名接頭辞 */
    string objectPrefix;

    /** 利益色 */
    color profitColor;

    /** 損失色 */
    color lossColor;

    /** 収支なし色 */
    color flatColor;

    /** フォントサイズ */
    int fontSize;

    /** フォント名 */
    string fontName;

    /**
     * コンストラクタ
     *
     * @param chartIdValue チャートID
     * @param objectPrefixValue オブジェクト名接頭辞
     */
    CloseProfitTextView(long chartIdValue, string objectPrefixValue) {
        this.chartId = chartIdValue;
        this.objectPrefix = objectPrefixValue;
        this.profitColor = clrLightSkyBlue;
        this.lossColor = clrLightPink;
        this.flatColor = clrSilver;
        this.fontSize = 20;
        this.fontName = "Consolas";
    }

    /**
     * 損益描画
     *
     * @param closeTimeValue 決済時刻
     * @param closePriceValue 決済価格
     * @param profitValue 損益
     * @param dealTicketValue 約定チケット
     */
    void draw(
        datetime closeTimeValue,
        double closePriceValue,
        double profitValue,
        ulong dealTicketValue
    ) {
        string objectName = this.buildObjectName(dealTicketValue, closeTimeValue);
        string textValue = this.buildProfitText(profitValue);
        color textColor = this.resolveTextColor(profitValue);
        ENUM_ANCHOR_POINT anchorPoint = ANCHOR_LEFT_UPPER;

        if (profitValue > 0.0) {
            anchorPoint = ANCHOR_LEFT_LOWER;
        }

        if (ObjectFind(this.chartId, objectName) >= 0) {
            ObjectDelete(this.chartId, objectName);
        }

        ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, closeTimeValue, closePriceValue);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, textValue);
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
     * @param dealTicketValue 約定チケット
     * @param closeTimeValue 決済時刻
     * @return オブジェクト名
     */
    string buildObjectName(ulong dealTicketValue, datetime closeTimeValue) {
        string objectName = this.objectPrefix + "_" + IntegerToString((int)closeTimeValue);

        if (dealTicketValue > 0) {
            objectName = this.objectPrefix + "_" + (string)dealTicketValue;
        }

        return objectName;
    }

    /**
     * 損益文字列生成
     *
     * @param profitValue 損益
     * @return 損益文字列
     */
    string buildProfitText(double profitValue) {
        string prefix = "";

        if (profitValue > 0.0) {
            prefix = "+";
        }

        return prefix + DoubleToString(profitValue, 2);
    }

    /**
     * 文字色取得
     *
     * @param profitValue 損益
     * @return 文字色
     */
    color resolveTextColor(double profitValue) {

        if (profitValue > 0.0) {
            return this.profitColor;
        }

        if (profitValue < 0.0) {
            return this.lossColor;
        }

        return this.flatColor;
    }
};

#endif
