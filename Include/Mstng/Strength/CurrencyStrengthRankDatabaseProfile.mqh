//+------------------------------------------------------------------+
//|              CurrencyStrengthRankDatabaseProfile.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_MQH

/**
 * 通貨強弱順位の参照元DBプロファイル。
 */
enum CurrencyStrengthRankDatabaseProfile {
    /** テスターで保存した過去集計を参照する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER = 0,

    /** ライブ実行で保存した集計を参照する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE = 1,

    /** 実行環境に合わせて自動選択する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_AUTO = 2,

    /** 同じM5時刻はLIVEを優先し、LIVEがない時刻をTESTERで補完する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER = 3
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_MQH
