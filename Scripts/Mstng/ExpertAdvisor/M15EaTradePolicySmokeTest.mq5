#property strict

#include <MstngM15Ea\Trade\M15EaTradePolicy.mqh>

/** 検証失敗数。 */
int failureCount = 0;

/**
 * 実注文を送らず条件を集計する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (!fromSuccess) {
        failureCount++;
        Print("ERROR M15EaTradePolicySmokeTest FAIL ", fromName);
    }
}

/**
 * 取引時刻後に確定したM15の谷・山を作る。
 */
Wave *createWave(const bool fromIsBuy) {
    Wave *wave = new Wave();
    ZigZagPoint *pivot = new ZigZagPoint();
    ZigZagPoint *latest = new ZigZagPoint();
    if (wave == NULL || pivot == NULL || latest == NULL) {
        if (pivot != NULL) {
            delete pivot;
        }
        if (latest != NULL) {
            delete latest;
        }
        if (wave != NULL) {
            delete wave;
        }
        return NULL;
    }
    MarketContext context("EURUSD", PERIOD_M15, "M15", 5);
    wave.marketContext = context;
    pivot.marketContext = context;
    latest.marketContext = context;
    pivot.rate = 1.1000;
    pivot.barTime = D'2026.01.01 04:00:00';
    pivot.barIndex = 2;
    pivot.isPeak = !fromIsBuy;
    pivot.isAddedPoint = false;
    latest.rate = 1.1100;
    if (!fromIsBuy) {
        latest.rate = 1.0900;
    }
    latest.barTime = D'2026.01.01 04:15:00';
    latest.barIndex = 1;
    latest.isPeak = fromIsBuy;
    latest.isAddedPoint = false;
    wave.zigZagPointList.Add(pivot);
    wave.zigZagPointList.Add(latest);
    return wave;
}

/**
 * 現在SLが候補より損失側にあるポジションを作る。
 */
void preparePosition(const bool fromIsBuy, PositionSnapshot &fromPosition) {
    fromPosition.hasPosition = true;
    fromPosition.isBuy = fromIsBuy;
    fromPosition.ticket = 1;
    fromPosition.identifier = 1;
    fromPosition.openTimeMilliseconds = (long)D'2026.01.01 00:00:00' * 1000;
    fromPosition.volume = 0.1;
    fromPosition.openPrice = 1.0950;
    fromPosition.stopLoss = 1.0900;
    if (!fromIsBuy) {
        fromPosition.stopLoss = 1.1100;
    }
}

/**
 * M15専用の識別子と決済分類を確認する。ログ初期化は行わない。
 */
void verifyProfileAndReasons() {
    EaTradeProfile profile;
    M15EaTradePolicy::profile(profile);
    verify(profile.isValid() && profile.timeFrame == PERIOD_M15
        && profile.actionUidPrefix == "M15_EA_ACTION_V1|"
        && profile.entryCommentPrefix == "MstngM15EaV1:"
        && profile.closeCommentPrefix == "MstngM15C:"
        && profile.trailStopLossSource == "M15_ZIGZAG_TRAIL"
        && profile.trailCrossedReason == "M15_ZIGZAG_TRAIL_CROSSED", "M15 profile identity");
    verify(profile.pendingBarField == "pending_stop_loss_bar_time"
        && profile.lastAppliedTrailBarField == "last_applied_trail_bar_time"
        && profile.lastTrailEvaluatedBarField == "last_trail_evaluated_bar_time", "M15 pending schema keys");
    M15EaTradePolicy policy;
    verify(policy.closeReason("INITIAL_STOP_LOSS_CROSSED", "", "") == "INITIAL_STOP_LOSS_CROSSED"
        && policy.closeReason("M15_ZIGZAG_TRAIL_CROSSED", "", "") == "M15_ZIGZAG_TRAIL_CROSSED",
        "crossed intent precedes broker reason");
    verify(policy.closeReason("", "INITIAL_STOP_LOSS", "SL") == "INITIAL_STOP_LOSS"
        && policy.closeReason("", "M15_ZIGZAG_TRAIL", "SL") == "M15_ZIGZAG_TRAIL"
        && policy.closeReason("", "EXTERNAL", "SL") == "EXTERNAL_STOP_LOSS"
        && policy.closeReason("", "H1_ZIGZAG_TRAIL", "SL") == "UNKNOWN_STOP_LOSS",
        "SL source remains M15 scoped");
    verify(policy.closeReason("", "", "CLIENT") == "EXTERNAL_CLOSE"
        && policy.closeReason("", "", "MOBILE") == "EXTERNAL_CLOSE"
        && policy.closeReason("", "", "WEB") == "EXTERNAL_CLOSE"
        && policy.closeReason("", "", "SO") == "UNKNOWN_CLOSE", "external close classification");
}

/**
 * M15のBUY/SELLで10pips余白と共通判定の結果を確認する。
 */
void verifyTrail(const bool fromIsBuy) {
    Wave *wave = createWave(fromIsBuy);
    verify(wave != NULL, "wave fixture allocation");
    if (wave == NULL) {
        return;
    }
    PositionSnapshot position;
    preparePosition(fromIsBuy, position);
    M15EaTradePolicy policy;
    EaTrailDecision result;
    double expectedTarget = 1.0990;
    if (!fromIsBuy) {
        expectedTarget = 1.1010;
    }
    verify(policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && result.shouldModify && MathAbs(result.targetStopLoss - expectedTarget) < 1.0e-9
        && result.pivotRate == 1.1 && result.pivotBarIndex == 2
        && result.pivotIsPeak == !fromIsBuy && result.skipReason == "", "M15 10 pips trail");
    wave.marketContext = MarketContext("EURUSD", PERIOD_H1, "H1", 5);
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && !result.shouldModify && result.targetStopLoss == 0.0
        && result.skipReason == "INVALID_TIMEFRAME", "H1 wave cannot drive M15 trail");
    wave.marketContext = MarketContext("EURUSD", PERIOD_M15, "M15", 5);
    ZigZagPoint *latest = wave.getLatestPoint();
    ZigZagPoint *pivot = wave.getLatestPoint2();
    latest.isAddedPoint = true;
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && result.skipReason == "ADDED_POINT", "unconfirmed latest point rejected");
    latest.isAddedPoint = false;
    pivot.isAddedPoint = true;
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && result.skipReason == "ADDED_POINT", "unconfirmed pivot rejected");
    pivot.isAddedPoint = false;
    latest.barIndex = 0;
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && result.skipReason == "FORMING_BAR", "forming M15 bar rejected");
    latest.barIndex = 1;
    position.openTimeMilliseconds = (long)pivot.barTime * 1000;
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && result.skipReason == "PIVOT_BEFORE_POSITION_OPEN", "pivot must follow entry time");
    preparePosition(fromIsBuy, position);
    position.stopLoss = expectedTarget;
    verify(!policy.evaluateTrail(position, wave, 0.0001, 0.0001, result)
        && !result.shouldModify && result.skipReason == "NOT_IMPROVED", "SL cannot retreat or stay unchanged");
    delete wave;
}

/**
 * チャート・注文・DB・運用ログを変更せず純粋判定を確認する。
 */
void OnStart() {
    verifyProfileAndReasons();
    verifyTrail(true);
    verifyTrail(false);
    Print("INFO M15EaTradePolicySmokeTest failures=", failureCount);
}
