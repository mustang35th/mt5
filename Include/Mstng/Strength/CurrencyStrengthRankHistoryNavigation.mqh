#ifndef MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_NAVIGATION_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_NAVIGATION_MQH

#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>

/**
 * 順位履歴の移動元識別と、取得済みキャッシュ内の前後検索を担当する。
 */
class CurrencyStrengthRankHistoryNavigation {
public:
    /**
     * 端末内で重複しない識別子を取得する。端末終了時に共有カウンターを破棄する。
     * 移動元の再初期化と複数の受信側の要求にも別のIDを割り当てる。
     */
    static int nextId() {
        string key = "Mstng.CurrencyRankHistory.Sequence";
        if (!GlobalVariableCheck(key) && !GlobalVariableTemp(key) && !GlobalVariableCheck(key)) {
            return 0;
        }

        for (int i = 0; i < 16; i++) {
            double current = 0;
            if (!GlobalVariableGet(key, current) || current < 0 || current >= 2147483647) {
                return 0;
            }

            if (GlobalVariableSetOnCondition(key, current + 1, current)) {
                return (int)current + 1;
            }
        }

        return 0;
    }

    /**
     * 昇順キャッシュから指定時刻より厳密に前／後の有効点を検索する。
     * 期限切れの先頭領域と不完全な点を除外し、欠損時刻は飛ばす。
     */
    static int findAdjacentIndex(const CurrencyStrengthAllRankPoint &fromPoints[],
            const int fromStartIndex, const datetime fromTime, const int fromDirection) {
        int count = ArraySize(fromPoints);
        if (fromStartIndex < 0 || fromStartIndex >= count || fromTime <= 0
                || (fromDirection != -1 && fromDirection != 1)) {
            return -1;
        }

        int leftIndex = fromStartIndex;
        int rightIndex = count;
        while (leftIndex < rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            datetime pointTime = fromPoints[middleIndex].m5BarTime;
            if (pointTime < fromTime || (fromDirection == 1 && pointTime == fromTime)) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex;
            }
        }

        int pointIndex = leftIndex;
        if (fromDirection == -1) {
            pointIndex--;
        }

        while (pointIndex >= fromStartIndex && pointIndex < count) {
            if (fromPoints[pointIndex].isValid()) {
                return pointIndex;
            }

            pointIndex += fromDirection;
        }

        return -1;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_NAVIGATION_MQH
