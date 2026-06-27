//+------------------------------------------------------------------+
//|                                          ExpertAdvisorElliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Util\UtilAll.mqh>

class ExpertAdvisorElliot {
public:
    
    ExpertAdvisorElliot(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
    }
    
    ~ExpertAdvisorElliot() {
    }
    
    bool isZigZagConfirmed(Elliot &elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isZigZagConfirmed = false;
        
        // 最新のZigZagポイントを取得する
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        
        // 追加途中のポイントでなければ、ZigZagは確定と判定する
        if (!latestPoint.isAddedPoint) {
            isZigZagConfirmed = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("latestPoint = %s", latestPoint.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isZigZagConfirmed = %s", (string)isZigZagConfirmed));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isZigZagConfirmed;
    }
    
    bool isBuySell(Elliot &elliot, bool fromIsBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isBuySell = false;
        
        if (fromIsBuy) {
            if (elliot.isBuy) {
                isBuySell = true;
            }
        } else {
            if (!elliot.isBuy) {
                isBuySell = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("elliot.isBuy = %s", (string)elliot.isBuy));
        
        this.logger.debug(__FUNCTION__, StringFormat("fromIsBuy = %s", (string)fromIsBuy));
        this.logger.debug(__FUNCTION__, StringFormat("isBuySell = %s", (string)isBuySell));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isBuySell;
    }
        
    bool isMotiveWave(Elliot &elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isMotiveWave = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        
        if (latestPoint.isMotiveWave()) {
            isMotiveWave = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("latestPoint = %s", latestPoint.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isMotiveWave = %s", (string)isMotiveWave));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isMotiveWave;
    }
    
    bool isSameTrend(Elliot &elliot, bool fromIsUptrend) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isSameTrend = false;
        
        bool isUptrend = elliot.isUptrend();
        
        if (fromIsUptrend) {
            if (isUptrend) {
                isSameTrend = true;
            }
        } else {
            if (!isUptrend) {
                isSameTrend = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isSameTrend = %s", (string)isSameTrend));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isSameTrend;
    }
    
private:
    Logger logger;
    
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;

};