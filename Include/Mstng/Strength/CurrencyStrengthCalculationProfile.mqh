//+------------------------------------------------------------------+
//|                 CurrencyStrengthCalculationProfile.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_CALCULATION_PROFILE_MQH
#define MSTNG_CURRENCY_STRENGTH_CALCULATION_PROFILE_MQH

/**
 * 通貨強弱DBの保存側と参照側で共有する集計識別情報。
 */
class CurrencyStrengthCalculationProfile {
public:
    /**
     * 実行環境に対応する集計ルール識別子を取得する。
     *
     * @param fromTester ストラテジーテスターの場合true。
     * @return 集計ルール識別子。
     */
    static string getCalculationVersion(const bool fromTester) {
        if (fromTester) {
            return "pair-direction-closed-v1";
        }

        return "pair-direction-raw-v6";
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
