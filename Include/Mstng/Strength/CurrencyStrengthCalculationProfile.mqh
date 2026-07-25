//+------------------------------------------------------------------+
//|                           CurrencyStrengthCalculationProfile.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_CALCULATION_PROFILE_MQH
#define MSTNG_CURRENCY_STRENGTH_CALCULATION_PROFILE_MQH

/**
 * 通貨強弱票の重み付け方式。
 */
enum CurrencyStrengthVoteWeightMode {
    /** 3対0と2対1を同じ1票として集計する現行方式。 */
    CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM = 0,

    /** 3対0を2票、2対1を1票として集計する加重方式。 */
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED = 1
};

/**
 * 通貨強弱DBの保存側と参照側で共有する集計識別情報。
 */
class CurrencyStrengthCalculationProfile {
public:
    /**
     * 確定足基準の集計ルール識別子を取得する。
     *
     * @param fromTester ストラテジーテスターの場合true。識別子は実行環境共通。
     * @param fromVoteWeightMode 票の重み付け方式。
     * @return 集計ルール識別子。
     */
    static string getCalculationVersion(
        const bool fromTester,
        const CurrencyStrengthVoteWeightMode fromVoteWeightMode =
            CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
    ) {
        if (fromVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED) {
            return "pair-direction-weighted-closed-v1";
        }

        return "pair-direction-closed-v1";
    }

    /**
     * オシレーター一致度に対応する票ウェイトを取得する。
     *
     * @param fromVoteWeightMode 票の重み付け方式。
     * @param fromOscillatorCount オシレーター総合判定値。
     * @return 票ウェイト。
     */
    static int getVoteWeight(
        const CurrencyStrengthVoteWeightMode fromVoteWeightMode,
        const int fromOscillatorCount
    ) {
        if (fromVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED
                && (fromOscillatorCount == 3
                    || fromOscillatorCount == -3)) {
            return 2;
        }

        return 1;
    }

    /**
     * 票の重み付け方式を表示文字列へ変換する。
     *
     * @param fromVoteWeightMode 票の重み付け方式。
     * @return UNIFORMまたはWEIGHTED。
     */
    static string getVoteWeightModeText(
        const CurrencyStrengthVoteWeightMode fromVoteWeightMode
    ) {
        if (fromVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED) {
            return "WEIGHTED";
        }

        return "UNIFORM";
    }

    /**
     * 票の重み付け方式が有効か判定する。
     *
     * @param fromVoteWeightMode 票の重み付け方式。
     * @return 有効な場合true。
     */
    static bool isVoteWeightModeValid(
        const CurrencyStrengthVoteWeightMode fromVoteWeightMode
    ) {
        return fromVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
            || fromVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
    }

    /**
     * 実行環境に対応する集計実行モードを取得する。
     *
     * @param fromTester ストラテジーテスターの場合true。
     * @return TESTERまたはLIVE。
     */
    static string getSourceMode(const bool fromTester) {
        if (fromTester) {
            return "TESTER";
        }

        return "LIVE";
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_CALCULATION_PROFILE_MQH
