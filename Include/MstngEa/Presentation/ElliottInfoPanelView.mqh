/**
 * Package: MstngEa.Presentation
 * File: ElliottInfoPanelView.mqh
 */

#ifndef MSTNGEA_PRESENTATION_ELLIOTTINFOPANELVIEW_MQH
#define MSTNGEA_PRESENTATION_ELLIOTTINFOPANELVIEW_MQH

/**
 * エリオット情報パネル表示
 */
class ElliottInfoPanelView {
public:
    /** チャートID */
    long chartId;
    /** ベース名 */
    string labelName;
    /** パネル名 */
    string panelName;
    /** ヘッダー名 */
    string headerName;
    /** タイトル名 */
    string titleName;
    /** 列ヘッダー名 */
    string columnHeaderName;
    /** TF列ヘッダー名 */
    string tfHeaderName;
    /** 売買列ヘッダー名 */
    string buySellHeaderName;
    /** オシレータ短期列ヘッダー名 */
    string oscillatorSHeaderName;
    /** オシレータ中期列ヘッダー名 */
    string oscillatorMHeaderName;
    /** オシレータ長期列ヘッダー名 */
    string oscillatorLHeaderName;
    /** GMMA列ヘッダー名 */
    string gmmaHeaderName;
    /** エリオット列ヘッダー名 */
    string elliottHeaderName;
    /** 区切り線名 */
    string separatorName;
    /** 作成済み */
    bool created;
    /** 左位置 */
    int xDistance;
    /** 上位置 */
    int yDistance;
    /** 横幅 */
    int panelWidth;
    /** 最小高さ */
    int minimumPanelHeight;
    /** 1行高さ */
    int rowHeight;
    /** 本文開始位置 */
    int firstRowYDistance;
    /** 生成済み行数 */
    int createdRowCount;
    /** 行名一覧 */
    string rowNames[];
    /** タイトル */
    string titleText;
    /** 列ヘッダー */
    string columnHeaderText;
    /** 背景色 */
    color panelBackgroundColor;
    /** ヘッダー色 */
    color headerBackgroundColor;
    /** 枠線色 */
    color borderColor;
    /** タイトル色 */
    color titleColor;
    /** 本文色 */
    color rowColor;
    /** BUY色 */
    color buyColor;
    /** SELL色 */
    color sellColor;
    /** 列ヘッダー色 */
    color columnHeaderColor;
    /** 区切り線色 */
    color separatorColor;
    /** フォント名 */
    string fontName;
    /** タイトルフォントサイズ */
    int titleFontSize;
    /** 本文フォントサイズ */
    int bodyFontSize;
    /** 角位置 */
    ENUM_BASE_CORNER corner;
    /** 初期化文言 */
    string initializingText;
    /** 最大想定行数 */
    int maximumRowCount;
    /** 下余白 */
    int bottomPadding;
    /** 列見出しY位置 */
    int columnHeaderYDistance;
    /** 区切り線Y位置 */
    int separatorYDistance;
    /** タイトルX位置 */
    int titleXDistance;
    /** 本文X位置 */
    int rowXDistance;
    /** 列見出しX位置 */
    int columnHeaderXDistance;
    /** TF列見出しX位置 */
    int tfHeaderXDistance;
    /** 売買列見出しX位置 */
    int buySellHeaderXDistance;
    /** オシレータ短期列見出しX位置 */
    int oscillatorSHeaderXDistance;
    /** オシレータ中期列見出しX位置 */
    int oscillatorMHeaderXDistance;
    /** オシレータ長期列見出しX位置 */
    int oscillatorLHeaderXDistance;
    /** GMMA列見出しX位置 */
    int gmmaHeaderXDistance;
    /** エリオット列見出しX位置 */
    int elliottHeaderXDistance;
    /** ヘッダー高さ */
    int headerHeight;
    /** 区切り線太さ */
    int separatorWidth;
    /** 行最大文字数 */
    int maxRowTextLength;

    /**
     * コンストラクタ
     *
     * @param chartIdValue チャートID
     * @param labelNameValue ラベル名
     */
    ElliottInfoPanelView(long chartIdValue, string labelNameValue) {
        this.chartId = chartIdValue;
        this.labelName = labelNameValue;
        this.panelName = labelNameValue + "_Panel";
        this.headerName = labelNameValue + "_Header";
        this.titleName = labelNameValue + "_Title";
        this.columnHeaderName = labelNameValue + "_ColumnHeader";
        this.tfHeaderName = labelNameValue + "_TfHeader";
        this.buySellHeaderName = labelNameValue + "_BuySellHeader";
        this.oscillatorSHeaderName = labelNameValue + "_OscillatorSHeader";
        this.oscillatorMHeaderName = labelNameValue + "_OscillatorMHeader";
        this.oscillatorLHeaderName = labelNameValue + "_OscillatorLHeader";
        this.gmmaHeaderName = labelNameValue + "_GmmaHeader";
        this.elliottHeaderName = labelNameValue + "_ElliottHeader";
        this.separatorName = labelNameValue + "_Separator";
        this.created = false;
        this.xDistance = 12;
        this.yDistance = 384;
        this.panelWidth = 392;
        this.minimumPanelHeight = 96;
        this.rowHeight = 18;
        this.firstRowYDistance = 64;
        this.createdRowCount = 0;
        this.titleText = "エリオット情報";
        this.columnHeaderText = this.buildColumnHeaderText();
        this.panelBackgroundColor = C'18,18,18';
        this.headerBackgroundColor = C'56,74,104';
        this.borderColor = clrDimGray;
        this.titleColor = clrWhite;
        this.rowColor = clrWhiteSmoke;
        this.buyColor = clrAqua;
        this.sellColor = clrHotPink;
        this.columnHeaderColor = C'180,180,180';
        this.separatorColor = clrDimGray;
        this.fontName = "MS Gothic";
        this.titleFontSize = 11;
        this.bodyFontSize = 10;
        this.corner = CORNER_LEFT_UPPER;
        this.initializingText = "-";
        this.maximumRowCount = 0;
        this.bottomPadding = 10;
        this.columnHeaderYDistance = 40;
        this.separatorYDistance = 58;
        this.titleXDistance = 12;
        this.rowXDistance = 16;
        this.columnHeaderXDistance = 16;
        this.tfHeaderXDistance = 16;
        this.buySellHeaderXDistance = 50;
        this.oscillatorSHeaderXDistance = 101;
        this.oscillatorMHeaderXDistance = 128;
        this.oscillatorLHeaderXDistance = 155;
        this.gmmaHeaderXDistance = 182;
        this.elliottHeaderXDistance = 216;
        this.headerHeight = 24;
        this.separatorWidth = 1;
        this.maxRowTextLength = 48;
        ArrayResize(this.rowNames, 0);
    }

    /**
     * パネル生成
     *
     * @return true: 生成成功
     */
    bool create() {

        if (!this.createPanel()) {
            return false;
        }

        if (!this.createHeader()) {
            return false;
        }

        if (!this.createTitleLabel()) {
            return false;
        }

        if (!this.createColumnHeaderLabels()) {
            return false;
        }

        if (!this.createSeparator()) {
            return false;
        }

        this.created = true;
        this.update(this.initializingText);

        return true;
    }

    /**
     * パネル更新
     *
     * @param textValue 表示文字列
     */
    void update(string textValue) {
        string lines[];
        int lineCount;
        int visibleLineCount;
        int panelHeight;
        int i;

        if (!this.created) {
            return;
        }

        lineCount = StringSplit(textValue, StringGetCharacter("\n", 0), lines);

        if (lineCount <= 0) {
            ArrayResize(lines, 1);
            lines[0] = this.initializingText;
            lineCount = 1;
        }

        visibleLineCount = lineCount;

        if (this.maximumRowCount > 0 && visibleLineCount > this.maximumRowCount) {
            visibleLineCount = this.maximumRowCount;
        }

        this.ensureRowLabels(visibleLineCount);

        for (i = 0; i < this.createdRowCount; i++) {
            if (i < visibleLineCount) {
                string rowText = this.trimRowText(lines[i]);
                ObjectSetString(this.chartId, this.rowNames[i], OBJPROP_TEXT, rowText);
                ObjectSetInteger(this.chartId, this.rowNames[i], OBJPROP_COLOR, this.resolveRowColor(rowText));
            } else {
                ObjectSetString(this.chartId, this.rowNames[i], OBJPROP_TEXT, "");
                ObjectSetInteger(this.chartId, this.rowNames[i], OBJPROP_COLOR, this.rowColor);
            }
        }

        panelHeight = this.firstRowYDistance + (visibleLineCount * this.rowHeight) + this.bottomPadding;

        if (panelHeight < this.minimumPanelHeight) {
            panelHeight = this.minimumPanelHeight;
        }

        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_YSIZE, panelHeight);
    }

    /**
     * パネル削除
     */
    void destroy() {
        int i;

        for (i = 0; i < this.createdRowCount; i++) {
            ObjectDelete(this.chartId, this.rowNames[i]);
        }

        ObjectDelete(this.chartId, this.separatorName);
        ObjectDelete(this.chartId, this.tfHeaderName);
        ObjectDelete(this.chartId, this.buySellHeaderName);
        ObjectDelete(this.chartId, this.oscillatorSHeaderName);
        ObjectDelete(this.chartId, this.oscillatorMHeaderName);
        ObjectDelete(this.chartId, this.oscillatorLHeaderName);
        ObjectDelete(this.chartId, this.gmmaHeaderName);
        ObjectDelete(this.chartId, this.elliottHeaderName);
        ObjectDelete(this.chartId, this.titleName);
        ObjectDelete(this.chartId, this.headerName);
        ObjectDelete(this.chartId, this.panelName);
        this.created = false;
    }

private:
    /**
     * 背景パネル生成
     *
     * @return true: 生成成功
     */
    bool createPanel() {

        if (!ObjectCreate(this.chartId, this.panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_XDISTANCE, this.xDistance);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_YDISTANCE, this.yDistance);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_XSIZE, this.panelWidth);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_YSIZE, this.minimumPanelHeight);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BGCOLOR, this.panelBackgroundColor);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_COLOR, this.borderColor);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_ZORDER, 0);

        return true;
    }

    /**
     * ヘッダー生成
     *
     * @return true: 生成成功
     */
    bool createHeader() {

        if (!ObjectCreate(this.chartId, this.headerName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_XDISTANCE, this.xDistance + 1);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_YDISTANCE, this.yDistance + 1);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_XSIZE, this.panelWidth - 2);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_YSIZE, this.headerHeight);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BGCOLOR, this.headerBackgroundColor);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_COLOR, this.headerBackgroundColor);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_ZORDER, 1);

        return true;
    }

    /**
     * タイトル生成
     *
     * @return true: 生成成功
     */
    bool createTitleLabel() {

        if (!ObjectCreate(this.chartId, this.titleName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_XDISTANCE, this.xDistance + this.titleXDistance);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_YDISTANCE, this.yDistance + 4);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_FONTSIZE, this.titleFontSize);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_COLOR, this.titleColor);
        ObjectSetString(this.chartId, this.titleName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, this.titleName, OBJPROP_TEXT, this.titleText);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 列見出し生成
     *
     * @return true: 生成成功
     */
    bool createColumnHeaderLabels() {

        if (!this.createSingleHeaderLabel(this.tfHeaderName, this.tfHeaderXDistance, "TF")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.buySellHeaderName, this.buySellHeaderXDistance, "売買")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.oscillatorSHeaderName, this.oscillatorSHeaderXDistance, "S")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.oscillatorMHeaderName, this.oscillatorMHeaderXDistance, "M")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.oscillatorLHeaderName, this.oscillatorLHeaderXDistance, "L")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.gmmaHeaderName, this.gmmaHeaderXDistance, "GMMA")) {
            return false;
        }

        if (!this.createSingleHeaderLabel(this.elliottHeaderName, this.elliottHeaderXDistance, "エリオット")) {
            return false;
        }

        return true;
    }

    /**
     * 単一列見出し生成
     *
     * @param headerNameValue 見出し名
     * @param headerXDistanceValue X位置
     * @param headerTextValue 表示文字列
     * @return true: 生成成功
     */
    bool createSingleHeaderLabel(string headerNameValue, int headerXDistanceValue, string headerTextValue) {

        if (!ObjectCreate(this.chartId, headerNameValue, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_XDISTANCE, this.xDistance + headerXDistanceValue);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_YDISTANCE, this.yDistance + this.columnHeaderYDistance);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_COLOR, this.columnHeaderColor);
        ObjectSetString(this.chartId, headerNameValue, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, headerNameValue, OBJPROP_TEXT, headerTextValue);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, headerNameValue, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 区切り線生成
     *
     * @return true: 生成成功
     */
    bool createSeparator() {

        if (!ObjectCreate(this.chartId, this.separatorName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_XDISTANCE, this.xDistance + 12);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_YDISTANCE, this.yDistance + this.separatorYDistance);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_XSIZE, this.panelWidth - 24);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_YSIZE, this.separatorWidth);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_BGCOLOR, this.separatorColor);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_COLOR, this.separatorColor);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.separatorName, OBJPROP_ZORDER, 1);

        return true;
    }

    /**
     * 行ラベルを確保
     *
     * @param requiredRowCountValue 必要行数
     */
    void ensureRowLabels(int requiredRowCountValue) {
        int startIndex;
        int i;

        if (requiredRowCountValue <= this.createdRowCount) {
            return;
        }

        startIndex = this.createdRowCount;
        ArrayResize(this.rowNames, requiredRowCountValue);
        this.createdRowCount = requiredRowCountValue;

        for (i = startIndex; i < this.createdRowCount; i++) {
            this.rowNames[i] = this.labelName + "_Row_" + IntegerToString(i);
            this.createRowLabel(i);
        }
    }

    /**
     * 行ラベル生成
     *
     * @param rowIndexValue 行番号
     * @return true: 生成成功
     */
    bool createRowLabel(int rowIndexValue) {
        int rowYDistance = this.yDistance + this.firstRowYDistance + (rowIndexValue * this.rowHeight);

        if (!ObjectCreate(this.chartId, this.rowNames[rowIndexValue], OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_XDISTANCE, this.xDistance + this.rowXDistance);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_YDISTANCE, rowYDistance);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_COLOR, this.rowColor);
        ObjectSetString(this.chartId, this.rowNames[rowIndexValue], OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, this.rowNames[rowIndexValue], OBJPROP_TEXT, this.initializingText);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.rowNames[rowIndexValue], OBJPROP_ZORDER, 2);

        return true;
    }


    /**
     * 列見出し文字列生成
     *
     * @return 列見出し文字列
     */
    string buildColumnHeaderText() {
        string text = "";

        text += this.rightPad("TF", 3);
        text += " ";
        text += this.rightPad("売買", 4);
        text += " ";
        text += this.rightPad("", 2);
        text += " ";
        text += this.rightPad("S", 2);
        text += " ";
        text += this.rightPad("M", 2);
        text += " ";
        text += this.rightPad("L", 2);
        text += " ";
        text += this.rightPad("GMMA", 4);
        text += " ";
        text += "エリオット";

        return text;
    }

    /**
     * 右側空白埋め
     *
     * @param textValue 対象文字列
     * @param lengthValue 桁数
     * @return 整形後文字列
     */
    string rightPad(string textValue, int lengthValue) {
        string textValueWork = textValue;

        while (StringLen(textValueWork) < lengthValue) {
            textValueWork += " ";
        }

        return textValueWork;
    }

    /**
     * 行色取得
     *
     * @param textValue 行文字列
     * @return 行色
     */
    color resolveRowColor(string textValue) {
        string upperText = textValue;
        StringToUpper(upperText);

        if (StringFind(upperText, "BUY") >= 0) {
            return this.buyColor;
        }

        if (StringFind(upperText, "SELL") >= 0) {
            return this.sellColor;
        }

        return this.rowColor;
    }

    /**
     * 行文字列整形
     *
     * @param textValue 行文字列
     * @return 整形後文字列
     */
    string trimRowText(string textValue) {
        string text = textValue;
        StringTrimLeft(text);
        StringTrimRight(text);

        if (StringLen(text) > this.maxRowTextLength) {
            text = StringSubstr(text, 0, this.maxRowTextLength);
        }

        return text;
    }
};

#endif
