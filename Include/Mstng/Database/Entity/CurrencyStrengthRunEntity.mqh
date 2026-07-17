//+------------------------------------------------------------------+
//|                                  CurrencyStrengthRunEntity.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RUN_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RUN_ENTITY_MQH

/**
 * 通貨強弱集計1回分のデータベースレコード。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct CurrencyStrengthRunEntity {
    /** 集計ID。 */
    long id;

    /** 集計時刻。 */
    datetime calculatedAt;

    /** 集計基準となるM15バー時刻。 */
    datetime m15BarTime;

    /** 集計ルールのバージョン。 */
    string calculationVersion;

    /** 集計元の取引サーバー名。 */
    string sourceServer;

    /** 集計元の口座ログイン番号。 */
    long sourceLogin;

    /** 集計元のチャートID。 */
    long sourceChartId;

    /** 期待する通貨ペア数。 */
    int expectedPairCount;

    /** 集計できた通貨ペア数。 */
    int validPairCount;

    /** 保存した票数。 */
    int voteCount;

    /** 完全集計フラグ。trueの場合は1、falseの場合は0。 */
    int isComplete;
};

#endif // MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RUN_ENTITY_MQH
