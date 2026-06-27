//+------------------------------------------------------------------+
//|                             ExpertAdvisorMTF_StochasticOrder.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class ExpertAdvisorMTF_StochasticOrder : public AbstractExpertAdvisor {
public:
    
    ExpertAdvisorMTF_StochasticOrder(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "MTF_StochasticOrder";
        this.fontSize = 20;
    }
    
    ~ExpertAdvisorMTF_StochasticOrder() {
    }
        
protected:
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && this.elliotAll.isBuySell(PERIOD_D1)
                
                && this.expertAdvisorElliot.isMotiveWave(this.elliotHigher1)
                && this.expertAdvisorElliot.isMotiveWave(this.elliotCurrent)
                
                //&& this.isStochasticMainOrder()
                //&& this.expertAdvisorOscillator.isStochasticMainOrder(this.elliotAll)
                
                && this.expertAdvisorOscillator.isStochasticMainOrderD1H1(this.elliotAll)
                
                
                && this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotH1, this.isBuy)
                
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
                    && this.isLossCut(100)
                    
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
    /*bool isStochasticMainOrder() {
        bool isStochasticMainOrder = false;
        
        if (this.isBuy) {
            if (this.isStochasticMainOrder(this.elliotD1, STOCH_MAIN_ORDER_S_M_L)
                    || this.isStochasticMainOrder(this.elliotH4, STOCH_MAIN_ORDER_S_M_L)) {
                if (this.isStochasticMainOrder(this.elliotH1, STOCH_MAIN_ORDER_S_M_L)
                        || this.isStochasticMainOrder(this.elliotH1, STOCH_MAIN_ORDER_M_S_L)) {
                    isStochasticMainOrder = true;
                }
            }
        } else {
            if (this.isStochasticMainOrder(this.elliotD1, STOCH_MAIN_ORDER_L_M_S)
                    || this.isStochasticMainOrder(this.elliotH4, STOCH_MAIN_ORDER_L_M_S)) {
                if (this.isStochasticMainOrder(this.elliotH1, STOCH_MAIN_ORDER_L_M_S)
                        || this.isStochasticMainOrder(this.elliotH1, STOCH_MAIN_ORDER_L_S_M)) {
                    isStochasticMainOrder = true;
                }
            }
        }
        
        return isStochasticMainOrder;
    }
    
    bool isStochasticMainOrder(Elliot *elliot, ENUM_STOCHASTIC_MAIN_ORDER value) {
        bool isStochasticMainOrder = false;
        
        if (elliot.oscillator.stochasticMainOrder == value) {
            isStochasticMainOrder = true;
        }
        
        return isStochasticMainOrder;
    }*/
    
    bool isElliot(Elliot *elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.timeFrameLabel));
        
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