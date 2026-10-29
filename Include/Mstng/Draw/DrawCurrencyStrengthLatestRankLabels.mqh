//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthLatestRankLabels.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

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
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は従来どおり即時に要求する。
     */
    DrawCurrencyStrengthLatestRankLabels(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
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
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastBaseColor = clrNONE;
        this.lastQuoteColor = clrNONE;
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthLatestRankLabels() {
        this.deleteObjects();
    }

    /**
     * 最新順位を順位線の右側へ描画する。
     * 固定表示設定は作成時に行い、更新時は通貨ごとに変更された位置・文字・色だけを反映する。
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
                && this.lastQuoteRank == fromQuoteRank
                && this.lastBaseCurrency == fromBaseCurrency
                && this.lastQuoteCurrency == fromQuoteCurrency
                && this.lastBaseColor == fromBaseColor
                && this.lastQuoteColor == fromQuoteColor) {
            return true;
        }

        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        if (!this.drawLabel(
            this.baseObjectName,
            fromSubWindow,
            fromBaseLabelTime,
            fromBaseCurrency,
            fromBaseRank,
            fromBaseColor,
            this.lastBaseLabelTime != fromBaseLabelTime || this.lastBaseRank != fromBaseRank,
            this.lastBaseRank != fromBaseRank || this.lastBaseCurrency != fromBaseCurrency,
            this.lastBaseColor != fromBaseColor
        ) || !this.drawLabel(
            this.quoteObjectName,
            fromSubWindow,
            fromQuoteLabelTime,
            fromQuoteCurrency,
            fromQuoteRank,
            fromQuoteColor,
            this.lastQuoteLabelTime != fromQuoteLabelTime || this.lastQuoteRank != fromQuoteRank,
            this.lastQuoteRank != fromQuoteRank || this.lastQuoteCurrency != fromQuoteCurrency,
            this.lastQuoteColor != fromQuoteColor
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
        this.lastBaseCurrency = fromBaseCurrency;
        this.lastQuoteCurrency = fromQuoteCurrency;
        this.lastBaseColor = fromBaseColor;
        this.lastQuoteColor = fromQuoteColor;

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

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

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。NULLの場合は即時要求。 */
    ChartRedrawRequest *redrawRequest;

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

    /** 前回描画した基軸通貨名。 */
    string lastBaseCurrency;

    /** 前回描画した決済通貨名。 */
    string lastQuoteCurrency;

    /** 前回描画した基軸通貨の文字色。 */
    color lastBaseColor;

    /** 前回描画した決済通貨の文字色。 */
    color lastQuoteColor;

    /**
     * 1通貨分の最新順位ラベルへ変更項目だけを反映する。初期化時はすべて設定する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTime ラベルを配置する時刻。
     * @param fromCurrency 表示する通貨名。
     * @param fromRank 表示する順位。
     * @param fromColor 文字色。
     * @param fromPositionChanged 時刻または順位位置が変わった場合true。
     * @param fromTextChanged 順位または通貨名が変わった場合true。
     * @param fromColorChanged 文字色が変わった場合true。
     * @return 描画に成功した場合true。
     */
    bool drawLabel(
        const string fromObjectName,
        const int fromSubWindow,
        const datetime fromLabelTime,
        const string fromCurrency,
        const int fromRank,
        const color fromColor,
        const bool fromPositionChanged,
        const bool fromTextChanged,
        const bool fromColorChanged
    ) {
        int objectWindow = ObjectFind(this.chartId, fromObjectName);

        if (objectWindow >= 0 && objectWindow != fromSubWindow) {
            if (!ObjectDelete(this.chartId, fromObjectName)) {
                return false;
            }

            objectWindow = -1;
        }

        bool initializeProperties = objectWindow < 0 || !this.created
            || this.lastSubWindow != fromSubWindow;
        double position = (double)(0 - fromRank);

        if (objectWindow < 0
                && !ObjectCreate(
            this.chartId,
            fromObjectName,
            OBJ_TEXT,
            fromSubWindow,
            fromLabelTime,
            position
        )) {
            return false;
        }

        if (initializeProperties && !this.configureObject(fromObjectName)) {
            return false;
        }

        if ((initializeProperties || fromPositionChanged) && !ObjectMove(
            this.chartId,
            fromObjectName,
            0,
            fromLabelTime,
            position
        )) {
            return false;
        }

        bool configured = true;

        if (initializeProperties || fromColorChanged) {
            configured = ObjectSetInteger(
                this.chartId,
                fromObjectName,
                OBJPROP_COLOR,
                fromColor
            );
        }

        if (initializeProperties || fromTextChanged) {
            configured = ObjectSetString(
                this.chartId,
                fromObjectName,
                OBJPROP_TEXT,
                StringFormat("%d:%s", fromRank, fromCurrency)
            ) && configured;
        }

        return configured;
    }

    /**
     * 最新順位ラベルの固定表示設定を作成時に適用する。
     *
     * @param fromObjectName 設定対象のオブジェクト名。
     * @return すべての設定に成功した場合true。
     */
    bool configureObject(const string fromObjectName) {
        bool configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_ANCHOR,
            ANCHOR_LEFT
        );
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_FONTSIZE,
            9
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_BACK,
            false
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_SELECTABLE,
            false
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_SELECTED,
            false
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_HIDDEN,
            true
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_ZORDER,
            2
        ) && configured;
        configured = ObjectSetString(
            this.chartId,
            fromObjectName,
            OBJPROP_FONT,
            "MS Gothic"
        ) && configured;

        return configured;
    }

    /**
     * 最新順位ラベルのオブジェクトを削除する。
     */
    void deleteObjects() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        ObjectDelete(this.chartId, this.baseObjectName);
        ObjectDelete(this.chartId, this.quoteObjectName);
        this.created = false;
        this.lastSubWindow = -1;
        this.lastBaseLabelTime = 0;
        this.lastQuoteLabelTime = 0;
        this.lastBaseRank = 0;
        this.lastQuoteRank = 0;
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastBaseColor = clrNONE;
        this.lastQuoteColor = clrNONE;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_LATEST_RANK_LABELS_MQH
