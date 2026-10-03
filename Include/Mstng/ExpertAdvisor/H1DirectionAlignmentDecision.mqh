//+------------------------------------------------------------------+
//|                                 H1DirectionAlignmentDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentResult.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * H1を基準にMN1、W1、D1およびH4のElliott売買方向を判定する。
 */
class H1DirectionAlignmentDecision {
public:
    /**
     * H1方向一致の診断状態とモード別通過結果を生成する。
     * M15分析では元M15方向を維持し、補正後を含むH1方向との一致を必須とする。
     *
     * OBSERVEでは診断結果を保持しつつ、エントリーゲートは常に
     * 通過させる。REQUIREDでは取得不能と不正値をfail-closeする。
     *
     * @param fromMode H1方向一致モード。
     * @param fromElliotAll 複数時間足Elliott分析結果。
     * @param fromResult 診断結果の格納先。
     * @param fromOriginal 補正を採用した場合の元分析。それ以外はNULL。
     * @param fromCorrectionTimeFrame 補正したD1またはH4。M15分析ではH1も許可。補正なしはPERIOD_CURRENT。
     * @return エントリー判定を継続する場合true。
     */
    bool evaluate(
        const H1DirectionAlignmentMode fromMode,
        ElliotAll *fromElliotAll,
        H1DirectionAlignmentResult &fromResult,
        ElliotAll *fromOriginal = NULL,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame = PERIOD_CURRENT
    ) {
        fromResult.reset();

        if (!isH1DirectionAlignmentModeValid(fromMode)) {
            fromResult.mode = "INVALID";
            fromResult.state = "INVALID";
            fromResult.isPassed = false;

            return false;
        }

        fromResult.mode = getH1DirectionAlignmentModeText(fromMode);
        fromResult.isPassed = false;

        if (fromMode == H1_DIRECTION_ALIGNMENT_D1_TO_H1) {
            fromResult.state = "D1_TO_H1";
            fromResult.isAvailable = true;
            fromResult.isValid = true;
            fromResult.isPassed = true;

            if (fromElliotAll != NULL
                    && fromElliotAll.elliotCurrent != NULL) {
                fromResult.direction = this.getDirection(
                    fromElliotAll.elliotCurrent
                );
            }

            return true;
        }

        Elliot *elliotMn1 = NULL;
        Elliot *elliotW1 = NULL;
        Elliot *elliotD1 = NULL;
        Elliot *elliotH4 = NULL;
        Elliot *elliotH1 = NULL;

        if (fromElliotAll != NULL) {
            elliotMn1 = fromElliotAll.getElliot(PERIOD_MN1);
            elliotW1 = fromElliotAll.getElliot(PERIOD_W1);
            elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
            elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
            elliotH1 = fromElliotAll.getElliot(PERIOD_H1);
        }

        if (elliotMn1 == NULL
                || elliotW1 == NULL
                || elliotD1 == NULL
                || elliotH4 == NULL
                || elliotH1 == NULL) {
            fromResult.state = "UNAVAILABLE";

            return this.isObserveMode(fromMode);
        }

        fromResult.isAvailable = true;
        fromResult.direction = this.getDirection(elliotH1);

        bool isCorrectionValid = this.isCorrectionContextValid(
            fromElliotAll, fromOriginal, fromCorrectionTimeFrame
        );
        if (!this.isCurrentContextValid(fromElliotAll, elliotH1.isBuy,
                    fromOriginal, fromCorrectionTimeFrame)
                || !fromElliotAll.isAnalysisSucceeded || !isCorrectionValid
                || !this.isDirectionStateValid(elliotMn1, PERIOD_MN1,
                    fromOriginal, fromCorrectionTimeFrame, elliotH1.isBuy)
                || !this.isDirectionStateValid(elliotW1, PERIOD_W1,
                    fromOriginal, fromCorrectionTimeFrame, elliotH1.isBuy)
                || !this.isDirectionStateValid(elliotD1, PERIOD_D1,
                    fromOriginal, fromCorrectionTimeFrame, elliotH1.isBuy)
                || !this.isDirectionStateValid(elliotH4, PERIOD_H4,
                    fromOriginal, fromCorrectionTimeFrame, elliotH1.isBuy)
                || !this.isDirectionStateValid(elliotH1, PERIOD_H1,
                    fromOriginal, fromCorrectionTimeFrame, elliotH1.isBuy)) {
            fromResult.state = "INVALID";

            return this.isObserveMode(fromMode);
        }

        bool isH1Buy = elliotH1.isBuy;
        fromResult.isMn1DirectionMatched = elliotMn1.isBuy == isH1Buy;
        fromResult.isW1DirectionMatched = elliotW1.isBuy == isH1Buy;
        bool isD1DirectionMatched = elliotD1.isBuy == isH1Buy;
        bool isH4DirectionMatched = elliotH4.isBuy == isH1Buy;

        if (!isD1DirectionMatched || !isH4DirectionMatched) {
            fromResult.state = "INVALID";

            return this.isObserveMode(fromMode);
        }

        if (fromMode
                == H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED
                && !this.isW1Ema200StateValid(elliotW1)) {
            fromResult.state = "INVALID";

            return false;
        }

        fromResult.isValid = true;

        if (fromMode
                == H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED) {
            Mtf3In3HigherTimeFrameDecision decision;
            string rejectReason;
            Elliot *originalD1 = NULL;
            if (fromCorrectionTimeFrame == PERIOD_D1) {
                originalD1 = fromOriginal.getElliot(PERIOD_D1);
            }
            fromResult.isPassed = decision.evaluateDirection(
                isH1Buy, elliotMn1, elliotW1, elliotD1, rejectReason, originalD1
            );
            this.setMn1OrW1Ema200State(
                isH1Buy,
                elliotW1,
                fromResult
            );

            return fromResult.isPassed;
        }

        fromResult.isPassed = fromResult.isMn1DirectionMatched
            && fromResult.isW1DirectionMatched;
        this.setState(isH1Buy, fromResult);

        if (this.isObserveMode(fromMode)) {
            return true;
        }

        return fromResult.isPassed;
    }

private:
    /**
     * H1またはM15の現在足が分析コンテキストと指定方向に一致するか確認する。
     *
     * @return 現在足の参照・通貨・方向が整合する場合true。
     */
    bool isCurrentContextValid(
        ElliotAll *fromSelected,
        const bool fromIsBuy,
        ElliotAll *fromOriginal,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame
    ) {
        ENUM_TIMEFRAMES currentTimeFrame = fromSelected.marketContext.timeFrame;
        if (currentTimeFrame != PERIOD_H1 && currentTimeFrame != PERIOD_M15) {
            return false;
        }
        Elliot *elliotCurrent = fromSelected.getElliot(currentTimeFrame);
        if (elliotCurrent == NULL || fromSelected.elliotCurrent != elliotCurrent
                || elliotCurrent.marketContext.symbolName != fromSelected.marketContext.symbolName
                || elliotCurrent.isBuy != fromIsBuy) {
            return false;
        }
        return this.isDirectionStateValid(elliotCurrent, currentTimeFrame,
            fromOriginal, fromCorrectionTimeFrame, fromIsBuy);
    }

    /**
     * 指定モードが観測専用か判定する。
     *
     * @param fromMode 判定対象モード。
     * @return 観測専用の場合true。
     */
    bool isObserveMode(const H1DirectionAlignmentMode fromMode) {
        return fromMode == H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE;
    }

    /**
     * Elliott方向値と時間足が整合しているか確認する。
     *
     * @param fromElliot 判定対象。
     * @param fromTimeFrame 期待する時間足。
     * @param fromOriginal 明示補正時の元分析。通常判定はNULL。
     * @param fromCorrectionTimeFrame 方向差を許容する1足。
     * @param fromIsBuy 元の現在足を基準とする補正後方向。
     * @return 方向値が判定可能な場合true。
     */
    bool isDirectionStateValid(
        Elliot *fromElliot,
        const ENUM_TIMEFRAMES fromTimeFrame,
        ElliotAll *fromOriginal,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame,
        const bool fromIsBuy
    ) {
        Mtf3In3HigherTimeFrameDecision decision;
        if (fromOriginal == NULL) {
            return decision.isDirectionStateValid(fromElliot, fromTimeFrame);
        }
        Elliot *originalElliot = fromOriginal.getElliot(fromTimeFrame);
        if (fromTimeFrame == fromCorrectionTimeFrame) {
            return decision.isCorrectedDirectionStateValid(
                fromElliot, originalElliot, fromTimeFrame, fromIsBuy
            );
        }
        return decision.isDirectionStateValid(originalElliot, fromTimeFrame)
            && decision.isDirectionStateValid(fromElliot, fromTimeFrame)
            && fromElliot.marketContext.symbolName == originalElliot.marketContext.symbolName
            && fromElliot.isBuy == originalElliot.isBuy;
    }

    /**
     * 元の現在足方向を維持し、対象となる上位足の片足だけを補正した入力か確認する。
     *
     * @return 補正なし、または指定した1足だけが元の現在足と逆方向の場合true。
     */
    bool isCorrectionContextValid(
        ElliotAll *fromSelected,
        ElliotAll *fromOriginal,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame
    ) {
        if (fromCorrectionTimeFrame == PERIOD_CURRENT) {
            return fromOriginal == NULL;
        }
        if (fromOriginal == NULL || fromSelected == NULL || fromOriginal == fromSelected
                || !fromOriginal.isAnalysisSucceeded
                || (fromSelected.marketContext.timeFrame != PERIOD_H1
                    && fromSelected.marketContext.timeFrame != PERIOD_M15)
                || fromOriginal.marketContext.timeFrame != fromSelected.marketContext.timeFrame
                || fromOriginal.marketContext.symbolName != fromSelected.marketContext.symbolName
                || (fromCorrectionTimeFrame != PERIOD_D1 && fromCorrectionTimeFrame != PERIOD_H4
                    && (fromSelected.marketContext.timeFrame != PERIOD_M15
                        || fromCorrectionTimeFrame != PERIOD_H1))) {
            return false;
        }
        Elliot *originalD1 = fromOriginal.getElliot(PERIOD_D1);
        Elliot *originalH4 = fromOriginal.getElliot(PERIOD_H4);
        Elliot *originalH1 = fromOriginal.getElliot(PERIOD_H1);
        Elliot *originalCurrent = fromOriginal.getElliot(fromOriginal.marketContext.timeFrame);
        Mtf3In3HigherTimeFrameDecision decision;
        if (!decision.isDirectionStateValid(originalD1, PERIOD_D1)
                || !decision.isDirectionStateValid(originalH4, PERIOD_H4)
                || !decision.isDirectionStateValid(originalH1, PERIOD_H1)
                || originalCurrent == NULL
                || !this.isCurrentContextValid(
                    fromOriginal, originalCurrent.isBuy, NULL, PERIOD_CURRENT)) {
            return false;
        }
        bool originalIsBuy = originalCurrent.isBuy;
        if (fromCorrectionTimeFrame == PERIOD_D1) {
            return originalD1.isBuy != originalIsBuy && originalH4.isBuy == originalIsBuy
                && originalH1.isBuy == originalIsBuy;
        }
        if (fromCorrectionTimeFrame == PERIOD_H4) {
            return originalH4.isBuy != originalIsBuy && originalD1.isBuy == originalIsBuy
                && originalH1.isBuy == originalIsBuy;
        }
        return originalH1.isBuy != originalIsBuy && originalD1.isBuy == originalIsBuy
            && originalH4.isBuy == originalIsBuy;
    }

    /**
     * W1 EMA200の方向値と表示値が整合しているか確認する。
     *
     * @param fromElliotW1 W1分析結果。
     * @return BUY、SELLまたはNONEとして整合している場合true。
     */
    bool isW1Ema200StateValid(Elliot *fromElliotW1) {
        Mtf3In3HigherTimeFrameDecision decision;
        return decision.isEma200StateValid(fromElliotW1, PERIOD_W1);
    }

    /**
     * Elliott売買方向を文字列へ変換する。
     *
     * @param fromElliot 変換対象。
     * @return BUY、SELLまたはNONE。
     */
    string getDirection(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "NONE";
        }

        if (fromElliot.isBuy) {
            return "BUY";
        }

        return "SELL";
    }

    /**
     * MN1とW1の一致状態を設定する。
     *
     * @param fromIsBuy H1がBUY方向の場合true。
     * @param fromResult 診断結果。
     */
    void setState(
        const bool fromIsBuy,
        H1DirectionAlignmentResult &fromResult
    ) {
        if (fromResult.isMn1DirectionMatched
                && fromResult.isW1DirectionMatched) {
            if (fromIsBuy) {
                fromResult.state = "FULL_BUY";
            } else {
                fromResult.state = "FULL_SELL";
            }

            return;
        }

        if (!fromResult.isMn1DirectionMatched
                && !fromResult.isW1DirectionMatched) {
            fromResult.state = "MN1_W1_MISMATCH";

            return;
        }

        if (!fromResult.isMn1DirectionMatched) {
            fromResult.state = "MN1_MISMATCH";

            return;
        }

        fromResult.state = "W1_MISMATCH";
    }

    /**
     * MN1またはW1 EMA200を使用するモードの診断状態を設定する。
     *
     * @param fromIsBuy H1がBUY方向の場合true。
     * @param fromElliotW1 W1分析結果。
     * @param fromResult 診断結果。
     */
    void setMn1OrW1Ema200State(
        const bool fromIsBuy,
        Elliot *fromElliotW1,
        H1DirectionAlignmentResult &fromResult
    ) {
        if (!fromResult.isW1DirectionMatched) {
            this.setState(fromIsBuy, fromResult);

            return;
        }

        if (fromResult.isMn1DirectionMatched) {
            this.setState(fromIsBuy, fromResult);

            return;
        }

        bool isW1Ema200Matched = false;

        if (fromIsBuy && fromElliotW1.oscillator.ema200.isBuy) {
            isW1Ema200Matched = true;
        } else if (!fromIsBuy && fromElliotW1.oscillator.ema200.isSell) {
            isW1Ema200Matched = true;
        }

        if (isW1Ema200Matched) {
            if (fromIsBuy) {
                fromResult.state = "EMA200_FALLBACK_BUY";
            } else {
                fromResult.state = "EMA200_FALLBACK_SELL";
            }

            return;
        }

        fromResult.state = "MN1_EMA200_MISMATCH";
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_DECISION_MQH
