//+------------------------------------------------------------------+
//|                                  H1D1EntrySortDecision.mqh       |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_H1_D1_ENTRY_SORT_DECISION_MQH
#define MSTNG_H1_D1_ENTRY_SORT_DECISION_MQH

#include <Mstng\Elliot\D1ElliotEmaSortDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3EntryPriorityDecision.mqh>

/**
 * H1一覧用のD1環境とエントリー優先度のソート結果。
 */
class H1D1EntrySortResult {
public:
    /** D1環境を評価できた場合true。 */
    bool isEvaluated;
    /** D1に対する上位足条件の一致ランク。 */
    D1ConditionSortRank d1ConditionRank;
    /** ENTRY判定に使用した時間足。 */
    ENUM_TIMEFRAMES entryTimeFrame;
    /** エントリー優先度。 */
    Mtf3In3EntryPriorityRank entryPriorityRank;
    /** 1波または3波に一致した時間足数。 */
    int waveMatchCount;
    /** 一致した副条件数。 */
    int conditionMatchCount;
    /** D1最新Waveの方向一致ランク。 */
    int d1WaveDirectionRank;
    /** D1 EMA200の方向一致ランク。 */
    int d1EmaDirectionRank;

    /**
     * 未判定状態で初期化する。
     */
    H1D1EntrySortResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.isEvaluated = false;
        this.d1ConditionRank = d1ConditionSortRankNg;
        this.entryTimeFrame = PERIOD_CURRENT;
        this.entryPriorityRank = mtf3In3EntryPriorityError;
        this.waveMatchCount = 0;
        this.conditionMatchCount = 0;
        this.d1WaveDirectionRank = 0;
        this.d1EmaDirectionRank = 0;
    }
};

/**
 * H1一覧でD1環境を主キー、ENTRY状態を副キーとして比較するクラス。
 *
 * D1条件ランクを最優先し、同じランクではD1と直接一致するH1判定を
 * H4代替判定より先にする。その後にENTRY状態と一致数を比較する。
 */
class H1D1EntrySortDecision {
public:
    /**
     * 既存のD1環境とENTRY判定からH1一覧用ソート結果を生成する。
     *
     * @param fromD1SortResult D1環境の判定結果。
     * @param fromEntryTimeFrame ENTRY判定に使用した時間足。
     * @param fromPriorityResult ENTRY優先度の判定結果。
     * @param fromResult H1一覧用ソート結果の格納先。
     */
    void evaluate(
        D1ElliotEmaSortResult &fromD1SortResult,
        ENUM_TIMEFRAMES fromEntryTimeFrame,
        Mtf3In3EntryPriorityResult &fromPriorityResult,
        H1D1EntrySortResult &fromResult
    ) {
        fromResult.reset();
        fromResult.entryTimeFrame = fromEntryTimeFrame;
        fromResult.entryPriorityRank = fromPriorityResult.rank;
        fromResult.waveMatchCount = fromPriorityResult.waveMatchCount;
        fromResult.conditionMatchCount =
            fromPriorityResult.conditionMatchCount;

        if (!fromD1SortResult.isEvaluated) {
            return;
        }

        fromResult.d1ConditionRank =
            fromD1SortResult.d1ConditionRank;
        fromResult.d1WaveDirectionRank =
            fromD1SortResult.d1WaveDirectionRank;
        fromResult.d1EmaDirectionRank =
            fromD1SortResult.d1EmaDirectionRank;
        fromResult.isEvaluated = true;
    }

    /**
     * 2つのH1一覧用ソート結果を優先順で比較する。
     *
     * @param fromLeftResult 左側の判定結果。
     * @param fromRightResult 右側の判定結果。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compare(
        H1D1EntrySortResult &fromLeftResult,
        H1D1EntrySortResult &fromRightResult
    ) {
        if (fromLeftResult.isEvaluated != fromRightResult.isEvaluated) {
            if (fromLeftResult.isEvaluated) {
                return -1;
            }

            return 1;
        }

        int compareResult = this.compareDescending(
            (int)fromLeftResult.d1ConditionRank,
            (int)fromRightResult.d1ConditionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareEntryTimeFrame(
            fromLeftResult.entryTimeFrame,
            fromRightResult.entryTimeFrame
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareAscending(
            (int)fromLeftResult.entryPriorityRank,
            (int)fromRightResult.entryPriorityRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareDescending(
            fromLeftResult.waveMatchCount,
            fromRightResult.waveMatchCount
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareDescending(
            fromLeftResult.conditionMatchCount,
            fromRightResult.conditionMatchCount
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareDescending(
            fromLeftResult.d1WaveDirectionRank,
            fromRightResult.d1WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        return this.compareDescending(
            fromLeftResult.d1EmaDirectionRank,
            fromRightResult.d1EmaDirectionRank
        );
    }

private:
    /**
     * ENTRY判定足をH1直接一致、H4代替の順で比較する。
     *
     * @param fromLeftTimeFrame 左側のENTRY判定足。
     * @param fromRightTimeFrame 右側のENTRY判定足。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compareEntryTimeFrame(
        ENUM_TIMEFRAMES fromLeftTimeFrame,
        ENUM_TIMEFRAMES fromRightTimeFrame
    ) {
        int leftRank = this.getEntryTimeFrameRank(fromLeftTimeFrame);
        int rightRank = this.getEntryTimeFrameRank(fromRightTimeFrame);

        return this.compareDescending(leftRank, rightRank);
    }

    /**
     * ENTRY判定足の優先ランクを取得する。
     *
     * @param fromTimeFrame ENTRY判定足。
     * @return H1の場合1、それ以外の場合0。
     */
    int getEntryTimeFrameRank(ENUM_TIMEFRAMES fromTimeFrame) {
        if (fromTimeFrame == PERIOD_H1) {
            return 1;
        }

        return 0;
    }

    /**
     * 小さい値を優先して比較する。
     *
     * @param fromLeftRank 左側ランク。
     * @param fromRightRank 右側ランク。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compareAscending(int fromLeftRank, int fromRightRank) {
        if (fromLeftRank < fromRightRank) {
            return -1;
        }

        if (fromLeftRank > fromRightRank) {
            return 1;
        }

        return 0;
    }

    /**
     * 大きい値を優先して比較する。
     *
     * @param fromLeftRank 左側ランク。
     * @param fromRightRank 右側ランク。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compareDescending(int fromLeftRank, int fromRightRank) {
        if (fromLeftRank > fromRightRank) {
            return -1;
        }

        if (fromLeftRank < fromRightRank) {
            return 1;
        }

        return 0;
    }
};

#endif // MSTNG_H1_D1_ENTRY_SORT_DECISION_MQH
