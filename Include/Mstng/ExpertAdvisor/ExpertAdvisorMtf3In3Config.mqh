#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_CONFIG_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_CONFIG_MQH

#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>

/**
 * MTF_3in3判定クラスの生成時に使用する設定。
 * 従来Factoryの省略引数と同じ既定値を持ち、呼び出し元が必要な項目だけを指定する。
 */
struct ExpertAdvisorMtf3In3Config {
    /** シグナル矢印を描画する場合true。 */
    bool isDrawArrow;

    /** 互換経路へ渡すW1確認モード。H1・M15は共通ポリシーを使用する。 */
    H1W1ConfirmationMode h1W1ConfirmationMode;

    /** 互換経路へ渡す方向一致モード。H1・M15は共通ポリシーを使用する。 */
    H1DirectionAlignmentMode h1DirectionAlignmentMode;

    /** 互換経路へ渡すEMA200確認モード。H1・M15は共通ポリシーを使用する。 */
    H1Ema200ConfirmationMode h1Ema200ConfirmationMode;

    /** H1はD1・H4、M15はD1・H4・H1の片足方向補正を使用する場合true。 */
    bool h1DirectionCorrectionEnabled;

    /** M15で使用するH4のFE上限（%）。0は制限なし。 */
    double m15H4MaxFibonacciExpansionPercent;

    /** M15で使用するH1のFE上限（%）。0は制限なし。 */
    double m15H1MaxFibonacciExpansionPercent;

    /** H1・M15でMN1方向とW1 EMA200の両方を必須にする場合true。 */
    bool h1Mn1AndW1Ema200Required;

    /** H1・M15でH4の波番号と第5波構造を制限する場合true。 */
    bool h1H4WaveRestrictionEnabled;

    /** M5でMN1方向とW1 EMA200の両方を必須にする場合true。 */
    bool m5Mn1AndW1Ema200Required;

    /** M5で補正なしのD1〜M5方向一致とH1・M15・M5のEMA200方向一致を必須にする場合true。 */
    bool m5D1ToM5EntryPolicyEnabled;

    /** 通常版M5で両期間の各OR判定に使用する最低順位差。 */
    int m5CurrencyStrengthMinimumRankDifference;

    /** M15で通貨別EMA200距離上限を使用する場合true。 */
    bool m15CurrencyEma200DistanceEnabled;

    /** M15で長中期の順位差2以上または方向に合う1位・8位を使用する場合true。 */
    bool m15LongMediumCurrencyStrengthEnabled;

    /** M1でM5・M1の主波1・3・5を用いる専用条件を使用する場合true。 */
    bool m1M5AndM1WavePolicyEnabled;

    /** M1専用条件でH4・H1・M15の逆方向1足を補正する場合true。 */
    bool m1DirectionCorrectionEnabled;

    /**
     * 従来のFactory呼び出しで省略した引数と同じ値に初期化する。
     */
    ExpertAdvisorMtf3In3Config() {
        this.isDrawArrow = true;
        this.h1W1ConfirmationMode = H1_W1_CONFIRMATION_OBSERVE_ONLY;
        this.h1DirectionAlignmentMode = H1_DIRECTION_ALIGNMENT_D1_TO_H1;
        this.h1Ema200ConfirmationMode = H1_EMA200_CONFIRMATION_H1_ONLY;
        this.h1DirectionCorrectionEnabled = false;
        this.m15H4MaxFibonacciExpansionPercent = 0.0;
        this.m15H1MaxFibonacciExpansionPercent = 0.0;
        this.h1Mn1AndW1Ema200Required = false;
        this.h1H4WaveRestrictionEnabled = true;
        this.m5Mn1AndW1Ema200Required = false;
        this.m5D1ToM5EntryPolicyEnabled = false;
        this.m5CurrencyStrengthMinimumRankDifference = 4;
        this.m15CurrencyEma200DistanceEnabled = false;
        this.m15LongMediumCurrencyStrengthEnabled = false;
        this.m1M5AndM1WavePolicyEnabled = false;
        this.m1DirectionCorrectionEnabled = false;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_CONFIG_MQH
