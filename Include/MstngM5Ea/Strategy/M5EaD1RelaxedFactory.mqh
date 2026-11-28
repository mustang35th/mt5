#ifndef MSTNGM5EA_STRATEGY_D1_RELAXED_FACTORY_MQH
#define MSTNGM5EA_STRATEGY_D1_RELAXED_FACTORY_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * D1方向一致を外す比較用M5判定。EMA200と通貨強弱は過去の比較条件を維持する。
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
     * 過去のD1緩和比較と同じM15・M5の主波1・3条件を維持する。
     */
    virtual bool isFifthWaveEntryAllowed() override {
        return false;
    }

    /**
     * D1の有効性確認は維持し、M5との方向一致だけを任意にする。
     */
    virtual bool isD1DirectionRequired() override {
        return false;
    }

    /**
     * 過去のD1緩和比較と同じH1・M15・M5のEMA200確認を維持する。
     */
    virtual bool isH1OnlyEma200Required() override {
        return false;
    }

    /**
     * 過去の比較と同じ順位差・端順位・増減方向条件を維持する。
     */
    virtual bool isCurrencyStrengthDirectionOnly() override {
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
