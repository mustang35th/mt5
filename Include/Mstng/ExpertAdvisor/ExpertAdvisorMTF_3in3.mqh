//+------------------------------------------------------------------+
//|                                        ExpertAdvisorMTF_3in3.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class ExpertAdvisorMTF_3in3 : public AbstractExpertAdvisor {
public:
    
    ExpertAdvisorMTF_3in3(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "MTF_3in3";
        this.fontSize = 20;
    }
    
    ~ExpertAdvisorMTF_3in3() {
    }
        
protected:
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && this.isBuy == this.isUptrend
                
                //&& this.expertAdvisorElliot.isSameTrend(this.elliotHigher1, this.isUptrend)
                
                //&& this.expertAdvisorElliot.isBuySell(this.elliotHigher1, this.isBuy)
                
                && this.isBuySell()
                
                && this.expertAdvisorElliot.isZigZagConfirmed(this.elliotCurrent)
                
                //&& this.expertAdvisorElliot.isMotiveWave(this.elliotHigher1)
                && this.expertAdvisorElliot.isMotiveWave(this.elliotCurrent)
                
                //&& this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotHigher1, this.isBuy)
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                && this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, this.isBuy)
                
                //&& this.isElliot3in3()
                
                //&& this.isElliot1or3(this.elliotCurrent)
                
                && this.isEma200BuySell(this.elliotHigher1)
                && this.isEma200BuySell(this.elliotCurrent)
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
        
        if (1 == 1
                //&& this.isLossCut(30)
                
                //&& this.isFibonacciExpansionPercent(this.elliotHigher1, 127.2)
                //&& this.isFibonacciExpansionPercent(this.elliotCurrent, 127.2)
                
                //&& this.isEma200BuySellHigher1()
                
                && this.isElliot1or3(this.elliotCurrent)
                
        ) {
            this.isEntry = true;
            this.isSendMail = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
    
    bool isBuySell() {
        bool isBuySell = false;
        
        if (this.timeFrame == PERIOD_M15) {
            if (this.expertAdvisorElliot.isBuySell(this.elliotH4, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotH1, this.isBuy)) {
                isBuySell = true;
            }
        }
        
        if (this.timeFrame == PERIOD_M5) {
            if (this.expertAdvisorElliot.isBuySell(this.elliotH4, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotH1, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotM15, this.isBuy)) {
                isBuySell = true;
            }
        }
        
        if (this.timeFrame == PERIOD_M1) {
            if (this.expertAdvisorElliot.isBuySell(this.elliotH4, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotH1, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotM15, this.isBuy)
                    && this.expertAdvisorElliot.isBuySell(this.elliotM5, this.isBuy)) {
                isBuySell = true;
            }
        }
        
        return isBuySell;
    }
    
    
    bool isEma200BuySell(Elliot *elliot) {
        bool isEma200BuySell = false;
        
        string buySellLabelCurrent = elliot.oscillator.ema200.getBuySellLabel();
        
        if (this.isBuy) {
            if (buySellLabelCurrent == "BUY") {
                isEma200BuySell = true;
            }
        } else {
            if (buySellLabelCurrent == "SELL") {
                isEma200BuySell = true;
            }
        }
        
        return isEma200BuySell;
    }
    
    /*bool isEma200BuySellHigher1() {
        bool isEma200BuySellHigher1 = false;
        
        string buySellLabelHigher1 = this.elliotHigher1.oscillator.ema200.getBuySellLabel();
        
        if (this.isBuy) {
            if (buySellLabelHigher1 != "SELL") {
                isEma200BuySellHigher1 = true;
            }
        } else {
            if (buySellLabelHigher1 != "BUY") {
                isEma200BuySellHigher1 = true;
            }
        }
        
        return isEma200BuySellHigher1;
    }
    
    bool isEma200BuySell() {
        bool isEma200BuySell = false;
        
        string buySellLabelCurrent = this.elliotCurrent.oscillator.ema200.getBuySellLabel();
        
        if (this.isBuy) {
            if (buySellLabelCurrent == "BUY") {
                isEma200BuySell = true;
            }
        } else {
            if (buySellLabelCurrent == "SELL") {
                isEma200BuySell = true;
            }
        }
        
        return isEma200BuySell;
    }*/
    
    bool isElliot1or3(Elliot *elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.timeFrameLabel));
        
        bool isElliot1or3 = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        string elliotLabel = latestPoint.elliotLabel;
        
        if (elliotLabel == "1" || elliotLabel == "3") {
            isElliot1or3 = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot1or3 = %s", (string)isElliot1or3));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot1or3;
    }
    
    bool isElliot3in3() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isElliot3in3 = false;
        
        ZigZagPoint *latestPointHigher1 = this.elliotHigher1.getLatestPoint();
        string elliotLabelHigher1 = latestPointHigher1.elliotLabel;
        string subElliotLabelHigher1 = latestPointHigher1.subElliotLabel;
        
        ZigZagPoint *latestPointCurrent = this.elliotCurrent.getLatestPoint();
        string elliotLabelCurrent = latestPointCurrent.elliotLabel;
        string subElliotLabelCurrent = latestPointCurrent.subElliotLabel;
        
        if (elliotLabelHigher1 == "1"
                //&& subElliotLabelHigher1 == "iii"
                && this.isSubElliotLabel(subElliotLabelHigher1)
        ) {
            if (elliotLabelCurrent == "3") {
                isElliot3in3 = true;
            }
        }
        
        if (elliotLabelHigher1 == "3"
                && this.isSubElliotLabel(subElliotLabelHigher1)) {
            if (elliotLabelCurrent == "3"
                    && this.isSubElliotLabel(subElliotLabelHigher1)) {
                isElliot3in3 = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot3in3 = %s", (string)isElliot3in3));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot3in3;
    }
    
    bool isSubElliotLabel(string subElliotLabel) {
        bool isSubElliotLabel = false;
        
        if (StringUtil::isEmpty(subElliotLabel) || subElliotLabel == "iii") {
            isSubElliotLabel = true;
        }
        
        return isSubElliotLabel;
    }
    
    
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
    
    
    
    /*bool isElliot3(Elliot *elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.timeFrameLabel));
        
        bool isElliot = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        string elliotLabel = latestPoint.elliotLabel;
        
        if (elliotLabel == "3") {
            isElliot = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot = %s", (string)isElliot));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot;
    }*/
    
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