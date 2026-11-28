#ifndef MSTNG_EXPERT_ADVISOR_MTF3IN3_M5_POLICY_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3IN3_M5_POLICY_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Config.mqh>

/**
 * 通常版ZigZagElliotとM5 EAで使用するM5専用の生成設定を共通化する。
 */
class Mtf3In3M5Policy {
public:
    /**
     * D1を含む片足補正・通常版波動条件を使用する設定を反映する。
     * 通貨強弱の取得結果と有効設定は分析側で同じ条件を適用する。
     *
     * @param fromConfig 反映先の生成設定。
     * @param fromDrawArrow シグナル描画を使用する場合true。
     * @param fromMinimumRankDifference 各期間の最低順位差。
     */
    static void apply(ExpertAdvisorMtf3In3Config &fromConfig,
            const bool fromDrawArrow, const int fromMinimumRankDifference) {
        fromConfig.isDrawArrow = fromDrawArrow;
        fromConfig.m5Mn1AndW1Ema200Required = false;
        fromConfig.m5D1ToM5EntryPolicyEnabled = true;
        fromConfig.m5CurrencyStrengthMinimumRankDifference = fromMinimumRankDifference;
    }
};

#endif
