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
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryAndTracker.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 通貨強弱のエントリー候補一覧を
 * 通貨強弱スコアパネルの左側へ固定表示する。
 */
class DrawCurrencyStrengthEntryCandidateList {
public:
    /**
     * 描画対象チャートと表示位置を指定して初期化する。
     * 初期表示はAND成立候補のみに絞り込む。
     * EMA200初期モードは通常チャートでH1＋M1、テスターではH1を使用する。
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
        this.andOnly = true;
        this.emaMode = currencyStrengthEntryEmaH1AndM1;
        if (Util::isStrategyTester()) {
            this.emaMode = currencyStrengthEntryEmaH1;
        }

        this.selectedSymbol = "";
        this.hasNewMarkers = false;
        this.displayedSelectedRow = -2;
        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.maximumCount = fromMaximumCount;
        this.gmoSymbolNameInfoAll.setGmo();
        this.panelWidth = 630;
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
     * @param fromUpdateTracking 実データ更新としてAND成立の変化を観測する場合true。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthEntryCandidateList *fromCandidateList,
            const bool fromUpdateTracking = true) {
        if (fromCandidateList == NULL) {
            this.andTracker.suspend();
            for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
                this.clearRow(i);
            }

            this.updatePairTooltips();
            this.updateSelectionBackground();
            DrawChartRedrawBatch::request(this.chartId);

            return false;
        }

        datetime serverTime = TimeCurrent();
        ulong nowMs = GetTickCount64();
        if (Util::isStrategyTester()) {
            nowMs = (ulong)serverTime * 1000;
        }

        bool isRankingReady = fromCandidateList.isRankingReady();
        if (!isRankingReady) {
            this.andTracker.suspend();
        } else if (fromUpdateTracking) {
            this.updateAndTracking(fromCandidateList, serverTime, nowMs);
        }

        if (!this.created && !this.create()) {
            return false;
        }

        int candidateCount = fromCandidateList.size();
        int andCount = 0;
        int visibleCount = 0;

        this.hasNewMarkers = false;
        if (isRankingReady) {
            for (int i = 0; i < candidateCount; i++) {
                CurrencyStrengthEntryCandidate candidate;
                candidate.reset();
                if (!fromCandidateList.get(i, candidate)) {
                    continue;
                }

                if (candidate.isAndReady(this.emaMode)) {
                    andCount++;
                }

                if (this.andOnly && !candidate.isAndReady(this.emaMode)) {
                    continue;
                }

                if (visibleCount < this.maximumCount) {
                    this.drawRow(visibleCount, candidate, serverTime, nowMs);
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
        DrawChartRedrawBatch::request(this.chartId);

        return true;
    }

    /**
     * データ取得失敗時にAND成立の比較を止め、残っているNEW表示を解除する。
     * 次の正常な実データ更新を新しい比較基準とする。
     */
    void suspendAndTracking() {
        this.andTracker.suspend();
        this.refreshNewMarkers();
    }

    /**
     * 分析を行わず、表示中のNEW文字の期限と反映失敗だけを再確認する。
     */
    void refreshNewMarkers() {
        if (!this.created || !this.hasNewMarkers) {
            return;
        }

        ulong nowMs = GetTickCount64();
        if (Util::isStrategyTester()) {
            nowMs = (ulong)TimeCurrent() * 1000;
        }

        bool hasPendingMarkers = false;
        bool isChanged = false;
        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            if (!this.displayedNewPending[i]) {
                continue;
            }

            bool isNew = this.displayedReady[i]
                && this.andTracker.isNew(this.displayedSymbols[i], this.displayedBuy[i], nowMs);
            string andText = this.displayedAndTexts[i];
            if (isNew) {
                andText += " NEW";
            }

            int cellIndex = i * this.getColumnCount() + 9;
            string previousText = this.displayedCellTexts[cellIndex];
            color previousColor = this.displayedCellColors[cellIndex];
            this.setCell(i, 9, andText, this.displayedAndColors[i]);
            if (previousText != this.displayedCellTexts[cellIndex]
                    || previousColor != this.displayedCellColors[cellIndex]) {
                isChanged = true;
            }

            this.displayedNewPending[i] = isNew
                || this.displayedCellTexts[cellIndex] != andText
                || this.displayedCellColors[cellIndex] != this.displayedAndColors[i];
            if (this.displayedNewPending[i]) {
                hasPendingMarkers = true;
            }
        }

        this.hasNewMarkers = hasPendingMarkers;
        if (isChanged) {
            DrawChartRedrawBatch::request(this.chartId);
        }
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
        DrawChartRedrawBatch::request(this.chartId);

        return true;
    }

    /**
     * EMA200のAND判定対象をH1、M1、H1＋M1の順に切り替える。
     * 呼び出し元で一覧を再描画し、比較パネルの強調対象を更新する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @return 自身の生成済みボタンを操作した場合true。
     */
    bool handleEmaModeClick(const string fromObjectName) {
        if (!this.created || fromObjectName != this.objectPrefix + "EmaModeButton") {
            return false;
        }

        if (this.emaMode == currencyStrengthEntryEmaH1) {
            this.emaMode = currencyStrengthEntryEmaM1;
        } else if (this.emaMode == currencyStrengthEntryEmaM1) {
            this.emaMode = currencyStrengthEntryEmaH1AndM1;
        } else {
            this.emaMode = currencyStrengthEntryEmaH1;
        }

        this.andTracker.reset();
        this.updateEmaModeButton();
        this.updateFilterButton();
        this.updateReadyButton();
        DrawChartRedrawBatch::request(this.chartId);

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
     * AND判定に使用するEMA200時間足を取得する。
     *
     * @return 現在のEMA200判定モード。
     */
    CurrencyStrengthEntryEmaMode getEmaMode() const {
        return this.emaMode;
    }

    /**
     * 保存済みの表示設定を復元し、モードが変わる場合だけAND追跡を初期化する。
     * 不正なモードの場合は変更せず、未生成時はチャートオブジェクトに触れない。
     *
     * @param fromAndOnly AND成立候補だけを表示する場合true。
     * @param fromEmaMode 保存済みのEMA200判定モード。
     */
    void restoreDisplaySettings(const bool fromAndOnly,
            const CurrencyStrengthEntryEmaMode fromEmaMode) {
        if (fromEmaMode != currencyStrengthEntryEmaH1
                && fromEmaMode != currencyStrengthEntryEmaM1
                && fromEmaMode != currencyStrengthEntryEmaH1AndM1) {
            return;
        }

        this.andOnly = fromAndOnly;
        if (this.emaMode != fromEmaMode) {
            this.emaMode = fromEmaMode;
            this.andTracker.reset();
        }

        if (this.created) {
            this.updateEmaModeButton();
            this.updateFilterButton();
            this.updateReadyButton();
            DrawChartRedrawBatch::request(this.chartId);
        }
    }

    /**
     * 現在表示しているPAIRセルまたはGMO目印のクリックから通貨ペア名を取得する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @param fromSymbolName 有効なPAIRセルまたはGMO目印の場合に返す通貨ペア名。
     * @return ペア選択が有効で、表示中のPAIRセルまたはGMO目印の場合true。
     */
    bool getClickedSymbol(const string fromObjectName, string &fromSymbolName) const {
        fromSymbolName = "";
        if (!this.pairSelectionEnabled || !this.created) {
            return false;
        }

        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            string pairObjectName = this.getCellObjectName(i, 1);
            string gmoObjectName = this.getGmoObjectName(i);
            if (this.displayedSymbols[i] == ""
                    || (fromObjectName != pairObjectName
                        && fromObjectName != gmoObjectName)) {
                continue;
            }

            if (ObjectFind(this.chartId, pairObjectName) < 0
                    || ObjectGetString(this.chartId, pairObjectName, OBJPROP_TEXT)
                        != this.displayedSymbols[i]) {
                return false;
            }

            if (fromObjectName == gmoObjectName
                    && (!this.displayedGmo[i]
                        || ObjectFind(this.chartId, gmoObjectName) < 0
                        || ObjectGetString(this.chartId, gmoObjectName, OBJPROP_TEXT)
                            != "[G]")) {
                return false;
            }

            fromSymbolName = this.displayedSymbols[i];

            return true;
        }

        return false;
    }

    /**
     * 自身のAND強調ボタンのクリックか確認し、押下状態を解除する。
     * 取得待ち中もON/OFF設定を変更できる。比較パネルの有無は呼び出し元で判定する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @return 生成済みの自身のボタンの場合true。
     */
    bool isReadyHighlightClick(const string fromObjectName) {
        if (fromObjectName != this.objectPrefix + "ReadyButton") {
            return false;
        }

        if (this.created) {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            DrawChartRedrawBatch::request(this.chartId);
        }

        return this.created;
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
     * READY強調のON/OFF設定をボタン表示へ反映する。取得待ちでも設定を保持する。
     * 手動選択している候補行の背景は変更しない。
     *
     * @param fromEnabled READY強調モードが有効な場合true。
     */
    void setReadyHighlightEnabled(const bool fromEnabled) {
        if (this.readyHighlightEnabled == fromEnabled) {
            return;
        }

        this.readyHighlightEnabled = fromEnabled;
        if (this.created) {
            this.updateReadyButton();
            DrawChartRedrawBatch::request(this.chartId);
        }
    }

    /**
     * 比較パネルで選択中の通貨ペアに対応する行背景を更新する。
     *
     * @param fromSymbolName 選択中の通貨ペア名。空文字列の場合は解除する。
     */
    void setSelectedSymbol(const string fromSymbolName) {
        if (this.selectedSymbol == fromSymbolName) {
            return;
        }

        this.selectedSymbol = fromSymbolName;
        if (this.created) {
            this.updateSelectionBackground();
            DrawChartRedrawBatch::request(this.chartId);
        }
    }

    /**
     * 比較パネルの有無に合わせてPAIRクリックと操作案内を切り替える。
     *
     * @param fromEnabled ペア選択を有効にする場合true。
     */
    void setPairSelectionEnabled(const bool fromEnabled) {
        if (this.pairSelectionEnabled == fromEnabled) {
            return;
        }

        this.pairSelectionEnabled = fromEnabled;
        if (this.created) {
            this.updatePairTooltips();
            this.updateSelectionBackground();
            this.updateReadyButton();
            DrawChartRedrawBatch::request(this.chartId);
        }
    }

    /**
     * 候補一覧専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        DrawChartRedrawBatch::request(this.chartId);
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

    /** 表示行ごとの候補方向。追跡キーの通貨ペア名と組み合わせて使う。 */
    bool displayedBuy[];

    /** NEW期限の確認、またはNEWセルの再反映が必要な行。 */
    bool displayedNewPending[];

    /** 表示行ごとのNEWを付ける前のAND判定文字列。 */
    string displayedAndTexts[];

    /** 表示行ごとのAND判定文字色。反映失敗時も期待値を保持する。 */
    color displayedAndColors[];

    /** NEW期限の確認または再反映が必要な表示行がある場合true。 */
    bool hasNewMarkers;

    /** 表示件数や絞り込みにかかわらず全候補のAND成立変化を保持する。 */
    CurrencyStrengthEntryAndTracker andTracker;

    /** 表示行ごとのGMO対象状態。空行や対象外はfalse。 */
    bool displayedGmo[];

    /** 消去済み行の表示状態。再生成時と行描画時に無効化する。 */
    bool clearedRows[];

    /** セルへ最後に反映した文字列。行と列を一次元で管理する。 */
    string displayedCellTexts[];

    /** セルへ最後に反映した文字色。 */
    color displayedCellColors[];

    /** セルへ最後に反映した説明文。 */
    string displayedCellTooltips[];

    /** GMO目印へ最後に反映した説明文。 */
    string displayedGmoTooltips[];

    /** 選択背景へ反映済みの行番号。-1は非選択、-2は未反映。 */
    int displayedSelectedRow;

    /** メールと共通のGMO対象判定に使用する通貨ペア定義。 */
    SymbolNameInfoAll gmoSymbolNameInfoAll;

    /** READY強調のON設定。取得待ち中も保持する。 */
    bool readyHighlightEnabled;

    /** AND成立候補だけを表示する場合true。 */
    bool andOnly;

    /** AND判定で要求するEMA200時間足。再生成時も保持する。 */
    CurrencyStrengthEntryEmaMode emaMode;

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
     * 絞り込みや描画成功に依存せず、全候補のAND成立変化を観測する。
     *
     * @param fromCandidateList 最新の候補一覧。
     * @param fromServerTime 今回の観測サーバー時刻。
     * @param fromNowMs NEW表示期限に使用するミリ秒時刻。
     */
    void updateAndTracking(CurrencyStrengthEntryCandidateList *fromCandidateList,
            const datetime fromServerTime, const ulong fromNowMs) {
        this.andTracker.beginUpdate(true);
        for (int i = 0; i < fromCandidateList.size(); i++) {
            CurrencyStrengthEntryCandidate candidate;
            candidate.reset();
            if (!fromCandidateList.get(i, candidate)) {
                this.andTracker.suspend();

                return;
            }

            this.andTracker.observe(candidate, this.emaMode, fromServerTime, fromNowMs);
        }

        this.andTracker.endUpdate();
    }

    /**
     * 候補一覧パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();
        int cellCount = this.maximumCount * this.getColumnCount();
        if (ArrayResize(this.displayedSymbols, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedReady, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedBuy, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedNewPending, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedAndTexts, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedAndColors, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedGmo, this.maximumCount) != this.maximumCount
                || ArrayResize(this.clearedRows, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedGmoTooltips, this.maximumCount) != this.maximumCount
                || ArrayResize(this.displayedCellTexts, cellCount) != cellCount
                || ArrayResize(this.displayedCellColors, cellCount) != cellCount
                || ArrayResize(this.displayedCellTooltips, cellCount) != cellCount) {
            this.destroyObjects();

            return false;
        }

        this.clearDisplayedSymbols();
        ArrayInitialize(this.clearedRows, false);
        ArrayInitialize(this.displayedCellColors, clrNONE);
        for (int i = 0; i < cellCount; i++) {
            this.displayedCellTexts[i] = "";
            this.displayedCellTooltips[i] = "";
        }

        for (int i = 0; i < this.maximumCount; i++) {
            this.displayedGmoTooltips[i] = "";
        }

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

        if (!this.createReadyButton() || !this.createFilterButton()
                || !this.createEmaModeButton()) {
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
            } else if (i == 5) {
                ObjectSetString(this.chartId, this.getHeaderObjectName(i),
                    OBJPROP_TOOLTIP, "長中期と中短期の小さい絶対順位差／絶対順位差合計");
            } else if (i == 7 || i == 8) {
                ObjectSetString(this.chartId, this.getHeaderObjectName(i),
                    OBJPROP_TOOLTIP, this.getHeaderText(i) + " EMA200の確定足判定");
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

            if (!this.createLabel(
                this.getGmoObjectName(i),
                this.getColumnLeftOffset(1) + 60,
                rowYDistance,
                this.bodyFontSize,
                this.headerColor,
                " "
            )) {
                this.destroyObjects();

                return false;
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
            "READY：方向一致＋長中期(差4以上or端)＋中短期差4以上 ／ WATCH：未達"
        ) || !this.createLabel(
            this.objectPrefix + "ReadyHint",
            14,
            footerYDistance + 19,
            this.bodyFontSize,
            this.mutedColor,
            " "
        ) || !this.createLabel(
            this.objectPrefix + "WatchHint",
            14,
            footerYDistance + 2 * 19,
            this.bodyFontSize,
            this.mutedColor,
            "EMA200は確定足 ／ NONE：方向なし ／ —：取得待ち ／ [G]：GMO対象"
        )) {
            this.destroyObjects();

            return false;
        }

        this.created = true;
        this.updateEmaModeButton();
        this.updateReadyButton();
        this.updateFilterButton();

        return true;
    }

    /**
     * タイトル右側へAND強調モードを切り替えるボタンを生成する。
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
     * AND判定に使用するEMA200時間足の切り替えボタンを生成する。
     *
     * @return ボタンを生成できた場合true。
     */
    bool createEmaModeButton() {
        string objectName = this.objectPrefix + "EmaModeButton";
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + 132);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 136);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 20);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.bodyFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, this.borderColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.normalColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'35,35,35');
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);

        return true;
    }

    /**
     * 選択中のEMA200時間足を短い表示名へ変換する。
     *
     * @return H1、M1、H1＋M1のいずれか。
     */
    string getEmaModeLabel() const {
        if (this.emaMode == currencyStrengthEntryEmaM1) {
            return "M1";
        }

        if (this.emaMode == currencyStrengthEntryEmaH1AndM1) {
            return "H1＋M1";
        }

        return "H1";
    }

    /**
     * EMA200モードボタンとAND成立条件の説明を更新する。
     */
    void updateEmaModeButton() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "EmaModeButton";
        string modeLabel = this.getEmaModeLabel();
        string tooltip = "クリックで H1 → M1 → H1＋M1 の順に切り替えます"
            + "\nAND成立：READY＋選択した時間足のEMA200が候補方向と一致"
            + "\nH1＋M1は両方の一致が必要です"
            + "\nH1は通貨強弱の集計時点、M1は最新確定足で判定します"
            + "\nNEW：未成立から成立への変化を検出してから60秒間"
            + "\n初回観測・取得復旧・モード切替後の基準状態にはNEWを付けません";
        if (Util::isStrategyTester()) {
            tooltip += "\nテスターでは下位足参照制限への対応のためM1は取得対象外です";
        }

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, "EMA200：" + modeLabel);
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, tooltip);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
        ObjectSetString(this.chartId, this.objectPrefix + "ReadyHint", OBJPROP_TEXT,
            "AND成立：READY＋" + modeLabel + " EMA200が候補方向と一致 ／ NEW：60秒");
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
            "全候補／READYかつ" + this.getEmaModeLabel()
                + " EMA200が候補方向と一致する候補を切り替えます");
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, backgroundColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
    }

    /**
     * AND強調ボタンの状態表示と操作可否を更新する。
     */
    void updateReadyButton() {
        if (!this.created) {
            return;
        }

        string objectName = this.objectPrefix + "ReadyButton";
        string buttonText = "AND強調：OFF";
        string tooltip = "\n";
        color textColor = this.mutedColor;
        color backgroundColor = C'35,35,35';
        if (this.pairSelectionEnabled) {
            textColor = this.normalColor;
            tooltip = "表示中のAND成立候補に含まれる通貨を比較パネルで強調します"
                + "\nEMA200判定：" + this.getEmaModeLabel();
        }

        if (this.readyHighlightEnabled) {
            buttonText = "AND強調：ON";
            textColor = this.warningColor;
            backgroundColor = C'58,62,42';
            if (!this.pairSelectionEnabled) {
                buttonText = "AND強調：ON(待機)";
                tooltip = "ON設定を保持しています。データ復旧後に強調を再開します。クリックでOFF。";
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
                "候補差：%d以上（長中期は端も可）｜ 候補%d・AND%d・表示%d",
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
     * @param fromServerTime 今回の表示サーバー時刻。
     * @param fromNowMs NEW表示期限に使用するミリ秒時刻。
     */
    void drawRow(
        const int fromRowIndex,
        CurrencyStrengthEntryCandidate &fromCandidate,
        const datetime fromServerTime,
        const ulong fromNowMs
    ) {
        this.clearedRows[fromRowIndex] = false;
        this.displayedSymbols[fromRowIndex] = fromCandidate.symbolName;
        this.displayedReady[fromRowIndex] = fromCandidate.isAndReady(this.emaMode);
        this.displayedBuy[fromRowIndex] = fromCandidate.isBuy;
        this.displayedGmo[fromRowIndex] =
            this.gmoSymbolNameInfoAll.isTarget(fromCandidate.symbolName);

        string gmoText = " ";
        if (this.displayedGmo[fromRowIndex]) {
            gmoText = "[G]";
        }

        ObjectSetString(this.chartId, this.getGmoObjectName(fromRowIndex),
            OBJPROP_TEXT, gmoText);

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

        string longMediumText = this.formatRanks(
            fromCandidate.baseLongMediumRank,
            fromCandidate.quoteLongMediumRank,
            fromCandidate.longMediumRankDifference
        );
        if (MathAbs(fromCandidate.longMediumRankDifference) < 4
                && fromCandidate.isLongMediumExtremeRankMatched()) {
            longMediumText += "端";
        }

        this.setCell(fromRowIndex, 3, longMediumText, this.normalColor);
        this.setCellTooltip(fromRowIndex, 3, this.getLongMediumTooltip(fromCandidate));
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

        color m1EmaColor = this.mutedColor;
        if (fromCandidate.m1EmaAvailable) {
            m1EmaColor = this.warningColor;
            if (fromCandidate.m1EmaIsBuy) {
                m1EmaColor = this.buyColor;
            } else if (fromCandidate.m1EmaIsSell) {
                m1EmaColor = this.sellColor;
            }
        }

        color andColor = this.mutedColor;
        if (fromCandidate.isAndReady(this.emaMode)) {
            andColor = directionColor;
        } else if (fromCandidate.isReady()) {
            andColor = this.warningColor;
        }

        this.setCell(fromRowIndex, 7, fromCandidate.getH1EmaLabel(), emaColor);
        this.setCell(fromRowIndex, 8, fromCandidate.getM1EmaLabel(), m1EmaColor);
        string andText = fromCandidate.getAndStatusLabel(this.emaMode);
        this.displayedAndTexts[fromRowIndex] = andText;
        this.displayedAndColors[fromRowIndex] = andColor;
        bool isNew = this.displayedReady[fromRowIndex]
            && this.andTracker.isNew(fromCandidate.symbolName, fromCandidate.isBuy, fromNowMs);
        if (isNew) {
            andText += " NEW";
        }

        int andCellIndex = fromRowIndex * this.getColumnCount() + 9;
        bool hadNewMarker = this.displayedNewPending[fromRowIndex];
        this.setCell(fromRowIndex, 9, andText, andColor);
        this.displayedNewPending[fromRowIndex] = isNew
            || (hadNewMarker && (this.displayedCellTexts[andCellIndex] != andText
                || this.displayedCellColors[andCellIndex] != andColor));
        if (this.displayedNewPending[fromRowIndex]) {
            this.hasNewMarkers = true;
        }

        string h1EmaTooltip = this.getEmaTooltip(fromCandidate);
        string m1EmaTooltip = this.getM1EmaTooltip(fromCandidate);
        this.setCellTooltip(fromRowIndex, 7, h1EmaTooltip);
        this.setCellTooltip(fromRowIndex, 8, m1EmaTooltip);
        string andTooltip = "EMA200判定：" + this.getEmaModeLabel()
            + " ／ AND：" + fromCandidate.getAndStatusLabel(this.emaMode);
        if (this.displayedReady[fromRowIndex]) {
            datetime detectedAt = this.andTracker.getDetectedAt(
                fromCandidate.symbolName, fromCandidate.isBuy);
            if (detectedAt > 0) {
                andTooltip += "\n新規成立検出 SERVER："
                    + TimeToString(detectedAt, TIME_DATE | TIME_SECONDS);
                if (fromServerTime >= detectedAt) {
                    long elapsedSeconds = fromServerTime - detectedAt;
                    andTooltip += StringFormat("\n表示更新時の検出経過：%I64d分%I64d秒",
                        elapsedSeconds / 60, elapsedSeconds % 60);
                }
            } else {
                andTooltip += "\n成立開始：未検出（初回観測・復旧・モード切替後の基準状態）";
            }
        }

        this.setCellTooltip(fromRowIndex, 9,
            andTooltip + "\n" + h1EmaTooltip + "\n\n" + m1EmaTooltip);
    }

    /**
     * 指定行の表示を消去する。
     *
     * @param fromRowIndex 表示行番号。
     */
    void clearRow(const int fromRowIndex) {
        if (this.clearedRows[fromRowIndex]) {
            return;
        }

        bool hadNewMarker = this.displayedNewPending[fromRowIndex];
        this.displayedSymbols[fromRowIndex] = "";
        this.displayedReady[fromRowIndex] = false;
        this.displayedBuy[fromRowIndex] = false;
        this.displayedNewPending[fromRowIndex] = false;
        this.displayedAndTexts[fromRowIndex] = " ";
        this.displayedAndColors[fromRowIndex] = this.mutedColor;
        this.displayedGmo[fromRowIndex] = false;

        // 空文字はMT5の既定文字Labelになるため、空白1文字で非表示にする。
        bool isCleared = true;
        for (int i = 0; i < this.getColumnCount(); i++) {
            this.setCell(fromRowIndex, i, " ", this.mutedColor);
            this.setCellTooltip(fromRowIndex, i, "\n");
            int cellIndex = fromRowIndex * this.getColumnCount() + i;
            if (this.displayedCellTexts[cellIndex] != " "
                    || this.displayedCellColors[cellIndex] != this.mutedColor
                    || this.displayedCellTooltips[cellIndex] != "\n") {
                isCleared = false;
            }
        }

        if (!ObjectSetString(this.chartId, this.getGmoObjectName(fromRowIndex),
                OBJPROP_TEXT, " ")) {
            isCleared = false;
        }

        this.setGmoTooltip(fromRowIndex, "\n");
        this.clearedRows[fromRowIndex] = isCleared
            && this.displayedGmoTooltips[fromRowIndex] == "\n";

        int andCellIndex = fromRowIndex * this.getColumnCount() + 9;
        this.displayedNewPending[fromRowIndex] = hadNewMarker
            && (this.displayedCellTexts[andCellIndex] != " "
                || this.displayedCellColors[andCellIndex] != this.mutedColor);
        if (this.displayedNewPending[fromRowIndex]) {
            this.hasNewMarkers = true;
        }
    }

    /**
     * 描画失敗や再生成に備えて、クリック可能な表示行の記録を消す。
     */
    void clearDisplayedSymbols() {
        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            this.displayedSymbols[i] = "";
            this.displayedAndTexts[i] = "";
        }

        ArrayInitialize(this.displayedReady, false);
        ArrayInitialize(this.displayedBuy, false);
        ArrayInitialize(this.displayedNewPending, false);
        ArrayInitialize(this.displayedAndColors, this.mutedColor);
        ArrayInitialize(this.displayedGmo, false);
        this.hasNewMarkers = false;
    }

    /**
     * 有効なPAIRセルとGMO目印に対象説明と比較パネルの操作案内を表示する。
     */
    void updatePairTooltips() {
        if (!this.created) {
            return;
        }

        for (int i = 0; i < ArraySize(this.displayedSymbols); i++) {
            string tooltip = "\n";
            string gmoTooltip = "\n";
            if (this.displayedSymbols[i] != "") {
                if (this.pairSelectionEnabled) {
                    tooltip = "クリックで比較パネルの2通貨を強調します";
                }

                if (this.displayedGmo[i]) {
                    tooltip = "[G]：GMO対象\n" + tooltip;
                    gmoTooltip = tooltip;
                }
            }

            this.setCellTooltip(i, 1, tooltip);
            this.setGmoTooltip(i, gmoTooltip);
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

        if (selectedRow == this.displayedSelectedRow) {
            return;
        }

        color backgroundColor = this.panelBackgroundColor;
        if (selectedRow >= 0) {
            if (!ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE,
                    this.yDistance + this.firstRowYDistance + selectedRow * this.rowHeight - 1)) {
                return;
            }

            backgroundColor = this.selectionBackgroundColor;
        }

        if (ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, backgroundColor)
                && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, backgroundColor)) {
            this.displayedSelectedRow = selectedRow;
        }
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
     * 長中期の順位条件と、候補方向に合う端順位の成立理由をまとめる。
     *
     * @param fromCandidate 表示対象候補。
     * @return 順位差と端順位の判定理由を含む説明。
     */
    string getLongMediumTooltip(CurrencyStrengthEntryCandidate &fromCandidate) {
        string conditionText = "長中期：差4・端順位条件は未達";
        if (fromCandidate.isLongMediumRankConditionMatched(4)) {
            conditionText = "長中期：順位差4以上で成立";
            if (MathAbs(fromCandidate.longMediumRankDifference) < 4) {
                conditionText = "長中期：端順位で成立（差4未満）";
            }
        }

        string sideText = "BUY";
        string baseCurrency = StringSubstr(fromCandidate.symbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromCandidate.symbolName, 3, 3);
        string strongCurrency = baseCurrency;
        string weakCurrency = quoteCurrency;
        int strongRank = fromCandidate.baseLongMediumRank;
        int weakRank = fromCandidate.quoteLongMediumRank;
        if (!fromCandidate.isBuy) {
            sideText = "SELL";
            strongCurrency = quoteCurrency;
            weakCurrency = baseCurrency;
            strongRank = fromCandidate.quoteLongMediumRank;
            weakRank = fromCandidate.baseLongMediumRank;
        }

        string tooltip = conditionText + " / " + sideText
            + StringFormat("\n%s %d位 / %s %d位（差%s）",
                baseCurrency, fromCandidate.baseLongMediumRank,
                quoteCurrency, fromCandidate.quoteLongMediumRank,
                this.formatDifference(fromCandidate.longMediumRankDifference));
        if (MathAbs(fromCandidate.longMediumRankDifference) < 4
                && fromCandidate.isLongMediumExtremeRankMatched()) {
            if (strongRank == 1) {
                tooltip += "\n強い通貨（買う" + strongCurrency + "）が1位";
            }
            if (weakRank == 8) {
                tooltip += "\n弱い通貨（売る" + weakCurrency + "）が8位";
            }
        }

        tooltip += "\n端＝強い通貨1位または弱い通貨8位"
            + "\nREADYには中短期差4以上も必要";

        return tooltip;
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
            + "\n通貨強弱のM5集計時点に対応するH1確定足";

        return tooltip;
    }

    /**
     * M1 EMA200の最新確定足と値を操作案内へまとめる。
     *
     * @param fromCandidate 表示対象候補。
     * @return 判定時刻、EMA値、終値との差、傾き、未取得理由を含む操作案内。
     */
    string getM1EmaTooltip(CurrencyStrengthEntryCandidate &fromCandidate) {
        if (Util::isStrategyTester()) {
            return "M1 EMA200：取得対象外\nテスターの下位足参照制限に対応するため取得しません";
        }

        if (!fromCandidate.m1EmaAvailable) {
            return "M1 EMA200：取得待ち\n最新確定足の共通判定を取得できていません";
        }

        string tooltip = "M1確定足 SERVER："
            + TimeToString(fromCandidate.m1EmaBarTime, TIME_DATE | TIME_MINUTES)
            + "\nEMA200：" + DoubleToString(fromCandidate.m1EmaValue, fromCandidate.m1EmaDigits)
            + StringFormat("\n終値－EMA200：%+.1f p\nEMA200傾き：%+.1f p",
                fromCandidate.m1EmaCloseDiffPips, fromCandidate.m1EmaSlopePips)
            + "\n共通判定：" + fromCandidate.getM1EmaLabel()
            + "\nM1は最新確定足。H1の集計基準時刻とは異なります";

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
        int cellIndex = fromRowIndex * this.getColumnCount() + fromColumnIndex;
        bool textChanged = this.displayedCellTexts[cellIndex] != fromText;
        bool colorChanged = this.displayedCellColors[cellIndex] != fromColor;
        if (!textChanged && !colorChanged) {
            return;
        }

        string objectName = this.getCellObjectName(
            fromRowIndex,
            fromColumnIndex
        );
        if (textChanged && ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText)) {
            this.displayedCellTexts[cellIndex] = fromText;
        }

        if (colorChanged && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor)) {
            this.displayedCellColors[cellIndex] = fromColor;
        }
    }

    /**
     * セルの説明文が変わった場合だけ反映する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromTooltip 説明文。
     */
    void setCellTooltip(const int fromRowIndex, const int fromColumnIndex, const string fromTooltip) {
        int cellIndex = fromRowIndex * this.getColumnCount() + fromColumnIndex;
        if (this.displayedCellTooltips[cellIndex] == fromTooltip) {
            return;
        }

        if (ObjectSetString(this.chartId, this.getCellObjectName(fromRowIndex, fromColumnIndex),
                OBJPROP_TOOLTIP, fromTooltip)) {
            this.displayedCellTooltips[cellIndex] = fromTooltip;
        }
    }

    /**
     * GMO目印の説明文が変わった場合だけ反映する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromTooltip 説明文。
     */
    void setGmoTooltip(const int fromRowIndex, const string fromTooltip) {
        if (this.displayedGmoTooltips[fromRowIndex] == fromTooltip) {
            return;
        }

        if (ObjectSetString(this.chartId, this.getGmoObjectName(fromRowIndex),
                OBJPROP_TOOLTIP, fromTooltip)) {
            this.displayedGmoTooltips[fromRowIndex] = fromTooltip;
        }
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
                return 36;
            case 2:
                return 128;
            case 3:
                return 172;
            case 4:
                return 258;
            case 5:
                return 336;
            case 6:
                return 402;
            case 7:
                return 454;
            case 8:
                return 500;
            case 9:
                return 548;
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
                return "差/合計";
            case 6:
                return "強弱";
            case 7:
                return "H1";
            case 8:
                return "M1";
            case 9:
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
     * GMO目印のオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @return オブジェクト名。
     */
    string getGmoObjectName(const int fromRowIndex) const {
        return this.objectPrefix + "Gmo_" + IntegerToString(fromRowIndex);
    }

    /**
     * 候補一覧専用オブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.readyHighlightEnabled = false;
        this.displayedSelectedRow = -2;
        this.hasNewMarkers = false;
        ArrayResize(this.displayedSymbols, 0);
        ArrayResize(this.displayedReady, 0);
        ArrayResize(this.displayedBuy, 0);
        ArrayResize(this.displayedNewPending, 0);
        ArrayResize(this.displayedAndTexts, 0);
        ArrayResize(this.displayedAndColors, 0);
        ArrayResize(this.displayedGmo, 0);
        ArrayResize(this.clearedRows, 0);
        ArrayResize(this.displayedCellTexts, 0);
        ArrayResize(this.displayedCellColors, 0);
        ArrayResize(this.displayedCellTooltips, 0);
        ArrayResize(this.displayedGmoTooltips, 0);
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
