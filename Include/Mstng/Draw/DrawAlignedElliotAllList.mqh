//+------------------------------------------------------------------+
//|                                     DrawAlignedElliotAllList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DRAW_DRAW_ALIGNED_ELLIOT_ALL_LIST_MQH
#define MSTNG_DRAW_DRAW_ALIGNED_ELLIOT_ALL_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Elliot\D1ElliotEmaSortDecision.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>
#include <Mstng\Elliot\ElliotListSortType.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Elliot\M15ElliotEmaSortDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3EntryPriorityDecision.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

enum DrawAlignedElliotAllListColumn {
    drawAlignedElliotAllListColumnSymbol = 0,
    drawAlignedElliotAllListColumnEntryPriority = 1,
    drawAlignedElliotAllListColumnTimeFrameStart = 2
};

/**
 * 指定開始足から表示時間足まで売買方向が一致した複数シンボルを描画するクラス。
 *
 * BUYとSELLを別セクションに分け、MN1から各時間足の最新Elliott波動、
 * Fibonacci比率およびEMA200方向を2段の固定一覧パネルへ表示する。
 * 分析結果と判定クラスへの参照は保持しない。
 */
class DrawAlignedElliotAllList {
public:
    /**
     * 描画対象チャートとインスタンス番号を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレントチャート。
     * @param fromInstanceIndex 同一チャート内でオブジェクト名を分離する番号。
     * @param fromSortType 一覧の並び替え基準。
     */
    DrawAlignedElliotAllList(
        long fromChartId = 0,
        int fromInstanceIndex = 0,
        ElliotListSortType fromSortType = ELLIOT_LIST_SORT_ENTRY_PRIORITY
    ) {
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
        this.createdH1RunnerUpCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;
        this.sortType = fromSortType;
        this.gmoSymbolNameInfoAll.setGmo();

        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = 12;
        this.yDistance = 12;
        this.panelWidth = 800;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 39;
        this.separatorYDistance = 58;
        this.firstGroupYDistance = 66;
        this.groupHeight = 20;
        this.rowHeight = 36;
        this.emaRowOffset = 16;
        this.sectionGap = 4;
        this.bottomPadding = 10;
        this.tableLeftOffset = 12;
        this.cellLeftPadding = 12;
        this.columnWidth = 108;
        this.fibonacciRightPadding = 18;
        this.entryLegendGap = 8;
        this.entryLegendWidth = 270;
        this.entryLegendHeight = 130;
        this.entryLegendRowHeight = 18;
        this.h1RunnerUpGroupHeight = 18;
        this.h1RunnerUpSectionGap = 4;

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
        this.entryReadyColor = clrLime;
        this.entryNearColor = clrGold;
        this.entrySetupColor = clrOrange;
        this.entryErrorColor = clrRed;
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
        bool h1RunnerUpPanelEnabled = currentTimeFrame == PERIOD_H1
            && fromDecision.getAlignmentRule()
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200;
        int h1RunnerUpIndexes[];
        H1ElliotAlignmentRunnerUpResult h1RunnerUpResults[];
        int h1RunnerUpBuyCount = 0;
        int h1RunnerUpSellCount = 0;
        int h1RunnerUpCount = 0;

        if (h1RunnerUpPanelEnabled) {
            h1RunnerUpCount = this.buildH1RunnerUpOrder(
                fromElliotAllList,
                fromDecision,
                currentTimeFrame,
                h1RunnerUpIndexes,
                h1RunnerUpResults,
                h1RunnerUpBuyCount,
                h1RunnerUpSellCount
            );
        }

        if (!this.created
                || this.createdRowCount != rowCount
                || this.createdBuyCount != buyCount
                || this.createdSellCount != sellCount
                || this.createdH1RunnerUpCount != h1RunnerUpCount
                || this.createdCurrentTimeFrame != currentTimeFrame) {
            if (!this.create(
                buyCount,
                sellCount,
                currentTimeFrame,
                displayTimeFrames,
                h1RunnerUpPanelEnabled,
                h1RunnerUpCount
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

        ENUM_TIMEFRAMES alignmentStartTimeFrame =
            fromDecision.getAlignmentStartTimeFrame();
        string alignmentStartTimeFrameText =
            TimeUtil::convertTimeFrameToString(alignmentStartTimeFrame);

        if (currentTimeFrame == PERIOD_H1
                && fromDecision.getAlignmentRule()
                    == ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200) {
            alignmentStartTimeFrameText = "W1-H1&(MN1|W1EMA)";
        } else if (currentTimeFrame == PERIOD_D1
                && fromDecision.getAlignmentRule()
                    == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200) {
            alignmentStartTimeFrameText = "W1&(MN1|W1EMA)";
        } else if (currentTimeFrame == PERIOD_D1
                && alignmentStartTimeFrame == PERIOD_MN1) {
            alignmentStartTimeFrameText = "MN1+W1";
        } else if (currentTimeFrame == PERIOD_H1
                && alignmentStartTimeFrame == PERIOD_D1) {
            alignmentStartTimeFrameText = "D1-H1";
        } else if (currentTimeFrame == PERIOD_H1
                && alignmentStartTimeFrame == PERIOD_MN1) {
            alignmentStartTimeFrameText = "MN1-H1";
        }

        if (alignmentStartTimeFrameText == "") {
            alignmentStartTimeFrameText = "CUR";
        }

        this.updateTitle(
            currentTimeFrameText,
            alignmentStartTimeFrameText,
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

        if (h1RunnerUpPanelEnabled) {
            this.drawH1RunnerUpRows(
                fromElliotAllList,
                h1RunnerUpIndexes,
                h1RunnerUpResults,
                h1RunnerUpBuyCount,
                h1RunnerUpSellCount
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

    /** 生成済みのデータ行数。 */
    int createdRowCount;

    /** 生成済みのBUY行数。 */
    int createdBuyCount;

    /** 生成済みのSELL行数。 */
    int createdSellCount;

    /** 生成済みのH1次点候補行数。 */
    int createdH1RunnerUpCount;

    /** 生成済み列の基準時間足。 */
    ENUM_TIMEFRAMES createdCurrentTimeFrame;

    /** 一覧の並び替え基準。 */
    ElliotListSortType sortType;

    /** GMO取引対象の判別用シンボル一覧。 */
    SymbolNameInfoAll gmoSymbolNameInfoAll;

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

    /** EMA200表示段の上段からの位置。 */
    int emaRowOffset;

    /** BUYとSELLセクション間の余白。 */
    int sectionGap;

    /** パネル下余白。 */
    int bottomPadding;

    /** 表のパネル左端からの位置。 */
    int tableLeftOffset;

    /** セル左端から文字列までの余白。 */
    int cellLeftPadding;

    /** 一覧の共通列幅。 */
    int columnWidth;

    /** Fibonacci表示の時間足列右端からの余白。 */
    int fibonacciRightPadding;

    /** 一覧とENTRY凡例の間隔。 */
    int entryLegendGap;

    /** ENTRY凡例の横幅。 */
    int entryLegendWidth;

    /** ENTRY凡例の高さ。 */
    int entryLegendHeight;

    /** ENTRY凡例1行の高さ。 */
    int entryLegendRowHeight;

    /** H1次点候補のグループ見出し高さ。 */
    int h1RunnerUpGroupHeight;

    /** H1次点候補のBUY・SELL間余白。 */
    int h1RunnerUpSectionGap;

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

    /** エントリーREADY文字色。 */
    color entryReadyColor;

    /** エントリーNEAR文字色。 */
    color entryNearColor;

    /** エントリーSETUP文字色。 */
    color entrySetupColor;

    /** エントリーERROR文字色。 */
    color entryErrorColor;

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
     * @param fromH1RunnerUpPanelEnabled H1次点候補を表示する場合true。
     * @param fromH1RunnerUpCount H1次点候補行数。
     * @return 生成に成功した場合true。
     */
    bool create(
        int fromBuyCount,
        int fromSellCount,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[],
        bool fromH1RunnerUpPanelEnabled,
        int fromH1RunnerUpCount
    ) {
        this.destroyObjects();

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);
        int columnCount = timeFrameCount
            + drawAlignedElliotAllListColumnTimeFrameStart;
        int rowCount = fromBuyCount + fromSellCount;

        this.panelWidth = this.calculatePanelWidth(
            fromCurrentTimeFrame,
            timeFrameCount
        );

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
            "ZigZag Elliott List ALL"
        )) {
            this.destroyObjects();
            return false;
        }

        if (fromH1RunnerUpPanelEnabled) {
            if (!this.createH1RunnerUpPanel(fromH1RunnerUpCount)) {
                this.destroyObjects();
                return false;
            }
        } else {
            if (!this.createEntryLegend()) {
                this.destroyObjects();
                return false;
            }
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
            this.xDistance + this.tableLeftOffset,
            this.yDistance + this.separatorYDistance,
            this.panelWidth - (this.tableLeftOffset * 2),
            1,
            this.borderColor,
            this.borderColor,
            1
        )) {
            this.destroyObjects();
            return false;
        }

        int verticalStartOffset = this.columnHeaderYDistance - 4;
        int verticalHeight = panelHeight
            - verticalStartOffset
            - this.bottomPadding;

        for (int i = 1; i < columnCount; i++) {
            int verticalXDistance = this.xDistance
                + this.getColumnLeftOffset(i)
                - this.cellLeftPadding;

            if (!this.createRectangle(
                this.objectPrefix + "ColumnSeparator_" + IntegerToString(i),
                verticalXDistance,
                this.yDistance + verticalStartOffset,
                1,
                verticalHeight,
                this.borderColor,
                this.borderColor,
                1
            )) {
                this.destroyObjects();
                return false;
            }
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

                if (!this.createLabel(
                    this.getEmaCellObjectName(i, j),
                    this.getColumnLeftOffset(j),
                    rowYDistance + this.emaRowOffset,
                    this.bodyFontSize,
                    this.mutedColor,
                    "-"
                )) {
                    this.destroyObjects();
                    return false;
                }

                if (j >= drawAlignedElliotAllListColumnTimeFrameStart
                        && !this.createLabel(
                            this.getFibonacciCellObjectName(i, j),
                            this.getColumnLeftOffset(j)
                                + this.columnWidth
                                - this.fibonacciRightPadding,
                            rowYDistance + this.emaRowOffset,
                            this.bodyFontSize - 1,
                            this.headerColor,
                            " ",
                            ANCHOR_RIGHT_UPPER
                        )) {
                    this.destroyObjects();
                    return false;
                }
            }

            bool drawSeparator = false;

            if (i < fromBuyCount - 1) {
                drawSeparator = true;
            } else if (i >= fromBuyCount && i < rowCount - 1) {
                drawSeparator = true;
            }

            if (drawSeparator && !this.createRectangle(
                this.objectPrefix + "RowSeparator_" + IntegerToString(i),
                this.xDistance + this.tableLeftOffset,
                this.yDistance + rowYDistance + this.rowHeight - 3,
                this.panelWidth - (this.tableLeftOffset * 2),
                1,
                this.borderColor,
                this.borderColor,
                1
            )) {
                this.destroyObjects();
                return false;
            }
        }

        this.createdRowCount = rowCount;
        this.createdBuyCount = fromBuyCount;
        this.createdSellCount = fromSellCount;
        this.createdH1RunnerUpCount = fromH1RunnerUpCount;
        this.createdCurrentTimeFrame = fromCurrentTimeFrame;
        this.created = true;

        return true;
    }

    /**
     * 一覧右側へENTRY優先度の凡例を生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool createEntryLegend() {
        int legendLeftOffset = this.panelWidth + this.entryLegendGap;

        if (!this.createRectangle(
            this.objectPrefix + "EntryLegendPanel",
            this.xDistance + legendLeftOffset,
            this.yDistance,
            this.entryLegendWidth,
            this.entryLegendHeight,
            this.panelBackgroundColor,
            this.borderColor,
            0
        )) {
            return false;
        }

        if (!this.createRectangle(
            this.objectPrefix + "EntryLegendTitleBackground",
            this.xDistance + legendLeftOffset + 1,
            this.yDistance + 1,
            this.entryLegendWidth - 2,
            this.headerHeight,
            this.headerBackgroundColor,
            this.headerBackgroundColor,
            1
        )) {
            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "EntryLegendTitle",
            legendLeftOffset + 12,
            5,
            this.titleFontSize,
            this.titleColor,
            "ENTRY 判定"
        )) {
            return false;
        }

        string legendTexts[] = {
            "READY  主要条件成立・最終判定前",
            "NEAR   あと1条件でREADY",
            "SETUP  対象波成立・複数条件待ち",
            "ALIGN  対象時間足の1/3波待ち",
            "ERROR  判定データ不足"
        };
        color legendColors[] = {
            this.entryReadyColor,
            this.entryNearColor,
            this.entrySetupColor,
            this.mutedColor,
            this.entryErrorColor
        };
        int legendCount = ArraySize(legendTexts);

        for (int i = 0; i < legendCount; i++) {
            if (!this.createLabel(
                this.objectPrefix + "EntryLegend_" + IntegerToString(i),
                legendLeftOffset + 12,
                this.headerHeight + 8 + (i * this.entryLegendRowHeight),
                this.bodyFontSize,
                legendColors[i],
                legendTexts[i]
            )) {
                return false;
            }
        }

        return true;
    }

    /**
     * 一覧右側へH1方向一致の次点候補パネルを生成する。
     *
     * @param fromRunnerUpCount 次点候補行数。
     * @return 生成に成功した場合true。
     */
    bool createH1RunnerUpPanel(int fromRunnerUpCount) {
        int panelLeftOffset = this.panelWidth + this.entryLegendGap;
        int firstGroupTopOffset = this.headerHeight + 8;
        int panelHeight = firstGroupTopOffset
            + (this.h1RunnerUpGroupHeight * 2)
            + this.h1RunnerUpSectionGap
            + (fromRunnerUpCount * this.entryLegendRowHeight)
            + this.bottomPadding;

        if (!this.createRectangle(
            this.objectPrefix + "H1RunnerUpPanel",
            this.xDistance + panelLeftOffset,
            this.yDistance,
            this.entryLegendWidth,
            panelHeight,
            this.panelBackgroundColor,
            this.borderColor,
            0
        )) {
            return false;
        }

        if (!this.createRectangle(
            this.objectPrefix + "H1RunnerUpTitleBackground",
            this.xDistance + panelLeftOffset + 1,
            this.yDistance + 1,
            this.entryLegendWidth - 2,
            this.headerHeight,
            this.headerBackgroundColor,
            this.headerBackgroundColor,
            1
        )) {
            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "H1RunnerUpTitle",
            panelLeftOffset + 12,
            5,
            this.titleFontSize,
            this.titleColor,
            "NEXT H1"
        )) {
            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "H1RunnerUpGroupBuy",
            panelLeftOffset + 12,
            firstGroupTopOffset,
            this.bodyFontSize,
            this.buyColor,
            "BUY 0"
        )) {
            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "H1RunnerUpGroupSell",
            panelLeftOffset + 12,
            firstGroupTopOffset
                + this.h1RunnerUpGroupHeight
                + this.h1RunnerUpSectionGap,
            this.bodyFontSize,
            this.sellColor,
            "SELL 0"
        )) {
            return false;
        }

        for (int i = 0; i < fromRunnerUpCount; i++) {
            if (!this.createLabel(
                this.getH1RunnerUpRowObjectName(i),
                panelLeftOffset + 12,
                firstGroupTopOffset + this.h1RunnerUpGroupHeight,
                this.bodyFontSize,
                this.mutedColor,
                "-"
            )) {
                return false;
            }
        }

        return true;
    }

    /**
     * H1方向一致の次点候補をBUY、SELL、未達条件の順に抽出する。
     *
     * 同一方向かつ同一未達条件の候補は元一覧の順序を維持する。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDecision H1次点候補判定クラス。
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromDisplayIndexes 表示用インデックスの格納先。
     * @param fromRunnerUpResults 次点候補判定結果の格納先。
     * @param fromBuyCount BUY候補件数の格納先。
     * @param fromSellCount SELL候補件数の格納先。
     * @return 次点候補件数。
     */
    int buildH1RunnerUpOrder(
        ElliotAllList *fromElliotAllList,
        ElliotDirectionAlignmentDecision *fromDecision,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        int &fromDisplayIndexes[],
        H1ElliotAlignmentRunnerUpResult &fromRunnerUpResults[],
        int &fromBuyCount,
        int &fromSellCount
    ) {
        ArrayResize(fromDisplayIndexes, 0);
        ArrayResize(fromRunnerUpResults, 0);
        fromBuyCount = 0;
        fromSellCount = 0;

        if (fromElliotAllList == NULL || fromDecision == NULL) {
            return 0;
        }

        int total = fromElliotAllList.elliotAllList.Total();

        if (ArrayResize(fromDisplayIndexes, total) != total
                || ArrayResize(fromRunnerUpResults, total) != total) {
            ArrayResize(fromDisplayIndexes, 0);
            ArrayResize(fromRunnerUpResults, 0);

            return 0;
        }

        int displayCount = 0;

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(i);
            H1ElliotAlignmentRunnerUpResult runnerUpResult;

            if (!fromDecision.getH1RunnerUpResult(
                elliotAll,
                fromCurrentTimeFrame,
                runnerUpResult
            ) || !runnerUpResult.isRunnerUp) {
                continue;
            }

            if (runnerUpResult.alignType == trendAlignBuy) {
                fromBuyCount++;
            } else if (runnerUpResult.alignType == trendAlignSell) {
                fromSellCount++;
            } else {
                continue;
            }

            fromDisplayIndexes[displayCount] = i;
            fromRunnerUpResults[displayCount] = runnerUpResult;
            displayCount++;
        }

        ArrayResize(fromDisplayIndexes, displayCount);
        ArrayResize(fromRunnerUpResults, displayCount);
        this.sortH1RunnerUpOrder(fromDisplayIndexes, fromRunnerUpResults);

        return displayCount;
    }

    /**
     * H1次点候補をBUY、SELL、未達条件の順に安定ソートする。
     *
     * @param fromDisplayIndexes 表示用インデックス。
     * @param fromRunnerUpResults インデックスと対応する次点候補判定結果。
     */
    void sortH1RunnerUpOrder(
        int &fromDisplayIndexes[],
        H1ElliotAlignmentRunnerUpResult &fromRunnerUpResults[]
    ) {
        int displayCount = ArraySize(fromDisplayIndexes);

        if (displayCount != ArraySize(fromRunnerUpResults)) {
            return;
        }

        for (int i = 1; i < displayCount; i++) {
            int currentIndex = fromDisplayIndexes[i];
            H1ElliotAlignmentRunnerUpResult currentResult =
                fromRunnerUpResults[i];
            int j = i - 1;

            while (j >= 0
                    && this.shouldShiftH1RunnerUpResult(
                        currentResult,
                        fromRunnerUpResults[j]
                    )) {
                fromDisplayIndexes[j + 1] = fromDisplayIndexes[j];
                fromRunnerUpResults[j + 1] = fromRunnerUpResults[j];
                j--;
            }

            fromDisplayIndexes[j + 1] = currentIndex;
            fromRunnerUpResults[j + 1] = currentResult;
        }
    }

    /**
     * 現在のH1次点候補を比較対象より前へ移動するか判定する。
     *
     * @param fromCurrentResult 現在の次点候補判定結果。
     * @param fromPreviousResult 比較対象の次点候補判定結果。
     * @return 現在結果を前へ移動する場合true。
     */
    bool shouldShiftH1RunnerUpResult(
        H1ElliotAlignmentRunnerUpResult &fromCurrentResult,
        H1ElliotAlignmentRunnerUpResult &fromPreviousResult
    ) {
        int currentDirectionOrder = this.getH1RunnerUpDirectionOrder(
            fromCurrentResult.alignType
        );
        int previousDirectionOrder = this.getH1RunnerUpDirectionOrder(
            fromPreviousResult.alignType
        );

        if (currentDirectionOrder != previousDirectionOrder) {
            return currentDirectionOrder < previousDirectionOrder;
        }

        if (fromCurrentResult.missingCondition
                != fromPreviousResult.missingCondition) {
            return (int)fromCurrentResult.missingCondition
                < (int)fromPreviousResult.missingCondition;
        }

        return false;
    }

    /**
     * H1次点候補の方向表示順を取得する。
     *
     * @param fromAlignType 次点候補の方向。
     * @return BUYは0、SELLは1、それ以外は2。
     */
    int getH1RunnerUpDirectionOrder(TrendAlignType fromAlignType) {
        if (fromAlignType == trendAlignBuy) {
            return 0;
        }

        if (fromAlignType == trendAlignSell) {
            return 1;
        }

        return 2;
    }

    /**
     * H1方向一致の次点候補パネルを更新する。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDisplayIndexes 表示用インデックス。
     * @param fromRunnerUpResults 次点候補判定結果。
     * @param fromBuyCount BUY候補件数。
     * @param fromSellCount SELL候補件数。
     */
    void drawH1RunnerUpRows(
        ElliotAllList *fromElliotAllList,
        const int &fromDisplayIndexes[],
        H1ElliotAlignmentRunnerUpResult &fromRunnerUpResults[],
        int fromBuyCount,
        int fromSellCount
    ) {
        if (fromElliotAllList == NULL) {
            return;
        }

        int displayCount = ArraySize(fromDisplayIndexes);

        if (displayCount != ArraySize(fromRunnerUpResults)
                || displayCount != fromBuyCount + fromSellCount) {
            return;
        }

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "H1RunnerUpTitle",
            OBJPROP_TEXT,
            StringFormat("NEXT H1 4/5  B%d / S%d", fromBuyCount, fromSellCount)
        );
        ObjectSetString(
            this.chartId,
            this.objectPrefix + "H1RunnerUpGroupBuy",
            OBJPROP_TEXT,
            StringFormat("BUY  %d", fromBuyCount)
        );
        ObjectSetString(
            this.chartId,
            this.objectPrefix + "H1RunnerUpGroupSell",
            OBJPROP_TEXT,
            StringFormat("SELL  %d", fromSellCount)
        );

        int sellGroupTopOffset = this.getH1RunnerUpSellGroupTopOffset(
            fromBuyCount
        );
        ObjectSetInteger(
            this.chartId,
            this.objectPrefix + "H1RunnerUpGroupSell",
            OBJPROP_YDISTANCE,
            this.yDistance + sellGroupTopOffset
        );

        for (int i = 0; i < displayCount; i++) {
            ElliotAll *elliotAll = fromElliotAllList.elliotAllList.At(
                fromDisplayIndexes[i]
            );
            string symbolText = "-";

            if (elliotAll != NULL) {
                symbolText = this.getSymbolText(
                    elliotAll.marketContext.symbolName
                );
            }

            string missingText = this.getH1RunnerUpMissingConditionText(
                (int)fromRunnerUpResults[i].missingCondition
            );
            string rowText = symbolText + "  WAIT " + missingText;
            string objectName = this.getH1RunnerUpRowObjectName(i);
            color rowColor = this.getAlignColor(
                fromRunnerUpResults[i].alignType
            );

            ObjectSetString(
                this.chartId,
                objectName,
                OBJPROP_TEXT,
                rowText
            );
            ObjectSetString(
                this.chartId,
                objectName,
                OBJPROP_TOOLTIP,
                rowText
            );
            ObjectSetInteger(
                this.chartId,
                objectName,
                OBJPROP_COLOR,
                rowColor
            );
            ObjectSetInteger(
                this.chartId,
                objectName,
                OBJPROP_YDISTANCE,
                this.yDistance + this.getH1RunnerUpRowTopOffset(
                    i,
                    fromBuyCount
                )
            );
        }
    }

    /**
     * H1次点候補の未達条件表示を取得する。
     *
     * @param fromMissingCondition 未達条件。
     * @return H1、H4、D1、W1またはMN1|W1EMA。
     */
    string getH1RunnerUpMissingConditionText(int fromMissingCondition) {
        if (fromMissingCondition == h1ElliotAlignmentMissingH1) {
            return "H1";
        }

        if (fromMissingCondition == h1ElliotAlignmentMissingH4) {
            return "H4";
        }

        if (fromMissingCondition == h1ElliotAlignmentMissingD1) {
            return "D1";
        }

        if (fromMissingCondition == h1ElliotAlignmentMissingW1) {
            return "W1";
        }

        if (fromMissingCondition
                == h1ElliotAlignmentMissingMn1OrW1Ema200) {
            return "MN1|W1EMA";
        }

        return "-";
    }

    /**
     * H1次点候補のSELLグループ見出し位置を取得する。
     *
     * @param fromBuyCount BUY候補件数。
     * @return パネル上端からの位置。
     */
    int getH1RunnerUpSellGroupTopOffset(int fromBuyCount) {
        return this.headerHeight
            + 8
            + this.h1RunnerUpGroupHeight
            + (fromBuyCount * this.entryLegendRowHeight)
            + this.h1RunnerUpSectionGap;
    }

    /**
     * H1次点候補行の位置を取得する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromBuyCount BUY候補件数。
     * @return パネル上端からの位置。
     */
    int getH1RunnerUpRowTopOffset(int fromRowIndex, int fromBuyCount) {
        int firstGroupTopOffset = this.headerHeight + 8;

        if (fromRowIndex < fromBuyCount) {
            return firstGroupTopOffset
                + this.h1RunnerUpGroupHeight
                + (fromRowIndex * this.entryLegendRowHeight);
        }

        int sellRowIndex = fromRowIndex - fromBuyCount;

        return this.getH1RunnerUpSellGroupTopOffset(fromBuyCount)
            + this.h1RunnerUpGroupHeight
            + (sellRowIndex * this.entryLegendRowHeight);
    }

    /**
     * 指定方向の一致結果を選択された優先順で描画する。
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
        int displayIndexes[];
        Mtf3In3EntryPriorityResult priorityResults[];
        D1ElliotEmaSortResult d1SortResults[];
        M15ElliotEmaSortResult m15SortResults[];
        int displayCount = this.buildDisplayOrder(
            fromElliotAllList,
            fromDecision,
            fromCurrentTimeFrame,
            fromAlignType,
            displayIndexes,
            priorityResults,
            d1SortResults,
            m15SortResults
        );

        for (int i = 0; i < displayCount; i++) {
            ElliotAll *elliotAll =
                fromElliotAllList.elliotAllList.At(displayIndexes[i]);

            this.drawRow(
                fromStartRowIndex + i,
                elliotAll,
                fromDisplayTimeFrames,
                fromAlignType,
                priorityResults[i]
            );
        }
    }

    /**
     * 指定方向の表示対象を抽出して選択された優先順へ並べる。
     *
     * 元のElliotAllListは変更せず、表示用インデックスと優先度結果だけを
     * 安定ソートする。
     *
     * @param fromElliotAllList 分析結果一覧。
     * @param fromDecision 完全一致判定クラス。
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromAlignType 抽出する方向。
     * @param fromDisplayIndexes 表示用インデックスの格納先。
     * @param fromPriorityResults 優先度判定結果の格納先。
     * @param fromD1SortResults D1 Elliott・EMA200ソート結果の格納先。
     * @param fromM15SortResults M15 Elliott・EMA200ソート結果の格納先。
     * @return 表示対象件数。
     */
    int buildDisplayOrder(
        ElliotAllList *fromElliotAllList,
        ElliotDirectionAlignmentDecision *fromDecision,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        TrendAlignType fromAlignType,
        int &fromDisplayIndexes[],
        Mtf3In3EntryPriorityResult &fromPriorityResults[],
        D1ElliotEmaSortResult &fromD1SortResults[],
        M15ElliotEmaSortResult &fromM15SortResults[]
    ) {
        ArrayResize(fromDisplayIndexes, 0);
        ArrayResize(fromPriorityResults, 0);
        ArrayResize(fromD1SortResults, 0);
        ArrayResize(fromM15SortResults, 0);

        int total = fromElliotAllList.elliotAllList.Total();

        if (ArrayResize(fromDisplayIndexes, total) != total
                || ArrayResize(fromPriorityResults, total) != total
                || ArrayResize(fromD1SortResults, total) != total
                || ArrayResize(fromM15SortResults, total) != total) {
            ArrayResize(fromDisplayIndexes, 0);
            ArrayResize(fromPriorityResults, 0);
            ArrayResize(fromD1SortResults, 0);
            ArrayResize(fromM15SortResults, 0);

            return 0;
        }

        Mtf3In3EntryPriorityDecision priorityDecision;
        D1ElliotEmaSortDecision d1SortDecision;
        M15ElliotEmaSortDecision m15SortDecision;
        int displayCount = 0;

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

            Mtf3In3EntryPriorityResult priorityResult;
            priorityResult.reset();
            priorityDecision.evaluate(
                elliotAll,
                fromCurrentTimeFrame,
                priorityResult
            );
            D1ElliotEmaSortResult d1SortResult;
            d1SortResult.reset();
            M15ElliotEmaSortResult m15SortResult;
            m15SortResult.reset();

            if (this.sortType == ELLIOT_LIST_SORT_D1_ELLIOT_EMA
                    && fromCurrentTimeFrame == PERIOD_D1) {
                d1SortDecision.evaluate(elliotAll, d1SortResult);
            }

            if (this.sortType == ELLIOT_LIST_SORT_M15_ELLIOT_EMA
                    && fromCurrentTimeFrame == PERIOD_M15) {
                m15SortDecision.evaluate(elliotAll, m15SortResult);
            }

            fromDisplayIndexes[displayCount] = i;
            fromPriorityResults[displayCount] = priorityResult;
            fromD1SortResults[displayCount] = d1SortResult;
            fromM15SortResults[displayCount] = m15SortResult;
            displayCount++;
        }

        ArrayResize(fromDisplayIndexes, displayCount);
        ArrayResize(fromPriorityResults, displayCount);
        ArrayResize(fromD1SortResults, displayCount);
        ArrayResize(fromM15SortResults, displayCount);
        this.sortDisplayOrder(
            fromCurrentTimeFrame,
            fromDisplayIndexes,
            fromPriorityResults,
            fromD1SortResults,
            fromM15SortResults
        );

        return displayCount;
    }

    /**
     * 表示用インデックスを優先度順に安定ソートする。
     *
     * D1またはM15 Elliott・EMA200ソート選択時は方向を主キーとし、
     * 現在のエントリー優先度を副キーにする。他の場合は優先度順にする。
     *
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromDisplayIndexes 表示用インデックス。
     * @param fromPriorityResults インデックスと対応する優先度判定結果。
     * @param fromD1SortResults インデックスと対応するD1ソート結果。
     * @param fromM15SortResults インデックスと対応するM15ソート結果。
     */
    void sortDisplayOrder(
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        int &fromDisplayIndexes[],
        Mtf3In3EntryPriorityResult &fromPriorityResults[],
        D1ElliotEmaSortResult &fromD1SortResults[],
        M15ElliotEmaSortResult &fromM15SortResults[]
    ) {
        int displayCount = ArraySize(fromDisplayIndexes);

        if (displayCount != ArraySize(fromPriorityResults)
                || displayCount != ArraySize(fromD1SortResults)
                || displayCount != ArraySize(fromM15SortResults)) {
            return;
        }

        for (int i = 1; i < displayCount; i++) {
            int currentIndex = fromDisplayIndexes[i];
            Mtf3In3EntryPriorityResult currentResult = fromPriorityResults[i];
            D1ElliotEmaSortResult currentD1SortResult =
                fromD1SortResults[i];
            M15ElliotEmaSortResult currentM15SortResult =
                fromM15SortResults[i];
            int j = i - 1;

            while (j >= 0
                    && this.shouldShiftDisplayResult(
                        fromCurrentTimeFrame,
                        currentD1SortResult,
                        fromD1SortResults[j],
                        currentM15SortResult,
                        fromM15SortResults[j],
                        currentResult,
                        fromPriorityResults[j]
                    )) {
                fromDisplayIndexes[j + 1] = fromDisplayIndexes[j];
                fromPriorityResults[j + 1] = fromPriorityResults[j];
                fromD1SortResults[j + 1] = fromD1SortResults[j];
                fromM15SortResults[j + 1] = fromM15SortResults[j];
                j--;
            }

            fromDisplayIndexes[j + 1] = currentIndex;
            fromPriorityResults[j + 1] = currentResult;
            fromD1SortResults[j + 1] = currentD1SortResult;
            fromM15SortResults[j + 1] = currentM15SortResult;
        }
    }

    /**
     * 現在の表示結果を比較対象より前へ移動するか判定する。
     *
     * @param fromCurrentTimeFrame 表示時間足。
     * @param fromCurrentD1SortResult 現在のD1ソート結果。
     * @param fromPreviousD1SortResult 比較対象のD1ソート結果。
     * @param fromCurrentM15SortResult 現在のM15ソート結果。
     * @param fromPreviousM15SortResult 比較対象のM15ソート結果。
     * @param fromCurrentPriorityResult 現在のエントリー優先度判定結果。
     * @param fromPreviousPriorityResult 比較対象のエントリー優先度判定結果。
     * @return 現在結果を前へ移動する場合true。
     */
    bool shouldShiftDisplayResult(
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        D1ElliotEmaSortResult &fromCurrentD1SortResult,
        D1ElliotEmaSortResult &fromPreviousD1SortResult,
        M15ElliotEmaSortResult &fromCurrentM15SortResult,
        M15ElliotEmaSortResult &fromPreviousM15SortResult,
        Mtf3In3EntryPriorityResult &fromCurrentPriorityResult,
        Mtf3In3EntryPriorityResult &fromPreviousPriorityResult
    ) {
        if (this.sortType == ELLIOT_LIST_SORT_D1_ELLIOT_EMA
                && fromCurrentTimeFrame == PERIOD_D1) {
            D1ElliotEmaSortDecision d1SortDecision;
            int compareResult = d1SortDecision.compare(
                fromCurrentD1SortResult,
                fromPreviousD1SortResult
            );

            if (compareResult < 0) {
                return true;
            }

            if (compareResult > 0) {
                return false;
            }
        }

        if (this.sortType == ELLIOT_LIST_SORT_M15_ELLIOT_EMA
                && fromCurrentTimeFrame == PERIOD_M15) {
            M15ElliotEmaSortDecision m15SortDecision;
            int compareResult = m15SortDecision.compare(
                fromCurrentM15SortResult,
                fromPreviousM15SortResult
            );

            if (compareResult < 0) {
                return true;
            }

            if (compareResult > 0) {
                return false;
            }
        }

        return this.shouldShiftPriorityResult(
            fromCurrentPriorityResult,
            fromPreviousPriorityResult
        );
    }

    /**
     * 現在の優先度結果を比較対象より前へ移動するか判定する。
     *
     * @param fromCurrentResult 現在の優先度判定結果。
     * @param fromPreviousResult 比較対象の優先度判定結果。
     * @return 現在結果を前へ移動する場合true。
     */
    bool shouldShiftPriorityResult(
        Mtf3In3EntryPriorityResult &fromCurrentResult,
        Mtf3In3EntryPriorityResult &fromPreviousResult
    ) {
        if (fromCurrentResult.rank != fromPreviousResult.rank) {
            return fromCurrentResult.rank < fromPreviousResult.rank;
        }

        if (fromCurrentResult.waveMatchCount
                != fromPreviousResult.waveMatchCount) {
            return fromCurrentResult.waveMatchCount
                > fromPreviousResult.waveMatchCount;
        }

        if (fromCurrentResult.conditionMatchCount
                != fromPreviousResult.conditionMatchCount) {
            return fromCurrentResult.conditionMatchCount
                > fromPreviousResult.conditionMatchCount;
        }

        return false;
    }

    /**
     * 1シンボル分の行を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromElliotAll 分析結果。
     * @param fromDisplayTimeFrames 表示対象時間足一覧。
     * @param fromAlignType 一致方向。
     * @param fromPriorityResult エントリー優先度判定結果。
     */
    void drawRow(
        int fromRowIndex,
        ElliotAll *fromElliotAll,
        const ENUM_TIMEFRAMES &fromDisplayTimeFrames[],
        TrendAlignType fromAlignType,
        Mtf3In3EntryPriorityResult &fromPriorityResult
    ) {
        if (fromElliotAll == NULL) {
            return;
        }

        color directionColor = this.getAlignColor(fromAlignType);

        this.setCell(
            fromRowIndex,
            drawAlignedElliotAllListColumnSymbol,
            this.getSymbolText(fromElliotAll.marketContext.symbolName),
            directionColor
        );
        this.setEmaCell(
            fromRowIndex,
            drawAlignedElliotAllListColumnSymbol,
            "EMA200",
            this.headerColor
        );
        this.setCell(
            fromRowIndex,
            drawAlignedElliotAllListColumnEntryPriority,
            this.getEntryPriorityText(fromPriorityResult.rank),
            this.getEntryPriorityColor(fromPriorityResult.rank)
        );
        this.setEmaCell(
            fromRowIndex,
            drawAlignedElliotAllListColumnEntryPriority,
            " ",
            this.mutedColor
        );

        int timeFrameCount = ArraySize(fromDisplayTimeFrames);

        for (int i = 0; i < timeFrameCount; i++) {
            Elliot *elliot = fromElliotAll.getElliot(fromDisplayTimeFrames[i]);
            int columnIndex = drawAlignedElliotAllListColumnTimeFrameStart + i;

            this.setCell(
                fromRowIndex,
                columnIndex,
                this.getWaveText(elliot),
                this.getWaveColor(elliot)
            );

            string emaText = this.getEmaText(elliot);

            this.setEmaCell(
                fromRowIndex,
                columnIndex,
                emaText,
                this.getEmaColor(emaText)
            );
            this.setFibonacciCell(
                fromRowIndex,
                columnIndex,
                this.getFibonacciText(elliot),
                this.headerColor
            );
            this.setTimeFrameCellTooltip(
                fromRowIndex,
                columnIndex,
                this.getWaveTooltip(elliot)
            );
        }
    }

    /**
     * タイトルを更新する。
     *
     * @param fromTimeFrameText 表示時間足。
     * @param fromAlignmentStartTimeFrameText 一致判定の開始時間足。
     * @param fromBuyCount BUY件数。
     * @param fromSellCount SELL件数。
     * @param fromTargetCount 対象通貨件数。
     * @param fromErrorCount 分析エラー件数。
     */
    void updateTitle(
        string fromTimeFrameText,
        string fromAlignmentStartTimeFrameText,
        int fromBuyCount,
        int fromSellCount,
        int fromTargetCount,
        int fromErrorCount
    ) {
        datetime serverTime = TimeCurrent();
        datetime japanTime = TimeJapanUtil::getJapanTime(serverTime);

        string fullTitleText = StringFormat(
            "ZigZag Elliott List ALL %s ANALYZE MN1 / ALIGN %s BUY %d / SELL %d / TARGET %d / ERROR %d JST %s SV %s",
            fromTimeFrameText,
            fromAlignmentStartTimeFrameText,
            fromBuyCount,
            fromSellCount,
            fromTargetCount,
            fromErrorCount,
            this.formatTitleTime(japanTime),
            this.formatTitleTime(serverTime)
        );
        string displayTitleText = fullTitleText;

        if (fromTimeFrameText == "D1") {
            displayTitleText = StringFormat(
                "ZZ Elliott %s/%s B%d S%d T%d E%d JST %s",
                fromTimeFrameText,
                fromAlignmentStartTimeFrameText,
                fromBuyCount,
                fromSellCount,
                fromTargetCount,
                fromErrorCount,
                this.formatTitleTime(japanTime)
            );
        }

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            displayTitleText
        );

        if (fromTimeFrameText == "D1") {
            ObjectSetString(
                this.chartId,
                this.objectPrefix + "Title",
                OBJPROP_TOOLTIP,
                fullTitleText
            );
        }
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
     * @return 未確定表示、方向、Elliottラベル、補完表示を連結した文字列。
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

        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();

        if (latestPoint != NULL && latestPoint.isAddedPoint) {
            text += "★";
        }

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
     * 最新ポイントのFibonacci表示文字列を取得する。
     *
     * @param fromElliot 対象時間足のElliot。
     * @return 修正波はF、推進波はFEを付けた比率。取得不能時は空文字列。
     */
    string getFibonacciText(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "";
        }

        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();

        if (latestPoint == NULL || latestPoint.orgElliotIndex <= 1) {
            return "";
        }

        double fibonacciPercent = latestPoint.fibonacciExpansionPercent;
        string prefix = "FE";

        if (latestPoint.orgElliotIndex % 2 == 0) {
            fibonacciPercent = latestPoint.fibonacciPercent;
            prefix = "F";
        }

        if (!this.isValidFibonacciPercent(fibonacciPercent)) {
            return "";
        }

        return prefix + DoubleToString(fibonacciPercent, 1);
    }

    /**
     * 最新波動の詳細ツールチップを取得する。
     *
     * @param fromElliot 対象時間足のElliot。
     * @return 波動種別、Fibonacci、値幅、経過本数などの詳細文字列。
     */
    string getWaveTooltip(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "\n";
        }

        Wave *latestWave = fromElliot.getLatestWave();
        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();

        if (latestWave == NULL || latestPoint == NULL) {
            return "\n";
        }

        string timeFrameText = fromElliot.marketContext.timeFrameLabel;

        if (timeFrameText == "") {
            timeFrameText = TimeUtil::convertTimeFrameToString(
                fromElliot.marketContext.timeFrame
            );
        }

        string waveTypeText = "CORRECTIVE";

        if (latestWave.isMotive) {
            waveTypeText = "MOTIVE";
        }

        string confirmedText = "UNCONFIRMED";

        if (latestWave.isConfirmed) {
            confirmedText = "CONFIRMED";
        }

        string elliotLabel = latestPoint.getElliotLabel();

        if (elliotLabel == "") {
            elliotLabel = "-";
        }

        string orgElliotLabel = latestPoint.orgElliotLabel;

        if (orgElliotLabel == "") {
            orgElliotLabel = "-";
        }

        string addedText = "NO";

        if (latestPoint.isAddedPoint) {
            addedText = "YES";
        }

        string correctedText = "NO";

        if (latestPoint.isCorrect) {
            correctedText = "YES";
        }

        string text = fromElliot.marketContext.symbolName + " " + timeFrameText;
        text += "\nWave: " + waveTypeText + " / " + confirmedText;
        text += "\nLabel: " + elliotLabel;
        text += "\nOriginal: " + orgElliotLabel;

        string fibonacciText = this.getFibonacciText(fromElliot);

        if (fibonacciText != "") {
            text += "\nFibonacci: " + fibonacciText + "%";

            if (latestPoint.orgElliotIndex % 2 == 0
                    && latestPoint.fiboDepthZoneLabel != "") {
                text += " / " + latestPoint.fiboDepthZoneLabel;
            }
        }

        if (MathIsValidNumber(latestPoint.pipsDiff)
                && latestPoint.pipsDiff != EMPTY_VALUE
                && latestPoint.pipsDiff > 0.0) {
            text += "\nMove: " + DoubleToString(latestPoint.pipsDiff, 1) + " pips";

            if (latestPoint.waveBarsFromStart > 0) {
                text += " / " + IntegerToString(latestPoint.waveBarsFromStart) + " bars";
            }
        } else if (latestPoint.waveBarsFromStart > 0) {
            text += "\nMove: "
                + IntegerToString(latestPoint.waveBarsFromStart)
                + " bars";
        }

        if (latestPoint.barTime > 0) {
            text += "\nTime: "
                + TimeToString(latestPoint.barTime, TIME_DATE | TIME_MINUTES);
        }

        if (MathIsValidNumber(latestPoint.rate)
                && latestPoint.rate != EMPTY_VALUE
                && latestPoint.rate > 0.0) {
            text += "\nPrice: " + latestPoint.getTextRate();
        }

        text += "\nAdded: " + addedText + " / Corrected: " + correctedText;

        if (latestWave.previousLastElliotLabel != "") {
            text += "\nPrevious: " + latestWave.previousLastElliotLabel;
        }

        return text;
    }

    /**
     * Fibonacci比率が表示可能か判定する。
     *
     * @param fromFibonacciPercent 判定対象の比率。
     * @return 有効な正数の場合true。
     */
    bool isValidFibonacciPercent(double fromFibonacciPercent) {
        if (!MathIsValidNumber(fromFibonacciPercent)
                || fromFibonacciPercent == EMPTY_VALUE
                || fromFibonacciPercent <= 0.0) {
            return false;
        }

        return true;
    }

    /**
     * EMA200の売買方向文字列を取得する。
     *
     * @param fromElliot 対象時間足のElliot。
     * @return BUY / SELL / -。
     */
    string getEmaText(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "-";
        }

        string emaText = fromElliot.oscillator.ema200.getBuySellLabel();

        if (emaText == "BUY" || emaText == "SELL") {
            return emaText;
        }

        return "-";
    }

    /**
     * EMA200の売買方向色を取得する。
     *
     * @param fromText EMA200の売買方向文字列。
     * @return BUYはBUY色、SELLはSELL色、それ以外は抑制色。
     */
    color getEmaColor(string fromText) {
        if (fromText == "BUY") {
            return this.buyColor;
        }

        if (fromText == "SELL") {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * エントリー優先度の表示文字列を取得する。
     *
     * @param fromRank エントリー優先度。
     * @return READY / NEAR / SETUP / ALIGN / ERROR。
     */
    string getEntryPriorityText(Mtf3In3EntryPriorityRank fromRank) {
        if (fromRank == mtf3In3EntryPriorityReady) {
            return "READY";
        }

        if (fromRank == mtf3In3EntryPriorityNear) {
            return "NEAR";
        }

        if (fromRank == mtf3In3EntryPrioritySetup) {
            return "SETUP";
        }

        if (fromRank == mtf3In3EntryPriorityAlign) {
            return "ALIGN";
        }

        return "ERROR";
    }

    /**
     * エントリー優先度の表示色を取得する。
     *
     * @param fromRank エントリー優先度。
     * @return 優先度に対応する表示色。
     */
    color getEntryPriorityColor(Mtf3In3EntryPriorityRank fromRank) {
        if (fromRank == mtf3In3EntryPriorityReady) {
            return this.entryReadyColor;
        }

        if (fromRank == mtf3In3EntryPriorityNear) {
            return this.entryNearColor;
        }

        if (fromRank == mtf3In3EntryPrioritySetup) {
            return this.entrySetupColor;
        }

        if (fromRank == mtf3In3EntryPriorityAlign) {
            return this.mutedColor;
        }

        return this.entryErrorColor;
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
     * GMO取引対象を付記したシンボル表示文字列を取得する。
     *
     * @param fromSymbolName 対象シンボル名。
     * @return GMO対象の場合は末尾へGMOを付けた文字列。
     */
    string getSymbolText(string fromSymbolName) {
        if (this.gmoSymbolNameInfoAll.isTarget(fromSymbolName)) {
            return fromSymbolName + " GMO";
        }

        return fromSymbolName;
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
     * EMA200セルの文字列と色を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setEmaCell(
        int fromRowIndex,
        int fromColumnIndex,
        string fromText,
        color fromColor
    ) {
        string objectName = this.getEmaCellObjectName(fromRowIndex, fromColumnIndex);

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * Fibonacciセルの文字列と色を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setFibonacciCell(
        int fromRowIndex,
        int fromColumnIndex,
        string fromText,
        color fromColor
    ) {
        string objectName = this.getFibonacciCellObjectName(
            fromRowIndex,
            fromColumnIndex
        );

        string displayText = fromText;

        if (displayText == "") {
            displayText = " ";
        }

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, displayText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * 時間足セルの上段、EMA200およびFibonacciへツールチップを設定する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromColumnIndex 列番号。
     * @param fromTooltip ツールチップ文字列。
     */
    void setTimeFrameCellTooltip(
        int fromRowIndex,
        int fromColumnIndex,
        string fromTooltip
    ) {
        ObjectSetString(
            this.chartId,
            this.getCellObjectName(fromRowIndex, fromColumnIndex),
            OBJPROP_TOOLTIP,
            fromTooltip
        );
        ObjectSetString(
            this.chartId,
            this.getEmaCellObjectName(fromRowIndex, fromColumnIndex),
            OBJPROP_TOOLTIP,
            fromTooltip
        );
        ObjectSetString(
            this.chartId,
            this.getFibonacciCellObjectName(fromRowIndex, fromColumnIndex),
            OBJPROP_TOOLTIP,
            fromTooltip
        );
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
     * @param fromAnchor ラベルのアンカー位置。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        string fromObjectName,
        int fromLeftOffset,
        int fromTopOffset,
        int fromFontSize,
        color fromColor,
        string fromText,
        ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER
    ) {
        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ANCHOR, fromAnchor);
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
     * @param fromCurrentTimeFrame 一覧基準の時間足。
     * @param fromTimeFrameCount 時間足列数。
     * @return パネル横幅。
     */
    int calculatePanelWidth(
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        int fromTimeFrameCount
    ) {
        int columnCount = fromTimeFrameCount
            + drawAlignedElliotAllListColumnTimeFrameStart;
        int width = (this.tableLeftOffset * 2)
            + (columnCount * this.columnWidth);

        if (fromCurrentTimeFrame == PERIOD_D1) {
            return width;
        }

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
        return this.tableLeftOffset
            + this.cellLeftPadding
            + (fromColumnIndex * this.columnWidth);
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

        if (fromColumnIndex == drawAlignedElliotAllListColumnEntryPriority) {
            return "ENTRY";
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
     * EMA200セルのオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getEmaCellObjectName(int fromRowIndex, int fromColumnIndex) {
        return this.objectPrefix
            + "Row_" + IntegerToString(fromRowIndex)
            + "_EmaColumn_" + IntegerToString(fromColumnIndex);
    }

    /**
     * Fibonacciセルのオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @param fromColumnIndex 列番号。
     * @return オブジェクト名。
     */
    string getFibonacciCellObjectName(int fromRowIndex, int fromColumnIndex) {
        return this.objectPrefix
            + "Row_" + IntegerToString(fromRowIndex)
            + "_FibonacciColumn_" + IntegerToString(fromColumnIndex);
    }

    /**
     * H1次点候補行のオブジェクト名を取得する。
     *
     * @param fromRowIndex 行番号。
     * @return オブジェクト名。
     */
    string getH1RunnerUpRowObjectName(int fromRowIndex) {
        return this.objectPrefix
            + "H1RunnerUpRow_" + IntegerToString(fromRowIndex);
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
        this.createdH1RunnerUpCount = 0;
        this.createdCurrentTimeFrame = PERIOD_CURRENT;
    }
};

#endif
