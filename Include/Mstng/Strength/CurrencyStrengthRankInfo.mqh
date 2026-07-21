//+------------------------------------------------------------------+
//|                                     CurrencyStrengthRankInfo.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_INFO_MQH

/**
 * 1通貨分の長中期・中短期平均順位を保持する。
 *
 * DAOのSELECT列順にフィールドを定義する。
 */
struct CurrencyStrengthRankInfo {
    /** 通貨名。 */
    string currencyName;

    /** 長中期平均スコア順位。 */
    int longMediumTermAverageRank;

    /** 中短期平均スコア順位。 */
    int mediumShortTermAverageRank;

    /**
     * 通貨名と順位が使用可能か判定する。
     *
     * @return 通貨名が設定済みで、両順位が1～8の場合true。
     */
    bool isValid() const {
        if (this.currencyName == "") {
            return false;
        }

        if (this.longMediumTermAverageRank < 1
                || this.longMediumTermAverageRank > 8
                || this.mediumShortTermAverageRank < 1
                || this.mediumShortTermAverageRank > 8) {
            return false;
        }

        return true;
    }

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.currencyName = "";
        this.longMediumTermAverageRank = 0;
        this.mediumShortTermAverageRank = 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_INFO_MQH
