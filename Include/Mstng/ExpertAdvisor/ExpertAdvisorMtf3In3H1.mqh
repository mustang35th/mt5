//+------------------------------------------------------------------+
//|                                       ExpertAdvisorMtf3In3H1.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>

/**
 * H1を現在足としてMTF_3in3エントリーを判定する。
 *
 * D1とH4は売買方向の一致確認に使用し、H1の第1波または第3波を
 * エントリー対象波動とする。EMA200はH1の方向だけを確認し、
 * H1の最新ZigZagポイントは確定・未確定を問わず、
 * エントリー成立時はメール送信対象とする。
 */
class ExpertAdvisorMtf3In3H1 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMtf3In3H1(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true
    ) : ExpertAdvisorMTF_3in3(fromMarketContext, fromIsDrawArrow) {
    }

protected:
    /**
     * H1が第1波または第3波か判定する。
     *
     * @return H1用の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        return this.isEntryWave(this.elliotCurrent);
    }

    /**
     * H1では最新ZigZagポイントの確定状態を条件に使用しない。
     *
     * @return H1の場合true。それ以外の場合false。
     */
    virtual bool isTimeFrameZigZagConfirmedConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        return true;
    }

    /**
     * H1のEMA200方向が売買方向と一致するか判定する。
     *
     * D1とH4のEMA200方向はH1エントリー条件に使用しない。
     *
     * @return H1のEMA200方向が一致する場合true。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        return this.expertAdvisorEma200.isEma200BuySell(
            this.elliotCurrent
        );
    }

    /**
     * H1では現在足とEMA200の距離制限を使用しない。
     *
     * @return H1の場合false。それ以外の場合true。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return true;
        }

        return false;
    }

    /**
     * H1エントリー成立時にメールを送信するか判定する。
     *
     * @return 常にtrue。
     */
    virtual bool shouldSendMail() override {
        return true;
    }

    /**
     * D1、H4およびH1の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        Mtf3In3H1ElliotStructureDecision structureDecision;
        Mtf3In3H1ElliotStructureResult structureResult;
        structureDecision.evaluate(this.elliotAll, structureResult);

        return "H1[" + structureResult.getDisplayLabel()
            + "] " + this.getThreeTimeFrameAlertText();
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH
