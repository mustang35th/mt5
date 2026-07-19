//+------------------------------------------------------------------+
//|                        CurrencyStrengthPairRankInfo.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_PAIR_RANK_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_PAIR_RANK_INFO_MQH

/**
 * 通貨ペア順位検索の結果状態。
 */
enum ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS {
    /** 検索処理に失敗した。 */
    CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR = -1,

    /** 対象年のデータベースファイルが存在しない。 */
    CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND = 0,

    /** データベースは存在するが対象レコードが存在しない。 */
    CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND = 1,

    /** 対象レコードを取得した。 */
    CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND = 2
};

/**
 * 表示対象通貨ペアの通貨強弱順位を保持する。
 *
 * DAOのSELECT列順にフィールドを定義する。
 */
struct CurrencyStrengthPairRankInfo {
    /** 集計ID。 */
    long runId;

    /** 集計基準となるM5バー時刻。 */
    datetime m5BarTime;

    /** 集計基準となるM5バー時刻表示文字列。 */
    string m5BarTimeText;

    /** 集計レコード更新時刻。 */
    datetime updatedAt;

    /** 基軸通貨。 */
    string baseCurrency;

    /** 基軸通貨の長中期平均スコア順位。 */
    int baseLongMediumTermAverageRank;

    /** 基軸通貨の中短期平均スコア順位。 */
    int baseMediumShortTermAverageRank;

    /** 決済通貨。 */
    string quoteCurrency;

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
        this.m5BarTimeText = "";
        this.updatedAt = 0;
        this.baseCurrency = "";
        this.baseLongMediumTermAverageRank = 0;
        this.baseMediumShortTermAverageRank = 0;
        this.quoteCurrency = "";
        this.quoteLongMediumTermAverageRank = 0;
        this.quoteMediumShortTermAverageRank = 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_PAIR_RANK_INFO_MQH
