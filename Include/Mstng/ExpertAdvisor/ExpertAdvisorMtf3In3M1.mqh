//+------------------------------------------------------------------+
//|                                  ExpertAdvisorMtf3In3M1.mqh      |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M1_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M1_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * M1エントリーの波動番号をM5・M1の第1波または第3波で判定する。
 *
 * M15の波動番号は制限せず、EMA200の方向・距離をエントリー条件に使用しない。
 * 方向補正が有効な場合はD1・M5・M1の元方向一致を必須とし、
 * H4・H1・M15の逆方向1足だけを補正してM1まで再分析する。
 */
class ExpertAdvisorMtf3In3M1 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと従来の互換設定を使用して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromH1W1ConfirmationMode 共通クラスへ引き継ぐW1確認モード。
     * @param fromH1DirectionAlignmentMode 共通クラスへ引き継ぐ方向一致モード。
     * @param fromH1Ema200ConfirmationMode 共通クラスへ引き継ぐEMA200確認モード。
     * @param fromDirectionCorrectionEnabled H4・H1・M15の逆方向1足を補正する場合true。
     */
    ExpertAdvisorMtf3In3M1(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY,
        bool fromDirectionCorrectionEnabled = false
    ) : ExpertAdvisorMTF_3in3(
        fromMarketContext,
        fromIsDrawArrow,
        fromH1W1ConfirmationMode,
        fromH1DirectionAlignmentMode,
        fromH1Ema200ConfirmationMode
    ) {
        this.isDirectionCorrectionEnabled = fromDirectionCorrectionEnabled;
        this.correctedElliotAll = NULL;
        this.correctedTimeFrame = PERIOD_CURRENT;
    }

    /**
     * 所有する補正分析を解放する。
     */
    ~ExpertAdvisorMtf3In3M1() {
        this.releaseCorrectedElliotAll();
    }

    /**
     * 直近の判定で方向を補正した時間足を取得する。
     *
     * @return 補正分析採用時はH4・H1・M15、それ以外はPERIOD_CURRENT。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (this.correctedElliotAll != NULL && this.elliotAll == this.correctedElliotAll) {
            return this.correctedTimeFrame;
        }

        return PERIOD_CURRENT;
    }

protected:
    /**
     * 共通の診断状態を初期化し、前回の補正分析を解放する。
     */
    virtual void resetStrategySpecificAnalysisOutcome() override {
        ExpertAdvisorMTF_3in3::resetStrategySpecificAnalysisOutcome();
        this.releaseCorrectedElliotAll();
    }

    /**
     * 元方向から、今回のエントリー条件へ使用する分析を選択する。
     *
     * @param fromOriginal 補正前のM1分析。所有権は呼び出し元が保持する。
     * @return 元分析または補正分析。方向不一致・不正・補正失敗の場合NULL。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (!this.isDirectionCorrectionEnabled) {
            return fromOriginal;
        }

        if (this.marketContext.timeFrame != PERIOD_M1 || fromOriginal == NULL
                || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_M1
                || fromOriginal.marketContext.symbolName != this.marketContext.symbolName) {
            return NULL;
        }

        ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_CURRENT;
        if (!this.resolveDirectionCorrectionTimeFrame(fromOriginal, correctionTimeFrame)) {
            return NULL;
        }

        if (correctionTimeFrame == PERIOD_CURRENT) {
            return fromOriginal;
        }

        this.correctedElliotAll = new ElliotAll(this.marketContext);
        if (this.correctedElliotAll == NULL
                || !this.correctedElliotAll.analyzeWithDirectionCorrection(
                    fromOriginal, correctionTimeFrame, fromOriginal.elliotCurrent.isBuy)) {
            this.logger.error(__FUNCTION__, "M1 corrected analysis failed");
            this.releaseCorrectedElliotAll();

            return NULL;
        }

        this.correctedTimeFrame = correctionTimeFrame;

        return this.correctedElliotAll;
    }

    /**
     * 明示した補正1足を含め、D1からM1までの分析方向一致を判定する。
     *
     * @return 元方向と採用方向がM1の補正条件を満たす場合true。
     */
    virtual bool isTimeFrameAnalysisDirectionConditionMatched() override {
        if (!this.isDirectionCorrectionEnabled) {
            return ExpertAdvisorMTF_3in3::isTimeFrameAnalysisDirectionConditionMatched();
        }

        ElliotAll *sourceAnalysis = this.getSourceElliotAll();
        if (this.marketContext.timeFrame != PERIOD_M1 || this.elliotAll == NULL
                || sourceAnalysis == NULL) {
            return false;
        }

        ENUM_TIMEFRAMES expectedCorrectionTimeFrame = PERIOD_CURRENT;
        if (!this.resolveDirectionCorrectionTimeFrame(sourceAnalysis, expectedCorrectionTimeFrame)
                || this.getCorrectionTimeFrame() != expectedCorrectionTimeFrame
                || sourceAnalysis.elliotCurrent.isBuy != this.isBuy) {
            return false;
        }

        Mtf3In3HigherTimeFrameDecision decision;
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1
        };
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = this.elliotAll.getElliot(timeFrames[i]);
            if (timeFrames[i] == expectedCorrectionTimeFrame) {
                if (!decision.isCorrectedDirectionStateValid(
                        elliot, sourceAnalysis.getElliot(timeFrames[i]), timeFrames[i], this.isBuy)) {
                    return false;
                }
            } else if (!decision.isDirectionStateValid(elliot, timeFrames[i])
                    || elliot.isBuy != this.isBuy) {
                return false;
            }
        }

        return true;
    }

    /**
     * M5・M1の最新主波がそれぞれ第1波または第3波か判定する。
     *
     * @return 両時間足が波動番号条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.elliotM5 == NULL || this.elliotM1 == NULL
                || this.elliotM5.getLatestPoint() == NULL || this.elliotM1.getLatestPoint() == NULL) {
            return false;
        }

        return this.isEntryWave(this.elliotM5)
            && this.isEntryWave(this.elliotM1);
    }

    /**
     * M1ではEMA200の方向一致をエントリー条件に使用しない。
     *
     * @return 常にtrue。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        return true;
    }

    /**
     * M1ではEMA200距離を診断用に保持し、エントリーの距離制限を使用しない。
     *
     * @return 常にfalse。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        return false;
    }

    /**
     * 補正後のM5・M1波動と補正時間足をチャートのアラートへ表示する。
     *
     * @return 補正なしの場合は従来の表示文字列。
     */
    virtual string getChartAlertText() override {
        if (this.getCorrectionTimeFrame() == PERIOD_CURRENT) {
            return this.alertText;
        }

        if (this.elliotM5 == NULL || this.elliotM1 == NULL
                || this.elliotM5.getLatestWave() == NULL
                || this.elliotM5.getLatestPoint() == NULL || this.elliotM1.getLatestPoint() == NULL) {
            return "";
        }

        string text = this.elliotM5.getLatestWave().trendLabel;
        text += this.elliotM5.getLatestPointElliotLabel();
        text += "-" + this.elliotM1.getLatestPointElliotLabel();
        text += " [" + TimeUtil::convertTimeFrameToString(this.correctedTimeFrame) + "補正]";

        return text;
    }

private:
    /** H4・H1・M15の逆方向1足を補正する場合true。 */
    bool isDirectionCorrectionEnabled;

    /** 全エントリー条件の判定に使用する補正分析。本クラスが所有する。 */
    ElliotAll *correctedElliotAll;

    /** 補正した時間足。補正なしの場合はPERIOD_CURRENT。 */
    ENUM_TIMEFRAMES correctedTimeFrame;

    /**
     * D1・M5・M1の元方向一致を確認し、逆方向1足だけを補正対象として返す。
     *
     * @param fromOriginal 補正前のM1分析。
     * @param fromCorrectionTimeFrame 全足一致・拒否時はPERIOD_CURRENT。
     * @return 全方向が有効で、H4・H1・M15の逆方向が1足以下の場合true。
     */
    bool resolveDirectionCorrectionTimeFrame(
        ElliotAll *fromOriginal,
        ENUM_TIMEFRAMES &fromCorrectionTimeFrame
    ) {
        fromCorrectionTimeFrame = PERIOD_CURRENT;
        if (fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_M1) {
            return false;
        }

        Mtf3In3HigherTimeFrameDecision decision;
        Elliot *originalCurrent = fromOriginal.getElliot(PERIOD_M1);
        if (!decision.isDirectionStateValid(originalCurrent, PERIOD_M1)
                || fromOriginal.elliotCurrent != originalCurrent
                || originalCurrent.marketContext.symbolName != fromOriginal.marketContext.symbolName) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_CURRENT;
        int mismatchCount = 0;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromOriginal.getElliot(timeFrames[i]);
            if (!decision.isDirectionStateValid(elliot, timeFrames[i])
                    || elliot.marketContext.symbolName != originalCurrent.marketContext.symbolName) {
                return false;
            }

            if (elliot.isBuy != originalCurrent.isBuy) {
                if (timeFrames[i] == PERIOD_D1 || timeFrames[i] == PERIOD_M5) {
                    return false;
                }

                mismatchCount++;
                correctionTimeFrame = timeFrames[i];
            }
        }

        if (mismatchCount > 1) {
            return false;
        }

        fromCorrectionTimeFrame = correctionTimeFrame;

        return true;
    }

    /**
     * 所有する補正分析を解放し、次回へ持ち越さない。
     */
    void releaseCorrectedElliotAll() {
        if (this.correctedElliotAll != NULL) {
            delete this.correctedElliotAll;
            this.correctedElliotAll = NULL;
        }

        this.correctedTimeFrame = PERIOD_CURRENT;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M1_MQH
