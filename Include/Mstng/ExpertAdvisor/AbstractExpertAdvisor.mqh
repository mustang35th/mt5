//+------------------------------------------------------------------+
//|                                        AbstractExpertAdvisor.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\ElliottWaveInfo.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorElliot.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorOscillator.mqh>

#include <Mstng\Mail\Mail.mqh>
#include <Mstng\Signal\SignalCount.mqh>

class AbstractExpertAdvisor {
public:
    string name;
    
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;
    
    bool isBuy;
    string buySellLabel;
    string buySellSymbol;
    bool isUptrend;
    
    bool isAlert;
    bool isEntry;
    bool isSendMail;
    
    string alertText;
    
    double stopLoss;
    
    string csvText;
    
    CArrayObj elliottWaveInfoList;
    
    AbstractExpertAdvisor() {
    };
    
    ~AbstractExpertAdvisor() {
        delete this.expertAdvisorElliot;
        delete this.expertAdvisorOscillator;
    };
    
    void init(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        
        this.isDrawArrow = fromIsDrawArrow;
        
        this.logger.debug(__FUNCTION__, "symbolName=" + this.symbolName);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.timeFrameLabel);
        
        this.expertAdvisorElliot = new ExpertAdvisorElliot(this.symbolName, this.timeFrame);
        this.expertAdvisorOscillator = new ExpertAdvisorOscillator(this.symbolName, this.timeFrame);
        
        this.isDarwText = false;
        this.fontSize = 10;
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    void analyze(ElliotAll *fromElliotAll, SignalCount *signalCount, int entryCount = 1) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (!this.setElliotAll(fromElliotAll)) {
            this.logger.error(__FUNCTION__, StringFormat("%s setElliotAll returned false", this.name));
            
            return;
        }
        
        bool isJudge = this.isJudge();
        
        if (isJudge) {
            this.isAlert = true;
            
            int count = signalCount.addCount(this.pointElliotCurrent_2.barTime, this.isBuy);
            
            if (count == entryCount) {
                this.elliotAll.mailTitile = StringFormat("【%s】", this.name);
                
                this.setEntry();
            } else {
                this.isAlert = false;
            }
            
            this.setCsvText();
            this.setStopLoss();
        }
        
        if (this.isDrawArrow) {
            this.drawArrow();
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    bool isExit(ElliotAll *fromElliotAll, bool isBuyPosition) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (!this.setElliotAll(fromElliotAll)) {
            this.logger.error(__FUNCTION__, StringFormat("%s setElliotAll returned false", this.name));
            
            return false;
        }
        
        bool isExit = false;
        
        if (this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, !isBuyPosition)) {
            isExit = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isExit = %s", (string)isExit));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isExit;
    }
    
    bool isStopLossModifiable() {
        bool isStopLossModifiable = false;
        
        
        
        
        return isStopLossModifiable;
    }
    
protected:
    Logger logger;
    
    bool isDrawArrow;
    bool isDarwText;
    
    ExpertAdvisorElliot *expertAdvisorElliot;
    ExpertAdvisorOscillator *expertAdvisorOscillator;
    
    ElliotAll *elliotAll;
    
    //Elliot *elliotMN1;
    //Elliot *elliotW1;
    Elliot *elliotD1;
    Elliot *elliotH4;
    Elliot *elliotH1;
    Elliot *elliotM15;
    Elliot *elliotM5;
    Elliot *elliotM1;
    
    Elliot *elliotHigher2;
    Elliot *elliotHigher1;
    Elliot *elliotCurrent;

    ZigZagPoint *pointElliotCurrent_2;
    ZigZagPoint *pointElliotCurrent_1;
    
    int fontSize;
    int arrowCdUp;
    int arrowCdDown;
    
    virtual bool isJudge() = 0;
    
    virtual void setEntry() = 0;
    
    bool isElliotM15() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        bool isElliotM15 = false;
        
        ZigZagPoint *latestPointM15 = this.elliotM15.getLatestPoint();
        string elliotLabelM15 = latestPointM15.elliotLabel;
        
        if (elliotLabelM15 == "1" || elliotLabelM15 == "3" || elliotLabelM15 == "5"
                || elliotLabelM15 == "C") {
            isElliotM15 = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliotM15 = %s", (string)isElliotM15));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliotM15;
    }
    
    bool isElliotM1() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        bool isElliot = false;
        
        ZigZagPoint *latestPointM5 = this.elliotM5.getLatestPoint();
        string elliotLabelM5 = latestPointM5.elliotLabel;
        //int elliotIndexM5 = latestPointM5.elliotIndex;
        
        ZigZagPoint *latestPointM1 = this.elliotM1.getLatestPoint();
        string elliotLabelM1 = latestPointM1.elliotLabel;
        
        if (elliotLabelM5 == "1") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3" || elliotLabelM1 == "5") {
                isElliot = true;
            }
        }
        
        if (elliotLabelM5 == "3") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3") {
                isElliot = true;
            }
        }
        
        if (elliotLabelM5 == "5") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3") {
                isElliot = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot = %s", (string)isElliot));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot;
    }
    
    bool isFibonacciExpansionPercent(Elliot *elliot, double inValue) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isFibonacciExpansionPercent = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        double fibonacciExpansionPercent = latestPoint.fibonacciExpansionPercent;
        
        if (fibonacciExpansionPercent <= inValue) {
            isFibonacciExpansionPercent = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("fibonacciExpansionPercent = %f", fibonacciExpansionPercent));
        this.logger.debug(__FUNCTION__, StringFormat("isFibonacciExpansionPercent = %s", (string)isFibonacciExpansionPercent));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isFibonacciExpansionPercent;
    }
    
    bool isFibonacciExpansionPercent(double inValue) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isFibonacciExpansionPercent = false;
        double fibonacciExpansionPercent = pointElliotCurrent_1.fibonacciExpansionPercent;
        
        if (fibonacciExpansionPercent <= inValue) {
            isFibonacciExpansionPercent = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("fibonacciExpansionPercent = %f", fibonacciExpansionPercent));
        this.logger.debug(__FUNCTION__, StringFormat("isFibonacciExpansionPercent = %s", (string)isFibonacciExpansionPercent));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isFibonacciExpansionPercent;
    }
    
    bool isLossCut(double inValue) {
        bool isLossCut = false;
        
        double diff = this.elliotAll.lossCut.diff;
        
        if (!Util::isJpy(this.symbolName)) {
            diff = this.elliotAll.lossCut.diffJpy;
        }
        
        if (diff <= inValue) {
            isLossCut = true;
        }
        
        return isLossCut;
    }
    
    /*bool isLossCutJpy(double inValue) {
        bool isLossCut = false;
        
        if (this.elliotAll.lossCut.diffJpy <= inValue) {
            isLossCut = true;
        }
        
        return isLossCut;
    }*/
    
    bool isSpread() {
        bool isSpread = false;
        
        if (this.elliotAll.todayRate.spread <= 3) {
            isSpread = true;
        }
        
        return isSpread;
    }
    
private:
    bool setElliotAll(ElliotAll *fromElliotAll) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        this.elliotAll = fromElliotAll;
        
        if (!this.elliotAll.isAnalysisSucceeded) {
            this.logger.error(__FUNCTION__, "elliotAll.isAnalysisSucceeded is false");
            
            return false;
        }
        
        this.isAlert = false;
        this.isEntry = false;
        this.isSendMail = false;
        
        this.alertText = "";
                    
        //this.elliotMN1 = this.elliotAll.elliotMN1;
        //this.elliotW1 = this.elliotAll.elliotW1;
        this.elliotD1 = this.elliotAll.getElliot(PERIOD_D1);
        this.elliotH4 = this.elliotAll.getElliot(PERIOD_H4);
        this.elliotH1 = this.elliotAll.getElliot(PERIOD_H1);
        this.elliotM15 = this.elliotAll.getElliot(PERIOD_M15);
        this.elliotM5 = this.elliotAll.getElliot(PERIOD_M5);
        this.elliotM1 = this.elliotAll.getElliot(PERIOD_M1);
        
        this.elliotHigher2 = this.elliotAll.getElliot(this.elliotAll.timeFrame, 2);
        this.elliotHigher1 = this.elliotAll.getElliot(this.elliotAll.timeFrame, 1);
        this.elliotCurrent = this.elliotAll.elliotCurrent;
        
        this.isBuy = this.elliotCurrent.isBuy;
        this.buySellLabel = this.elliotCurrent.buySellLabel;
        
        this.buySellSymbol = "▲";
        
        if (!this.isBuy) {
            this.buySellSymbol = "▼";
        }
        
        this.isUptrend = this.elliotCurrent.isUptrend();
        
        this.pointElliotCurrent_2 = this.elliotCurrent.getLatestPoint2();
        if (this.pointElliotCurrent_2 == NULL) {
            this.logger.error(__FUNCTION__, "pointElliotCurrent_2 is NULL");
            
            return false;
        }
        
        this.pointElliotCurrent_1 = this.elliotCurrent.getLatestPoint();
        if (this.pointElliotCurrent_1 == NULL) {
            this.logger.error(__FUNCTION__, "pointElliotCurrent_1 is NULL");
            
            return false;
        }
        
        this.setElliottWaveInfoList();
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    void drawArrow() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        if (this.isAlert) {
            color fontColor = clrLightGray;
            int arrowCd = 117;
            double offset = 0;
            
            if (this.isBuy) {
                arrowCd = this.arrowCdUp;
                
                fontColor = clrBlue;
                
                if (this.isEntry) {
                    fontColor = clrDodgerBlue;
                }            
            } else {
                arrowCd = this.arrowCdDown;
                
                fontColor = clrRed;
                
                if (this.isEntry) {
                    fontColor = clrMagenta;
                }
            }
            
            if (this.isDarwText) {
                datetime drawDatetime = iTime(this.symbolName, this.timeFrame, 0);
                double drawPrice = iOpen(this.symbolName, this.timeFrame, 0) /*+ common.getOffset(isBuy, offset)*/;
    
                DrawUtil::setTextFixed("Text" + this.name  + IntegerToString((int)drawDatetime), "MS Gothic", fontColor, 
                        this.fontSize, this.alertText, drawDatetime, drawPrice);
                
            } else {
                DrawUtil::setArrow("Arrow" + this.name, fontColor, arrowCd, this.fontSize, 0, offset);
            }
            
            if (this.elliotAll.isSendMail) {
                Mail::sendMail(this.elliotAll, this.isSendMail);
            } else {
                string text = "Alert";
                
                if (this.isEntry) {
                    text = "Entry";
                }
                
                Print(StringFormat(",%s,%s", text, elliotAll.getCsv()));
            }
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    void setElliottWaveInfoList() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.elliottWaveInfoList.Clear();
        
        CArrayObj *elliotList = &(this.elliotAll.elliotList);
        
        for (int i = 0; i < elliotList.Total(); i++) {
            Elliot *elliot = elliotList.At(i);
            
            Wave *latestWave = elliot.getLatestWave();
        
            if (latestWave == NULL) {
                return;
            }
        
            ZigZagPoint *zigZagPoint = latestWave.getLatestPoint();
            
            //ElliottWaveInfo *elliottWaveInfo = new ElliottWaveInfo(elliot.timeFrameLabel, elliot.buySellLabel, 
            //    StringUtil::addSign(elliot.oscillator.oscillatorCount), StringUtil::addSign(elliot.oscillator.gmmaCrossCount), zigZagPoint.getTextIndexInfo());
            
            ElliottWaveInfo *elliottWaveInfo = new ElliottWaveInfo();
            
            elliottWaveInfo.timeFrame = elliot.timeFrameLabel;
            elliottWaveInfo.buySell = elliot.buySellLabel;
            elliottWaveInfo.oscillator = StringUtil::addSign(elliot.oscillator.oscillatorCount);
            elliottWaveInfo.oscillatorS = StringUtil::addSign(elliot.oscillator.stochasticShort.count);
            elliottWaveInfo.oscillatorM = StringUtil::addSign(elliot.oscillator.stochasticMiddle.count);
            elliottWaveInfo.oscillatorL = StringUtil::addSign(elliot.oscillator.stochasticLong.count);
            elliottWaveInfo.gmma = StringUtil::addSign(elliot.oscillator.gmmaCrossCount);
            elliottWaveInfo.elliott = zigZagPoint.getTextIndexInfo();
            
            this.elliottWaveInfoList.Add(elliottWaveInfo);
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    void setCsvText() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        this.csvText = this.elliotAll.getCsv(true);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    void setStopLoss() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        this.stopLoss = this.elliotAll.lossCut.lc5;
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};