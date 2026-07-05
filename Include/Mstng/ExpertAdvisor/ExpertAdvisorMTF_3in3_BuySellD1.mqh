//+------------------------------------------------------------------+
//|                              ExpertAdvisorMTF_3in3_BuySellD1.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class ExpertAdvisorMTF_3in3_BuySellD1 : public AbstractExpertAdvisor {
public:
    
    ExpertAdvisorMTF_3in3_BuySellD1(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "MTF_3in3_BuySellD1";
        this.fontSize = 20;
    }
    
    ~ExpertAdvisorMTF_3in3_BuySellD1() {
    }
        
protected:
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && this.elliotAll.isBuySell(PERIOD_D1)
                
                && this.expertAdvisorOscillator.isTrendCountNeutral(this.elliotD1)
                
                && this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, this.isBuy)
        ) {            
            isJudge = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isJudge = %s", (string)isJudge));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isJudge;
    }        
    
    void setEntry() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.alertText = this.getAlertText();
                
        if (!this.isEntry) {
            if (1 == 1
                    //&& this.isLossCut(50)
                    
                    && this.isElliot(this.elliotHigher1)
                    && this.isElliot(this.elliotCurrent)
                    
            ) {
                this.isEntry = true;
                this.isSendMail = true;
            }
        }        
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
    bool isElliot(Elliot *elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.marketContext.timeFrameLabel));
        
        bool isElliot = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        string elliotLabel = latestPoint.elliotLabel;
        
        if (elliotLabel == "1" || elliotLabel == "3" || elliotLabel == "5") {
            isElliot = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot = %s", (string)isElliot));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot;
    }
        
    string getAlertText() {
        string text = "";
        
        Wave *latestWaveHigher1 = this.elliotHigher1.getLatestWave();
        
        text += latestWaveHigher1.trendLabel;
        text += elliotHigher1.getLatestPointElliotLabel();
        
        text += "-";
        
        text += elliotCurrent.getLatestPointElliotLabel();
        
        return text;
    }
    
};