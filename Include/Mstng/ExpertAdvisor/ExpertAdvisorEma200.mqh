//+------------------------------------------------------------------+
//|                                          ExpertAdvisorEma200.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EMA200_MQH
#define MSTNG_EXPERT_ADVISOR_EMA200_MQH

#include <Mstng\Elliot\Elliot.mqh>

/**
 * ExpertAdvisor用EMA200判定クラス
 */
class ExpertAdvisorEma200 {
public:
    /** BUY方向の場合true */
    bool isBuy;

    /**
     * コンストラクタ
     */
    ExpertAdvisorEma200() {
        this.isBuy = true;
    }

    /**
     * コンストラクタ
     *
     * @param fromIsBuy BUY方向の場合true
     */
    ExpertAdvisorEma200(bool fromIsBuy) {
        this.isBuy = fromIsBuy;
    }

    /**
     * 売買方向を設定する。
     *
     * @param fromIsBuy BUY方向の場合true
     */
    void setIsBuy(bool fromIsBuy) {
        this.isBuy = fromIsBuy;
    }

    /**
     * 現在足と1つ上位足のEMA200の並びが売買方向と一致するか判定する。
     *
     * @param fromElliotHigher1 1つ上位足のElliot情報
     * @param fromElliotCurrent 現在足のElliot情報
     * @return 売買方向とEMA200の並びが一致する場合true
     */
    bool isEma200CurrentAndHigher1(
        Elliot &fromElliotHigher1,
        Elliot &fromElliotCurrent
    ) {
        bool isEma200 = false;

        double ema200Higher1 = fromElliotHigher1.oscillator.ema200.ema200Shift1;
        double ema200Current = fromElliotCurrent.oscillator.ema200.ema200Shift1;

        if (this.isBuy) {
            if (ema200Current > ema200Higher1) {
                isEma200 = true;
            }
        } else {
            if (ema200Current < ema200Higher1) {
                isEma200 = true;
            }
        }

        return isEma200;
    }

    /**
     * 指定したElliotのEMA200判定が現在の売買方向と一致するか判定する。
     *
     * @param elliot 判定対象
     * @return EMA200判定が現在の売買方向と一致する場合true
     */
    bool isEma200BuySell(Elliot *elliot) {
        bool isEma200BuySell = false;

        if (elliot == NULL) {
            return false;
        }

        string buySellLabelCurrent = elliot.oscillator.ema200.getBuySellLabel();

        if (this.isBuy) {
            if (buySellLabelCurrent == "BUY") {
                isEma200BuySell = true;
            }
        } else {
            if (buySellLabelCurrent == "SELL") {
                isEma200BuySell = true;
            }
        }

        return isEma200BuySell;
    }
};

#endif