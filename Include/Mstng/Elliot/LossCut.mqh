//+------------------------------------------------------------------+
//|                                                      LossCut.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Util\TodayRate.mqh>

// ロスカット
class LossCut {
public:
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;
    
    bool isBuy;
    
    double rate;
    
    double diff;
    double diffJpy;
    
    double lc0;
    double lc5;
    double lc10;
    double lc15;
    
    // コンストラクタ
    //LossCut(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
    LossCut() {
        this.logger.setLevel(LOG_INFO);
        
        this.rate = 0;
        
        this.diff = 0;
        this.diffJpy = 0;
        
        this.lc0 = 0;
        this.lc5 = 0;
        this.lc10 = 0;
        this.lc15 = 0;
    }
    
    // デストラクタ
    ~LossCut() {
    }
    
    string getText() {
        string text = "";
        
        int digits = RateUtil::getDigits(this.symbolName);
        
        text += StringFormat("Loss Cut %s\n" ,this.timeFrameLabel);
        text += StringFormat("diff = %spips\n", DoubleToString(diff, 1));
        
        if (this.diffJpy > 0) {
            text += StringFormat("diffJpy = %spips\n", DoubleToString(diffJpy, 1));
        }
        
        text += "\n";
        
        text += StringFormat("0 -> %s\n", DoubleToString(lc0,  digits));
        text += StringFormat("5 -> %s\n", DoubleToString(lc5,  digits));
        text += StringFormat("10-> %s\n", DoubleToString(lc10, digits));
        text += StringFormat("15-> %s\n", DoubleToString(lc15, digits));
    
        return text;
    }
        
    void setData(Elliot &elliot, TodayRate &todayRate) {
        this.symbolName = elliot.symbolName;
        this.timeFrame = elliot.timeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        
        this.logger.setSymbolNameAndTimeFrame(this.symbolName, this.timeFrame);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        ZigZagPoint *latestZigZagPoint2 = elliot.getLatestPoint2();
        
        if (latestZigZagPoint2 == NULL) {
            return;
        }
        
        this.isBuy = elliot.isBuy;
        
        this.lc0 = latestZigZagPoint2.rate;
        
        this.rate = todayRate.bid;    // 初期は売り
                                
        if (this.isBuy) {
            this.rate = todayRate.ask;
        }
        
        this.diff = RateUtil::getDiffPips(this.rate, this.lc0, this.symbolName);
        
        if (!Util::isJpy(this.symbolName)) {
            double jpyAmount = 0.0;
    
            if (PipConverter::tryConvertPipsToJpy(this.symbolName, this.diff, 100, jpyAmount)) {
                this.diffJpy = (int)MathRound(jpyAmount);
            }
        }
        
        this.lc5 = lc0 + RateUtil::getOffset(this.isBuy, 5, this.symbolName);
        this.lc10 = lc0 + RateUtil::getOffset(this.isBuy, 10, this.symbolName);
        this.lc15 = lc0 + RateUtil::getOffset(this.isBuy, 15, this.symbolName);
        
        this.logger.debug(__FUNCTION__, StringFormat("%s", this.toString()));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * @brief 内容を文字列化して返します。
     *
     * @param digits 価格系の表示桁数（未指定時はシンボル桁 or _Digits）
     * @return "LossCut{...}" 形式の文字列
     */
    string toString(const int digits = -1) const {
        int d = digits;
        if(d < 0)
        {
            d = (symbolName == "" ? _Digits : (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS));
        }

        return StringFormat(
            "LossCut{symbol=%s, tf=%s, tfLabel=%s, isBuy=%s, rate=%.*f, diff=%.*f, lc0=%.*f, lc5=%.*f, lc10=%.*f, lc15=%.*f}",
            symbolName,
            EnumToString(timeFrame),
            timeFrameLabel,
            (isBuy ? "true" : "false"),
            d, rate,
            d, diff,
            d, lc0,
            d, lc5,
            d, lc10,
            d, lc15
        );
    }
    
private:
    Logger logger;
};