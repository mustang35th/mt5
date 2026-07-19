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
    DrawCurrencyStrengthPairRank(long fromChartId = 0, int fromXDistance = 12) {
        this.chartId = fromChartId;
        this.objectPrefix = Constant::PREFIX_FIXED + "CurrencyStrengthPairRank_";
        this.created = false;
        this.corner = CORNER_RIGHT_UPPER;
        this.xDistance = fromXDistance;
        this.yDistance = 0;
        this.panelWidth = 254;
        this.panelHeight = 124;
        this.fontName = "MS Gothic";
        this.titleFontSize = 10;
        this.bodyFontSize = 9;
        this.panelBackgroundColor = C'18,18,18';
        this.headerBackgroundColor = C'56,74,104';
        this.borderColor = clrDimGray;
        this.titleColor = clrWhite;
        this.headerColor = C'180,180,180';
        this.normalColor = clrWhiteSmoke;
        this.rankColor = clrGold;
        this.mutedColor = C'130,130,130';
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
     * @param fromInfo 順位表示情報。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthPairRankInfo &fromInfo) {
        if (!this.ensureCreated()) {
            return false;
        }

        this.setLabelText("BaseCurrency", fromInfo.baseCurrency, this.normalColor);
        this.setLabelText(
            "BaseLongMediumRank",
            this.formatRank(fromInfo.baseLongMediumTermAverageRank),
            this.getRankColor(fromInfo.baseLongMediumTermAverageRank)
        );
        this.setLabelText(
            "BaseMediumShortRank",
            this.formatRank(fromInfo.baseMediumShortTermAverageRank),
            this.getRankColor(fromInfo.baseMediumShortTermAverageRank)
        );
        this.setLabelText("QuoteCurrency", fromInfo.quoteCurrency, this.normalColor);
        this.setLabelText(
            "QuoteLongMediumRank",
            this.formatRank(fromInfo.quoteLongMediumTermAverageRank),
            this.getRankColor(fromInfo.quoteLongMediumTermAverageRank)
        );
        this.setLabelText(
            "QuoteMediumShortRank",
            this.formatRank(fromInfo.quoteMediumShortTermAverageRank),
            this.getRankColor(fromInfo.quoteMediumShortTermAverageRank)
        );

        string m5BarTimeText = fromInfo.m5BarTimeText;

        if (m5BarTimeText == "" && fromInfo.m5BarTime > 0) {
            m5BarTimeText = TimeToString(
                fromInfo.m5BarTime,
                TIME_DATE | TIME_MINUTES
            );
        }

        if (m5BarTimeText == "") {
            m5BarTimeText = "-";
        }

        this.setLabelText("M5BarTime", "M5 " + m5BarTimeText, this.mutedColor);
        ChartRedraw(this.chartId);

        return true;
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

        this.setLabelText("BaseCurrency", fromBaseCurrency, this.normalColor);
        this.setLabelText("BaseLongMediumRank", "-", this.mutedColor);
        this.setLabelText("BaseMediumShortRank", "-", this.mutedColor);
        this.setLabelText("QuoteCurrency", fromQuoteCurrency, this.normalColor);
        this.setLabelText("QuoteLongMediumRank", "-", this.mutedColor);
        this.setLabelText("QuoteMediumShortRank", "-", this.mutedColor);
        this.setLabelText("M5BarTime", "M5 -", this.mutedColor);
        ChartRedraw(this.chartId);

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

        this.setRectanglePosition("Panel", 0, 0);
        this.setRectanglePosition("TitleBackground", 1, 1);
        this.setRectanglePosition("HeaderSeparator", 12, 53);
        this.setRectanglePosition("FooterSeparator", 12, 99);
        this.setLabelPosition("Title", 14, 5);
        this.setLabelPosition("LongMediumHeader", 91, 34);
        this.setLabelPosition("MediumShortHeader", 171, 34);
        this.setLabelPosition("BaseCurrency", 14, 59);
        this.setLabelPosition("BaseLongMediumRank", 109, 59);
        this.setLabelPosition("BaseMediumShortRank", 189, 59);
        this.setLabelPosition("QuoteCurrency", 14, 78);
        this.setLabelPosition("QuoteLongMediumRank", 109, 78);
        this.setLabelPosition("QuoteMediumShortRank", 189, 78);
        this.setLabelPosition("M5BarTime", 14, 104);
        ChartRedraw(this.chartId);
    }

    /**
     * 順位パネル専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 順位パネル専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル生成済みの場合true。 */
    bool created;

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

    /** 順位文字色。 */
    color rankColor;

    /** 補助文字色。 */
    color mutedColor;

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

        if (!this.createRectangle(
            "Panel",
            0,
            0,
            this.panelWidth,
            this.panelHeight,
            this.panelBackgroundColor,
            this.borderColor,
            0
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createRectangle(
            "TitleBackground",
            1,
            1,
            this.panelWidth - 2,
            25,
            this.headerBackgroundColor,
            this.headerBackgroundColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "Title",
            14,
            5,
            this.titleFontSize,
            this.titleColor,
            "通貨強弱 Rank"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "LongMediumHeader",
            91,
            34,
            this.bodyFontSize,
            this.headerColor,
            "長中期"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "MediumShortHeader",
            171,
            34,
            this.bodyFontSize,
            this.headerColor,
            "中短期"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createRectangle(
            "HeaderSeparator",
            12,
            53,
            this.panelWidth - 24,
            1,
            this.borderColor,
            this.borderColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createDataLabels()) {
            this.destroyObjects();

            return false;
        }

        if (!this.createRectangle(
            "FooterSeparator",
            12,
            99,
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
            "M5BarTime",
            14,
            104,
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
     * 通貨別順位の表示ラベルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool createDataLabels() {
        if (!this.createLabel(
            "BaseCurrency",
            14,
            59,
            this.bodyFontSize,
            this.normalColor,
            "-"
        )) {
            return false;
        }

        if (!this.createLabel(
            "BaseLongMediumRank",
            109,
            59,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            return false;
        }

        if (!this.createLabel(
            "BaseMediumShortRank",
            189,
            59,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            return false;
        }

        if (!this.createLabel(
            "QuoteCurrency",
            14,
            78,
            this.bodyFontSize,
            this.normalColor,
            "-"
        )) {
            return false;
        }

        if (!this.createLabel(
            "QuoteLongMediumRank",
            109,
            78,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        )) {
            return false;
        }

        return this.createLabel(
            "QuoteMediumShortRank",
            189,
            78,
            this.bodyFontSize,
            this.mutedColor,
            "-"
        );
    }

    /**
     * 矩形ラベルを生成する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromWidth 横幅。
     * @param fromHeight 高さ。
     * @param fromBackgroundColor 背景色。
     * @param fromBorderColor 枠線色。
     * @param fromZOrder Zオーダー。
     * @return 生成に成功した場合true。
     */
    bool createRectangle(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset,
        int fromWidth,
        int fromHeight,
        color fromBackgroundColor,
        color fromBorderColor,
        int fromZOrder
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        if (!ObjectCreate(this.chartId, objectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        this.setRectanglePosition(fromNameSuffix, fromLeftOffset, fromTopOffset);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromBackgroundColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromBorderColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, fromZOrder);

        return true;
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
     * チャート高さから右中央のY位置を計算する。
     */
    void calculateYDistance() {
        int chartHeight = (int)ChartGetInteger(
            this.chartId,
            CHART_HEIGHT_IN_PIXELS,
            0
        );
        this.yDistance = (chartHeight - this.panelHeight) / 2;

        if (this.yDistance < 0) {
            this.yDistance = 0;
        }
    }

    /**
     * 矩形ラベルをパネル基準位置へ配置する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     */
    void setRectanglePosition(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;
        int rectangleXDistance = this.xDistance + fromLeftOffset;

        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, rectangleXDistance);
        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
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
     * 順位を表示文字列へ変換する。
     *
     * @param fromRank 順位。
     * @return 正の順位、または未取得を表すハイフン。
     */
    string formatRank(int fromRank) {
        if (fromRank <= 0) {
            return "-";
        }

        return IntegerToString(fromRank);
    }

    /**
     * 順位状態に対応する文字色を取得する。
     *
     * @param fromRank 順位。
     * @return 取得済み順位色、または未取得色。
     */
    color getRankColor(int fromRank) {
        if (fromRank <= 0) {
            return this.mutedColor;
        }

        return this.rankColor;
    }

    /**
     * 順位パネル専用オブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH
