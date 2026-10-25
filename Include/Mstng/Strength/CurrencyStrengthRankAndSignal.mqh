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
 * 長中期と中短期のAND条件、長中期のみの条件、および帯の準備・成立状態を判定する。
 */
class CurrencyStrengthRankAndSignal {
public:
    /**
     * 同一M5時刻の順位から、指定した期間条件の売買方向を取得する。
     *
     * @param fromPoint 判定する通貨ペア順位。
     * @param fromMinimumDifference 判定対象期間に必要な順位差の絶対値。
     * @param fromLongMediumOnly 長中期のみを判定する場合true。
     * @return BUY条件成立は1、SELL条件成立は-1、条件未達または無効順位は0。
     */
    static int getDirection(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const int fromMinimumDifference,
        const bool fromLongMediumOnly = false
    ) {
        if (fromMinimumDifference < 1
                || !isValidRank(fromPoint.baseLongMediumTermAverageRank)
                || !isValidRank(fromPoint.quoteLongMediumTermAverageRank)) {
            return 0;
        }

        int longMediumDifference = fromPoint.quoteLongMediumTermAverageRank
            - fromPoint.baseLongMediumTermAverageRank;
        if (fromLongMediumOnly) {
            if (longMediumDifference >= fromMinimumDifference) {
                return 1;
            }

            if (longMediumDifference <= -fromMinimumDifference) {
                return -1;
            }

            return 0;
        }

        if (!isValidRank(fromPoint.baseMediumShortTermAverageRank)
                || !isValidRank(fromPoint.quoteMediumShortTermAverageRank)) {
            return 0;
        }

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

    /**
     * 帯の売買方向と準備・成立状態を取得する。
     *
     * 両期間が同方向で片方だけ順位差の基準に達した場合は準備、両方なら成立とする。
     * 長中期のみを使う場合は成立だけを返す。
     *
     * @param fromPoint 判定する通貨ペア順位。
     * @param fromMinimumDifference 準備・成立の基準となる順位差の絶対値。
     * @param fromLongMediumOnly 長中期のみを判定する場合true。
     * @return BUY準備1・成立2、SELL準備-1・成立-2、待機または無効順位0。
     */
    static int getRibbonState(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const int fromMinimumDifference,
        const bool fromLongMediumOnly = false
    ) {
        int direction = getDirection(fromPoint, fromMinimumDifference, fromLongMediumOnly);
        if (direction != 0) {
            return direction * 2;
        }

        if (fromLongMediumOnly || fromMinimumDifference < 1
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
        if (longMediumDifference > 0 && mediumShortDifference > 0
                && (longMediumDifference >= fromMinimumDifference
                    || mediumShortDifference >= fromMinimumDifference)) {
            return 1;
        }

        if (longMediumDifference < 0 && mediumShortDifference < 0
                && (longMediumDifference <= -fromMinimumDifference
                    || mediumShortDifference <= -fromMinimumDifference)) {
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
