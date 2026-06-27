//+------------------------------------------------------------------+
//|                            HigherStochasticMainOrderDecision.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef HIGHER_STOCHASTIC_MAIN_ORDER_DECISION_MQH
#define HIGHER_STOCHASTIC_MAIN_ORDER_DECISION_MQH

#include <Mstng\Elliot\Elliot.mqh>

/**
 * 上位足ストキャスMain0並び順多数決判定
 */
class HigherStochasticMainOrderDecision {
public:
    /** 売買判定済み */
    bool isDetermined;

    /** BUY判定 */
    bool isBuy;

    /** 売買ラベル */
    string buySellLabel;

    /** BUY数 */
    int buyCount;

    /** SELL数 */
    int sellCount;

    /** NONE数 */
    int noneCount;

    /**
     * コンストラクタ
     */
    HigherStochasticMainOrderDecision() {
        // 初期化
        this.clear();
    }

    /**
     * 初期化
     */
    void clear() {
        // 判定結果初期化
        this.isDetermined = false;
        this.isBuy = false;
        this.buySellLabel = "NONE";

        // 集計値初期化
        this.buyCount = 0;
        this.sellCount = 0;
        this.noneCount = 0;
    }

    /**
     * 上位足エリオットから多数決判定を設定
     *
     * @param d1ElliotValue D1エリオット
     * @param h4ElliotValue H4エリオット
     * @param h1ElliotValue H1エリオット
     */
    void setData(
        Elliot *d1ElliotValue,
        Elliot *h4ElliotValue,
        Elliot *h1ElliotValue
    ) {
        // 初期化
        this.clear();

        // 上位足集計
        this.addElliot(d1ElliotValue);
        this.addElliot(h4ElliotValue);
        this.addElliot(h1ElliotValue);

        // 多数決判定
        this.setDecision();
    }

    /**
     * 売買文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getBuySellText() {
        return this.buySellLabel;
    }

    /**
     * 集計文字列を取得
     *
     * @return 集計文字列
     */
    string getSummaryText() {
        return StringFormat(
            "%s(BUY=%d SELL=%d NONE=%d)",
            this.buySellLabel,
            this.buyCount,
            this.sellCount,
            this.noneCount
        );
    }

    /**
     * CSVヘッダーを取得
     *
     * @return CSVヘッダー
     */
    static string getCsvHeader() {
        return "HigherStochasticMainOrderBuySell"
            + ",HigherStochasticMainOrderBuyCount"
            + ",HigherStochasticMainOrderSellCount"
            + ",HigherStochasticMainOrderNoneCount";
    }

    /**
     * CSVデータを取得
     *
     * @return CSVデータ
     */
    string getCsvData() {
        return this.buySellLabel
            + "," + IntegerToString(this.buyCount)
            + "," + IntegerToString(this.sellCount)
            + "," + IntegerToString(this.noneCount);
    }

private:
    /**
     * エリオットのストキャスMain0並び順を集計
     *
     * @param elliotValue エリオット
     */
    void addElliot(Elliot *elliotValue) {
        // 未取得
        if (elliotValue == NULL) {
            this.noneCount++;

            return;
        }

        // BUY加算
        if (elliotValue.oscillator.isBuyStochasticMainOrder()) {
            this.buyCount++;

            return;
        }

        // SELL加算
        if (elliotValue.oscillator.isSellStochasticMainOrder()) {
            this.sellCount++;

            return;
        }

        this.noneCount++;
    }

    /**
     * 多数決判定を設定
     */
    void setDecision() {
        // BUY多数決
        if (this.buyCount >= 2) {
            this.isDetermined = true;
            this.isBuy = true;
            this.buySellLabel = "BUY";

            return;
        }

        // SELL多数決
        if (this.sellCount >= 2) {
            this.isDetermined = true;
            this.isBuy = false;
            this.buySellLabel = "SELL";

            return;
        }

        this.isDetermined = false;
        this.isBuy = false;
        this.buySellLabel = "NONE";
    }
};

#endif
