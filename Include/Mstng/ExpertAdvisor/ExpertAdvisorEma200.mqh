//+------------------------------------------------------------------+
//|                                          ExpertAdvisorEma200.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EMA200_MQH
#define MSTNG_EXPERT_ADVISOR_EMA200_MQH

#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * ExpertAdvisor用のEMA200売買方向判定を行うクラス。
 */
class ExpertAdvisorEma200 {
public:
    /** BUY方向の場合true。 */
    bool isBuy;

    /**
     * BUY方向を既定値として初期化する。
     */
    ExpertAdvisorEma200() {
        this.isBuy = true;
    }

    /**
     * 売買方向を指定して初期化する。
     *
     * @param fromIsBuy BUY方向の場合true。
     */
    ExpertAdvisorEma200(bool fromIsBuy) {
        this.isBuy = fromIsBuy;
    }

    /**
     * 売買方向を設定する。
     *
     * @param fromIsBuy BUY方向の場合true。
     */
    void setIsBuy(bool fromIsBuy) {
        this.isBuy = fromIsBuy;
    }

    /**
     * 複数時間足のEMA200候補条件を満たすか判定する。
     *
     * @param fromElliotAll 判定対象。
     * @return EMA200候補条件を満たす場合true。
     */
    bool isEma200Candidate(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return false;
        }

        if (!fromElliotAll.isAnalysisSucceeded) {
            return false;
        }

        Elliot *elliotCurrent = fromElliotAll.elliotCurrent;

        if (elliotCurrent == NULL) {
            return false;
        }

        if (elliotCurrent.isBuy != this.isBuy) {
            return false;
        }

        Elliot *elliotHigher1 = fromElliotAll.getElliot(
            fromElliotAll.marketContext.timeFrame,
            1
        );

        if (elliotHigher1 == NULL) {
            return false;
        }

        if (!fromElliotAll.isBuySell(PERIOD_H4)) {
            return false;
        }

        if (!this.isEma200BuySell(elliotHigher1)) {
            return false;
        }

        if (!this.isEma200BuySell(elliotCurrent)) {
            return false;
        }

        return this.isEma200CurrentAndHigher(elliotHigher1, elliotCurrent);
    }

    /**
     * 現在足と上位足のEMA200の並びが売買方向と一致するか判定する。
     *
     * @param fromElliotHigher 上位足のElliot情報。
     * @param fromElliotCurrent 現在足のElliot情報。
     * @return 売買方向とEMA200の並びが一致する場合true。
     */
    bool isEma200CurrentAndHigher(
        Elliot &fromElliotHigher,
        Elliot &fromElliotCurrent
    ) {
        bool isEma200 = false;

        double ema200Higher = fromElliotHigher.oscillator.ema200.ema200Shift1;
        double ema200Current = fromElliotCurrent.oscillator.ema200.ema200Shift1;

        if (this.isBuy) {
            if (ema200Current > ema200Higher) {
                isEma200 = true;
            }
        } else {
            if (ema200Current < ema200Higher) {
                isEma200 = true;
            }
        }

        return isEma200;
    }

    /**
     * 指定したElliotのEMA200判定が現在の売買方向と一致するか判定する。
     *
     * @param elliot 判定対象。
     * @return EMA200判定が現在の売買方向と一致する場合true。
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

    /**
     * Close1とEMA200[1]の距離が上限以内か判定する。
     *
     * @param elliot 判定対象。
     * @param fromMaxPips 距離上限pips。
     * @return 距離が上限以内の場合true。
     */
    bool isCloseEma200DiffPipsWithin(Elliot *elliot, double fromMaxPips) {
        if (elliot == NULL) {
            return false;
        }

        double maxPips = MathAbs(fromMaxPips);
        double closeEma200DiffPips = MathAbs(elliot.oscillator.ema200.closeEma200DiffPips);

        if (closeEma200DiffPips <= maxPips) {
            return true;
        }

        return false;
    }
};

#endif
