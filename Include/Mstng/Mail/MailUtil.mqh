//+------------------------------------------------------------------+
//|                                                     MailUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"


class MailUtil {
public:
    static string addSign(const int value) {
        if (value > 0) {
            return "+" + IntegerToString(value);
        }
    
        return IntegerToString(value);
    }


};