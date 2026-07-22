//+------------------------------------------------------------------+
//|         DrawCurrencyStrengthAllLatestRankLabels.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_ALL_LATEST_RANK_LABELS_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_ALL_LATEST_RANK_LABELS_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>

/**
 * 全通貨の通貨強弱順位線へ最新値ラベルを描画する。
 */
class DrawCurrencyStrengthAllLatestRankLabels {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     */
    DrawCurrencyStrengthAllLatestRankLabels(
        const long fromChartId,
        const string fromObjectSuffix
    ) {
        this.chartId = fromChartId;
        this.currencyNames[0] = ConstantCurrency::USD;
        this.currencyNames[1] = ConstantCurrency::JPY;
        this.currencyNames[2] = ConstantCurrency::EUR;
        this.currencyNames[3] = ConstantCurrency::GBP;
        this.currencyNames[4] = ConstantCurrency::AUD;
        this.currencyNames[5] = ConstantCurrency::NZD;
        this.currencyNames[6] = ConstantCurrency::CAD;
        this.currencyNames[7] = ConstantCurrency::CHF;

        for (int i = 0; i < 8; i++) {
            this.objectNames[i] = Constant::PREFIX_FIXED
                + "CurrencyStrengthAllLatest_"
                + this.currencyNames[i]
                + "_"
                + fromObjectSuffix;
        }

        this.resetCache();
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthAllLatestRankLabels() {
        this.deleteObjects();
    }

    /**
     * 全通貨の最新順位を順位線の右側へ描画する。
     *
     * 配列の通貨順はUSD、JPY、EUR、GBP、AUD、NZD、CAD、CHFとする。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTimes 各通貨のラベルを配置する時刻。
     * @param fromRanks 各通貨の順位。
     * @return 描画に成功した場合true。
     */
    bool draw(
        const int fromSubWindow,
        const datetime &fromLabelTimes[],
        const int &fromRanks[]
    ) {
        if (!this.isValid(fromSubWindow, fromLabelTimes, fromRanks)) {
            this.clear();

            return true;
        }

        if (this.isSameValues(fromSubWindow, fromLabelTimes, fromRanks)) {
            return true;
        }

        for (int i = 0; i < 8; i++) {
            double position = (double)(0 - fromRanks[i]);

            if (!this.drawLabel(
                this.objectNames[i],
                fromSubWindow,
                fromLabelTimes[i],
                position,
                StringFormat("%d:%s", fromRanks[i], this.currencyNames[i]),
                ConstantCurrency::getColor(this.currencyNames[i])
            )) {
                this.deleteObjects();

                return false;
            }
        }

        this.created = true;
        this.lastSubWindow = fromSubWindow;

        for (int i = 0; i < 8; i++) {
            this.lastLabelTimes[i] = fromLabelTimes[i];
            this.lastRanks[i] = fromRanks[i];
        }

        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 全通貨の最新順位ラベルを削除する。
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

    /** 通貨コード配列。 */
    string currencyNames[8];

    /** 最新順位ラベルのオブジェクト名配列。 */
    string objectNames[8];

    /** ラベル生成済みの場合true。 */
    bool created;

    /** 前回描画したサブウィンドウ番号。 */
    int lastSubWindow;

    /** 前回描画したラベル時刻配列。 */
    datetime lastLabelTimes[8];

    /** 前回描画した順位配列。 */
    int lastRanks[8];

    /**
     * 描画引数が有効か判定する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTimes 各通貨のラベルを配置する時刻。
     * @param fromRanks 各通貨の順位。
     * @return 有効な場合true。
     */
    bool isValid(
        const int fromSubWindow,
        const datetime &fromLabelTimes[],
        const int &fromRanks[]
    ) {
        if (fromSubWindow <= 0
                || ArraySize(fromLabelTimes) < 8
                || ArraySize(fromRanks) < 8) {
            return false;
        }

        for (int i = 0; i < 8; i++) {
            if (fromLabelTimes[i] <= 0
                    || fromRanks[i] < 1
                    || fromRanks[i] > 8) {
                return false;
            }
        }

        return true;
    }

    /**
     * 前回描画時と同じ値か判定する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTimes 各通貨のラベルを配置する時刻。
     * @param fromRanks 各通貨の順位。
     * @return 同じ値の場合true。
     */
    bool isSameValues(
        const int fromSubWindow,
        const datetime &fromLabelTimes[],
        const int &fromRanks[]
    ) {
        if (!this.created || this.lastSubWindow != fromSubWindow) {
            return false;
        }

        for (int i = 0; i < 8; i++) {
            if (this.lastLabelTimes[i] != fromLabelTimes[i]
                    || this.lastRanks[i] != fromRanks[i]) {
                return false;
            }
        }

        return true;
    }

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
     * 全通貨の最新順位ラベルを削除する。
     */
    void deleteObjects() {
        for (int i = 0; i < 8; i++) {
            ObjectDelete(this.chartId, this.objectNames[i]);
        }

        this.resetCache();
    }

    /**
     * 前回描画値を初期化する。
     */
    void resetCache() {
        this.created = false;
        this.lastSubWindow = -1;

        for (int i = 0; i < 8; i++) {
            this.lastLabelTimes[i] = 0;
            this.lastRanks[i] = 0;
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_ALL_LATEST_RANK_LABELS_MQH
