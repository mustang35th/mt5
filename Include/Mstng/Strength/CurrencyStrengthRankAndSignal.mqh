//+------------------------------------------------------------------+
//|                              CurrencyStrengthRankAndSignal.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_AND_SIGNAL_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_AND_SIGNAL_MQH

#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>

/**
 * 長中期と中短期の順位差が同方向で基準以上となるAND条件を判定する。
 */
class CurrencyStrengthRankAndSignal {
public:
    /**
     * 同一M5時刻の長中期と中短期からAND条件の売買方向を取得する。
     *
     * @param fromPoint 判定する通貨ペア順位。
     * @param fromMinimumDifference 両期間に必要な順位差の絶対値。
     * @return BUY一致は1、SELL一致は-1、条件未達または無効順位は0。
     */
    static int getDirection(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const int fromMinimumDifference
    ) {
        if (fromMinimumDifference < 1
                || !isValidRank(fromPoint.baseLongMediumTermAverageRank)
                || !isValidRank(fromPoint.quoteLongMediumTermAverageRank)
                || !isValidRank(fromPoint.baseMediumShortTermAverageRank)
                || !isValidRank(fromPoint.quoteMediumShortTermAverageRank)) {
            return 0;
        }

        int longMediumDifference = fromPoint.quoteLongMediumTermAverageRank
            - fromPoint.baseLongMediumTermAverageRank;
        int mediumShortDifference = fromPoint.quoteMediumShortTermAverageRank
            - fromPoint.baseMediumShortTermAverageRank;

        if (longMediumDifference >= fromMinimumDifference
                && mediumShortDifference >= fromMinimumDifference) {
            return 1;
        }

        if (longMediumDifference <= -fromMinimumDifference
                && mediumShortDifference <= -fromMinimumDifference) {
            return -1;
        }

        return 0;
    }

private:
    /**
     * 1位から8位までの有効な順位か判定する。
     *
     * @param fromRank 判定する順位。
     * @return 有効な順位の場合true。
     */
    static bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_AND_SIGNAL_MQH
