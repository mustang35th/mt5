//+------------------------------------------------------------------+
//|                      CurrencyStrengthRankQueryMode.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_QUERY_MODE_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_QUERY_MODE_MQH

/**
 * 通貨強弱順位の検索方法。
 */
enum CurrencyStrengthRankQueryMode {
    /** 対象M5バー時刻と一致する順位のみ採用する。 */
    CURRENCY_STRENGTH_RANK_QUERY_MODE_EXACT = 0,

    /** 対象M5バー時刻以前の最新順位を採用する。 */
    CURRENCY_STRENGTH_RANK_QUERY_MODE_LATEST_AT_OR_BEFORE = 1
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_QUERY_MODE_MQH
