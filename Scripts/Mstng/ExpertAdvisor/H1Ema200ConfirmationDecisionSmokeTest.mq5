//+------------------------------------------------------------------+
//|                  H1Ema200ConfirmationDecisionSmokeTest.mq5       |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationDecision.mqh>

/**
 * テスト用Elliott分析結果へElliott方向とEMA200方向を設定する。
 *
 * @param fromTimeFrame 対象時間足。
 * @param fromIsElliotBuy Elliott方向がBUYの場合true。
 * @param fromEma200Direction EMA200方向。BUY、SELLまたはNONE。
 * @return 呼び出し側が所有するテスト用Elliott分析結果。
 */
Elliot *createElliot(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const bool fromIsElliotBuy,
    const string fromEma200Direction
) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    elliot.isBuy = fromIsElliotBuy;
    elliot.oscillator.isBuy = fromIsElliotBuy;

    if (fromIsElliotBuy) {
        elliot.buySellLabel = "BUY";
    } else {
        elliot.buySellLabel = "SELL";
    }

    elliot.oscillator.ema200.isBuy = false;
    elliot.oscillator.ema200.isSell = false;
    elliot.oscillator.ema200.buySellLabel = fromEma200Direction;

    if (fromEma200Direction == "BUY") {
        elliot.oscillator.ema200.isBuy = true;
    }

    if (fromEma200Direction == "SELL") {
        elliot.oscillator.ema200.isSell = true;
    }

    return elliot;
}

/**
 * 1つのEMA200確認結果を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromMode 確認モード。
 * @param fromIsBuy エントリーがBUY方向の場合true。
 * @param fromElliotH1 H1分析結果。
 * @param fromElliotH4 H4分析結果。
 * @param fromExpectedResult 期待する判定結果。
 * @return 期待値と一致する場合true。
 */
bool assertDecision(
    const string fromCaseName,
    const H1Ema200ConfirmationMode fromMode,
    const bool fromIsBuy,
    Elliot *fromElliotH1,
    Elliot *fromElliotH4,
    const bool fromExpectedResult
) {
    H1Ema200ConfirmationDecision decision;
    bool result = decision.evaluate(
        fromMode,
        fromIsBuy,
        fromElliotH1,
        fromElliotH4
    );

    if (result != fromExpectedResult) {
        string entryDirection = "SELL";

        if (fromIsBuy) {
            entryDirection = "BUY";
        }

        PrintFormat(
            "FAIL %s mode=%s entry=%s actual=%s expected=%s",
            fromCaseName,
            getH1Ema200ConfirmationModeText(fromMode),
            entryDirection,
            (string)result,
            (string)fromExpectedResult
        );

        return false;
    }

    return true;
}

/**
 * H1_ONLYモードのH1一致、不一致およびNONEを検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateH1OnlyCases() {
    bool isAllMatched = true;
    Elliot *elliotH1 = createElliot(PERIOD_H1, true, "BUY");
    Elliot *elliotH4 = createElliot(PERIOD_H4, false, "SELL");

    if (!assertDecision(
            "H1_ONLY BUY ignores opposite H4",
            H1_EMA200_CONFIRMATION_H1_ONLY,
            true,
            elliotH1,
            elliotH4,
            true
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    elliotH1 = createElliot(PERIOD_H1, false, "SELL");

    if (!assertDecision(
            "H1_ONLY H1 mismatch",
            H1_EMA200_CONFIRMATION_H1_ONLY,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    elliotH1 = createElliot(PERIOD_H1, true, "NONE");

    if (!assertDecision(
            "H1_ONLY H1 NONE",
            H1_EMA200_CONFIRMATION_H1_ONLY,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;

    return isAllMatched;
}

/**
 * H1_AND_H4_REQUIREDモードのBUY/SELL一致を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateStrictMatchedCases() {
    bool isAllMatched = true;
    Elliot *elliotH1 = createElliot(PERIOD_H1, true, "BUY");
    Elliot *elliotH4 = createElliot(PERIOD_H4, true, "BUY");

    if (!assertDecision(
            "STRICT BUY",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            elliotH4,
            true
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;
    elliotH1 = createElliot(PERIOD_H1, false, "SELL");
    elliotH4 = createElliot(PERIOD_H4, false, "SELL");

    if (!assertDecision(
            "STRICT SELL",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            false,
            elliotH1,
            elliotH4,
            true
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;

    return isAllMatched;
}

/**
 * H1_AND_H4_REQUIREDモードのfail-closed動作を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateStrictRejectedCases() {
    bool isAllMatched = true;
    Elliot *elliotH1 = createElliot(PERIOD_H1, true, "BUY");
    Elliot *elliotH4 = createElliot(PERIOD_H4, false, "SELL");

    if (!assertDecision(
            "STRICT H4 opposite",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH4;
    elliotH4 = createElliot(PERIOD_H4, true, "NONE");

    if (!assertDecision(
            "STRICT H4 NONE",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH4;

    if (!assertDecision(
            "STRICT H4 NULL",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            NULL,
            false
        )) {
        isAllMatched = false;
    }

    elliotH4 = createElliot(PERIOD_D1, true, "BUY");

    if (!assertDecision(
            "STRICT invalid H4 timeframe",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;
    elliotH1 = createElliot(PERIOD_H4, true, "BUY");
    elliotH4 = createElliot(PERIOD_H4, true, "BUY");

    if (!assertDecision(
            "STRICT invalid H1 timeframe",
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;

    return isAllMatched;
}

/**
 * 不正モードとenumの文字列・妥当性判定を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateModeCases() {
    bool isAllMatched = true;
    H1Ema200ConfirmationMode invalidMode = (H1Ema200ConfirmationMode)99;

    if (getH1Ema200ConfirmationModeText(
            H1_EMA200_CONFIRMATION_H1_ONLY
        ) != "H1_ONLY"
            || getH1Ema200ConfirmationModeText(
                H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
            ) != "H1_AND_H4_REQUIRED"
            || getH1Ema200ConfirmationModeText(invalidMode) != "INVALID"
            || !isH1Ema200ConfirmationModeValid(
                H1_EMA200_CONFIRMATION_H1_ONLY
            )
            || !isH1Ema200ConfirmationModeValid(
                H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
            )
            || isH1Ema200ConfirmationModeValid(invalidMode)) {
        Print("FAIL mode text or validation");
        isAllMatched = false;
    }

    Elliot *elliotH1 = createElliot(PERIOD_H1, true, "BUY");
    Elliot *elliotH4 = createElliot(PERIOD_H4, true, "BUY");

    if (!assertDecision(
            "invalid mode",
            invalidMode,
            true,
            elliotH1,
            elliotH4,
            false
        )) {
        isAllMatched = false;
    }

    delete elliotH1;
    delete elliotH4;

    return isAllMatched;
}

/**
 * H1 EMA200確認モードの全主要分岐を検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!validateH1OnlyCases()) {
        failureCount++;
    }

    if (!validateStrictMatchedCases()) {
        failureCount++;
    }

    if (!validateStrictRejectedCases()) {
        failureCount++;
    }

    if (!validateModeCases()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("H1Ema200ConfirmationDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1Ema200ConfirmationDecisionSmokeTest FAIL count=%d",
        failureCount
    );
}
