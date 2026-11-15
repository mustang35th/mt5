#ifndef MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_EVALUATOR_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_EVALUATOR_MQH

#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDeltaEvaluator.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionInfo.mqh>

/**
 * 現在の分析順位と連続する過去M5順位から、選択集計期間の増減方向を復元する。
 * 現在足を再評価しても、前回の評価結果を同じM5内で積み重ねない。
 */
class CurrencyStrengthRankGapDirectionEvaluator {
public:
    /**
     * 順位差が変化した場合は方向を更新し、横ばいなら直前方向を返す。
     *
     * @param fromCurrentGap 現在の順位差。
     * @param fromPreviousGap 直前の順位差。
     * @param fromPreviousDirection 引き継ぐ方向。上昇1、下降-1、不明0。
     * @return 更新後の方向。
     */
    static int updateDirection(const int fromCurrentGap, const int fromPreviousGap,
            const int fromPreviousDirection) {
        if (fromCurrentGap > fromPreviousGap) {
            return 1;
        }

        if (fromCurrentGap < fromPreviousGap) {
            return -1;
        }

        return fromPreviousDirection;
    }

    /**
     * 現在値から古いM5へ遡り、最初の増減または欠損までで方向を決定する。
     * 直前M5が欠損なら取得待ち、それより古い欠損なら方向不明で確定する。
     *
     * @param fromPoints 時刻昇順の過去順位。現在・未来の点は評価しない。
     * @param fromStartIndex 保持履歴の有効先頭位置。
     * @param fromExecutionInfo 今回の分析に採用した現在順位。
     * @param fromResult 判定結果。
     * @param fromLongMedium 長中期を評価する場合true、中短期の場合false。
     */
    static void evaluate(const CurrencyStrengthPairRankPoint &fromPoints[],
            const int fromStartIndex, const CurrencyStrengthExecutionInfo &fromExecutionInfo,
            CurrencyStrengthRankGapDirectionInfo &fromResult, const bool fromLongMedium = true) {
        fromResult.reset();
        fromResult.enabled = true;
        fromResult.waiting = true;
        datetime targetTime = fromExecutionInfo.targetM5BarTime;
        fromResult.targetM5BarTime = targetTime;
        if (targetTime <= 300 || targetTime % 300 != 0 || !fromExecutionInfo.isExactM5Bar()
                || fromExecutionInfo.pairRankInfo.runId <= 0) {
            return;
        }

        fromResult.currentAvailable = true;
        if (fromLongMedium) {
            fromResult.currentGap = fromExecutionInfo.getLongMediumRankDifference();
        } else {
            fromResult.currentGap = fromExecutionInfo.getMediumShortRankDifference();
        }

        datetime previousTime = targetTime - 300;
        int previousIndex = -1;
        int baseRank = 0;
        int quoteRank = 0;
        int previousGap = 0;
        if (!CurrencyStrengthRankDeltaEvaluator::evaluateGap(fromPoints, fromStartIndex,
                previousTime, fromLongMedium, baseRank, quoteRank, previousGap, previousIndex)) {
            return;
        }

        fromResult.hasPrevious = true;
        fromResult.previousGap = previousGap;
        fromResult.waiting = false;
        int direction = updateDirection(fromResult.currentGap, previousGap, 0);
        if (direction != 0) {
            fromResult.direction = direction;
            fromResult.directionChangedAt = targetTime;

            return;
        }

        datetime firstTime = (datetime)MathMax(300, (long)targetTime - 30 * 86400);
        datetime newerTime = previousTime;
        int newerGap = previousGap;
        for (int i = previousIndex - 1; i >= fromStartIndex; i--) {
            datetime olderTime = fromPoints[i].m5BarTime;
            int olderBaseRank = fromPoints[i].baseMediumShortTermAverageRank;
            int olderQuoteRank = fromPoints[i].quoteMediumShortTermAverageRank;
            if (fromLongMedium) {
                olderBaseRank = fromPoints[i].baseLongMediumTermAverageRank;
                olderQuoteRank = fromPoints[i].quoteLongMediumTermAverageRank;
            }

            if (olderTime < firstTime || olderTime != newerTime - 300
                    || fromPoints[i].runId <= 0
                    || olderBaseRank < 1 || olderBaseRank > 8
                    || olderQuoteRank < 1 || olderQuoteRank > 8) {
                return;
            }

            int olderGap = olderQuoteRank - olderBaseRank;
            direction = updateDirection(newerGap, olderGap, 0);
            if (direction != 0) {
                fromResult.direction = direction;
                fromResult.directionChangedAt = newerTime;

                return;
            }

            newerTime = olderTime;
            newerGap = olderGap;
        }
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_EVALUATOR_MQH
