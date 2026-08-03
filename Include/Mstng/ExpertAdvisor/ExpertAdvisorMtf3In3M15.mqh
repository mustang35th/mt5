//+------------------------------------------------------------------+
//|                             ExpertAdvisorMtf3In3M15.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>

/**
 * M15を現在足としてMTF_3in3エントリーを判定する。
 *
 * H4、H1およびM15の第1波または第3波を
 * エントリー対象波動とする。
 */
class ExpertAdvisorMtf3In3M15 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMtf3In3M15(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true
    ) : ExpertAdvisorMTF_3in3(fromMarketContext, fromIsDrawArrow) {
    }

protected:
    /**
     * H4、H1およびM15が第1波または第3波か判定する。
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
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M15_MQH
