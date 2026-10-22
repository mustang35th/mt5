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
 * 通貨強弱スコアパネルの左側へ固定表示する。
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
        this.andOnly = false;
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
            for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
                this.clearRow(i);
            }

            this.updatePairTooltips();
            this.updateSelectionBackground();
            ChartRedraw(this.chartId);

            return false;
        }

        if (!this.created && !this.create()) {
            return false;
        }

        int candidateCount = fromCandidateList.size();
        int andCount = 0;
        int visibleCount = 0;

        if (fromCandidateList.isRankingReady()) {
            for (int i = 0; i < candidateCount; i++) {
                CurrencyStrengthEntryCandidate candidate;
                candidate.reset();
                if (!fromCandidateList.get(i, candidate)) {
                    continue;
                }

                if (candidate.isAndReady()) {
                    andCount++;
                }

                if (this.andOnly && !candidate.isAndReady()) {
                    continue;
                }

                if (visibleCount < this.maximumCount) {
                    this.drawRow(visibleCount, candidate);
                    visibleCount++;
                }
            }
        }

        for (int i = visibleCount; i < this.maximumCount; i++) {
            this.clearRow(i);
        }

        this.updateTitle(fromCandidateList, andCount, visibleCount);
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
     * 自身の絞り込みボタンのクリックで、表示対象を切り替える。
     * 呼び出し元で候補一覧を再描画し、比較パネルの強調対象を更新する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @return 自身の生成済みボタンを操作した場合true。
     */
    bool handleFilterClick(const string fromObjectName) {
        if (!this.created || fromObjectName != this.objectPrefix + "FilterButton") {
            return false;
        }

        this.andOnly = !this.andOnly;
        this.updateFilterButton();
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * AND成立候補だけに絞り込んでいるか取得する。
     *
     * @return AND成立候補だけを表示する場合true。
     */
    bool isAndOnly() const {
        return this.andOnly;
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
     * 自身のREADY＋H1強調ボタンのクリックか確認し、押下状態を解除する。
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
     * 現在表示中の有効なAND成立候補だけを取得する。
     *
     * @param fromSymbols 表示順位順のAND成立通貨ペア名を格納する配列。
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

    /** 表示行ごとのAND成立状態。空行や未成立はfalse。 */
    bool displayedReady[];

    /** 比較パネルから通知されたREADY強調モード。 */
    bool readyHighlightEnabled;

    /** AND成立候補だけを表示する場合true。 */
    bool andOnly;

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
        int panelHeight = footerYDistance + 3 * 19
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

        if (!this.createReadyButton() || !this.createFilterButton()) {
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

            if (i == 3 || i == 4) {
                ObjectSetString(this.chartId, this.getHeaderObjectName(i),
                    OBJPROP_TOOLTIP, "基軸通貨順位/決済通貨順位(符号付き順位差)");
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
            "READY：両期間の順位差の大きさが4以上 ／ WATCH：4未満の期間あり"
        ) || !this.createLabel(
            this.objectPrefix + "ReadyHint",
            14,
            footerYDistance + 19,
            this.bodyFontSize,
            this.mutedColor,
            "AND成立：READY かつ候補方向とH1 EMA200の共通判定が一致"
        ) || !this.createLabel(
            this.objectPrefix + "WatchHint",
            14,
            footerYDistance + 2 * 19,
            this.bodyFontSize,
            this.mutedColor,
            "H1は確定足 ／ NONE：方向なし ／ —：取得待ち ／ B/Q：基軸/決済"
        )) {
            this.destroyObjects();

            return false;
        }

        this.created = true;
        this.updateReadyButton();
        this.updateFilterButton();

        return true;
    }

    /**
     * タイトル右側へREADY＋H1強調モードを切り替えるボタンを生成する。
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
            this.xDistance + this.panelWidth - 204);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 192);
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
     * 全候補とAND成立候補の表示を切り替えるボタンを生成する。
     *
     * @return ボタンを生成できた場合true。
     */
    bool createFilterButton() {
        string objectName = this.objectPrefix + "FilterButton";
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE,
            this.xDistance + this.panelWidth - 352);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 140);
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
     * 絞り込みボタンへ現在の表示対象を反映する。
     */
    void updateFilterButton() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "FilterButton";
        string buttonText = "表示：全候補";
        color textColor = this.normalColor;
        color backgroundColor = C'35,35,35';
        if (this.andOnly) {
            buttonText = "AND成立のみ";
            textColor = this.warningColor;
            backgroundColor = C'58,62,42';
        }

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, buttonText);
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP,
            "全候補／READYかつH1 EMA200が同方向の候補を切り替えます");
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, backgroundColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
    }

    /**
     * READY＋H1強調ボタンの状態表示と操作可否を更新する。
     */
    void updateReadyButton() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "ReadyButton";
        string buttonText = "READY＋H1強調：OFF";
        string tooltip = "\n";
        color textColor = this.mutedColor;
        color backgroundColor = C'35,35,35';
        if (this.pairSelectionEnabled) {
            textColor = this.normalColor;
            tooltip = "表示中のAND成立候補に含まれる通貨を比較パネルで強調します";
            if (this.readyHighlightEnabled) {
                buttonText = "READY＋H1強調：ON";
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
     * @param fromAndCount 全候補中のAND成立件数。
     * @param fromVisibleCount 現在の表示件数。
     */
    void updateTitle(
        CurrencyStrengthEntryCandidateList *fromCandidateList,
        const int fromAndCount,
        const int fromVisibleCount
    ) {
        string summaryText = StringFormat(
            "集計待ち：%d/%dペア",
            fromCandidateList.getValidPairCount(),
            fromCandidateList.getExpectedPairCount()
        );
        color displayColor = this.warningColor;

        if (fromCandidateList.isRankingReady()) {
            summaryText = StringFormat(
                "必要順位差：%d以上 ｜ 候補：%d件 ｜ AND成立：%d件 ｜ 表示：%d件",
                fromCandidateList.getMinimumRankDifference(),
                fromCandidateList.size(),
                fromAndCount,
                fromVisibleCount
            );
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
        this.displayedReady[fromRowIndex] = fromCandidate.isAndReady();
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
                fromCandidate.quoteLongMediumRank,
                fromCandidate.longMediumRankDifference
            ),
            this.normalColor
        );
        this.setCell(
            fromRowIndex,
            4,
            this.formatRanks(
                fromCandidate.baseMediumShortRank,
                fromCandidate.quoteMediumShortRank,
                fromCandidate.mediumShortRankDifference
            ),
            this.normalColor
        );
        this.setCell(
            fromRowIndex,
            5,
            StringFormat("%d / %d", fromCandidate.minimumRankDifference,
                fromCandidate.totalRankDifference),
            this.normalColor
        );
        this.setCell(fromRowIndex, 6, stateText, stateColor);

        color emaColor = this.mutedColor;
        if (fromCandidate.h1EmaAvailable) {
            emaColor = this.warningColor;
            if (fromCandidate.h1EmaIsBuy) {
                emaColor = this.buyColor;
            } else if (fromCandidate.h1EmaIsSell) {
                emaColor = this.sellColor;
            }
        }

        color andColor = this.mutedColor;
        if (fromCandidate.isAndReady()) {
            andColor = directionColor;
        } else if (fromCandidate.isReady()) {
            andColor = this.warningColor;
        }

        this.setCell(fromRowIndex, 7, fromCandidate.getH1EmaLabel(), emaColor);
        this.setCell(fromRowIndex, 8, fromCandidate.getAndStatusLabel(), andColor);
        string emaTooltip = this.getEmaTooltip(fromCandidate);
        ObjectSetString(this.chartId, this.getCellObjectName(fromRowIndex, 7),
            OBJPROP_TOOLTIP, emaTooltip);
        ObjectSetString(this.chartId, this.getCellObjectName(fromRowIndex, 8),
            OBJPROP_TOOLTIP, emaTooltip);
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
            ObjectSetString(this.chartId, this.getCellObjectName(fromRowIndex, i),
                OBJPROP_TOOLTIP, "\n");
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
     * 基軸通貨順位、決済通貨順位と符号付き順位差を1行へまとめる。
     *
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteRank 決済通貨順位。
     * @param fromDifference 順位差。
     * @return 基軸通貨順位/決済通貨順位(符号付き順位差)。
     */
    string formatRanks(
        const int fromBaseRank,
        const int fromQuoteRank,
        const int fromDifference
    ) {
        return StringFormat("%d/%d(%s)", fromBaseRank, fromQuoteRank,
            this.formatDifference(fromDifference));
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
     * H1 EMA200の共通判定に使った確定足と値を操作案内へまとめる。
     *
     * @param fromCandidate 表示対象候補。
     * @return 判定時刻、EMA値、終値との差、傾きを含む操作案内。
     */
    string getEmaTooltip(CurrencyStrengthEntryCandidate &fromCandidate) {
        if (!fromCandidate.h1EmaAvailable) {
            return "H1 EMA200：取得待ち\n確定足の共通判定を取得できていません";
        }

        string tooltip = "H1確定足 SERVER："
            + TimeToString(fromCandidate.h1EmaBarTime, TIME_DATE | TIME_MINUTES)
            + "\nEMA200：" + DoubleToString(fromCandidate.h1EmaValue, fromCandidate.h1EmaDigits)
            + StringFormat("\n終値－EMA200：%+.1f p\nEMA200傾き：%+.1f p",
                fromCandidate.h1EmaCloseDiffPips, fromCandidate.h1EmaSlopePips)
            + "\n共通判定：" + fromCandidate.getH1EmaLabel()
            + " ／ AND：" + fromCandidate.getAndStatusLabel();

        return tooltip;
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
        return 9;
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
                return 164;
            case 4:
                return 260;
            case 5:
                return 356;
            case 6:
                return 452;
            case 7:
                return 538;
            case 8:
                return 610;
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
                return "長中期";
            case 4:
                return "中短期";
            case 5:
                return "MIN/TOTAL";
            case 6:
                return "強弱";
            case 7:
                return "H1 EMA200";
            case 8:
                return "AND判定";
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
