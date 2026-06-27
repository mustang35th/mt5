/**
 * Package: MstngEa.Presentation
 * File: StatusLabelView.mqh
 */

#ifndef MSTNGEA_PRESENTATION_STATUSLABELVIEW_MQH
#define MSTNGEA_PRESENTATION_STATUSLABELVIEW_MQH

/**
 * 稼働状況パネル表示
 */
class StatusLabelView {
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

    /** 生成済み */
    bool created;

    /** 左位置 */
    int xDistance;

    /** 上位置 */
    int yDistance;

    /** 横幅 */
    int panelWidth;

    /** 高さ */
    int panelHeight;

    /** 行数 */
    int rowCount;

    /** キャプション名一覧 */
    string captionNames[16];

    /** 値名一覧 */
    string valueNames[16];

    /** 行タイトル一覧 */
    string rowTitles[16];

    /** 値一覧 */
    string rowValues[16];

    /** 1行高さ */
    int rowHeight;

    /** 値列開始位置 */
    int valueXDistance;

    /** 行開始位置 */
    int firstRowYDistance;

    /** タイトル表示 */
    string titleText;

    /** 待機ヘッダー色 */
    color waitHeaderColor;

    /** 買いヘッダー色 */
    color buyHeaderColor;

    /** 売りヘッダー色 */
    color sellHeaderColor;

    /** 通常パネル背景色 */
    color normalPanelBackgroundColor;

    /** 含み益パネル背景色 */
    color profitPanelBackgroundColor;

    /** 含み損パネル背景色 */
    color lossPanelBackgroundColor;

    /** 通常ヘッダー色 */
    color normalHeaderColor;

    /** 含み益ヘッダー色 */
    color profitHeaderColor;

    /** 含み損ヘッダー色 */
    color lossHeaderColor;

    /** 通常枠線色 */
    color normalBorderColor;

    /** 含み益枠線色 */
    color profitBorderColor;

    /** 含み損枠線色 */
    color lossBorderColor;

    /** タイトル色 */
    color titleColor;

    /** キャプション色 */
    color captionColor;

    /** 値色 */
    color valueColor;

    /** エラー値色 */
    color errorColor;

    /** 正常値色 */
    color okColor;

    /** フォント名 */
    string fontName;

    /** タイトルフォントサイズ */
    int titleFontSize;

    /** 本文フォントサイズ */
    int bodyFontSize;

    /** 角位置 */
    ENUM_BASE_CORNER corner;

    /** 初期化中表示 */
    string initializingText;

    /** エラー行番号 */
    int errorRowIndex;

    /** 状態行番号 */
    int stateRowIndex;

    /** ポジション行番号 */
    int positionRowIndex;

    /** ストップロス行番号 */
    int stopLossRowIndex;

    /** 評価損益行番号 */
    int profitRowIndex;

    /** 建値移動行番号 */
    int breakEvenRowIndex;

    /** 利益戻し決済行番号 */
    int trailExitRowIndex;

    /** アクション行番号 */
    int actionRowIndex;

    /** マジック行番号 */
    int magicRowIndex;

    /** ロット行番号 */
    int lotRowIndex;

    /** シンボル行番号 */
    int symbolRowIndex;

    /** 時間足行番号 */
    int timeframeRowIndex;

    /** 戦略行番号 */
    int strategyRowIndex;

    /** スプレッド行番号 */
    int spreadRowIndex;

    /** 日本時刻行番号 */
    int jstTimeRowIndex;

    /** サーバ時刻行番号 */
    int serverTimeRowIndex;

    /**
     * コンストラクタ
     *
     * @param chartIdValue チャートID
     * @param labelNameValue ラベル名
     */
    StatusLabelView(long chartIdValue, string labelNameValue) {
        this.chartId = chartIdValue;
        this.labelName = labelNameValue;
        this.panelName = labelNameValue + "_Panel";
        this.headerName = labelNameValue + "_Header";
        this.titleName = labelNameValue + "_Title";
        this.created = false;
        this.xDistance = 12;
        this.yDistance = 18;
        this.panelWidth = 560;
        this.panelHeight = 354;
        this.rowCount = 16;
        this.rowHeight = 18;
        this.valueXDistance = 124;
        this.firstRowYDistance = 42;
        this.titleText = "MstngEa [■ WAIT]";
        this.waitHeaderColor = C'70,82,94';
        this.buyHeaderColor = C'30,120,78';
        this.sellHeaderColor = C'150,58,58';
        this.normalHeaderColor = clrDarkOrange;
        this.profitHeaderColor = clrLimeGreen;
        this.lossHeaderColor = clrTomato;
        this.normalPanelBackgroundColor = C'18,18,18';
        this.profitPanelBackgroundColor = C'12,30,16';
        this.lossPanelBackgroundColor = C'36,16,16';
        this.normalBorderColor = clrDimGray;
        this.profitBorderColor = clrLimeGreen;
        this.lossBorderColor = clrTomato;
        this.titleColor = clrWhite;
        this.captionColor = C'180,180,180';
        this.valueColor = clrWhiteSmoke;
        this.errorColor = clrTomato;
        this.okColor = clrLimeGreen;
        this.fontName = "Consolas";
        this.titleFontSize = 11;
        this.bodyFontSize = 10;
        this.corner = CORNER_LEFT_UPPER;
        this.initializingText = "Initializing";
        this.errorRowIndex = 13;
        this.stateRowIndex = 0;
        this.symbolRowIndex = 1;
        this.timeframeRowIndex = 2;
        this.strategyRowIndex = 3;
        this.spreadRowIndex = 5;
        this.lotRowIndex = 4;
        this.magicRowIndex = 6;
        this.positionRowIndex = 7;
        this.stopLossRowIndex = 8;
        this.profitRowIndex = 9;
        this.jstTimeRowIndex = 10;
        this.serverTimeRowIndex = 11;
        this.actionRowIndex = 12;

        this.initializeRowDefinitions();
        this.initializeObjectNames();
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

        if (!this.createRowLabels()) {
            return false;
        }

        this.created = true;
        this.update(this.buildInitializingText());

        return true;
    }

    /**
     * パネル更新
     *
     * @param textValue 表示文字列
     */
    void update(string textValue) {

        if (!this.created) {
            return;
        }

        // 表示文字列を行ごとに反映
        this.applyRows(textValue);

        // ヘッダー表示とパネル配色を更新
        this.applyPanelTheme();
    }

    /**
     * パネル削除
     */
    void destroy() {
        int i;

        for (i = 0; i < this.rowCount; i++) {
            ObjectDelete(this.chartId, this.captionNames[i]);
            ObjectDelete(this.chartId, this.valueNames[i]);
        }

        ObjectDelete(this.chartId, this.titleName);
        ObjectDelete(this.chartId, this.headerName);
        ObjectDelete(this.chartId, this.panelName);
        this.created = false;
    }

private:
    /**
     * 行定義初期化
     */
    void initializeRowDefinitions() {
        this.rowTitles[0] = "State";
        this.rowTitles[1] = "Symbol";
        this.rowTitles[2] = "Timeframe";
        this.rowTitles[3] = "Strategy";
        this.rowTitles[4] = "Lot";
        this.rowTitles[5] = "Spread";
        this.rowTitles[6] = "Magic";
        this.rowTitles[7] = "Position";
        this.rowTitles[8] = "StopLoss";
        this.rowTitles[9] = "Profit";
        this.rowTitles[10] = "JstTime";
        this.rowTitles[11] = "ServerTime";
        this.rowTitles[12] = "BreakEven";
        this.rowTitles[13] = "TrailExit";
        this.rowTitles[14] = "Action";
        this.rowTitles[15] = "Error";

        int i;

        for (i = 0; i < this.rowCount; i++) {
            this.rowValues[i] = "-";
        }
    }

    /**
     * オブジェクト名初期化
     */
    void initializeObjectNames() {
        int i;

        for (i = 0; i < this.rowCount; i++) {
            this.captionNames[i] = this.labelName + "_Caption_" + IntegerToString(i);
            this.valueNames[i] = this.labelName + "_Value_" + IntegerToString(i);
        }
    }

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
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_YSIZE, this.panelHeight);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BGCOLOR, this.normalPanelBackgroundColor);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_COLOR, this.normalBorderColor);
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
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_YSIZE, 24);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BGCOLOR, this.normalHeaderColor);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_COLOR, this.normalHeaderColor);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_ZORDER, 1);

        return true;
    }

    /**
     * タイトルラベル生成
     *
     * @return true: 生成成功
     */
    bool createTitleLabel() {

        if (!ObjectCreate(this.chartId, this.titleName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.titleName, OBJPROP_XDISTANCE, this.xDistance + 12);
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
     * 行ラベル生成
     *
     * @return true: 生成成功
     */
    bool createRowLabels() {
        int i;

        for (i = 0; i < this.rowCount; i++) {

            if (!this.createCaptionLabel(i)) {
                return false;
            }

            if (!this.createValueLabel(i)) {
                return false;
            }
        }

        return true;
    }

    /**
     * キャプションラベル生成
     *
     * @param rowIndexValue 行番号
     * @return true: 生成成功
     */
    bool createCaptionLabel(int rowIndexValue) {
        int rowYDistance = this.yDistance + this.firstRowYDistance + (rowIndexValue * this.rowHeight);

        if (!ObjectCreate(this.chartId, this.captionNames[rowIndexValue], OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_XDISTANCE, this.xDistance + 14);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_YDISTANCE, rowYDistance);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_COLOR, this.captionColor);
        ObjectSetString(this.chartId, this.captionNames[rowIndexValue], OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, this.captionNames[rowIndexValue], OBJPROP_TEXT, this.rowTitles[rowIndexValue]);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.captionNames[rowIndexValue], OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 値ラベル生成
     *
     * @param rowIndexValue 行番号
     * @return true: 生成成功
     */
    bool createValueLabel(int rowIndexValue) {
        int rowYDistance = this.yDistance + this.firstRowYDistance + (rowIndexValue * this.rowHeight);

        if (!ObjectCreate(this.chartId, this.valueNames[rowIndexValue], OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_XDISTANCE, this.xDistance + this.valueXDistance);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_YDISTANCE, rowYDistance);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_COLOR, this.valueColor);
        ObjectSetString(this.chartId, this.valueNames[rowIndexValue], OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, this.valueNames[rowIndexValue], OBJPROP_TEXT, this.initializingText);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, this.valueNames[rowIndexValue], OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 初期化中文字列生成
     *
     * @return 初期化中文字列
     */
    string buildInitializingText() {
        string text = "State      : INITIALIZING\n";
        text += "Symbol     : -\n";
        text += "Timeframe  : -\n";
        text += "Strategy   : -\n";
        text += "Lot        : -\n";
        text += "Spread     : -\n";
        text += "Magic      : -\n";
        text += "Position   : -\n";
        text += "StopLoss   : -\n";
        text += "Profit     : -\n";
        text += "JstTime    : -\n";
        text += "ServerTime : -\n";
        text += "Action     : -\n";
        text += "Error      : -";

        return text;
    }

    /**
     * 行反映
     *
     * @param textValue 表示文字列
     */
    void applyRows(string textValue) {
        string lines[];
        int lineCount = StringSplit(textValue, StringGetCharacter("\n", 0), lines);
        int i;

        for (i = 0; i < this.rowCount; i++) {
            this.rowValues[i] = "-";
        }

        if (lineCount > 0) {
            int limit = lineCount;

            if (limit > this.rowCount) {
                limit = this.rowCount;
            }

            for (i = 0; i < limit; i++) {
                this.applyLine(i, lines[i]);
            }
        }

        for (i = 0; i < this.rowCount; i++) {
            ObjectSetString(this.chartId, this.captionNames[i], OBJPROP_TEXT, this.rowTitles[i]);
            ObjectSetString(this.chartId, this.valueNames[i], OBJPROP_TEXT, this.rowValues[i]);
            ObjectSetInteger(this.chartId, this.valueNames[i], OBJPROP_COLOR, this.resolveValueColor(i));
        }
    }

    /**
     * 1行反映
     *
     * @param rowIndexValue 行番号
     * @param lineValue 1行文字列
     */
    void applyLine(int rowIndexValue, string lineValue) {
        string workLine = lineValue;
        int delimiterIndex = StringFind(workLine, ":");

        if (delimiterIndex < 0) {
            this.rowValues[rowIndexValue] = this.trimText(workLine);
            return;
        }

        string captionText = StringSubstr(workLine, 0, delimiterIndex);
        string valueText = StringSubstr(workLine, delimiterIndex + 1);
        captionText = this.trimText(captionText);
        valueText = this.trimText(valueText);

        if (captionText != "") {
            this.rowTitles[rowIndexValue] = captionText;
        }

        if (valueText == "") {
            valueText = "-";
        }

        this.rowValues[rowIndexValue] = valueText;
    }

    /**
     * 前後空白除去
     *
     * @param textValue 対象文字列
     * @return 整形後文字列
     */
    string trimText(string textValue) {
        string text = textValue;
        StringTrimLeft(text);
        StringTrimRight(text);

        return text;
    }


    /**
     * パネル配色反映
     */
    void applyPanelTheme() {
        color resolvedHeaderColor = this.resolveHeaderColor();
        color resolvedPanelColor = this.resolvePanelBackgroundColor();
        color resolvedBorderColor = this.resolveBorderColor();
        string resolvedHeaderText = this.resolveHeaderText();

        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_BGCOLOR, resolvedHeaderColor);
        ObjectSetInteger(this.chartId, this.headerName, OBJPROP_COLOR, resolvedHeaderColor);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_BGCOLOR, resolvedPanelColor);
        ObjectSetInteger(this.chartId, this.panelName, OBJPROP_COLOR, resolvedBorderColor);
        ObjectSetString(this.chartId, this.titleName, OBJPROP_TEXT, resolvedHeaderText);
    }

    /**
     * ヘッダー色取得
     *
     * @return ヘッダー色
     */
    color resolveHeaderColor() {
        string positionMode = this.getPositionMode();

        if (positionMode == "BUY") {
            return this.buyHeaderColor;
        }

        if (positionMode == "SELL") {
            return this.sellHeaderColor;
        }

        return this.waitHeaderColor;
    }

    /**
     * ヘッダー文字列取得
     *
     * @return ヘッダー文字列
     */
    string resolveHeaderText() {
        string positionMode = this.getPositionMode();

        if (positionMode == "BUY") {
            return "MstngEa [▲ BUY]";
        }

        if (positionMode == "SELL") {
            return "MstngEa [▼ SELL]";
        }

        return "MstngEa [■ WAIT]";
    }

    /**
     * ポジションモード取得
     *
     * @return WAIT / BUY / SELL
     */
    string getPositionMode() {
        string positionText = this.rowValues[this.positionRowIndex];

        if (StringFind(positionText, "BUY") == 0) {
            return "BUY";
        }

        if (StringFind(positionText, "SELL") == 0) {
            return "SELL";
        }

        return "WAIT";
    }

    /**
     * パネル背景色取得
     *
     * @return パネル背景色
     */
    color resolvePanelBackgroundColor() {
        double profitValue = this.getFloatingProfitValue();

        if (profitValue > 0.0) {
            return this.profitPanelBackgroundColor;
        }

        if (profitValue < 0.0) {
            return this.lossPanelBackgroundColor;
        }

        return this.normalPanelBackgroundColor;
    }

    /**
     * 枠線色取得
     *
     * @return 枠線色
     */
    color resolveBorderColor() {
        double profitValue = this.getFloatingProfitValue();

        if (profitValue > 0.0) {
            return this.profitBorderColor;
        }

        if (profitValue < 0.0) {
            return this.lossBorderColor;
        }

        return this.normalBorderColor;
    }

    /**
     * 評価損益値取得
     *
     * @return 評価損益値
     */
    double getFloatingProfitValue() {
        string profitText = this.rowValues[this.profitRowIndex];

        if (profitText == "" || profitText == "-" || profitText == "NONE") {
            return 0.0;
        }

        return StringToDouble(profitText);
    }

    /**
     * 値色取得
     *
     * @param rowIndexValue 行番号
     * @return 文字色
     */
    color resolveValueColor(int rowIndexValue) {
        string valueText = this.rowValues[rowIndexValue];

        if (rowIndexValue == this.errorRowIndex) {

            if (valueText == "-" || valueText == "" || valueText == "NONE") {
                return this.okColor;
            }

            return this.errorColor;
        }

        if (rowIndexValue == this.stateRowIndex) {

            if (valueText == "RUNNING") {
                return this.okColor;
            }
        }

        if (rowIndexValue == this.positionRowIndex) {

            if (valueText == "NONE") {
                return this.captionColor;
            }
        }

        if (rowIndexValue == this.actionRowIndex) {

            if (valueText == "ENTRY" || valueText == "EXIT" || valueText == "CLOSE") {
                return this.okColor;
            }
        }

        if (rowIndexValue == this.breakEvenRowIndex) {

            if (StringFind(valueText, "DONE") >= 0) {
                return clrAqua;
            }

            if (StringFind(valueText, "OFF") >= 0) {
                return this.captionColor;
            }
        }

        if (rowIndexValue == this.trailExitRowIndex) {

            if (StringFind(valueText, "ACTIVE") >= 0) {
                return clrGold;
            }

            if (StringFind(valueText, "OFF") >= 0) {
                return this.captionColor;
            }
        }

        if (rowIndexValue == this.profitRowIndex) {
            double profitValue = StringToDouble(valueText);

            if (profitValue > 0.0) {
                return this.okColor;
            }

            if (profitValue < 0.0) {
                return this.errorColor;
            }

            if (valueText == "NONE") {
                return this.captionColor;
            }
        }

        if (rowIndexValue == this.stopLossRowIndex) {

            if (valueText == "NONE") {
                return this.captionColor;
            }
        }

        return this.valueColor;
    }
};

#endif
