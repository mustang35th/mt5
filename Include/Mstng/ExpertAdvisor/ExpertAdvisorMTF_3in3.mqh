//+------------------------------------------------------------------+
//|                                        ExpertAdvisorMTF_3in3.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>

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

    /**
     * 直近のMTF_3in3アラート判定結果を取得する。
     *
     * @return analyze()で確定したアラートおよびエントリー判定結果。
     */
    Mtf3In3AlertResult getAlertResult() {
        Mtf3In3AlertResult result;
        result.reset();

        result.isJudge = this.isJudgeMatched;
        result.signalCount = this.signalCountResult;
        result.entryCount = this.entryCountResult;

        if (this.isJudgeMatched
                && this.signalCountResult == this.entryCountResult) {
            result.isEntryCountMatch = true;
        }

        result.isEntryEvaluated = this.isEntryEvaluated;
        result.isAlert = this.isAlert;
        result.isEntry = this.isEntry;
        result.isSendMail = this.isSendMail;
        result.isBuy = this.isBuy;

        if (!this.isEntryEvaluated) {
            return result;
        }

        result.entryResult = this.entryResult;
        result.currentElliotLabel = this.currentElliotLabel;
        result.isEntryWave = this.isEntryWaveResult;
        result.closeEma200DiffPips = this.closeEma200DiffPipsResult;
        result.maxCloseEma200DiffPips = this.maxCloseEma200DiffPipsResult;
        result.isEma200DistanceWithin = this.isEma200DistanceWithinResult;

        return result;
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

                && this.elliotAll.isBuySell(PERIOD_D1)

                //&& this.expertAdvisorElliot.isWaveUnconfirmed(this.elliotH1)

                && this.expertAdvisorElliot.isZigZagConfirmed(this.elliotCurrent)
                
                && this.isElliot1or3(this.elliotHigher2)
                && this.isElliot1or3(this.elliotHigher1)
                && this.isElliot1or3(this.elliotCurrent)
                
                //&& this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotHigher1, this.isBuy)
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                && this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, this.isBuy)
                
                && this.expertAdvisorEma200.isEma200BuySellOrNone(this.elliotHigher2)
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
        
        this.resetEntryValidation();
        this.alertText = this.getAlertText();
        
        this.elliotAll.mailTitile = StringFormat("【%s】", this.alertText);

        //this.elliotAll.mailTitile += this.marketContext.timeFrameLabel;
        
        /*if (this.marketContext.timeFrame == PERIOD_M1) {
            this.elliotAll.mailTitile = "*" + this.elliotAll.mailTitile;
        }*/
        
        ZigZagPoint *latestPoint = this.elliotCurrent.getLatestPoint();
        this.currentElliotLabel = latestPoint.elliotLabel;
        this.isEntryWaveResult = this.isElliot1or3(this.elliotCurrent);
        bool isM5Elliot3FibonacciExpansionWithinResult =
            this.isM5Elliot3FibonacciExpansionWithin();
        this.closeEma200DiffPipsResult = MathAbs(
            this.elliotCurrent.oscillator.ema200.closeEma200DiffPips
        );
        this.maxCloseEma200DiffPipsResult = this.getMaxCloseEma200DiffPips();
        this.isEma200DistanceWithinResult =
            this.expertAdvisorEma200.isCloseEma200DiffPipsWithin(
                this.elliotCurrent,
                this.maxCloseEma200DiffPipsResult
            );

        if (!this.isEntryWaveResult) {
            this.entryResult = "ELLIOT_LABEL_REJECTED";
        } else if (!isM5Elliot3FibonacciExpansionWithinResult) {
            this.entryResult = "M5_ELLIOT3_FE_REJECTED";
        } else if (!this.isEma200DistanceWithinResult) {
            this.entryResult = "EMA200_DISTANCE_REJECTED";
        } else {
            bool isH1DisplayWaveEntryRegistered =
                this.tryRegisterH1DisplayWaveEntry();

            if (isH1DisplayWaveEntryRegistered) {
                this.isEntry = true;
                this.entryResult = "ENTRY";

                if (this.elliotCurrent.marketContext.timeFrame == PERIOD_M5) {
                    this.isSendMail = true;
                }
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
    /** M5第3波のフィボナッチエクスパンション許容上限%。 */
    static const double maxM5Elliot3FibonacciExpansionPercent;

    /** Close1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPips;

    /** JPYペアのClose1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPipsJpy;

    /** 直近のエントリー判定結果コード。 */
    string entryResult;

    /** 直近の現在時間足Elliottラベル。 */
    string currentElliotLabel;

    /** 直近の現在時間足がエントリー対象波動の場合true。 */
    bool isEntryWaveResult;

    /** 直近のClose1とEMA200[1]の距離pips。 */
    double closeEma200DiffPipsResult;

    /** 直近のClose1とEMA200[1]の許容距離pips。 */
    double maxCloseEma200DiffPipsResult;

    /** 直近のClose1とEMA200[1]の距離が許容範囲内の場合true。 */
    bool isEma200DistanceWithinResult;

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
        this.resetEntryValidation();
    }

    /**
     * エントリー条件の検証結果を初期化する。
     */
    void resetEntryValidation() {
        this.entryResult = "NOT_EVALUATED";
        this.currentElliotLabel = "";
        this.isEntryWaveResult = false;
        this.closeEma200DiffPipsResult = 0.0;
        this.maxCloseEma200DiffPipsResult = 0.0;
        this.isEma200DistanceWithinResult = false;
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

    /**
     * M5エントリー対象のH1表示波を使用済みとして登録する。
     *
     * H1の波開始時刻、上位波・下位波の複合ラベルおよび方向で識別し、
     * 同一表示波への2回目以降のエントリーを拒否する。
     *
     * @return M5以外、またはH1表示波を新規登録できた場合true。
     */
    bool tryRegisterH1DisplayWaveEntry() {
        if (!this.elliotAll.isH1DisplayWaveEntryLimitEnabled) {
            return true;
        }

        if (this.marketContext.timeFrame != PERIOD_M5) {
            return true;
        }

        if (this.analysisSignalCount == NULL) {
            this.entryResult = "H1_DISPLAY_WAVE_TRACKER_UNAVAILABLE";
            this.logger.error(__FUNCTION__, "analysisSignalCount is NULL");

            return false;
        }

        if (this.elliotHigher2 == NULL) {
            this.entryResult = "H1_DISPLAY_WAVE_INVALID";
            this.logger.error(__FUNCTION__, "elliotHigher2 is NULL");

            return false;
        }

        Wave *latestWaveHigher2 = this.elliotHigher2.getLatestWave();
        ZigZagPoint *latestPointHigher2 = this.elliotHigher2.getLatestPoint();
        ZigZagPoint *waveStartPointHigher2 = this.elliotHigher2.getLatestPoint2();

        if (latestWaveHigher2 == NULL
                || latestPointHigher2 == NULL
                || waveStartPointHigher2 == NULL) {
            this.entryResult = "H1_DISPLAY_WAVE_INVALID";
            this.logger.error(__FUNCTION__, "H1 display wave point is NULL");

            return false;
        }

        datetime waveStartTime = waveStartPointHigher2.barTime;
        string waveLabel = latestPointHigher2.getElliotLabel();
        bool isH1Uptrend = latestWaveHigher2.isUptrend;

        if (waveStartTime <= 0 || StringUtil::isEmpty(waveLabel)) {
            this.entryResult = "H1_DISPLAY_WAVE_INVALID";
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 display wave key is invalid. start=%s label=%s",
                    TimeToString(waveStartTime, TIME_DATE | TIME_MINUTES),
                    waveLabel
                )
            );

            return false;
        }

        if (this.analysisSignalCount.isEntryWaveUsed(
                waveStartTime,
                waveLabel,
                isH1Uptrend
        )) {
            this.entryResult = "H1_DISPLAY_WAVE_ENTRY_ALREADY_USED";
            this.logger.info(
                __FUNCTION__,
                StringFormat(
                    "H1 display wave entry already used. start=%s label=%s isUptrend=%s",
                    TimeToString(waveStartTime, TIME_DATE | TIME_MINUTES),
                    waveLabel,
                    (string)isH1Uptrend
                )
            );

            return false;
        }

        bool isMarked = this.analysisSignalCount.markEntryWaveUsed(
            waveStartTime,
            waveLabel,
            isH1Uptrend
        );

        if (!isMarked) {
            this.entryResult = "H1_DISPLAY_WAVE_REGISTER_FAILED";
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 display wave registration failed. start=%s label=%s isUptrend=%s",
                    TimeToString(waveStartTime, TIME_DATE | TIME_MINUTES),
                    waveLabel,
                    (string)isH1Uptrend
                )
            );

            return false;
        }

        return true;
    }

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
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot1or3 = %s", (string)isElliot1or3));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot1or3;
    }

    /**
     * 現在足がM5第3波の場合にフィボナッチエクスパンション上限を確認する。
     *
     * @return M5第3波以外、またはFEが許容上限以下の場合true。
     */
    bool isM5Elliot3FibonacciExpansionWithin() {
        if (this.elliotCurrent.marketContext.timeFrame != PERIOD_M5) {
            return true;
        }

        ZigZagPoint *latestPoint = this.elliotCurrent.getLatestPoint();

        if (latestPoint == NULL) {
            return false;
        }

        if (latestPoint.elliotLabel != "3") {
            return true;
        }

        double fibonacciExpansionPercent =
            latestPoint.fibonacciExpansionPercent;

        if (!MathIsValidNumber(fibonacciExpansionPercent)
                || fibonacciExpansionPercent == EMPTY_VALUE
                || fibonacciExpansionPercent <= 0.0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "invalid M5 Elliott wave 3 FE. value=%f",
                    fibonacciExpansionPercent
                )
            );

            return false;
        }

        fibonacciExpansionPercent = NormalizeDouble(
            fibonacciExpansionPercent,
            1
        );

        if (fibonacciExpansionPercent
                <= ExpertAdvisorMTF_3in3::maxM5Elliot3FibonacciExpansionPercent) {
            return true;
        }

        return false;
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
        
        if (this.marketContext.timeFrame == PERIOD_M5) {
            Wave *latestWaveHigher2 = this.elliotHigher2.getLatestWave();

            text += latestWaveHigher2.trendLabel;
            text += this.elliotHigher2.getLatestPointElliotLabel();
            text += "-";
        } else {
            Wave *latestWaveHigher1 = this.elliotHigher1.getLatestWave();

            text += latestWaveHigher1.trendLabel;
        }

        text += this.elliotHigher1.getLatestPointElliotLabel();
        
        text += "-";
        
        text += this.elliotCurrent.getLatestPointElliotLabel();
        
        return text;
    }
    
};

const double ExpertAdvisorMTF_3in3::maxM5Elliot3FibonacciExpansionPercent = 161.8;
const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPips = 25.0;
const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPipsJpy = 25.0;
