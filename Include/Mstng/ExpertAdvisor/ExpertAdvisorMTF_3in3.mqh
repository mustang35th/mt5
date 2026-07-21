//+------------------------------------------------------------------+
//|                                        ExpertAdvisorMTF_3in3.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

/**
 * 複数時間足のElliott波動、GMMAおよびEMA200を使用してエントリーを判定する。
 */
class ExpertAdvisorMTF_3in3 : public AbstractExpertAdvisor {
public:

    /**
     * 分析対象と描画設定を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル。
     * @param fromTimeFrame 分析対象時間足。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMTF_3in3(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow = true) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromIsDrawArrow);
    }

    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMTF_3in3(MarketContext &fromMarketContext, bool fromIsDrawArrow = true) {
        this.initialize(fromMarketContext, fromIsDrawArrow);
    }

    /**
     * デストラクタ。
     */
    ~ExpertAdvisorMTF_3in3() {
    }
        
protected:
    /**
     * スプレッド、トレンド、波動および各テクニカル条件からシグナルを判定する。
     *
     * @return すべての判定条件を満たす場合true。
     */
    bool isJudge() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isJudge = false;
        
        if (1 == 1
                && this.isSpread()
                
                && this.isBuy == this.isUptrend
                
                //&& this.expertAdvisorElliot.isSameTrend(this.elliotHigher1, this.isUptrend)
                
                //&& this.expertAdvisorElliot.isBuySell(this.elliotHigher1, this.isBuy)
                
                //&& this.isBuySell()
                
                //&& this.expertAdvisorElliot.isBuySellFromH4(this.elliotAll, this.isBuy)
                //&& this.expertAdvisorElliot.isBuySellFromH1(this.elliotAll, this.isBuy)

                && this.elliotAll.isBuySell(PERIOD_H4)
                
                && this.expertAdvisorElliot.isZigZagConfirmed(this.elliotCurrent)
                
                //&& this.expertAdvisorElliot.isMotiveWave(this.elliotHigher1)
                && this.expertAdvisorElliot.isMotiveWave(this.elliotCurrent)
                
                //&& this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotHigher1, this.isBuy)
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                && this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, this.isBuy)
                
                //&& this.isElliot3in3()
                
                //&& this.isElliot1or3(this.elliotCurrent)
                
                //&& this.expertAdvisorEma200.isEma200BuySell(this.elliotHigher2)
                && this.expertAdvisorEma200.isEma200BuySell(this.elliotHigher1)
                && this.expertAdvisorEma200.isEma200BuySell(this.elliotCurrent)
                
                //&& this.expertAdvisorEma200.isEma200CurrentAndHigher(this.elliotHigher2, this.elliotHigher1)
                //&& this.expertAdvisorEma200.isEma200CurrentAndHigher(this.elliotHigher1, this.elliotCurrent)
        ) {            
            isJudge = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isJudge = %s", (string)isJudge));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isJudge;
    }        

    /**
     * Elliott波動条件を確認し、エントリーおよびメール送信フラグを設定する。
     */
    void setEntry() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.alertText = this.getAlertText();
        
        this.elliotAll.mailTitile += this.marketContext.timeFrameLabel;
        
        /*if (this.marketContext.timeFrame == PERIOD_M1) {
            this.elliotAll.mailTitile = "*" + this.elliotAll.mailTitile;
        }*/
        
        if (1 == 1
                //&& this.isLossCut(30)
                
                //&& this.isFibonacciExpansionPercent(this.elliotHigher1, 127.2)
                //&& this.isFibonacciExpansionPercent(this.elliotCurrent, 127.2)
                
                //&& this.isEma200BuySellHigher1()
                
                && this.isElliot1or3(this.elliotCurrent)
                && this.expertAdvisorEma200.isCloseEma200DiffPipsWithin(
                    this.elliotCurrent,
                    this.getMaxCloseEma200DiffPips()
                )
                
        ) {
            this.isEntry = true;

            if (this.elliotCurrent.marketContext.timeFrame == PERIOD_M5
                    || this.elliotCurrent.marketContext.timeFrame == PERIOD_M1) {
                this.isSendMail = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
    /** Close1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPips;

    /** JPYペアのClose1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPipsJpy;

    /**
     * 市場コンテキストを使用して共通設定とEA固有設定を初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    void initialize(MarketContext &fromMarketContext, bool fromIsDrawArrow) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext, fromIsDrawArrow);

        this.isDarwText = true;
        this.name = "MTF_3in3";
        this.fontSize = 20;
    }

    /**
     * Close1とEMA200[1]のエントリー許容距離pipsを取得する。
     *
     * @return エントリー許容距離pips。
     */
    double getMaxCloseEma200DiffPips() {
        if (this.marketContext.isJpy()) {
            return ExpertAdvisorMTF_3in3::maxCloseEma200DiffPipsJpy;
        }

        return ExpertAdvisorMTF_3in3::maxCloseEma200DiffPips;
    }

    // 旧バージョンの上位時間足判定実装（未使用）。必要時は再有効化して利用。
    
    /**
     * 指定したElliotの最新ポイントが第1波または第3波か判定する。
     *
     * @param elliot 判定対象。
     * @return 最新ポイントが第1波または第3波の場合true。
     */
    bool isElliot1or3(Elliot *elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.strPeriod = %s", elliot.marketContext.timeFrameLabel));
        
        bool isElliot1or3 = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        string elliotLabel = latestPoint.elliotLabel;
        
        if (elliotLabel == "1" || elliotLabel == "3") {
            isElliot1or3 = true;
        }
        
        if (elliot.marketContext.timeFrame == PERIOD_M1) {
            if (elliotLabel == "5") {
                isElliot1or3 = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot1or3 = %s", (string)isElliot1or3));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot1or3;
    }

    /**
     * 上位足と現在足が3波中の3波に該当するか判定する。
     *
     * @return 3波中の3波に該当する場合true。
     */
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

    /**
     * 下位波動ラベルが判定対象として有効か確認する。
     *
     * @param subElliotLabel 下位波動ラベル。
     * @return 空文字または第iii波の場合true。
     */
    bool isSubElliotLabel(string subElliotLabel) {
        bool isSubElliotLabel = false;
        
        if (StringUtil::isEmpty(subElliotLabel) || subElliotLabel == "iii") {
            isSubElliotLabel = true;
        }
        
        return isSubElliotLabel;
    }

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

const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPips = 20.0;
const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPipsJpy = 25.0;
