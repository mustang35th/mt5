//+------------------------------------------------------------------+
//|                            H1W1ConfirmationDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationDecision.mqh>

/**
 * W1分析オブジェクトへ方向とEMA200方向を設定する。
 *
 * @param fromElliotW1 設定対象。
 * @param fromIsW1Buy W1方向がBUYの場合true。
 * @param fromEma200Direction BUY、SELLまたはNONE。
 */
void setW1State(
    Elliot *fromElliotW1,
    const bool fromIsW1Buy,
    const string fromEma200Direction
) {
    fromElliotW1.isBuy = fromIsW1Buy;
    fromElliotW1.oscillator.isBuy = fromIsW1Buy;

    if (fromIsW1Buy) {
        fromElliotW1.buySellLabel = "BUY";
    } else {
        fromElliotW1.buySellLabel = "SELL";
    }

    fromElliotW1.oscillator.ema200.isBuy = false;
    fromElliotW1.oscillator.ema200.isSell = false;
    fromElliotW1.oscillator.ema200.buySellLabel = fromEma200Direction;

    if (fromEma200Direction == "BUY") {
        fromElliotW1.oscillator.ema200.isBuy = true;
    }

    if (fromEma200Direction == "SELL") {
        fromElliotW1.oscillator.ema200.isSell = true;
    }
}

/**
 * 診断結果を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromResult 判定結果。
 * @param fromExpectedMode 期待モード。
 * @param fromExpectedState 期待状態。
 * @param fromExpectedDirectionMatched W1方向一致の期待値。
 * @param fromExpectedEma200Matched W1 EMA200方向一致の期待値。
 * @param fromExpectedPassed モード判定通過の期待値。
 * @return すべて一致する場合true。
 */
bool assertResult(
    const string fromCaseName,
    H1W1ConfirmationResult &fromResult,
    const string fromExpectedMode,
    const string fromExpectedState,
    const bool fromExpectedDirectionMatched,
    const bool fromExpectedEma200Matched,
    const bool fromExpectedPassed
) {
    bool isMatched = fromResult.mode == fromExpectedMode
        && fromResult.state == fromExpectedState
        && fromResult.isAvailable
        && fromResult.isValid
        && fromResult.isDirectionMatched
            == fromExpectedDirectionMatched
        && fromResult.isEma200Matched == fromExpectedEma200Matched
        && fromResult.isPassed == fromExpectedPassed;

    if (!isMatched) {
        PrintFormat(
            "FAIL %s mode=%s state=%s available=%s valid=%s "
            + "directionMatched=%s emaMatched=%s passed=%s",
            fromCaseName,
            fromResult.mode,
            fromResult.state,
            (string)fromResult.isAvailable,
            (string)fromResult.isValid,
            (string)fromResult.isDirectionMatched,
            (string)fromResult.isEma200Matched,
            (string)fromResult.isPassed
        );
    }

    return isMatched;
}

/**
 * 1つの方向組み合わせをOBSERVE、OR、ANDで検証する。
 *
 * @param fromCaseName ケース名。
 * @param fromIsEntryBuy エントリー方向がBUYの場合true。
 * @param fromIsW1Buy W1方向がBUYの場合true。
 * @param fromEma200Direction W1 EMA200方向。
 * @param fromExpectedState 期待状態。
 * @param fromExpectedDirectionMatched W1方向一致の期待値。
 * @param fromExpectedEma200Matched W1 EMA200方向一致の期待値。
 * @return 3モードすべてが期待値どおりの場合true。
 */
bool validateDirectionalCase(
    const string fromCaseName,
    const bool fromIsEntryBuy,
    const bool fromIsW1Buy,
    const string fromEma200Direction,
    const string fromExpectedState,
    const bool fromExpectedDirectionMatched,
    const bool fromExpectedEma200Matched
) {
    Elliot *elliotW1 = new Elliot("EURUSD", PERIOD_W1);

    if (elliotW1 == NULL) {
        Print("FAIL allocation " + fromCaseName);

        return false;
    }

    setW1State(elliotW1, fromIsW1Buy, fromEma200Direction);
    H1W1ConfirmationDecision decision;
    H1W1ConfirmationResult result;
    bool isOrPassed = fromExpectedDirectionMatched
        || fromExpectedEma200Matched;
    bool isAndPassed = fromExpectedDirectionMatched
        && fromExpectedEma200Matched;
    bool isAllMatched = true;
    bool isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_OBSERVE_ONLY,
        fromIsEntryBuy,
        elliotW1,
        result
    );

    if (!isGatePassed
            || !assertResult(
                fromCaseName + " OBSERVE",
                result,
                "OBSERVE_ONLY",
                fromExpectedState,
                fromExpectedDirectionMatched,
                fromExpectedEma200Matched,
                isOrPassed
            )) {
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_DIRECTION_OR_EMA200,
        fromIsEntryBuy,
        elliotW1,
        result
    );

    if (isGatePassed != isOrPassed
            || !assertResult(
                fromCaseName + " OR",
                result,
                "DIRECTION_OR_EMA200",
                fromExpectedState,
                fromExpectedDirectionMatched,
                fromExpectedEma200Matched,
                isOrPassed
            )) {
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_DIRECTION_AND_EMA200,
        fromIsEntryBuy,
        elliotW1,
        result
    );

    if (isGatePassed != isAndPassed
            || !assertResult(
                fromCaseName + " AND",
                result,
                "DIRECTION_AND_EMA200",
                fromExpectedState,
                fromExpectedDirectionMatched,
                fromExpectedEma200Matched,
                isAndPassed
            )) {
        isAllMatched = false;
    }

    delete elliotW1;

    return isAllMatched;
}

/**
 * OFF、取得不能、不正値のfail-closed動作を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateEdgeCases() {
    H1W1ConfirmationDecision decision;
    H1W1ConfirmationResult result;
    bool isAllMatched = true;
    bool isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_OFF,
        true,
        NULL,
        result
    );

    if (!isGatePassed
            || result.mode != "OFF"
            || result.state != "OFF"
            || !result.isPassed) {
        Print("FAIL OFF");
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_OBSERVE_ONLY,
        true,
        NULL,
        result
    );

    if (!isGatePassed
            || result.state != "UNAVAILABLE"
            || result.isPassed
            || result.isAvailable
            || result.isValid) {
        Print("FAIL unavailable observe");
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_DIRECTION_OR_EMA200,
        true,
        NULL,
        result
    );

    if (isGatePassed || result.state != "UNAVAILABLE") {
        Print("FAIL unavailable enforced");
        isAllMatched = false;
    }

    Elliot *elliotD1 = new Elliot("EURUSD", PERIOD_D1);
    setW1State(elliotD1, true, "BUY");
    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_OBSERVE_ONLY,
        true,
        elliotD1,
        result
    );

    if (!isGatePassed
            || result.state != "INVALID"
            || !result.isAvailable
            || result.isValid
            || result.isPassed) {
        Print("FAIL invalid timeframe");
        isAllMatched = false;
    }

    delete elliotD1;
    Elliot *elliotW1 = new Elliot("EURUSD", PERIOD_W1);
    setW1State(elliotW1, true, "BUY");
    elliotW1.oscillator.ema200.isSell = true;
    isGatePassed = decision.evaluate(
        H1_W1_CONFIRMATION_DIRECTION_OR_EMA200,
        true,
        elliotW1,
        result
    );

    if (isGatePassed
            || result.state != "INVALID"
            || result.isValid
            || result.isPassed) {
        Print("FAIL invalid EMA flags");
        isAllMatched = false;
    }

    isGatePassed = decision.evaluate(
        (H1W1ConfirmationMode)99,
        true,
        elliotW1,
        result
    );

    if (isGatePassed
            || result.mode != "OFF"
            || result.state != "INVALID"
            || result.isPassed) {
        Print("FAIL invalid mode normalization");
        isAllMatched = false;
    }

    delete elliotW1;

    return isAllMatched;
}

/**
 * W1確認専用Elliotが親子解析一覧から分離されることを検証する。
 *
 * @return 専用参照だけへ設定され、通常一覧にW1が存在しない場合true。
 */
bool validateDetachedSnapshot() {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_H1);
    Elliot *elliotW1 = new Elliot("EURUSD", PERIOD_W1);

    if (elliotAll == NULL || elliotW1 == NULL) {
        if (elliotW1 != NULL) {
            delete elliotW1;
        }
        if (elliotAll != NULL) {
            delete elliotAll;
        }

        Print("FAIL detached snapshot allocation");

        return false;
    }

    elliotAll.setH1W1ConfirmationElliot(elliotW1);
    bool isMatched = elliotAll.getH1W1ConfirmationElliot() == elliotW1
        && elliotAll.getElliot(PERIOD_W1) == NULL
        && elliotAll.elliotList.Total() == 0;

    if (!isMatched) {
        Print("FAIL detached snapshot isolation");
    }

    delete elliotAll;

    return isMatched;
}

/**
 * BUY/SELL対称の6状態と全モードを検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!validateDirectionalCase(
            "BUY STRONG", true, true, "BUY", "STRONG", true, true
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "BUY DIRECTION_ONLY",
            true, true, "NONE", "DIRECTION_ONLY", true, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "BUY EMA_CONFLICT",
            true, true, "SELL", "EMA_CONFLICT", true, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "BUY EMA_ONLY", true, false, "BUY", "EMA_ONLY", false, true
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "BUY REJECT_NONE",
            true, false, "NONE", "REJECT_NONE", false, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "BUY REJECT", true, false, "SELL", "REJECT", false, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL STRONG", false, false, "SELL", "STRONG", true, true
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL DIRECTION_ONLY",
            false, false, "NONE", "DIRECTION_ONLY", true, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL EMA_CONFLICT",
            false, false, "BUY", "EMA_CONFLICT", true, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL EMA_ONLY", false, true, "SELL", "EMA_ONLY", false, true
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL REJECT_NONE",
            false, true, "NONE", "REJECT_NONE", false, false
    )) {
        failureCount++;
    }
    if (!validateDirectionalCase(
            "SELL REJECT", false, true, "BUY", "REJECT", false, false
    )) {
        failureCount++;
    }
    if (!validateEdgeCases()) {
        failureCount++;
    }
    if (!validateDetachedSnapshot()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("H1W1ConfirmationDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1W1ConfirmationDecisionSmokeTest FAIL count=%d",
        failureCount
    );
}
