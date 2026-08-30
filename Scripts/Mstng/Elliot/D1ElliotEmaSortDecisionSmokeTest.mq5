//+------------------------------------------------------------------+
//|                 D1ElliotEmaSortDecisionSmokeTest.mq5            |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\D1ElliotEmaSortDecision.mqh>

/** 失敗したテスト件数。 */
int gFailureCount = 0;

/**
 * D1条件ランクを表示文字列へ変換する。
 *
 * @param fromRank D1条件ランク。
 * @return NG、B、A、SまたはUNKNOWN。
 */
string getConditionRankText(const int fromRank) {
    if (fromRank == 0) {
        return "NG";
    }

    if (fromRank == 1) {
        return "B";
    }

    if (fromRank == 2) {
        return "A";
    }

    if (fromRank == 3) {
        return "S";
    }

    return "UNKNOWN";
}

/**
 * D1条件ランクを期待値と照合する。
 *
 * @param fromCaseName テストケース名。
 * @param fromIsD1Buy D1がBUYの場合true。
 * @param fromIsW1Buy W1がBUYの場合true。
 * @param fromIsMn1Buy MN1がBUYの場合true。
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true。
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true。
 * @param fromExpectedRank 期待するD1条件ランク。
 */
void assertConditionRank(
    const string fromCaseName,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const int fromExpectedRank
) {
    D1ConditionSortRank actualRank =
        D1ElliotEmaSortDecision::evaluateConditionRank(
            fromIsD1Buy,
            fromIsW1Buy,
            fromIsMn1Buy,
            fromIsW1Ema200Buy,
            fromIsW1Ema200Sell
        );

    if ((int)actualRank == fromExpectedRank) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%s(%d) actual=%s(%d)",
        fromCaseName,
        getConditionRankText(fromExpectedRank),
        fromExpectedRank,
        getConditionRankText((int)actualRank),
        (int)actualRank
    );
}

/**
 * 比較テスト用のD1ソート結果を設定する。
 *
 * @param fromResult 設定対象のD1ソート結果。
 * @param fromConditionRank D1条件ランク。
 * @param fromD1WaveDirectionRank D1最新Wave方向ランク。
 * @param fromD1EmaDirectionRank D1 EMA200方向ランク。
 * @param fromW1WaveDirectionRank W1最新Wave方向ランク。
 * @param fromW1EmaDirectionRank W1 EMA200方向ランク。
 * @param fromMn1WaveDirectionRank MN1最新Wave方向ランク。
 */
void setSortResult(
    D1ElliotEmaSortResult &fromResult,
    const int fromConditionRank,
    const int fromD1WaveDirectionRank,
    const int fromD1EmaDirectionRank,
    const int fromW1WaveDirectionRank,
    const int fromW1EmaDirectionRank,
    const int fromMn1WaveDirectionRank
) {
    fromResult.reset();
    fromResult.isEvaluated = true;
    fromResult.d1ConditionRank =
        (D1ConditionSortRank)fromConditionRank;
    fromResult.d1WaveDirectionRank = fromD1WaveDirectionRank;
    fromResult.d1EmaDirectionRank = fromD1EmaDirectionRank;
    fromResult.w1WaveDirectionRank = fromW1WaveDirectionRank;
    fromResult.w1EmaDirectionRank = fromW1EmaDirectionRank;
    fromResult.mn1WaveDirectionRank = fromMn1WaveDirectionRank;
}

/**
 * 2つのD1ソート結果の比較値を期待値と照合する。
 *
 * @param fromCaseName テストケース名。
 * @param fromLeftResult 左側のD1ソート結果。
 * @param fromRightResult 右側のD1ソート結果。
 * @param fromExpectedCompareResult 期待する比較値。
 */
void assertCompare(
    const string fromCaseName,
    D1ElliotEmaSortResult &fromLeftResult,
    D1ElliotEmaSortResult &fromRightResult,
    const int fromExpectedCompareResult
) {
    D1ElliotEmaSortDecision decision;
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
 * BUY方向のS、A、BおよびNGを検証する。
 */
void validateBuyConditionRanks() {
    assertConditionRank(
        "BUY S",
        true, true, true, true, false, 3
    );
    assertConditionRank(
        "BUY A MN1 ONLY EMA NONE",
        true, true, true, false, false, 2
    );
    assertConditionRank(
        "BUY A MN1 ONLY EMA OPPOSITE",
        true, true, true, false, true, 2
    );
    assertConditionRank(
        "BUY A EMA ONLY",
        true, true, false, true, false, 2
    );
    assertConditionRank(
        "BUY B EMA NONE",
        true, true, false, false, false, 1
    );
    assertConditionRank(
        "BUY B EMA OPPOSITE",
        true, true, false, false, true, 1
    );
    assertConditionRank(
        "BUY NG W1 MISMATCH",
        true, false, true, true, false, 0
    );
}

/**
 * SELL方向のS、A、BおよびNGを検証する。
 */
void validateSellConditionRanks() {
    assertConditionRank(
        "SELL S",
        false, false, false, false, true, 3
    );
    assertConditionRank(
        "SELL A MN1 ONLY EMA NONE",
        false, false, false, false, false, 2
    );
    assertConditionRank(
        "SELL A MN1 ONLY EMA OPPOSITE",
        false, false, false, true, false, 2
    );
    assertConditionRank(
        "SELL A EMA ONLY",
        false, false, true, false, true, 2
    );
    assertConditionRank(
        "SELL B EMA NONE",
        false, false, true, false, false, 1
    );
    assertConditionRank(
        "SELL B EMA OPPOSITE",
        false, false, true, true, false, 1
    );
    assertConditionRank(
        "SELL NG W1 MISMATCH",
        false, true, false, false, true, 0
    );
}

/**
 * W1 EMA200のBUY・SELL競合を一致条件に数えないことを検証する。
 */
void validateConflictingEmaConditionRanks() {
    assertConditionRank(
        "BUY CONFLICT WITH MN1",
        true, true, true, true, true, 2
    );
    assertConditionRank(
        "BUY CONFLICT WITHOUT MN1",
        true, true, false, true, true, 1
    );
    assertConditionRank(
        "SELL CONFLICT WITH MN1",
        false, false, false, true, true, 2
    );
    assertConditionRank(
        "SELL CONFLICT WITHOUT MN1",
        false, false, true, true, true, 1
    );
}

/**
 * D1条件ランクが既存キーより先にS、A、B、NGの順で比較されることを検証する。
 */
void validateConditionRankCompareOrder() {
    D1ElliotEmaSortResult leftResult;
    D1ElliotEmaSortResult rightResult;

    setSortResult(leftResult, 3, 0, 0, 0, 0, 0);
    setSortResult(rightResult, 2, 2, 2, 2, 2, 2);
    assertCompare("S BEFORE A", leftResult, rightResult, -1);

    setSortResult(leftResult, 2, 0, 0, 0, 0, 0);
    setSortResult(rightResult, 1, 2, 2, 2, 2, 2);
    assertCompare("A BEFORE B", leftResult, rightResult, -1);

    setSortResult(leftResult, 1, 0, 0, 0, 0, 0);
    setSortResult(rightResult, 0, 2, 2, 2, 2, 2);
    assertCompare("B BEFORE NG", leftResult, rightResult, -1);

    setSortResult(leftResult, 0, 2, 2, 2, 2, 2);
    setSortResult(rightResult, 3, 0, 0, 0, 0, 0);
    assertCompare("NG AFTER S", leftResult, rightResult, 1);
}

/**
 * D1条件ランクが同じ場合に既存キーの辞書順を維持することを検証する。
 */
void validateExistingKeyCompareOrder() {
    D1ElliotEmaSortResult leftResult;
    D1ElliotEmaSortResult rightResult;

    setSortResult(leftResult, 2, 2, 0, 0, 0, 0);
    setSortResult(rightResult, 2, 0, 2, 2, 2, 2);
    assertCompare("D1 WAVE SECONDARY", leftResult, rightResult, -1);

    setSortResult(leftResult, 2, 2, 2, 0, 0, 0);
    setSortResult(rightResult, 2, 2, 0, 2, 2, 2);
    assertCompare("D1 EMA SECONDARY", leftResult, rightResult, -1);

    setSortResult(leftResult, 2, 2, 2, 2, 0, 0);
    setSortResult(rightResult, 2, 2, 2, 0, 2, 2);
    assertCompare("W1 WAVE SECONDARY", leftResult, rightResult, -1);

    setSortResult(leftResult, 2, 2, 2, 2, 2, 0);
    setSortResult(rightResult, 2, 2, 2, 2, 0, 2);
    assertCompare("W1 EMA SECONDARY", leftResult, rightResult, -1);

    setSortResult(leftResult, 2, 2, 2, 2, 2, 2);
    setSortResult(rightResult, 2, 2, 2, 2, 2, 0);
    assertCompare("MN1 WAVE SECONDARY", leftResult, rightResult, -1);
}

/**
 * 未評価結果の優先順位および完全同順位を検証する。
 */
void validateEvaluationAndTieCompareOrder() {
    D1ElliotEmaSortResult evaluatedResult;
    D1ElliotEmaSortResult unevaluatedResult;
    D1ElliotEmaSortResult sameResult;

    setSortResult(evaluatedResult, 1, 0, 0, 0, 0, 0);
    unevaluatedResult.reset();
    assertCompare(
        "EVALUATED BEFORE UNEVALUATED",
        evaluatedResult,
        unevaluatedResult,
        -1
    );
    assertCompare(
        "UNEVALUATED AFTER EVALUATED",
        unevaluatedResult,
        evaluatedResult,
        1
    );

    setSortResult(sameResult, 1, 0, 0, 0, 0, 0);
    assertCompare("SAME RESULT", evaluatedResult, sameResult, 0);
}

/**
 * D1 Elliott・EMA200ソート判定のSmokeTestを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateBuyConditionRanks();
    validateSellConditionRanks();
    validateConflictingEmaConditionRanks();
    validateConditionRankCompareOrder();
    validateExistingKeyCompareOrder();
    validateEvaluationAndTieCompareOrder();

    if (gFailureCount == 0) {
        Print("D1ElliotEmaSortDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "D1ElliotEmaSortDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
