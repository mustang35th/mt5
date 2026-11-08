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
     * M15の長中期順位差2、または方向に合う1位・8位で成立方向を取得する。
     *
     * @param fromBaseRank 基軸通貨の長中期順位。
     * @param fromQuoteRank 決済通貨の長中期順位。
     * @return BUY条件成立は1、SELL条件成立は-1、同順位・未達・無効順位は0。
     */
    static int getM15LongMediumDirection(const int fromBaseRank, const int fromQuoteRank) {
        return getLongMediumDirection(fromBaseRank, fromQuoteRank, 2);
    }

    /**
     * 帯で中短期を判定対象に含めないチャート時間足か確認する。
     *
     * @param fromChartPeriod 判定対象チャートの時間足。
     * @return M15またはH1以上の場合true。
     */
    static bool isLongMediumOnlyChartPeriod(const ENUM_TIMEFRAMES fromChartPeriod) {
        return fromChartPeriod == PERIOD_M15
            || PeriodSeconds(fromChartPeriod) >= PeriodSeconds(PERIOD_H1);
    }

    /**
     * 長中期の順位差または方向に合う1位・8位から強調方向を取得する。
     * 帯と順位線・方向バー・ラベルで同じ長中期条件を使用する。
     *
     * @param fromBaseRank 基軸通貨の長中期順位。
     * @param fromQuoteRank 決済通貨の長中期順位。
     * @param fromMinimumDifference 順位差の基準。
     * @return BUYは1、SELLは-1、未達・同順位・無効順位は0。
     */
    static int getLongMediumDirection(
        const int fromBaseRank,
        const int fromQuoteRank,
        const int fromMinimumDifference
    ) {
        if (fromMinimumDifference < 1
                || !isValidRank(fromBaseRank) || !isValidRank(fromQuoteRank)) {
            return 0;
        }

        int rankDifference = fromQuoteRank - fromBaseRank;
        if (rankDifference > 0
                && (rankDifference >= fromMinimumDifference
                    || fromBaseRank == 1 || fromQuoteRank == 8)) {
            return 1;
        }

        if (rankDifference < 0
                && (rankDifference <= -fromMinimumDifference
                    || fromBaseRank == 8 || fromQuoteRank == 1)) {
            return -1;
        }

        return 0;
    }

    /**
     * 中短期の順位差または方向に合う1位・8位から成立方向を取得する。
     * 長中期と同じ順位条件を使用する。
     *
     * @param fromBaseRank 基軸通貨の中短期順位。
     * @param fromQuoteRank 決済通貨の中短期順位。
     * @param fromMinimumDifference 順位差の基準。
     * @return BUYは1、SELLは-1、未達・同順位・無効順位は0。
     */
    static int getMediumShortDirection(
        const int fromBaseRank,
        const int fromQuoteRank,
        const int fromMinimumDifference
    ) {
        return getLongMediumDirection(fromBaseRank, fromQuoteRank, fromMinimumDifference);
    }

    /**
     * 同一M5時刻の順位から、指定した期間条件の売買方向を取得する。
     * 長中期のみの場合は、順位差の基準または方向に合う1位・8位で成立とする。
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
        if (fromLongMediumOnly) {
            return getLongMediumDirection(
                fromPoint.baseLongMediumTermAverageRank,
                fromPoint.quoteLongMediumTermAverageRank,
                fromMinimumDifference
            );
        }

        if (fromMinimumDifference < 1
                || !isValidRank(fromPoint.baseLongMediumTermAverageRank)
                || !isValidRank(fromPoint.quoteLongMediumTermAverageRank)) {
            return 0;
        }

        int longMediumDifference = fromPoint.quoteLongMediumTermAverageRank
            - fromPoint.baseLongMediumTermAverageRank;
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
     * 帯の判定に必要な順位がすべて有効か確認する。
     *
     * @param fromPoint 判定する通貨ペア順位。
     * @param fromLongMediumOnly 長中期のみを判定する場合true。
     * @return 必要な順位がすべて1位から8位の場合true。
     */
    static bool hasValidRibbonRanks(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const bool fromLongMediumOnly = false
    ) {
        if (!isValidRank(fromPoint.baseLongMediumTermAverageRank)
                || !isValidRank(fromPoint.quoteLongMediumTermAverageRank)) {
            return false;
        }

        if (fromLongMediumOnly) {
            return true;
        }

        return isValidRank(fromPoint.baseMediumShortTermAverageRank)
            && isValidRank(fromPoint.quoteMediumShortTermAverageRank);
    }

    /**
     * 帯の売買方向と準備・成立状態を取得する。
     *
     * 両期間が同方向で片方だけ条件を満たした場合は準備、両方なら成立とする。
     * 長中期・中短期それぞれで、順位差の基準または売買方向に合う1位・8位を許可する。
     * 長中期のみを使う場合も同じOR条件を使い、準備を設けず成立だけを返す。
     * M15は長中期の固定順位差2または方向に合う1位・8位を使い、準備を設けない。
     *
     * @param fromPoint 判定する通貨ペア順位。
     * @param fromMinimumDifference 準備・成立の基準となる順位差の絶対値。
     * @param fromLongMediumOnly 長中期のみを判定する場合true。
     * @param fromChartPeriod M15専用条件を適用する時間足。省略時は従来条件。
     * @return BUY準備1・成立2、SELL準備-1・成立-2、待機または無効順位0。
     */
    static int getRibbonState(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const int fromMinimumDifference,
        const bool fromLongMediumOnly = false,
        const ENUM_TIMEFRAMES fromChartPeriod = PERIOD_CURRENT
    ) {
        if (fromChartPeriod == PERIOD_M15) {
            return getM15LongMediumDirection(fromPoint.baseLongMediumTermAverageRank,
                fromPoint.quoteLongMediumTermAverageRank) * 2;
        }

        if (fromLongMediumOnly) {
            return getDirection(fromPoint, fromMinimumDifference, true) * 2;
        }

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
        if (longMediumDifference > 0 && mediumShortDifference > 0) {
            bool isLongMediumReady = longMediumDifference >= fromMinimumDifference
                || fromPoint.baseLongMediumTermAverageRank == 1
                || fromPoint.quoteLongMediumTermAverageRank == 8;
            bool isMediumShortReady = mediumShortDifference >= fromMinimumDifference
                || fromPoint.baseMediumShortTermAverageRank == 1
                || fromPoint.quoteMediumShortTermAverageRank == 8;
            if (isLongMediumReady && isMediumShortReady) {
                return 2;
            }

            if (isLongMediumReady || isMediumShortReady) {
                return 1;
            }
        }

        if (longMediumDifference < 0 && mediumShortDifference < 0) {
            bool isLongMediumReady = longMediumDifference <= -fromMinimumDifference
                || fromPoint.baseLongMediumTermAverageRank == 8
                || fromPoint.quoteLongMediumTermAverageRank == 1;
            bool isMediumShortReady = mediumShortDifference <= -fromMinimumDifference
                || fromPoint.baseMediumShortTermAverageRank == 8
                || fromPoint.quoteMediumShortTermAverageRank == 1;
            if (isLongMediumReady && isMediumShortReady) {
                return -2;
            }

            if (isLongMediumReady || isMediumShortReady) {
                return -1;
            }
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
