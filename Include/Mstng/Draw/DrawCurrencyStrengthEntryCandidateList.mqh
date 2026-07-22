//+------------------------------------------------------------------+
//|           DrawCurrencyStrengthEntryCandidateList.mqh |
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
     */
    DrawCurrencyStrengthEntryCandidateList(
        const long fromChartId,
        const int fromXDistance,
        const int fromYDistance,
        const int fromMaximumCount
    ) {
        this.chartId = fromChartId;
        string baseObjectPrefix = Constant::PREFIX_FIXED
            + "CurrencyStrengthEntryCandidateList_";
        int instanceIndex = 0;
        this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";

        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0) {
            instanceIndex++;
            this.objectPrefix = baseObjectPrefix
                + IntegerToString(instanceIndex)
                + "_";
        }

        this.created = false;
        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.maximumCount = fromMaximumCount;
        this.panelWidth = 1000;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 39;
        this.separatorYDistance = 58;
        this.firstRowYDistance = 65;
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

        ChartRedraw(this.chartId);

        return true;
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

    /**
     * 候補一覧パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();
        int panelHeight = this.firstRowYDistance
            + this.maximumCount * this.rowHeight
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
            "ENTRY CANDIDATES"
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

        this.created = true;

        return true;
    }

    /**
     * 候補一覧タイトルを更新する。
     *
     * @param fromCandidateList 候補一覧。
     */
    void updateTitle(CurrencyStrengthEntryCandidateList *fromCandidateList) {
        string titleText = StringFormat(
            "ENTRY CANDIDATES  WAITING DATA %d/%d",
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
                titleText = StringFormat(
                    "ENTRY CANDIDATES  LONG-MID + MID-SHORT  MIN GAP %d  NO ENTRY CANDIDATES",
                    fromCandidateList.getMinimumRankDifference()
                );
            } else {
                titleText = StringFormat(
                    "ENTRY CANDIDATES  LONG-MID + MID-SHORT  MIN GAP %d  FOUND %d  TOP %d",
                    fromCandidateList.getMinimumRankDifference(),
                    fromCandidateList.size(),
                    visibleCount
                );
            }

            displayColor = this.titleColor;
        }

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            titleText
        );
        ObjectSetInteger(
            this.chartId,
            this.objectPrefix + "Title",
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
        for (int i = 0; i < this.getColumnCount(); i++) {
            this.setCell(fromRowIndex, i, "", this.mutedColor);
        }
    }

    /**
     * 基軸通貨順位と決済通貨順位を表示用文字列へ変換する。
     *
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteRank 決済通貨順位。
     * @return 基軸通貨順位/決済通貨順位。
     */
    string formatRanks(const int fromBaseRank, const int fromQuoteRank) {
        return StringFormat("%d / %d", fromBaseRank, fromQuoteRank);
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
                return 44;
            case 2:
                return 125;
            case 3:
                return 200;
            case 4:
                return 350;
            case 5:
                return 420;
            case 6:
                return 580;
            case 7:
                return 650;
            case 8:
                return 720;
            case 9:
                return 800;
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
    ) {
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
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
