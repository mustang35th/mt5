//+------------------------------------------------------------------+
//|                                 DrawCurrencyStrengthList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_LIST_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 通貨別の相対強弱を順位付き一覧としてチャートへ描画する。
 */
class DrawCurrencyStrengthList {
public:
    /**
     * 描画対象チャートと表示位置を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート左端からの距離。
     * @param fromYDistance チャート上端からの距離。
     */
    DrawCurrencyStrengthList(
        long fromChartId = 0,
        int fromXDistance = 12,
        int fromYDistance = 12
    ) {
        this.chartId = fromChartId;
        string baseObjectPrefix = Constant::PREFIX_FIXED + "CurrencyStrengthList_";
        int instanceIndex = 0;
        this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";

        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0) {
            instanceIndex++;
            this.objectPrefix = baseObjectPrefix
                + IntegerToString(instanceIndex)
                + "_";
        }

        this.created = false;
        this.createdRowCount = 0;

        this.corner = CORNER_LEFT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.panelWidth = 1000;
        this.headerHeight = 25;
        this.columnHeaderYDistance = 39;
        this.separatorYDistance = 58;
        this.firstRowYDistance = 65;
        this.rowHeight = 19;
        this.bottomPadding = 36;

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
    ~DrawCurrencyStrengthList() {
        if (this.created) {
            this.destroyObjects();
        }
    }

    /**
     * 通貨強弱ランキングを描画する。
     *
     * @param fromCalculator 描画対象の集計結果。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthCalculator *fromCalculator) {
        if (fromCalculator == NULL) {
            return false;
        }

        int total = fromCalculator.size();

        if (total <= 0) {
            return false;
        }

        if (!this.created || this.createdRowCount != total) {
            if (!this.create(total, fromCalculator)) {
                return false;
            }
        }

        int displayOrder[];
        this.buildDisplayOrder(fromCalculator, displayOrder);
        this.updateTitle(fromCalculator);
        bool isRankingValid = fromCalculator.validPairCount
            == fromCalculator.getExpectedPairCount();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo =
                fromCalculator.getInfo(displayOrder[i]);
            this.drawRow(i, currencyStrengthInfo, isRankingValid);
        }

        this.updateSummary(fromCalculator);
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

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** チャート左端からの距離。 */
    int xDistance;

    /** チャート上端からの距離。 */
    int yDistance;

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

    /** フォント名。 */
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

    /** 強い方向の文字色。 */
    color buyColor;

    /** 弱い方向の文字色。 */
    color sellColor;

    /** 取得不足の文字色。 */
    color warningColor;

    /**
     * 指定行数の一覧パネルを生成する。
     *
     * @param fromRowCount 生成するデータ行数。
     * @param fromCalculator 列情報を取得する集計クラス。
     * @return 生成に成功した場合true。
     */
    bool create(
        int fromRowCount,
        CurrencyStrengthCalculator *fromCalculator
    ) {
        this.destroyObjects();

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
            "Elliot Currency Strength"
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
                this.getHeaderText(i, fromCalculator)
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

        for (int i = 0; i < fromRowCount; i++) {
            int rowYDistance = this.firstRowYDistance + (i * this.rowHeight);

            for (int j = 0; j < this.getColumnCount(); j++) {
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

        int summarySeparatorYDistance = this.firstRowYDistance
            + (fromRowCount * this.rowHeight)
            + 2;

        if (!this.createRectangle(
            this.objectPrefix + "SummarySeparator",
            this.xDistance + 12,
            this.yDistance + summarySeparatorYDistance,
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
            this.objectPrefix + "Summary",
            14,
            summarySeparatorYDistance + 7,
            this.bodyFontSize,
            this.normalColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        this.createdRowCount = fromRowCount;
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
     * 総合スコア降順の表示順を生成する。
     *
     * @param fromCalculator 集計結果。
     * @param fromDisplayOrder 表示順の格納先。
     */
    void buildDisplayOrder(
        CurrencyStrengthCalculator *fromCalculator,
        int &fromDisplayOrder[]
    ) {
        int total = fromCalculator.size();
        ArrayResize(fromDisplayOrder, total);

        for (int i = 0; i < total; i++) {
            fromDisplayOrder[i] = i;
        }

        if (fromCalculator.validPairCount
                < fromCalculator.getExpectedPairCount()) {
            return;
        }

        for (int i = 1; i < total; i++) {
            int currentIndex = fromDisplayOrder[i];
            CurrencyStrengthInfo *currentInfo = fromCalculator.getInfo(currentIndex);
            int j = i - 1;

            while (j >= 0) {
                CurrencyStrengthInfo *previousInfo =
                    fromCalculator.getInfo(fromDisplayOrder[j]);
                bool shouldShift = false;

                if (previousInfo == NULL || currentInfo == NULL) {
                    break;
                }

                int previousSampleCount = previousInfo.getTotalSampleCount();
                int currentSampleCount = currentInfo.getTotalSampleCount();

                if (previousSampleCount <= 0 && currentSampleCount > 0) {
                    shouldShift = true;
                } else if (previousSampleCount > 0 && currentSampleCount > 0
                        && previousInfo.getTotalScore() < currentInfo.getTotalScore()) {
                    shouldShift = true;
                }

                if (!shouldShift) {
                    break;
                }

                fromDisplayOrder[j + 1] = fromDisplayOrder[j];
                j--;
            }

            fromDisplayOrder[j + 1] = currentIndex;
        }
    }

    /**
     * 1通貨分の行を更新する。
     *
     * @param fromRowIndex 表示行番号。
     * @param fromCurrencyStrengthInfo 通貨別集計結果。
     * @param fromIsRankingValid 順位を表示できる場合true。
     */
    void drawRow(
        int fromRowIndex,
        CurrencyStrengthInfo *fromCurrencyStrengthInfo,
        bool fromIsRankingValid
    ) {
        if (fromCurrencyStrengthInfo == NULL) {
            for (int i = 0; i < this.getColumnCount(); i++) {
                this.setCell(fromRowIndex, i, "-", this.mutedColor);
            }

            return;
        }

        double totalScore = fromCurrencyStrengthInfo.getTotalScore();
        int coverage = fromCurrencyStrengthInfo.getSampleCount(0);
        string rankText = "-";

        if (fromIsRankingValid) {
            rankText = IntegerToString(fromRowIndex + 1);
        }

        this.setCell(fromRowIndex, 0, rankText, this.mutedColor);
        this.setCell(
            fromRowIndex,
            1,
            fromCurrencyStrengthInfo.currencyName,
            this.getScoreColor(totalScore)
        );

        for (int i = 0; i < 7; i++) {
            int sampleCount = fromCurrencyStrengthInfo.getSampleCount(i);
            double score = fromCurrencyStrengthInfo.getScore(i);
            this.setCell(
                fromRowIndex,
                i + 2,
                this.formatScore(score, sampleCount),
                this.getScoreColor(score)
            );
        }

        this.setCell(
            fromRowIndex,
            9,
            this.formatAverageScore(
                fromCurrencyStrengthInfo.getLongTermAverageScore(),
                coverage
            ),
            this.getScoreColor(
                fromCurrencyStrengthInfo.getLongTermAverageScore()
            )
        );
        this.setCell(
            fromRowIndex,
            10,
            this.formatAverageScore(
                fromCurrencyStrengthInfo.getLongMediumTermAverageScore(),
                coverage
            ),
            this.getScoreColor(
                fromCurrencyStrengthInfo.getLongMediumTermAverageScore()
            )
        );
        this.setCell(
            fromRowIndex,
            11,
            this.formatAverageScore(
                fromCurrencyStrengthInfo.getMediumTermAverageScore(),
                coverage
            ),
            this.getScoreColor(
                fromCurrencyStrengthInfo.getMediumTermAverageScore()
            )
        );
        this.setCell(
            fromRowIndex,
            12,
            this.formatAverageScore(
                fromCurrencyStrengthInfo.getMediumShortTermAverageScore(),
                coverage
            ),
            this.getScoreColor(
                fromCurrencyStrengthInfo.getMediumShortTermAverageScore()
            )
        );
        this.setCell(
            fromRowIndex,
            13,
            this.formatAverageScore(
                fromCurrencyStrengthInfo.getShortTermAverageScore(),
                coverage
            ),
            this.getScoreColor(
                fromCurrencyStrengthInfo.getShortTermAverageScore()
            )
        );
        this.setCell(
            fromRowIndex,
            14,
            this.formatScore(
                totalScore,
                fromCurrencyStrengthInfo.getTotalSampleCount()
            ),
            this.getScoreColor(totalScore)
        );

        color coverageColor = this.normalColor;

        if (coverage < 7) {
            coverageColor = this.warningColor;
        }

        this.setCell(
            fromRowIndex,
            15,
            IntegerToString(coverage),
            coverageColor
        );
    }

    /**
     * タイトルを更新する。
     *
     * @param fromCalculator 集計結果。
     */
    void updateTitle(CurrencyStrengthCalculator *fromCalculator) {
        datetime japanTime = TimeJapanUtil::getJapanTime(TimeCurrent());
        string titleText = StringFormat(
            "Elliot Currency Strength  PAIRS %d/%d  JST %s",
            fromCalculator.validPairCount,
            fromCalculator.getExpectedPairCount(),
            this.formatTitleTime(japanTime)
        );

        ObjectSetString(
            this.chartId,
            this.objectPrefix + "Title",
            OBJPROP_TEXT,
            titleText
        );
    }

    /**
     * 最強通貨、最弱通貨および売買候補を更新する。
     *
     * @param fromCalculator 集計結果。
     */
    void updateSummary(CurrencyStrengthCalculator *fromCalculator) {
        CurrencyStrengthInfo *strongest = fromCalculator.getStrongest();
        CurrencyStrengthInfo *weakest = fromCalculator.getWeakest();
        string summaryText = StringFormat(
            "WAITING DATA %d/%d",
            fromCalculator.validPairCount,
            fromCalculator.getExpectedPairCount()
        );
        color summaryColor = this.warningColor;

        if (fromCalculator.validPairCount == fromCalculator.getExpectedPairCount()
                && strongest != NULL
                && weakest != NULL) {
            double scoreDifference = MathAbs(
                strongest.getTotalScore() - weakest.getTotalScore()
            );

            if (scoreDifference < 0.1) {
                summaryText = "NO CLEAR STRENGTH";
            } else {
                summaryText = StringFormat(
                    "STRONG %s %s   WEAK %s %s   %s",
                    strongest.currencyName,
                    this.formatScore(strongest.getTotalScore(), strongest.getTotalSampleCount()),
                    weakest.currencyName,
                    this.formatScore(weakest.getTotalScore(), weakest.getTotalSampleCount()),
                    fromCalculator.getPairSignalText()
                );
                summaryColor = this.normalColor;
            }
        }

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
            summaryColor
        );
    }

    /**
     * セルの文字列と色を更新する。
     *
     * @param fromRowIndex 行番号。
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
     * スコアを符号付き文字列へ変換する。
     *
     * @param fromScore 強弱スコア。
     * @param fromSampleCount 有効票数。
     * @return 表示文字列。有効票がない場合はハイフン。
     */
    string formatScore(double fromScore, int fromSampleCount) {
        if (fromSampleCount <= 0) {
            return "-";
        }

        string scoreText = DoubleToString(fromScore, 0);

        if (fromScore > 0.0) {
            scoreText = "+" + scoreText;
        }

        return scoreText;
    }

    /**
     * 平均スコアを小数2桁の符号付き文字列へ変換する。
     *
     * @param fromScore 平均スコア。
     * @param fromSampleCount 有効票数。
     * @return 表示文字列。有効票がない場合はハイフン。
     */
    string formatAverageScore(double fromScore, int fromSampleCount) {
        if (fromSampleCount <= 0) {
            return "-";
        }

        string scoreText = DoubleToString(fromScore, 2);

        if (fromScore > 0.0) {
            scoreText = "+" + scoreText;
        }

        return scoreText;
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
     * スコアに対応する文字色を取得する。
     *
     * @param fromScore 強弱スコア。
     * @return 文字色。
     */
    color getScoreColor(double fromScore) {
        if (fromScore > 0.0) {
            return this.buyColor;
        }

        if (fromScore < 0.0) {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * 全列数を取得する。
     *
     * @return 全列数。
     */
    int getColumnCount() {
        return 16;
    }

    /**
     * 列の左位置を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @return パネル左端からの位置。
     */
    int getColumnLeftOffset(int fromColumnIndex) {
        switch (fromColumnIndex) {
            case 0:
                return 14;
            case 1:
                return 42;
            case 2:
                return 96;
            case 3:
                return 154;
            case 4:
                return 212;
            case 5:
                return 270;
            case 6:
                return 328;
            case 7:
                return 386;
            case 8:
                return 444;
            case 9:
                return 508;
            case 10:
                return 570;
            case 11:
                return 660;
            case 12:
                return 718;
            case 13:
                return 818;
            case 14:
                return 884;
            case 15:
                return 960;
        }

        return 14;
    }

    /**
     * 列ヘッダー文字列を取得する。
     *
     * @param fromColumnIndex 列番号。
     * @param fromCalculator 時間足情報を取得する集計クラス。
     * @return 列ヘッダー文字列。
     */
    string getHeaderText(
        int fromColumnIndex,
        CurrencyStrengthCalculator *fromCalculator
    ) {
        if (fromColumnIndex == 0) {
            return "#";
        }

        if (fromColumnIndex == 1) {
            return "CCY";
        }

        if (2 <= fromColumnIndex && fromColumnIndex <= 8) {
            return TimeUtil::convertTimeFrameToString(
                fromCalculator.getTimeFrame(fromColumnIndex - 2)
            );
        }

        if (fromColumnIndex == 9) {
            return "LONG";
        }

        if (fromColumnIndex == 10) {
            return "LONG-MID";
        }

        if (fromColumnIndex == 11) {
            return "MID";
        }

        if (fromColumnIndex == 12) {
            return "MID-SHORT";
        }

        if (fromColumnIndex == 13) {
            return "SHORT";
        }

        if (fromColumnIndex == 14) {
            return "TOTAL";
        }

        if (fromColumnIndex == 15) {
            return "N";
        }

        return "";
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
    }
};

#endif
