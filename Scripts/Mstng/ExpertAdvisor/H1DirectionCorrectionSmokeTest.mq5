//+------------------------------------------------------------------+
//|                              H1DirectionCorrectionSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property version "1.00"

#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>

/**
 * 補正前の実測方向を持つH1またはM15までの分析を作成する。
 *
 * @return テスト呼び出し側が所有する分析。
 */
ElliotAll *createAnalysis(const bool fromIsBuy, const bool fromD1Matched,
        const bool fromH4Matched, const bool fromCorrected,
        const ENUM_TIMEFRAMES fromTimeFrame = PERIOD_H1,
        const bool fromH1Matched = true) {
    ElliotAll *analysis = new ElliotAll("EURUSD", fromTimeFrame);
    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    int timeFrameCount = 5;
    if (fromTimeFrame == PERIOD_M15) {
        timeFrameCount = 6;
    }
    for (int i = 0; i < timeFrameCount; i++) {
        Elliot *elliot = new Elliot("EURUSD", timeFrames[i]);
        bool originalIsBuy = fromIsBuy;
        if ((timeFrames[i] == PERIOD_D1 && !fromD1Matched)
                || (timeFrames[i] == PERIOD_H4 && !fromH4Matched)
                || (timeFrames[i] == PERIOD_H1 && !fromH1Matched)) {
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
    analysis.elliotCurrent = analysis.getElliot(fromTimeFrame);
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
 * BUY・SELLのH1用D1/H4、M15用D1/H4/H1全組み合わせと補正足の限定を確認する。
 */
bool validateDirectionMatrix(const ENUM_TIMEFRAMES fromTimeFrame) {
    bool isSucceeded = true;
    int combinationCount = 4;
    if (fromTimeFrame == PERIOD_M15) {
        combinationCount = 8;
    }
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < combinationCount; j++) {
            bool isBuy = i == 0;
            bool isD1Matched = (j & 1) != 0;
            bool isH4Matched = (j & 2) != 0;
            bool isH1Matched = fromTimeFrame == PERIOD_H1 || (j & 4) != 0;
            ElliotAll *original = createAnalysis(isBuy, isD1Matched, isH4Matched,
                false, fromTimeFrame, isH1Matched);
            ElliotAll *selected = createAnalysis(isBuy, isD1Matched, isH4Matched,
                true, fromTimeFrame, isH1Matched);
            if (!checkDirection("original", original, NULL, PERIOD_CURRENT,
                    isD1Matched && isH4Matched && isH1Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("D1 explicit correction", selected, original, PERIOD_D1,
                    !isD1Matched && isH4Matched && isH1Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("H4 explicit correction", selected, original, PERIOD_H4,
                    isD1Matched && !isH4Matched && isH1Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("missing correction metadata", selected, NULL, PERIOD_CURRENT,
                    isD1Matched && isH4Matched && isH1Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("H1 explicit correction", selected, original, PERIOD_H1,
                    fromTimeFrame == PERIOD_M15 && isD1Matched && isH4Matched && !isH1Matched)) {
                isSucceeded = false;
            }
            if (!checkDirection("current M15 correction prohibited", selected, original, PERIOD_M15, false)) {
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
bool validateInvalidInputs(const ENUM_TIMEFRAMES fromTimeFrame) {
    bool isSucceeded = true;
    int correctionCount = 2;
    if (fromTimeFrame == PERIOD_M15) {
        correctionCount = 3;
    }
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < correctionCount; j++) {
            bool isBuy = i == 0;
            bool isD1Matched = j != 0;
            bool isH4Matched = j != 1;
            bool isH1Matched = j != 2;
            ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_D1;
            if (!isH4Matched) {
                correctionTimeFrame = PERIOD_H4;
            } else if (!isH1Matched) {
                correctionTimeFrame = PERIOD_H1;
            }
            ElliotAll *original = createAnalysis(isBuy, isD1Matched, isH4Matched,
                false, fromTimeFrame, isH1Matched);
            ElliotAll *selected = createAnalysis(isBuy, isD1Matched, isH4Matched,
                true, fromTimeFrame, isH1Matched);
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
 * M15の方向・参照・元分析の現在足が不整合な入力を除外する。
 */
bool validateM15CurrentContext(const ENUM_TIMEFRAMES fromCorrectionTimeFrame) {
    bool isSucceeded = true;
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        ElliotAll *original = createAnalysis(isBuy, fromCorrectionTimeFrame != PERIOD_D1,
            fromCorrectionTimeFrame != PERIOD_H4, false, PERIOD_M15,
            fromCorrectionTimeFrame != PERIOD_H1);
        ElliotAll *selected = createAnalysis(isBuy, fromCorrectionTimeFrame != PERIOD_D1,
            fromCorrectionTimeFrame != PERIOD_H4, true, PERIOD_M15,
            fromCorrectionTimeFrame != PERIOD_H1);
        Elliot *selectedM15 = selected.getElliot(PERIOD_M15);
        Elliot *originalM15 = original.getElliot(PERIOD_M15);
        selectedM15.isBuy = !isBuy;
        selectedM15.oscillator.isBuy = !isBuy;
        selectedM15.buySellLabel = Constant::getBuySell(!isBuy);
        if (!checkDirection("M15 direction mismatch", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        selectedM15.isBuy = isBuy;
        selectedM15.oscillator.isBuy = isBuy;
        selectedM15.buySellLabel = "INVALID";
        if (!checkDirection("M15 invalid direction label", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        selectedM15.buySellLabel = Constant::getBuySell(isBuy);
        selected.elliotCurrent = selected.getElliot(PERIOD_H1);
        if (!checkDirection("M15 wrong current reference", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        selected.elliotCurrent = selectedM15;
        selectedM15.marketContext.symbolName = "USDJPY";
        if (!checkDirection("M15 wrong symbol", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        selectedM15.marketContext.symbolName = "EURUSD";
        original.elliotCurrent = original.getElliot(PERIOD_H1);
        if (!checkDirection("M15 wrong original current", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        original.elliotCurrent = originalM15;
        original.marketContext.timeFrame = PERIOD_H1;
        if (!checkDirection("M15 wrong original context", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        original.marketContext.timeFrame = PERIOD_M15;
        originalM15.isBuy = !isBuy;
        originalM15.oscillator.isBuy = !isBuy;
        originalM15.buySellLabel = Constant::getBuySell(!isBuy);
        if (!checkDirection("M15 original direction mismatch", selected, original, fromCorrectionTimeFrame, false)) {
            isSucceeded = false;
        }
        originalM15.isBuy = isBuy;
        originalM15.oscillator.isBuy = isBuy;
        originalM15.buySellLabel = Constant::getBuySell(isBuy);
        if (!checkDirection("M15 restored current context", selected, original, fromCorrectionTimeFrame, true)) {
            isSucceeded = false;
        }
        delete selected;
        delete original;
    }
    return isSucceeded;
}

/**
 * 市場履歴を使わず、方向補正の限定許可と通常判定の厳格性を検証する。
 */
void OnStart() {
    bool isMatrixSucceeded = validateDirectionMatrix(PERIOD_H1);
    bool isInvalidSucceeded = validateInvalidInputs(PERIOD_H1);
    bool isM15MatrixSucceeded = validateDirectionMatrix(PERIOD_M15);
    bool isM15InvalidSucceeded = validateInvalidInputs(PERIOD_M15);
    bool isM15D1CurrentSucceeded = validateM15CurrentContext(PERIOD_D1);
    bool isM15H4CurrentSucceeded = validateM15CurrentContext(PERIOD_H4);
    bool isM15H1CurrentSucceeded = validateM15CurrentContext(PERIOD_H1);
    if (isMatrixSucceeded && isInvalidSucceeded && isM15MatrixSucceeded
            && isM15InvalidSucceeded && isM15D1CurrentSucceeded
            && isM15H4CurrentSucceeded && isM15H1CurrentSucceeded) {
        Print("PASS H1DirectionCorrectionSmokeTest");
    } else {
        Print("FAIL H1DirectionCorrectionSmokeTest");
    }
}
