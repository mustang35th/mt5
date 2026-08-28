//+------------------------------------------------------------------+
//|        ZigZagElliotH1StudyOutcomeCalculatorSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Analysis\ZigZagElliotH1StudyOutcomeCalculator.mqh>

/** テスト用の1pip価格幅。 */
const double testPipSize = 0.0001;

/** テスト用のエントリー価格。 */
const double testEntryPrice = 1.2000;

/** テスト用のエントリー時Spread。 */
const double testSpreadPips = 2.0;

/** テスト用のエントリー時ATR14。 */
const double testAtr14Pips = 10.0;

/**
 * double値を許容誤差付きで照合する。
 *
 * @param fromCaseName ケース名
 * @param fromFieldName 項目名
 * @param fromActual 実値
 * @param fromExpected 期待値
 * @return 一致する場合true
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
 * int値を照合する。
 *
 * @param fromCaseName ケース名
 * @param fromFieldName 項目名
 * @param fromActual 実値
 * @param fromExpected 期待値
 * @return 一致する場合true
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
 * long値を照合する。
 *
 * @param fromCaseName ケース名
 * @param fromFieldName 項目名
 * @param fromActual 実値
 * @param fromExpected 期待値
 * @return 一致する場合true
 */
bool assertLong(
    const string fromCaseName,
    const string fromFieldName,
    const long fromActual,
    const long fromExpected
) {
    if (fromActual == fromExpected) {
        return true;
    }

    PrintFormat(
        "FAIL %s %s actual=%I64d expected=%I64d",
        fromCaseName,
        fromFieldName,
        fromActual,
        fromExpected
    );

    return false;
}

/**
 * string値を照合する。
 *
 * @param fromCaseName ケース名
 * @param fromFieldName 項目名
 * @param fromActual 実値
 * @param fromExpected 期待値
 * @return 一致する場合true
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
 * bool値を照合する。
 *
 * @param fromCaseName ケース名
 * @param fromFieldName 項目名
 * @param fromActual 実値
 * @param fromExpected 期待値
 * @return 一致する場合true
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
 * Observationの完全一致方向を設定する。
 *
 * @param fromRow 設定対象
 * @param fromSide BUYまたはSELL
 */
void setAlignmentSide(
    ZigZagElliotH1StudyObservationRow &fromRow,
    const string fromSide
) {
    fromRow.isRequiredTimeFramesComplete = 1;
    fromRow.isW1Available = 1;
    fromRow.isD1Available = 1;
    fromRow.isH4Available = 1;
    fromRow.isH1Available = 1;

    if (fromSide == "BUY") {
        fromRow.w1IsBuy = 1;
        fromRow.d1IsBuy = 1;
        fromRow.h4IsBuy = 1;
        fromRow.h1IsBuy = 1;
        fromRow.h4IsEma200Buy = 1;
        fromRow.h4IsEma200Sell = 0;
        fromRow.h1IsEma200Buy = 1;
        fromRow.h1IsEma200Sell = 0;
        fromRow.fullAlignmentSide = "BUY";

        return;
    }

    fromRow.w1IsBuy = 0;
    fromRow.d1IsBuy = 0;
    fromRow.h4IsBuy = 0;
    fromRow.h1IsBuy = 0;
    fromRow.h4IsEma200Buy = 0;
    fromRow.h4IsEma200Sell = 1;
    fromRow.h1IsEma200Buy = 0;
    fromRow.h1IsEma200Sell = 1;
    fromRow.fullAlignmentSide = "SELL";
}

/**
 * テスト用Observationを初期化する。
 *
 * @param fromRow 設定対象
 * @param fromObservationId Observation ID
 * @param fromAnchorBarTime H1開始サーバー時刻
 * @param fromCurrentOpen 現在H1始値
 * @param fromSide 完全一致方向
 */
void initializeObservation(
    ZigZagElliotH1StudyObservationRow &fromRow,
    const long fromObservationId,
    const datetime fromAnchorBarTime,
    const double fromCurrentOpen,
    const string fromSide
) {
    fromRow.reset();
    fromRow.observationId = fromObservationId;
    fromRow.runId = 1;
    fromRow.sourceMode = "TESTER";
    fromRow.sourceServer = "SMOKE_SERVER";
    fromRow.symbolName = "EURUSD";
    fromRow.anchorTimeFrame = (int)PERIOD_H1;
    fromRow.anchorTimeFrameText = "H1";
    fromRow.capturePhase = "BAR_OPEN_FIRST_SUCCESS";
    fromRow.analysisVersion = "SMOKE_ANALYSIS_V1";
    fromRow.analysisInputHash = "SMOKE_INPUT_HASH";
    fromRow.anchorBarTime = fromAnchorBarTime;
    fromRow.anchorBarTimeText = TimeToString(
        fromAnchorBarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromRow.anchorJstTime = fromAnchorBarTime + 9 * 3600;
    fromRow.anchorJstTimeText = TimeToString(
        fromRow.anchorJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromRow.isSpreadAvailable = 1;
    fromRow.spreadPips = testSpreadPips;
    fromRow.pipSize = testPipSize;
    fromRow.pipSizeSource = "SOURCE_DB";
    fromRow.snapshotHash = "SMOKE_SNAPSHOT";
    fromRow.timeFrameCount = 5;
    fromRow.currentOpen = fromCurrentOpen;
    fromRow.previousOpen = fromCurrentOpen;
    fromRow.previousHigh = fromCurrentOpen;
    fromRow.previousLow = fromCurrentOpen;
    fromRow.previousClose = fromCurrentOpen;
    fromRow.isAtr14Available = 1;
    fromRow.atr14Pips = testAtr14Pips;
    setAlignmentSide(fromRow, fromSide);
}

/**
 * 指定方向・期間の通常H1テスト列を生成する。
 *
 * 評価bar jは有利j pips、不利j/2 pips、終値j/2 pipsとする。
 *
 * @param fromSide BUYまたはSELL
 * @param fromHorizonH1Bars 評価対象H1本数
 * @param fromRows 生成先
 */
void buildRegularRows(
    const string fromSide,
    const int fromHorizonH1Bars,
    ZigZagElliotH1StudyObservationRow &fromRows[]
) {
    int rowCount = fromHorizonH1Bars + 1;
    ArrayResize(fromRows, rowCount);
    datetime entryTime = D'2026.01.05 00:00:00';
    long baseObservationId = 100000 + fromHorizonH1Bars * 100;

    if (fromSide == "SELL") {
        baseObservationId += 50000;
    }

    for (int i = 0; i < rowCount; i++) {
        initializeObservation(
            fromRows[i],
            baseObservationId + i,
            entryTime + i * 3600,
            testEntryPrice,
            fromSide
        );

        if (i == 0) {
            continue;
        }

        double favorablePips = (double)i;
        double adversePips = (double)i / 2.0;
        fromRows[i].previousOpen = testEntryPrice;

        if (fromSide == "BUY") {
            fromRows[i].previousHigh = testEntryPrice
                + favorablePips * testPipSize;
            fromRows[i].previousLow = testEntryPrice
                - adversePips * testPipSize;
            fromRows[i].previousClose = testEntryPrice
                + adversePips * testPipSize;
        } else {
            fromRows[i].previousHigh = testEntryPrice
                + adversePips * testPipSize;
            fromRows[i].previousLow = testEntryPrice
                - favorablePips * testPipSize;
            fromRows[i].previousClose = testEntryPrice
                - adversePips * testPipSize;
        }
    }
}

/**
 * BUYまたはSELLの1期間分を検証する。
 *
 * @param fromSide BUYまたはSELL
 * @param fromHorizonH1Bars 評価対象H1本数
 * @return 全項目が期待値と一致する場合true
 */
bool validateDirectionalHorizon(
    const string fromSide,
    const int fromHorizonH1Bars
) {
    string caseName = fromSide + " horizon "
        + IntegerToString(fromHorizonH1Bars);
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows(fromSide, fromHorizonH1Bars, rows);
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated =
        ZigZagElliotH1StudyOutcomeCalculator::calculate(
            rows,
            0,
            fromSide,
            fromHorizonH1Bars,
            result
        );
    bool isMatched = isCalculated;
    double grossProfitPips = (double)fromHorizonH1Bars / 2.0;
    double netProfitPips = grossProfitPips - testSpreadPips;
    double expectedExitPrice = testEntryPrice
        + grossProfitPips * testPipSize;

    if (fromSide == "SELL") {
        expectedExitPrice = testEntryPrice
            - grossProfitPips * testPipSize;
    }

    if (!assertInteger(
            caseName,
            "isCalculated",
            result.isCalculated,
            1
        )) {
        isMatched = false;
    }
    if (!assertText(caseName, "dataStatus", result.dataStatus, "READY")) {
        isMatched = false;
    }
    if (!assertLong(
            caseName,
            "endObsId",
            result.endObsId,
            rows[fromHorizonH1Bars].observationId
        )) {
        isMatched = false;
    }
    if (!assertLong(
            caseName,
            "endTime",
            (long)result.endTime,
            (long)rows[fromHorizonH1Bars].anchorBarTime
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "exitPrice",
            result.exitPrice,
            expectedExitPrice
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "grossProfitPips",
            result.grossProfitPips,
            grossProfitPips
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "spreadAdjustedProfitPips",
            result.spreadAdjustedProfitPips,
            netProfitPips
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "grossProfitAtr",
            result.grossProfitAtr,
            grossProfitPips / testAtr14Pips
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "spreadAdjustedProfitAtr",
            result.spreadAdjustedProfitAtr,
            netProfitPips / testAtr14Pips
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "mfePips",
            result.mfePips,
            (double)fromHorizonH1Bars
        )) {
        isMatched = false;
    }
    if (!assertDouble(
            caseName,
            "maePips",
            result.maePips,
            (double)fromHorizonH1Bars / 2.0
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "maxProfitH1Bars",
            result.maxProfitH1Bars,
            fromHorizonH1Bars
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            fromHorizonH1Bars
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 最大利益へ最初に到達したH1本数をBUY・SELLで検証する。
 *
 * @return 同じ最大値の2回目では更新されない場合true
 */
bool validateFirstMaximumProfitBar() {
    bool isMatched = true;
    string sides[2] = {"BUY", "SELL"};

    for (int i = 0; i < ArraySize(sides); i++) {
        string side = sides[i];
        string caseName = side + " first maximum";
        ZigZagElliotH1StudyObservationRow rows[];
        buildRegularRows(side, 6, rows);

        for (int j = 1; j <= 6; j++) {
            double favorablePips = 5.0;

            if (j == 2 || j == 4) {
                favorablePips = 30.0;
            }

            if (side == "BUY") {
                rows[j].previousHigh = testEntryPrice
                    + favorablePips * testPipSize;
            } else {
                rows[j].previousLow = testEntryPrice
                    - favorablePips * testPipSize;
            }
        }

        ZigZagElliotH1StudyOutcomeCalculationResult result;
        bool isCalculated =
            ZigZagElliotH1StudyOutcomeCalculator::calculate(
                rows,
                0,
                side,
                6,
                result
            );

        if (!isCalculated) {
            Print(
                "FAIL " + caseName + " status=" + result.dataStatus
            );
            isMatched = false;
        }
        if (!assertDouble(caseName, "mfePips", result.mfePips, 30.0)) {
            isMatched = false;
        }
        if (!assertInteger(
                caseName,
                "maxProfitH1Bars",
                result.maxProfitH1Bars,
                2
            )) {
            isMatched = false;
        }
    }

    return isMatched;
}

/**
 * 有利方向へ一度も進まない場合のMFEと到達本数を検証する。
 *
 * @return MFEと最大利益到達本数が0の場合true
 */
bool validateZeroMfe() {
    string caseName = "BUY zero MFE";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 6, rows);

    for (int i = 1; i <= 6; i++) {
        rows[i].previousHigh = testEntryPrice;
        rows[i].previousLow = testEntryPrice - 10.0 * testPipSize;
        rows[i].previousClose = testEntryPrice - 5.0 * testPipSize;
    }

    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "BUY",
        6,
        result
    );
    bool isMatched = isCalculated;

    if (!assertDouble(caseName, "mfePips", result.mfePips, 0.0)) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "maxProfitH1Bars",
            result.maxProfitH1Bars,
            0
        )) {
        isMatched = false;
    }
    if (!assertDouble(caseName, "maePips", result.maePips, 10.0)) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * Viewerと同じ市場H1連続規則を検証する。
 *
 * @return 通常、週末、ChristmasおよびNewYearが期待値と一致する場合true
 */
bool validateMarketH1Continuity() {
    string caseName = "market H1 continuity";
    bool isMatched = true;

    if (!assertBoolean(
            caseName,
            "regular",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2026.01.05 00:00:00',
                D'2026.01.05 01:00:00'
            ),
            true
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "weekend",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2026.01.09 23:00:00',
                D'2026.01.12 00:00:00'
            ),
            true
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "Christmas",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2025.12.24 23:00:00',
                D'2025.12.26 00:00:00'
            ),
            true
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "NewYear",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2025.12.31 23:00:00',
                D'2026.01.02 00:00:00'
            ),
            true
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "twoHourGap",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2026.01.05 00:00:00',
                D'2026.01.05 02:00:00'
            ),
            false
        )) {
        isMatched = false;
    }
    if (!assertBoolean(
            caseName,
            "weekendSkip",
            ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                D'2026.01.09 23:00:00',
                D'2026.01.12 01:00:00'
            ),
            false
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 既知の休場境界を含む6H1計算を検証する。
 *
 * @param fromCaseName ケース名
 * @param fromEntryTime 休場前のエントリーH1時刻
 * @param fromNextTime 休場後の次H1時刻
 * @return 6H1をREADYまで計算できる場合true
 */
bool validateClosureOutcome(
    const string fromCaseName,
    const datetime fromEntryTime,
    const datetime fromNextTime
) {
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 6, rows);
    rows[0].anchorBarTime = fromEntryTime;

    for (int i = 1; i <= 6; i++) {
        rows[i].anchorBarTime = fromNextTime + (i - 1) * 3600;
    }

    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "BUY",
        6,
        result
    );
    bool isMatched = isCalculated;

    if (!assertText(
            fromCaseName,
            "dataStatus",
            result.dataStatus,
            "READY"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            fromCaseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            6
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 通常のH1欠損を後行へskipせず拒否することを検証する。
 *
 * @return FUTURE_H1_GAPとなる場合true
 */
bool validateNormalGap() {
    string caseName = "normal H1 gap";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 6, rows);
    rows[3].anchorBarTime += 3600;
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "BUY",
        6,
        result
    );
    bool isMatched = !isCalculated;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "FUTURE_H1_GAP"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            2
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * H1子行欠損を拒否することを検証する。
 *
 * @return FUTURE_H1_MISSINGとなる場合true
 */
bool validateMissingH1() {
    string caseName = "missing H1";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("SELL", 6, rows);
    rows[4].isH1Available = 0;
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "SELL",
        6,
        result
    );
    bool isMatched = !isCalculated;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "FUTURE_H1_MISSING"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            3
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 不正な確定H1 OHLCを拒否することを検証する。
 *
 * @return FUTURE_OHLC_INVALIDとなる場合true
 */
bool validateInvalidOhlc() {
    string caseName = "invalid H1 OHLC";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 6, rows);
    rows[2].previousHigh = rows[2].previousOpen - testPipSize;
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "BUY",
        6,
        result
    );
    bool isMatched = !isCalculated;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "FUTURE_OHLC_INVALID"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            1
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 同じ配列で短期READYと長期future不足を検証する。
 *
 * @return 12H1はREADY、24H1はFUTURE_INCOMPLETEとなる場合true
 */
bool validateFutureIncomplete() {
    string caseName = "future incomplete";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 12, rows);
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isShortCalculated =
        ZigZagElliotH1StudyOutcomeCalculator::calculate(
            rows,
            0,
            "BUY",
            12,
            result
        );
    bool isMatched = isShortCalculated;

    if (!assertText(
            caseName,
            "shortStatus",
            result.dataStatus,
            "READY"
        )) {
        isMatched = false;
    }

    bool isLongCalculated =
        ZigZagElliotH1StudyOutcomeCalculator::calculate(
            rows,
            0,
            "BUY",
            24,
            result
        );

    if (isLongCalculated) {
        Print("FAIL " + caseName + " long unexpectedly calculated");
        isMatched = false;
    }
    if (!assertText(
            caseName,
            "longStatus",
            result.dataStatus,
            "FUTURE_INCOMPLETE"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "longEvaluatedH1Bars",
            result.evaluatedH1Bars,
            12
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 長期future不足より手前のGapを優先して記録することを検証する。
 *
 * @return FUTURE_H1_GAPと検証済み本数を保持する場合true
 */
bool validateGapBeforeFutureIncomplete() {
    string caseName = "gap before future incomplete";
    ZigZagElliotH1StudyObservationRow rows[];
    buildRegularRows("BUY", 12, rows);
    rows[5].anchorBarTime += 3600;
    ZigZagElliotH1StudyOutcomeCalculationResult result;
    bool isCalculated = ZigZagElliotH1StudyOutcomeCalculator::calculate(
        rows,
        0,
        "BUY",
        24,
        result
    );
    bool isMatched = !isCalculated;

    if (!assertText(
            caseName,
            "dataStatus",
            result.dataStatus,
            "FUTURE_H1_GAP"
        )) {
        isMatched = false;
    }
    if (!assertInteger(
            caseName,
            "evaluatedH1Bars",
            result.evaluatedH1Bars,
            4
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * 完全一致方向分類のBUY、SELLおよび欠損を検証する。
 *
 * @return 全分類が期待値と一致する場合true
 */
bool validateFullAlignmentClassification() {
    string caseName = "full alignment classification";
    bool isMatched = true;
    ZigZagElliotH1StudyObservationRow row;
    initializeObservation(
        row,
        1,
        D'2026.01.05 00:00:00',
        testEntryPrice,
        "BUY"
    );

    if (!assertText(
            caseName,
            "BUY",
            ZigZagElliotH1StudyOutcomeCalculator::
                classifyFullAlignmentSide(row),
            "BUY"
        )) {
        isMatched = false;
    }

    setAlignmentSide(row, "SELL");

    if (!assertText(
            caseName,
            "SELL",
            ZigZagElliotH1StudyOutcomeCalculator::
                classifyFullAlignmentSide(row),
            "SELL"
        )) {
        isMatched = false;
    }

    row.h1IsEma200Buy = 1;

    if (!assertText(
            caseName,
            "invalidEma",
            ZigZagElliotH1StudyOutcomeCalculator::
                classifyFullAlignmentSide(row),
            ""
        )) {
        isMatched = false;
    }

    setAlignmentSide(row, "BUY");
    row.isRequiredTimeFramesComplete = 0;

    if (!assertText(
            caseName,
            "missingTimeFrame",
            ZigZagElliotH1StudyOutcomeCalculator::
                classifyFullAlignmentSide(row),
            ""
        )) {
        isMatched = false;
    }

    return isMatched;
}

/**
 * H1推移研究の方向別成績、連続性およびfail-closed条件を検証する。
 */
void OnStart() {
    int failureCount = 0;
    int horizons[4] = {6, 12, 24, 48};

    for (int i = 0; i < ArraySize(horizons); i++) {
        if (!validateDirectionalHorizon("BUY", horizons[i])) {
            failureCount++;
        }
        if (!validateDirectionalHorizon("SELL", horizons[i])) {
            failureCount++;
        }
    }

    if (!validateFirstMaximumProfitBar()) {
        failureCount++;
    }
    if (!validateZeroMfe()) {
        failureCount++;
    }
    if (!validateMarketH1Continuity()) {
        failureCount++;
    }
    if (!validateClosureOutcome(
            "weekend outcome",
            D'2026.01.09 23:00:00',
            D'2026.01.12 00:00:00'
        )) {
        failureCount++;
    }
    if (!validateClosureOutcome(
            "Christmas outcome",
            D'2025.12.24 23:00:00',
            D'2025.12.26 00:00:00'
        )) {
        failureCount++;
    }
    if (!validateClosureOutcome(
            "NewYear outcome",
            D'2025.12.31 23:00:00',
            D'2026.01.02 00:00:00'
        )) {
        failureCount++;
    }
    if (!validateNormalGap()) {
        failureCount++;
    }
    if (!validateMissingH1()) {
        failureCount++;
    }
    if (!validateInvalidOhlc()) {
        failureCount++;
    }
    if (!validateFutureIncomplete()) {
        failureCount++;
    }
    if (!validateGapBeforeFutureIncomplete()) {
        failureCount++;
    }
    if (!validateFullAlignmentClassification()) {
        failureCount++;
    }

    if (failureCount == 0) {
        Print("ZigZagElliotH1StudyOutcomeCalculatorSmokeTest PASS");

        return;
    }

    PrintFormat(
        "ZigZagElliotH1StudyOutcomeCalculatorSmokeTest FAIL count=%d",
        failureCount
    );
}
