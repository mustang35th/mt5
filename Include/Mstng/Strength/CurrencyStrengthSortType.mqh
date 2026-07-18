//+------------------------------------------------------------------+
//|                                     CurrencyStrengthSortType.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_SORT_TYPE_MQH
#define MSTNG_CURRENCY_STRENGTH_SORT_TYPE_MQH

/**
 * 通貨強弱一覧の並び替え基準。
 */
enum CurrencyStrengthSortType {
    CURRENCY_STRENGTH_SORT_TOTAL = 0,        // TOTAL
    CURRENCY_STRENGTH_SORT_LONG = 1,         // LONG
    CURRENCY_STRENGTH_SORT_LONG_MEDIUM = 2,  // LONG-MID
    CURRENCY_STRENGTH_SORT_MEDIUM = 3,       // MID
    CURRENCY_STRENGTH_SORT_MEDIUM_SHORT = 4, // MID-SHORT
    CURRENCY_STRENGTH_SORT_SHORT = 5         // SHORT
};

#endif // MSTNG_CURRENCY_STRENGTH_SORT_TYPE_MQH
