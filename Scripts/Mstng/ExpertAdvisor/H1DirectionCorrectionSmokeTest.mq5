//+------------------------------------------------------------------+
//|                              H1DirectionCorrectionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property version "1.00"

#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>

/**
 * 補正前の実測方向を持つ5足の分析を作成する。
 *
 * @return テスト呼び出し側が所有する分析。
 */
ElliotAll *createAnalysis(const bool fromIsBuy, const bool fromD1Matched,
        const bool fromH4Matched, const bool fromCorrected) {
    ElliotAll *analysis = new ElliotAll("EURUSD", PERIOD_H1);
    ENUM_TIMEFRAMES timeFrames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1};
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = new Elliot("EURUSD", timeFrames[i]);
        bool originalIsBuy = fromIsBuy;
        if ((timeFrames[i] == PERIOD_D1 && !fromD1Matched)
                || (timeFrames[i] == PERIOD_H4 && !fromH4Matched)) {
            originalIsBuy = !fromIsBuy;
        }
        elliot.oscillator.isBuy = originalIsBuy;
        elliot.isBuy = originalIsBuy;
        if (fromCorrected) {
            elliot.isBuy = fromIsBuy;
        }
        elliot.buySellLabel = Constant::getBuySell(elliot.isBuy);
        elliot.oscillator.ema200.isBuy = fromIsBuy;
        elliot.oscillator.ema200.isSell = !fromIsBuy;
        elliot.oscillator.ema200.buySellLabel = Constant::getBuySell(fromIsBuy);
        analysis.elliotList.Add(elliot);
    }
    analysis.elliotCurrent = analysis.getElliot(PERIOD_H1);
    analysis.isAnalysisSucceeded = true;
    return analysis;
}

/**
 * 明示補正を含む方向判定の通過結果を照合する。
 */
bool checkDirection(const string fromName, ElliotAll *fromSelected,
        ElliotAll *fromOriginal, const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromExpected) {
    H1DirectionAlignmentDecision decision;
    H1DirectionAlignmentResult result;
    bool actual = decision.evaluate(Mtf3In3H1Policy::getDirectionAlignmentMode(),
        fromSelected, result, fromOriginal, fromTimeFrame);
    if (actual != fromExpected || result.isPassed != fromExpected) {
        PrintFormat("FAIL %s actual=%s expected=%s state=%s", fromName,
            (string)actual, (string)fromExpected, result.state);
        return false;
    }
    return true;
}

/**
 * BUY・SELLのD1/H4全組み合わせと、指定された補正足だけの許容を確認する。
 */
bool validateDirectionMatrix() {
    bool isSucceeded = true;
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 4; j++) {
            bool isBuy = i == 0;
            bool isD1Matched = (j & 1) != 0;
            bool isH4Matched = (j & 2) != 0;
            ElliotAll *original = createAnalysis(isBuy, isD1Matched, isH4Matched, false);
            ElliotAll *selected = createAnalysis(isBuy, isD1Matched, isH4Matched, true);
            if (!checkDirection("original", original, NULL, PERIOD_CURRENT,
                    isD1Matched && isH4Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("D1 explicit correction", selected, original, PERIOD_D1,
                    !isD1Matched && isH4Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("H4 explicit correction", selected, original, PERIOD_H4,
                    isD1Matched && !isH4Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("missing correction metadata", selected, NULL, PERIOD_CURRENT,
                    isD1Matched && isH4Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("wrong correction timeframe", selected, original, PERIOD_H1, false)) {
                isSucceeded = false;
            }
            delete selected;
            delete original;
        }
    }
    return isSucceeded;
}

/**
 * 元方向不正、実測方向改変、補正足以外の変更および上位条件未達を除外する。
 */
bool validateInvalidInputs() {
    bool isSucceeded = true;
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            bool isBuy = i == 0;
            bool isD1Matched = j == 1;
            bool isH4Matched = j == 0;
            ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_D1;
            if (isD1Matched) {
                correctionTimeFrame = PERIOD_H4;
            }
            ElliotAll *original = createAnalysis(isBuy, isD1Matched, isH4Matched, false);
            ElliotAll *selected = createAnalysis(isBuy, isD1Matched, isH4Matched, true);
            Elliot *target = selected.getElliot(correctionTimeFrame);
            Elliot *originalTarget = original.getElliot(correctionTimeFrame);
            if (!checkDirection("missing original", selected, NULL, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            if (!checkDirection("missing selection", NULL, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            originalTarget.buySellLabel = "INVALID";
            if (!checkDirection("invalid original", selected, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            originalTarget.buySellLabel = Constant::getBuySell(originalTarget.isBuy);
            target.oscillator.isBuy = isBuy;
            if (!checkDirection("changed raw oscillator", selected, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            target.oscillator.isBuy = !isBuy;
            target.buySellLabel = Constant::getBuySell(!isBuy);
            if (!checkDirection("invalid corrected label", selected, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            target.buySellLabel = Constant::getBuySell(isBuy);
            Elliot *selectedW1 = selected.getElliot(PERIOD_W1);
            selectedW1.isBuy = !isBuy;
            selectedW1.oscillator.isBuy = !isBuy;
            selectedW1.buySellLabel = Constant::getBuySell(!isBuy);
            if (!checkDirection("changed unrelated timeframe", selected, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            selectedW1.isBuy = isBuy;
            selectedW1.oscillator.isBuy = isBuy;
            selectedW1.buySellLabel = Constant::getBuySell(isBuy);
            selectedW1.oscillator.ema200.buySellLabel = "INVALID";
            if (!checkDirection("W1 EMA invalid", selected, original, correctionTimeFrame, false)) {
                isSucceeded = false;
            }
            selectedW1.oscillator.ema200.buySellLabel = Constant::getBuySell(isBuy);
            if (!checkDirection("restored", selected, original, correctionTimeFrame, true)) {
                isSucceeded = false;
            }
            delete selected;
            delete original;
        }
    }
    return isSucceeded;
}

/**
 * 市場履歴を使わず、方向補正の限定許可と通常判定の厳格性を検証する。
 */
void OnStart() {
    bool isMatrixSucceeded = validateDirectionMatrix();
    bool isInvalidSucceeded = validateInvalidInputs();
    if (isMatrixSucceeded && isInvalidSucceeded) {
        Print("PASS H1DirectionCorrectionSmokeTest");
    } else {
        Print("FAIL H1DirectionCorrectionSmokeTest");
    }
}
