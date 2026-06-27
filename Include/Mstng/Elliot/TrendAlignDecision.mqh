//+------------------------------------------------------------------+
//|                                           TrendAlignDecision.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef TREND_ALIGN_DECISION_MQH
#define TREND_ALIGN_DECISION_MQH

#include <Mstng\Elliot\Elliot.mqh>

/**
 * トレンド一致種別
 */
enum TrendAlignType
{
    trendAlignNone = 0,  // 不一致
    trendAlignBuy = 1,   // BUY一致
    trendAlignSell = -1  // SELL一致
};


/**
 * 複数時間足トレンド一致判定
 */
class TrendAlignDecision {
public:
    /** D1/H4/H1/M15一致判定 */
    TrendAlignType trendAlignD1H4H1M15;

    /** D1/H4/H1一致判定 */
    TrendAlignType trendAlignD1H4H1;

    /** H4/H1/M15一致判定 */
    TrendAlignType trendAlignH4H1M15;

    /** H4/H1一致判定 */
    TrendAlignType trendAlignH4H1;

    /** H1/M15一致判定 */
    TrendAlignType trendAlignH1M15;

    /** D1/H4/H1/M15一致ラベル */
    string trendAlignD1H4H1M15Label;

    /** D1/H4/H1一致ラベル */
    string trendAlignD1H4H1Label;

    /** H4/H1/M15一致ラベル */
    string trendAlignH4H1M15Label;

    /** H4/H1一致ラベル */
    string trendAlignH4H1Label;

    /** H1/M15一致ラベル */
    string trendAlignH1M15Label;

    /**
     * コンストラクタ
     */
    TrendAlignDecision() {
        // 初期化
        this.clear();
    }

    /**
     * 初期化
     */
    void clear() {
        // 判定初期化
        this.trendAlignD1H4H1M15 = trendAlignNone;
        this.trendAlignD1H4H1 = trendAlignNone;
        this.trendAlignH4H1M15 = trendAlignNone;
        this.trendAlignH4H1 = trendAlignNone;
        this.trendAlignH1M15 = trendAlignNone;

        // ラベル初期化
        this.trendAlignD1H4H1M15Label = "NONE";
        this.trendAlignD1H4H1Label = "NONE";
        this.trendAlignH4H1M15Label = "NONE";
        this.trendAlignH4H1Label = "NONE";
        this.trendAlignH1M15Label = "NONE";
    }

    /**
     * エリオットからトレンド一致判定を設定
     *
     * @param d1ElliotValue D1エリオット
     * @param h4ElliotValue H4エリオット
     * @param h1ElliotValue H1エリオット
     * @param m15ElliotValue M15エリオット
     */
    void setData(
        Elliot *d1ElliotValue,
        Elliot *h4ElliotValue,
        Elliot *h1ElliotValue,
        Elliot *m15ElliotValue
    ) {
        // 初期化
        this.clear();

        // 一致判定
        this.trendAlignD1H4H1M15 = this.getAlignType4(
            d1ElliotValue,
            h4ElliotValue,
            h1ElliotValue,
            m15ElliotValue
        );

        this.trendAlignD1H4H1 = this.getAlignType3(
            d1ElliotValue,
            h4ElliotValue,
            h1ElliotValue
        );

        this.trendAlignH4H1M15 = this.getAlignType3(
            h4ElliotValue,
            h1ElliotValue,
            m15ElliotValue
        );

        this.trendAlignH4H1 = this.getAlignType2(h4ElliotValue, h1ElliotValue);

        this.trendAlignH1M15 = this.getAlignType2(h1ElliotValue, m15ElliotValue);

        // ラベル設定
        this.trendAlignD1H4H1M15Label = TrendAlignDecision::toString(this.trendAlignD1H4H1M15);
        this.trendAlignD1H4H1Label = TrendAlignDecision::toString(this.trendAlignD1H4H1);
        this.trendAlignH4H1M15Label = TrendAlignDecision::toString(this.trendAlignH4H1M15);
        this.trendAlignH4H1Label = TrendAlignDecision::toString(this.trendAlignH4H1);
        this.trendAlignH1M15Label = TrendAlignDecision::toString(this.trendAlignH1M15);
    }

    /**
     * D1/H4/H1/M15一致文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getD1H4H1M15Text() {
        return this.trendAlignD1H4H1M15Label;
    }

    /**
     * D1/H4/H1一致文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getD1H4H1Text() {
        return this.trendAlignD1H4H1Label;
    }

    /**
     * H4/H1/M15一致文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getH4H1M15Text() {
        return this.trendAlignH4H1M15Label;
    }

    /**
     * H4/H1一致文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getH4H1Text() {
        return this.trendAlignH4H1Label;
    }

    /**
     * H1/M15一致文字列を取得
     *
     * @return BUY / SELL / NONE
     */
    string getH1M15Text() {
        return this.trendAlignH1M15Label;
    }

    /**
     * D1/H4/H1/M15がBUY一致か判定
     *
     * @return true: BUY一致
     */
    bool isD1H4H1M15Buy() {
        return this.trendAlignD1H4H1M15 == trendAlignBuy;
    }

    /**
     * D1/H4/H1/M15がSELL一致か判定
     *
     * @return true: SELL一致
     */
    bool isD1H4H1M15Sell() {
        return this.trendAlignD1H4H1M15 == trendAlignSell;
    }

    /**
     * D1/H4/H1がBUY一致か判定
     *
     * @return true: BUY一致
     */
    bool isD1H4H1Buy() {
        return this.trendAlignD1H4H1 == trendAlignBuy;
    }

    /**
     * D1/H4/H1がSELL一致か判定
     *
     * @return true: SELL一致
     */
    bool isD1H4H1Sell() {
        return this.trendAlignD1H4H1 == trendAlignSell;
    }

    /**
     * H4/H1/M15がBUY一致か判定
     *
     * @return true: BUY一致
     */
    bool isH4H1M15Buy() {
        return this.trendAlignH4H1M15 == trendAlignBuy;
    }

    /**
     * H4/H1/M15がSELL一致か判定
     *
     * @return true: SELL一致
     */
    bool isH4H1M15Sell() {
        return this.trendAlignH4H1M15 == trendAlignSell;
    }

    /**
     * H4/H1がBUY一致か判定
     *
     * @return true: BUY一致
     */
    bool isH4H1Buy() {
        return this.trendAlignH4H1 == trendAlignBuy;
    }

    /**
     * H4/H1がSELL一致か判定
     *
     * @return true: SELL一致
     */
    bool isH4H1Sell() {
        return this.trendAlignH4H1 == trendAlignSell;
    }

    /**
     * H1/M15がBUY一致か判定
     *
     * @return true: BUY一致
     */
    bool isH1M15Buy() {
        return this.trendAlignH1M15 == trendAlignBuy;
    }

    /**
     * H1/M15がSELL一致か判定
     *
     * @return true: SELL一致
     */
    bool isH1M15Sell() {
        return this.trendAlignH1M15 == trendAlignSell;
    }

    /**
     * CSVヘッダーを取得
     *
     * @return CSVヘッダー
     */
    static string getCsvHeader() {
        return "TrendAlign_D1_H4_H1_M15"
            + ",TrendAlign_D1_H4_H1"
            + ",TrendAlign_H4_H1_M15"
            + ",TrendAlign_H4_H1"
            + ",TrendAlign_H1_M15";
    }

    /**
     * CSVデータを取得
     *
     * @return CSVデータ
     */
    string getCsvData() {
        return this.trendAlignD1H4H1M15Label
            + "," + this.trendAlignD1H4H1Label
            + "," + this.trendAlignH4H1M15Label
            + "," + this.trendAlignH4H1Label
            + "," + this.trendAlignH1M15Label;
    }

    /**
     * トレンド一致種別を文字列へ変換
     *
     * @param trendAlignTypeValue トレンド一致種別
     * @return BUY / SELL / NONE
     */
    static string toString(const TrendAlignType trendAlignTypeValue) {
        if (trendAlignTypeValue == trendAlignBuy) {
            return "BUY";
        }

        if (trendAlignTypeValue == trendAlignSell) {
            return "SELL";
        }

        return "NONE";
    }

private:
    /**
     * 2時間足の一致種別を取得
     *
     * @param elliot1Value エリオット1
     * @param elliot2Value エリオット2
     * @return トレンド一致種別
     */
    TrendAlignType getAlignType2(Elliot *elliot1Value, Elliot *elliot2Value) {
        if (
            this.isBuyTrend(elliot1Value)
            && this.isBuyTrend(elliot2Value)
        ) {
            return trendAlignBuy;
        }

        if (
            this.isSellTrend(elliot1Value)
            && this.isSellTrend(elliot2Value)
        ) {
            return trendAlignSell;
        }

        return trendAlignNone;
    }

    /**
     * 3時間足の一致種別を取得
     *
     * @param elliot1Value エリオット1
     * @param elliot2Value エリオット2
     * @param elliot3Value エリオット3
     * @return トレンド一致種別
     */
    TrendAlignType getAlignType3(
        Elliot *elliot1Value,
        Elliot *elliot2Value,
        Elliot *elliot3Value
    ) {
        if (
            this.isBuyTrend(elliot1Value)
            && this.isBuyTrend(elliot2Value)
            && this.isBuyTrend(elliot3Value)
        ) {
            return trendAlignBuy;
        }

        if (
            this.isSellTrend(elliot1Value)
            && this.isSellTrend(elliot2Value)
            && this.isSellTrend(elliot3Value)
        ) {
            return trendAlignSell;
        }

        return trendAlignNone;
    }

    /**
     * 4時間足の一致種別を取得
     *
     * @param elliot1Value エリオット1
     * @param elliot2Value エリオット2
     * @param elliot3Value エリオット3
     * @param elliot4Value エリオット4
     * @return トレンド一致種別
     */
    TrendAlignType getAlignType4(
        Elliot *elliot1Value,
        Elliot *elliot2Value,
        Elliot *elliot3Value,
        Elliot *elliot4Value
    ) {
        if (
            this.isBuyTrend(elliot1Value)
            && this.isBuyTrend(elliot2Value)
            && this.isBuyTrend(elliot3Value)
            && this.isBuyTrend(elliot4Value)
        ) {
            return trendAlignBuy;
        }

        if (
            this.isSellTrend(elliot1Value)
            && this.isSellTrend(elliot2Value)
            && this.isSellTrend(elliot3Value)
            && this.isSellTrend(elliot4Value)
        ) {
            return trendAlignSell;
        }

        return trendAlignNone;
    }

    /**
     * BUYトレンドか判定
     *
     * @param elliotValue エリオット
     * @return true: BUYトレンド
     */
    bool isBuyTrend(Elliot *elliotValue) {
        if (!this.hasLatestWave(elliotValue)) {
            return false;
        }

        return elliotValue.isUptrend();
    }

    /**
     * SELLトレンドか判定
     *
     * @param elliotValue エリオット
     * @return true: SELLトレンド
     */
    bool isSellTrend(Elliot *elliotValue) {
        if (!this.hasLatestWave(elliotValue)) {
            return false;
        }

        if (elliotValue.isUptrend()) {
            return false;
        }

        return true;
    }

    /**
     * 最新波動を持つか判定
     *
     * @param elliotValue エリオット
     * @return true: 最新波動あり
     */
    bool hasLatestWave(Elliot *elliotValue) {
        if (elliotValue == NULL) {
            return false;
        }

        if (elliotValue.getLatestWave() == NULL) {
            return false;
        }

        return true;
    }
};

#endif
