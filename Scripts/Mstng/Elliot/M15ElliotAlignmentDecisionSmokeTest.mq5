//+------------------------------------------------------------------+
//|                         M15ElliotAlignmentDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>
#include <Mstng\Elliot\M15ElliotEmaSortDecision.mqh>

/** 失敗した検証件数。 */
int failureCount = 0;

/** 実行した検証件数。 */
int assertionCount = 0;

/**
 * 検証結果を集計する。
 */
void assertCondition(const bool fromSuccess, const string fromCaseName) {
    assertionCount++;
    if (!fromSuccess) {
        failureCount++;
        Print("FAIL ", fromCaseName);
    }
}

/**
 * 計算済みのEMA200状態を設定する。0=NONE、1=BUY、-1=SELL。
 */
void setEma(Elliot *fromElliot, const int fromDirection) {
    Ema200 *ema200 = GetPointer(fromElliot.oscillator.ema200);
    ema200.setMarketContext(fromElliot.marketContext);
    ema200.close1 = 1.10;
    ema200.ema200Shift1 = 1.10;
    ema200.ema200Compare = 1.10;
    ema200.slopePips = 0.0;
    ema200.closeEma200DiffPips = 0.0;
    ema200.closePosition = EMA200_POSITION_EQUAL;
    ema200.slopeDirection = EMA200_SLOPE_NONE;
    ema200.upCount = 0;
    ema200.downCount = 0;
    ema200.trendCount = 0;
    ema200.isBuy = fromDirection == 1;
    ema200.isSell = fromDirection == -1;
    ema200.buySellLabel = "NONE";
    if (fromDirection == 1) {
        ema200.close1 = 1.11;
        ema200.ema200Compare = 1.09;
        ema200.slopePips = 100.0;
        ema200.closeEma200DiffPips = 100.0;
        ema200.closePosition = EMA200_POSITION_ABOVE;
        ema200.slopeDirection = EMA200_SLOPE_UP;
        ema200.upCount = 4;
        ema200.trendCount = 4;
        ema200.buySellLabel = "BUY";
    } else if (fromDirection == -1) {
        ema200.close1 = 1.09;
        ema200.ema200Compare = 1.11;
        ema200.slopePips = -100.0;
        ema200.closeEma200DiffPips = -100.0;
        ema200.closePosition = EMA200_POSITION_BELOW;
        ema200.slopeDirection = EMA200_SLOPE_DOWN;
        ema200.downCount = 4;
        ema200.trendCount = -4;
        ema200.buySellLabel = "SELL";
    }
}

/**
 * 最新波動とポイントを持つ最小の分析結果を生成する。
 */
Elliot *createReadyElliot(const ENUM_TIMEFRAMES fromTimeFrame) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);
    if (elliot == NULL) {
        return NULL;
    }

    elliot.isBuy = true;
    CArrayObj pointList;
    ZigZagPoint *point = new ZigZagPoint(elliot.marketContext);
    if (point == NULL) {
        delete elliot;

        return NULL;
    }

    point.elliotIndex = 1;
    point.isElliotAlphabet = false;
    point.setElliotLabel();
    if (!pointList.Add(point)) {
        delete point;
        delete elliot;

        return NULL;
    }

    Wave *wave = new Wave(elliot.marketContext, pointList, true, true);
    if (wave == NULL || !elliot.waveList.Add(wave)) {
        if (wave != NULL) {
            delete wave;
        }

        delete elliot;

        return NULL;
    }

    setEma(elliot, 1);

    return elliot;
}

/**
 * MN1～M15の分析結果を生成する。
 */
ElliotAll *createFixture() {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_M15);
    if (elliotAll == NULL) {
        return NULL;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = createReadyElliot(timeFrames[i]);
        if (elliot == NULL || !elliotAll.elliotList.Add(elliot)) {
            if (elliot != NULL) {
                delete elliot;
            }

            delete elliotAll;

            return NULL;
        }
    }

    elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_M15);
    elliotAll.isAnalysisSucceeded = true;

    return elliotAll;
}

/**
 * 全一致とM15逆＋EMA200 NONEの基本分類を確認する。
 */
void validateBasicGroups() {
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    M15ElliotAlignmentDecision decision;
    M15ElliotAlignmentResult result;
    decision.evaluate(elliotAll, result);
    assertCondition(result.isEvaluated && result.alignType == trendAlignBuy
        && result.group == m15ElliotAlignmentAll, "all BUY");

    elliotAll.getElliot(PERIOD_M15).isBuy = false;
    setEma(elliotAll.getElliot(PERIOD_H1), 0);
    decision.evaluate(elliotAll, result);
    assertCondition(result.isEvaluated && result.alignType == trendAlignBuy
        && result.group == m15ElliotAlignmentBoth
        && result.analysisOppositeTimeFrame == PERIOD_M15
        && result.emaMismatchTimeFrame == PERIOD_H1 && result.isEmaNone,
        "M15 reverse and H1 NONE");
    assertCondition(!elliotAll.getElliot(PERIOD_M15).isBuy,
        "original M15 analysis direction preserved");

    delete elliotAll;
}

/**
 * 分析方向64通りとEMA200の3状態5足、243通りを組み合わせて検証する。
 * 期待値は全一致から1足だけ差し替えた許可パターンの一覧で生成する。
 */
void validateAllCombinations() {
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "combinations fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    int placeValues[] = { 1, 3, 9, 27, 81 };
    M15ElliotAlignmentDecision decision;
    ElliotDirectionAlignmentDecision shared(PERIOD_MN1,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_MN1_WITH_EMA200);
    M15ElliotAlignmentResult result;
    for (int i = 0; i < 64; i++) {
        TrendAlignType expectedDirection = trendAlignNone;
        ENUM_TIMEFRAMES expectedAnalysisTimeFrame = PERIOD_CURRENT;
        if (i == 0) {
            expectedDirection = trendAlignSell;
        } else if (i == 63) {
            expectedDirection = trendAlignBuy;
        }

        for (int k = 0; k < ArraySize(timeFrames); k++) {
            elliotAll.getElliot(timeFrames[k]).isBuy = (i & (1 << k)) != 0;
            if (i == (1 << k)) {
                expectedDirection = trendAlignSell;
                expectedAnalysisTimeFrame = timeFrames[k];
            } else if (i == 63 - (1 << k)) {
                expectedDirection = trendAlignBuy;
                expectedAnalysisTimeFrame = timeFrames[k];
            }
        }

        int matchingEmaCode = 242;
        int matchingEmaDigit = 2;
        if (expectedDirection == trendAlignBuy) {
            matchingEmaCode = 121;
            matchingEmaDigit = 1;
        }

        for (int j = 0; j < 243; j++) {
            bool isEmaAllowed = j == matchingEmaCode;
            ENUM_TIMEFRAMES expectedEmaTimeFrame = PERIOD_CURRENT;
            bool expectedEmaNone = false;
            for (int k = 0; k < ArraySize(placeValues); k++) {
                int emaDigit = (j / placeValues[k]) % 3;
                int emaDirection = 0;
                if (emaDigit == 1) {
                    emaDirection = 1;
                } else if (emaDigit == 2) {
                    emaDirection = -1;
                }

                setEma(elliotAll.getElliot(timeFrames[k + 1]), emaDirection);
                if (j == matchingEmaCode - matchingEmaDigit * placeValues[k]) {
                    isEmaAllowed = true;
                    expectedEmaTimeFrame = timeFrames[k + 1];
                    expectedEmaNone = true;
                } else if (j == matchingEmaCode
                        + (3 - 2 * matchingEmaDigit) * placeValues[k]) {
                    isEmaAllowed = true;
                    expectedEmaTimeFrame = timeFrames[k + 1];
                }
            }

            TrendAlignType expected = expectedDirection;
            M15ElliotAlignmentGroup expectedGroup = m15ElliotAlignmentNone;
            if (expectedDirection != trendAlignNone && isEmaAllowed) {
                expectedGroup = m15ElliotAlignmentAll;
                if (expectedAnalysisTimeFrame != PERIOD_CURRENT) {
                    expectedGroup = m15ElliotAlignmentAnalysisOpposite;
                }

                if (expectedEmaTimeFrame != PERIOD_CURRENT) {
                    expectedGroup = m15ElliotAlignmentEmaMismatch;
                    if (expectedAnalysisTimeFrame != PERIOD_CURRENT) {
                        expectedGroup = m15ElliotAlignmentBoth;
                    }
                }
            } else {
                expected = trendAlignNone;
            }

            string caseName = StringFormat("analysisMask=%d emaCode=%d", i, j);
            decision.evaluate(elliotAll, result);
            assertCondition(result.isEvaluated && result.alignType == expected
                && result.group == expectedGroup, caseName + " classification");
            if (expectedGroup != m15ElliotAlignmentNone) {
                assertCondition(result.analysisOppositeTimeFrame == expectedAnalysisTimeFrame
                    && result.emaMismatchTimeFrame == expectedEmaTimeFrame
                    && result.isEmaNone == expectedEmaNone, caseName + " exception details");
            } else {
                assertCondition(result.analysisOppositeTimeFrame == PERIOD_CURRENT
                    && result.emaMismatchTimeFrame == PERIOD_CURRENT
                    && !result.isEmaNone, caseName + " excluded details reset");
            }

            assertCondition(shared.isReady(elliotAll, PERIOD_M15)
                && shared.getAlignType(elliotAll, PERIOD_M15) == expected,
                caseName + " shared rule");
            for (int k = 0; k < ArraySize(timeFrames); k++) {
                assertCondition(elliotAll.getElliot(timeFrames[k]).isBuy
                    == ((i & (1 << k)) != 0), caseName + " original direction preserved");
            }
        }
    }

    delete elliotAll;
}

/**
 * 無効な結果で前回の方向や例外時間足が残らないことも確認する。
 */
void assertInvalid(ElliotAll *fromElliotAll, const string fromCaseName) {
    M15ElliotAlignmentDecision decision;
    M15ElliotAlignmentResult result;
    result.isEvaluated = true;
    result.alignType = trendAlignBuy;
    result.group = m15ElliotAlignmentBoth;
    result.analysisOppositeTimeFrame = PERIOD_M15;
    result.emaMismatchTimeFrame = PERIOD_H1;
    result.isEmaNone = true;
    decision.evaluate(fromElliotAll, result);
    assertCondition(!result.isEvaluated && result.alignType == trendAlignNone
        && result.group == m15ElliotAlignmentNone
        && result.analysisOppositeTimeFrame == PERIOD_CURRENT
        && result.emaMismatchTimeFrame == PERIOD_CURRENT && !result.isEmaNone,
        fromCaseName + " invalid and reset");

    ElliotDirectionAlignmentDecision shared(PERIOD_MN1,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_MN1_WITH_EMA200);
    assertCondition(!shared.isReady(fromElliotAll, PERIOD_M15)
        && shared.getAlignType(fromElliotAll, PERIOD_M15) == trendAlignNone,
        fromCaseName + " shared invalid");
}

/**
 * 全6足の欠落、波動とポイントの欠落、時間足の取り違えを検証する。
 */
void validateInvalidAnalysis() {
    assertInvalid(NULL, "null analysis");
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "invalid analysis fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    elliotAll.isAnalysisSucceeded = false;
    assertInvalid(elliotAll, "failed analysis");
    elliotAll.isAnalysisSucceeded = true;
    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = elliotAll.getElliot(timeFrames[i]);
        string caseName = EnumToString(timeFrames[i]);
        elliot.marketContext.timeFrame = PERIOD_M30;
        assertInvalid(elliotAll, caseName + " missing timeframe");
        elliot.marketContext.timeFrame = timeFrames[i];
        elliot.oscillator.marketContext.timeFrame = PERIOD_M30;
        assertInvalid(elliotAll, caseName + " oscillator timeframe");
        elliot.oscillator.marketContext.timeFrame = timeFrames[i];

        Wave *wave = (Wave *)elliot.waveList.Detach(0);
        assertInvalid(elliotAll, caseName + " missing wave");
        assertCondition(elliot.waveList.Add(wave), caseName + " restore wave");
        wave.marketContext.timeFrame = PERIOD_M30;
        assertInvalid(elliotAll, caseName + " wave timeframe");
        wave.marketContext.timeFrame = timeFrames[i];

        ZigZagPoint *point = (ZigZagPoint *)wave.zigZagPointList.Detach(0);
        assertInvalid(elliotAll, caseName + " missing point");
        assertCondition(wave.zigZagPointList.Add(point), caseName + " restore point");
        point.marketContext.timeFrame = PERIOD_M30;
        assertInvalid(elliotAll, caseName + " point timeframe");
        point.marketContext.timeFrame = timeFrames[i];
    }

    delete elliotAll;
}

/**
 * EMA200の正常なNONEと、初期化値、取得失敗、不整合を区別する。
 */
void validateInvalidEma() {
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "invalid EMA fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    M15ElliotAlignmentDecision decision;
    M15ElliotAlignmentResult result;
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = elliotAll.getElliot(timeFrames[i]);
        Ema200 *ema200 = GetPointer(elliot.oscillator.ema200);
        string caseName = EnumToString(timeFrames[i]);
        for (int j = 0; j < 3; j++) {
            int direction = j - 1;
            setEma(elliot, direction);
            string validLabel = ema200.buySellLabel;
            ema200.marketContext.timeFrame = PERIOD_M30;
            assertInvalid(elliotAll, caseName + " EMA timeframe");
            ema200.marketContext.timeFrame = timeFrames[i];

            ema200.buySellLabel = "INVALID";
            assertInvalid(elliotAll, caseName + " invalid label");
            ema200.buySellLabel = validLabel;
            ema200.isBuy = true;
            ema200.isSell = true;
            assertInvalid(elliotAll, caseName + " conflicting flags");
            setEma(elliot, direction);
            ema200.buySellLabel = "NONE";
            if (direction == 0) {
                ema200.buySellLabel = "BUY";
            }

            assertInvalid(elliotAll, caseName + " label and flag disagree");
            setEma(elliot, direction);
            ema200.close1 = 0.0;
            assertInvalid(elliotAll, caseName + " missing close");
            setEma(elliot, direction);
            ema200.ema200Shift1 = EMPTY_VALUE;
            assertInvalid(elliotAll, caseName + " missing current EMA");
            setEma(elliot, direction);
            ema200.ema200Compare = 0.0;
            assertInvalid(elliotAll, caseName + " missing comparison EMA");
            setEma(elliot, direction);
            ema200.closePosition = EMA200_POSITION_NONE;
            assertInvalid(elliotAll, caseName + " uncalculated position");
            setEma(elliot, direction);
            ema200.slopeDirection = (ENUM_EMA200_SLOPE_DIRECTION)99;
            assertInvalid(elliotAll, caseName + " invalid slope direction");
            setEma(elliot, direction);
            ema200.slopePips = EMPTY_VALUE;
            assertInvalid(elliotAll, caseName + " missing slope");
            setEma(elliot, direction);
            ema200.closeEma200DiffPips = EMPTY_VALUE;
            assertInvalid(elliotAll, caseName + " missing distance");
        }

        ema200.clear();
        ema200.setMarketContext(elliot.marketContext);
        assertInvalid(elliotAll, caseName + " reset NONE");
        setEma(elliot, 0);
        decision.evaluate(elliotAll, result);
        assertCondition(result.isEvaluated && result.alignType == trendAlignBuy
            && result.group == m15ElliotAlignmentEmaMismatch && result.isEmaNone
            && result.emaMismatchTimeFrame == timeFrames[i], caseName + " valid flat NONE");
        setEma(elliot, 1);
    }

    elliotAll.getElliot(PERIOD_MN1).oscillator.ema200.clear();
    decision.evaluate(elliotAll, result);
    assertCondition(result.isEvaluated && result.group == m15ElliotAlignmentAll,
        "MN1 EMA is outside scope");

    delete elliotAll;
}

/**
 * 新ルールの対象範囲と既存M15ルールの互換性を検証する。
 */
void validateSharedRuleScope() {
    assertCondition((int)ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_W1_WITH_EMA200 == 8
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_MN1_WITH_EMA200 == 9,
        "existing enum preserved");
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "scope fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    ENUM_TIMEFRAMES scopes[] = {
        PERIOD_CURRENT, PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4,
        PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
    };
    for (int i = 0; i < ArraySize(scopes); i++) {
        ElliotDirectionAlignmentDecision decision(scopes[i],
            ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_MN1_WITH_EMA200);
        for (int j = 0; j < ArraySize(scopes); j++) {
            bool isAllowed = scopes[i] == PERIOD_MN1 && scopes[j] == PERIOD_M15;
            TrendAlignType expected = trendAlignNone;
            if (isAllowed) {
                expected = trendAlignBuy;
            }

            ENUM_TIMEFRAMES actualTimeFrames[];
            bool isBuilt = decision.buildTargetTimeFrames(scopes[j], actualTimeFrames);
            assertCondition(isBuilt == isAllowed
                && decision.isReady(elliotAll, scopes[j]) == isAllowed
                && decision.getAlignType(elliotAll, scopes[j]) == expected,
                "scope " + EnumToString(scopes[i]) + " -> " + EnumToString(scopes[j]));
            if (isAllowed) {
                assertCondition(ArraySize(actualTimeFrames) == 6
                    && actualTimeFrames[0] == PERIOD_MN1
                    && actualTimeFrames[5] == PERIOD_M15, "new rule target range");
            } else {
                assertCondition(ArraySize(actualTimeFrames) == 0, "invalid target range empty");
            }
        }
    }

    ElliotDirectionAlignmentDecision legacy(PERIOD_W1,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_W1_WITH_EMA200);
    elliotAll.getElliot(PERIOD_MN1).isBuy = false;
    setEma(elliotAll.getElliot(PERIOD_W1), 0);
    assertCondition(legacy.isReady(elliotAll, PERIOD_M15)
        && legacy.getAlignType(elliotAll, PERIOD_M15) == trendAlignBuy,
        "old rule ignores MN1 analysis and W1 EMA");
    setEma(elliotAll.getElliot(PERIOD_H1), 0);
    assertCondition(legacy.getAlignType(elliotAll, PERIOD_M15) == trendAlignNone,
        "old rule excludes H1 EMA NONE");
    setEma(elliotAll.getElliot(PERIOD_H1), 1);
    elliotAll.getElliot(PERIOD_M15).isBuy = false;
    assertCondition(legacy.getAlignType(elliotAll, PERIOD_M15) == trendAlignNone,
        "old rule retains M15 direction reference");

    delete elliotAll;
}

/**
 * M15だけ逆でも多数派をソートの基準にし、既存の呼び出しではM15基準を維持する。
 */
void validateMajoritySort() {
    ElliotAll *elliotAll = createFixture();
    assertCondition(elliotAll != NULL, "majority sort fixture allocation");
    if (elliotAll == NULL) {
        return;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    M15ElliotEmaSortDecision decision;
    M15ElliotEmaSortResult majorityResult;
    M15ElliotEmaSortResult legacyResult;
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int emaDirection = -1;
        if (isBuy) {
            emaDirection = 1;
        }

        for (int j = 0; j < ArraySize(timeFrames); j++) {
            Elliot *elliot = elliotAll.getElliot(timeFrames[j]);
            elliot.isBuy = isBuy;
            elliot.getLatestWave().isUptrend = isBuy;
            setEma(elliot, emaDirection);
        }

        Elliot *elliotM15 = elliotAll.getElliot(PERIOD_M15);
        elliotM15.isBuy = !isBuy;
        elliotM15.getLatestWave().isUptrend = !isBuy;
        decision.evaluate(elliotAll, isBuy, majorityResult);
        decision.evaluate(elliotAll, legacyResult);
        assertCondition(majorityResult.isEvaluated
            && majorityResult.m15WaveDirectionRank == 0
            && majorityResult.m15EmaDirectionRank == 2
            && majorityResult.h1WaveDirectionRank == 2
            && majorityResult.h1EmaDirectionRank == 2
            && majorityResult.h4WaveDirectionRank == 2
            && majorityResult.h4EmaDirectionRank == 2
            && majorityResult.d1EmaDirectionRank == 2, "majority sort direction");
        assertCondition(legacyResult.isEvaluated
            && legacyResult.m15WaveDirectionRank == 2
            && legacyResult.m15EmaDirectionRank == 0
            && legacyResult.h1WaveDirectionRank == 0
            && legacyResult.h1EmaDirectionRank == 0
            && legacyResult.h4WaveDirectionRank == 0
            && legacyResult.h4EmaDirectionRank == 0
            && legacyResult.d1EmaDirectionRank == 0, "legacy sort remains M15");
        assertCondition(elliotM15.isBuy == !isBuy, "sort preserves original M15 direction");

        setEma(elliotM15, 0);
        decision.evaluate(elliotAll, isBuy, majorityResult);
        decision.evaluate(elliotAll, legacyResult);
        assertCondition(majorityResult.m15EmaDirectionRank == 1
            && legacyResult.m15EmaDirectionRank == 1, "NONE sort rank is neutral");
    }

    delete elliotAll;
}

/**
 * M15の4分類と共有判定ルールを検証する。
 */
void OnStart() {
    failureCount = 0;
    assertionCount = 0;
    validateBasicGroups();
    validateAllCombinations();
    validateInvalidAnalysis();
    validateInvalidEma();
    validateSharedRuleScope();
    validateMajoritySort();
    if (failureCount == 0) {
        PrintFormat("M15ElliotAlignmentDecisionSmokeTest PASS assertions=%d", assertionCount);

        return;
    }

    PrintFormat("M15ElliotAlignmentDecisionSmokeTest FAIL count=%d assertions=%d",
        failureCount, assertionCount);
}
