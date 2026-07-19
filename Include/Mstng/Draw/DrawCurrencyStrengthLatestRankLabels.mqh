//+------------------------------------------------------------------+
//|               DrawCurrencyStrengthLatestRankLabels.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH

#include <Mstng\Constant\Constant.mqh>

/**
 * 通貨強弱順位線の最新値ラベルを描画する。
 */
class DrawCurrencyStrengthLatestRankLabels {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     */
    DrawCurrencyStrengthLatestRankLabels(
        const long fromChartId,
        const string fromObjectSuffix
    ) {
        this.chartId = fromChartId;
        this.baseObjectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthLatestBase_"
            + fromObjectSuffix;
        this.quoteObjectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthLatestQuote_"
            + fromObjectSuffix;
        this.created = false;
        this.lastSubWindow = -1;
        this.lastBaseLabelTime = 0;
        this.lastQuoteLabelTime = 0;
        this.lastBaseRank = 0;
        this.lastQuoteRank = 0;
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthLatestRankLabels() {
        this.clear();
    }

    /**
     * 最新順位を順位線の右側へ描画する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromBaseLabelTime 基軸通貨ラベルを配置する時刻。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromBaseRank 基軸通貨の順位。
     * @param fromBaseColor 基軸通貨の線色。
     * @param fromQuoteLabelTime 決済通貨ラベルを配置する時刻。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromQuoteRank 決済通貨の順位。
     * @param fromQuoteColor 決済通貨の線色。
     * @return 描画に成功した場合true。
     */
    bool draw(
        const int fromSubWindow,
        const datetime fromBaseLabelTime,
        const string fromBaseCurrency,
        const int fromBaseRank,
        const color fromBaseColor,
        const datetime fromQuoteLabelTime,
        const string fromQuoteCurrency,
        const int fromQuoteRank,
        const color fromQuoteColor
    ) {
        if (fromSubWindow <= 0
                || fromBaseLabelTime <= 0
                || fromBaseCurrency == ""
                || fromBaseRank < 1
                || fromBaseRank > 8
                || fromQuoteLabelTime <= 0
                || fromQuoteCurrency == ""
                || fromQuoteRank < 1
                || fromQuoteRank > 8) {
            this.clear();

            return true;
        }

        if (this.created
                && this.lastSubWindow == fromSubWindow
                && this.lastBaseLabelTime == fromBaseLabelTime
                && this.lastQuoteLabelTime == fromQuoteLabelTime
                && this.lastBaseRank == fromBaseRank
                && this.lastQuoteRank == fromQuoteRank) {
            return true;
        }

        double basePosition = (double)(0 - fromBaseRank);
        double quotePosition = (double)(0 - fromQuoteRank);

        if (!this.drawLabel(
            this.baseObjectName,
            fromSubWindow,
            fromBaseLabelTime,
            basePosition,
            StringFormat("%d:%s", fromBaseRank, fromBaseCurrency),
            fromBaseColor
        ) || !this.drawLabel(
            this.quoteObjectName,
            fromSubWindow,
            fromQuoteLabelTime,
            quotePosition,
            StringFormat("%d:%s", fromQuoteRank, fromQuoteCurrency),
            fromQuoteColor
        )) {
            this.deleteObjects();

            return false;
        }

        this.created = true;
        this.lastSubWindow = fromSubWindow;
        this.lastBaseLabelTime = fromBaseLabelTime;
        this.lastQuoteLabelTime = fromQuoteLabelTime;
        this.lastBaseRank = fromBaseRank;
        this.lastQuoteRank = fromQuoteRank;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 最新順位ラベルを削除する。
     */
    void clear() {
        if (!this.created) {
            return;
        }

        this.deleteObjects();
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 基軸通貨ラベルのオブジェクト名。 */
    string baseObjectName;

    /** 決済通貨ラベルのオブジェクト名。 */
    string quoteObjectName;

    /** ラベル生成済みの場合true。 */
    bool created;

    /** 前回描画したサブウィンドウ番号。 */
    int lastSubWindow;

    /** 前回描画した基軸通貨ラベル時刻。 */
    datetime lastBaseLabelTime;

    /** 前回描画した決済通貨ラベル時刻。 */
    datetime lastQuoteLabelTime;

    /** 前回描画した基軸通貨順位。 */
    int lastBaseRank;

    /** 前回描画した決済通貨順位。 */
    int lastQuoteRank;

    /**
     * 1通貨分の最新順位ラベルを描画する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTime ラベルを配置する時刻。
     * @param fromPosition ラベルを配置する順位位置。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     * @return 描画に成功した場合true。
     */
    bool drawLabel(
        const string fromObjectName,
        const int fromSubWindow,
        const datetime fromLabelTime,
        const double fromPosition,
        const string fromText,
        const color fromColor
    ) {
        int objectWindow = ObjectFind(this.chartId, fromObjectName);

        if (objectWindow >= 0 && objectWindow != fromSubWindow) {
            ObjectDelete(this.chartId, fromObjectName);
            objectWindow = -1;
        }

        if (objectWindow < 0
                && !ObjectCreate(
            this.chartId,
            fromObjectName,
            OBJ_TEXT,
            fromSubWindow,
            fromLabelTime,
            fromPosition
        )) {
            return false;
        }

        if (!ObjectMove(
            this.chartId,
            fromObjectName,
            0,
            fromLabelTime,
            fromPosition
        )) {
            return false;
        }

        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_ANCHOR,
            ANCHOR_LEFT
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_FONTSIZE,
            9
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_COLOR,
            fromColor
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_BACK,
            false
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_SELECTABLE,
            false
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_SELECTED,
            false
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_HIDDEN,
            true
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_ZORDER,
            2
        );
        ObjectSetString(
            this.chartId,
            fromObjectName,
            OBJPROP_FONT,
            "MS Gothic"
        );
        ObjectSetString(
            this.chartId,
            fromObjectName,
            OBJPROP_TEXT,
            fromText
        );

        return true;
    }

    /**
     * 最新順位ラベルのオブジェクトを削除する。
     */
    void deleteObjects() {
        ObjectDelete(this.chartId, this.baseObjectName);
        ObjectDelete(this.chartId, this.quoteObjectName);
        this.created = false;
        this.lastSubWindow = -1;
        this.lastBaseLabelTime = 0;
        this.lastQuoteLabelTime = 0;
        this.lastBaseRank = 0;
        this.lastQuoteRank = 0;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH
