//+------------------------------------------------------------------+
//|                               CurrencyStrengthResultEntity.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RESULT_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RESULT_ENTITY_MQH

/**
 * 通貨単位の通貨強弱集計結果データベースレコード。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct CurrencyStrengthResultEntity {
    /** 集計結果ID。 */
    long id;

    /** 集計ID。 */
    long runId;

    /** 通貨名。 */
    string currencyName;

    /** D1の未正規化合計。 */
    int d1Score;

    /** H4の未正規化合計。 */
    int h4Score;

    /** H1の未正規化合計。 */
    int h1Score;

    /** M15の未正規化合計。 */
    int m15Score;

    /** 全時間足の未正規化合計。 */
    int totalScore;

    /** D1の票数。 */
    int d1SampleCount;

    /** H4の票数。 */
    int h4SampleCount;

    /** H1の票数。 */
    int h1SampleCount;

    /** M15の票数。 */
    int m15SampleCount;

    /** 全時間足の票数。 */
    int totalSampleCount;
};

#endif // MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RESULT_ENTITY_MQH
