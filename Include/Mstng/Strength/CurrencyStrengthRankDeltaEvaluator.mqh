//+------------------------------------------------------------------+
//|                           CurrencyStrengthRankDeltaEvaluator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_DELTA_EVALUATOR_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_DELTA_EVALUATOR_MQH

#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>

/**
 * 通貨ペアのM5順位履歴から、各足の順位差と指定時間前に対する変化を評価する。
 *
 * 指定した時刻と厳密に一致する履歴だけを使用し、古い順位で欠損を補わない。
 */
class CurrencyStrengthRankDeltaEvaluator {
public:
    /**
     * 時刻昇順の履歴から、指定したM5時刻と一致する位置を検索する。
     * 前回位置と隣接位置を優先し、それ以外は探索範囲を絞って二分探索する。
     *
     * @param fromPoints 時刻昇順の順位履歴。
     * @param fromStartIndex 有効な履歴の先頭位置。
     * @param fromTime 検索する時刻。
     * @param fromPreviousIndex 前回見つかった位置。未取得の場合は-1。
     * @return 厳密に一致する位置。見つからない場合は-1。
     */
    static int findIndex(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const int fromStartIndex,
        const datetime fromTime,
        const int fromPreviousIndex = -1
    ) {
        int total = ArraySize(fromPoints);
        if (fromStartIndex < 0 || fromStartIndex >= total || fromTime <= 0) {
            return -1;
        }

        int leftIndex = fromStartIndex;
        int rightIndex = total - 1;
        if (fromPreviousIndex >= fromStartIndex && fromPreviousIndex < total) {
            datetime previousTime = fromPoints[fromPreviousIndex].m5BarTime;
            if (previousTime == fromTime) {
                return fromPreviousIndex;
            }

            if (previousTime < fromTime) {
                leftIndex = fromPreviousIndex + 1;
                if (leftIndex < total && fromPoints[leftIndex].m5BarTime == fromTime) {
                    return leftIndex;
                }
            } else {
                rightIndex = fromPreviousIndex - 1;
                if (rightIndex >= fromStartIndex && fromPoints[rightIndex].m5BarTime == fromTime) {
                    return rightIndex;
                }
            }
        }

        while (leftIndex <= rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            datetime middleTime = fromPoints[middleIndex].m5BarTime;
            if (middleTime == fromTime) {
                return middleIndex;
            }

            if (middleTime < fromTime) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex - 1;
            }
        }

        return -1;
    }

    /**
     * 指定した1足の両通貨順位と「決済通貨順位－基軸通貨順位」を求める。
     * 前後の足の有無に依存せず、同順位の0も有効値として扱う。
     *
     * @param fromPoints 時刻昇順の順位履歴。
     * @param fromStartIndex 有効な履歴の先頭位置。
     * @param fromTime 対象のM5足開始時刻。
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @param fromBaseRank 基軸通貨の順位。失敗時は0。
     * @param fromQuoteRank 決済通貨の順位。失敗時は0。
     * @param fromGap 決済通貨順位から基軸通貨順位を引いた値。失敗時は0。
     * @param fromCurrentIndex 検索ヒント兼取得位置。失敗時は-1。
     * @return 指定時刻と選択期間の両通貨順位が有効な場合true。
     */
    static bool evaluateGap(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const int fromStartIndex,
        const datetime fromTime,
        const bool fromLongMedium,
        int &fromBaseRank,
        int &fromQuoteRank,
        int &fromGap,
        int &fromCurrentIndex
    ) {
        int currentIndexHint = fromCurrentIndex;
        fromBaseRank = 0;
        fromQuoteRank = 0;
        fromGap = 0;
        fromCurrentIndex = -1;
        if (fromTime <= 0 || fromTime % 300 != 0) {
            return false;
        }

        int currentIndex = findIndex(fromPoints, fromStartIndex, fromTime, currentIndexHint);
        if (currentIndex < 0) {
            return false;
        }

        int baseRank = 0;
        int quoteRank = 0;
        if (!getRanks(fromPoints[currentIndex], fromTime, fromLongMedium, baseRank, quoteRank)) {
            return false;
        }

        fromBaseRank = baseRank;
        fromQuoteRank = quoteRank;
        fromGap = quoteRank - baseRank;
        fromCurrentIndex = currentIndex;

        return true;
    }

    /**
     * 現在と指定秒数前の「決済通貨順位－基軸通貨順位」の変化を求める。
     * 両端が有効なら中間履歴の欠損は許容し、同順位の0も有効値として扱う。
     *
     * @param fromPoints 時刻昇順の順位履歴。
     * @param fromStartIndex 有効な履歴の先頭位置。
     * @param fromTime 現在側のM5足開始時刻。
     * @param fromCompareSeconds 比較する秒数。正の300秒倍数。
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @param fromCurrentGap 現在の順位差。失敗時は0。
     * @param fromPreviousGap 比較時刻の順位差。失敗時は0。
     * @param fromDelta 現在の順位差から比較時刻の順位差を引いた値。失敗時は0。
     * @param fromCurrentIndex 現在側の検索ヒント兼取得位置。失敗時は-1。
     * @param fromPreviousIndex 比較側の検索ヒント兼取得位置。失敗時は-1。
     * @return 両端の時刻と選択期間の順位が有効な場合true。
     */
    static bool evaluate(
        const CurrencyStrengthPairRankPoint &fromPoints[],
        const int fromStartIndex,
        const datetime fromTime,
        const int fromCompareSeconds,
        const bool fromLongMedium,
        int &fromCurrentGap,
        int &fromPreviousGap,
        int &fromDelta,
        int &fromCurrentIndex,
        int &fromPreviousIndex
    ) {
        int currentIndexHint = fromCurrentIndex;
        int previousIndexHint = fromPreviousIndex;
        fromCurrentGap = 0;
        fromPreviousGap = 0;
        fromDelta = 0;
        fromCurrentIndex = -1;
        fromPreviousIndex = -1;

        const int frameSeconds = 300;
        if (fromTime <= 0 || fromTime % frameSeconds != 0
                || fromCompareSeconds <= 0 || fromCompareSeconds % frameSeconds != 0
                || fromTime <= fromCompareSeconds) {
            return false;
        }

        datetime previousTime = fromTime - fromCompareSeconds;
        int currentIndex = findIndex(fromPoints, fromStartIndex, fromTime, currentIndexHint);
        int previousIndex = findIndex(fromPoints, fromStartIndex, previousTime, previousIndexHint);
        if (currentIndex < 0 || previousIndex < 0) {
            return false;
        }

        int currentGap = 0;
        int previousGap = 0;
        if (!getGap(fromPoints[currentIndex], fromTime, fromLongMedium, currentGap)
                || !getGap(fromPoints[previousIndex], previousTime, fromLongMedium, previousGap)) {
            return false;
        }

        fromCurrentGap = currentGap;
        fromPreviousGap = previousGap;
        fromDelta = currentGap - previousGap;
        fromCurrentIndex = currentIndex;
        fromPreviousIndex = previousIndex;

        return true;
    }

private:
    /**
     * 時刻と選択期間の順位を検証し、決済通貨順位から基軸通貨順位を引く。
     *
     * @param fromPoint 判定する履歴点。
     * @param fromTime 必須のM5足開始時刻。
     * @param fromLongMedium 長中期の場合true。
     * @param fromGap 順位差の出力先。
     * @return 集計ID・時刻・選択期間の両通貨順位が有効な場合true。
     */
    static bool getGap(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const datetime fromTime,
        const bool fromLongMedium,
        int &fromGap
    ) {
        int baseRank = 0;
        int quoteRank = 0;
        if (!getRanks(fromPoint, fromTime, fromLongMedium, baseRank, quoteRank)) {
            return false;
        }

        fromGap = quoteRank - baseRank;

        return true;
    }

    /**
     * 集計ID・時刻・選択期間の順位を検証し、両通貨順位を返す。
     *
     * @param fromPoint 判定する履歴点。
     * @param fromTime 必須のM5足開始時刻。
     * @param fromLongMedium 長中期の場合true。
     * @param fromBaseRank 基軸通貨順位の出力先。
     * @param fromQuoteRank 決済通貨順位の出力先。
     * @return 両通貨順位が1～8の場合true。
     */
    static bool getRanks(
        const CurrencyStrengthPairRankPoint &fromPoint,
        const datetime fromTime,
        const bool fromLongMedium,
        int &fromBaseRank,
        int &fromQuoteRank
    ) {
        if (fromPoint.runId <= 0 || fromPoint.m5BarTime != fromTime) {
            return false;
        }

        int baseRank = fromPoint.baseMediumShortTermAverageRank;
        int quoteRank = fromPoint.quoteMediumShortTermAverageRank;
        if (fromLongMedium) {
            baseRank = fromPoint.baseLongMediumTermAverageRank;
            quoteRank = fromPoint.quoteLongMediumTermAverageRank;
        }

        if (baseRank < 1 || baseRank > 8 || quoteRank < 1 || quoteRank > 8) {
            return false;
        }

        fromBaseRank = baseRank;
        fromQuoteRank = quoteRank;

        return true;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_DELTA_EVALUATOR_MQH
