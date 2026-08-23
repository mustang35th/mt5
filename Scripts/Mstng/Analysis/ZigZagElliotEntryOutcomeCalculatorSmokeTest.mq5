//+------------------------------------------------------------------+
//|           ZigZagElliotEntryOutcomeCalculatorSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Analysis\ZigZagElliotEntryHistoryValidator.mqh>
#include <Mstng\Analysis\ZigZagElliotEntryOutcomeCalculator.mqh>

/** テスト用の1pip価格幅。 */
const double testPipSize = 0.0001;

/** テスト用の1point価格幅。 */
const double testPoint = 0.00001;

/**
 * テスト用M1バーを生成する。
 *
 * @param fromTime バー開始時刻。
 * @param fromOpen 始値。
 * @param fromHigh 高値。
 * @param fromLow 安値。
 * @param fromClose 終値。
 * @param fromSpreadPoints spread points。
 * @return 生成したM1バー。
 */
MqlRates createRate(
    const datetime fromTime,
    const double fromOpen,
    const double fromHigh,
    const double fromLow,
    const double fromClose,
    const int fromSpreadPoints
) {
    MqlRates rate;
    ZeroMemory(rate);
    rate.time = fromTime;
    rate.open = fromOpen;
    rate.high = fromHigh;
    rate.low = fromLow;
    rate.close = fromClose;
    rate.spread = fromSpreadPoints;

    return rate;
}

/**
 * tick volumeを持つテスト用バーを生成する。
 *
 * @param fromTime バー開始時刻。
 * @param fromOpen 始値。
 * @param fromHigh 高値。
 * @param fromLow 安値。
 * @param fromClose 終値。
 * @param fromTickVolume tick volume。
 * @return 生成したバー。
 */
MqlRates createRateWithVolume(
    const datetime fromTime,
    const double fromOpen,
    const double fromHigh,
    const double fromLow,
    const double fromClose,
    const long fromTickVolume
) {
    MqlRates rate = createRate(
        fromTime,
        fromOpen,
        fromHigh,
        fromLow,
        fromClose,
        10
    );
    rate.tick_volume = fromTickVolume;

    return rate;
}

/**
 * double値を許容誤差付きで照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromFieldName 項目名。
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool assertDouble(
    const string fromCaseName,
    const string fromFieldName,
    const double fromActual,
    const double fromExpected
) {
    if (MathAbs(fromActual - fromExpected) <= 0.00000001) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%.10f expected=%.10f",
        fromCaseName,
        fromFieldName,
        fromActual,
        fromExpected
    );

    return false;
}

/**
 * 文字列値を照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromFieldName 項目名。
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool assertText(
    const string fromCaseName,
    const string fromFieldName,
    const string fromActual,
    const string fromExpected
) {
    if (fromActual == fromExpected) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%s expected=%s",
        fromCaseName,
        fromFieldName,
        fromActual,
        fromExpected
    );

    return false;
}

/**
 * 文字列に期待する部分文字列が含まれるか確認する。
 *
 * @param fromCaseName ケース名。
 * @param fromFieldName 項目名。
 * @param fromActual 実値。
 * @param fromExpectedPart 期待する部分文字列。
 * @return 含まれる場合true。
 */
bool assertTextContains(
    const string fromCaseName,
    const string fromFieldName,
    const string fromActual,
    const string fromExpectedPart
) {
    if (StringFind(fromActual, fromExpectedPart) >= 0) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%s expectedPart=%s",
        fromCaseName,
        fromFieldName,
        fromActual,
        fromExpectedPart
    );

    return false;
}

/**
 * 整数値を照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromFieldName 項目名。
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool assertInteger(
    const string fromCaseName,
    const string fromFieldName,
    const int fromActual,
    const int fromExpected
) {
    if (fromActual == fromExpected) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%d expected=%d",
        fromCaseName,
        fromFieldName,
        fromActual,
        fromExpected
    );

    return false;
}

/**
 * bool値を照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromFieldName 項目名。
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool assertBoolean(
    const string fromCaseName,
    const string fromFieldName,
    const bool fromActual,
    const bool fromExpected
) {
    if (fromActual == fromExpected) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%s expected=%s",
        fromCaseName,
        fromFieldName,
        (string)fromActual,
        (string)fromExpected
    );

    return false;
}

/**
 * BUYが期間終了まで保有されるケースを検証する。
 *
 * @return 期待値と一致する場合true。
 */
bool validateBuyHorizon() {
    string caseName = "BUY horizon";
    MqlRates rates[2];
    rates[0] = createRate(
        D'2026.01.05 00:00:00',
        1.1000,
        1.1020,
        1.0990,
        1.1010,
        0
    );
    rates[1] = createRate(
        D'2026.01.05 00:01:00',
        1.1010,
        1.1030,
        1.1000,
        1.1025,
        10
    );
    ZigZagElliotEntryOutcomeResult result;
    bool isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "BUY",
        1.1000,
        1.0900,
        testPipSize,
        testPoint,
        D'2026.01.05 00:00:00',
        D'2026.01.05 00:02:00',
        rates,
        result
    );
    bool isMatched = isCalculated;

    if (!isCalculated) {
        Print("FAIL " + caseName + " calculate status=" + result.dataStatus);
    }
    if (!assertText(caseName, "dataStatus", result.dataStatus, "READY")) {
        isMatched = false;
    }
    if (!assertText(caseName, "exitReason", result.exitReason, "HORIZON")) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "riskPips", result.riskPips, 100.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "mfePips", result.mfePips, 30.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "maePips", result.maePips, 10.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitPips", result.profitPips, 25.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitR", result.profitR, 0.25)) {
        isMatched = false;
    }
    if (!assertInteger(caseName, "barsHeldM1", result.barsHeldM1, 2)) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "zeroSpreadBarCount",
            result.zeroSpreadBarCount,
            0
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "exitBarOrderUnknown",
            result.exitBarOrderUnknown,
            false
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * SELLがspread込みAsk価格で評価されるケースを検証する。
 *
 * @return 期待値と一致する場合true。
 */
bool validateSellSpread() {
    string caseName = "SELL spread";
    MqlRates rates[1];
    rates[0] = createRate(
        D'2026.01.05 01:00:00',
        1.1999,
        1.2004,
        1.1979,
        1.1989,
        10
    );
    ZigZagElliotEntryOutcomeResult result;
    bool isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "SELL",
        1.2000,
        1.2100,
        testPipSize,
        testPoint,
        D'2026.01.05 01:00:00',
        D'2026.01.05 01:01:00',
        rates,
        result
    );
    bool isMatched = isCalculated;

    if (!isCalculated) {
        Print("FAIL " + caseName + " calculate status=" + result.dataStatus);
    }
    if (!assertDouble(caseName, "exitPrice", result.exitPrice, 1.1990)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "mfePips", result.mfePips, 20.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "maePips", result.maePips, 5.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitPips", result.profitPips, 10.0)) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * SL到達バーの有利側極値をMFEへ含めないことを検証する。
 *
 * @return 期待値と一致する場合true。
 */
bool validateStopLossConservative() {
    string caseName = "SL conservative";
    MqlRates rates[2];
    rates[0] = createRate(
        D'2026.01.05 02:00:00',
        1.1000,
        1.1020,
        1.0990,
        1.1010,
        10
    );
    rates[1] = createRate(
        D'2026.01.05 02:01:00',
        1.1010,
        1.1100,
        1.0940,
        1.0960,
        10
    );
    ZigZagElliotEntryOutcomeResult result;
    bool isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "BUY",
        1.1000,
        1.0950,
        testPipSize,
        testPoint,
        D'2026.01.05 02:00:00',
        D'2026.01.05 02:02:00',
        rates,
        result
    );
    bool isMatched = isCalculated;

    if (!isCalculated) {
        Print("FAIL " + caseName + " calculate status=" + result.dataStatus);
    }
    if (!assertText(caseName, "exitReason", result.exitReason, "INITIAL_SL")) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "exitPrice", result.exitPrice, 1.0950)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "mfePips", result.mfePips, 20.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "maePips", result.maePips, 50.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitR", result.profitR, -1.0)) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "exitBarOrderUnknown",
            result.exitBarOrderUnknown,
            true
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 初期SLを越えるgapでは始値で悪化決済することを検証する。
 *
 * @return 期待値と一致する場合true。
 */
bool validateGapStopLoss() {
    string caseName = "gap stop loss";
    MqlRates rates[1];
    rates[0] = createRate(
        D'2026.01.05 03:00:00',
        1.0930,
        1.0940,
        1.0920,
        1.0935,
        10
    );
    ZigZagElliotEntryOutcomeResult result;
    bool isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "BUY",
        1.1000,
        1.0950,
        testPipSize,
        testPoint,
        D'2026.01.05 03:00:00',
        D'2026.01.05 03:01:00',
        rates,
        result
    );
    bool isMatched = isCalculated;

    if (!isCalculated) {
        Print("FAIL " + caseName + " calculate status=" + result.dataStatus);
    }
    if (!assertDouble(caseName, "exitPrice", result.exitPrice, 1.0930)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "maePips", result.maePips, 70.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitPips", result.profitPips, -70.0)) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "profitR", result.profitR, -1.4)) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "exitBarOrderUnknown",
            result.exitBarOrderUnknown,
            false
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 無ティック分があるM1でもH1集計が一致すれば受理することを検証する。
 *
 * @return 完全な履歴として受理される場合true。
 */
bool validateSparseM1Coverage() {
    string caseName = "sparse M1 coverage";
    MqlRates h1Rates[1];
    h1Rates[0] = createRateWithVolume(
        D'2026.01.05 06:00:00',
        1.1000,
        1.1050,
        1.0990,
        1.1040,
        12
    );
    MqlRates m1Rates[3];
    m1Rates[0] = createRateWithVolume(
        D'2026.01.05 06:00:00',
        1.1000,
        1.1010,
        1.0990,
        1.1005,
        3
    );
    m1Rates[1] = createRateWithVolume(
        D'2026.01.05 06:17:00',
        1.1005,
        1.1050,
        1.1000,
        1.1045,
        5
    );
    m1Rates[2] = createRateWithVolume(
        D'2026.01.05 06:59:00',
        1.1045,
        1.1048,
        1.1030,
        1.1040,
        4
    );
    ZigZagElliotEntryHistoryValidationResult result;
    bool isValid = ZigZagElliotEntryHistoryValidator::validate(
        h1Rates,
        1,
        m1Rates,
        testPoint,
        result
    );
    bool isMatched = isValid;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "READY"
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * OHLCが一致してもM1のvolume不足を拒否することを検証する。
 *
 * @return 不完全履歴として拒否される場合true。
 */
bool validateM1VolumeMismatch() {
    string caseName = "M1 volume mismatch";
    MqlRates h1Rates[1];
    h1Rates[0] = createRateWithVolume(
        D'2026.01.05 07:00:00',
        1.1000,
        1.1050,
        1.0990,
        1.1040,
        13
    );
    MqlRates m1Rates[3];
    m1Rates[0] = createRateWithVolume(
        D'2026.01.05 07:00:00',
        1.1000,
        1.1010,
        1.0990,
        1.1005,
        3
    );
    m1Rates[1] = createRateWithVolume(
        D'2026.01.05 07:17:00',
        1.1005,
        1.1050,
        1.1000,
        1.1045,
        5
    );
    m1Rates[2] = createRateWithVolume(
        D'2026.01.05 07:59:00',
        1.1045,
        1.1048,
        1.1030,
        1.1040,
        4
    );
    ZigZagElliotEntryHistoryValidationResult result;
    bool isValid = ZigZagElliotEntryHistoryValidator::validate(
        h1Rates,
        1,
        m1Rates,
        testPoint,
        result
    );
    bool isMatched = !isValid;

    if (isValid) {
        Print("FAIL " + caseName + " unexpectedly valid");
    }
    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "HISTORY_PARTIAL"
        )) {
        isMatched = false;
    }
    if (!assertTextContains(
            caseName,
            "calculationNote",
            result.calculationNote,
            "M1_H1_VOLUME_MISMATCH"
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * H1間の週末ギャップを許容することを検証する。
 *
 * @return 完全な履歴として受理される場合true。
 */
bool validateWeekendM1Coverage() {
    string caseName = "weekend M1 coverage";
    MqlRates h1Rates[2];
    h1Rates[0] = createRateWithVolume(
        D'2026.01.09 23:00:00',
        1.1000,
        1.1020,
        1.0990,
        1.1010,
        5
    );
    h1Rates[1] = createRateWithVolume(
        D'2026.01.12 00:00:00',
        1.1030,
        1.1050,
        1.1020,
        1.1040,
        7
    );
    MqlRates m1Rates[4];
    m1Rates[0] = createRateWithVolume(
        D'2026.01.09 23:00:00',
        1.1000,
        1.1010,
        1.0990,
        1.1005,
        2
    );
    m1Rates[1] = createRateWithVolume(
        D'2026.01.09 23:59:00',
        1.1005,
        1.1020,
        1.1000,
        1.1010,
        3
    );
    m1Rates[2] = createRateWithVolume(
        D'2026.01.12 00:01:00',
        1.1030,
        1.1040,
        1.1020,
        1.1035,
        4
    );
    m1Rates[3] = createRateWithVolume(
        D'2026.01.12 00:58:00',
        1.1035,
        1.1050,
        1.1030,
        1.1040,
        3
    );
    ZigZagElliotEntryHistoryValidationResult result;
    bool isValid = ZigZagElliotEntryHistoryValidator::validate(
        h1Rates,
        2,
        m1Rates,
        testPoint,
        result
    );
    bool isMatched = isValid;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "READY"
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 不正OHLCと時刻逆転をfail-closedにすることを検証する。
 *
 * @return すべて拒否される場合true。
 */
bool validateInvalidInput() {
    bool isMatched = true;
    MqlRates invalidOhlcRates[1];
    invalidOhlcRates[0] = createRate(
        D'2026.01.05 04:00:00',
        1.1000,
        1.0990,
        1.0980,
        1.1000,
        10
    );
    ZigZagElliotEntryOutcomeResult result;
    bool isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "BUY",
        1.1000,
        1.0950,
        testPipSize,
        testPoint,
        D'2026.01.05 04:00:00',
        D'2026.01.05 04:01:00',
        invalidOhlcRates,
        result
    );

    if (isCalculated) {
        Print("FAIL invalid OHLC unexpectedly calculated");
        isMatched = false;
    }
    if (!assertText(
            "invalid OHLC",
            "dataStatus",
            result.dataStatus,
            "INVALID_RATE_OHLC"
        )) {
        isMatched = false;
    }

    MqlRates reversedRates[2];
    reversedRates[0] = createRate(
        D'2026.01.05 05:01:00',
        1.1000,
        1.1010,
        1.0990,
        1.1000,
        10
    );
    reversedRates[1] = createRate(
        D'2026.01.05 05:00:00',
        1.1000,
        1.1010,
        1.0990,
        1.1000,
        10
    );
    isCalculated = ZigZagElliotEntryOutcomeCalculator::calculate(
        "BUY",
        1.1000,
        1.0950,
        testPipSize,
        testPoint,
        D'2026.01.05 05:00:00',
        D'2026.01.05 05:02:00',
        reversedRates,
        result
    );

    if (isCalculated) {
        Print("FAIL reversed time unexpectedly calculated");
        isMatched = false;
    }
    if (!assertText(
            "reversed time",
            "dataStatus",
            result.dataStatus,
            "INVALID_RATE_TIME_ORDER"
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * エントリー結果計算の正常系、SLおよび不正入力を検証する。
 */
void OnStart() {
    int failureCount = 0;

    if (!validateBuyHorizon()) {
        failureCount++;
    }
    if (!validateSellSpread()) {
        failureCount++;
    }
    if (!validateStopLossConservative()) {
        failureCount++;
    }
    if (!validateGapStopLoss()) {
        failureCount++;
    }
    if (!validateSparseM1Coverage()) {
        failureCount++;
    }
    if (!validateM1VolumeMismatch()) {
        failureCount++;
    }
    if (!validateWeekendM1Coverage()) {
        failureCount++;
    }
    if (!validateInvalidInput()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("ZigZagElliotEntryOutcomeCalculatorSmokeTest PASS");

        return;
    }

    PrintFormat(
        "ZigZagElliotEntryOutcomeCalculatorSmokeTest FAIL count=%d",
        failureCount
    );
}
