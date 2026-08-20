//+------------------------------------------------------------------+
//|                        H1DirectionAlignmentDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>

/**
 * Elliott分析オブジェクトへ売買方向を設定する。
 *
 * @param fromElliot 設定対象。
 * @param fromIsBuy BUY方向の場合true。
 */
void setDirection(Elliot *fromElliot, const bool fromIsBuy) {
    fromElliot.isBuy = fromIsBuy;
    fromElliot.oscillator.isBuy = fromIsBuy;

    if (fromIsBuy) {
        fromElliot.buySellLabel = "BUY";
    } else {
        fromElliot.buySellLabel = "SELL";
    }
}

/**
 * テスト用ElliotへEMA200方向を設定する。
 *
 * @param fromElliot 設定対象。
 * @param fromIsBuy BUYフラグ。
 * @param fromIsSell SELLフラグ。
 * @param fromLabel BUY、SELLまたはNONE。
 */
void setEma200Direction(
    Elliot *fromElliot,
    const bool fromIsBuy,
    const bool fromIsSell,
    const string fromLabel
) {
    fromElliot.oscillator.ema200.isBuy = fromIsBuy;
    fromElliot.oscillator.ema200.isSell = fromIsSell;
    fromElliot.oscillator.ema200.buySellLabel = fromLabel;
}

/**
 * MN1からH1までの方向を持つテスト用分析結果を生成する。
 *
 * @param fromIsMn1Buy MN1がBUY方向の場合true。
 * @param fromIsW1Buy W1がBUY方向の場合true。
 * @param fromIsD1Buy D1がBUY方向の場合true。
 * @param fromIsH4Buy H4がBUY方向の場合true。
 * @param fromIsH1Buy H1がBUY方向の場合true。
 * @param fromIncludeMn1 MN1を含める場合true。
 * @return 呼び出し側が所有するテスト用分析結果。
 */
ElliotAll *createElliotAll(
    const bool fromIsMn1Buy,
    const bool fromIsW1Buy,
    const bool fromIsD1Buy,
    const bool fromIsH4Buy,
    const bool fromIsH1Buy,
    const bool fromIncludeMn1 = true
) {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_H1);
    Elliot *elliotMn1 = new Elliot("EURUSD", PERIOD_MN1);
    Elliot *elliotW1 = new Elliot("EURUSD", PERIOD_W1);
    Elliot *elliotD1 = new Elliot("EURUSD", PERIOD_D1);
    Elliot *elliotH4 = new Elliot("EURUSD", PERIOD_H4);
    Elliot *elliotH1 = new Elliot("EURUSD", PERIOD_H1);

    if (elliotAll == NULL
            || elliotMn1 == NULL
            || elliotW1 == NULL
            || elliotD1 == NULL
            || elliotH4 == NULL
            || elliotH1 == NULL) {
        Print("FAIL allocation");

        return elliotAll;
    }

    setDirection(elliotMn1, fromIsMn1Buy);
    setDirection(elliotW1, fromIsW1Buy);
    setDirection(elliotD1, fromIsD1Buy);
    setDirection(elliotH4, fromIsH4Buy);
    setDirection(elliotH1, fromIsH1Buy);

    if (fromIncludeMn1) {
        elliotAll.elliotList.Add(elliotMn1);
    } else {
        delete elliotMn1;
    }

    elliotAll.elliotList.Add(elliotW1);
    elliotAll.elliotList.Add(elliotD1);
    elliotAll.elliotList.Add(elliotH4);
    elliotAll.elliotList.Add(elliotH1);
    elliotAll.elliotCurrent = elliotH1;
    elliotAll.isAnalysisSucceeded = true;

    return elliotAll;
}

/**
 * 診断結果を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromResult 判定結果。
 * @param fromExpectedMode 期待モード。
 * @param fromExpectedState 期待状態。
 * @param fromExpectedDirection 期待方向。
 * @param fromExpectedMn1Matched MN1一致の期待値。
 * @param fromExpectedW1Matched W1一致の期待値。
 * @param fromExpectedPassed 一致判定の期待値。
 * @return すべて一致する場合true。
 */
bool assertResult(
    const string fromCaseName,
    H1DirectionAlignmentResult &fromResult,
    const string fromExpectedMode,
    const string fromExpectedState,
    const string fromExpectedDirection,
    const bool fromExpectedMn1Matched,
    const bool fromExpectedW1Matched,
    const bool fromExpectedPassed
) {
    bool isMatched = fromResult.mode == fromExpectedMode
        && fromResult.state == fromExpectedState
        && fromResult.isAvailable
        && fromResult.isValid
        && fromResult.direction == fromExpectedDirection
        && fromResult.isMn1DirectionMatched == fromExpectedMn1Matched
        && fromResult.isW1DirectionMatched == fromExpectedW1Matched
        && fromResult.isPassed == fromExpectedPassed;

    if (!isMatched) {
        PrintFormat(
            "FAIL %s mode=%s state=%s available=%s valid=%s "
            + "direction=%s mn1Matched=%s w1Matched=%s passed=%s",
            fromCaseName,
            fromResult.mode,
            fromResult.state,
            (string)fromResult.isAvailable,
            (string)fromResult.isValid,
            fromResult.direction,
            (string)fromResult.isMn1DirectionMatched,
            (string)fromResult.isW1DirectionMatched,
            (string)fromResult.isPassed
        );
    }

    return isMatched;
}

/**
 * 全一致と方向不一致の各状態を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateDirectionalCases() {
    H1DirectionAlignmentDecision decision;
    H1DirectionAlignmentResult result;
    bool isAllMatched = true;
    ElliotAll *elliotAll = createElliotAll(
        true, true, true, true, true
    );
    bool isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "FULL BUY OBSERVE",
                result,
                "MN1_TO_H1_OBSERVE",
                "FULL_BUY",
                "BUY",
                true,
                true,
                true
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(false, false, false, false, false);
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "FULL SELL REQUIRED",
                result,
                "MN1_TO_H1_REQUIRED",
                "FULL_SELL",
                "SELL",
                true,
                true,
                true
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(false, true, true, true, true);
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "MN1 MISMATCH OBSERVE",
                result,
                "MN1_TO_H1_OBSERVE",
                "MN1_MISMATCH",
                "BUY",
                false,
                true,
                false
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, false, true, true, true);
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || !assertResult(
                "W1 MISMATCH REQUIRED",
                result,
                "MN1_TO_H1_REQUIRED",
                "W1_MISMATCH",
                "BUY",
                true,
                false,
                false
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(false, false, true, true, true);
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || !assertResult(
                "MN1 W1 MISMATCH REQUIRED",
                result,
                "MN1_TO_H1_REQUIRED",
                "MN1_W1_MISMATCH",
                "BUY",
                false,
                false,
                false
            )) {
        isAllMatched = false;
    }

    delete elliotAll;

    return isAllMatched;
}

/**
 * MN1またはW1 EMA200を使用する必須モードを検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateMn1OrEma200Cases() {
    H1DirectionAlignmentDecision decision;
    H1DirectionAlignmentResult result;
    bool isAllMatched = true;
    ElliotAll *elliotAll = createElliotAll(
        true, true, true, true, true
    );
    bool isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "MN1 BUY MATCH",
                result,
                "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
                "FULL_BUY",
                "BUY",
                true,
                true,
                true
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(false, true, true, true, true);
    Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, true, false, "BUY");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "EMA200 FALLBACK BUY",
                result,
                "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
                "EMA200_FALLBACK_BUY",
                "BUY",
                false,
                true,
                true
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, false, false, false, false);
    elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, false, true, "SELL");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (!isGatePassed
            || !assertResult(
                "EMA200 FALLBACK SELL",
                result,
                "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
                "EMA200_FALLBACK_SELL",
                "SELL",
                false,
                true,
                true
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(false, true, true, true, true);
    elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, false, true, "SELL");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || !assertResult(
                "MN1 EMA200 MISMATCH",
                result,
                "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
                "MN1_EMA200_MISMATCH",
                "BUY",
                false,
                true,
                false
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, false, true, true, true);
    elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, true, false, "BUY");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || !assertResult(
                "W1 REQUIRED",
                result,
                "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
                "W1_MISMATCH",
                "BUY",
                true,
                false,
                false
            )) {
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, true, true, true, true);
    elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, true, true, "BUY");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.state != "INVALID"
            || !result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL EMA200 conflict");
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, true, true, true, true);
    elliotW1 = elliotAll.getElliot(PERIOD_W1);
    setEma200Direction(elliotW1, true, false, "SELL");
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.state != "INVALID"
            || !result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL EMA200 inconsistent label");
        isAllMatched = false;
    }

    delete elliotAll;

    return isAllMatched;
}

/**
 * 既定、取得不能および不正値の動作を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateEdgeCases() {
    H1DirectionAlignmentDecision decision;
    H1DirectionAlignmentResult result;
    bool isAllMatched = true;
    result.reset();

    if (result.state != "NOT_APPLICABLE" || !result.isPassed) {
        Print("FAIL NOT_APPLICABLE reset");
        isAllMatched = false;
    }

    ElliotAll *legacyElliotAll = createElliotAll(
        true, true, true, true, true
    );
    bool isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_D1_TO_H1,
        legacyElliotAll,
        result
    );

    if (!isGatePassed
            || result.mode != "D1_TO_H1"
            || result.state != "D1_TO_H1"
            || !result.isAvailable
            || !result.isValid
            || result.direction != "BUY"
            || !result.isPassed) {
        Print("FAIL D1_TO_H1 compatibility");
        isAllMatched = false;
    }

    delete legacyElliotAll;
    ElliotAll *elliotAll = createElliotAll(
        true, true, true, true, true, false
    );
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE,
        elliotAll,
        result
    );

    if (!isGatePassed
            || result.state != "UNAVAILABLE"
            || result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL unavailable observe");
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.state != "UNAVAILABLE"
            || result.isPassed) {
        Print("FAIL unavailable required");
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, true, false, true, true);
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.state != "INVALID"
            || !result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL D1 H4 legacy precondition");
        isAllMatched = false;
    }

    delete elliotAll;
    elliotAll = createElliotAll(true, true, true, true, true);
    Elliot *elliotMn1 = elliotAll.getElliot(PERIOD_MN1);
    elliotMn1.oscillator.isBuy = false;
    isGatePassed = decision.evaluate(
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.state != "INVALID"
            || !result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL invalid direction state");
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        (H1DirectionAlignmentMode)99,
        elliotAll,
        result
    );

    if (isGatePassed
            || result.mode != "INVALID"
            || result.state != "INVALID"
            || result.isPassed) {
        Print("FAIL invalid mode");
        isAllMatched = false;
    }

    delete elliotAll;

    return isAllMatched;
}

/**
 * BUY/SELL対称の一致状態とfail-close動作を検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!validateDirectionalCases()) {
        failureCount++;
    }

    if (!validateMn1OrEma200Cases()) {
        failureCount++;
    }

    if (!validateEdgeCases()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("H1DirectionAlignmentDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1DirectionAlignmentDecisionSmokeTest FAIL count=%d",
        failureCount
    );
}
