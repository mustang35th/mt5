//+------------------------------------------------------------------+
//|                                  DrawAlignedElliotAllList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DRAW_DRAW_ALIGNED_ELLIOT_ALL_LIST_MQH
#define MSTNG_DRAW_DRAW_ALIGNED_ELLIOT_ALL_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

enum DrawAlignedElliotAllListColumn {
    drawAlignedElliotAllListColumnSymbol = 0,
    drawAlignedElliotAllListColumnTimeFrameStart = 1
};

/**
 * D1から表示時間足まで売買方向が一致した複数シンボルを描画するクラス。
 *
 * BUYとSELLを別セクションに分け、MN1から各時間足の最新Elliott波動を
 * 固定一覧パネルへ表示する。分析結果と判定クラスへの参照は保持しない。
 */
class DrawAlignedElliotAllList {
public:
    /**
     * 描画対象チャートとインスタンス番号を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレントチャート。
     * @param fromInstanceIndex 同一チャート内でオブジェクト名を分離する番号。
     */
    DrawAlignedElliotAllList(long fromChartId = 0, int fromInstanceIndex = 0) {
        this.chartId = fromChartId;

        if (this.chartId == 0) {
            this.chartId = ChartID();
        }

        ulong instanceToken = GetMicrosecondCount();

        this.objectPrefix = Constant::PREFIX_FIXED
            + "ZzElList_"
            + IntegerToString(fromInstanceIndex)
            + "_" + StringFormat("%I64u", instanceToken) + "_";

        this.created = false;
        this.createdRowCount = 0;
        this.createdBuyCount = 0;
        this.createdSellCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;

        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = 12;
        this.yDistance = 12;
        this.panelWidth = 800;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 39;
        this.separatorYDistance = 58;
        this.firstGroupYDistance = 66;
        this.groupHeight = 20;
        this.rowHeight = 20;
        this.sectionGap = 4;
        this.bottomPadding = 10;
        this.timeFrameColumnWidth = 108;

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
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawAlignedElliotAllList() {
        this.destroyObjects();
    }

    /**
     * 売買方向が完全一致した複数シンボルを一覧表示する。
     *
     * @param fromElliotAllList 描画対象の分析結果一覧。
     * @param fromDecision 完全一致および分析準備状態の判定クラス。
     * @return 描画に成功した場合true。
     */
    bool draw(
        ElliotAllList *fromElliotAllList,
        ElliotDirectionAlignmentDecision *fromDecision
    ) {
        if (fromElliotAllList == NULL || fromDecision == NULL) {
            return false;
        }

        ENUM_TIMEFRAMES currentTimeFrame = fromElliotAllList.marketContext.timeFrame;
        ENUM_TIMEFRAMES displayTimeFrames[];

        if (!ElliotTimeFrameRange::build(
            PERIOD_MN1,
            currentTimeFrame,
            displayTimeFrames
        )) {
            return false;
        }

        int buyCount = 0;
        int sellCount = 0;
        int errorCount = 0;

        this.countRows(
            fromElliotAllList,
            fromDecision,
            currentTimeFrame,
            buyCount,
            sellCount,
            errorCount
        );

        int rowCount = buyCount + sellCount;

        if (!this.created
                || this.createdRowCount != rowCount
                || this.createdBuyCount != buyCount
                || this.createdSellCount != sellCount
                || this.createdCurrentTimeFrame != currentTimeFrame) {
            if (!this.create(
                buyCount,
                sellCount,
                currentTimeFrame,
                displayTimeFrames
            )) {
                return false;
            }
        }

        int targetCount = fromElliotAllList.targetCount;
        string currentTimeFrameText = TimeUtil::convertTimeFrameToString(currentTimeFrame);

        if (currentTimeFrameText == "") {
            currentTimeFrameText = fromElliotAllList.marketContext.timeFrameLabel;
        }

        if (currentTimeFrameText == "") {
            currentTimeFrameText = "CUR";
        }

        this.updateTitle(
            currentTimeFrameText,
            buyCount,
            sellCount,
            targetCount,
            errorCount
        );
        this.updateGroupHeaders(buyCount, sellCount);
        this.drawRows(
            fromElliotAllList,
            fromDecision,
            currentTimeFrame,
            displayTimeFrames,
            trendAlignBuy,
            0
        );
        this.drawRows(
            fromElliotAllList,
            fromDecision,
            currentTimeFrame,
            displayTimeFrames,
            trendAlignSell,
            buyCount
        );

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

    /** 生成済みのデータ行数。 */
    int createdRowCount;

    /** 生成済みのBUY行数。 */
    int createdBuyCount;

    /** 生成済みのSELL行数。 */
    int createdSellCount;

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

    /** タイトル背景の高さ。 */
    int headerHeight;

    /** 列ヘッダーのY位置。 */
    int columnHeaderYDistance;

    /** 区切り線のY位置。 */
    int separatorYDistance;

    /** BUYグループ見出しのY位置。 */
    int firstGroupYDistance;

    /** グループ見出しの高さ。 */
    int groupHeight;

    /** データ行の高さ。 */
    int rowHeight;

    /** BUYとSELLセクション間の余白。 */
    int sectionGap;

    /** パネル下余白。 */
    int bottomPadding;

    /** 時間足列の横幅。 */
    int timeFrameColumnWidth;

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

    /** 取得不能時の文字色。 */
    color mutedColor;

    /** BUY文字色。 */
    color buyColor;

    /** SELL文字色。 */
    color sellColor;

    /**
     * 表示対象件数と分析エラー件数を集計する。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDecision 完全一致判定クラス。
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromBuyCount BUY件数の格納先。
     * @param fromSellCount SELL件数の格納先。
     * @param fromErrorCount エラー件数の格納先。
     */
    void countRows(
        ElliotAllList *fromElliotAllList,
        ElliotDirectionAlignmentDecision *fromDecision,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        int &fromBuyCount,
        int &fromSellCount,
        int &fromErrorCount
    ) {
        fromBuyCount = 0;
        fromSellCount = 0;
        fromErrorCount = 0;

        int total = fromElliotAllList.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(i);

            if (!fromDecision.isReady(elliotAll, fromCurrentTimeFrame)) {
                fromErrorCount++;
                continue;
            }

            TrendAlignType alignType = fromDecision.getAlignType(
                elliotAll,
                fromCurrentTimeFrame
            );

            if (alignType == trendAlignBuy) {
                fromBuyCount++;
                continue;
            }

            if (alignType == trendAlignSell) {
                fromSellCount++;
            }
        }

        if (fromElliotAllList.targetCount > total) {
            fromErrorCount += fromElliotAllList.targetCount - total;
        }
    }

    /**
     * 指定件数の一覧パネルを生成する。
     *
     * @param fromBuyCount BUY行数。
     * @param fromSellCount SELL行数。
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @return 生成に成功した場合true。
     */
    bool create(
        int fromBuyCount,
        int fromSellCount,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[]
    ) {
        this.destroyObjects();

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);
        int columnCount = timeFrameCount + 1;
        int rowCount = fromBuyCount + fromSellCount;

        this.panelWidth = this.calculatePanelWidth(timeFrameCount);

        int sellGroupYDistance = this.getSellGroupYDistance(fromBuyCount);
        int panelHeight = sellGroupYDistance
            + this.groupHeight
            + (fromSellCount * this.rowHeight)
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
            "ZigZag Elliott List GMO"
        )) {
            this.destroyObjects();
            return false;
        }

        for (int i = 0; i < columnCount; i++) {
            if (!this.createLabel(
                this.getHeaderObjectName(i),
                this.getColumnLeftOffset(i),
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

        if (!this.createLabel(
            this.objectPrefix + "GroupBuy",
            14,
            this.firstGroupYDistance,
            this.bodyFontSize,
            this.buyColor,
            "BUY"
        )) {
            this.destroyObjects();
            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "GroupSell",
            14,
            sellGroupYDistance,
            this.bodyFontSize,
            this.sellColor,
            "SELL"
        )) {
            this.destroyObjects();
            return false;
        }

        for (int i = 0; i < rowCount; i++) {
            int rowYDistance = this.getRowYDistance(i, fromBuyCount);

            for (int j = 0; j < columnCount; j++) {
                if (!this.createLabel(
                    this.getCellObjectName(i, j),
                    this.getColumnLeftOffset(j),
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

        this.createdRowCount = rowCount;
        this.createdBuyCount = fromBuyCount;
        this.createdSellCount = fromSellCount;
        this.createdCurrentTimeFrame = fromCurrentTimeFrame;
        this.created = true;

        return true;
    }

    /**
     * 指定方向の一致結果を入力順で描画する。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDecision 完全一致判定クラス。
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @param fromAlignType 描画する方向。
     * @param fromStartRowIndex 描画開始行番号。
     */
    void drawRows(
        ElliotAllList *fromElliotAllList,
        ElliotDirectionAlignmentDecision *fromDecision,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[],
        TrendAlignType fromAlignType,
        int fromStartRowIndex
    ) {
        int total = fromElliotAllList.elliotAllList.Total();
        int rowIndex = fromStartRowIndex;

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(i);

            if (!fromDecision.isReady(elliotAll, fromCurrentTimeFrame)) {
                continue;
            }

            TrendAlignType alignType = fromDecision.getAlignType(
                elliotAll,
                fromCurrentTimeFrame
            );

            if (alignType != fromAlignType) {
                continue;
            }

            this.drawRow(
                rowIndex,
                elliotAll,
                fromDisplayTimeFrames,
                fromAlignType
            );
            rowIndex++;
        }
    }

    /**
     * 1シンボル分の行を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromElliotAll 分析結果。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @param fromAlignType 一致方向。
     */
    void drawRow(
        int fromRowIndex,
        ElliotAll *fromElliotAll,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[],
        TrendAlignType fromAlignType
    ) {
        if (fromElliotAll == NULL) {
            return;
        }

        color directionColor = this.getAlignColor(fromAlignType);

        this.setCell(
            fromRowIndex,
            drawAlignedElliotAllListColumnSymbol,
            fromElliotAll.marketContext.symbolName,
            directionColor
        );

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);

        for (int i = 0; i < timeFrameCount; i++) {
            Elliot *elliot = fromElliotAll.getElliot(fromDisplayTimeFrames[i]);

            this.setCell(
                fromRowIndex,
                drawAlignedElliotAllListColumnTimeFrameStart + i,
                this.getWaveText(elliot),
                this.getWaveColor(elliot)
            );
        }
    }

    /**
     * タイトルを更新する。
     *
     * @param fromTimeFrameText 表示時間足。
     * @param fromBuyCount BUY件数。
     * @param fromSellCount SELL件数。
     * @param fromTargetCount 対象通貨件数。
     * @param fromErrorCount 分析エラー件数。
     */
    void updateTitle(
        string fromTimeFrameText,
        int fromBuyCount,
        int fromSellCount,
        int fromTargetCount,
        int fromErrorCount
    ) {
        datetime serverTime = TimeCurrent();
        datetime japanTime = TimeJapanUtil::getJapanTime(serverTime);

        string titleText = StringFormat(
            "ZigZag Elliott List GMO %s ANALYZE MN1 / ALIGN D1 BUY %d / SELL %d / TARGET %d / ERROR %d JST %s SV %s",
            fromTimeFrameText,
            fromBuyCount,
            fromSellCount,
            fromTargetCount,
            fromErrorCount,
            this.formatTitleTime(japanTime),
            this.formatTitleTime(serverTime)
        );

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            titleText
        );
    }

    /**
     * BUYとSELLのグループ見出しを更新する。
     *
     * @param fromBuyCount BUY件数。
     * @param fromSellCount SELL件数。
     */
    void updateGroupHeaders(int fromBuyCount, int fromSellCount) {
        ObjectSetString(
            this.chartId,
            this.objectPrefix + "GroupBuy",
            OBJPROP_TEXT,
            StringFormat("BUY  %d", fromBuyCount)
        );
        ObjectSetString(
            this.chartId,
            this.objectPrefix + "GroupSell",
            OBJPROP_TEXT,
            StringFormat("SELL  %d", fromSellCount)
        );
    }

    /**
     * 最新Waveの表示文字列を取得する。
     *
     * @param fromElliot 対象時間足のElliot。
     * @return 未確定表示、方向、Elliottラベルを連結した文字列。
     */
    string getWaveText(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "-";
        }

        Wave *latestWave = fromElliot.getLatestWave();

        if (latestWave == NULL || latestWave.trendLabel == "") {
            return "-";
        }

        string elliotLabel = fromElliot.getLatestPointElliotLabel();

        if (elliotLabel == "") {
            return "-";
        }

        string text = "";

        if (!latestWave.isConfirmed) {
            text = "【未】";
        }

        text += latestWave.trendLabel;
        text += elliotLabel;

        return text;
    }

    /**
     * Elliotの売買方向色を取得する。
     *
     * @param fromElliot 対象時間足のElliot。
     * @return BUYはBUY色、SELLはSELL色、取得不能時は抑制色。
     */
    color getWaveColor(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return this.mutedColor;
        }

        if (fromElliot.isBuy) {
            return this.buyColor;
        }

        return this.sellColor;
    }

    /**
     * 一致方向の表示色を取得する。
     *
     * @param fromAlignType 一致方向。
     * @return BUY色、SELL色または抑制色。
     */
    color getAlignColor(TrendAlignType fromAlignType) {
        if (fromAlignType == trendAlignBuy) {
            return this.buyColor;
        }

        if (fromAlignType == trendAlignSell) {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * タイトル表示用の日時文字列へ変換する。
     *
     * @param fromDatetime 変換対象日時。
     * @return 月日と時分を表す文字列。
     */
    string formatTitleTime(datetime fromDatetime) {
        MqlDateTime dateTime;
        TimeToStruct(fromDatetime, dateTime);

        return StringFormat(
            "%02d/%02d %02d:%02d",
            dateTime.mon,
            dateTime.day,
            dateTime.hour,
            dateTime.min
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

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
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
     * 時間足列数に応じたパネル横幅を取得する。
     *
     * @param fromTimeFrameCount 時間足列数。
     * @return パネル横幅。
     */
    int calculatePanelWidth(int fromTimeFrameCount) {
        int width = 170 + (fromTimeFrameCount * this.timeFrameColumnWidth);

        if (width < 800) {
            width = 800;
        }

        return width;
    }

    /**
     * 列の左端位置を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return パネル左端からの位置。
     */
    int getColumnLeftOffset(int fromColumnIndex) {
        if (fromColumnIndex == drawAlignedElliotAllListColumnSymbol) {
            return 14;
        }

        return 106
            + ((fromColumnIndex - drawAlignedElliotAllListColumnTimeFrameStart)
                * this.timeFrameColumnWidth);
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
        if (fromColumnIndex == drawAlignedElliotAllListColumnSymbol) {
            return "SYMBOL";
        }

        int timeFrameIndex = fromColumnIndex
            - drawAlignedElliotAllListColumnTimeFrameStart;

        if (timeFrameIndex < 0 || ArraySize(fromDisplayTimeFrames) <= timeFrameIndex) {
            return "-";
        }

        return TimeUtil::convertTimeFrameToString(fromDisplayTimeFrames[timeFrameIndex]);
    }

    /**
     * SELLグループ見出しのY位置を取得する。
     *
     * @param fromBuyCount BUY行数。
     * @return パネル上端からの位置。
     */
    int getSellGroupYDistance(int fromBuyCount) {
        return this.firstGroupYDistance
            + this.groupHeight
            + (fromBuyCount * this.rowHeight)
            + this.sectionGap;
    }

    /**
     * 指定表示行のY位置を取得する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromBuyCount BUY行数。
     * @return パネル上端からの位置。
     */
    int getRowYDistance(int fromRowIndex, int fromBuyCount) {
        if (fromRowIndex < fromBuyCount) {
            return this.firstGroupYDistance
                + this.groupHeight
                + (fromRowIndex * this.rowHeight);
        }

        int sellRowIndex = fromRowIndex - fromBuyCount;

        return this.getSellGroupYDistance(fromBuyCount)
            + this.groupHeight
            + (sellRowIndex * this.rowHeight);
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
        this.createdBuyCount = 0;
        this.createdSellCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;
    }
};

#endif
