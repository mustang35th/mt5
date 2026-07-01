//+------------------------------------------------------------------+
//|                                                    TodayRate.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Util\PipConverter.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * 現在のBid・Ask・スプレッドおよび当日の日足高値・安値を管理するクラス。
 */
class TodayRate {
public:
    /** 取得対象の市場コンテキスト */
    MarketContext marketContext;

    /** 現在のAsk価格 */
    double ask;

    /** 現在のBid価格 */
    double bid;

    /** スプレッド（pips） */
    double spread;

    /** 当日の日足高値 */
    double high;

    /** 当日の日足安値 */
    double low;

    /** 当日の日足高値・安値の差（pips） */
    int diff;

    /** 当日値幅を円換算した値 */
    int diffJpy;
    
    /** Ask表示文字列 */
    string askLabel;

    /** Bid表示文字列 */
    string bidLabel;

    /** スプレッド表示文字列 */
    string spreadLabel;

    /** 日足高値表示文字列 */
    string highLabel;

    /** 日足安値表示文字列 */
    string lowLabel;

    /** 日足値幅表示文字列 */
    string diffLabel;

    /** 円換算値幅表示文字列 */
    string diffJpyLabel;

    /**
     * デフォルトコンストラクタ。
     */
    TodayRate() {
    }
    
    /**
     * シンボル名を指定して現在値と当日値幅を取得する。
     *
     * @param fromSymbolName 取得対象のシンボル名
     */
    TodayRate(string fromSymbolName) {
        this.ask = 0.0;
        this.bid = 0.0;
        this.spread = 0.0;

        this.high = 0.0;
        this.low = 0.0;
        this.diff = 0;
        this.diffJpy = 0;

        this.askLabel = "";
        this.bidLabel = "";
        this.spreadLabel = "";

        this.highLabel = "";
        this.lowLabel = "";
        this.diffLabel = "";
        this.diffJpyLabel = "";

        this.update(fromSymbolName);
    }

    /**
     * デストラクタ。
     */
    ~TodayRate() {
    }

    /**
     * 市場コンテキストを使用して最新値を取得する。
     *
     * 日足高値・安値は、コンテキストの時間足にかかわらずPERIOD_D1から取得する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     */
    void update(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
        this.updateValues();
    }

    /**
     * シンボル名を使用して最新値を再取得する。
     *
     * @param fromSymbolName 取得対象のシンボル名
     */
    void update(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_D1);

        this.update(context);
    }

    /**
     * 保持している価格情報を文字列化する。
     *
     * @return 価格情報文字列
     */
    string toString() {
        string text = "";

        text += "\n";
        text += "    symbolName=" + this.marketContext.symbolName + "\n";

        text += "    ask=" + this.askLabel + "\n";
        text += "    bid=" + this.bidLabel + "\n";
        text += "    spread=" + this.spreadLabel + "\n";

        text += "    high=" + this.highLabel + "\n";
        text += "    low=" + this.lowLabel + "\n";
        text += "    diff=" + this.diffLabel + "\n";

        return text;
    }

private:
    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }

    /**
     * 保持している市場コンテキストを使用して最新値とラベルを更新する。
     */
    void updateValues() {
        // シンボルが未選択の場合に備える
        SymbolSelect(this.marketContext.symbolName, true);

        int digits = this.marketContext.digits;

        // Ask/Bid
        double askLocal = 0.0;
        double bidLocal = 0.0;

        if (SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_ASK, askLocal)) {
            this.ask = askLocal;
        }

        if (SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_BID, bidLocal)) {
            this.bid = bidLocal;
        }

        // Spread（pips）
        this.spread = RateUtil::getDiffPips(this.bid, this.ask, this.marketContext);

        // D1 高値/安値（当日バー：shift=0）
        this.high = iHigh(this.marketContext.symbolName, PERIOD_D1, 0);
        this.low  = iLow(this.marketContext.symbolName, PERIOD_D1, 0);

        // Diff（pips、int）
        double diffPips = RateUtil::getDiffPips(this.low, this.high, this.marketContext);
        this.diff = (int)MathRound(diffPips);
        
        
        if (!this.marketContext.isJpy()) {
            double jpyAmount = 0.0;
    
            if (PipConverter::tryConvertPipsToJpy(this.marketContext, this.diff, 100, jpyAmount)) {
                this.diffJpy = (int)MathRound(jpyAmount);
            }
        }
        

        // ラベル作成
        this.askLabel = DoubleToString(this.ask, digits);
        this.bidLabel = DoubleToString(this.bid, digits);
        this.spreadLabel = DoubleToString(this.spread, 1);

        this.highLabel = DoubleToString(this.high, digits);
        this.lowLabel = DoubleToString(this.low, digits);
        this.diffLabel = IntegerToString(this.diff);
        this.diffJpyLabel = IntegerToString(this.diffJpy);
    }

};


