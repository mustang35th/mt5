//+------------------------------------------------------------------+
//|                          DrawCurrencyStrengthRankComparison.mqh   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_COMPARISON_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_COMPARISON_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>

/**
 * 同一時点の長中期と中短期の通貨順位を、固定位置の接続線で比較する。
 * 同順位は実順位を保ち、通貨名順の別行へ表示する。
 */
class DrawCurrencyStrengthRankComparison {
public:
    /**
     * 描画対象と固定位置を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート左端からの距離。
     * @param fromYDistance チャート上端からの距離。
     * @param fromInstanceKey 同一チャート内のインスタンス識別子。
     */
    DrawCurrencyStrengthRankComparison(
        long fromChartId = 0,
        int fromXDistance = 12,
        int fromYDistance = 12,
        string fromInstanceKey = ""
    ) {
        this.chartId = fromChartId;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.panelWidth = 360;
        this.panelHeight = 350;
        this.firstRowYDistance = 82;
        this.rowHeight = 26;
        this.canvasLeft = 76;
        this.canvasTop = 80;
        this.canvasWidth = 208;
        this.canvasHeight = 208;
        this.displayRowCount = 8;
        this.requiredRowCount = 8;
        this.fontName = "MS Gothic";
        this.panelBackgroundColor = C'18,18,18';
        this.headerBackgroundColor = C'56,74,104';
        this.mutedColor = C'130,130,130';
        this.created = false;
        this.rankingReady = false;
        this.selectedCurrency = "";
        this.selectedSecondCurrency = "";
        this.selectedPair = "";
        this.readyHighlightEnabled = false;
        this.readyCurrencyCount = 0;
        ArrayInitialize(this.readyCurrencyMask, false);
        this.statusText = "WAITING DATA";
        this.statusColor = clrGold;

        this.currencyNames[0] = "USD";
        this.currencyNames[1] = "JPY";
        this.currencyNames[2] = "EUR";
        this.currencyNames[3] = "GBP";
        this.currencyNames[4] = "AUD";
        this.currencyNames[5] = "NZD";
        this.currencyNames[6] = "CAD";
        this.currencyNames[7] = "CHF";

        // オブジェクト名の63文字制限内に背景名と連番を収める。
        string baseObjectPrefix = Constant::PREFIX_FIXED + "CurrencyRank_";
        if (fromInstanceKey != "") {
            baseObjectPrefix += StringSubstr(fromInstanceKey, 0, 12) + "_";
        }

        // 描画前に複数インスタンスが作られた場合も名前を重複させない。
        static int nextInstanceIndex = 0;
        int instanceIndex = nextInstanceIndex;
        this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";
        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0) {
            instanceIndex++;
            this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";
        }

        nextInstanceIndex = instanceIndex + 1;
    }

    /**
     * 描画オブジェクトとCanvasリソースを解放する。
     */
    ~DrawCurrencyStrengthRankComparison() {
        this.destroyObjects();
    }

    /**
     * 集計結果の実順位を取得し、左右の通貨と接続線を更新する。
     *
     * @param fromCalculator 通貨強弱集計結果。
     * @param fromSnapshotTime 互換性のため保持する対象時刻。日時は共通欄で表示する。
     * @return パネル更新に成功した場合true。集計待ちは正常表示としてtrue。
     */
    bool draw(CurrencyStrengthCalculator *fromCalculator, datetime fromSnapshotTime = 0) {
        if (fromCalculator == NULL) {
            this.resetReadyHighlight(true);

            return false;
        }

        bool ranksReady = this.readRanks(fromCalculator);
        string previousSelection = this.selectedCurrency;
        string previousSecondSelection = this.selectedSecondCurrency;
        string previousPairSelection = this.selectedPair;
        bool previousReadyHighlight = this.readyHighlightEnabled;
        int previousReadyCurrencyCount = this.readyCurrencyCount;
        bool previousReadyCurrencyMask[8];
        ArrayCopy(previousReadyCurrencyMask, this.readyCurrencyMask);
        if (!this.created || (ranksReady && this.displayRowCount != this.requiredRowCount)) {
            if (ranksReady) {
                this.displayRowCount = this.requiredRowCount;
            }

            this.canvasHeight = this.displayRowCount * this.rowHeight;
            this.panelHeight = this.firstRowYDistance + this.canvasHeight + 60;
            if (!this.create()) {
                return false;
            }

            this.selectedCurrency = previousSelection;
            this.selectedSecondCurrency = previousSecondSelection;
            this.selectedPair = previousPairSelection;
            this.readyHighlightEnabled = previousReadyHighlight;
            this.readyCurrencyCount = previousReadyCurrencyCount;
            ArrayCopy(this.readyCurrencyMask, previousReadyCurrencyMask);
        }

        this.rankingReady = ranksReady;
        if (!this.rankingReady) {
            this.selectedCurrency = "";
            this.selectedSecondCurrency = "";
            this.selectedPair = "";
            this.resetReadyHighlight();
        }

        this.updateTitle(fromCalculator);
        this.renderComparison();
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 固定パネル幅を取得する。
     *
     * @return ピクセル単位のパネル幅。
     */
    int getPanelWidth() const {
        return this.panelWidth;
    }

    /**
     * 専用オブジェクトとCanvasリソースを削除する。
     */
    void clear() {
        this.destroyObjects();
        ChartRedraw(this.chartId);
    }

    /**
     * 表示中のREADY候補に含まれる通貨をまとめて強調する。
     * 対象が空でもONを保持し、全通貨を通常表示する。
     *
     * @param fromEnabled READY強調を有効にする場合true。
     * @param fromSymbols 主要8通貨からなる大文字6文字の候補ペア一覧。
     * @return 設定を反映できた場合true。無効な指定ではREADY強調を解除する。
     */
    bool setReadyHighlight(const bool fromEnabled, const string &fromSymbols[]) {
        if (!fromEnabled) {
            this.resetReadyHighlight(true);

            return true;
        }

        if (!this.created || !this.rankingReady) {
            this.resetReadyHighlight(true);

            return false;
        }

        bool nextCurrencyMask[8];
        ArrayInitialize(nextCurrencyMask, false);
        int nextCurrencyCount = 0;
        for (int i = 0; i < ArraySize(fromSymbols); i++) {
            if (StringLen(fromSymbols[i]) != 6) {
                this.resetReadyHighlight(true);

                return false;
            }

            int baseIndex = this.getCurrencyIndex(StringSubstr(fromSymbols[i], 0, 3));
            int quoteIndex = this.getCurrencyIndex(StringSubstr(fromSymbols[i], 3, 3));
            if (baseIndex < 0 || quoteIndex < 0 || baseIndex == quoteIndex) {
                this.resetReadyHighlight(true);

                return false;
            }

            if (!nextCurrencyMask[baseIndex]) {
                nextCurrencyMask[baseIndex] = true;
                nextCurrencyCount++;
            }

            if (!nextCurrencyMask[quoteIndex]) {
                nextCurrencyMask[quoteIndex] = true;
                nextCurrencyCount++;
            }
        }

        this.selectedCurrency = "";
        this.selectedSecondCurrency = "";
        this.selectedPair = "";
        this.readyHighlightEnabled = true;
        this.readyCurrencyCount = nextCurrencyCount;
        ArrayCopy(this.readyCurrencyMask, nextCurrencyMask);
        this.renderComparison();
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * READY候補の通貨強調が有効か取得する。
     *
     * @return 対象通貨の有無にかかわらずREADY強調がONならtrue。
     */
    bool isReadyHighlightEnabled() const {
        return this.readyHighlightEnabled;
    }

    /**
     * 候補ペアの2通貨を強調する。同じペアの再選択では強調を解除する。
     *
     * @param fromSymbolName 主要8通貨からなる大文字6文字の通貨ペア名。
     * @return 有効な通貨ペアの選択を処理した場合true。
     */
    bool togglePairSelection(const string fromSymbolName) {
        if (!this.created || !this.rankingReady || StringLen(fromSymbolName) != 6) {
            return false;
        }

        string baseCurrency = StringSubstr(fromSymbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromSymbolName, 3, 3);
        if (baseCurrency == quoteCurrency
                || this.getCurrencyIndex(baseCurrency) < 0
                || this.getCurrencyIndex(quoteCurrency) < 0) {
            return false;
        }

        this.resetReadyHighlight();
        if (this.selectedPair == fromSymbolName) {
            this.selectedCurrency = "";
            this.selectedSecondCurrency = "";
            this.selectedPair = "";
        } else {
            this.selectedCurrency = baseCurrency;
            this.selectedSecondCurrency = quoteCurrency;
            this.selectedPair = fromSymbolName;
        }

        this.renderComparison();
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 候補ペアのクリックで選択している通貨ペア名を取得する。
     *
     * @return 候補から選択中の通貨ペア名。未選択または通貨名からの手動選択は空文字。
     */
    string getSelectedPair() const {
        return this.selectedPair;
    }

    /**
     * 候補ペアの選択だけを解除する。通貨名からの手動選択は維持する。
     */
    void clearPairSelection() {
        if (this.selectedPair == "") {
            return;
        }

        this.selectedCurrency = "";
        this.selectedSecondCurrency = "";
        this.selectedPair = "";
        if (this.created) {
            this.renderComparison();
            ChartRedraw(this.chartId);
        }
    }

    /**
     * 通貨ラベルのクリックで最大2通貨を選択する。選択済み通貨は解除する。
     * 3通貨目は先に選択した通貨と入れ替え、解除ボタンでは選択をすべて消す。
     *
     * @param fromObjectName CHARTEVENT_OBJECT_CLICKで通知された名前。
     * @return このパネルの有効な通貨または解除ボタンのクリックを処理した場合true。
     */
    bool handleObjectClick(const string fromObjectName) {
        if (!this.created) {
            return false;
        }

        if (fromObjectName == this.objectPrefix + "ClearSelection") {
            this.selectedCurrency = "";
            this.selectedSecondCurrency = "";
            this.selectedPair = "";
            this.resetReadyHighlight();
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.renderComparison();
            ChartRedraw(this.chartId);

            return true;
        }

        if (!this.rankingReady) {
            return false;
        }

        for (int i = 0; i < 8; i++) {
            if (fromObjectName != this.getCurrencyObjectName(true, i)
                    && fromObjectName != this.getCurrencyObjectName(false, i)) {
                continue;
            }

            this.resetReadyHighlight();
            this.selectedPair = "";
            if (this.selectedCurrency == this.currencyNames[i]) {
                this.selectedCurrency = this.selectedSecondCurrency;
                this.selectedSecondCurrency = "";
            } else if (this.selectedSecondCurrency == this.currencyNames[i]) {
                this.selectedSecondCurrency = "";
            } else if (this.selectedCurrency == "") {
                this.selectedCurrency = this.currencyNames[i];
            } else if (this.selectedSecondCurrency == "") {
                this.selectedSecondCurrency = this.currencyNames[i];
            } else {
                this.selectedCurrency = this.selectedSecondCurrency;
                this.selectedSecondCurrency = this.currencyNames[i];
            }

            this.renderComparison();
            ChartRedraw(this.chartId);

            return true;
        }

        return false;
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル生成済みの場合true。 */
    bool created;

    /** 全通貨の実順位が利用可能な場合true。 */
    bool rankingReady;

    /** パネル左位置。 */
    int xDistance;

    /** パネル上位置。 */
    int yDistance;

    /** パネル幅。 */
    int panelWidth;

    /** パネル高さ。 */
    int panelHeight;

    /** 通貨ラベルの先頭行位置。 */
    int firstRowYDistance;

    /** 通貨表示行の高さ。 */
    int rowHeight;

    /** Canvas左位置。パネル左端からの距離。 */
    int canvasLeft;

    /** Canvas上位置。パネル上端からの距離。 */
    int canvasTop;

    /** Canvas幅。 */
    int canvasWidth;

    /** Canvas高さ。 */
    int canvasHeight;

    /** 現在のパネルで確保した表示行数。 */
    int displayRowCount;

    /** 共有順位帯に必要な表示行数。 */
    int requiredRowCount;

    /** 接続線用の透明Canvas。 */
    CCanvas lineCanvas;

    /** 表示フォント。 */
    string fontName;

    /** パネル背景色。 */
    color panelBackgroundColor;

    /** タイトル背景色。 */
    color headerBackgroundColor;

    /** 補助文字色。 */
    color mutedColor;

    /** 色とオブジェクト名を固定する主要8通貨。 */
    string currencyNames[8];

    /** 通貨ごとの長中期の実順位。 */
    int leftRanks[8];

    /** 通貨ごとの中短期の実順位。 */
    int rightRanks[8];

    /** 通貨ごとの長中期表示行。 */
    int leftRows[8];

    /** 通貨ごとの中短期表示行。 */
    int rightRows[8];

    /** 実順位1から8の共有帯の開始行。 */
    int rankBandStarts[8];

    /** 実順位1から8の共有帯の行数。 */
    int rankBandSizes[8];

    /** 先に選択した通貨。空文字は選択なし。 */
    string selectedCurrency;

    /** 後に選択した通貨。空文字は2通貨目の選択なし。 */
    string selectedSecondCurrency;

    /** 候補から選択中のペア。空文字は未選択または通貨名からの手動選択。 */
    string selectedPair;

    /** 表示中のREADY候補の通貨を強調する場合true。 */
    bool readyHighlightEnabled;

    /** READY候補に含まれる通貨の選択状態。 */
    bool readyCurrencyMask[8];

    /** READY候補に含まれる重複なしの通貨数。 */
    int readyCurrencyCount;

    /** 通貨未選択時に表示する集計状態。 */
    string statusText;

    /** 通貨未選択時の集計状態の文字色。 */
    color statusColor;

    /**
     * 背景、透明Canvas、文字の順に固定パネルを生成する。
     *
     * @return 全オブジェクトを生成できた場合true。
     */
    bool create() {
        this.destroyObjects();
        int footerTop = this.firstRowYDistance + this.canvasHeight + 7;

        if (!this.createRectangle("Panel", 0, 0, this.panelWidth, this.panelHeight,
                this.panelBackgroundColor, clrDimGray)
                || !this.createRectangle("TitleBackground", 1, 1, this.panelWidth - 2, 25,
                    this.headerBackgroundColor, this.headerBackgroundColor)
                || !this.createRectangle("HeaderSeparator", 12, 73, this.panelWidth - 24, 1,
                    clrDimGray, clrDimGray)
                || !this.createRectangle("FooterSeparator", 12, footerTop, this.panelWidth - 24, 1,
                    clrDimGray, clrDimGray)) {
            this.destroyObjects();

            return false;
        }

        string canvasName = this.objectPrefix + "Lines";
        if (!this.lineCanvas.CreateBitmapLabel(
                this.chartId, 0, canvasName,
                this.xDistance + this.canvasLeft, this.yDistance + this.canvasTop,
                this.canvasWidth, this.canvasHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
            this.destroyObjects();

            return false;
        }

        this.configureObject(canvasName, 0);
        ObjectSetInteger(this.chartId, canvasName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetString(this.chartId, canvasName, OBJPROP_TOOLTIP, "\n");
        this.lineCanvas.Erase(0);
        this.lineCanvas.Update(false);

        if (!this.createLabel("Title", 14, 5, 11, clrWhite, "通貨順位比較")
                || !this.createLabel("Status", 14, 32, 10, clrGold, "WAITING DATA")
                || !this.createClearSelectionButton()
                || !this.createLabel("LeftHeader", 14, 55, 10, C'180,180,180', "LONG-MID")
                || !this.createLabel("RightHeader", this.panelWidth - 102, 55, 10, C'180,180,180', "MID-SHORT")
                || !this.createLabel("Footer", 14, footerTop + 9, 10, this.mutedColor,
                    "同時点の比較・同順位は同じ帯")
                || !this.createLabel("Hint", 14, footerTop + 30, 10, this.mutedColor,
                    "2通貨まで選択・再クリックで解除")) {
            this.destroyObjects();

            return false;
        }

        ObjectSetString(this.chartId, this.objectPrefix + "LeftHeader", OBJPROP_TOOLTIP,
            "長中期：MN1・W1・D1・H4・H1の平均スコア順位");
        ObjectSetString(this.chartId, this.objectPrefix + "RightHeader", OBJPROP_TOOLTIP,
            "中短期：D1・H4・H1・M15・M5の平均スコア順位");

        for (int i = 0; i < 8; i++) {
            if (!this.createLabel("Left_" + this.currencyNames[i], 14,
                    this.firstRowYDistance + i * this.rowHeight, 11, this.getCurrencyColor(i), " ")
                    || !this.createLabel("Right_" + this.currencyNames[i], this.panelWidth - 62,
                        this.firstRowYDistance + i * this.rowHeight, 11, this.getCurrencyColor(i), " ")) {
                this.destroyObjects();

                return false;
            }

            string tooltip = this.currencyNames[i]
                + "：クリックで選択・解除（最大2通貨）。3通貨目は先に選んだ通貨と入替。"
                + "数字は実順位、同順位は通貨名順。";
            ObjectSetInteger(this.chartId, this.getCurrencyObjectName(true, i), OBJPROP_ZORDER, 3);
            ObjectSetInteger(this.chartId, this.getCurrencyObjectName(false, i), OBJPROP_ZORDER, 3);
            ObjectSetString(this.chartId, this.getCurrencyObjectName(true, i), OBJPROP_TOOLTIP, tooltip);
            ObjectSetString(this.chartId, this.getCurrencyObjectName(false, i), OBJPROP_TOOLTIP, tooltip);
        }

        this.created = true;

        return true;
    }

    /**
     * 全28ペアが揃った場合だけ、既存APIから8通貨の実順位を取得する。
     *
     * @param fromCalculator 集計結果。
     * @return 両期間の全順位が有効な場合true。
     */
    bool readRanks(CurrencyStrengthCalculator *fromCalculator) {
        if (fromCalculator.validPairCount != fromCalculator.getExpectedPairCount()
                || fromCalculator.size() != 8) {
            return false;
        }

        bool assigned[8];
        ArrayInitialize(assigned, false);
        for (int i = 0; i < 8; i++) {
            CurrencyStrengthInfo *info = fromCalculator.getInfo(i);
            if (info == NULL) {
                return false;
            }

            int currencyIndex = this.getCurrencyIndex(info.currencyName);
            if (currencyIndex < 0 || assigned[currencyIndex]) {
                return false;
            }

            int leftRank = fromCalculator.getLongMediumTermAverageRank(i);
            int rightRank = fromCalculator.getMediumShortTermAverageRank(i);
            if (leftRank < 1 || leftRank > 8 || rightRank < 1 || rightRank > 8) {
                return false;
            }

            assigned[currencyIndex] = true;
            this.leftRanks[currencyIndex] = leftRank;
            this.rightRanks[currencyIndex] = rightRank;
        }

        this.buildRankBands();
        this.buildRows(this.leftRanks, this.leftRows);
        this.buildRows(this.rightRanks, this.rightRows);

        return true;
    }

    /**
     * 左右で共有する実順位帯を作り、同順位数の多い側に必要な行数を確保する。
     */
    void buildRankBands() {
        int leftCounts[8];
        int rightCounts[8];
        ArrayInitialize(leftCounts, 0);
        ArrayInitialize(rightCounts, 0);
        for (int i = 0; i < 8; i++) {
            leftCounts[this.leftRanks[i] - 1]++;
            rightCounts[this.rightRanks[i] - 1]++;
        }

        this.requiredRowCount = 0;
        for (int i = 0; i < 8; i++) {
            this.rankBandStarts[i] = this.requiredRowCount;
            this.rankBandSizes[i] = leftCounts[i];
            if (rightCounts[i] > this.rankBandSizes[i]) {
                this.rankBandSizes[i] = rightCounts[i];
            }

            this.requiredRowCount += this.rankBandSizes[i];
        }
    }

    /**
     * 実順位、通貨名の順に並べ、重ならない表示行を割り当てる。
     *
     * @param fromRanks 通貨ごとの実順位。
     * @param fromRows 通貨ごとの表示行格納先。
     */
    void buildRows(const int &fromRanks[], int &fromRows[]) {
        int order[8];
        for (int i = 0; i < 8; i++) {
            order[i] = i;
        }

        for (int i = 1; i < 8; i++) {
            int currencyIndex = order[i];
            int j = i - 1;
            while (j >= 0) {
                int previousIndex = order[j];
                if (fromRanks[currencyIndex] > fromRanks[previousIndex]
                        || (fromRanks[currencyIndex] == fromRanks[previousIndex]
                            && StringCompare(this.currencyNames[currencyIndex],
                                this.currencyNames[previousIndex]) >= 0)) {
                    break;
                }

                order[j + 1] = order[j];
                j--;
            }

            order[j + 1] = currencyIndex;
        }

        int usedRows[8];
        ArrayInitialize(usedRows, 0);
        for (int i = 0; i < 8; i++) {
            int rankIndex = fromRanks[order[i]] - 1;
            fromRows[order[i]] = this.rankBandStarts[rankIndex] + usedRows[rankIndex];
            usedRows[rankIndex]++;
        }
    }

    /**
     * 集計方式と集計済みペア数を更新する。
     *
     * @param fromCalculator 集計結果。
     */
    void updateTitle(CurrencyStrengthCalculator *fromCalculator) {
        string voteWeightModeText = "均等";
        if (fromCalculator.getVoteWeightMode() == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED) {
            voteWeightModeText = "重み付き";
        }

        ObjectSetString(this.chartId, this.objectPrefix + "Title", OBJPROP_TEXT,
            "通貨順位比較［" + voteWeightModeText + "］");

        this.statusText = StringFormat("WAITING DATA %d/%d",
            fromCalculator.validPairCount, fromCalculator.getExpectedPairCount());
        this.statusColor = clrGold;
        if (this.rankingReady) {
            this.statusText = StringFormat("集計済み：%d/%dペア",
                fromCalculator.validPairCount, fromCalculator.getExpectedPairCount());
            this.statusColor = this.mutedColor;
        }
    }

    /**
     * READY強調、選択中の通貨、または直近の集計状態を表示する。
     */
    void updateSelectionStatus() {
        string displayText = this.statusText;
        color displayColor = this.statusColor;
        bool hasSelection = this.rankingReady
            && (this.selectedCurrency != "" || this.readyHighlightEnabled);
        if (this.rankingReady && this.readyHighlightEnabled) {
            displayText = "AND対象なし";
            displayColor = this.mutedColor;
            if (this.readyCurrencyCount > 0) {
                displayText = StringFormat("AND成立：%d通貨", this.readyCurrencyCount);
                displayColor = clrWhite;
            }
        } else if (hasSelection) {
            displayText = "選択：" + this.selectedCurrency;
            if (this.selectedPair != "") {
                displayText = "選択：" + this.selectedPair;
            } else if (this.selectedSecondCurrency != "") {
                displayText += " / " + this.selectedSecondCurrency;
            }

            displayColor = clrWhite;
        }

        ObjectSetString(this.chartId, this.objectPrefix + "Status", OBJPROP_TEXT, displayText);
        ObjectSetInteger(this.chartId, this.objectPrefix + "Status", OBJPROP_COLOR, displayColor);

        color clearButtonColor = this.mutedColor;
        if (hasSelection) {
            clearButtonColor = clrWhite;
        }

        ObjectSetInteger(this.chartId, this.objectPrefix + "ClearSelection",
            OBJPROP_COLOR, clearButtonColor);
    }

    /**
     * 保持済み順位から通貨ラベルと接続線を更新する。
     */
    void renderComparison() {
        this.updateSelectionStatus();
        this.lineCanvas.Erase(0);
        for (int i = 0; i < 8; i++) {
            string leftText = " ";
            string rightText = " ";
            color labelColor = this.getCurrencyColor(i);
            if (this.rankingReady) {
                leftText = StringFormat("%d %s", this.leftRanks[i], this.currencyNames[i]);
                rightText = StringFormat("%d %s", this.rightRanks[i], this.currencyNames[i]);
                ObjectSetInteger(this.chartId, this.getCurrencyObjectName(true, i), OBJPROP_YDISTANCE,
                    this.yDistance + this.firstRowYDistance + this.leftRows[i] * this.rowHeight);
                ObjectSetInteger(this.chartId, this.getCurrencyObjectName(false, i), OBJPROP_YDISTANCE,
                    this.yDistance + this.firstRowYDistance + this.rightRows[i] * this.rowHeight);
                if (this.hasHighlightedCurrencies()) {
                    labelColor = this.mutedColor;
                    if (this.isCurrencySelected(this.currencyNames[i])) {
                        labelColor = clrWhite;
                    }
                }
            }

            ObjectSetString(this.chartId, this.getCurrencyObjectName(true, i), OBJPROP_TEXT, leftText);
            ObjectSetString(this.chartId, this.getCurrencyObjectName(false, i), OBJPROP_TEXT, rightText);
            ObjectSetInteger(this.chartId, this.getCurrencyObjectName(true, i), OBJPROP_COLOR, labelColor);
            ObjectSetInteger(this.chartId, this.getCurrencyObjectName(false, i), OBJPROP_COLOR, labelColor);
        }

        if (this.rankingReady) {
            this.drawRankBands();
            for (int i = 0; i < 8; i++) {
                if (!this.isCurrencySelected(this.currencyNames[i])) {
                    this.drawConnection(i, false);
                }
            }

            for (int i = 0; i < 8; i++) {
                if (this.isCurrencySelected(this.currencyNames[i])) {
                    this.drawConnection(i, true);
                }
            }
        }

        this.lineCanvas.Update(false);
    }

    /**
     * READY強調または手動・候補ペア選択による通貨の選択状態を判定する。
     *
     * @param fromCurrencyName 通貨名。
     * @return 強調対象の場合true。
     */
    bool isCurrencySelected(const string fromCurrencyName) {
        if (this.readyHighlightEnabled) {
            int currencyIndex = this.getCurrencyIndex(fromCurrencyName);
            if (currencyIndex < 0) {
                return false;
            }

            return this.readyCurrencyMask[currencyIndex];
        }

        return this.selectedCurrency == fromCurrencyName
            || this.selectedSecondCurrency == fromCurrencyName;
    }

    /**
     * 他通貨を薄く表示するための強調対象があるか判定する。
     *
     * @return 手動選択またはREADY対象通貨がある場合true。
     */
    bool hasHighlightedCurrencies() const {
        return this.selectedCurrency != ""
            || (this.readyHighlightEnabled && this.readyCurrencyCount > 0);
    }

    /**
     * READY強調だけを解除し、手動選択は変更しない。
     *
     * @param fromRedraw ONから解除した場合に表示も更新するならtrue。
     */
    void resetReadyHighlight(const bool fromRedraw = false) {
        bool wasEnabled = this.readyHighlightEnabled;
        this.readyHighlightEnabled = false;
        this.readyCurrencyCount = 0;
        ArrayInitialize(this.readyCurrencyMask, false);
        if (fromRedraw && wasEnabled && this.created) {
            this.renderComparison();
            ChartRedraw(this.chartId);
        }
    }

    /**
     * 左右共通の順位帯を薄く描き、同順位内の表示ずらしを区別する。
     */
    void drawRankBands() {
        for (int i = 0; i < 8; i++) {
            if (this.rankBandSizes[i] <= 0) {
                continue;
            }

            int top = this.rankBandStarts[i] * this.rowHeight;
            int bottom = top + this.rankBandSizes[i] * this.rowHeight - 1;
            uint bandColor = ColorToARGB(C'45,55,70', 70);
            if (i % 2 == 0) {
                bandColor = ColorToARGB(C'65,75,90', 70);
            }

            this.lineCanvas.FillRectangle(0, top, this.canvasWidth - 1, bottom, bandColor);
            this.lineCanvas.LineHorizontal(0, this.canvasWidth - 1, top,
                ColorToARGB(clrDimGray, 75));
        }
    }

    /**
     * 1通貨の線を描く。選択線は最後に太く描いて交差位置でも追跡可能にする。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @param fromSelected 強調する場合true。
     */
    void drawConnection(const int fromCurrencyIndex, const bool fromSelected) {
        int leftY = this.firstRowYDistance - this.canvasTop
            + this.leftRows[fromCurrencyIndex] * this.rowHeight + 8;
        int rightY = this.firstRowYDistance - this.canvasTop
            + this.rightRows[fromCurrencyIndex] * this.rowHeight + 8;
        uchar opacity = 230;
        if (this.hasHighlightedCurrencies() && !fromSelected) {
            opacity = 55;
        }

        uint lineColor = ColorToARGB(this.getCurrencyColor(fromCurrencyIndex), opacity);
        int radius = 2;
        if (fromSelected) {
            lineColor = ColorToARGB(this.getCurrencyColor(fromCurrencyIndex), 255);
            this.lineCanvas.LineAA(4, leftY - 1, this.canvasWidth - 5, rightY - 1, lineColor);
            this.lineCanvas.LineAA(4, leftY + 1, this.canvasWidth - 5, rightY + 1, lineColor);
            radius = 3;
        }

        this.lineCanvas.LineAA(4, leftY, this.canvasWidth - 5, rightY, lineColor);
        this.lineCanvas.FillCircle(4, leftY, radius, lineColor);
        this.lineCanvas.FillCircle(this.canvasWidth - 5, rightY, radius, lineColor);
    }

    /**
     * 通貨名に対応する固定インデックスを取得する。
     *
     * @param fromCurrencyName 通貨名。
     * @return 見つからない場合は-1。
     */
    int getCurrencyIndex(const string fromCurrencyName) {
        for (int i = 0; i < 8; i++) {
            if (this.currencyNames[i] == fromCurrencyName) {
                return i;
            }
        }

        return -1;
    }

    /**
     * 共通の通貨定義から表示色を取得する。順位や売買方向では変更しない。
     *
     * @param fromCurrencyIndex 固定通貨番号。
     * @return 通貨の表示色。
     */
    color getCurrencyColor(const int fromCurrencyIndex) {
        if (fromCurrencyIndex < 0 || fromCurrencyIndex >= ArraySize(this.currencyNames)) {
            return this.mutedColor;
        }

        return ConstantCurrency::getColor(this.currencyNames[fromCurrencyIndex]);
    }

    /**
     * 通貨クリック用のオブジェクト名を取得する。
     *
     * @param fromLeft 長中期側の場合true。
     * @param fromCurrencyIndex 固定通貨番号。
     * @return オブジェクト名。
     */
    string getCurrencyObjectName(const bool fromLeft, const int fromCurrencyIndex) {
        string side = "Right_";
        if (fromLeft) {
            side = "Left_";
        }

        return this.objectPrefix + side + this.currencyNames[fromCurrencyIndex];
    }

    /**
     * 固定矩形を生成する。
     *
     * @return オブジェクトを生成できた場合true。
     */
    bool createRectangle(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const int fromHeight, const color fromBackground,
            const color fromBorder) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 0);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + fromLeft);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + fromTop);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromBackground);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromBorder);

        return true;
    }

    /**
     * 固定文字ラベルを生成する。
     *
     * @return オブジェクトを生成できた場合true。
     */
    bool createLabel(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromFontSize, const color fromColor, const string fromText) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 2);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + fromLeft);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + fromTop);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);

        return true;
    }

    /**
     * 集計状態の右側へ、手動選択と候補ペアの強調をすべて解除するボタンを生成する。
     *
     * @return ボタンを生成できた場合true。
     */
    bool createClearSelectionButton() {
        string objectName = this.objectPrefix + "ClearSelection";
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE,
            this.xDistance + this.panelWidth - 66);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 29);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 52);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 22);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.mutedColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'35,35,35');
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, clrDimGray);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, "解除");
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP,
            "手動選択・候補ペア・READY＋H1強調をすべて解除します");

        return true;
    }

    /**
     * チャートの移動や拡縮から独立したオブジェクト属性を設定する。
     *
     * @param fromObjectName 対象名。
     * @param fromZOrder クリックの優先度。
     */
    void configureObject(const string fromObjectName, const int fromZOrder) {
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, fromZOrder);
    }

    /**
     * 部分生成の失敗時も含め、所有する全リソースを解放する。
     */
    void destroyObjects() {
        this.lineCanvas.Destroy();
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.rankingReady = false;
        this.selectedCurrency = "";
        this.selectedSecondCurrency = "";
        this.selectedPair = "";
        this.resetReadyHighlight();
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_COMPARISON_MQH
