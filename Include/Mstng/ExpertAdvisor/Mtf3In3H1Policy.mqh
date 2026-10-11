#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_POLICY_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_POLICY_MQH

#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>

/**
 * 通常インジケーター、一覧AlertおよびEAで共有するH1エントリーの固定設定。
 * 判定本体と診断・Run設定の記録は、同じ固定値を参照する。
 */
class Mtf3In3H1Policy {
public:
    /**
     * W1～H1の方向一致と、MN1またはW1 EMA200の同方向一致を要求する。
     * AND指定時はMN1～H1の全方向一致を要求し、W1確認側でEMA200を必須にする。
     *
     * @param fromRequireMn1AndW1Ema200 MN1とW1 EMA200の両方を必須にする場合true。
     */
    static H1DirectionAlignmentMode getDirectionAlignmentMode(
        const bool fromRequireMn1AndW1Ema200 = false
    ) {
        if (fromRequireMn1AndW1Ema200) {
            return H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED;
        }

        return H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED;
    }

    /**
     * H1・H4・D1のEMA200方向一致を必須とする。
     */
    static H1Ema200ConfirmationMode getEma200ConfirmationMode() {
        return H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED;
    }

    /**
     * 通常はW1追加確認を診断だけにし、AND指定時は方向とEMA200の一致を必須にする。
     *
     * @param fromRequireMn1AndW1Ema200 MN1とW1 EMA200の両方を必須にする場合true。
     */
    static H1W1ConfirmationMode getW1ConfirmationMode(
        const bool fromRequireMn1AndW1Ema200 = false
    ) {
        if (fromRequireMn1AndW1Ema200) {
            return H1_W1_CONFIRMATION_DIRECTION_AND_EMA200;
        }

        return H1_W1_CONFIRMATION_OBSERVE_ONLY;
    }

    /**
     * H1の共通判定に必要なElliott分析の開始時間足を返す。
     */
    static ENUM_TIMEFRAMES getAnalysisStartTimeFrame() {
        return PERIOD_MN1;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_POLICY_MQH
