//+------------------------------------------------------------------+
//|                 Mtf3In3Ema200DistancePolicySmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\Mtf3In3Ema200DistancePolicy.mqh>

/**
 * 時間足別のEMA200距離上限を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromTimeFrame 判定対象時間足。
 * @param fromExpectedMaxPips 期待する距離上限pips。
 * @return 期待値と一致する場合true。
 */
bool assertMaxPips(
    const string fromCaseName,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const double fromExpectedMaxPips
) {
    Mtf3In3Ema200DistancePolicy policy;
    double actualMaxPips = policy.getMaxCloseEma200DiffPips(
        fromTimeFrame
    );

    if (actualMaxPips != fromExpectedMaxPips) {
        PrintFormat(
            "FAIL %s actual=%.1f expected=%.1f",
            fromCaseName,
            actualMaxPips,
            fromExpectedMaxPips
        );

        return false;
    }

    return true;
}

/**
 * EMA200距離判定を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromTimeFrame 判定対象時間足。
 * @param fromCloseEma200DiffPips Close1とEMA200[1]の距離pips。
 * @param fromExpectedResult 期待する判定結果。
 * @return 期待値と一致する場合true。
 */
bool assertDistance(
    const string fromCaseName,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const double fromCloseEma200DiffPips,
    const bool fromExpectedResult
) {
    Mtf3In3Ema200DistancePolicy policy;
    bool actualResult = policy.isCloseEma200DiffPipsWithin(
        fromTimeFrame,
        fromCloseEma200DiffPips
    );

    if (actualResult != fromExpectedResult) {
        PrintFormat(
            "FAIL %s diff=%.1f actual=%s expected=%s",
            fromCaseName,
            fromCloseEma200DiffPips,
            (string)actualResult,
            (string)fromExpectedResult
        );

        return false;
    }

    return true;
}

/**
 * H1の50 pips上限とH1以外の25 pips上限を検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!assertMaxPips("H1 max", PERIOD_H1, 50.0)) {
        failureCount++;
    }

    if (!assertMaxPips("M15 max", PERIOD_M15, 25.0)) {
        failureCount++;
    }

    if (!assertMaxPips("M5 max", PERIOD_M5, 25.0)) {
        failureCount++;
    }

    if (!assertDistance("H1 below", PERIOD_H1, 49.9, true)) {
        failureCount++;
    }

    if (!assertDistance("H1 boundary", PERIOD_H1, 50.0, true)) {
        failureCount++;
    }

    if (!assertDistance("H1 over", PERIOD_H1, 50.1, false)) {
        failureCount++;
    }

    if (!assertDistance("H1 negative boundary", PERIOD_H1, -50.0, true)) {
        failureCount++;
    }

    if (!assertDistance("H1 negative over", PERIOD_H1, -50.1, false)) {
        failureCount++;
    }

    if (!assertDistance("M5 below", PERIOD_M5, 24.9, true)) {
        failureCount++;
    }

    if (!assertDistance("M5 boundary", PERIOD_M5, 25.0, true)) {
        failureCount++;
    }

    if (!assertDistance("M5 over", PERIOD_M5, 25.1, false)) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("Mtf3In3Ema200DistancePolicySmokeTest PASS");

        return;
    }

    PrintFormat(
        "Mtf3In3Ema200DistancePolicySmokeTest FAIL count=%d",
        failureCount
    );
}
