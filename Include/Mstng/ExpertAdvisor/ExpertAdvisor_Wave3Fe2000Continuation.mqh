//+------------------------------------------------------------------+
//|                        ExpertAdvisor_Wave3Fe2000Continuation.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class ExpertAdvisor_Wave3Fe2000Continuation : public AbstractExpertAdvisor {
public:
    
    ExpertAdvisor_Wave3Fe2000Continuation(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "Wave3Fe2000Continuation";
        this.fontSize = 20;
    }
    
    ~ExpertAdvisor_Wave3Fe2000Continuation() {
    }
        
protected:
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && this.expertAdvisorElliot.isZigZagConfirmed(this.elliotCurrent)
                
                && this.isElliot(this.elliotCurrent)
                
                && this.expertAdvisorElliot.isBuySell(this.elliotHigher1, this.isBuy)
                
                && this.isBuy == this.isUptrend
                
                //&& this.isBuy == this.elliotAll.higherStochasticMainOrderDecision.isBuy
                
                && this.expertAdvisorElliot.isSameTrend(this.elliotHigher2, this.isUptrend)
                && this.expertAdvisorElliot.isSameTrend(this.elliotHigher1, this.isUptrend)
                
                //&& this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotH1, this.isBuy)    // 大きな流れはH1で判断
                
                && this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotHigher1, this.isBuy)
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                                
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
        
        this.elliotAll.mailTitile += this.timeFrameLabel;
        
        if (!this.isEntry) {
            if (1 == 1                    
                    //&& this.elliotCurrent.isPrevCorrectionCCompleted()
                    
                    //&& this.elliotCurrent.getPreviousLastElliotLabel() == "C"
                    
                    //&& this.isLossCut(100)
                    
                    //&& this.elliotH4.oscillator.isStochasticMainOrder
                    
                    //&& this.isElliot(this.elliotHigher1)
                    //&& this.isElliot(this.elliotCurrent)
                    
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
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.timeFrameLabel));
        
        bool isElliot = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        string elliotLabel = latestPoint.elliotLabel;
        string subElliotLabel = latestPoint.subElliotLabel;
        
        if (elliotLabel == "3") {
            isElliot = true;
        }
        
        /*if (elliotLabel == "1" 
                || (elliotLabel == "3" && StringUtil::isEmpty(subElliotLabel))) {
            isElliot = true;
        }*/
        
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

