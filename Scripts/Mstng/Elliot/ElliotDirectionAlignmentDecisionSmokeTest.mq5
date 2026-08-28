//+------------------------------------------------------------------+
//|                    ElliotDirectionAlignmentDecisionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

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
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_MN1_OR_EMA_AND_H4_OR_H1 == 6;

    if (isMatched) {
        return;
    }

    gFailureCount++;
    Print("FAIL ALIGNMENT RULE ENUM VALUES");
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

    if (gFailureCount == 0) {
        Print("ElliotDirectionAlignmentDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "ElliotDirectionAlignmentDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
