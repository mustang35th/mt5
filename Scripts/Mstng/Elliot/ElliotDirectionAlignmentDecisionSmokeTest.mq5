//+------------------------------------------------------------------+
//|                    ElliotDirectionAlignmentDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Elliot\D1ElliotEmaSortDecision.mqh>
#include <Mstng\Elliot\ElliotDirectionAlignmentDecision.mqh>

/** 失敗したテスト件数。 */
int gFailureCount = 0;

/**
 * トレンド一致種別を表示文字列へ変換する。
 *
 * @param fromAlignType トレンド一致種別
 * @return 表示文字列
 */
string convertAlignTypeText(const TrendAlignType fromAlignType) {
    if (fromAlignType == trendAlignBuy) {
        return "BUY";
    }

    if (fromAlignType == trendAlignSell) {
        return "SELL";
    }

    return "NONE";
}

/**
 * 判定可能な最小Elliotを生成する。
 *
 * @param fromTimeFrame 対象時間足
 * @param fromIsBuy BUY方向の場合true
 * @return 呼び出し側が所有するElliot。生成失敗時NULL
 */
Elliot *createReadyElliot(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const bool fromIsBuy
) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    elliot.isBuy = fromIsBuy;
    elliot.oscillator.isBuy = fromIsBuy;

    if (fromIsBuy) {
        elliot.buySellLabel = "BUY";
    } else {
        elliot.buySellLabel = "SELL";
    }

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

    Wave *wave = new Wave(
        elliot.marketContext,
        pointList,
        true,
        fromIsBuy
    );

    if (wave == NULL || !elliot.waveList.Add(wave)) {
        if (wave != NULL) {
            delete wave;
        }

        delete elliot;

        return NULL;
    }

    return elliot;
}

/**
 * M5終端の同一分析結果をH1とM5で独立評価できることを検証する。
 */
void validateIndependentViewTimeFrames() {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_M5);
    Elliot *elliotH1 = createReadyElliot(PERIOD_H1, true);
    Elliot *elliotM5 = createReadyElliot(PERIOD_M5, false);

    if (elliotAll == NULL || elliotH1 == NULL || elliotM5 == NULL) {
        if (elliotH1 != NULL) {
            delete elliotH1;
        }

        if (elliotM5 != NULL) {
            delete elliotM5;
        }

        if (elliotAll != NULL) {
            delete elliotAll;
        }

        gFailureCount++;
        Print("FAIL INDEPENDENT VIEW allocation");

        return;
    }

    if (!elliotAll.elliotList.Add(elliotH1)) {
        delete elliotH1;
        delete elliotM5;
        delete elliotAll;
        gFailureCount++;
        Print("FAIL INDEPENDENT VIEW add H1");

        return;
    }

    if (!elliotAll.elliotList.Add(elliotM5)) {
        delete elliotM5;
        delete elliotAll;
        gFailureCount++;
        Print("FAIL INDEPENDENT VIEW add M5");

        return;
    }

    elliotAll.elliotCurrent = elliotM5;
    elliotAll.isAnalysisSucceeded = true;

    ElliotDirectionAlignmentDecision h1Decision(PERIOD_H1);
    ElliotDirectionAlignmentDecision m5Decision(PERIOD_M5);
    bool isH1Ready = h1Decision.isReady(elliotAll, PERIOD_H1);
    bool isM5Ready = m5Decision.isReady(elliotAll, PERIOD_M5);
    TrendAlignType h1AlignType = h1Decision.getAlignType(
        elliotAll,
        PERIOD_H1
    );
    TrendAlignType m5AlignType = m5Decision.getAlignType(
        elliotAll,
        PERIOD_M5
    );

    if (!isH1Ready
            || !isM5Ready
            || h1AlignType != trendAlignBuy
            || m5AlignType != trendAlignSell) {
        gFailureCount++;
        PrintFormat(
            "FAIL INDEPENDENT VIEW h1Ready=%s m5Ready=%s h1=%s m5=%s",
            (string)isH1Ready,
            (string)isM5Ready,
            convertAlignTypeText(h1AlignType),
            convertAlignTypeText(m5AlignType)
        );
    }

    delete elliotAll;
}

/**
 * D1専用方向一致判定の期待値を検証する。
 *
 * @param fromCaseName テストケース名
 * @param fromIsD1Buy D1がBUYの場合true
 * @param fromIsW1Buy W1がBUYの場合true
 * @param fromIsMn1Buy MN1がBUYの場合true
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
 * @param fromExpected 期待するトレンド一致種別
 */
void assertD1Alignment(
    const string fromCaseName,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const TrendAlignType fromExpected
) {
    TrendAlignType actual =
        ElliotDirectionAlignmentDecision::evaluateD1W1WithMn1OrEma200(
            fromIsD1Buy,
            fromIsW1Buy,
            fromIsMn1Buy,
            fromIsW1Ema200Buy,
            fromIsW1Ema200Sell
        );

    if (actual == fromExpected) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%s actual=%s",
        fromCaseName,
        convertAlignTypeText(fromExpected),
        convertAlignTypeText(actual)
    );
}

/**
 * H4専用方向一致判定の期待値を検証する。
 *
 * @param fromCaseName テストケース名
 * @param fromIsH4Buy H4がBUYの場合true
 * @param fromIsD1Buy D1がBUYの場合true
 * @param fromIsW1Buy W1がBUYの場合true
 * @param fromIsMn1Buy MN1がBUYの場合true
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
 * @param fromExpected 期待するトレンド一致種別
 */
void assertH4Alignment(
    const string fromCaseName,
    const bool fromIsH4Buy,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const TrendAlignType fromExpected
) {
    TrendAlignType actual =
        ElliotDirectionAlignmentDecision::evaluateH4W1WithMn1OrEma200(
            fromIsH4Buy,
            fromIsD1Buy,
            fromIsW1Buy,
            fromIsMn1Buy,
            fromIsW1Ema200Buy,
            fromIsW1Ema200Sell
        );

    if (actual == fromExpected) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%s actual=%s",
        fromCaseName,
        convertAlignTypeText(fromExpected),
        convertAlignTypeText(actual)
    );
}

/**
 * H1専用方向一致判定の期待値を検証する。
 *
 * @param fromCaseName テストケース名
 * @param fromIsH1Buy H1がBUYの場合true
 * @param fromIsH4Buy H4がBUYの場合true
 * @param fromIsD1Buy D1がBUYの場合true
 * @param fromIsW1Buy W1がBUYの場合true
 * @param fromIsMn1Buy MN1がBUYの場合true
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
 * @param fromExpected 期待するトレンド一致種別
 */
void assertH1Alignment(
    const string fromCaseName,
    const bool fromIsH1Buy,
    const bool fromIsH4Buy,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const TrendAlignType fromExpected
) {
    TrendAlignType actual =
        ElliotDirectionAlignmentDecision::evaluateH1W1WithMn1OrEma200(
            fromIsH1Buy,
            fromIsH4Buy,
            fromIsD1Buy,
            fromIsW1Buy,
            fromIsMn1Buy,
            fromIsW1Ema200Buy,
            fromIsW1Ema200Sell
        );

    if (actual == fromExpected) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s expected=%s actual=%s",
        fromCaseName,
        convertAlignTypeText(fromExpected),
        convertAlignTypeText(actual)
    );
}

/**
 * D1条件とH4またはH1条件を組み合わせる判定の期待値を検証する。
 *
 * @param fromCaseName テストケース名
 * @param fromAlignmentRule 一致判定ルール
 * @param fromIsH1Buy H1がBUYの場合true
 * @param fromIsH4Buy H4がBUYの場合true
 * @param fromIsD1Buy D1がBUYの場合true
 * @param fromIsW1Buy W1がBUYの場合true
 * @param fromIsMn1Buy MN1がBUYの場合true
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
 * @param fromExpected 期待するトレンド一致種別
 */
void assertH1D1OrAlignment(
    const string fromCaseName,
    const ElliotDirectionAlignmentRule fromAlignmentRule,
    const bool fromIsH1Buy,
    const bool fromIsH4Buy,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const TrendAlignType fromExpected
) {
    TrendAlignType actual = trendAlignNone;

    if (fromAlignmentRule
            == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_AND_H4_OR_H1) {
        actual = ElliotDirectionAlignmentDecision::
            evaluateH1D1W1WithH4OrH1(
                fromIsH1Buy,
                fromIsH4Buy,
                fromIsD1Buy,
                fromIsW1Buy
            );
    } else if (fromAlignmentRule
            == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_MN1_W1_AND_H4_OR_H1) {
        actual = ElliotDirectionAlignmentDecision::
            evaluateH1D1Mn1W1WithH4OrH1(
                fromIsH1Buy,
                fromIsH4Buy,
                fromIsD1Buy,
                fromIsW1Buy,
                fromIsMn1Buy
            );
    } else if (fromAlignmentRule
            == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_MN1_OR_EMA_AND_H4_OR_H1) {
        actual = ElliotDirectionAlignmentDecision::
            evaluateH1D1W1WithMn1OrEma200AndH4OrH1(
                fromIsH1Buy,
                fromIsH4Buy,
                fromIsD1Buy,
                fromIsW1Buy,
                fromIsMn1Buy,
                fromIsW1Ema200Buy,
                fromIsW1Ema200Sell
            );
    }

    if (actual == fromExpected) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s rule=%d expected=%s actual=%s",
        fromCaseName,
        (int)fromAlignmentRule,
        convertAlignTypeText(fromExpected),
        convertAlignTypeText(actual)
    );
}

/**
 * H1次点候補判定の期待値を検証する。
 *
 * @param fromCaseName テストケース名
 * @param fromIsH1Buy H1がBUYの場合true
 * @param fromIsH4Buy H4がBUYの場合true
 * @param fromIsD1Buy D1がBUYの場合true
 * @param fromIsW1Buy W1がBUYの場合true
 * @param fromIsMn1Buy MN1がBUYの場合true
 * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
 * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
 * @param fromExpectedAvailable 判定可能な期待値
 * @param fromExpectedRunnerUp 次点候補の期待値
 * @param fromExpectedAlignType 完成時方向の期待値
 * @param fromExpectedMissingCondition 不足条件の期待値
 */
void assertH1RunnerUp(
    const string fromCaseName,
    const bool fromIsH1Buy,
    const bool fromIsH4Buy,
    const bool fromIsD1Buy,
    const bool fromIsW1Buy,
    const bool fromIsMn1Buy,
    const bool fromIsW1Ema200Buy,
    const bool fromIsW1Ema200Sell,
    const bool fromExpectedAvailable,
    const bool fromExpectedRunnerUp,
    const TrendAlignType fromExpectedAlignType,
    const H1ElliotAlignmentMissingCondition fromExpectedMissingCondition
) {
    H1ElliotAlignmentRunnerUpResult result;
    bool isAvailable =
        ElliotDirectionAlignmentDecision::
            evaluateH1W1WithMn1OrEma200RunnerUp(
                fromIsH1Buy,
                fromIsH4Buy,
                fromIsD1Buy,
                fromIsW1Buy,
                fromIsMn1Buy,
                fromIsW1Ema200Buy,
                fromIsW1Ema200Sell,
                result
            );
    bool isMatched = isAvailable == fromExpectedAvailable
        && result.isRunnerUp == fromExpectedRunnerUp
        && result.alignType == fromExpectedAlignType
        && result.missingCondition == fromExpectedMissingCondition;

    if (fromExpectedRunnerUp) {
        isMatched = isMatched
            && result.matchedConditionCount == 4
            && result.requiredConditionCount == 5;
    }

    if (isMatched) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s available=%s runnerUp=%s align=%s missing=%d matched=%d required=%d",
        fromCaseName,
        (string)isAvailable,
        (string)result.isRunnerUp,
        convertAlignTypeText(result.alignType),
        (int)result.missingCondition,
        result.matchedConditionCount,
        result.requiredConditionCount
    );
}

/**
 * BUY方向の判定ケースを検証する。
 */
void validateBuyCases() {
    assertD1Alignment(
        "BUY MN1 MATCH EMA NONE",
        true, true, true, false, false, trendAlignBuy
    );
    assertD1Alignment(
        "BUY EMA MATCH",
        true, true, false, true, false, trendAlignBuy
    );
    assertD1Alignment(
        "BUY MN1 MATCH EMA OPPOSITE",
        true, true, true, false, true, trendAlignBuy
    );
    assertD1Alignment(
        "BUY NEITHER MATCH",
        true, true, false, false, false, trendAlignNone
    );
    assertD1Alignment(
        "BUY EMA OPPOSITE",
        true, true, false, false, true, trendAlignNone
    );
    assertD1Alignment(
        "BUY W1 MISMATCH",
        true, false, true, true, false, trendAlignNone
    );
}

/**
 * SELL方向の判定ケースを検証する。
 */
void validateSellCases() {
    assertD1Alignment(
        "SELL MN1 MATCH EMA NONE",
        false, false, false, false, false, trendAlignSell
    );
    assertD1Alignment(
        "SELL EMA MATCH",
        false, false, true, false, true, trendAlignSell
    );
    assertD1Alignment(
        "SELL MN1 MATCH EMA OPPOSITE",
        false, false, false, true, false, trendAlignSell
    );
    assertD1Alignment(
        "SELL NEITHER MATCH",
        false, false, true, false, false, trendAlignNone
    );
    assertD1Alignment(
        "SELL EMA OPPOSITE",
        false, false, true, true, false, trendAlignNone
    );
    assertD1Alignment(
        "SELL W1 MISMATCH",
        false, true, false, false, true, trendAlignNone
    );
}

/**
 * 不正なEMA200状態を安全側へ倒すことを検証する。
 */
void validateInvalidEmaCases() {
    assertD1Alignment(
        "BUY EMA CONFLICT",
        true, true, true, true, true, trendAlignNone
    );
    assertD1Alignment(
        "SELL EMA CONFLICT",
        false, false, false, true, true, trendAlignNone
    );
}

/**
 * H4のBUY方向判定ケースを検証する。
 */
void validateH4BuyCases() {
    assertH4Alignment(
        "H4 BUY MN1 FALLBACK",
        true, true, true, true, false, false, trendAlignBuy
    );
    assertH4Alignment(
        "H4 BUY EMA FALLBACK",
        true, true, true, false, true, false, trendAlignBuy
    );
    assertH4Alignment(
        "H4 BUY H4 MISMATCH",
        false, true, true, true, true, false, trendAlignNone
    );
    assertH4Alignment(
        "H4 BUY W1 MISMATCH",
        true, true, false, true, true, false, trendAlignNone
    );
    assertH4Alignment(
        "H4 BUY NEITHER MATCH",
        true, true, true, false, false, false, trendAlignNone
    );
}

/**
 * H4のSELL方向判定ケースを検証する。
 */
void validateH4SellCases() {
    assertH4Alignment(
        "H4 SELL MN1 FALLBACK",
        false, false, false, false, false, false, trendAlignSell
    );
    assertH4Alignment(
        "H4 SELL EMA FALLBACK",
        false, false, false, true, false, true, trendAlignSell
    );
    assertH4Alignment(
        "H4 SELL H4 MISMATCH",
        true, false, false, false, false, true, trendAlignNone
    );
    assertH4Alignment(
        "H4 SELL W1 MISMATCH",
        false, false, true, false, false, true, trendAlignNone
    );
    assertH4Alignment(
        "H4 SELL NEITHER MATCH",
        false, false, false, true, false, false, trendAlignNone
    );
}

/**
 * H4判定で不正なEMA200状態を安全側へ倒すことを検証する。
 */
void validateH4InvalidEmaCases() {
    assertH4Alignment(
        "H4 BUY EMA CONFLICT",
        true, true, true, true, true, true, trendAlignNone
    );
    assertH4Alignment(
        "H4 SELL EMA CONFLICT",
        false, false, false, false, true, true, trendAlignNone
    );
}

/**
 * H1のBUY方向判定ケースを検証する。
 */
void validateH1BuyCases() {
    assertH1Alignment(
        "H1 BUY MN1 MATCH EMA NONE",
        true, true, true, true, true, false, false, trendAlignBuy
    );
    assertH1Alignment(
        "H1 BUY EMA MATCH",
        true, true, true, true, false, true, false, trendAlignBuy
    );
    assertH1Alignment(
        "H1 BUY MN1 MATCH EMA OPPOSITE",
        true, true, true, true, true, false, true, trendAlignBuy
    );
    assertH1Alignment(
        "H1 BUY NEITHER MATCH",
        true, true, true, true, false, false, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 BUY EMA OPPOSITE",
        true, true, true, true, false, false, true, trendAlignNone
    );
    assertH1Alignment(
        "H1 BUY W1 MISMATCH",
        true, true, true, false, true, true, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 BUY D1 MISMATCH",
        true, true, false, true, true, true, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 BUY H4 MISMATCH",
        true, false, true, true, true, true, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 DIRECTION MISMATCH",
        false, true, true, true, true, true, false, trendAlignNone
    );
}

/**
 * H1のSELL方向判定ケースを検証する。
 */
void validateH1SellCases() {
    assertH1Alignment(
        "H1 SELL MN1 MATCH EMA NONE",
        false, false, false, false, false, false, false, trendAlignSell
    );
    assertH1Alignment(
        "H1 SELL EMA MATCH",
        false, false, false, false, true, false, true, trendAlignSell
    );
    assertH1Alignment(
        "H1 SELL MN1 MATCH EMA OPPOSITE",
        false, false, false, false, false, true, false, trendAlignSell
    );
    assertH1Alignment(
        "H1 SELL NEITHER MATCH",
        false, false, false, false, true, false, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 SELL EMA OPPOSITE",
        false, false, false, false, true, true, false, trendAlignNone
    );
    assertH1Alignment(
        "H1 SELL W1 MISMATCH",
        false, false, false, true, false, false, true, trendAlignNone
    );
}

/**
 * H1判定で不正なEMA200状態を安全側へ倒すことを検証する。
 */
void validateH1InvalidEmaCases() {
    assertH1Alignment(
        "H1 BUY EMA CONFLICT",
        true, true, true, true, true, true, true, trendAlignNone
    );
    assertH1Alignment(
        "H1 SELL EMA CONFLICT",
        false, false, false, false, false, true, true, trendAlignNone
    );
}

/**
 * D1とW1の一致にH4またはH1の一致を加える判定を検証する。
 */
void validateH1D1W1WithH4OrH1Cases() {
    ElliotDirectionAlignmentRule rule =
        ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_AND_H4_OR_H1;

    assertH1D1OrAlignment(
        "D1 W1 OR BUY BOTH",
        rule, true, true, true, true, false, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 OR BUY H4 ONLY",
        rule, false, true, true, true, false, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 OR BUY H1 ONLY",
        rule, true, false, true, true, false, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 OR BUY NEITHER",
        rule, false, false, true, true, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 OR BUY W1 MISMATCH",
        rule, true, true, true, false, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 OR SELL BOTH",
        rule, false, false, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 OR SELL H4 ONLY",
        rule, true, false, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 OR SELL H1 ONLY",
        rule, false, true, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 OR SELL NEITHER",
        rule, true, true, false, false, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 OR SELL W1 MISMATCH",
        rule, false, false, false, true, false, false, false, trendAlignNone
    );
}

/**
 * MN1、W1、D1の一致にH4またはH1の一致を加える判定を検証する。
 */
void validateH1D1Mn1W1WithH4OrH1Cases() {
    ElliotDirectionAlignmentRule rule =
        ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_MN1_W1_AND_H4_OR_H1;

    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY BOTH",
        rule, true, true, true, true, true, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY H4 ONLY",
        rule, false, true, true, true, true, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY H1 ONLY",
        rule, true, false, true, true, true, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY NEITHER",
        rule, false, false, true, true, true, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY W1 MISMATCH",
        rule, true, true, true, false, true, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR BUY MN1 MISMATCH",
        rule, true, true, true, true, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL BOTH",
        rule, false, false, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL H4 ONLY",
        rule, true, false, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL H1 ONLY",
        rule, false, true, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL NEITHER",
        rule, true, true, false, false, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL W1 MISMATCH",
        rule, false, false, false, true, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 MN1 W1 OR SELL MN1 MISMATCH",
        rule, false, false, false, false, true, false, false, trendAlignNone
    );
}

/**
 * D1とW1、MN1またはEMA200、H4またはH1の複合判定を検証する。
 */
void validateH1D1W1WithMn1OrEmaAndH4OrH1Cases() {
    ElliotDirectionAlignmentRule rule =
        ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_MN1_OR_EMA_AND_H4_OR_H1;

    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY BOTH",
        rule, true, true, true, true, true, false, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY H4 ONLY",
        rule, false, true, true, true, false, true, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY H1 ONLY",
        rule, true, false, true, true, false, true, false, trendAlignBuy
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY LOWER NEITHER",
        rule, false, false, true, true, true, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY W1 MISMATCH",
        rule, true, true, true, false, true, true, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY BASE NEITHER",
        rule, true, true, true, true, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR BUY EMA CONFLICT",
        rule, true, true, true, true, true, true, true, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL BOTH",
        rule, false, false, false, false, false, false, false, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL H4 ONLY",
        rule, true, false, false, false, true, false, true, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL H1 ONLY",
        rule, false, true, false, false, true, false, true, trendAlignSell
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL LOWER NEITHER",
        rule, true, true, false, false, false, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL W1 MISMATCH",
        rule, false, false, false, true, false, false, true, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL BASE NEITHER",
        rule, false, false, false, false, true, false, false, trendAlignNone
    );
    assertH1D1OrAlignment(
        "D1 W1 MN1 EMA OR SELL EMA CONFLICT",
        rule, false, false, false, false, false, true, true, trendAlignNone
    );
}

/**
 * H1次点候補のBUY完成形を検証する。
 */
void validateH1BuyRunnerUpCases() {
    assertH1RunnerUp(
        "H1 BUY COMPLETE",
        true, true, true, true, true, false, false,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
    assertH1RunnerUp(
        "H1 BUY WAIT H1",
        false, true, true, true, true, false, false,
        true, true, trendAlignBuy, h1ElliotAlignmentMissingH1
    );
    assertH1RunnerUp(
        "H1 BUY WAIT H4",
        true, false, true, true, true, false, false,
        true, true, trendAlignBuy, h1ElliotAlignmentMissingH4
    );
    assertH1RunnerUp(
        "H1 BUY WAIT D1",
        true, true, false, true, true, false, false,
        true, true, trendAlignBuy, h1ElliotAlignmentMissingD1
    );
    assertH1RunnerUp(
        "H1 BUY WAIT W1",
        true, true, true, false, true, false, false,
        true, true, trendAlignBuy, h1ElliotAlignmentMissingW1
    );
    assertH1RunnerUp(
        "H1 BUY WAIT MN1 OR EMA",
        true, true, true, true, false, false, false,
        true, true, trendAlignBuy,
        h1ElliotAlignmentMissingMn1OrW1Ema200
    );
    assertH1RunnerUp(
        "H1 BUY EMA ALTERNATIVE COMPLETE",
        true, true, true, true, false, true, false,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
    assertH1RunnerUp(
        "H1 BUY TWO CONDITIONS MISSING",
        true, false, false, true, true, false, false,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
}

/**
 * H1次点候補のSELL完成形を検証する。
 */
void validateH1SellRunnerUpCases() {
    assertH1RunnerUp(
        "H1 SELL COMPLETE",
        false, false, false, false, false, false, false,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
    assertH1RunnerUp(
        "H1 SELL WAIT H1",
        true, false, false, false, false, false, false,
        true, true, trendAlignSell, h1ElliotAlignmentMissingH1
    );
    assertH1RunnerUp(
        "H1 SELL WAIT H4",
        false, true, false, false, false, false, false,
        true, true, trendAlignSell, h1ElliotAlignmentMissingH4
    );
    assertH1RunnerUp(
        "H1 SELL WAIT D1",
        false, false, true, false, false, false, false,
        true, true, trendAlignSell, h1ElliotAlignmentMissingD1
    );
    assertH1RunnerUp(
        "H1 SELL WAIT W1",
        false, false, false, true, false, false, false,
        true, true, trendAlignSell, h1ElliotAlignmentMissingW1
    );
    assertH1RunnerUp(
        "H1 SELL WAIT MN1 OR EMA",
        false, false, false, false, true, false, false,
        true, true, trendAlignSell,
        h1ElliotAlignmentMissingMn1OrW1Ema200
    );
    assertH1RunnerUp(
        "H1 SELL EMA ALTERNATIVE COMPLETE",
        false, false, false, false, true, false, true,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
    assertH1RunnerUp(
        "H1 SELL TWO CONDITIONS MISSING",
        false, true, true, false, false, false, false,
        true, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
}

/**
 * H1次点候補で不正なEMA200状態を除外することを検証する。
 */
void validateH1RunnerUpInvalidEmaCases() {
    assertH1RunnerUp(
        "H1 RUNNER UP EMA CONFLICT",
        true, true, true, true, false, true, true,
        false, false, trendAlignNone, h1ElliotAlignmentMissingNone
    );
}

/**
 * 内部判定ルールのenum値が既存互換であることを検証する。
 */
void validateAlignmentRuleValues() {
    bool isMatched =
        (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES == 0
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200 == 1
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200 == 2
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_H4_W1_WITH_MN1_OR_EMA200 == 3
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_AND_H4_OR_H1 == 4
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_MN1_W1_AND_H4_OR_H1 == 5
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_MN1_OR_EMA_AND_H4_OR_H1 == 6
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_M5_D1_M15_WITH_H4_OR_H1 == 7;

    if (isMatched) {
        return;
    }

    gFailureCount++;
    Print("FAIL ALIGNMENT RULE ENUM VALUES");
}

/**
 * 追加の固定値テストの成否を記録する。
 */
void assertD1EmaCondition(const bool fromSuccess, const string fromCaseName) {
    if (!fromSuccess) {
        gFailureCount++;
        Print("FAIL ", fromCaseName);
    }
}

/**
 * EMA200のフラグとラベルを独立指定し、不整合状態も再現する。
 */
void setD1TestEma(Elliot *fromElliot, const bool fromIsBuy,
        const bool fromIsSell, const string fromLabel) {
    fromElliot.oscillator.ema200.isBuy = fromIsBuy;
    fromElliot.oscillator.ema200.isSell = fromIsSell;
    fromElliot.oscillator.ema200.buySellLabel = fromLabel;
}

/**
 * 既存の最小Elliotを使用し、D1と下位足を同じ結果から評価するfixtureを作る。
 */
ElliotAll *createD1EmaFilterFixture(const bool fromIsBuy) {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_M5);
    if (elliotAll == NULL) {
        return NULL;
    }
    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4,
        PERIOD_H1, PERIOD_M15, PERIOD_M5
    };
    string direction = convertAlignTypeText(trendAlignSell);
    if (fromIsBuy) {
        direction = convertAlignTypeText(trendAlignBuy);
    }
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = createReadyElliot(timeFrames[i], fromIsBuy);
        if (elliot == NULL || !elliotAll.elliotList.Add(elliot)) {
            if (elliot != NULL) {
                delete elliot;
            }
            delete elliotAll;
            return NULL;
        }
        setD1TestEma(elliot, fromIsBuy, !fromIsBuy, direction);
    }
    elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_M5);
    elliotAll.isAnalysisSucceeded = true;
    return elliotAll;
}

/**
 * EMA不一致を分析エラーと混同せず、実際の一覧判定APIで期待値を確認する。
 */
void assertD1EmaObjectAlignment(const string fromCaseName,
        ElliotDirectionAlignmentDecision &fromDecision, ElliotAll *fromElliotAll,
        const ENUM_TIMEFRAMES fromTimeFrame, const bool fromExpectedReady,
        const TrendAlignType fromExpectedAlignType) {
    bool ready = fromDecision.isReady(fromElliotAll, fromTimeFrame);
    TrendAlignType actual = fromDecision.getAlignType(fromElliotAll, fromTimeFrame);
    if (ready != fromExpectedReady || actual != fromExpectedAlignType) {
        gFailureCount++;
        PrintFormat("FAIL %s ready=%s expectedReady=%s align=%s expectedAlign=%s",
            fromCaseName, (string)ready, (string)fromExpectedReady,
            convertAlignTypeText(actual), convertAlignTypeText(fromExpectedAlignType));
    }
}

/**
 * D1の既存3モードへEMA200条件だけをAND追加し、旧APIの初期値を維持する。
 */
void validateD1EmaRequiredModes() {
    ENUM_TIMEFRAMES startTimeFrames[] = { PERIOD_W1, PERIOD_MN1, PERIOD_MN1 };
    ElliotDirectionAlignmentRule rules[] = {
        ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200
    };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        string direction = convertAlignTypeText(expected);
        string opposite = "BUY";
        if (isBuy) {
            opposite = "SELL";
        }
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, direction + " D1 EMA fixture");
        if (elliotAll == NULL) {
            continue;
        }
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
        Elliot *elliotMN1 = elliotAll.getElliot(PERIOD_MN1);
        for (int j = 0; j < ArraySize(rules); j++) {
            string caseName = direction + " D1 MODE " + IntegerToString(j);
            ElliotDirectionAlignmentDecision decision(startTimeFrames[j], rules[j], true);
            ElliotDirectionAlignmentDecision legacy(startTimeFrames[j], rules[j]);
            assertD1EmaCondition(decision.isD1Ema200Required()
                && !legacy.isD1Ema200Required(), caseName + " opt-in getter");
            setD1TestEma(elliotD1, isBuy, !isBuy, direction);
            assertD1EmaObjectAlignment(caseName + " match", decision,
                elliotAll, PERIOD_D1, true, expected);
            setD1TestEma(elliotD1, !isBuy, isBuy, opposite);
            assertD1EmaObjectAlignment(caseName + " opposite", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            assertD1EmaObjectAlignment(caseName + " default ignores opposite", legacy,
                elliotAll, PERIOD_D1, true, expected);
            setD1TestEma(elliotD1, false, false, "NONE");
            assertD1EmaObjectAlignment(caseName + " NONE is ready but excluded", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            assertD1EmaObjectAlignment(caseName + " default ignores NONE", legacy,
                elliotAll, PERIOD_D1, true, expected);
            setD1TestEma(elliotD1, true, true, direction);
            assertD1EmaObjectAlignment(caseName + " conflicting flags", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            setD1TestEma(elliotD1, isBuy, !isBuy, opposite);
            assertD1EmaObjectAlignment(caseName + " stale opposite label", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            setD1TestEma(elliotD1, isBuy, !isBuy, "NONE");
            assertD1EmaObjectAlignment(caseName + " stale NONE label", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            setD1TestEma(elliotD1, false, false, direction);
            assertD1EmaObjectAlignment(caseName + " matching label without flag", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            setD1TestEma(elliotD1, isBuy, !isBuy, direction);

            elliotW1.isBuy = !isBuy;
            assertD1EmaObjectAlignment(caseName + " W1 still required", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            elliotW1.isBuy = isBuy;
            elliotMN1.isBuy = !isBuy;
            TrendAlignType mn1OppositeExpected = expected;
            if (j == 1) {
                mn1OppositeExpected = trendAlignNone;
            }
            assertD1EmaObjectAlignment(caseName + " original MN1 rule", decision,
                elliotAll, PERIOD_D1, true, mn1OppositeExpected);
            if (j == 2) {
                setD1TestEma(elliotW1, false, false, "NONE");
                assertD1EmaObjectAlignment(caseName + " neither upper alternative", decision,
                    elliotAll, PERIOD_D1, true, trendAlignNone);
                elliotMN1.isBuy = isBuy;
                assertD1EmaObjectAlignment(caseName + " MN1 fallback remains", decision,
                    elliotAll, PERIOD_D1, true, expected);
                setD1TestEma(elliotW1, isBuy, !isBuy, direction);
            }
            elliotMN1.isBuy = isBuy;

            elliotD1.oscillator.marketContext.timeFrame = PERIOD_H4;
            assertD1EmaObjectAlignment(caseName + " oscillator timeframe", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            elliotD1.oscillator.marketContext.timeFrame = PERIOD_D1;
            elliotD1.oscillator.ema200.marketContext.timeFrame = PERIOD_H4;
            assertD1EmaObjectAlignment(caseName + " EMA timeframe", decision,
                elliotAll, PERIOD_D1, true, trendAlignNone);
            elliotD1.oscillator.ema200.marketContext.timeFrame = PERIOD_D1;
            elliotD1.marketContext.timeFrame = PERIOD_H4;
            assertD1EmaObjectAlignment(caseName + " missing D1 timeframe", decision,
                elliotAll, PERIOD_D1, false, trendAlignNone);
            elliotD1.marketContext.timeFrame = PERIOD_D1;
            elliotAll.isAnalysisSucceeded = false;
            assertD1EmaObjectAlignment(caseName + " analysis incomplete", decision,
                elliotAll, PERIOD_D1, false, trendAlignNone);
            elliotAll.isAnalysisSucceeded = true;
            assertD1EmaObjectAlignment(caseName + " null analysis", decision,
                NULL, PERIOD_D1, false, trendAlignNone);
            assertD1EmaObjectAlignment(caseName + " restored match", decision,
                elliotAll, PERIOD_D1, true, expected);
        }
        delete elliotAll;
    }
}

/**
 * フラグがtrueでもD1以外の一覧・共通H1/H4判定にEMA制約を広げない。
 */
void validateD1EmaOtherTimeFrames() {
    ENUM_TIMEFRAMES timeFrames[] = { PERIOD_H1, PERIOD_H4, PERIOD_M5 };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        string direction = convertAlignTypeText(expected);
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, direction + " other timeframe fixture");
        if (elliotAll == NULL) {
            continue;
        }
        setD1TestEma(elliotAll.getElliot(PERIOD_D1), false, false, "NONE");
        for (int j = 0; j < ArraySize(timeFrames); j++) {
            ElliotDirectionAlignmentDecision decision(PERIOD_D1,
                ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES, true);
            assertD1EmaObjectAlignment(direction + " non-D1 " + EnumToString(timeFrames[j]),
                decision, elliotAll, timeFrames[j], true, expected);
        }
        ElliotDirectionAlignmentDecision h1Decision(PERIOD_MN1,
            ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200, true);
        ElliotDirectionAlignmentDecision h4Decision(PERIOD_MN1,
            ELLIOT_DIRECTION_ALIGNMENT_RULE_H4_W1_WITH_MN1_OR_EMA200, true);
        assertD1EmaObjectAlignment(direction + " H1 shared rule unaffected", h1Decision,
            elliotAll, PERIOD_H1, true, expected);
        assertD1EmaObjectAlignment(direction + " H4 shared rule unaffected", h4Decision,
            elliotAll, PERIOD_H4, true, expected);
        delete elliotAll;
    }
}

/**
 * D1 EMAの必須化と、上位足補強を示す既存S/A/B/NG分類が独立していることを確認する。
 */
void validateD1EmaRankIndependence() {
    D1ConditionSortRank expectedRanks[] = {
        d1ConditionSortRankS, d1ConditionSortRankA,
        d1ConditionSortRankB, d1ConditionSortRankNg
    };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        string direction = "SELL";
        if (isBuy) {
            direction = "BUY";
        }
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, direction + " rank fixture");
        if (elliotAll == NULL) {
            continue;
        }
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
        Elliot *elliotMN1 = elliotAll.getElliot(PERIOD_MN1);
        D1ElliotEmaSortDecision sortDecision;
        for (int j = 0; j < ArraySize(expectedRanks); j++) {
            elliotW1.isBuy = isBuy;
            elliotMN1.isBuy = isBuy;
            setD1TestEma(elliotW1, isBuy, !isBuy, direction);
            if (j > 0) {
                setD1TestEma(elliotW1, false, false, "NONE");
            }
            if (j > 1) {
                elliotMN1.isBuy = !isBuy;
            }
            if (j == 3) {
                elliotW1.isBuy = !isBuy;
            }
            setD1TestEma(elliotD1, isBuy, !isBuy, direction);
            D1ElliotEmaSortResult matched;
            sortDecision.evaluate(elliotAll, matched);
            setD1TestEma(elliotD1, false, false, "NONE");
            D1ElliotEmaSortResult none;
            sortDecision.evaluate(elliotAll, none);
            assertD1EmaCondition(matched.isEvaluated && none.isEvaluated
                && matched.d1ConditionRank == expectedRanks[j]
                && none.d1ConditionRank == expectedRanks[j]
                && matched.d1EmaDirectionRank == 2 && none.d1EmaDirectionRank == 1,
                direction + " D1 rank unchanged " + IntegerToString(j));
        }
        delete elliotAll;
    }
}

/**
 * H1全4モードとD1全3条件のANDを、BUY/SELLの固定結果で検証する。
 */
void validateH1D1ConditionCombinations() {
    ENUM_TIMEFRAMES d1Starts[] = { PERIOD_W1, PERIOD_MN1, PERIOD_MN1 };
    ElliotDirectionAlignmentRule d1Rules[] = {
        ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200
    };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        string direction = convertAlignTypeText(expected);
        string opposite = "BUY";
        if (isBuy) {
            opposite = "SELL";
        }
        for (int j = 0; j < 4; j++) {
            for (int k = 0; k < ArraySize(d1Rules); k++) {
                string caseName = direction + " H1 MODE " + IntegerToString(j)
                    + " D1 MODE " + IntegerToString(k);
                ENUM_TIMEFRAMES h1Start = PERIOD_D1;
                ElliotDirectionAlignmentRule h1Rule = ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES;
                if (j == 1) {
                    h1Start = PERIOD_MN1;
                } else if (j == 2) {
                    h1Start = PERIOD_MN1;
                    h1Rule = ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200;
                } else if (j == 3) {
                    h1Start = d1Starts[k];
                    h1Rule = ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_AND_H4_OR_H1;
                    if (k == 1) {
                        h1Rule = ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_MN1_W1_AND_H4_OR_H1;
                    } else if (k == 2) {
                        h1Rule = ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_MN1_OR_EMA_AND_H4_OR_H1;
                    }
                }
                ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
                assertD1EmaCondition(elliotAll != NULL, caseName + " fixture");
                if (elliotAll == NULL) {
                    continue;
                }
                Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
                Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
                Elliot *elliotMN1 = elliotAll.getElliot(PERIOD_MN1);
                Elliot *elliotH4 = elliotAll.getElliot(PERIOD_H4);
                Elliot *elliotH1 = elliotAll.getElliot(PERIOD_H1);
                ElliotDirectionAlignmentDecision decision(h1Start, h1Rule);
                ElliotDirectionAlignmentDecision legacy(h1Start, h1Rule);
                assertD1EmaCondition(!decision.isH1D1ConditionRequired(), caseName + " default disabled");
                decision.setH1D1Condition(d1Starts[k], d1Rules[k]);
                assertD1EmaCondition(decision.isH1D1ConditionRequired(), caseName + " enabled getter");
                assertD1EmaObjectAlignment(caseName + " all matched", decision,
                    elliotAll, PERIOD_H1, true, expected);
                setD1TestEma(elliotD1, false, false, "NONE");
                assertD1EmaObjectAlignment(caseName + " D1 NONE ready but excluded", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                assertD1EmaObjectAlignment(caseName + " legacy ignores D1 NONE", legacy,
                    elliotAll, PERIOD_H1, true, expected);
                setD1TestEma(elliotD1, !isBuy, isBuy, opposite);
                assertD1EmaObjectAlignment(caseName + " D1 EMA opposite", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                setD1TestEma(elliotD1, true, true, direction);
                assertD1EmaObjectAlignment(caseName + " D1 EMA conflicting flags", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                setD1TestEma(elliotD1, isBuy, !isBuy, opposite);
                assertD1EmaObjectAlignment(caseName + " D1 EMA stale label", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                setD1TestEma(elliotD1, isBuy, !isBuy, direction);

                setD1TestEma(elliotH4, false, false, "NONE");
                setD1TestEma(elliotH1, !isBuy, isBuy, opposite);
                assertD1EmaObjectAlignment(caseName + " H4 H1 EMA remain optional", decision,
                    elliotAll, PERIOD_H1, true, expected);
                elliotH1.isBuy = !isBuy;
                TrendAlignType lowerMismatchExpected = trendAlignNone;
                if (j == 3) {
                    lowerMismatchExpected = expected;
                }
                assertD1EmaObjectAlignment(caseName + " H4 only uses D1 EMA direction", decision,
                    elliotAll, PERIOD_H1, true, lowerMismatchExpected);
                elliotH4.isBuy = !isBuy;
                assertD1EmaObjectAlignment(caseName + " neither lower matches", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                elliotH1.isBuy = isBuy;
                assertD1EmaObjectAlignment(caseName + " H1 only keeps original OR", decision,
                    elliotAll, PERIOD_H1, true, lowerMismatchExpected);
                elliotH4.isBuy = isBuy;

                elliotW1.isBuy = !isBuy;
                assertD1EmaObjectAlignment(caseName + " D1 requires W1", decision,
                    elliotAll, PERIOD_H1, true, trendAlignNone);
                elliotW1.isBuy = isBuy;
                elliotMN1.isBuy = !isBuy;
                TrendAlignType mn1Expected = expected;
                if (j == 1 || k == 1) {
                    mn1Expected = trendAlignNone;
                }
                assertD1EmaObjectAlignment(caseName + " selected MN1 requirement", decision,
                    elliotAll, PERIOD_H1, true, mn1Expected);
                setD1TestEma(elliotW1, false, false, "NONE");
                TrendAlignType noAlternativeExpected = trendAlignNone;
                if (k == 0 && (j == 0 || j == 3)) {
                    noAlternativeExpected = expected;
                }
                assertD1EmaObjectAlignment(caseName + " no upper alternative", decision,
                    elliotAll, PERIOD_H1, true, noAlternativeExpected);
                elliotMN1.isBuy = isBuy;
                setD1TestEma(elliotW1, isBuy, !isBuy, direction);
                elliotW1.marketContext.timeFrame = PERIOD_M30;
                assertD1EmaObjectAlignment(caseName + " missing added W1 data", decision,
                    elliotAll, PERIOD_H1, false, trendAlignNone);
                if (j == 0) {
                    assertD1EmaObjectAlignment(caseName + " legacy needs no W1", legacy,
                        elliotAll, PERIOD_H1, true, expected);
                }
                elliotW1.marketContext.timeFrame = PERIOD_W1;
                setD1TestEma(elliotD1, false, false, "NONE");
                decision.setH1D1Condition(PERIOD_CURRENT, ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES);
                assertD1EmaCondition(!decision.isH1D1ConditionRequired(), caseName + " CURRENT disables");
                assertD1EmaObjectAlignment(caseName + " disabled restores legacy", decision,
                    elliotAll, PERIOD_H1, true, expected);
                delete elliotAll;
            }
        }
    }
}

/**
 * H1用の追加設定はD1・H4・M5と既存共有static判定へ適用しない。
 */
void validateH1D1ConditionScope() {
    ENUM_TIMEFRAMES timeFrames[] = { PERIOD_D1, PERIOD_H4, PERIOD_M5 };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, "H1 D1 scope fixture");
        if (elliotAll == NULL) {
            continue;
        }
        setD1TestEma(elliotAll.getElliot(PERIOD_D1), false, false, "NONE");
        elliotAll.getElliot(PERIOD_MN1).isBuy = !isBuy;
        for (int j = 0; j < ArraySize(timeFrames); j++) {
            ElliotDirectionAlignmentDecision decision(PERIOD_D1);
            decision.setH1D1Condition(PERIOD_MN1, ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES);
            assertD1EmaObjectAlignment("H1 D1 scope " + EnumToString(timeFrames[j]), decision,
                elliotAll, timeFrames[j], true, expected);
        }
        assertD1EmaCondition(ElliotDirectionAlignmentDecision::evaluateH1W1WithMn1OrEma200(
            isBuy, isBuy, isBuy, isBuy, isBuy, false, false) == expected,
            "H1 shared static remains independent of D1 EMA");
        delete elliotAll;
    }
}

/**
 * 次点判定の評価可否と候補有無を区別し、不成立時の古い候補を残さない。
 */
void assertH1D1RunnerUp(const string fromCaseName, ElliotDirectionAlignmentDecision &fromDecision,
        ElliotAll *fromElliotAll, const bool fromExpectedAvailable, const bool fromExpectedRunnerUp,
        const TrendAlignType fromExpectedDirection,
        const H1ElliotAlignmentMissingCondition fromExpectedMissing) {
    H1ElliotAlignmentRunnerUpResult result;
    result.isRunnerUp = true;
    result.alignType = trendAlignSell;
    result.missingCondition = h1ElliotAlignmentMissingW1;
    result.matchedConditionCount = 99;
    bool available = fromDecision.getH1RunnerUpResult(fromElliotAll, PERIOD_H1, result);
    int expectedCount = 0;
    if (fromExpectedRunnerUp) {
        expectedCount = 4;
    }
    assertD1EmaCondition(available == fromExpectedAvailable && result.isRunnerUp == fromExpectedRunnerUp
        && result.alignType == fromExpectedDirection && result.missingCondition == fromExpectedMissing
        && result.matchedConditionCount == expectedCount && result.requiredConditionCount == 5,
        fromCaseName);
}

/**
 * D1土台が合格した次点だけを許可し、通常不成立は分析不能として扱わない。
 */
void validateH1D1RunnerUpGate() {
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        string direction = convertAlignTypeText(expected);
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, direction + " H1 D1 runner fixture");
        if (elliotAll == NULL) {
            continue;
        }
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        Elliot *elliotH1 = elliotAll.getElliot(PERIOD_H1);
        Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
        ElliotDirectionAlignmentDecision decision(PERIOD_MN1,
            ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200);
        ElliotDirectionAlignmentDecision legacy(PERIOD_MN1,
            ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200);
        decision.setH1D1Condition(PERIOD_W1, ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES);
        elliotH1.isBuy = !isBuy;
        assertH1D1RunnerUp(direction + " qualified D1 allows H1 wait", decision,
            elliotAll, true, true, expected, h1ElliotAlignmentMissingH1);
        setD1TestEma(elliotD1, false, false, "NONE");
        assertH1D1RunnerUp(direction + " D1 NONE excludes runner but remains available", decision,
            elliotAll, true, false, trendAlignNone, h1ElliotAlignmentMissingNone);
        assertH1D1RunnerUp(direction + " unconfigured runner remains legacy", legacy,
            elliotAll, true, true, expected, h1ElliotAlignmentMissingH1);
        setD1TestEma(elliotD1, isBuy, !isBuy, direction);
        elliotH1.isBuy = isBuy;
        elliotW1.isBuy = !isBuy;
        assertH1D1RunnerUp(direction + " legacy W1 wait exists", legacy,
            elliotAll, true, true, expected, h1ElliotAlignmentMissingW1);
        assertH1D1RunnerUp(direction + " D1 upper mismatch excludes W1 wait", decision,
            elliotAll, true, false, trendAlignNone, h1ElliotAlignmentMissingNone);
        elliotW1.isBuy = isBuy;
        elliotH1.isBuy = !isBuy;
        elliotD1.marketContext.timeFrame = PERIOD_M30;
        assertH1D1RunnerUp(direction + " missing D1 data unavailable", decision,
            elliotAll, false, false, trendAlignNone, h1ElliotAlignmentMissingNone);
        elliotD1.marketContext.timeFrame = PERIOD_D1;
        assertH1D1RunnerUp(direction + " restored D1 allows runner again", decision,
            elliotAll, true, true, expected, h1ElliotAlignmentMissingH1);
        delete elliotAll;
    }
}

/**
 * M5の全32方向組合せでA案と従来の全足一致を比較し、適用範囲と欠損を確認する。
 */
void validateM5D1M15WithH4OrH1() {
    ElliotAll *elliotAll = createD1EmaFilterFixture(true);
    assertD1EmaCondition(elliotAll != NULL, "M5 OR fixture");
    if (elliotAll == NULL) {
        return;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
    };
    ElliotDirectionAlignmentDecision decision(PERIOD_D1,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_M5_D1_M15_WITH_H4_OR_H1);
    ElliotDirectionAlignmentDecision legacy(PERIOD_D1);
    for (int i = 0; i < 32; i++) {
        bool isBuy = (i & 16) != 0;
        string direction = "SELL";
        if (isBuy) {
            direction = "BUY";
        }
        for (int j = 0; j < ArraySize(timeFrames); j++) {
            elliotAll.getElliot(timeFrames[j]).isBuy = (i & (1 << j)) != 0;
            setD1TestEma(elliotAll.getElliot(timeFrames[j]), isBuy, !isBuy, direction);
        }

        // bit順はD1・H4・H1・M15・M5。全一致とH4/H1片方不一致だけを許可。
        TrendAlignType expected = trendAlignNone;
        TrendAlignType legacyExpected = trendAlignNone;
        if (i == 0 || i == 2 || i == 4) {
            expected = trendAlignSell;
        } else if (i == 27 || i == 29 || i == 31) {
            expected = trendAlignBuy;
        }
        if (i == 0) {
            legacyExpected = trendAlignSell;
        } else if (i == 31) {
            legacyExpected = trendAlignBuy;
        }

        string caseName = "M5 OR mask=" + IntegerToString(i);
        assertD1EmaObjectAlignment(caseName, decision, elliotAll,
            PERIOD_M5, true, expected);
        assertD1EmaObjectAlignment(caseName + " legacy", legacy, elliotAll,
            PERIOD_M5, true, legacyExpected);

        // MN1・W1の分析方向とEMA方向は抽出条件に含めない。
        elliotAll.getElliot(PERIOD_MN1).isBuy = !isBuy;
        elliotAll.getElliot(PERIOD_W1).isBuy = !isBuy;
        string oppositeLabel = "BUY";
        if (isBuy) {
            oppositeLabel = "SELL";
        }
        setD1TestEma(elliotAll.getElliot(PERIOD_MN1), !isBuy, isBuy, oppositeLabel);
        setD1TestEma(elliotAll.getElliot(PERIOD_W1), !isBuy, isBuy, oppositeLabel);
        assertD1EmaObjectAlignment(caseName + " upper EMA optional", decision,
            elliotAll, PERIOD_M5, true, expected);
    }

    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = elliotAll.getElliot(timeFrames[i]);
        elliot.marketContext.timeFrame = PERIOD_M30;
        assertD1EmaObjectAlignment("M5 OR missing " + EnumToString(timeFrames[i]),
            decision, elliotAll, PERIOD_M5, false, trendAlignNone);
        elliot.marketContext.timeFrame = timeFrames[i];
    }
    elliotAll.isAnalysisSucceeded = false;
    assertD1EmaObjectAlignment("M5 OR incomplete", decision, elliotAll,
        PERIOD_M5, false, trendAlignNone);
    elliotAll.isAnalysisSucceeded = true;
    assertD1EmaObjectAlignment("M5 OR null", decision, NULL,
        PERIOD_M5, false, trendAlignNone);
    assertD1EmaObjectAlignment("M5 OR restored", decision, elliotAll,
        PERIOD_M5, true, trendAlignBuy);

    ENUM_TIMEFRAMES otherTimeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M1
    };
    for (int i = 0; i < ArraySize(otherTimeFrames); i++) {
        assertD1EmaObjectAlignment("M5 OR rejects " + EnumToString(otherTimeFrames[i]),
            decision, elliotAll, otherTimeFrames[i], false, trendAlignNone);
    }
    ElliotDirectionAlignmentDecision invalidStart(PERIOD_H4,
        ELLIOT_DIRECTION_ALIGNMENT_RULE_M5_D1_M15_WITH_H4_OR_H1);
    assertD1EmaObjectAlignment("M5 OR invalid start", invalidStart, elliotAll,
        PERIOD_M5, false, trendAlignNone);
    delete elliotAll;
}

/**
 * M5の5足EMA全方向組合せと、各足のNONE・不整合をBUY/SELL両方向で確認する。
 */
void validateM5Ema200Required() {
    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
    };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        TrendAlignType expected = trendAlignSell;
        if (isBuy) {
            expected = trendAlignBuy;
        }
        string direction = convertAlignTypeText(expected);
        string oppositeLabel = "BUY";
        if (isBuy) {
            oppositeLabel = "SELL";
        }
        ElliotAll *elliotAll = createD1EmaFilterFixture(isBuy);
        assertD1EmaCondition(elliotAll != NULL, direction + " EMA5 fixture");
        if (elliotAll == NULL) {
            continue;
        }
        ElliotDirectionAlignmentDecision decision(PERIOD_D1,
            ELLIOT_DIRECTION_ALIGNMENT_RULE_M5_D1_M15_WITH_H4_OR_H1);
        ElliotDirectionAlignmentDecision legacy(PERIOD_D1);

        for (int j = 0; j < 32; j++) {
            for (int k = 0; k < ArraySize(timeFrames); k++) {
                bool isEmaBuy = (j & (1 << k)) != 0;
                string emaLabel = "SELL";
                if (isEmaBuy) {
                    emaLabel = "BUY";
                }
                setD1TestEma(elliotAll.getElliot(timeFrames[k]),
                    isEmaBuy, !isEmaBuy, emaLabel);
            }
            TrendAlignType emaExpected = trendAlignNone;
            if ((isBuy && j == 31) || (!isBuy && j == 0)) {
                emaExpected = expected;
            }
            string caseName = direction + " EMA5 mask=" + IntegerToString(j);
            assertD1EmaObjectAlignment(caseName, decision, elliotAll,
                PERIOD_M5, true, emaExpected);
            assertD1EmaObjectAlignment(caseName + " legacy unchanged", legacy,
                elliotAll, PERIOD_M5, true, expected);
        }

        for (int j = 0; j < ArraySize(timeFrames); j++) {
            setD1TestEma(elliotAll.getElliot(timeFrames[j]), isBuy, !isBuy, direction);
        }
        for (int j = 0; j < ArraySize(timeFrames); j++) {
            Elliot *elliot = elliotAll.getElliot(timeFrames[j]);
            string caseName = direction + " EMA5 " + EnumToString(timeFrames[j]);
            setD1TestEma(elliot, false, false, "NONE");
            assertD1EmaObjectAlignment(caseName + " NONE", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            setD1TestEma(elliot, true, true, direction);
            assertD1EmaObjectAlignment(caseName + " conflicting flags", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            setD1TestEma(elliot, false, false, direction);
            assertD1EmaObjectAlignment(caseName + " label without flag", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            setD1TestEma(elliot, isBuy, !isBuy, oppositeLabel);
            assertD1EmaObjectAlignment(caseName + " stale opposite label", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            setD1TestEma(elliot, isBuy, !isBuy, "NONE");
            assertD1EmaObjectAlignment(caseName + " stale NONE label", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            setD1TestEma(elliot, isBuy, !isBuy, direction);
            elliot.oscillator.marketContext.timeFrame = PERIOD_M30;
            assertD1EmaObjectAlignment(caseName + " oscillator timeframe", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            elliot.oscillator.marketContext.timeFrame = timeFrames[j];
            elliot.oscillator.ema200.marketContext.timeFrame = PERIOD_M30;
            assertD1EmaObjectAlignment(caseName + " EMA timeframe", decision,
                elliotAll, PERIOD_M5, true, trendAlignNone);
            elliot.oscillator.ema200.marketContext.timeFrame = timeFrames[j];
            assertD1EmaObjectAlignment(caseName + " restored", decision,
                elliotAll, PERIOD_M5, true, expected);
        }
        delete elliotAll;
    }
}

/**
 * Smokeテストを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateBuyCases();
    validateSellCases();
    validateInvalidEmaCases();
    validateH4BuyCases();
    validateH4SellCases();
    validateH4InvalidEmaCases();
    validateH1BuyCases();
    validateH1SellCases();
    validateH1InvalidEmaCases();
    validateH1D1W1WithH4OrH1Cases();
    validateH1D1Mn1W1WithH4OrH1Cases();
    validateH1D1W1WithMn1OrEmaAndH4OrH1Cases();
    validateH1BuyRunnerUpCases();
    validateH1SellRunnerUpCases();
    validateH1RunnerUpInvalidEmaCases();
    validateAlignmentRuleValues();
    validateIndependentViewTimeFrames();
    validateD1EmaRequiredModes();
    validateD1EmaOtherTimeFrames();
    validateD1EmaRankIndependence();
    validateH1D1ConditionCombinations();
    validateH1D1ConditionScope();
    validateH1D1RunnerUpGate();
    validateM5D1M15WithH4OrH1();
    validateM5Ema200Required();

    if (gFailureCount == 0) {
        Print("ElliotDirectionAlignmentDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "ElliotDirectionAlignmentDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
