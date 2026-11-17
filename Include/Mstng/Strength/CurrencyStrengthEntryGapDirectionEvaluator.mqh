#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_EVALUATOR_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_EVALUATOR_MQH

#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionInfo.mqh>

/**
 * 現在候補と共通の全通貨M5履歴から、選択集計期間の順位差の直近増減方向を復元する。
 * 対象ペアの選択期間の順位だけを参照し、現在・未来のDB順位を使用しない。
 */
class CurrencyStrengthEntryGapDirectionEvaluator {
public:
    /**
     * 現在から古いM5へ遡り、最初の増減または履歴の途切れで方向を決定する。
     * 直前M5の欠損は取得待ち、それ以前の欠損や30日間の横ばいは方向不明とする。
     *
     * @param fromPoints 時刻昇順の全通貨順位履歴。
     * @param fromTargetM5BarTime 現在候補のM5足開始時刻。
     * @param fromCandidate 現在の両集計期間の順位を持つ候補。
     * @param fromResult 判定結果の格納先。
     * @param fromLongMedium 長中期を評価する場合true、中短期の場合false。
     */
    static void evaluate(const CurrencyStrengthAllRankPoint &fromPoints[],
            const datetime fromTargetM5BarTime, const CurrencyStrengthEntryCandidate &fromCandidate,
            CurrencyStrengthRankGapDirectionInfo &fromResult, const bool fromLongMedium = true) {
        fromResult.reset();
        fromResult.enabled = true;
        fromResult.waiting = true;
        fromResult.targetM5BarTime = fromTargetM5BarTime;
        int baseRank = fromCandidate.baseLongMediumRank;
        int quoteRank = fromCandidate.quoteLongMediumRank;
        if (!fromLongMedium) {
            baseRank = fromCandidate.baseMediumShortRank;
            quoteRank = fromCandidate.quoteMediumShortRank;
        }

        if (fromTargetM5BarTime <= 300 || fromTargetM5BarTime % 300 != 0
                || StringLen(fromCandidate.symbolName) != 6
                || !isValidRank(baseRank) || !isValidRank(quoteRank)) {
            return;
        }

        string baseCurrency = StringSubstr(fromCandidate.symbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromCandidate.symbolName, 3, 3);
        if (baseCurrency == quoteCurrency) {
            return;
        }

        fromResult.currentAvailable = true;
        fromResult.currentGap = quoteRank - baseRank;
        datetime previousTime = fromTargetM5BarTime - 300;
        int previousIndex = findPointIndex(fromPoints, previousTime);
        int previousGap = 0;
        if (previousIndex < 0
                || !readGap(fromPoints[previousIndex], baseCurrency, quoteCurrency, previousGap, fromLongMedium)) {
            return;
        }

        fromResult.hasPrevious = true;
        fromResult.previousGap = previousGap;
        fromResult.waiting = false;
        int direction = getDirection(fromResult.currentGap, previousGap);
        if (direction != 0) {
            fromResult.direction = direction;
            fromResult.directionChangedAt = fromTargetM5BarTime;

            return;
        }

        datetime firstTime = (datetime)MathMax(300, (long)fromTargetM5BarTime - 30 * 86400);
        datetime newerTime = previousTime;
        int newerGap = previousGap;
        for (int i = previousIndex - 1; i >= 0; i--) {
            datetime olderTime = fromPoints[i].m5BarTime;
            int olderGap = 0;
            if (olderTime < firstTime || olderTime != newerTime - 300
                    || !readGap(fromPoints[i], baseCurrency, quoteCurrency, olderGap, fromLongMedium)) {
                return;
            }

            direction = getDirection(newerGap, olderGap);
            if (direction != 0) {
                fromResult.direction = direction;
                fromResult.directionChangedAt = newerTime;

                return;
            }

            newerTime = olderTime;
            newerGap = olderGap;
        }
    }

private:
    /**
     * 指定M5と完全一致する点を二分探索する。現在・未来の点を代用しない。
     */
    static int findPointIndex(const CurrencyStrengthAllRankPoint &fromPoints[], const datetime fromTime) {
        int leftIndex = 0;
        int rightIndex = ArraySize(fromPoints) - 1;
        while (leftIndex <= rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            if (fromPoints[middleIndex].m5BarTime == fromTime) {
                return middleIndex;
            }

            if (fromPoints[middleIndex].m5BarTime < fromTime) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex - 1;
            }
        }

        return -1;
    }

    /**
     * 対象ペアの選択期間の順位だけを検証して順位差を取得する。
     */
    static bool readGap(const CurrencyStrengthAllRankPoint &fromPoint,
            const string fromBaseCurrency, const string fromQuoteCurrency,
            int &fromGap, const bool fromLongMedium) {
        int baseRank = fromPoint.getLongMediumRank(fromBaseCurrency);
        int quoteRank = fromPoint.getLongMediumRank(fromQuoteCurrency);
        if (!fromLongMedium) {
            baseRank = fromPoint.getMediumShortRank(fromBaseCurrency);
            quoteRank = fromPoint.getMediumShortRank(fromQuoteCurrency);
        }

        if (fromPoint.runId <= 0 || !isValidRank(baseRank) || !isValidRank(quoteRank)) {
            return false;
        }

        fromGap = quoteRank - baseRank;

        return true;
    }

    /**
     * 順位が主要8通貨の範囲内か判定する。
     */
    static bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }

    /**
     * 新しい順位差の増加を1、減少を-1、横ばいを0で返す。
     */
    static int getDirection(const int fromNewerGap, const int fromOlderGap) {
        if (fromNewerGap > fromOlderGap) {
            return 1;
        }

        if (fromNewerGap < fromOlderGap) {
            return -1;
        }

        return 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_EVALUATOR_MQH
