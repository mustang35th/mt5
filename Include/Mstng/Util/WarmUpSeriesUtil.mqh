//+------------------------------------------------------------------+
//|                                             WarmUpSeriesUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __WARMUP_SERIES_UTIL_MQH__
#define __WARMUP_SERIES_UTIL_MQH__

#include <Mstng\Common\MarketContext.mqh>

/**
 * 指定シンボルの価格系列を時間足単位で
 * あらかじめ初期化（warm-up）するユーティリティです。
 */
class WarmUpSeriesUtil {
public:
    /**
     * 代表的な時間足（MN1→…→M1）を warm-up する。
     * fromTimeFrame までを対象とし、それより下位（短い）足は含めない。
     *
     * 対象時間足は固定8本（MN1、W1、D1、H4、H1、M15、M5、M1）のみです。
     *
     * @param symbolName     シンボル名
     * @param fromTimeFrame  対象上限時間足（例：PERIOD_W1 の場合、MN1/W1 まで）。
     * @param barsNeeded     各時間足で CopyRates するバー本数（同期促進目的）
     */
    static void warmUpFromMn1To(string symbolName, ENUM_TIMEFRAMES fromTimeFrame, int barsNeeded = 200) {
        MarketContext context(symbolName, fromTimeFrame);

        WarmUpSeriesUtil::warmUpFromMn1To(context, barsNeeded);
    }

    /**
     * 市場コンテキストを使用してMN1から対象時間足までをウォームアップする。
     *
     * @param fromMarketContext ウォームアップ対象の市場コンテキスト。
     * @param barsNeeded 各時間足で CopyRates するバー本数。
     */
    static void warmUpFromMn1To(MarketContext &fromMarketContext, int barsNeeded = 200) {
        SymbolSelect(fromMarketContext.symbolName, true);

        ENUM_TIMEFRAMES tfs[];
        WarmUpSeriesUtil::buildTimeframesFromMn1To(fromMarketContext.timeFrame, tfs);

        WarmUpSeriesUtil::warmUp(fromMarketContext, tfs, barsNeeded);
    }

    /**
     * 指定した時間足配列を warm-up する。
     *
     * @param symbolName   シンボル名
     * @param timeFrames   対象時間足配列。
     * @param barsNeeded   CopyRates する本数。
     */
    static void warmUp(string symbolName, const ENUM_TIMEFRAMES &timeFrames[], int barsNeeded = 200) {
        MarketContext context(symbolName, PERIOD_CURRENT);

        WarmUpSeriesUtil::warmUp(context, timeFrames, barsNeeded);
    }

    /**
     * 市場コンテキストのシンボルについて指定時間足配列をウォームアップする。
     *
     * @param fromMarketContext ウォームアップ対象の市場コンテキスト
     * @param timeFrames 対象時間足配列。
     * @param barsNeeded CopyRates する本数。
     */
    static void warmUp(
        MarketContext &fromMarketContext,
        const ENUM_TIMEFRAMES &timeFrames[],
        int barsNeeded = 200
    ) {
        SymbolSelect(fromMarketContext.symbolName, true);

        int total = ArraySize(timeFrames);

        for (int i = 0; i < total; i++) {
            ENUM_TIMEFRAMES timeFrame = timeFrames[i];

            MqlRates rates[];
            ArraySetAsSeries(rates, true);

            ResetLastError();
            CopyRates(fromMarketContext.symbolName, timeFrame, 0, barsNeeded, rates);
        }
    }

    /**
     * シリーズ同期済みかを判定する。
     * CopyBuffer前のガード用途。
     *
     * @param symbolName 対象シンボル名
     * @param timeFrame  対象時間足
     * @return 同期済みの場合 true。
     */
    static bool isSeriesSynchronized(string symbolName, ENUM_TIMEFRAMES timeFrame) {
        MarketContext context(symbolName, timeFrame);

        return WarmUpSeriesUtil::isSeriesSynchronized(context);
    }

    /**
     * 市場コンテキストの価格系列が同期済みかを判定する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     * @return 同期済みの場合 true。
     */
    static bool isSeriesSynchronized(MarketContext &fromMarketContext) {
        long synced = 0;

        if (!SeriesInfoInteger(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            SERIES_SYNCHRONIZED,
            synced
        )) {
            return false;
        }

        return (synced != 0);
    }

private:
    /**
     * MN1→...→fromTimeFrame までの時間足配列を構築する。
     *
     * @param fromTimeFrame 取得上限時間足
     * @param fromOutTimeFrames 生成先配列（out）。
     */
    static void buildTimeframesFromMn1To(ENUM_TIMEFRAMES fromTimeFrame, ENUM_TIMEFRAMES &outTimeFrames[]) {
        ENUM_TIMEFRAMES all[] = {
            PERIOD_MN1,
            PERIOD_W1,
            PERIOD_D1,
            PERIOD_H4,
            PERIOD_H1,
            PERIOD_M15,
            PERIOD_M5,
            PERIOD_M1
        };

        int index = WarmUpSeriesUtil::findIndex(all, fromTimeFrame);

        if (index < 0) {
            ArrayResize(outTimeFrames, ArraySize(all));
            for (int i = 0; i < ArraySize(all); i++) {
                outTimeFrames[i] = all[i];
            }
            return;
        }

        ArrayResize(outTimeFrames, index + 1);
        for (int i = 0; i <= index; i++) {
            outTimeFrames[i] = all[i];
        }
    }

    /**
     * 配列内で指定値のインデックスを検索する。
     *
     * @param fromArray 対象配列
     * @param fromValue 検索対象値。
     * @return 発見時はインデックス、見つからなければ-1。
     */
    static int findIndex(const ENUM_TIMEFRAMES &fromArray[], ENUM_TIMEFRAMES fromValue) {
        int total = ArraySize(fromArray);

        for (int i = 0; i < total; i++) {
            if (fromArray[i] == fromValue) {
                return i;
            }
        }

        return -1;
    }
};

#endif  // __WARMUP_SERIES_UTIL_MQH__


