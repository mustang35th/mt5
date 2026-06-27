//+------------------------------------------------------------------+
//|                                                MarketContext.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\RateUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 市場コンテキスト
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
    
    MarketContext() {
    }
    
    /**
     * コンストラクタ
     *
     * @param symbolNameValue 銘柄名
     * @param timeFrameValue 時間足
     */
    MarketContext(
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue
    ) {
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        this.digits = RateUtil::getDigits(this.symbolName);
    }

    /**
     * コンストラクタ
     *
     * @param symbolNameValue 銘柄名
     * @param timeFrameValue 時間足
     * @param timeFrameLabelValue 時間足表示名
     * @param digitsValue 小数桁数
     */
    MarketContext(
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        string timeFrameLabelValue,
        int digitsValue
    ) {
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.timeFrameLabel = timeFrameLabelValue;
        this.digits = digitsValue;
    }
};