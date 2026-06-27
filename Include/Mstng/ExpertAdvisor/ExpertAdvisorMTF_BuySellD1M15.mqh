//+------------------------------------------------------------------+
//|                                ExpertAdvisorMTF_BuySellD1M15.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>
#include <Mstng\ExpertAdvisor\Common\ExpertAdvisorBuySell.mqh>

class ExpertAdvisorMTF_BuySellD1M15 : public AbstractExpertAdvisor {
public:
    ExpertAdvisorBuySell *expertAdvisorBuySell;
    
    ExpertAdvisorMTF_BuySellD1M15(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "MTF_BuySellD1M15";
        this.fontSize = 20;
    }
    
    ~ExpertAdvisorMTF_BuySellD1M15() {
        delete expertAdvisorBuySell;
    }
    
protected:
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        expertAdvisorBuySell = new ExpertAdvisorBuySell(this.symbolName, this.timeFrame);
        
        expertAdvisorBuySell.setRank(this.elliotAll);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && expertAdvisorBuySell.rank != EXPERT_ADVISOR_ENTRY_RANK_NON
                
                && expertAdvisorBuySell.isBuy == this.isBuy
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                
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
                    
                    //&& this.isElliot(this.elliotHigher1)
                    //&& this.isElliot(this.elliotCurrent)
                    
            ) {
                this.isEntry = true;
                this.isSendMail = true;
                
                elliotAll.mailTitile += this.alertText;
            }
        }        
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
        
    string getAlertText() {
        string text = "";
        
        //text += this.buySellLabel;
        text += buySellSymbol;
        text += "-";
        text += expertAdvisorBuySell.rankLabel;
        
        return text;
    }
    
};