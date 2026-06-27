//+------------------------------------------------------------------+
//|                                                   SignalInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>

class SignalInfo : public CObject {
public:
    
    SignalInfo(datetime fromTime, bool fromIsBuy) {
        this.time = fromTime;
        this.isBuy = fromIsBuy;
        this.count = 0;
    }
    
    ~SignalInfo() {
    }

    int addCount() {
        this.count++;
        
        return this.count;
    }
    
    // 同じインスタンスか判定
    bool isEqual(datetime fromTime, bool fromIsBuy) {
        bool isEqual = false;
        
        if (this.time == fromTime && this.isBuy == fromIsBuy) {
            isEqual = true;
        }
        
        return isEqual;
    }

private:
    datetime time;  // 基準となるZigZagポイントの時刻
    bool isBuy; // 売買フラグ
    
    int count;

};