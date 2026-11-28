#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_M5_INDICATOR_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_M5_INDICATOR_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M5.mqh>

/**
 * 通常版ZigZagElliotのM5でEMA200方向と第3波FEを条件外にする。
 * 分析値は変更せず、表示・保存には実測値を引き続き使用する。
 */
class ExpertAdvisorMtf3In3M5Indicator : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * D1を含む片足補正と通貨強弱の方向一致を使用して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMtf3In3M5Indicator(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true
    ) : ExpertAdvisorMtf3In3M5(fromMarketContext, fromIsDrawArrow, false, true, 1) {
    }

protected:
    /**
     * EMA200方向をENTRY条件に使用しない。
     *
     * @return 常にtrue。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        return true;
    }

    /**
     * 第3波FEの上限・取得可否をENTRY条件に使用しない。
     * 波動・方向・GMMA等の共通条件は基底クラスで判定する。
     *
     * @param fromRejectReason 条件外のため空文字列を設定する。
     * @return 常にtrue。
     */
    virtual bool isTimeFrameEntryConditionMatched(string &fromRejectReason) override {
        fromRejectReason = "";

        return true;
    }
};

#endif
