//+------------------------------------------------------------------+
//|                       DrawCurrencyStrengthEntryCandidateList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>

/**
 * 通貨強弱のエントリー候補一覧を
 * ランキングパネルの右側へ固定表示する。
 */
class DrawCurrencyStrengthEntryCandidateList {
public:
    /**
     * 描画対象チャートと表示位置を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート左端からの距離。
     * @param fromYDistance チャート上端からの距離。
     * @param fromMaximumCount 最大表示件数。
     * @param fromInstanceKey 同一チャート内のインスタンス識別子。
     */
    DrawCurrencyStrengthEntryCandidateList(
        const long fromChartId,
        const int fromXDistance,
        const int fromYDistance,
        const int fromMaximumCount,
        const string fromInstanceKey = ""
    ) {
        this.chartId = fromChartId;
        string baseObjectPrefix = Constant::PREFIX_FIXED
            + "CurrencyStrengthEntryCandidateList_";

        if (fromInstanceKey != "") {
            baseObjectPrefix = Constant::PREFIX_FIXED
                + "CurrencyStrengthEntry_"
                + fromInstanceKey
                + "_";
        }

        int instanceIndex = 0;
        this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";

        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0) {
            instanceIndex++;
            this.objectPrefix = baseObjectPrefix
                + IntegerToString(instanceIndex)
                + "_";
        }

        this.created = false;
        this.pairSelectionEnabled = false;
        this.readyHighlightEnabled = false;
        this.selectedSymbol = "";
        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.maximumCount = fromMaximumCount;
        this.panelWidth = 680;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 61;
        this.separatorYDistance = 80;
        this.firstRowYDistance = 87;
        this.rowHeight = 19;
        this.bottomPadding = 10;
        this.fontName = "MS Gothic";
        this.titleFontSize = 11;
        this.bodyFontSize = 10;
        this.panelBackgroundColor = C'18,18,18';
        this.headerBackgroundColor = C'56,74,104';
        this.borderColor = clrDimGray;
        this.titleColor = clrWhite;
        this.headerColor = C'180,180,180';
        this.normalColor = clrWhiteSmoke;
        this.mutedColor = C'130,130,130';
        this.buyColor = clrAqua;
        this.sellColor = clrHotPink;
        this.warningColor = clrGold;
        this.selectionBackgroundColor = C'29,44,58';
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawCurrencyStrengthEntryCandidateList() {
        this.clear();
    }

    /**
     * エントリー候補一覧を描画する。
     *
     * @param fromCandidateList 描画対象の候補一覧。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthEntryCandidateList *fromCandidateList) {
        if (fromCandidateList == NULL) {
            this.clearDisplayedSymbols();
            this.updatePairTooltips();
            this.updateSelectionBackground();
            ChartRedraw(this.chartId);

            return false;
        }

        if (!this.created && !this.create()) {
            return false;
        }

        this.updateTitle(fromCandidateList);

        int candidateCount = fromCandidateList.size();

        for (int i = 0; i < this.maximumCount; i++) {
            CurrencyStrengthEntryCandidate candidate;
            candidate.reset();

            if (fromCandidateList.isRankingReady()
                    && i < candidateCount
                    && fromCandidateList.get(i, candidate)) {
                this.drawRow(i, candidate);
            } else {
                this.clearRow(i);
            }
        }

        this.updatePairTooltips();
        this.updateSelectionBackground();
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 候補一覧のパネル幅を取得する。
     *
     * @return ピクセル単位のパネル幅。
     */
    int getPanelWidth() const {
        return this.panelWidth;
    }

    /**
     * 現在表示しているPAIRセルのクリックから通貨ペア名を取得する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @param fromSymbolName 有効なPAIRセルの場合に返す通貨ペア名。
     * @return ペア選択が有効で、表示中のPAIRセルの場合true。
     */
    bool getClickedSymbol(const string fromObjectName, string &fromSymbolName) const {
        fromSymbolName = "";
        if (!this.pairSelectionEnabled || !this.created) {
            return false;
        }

        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            if (this.displayedSymbols[i] == ""
                    || fromObjectName != this.getCellObjectName(i, 1)) {
                continue;
            }

            if (ObjectFind(this.chartId, fromObjectName) < 0
                    || ObjectGetString(this.chartId, fromObjectName, OBJPROP_TEXT)
                        != this.displayedSymbols[i]) {
                return false;
            }

            fromSymbolName = this.displayedSymbols[i];

            return true;
        }

        return false;
    }

    /**
     * 自身のREADY強調ボタンのクリックか確認し、押下状態を解除する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @return 比較パネルとの連携が有効な自身のボタンの場合true。
     */
    bool isReadyHighlightClick(const string fromObjectName) {
        if (fromObjectName != this.objectPrefix + "ReadyButton") {
            return false;
        }

        if (this.created) {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            ChartRedraw(this.chartId);
        }

        return this.created && this.pairSelectionEnabled;
    }

    /**
     * 現在表示中の有効なREADY候補だけを取得する。
     *
     * @param fromSymbols 表示順位順のREADY通貨ペア名を格納する配列。
     * @return 取得した通貨ペア数。連携無効や未生成の場合は0。
     */
    int getDisplayedReadySymbols(string &fromSymbols[]) const {
        ArrayResize(fromSymbols, 0);
        if (!this.created || !this.pairSelectionEnabled) {
            return 0;
        }

        int count = 0;
        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            string symbolName = "";
            if (!this.displayedReady[i]
                    || !this.getClickedSymbol(this.getCellObjectName(i, 1), symbolName)) {
                continue;
            }

            if (ArrayResize(fromSymbols, count + 1) != count + 1) {
                ArrayResize(fromSymbols, 0);

                return 0;
            }

            fromSymbols[count] = symbolName;
            count++;
        }

        return count;
    }

    /**
     * 比較パネルのREADY強調モードをボタン表示へ反映する。
     * 手動選択している候補行の背景は変更しない。
     *
     * @param fromEnabled READY強調モードが有効な場合true。
     */
    void setReadyHighlightEnabled(const bool fromEnabled) {
        this.readyHighlightEnabled = fromEnabled && this.pairSelectionEnabled;
        if (this.created) {
            this.updateReadyButton();
            ChartRedraw(this.chartId);
        }
    }

    /**
     * 比較パネルで選択中の通貨ペアに対応する行背景を更新する。
     *
     * @param fromSymbolName 選択中の通貨ペア名。空文字列の場合は解除する。
     */
    void setSelectedSymbol(const string fromSymbolName) {
        this.selectedSymbol = fromSymbolName;
        if (this.created) {
            this.updateSelectionBackground();
            ChartRedraw(this.chartId);
        }
    }

    /**
     * 比較パネルの有無に合わせてPAIRクリックと操作案内を切り替える。
     *
     * @param fromEnabled ペア選択を有効にする場合true。
     */
    void setPairSelectionEnabled(const bool fromEnabled) {
        this.pairSelectionEnabled = fromEnabled;
        if (!fromEnabled) {
            this.readyHighlightEnabled = false;
        }

        if (this.created) {
            this.updatePairTooltips();
            this.updateSelectionBackground();
            this.updateReadyButton();
            ChartRedraw(this.chartId);
        }
    }

    /**
     * 候補一覧専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 候補一覧専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** オブジェクト生成済みの場合true。 */
    bool created;

    /** 比較パネルへ通貨ペアの選択を通知できる場合true。 */
    bool pairSelectionEnabled;

    /** 表示行ごとの有効な通貨ペア名。空行は空文字列。 */
    string displayedSymbols[];

    /** 表示行ごとのREADY状態。空行やWATCHはfalse。 */
    bool displayedReady[];

    /** 比較パネルから通知されたREADY強調モード。 */
    bool readyHighlightEnabled;

    /** 選択中の通貨ペア名。表示順位の圏外でも保持する。 */
    string selectedSymbol;

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** チャート左端からの距離。 */
    int xDistance;

    /** チャート上端からの距離。 */
    int yDistance;

    /** 最大表示件数。 */
    int maximumCount;

    /** パネル幅。 */
    int panelWidth;

    /** タイトル背景の高さ。 */
    int headerHeight;

    /** 列ヘッダーのY位置。 */
    int columnHeaderYDistance;

    /** ヘッダー区切り線のY位置。 */
    int separatorYDistance;

    /** データ先頭行のY位置。 */
    int firstRowYDistance;

    /** 1行の高さ。 */
    int rowHeight;

    /** パネル下部余白。 */
    int bottomPadding;

    /** 表示フォント名。 */
    string fontName;

    /** タイトル文字サイズ。 */
    int titleFontSize;

    /** 本文文字サイズ。 */
    int bodyFontSize;

    /** パネル背景色。 */
    color panelBackgroundColor;

    /** タイトル背景色。 */
    color headerBackgroundColor;

    /** 枠線色。 */
    color borderColor;

    /** タイトル文字色。 */
    color titleColor;

    /** 列ヘッダー文字色。 */
    color headerColor;

    /** 通常文字色。 */
    color normalColor;

    /** 補助文字色。 */
    color mutedColor;

    /** BUY候補文字色。 */
    color buyColor;

    /** SELL候補文字色。 */
    color sellColor;

    /** 注意表示文字色。 */
    color warningColor;

    /** 選択行の背景色。BUY・SELLの文字色は変更しない。 */
    color selectionBackgroundColor;

    /**
     * 候補一覧パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();
        if (ArrayResize(this.displayedSymbols, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedReady, this.maximumCount) != this.maximumCount) {
            this.destroyObjects();

            return false;
        }

        this.clearDisplayedSymbols();

        int footerSeparatorYDistance = this.firstRowYDistance
            + this.maximumCount * this.rowHeight + 4;
        int footerYDistance = footerSeparatorYDistance + 12;
        int panelHeight = footerYDistance + 3 * this.rowHeight
            + this.bottomPadding;

        if (!this.createRectangle(
            this.objectPrefix + "Panel",
            this.xDistance,
            this.yDistance,
            this.panelWidth,
            panelHeight,
            this.panelBackgroundColor,
            this.borderColor,
            0
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createRectangle(
            this.objectPrefix + "TitleBackground",
            this.xDistance + 1,
            this.yDistance + 1,
            this.panelWidth - 2,
            this.headerHeight,
            this.headerBackgroundColor,
            this.headerBackgroundColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "Title",
            14,
            5,
            this.titleFontSize,
            this.titleColor,
            "売買候補一覧"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createReadyButton()) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "Summary",
            14,
            35,
            this.bodyFontSize,
            this.headerColor,
            "集計待ち"
        )) {
            this.destroyObjects();

            return false;
        }

        for (int i = 0; i < this.getColumnCount(); i++) {
            if (!this.createLabel(
                this.getHeaderObjectName(i),
                this.getColumnLeftOffset(i),
                this.columnHeaderYDistance,
                this.bodyFontSize,
                this.headerColor,
                this.getHeaderText(i)
            )) {
                this.destroyObjects();

                return false;
            }
        }

        if (!this.createRectangle(
            this.objectPrefix + "HeaderSeparator",
            this.xDistance + 12,
            this.yDistance + this.separatorYDistance,
            this.panelWidth - 24,
            1,
            this.borderColor,
            this.borderColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        // 行ラベルより先に生成して、背景で文字やPAIRクリックを覆わない。
        string selectionObjectName = this.objectPrefix + "Selection";
        if (!this.createRectangle(
            selectionObjectName,
            this.xDistance + 10,
            this.yDistance + this.firstRowYDistance - 1,
            this.panelWidth - 20,
            this.rowHeight,
            this.panelBackgroundColor,
            this.panelBackgroundColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        // 表示時間足を切り替えると前面へ移るため、常時表示して未選択時はパネル色にする。
        ObjectSetInteger(this.chartId, selectionObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetString(this.chartId, selectionObjectName, OBJPROP_TOOLTIP, "\n");

        for (int i = 0; i < this.maximumCount; i++) {
            int rowYDistance = this.firstRowYDistance + i * this.rowHeight;

            for (int j = 0; j < this.getColumnCount(); j++) {
                if (!this.createLabel(
                    this.getCellObjectName(i, j),
                    this.getColumnLeftOffset(j),
                    rowYDistance,
                    this.bodyFontSize,
                    this.normalColor,
                    ""
                )) {
                    this.destroyObjects();

                    return false;
                }
            }
        }

        if (!this.createRectangle(
            this.objectPrefix + "FooterSeparator",
            this.xDistance + 12,
            this.yDistance + footerSeparatorYDistance,
            this.panelWidth - 24,
            1,
            this.borderColor,
            this.borderColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "Description",
            14,
            footerYDistance,
            this.bodyFontSize,
            this.mutedColor,
            "長中期・中短期の両方で強弱方向が一致するペア"
        ) || !this.createLabel(
            this.objectPrefix + "ReadyHint",
            14,
            footerYDistance + this.rowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "READY：両期間の順位差の大きさが4以上"
        ) || !this.createLabel(
            this.objectPrefix + "WatchHint",
            14,
            footerYDistance + 2 * this.rowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "WATCH：候補条件を満たすが、どちらかの順位差の大きさが4未満"
        )) {
            this.destroyObjects();

            return false;
        }

        this.created = true;
        this.updateReadyButton();

        return true;
    }

    /**
     * タイトル右側へREADY強調モードを切り替えるボタンを生成する。
     *
     * @return ボタンを生成できた場合true。
     */
    bool createReadyButton() {
        string objectName = this.objectPrefix + "ReadyButton";
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE,
            this.xDistance + this.panelWidth - 162);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 150);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 20);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, this.borderColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);

        return true;
    }

    /**
     * READY強調ボタンの状態表示と操作可否を更新する。
     */
    void updateReadyButton() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "ReadyButton";
        string buttonText = "READY強調：OFF";
        string tooltip = "\n";
        color textColor = this.mutedColor;
        color backgroundColor = C'35,35,35';
        if (this.pairSelectionEnabled) {
            textColor = this.normalColor;
            tooltip = "表示中のREADY候補に含まれる通貨を比較パネルで強調します";
            if (this.readyHighlightEnabled) {
                buttonText = "READY強調：ON";
                textColor = this.warningColor;
                backgroundColor = C'58,62,42';
            }
        }

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, buttonText);
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, tooltip);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, backgroundColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
    }

    /**
     * 日本語タイトルと、候補条件・件数・集計状態を更新する。
     *
     * @param fromCandidateList 候補一覧。
     */
    void updateTitle(CurrencyStrengthEntryCandidateList *fromCandidateList) {
        string summaryText = StringFormat(
            "集計待ち：%d/%dペア",
            fromCandidateList.getValidPairCount(),
            fromCandidateList.getExpectedPairCount()
        );
        color displayColor = this.warningColor;

        if (fromCandidateList.isRankingReady()) {
            int visibleCount = fromCandidateList.size();

            if (visibleCount > this.maximumCount) {
                visibleCount = this.maximumCount;
            }

            if (fromCandidateList.size() <= 0) {
                summaryText = StringFormat(
                    "必要順位差：%d以上 ｜ 候補なし",
                    fromCandidateList.getMinimumRankDifference()
                );
            } else {
                summaryText = StringFormat(
                    "必要順位差：%d以上 ｜ 候補：%d件 ｜ 表示：%d件",
                    fromCandidateList.getMinimumRankDifference(),
                    fromCandidateList.size(),
                    visibleCount
                );
            }

            displayColor = this.headerColor;
        }

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            "売買候補一覧"
        );
        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Summary",
            OBJPROP_TEXT,
            summaryText
        );
        ObjectSetInteger(
            this.chartId,
            this.objectPrefix + "Summary",
            OBJPROP_COLOR,
            displayColor
        );
    }

    /**
     * 候補1件分を表示する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromCandidate 表示対象候補。
     */
    void drawRow(
        const int fromRowIndex,
        CurrencyStrengthEntryCandidate &fromCandidate
    ) {
        this.displayedSymbols[fromRowIndex] = fromCandidate.symbolName;
        this.displayedReady[fromRowIndex] = fromCandidate.isReady();
        color directionColor = this.sellColor;

        if (fromCandidate.isBuy) {
            directionColor = this.buyColor;
        }

        string sideText = "SELL";

        if (fromCandidate.isBuy) {
            sideText = "BUY";
        }

        string stateText = "WATCH";
        color stateColor = this.warningColor;

        if (fromCandidate.isReady()) {
            stateText = "READY";
            stateColor = directionColor;
        }

        this.setCell(
            fromRowIndex,
            0,
            IntegerToString(fromRowIndex + 1),
            this.mutedColor
        );
        this.setCell(
            fromRowIndex,
            1,
            fromCandidate.symbolName,
            directionColor
        );
        this.setCell(fromRowIndex, 2, sideText, directionColor);
        this.setCell(
            fromRowIndex,
            3,
            this.formatRanks(
                fromCandidate.baseLongMediumRank,
                fromCandidate.quoteLongMediumRank
            ),
            this.normalColor
        );
        this.setCell(
            fromRowIndex,
            4,
            this.formatDifference(fromCandidate.longMediumRankDifference),
            directionColor
        );
        this.setCell(
            fromRowIndex,
            5,
            this.formatRanks(
                fromCandidate.baseMediumShortRank,
                fromCandidate.quoteMediumShortRank
            ),
            this.normalColor
        );
        this.setCell(
            fromRowIndex,
            6,
            this.formatDifference(fromCandidate.mediumShortRankDifference),
            directionColor
        );
        this.setCell(
            fromRowIndex,
            7,
            IntegerToString(fromCandidate.minimumRankDifference),
            this.normalColor
        );
        this.setCell(
            fromRowIndex,
            8,
            IntegerToString(fromCandidate.totalRankDifference),
            this.normalColor
        );
        this.setCell(fromRowIndex, 9, stateText, stateColor);
    }

    /**
     * 指定行の表示を消去する。
     *
     * @param fromRowIndex 表示行番号。
     */
    void clearRow(const int fromRowIndex) {
        this.displayedSymbols[fromRowIndex] = "";
        this.displayedReady[fromRowIndex] = false;

        // 空文字はMT5の既定文字Labelになるため、空白1文字で非表示にする。
        for (int i = 0; i < this.getColumnCount(); i++) {
            this.setCell(fromRowIndex, i, " ", this.mutedColor);
        }
    }

    /**
     * 描画失敗や再生成に備えて、クリック可能な表示行の記録を消す。
     */
    void clearDisplayedSymbols() {
        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            this.displayedSymbols[i] = "";
        }

        ArrayInitialize(this.displayedReady, false);
    }

    /**
     * 有効なPAIRセルだけに比較パネルの操作案内を表示する。
     */
    void updatePairTooltips() {
        if (!this.created) {
            return;
        }

        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            string tooltip = "\n";
            if (this.pairSelectionEnabled && this.displayedSymbols[i] != "") {
                tooltip = "クリックで比較パネルの2通貨を強調します";
            }

            ObjectSetString(this.chartId, this.getCellObjectName(i, 1), OBJPROP_TOOLTIP, tooltip);
        }
    }

    /**
     * 選択中ペアの表示位置へ背景を移動し、圏外や解除時にはパネル色に戻す。
     */
    void updateSelectionBackground() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "Selection";
        int selectedRow = -1;
        if (this.pairSelectionEnabled && this.selectedSymbol != "") {
            for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
                if (this.displayedSymbols[i] == this.selectedSymbol) {
                    selectedRow = i;
                    break;
                }
            }
        }

        if (selectedRow < 0) {
            ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, this.panelBackgroundColor);
            ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.panelBackgroundColor);
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE,
            this.yDistance + this.firstRowYDistance + selectedRow * this.rowHeight - 1);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, this.selectionBackgroundColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.selectionBackgroundColor);
    }

    /**
     * 基軸通貨順位と決済通貨順位を表示用文字列へ変換する。
     *
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteRank 決済通貨順位。
     * @return 基軸通貨順位/決済通貨順位。
     */
    string formatRanks(const int fromBaseRank, const int fromQuoteRank) {
        return StringFormat("%d/%d", fromBaseRank, fromQuoteRank);
    }

    /**
     * 順位差を符号付き表示用文字列へ変換する。
     *
     * @param fromDifference 順位差。
     * @return 符号付き順位差。
     */
    string formatDifference(const int fromDifference) {
        if (fromDifference > 0) {
            return "+" + IntegerToString(fromDifference);
        }

        return IntegerToString(fromDifference);
    }

    /**
     * 候補一覧のセル文字列と色を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setCell(
        const int fromRowIndex,
        const int fromColumnIndex,
        const string fromText,
        const color fromColor
    ) {
        string objectName = this.getCellObjectName(
            fromRowIndex,
            fromColumnIndex
        );
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * 矩形ラベルを生成する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromXDistance X位置。
     * @param fromYDistance Y位置。
     * @param fromWidth 横幅。
     * @param fromHeight 高さ。
     * @param fromBackgroundColor 背景色。
     * @param fromBorderColor 枠線色。
     * @param fromZOrder Zオーダー。
     * @return 生成に成功した場合true。
     */
    bool createRectangle(
        const string fromObjectName,
        const int fromXDistance,
        const int fromYDistance,
        const int fromWidth,
        const int fromHeight,
        const color fromBackgroundColor,
        const color fromBorderColor,
        const int fromZOrder
    ) {
        if (!ObjectCreate(
            this.chartId,
            fromObjectName,
            OBJ_RECTANGLE_LABEL,
            0,
            0,
            0
        )) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XDISTANCE, fromXDistance);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YDISTANCE, fromYDistance);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_BGCOLOR,
            fromBackgroundColor
        );
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_COLOR, fromBorderColor);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, fromZOrder);

        return true;
    }

    /**
     * 固定位置ラベルを生成する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromFontSize 文字サイズ。
     * @param fromColor 文字色。
     * @param fromText 表示文字列。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        const string fromObjectName,
        const int fromLeftOffset,
        const int fromTopOffset,
        const int fromFontSize,
        const color fromColor,
        const string fromText
    ) {
        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_ANCHOR,
            ANCHOR_LEFT_UPPER
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_XDISTANCE,
            this.xDistance + fromLeftOffset
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, fromObjectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, fromObjectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 全列数を取得する。
     *
     * @return 全列数。
     */
    int getColumnCount() {
        return 10;
    }

    /**
     * 列の左位置を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return パネル左端からの位置。
     */
    int getColumnLeftOffset(const int fromColumnIndex) {
        switch (fromColumnIndex) {
            case 0:
                return 14;
            case 1:
                return 40;
            case 2:
                return 110;
            case 3:
                return 160;
            case 4:
                return 270;
            case 5:
                return 320;
            case 6:
                return 435;
            case 7:
                return 480;
            case 8:
                return 525;
            case 9:
                return 595;
        }

        return 14;
    }

    /**
     * 列ヘッダー文字列を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return 列ヘッダー文字列。
     */
    string getHeaderText(const int fromColumnIndex) {
        switch (fromColumnIndex) {
            case 0:
                return "#";
            case 1:
                return "PAIR";
            case 2:
                return "SIDE";
            case 3:
                return "LONG-MID B/Q";
            case 4:
                return "DIFF";
            case 5:
                return "MID-SHORT B/Q";
            case 6:
                return "DIFF";
            case 7:
                return "MIN";
            case 8:
                return "TOTAL";
            case 9:
                return "STATE";
        }

        return "";
    }

    /**
     * 列ヘッダーのオブジェクト名を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getHeaderObjectName(const int fromColumnIndex) {
        return this.objectPrefix
            + "Header_"
            + IntegerToString(fromColumnIndex);
    }

    /**
     * セルのオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getCellObjectName(
        const int fromRowIndex,
        const int fromColumnIndex
    ) const {
        return this.objectPrefix
            + "Row_" + IntegerToString(fromRowIndex)
            + "_Column_" + IntegerToString(fromColumnIndex);
    }

    /**
     * 候補一覧専用オブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.readyHighlightEnabled = false;
        ArrayResize(this.displayedSymbols, 0);
        ArrayResize(this.displayedReady, 0);
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
