#property version "1.00"
#property script_show_inputs

#include <MstngH1Ea\Strategy\H1EaInitialStopLossDecision.mqh>

/** 検証失敗数。 */
int failureCount = 0;

/**
 * 期待条件を確認する。
 */
void assertCondition(const string fromName, const bool fromCondition) {
    if (!fromCondition) {
        failureCount++;
        Print("FAIL " + fromName);
    }
}

/**
 * 発注しない初期SL純粋判定のSmokeTest。
 */
void OnStart() {
    H1EaInitialStopLossDecision decision;
    H1EaInitialStopLossResult result;
    assertCondition("BUY 10 pips buffer", decision.evaluate(
        true, 1.10000, false, 1.10190, 1.10200, 0.0001, 0.00001,
        0.00001, 10, 30.0, result
    ));
    assertCondition("BUY stop/risk", MathAbs(result.stopLoss - 1.099) < 1.0e-10
        && MathAbs(result.riskPips - 30.0) < 1.0e-8);
    assertCondition("SELL 10 pips buffer", decision.evaluate(
        false, 1.10200, true, 1.10000, 1.10010, 0.0001, 0.00001,
        0.00001, 10, 30.0, result
    ));
    assertCondition("SELL stop/risk", MathAbs(result.stopLoss - 1.103) < 1.0e-10
        && MathAbs(result.riskPips - 30.0) < 1.0e-8);
    assertCondition("unset maximum rejects", !decision.evaluate(
        true, 1.1, false, 1.1019, 1.102, 0.0001, 0.00001,
        0.00001, 0, 0.0, result
    ) && result.reasonCode == "MAX_INITIAL_STOP_LOSS_UNSET");
    assertCondition("maximum exceeded", !decision.evaluate(
        true, 1.1, false, 1.1019, 1.102, 0.0001, 0.00001,
        0.00001, 0, 29.9, result
    ) && result.reasonCode == "INITIAL_STOP_LOSS_TOO_WIDE");
    assertCondition("BUY peak rejects", !decision.evaluate(
        true, 1.1, true, 1.1019, 1.102, 0.0001, 0.00001,
        0.00001, 0, 50.0, result
    ) && result.reasonCode == "INITIAL_STOP_LOSS_PIVOT_DIRECTION_MISMATCH");
    assertCondition("SELL valley rejects", !decision.evaluate(
        false, 1.102, false, 1.1, 1.1001, 0.0001, 0.00001,
        0.00001, 0, 50.0, result
    ));
    assertCondition("stops uses BUY Bid", !decision.evaluate(
        true, 1.1, false, 1.0992, 1.0993, 0.0001, 0.00001,
        0.00001, 30, 50.0, result
    ) && result.reasonCode == "INITIAL_STOP_LOSS_STOPS_LEVEL");
    assertCondition("stops uses SELL Ask", !decision.evaluate(
        false, 1.1, true, 1.1007, 1.1008, 0.0001, 0.00001,
        0.00001, 30, 50.0, result
    ) && result.reasonCode == "INITIAL_STOP_LOSS_STOPS_LEVEL");
    assertCondition("BUY round down", decision.evaluate(
        true, 1.10003, false, 1.1019, 1.102, 0.0001, 0.00005,
        0.00001, 0, 50.0, result
    ) && MathAbs(result.stopLoss - 1.09900) < 1.0e-10);
    assertCondition("SELL round up", decision.evaluate(
        false, 1.10003, true, 1.098, 1.0981, 0.0001, 0.00005,
        0.00001, 0, 50.0, result
    ) && MathAbs(result.stopLoss - 1.10105) < 1.0e-10);
    assertCondition("invalid unit", !decision.evaluate(
        true, 1.1, false, 1.1019, 1.102, 0.0, 0.00001,
        0.00001, 0, 50.0, result
    ));
    assertCondition("nonpositive SL", !decision.evaluate(
        true, 0.0005, false, 0.0019, 0.002, 0.0001, 0.00001,
        0.00001, 0, 50.0, result
    ));
    assertCondition("crossed BUY SL", !decision.evaluate(
        true, 1.105, false, 1.1019, 1.102, 0.0001, 0.00001,
        0.00001, 0, 50.0, result
    ) && result.reasonCode == "INITIAL_STOP_LOSS_WRONG_SIDE");
    assertCondition("EMPTY_VALUE price", !decision.evaluate(
        true, EMPTY_VALUE, false, 1.1019, 1.102, 0.0001, 0.00001,
        0.00001, 0, 50.0, result
    ));
    PrintFormat("MstngH1InitialStopLossSmokeTest completed failures=%d", failureCount);
}
