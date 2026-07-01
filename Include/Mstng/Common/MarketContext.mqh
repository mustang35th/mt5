//+------------------------------------------------------------------+
//|                                                MarketContext.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_COMMON_MARKET_CONTEXT_MQH
#define MSTNG_COMMON_MARKET_CONTEXT_MQH

#include <Mstng\Util\TimeUtil.mqh>

/**
 * 市場コンテキスト。
 */
class MarketContext {
public:
    /** 銘柄名 */
    string symbolName;

    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /** 時間足表示名 */
    string timeFrameLabel;

    /** 小数桁数 */
    int digits;

    /**
     * デフォルトコンストラクタ。
     */
    MarketContext() {
        this.symbolName = "";
        this.timeFrame = PERIOD_CURRENT;
        this.timeFrameLabel = "";
        this.digits = 0;
    }

    /**
     * 銘柄名と時間足を指定して初期化する。
     *
     * @param fromSymbolName 銘柄名
     * @param fromTimeFrame 時間足
     */
    MarketContext(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame
    ) {
        this.setSymbolName(fromSymbolName);
        this.setTimeFrame(fromTimeFrame);
    }

    /**
     * 市場コンテキストの全項目を指定して初期化する。
     *
     * @param fromSymbolName 銘柄名
     * @param fromTimeFrame 時間足
     * @param fromTimeFrameLabel 時間足表示名
     * @param fromDigits 小数桁数
     */
    MarketContext(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        string fromTimeFrameLabel,
        int fromDigits
    ) {
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = fromTimeFrameLabel;
        this.digits = fromDigits;
    }

    /**
     * 円建てシンボルか判定する。
     *
     * @return シンボル名にJPYを含む場合はtrue
     */
    bool isJpy() const {
        return StringFind(this.symbolName, "JPY") >= 0;
    }

    /**
     * 1ポイントの価格を取得する。
     *
     * @return 1ポイントの価格
     */
    double getPoint() const {
        return SymbolInfoDouble(this.symbolName, SYMBOL_POINT);
    }

    /**
     * 銘柄名を設定し、小数桁数を更新する。
     *
     * @param fromSymbolName 銘柄名
     */
    void setSymbolName(string fromSymbolName) {
        this.symbolName = fromSymbolName;
        this.digits = (int)SymbolInfoInteger(this.symbolName, SYMBOL_DIGITS);
    }

    /**
     * 時間足を設定し、時間足表示名を更新する。
     *
     * @param fromTimeFrame 時間足
     */
    void setTimeFrame(ENUM_TIMEFRAMES fromTimeFrame) {
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
    }
};

#endif // MSTNG_COMMON_MARKET_CONTEXT_MQH



