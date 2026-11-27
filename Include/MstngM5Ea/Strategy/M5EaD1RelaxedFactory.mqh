#ifndef MSTNGM5EA_STRATEGY_D1_RELAXED_FACTORY_MQH
#define MSTNGM5EA_STRATEGY_D1_RELAXED_FACTORY_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * D1方向一致だけを外す比較用M5判定。波動・補正・通貨強弱は通常版を継承する。
 */
class M5EaD1RelaxedStrategy : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * 通常版M5の設定を維持したまま比較判定を作成する。
     */
    M5EaD1RelaxedStrategy(MarketContext &fromContext, const ExpertAdvisorMtf3In3Config &fromConfig)
        : ExpertAdvisorMtf3In3M5(fromContext, fromConfig.isDrawArrow,
            fromConfig.m5Mn1AndW1Ema200Required, fromConfig.m5D1ToM5EntryPolicyEnabled,
            fromConfig.m5CurrencyStrengthMinimumRankDifference) {
    }

protected:
    /**
     * D1の有効性確認は維持し、M5との方向一致だけを任意にする。
     */
    virtual bool isD1DirectionRequired() override {
        return false;
    }
};

/**
 * 比較専用EAのコンパイル時だけ通常Factoryを置き換える。
 */
class M5EaD1RelaxedFactory {
public:
    /**
     * 比較EAを起動できる実行環境か確認する。
     */
    static bool isRuntimeAllowed() {
        return Util::isStrategyTester();
    }

    /**
     * 通常版M5ポリシーだけを比較対象とし、他の設定を誤用した場合は拒否する。
     * @return 呼び出し側が所有する判定クラス。不適合時はNULL。
     */
    static ExpertAdvisorMTF_3in3 *create(MarketContext &fromContext,
            const ExpertAdvisorMtf3In3Config &fromConfig) {
        if (fromContext.timeFrame != PERIOD_M5 || !fromConfig.m5D1ToM5EntryPolicyEnabled
                || fromConfig.m5Mn1AndW1Ema200Required) {
            return NULL;
        }

        return new M5EaD1RelaxedStrategy(fromContext, fromConfig);
    }
};

#endif
