//+------------------------------------------------------------------+
//|                                           ElliotListSortType.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_LIST_SORT_TYPE_MQH
#define MSTNG_ELLIOT_LIST_SORT_TYPE_MQH

/**
 * ZigZag Elliott一覧の並び替え基準。
 */
enum ElliotListSortType {
    ELLIOT_LIST_SORT_ENTRY_PRIORITY = 0,  // ENTRY PRIORITY
    ELLIOT_LIST_SORT_M15_ELLIOT_EMA = 1, // M15 ELLIOTT / EMA200
    ELLIOT_LIST_SORT_D1_ELLIOT_EMA = 2   // D1 ELLIOTT / EMA200
};

#endif // MSTNG_ELLIOT_LIST_SORT_TYPE_MQH
