//+------------------------------------------------------------------+
//|                                       PriceMovementAnalyzer.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_ANALYSIS_PRICE_MOVEMENT_ANALYZER_MQH
#define MSTNG_ANALYSIS_PRICE_MOVEMENT_ANALYZER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\AverageTrueRange.mqh>
#include <Mstng\Oscillator\PriceMovementInfo.mqh>
#include <Mstng\Util\RateUtil.mqh>

/**
 * 直近3本の確定足の平均高安差を、その直前のATR14と比較する。
 * 現在スプレッドとの倍率は補助情報として保持する。
 */
class PriceMovementAnalyzer {
public:
    /**
     * 値動きの計算方式をアラート実行情報へ保存するための文字列を取得する。
     *
     * @return 計算バージョン、確定足本数、ATR参照位置と分類閾値。
     */
    static string getCalculationProfileText() {
        return "priceMovementVersion=PRICE_MOVEMENT_V1"
            + "|priceMovementRecentBars=3|priceMovementAtrPeriod=14"
            + "|priceMovementReferenceShift=4"
            + "|priceMovementCalmUpperRatio=0.8|priceMovementActiveLowerRatio=1.2";
    }

    /**
     * 対象時間足の値動きを計算する。
     *
     * @param fromMarketContext 対象銘柄と時間足。
     * @param fromHandlePool 既存のATR14ハンドルプール。
     * @param fromResult 計算結果。失敗時は判定不能。
     * @return 値幅とATRの比較が成功した場合true。
     */
    bool update(
        MarketContext &fromMarketContext,
        AverageTrueRangeHandlePool *fromHandlePool,
        PriceMovementInfo &fromResult
    ) {
        fromResult.resetValues();

        if (fromHandlePool == NULL) {
            return false;
        }

        double pipSize = RateUtil::getPoint(fromMarketContext)
            * RateUtil::getPipInPoints(fromMarketContext);
        if (!MathIsValidNumber(pipSize) || pipSize <= 0.0) {
            return false;
        }

        // shift 1〜3が対象足、shift 4が基準ATRの足。
        const int recentBars = 3;
        const int referenceShift = recentBars + 1;
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            1,
            referenceShift,
            rates
        );
        if (copied != referenceShift) {
            return false;
        }

        double totalRange = 0.0;
        for (int i = 0; i < recentBars; i++) {
            if (!MathIsValidNumber(rates[i].high)
                    || !MathIsValidNumber(rates[i].low)
                    || rates[i].high == EMPTY_VALUE
                    || rates[i].low == EMPTY_VALUE
                    || rates[i].high < rates[i].low
                    || rates[i].time <= rates[i + 1].time
                    || rates[i + 1].time <= 0) {
                return false;
            }

            totalRange += rates[i].high - rates[i].low;
        }

        AverageTrueRange averageTrueRange(fromMarketContext, fromHandlePool);
        double referenceAtr = 0.0;
        if (!averageTrueRange.getAtrValue(
                fromMarketContext,
                referenceShift,
                referenceAtr)) {
            return false;
        }

        if (!MathIsValidNumber(referenceAtr)
                || referenceAtr == EMPTY_VALUE
                || referenceAtr <= 0.0) {
            return false;
        }

        // 取得中に新しい足へ移った場合は異なる時点の値を混ぜない。
        if (iTime(fromMarketContext.symbolName, fromMarketContext.timeFrame, 1)
                    != rates[0].time
                || iTime(fromMarketContext.symbolName, fromMarketContext.timeFrame, referenceShift)
                    != rates[recentBars].time) {
            return false;
        }

        double averageRange = totalRange / recentBars;
        double activityRatio = averageRange / referenceAtr;
        if (!MathIsValidNumber(averageRange) || !MathIsValidNumber(activityRatio)) {
            return false;
        }

        fromResult.averageRangePips = averageRange / pipSize;
        fromResult.referenceAtrPips = referenceAtr / pipSize;
        fromResult.activityRatio = activityRatio;
        fromResult.referenceBarTime = rates[0].time;
        fromResult.level = PRICE_MOVEMENT_NORMAL;
        if (activityRatio < 0.8) {
            fromResult.level = PRICE_MOVEMENT_CALM;
        } else if (activityRatio >= 1.2) {
            fromResult.level = PRICE_MOVEMENT_ACTIVE;
        }

        // スプレッドが取得できない場合も値幅とATRの比較は表示できる。
        MqlTick quote;
        if (SymbolInfoTick(fromMarketContext.symbolName, quote)
                && MathIsValidNumber(quote.ask)
                && MathIsValidNumber(quote.bid)
                && quote.ask != EMPTY_VALUE
                && quote.bid != EMPTY_VALUE
                && quote.bid > 0.0
                && quote.ask > quote.bid) {
            double rangeSpreadRatio = averageRange / (quote.ask - quote.bid);
            if (MathIsValidNumber(rangeSpreadRatio)) {
                fromResult.rangeSpreadRatio = rangeSpreadRatio;
                fromResult.isSpreadValid = true;
            }
        }

        fromResult.isValid = true;

        return true;
    }
};

#endif // MSTNG_ANALYSIS_PRICE_MOVEMENT_ANALYZER_MQH
