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
 * 内部判定ルールのenum値が既存互換であることを検証する。
 */
void validateAlignmentRuleValues() {
    bool isMatched =
        (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES == 0
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200 == 1
        && (int)ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200 == 2;

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
    validateH1BuyCases();
    validateH1SellCases();
    validateH1InvalidEmaCases();
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
