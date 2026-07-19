//+------------------------------------------------------------------+
//|                       CurrencyStrengthPairRankPoint.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_PAIR_RANK_POINT_MQH
#define MSTNG_CURRENCY_STRENGTH_PAIR_RANK_POINT_MQH

/**
 * 表示対象通貨ペアの通貨強弱順位を時系列の1点として保持する。
 *
 * DAOのSELECT列順にフィールドを定義する。
 */
struct CurrencyStrengthPairRankPoint {
    /** 集計ID。 */
    long runId;

    /** 集計基準となるM5バー時刻。 */
    datetime m5BarTime;

    /** 集計レコード更新時刻。 */
    datetime updatedAt;

    /** 基軸通貨の長中期平均スコア順位。 */
    int baseLongMediumTermAverageRank;

    /** 基軸通貨の中短期平均スコア順位。 */
    int baseMediumShortTermAverageRank;

    /** 決済通貨の長中期平均スコア順位。 */
    int quoteLongMediumTermAverageRank;

    /** 決済通貨の中短期平均スコア順位。 */
    int quoteMediumShortTermAverageRank;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.runId = 0;
        this.m5BarTime = 0;
        this.updatedAt = 0;
        this.baseLongMediumTermAverageRank = 0;
        this.baseMediumShortTermAverageRank = 0;
        this.quoteLongMediumTermAverageRank = 0;
        this.quoteMediumShortTermAverageRank = 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_PAIR_RANK_POINT_MQH
