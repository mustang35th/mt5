//+------------------------------------------------------------------+
//|                                     H1W1ConfirmationDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_DECISION_MQH

#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationResult.mqh>

/**
 * H1エントリー方向に対するW1方向とW1 EMA200方向を判定する。
 */
class H1W1ConfirmationDecision {
public:
    /**
     * W1確認の診断状態とモード別通過結果を生成する。
     *
     * OBSERVE_ONLYではOR条件の診断結果をisPassedへ保持するが、
     * 呼び出し元のエントリーゲートは常に通過させる。
     *
     * @param fromMode W1確認モード。
     * @param fromIsBuy エントリーがBUY方向の場合true。
     * @param fromElliotW1 W1分析結果。
     * @param fromResult 診断結果の格納先。
     * @return エントリー判定を継続する場合true。
     */
    bool evaluate(
        const H1W1ConfirmationMode fromMode,
        const bool fromIsBuy,
        Elliot *fromElliotW1,
        H1W1ConfirmationResult &fromResult
    ) {
        fromResult.reset();

        if (!isH1W1ConfirmationModeValid(fromMode)) {
            fromResult.mode = "OFF";
            fromResult.state = "INVALID";
            fromResult.isPassed = false;

            return false;
        }

        fromResult.mode = getH1W1ConfirmationModeText(fromMode);

        if (fromMode == H1_W1_CONFIRMATION_OFF) {
            fromResult.state = "OFF";

            return true;
        }

        if (fromElliotW1 == NULL) {
            fromResult.state = "UNAVAILABLE";
            fromResult.isPassed = false;

            return fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY;
        }

        fromResult.isAvailable = true;

        if (!this.isW1DirectionStateValid(fromElliotW1)) {
            fromResult.state = "INVALID";
            fromResult.isPassed = false;

            return fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY;
        }

        fromResult.ema200Direction =
            fromElliotW1.oscillator.ema200.getBuySellLabel();

        if (!this.isEma200StateValid(
                fromElliotW1,
                fromResult.ema200Direction
        )) {
            fromResult.state = "INVALID";
            fromResult.isPassed = false;

            return fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY;
        }

        fromResult.isValid = true;
        fromResult.isDirectionMatched =
            fromElliotW1.isBuy == fromIsBuy;
        fromResult.isEma200Matched =
            (fromIsBuy && fromResult.ema200Direction == "BUY")
            || (!fromIsBuy && fromResult.ema200Direction == "SELL");
        bool isEma200None = fromResult.ema200Direction == "NONE";

        this.setState(isEma200None, fromResult);

        bool isOrPassed = fromResult.isDirectionMatched
            || fromResult.isEma200Matched;
        bool isAndPassed = fromResult.isDirectionMatched
            && fromResult.isEma200Matched;
        fromResult.isPassed = isOrPassed;

        if (fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY) {
            return true;
        }

        if (fromMode == H1_W1_CONFIRMATION_DIRECTION_OR_EMA200) {
            return isOrPassed;
        }

        fromResult.isPassed = isAndPassed;

        return isAndPassed;
    }

private:
    /**
     * W1方向の分析結果がW1として整合しているか確認する。
     *
     * @param fromElliotW1 W1分析結果。
     * @return 時間足と方向値が整合する場合true。
     */
    bool isW1DirectionStateValid(Elliot *fromElliotW1) {
        if (fromElliotW1 == NULL
                || fromElliotW1.marketContext.timeFrame != PERIOD_W1
                || fromElliotW1.oscillator.marketContext.timeFrame
                    != PERIOD_W1
                || fromElliotW1.oscillator.ema200.marketContext.timeFrame
                    != PERIOD_W1
                || fromElliotW1.isBuy
                    != fromElliotW1.oscillator.isBuy) {
            return false;
        }

        if (fromElliotW1.isBuy) {
            return fromElliotW1.buySellLabel == "BUY";
        }

        return fromElliotW1.buySellLabel == "SELL";
    }

    /**
     * EMA200方向文字列が判定可能か確認する。
     *
     * @param fromElliotW1 W1分析結果。
     * @param fromDirection EMA200方向文字列。
     * @return BUY、SELLまたはNONEの場合true。
     */
    bool isEma200StateValid(
        Elliot *fromElliotW1,
        const string fromDirection
    ) {
        if (fromElliotW1 == NULL) {
            return false;
        }

        bool isEma200Buy = fromElliotW1.oscillator.ema200.isBuy;
        bool isEma200Sell = fromElliotW1.oscillator.ema200.isSell;

        if (isEma200Buy && !isEma200Sell) {
            return fromDirection == "BUY";
        }

        if (!isEma200Buy && isEma200Sell) {
            return fromDirection == "SELL";
        }

        if (!isEma200Buy && !isEma200Sell) {
            return fromDirection == "NONE";
        }

        return false;
    }

    /**
     * W1方向とEMA200方向の組み合わせから診断状態を設定する。
     *
     * @param fromIsEma200None EMA200がNONEの場合true。
     * @param fromResult 診断結果。
     */
    void setState(
        const bool fromIsEma200None,
        H1W1ConfirmationResult &fromResult
    ) {
        if (fromResult.isDirectionMatched
                && fromResult.isEma200Matched) {
            fromResult.state = "STRONG";

            return;
        }

        if (fromResult.isDirectionMatched) {
            if (fromIsEma200None) {
                fromResult.state = "DIRECTION_ONLY";
            } else {
                fromResult.state = "EMA_CONFLICT";
            }

            return;
        }

        if (fromResult.isEma200Matched) {
            fromResult.state = "EMA_ONLY";

            return;
        }

        if (fromIsEma200None) {
            fromResult.state = "REJECT_NONE";

            return;
        }

        fromResult.state = "REJECT";
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_DECISION_MQH
