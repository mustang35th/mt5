//+------------------------------------------------------------------+
//|                      DrawCurrencyStrengthAllLatestRankLabels.mqh |
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
#include <Mstng\Draw\ChartRedrawRequest.mqh>

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
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は従来どおり再描画する。
     */
    DrawCurrencyStrengthAllLatestRankLabels(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
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
     * 固定設定は作成時に行い、更新時は通貨ごとに変更された位置・文字だけを反映する。
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

        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        for (int i = 0; i < 8; i++) {
            bool rankChanged = this.lastRanks[i] != fromRanks[i];
            bool positionChanged = this.lastLabelTimes[i] != fromLabelTimes[i] || rankChanged;

            if (this.created && this.lastSubWindow == fromSubWindow && !positionChanged) {
                continue;
            }

            if (!this.drawLabel(
                this.objectNames[i],
                fromSubWindow,
                fromLabelTimes[i],
                this.currencyNames[i],
                fromRanks[i],
                positionChanged,
                rankChanged
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

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

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

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。 */
    ChartRedrawRequest *redrawRequest;

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
     * 1通貨分の最新順位ラベルへ変更項目だけを反映する。初期化時はすべて設定する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromLabelTime ラベルを配置する時刻。
     * @param fromCurrency 表示する通貨名。
     * @param fromRank 表示する順位。
     * @param fromPositionChanged 時刻または順位位置が変わった場合true。
     * @param fromTextChanged 順位が変わった場合true。
     * @return 描画に成功した場合true。
     */
    bool drawLabel(
        const string fromObjectName,
        const int fromSubWindow,
        const datetime fromLabelTime,
        const string fromCurrency,
        const int fromRank,
        const bool fromPositionChanged,
        const bool fromTextChanged
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

        if (initializeProperties && !this.configureObject(
            fromObjectName,
            ConstantCurrency::getColor(fromCurrency)
        )) {
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

        if ((initializeProperties || fromTextChanged) && !ObjectSetString(
            this.chartId,
            fromObjectName,
            OBJPROP_TEXT,
            StringFormat("%d:%s", fromRank, fromCurrency)
        )) {
            return false;
        }

        return true;
    }

    /**
     * 最新順位ラベルの通貨色と固定表示設定を作成時に適用する。
     *
     * @param fromObjectName 設定対象のオブジェクト名。
     * @param fromColor 通貨の文字色。
     * @return すべての設定に成功した場合true。
     */
    bool configureObject(const string fromObjectName, const color fromColor) {
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
            OBJPROP_COLOR,
            fromColor
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
     * 全通貨の最新順位ラベルを削除する。
     */
    void deleteObjects() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

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
