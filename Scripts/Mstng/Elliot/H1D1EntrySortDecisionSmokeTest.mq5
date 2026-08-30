//+------------------------------------------------------------------+
//|                  H1D1EntrySortDecisionSmokeTest.mq5              |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\ElliotListSortType.mqh>
#include <Mstng\Elliot\H1D1EntrySortDecision.mqh>

/** 失敗したテスト件数。 */
int gFailureCount = 0;

/**
 * H1一覧用ソート結果をテスト値で生成する。
 *
 * @param fromResult 生成先。
 * @param fromIsD1Evaluated D1環境を評価済みにする場合true。
 * @param fromD1ConditionRank D1条件ランク。
 * @param fromEntryTimeFrame ENTRY判定足。
 * @param fromEntryPriorityRank ENTRY優先度。
 * @param fromWaveMatchCount 波動一致数。
 * @param fromConditionMatchCount 副条件一致数。
 * @param fromD1WaveDirectionRank D1 Wave方向一致ランク。
 * @param fromD1EmaDirectionRank D1 EMA200方向一致ランク。
 */
void buildSortResult(
    H1D1EntrySortResult &fromResult,
    const bool fromIsD1Evaluated,
    const int fromD1ConditionRank,
    const ENUM_TIMEFRAMES fromEntryTimeFrame,
    const Mtf3In3EntryPriorityRank fromEntryPriorityRank,
    const int fromWaveMatchCount,
    const int fromConditionMatchCount,
    const int fromD1WaveDirectionRank,
    const int fromD1EmaDirectionRank
) {
    D1ElliotEmaSortResult d1SortResult;
    d1SortResult.reset();
    d1SortResult.isEvaluated = fromIsD1Evaluated;
    d1SortResult.d1ConditionRank =
        (D1ConditionSortRank)fromD1ConditionRank;
    d1SortResult.d1WaveDirectionRank = fromD1WaveDirectionRank;
    d1SortResult.d1EmaDirectionRank = fromD1EmaDirectionRank;

    Mtf3In3EntryPriorityResult priorityResult;
    priorityResult.reset();
    priorityResult.rank = fromEntryPriorityRank;
    priorityResult.waveMatchCount = fromWaveMatchCount;
    priorityResult.conditionMatchCount = fromConditionMatchCount;

    H1D1EntrySortDecision decision;
    decision.evaluate(
        d1SortResult,
        fromEntryTimeFrame,
        priorityResult,
        fromResult
    );
}

/**
 * 2つのソート結果を期待値と照合する。
 *
 * @param fromCaseName テストケース名。
 * @param fromLeftResult 左側結果。
 * @param fromRightResult 右側結果。
 * @param fromExpectedCompareResult 期待する比較値。
 */
void assertCompare(
    const string fromCaseName,
    H1D1EntrySortResult &fromLeftResult,
    H1D1EntrySortResult &fromRightResult,
    const int fromExpectedCompareResult
) {
    H1D1EntrySortDecision decision;
    int actualCompareResult = decision.compare(
        fromLeftResult,
        fromRightResult
    );

    if (actualCompareResult == fromExpectedCompareResult) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%d actual=%d",
        fromCaseName,
        fromExpectedCompareResult,
        actualCompareResult
    );
}

/**
 * 優先結果と後続結果を左右両方向で照合する。
 *
 * @param fromCaseName テストケース名。
 * @param fromPreferredResult 優先される結果。
 * @param fromFollowingResult 後続になる結果。
 */
void assertOrder(
    const string fromCaseName,
    H1D1EntrySortResult &fromPreferredResult,
    H1D1EntrySortResult &fromFollowingResult
) {
    assertCompare(
        fromCaseName + " FORWARD",
        fromPreferredResult,
        fromFollowingResult,
        -1
    );
    assertCompare(
        fromCaseName + " REVERSE",
        fromFollowingResult,
        fromPreferredResult,
        1
    );
}

/**
 * 整数値を期待値と照合する。
 *
 * @param fromCaseName テストケース名。
 * @param fromActualValue 実際の値。
 * @param fromExpectedValue 期待値。
 */
void assertInt(
    const string fromCaseName,
    const int fromActualValue,
    const int fromExpectedValue
) {
    if (fromActualValue == fromExpectedValue) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%d actual=%d",
        fromCaseName,
        fromExpectedValue,
        fromActualValue
    );
}

/**
 * D1評価可否とD1条件ランクが最優先されることを検証する。
 */
void validateD1Priority() {
    H1D1EntrySortResult leftResult;
    H1D1EntrySortResult rightResult;

    buildSortResult(
        leftResult, true, 3, PERIOD_H4,
        mtf3In3EntryPriorityError, 0, 0, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder("D1 S BEFORE A READY", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H4,
        mtf3In3EntryPriorityError, 0, 0, 0, 0
    );
    buildSortResult(
        rightResult, true, 1, PERIOD_H1,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder("D1 A BEFORE B READY", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 1, PERIOD_H4,
        mtf3In3EntryPriorityError, 0, 0, 0, 0
    );
    buildSortResult(
        rightResult, true, 0, PERIOD_H1,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder("D1 B BEFORE NG READY", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 0, PERIOD_H4,
        mtf3In3EntryPriorityError, 0, 0, 0, 0
    );
    buildSortResult(
        rightResult, false, 3, PERIOD_H1,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder("D1 EVALUATED FIRST", leftResult, rightResult);
}

/**
 * 同じD1条件ではH1直接一致がH4代替より優先されることを検証する。
 */
void validateEntryTimeFramePriority() {
    H1D1EntrySortResult h1Result;
    H1D1EntrySortResult h4Result;

    buildSortResult(
        h1Result, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityNear, 1, 8, 0, 0
    );
    buildSortResult(
        h4Result, true, 2, PERIOD_H4,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder("H1 DIRECT BEFORE H4 READY", h1Result, h4Result);
}

/**
 * ENTRY状態、波動一致数、副条件一致数の順を検証する。
 */
void validateEntryPriority() {
    H1D1EntrySortResult leftResult;
    H1D1EntrySortResult rightResult;

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityReady, 1, 5, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityNear, 3, 9, 2, 2
    );
    assertOrder("READY BEFORE NEAR", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityNear, 1, 5, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 3, 9, 2, 2
    );
    assertOrder("NEAR BEFORE SETUP", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 5, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityAlign, 3, 9, 2, 2
    );
    assertOrder("SETUP BEFORE ALIGN", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityAlign, 1, 5, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPriorityError, 3, 9, 2, 2
    );
    assertOrder("ALIGN BEFORE ERROR", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 2, 5, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 9, 2, 2
    );
    assertOrder("MORE WAVES FIRST", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 8, 0, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 2
    );
    assertOrder("MORE CONDITIONS FIRST", leftResult, rightResult);
}

/**
 * ENTRY条件が同じ場合にD1 Wave、D1 EMA200の順で比較することを検証する。
 */
void validateD1DetailPriority() {
    H1D1EntrySortResult leftResult;
    H1D1EntrySortResult rightResult;

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 0
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 0, 2
    );
    assertOrder("D1 WAVE BEFORE EMA", leftResult, rightResult);

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 2
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 1
    );
    assertOrder("D1 EMA FINAL KEY", leftResult, rightResult);
}

/**
 * evaluateの転記、reset、およびD1未評価同士の比較を検証する。
 */
void validateEvaluateAndReset() {
    H1D1EntrySortResult result;
    H1D1EntrySortResult followingResult;

    buildSortResult(
        result, true, 2, PERIOD_H4,
        mtf3In3EntryPriorityNear, 2, 7, 2, 1
    );
    assertInt("COPY EVALUATED", (int)result.isEvaluated, 1);
    assertInt("COPY D1 RANK", (int)result.d1ConditionRank, 2);
    assertInt("COPY ENTRY TF", (int)result.entryTimeFrame, (int)PERIOD_H4);
    assertInt(
        "COPY ENTRY RANK",
        (int)result.entryPriorityRank,
        (int)mtf3In3EntryPriorityNear
    );
    assertInt("COPY WAVES", result.waveMatchCount, 2);
    assertInt("COPY CONDITIONS", result.conditionMatchCount, 7);
    assertInt("COPY D1 WAVE", result.d1WaveDirectionRank, 2);
    assertInt("COPY D1 EMA", result.d1EmaDirectionRank, 1);

    result.reset();
    assertInt("RESET EVALUATED", (int)result.isEvaluated, 0);
    assertInt(
        "RESET ENTRY RANK",
        (int)result.entryPriorityRank,
        (int)mtf3In3EntryPriorityError
    );

    buildSortResult(
        result, false, 3, PERIOD_H1,
        mtf3In3EntryPriorityNear, 1, 8, 2, 2
    );
    buildSortResult(
        followingResult, false, 3, PERIOD_H4,
        mtf3In3EntryPriorityReady, 3, 9, 2, 2
    );
    assertOrder(
        "UNEVALUATED H1 BEFORE H4",
        result,
        followingResult
    );
}

/**
 * 完全同順位と既存enum値の互換性を検証する。
 */
void validateTieAndEnumValues() {
    H1D1EntrySortResult leftResult;
    H1D1EntrySortResult rightResult;

    buildSortResult(
        leftResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 2
    );
    buildSortResult(
        rightResult, true, 2, PERIOD_H1,
        mtf3In3EntryPrioritySetup, 1, 7, 2, 2
    );
    assertCompare("STABLE TIE", leftResult, rightResult, 0);

    assertInt("ENUM ENTRY", (int)ELLIOT_LIST_SORT_ENTRY_PRIORITY, 0);
    assertInt("ENUM M15", (int)ELLIOT_LIST_SORT_M15_ELLIOT_EMA, 1);
    assertInt("ENUM D1", (int)ELLIOT_LIST_SORT_D1_ELLIOT_EMA, 2);
    assertInt("ENUM H1", (int)ELLIOT_LIST_SORT_H1_D1_ENTRY, 3);
}

/**
 * H1 D1環境・ENTRYソート判定のSmokeTestを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateD1Priority();
    validateEntryTimeFramePriority();
    validateEntryPriority();
    validateD1DetailPriority();
    validateEvaluateAndReset();
    validateTieAndEnumValues();

    if (gFailureCount == 0) {
        Print("H1D1EntrySortDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1D1EntrySortDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
