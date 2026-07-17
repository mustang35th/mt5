//+------------------------------------------------------------------+
//|                              CurrencyStrengthPairVote.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_PAIR_VOTE_MQH
#define MSTNG_CURRENCY_STRENGTH_PAIR_VOTE_MQH

/**
 * 1通貨ペア・1時間足分の通貨強弱票と反映後集計値。
 */
struct CurrencyStrengthPairVote {
    /** 通貨ペア処理順。 */
    int pairOrder;

    /** 時間足処理順。 */
    int timeFrameOrder;

    /** 6文字の正規シンボル名。 */
    string canonicalSymbolName;

    /** ブローカー上の実シンボル名。 */
    string resolvedSymbolName;

    /** 時間足。 */
    ENUM_TIMEFRAMES timeFrame;

    /** 参照した現在足の開始時刻。 */
    datetime barTime;

    /** 基軸通貨。 */
    string baseCurrency;

    /** 決済通貨。 */
    string quoteCurrency;

    /** BUY判定の場合true。 */
    bool isBuy;

    /** 判定元のオシレーター値。 */
    int oscillatorCount;

    /** 基軸通貨へ加算した票。 */
    int baseScore;

    /** 票反映後の基軸通貨時間足別スコア。 */
    int baseScoreAfter;

    /** 票反映後の決済通貨時間足別スコア。 */
    int quoteScoreAfter;
};

#endif // MSTNG_CURRENCY_STRENGTH_PAIR_VOTE_MQH
