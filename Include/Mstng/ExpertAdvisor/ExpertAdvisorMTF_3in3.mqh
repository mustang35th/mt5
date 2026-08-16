//+------------------------------------------------------------------+
//|                                        ExpertAdvisorMTF_3in3.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF_3IN3_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF_3IN3_MQH

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentResult.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationResult.mqh>
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
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード。
     * @param fromH1DirectionAlignmentMode H1エントリーの方向一致モード。
     */
    ExpertAdvisorMTF_3in3(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(
            context,
            fromIsDrawArrow,
            fromH1W1ConfirmationMode,
            fromH1DirectionAlignmentMode
        );
    }

    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード。
     * @param fromH1DirectionAlignmentMode H1エントリーの方向一致モード。
     */
    ExpertAdvisorMTF_3in3(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1
    ) {
        this.initialize(
            fromMarketContext,
            fromIsDrawArrow,
            fromH1W1ConfirmationMode,
            fromH1DirectionAlignmentMode
        );
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
        result.w1ConfirmationMode = this.w1ConfirmationResult.mode;
        result.w1ConfirmationState = this.w1ConfirmationResult.state;
        result.isW1ConfirmationAvailable =
            this.w1ConfirmationResult.isAvailable;
        result.isW1ConfirmationValid =
            this.w1ConfirmationResult.isValid;
        result.isW1DirectionMatched =
            this.w1ConfirmationResult.isDirectionMatched;
        result.w1Ema200Direction =
            this.w1ConfirmationResult.ema200Direction;
        result.isW1Ema200Matched =
            this.w1ConfirmationResult.isEma200Matched;
        result.isW1ConfirmationPassed =
            this.w1ConfirmationResult.isPassed;
        result.h1DirectionAlignmentMode =
            this.h1DirectionAlignmentResult.mode;
        result.h1DirectionAlignmentState =
            this.h1DirectionAlignmentResult.state;
        result.isH1DirectionAlignmentAvailable =
            this.h1DirectionAlignmentResult.isAvailable;
        result.isH1DirectionAlignmentValid =
            this.h1DirectionAlignmentResult.isValid;
        result.h1DirectionAlignmentDirection =
            this.h1DirectionAlignmentResult.direction;
        result.isH1Mn1DirectionMatched =
            this.h1DirectionAlignmentResult.isMn1DirectionMatched;
        result.isH1W1DirectionMatched =
            this.h1DirectionAlignmentResult.isW1DirectionMatched;
        result.isH1DirectionAlignmentPassed =
            this.h1DirectionAlignmentResult.isPassed;

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
    /** H1エントリーの方向一致モード。 */
    H1DirectionAlignmentMode h1DirectionAlignmentMode;

    /** 直近のH1方向一致診断結果。 */
    H1DirectionAlignmentResult h1DirectionAlignmentResult;

    /** H1エントリーのW1確認モード。 */
    H1W1ConfirmationMode h1W1ConfirmationMode;

    /** 直近のW1確認診断結果。 */
    H1W1ConfirmationResult w1ConfirmationResult;

    /**
     * W1確認診断を今回の分析用の未判定状態へ初期化する。
     */
    virtual void resetStrategySpecificAnalysisOutcome() override {
        this.resetTimeFrameDirectionAlignmentResult();
        this.resetTimeFrameHigherConfirmationResult();
    }

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

                && this.isTimeFrameDirectionAlignmentConditionMatched()

                //&& this.expertAdvisorElliot.isWaveUnconfirmed(this.elliotH1)

                && this.isTimeFrameZigZagConfirmedConditionMatched()
                
                && this.isTimeFrameWaveConditionMatched()
                
                //&& this.expertAdvisorOscillator.isGmmaTrend_1(this.elliotHigher1, this.isBuy)
                
                && this.expertAdvisorOscillator.isGmmaTrend_2(this.elliotCurrent, this.isBuy)
                && this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, this.isBuy)
                
                && this.isTimeFrameEma200ConditionMatched()

                && this.isTimeFrameHigherConfirmationConditionMatched()
                
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
        this.alertText = this.buildAlertText();
        
        this.elliotAll.mailTitile = StringFormat("【%s】", this.alertText);

        //this.elliotAll.mailTitile += this.marketContext.timeFrameLabel;
        
        /*if (this.marketContext.timeFrame == PERIOD_M1) {
            this.elliotAll.mailTitile = "*" + this.elliotAll.mailTitile;
        }*/
        
        ZigZagPoint *latestPoint = this.elliotCurrent.getLatestPoint();
        this.currentElliotLabel = latestPoint.elliotLabel;
        this.isEntryWaveResult = this.isEntryWave(this.elliotCurrent);
        string timeFrameRejectReason = "";
        bool isTimeFrameEntryAllowed =
            this.isTimeFrameEntryConditionMatched(timeFrameRejectReason);
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
        } else if (!isTimeFrameEntryAllowed) {
            if (StringUtil::isEmpty(timeFrameRejectReason)) {
                this.entryResult = "TIME_FRAME_ENTRY_REJECTED";
            } else {
                this.entryResult = timeFrameRejectReason;
            }
        } else if (this.isTimeFrameEma200DistanceRequired()
                && !this.isEma200DistanceWithinResult) {
            this.entryResult = "EMA200_DISTANCE_REJECTED";
        } else {
            bool isEntryScopeRegistered = this.tryRegisterEntryScope();

            if (isEntryScopeRegistered) {
                this.isEntry = true;
                this.entryResult = "ENTRY";

                if (this.shouldSendMail()) {
                    this.isSendMail = true;
                }
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        this.logger.debug(__FUNCTION__, StringFormat("isSendMail = %s", (string)this.isSendMail));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 時間足固有の波動条件を判定する。
     *
     * @return 時間足固有の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() {
        return this.isEntryWave(this.elliotHigher2)
            && this.isEntryWave(this.elliotHigher1)
            && this.isEntryWave(this.elliotCurrent);
    }

    /**
     * 時間足固有のZigZag確定条件を判定する。
     *
     * @return 現在足の最新ZigZagポイントが確定している場合true。
     */
    virtual bool isTimeFrameZigZagConfirmedConditionMatched() {
        return this.expertAdvisorElliot.isZigZagConfirmed(
            this.elliotCurrent
        );
    }

    /**
     * 時間足固有のEMA200方向条件を判定する。
     *
     * @return 時間足固有のEMA200方向条件を満たす場合true。
     */
    virtual bool isTimeFrameEma200ConditionMatched() {
        return this.expertAdvisorEma200.isEma200BuySellOrNone(
            this.elliotHigher2
        )
            && this.expertAdvisorEma200.isEma200BuySell(
                this.elliotHigher1
            )
            && this.expertAdvisorEma200.isEma200BuySell(
                this.elliotCurrent
            );
    }

    /**
     * 時間足固有の上位足確認条件を判定する。
     *
     * @return 時間足固有の上位足確認条件を満たす場合true。
     */
    virtual bool isTimeFrameHigherConfirmationConditionMatched() {
        return true;
    }

    /**
     * 時間足固有の売買方向一致条件を判定する。
     *
     * @return 時間足固有の方向一致条件を満たす場合true。
     */
    virtual bool isTimeFrameDirectionAlignmentConditionMatched() {
        return true;
    }

    /**
     * 時間足固有の追加エントリー条件を判定する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return 時間足固有の追加条件を満たす場合true。
     */
    virtual bool isTimeFrameEntryConditionMatched(
        string &fromRejectReason
    ) {
        fromRejectReason = "";

        return true;
    }

    /**
     * 現在足とEMA200の距離制限を使用するか判定する。
     *
     * @return 距離制限を使用する場合true。
     */
    virtual bool isTimeFrameEma200DistanceRequired() {
        return true;
    }

    /**
     * 時間足固有のエントリー範囲を登録する。
     *
     * @return 登録不要、または新規登録できた場合true。
     */
    virtual bool tryRegisterEntryScope() {
        return true;
    }

    /**
     * エントリー成立時にメールを送信するか判定する。
     *
     * @return メールを送信する場合true。
     */
    virtual bool shouldSendMail() {
        return false;
    }

    /**
     * 上位足と現在足の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() {
        return this.getTwoTimeFrameAlertText();
    }

    /**
     * 指定したElliotの最新ポイントが第1波または第3波か判定する。
     *
     * @param fromElliot 判定対象。
     * @return 最新ポイントが第1波または第3波の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) {
        return this.isElliot1or3(fromElliot);
    }

    /**
     * M5第3波のフィボナッチエクスパンション上限を確認する。
     *
     * @return M5第3波以外、またはFEが許容上限以下の場合true。
     */
    bool isM5EntryFibonacciExpansionWithin() {
        return this.isM5Elliot3FibonacciExpansionWithin();
    }

    /**
     * M5エントリー対象のH1表示波を使用済みとして登録する。
     *
     * @return H1表示波を新規登録できた場合true。
     */
    bool tryRegisterH1EntryScope() {
        return this.tryRegisterH1DisplayWaveEntry();
    }

    /**
     * 上位1足と現在足の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    string getTwoTimeFrameAlertText() {
        string text = "";
        Wave *latestWaveHigher1 = this.elliotHigher1.getLatestWave();

        text += latestWaveHigher1.trendLabel;
        text += this.elliotHigher1.getLatestPointElliotLabel();
        text += "-";
        text += this.elliotCurrent.getLatestPointElliotLabel();

        return text;
    }

    /**
     * 上位2足と現在足の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    string getThreeTimeFrameAlertText() {
        string text = "";
        Wave *latestWaveHigher2 = this.elliotHigher2.getLatestWave();

        text += latestWaveHigher2.trendLabel;
        text += this.elliotHigher2.getLatestPointElliotLabel();
        text += "-";
        text += this.elliotHigher1.getLatestPointElliotLabel();
        text += "-";
        text += this.elliotCurrent.getLatestPointElliotLabel();

        return text;
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
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード。
     * @param fromH1DirectionAlignmentMode H1エントリーの方向一致モード。
     */
    void initialize(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow,
        H1W1ConfirmationMode fromH1W1ConfirmationMode,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode
    ) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext, fromIsDrawArrow);

        this.h1DirectionAlignmentMode = fromH1DirectionAlignmentMode;
        this.h1W1ConfirmationMode = fromH1W1ConfirmationMode;
        this.h1DirectionAlignmentResult.reset();
        this.w1ConfirmationResult.reset();
        this.isDarwText = true;
        this.name = "MTF_3in3";
        this.fontSize = 20;
        this.resetEntryValidation();
    }

    /**
     * H1方向一致診断を今回の分析用の未判定状態へ初期化する。
     */
    void resetTimeFrameDirectionAlignmentResult() {
        this.h1DirectionAlignmentResult.reset();

        if (this.marketContext.timeFrame != PERIOD_H1) {
            return;
        }

        if (!isH1DirectionAlignmentModeValid(
                this.h1DirectionAlignmentMode
        )) {
            this.h1DirectionAlignmentResult.mode = "INVALID";
            this.h1DirectionAlignmentResult.state = "INVALID";
            this.h1DirectionAlignmentResult.isPassed = false;

            return;
        }

        this.h1DirectionAlignmentResult.mode =
            getH1DirectionAlignmentModeText(
                this.h1DirectionAlignmentMode
            );
        this.h1DirectionAlignmentResult.state = "NOT_EVALUATED";
        this.h1DirectionAlignmentResult.isPassed = false;
    }

    /**
     * 上位足確認診断を今回の分析用の未判定状態へ初期化する。
     */
    void resetTimeFrameHigherConfirmationResult() {
        this.w1ConfirmationResult.reset();

        if (this.marketContext.timeFrame != PERIOD_H1) {
            return;
        }

        if (!isH1W1ConfirmationModeValid(this.h1W1ConfirmationMode)) {
            this.w1ConfirmationResult.state = "INVALID";
            this.w1ConfirmationResult.isPassed = false;

            return;
        }

        this.w1ConfirmationResult.mode =
            getH1W1ConfirmationModeText(this.h1W1ConfirmationMode);

        if (this.h1W1ConfirmationMode == H1_W1_CONFIRMATION_OFF) {
            this.w1ConfirmationResult.state = "OFF";

            return;
        }

        this.w1ConfirmationResult.state = "NOT_EVALUATED";
        this.w1ConfirmationResult.isPassed = false;
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
    
};

const double ExpertAdvisorMTF_3in3::maxM5Elliot3FibonacciExpansionPercent = 161.8;
const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPips = 25.0;
const double ExpertAdvisorMTF_3in3::maxCloseEma200DiffPipsJpy = 25.0;

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF_3IN3_MQH
