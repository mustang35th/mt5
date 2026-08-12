//+------------------------------------------------------------------+
//|                                               SignalDecision.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Domain
 * File: SignalDecision.mqh
 */

#ifndef MSTNGEA_DOMAIN_SIGNALDECISION_MQH
#define MSTNGEA_DOMAIN_SIGNALDECISION_MQH

#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>

/**
 * エントリー判定結果
 */
struct SignalDecision {
    /** エントリー対象 */
    bool isEntry;

    /** true: 買い false: 売り */
    bool isBuy;

    /** 理由 */
    string reason;

    /** ストップロス価格 */
    double stopLoss;

    /** CSV情報 */
    string csvText;

    /** アラート表示文字列 */
    string alertText;

    /** MTF_3in3のアラート検証結果 */
    Mtf3In3AlertResult mtf3In3AlertResult;
};

#endif
