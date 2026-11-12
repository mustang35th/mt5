//+------------------------------------------------------------------+
//|                    CurrencyStrengthTrendContinuationEvaluator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_EVALUATOR_MQH
#define MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_EVALUATOR_MQH

#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>
#include <Mstng\Strength\CurrencyStrengthTrendContinuationInfo.mqh>

/**
 * 全通貨のM5順位履歴から候補方向の継続性を評価する。
 *
 * 現在枠には候補の順位を使い、欠損や同順位を跨いで連続時間を延ばさない。
 */
class CurrencyStrengthTrendContinuationEvaluator {
public:
    /**
     * 直近3時間の方向一致率、連続時間と中短期順位差の変化を評価する。
     *
     * @param fromPoints 時刻昇順の全通貨順位履歴。
     * @param fromTargetM5BarTime 現在の候補に対応するM5足開始時刻。
     * @param fromCandidate 現在順位と判定方向を持つ候補。
     * @param fromResult 判定結果の格納先。
     */
    static void evaluate(
        const CurrencyStrengthAllRankPoint &fromPoints[],
        const datetime fromTargetM5BarTime,
        const CurrencyStrengthEntryCandidate &fromCandidate,
        CurrencyStrengthTrendContinuationInfo &fromResult
    ) {
        fromResult.reset();

        const int frameSeconds = 300;
        const int evaluationCount = 36;
        if (fromTargetM5BarTime <= 0
                || fromTargetM5BarTime % frameSeconds != 0
                || StringLen(fromCandidate.symbolName) != 6) {
            return;
        }

        string baseCurrency = StringSubstr(fromCandidate.symbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromCandidate.symbolName, 3, 3);
        if (baseCurrency == quoteCurrency) {
            return;
        }

        int direction = -1;
        if (fromCandidate.isBuy) {
            direction = 1;
        }

        int historyIndex = ArraySize(fromPoints) - 1;
        int recentValidCount = 0;
        int previousValidCount = 0;
        int recentDifferenceTotal = 0;
        int previousDifferenceTotal = 0;
        bool consecutive = true;

        // 36枠に加え、3時間前の境界は連続秒数の判定だけに使用する。
        for (int i = 0; i <= evaluationCount; i++) {
            datetime slotTime = fromTargetM5BarTime - i * frameSeconds;
            int baseLongMediumRank = 0;
            int quoteLongMediumRank = 0;
            int baseMediumShortRank = 0;
            int quoteMediumShortRank = 0;
            bool valid = false;
            bool supplemented = false;

            if (i == 0) {
                baseLongMediumRank = fromCandidate.baseLongMediumRank;
                quoteLongMediumRank = fromCandidate.quoteLongMediumRank;
                baseMediumShortRank = fromCandidate.baseMediumShortRank;
                quoteMediumShortRank = fromCandidate.quoteMediumShortRank;
                valid = isValidRank(baseLongMediumRank)
                    && isValidRank(quoteLongMediumRank)
                    && isValidRank(baseMediumShortRank)
                    && isValidRank(quoteMediumShortRank);
            } else {
                // 現在・未来のDB点は使わず、要求時刻と一致する有効点だけを採用する。
                while (historyIndex >= 0 && fromPoints[historyIndex].m5BarTime >= slotTime) {
                    if (fromPoints[historyIndex].m5BarTime == slotTime
                            && fromPoints[historyIndex].isValid()) {
                        baseLongMediumRank = fromPoints[historyIndex].getLongMediumRank(baseCurrency);
                        quoteLongMediumRank = fromPoints[historyIndex].getLongMediumRank(quoteCurrency);
                        baseMediumShortRank = fromPoints[historyIndex].getMediumShortRank(baseCurrency);
                        quoteMediumShortRank = fromPoints[historyIndex].getMediumShortRank(quoteCurrency);
                        valid = isValidRank(baseLongMediumRank)
                            && isValidRank(quoteLongMediumRank)
                            && isValidRank(baseMediumShortRank)
                            && isValidRank(quoteMediumShortRank);
                        supplemented = fromPoints[historyIndex].sourceMode == "TESTER";
                    }

                    historyIndex--;
                    if (valid) {
                        break;
                    }
                }
            }

            int longMediumDifference = (quoteLongMediumRank - baseLongMediumRank) * direction;
            int mediumShortDifference = (quoteMediumShortRank - baseMediumShortRank) * direction;
            bool matched = valid && longMediumDifference > 0 && mediumShortDifference > 0;
            if (valid && supplemented) {
                fromResult.supplemented = true;
            }

            if (i < evaluationCount && valid) {
                fromResult.validCount++;
                if (matched) {
                    fromResult.matchedCount++;
                }

                if (i < 6) {
                    recentValidCount++;
                    recentDifferenceTotal += mediumShortDifference;
                } else if (i < 12) {
                    previousValidCount++;
                    previousDifferenceTotal += mediumShortDifference;
                }
            }

            if (consecutive) {
                if (matched) {
                    fromResult.consecutiveSeconds = i * frameSeconds;
                } else {
                    consecutive = false;
                }
            }
        }

        fromResult.available = fromResult.validCount == evaluationCount;
        fromResult.gapAvailable = recentValidCount == 6 && previousValidCount == 6;
        if (!fromResult.gapAvailable) {
            return;
        }

        fromResult.recentAverageDifference = (double)recentDifferenceTotal / 6.0;
        fromResult.previousAverageDifference = (double)previousDifferenceTotal / 6.0;
        // 各6枠なので合計差3が平均差0.5に相当し、浮動小数点の境界誤差も避ける。
        int totalDifferenceChange = recentDifferenceTotal - previousDifferenceTotal;
        if (totalDifferenceChange >= 3) {
            fromResult.gapChange = 1;
        } else if (totalDifferenceChange <= -3) {
            fromResult.gapChange = -1;
        }
    }

private:
    /**
     * 順位が主要8通貨の範囲内か判定する。
     *
     * @param fromRank 判定する順位。
     * @return 1位から8位の場合true。
     */
    static bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_EVALUATOR_MQH
