//+------------------------------------------------------------------+
//|                                 H1Ema200ConfirmationDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_DECISION_MQH

#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>

/**
 * H1エントリー方向に対するH1およびH4 EMA200方向を判定する。
 */
class H1Ema200ConfirmationDecision {
public:
    /**
     * モード別のEMA200方向条件を判定する。
     *
     * H1_ONLYではH4の状態を使用しない。H1_AND_H4_REQUIREDでは
     * H1とH4の両方がエントリー方向と一致する場合だけ通過させる。
     *
     * @param fromMode H1 EMA200確認モード。
     * @param fromIsBuy エントリーがBUY方向の場合true。
     * @param fromElliotH1 H1分析結果。
     * @param fromElliotH4 H4分析結果。
     * @return 選択モードのEMA200条件を満たす場合true。
     */
    bool evaluate(
        const H1Ema200ConfirmationMode fromMode,
        const bool fromIsBuy,
        Elliot *fromElliotH1,
        Elliot *fromElliotH4
    ) {
        if (!isH1Ema200ConfirmationModeValid(fromMode)) {
            return false;
        }

        if (!this.isDirectionMatched(
                fromElliotH1,
                PERIOD_H1,
                fromIsBuy
        )) {
            return false;
        }

        if (fromMode == H1_EMA200_CONFIRMATION_H1_ONLY) {
            return true;
        }

        return this.isDirectionMatched(
            fromElliotH4,
            PERIOD_H4,
            fromIsBuy
        );
    }

private:
    /**
     * 指定時間足のEMA200方向がエントリー方向と一致するか判定する。
     *
     * @param fromElliot 判定対象。
     * @param fromTimeFrame 期待する時間足。
     * @param fromIsBuy エントリーがBUY方向の場合true。
     * @return 時間足、フラグおよびラベルが整合して一致する場合true。
     */
    bool isDirectionMatched(
        Elliot *fromElliot,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromIsBuy
    ) {
        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame
                    != fromTimeFrame
                || fromElliot.oscillator.ema200.marketContext.timeFrame
                    != fromTimeFrame) {
            return false;
        }

        bool isEma200Buy = fromElliot.oscillator.ema200.isBuy;
        bool isEma200Sell = fromElliot.oscillator.ema200.isSell;
        string direction =
            fromElliot.oscillator.ema200.getBuySellLabel();

        if (fromIsBuy) {
            return isEma200Buy
                && !isEma200Sell
                && direction == "BUY";
        }

        return !isEma200Buy
            && isEma200Sell
            && direction == "SELL";
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_DECISION_MQH
