//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthPairRank.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>

/**
 * 表示中の通貨ペアに対応する通貨強弱順位をチャート右中央へ描画する。
 */
class DrawCurrencyStrengthPairRank {
public:
    /**
     * 描画対象チャートを指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート右端からの距離。
     */
    DrawCurrencyStrengthPairRank(long fromChartId = 0, int fromXDistance = 48) {
        this.chartId = fromChartId;
        this.objectPrefix = Constant::PREFIX_FIXED + "CurrencyStrengthPairRank_";
        this.created = false;
        this.hasRankData = false;
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;
        this.corner = CORNER_RIGHT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = 0;
        this.panelWidth = 244;
        this.panelHeight = 246;
        this.rankTopOffset = 69;
        this.rankRowHeight = 19;
        this.fontName = "MS Gothic";
        this.titleFontSize = 15;
        this.bodyFontSize = 15;
        this.headerColor = C'180,180,180';
        this.mutedColor = C'130,130,130';
        this.buyColor = clrDeepSkyBlue;
        this.sellColor = clrHotPink;
        this.warningColor = clrGold;
        this.errorColor = clrTomato;
        this.rankGridColor = C'45,45,45';
        this.rankGridBoundaryColor = C'90,90,90';
        this.calculateYDistance();
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawCurrencyStrengthPairRank() {
        this.destroyObjects();
    }

    /**
     * 表示中の通貨ペアに対応する順位を描画する。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthExecutionInfo &fromInfo) {
        if (!fromInfo.isAvailable()) {
            return this.drawUnavailable(
                fromInfo.pairRankInfo.baseCurrency,
                fromInfo.pairRankInfo.quoteCurrency
            );
        }

        if (!this.ensureCreated()) {
            return false;
        }

        CurrencyStrengthPairRankInfo pairRankInfo = fromInfo.pairRankInfo;
        int longMediumDifference = fromInfo.getLongMediumRankDifference();
        int mediumShortDifference = fromInfo.getMediumShortRankDifference();

        this.updateSourceBadge(fromInfo.sourceMode);
        this.updateDecision(longMediumDifference, mediumShortDifference);
        this.setLabelText(
            "LongMediumSignal",
            this.formatSignal(longMediumDifference),
            this.getSignalColor(longMediumDifference)
        );
        this.setLabelText(
            "MediumShortSignal",
            this.formatSignal(mediumShortDifference),
            this.getSignalColor(mediumShortDifference)
        );
        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            42,
            pairRankInfo.baseCurrency,
            pairRankInfo.baseLongMediumTermAverageRank,
            pairRankInfo.quoteCurrency,
            pairRankInfo.quoteLongMediumTermAverageRank
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            164,
            pairRankInfo.baseCurrency,
            pairRankInfo.baseMediumShortTermAverageRank,
            pairRankInfo.quoteCurrency,
            pairRankInfo.quoteMediumShortTermAverageRank
        );

        string m5BarTimeText = this.formatM5BarTime(pairRankInfo);

        this.setLabelText("M5BarTime", "M5 " + m5BarTimeText, this.mutedColor);

        if (fromInfo.targetM5BarTime > 0
                && pairRankInfo.m5BarTime != fromInfo.targetM5BarTime) {
            this.setLabelText("StateBadge", "STALE", this.warningColor);
        } else {
            this.setLabelText("StateBadge", " ", this.mutedColor);
        }

        this.hasRankData = true;
        this.lastExecutionInfo = fromInfo;
        this.lastBaseCurrency = pairRankInfo.baseCurrency;
        this.lastQuoteCurrency = pairRankInfo.quoteCurrency;
        this.lastDisplayAvailable = true;
        this.lastDisplayError = false;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 従来形式の順位情報を描画する。
     *
     * @param fromInfo 通貨ペア順位情報。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthPairRankInfo &fromInfo) {
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo.reset();
        executionInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
        executionInfo.targetM5BarTime = fromInfo.m5BarTime;
        executionInfo.sourceMode = "-";
        executionInfo.pairRankInfo = fromInfo;

        return this.draw(executionInfo);
    }

    /**
     * 順位を取得できない状態のパネルを描画する。
     *
     * @param fromBaseCurrency 基軸通貨名。
     * @param fromQuoteCurrency 決済通貨名。
     * @return 描画に成功した場合true。
     */
    bool drawUnavailable(string fromBaseCurrency, string fromQuoteCurrency) {
        if (!this.ensureCreated()) {
            return false;
        }

        this.setLabelText("SourceBadge", "-", this.mutedColor);
        this.setLabelText("Decision", "NO DATA", this.mutedColor);
        this.setLabelText("StateBadge", " ", this.mutedColor);
        this.setLabelText("LongMediumSignal", "-", this.mutedColor);
        this.setLabelText("MediumShortSignal", "-", this.mutedColor);
        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            42,
            fromBaseCurrency,
            0,
            fromQuoteCurrency,
            0
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            164,
            fromBaseCurrency,
            0,
            fromQuoteCurrency,
            0
        );
        this.setLabelText("M5BarTime", "M5 -", this.mutedColor);
        this.hasRankData = false;
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = fromBaseCurrency;
        this.lastQuoteCurrency = fromQuoteCurrency;
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 取得エラーを表示し、直前の順位表示を維持する。
     *
     * @return 描画に成功した場合true。
     */
    bool drawError() {
        if (!this.ensureCreated()) {
            return false;
        }

        string errorText = "ERROR";

        if (this.hasRankData) {
            errorText = "ERR 前回値";
        }

        this.setLabelText("StateBadge", errorText, this.errorColor);
        this.lastDisplayError = true;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 最終表示内容を再生成し、他のチャート描画より前面へ戻す。
     *
     * @return 再描画に成功した場合true。
     */
    bool redrawOnTop() {
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo = this.lastExecutionInfo;
        string baseCurrency = this.lastBaseCurrency;
        string quoteCurrency = this.lastQuoteCurrency;
        bool displayAvailable = this.lastDisplayAvailable;
        bool displayError = this.lastDisplayError;

        this.destroyObjects();

        bool isSuccess = false;

        if (displayAvailable) {
            isSuccess = this.draw(executionInfo);
        } else {
            isSuccess = this.drawUnavailable(baseCurrency, quoteCurrency);
        }

        if (!isSuccess) {
            return false;
        }

        if (displayError) {
            return this.drawError();
        }

        return true;
    }

    /**
     * 現在のチャート高さに合わせてパネルを右中央へ再配置する。
     */
    void reposition() {
        this.calculateYDistance();

        if (!this.created) {
            return;
        }

        this.repositionRankGrid();
        this.setLabelPosition("Decision", 70, 5);
        this.setLabelPosition("StateBadge", 132, 6);
        this.setLabelPosition("SourceBadge", 192, 6);
        this.setLabelPosition("LongMediumHeader", 47, 28);
        this.setLabelPosition("MediumShortHeader", 168, 28);
        this.setLabelPosition("LongMediumSignal", 45, 47);
        this.setLabelPosition("MediumShortSignal", 166, 47);
        this.repositionRankColumns();
        this.setLabelPosition(
            "M5BarTime",
            this.getM5BarTimeLeftOffset(),
            this.getM5BarTimeTopOffset()
        );
        ChartRedraw(this.chartId);
    }

    /**
     * 順位パネル専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 順位パネル専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル生成済みの場合true。 */
    bool created;

    /** 直前の有効な順位を表示中の場合true。 */
    bool hasRankData;

    /** 最後に表示した実行時通貨強弱情報。 */
    CurrencyStrengthExecutionInfo lastExecutionInfo;

    /** 最後に表示した基軸通貨コード。 */
    string lastBaseCurrency;

    /** 最後に表示した決済通貨コード。 */
    string lastQuoteCurrency;

    /** 最後の表示が有効な順位の場合true。 */
    bool lastDisplayAvailable;

    /** 最後の表示に取得エラーを重ねている場合true。 */
    bool lastDisplayError;

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** チャート右端からの距離。 */
    int xDistance;

    /** チャート上端からの距離。 */
    int yDistance;

    /** パネル幅。 */
    int panelWidth;

    /** パネル高さ。 */
    int panelHeight;

    /** 1位を表示するパネル上端からの位置。 */
    int rankTopOffset;

    /** 順位1段分の高さ。 */
    int rankRowHeight;

    /** 表示フォント名。 */
    string fontName;

    /** タイトル文字サイズ。 */
    int titleFontSize;

    /** 本文文字サイズ。 */
    int bodyFontSize;

    /** 列ヘッダー文字色。 */
    color headerColor;

    /** 補助文字色。 */
    color mutedColor;

    /** 買い方向文字色。 */
    color buyColor;

    /** 売り方向文字色。 */
    color sellColor;

    /** 警告文字色。 */
    color warningColor;

    /** エラー文字色。 */
    color errorColor;

    /** 順位行の罫線色。 */
    color rankGridColor;

    /** 順位領域境界と中央線の色。 */
    color rankGridBoundaryColor;

    /**
     * 必要に応じて順位パネルを生成する。
     *
     * @return パネルを使用できる場合true。
     */
    bool ensureCreated() {
        if (this.created) {
            return true;
        }

        return this.create();
    }

    /**
     * 順位パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();
        this.calculateYDistance();

        if (!this.createRankGrid()) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "SourceBadge",
            192,
            6,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "Decision",
            70,
            5,
            this.titleFontSize,
            this.mutedColor,
            "NO DATA"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "StateBadge",
            132,
            6,
            this.bodyFontSize,
            this.mutedColor,
            " "
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "LongMediumHeader",
            47,
            28,
            this.bodyFontSize,
            this.headerColor,
            "長中期"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "MediumShortHeader",
            168,
            28,
            this.bodyFontSize,
            this.headerColor,
            "中短期"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "LongMediumSignal",
            45,
            47,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "MediumShortSignal",
            166,
            47,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "BaseLongMediumRank",
            42,
            this.rankTopOffset,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "BaseMediumShortRank",
            164,
            this.rankTopOffset,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "QuoteLongMediumRank",
            42,
            this.rankTopOffset + this.rankRowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "QuoteMediumShortRank",
            164,
            this.rankTopOffset + this.rankRowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "M5BarTime",
            this.getM5BarTimeLeftOffset(),
            this.getM5BarTimeTopOffset(),
            this.bodyFontSize,
            this.mutedColor,
            "M5 -"
        )) {
            this.destroyObjects();

            return false;
        }

        this.created = true;

        return true;
    }

    /**
     * 8順位の横罫線と期間列の中央縦線を生成する。
     *
     * 外枠は生成せず、罫線をパネル左右端より内側へ収める。
     *
     * @return 生成に成功した場合true。
     */
    bool createRankGrid() {
        int gridTopOffset = this.getRankGridTopOffset();
        int horizontalRightOffset = 10;
        int horizontalWidth = this.panelWidth - 20;

        for (int i = 0; i <= 8; i++) {
            color lineColor = this.rankGridColor;

            if (i == 0 || i == 8) {
                lineColor = this.rankGridBoundaryColor;
            }

            if (!this.createRankGridLine(
                "RankGridHorizontal" + IntegerToString(i),
                horizontalRightOffset,
                gridTopOffset + i * this.rankRowHeight,
                horizontalWidth,
                1,
                lineColor
            )) {
                return false;
            }
        }

        int centerTopOffset = 27;
        int gridBottomOffset = gridTopOffset + 8 * this.rankRowHeight;

        return this.createRankGridLine(
            "RankGridCenter",
            this.panelWidth / 2,
            centerTopOffset,
            1,
            gridBottomOffset - centerTopOffset + 1,
            this.rankGridBoundaryColor
        );
    }

    /**
     * 順位罫線用の矩形ラベルを生成する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromRightOffset パネル右端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromWidth 横幅。
     * @param fromHeight 高さ。
     * @param fromColor 罫線色。
     * @return 生成に成功した場合true。
     */
    bool createRankGridLine(
        string fromNameSuffix,
        int fromRightOffset,
        int fromTopOffset,
        int fromWidth,
        int fromHeight,
        color fromColor
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        if (!ObjectCreate(
            this.chartId,
            objectName,
            OBJ_RECTANGLE_LABEL,
            0,
            0,
            0
        )) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        this.setRankGridLinePosition(
            fromNameSuffix,
            fromRightOffset,
            fromTopOffset,
            fromWidth
        );
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 1);

        return true;
    }

    /**
     * 保存済みの罫線を現在のパネル位置へ再配置する。
     */
    void repositionRankGrid() {
        int gridTopOffset = this.getRankGridTopOffset();

        for (int i = 0; i <= 8; i++) {
            this.setRankGridLinePosition(
                "RankGridHorizontal" + IntegerToString(i),
                10,
                gridTopOffset + i * this.rankRowHeight,
                this.panelWidth - 20
            );
        }

        this.setRankGridLinePosition(
            "RankGridCenter",
            this.panelWidth / 2,
            27,
            1
        );
    }

    /**
     * 順位領域の上端位置を取得する。
     *
     * @return パネル上端からのY位置。
     */
    int getRankGridTopOffset() {
        return this.rankTopOffset - 3;
    }

    /**
     * 罫線を右上基準の固定座標へ配置する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromRightOffset パネル右端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromWidth 罫線の横幅。
     */
    void setRankGridLinePosition(
        string fromNameSuffix,
        int fromRightOffset,
        int fromTopOffset,
        int fromWidth
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_XDISTANCE,
            this.xDistance + fromRightOffset + fromWidth
        );
        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
    }

    /**
     * 実際に採用されたDB取得元を表示する。
     *
     * @param fromSourceMode LIVEまたはTESTER。
     */
    void updateSourceBadge(const string fromSourceMode) {
        string sourceMode = fromSourceMode;
        StringToUpper(sourceMode);

        if (sourceMode == "LIVE") {
            this.setLabelText("SourceBadge", "LIVE", clrLime);

            return;
        }

        if (sourceMode == "TESTER") {
            this.setLabelText("SourceBadge", "TESTER", this.warningColor);

            return;
        }

        if (sourceMode == "") {
            sourceMode = "-";
        }

        this.setLabelText("SourceBadge", sourceMode, this.mutedColor);
    }

    /**
     * 長中期と中短期の方向一致状態を表示する。
     *
     * @param fromLongMediumDifference 長中期順位差。
     * @param fromMediumShortDifference 中短期順位差。
     */
    void updateDecision(
        const int fromLongMediumDifference,
        const int fromMediumShortDifference
    ) {
        if (fromLongMediumDifference > 0 && fromMediumShortDifference > 0) {
            this.setLabelText("Decision", "BUY一致", this.buyColor);

            return;
        }

        if (fromLongMediumDifference < 0 && fromMediumShortDifference < 0) {
            this.setLabelText("Decision", "SELL一致", this.sellColor);

            return;
        }

        this.setLabelText("Decision", "MIXED", this.warningColor);
    }

    /**
     * 順位差を売買方向表示へ変換する。
     *
     * @param fromDifference 決済通貨順位から基軸通貨順位を引いた値。
     * @return BUY、SELLまたはFLATと順位差。
     */
    string formatSignal(const int fromDifference) {
        if (fromDifference > 0) {
            return StringFormat("BUY +%d", fromDifference);
        }

        if (fromDifference < 0) {
            return StringFormat("SELL %d", fromDifference);
        }

        return "FLAT 0";
    }

    /**
     * 順位差に対応する文字色を取得する。
     *
     * @param fromDifference 順位差。
     * @return 売買方向に対応する文字色。
     */
    color getSignalColor(const int fromDifference) {
        if (fromDifference > 0) {
            return this.buyColor;
        }

        if (fromDifference < 0) {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * 期間列内の2通貨を実際の順位位置へ表示する。
     *
     * @param fromBaseLabelName 基軸通貨ラベル名。
     * @param fromQuoteLabelName 決済通貨ラベル名。
     * @param fromColumnLeftOffset 通常時の列内X位置。
     * @param fromBaseCurrency 基軸通貨コード。
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteCurrency 決済通貨コード。
     * @param fromQuoteRank 決済通貨順位。
     */
    void updateRankColumn(
        const string fromBaseLabelName,
        const string fromQuoteLabelName,
        const int fromColumnLeftOffset,
        const string fromBaseCurrency,
        const int fromBaseRank,
        const string fromQuoteCurrency,
        const int fromQuoteRank
    ) {
        this.setLabelText(
            fromBaseLabelName,
            this.formatRankEntry(fromBaseCurrency, fromBaseRank),
            ConstantCurrency::getColor(fromBaseCurrency)
        );
        this.setLabelText(
            fromQuoteLabelName,
            this.formatRankEntry(fromQuoteCurrency, fromQuoteRank),
            ConstantCurrency::getColor(fromQuoteCurrency)
        );

        this.positionRankColumn(
            fromBaseLabelName,
            fromQuoteLabelName,
            fromColumnLeftOffset,
            fromBaseRank,
            fromQuoteRank
        );
    }

    /**
     * 期間列内の2通貨を順位に対応する座標へ配置する。
     *
     * @param fromBaseLabelName 基軸通貨ラベル名。
     * @param fromQuoteLabelName 決済通貨ラベル名。
     * @param fromColumnLeftOffset 通常時の列内X位置。
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteRank 決済通貨順位。
     */
    void positionRankColumn(
        const string fromBaseLabelName,
        const string fromQuoteLabelName,
        const int fromColumnLeftOffset,
        const int fromBaseRank,
        const int fromQuoteRank
    ) {
        bool baseRankValid = this.isValidRank(fromBaseRank);
        bool quoteRankValid = this.isValidRank(fromQuoteRank);
        int baseLeftOffset = fromColumnLeftOffset;
        int quoteLeftOffset = fromColumnLeftOffset;
        int baseTopOffset = this.rankTopOffset;
        int quoteTopOffset = this.rankTopOffset + this.rankRowHeight;

        if (baseRankValid) {
            baseTopOffset = this.getRankTopOffset(fromBaseRank);
        }

        if (quoteRankValid) {
            quoteTopOffset = this.getRankTopOffset(fromQuoteRank);
        }

        if (baseRankValid
                && quoteRankValid
                && fromBaseRank == fromQuoteRank) {
            baseLeftOffset = fromColumnLeftOffset - 34;
            quoteLeftOffset = fromColumnLeftOffset + 26;
        }

        this.setLabelPosition(
            fromBaseLabelName,
            baseLeftOffset,
            baseTopOffset
        );
        this.setLabelPosition(
            fromQuoteLabelName,
            quoteLeftOffset,
            quoteTopOffset
        );
    }

    /**
     * 保存済み順位を使用して2期間の順位列を再配置する。
     */
    void repositionRankColumns() {
        if (this.lastDisplayAvailable) {
            CurrencyStrengthPairRankInfo pairRankInfo =
                this.lastExecutionInfo.pairRankInfo;

            this.updateRankColumn(
                "BaseLongMediumRank",
                "QuoteLongMediumRank",
                42,
                pairRankInfo.baseCurrency,
                pairRankInfo.baseLongMediumTermAverageRank,
                pairRankInfo.quoteCurrency,
                pairRankInfo.quoteLongMediumTermAverageRank
            );
            this.updateRankColumn(
                "BaseMediumShortRank",
                "QuoteMediumShortRank",
                164,
                pairRankInfo.baseCurrency,
                pairRankInfo.baseMediumShortTermAverageRank,
                pairRankInfo.quoteCurrency,
                pairRankInfo.quoteMediumShortTermAverageRank
            );

            return;
        }

        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            42,
            this.lastBaseCurrency,
            0,
            this.lastQuoteCurrency,
            0
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            164,
            this.lastBaseCurrency,
            0,
            this.lastQuoteCurrency,
            0
        );
    }

    /**
     * 指定順位のパネル上端からの位置を取得する。
     *
     * @param fromRank 1位から8位。
     * @return 順位に対応するY位置。
     */
    int getRankTopOffset(const int fromRank) {
        return this.rankTopOffset + (fromRank - 1) * this.rankRowHeight;
    }

    /**
     * M5時刻のパネル上端からの位置を取得する。
     *
     * @return M5時刻のY位置。
     */
    int getM5BarTimeTopOffset() {
        return this.rankTopOffset + 8 * this.rankRowHeight + 3;
    }

    /**
     * M5時刻のパネル左端からの位置を取得する。
     *
     * @return M5時刻のX位置。
     */
    int getM5BarTimeLeftOffset() {
        return 8 + this.bodyFontSize * 2;
    }

    /**
     * 表示可能な通貨順位か判定する。
     *
     * @param fromRank 通貨順位。
     * @return 1位から8位の場合true。
     */
    bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }

    /**
     * 通貨コードと順位をコンパクトな表示文字列へ変換する。
     *
     * @param fromCurrency 通貨コード。
     * @param fromRank 順位。
     * @return 通貨コードと順位。未取得順位の場合はハイフン。
     */
    string formatRankEntry(const string fromCurrency, const int fromRank) {
        string currency = fromCurrency;

        if (currency == "") {
            currency = "-";
        }

        if (!this.isValidRank(fromRank)) {
            return currency + " -";
        }

        return currency + " " + IntegerToString(fromRank) + "位";
    }

    /**
     * M5バー時刻を短い表示文字列へ変換する。
     *
     * @param fromInfo 通貨ペア順位情報。
     * @return 月日と時分。未取得の場合はハイフン。
     */
    string formatM5BarTime(CurrencyStrengthPairRankInfo &fromInfo) {
        if (fromInfo.m5BarTime <= 0) {
            return "-";
        }

        MqlDateTime barDateTime;
        TimeToStruct(fromInfo.m5BarTime, barDateTime);

        return StringFormat(
            "%02d.%02d %02d:%02d",
            barDateTime.mon,
            barDateTime.day,
            barDateTime.hour,
            barDateTime.min
        );
    }

    /**
     * 固定位置ラベルを生成する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromFontSize フォントサイズ。
     * @param fromColor 文字色。
     * @param fromText 表示文字列。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset,
        int fromFontSize,
        color fromColor,
        string fromText
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        this.setLabelPosition(fromNameSuffix, fromLeftOffset, fromTopOffset);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * チャート高さから右中央より少し下のY位置を計算する。
     */
    void calculateYDistance() {
        int chartHeight = (int)ChartGetInteger(
            this.chartId,
            CHART_HEIGHT_IN_PIXELS,
            0
        );
        int verticalOffset = 20 + this.rankRowHeight * 3;
        this.yDistance = (chartHeight - this.panelHeight) / 2
            + verticalOffset;

        if (this.yDistance < 0) {
            this.yDistance = 0;
        }
    }

    /**
     * 文字ラベルをパネル基準位置へ配置する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     */
    void setLabelPosition(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;
        int labelXDistance = this.xDistance + this.panelWidth - fromLeftOffset;

        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, labelXDistance);
        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
    }

    /**
     * ラベル文字列と文字色を更新する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setLabelText(
        string fromNameSuffix,
        string fromText,
        color fromColor
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * 順位パネル専用オブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.hasRankData = false;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH
