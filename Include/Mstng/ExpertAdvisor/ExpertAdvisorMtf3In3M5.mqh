//+------------------------------------------------------------------+
//|                                       ExpertAdvisorMtf3In3M5.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * M5を現在足としてMTF_3in3エントリーを判定する。
 *
 * 通常版はM15・M5の主波1・3、従来ポリシーはM5の1・3・A・C波を対象とし、M5固有の
 * FE上限、H1表示波の重複制限および成立時のメール送信を管理する。
 * 通常版M5ではD1からM5の元方向一致とH1・M15・M5のEMA200一致を使用する。
 * その他の呼び出し元では従来の上位足条件と片足方向補正を維持する。
 */
class ExpertAdvisorMtf3In3M5 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromRequireMn1AndW1Ema200 MN1方向とW1 EMA200の両方を必須にする場合true。
     * @param fromD1ToM5EntryPolicyEnabled 補正なしのD1～M5方向一致とH1～M5のEMA200一致を使用する場合true。
     * @param fromCurrencyStrengthMinimumRankDifference 通常版M5で両期間に要求する最低順位差。
     */
    ExpertAdvisorMtf3In3M5(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        bool fromRequireMn1AndW1Ema200 = false,
        bool fromD1ToM5EntryPolicyEnabled = false,
        int fromCurrencyStrengthMinimumRankDifference = 4
    ) : ExpertAdvisorMTF_3in3(fromMarketContext, fromIsDrawArrow) {
        this.isMn1AndW1Ema200Required = fromRequireMn1AndW1Ema200;
        this.isD1ToM5EntryPolicyEnabled = fromD1ToM5EntryPolicyEnabled;
        this.currencyStrengthMinimumRankDifference = fromCurrencyStrengthMinimumRankDifference;
        this.correctedElliotAll = NULL;
        this.correctedTimeFrame = PERIOD_CURRENT;
    }

    /**
     * 所有する補正分析を解放する。
     */
    ~ExpertAdvisorMtf3In3M5() {
        this.releaseCorrectedElliotAll();
    }

    /**
     * 直近の判定に採用した補正時間足を取得する。
     *
     * @return 補正分析の採用時はH4またはH1。それ以外はPERIOD_CURRENT。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (this.correctedElliotAll != NULL
                && this.elliotAll == this.correctedElliotAll) {
            return this.correctedTimeFrame;
        }

        return PERIOD_CURRENT;
    }

protected:
    /**
     * 通常版M5の最低順位差を取得する。従来ポリシーは方向一致のみとする。
     *
     * @return 両期間に要求する最低順位差。
     */
    virtual int getCurrencyStrengthMinimumRankDifference() override {
        if (this.isD1ToM5EntryPolicyEnabled) {
            return this.currencyStrengthMinimumRankDifference;
        }

        return 1;
    }

    /**
     * M5エントリーのスプレッドが全通貨共通の許容範囲内か判定する。
     *
     * @return スプレッドが5.0 pips以下の場合true。
     */
    virtual bool isSpread() override {
        return this.elliotAll.todayRate.spread <= 5.0;
    }

    /**
     * 前回の補正分析を破棄し、今回の判定結果を初期化する。
     */
    virtual void resetStrategySpecificAnalysisOutcome() override {
        ExpertAdvisorMTF_3in3::resetStrategySpecificAnalysisOutcome();
        this.releaseCorrectedElliotAll();
    }

    /**
     * 元のH4・H1方向から、今回の全エントリー条件へ使用する分析を選択する。
     *
     * D1～M5ポリシーでは元分析を採用し、方向補正を実行しない。
     * 両足同方向なら元分析を採用し、片足逆方向ならその足を補正してM5まで
     * 再分析する。両足逆方向または補正失敗の場合は判定対象外とする。
     *
     * @param fromOriginal 補正前の分析結果。所有権は呼び出し元が保持する。
     * @return 採用する分析への非所有参照。判定対象外の場合はNULL。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (this.marketContext.timeFrame != PERIOD_M5
                || fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_M5
                || fromOriginal.marketContext.symbolName != this.marketContext.symbolName) {
            return NULL;
        }

        if (this.isD1ToM5EntryPolicyEnabled) {
            return fromOriginal;
        }

        Elliot *originalH4 = fromOriginal.getElliot(PERIOD_H4);
        Elliot *originalH1 = fromOriginal.getElliot(PERIOD_H1);
        Elliot *originalCurrent = fromOriginal.getElliot(PERIOD_M5);
        Mtf3In3HigherTimeFrameDecision decision;
        if (!decision.isDirectionStateValid(originalH4, PERIOD_H4)
                || !decision.isDirectionStateValid(originalH1, PERIOD_H1)
                || !decision.isDirectionStateValid(originalCurrent, PERIOD_M5)) {
            return NULL;
        }

        bool isH4Matched = originalH4.isBuy == originalCurrent.isBuy;
        bool isH1Matched = originalH1.isBuy == originalCurrent.isBuy;
        if (isH4Matched && isH1Matched) {
            return fromOriginal;
        }

        if (!isH4Matched && !isH1Matched) {
            return NULL;
        }

        ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_H1;
        if (!isH4Matched) {
            correctionTimeFrame = PERIOD_H4;
        }

        this.correctedElliotAll = new ElliotAll(this.marketContext);
        if (this.correctedElliotAll == NULL
                || !this.correctedElliotAll.analyzeWithDirectionCorrection(
                    fromOriginal, correctionTimeFrame, originalCurrent.isBuy)) {
            this.logger.error(__FUNCTION__, "M5 corrected analysis failed");
            this.releaseCorrectedElliotAll();
            return NULL;
        }

        this.correctedTimeFrame = correctionTimeFrame;

        return this.correctedElliotAll;
    }

    /**
     * M5ではEMA200距離を診断用に保持し、エントリー制限を一旦無効にする。
     *
     * @return 常にfalse。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        return false;
    }

    /**
     * ポリシーに応じた対象足のEMA200がM5分析方向と一致するか判定する。
     * 通常版はH1・M15・M5、従来ポリシーはD1・H4も確認する。
     *
     * @return 対象足すべてが有効かつ同方向の場合true。NONEは許可しない。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }

        Mtf3In3HigherTimeFrameDecision decision;
        ENUM_TIMEFRAMES timeFrames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        int firstTimeFrameIndex = 0;
        if (this.isD1ToM5EntryPolicyEnabled) {
            firstTimeFrameIndex = 2;
        }

        for (int i = firstTimeFrameIndex; i < ArraySize(timeFrames); i++) {
            if (!decision.isEma200DirectionMatched(
                    this.elliotAll.getElliot(timeFrames[i]), timeFrames[i], this.isBuy)) {
                return false;
            }
        }

        return true;
    }

    /**
     * 通常版ではD1・H4・H1・M15・M5の元方向がすべて一致するか判定する。
     * 従来ポリシーではM15と、H4またはH1の同方向一致を確認する。
     *
     * @return M5固有の分析方向条件を満たす場合true。
     */
    virtual bool isTimeFrameAnalysisDirectionConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }

        if (this.isD1ToM5EntryPolicyEnabled) {
            Mtf3In3HigherTimeFrameDecision decision;
            ENUM_TIMEFRAMES timeFrames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
            for (int i = 0; i < ArraySize(timeFrames); i++) {
                Elliot *elliot = this.elliotAll.getElliot(timeFrames[i]);
                if (!decision.isDirectionStateValid(elliot, timeFrames[i])
                        || elliot.isBuy != this.isBuy) {
                    return false;
                }
            }

            return true;
        }

        return this.elliotAll.isBuySellH4OrH1AndM15();
    }

    /**
     * 従来ポリシーのMN1・W1・D1追加条件をM5分析方向で判定する。
     * D1～M5ポリシーでは方向とEMA200を専用判定で確認し、追加条件を使用しない。
     *
     * @return 上位足条件を満たす場合true。
     */
    virtual bool isTimeFrameDirectionAlignmentConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }

        if (this.isD1ToM5EntryPolicyEnabled) {
            return true;
        }

        Mtf3In3HigherTimeFrameDecision decision;
        string rejectReason;
        bool isPassed = decision.evaluate(this.elliotAll, this.isBuy, rejectReason);
        if (isPassed && this.isMn1AndW1Ema200Required) {
            Elliot *elliotMn1 = this.elliotAll.getElliot(PERIOD_MN1);
            if (elliotMn1.isBuy != this.isBuy) {
                rejectReason = "MN1_DIRECTION_MISMATCH";
                isPassed = false;
            } else if (!decision.isEma200DirectionMatched(
                    this.elliotAll.getElliot(PERIOD_W1), PERIOD_W1, this.isBuy)) {
                rejectReason = "W1_EMA200_MISMATCH";
                isPassed = false;
            }
        }

        if (!isPassed) {
            this.logger.debug(__FUNCTION__, "higher timeframe rejected: " + rejectReason);
        }

        return isPassed;
    }

    /**
     * 通常版はM15・M5両方の主波1・3を、初回回数の加算前に確認する。
     * 従来ポリシーではM5の主波だけを判定する。
     *
     * @return M5用の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }

        if (!this.isEntryWave(this.elliotCurrent)) {
            return false;
        }

        if (this.isD1ToM5EntryPolicyEnabled) {
            Elliot *m15Analysis = this.elliotAll.getElliot(PERIOD_M15);
            if (m15Analysis == NULL || m15Analysis.marketContext.timeFrame != PERIOD_M15) {
                return false;
            }

            ZigZagPoint *latestPoint = m15Analysis.getLatestPoint();
            if (latestPoint == NULL) {
                return false;
            }

            return latestPoint.elliotLabel == "1" || latestPoint.elliotLabel == "3";
        }

        return true;
    }

    /**
     * M5の最新主波を判定する。通常版は1・3、従来ポリシーは1・3・A・Cを許可する。
     *
     * @param fromElliot 判定対象。副次波ラベルは使用しない。
     * @return M5の主波がエントリー対象の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) override {
        if (fromElliot == NULL || fromElliot.marketContext.timeFrame != PERIOD_M5) {
            return false;
        }

        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();
        if (latestPoint == NULL) {
            return false;
        }

        string elliotLabel = latestPoint.elliotLabel;

        if (this.isD1ToM5EntryPolicyEnabled) {
            return elliotLabel == "1" || elliotLabel == "3";
        }

        return elliotLabel == "1" || elliotLabel == "3"
            || elliotLabel == "A" || elliotLabel == "C";
    }

    /**
     * M5第3波・C波のフィボナッチエクスパンション上限を確認する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return M5固有の追加条件を満たす場合true。
     */
    virtual bool isTimeFrameEntryConditionMatched(
        string &fromRejectReason
    ) override {
        fromRejectReason = "";

        if (this.isM5EntryFibonacciExpansionWithin()) {
            return true;
        }

        fromRejectReason = "M5_ELLIOT3_FE_REJECTED";
        if (this.elliotCurrent != NULL) {
            ZigZagPoint *latestPoint = this.elliotCurrent.getLatestPoint();
            if (latestPoint != NULL && latestPoint.elliotLabel == "C") {
                fromRejectReason = "M5_ELLIOTC_FE_REJECTED";
            }
        }

        return false;
    }

    /**
     * M5エントリー対象のH1表示波を使用済みとして登録する。
     *
     * @return 登録不要、またはH1表示波を新規登録できた場合true。
     */
    virtual bool tryRegisterEntryScope() override {
        return this.tryRegisterH1EntryScope();
    }

    /**
     * M5エントリー成立時にメールを送信するか判定する。
     *
     * @return 通常版ZigZagElliot以外の場合true。
     */
    virtual bool shouldSendMail() override {
        return MQLInfoString(MQL_PROGRAM_NAME) != "ZigZagElliot";
    }

    /**
     * 元分析のH1、M15およびM5から既存履歴用のアラート文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        return this.getThreeTimeFrameAlertText();
    }

    /**
     * 判定に採用したH1・M15・M5の波動をチャートへ表示する。
     *
     * @return 採用した波動ラベル。補正分析の場合は補正した時間足を末尾へ付ける。
     */
    virtual string getChartAlertText() override {
        string chartAlertText = this.getThreeTimeFrameAlertText(this.elliotAll, true);
        if (chartAlertText == "" || this.correctedElliotAll == NULL
                || this.elliotAll != this.correctedElliotAll) {
            return chartAlertText;
        }

        if (this.correctedTimeFrame == PERIOD_H1) {
            chartAlertText += " [H1C]";
        } else if (this.correctedTimeFrame == PERIOD_H4) {
            chartAlertText += " [H4C]";
        }

        return chartAlertText;
    }

    /**
     * 補正採用時は画面と同じ件名、および補正前後の全分析をメールへ渡す。
     *
     * 送信設定と共通情報は元分析を使用し、分析結果の所有権は移動しない。
     */
    virtual void sendAlertMail() override {
        ElliotAll *sourceAnalysis = this.getSourceElliotAll();
        if (this.correctedElliotAll != NULL
                && this.elliotAll == this.correctedElliotAll) {
            Mail::sendMail(
                sourceAnalysis,
                this.isSendMail,
                this.elliotAll,
                this.correctedTimeFrame,
                this.getChartAlertText()
            );
            return;
        }

        Mail::sendMail(sourceAnalysis, this.isSendMail);
    }

private:
    /** 通常版M5の通貨強弱フィルタで両期間に要求する最低順位差。 */
    int currencyStrengthMinimumRankDifference;

    /** MN1方向とW1 EMA200の両方を必須にする場合true。 */
    bool isMn1AndW1Ema200Required;

    /** 補正なしのD1～M5方向一致とH1・M15・M5のEMA200一致を使用する場合true。 */
    bool isD1ToM5EntryPolicyEnabled;

    /** 全エントリー条件の判定に使用する補正分析。本クラスが所有する。 */
    ElliotAll *correctedElliotAll;

    /** 補正分析で方向を変更した時間足。補正なしはPERIOD_CURRENT。 */
    ENUM_TIMEFRAMES correctedTimeFrame;

    /**
     * 所有する補正分析を解放し、次回への持ち越しを防止する。
     */
    void releaseCorrectedElliotAll() {
        if (this.correctedElliotAll != NULL) {
            delete this.correctedElliotAll;
            this.correctedElliotAll = NULL;
        }
        this.correctedTimeFrame = PERIOD_CURRENT;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH
