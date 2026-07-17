//+------------------------------------------------------------------+
//|                             CurrencyStrengthPairVoteEntity.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_PAIR_VOTE_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_PAIR_VOTE_ENTITY_MQH

/**
 * 通貨ペア・時間足単位の通貨強弱票データベースレコード。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct CurrencyStrengthPairVoteEntity {
    /** 票ID。 */
    long id;

    /** 集計ID。 */
    long runId;

    /** 通貨ペアの集計順。 */
    int pairOrder;

    /** 時間足の集計順。 */
    int timeFrameOrder;

    /** 標準通貨ペア名。 */
    string canonicalSymbolName;

    /** ブローカー環境で解決したシンボル名。 */
    string resolvedSymbolName;

    /** 時間足。 */
    int timeFrame;

    /** 時間足表示文字列。 */
    string timeFrameText;

    /** 判定対象のバー時刻。 */
    datetime barTime;

    /** 判定対象のバー時刻表示文字列。 */
    string barTimeText;

    /** 基軸通貨名。 */
    string baseCurrency;

    /** 決済通貨名。 */
    string quoteCurrency;

    /** BUYフラグ。trueの場合は1、falseの場合は0。 */
    int isBuy;

    /** オシレーター総合判定値。 */
    int oscillatorCount;

    /** 基軸通貨へ加算した票。 */
    int baseScore;

    /** 票反映後の基軸通貨累積値。 */
    int baseScoreAfter;

    /** 票反映後の決済通貨累積値。 */
    int quoteScoreAfter;
};

#endif // MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_PAIR_VOTE_ENTITY_MQH
