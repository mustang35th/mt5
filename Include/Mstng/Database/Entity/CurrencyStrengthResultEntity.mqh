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

    /** MN1の未正規化合計。 */
    int mn1Score;

    /** W1の未正規化合計。 */
    int w1Score;

    /** D1の未正規化合計。 */
    int d1Score;

    /** H4の未正規化合計。 */
    int h4Score;

    /** H1の未正規化合計。 */
    int h1Score;

    /** M15の未正規化合計。 */
    int m15Score;

    /** M5の未正規化合計。 */
    int m5Score;

    /** 全時間足の未正規化合計。 */
    int totalScore;

    /** MN1の票数。 */
    int mn1SampleCount;

    /** W1の票数。 */
    int w1SampleCount;

    /** D1の票数。 */
    int d1SampleCount;

    /** H4の票数。 */
    int h4SampleCount;

    /** H1の票数。 */
    int h1SampleCount;

    /** M15の票数。 */
    int m15SampleCount;

    /** M5の票数。 */
    int m5SampleCount;

    /** 全時間足の票数。 */
    int totalSampleCount;

    /** 長期スコア平均。 */
    double longTermAverageScore;

    /** 長期平均スコア順位。 */
    int longTermAverageRank;

    /** 長中期スコア平均。 */
    double longMediumTermAverageScore;

    /** 長中期平均スコア順位。 */
    int longMediumTermAverageRank;

    /** 中期スコア平均。 */
    double mediumTermAverageScore;

    /** 中期平均スコア順位。 */
    int mediumTermAverageRank;

    /** 中短期スコア平均。 */
    double mediumShortTermAverageScore;

    /** 中短期平均スコア順位。 */
    int mediumShortTermAverageRank;

    /** 短期スコア平均。 */
    double shortTermAverageScore;

    /** 短期平均スコア順位。 */
    int shortTermAverageRank;

    /** レコード更新時刻。 */
    datetime updatedAt;

    /** レコード更新時刻表示文字列。 */
    string updatedAtText;
};

#endif // MSTNG_DATABASE_ENTITY_CURRENCY_STRENGTH_RESULT_ENTITY_MQH
