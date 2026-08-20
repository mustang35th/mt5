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
#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentResult.mqh>

/**
 * H1を基準にMN1、W1、D1およびH4のElliott売買方向を判定する。
 */
class H1DirectionAlignmentDecision {
public:
    /**
     * H1方向一致の診断状態とモード別通過結果を生成する。
     *
     * OBSERVEでは診断結果を保持しつつ、エントリーゲートは常に
     * 通過させる。REQUIREDでは取得不能と不正値をfail-closeする。
     *
     * @param fromMode H1方向一致モード。
     * @param fromElliotAll 複数時間足Elliott分析結果。
     * @param fromResult 診断結果の格納先。
     * @return エントリー判定を継続する場合true。
     */
    bool evaluate(
        const H1DirectionAlignmentMode fromMode,
        ElliotAll *fromElliotAll,
        H1DirectionAlignmentResult &fromResult
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

        if (fromElliotAll.elliotCurrent != elliotH1
                || !fromElliotAll.isAnalysisSucceeded
                || !this.isDirectionStateValid(elliotMn1, PERIOD_MN1)
                || !this.isDirectionStateValid(elliotW1, PERIOD_W1)
                || !this.isDirectionStateValid(elliotD1, PERIOD_D1)
                || !this.isDirectionStateValid(elliotH4, PERIOD_H4)
                || !this.isDirectionStateValid(elliotH1, PERIOD_H1)) {
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
            TrendAlignType alignType =
                ElliotDirectionAlignmentDecision::evaluateH1W1WithMn1OrEma200(
                    elliotH1.isBuy,
                    elliotH4.isBuy,
                    elliotD1.isBuy,
                    elliotW1.isBuy,
                    elliotMn1.isBuy,
                    elliotW1.oscillator.ema200.isBuy,
                    elliotW1.oscillator.ema200.isSell
                );
            fromResult.isPassed = this.isExpectedAlignType(
                isH1Buy,
                alignType
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
     * @return 方向値が判定可能な場合true。
     */
    bool isDirectionStateValid(
        Elliot *fromElliot,
        const ENUM_TIMEFRAMES fromTimeFrame
    ) {
        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame
                    != fromTimeFrame
                || fromElliot.isBuy != fromElliot.oscillator.isBuy) {
            return false;
        }

        if (fromElliot.isBuy) {
            return fromElliot.buySellLabel == "BUY";
        }

        return fromElliot.buySellLabel == "SELL";
    }

    /**
     * W1 EMA200の方向値と表示値が整合しているか確認する。
     *
     * @param fromElliotW1 W1分析結果。
     * @return BUY、SELLまたはNONEとして整合している場合true。
     */
    bool isW1Ema200StateValid(Elliot *fromElliotW1) {
        if (fromElliotW1 == NULL
                || fromElliotW1.oscillator.ema200.marketContext.timeFrame
                    != PERIOD_W1) {
            return false;
        }

        bool isEma200Buy = fromElliotW1.oscillator.ema200.isBuy;
        bool isEma200Sell = fromElliotW1.oscillator.ema200.isSell;
        string direction =
            fromElliotW1.oscillator.ema200.getBuySellLabel();

        if (isEma200Buy && !isEma200Sell) {
            return direction == "BUY";
        }

        if (!isEma200Buy && isEma200Sell) {
            return direction == "SELL";
        }

        if (!isEma200Buy && !isEma200Sell) {
            return direction == "NONE";
        }

        return false;
    }

    /**
     * 判定結果がH1の売買方向と一致しているか確認する。
     *
     * @param fromIsBuy H1がBUY方向の場合true。
     * @param fromAlignType 判定された一致方向。
     * @return H1方向と同じBUYまたはSELL一致の場合true。
     */
    bool isExpectedAlignType(
        const bool fromIsBuy,
        const TrendAlignType fromAlignType
    ) {
        if (fromIsBuy) {
            return fromAlignType == trendAlignBuy;
        }

        return fromAlignType == trendAlignSell;
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
