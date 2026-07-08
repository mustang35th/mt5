//+------------------------------------------------------------------+
//|                              ExpertAdvisorMTF_3in3_BuySellD1.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

/**
 * D1方向一致とオシレーター条件を使って複数時間足エントリーを判定するEA。
 */
class ExpertAdvisorMTF_3in3_BuySellD1 : public AbstractExpertAdvisor {
public:
    
    /**
     * 分析対象と描画設定を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル。
     * @param fromTimeFrame 分析対象時間足。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMTF_3in3_BuySellD1(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.init(fromSymbolName, fromTimeFrame, fromIsDrawArrow);
        
        this.isDarwText = true;
        this.name = "MTF_3in3_BuySellD1";
        this.fontSize = 20;
    }
    
    /**
     * デストラクタ。
     */
    ~ExpertAdvisorMTF_3in3_BuySellD1() {
    }
        
protected:
    /**
     * D1方向一致、D1中立判定、GMMAクロスからシグナルを判定する。
     *
     * @return 判定条件を満たす場合true。
     */
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
    
    /**
     * 波動条件を確認し、エントリーおよびメール送信フラグを設定する。
     */
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
    /**
     * 指定したElliotの最新ポイントが推進波か判定する。
     *
     * @param elliot 判定対象。
     * @return 最新ポイントが第1波、第3波または第5波の場合true。
     */
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
        
    /**
     * 上位足と現在足の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
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
