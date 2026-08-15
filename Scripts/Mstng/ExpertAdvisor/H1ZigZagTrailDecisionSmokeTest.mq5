//+------------------------------------------------------------------+
//|                               H1ZigZagTrailDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <MstngEa\Strategy\H1ZigZagTrailDecision.mqh>

/** テスト用の1pip価格幅。 */
const double TEST_PIP_SIZE = 0.0001;

/** テスト用の最小価格刻み。 */
const double TEST_TICK_SIZE = 0.0001;

/** テスト用のトレイル幅。 */
const double TEST_BUFFER_PIPS = 5.0;

/**
 * テスト用ポジションを生成する。
 *
 * @param fromIsBuy BUYの場合true。
 * @param fromStopLoss 現在SL。
 * @return テスト用ポジション。
 */
PositionSnapshot createPosition(
    const bool fromIsBuy,
    const double fromStopLoss
) {
    PositionSnapshot positionSnapshot;
    positionSnapshot.hasPosition = true;
    positionSnapshot.isBuy = fromIsBuy;
    positionSnapshot.ticket = 1;
    positionSnapshot.identifier = 1;
    positionSnapshot.openTimeMilliseconds =
        (long)D'2026.01.01 00:00:00' * 1000;
    positionSnapshot.volume = 0.1;
    positionSnapshot.openPrice = 1.0950;
    positionSnapshot.stopLoss = fromStopLoss;

    return positionSnapshot;
}

/**
 * テスト用ZigZagポイントを生成する。
 *
 * @param fromRate ポイント価格。
 * @param fromBarTime ポイント時刻。
 * @param fromBarIndex バー位置。
 * @param fromIsPeak 山の場合true。
 * @param fromIsAddedPoint 補完ポイントの場合true。
 * @return 生成したポイント。
 */
ZigZagPoint *createPoint(
    const double fromRate,
    const datetime fromBarTime,
    const int fromBarIndex,
    const bool fromIsPeak,
    const bool fromIsAddedPoint
) {
    ZigZagPoint *point = new ZigZagPoint();

    if (point == NULL) {
        return NULL;
    }

    point.marketContext = MarketContext(
        "EURUSD",
        PERIOD_H1,
        "H1",
        5
    );
    point.rate = fromRate;
    point.barTime = fromBarTime;
    point.barIndex = fromBarIndex;
    point.isPeak = fromIsPeak;
    point.isAddedPoint = fromIsAddedPoint;

    return point;
}

/**
 * 1つ前と最新の2ポイントを持つテスト用Waveを生成する。
 *
 * @param fromPivotRate 1つ前のポイント価格。
 * @param fromLatestRate 最新ポイント価格。
 * @param fromPivotTime 1つ前のポイント時刻。
 * @param fromLatestTime 最新ポイント時刻。
 * @param fromPivotBarIndex 1つ前のポイントのバー位置。
 * @param fromLatestBarIndex 最新ポイントのバー位置。
 * @param fromPivotIsPeak 1つ前が山の場合true。
 * @param fromLatestIsPeak 最新が山の場合true。
 * @param fromPivotIsAdded 1つ前が補完点の場合true。
 * @param fromLatestIsAdded 最新が補完点の場合true。
 * @return 生成したWave。
 */
Wave *createWave(
    const double fromPivotRate,
    const double fromLatestRate,
    const datetime fromPivotTime,
    const datetime fromLatestTime,
    const int fromPivotBarIndex,
    const int fromLatestBarIndex,
    const bool fromPivotIsPeak,
    const bool fromLatestIsPeak,
    const bool fromPivotIsAdded,
    const bool fromLatestIsAdded
) {
    Wave *wave = new Wave();

    if (wave == NULL) {
        return NULL;
    }

    wave.marketContext = MarketContext(
        "EURUSD",
        PERIOD_H1,
        "H1",
        5
    );
    ZigZagPoint *pivotPoint = createPoint(
        fromPivotRate,
        fromPivotTime,
        fromPivotBarIndex,
        fromPivotIsPeak,
        fromPivotIsAdded
    );
    ZigZagPoint *latestPoint = createPoint(
        fromLatestRate,
        fromLatestTime,
        fromLatestBarIndex,
        fromLatestIsPeak,
        fromLatestIsAdded
    );

    if (pivotPoint == NULL || latestPoint == NULL) {
        if (pivotPoint != NULL) {
            delete pivotPoint;
        }
        if (latestPoint != NULL) {
            delete latestPoint;
        }

        delete wave;

        return NULL;
    }

    wave.zigZagPointList.Add(pivotPoint);
    wave.zigZagPointList.Add(latestPoint);

    return wave;
}

/**
 * 標準のBUY用Waveを生成する。
 *
 * @return 谷から山へ進むWave。
 */
Wave *createBuyWave() {
    return createWave(
        1.1000,
        1.1100,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        false,
        true,
        false,
        false
    );
}

/**
 * 標準のSELL用Waveを生成する。
 *
 * @return 山から谷へ進むWave。
 */
Wave *createSellWave() {
    return createWave(
        1.1000,
        1.0900,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        true,
        false,
        false,
        false
    );
}

/**
 * 判定結果が期待どおりか確認する。
 *
 * @param fromCaseName ケース名。
 * @param fromActual 実際の変更可否。
 * @param fromResult 判定結果。
 * @param fromExpectedModify 期待する変更可否。
 * @param fromExpectedTarget 期待するSL候補。
 * @param fromExpectedReason 期待する見送り理由。
 * @return 一致する場合true。
 */
bool assertDecision(
    const string fromCaseName,
    const bool fromActual,
    H1ZigZagTrailDecisionResult &fromResult,
    const bool fromExpectedModify,
    const double fromExpectedTarget,
    const string fromExpectedReason
) {
    bool isTargetMatched = MathAbs(
        fromResult.targetStopLoss - fromExpectedTarget
    ) < 0.00000001;
    bool isMatched = fromActual == fromExpectedModify
        && fromResult.shouldModify == fromExpectedModify
        && isTargetMatched
        && fromResult.skipReason == fromExpectedReason;

    if (!isMatched) {
        PrintFormat(
            "FAIL %s actual=%s shouldModify=%s target=%.8f reason=%s",
            fromCaseName,
            (string)fromActual,
            (string)fromResult.shouldModify,
            fromResult.targetStopLoss,
            fromResult.skipReason
        );
    }

    return isMatched;
}

/**
 * 指定Waveを評価し、期待結果と比較する。
 *
 * @param fromCaseName ケース名。
 * @param fromPositionSnapshot ポジション状態。
 * @param fromWave H1 Wave。
 * @param fromExpectedModify 期待する変更可否。
 * @param fromExpectedTarget 期待するSL候補。
 * @param fromExpectedReason 期待する見送り理由。
 * @return 一致する場合true。
 */
bool validateWave(
    const string fromCaseName,
    PositionSnapshot &fromPositionSnapshot,
    Wave *fromWave,
    const bool fromExpectedModify,
    const double fromExpectedTarget,
    const string fromExpectedReason
) {
    if (fromWave == NULL) {
        Print("FAIL allocation " + fromCaseName);

        return false;
    }

    H1ZigZagTrailDecision decision;
    H1ZigZagTrailDecisionResult result;
    bool shouldModify = decision.evaluate(
        fromPositionSnapshot,
        fromWave,
        TEST_BUFFER_PIPS,
        TEST_PIP_SIZE,
        TEST_TICK_SIZE,
        result
    );
    bool isMatched = assertDecision(
        fromCaseName,
        shouldModify,
        result,
        fromExpectedModify,
        fromExpectedTarget,
        fromExpectedReason
    );

    delete fromWave;

    return isMatched;
}

/**
 * BUYとSELLの正常なトレイル更新を確認する。
 *
 * @return すべて一致する場合true。
 */
bool validateAcceptedCases() {
    bool isAllMatched = true;
    PositionSnapshot buyPosition = createPosition(true, 1.0994);

    if (!validateWave(
            "BUY accepted",
            buyPosition,
            createBuyWave(),
            true,
            1.0995,
            ""
    )) {
        isAllMatched = false;
    }

    PositionSnapshot sellPosition = createPosition(false, 1.1006);

    if (!validateWave(
            "SELL accepted",
            sellPosition,
            createSellWave(),
            true,
            1.1005,
            ""
    )) {
        isAllMatched = false;
    }

    return isAllMatched;
}

/**
 * 補完ポイント、形成中足、極性不一致を確認する。
 *
 * @return すべて見送られる場合true。
 */
bool validatePointRejections() {
    bool isAllMatched = true;
    PositionSnapshot buyPosition = createPosition(true, 1.0900);
    Wave *addedWave = createWave(
        1.1000,
        1.1100,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        false,
        true,
        true,
        false
    );

    if (!validateWave(
            "added point",
            buyPosition,
            addedWave,
            false,
            0.0,
            "ADDED_POINT"
    )) {
        isAllMatched = false;
    }

    Wave *formingWave = createWave(
        1.1000,
        1.1100,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        0,
        false,
        true,
        false,
        false
    );

    if (!validateWave(
            "forming bar",
            buyPosition,
            formingWave,
            false,
            0.0,
            "FORMING_BAR"
    )) {
        isAllMatched = false;
    }

    Wave *wrongBuyPolarity = createWave(
        1.1000,
        1.0900,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        true,
        false,
        false,
        false
    );

    if (!validateWave(
            "BUY polarity",
            buyPosition,
            wrongBuyPolarity,
            false,
            0.0,
            "DIRECTION_MISMATCH"
    )) {
        isAllMatched = false;
    }

    PositionSnapshot sellPosition = createPosition(false, 1.1200);
    Wave *wrongSellPolarity = createBuyWave();

    if (!validateWave(
            "SELL polarity",
            sellPosition,
            wrongSellPolarity,
            false,
            0.0,
            "DIRECTION_MISMATCH"
    )) {
        isAllMatched = false;
    }

    return isAllMatched;
}

/**
 * エントリー前ポイントとSL後退を確認する。
 *
 * @return すべて見送られる場合true。
 */
bool validatePositionRejections() {
    bool isAllMatched = true;
    PositionSnapshot buyPosition = createPosition(true, 1.0995);
    Wave *beforeOpenWave = createWave(
        1.1000,
        1.1100,
        D'2025.12.31 23:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        false,
        true,
        false,
        false
    );

    if (!validateWave(
            "pivot before open",
            buyPosition,
            beforeOpenWave,
            false,
            0.0,
            "PIVOT_BEFORE_POSITION_OPEN"
    )) {
        isAllMatched = false;
    }

    if (!validateWave(
            "BUY backward",
            buyPosition,
            createBuyWave(),
            false,
            1.0995,
            "NOT_IMPROVED"
    )) {
        isAllMatched = false;
    }

    PositionSnapshot sellPosition = createPosition(false, 1.1005);

    if (!validateWave(
            "SELL backward",
            sellPosition,
            createSellWave(),
            false,
            1.1005,
            "NOT_IMPROVED"
    )) {
        isAllMatched = false;
    }

    return isAllMatched;
}

/**
 * ポイント不足、時刻逆転および無効ポイントを確認する。
 *
 * @return すべて見送られる場合true。
 */
bool validateInvalidCases() {
    bool isAllMatched = true;
    PositionSnapshot buyPosition = createPosition(true, 1.0900);
    Wave *emptyWave = new Wave();
    emptyWave.marketContext = MarketContext(
        "EURUSD",
        PERIOD_H1,
        "H1",
        5
    );

    if (!validateWave(
            "points unavailable",
            buyPosition,
            emptyWave,
            false,
            0.0,
            "POINTS_UNAVAILABLE"
    )) {
        isAllMatched = false;
    }

    Wave *reversedTimeWave = createWave(
        1.1000,
        1.1100,
        D'2026.01.01 08:00:00',
        D'2026.01.01 04:00:00',
        2,
        1,
        false,
        true,
        false,
        false
    );

    if (!validateWave(
            "point order",
            buyPosition,
            reversedTimeWave,
            false,
            0.0,
            "INVALID_POINT_ORDER"
    )) {
        isAllMatched = false;
    }

    Wave *invalidRateWave = createWave(
        0.0,
        1.1100,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        false,
        true,
        false,
        false
    );

    if (!validateWave(
            "invalid point",
            buyPosition,
            invalidRateWave,
            false,
            0.0,
            "INVALID_POINT"
    )) {
        isAllMatched = false;
    }

    Wave *invalidTargetWave = createWave(
        0.0004,
        0.0010,
        D'2026.01.01 04:00:00',
        D'2026.01.01 08:00:00',
        2,
        1,
        false,
        true,
        false,
        false
    );

    if (!validateWave(
            "invalid target",
            buyPosition,
            invalidTargetWave,
            false,
            -0.0001,
            "INVALID_TARGET"
    )) {
        isAllMatched = false;
    }

    return isAllMatched;
}

/**
 * H1 ZigZagトレイルの正常系と見送り条件を検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!validateAcceptedCases()) {
        failureCount++;
    }
    if (!validatePointRejections()) {
        failureCount++;
    }
    if (!validatePositionRejections()) {
        failureCount++;
    }
    if (!validateInvalidCases()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("H1ZigZagTrailDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1ZigZagTrailDecisionSmokeTest FAIL count=%d",
        failureCount
    );
}
