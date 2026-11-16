#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_CLEANUP_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_CLEANUP_MQH

#include <Mstng\Constant\Constant.mqh>

/**
 * Rank Gapの初回描画前に、以前のインスタンスが残した表示を回収する。
 * 同じサブ画面に複数のRank Gapがある場合は、稼働中の表示を保護する。
 */
class DrawCurrencyStrengthRankDeltaCleanup {
public:
    /**
     * 単独のRank Gapサブ画面に限り、専用接頭辞の古い表示を削除する。
     *
     * @param fromChartId 表示先のチャート。
     * @param fromSubWindow このインジケーターのサブ画面。
     * @return 清掃完了または複数表示保護の場合true。画面準備中・削除失敗はfalse。
     */
    static bool prepare(const long fromChartId, const int fromSubWindow) {
        if (fromSubWindow < 1) {
            return false;
        }

        int rankGapCount = 0;
        ResetLastError();
        int indicatorCount = ChartIndicatorsTotal(fromChartId, fromSubWindow);
        if (GetLastError() != 0 || indicatorCount < 1) {
            return false;
        }

        for (int i = 0; i < indicatorCount; i++) {
            ResetLastError();
            string indicatorName = ChartIndicatorName(fromChartId, fromSubWindow, i);
            if (GetLastError() != 0 || indicatorName == "") {
                return false;
            }

            if (StringFind(indicatorName, "Rank Gap ") == 0) {
                rankGapCount++;
            }
        }

        if (rankGapCount == 0) {
            return false;
        }

        if (rankGapCount > 1) {
            return true;
        }

        bool cleared = clearPrefix(fromChartId, fromSubWindow, "GapRanks_");
        cleared = clearPrefix(fromChartId, fromSubWindow, "RankDelta_") && cleared;
        cleared = clearPrefix(fromChartId, fromSubWindow, "RankGapFill_") && cleared;

        return cleared;
    }

private:
    /**
     * 指定サブ画面内のRank Gap所有オブジェクトだけを同期削除する。
     */
    static bool clearPrefix(const long fromChartId, const int fromSubWindow, const string fromSuffix) {
        ResetLastError();
        ObjectsDeleteAll(fromChartId, Constant::PREFIX_FIXED + fromSuffix, fromSubWindow, -1);

        return GetLastError() == 0;
    }
};

#endif
