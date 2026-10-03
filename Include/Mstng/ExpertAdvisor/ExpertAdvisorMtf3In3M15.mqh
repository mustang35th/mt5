//+------------------------------------------------------------------+
//|                                      ExpertAdvisorMtf3In3M15.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\H1EntryWaveDecision.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>

/**
 * M15を現在足としてMTF_3in3エントリーを判定する。
 *
 * H1と同じ上位足条件に、M15の方向・波動・GMMA・EMA200および
 * 最新ZigZagポイントの確定条件を追加する。全条件が成立するまで
 * シグナル回数を消費せず、D1・H4・H1の片足補正はM15まで再分析する。
 * GMMAはM15だけを判定し、H1のGMMAは条件に使用しない。
 */
class ExpertAdvisorMtf3In3M15 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromDirectionCorrectionEnabled D1・H4・H1の片足方向補正を使用する場合true。
     */
    ExpertAdvisorMtf3In3M15(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        bool fromDirectionCorrectionEnabled = false
    ) : ExpertAdvisorMTF_3in3(
        fromMarketContext,
        fromIsDrawArrow,
        Mtf3In3H1Policy::getW1ConfirmationMode(),
        Mtf3In3H1Policy::getDirectionAlignmentMode(),
        Mtf3In3H1Policy::getEma200ConfirmationMode()
    ) {
        this.isDirectionCorrectionEnabled = fromDirectionCorrectionEnabled;
        this.correctedElliotAll = NULL;
        this.correctedTimeFrame = PERIOD_CURRENT;
    }

    /**
     * 所有する補正分析を解放する。
     */
    ~ExpertAdvisorMtf3In3M15() {
        this.releaseCorrectedElliotAll();
    }

    /**
     * 判定に採用した方向補正の時間足を取得する。
     *
     * @return 補正時はD1、H4またはH1、補正なしはPERIOD_CURRENT。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (this.correctedElliotAll != NULL && this.elliotAll == this.correctedElliotAll) {
            return this.correctedTimeFrame;
        }
        return PERIOD_CURRENT;
    }

protected:
    /**
     * 前回の補正分析を解放し、今回の診断結果を初期化する。
     */
    virtual void resetStrategySpecificAnalysisOutcome() override {
        ExpertAdvisorMTF_3in3::resetStrategySpecificAnalysisOutcome();
        this.releaseCorrectedElliotAll();
    }

    /**
     * 元M15方向を基準にD1・H4・H1の片足を補正し、M15まで再分析する。
     *
     * @param fromOriginal 元のM15分析。所有権は呼び出し元が保持する。
     * @return 全条件で参照する分析。分析不正または2足以上逆方向はNULL。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (this.marketContext.timeFrame != PERIOD_M15
                || fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_M15
                || fromOriginal.marketContext.symbolName != this.marketContext.symbolName) {
            return NULL;
        }
        Elliot *originalD1 = fromOriginal.getElliot(PERIOD_D1);
        Elliot *originalH4 = fromOriginal.getElliot(PERIOD_H4);
        Elliot *originalH1 = fromOriginal.getElliot(PERIOD_H1);
        Elliot *originalM15 = fromOriginal.getElliot(PERIOD_M15);
        Mtf3In3HigherTimeFrameDecision decision;
        if (!decision.isDirectionStateValid(originalD1, PERIOD_D1)
                || !decision.isDirectionStateValid(originalH4, PERIOD_H4)
                || !decision.isDirectionStateValid(originalH1, PERIOD_H1)
                || !decision.isDirectionStateValid(originalM15, PERIOD_M15)
                || fromOriginal.elliotCurrent != originalM15) {
            return NULL;
        }
        if (!this.isDirectionCorrectionEnabled) {
            return fromOriginal;
        }
        int mismatchCount = 0;
        ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_CURRENT;
        if (originalD1.isBuy != originalM15.isBuy) {
            mismatchCount++;
            correctionTimeFrame = PERIOD_D1;
        }
        if (originalH4.isBuy != originalM15.isBuy) {
            mismatchCount++;
            correctionTimeFrame = PERIOD_H4;
        }
        if (originalH1.isBuy != originalM15.isBuy) {
            mismatchCount++;
            correctionTimeFrame = PERIOD_H1;
        }
        if (mismatchCount == 0) {
            return fromOriginal;
        }
        if (mismatchCount > 1) {
            return NULL;
        }
        this.correctedElliotAll = new ElliotAll(this.marketContext);
        if (this.correctedElliotAll == NULL
                || !this.correctedElliotAll.analyzeWithDirectionCorrection(
                    fromOriginal, correctionTimeFrame, originalM15.isBuy)) {
            this.logger.error(__FUNCTION__, "M15 corrected analysis failed");
            this.releaseCorrectedElliotAll();
            return NULL;
        }
        this.correctedTimeFrame = correctionTimeFrame;
        return this.correctedElliotAll;
    }

    /**
     * H1と同じスプレッド上限を判定する。
     *
     * @return スプレッドが5.0 pips以下の場合true。
     */
    virtual bool isSpread() override {
        return this.elliotAll.todayRate.spread <= 5.0;
    }

    /**
     * H1の共通方向条件とM15の同方向を判定する。
     *
     * @return 全方向条件が成立する場合true。
     */
    virtual bool isTimeFrameDirectionAlignmentConditionMatched() override {
        H1DirectionAlignmentDecision decision;
        ElliotAll *originalAnalysis = NULL;
        ENUM_TIMEFRAMES correctionTimeFrame = this.getCorrectionTimeFrame();
        if (correctionTimeFrame != PERIOD_CURRENT) {
            originalAnalysis = this.getSourceElliotAll();
        }
        return decision.evaluate(
            this.h1DirectionAlignmentMode,
            this.elliotAll,
            this.h1DirectionAlignmentResult,
            originalAnalysis,
            correctionTimeFrame
        );
    }

    /**
     * 回数加算前にH4・H1・M15の第1波、第3波または有効な第5波を判定する。
     *
     * @return M15用の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M15) {
            return false;
        }

        return this.isEntryWave(this.elliotHigher2)
            && this.isEntryWave(this.elliotHigher1)
            && this.isEntryWave(this.elliotCurrent);
    }

    /**
     * H1と同じ第5波の構造条件を各時間足へ適用する。
     *
     * @param fromElliot H4、H1またはM15の分析。
     * @return 第1波、第3波または第3波に副次波がない有効な第5波の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) override {
        if (fromElliot == NULL) {
            return false;
        }
        ENUM_TIMEFRAMES timeFrame = fromElliot.marketContext.timeFrame;
        if (timeFrame != PERIOD_H4 && timeFrame != PERIOD_H1 && timeFrame != PERIOD_M15) {
            return false;
        }
        H1EntryWaveDecision decision;
        H1EntryWaveResult result;
        return decision.evaluate(fromElliot, timeFrame, result);
    }

    /**
     * H1共通EMA200条件にM15 EMA200の同方向一致を追加する。
     *
     * @return D1・H4・H1・M15のEMA200が同方向の場合true。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        H1Ema200ConfirmationDecision h1Decision;
        Mtf3In3HigherTimeFrameDecision decision;
        return h1Decision.evaluate(
            this.h1Ema200ConfirmationMode, this.isBuy,
            this.elliotH1, this.elliotH4, this.elliotD1
        ) && decision.isEma200DirectionMatched(this.elliotCurrent, PERIOD_M15, this.isBuy);
    }

    /**
     * H1のWave方向を再確認し、共通W1診断を記録する。
     *
     * @return H1条件を維持してM15のエントリー判定を続行できる場合true。
     */
    virtual bool isTimeFrameHigherConfirmationConditionMatched() override {
        if (this.elliotH1 == NULL || this.elliotH1.getLatestWave() == NULL
                || this.elliotH1.isUptrend() != this.isBuy) {
            return false;
        }
        H1W1ConfirmationDecision decision;
        return decision.evaluate(
            this.h1W1ConfirmationMode, this.isBuy,
            this.elliotAll.getElliot(PERIOD_W1), this.w1ConfirmationResult
        );
    }

    /**
     * H1と同じくEMA200の距離制限を適用しない。
     *
     * @return 常にfalse。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        return false;
    }

    /**
     * H4、H1およびM15の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        return this.getThreeTimeFrameAlertText();
    }

    /**
     * 採用分析のH4・H1・M15波動と補正時間足をチャートへ表示する。
     *
     * @return 判定に採用した分析のアラート文言。
     */
    virtual string getChartAlertText() override {
        string chartAlertText = this.getThreeTimeFrameAlertText(this.elliotAll);
        ENUM_TIMEFRAMES correctionTimeFrame = this.getCorrectionTimeFrame();
        if (chartAlertText != "" && correctionTimeFrame != PERIOD_CURRENT) {
            chartAlertText += " [" + TimeUtil::convertTimeFrameToString(correctionTimeFrame) + "補正]";
        }
        return chartAlertText;
    }

private:
    /** D1・H4・H1の片足方向補正を使用する場合true。 */
    bool isDirectionCorrectionEnabled;

    /** 全条件の判定に採用する補正分析。本クラスが所有する。 */
    ElliotAll *correctedElliotAll;

    /** 補正した時間足。補正なしはPERIOD_CURRENT。 */
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

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH
