//+------------------------------------------------------------------+
//|                                         DrawElliotAllList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DRAW_DRAW_ELLIOT_ALL_LIST_MQH
#define MSTNG_DRAW_DRAW_ELLIOT_ALL_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\TimeFrameInfoAll.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorEma200.mqh>
#include <Mstng\Util\TimeUtil.mqh>

enum DrawElliotAllListColumn {
    drawElliotAllListColumnSymbol = 0,
    drawElliotAllListColumnTimeFrameStart = 1
};

enum DrawElliotAllListStatus {
    drawElliotAllListStatusReady = 0,
    drawElliotAllListStatusWatch = 1,
    drawElliotAllListStatusNone = 2,
    drawElliotAllListStatusError = 3
};

/**
 * 複数シンボルのElliott分析結果を固定一覧パネルへ描画するクラス。
 *
 * チャートオブジェクトは初回だけ生成し、分析更新時は表示文字列と色を
 * 更新する。分析オブジェクトへの参照は保持しない。
 */
class DrawElliotAllList {
public:
    /**
     * 描画対象チャートを指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     */
    DrawElliotAllList(long fromChartId = 0) {
        this.chartId = fromChartId;
        this.objectPrefix = Constant::PREFIX_FIXED + "ElliotAllList_";
        this.created = false;
        this.createdRowCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;

        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = 12;
        this.yDistance = 12;
        this.panelWidth = 600;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 39;
        this.separatorYDistance = 58;
        this.firstRowYDistance = 65;
        this.rowHeight = 18;
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
        this.watchColor = clrGold;
        this.errorColor = clrTomato;
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawElliotAllList() {
        if (this.created) {
            this.destroyObjects();
        }
    }

    /**
     * 複数シンボルの分析結果を一覧表示する。
     *
     * @param fromElliotAllList 描画対象の分析結果一覧。
     * @return 描画に成功した場合true。
     */
    bool draw(ElliotAllList *fromElliotAllList) {
        if (fromElliotAllList == NULL) {
            return false;
        }

        int total = fromElliotAllList.elliotAllList.Total();
        ENUM_TIMEFRAMES displayTimeFrames[];

        if (!this.buildDisplayTimeFrames(
            fromElliotAllList.marketContext.timeFrame,
            displayTimeFrames
        )) {
            return false;
        }

        if (!this.created
                || this.createdRowCount != total
                || this.createdCurrentTimeFrame != fromElliotAllList.marketContext.timeFrame) {
            if (!this.create(
                total,
                fromElliotAllList.marketContext.timeFrame,
                displayTimeFrames
            )) {
                return false;
            }
        }

        int displayOrder[];
        int statusRanks[];
        int readyCount = this.buildDisplayOrder(
            fromElliotAllList,
            displayOrder,
            statusRanks
        );

        string currentTimeFrameText = fromElliotAllList.marketContext.timeFrameLabel;

        if (currentTimeFrameText == "") {
            currentTimeFrameText = "CUR";
        }

        this.updateTitle(currentTimeFrameText, readyCount, total);

        for (int i = 0; i < total; i++) {
            int analysisIndex = displayOrder[i];
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(analysisIndex);

            this.drawRow(
                i,
                elliotAll,
                statusRanks[analysisIndex],
                displayTimeFrames
            );
        }

        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 一覧パネル専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 一覧パネル専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル生成済みの場合true。 */
    bool created;

    /** 生成済みの行数。 */
    int createdRowCount;

    /** 生成済み列の基準時間足。 */
    ENUM_TIMEFRAMES createdCurrentTimeFrame;

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** チャート左端からの距離。 */
    int xDistance;

    /** チャート上端からの距離。 */
    int yDistance;

    /** パネル横幅。 */
    int panelWidth;

    /** ヘッダー高さ。 */
    int headerHeight;

    /** 列ヘッダーのY位置。 */
    int columnHeaderYDistance;

    /** 区切り線のY位置。 */
    int separatorYDistance;

    /** 先頭データ行のY位置。 */
    int firstRowYDistance;

    /** データ行の高さ。 */
    int rowHeight;

    /** パネル下余白。 */
    int bottomPadding;

    /** 表示フォント名。 */
    string fontName;

    /** タイトルのフォントサイズ。 */
    int titleFontSize;

    /** 本文のフォントサイズ。 */
    int bodyFontSize;

    /** パネル背景色。 */
    color panelBackgroundColor;

    /** タイトル背景色。 */
    color headerBackgroundColor;

    /** パネル枠線色。 */
    color borderColor;

    /** タイトル文字色。 */
    color titleColor;

    /** 列ヘッダー文字色。 */
    color headerColor;

    /** 通常文字色。 */
    color normalColor;

    /** 非該当文字色。 */
    color mutedColor;

    /** BUY文字色。 */
    color buyColor;

    /** SELL文字色。 */
    color sellColor;

    /** WATCH文字色。 */
    color watchColor;

    /** ERROR文字色。 */
    color errorColor;

    /**
     * 指定行数の一覧パネルを生成する。
     *
     * @param fromRowCount 生成するデータ行数。
     * @param fromCurrentTimeFrame 基準時間足。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @return 生成に成功した場合true。
     */
    bool create(
        int fromRowCount,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[]
    ) {
        this.destroyObjects();

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);
        int columnCount = this.getColumnCount(timeFrameCount);

        this.panelWidth = this.calculatePanelWidth(timeFrameCount);

        int panelHeight = this.firstRowYDistance
            + (fromRowCount * this.rowHeight)
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
            "ZigZag Elliot List"
        )) {
            this.destroyObjects();

            return false;
        }

        for (int i = 0; i < columnCount; i++) {
            if (!this.createLabel(
                this.getHeaderObjectName(i),
                this.getColumnLeftOffset(i, timeFrameCount),
                this.columnHeaderYDistance,
                this.bodyFontSize,
                this.headerColor,
                this.getHeaderText(i, fromDisplayTimeFrames)
            )) {
                this.destroyObjects();

                return false;
            }
        }

        if (!this.createRectangle(
            this.objectPrefix + "Separator",
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

        for (int i = 0; i < fromRowCount; i++) {
            for (int j = 0; j < columnCount; j++) {
                int rowYDistance = this.firstRowYDistance + (i * this.rowHeight);

                if (!this.createLabel(
                    this.getCellObjectName(i, j),
                    this.getColumnLeftOffset(j, timeFrameCount),
                    rowYDistance,
                    this.bodyFontSize,
                    this.normalColor,
                    "-"
                )) {
                    this.destroyObjects();

                    return false;
                }
            }
        }

        this.createdRowCount = fromRowCount;
        this.createdCurrentTimeFrame = fromCurrentTimeFrame;
        this.created = true;

        return true;
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
        string fromObjectName,
        int fromXDistance,
        int fromYDistance,
        int fromWidth,
        int fromHeight,
        color fromBackgroundColor,
        color fromBorderColor,
        int fromZOrder
    ) {
        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XDISTANCE, fromXDistance);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YDISTANCE, fromYDistance);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BGCOLOR, fromBackgroundColor);
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
     * @param fromFontSize フォントサイズ。
     * @param fromColor 文字色。
     * @param fromText 表示文字列。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        string fromObjectName,
        int fromLeftOffset,
        int fromTopOffset,
        int fromFontSize,
        color fromColor,
        string fromText
    ) {
        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        int labelXDistance = this.xDistance + fromLeftOffset;

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XDISTANCE, labelXDistance);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YDISTANCE, this.yDistance + fromTopOffset);
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
     * READY優先の表示順と行状態を生成する。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDisplayOrder 表示順の格納先。
     * @param fromStatusRanks 行状態の格納先。
     * @return READYの件数。
     */
    int buildDisplayOrder(
        ElliotAllList *fromElliotAllList,
        int &fromDisplayOrder[],
        int &fromStatusRanks[]
    ) {
        int total = fromElliotAllList.elliotAllList.Total();
        int readyCount = 0;

        ArrayResize(fromDisplayOrder, total);
        ArrayResize(fromStatusRanks, total);

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(i);

            fromDisplayOrder[i] = i;
            fromStatusRanks[i] = this.getStatusRank(elliotAll);

            if (fromStatusRanks[i] == drawElliotAllListStatusReady) {
                readyCount++;
            }
        }

        for (int i = 1; i < total; i++) {
            int currentIndex = fromDisplayOrder[i];
            int j = i - 1;

            while (j >= 0
                    && fromStatusRanks[fromDisplayOrder[j]] > fromStatusRanks[currentIndex]) {
                fromDisplayOrder[j + 1] = fromDisplayOrder[j];
                j--;
            }

            fromDisplayOrder[j + 1] = currentIndex;
        }

        return readyCount;
    }

    /**
     * 1シンボル分の行を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromElliotAll 分析結果。
     * @param fromStatusRank 行状態。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     */
    void drawRow(
        int fromRowIndex,
        ElliotAll *fromElliotAll,
        int fromStatusRank,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[]
    ) {
        int timeFrameCount = ArraySize(fromDisplayTimeFrames);
        int alignColumnIndex = drawElliotAllListColumnTimeFrameStart + timeFrameCount;
        int emaColumnIndex = alignColumnIndex + 1;
        int smoColumnIndex = emaColumnIndex + 1;
        int statusColumnIndex = smoColumnIndex + 1;

        string symbolText = "UNKNOWN";

        if (fromElliotAll != NULL) {
            symbolText = fromElliotAll.marketContext.symbolName;
        }

        color symbolColor = this.getStatusColor(fromElliotAll, fromStatusRank);

        this.setCell(
            fromRowIndex,
            drawElliotAllListColumnSymbol,
            symbolText,
            symbolColor
        );

        for (int i = 0; i < timeFrameCount; i++) {
            Elliot *elliot = NULL;

            if (fromElliotAll != NULL) {
                elliot = fromElliotAll.getElliot(fromDisplayTimeFrames[i]);
            }

            string buySellText = this.getBuySellText(elliot);

            this.setCell(
                fromRowIndex,
                drawElliotAllListColumnTimeFrameStart + i,
                buySellText,
                this.getDirectionColor(buySellText)
            );
        }

        if (fromStatusRank == drawElliotAllListStatusError) {
            this.setCell(fromRowIndex, alignColumnIndex, "-", this.mutedColor);
            this.setCell(fromRowIndex, emaColumnIndex, "-", this.mutedColor);
            this.setCell(fromRowIndex, smoColumnIndex, "-", this.mutedColor);
            this.setCell(
                fromRowIndex,
                statusColumnIndex,
                "ERROR",
                this.errorColor
            );

            return;
        }

        string alignText = fromElliotAll.trendAlignDecision.getD1H4H1M15Text();
        string emaText = this.getEmaText(fromElliotAll);
        string smoText = fromElliotAll.higherStochasticMainOrderDecision.getBuySellText();
        string statusText = this.getStatusText(fromStatusRank);

        this.setCell(fromRowIndex, alignColumnIndex, alignText, this.getDirectionColor(alignText));
        this.setCell(fromRowIndex, emaColumnIndex, emaText, this.getEmaColor(emaText));
        this.setCell(fromRowIndex, smoColumnIndex, smoText, this.getDirectionColor(smoText));
        this.setCell(
            fromRowIndex,
            statusColumnIndex,
            statusText,
            this.getStatusColor(fromElliotAll, fromStatusRank)
        );
    }

    /**
     * タイトルを更新する。
     *
     * @param fromTimeFrameText 現在時間足。
     * @param fromReadyCount READY件数。
     * @param fromTotal 全件数。
     */
    void updateTitle(string fromTimeFrameText, int fromReadyCount, int fromTotal) {
        string titleText = StringFormat(
            "ZigZag Elliot List  %s  READY %d/%d  %s",
            fromTimeFrameText,
            fromReadyCount,
            fromTotal,
            TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)
        );

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            titleText
        );
    }

    /**
     * セルの文字列と色を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setCell(
        int fromRowIndex,
        int fromColumnIndex,
        string fromText,
        color fromColor
    ) {
        string objectName = this.getCellObjectName(fromRowIndex, fromColumnIndex);

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * 分析結果の表示状態を取得する。
     *
     * @param fromElliotAll 分析結果。
     * @return 表示状態。
     */
    int getStatusRank(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return drawElliotAllListStatusError;
        }

        if (!fromElliotAll.isAnalysisSucceeded || fromElliotAll.elliotCurrent == NULL) {
            return drawElliotAllListStatusError;
        }

        ExpertAdvisorEma200 expertAdvisorEma200(fromElliotAll.elliotCurrent.isBuy);

        if (expertAdvisorEma200.isEma200Candidate(fromElliotAll)) {
            return drawElliotAllListStatusReady;
        }

        if (fromElliotAll.isBuySell(PERIOD_H4)) {
            return drawElliotAllListStatusWatch;
        }

        return drawElliotAllListStatusNone;
    }

    /**
     * 行状態の表示文字列を取得する。
     *
     * @param fromStatusRank 行状態。
     * @return 表示文字列。
     */
    string getStatusText(int fromStatusRank) {
        if (fromStatusRank == drawElliotAllListStatusReady) {
            return "READY";
        }

        if (fromStatusRank == drawElliotAllListStatusWatch) {
            return "WATCH";
        }

        if (fromStatusRank == drawElliotAllListStatusError) {
            return "ERROR";
        }

        return "NONE";
    }

    /**
     * 行状態の色を取得する。
     *
     * @param fromElliotAll 分析結果。
     * @param fromStatusRank 行状態。
     * @return 表示色。
     */
    color getStatusColor(ElliotAll *fromElliotAll, int fromStatusRank) {
        if (fromStatusRank == drawElliotAllListStatusError) {
            return this.errorColor;
        }

        if (fromStatusRank == drawElliotAllListStatusWatch) {
            return this.watchColor;
        }

        if (fromStatusRank == drawElliotAllListStatusReady
                && fromElliotAll != NULL
                && fromElliotAll.elliotCurrent != NULL) {
            if (fromElliotAll.elliotCurrent.isBuy) {
                return this.buyColor;
            }

            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * Elliotの売買方向文字列を取得する。
     *
     * @param fromElliot 対象Elliot。
     * @return BUY / SELL / -。
     */
    string getBuySellText(Elliot *fromElliot) {
        if (fromElliot == NULL || fromElliot.buySellLabel == "") {
            return "-";
        }

        return fromElliot.buySellLabel;
    }

    /**
     * 現在足と直上位足のEMA200方向を取得する。
     *
     * @param fromElliotAll 分析結果。
     * @return 現在足/直上位足のEMA200方向。
     */
    string getEmaText(ElliotAll *fromElliotAll) {
        Elliot *elliotCurrent = fromElliotAll.elliotCurrent;
        Elliot *elliotHigher1 = fromElliotAll.getElliot(
            fromElliotAll.marketContext.timeFrame,
            1
        );

        string currentText = "-";
        string higherText = "-";

        if (elliotCurrent != NULL) {
            currentText = elliotCurrent.oscillator.ema200.getBuySellLabel();
        }

        if (elliotHigher1 != NULL) {
            higherText = elliotHigher1.oscillator.ema200.getBuySellLabel();
        }

        if (currentText == "NONE") {
            currentText = "-";
        }

        if (higherText == "NONE") {
            higherText = "-";
        }

        return currentText + "/" + higherText;
    }

    /**
     * 売買方向文字列の色を取得する。
     *
     * @param fromText 売買方向文字列。
     * @return 表示色。
     */
    color getDirectionColor(string fromText) {
        if (fromText == "BUY") {
            return this.buyColor;
        }

        if (fromText == "SELL") {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * EMA200方向文字列の色を取得する。
     *
     * @param fromText EMA200方向文字列。
     * @return 表示色。
     */
    color getEmaColor(string fromText) {
        if (fromText == "BUY/BUY") {
            return this.buyColor;
        }

        if (fromText == "SELL/SELL") {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * 基準時間足までの表示対象時間足一覧を生成する。
     *
     * @param fromCurrentTimeFrame 基準時間足。
     * @param fromDisplayTimeFrames 表示対象時間足一覧の格納先。
     * @return 対応時間足の場合true。
     */
    bool buildDisplayTimeFrames(
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        ENUM_TIMEFRAMES &fromDisplayTimeFrames[]
    ) {
        TimeFrameInfoAll timeFrameInfoAll;
        int d1Index = -1;
        int currentIndex = -1;
        int total = timeFrameInfoAll.getCount();

        for (int i = 0; i < total; i++) {
            TimeFrameInfo *timeFrameInfo = timeFrameInfoAll.timeFrameInfoList.At(i);

            if (timeFrameInfo == NULL) {
                continue;
            }

            if (timeFrameInfo.timeFrame == PERIOD_D1) {
                d1Index = i;
            }

            if (timeFrameInfo.timeFrame == fromCurrentTimeFrame) {
                currentIndex = i;
            }
        }

        if (d1Index < 0 || currentIndex < 0 || d1Index < currentIndex) {
            ArrayResize(fromDisplayTimeFrames, 0);

            return false;
        }

        int displayCount = d1Index - currentIndex + 1;
        int displayIndex = 0;

        ArrayResize(fromDisplayTimeFrames, displayCount);

        for (int i = d1Index; i >= currentIndex; i--) {
            TimeFrameInfo *timeFrameInfo = timeFrameInfoAll.timeFrameInfoList.At(i);

            if (timeFrameInfo == NULL) {
                ArrayResize(fromDisplayTimeFrames, 0);

                return false;
            }

            fromDisplayTimeFrames[displayIndex] = timeFrameInfo.timeFrame;
            displayIndex++;
        }

        return true;
    }

    /**
     * 全表示列数を取得する。
     *
     * @param fromTimeFrameCount 時間足列数。
     * @return 全表示列数。
     */
    int getColumnCount(int fromTimeFrameCount) {
        return fromTimeFrameCount + 5;
    }

    /**
     * 時間足列数に応じたパネル横幅を取得する。
     *
     * @param fromTimeFrameCount 時間足列数。
     * @return パネル横幅。
     */
    int calculatePanelWidth(int fromTimeFrameCount) {
        return 400 + (fromTimeFrameCount * 50);
    }

    /**
     * 列の左端位置を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @param fromTimeFrameCount 時間足列数。
     * @return パネル左端からの位置。
     */
    int getColumnLeftOffset(int fromColumnIndex, int fromTimeFrameCount) {
        if (fromColumnIndex == drawElliotAllListColumnSymbol) {
            return 14;
        }

        if (drawElliotAllListColumnTimeFrameStart <= fromColumnIndex
                && fromColumnIndex <= fromTimeFrameCount) {
            return 106 + ((fromColumnIndex - drawElliotAllListColumnTimeFrameStart) * 50);
        }

        int alignColumnIndex = drawElliotAllListColumnTimeFrameStart + fromTimeFrameCount;
        int alignLeftOffset = 116 + (fromTimeFrameCount * 50);

        if (fromColumnIndex == alignColumnIndex) {
            return alignLeftOffset;
        }

        if (fromColumnIndex == alignColumnIndex + 1) {
            return alignLeftOffset + 70;
        }

        if (fromColumnIndex == alignColumnIndex + 2) {
            return alignLeftOffset + 164;
        }

        return alignLeftOffset + 218;
    }

    /**
     * 列ヘッダー文字列を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @return 列ヘッダー文字列。
     */
    string getHeaderText(
        int fromColumnIndex,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[]
    ) {
        if (fromColumnIndex == drawElliotAllListColumnSymbol) {
            return "SYMBOL";
        }

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);
        int timeFrameIndex = fromColumnIndex - drawElliotAllListColumnTimeFrameStart;

        if (0 <= timeFrameIndex && timeFrameIndex < timeFrameCount) {
            return TimeUtil::convertTimeFrameToString(fromDisplayTimeFrames[timeFrameIndex]);
        }

        int alignColumnIndex = drawElliotAllListColumnTimeFrameStart + timeFrameCount;

        if (fromColumnIndex == alignColumnIndex) {
            return "W M15+";
        }

        if (fromColumnIndex == alignColumnIndex + 1) {
            return "EMA C/H";
        }

        if (fromColumnIndex == alignColumnIndex + 2) {
            return "SMO";
        }

        return "STATUS";
    }

    /**
     * 列ヘッダーのオブジェクト名を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getHeaderObjectName(int fromColumnIndex) {
        return this.objectPrefix + "Header_" + IntegerToString(fromColumnIndex);
    }

    /**
     * セルのオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getCellObjectName(int fromRowIndex, int fromColumnIndex) {
        return this.objectPrefix
            + "Row_" + IntegerToString(fromRowIndex)
            + "_Column_" + IntegerToString(fromColumnIndex);
    }

    /**
     * 一覧パネル専用オブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.createdRowCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;
    }
};

#endif
