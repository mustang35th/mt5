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
 * @param fromElliotD1 D1分析結果。省略時は既存4引数APIを検証する。
 * @return 期待値と一致する場合true。
 */
bool assertDecision(
    const string fromCaseName,
    const H1Ema200ConfirmationMode fromMode,
    const bool fromIsBuy,
    Elliot *fromElliotH1,
    Elliot *fromElliotH4,
    const bool fromExpectedResult,
    Elliot *fromElliotD1 = NULL
) {
    H1Ema200ConfirmationDecision decision;
    bool result = false;

    if (fromElliotD1 == NULL) {
        result = decision.evaluate(
            fromMode,
            fromIsBuy,
            fromElliotH1,
            fromElliotH4
        );
    } else {
        result = decision.evaluate(
            fromMode,
            fromIsBuy,
            fromElliotH1,
            fromElliotH4,
            fromElliotD1
        );
    }

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
 * 3足一致モードで、指定した1足の状態だけを変えて判定する。
 *
 * @param fromIsBuy エントリー方向がBUYの場合true。
 * @param fromInvalidIndex 不整合にする足。H1=0、H4=1、D1=2、一致=-1。
 * @param fromInvalidState 不整合状態。一致の場合はMATCH。
 * @return 期待値と一致する場合true。
 */
bool validateThreeTimeFrameCase(
    const bool fromIsBuy,
    const int fromInvalidIndex,
    const string fromInvalidState
) {
    ENUM_TIMEFRAMES timeFrames[] = {PERIOD_H1, PERIOD_H4, PERIOD_D1};
    Elliot *elliots[3];
    string direction = "SELL";

    if (fromIsBuy) {
        direction = "BUY";
    }

    for (int i = 0; i < ArraySize(elliots); i++) {
        elliots[i] = NULL;
    }

    bool isCreated = true;

    for (int i = 0; i < ArraySize(elliots); i++) {
        elliots[i] = createElliot(timeFrames[i], fromIsBuy, direction);

        if (elliots[i] == NULL) {
            isCreated = false;
        }
    }

    if (!isCreated) {
        Print("FAIL three-timeframe fixture allocation");

        for (int i = 0; i < ArraySize(elliots); i++) {
            if (elliots[i] != NULL) {
                delete elliots[i];
            }
        }

        return false;
    }

    string caseName = "THREE " + direction + " MATCH";
    bool expectedResult = true;

    if (fromInvalidIndex >= 0) {
        caseName = "THREE " + direction + " "
            + EnumToString(timeFrames[fromInvalidIndex]) + " " + fromInvalidState;
        expectedResult = false;
        Elliot *invalidElliot = elliots[fromInvalidIndex];

        if (fromInvalidState == "OPPOSITE") {
            invalidElliot.oscillator.ema200.isBuy = !fromIsBuy;
            invalidElliot.oscillator.ema200.isSell = fromIsBuy;
            invalidElliot.oscillator.ema200.buySellLabel = "BUY";

            if (fromIsBuy) {
                invalidElliot.oscillator.ema200.buySellLabel = "SELL";
            }
        } else if (fromInvalidState == "NONE") {
            invalidElliot.oscillator.ema200.isBuy = false;
            invalidElliot.oscillator.ema200.isSell = false;
            invalidElliot.oscillator.ema200.buySellLabel = "NONE";
        } else if (fromInvalidState == "BOTH") {
            invalidElliot.oscillator.ema200.isBuy = true;
            invalidElliot.oscillator.ema200.isSell = true;
        } else if (fromInvalidState == "NULL") {
            delete elliots[fromInvalidIndex];
            elliots[fromInvalidIndex] = NULL;
        } else if (fromInvalidState == "ELLIOT_TIMEFRAME") {
            invalidElliot.marketContext.timeFrame = PERIOD_M15;
        } else if (fromInvalidState == "OSCILLATOR_TIMEFRAME") {
            invalidElliot.oscillator.marketContext.timeFrame = PERIOD_M15;
        } else if (fromInvalidState == "EMA200_TIMEFRAME") {
            invalidElliot.oscillator.ema200.marketContext.timeFrame = PERIOD_M15;
        }
    }

    bool isMatched = assertDecision(
        caseName,
        H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED,
        fromIsBuy,
        elliots[0],
        elliots[1],
        expectedResult,
        elliots[2]
    );

    for (int i = 0; i < ArraySize(elliots); i++) {
        if (elliots[i] != NULL) {
            delete elliots[i];
        }
    }

    return isMatched;
}

/**
 * BUY/SELLの3足一致と、各足の欠損・方向・時間足不整合を検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateThreeTimeFrameCases() {
    bool isAllMatched = true;
    string invalidStates[] = {
        "OPPOSITE", "NONE", "BOTH", "NULL", "ELLIOT_TIMEFRAME",
        "OSCILLATOR_TIMEFRAME", "EMA200_TIMEFRAME"
    };

    for (int i = 0; i < 2; i++) {
        bool isBuy = (i == 0);

        if (!validateThreeTimeFrameCase(isBuy, -1, "MATCH")) {
            isAllMatched = false;
        }

        for (int j = 0; j < 3; j++) {
            for (int k = 0; k < ArraySize(invalidStates); k++) {
                if (!validateThreeTimeFrameCase(isBuy, j, invalidStates[k])) {
                    isAllMatched = false;
                }
            }
        }
    }

    return isAllMatched;
}

/**
 * 旧2モードはD1省略・逆向きでも判定が変わらないことを検証する。
 *
 * @return すべて期待値どおりの場合true。
 */
bool validateLegacyD1IndependenceCases() {
    bool isAllMatched = true;
    H1Ema200ConfirmationMode modes[] = {
        H1_EMA200_CONFIRMATION_H1_ONLY,
        H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
    };

    for (int i = 0; i < 2; i++) {
        bool isBuy = (i == 0);
        string direction = "SELL";
        string oppositeDirection = "BUY";

        if (isBuy) {
            direction = "BUY";
            oppositeDirection = "SELL";
        }

        Elliot *elliotH1 = createElliot(PERIOD_H1, isBuy, direction);
        Elliot *elliotH4 = createElliot(PERIOD_H4, isBuy, direction);
        Elliot *elliotD1 = createElliot(PERIOD_D1, !isBuy, oppositeDirection);

        if (elliotH1 == NULL || elliotH4 == NULL || elliotD1 == NULL) {
            Print("FAIL legacy fixture allocation");
            isAllMatched = false;
        } else {
            for (int j = 0; j < ArraySize(modes); j++) {
                if (!assertDecision(
                        "LEGACY " + direction + " D1 omitted",
                        modes[j], isBuy, elliotH1, elliotH4, true
                    )) {
                    isAllMatched = false;
                }

                if (!assertDecision(
                        "LEGACY " + direction + " D1 opposite",
                        modes[j], isBuy, elliotH1, elliotH4, true, elliotD1
                    )) {
                    isAllMatched = false;
                }
            }
        }

        if (elliotH1 != NULL) {
            delete elliotH1;
        }
        if (elliotH4 != NULL) {
            delete elliotH4;
        }
        if (elliotD1 != NULL) {
            delete elliotD1;
        }
    }

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

    if ((int)H1_EMA200_CONFIRMATION_H1_ONLY != 0
            || (int)H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED != 1
            || (int)H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED != 2
            || getH1Ema200ConfirmationModeText(
                H1_EMA200_CONFIRMATION_H1_ONLY
            ) != "H1_ONLY"
            || getH1Ema200ConfirmationModeText(
                H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
            ) != "H1_AND_H4_REQUIRED"
            || getH1Ema200ConfirmationModeText(
                H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED
            ) != "H1_AND_H4_AND_D1_REQUIRED"
            || getH1Ema200ConfirmationModeText(invalidMode) != "INVALID"
            || !isH1Ema200ConfirmationModeValid(
                H1_EMA200_CONFIRMATION_H1_ONLY
            )
            || !isH1Ema200ConfirmationModeValid(
                H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
            )
            || !isH1Ema200ConfirmationModeValid(
                H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED
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

    Elliot *elliotD1 = createElliot(PERIOD_D1, true, "BUY");
    int invalidModes[] = {-1, 3, 99};

    if (elliotH1 == NULL || elliotH4 == NULL || elliotD1 == NULL) {
        Print("FAIL invalid-mode fixture allocation");
        isAllMatched = false;
    } else {
        for (int i = 0; i < ArraySize(invalidModes); i++) {
            H1Ema200ConfirmationMode rejectedMode =
                (H1Ema200ConfirmationMode)invalidModes[i];

            if (getH1Ema200ConfirmationModeText(rejectedMode) != "INVALID"
                    || isH1Ema200ConfirmationModeValid(rejectedMode)) {
                PrintFormat("FAIL invalid mode value=%d", invalidModes[i]);
                isAllMatched = false;
            }

            if (!assertDecision(
                    "invalid mode with three matching timeframes",
                    rejectedMode, true, elliotH1, elliotH4, false, elliotD1
                )) {
                isAllMatched = false;
            }
        }
    }

    delete elliotH1;
    delete elliotH4;
    if (elliotD1 != NULL) {
        delete elliotD1;
    }

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

    if (!validateThreeTimeFrameCases()) {
        failureCount++;
    }

    if (!validateLegacyD1IndependenceCases()) {
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
