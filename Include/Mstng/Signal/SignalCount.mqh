//+------------------------------------------------------------------+
//|                                                  SignalCount.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Signal\SignalInfo.mqh>
#include <Mstng\Util\UtilAll.mqh>

class SignalCount : public CObject {
public:
    SignalCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
    }
    
    ~SignalCount() {
    }

    // カウンタ加算
    int addCount(datetime time, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int count = 0;
                
        SignalInfo *signalInfo = this.getSignalInfo(time, isBuy);
        
        if (signalInfo == NULL) {
            this.logger.debug(__FUNCTION__, "SignalCountなし　新規作成");
            
            signalInfo = new SignalInfo(time, isBuy);
            count = signalInfo.addCount();
            
            this.signalInfoList.Add(signalInfo);
            
        } else {
            this.logger.debug(__FUNCTION__, "SignalCountあり");
            
            count = signalInfo.addCount();
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("count = %d", count));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return count;
    }


private:
    Logger logger;
    
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;
    
    CArrayObj signalInfoList;
    
    SignalInfo *getSignalInfo(datetime time, bool isBuy) {
        
        for (int i = 0; i < this.signalInfoList.Total(); i++) {
            SignalInfo *signalInfo = this.signalInfoList.At(i);
            
            if (signalInfo.isEqual(time, isBuy)) {
                return signalInfo;
            }
        }
        
        return NULL;
    }
};        