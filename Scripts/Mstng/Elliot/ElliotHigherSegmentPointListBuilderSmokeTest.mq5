//+------------------------------------------------------------------+
//|            ElliotHigherSegmentPointListBuilderSmokeTest.mq5     |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.20"

#include <Mstng\Elliot\Analysis\ElliotHigherSegmentPointListBuilder.mqh>
#include <Mstng\Elliot\Wave.mqh>

/** 失敗した検証項目数。 */
int gFailureCount = 0;

/**
 * 条件を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromCondition 期待する条件
 */
void assertCondition(
    const string fromCaseName,
    const bool fromCondition
) {
    if (fromCondition) {
        return;
    }

    gFailureCount++;
    Print("FAIL " + fromCaseName);
}

/**
 * テスト用ポイントを新しい順の一覧へ追加する。
 *
 * @param fromPointList 追加先一覧
 * @param fromMarketContext 市場コンテキスト
 * @param fromBarTime バー時刻
 * @param fromRate レート
 * @param fromIsPeak 山の場合true
 * @param fromIsAddedPoint 補完ポイントの場合true
 * @return 追加に成功した場合true
 */
bool addPoint(
    CArrayObj &fromPointList,
    MarketContext &fromMarketContext,
    const datetime fromBarTime,
    const double fromRate,
    const bool fromIsPeak,
    const bool fromIsAddedPoint
) {
    ZigZagPoint *point = new ZigZagPoint(fromMarketContext);

    if (point == NULL) {
        return false;
    }

    point.barTime = fromBarTime;
    point.barTimeNext = fromBarTime
        + PeriodSeconds(fromMarketContext.timeFrame);
    point.rate = fromRate;
    point.isPeak = fromIsPeak;
    point.isAddedPoint = fromIsAddedPoint;

    if (!fromPointList.Add(point)) {
        delete point;

        return false;
    }

    return true;
}

/**
 * 上位足の左右境界を設定する。
 *
 * @param fromLeftPoint 古い側境界
 * @param fromRightPoint 新しい側境界
 * @param fromBaseTime 左境界バー開始時刻
 * @param fromLeftRate 左境界レート
 * @param fromRightRate 右境界レート
 * @param fromIsUptrend 上昇区間の場合true
 */
void setHigherPoints(
    ZigZagPoint &fromLeftPoint,
    ZigZagPoint &fromRightPoint,
    const datetime fromBaseTime,
    const double fromLeftRate,
    const double fromRightRate,
    const bool fromIsUptrend
) {
    fromLeftPoint.barTime = fromBaseTime;
    fromLeftPoint.barTimeNext = fromBaseTime
        + PeriodSeconds(fromLeftPoint.marketContext.timeFrame);
    fromLeftPoint.rate = fromLeftRate;
    fromLeftPoint.isPeak = true;

    fromRightPoint.barTime = fromBaseTime + 8 * 3600;
    fromRightPoint.barTimeNext = fromRightPoint.barTime
        + PeriodSeconds(fromRightPoint.marketContext.timeFrame);
    fromRightPoint.rate = fromRightRate;
    fromRightPoint.isPeak = false;

    if (fromIsUptrend) {
        fromLeftPoint.isPeak = false;
        fromRightPoint.isPeak = true;
    }
}

/**
 * 前後に文脈点を持つ下降4点区間を生成する。
 *
 * 親バー終端と同時刻の点も含め、半開区間から除外されることを確認する。
 *
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromPointList 生成先一覧
 * @return 生成に成功した場合true
 */
bool createDownPointList(
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList
) {
    datetime baseTime = D'2026.08.01 00:00:00';
    bool result = addPoint(fromPointList, fromMarketContext,
        baseTime + 12 * 3600, 0.90000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 11 * 3600, 1.18000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 10 * 3600, 1.22000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 9 * 3600, 1.15000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 6 * 3600, 1.25000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 5 * 3600, 1.20000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 2 * 3600, 1.30000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 1 * 3600, 1.10000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime, 1.27000, true, false);

    return result;
}

/**
 * 前後に文脈点を持つ上昇4点区間を生成する。
 *
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromPointList 生成先一覧
 * @return 生成に成功した場合true
 */
bool createUpPointList(
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList
) {
    datetime baseTime = D'2026.08.02 00:00:00';
    bool result = addPoint(fromPointList, fromMarketContext,
        baseTime + 11 * 3600, 1.22000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 10 * 3600, 1.18000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 9 * 3600, 1.25000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 6 * 3600, 1.15000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 5 * 3600, 1.20000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 2 * 3600, 1.10000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 1 * 3600, 1.14000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime, 1.12000, false, false);

    return result;
}

/**
 * 親境界間に5点を持つ区間を生成する。
 *
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromPointList 生成先一覧
 * @return 生成に成功した場合true
 */
bool createFivePointList(
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList
) {
    datetime baseTime = D'2026.08.03 00:00:00';
    bool result = addPoint(fromPointList, fromMarketContext,
        baseTime + 10 * 3600, 1.20000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 9 * 3600, 1.10000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 7 * 3600, 1.18000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 6 * 3600, 1.12000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 5 * 3600, 1.25000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 2 * 3600, 1.30000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 1 * 3600, 1.15000, false, false);

    return result;
}

/**
 * 有効な境界ペアが2組ある区間を生成する。
 *
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromPointList 生成先一覧
 * @return 生成に成功した場合true
 */
bool createAmbiguousPointList(
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList
) {
    datetime baseTime = D'2026.08.04 00:00:00';
    bool result = addPoint(fromPointList, fromMarketContext,
        baseTime + 11 * 3600, 1.15000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 10 * 3600, 1.25000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 9 * 3600, 1.15000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 3 * 3600, 1.30000, true, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 2 * 3600 + 30 * 60, 1.20000, false, false);
    result = result && addPoint(fromPointList, fromMarketContext,
        baseTime + 1 * 3600, 1.30000, true, false);

    return result;
}

/**
 * 下降2点Waveと上昇3点Waveを新しい順で生成する。
 *
 * 2つのWaveは境界点を共有し、重複を除くと親下降区間の4点となる。
 *
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromWaveList 生成先Wave一覧
 * @param fromMismatchBoundary 共有境界の価格を不一致にする場合true
 * @return 生成に成功した場合true
 */
bool createDownSplitWaveList(
    MarketContext &fromMarketContext,
    CArrayObj &fromWaveList,
    const bool fromMismatchBoundary = false
) {
    datetime baseTime = D'2026.08.05 00:00:00';
    CArrayObj newerPointList;
    bool result = addPoint(newerPointList, fromMarketContext,
        baseTime + 5 * 3600, 1.20000, false, false);
    result = result && addPoint(newerPointList, fromMarketContext,
        baseTime + 6 * 3600, 1.25000, true, false);
    result = result && addPoint(newerPointList, fromMarketContext,
        baseTime + 9 * 3600, 1.15000, false, false);

    if (!result) {
        return false;
    }

    Wave *newerWave = new Wave(
        fromMarketContext,
        newerPointList,
        false,
        true
    );

    if (newerWave == NULL || !fromWaveList.Add(newerWave)) {
        if (newerWave != NULL) {
            delete newerWave;
        }

        return false;
    }

    double sharedBoundaryRate = 1.20000;

    if (fromMismatchBoundary) {
        sharedBoundaryRate = 1.20100;
    }

    CArrayObj olderPointList;
    result = addPoint(olderPointList, fromMarketContext,
        baseTime + 2 * 3600, 1.30000, true, false);
    result = result && addPoint(olderPointList, fromMarketContext,
        baseTime + 5 * 3600, sharedBoundaryRate, false, false);

    if (!result) {
        return false;
    }

    Wave *olderWave = new Wave(
        fromMarketContext,
        olderPointList,
        false,
        false
    );

    if (olderWave == NULL || !fromWaveList.Add(olderWave)) {
        if (olderWave != NULL) {
            delete olderWave;
        }

        return false;
    }

    return true;
}

/**
 * 入力非破壊確認用文字列を生成する。
 *
 * @param fromPointList 対象一覧
 * @return ポイント主要値を連結した文字列
 */
string createPointListSignature(CArrayObj &fromPointList) {
    string signature = IntegerToString(fromPointList.Total());

    for (int i = 0; i < fromPointList.Total(); i++) {
        ZigZagPoint *point = fromPointList.At(i);

        if (CheckPointer(point) == POINTER_INVALID) {
            signature += "|INVALID";
            continue;
        }

        signature += "|" + TimeToString(point.barTime,
            TIME_DATE | TIME_MINUTES);
        signature += "," + DoubleToString(point.rate, 5);
        signature += "," + IntegerToString((int)point.isPeak);
        signature += "," + IntegerToString((int)point.isAddedPoint);
        signature += "," + point.marketContext.symbolName;
        signature += "," + IntegerToString(
            (int)point.marketContext.timeFrame);
    }

    return signature;
}

/**
 * 出力ポイントがすべて複製か検証する。
 *
 * @param fromRawPointList 入力一覧
 * @param fromOutputPointList 出力一覧
 * @return 全出力が別インスタンスの場合true
 */
bool areOutputPointsCloned(
    CArrayObj &fromRawPointList,
    CArrayObj &fromOutputPointList
) {
    for (int i = 0; i < fromOutputPointList.Total(); i++) {
        ZigZagPoint *outputPoint = fromOutputPointList.At(i);

        for (int j = 0; j < fromRawPointList.Total(); j++) {
            ZigZagPoint *rawPoint = fromRawPointList.At(j);

            if (outputPoint == rawPoint) {
                return false;
            }
        }
    }

    return true;
}

/**
 * 出力ポイントを検証する。
 *
 * @param fromCaseName 検証名
 * @param fromPointList 出力一覧
 * @param fromIndex 出力位置
 * @param fromTime 期待時刻
 * @param fromRate 期待レート
 * @param fromIsPeak 期待する山谷
 */
void assertOutputPoint(
    const string fromCaseName,
    CArrayObj &fromPointList,
    const int fromIndex,
    const datetime fromTime,
    const double fromRate,
    const bool fromIsPeak
) {
    if (fromIndex >= fromPointList.Total()) {
        assertCondition(fromCaseName + " missing", false);
        return;
    }

    ZigZagPoint *point = fromPointList.At(fromIndex);
    assertCondition(
        fromCaseName,
        CheckPointer(point) != POINTER_INVALID
        && point.barTime == fromTime
        && point.rate == fromRate
        && point.isPeak == fromIsPeak
        && !point.isAddedPoint
    );
}

/**
 * 単一修正WaveのA-B-C表示を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromMarketContext 市場コンテキスト
 * @param fromPointList 4点一覧
 * @param fromIsUptrend Wave方向
 * @param fromTrendLabel 期待方向ラベル
 */
void assertCorrectionLabels(
    const string fromCaseName,
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList,
    const bool fromIsUptrend,
    const string fromTrendLabel
) {
    Wave correctionWave(fromMarketContext, fromPointList, false,
        fromIsUptrend);
    correctionWave.analyze();
    assertCondition(fromCaseName + " total",
        correctionWave.zigZagPointList.Total() == 4);

    if (correctionWave.zigZagPointList.Total() != 4) {
        return;
    }

    ZigZagPoint *pointA = correctionWave.zigZagPointList.At(1);
    ZigZagPoint *pointB = correctionWave.zigZagPointList.At(2);
    ZigZagPoint *pointC = correctionWave.zigZagPointList.At(3);
    assertCondition(fromCaseName + " A",
        correctionWave.trendLabel + pointA.elliotLabel
            == fromTrendLabel + "A");
    assertCondition(fromCaseName + " B",
        correctionWave.trendLabel + pointB.elliotLabel
            == fromTrendLabel + "B");
    assertCondition(fromCaseName + " C",
        correctionWave.trendLabel + pointC.elliotLabel
            == fromTrendLabel + "C");
}

/**
 * Builderの拒否、出力消去および入力非破壊を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromMarketContext 下位足市場コンテキスト
 * @param fromPointList 入力一覧
 * @param fromLeftPoint 上位足左境界
 * @param fromRightPoint 上位足右境界
 * @param fromIsUptrend 期待方向
 * @param fromErrorText 期待する失敗理由の一部
 */
void assertRejected(
    const string fromCaseName,
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList,
    ZigZagPoint &fromLeftPoint,
    ZigZagPoint &fromRightPoint,
    const bool fromIsUptrend,
    const string fromErrorText
) {
    string signature = createPointListSignature(fromPointList);
    CArrayObj outputPointList;
    addPoint(outputPointList, fromMarketContext,
        D'2026.07.01 00:00:00', 1.00000, false, false);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.build(fromMarketContext, fromPointList,
        fromLeftPoint, fromRightPoint, fromIsUptrend, outputPointList);
    assertCondition(fromCaseName + " rejected", !result);
    assertCondition(fromCaseName + " output cleared",
        outputPointList.Total() == 0);
    assertCondition(fromCaseName + " error",
        StringFind(builder.getErrorMessage(), fromErrorText) >= 0);
    assertCondition(fromCaseName + " input unchanged",
        createPointListSignature(fromPointList) == signature);
}

/**
 * 下降4点の切り出しとラベルを検証する。
 */
void validateDownSuccess() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    CArrayObj points;
    CArrayObj output;
    assertCondition("DOWN fixture", createDownPointList(context, points));
    ZigZagPoint left(higherContext);
    ZigZagPoint right(higherContext);
    setHigherPoints(left, right, D'2026.08.01 00:00:00',
        1.30500, 1.14500, false);
    string signature = createPointListSignature(points);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.build(context, points, left, right, false, output);
    assertCondition("DOWN build", result);
    assertCondition("DOWN total", output.Total() == 4);
    assertOutputPoint("DOWN 0", output, 0,
        D'2026.08.01 02:00:00', 1.30000, true);
    assertOutputPoint("DOWN 1", output, 1,
        D'2026.08.01 05:00:00', 1.20000, false);
    assertOutputPoint("DOWN 2", output, 2,
        D'2026.08.01 06:00:00', 1.25000, true);
    assertOutputPoint("DOWN 3", output, 3,
        D'2026.08.01 09:00:00', 1.15000, false);
    assertCondition("DOWN cloned", areOutputPointsCloned(points, output));
    assertCorrectionLabels("DOWN labels", context, output, false, "▼");
    assertCondition("DOWN immutable",
        createPointListSignature(points) == signature);
}

/**
 * 上昇4点の切り出しとラベルを検証する。
 */
void validateUpSuccess() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    CArrayObj points;
    CArrayObj output;
    assertCondition("UP fixture", createUpPointList(context, points));
    ZigZagPoint left(higherContext);
    ZigZagPoint right(higherContext);
    setHigherPoints(left, right, D'2026.08.02 00:00:00',
        1.10000, 1.25000, true);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.build(context, points, left, right, true, output);
    assertCondition("UP build", result);
    assertCondition("UP total", output.Total() == 4);
    assertOutputPoint("UP 0", output, 0,
        D'2026.08.02 02:00:00', 1.10000, false);
    assertOutputPoint("UP 1", output, 1,
        D'2026.08.02 05:00:00', 1.20000, true);
    assertOutputPoint("UP 2", output, 2,
        D'2026.08.02 06:00:00', 1.15000, false);
    assertOutputPoint("UP 3", output, 3,
        D'2026.08.02 09:00:00', 1.25000, true);
    assertCorrectionLabels("UP labels", context, output, true, "▲");
}

/**
 * 分析後の2Waveを親方向の単一修正Waveへ統合できることを検証する。
 */
void validateWaveRangeSuccess() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    CArrayObj waveList;
    CArrayObj output;
    assertCondition(
        "WAVE RANGE fixture",
        createDownSplitWaveList(context, waveList)
    );
    ZigZagPoint left(higherContext);
    ZigZagPoint right(higherContext);
    setHigherPoints(left, right, D'2026.08.05 00:00:00',
        1.30000, 1.15000, false);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromWaveRange(
        context,
        waveList,
        0,
        1,
        left,
        right,
        false,
        output
    );
    assertCondition("WAVE RANGE build", result);
    assertCondition("WAVE RANGE total", output.Total() == 4);
    assertOutputPoint("WAVE RANGE 0", output, 0,
        D'2026.08.05 02:00:00', 1.30000, true);
    assertOutputPoint("WAVE RANGE 1", output, 1,
        D'2026.08.05 05:00:00', 1.20000, false);
    assertOutputPoint("WAVE RANGE 2", output, 2,
        D'2026.08.05 06:00:00', 1.25000, true);
    assertOutputPoint("WAVE RANGE 3", output, 3,
        D'2026.08.05 09:00:00', 1.15000, false);
    assertCorrectionLabels(
        "WAVE RANGE labels",
        context,
        output,
        false,
        "▼"
    );
}

/**
 * Wave範囲外および共有境界不一致が拒否されることを検証する。
 */
void validateWaveRangeConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    CArrayObj waveList;
    createDownSplitWaveList(context, waveList);
    ZigZagPoint left(higherContext);
    ZigZagPoint right(higherContext);
    setHigherPoints(left, right, D'2026.08.05 00:00:00',
        1.30000, 1.15000, false);
    CArrayObj output;
    addPoint(output, context, D'2026.07.01 00:00:00',
        1.00000, false, false);
    ElliotHigherSegmentPointListBuilder rangeBuilder;
    bool result = rangeBuilder.buildFromWaveRange(
        context,
        waveList,
        0,
        2,
        left,
        right,
        false,
        output
    );
    assertCondition("WAVE RANGE outside rejected", !result);
    assertCondition("WAVE RANGE outside output cleared",
        output.Total() == 0);
    assertCondition(
        "WAVE RANGE outside error",
        StringFind(
            rangeBuilder.getErrorMessage(),
            "wave range is invalid"
        ) >= 0
    );

    CArrayObj mismatchWaveList;
    createDownSplitWaveList(context, mismatchWaveList, true);
    addPoint(output, context, D'2026.07.01 00:00:00',
        1.00000, false, false);
    ElliotHigherSegmentPointListBuilder mismatchBuilder;
    result = mismatchBuilder.buildFromWaveRange(
        context,
        mismatchWaveList,
        0,
        1,
        left,
        right,
        false,
        output
    );
    assertCondition("WAVE RANGE boundary rejected", !result);
    assertCondition("WAVE RANGE boundary output cleared",
        output.Total() == 0);
    assertCondition(
        "WAVE RANGE boundary error",
        StringFind(
            mismatchBuilder.getErrorMessage(),
            "shared wave boundary mismatch"
        ) >= 0
    );

    CArrayObj addedBoundaryWaveList;
    createDownSplitWaveList(context, addedBoundaryWaveList);
    Wave *olderWave = addedBoundaryWaveList.At(1);
    ZigZagPoint *olderBoundary = olderWave.zigZagPointList.At(
        olderWave.zigZagPointList.Total() - 1
    );
    olderBoundary.isAddedPoint = true;
    addPoint(output, context, D'2026.07.01 00:00:00',
        1.00000, false, false);
    ElliotHigherSegmentPointListBuilder addedBoundaryBuilder;
    result = addedBoundaryBuilder.buildFromWaveRange(
        context,
        addedBoundaryWaveList,
        0,
        1,
        left,
        right,
        false,
        output
    );
    assertCondition("WAVE RANGE added boundary rejected", !result);
    assertCondition("WAVE RANGE added boundary output cleared",
        output.Total() == 0);
    assertCondition(
        "WAVE RANGE added boundary error",
        StringFind(
            addedBoundaryBuilder.getErrorMessage(),
            "shared wave boundary mismatch"
        ) >= 0
    );
}

/**
 * Strict V1の拒否条件を検証する。
 */
void validateStrictConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);

    CArrayObj boundaryPoints;
    createDownPointList(context, boundaryPoints);
    ZigZagPoint boundaryLeft(higherContext);
    ZigZagPoint boundaryRight(higherContext);
    setHigherPoints(boundaryLeft, boundaryRight,
        D'2026.08.01 00:00:00', 1.30500, 1.14500, false);
    boundaryRight.barTime = D'2026.08.01 13:00:00';
    boundaryRight.barTimeNext = D'2026.08.01 17:00:00';
    assertRejected("boundary mismatch", context, boundaryPoints,
        boundaryLeft, boundaryRight, false, "right boundary point not found");

    CArrayObj fivePoints;
    createFivePointList(context, fivePoints);
    ZigZagPoint fiveLeft(higherContext);
    ZigZagPoint fiveRight(higherContext);
    setHigherPoints(fiveLeft, fiveRight, D'2026.08.03 00:00:00',
        1.30000, 1.10000, false);
    assertRejected("five points", context, fivePoints, fiveLeft, fiveRight,
        false, "boundary slice must contain four points");

    CArrayObj addedPoints;
    createDownPointList(context, addedPoints);
    ZigZagPoint *addedPoint = addedPoints.At(5);
    addedPoint.isAddedPoint = true;
    ZigZagPoint addedLeft(higherContext);
    ZigZagPoint addedRight(higherContext);
    setHigherPoints(addedLeft, addedRight, D'2026.08.01 00:00:00',
        1.30500, 1.14500, false);
    assertRejected("added point", context, addedPoints,
        addedLeft, addedRight, false, "added point is not allowed");
}

/**
 * 配列順、局所レート、全体方向および一意性を検証する。
 */
void validateSequenceConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);

    CArrayObj alternatePoints;
    createDownPointList(context, alternatePoints);
    ZigZagPoint *alternatePoint = alternatePoints.At(4);
    alternatePoint.isPeak = false;
    ZigZagPoint alternateLeft(higherContext);
    ZigZagPoint alternateRight(higherContext);
    setHigherPoints(alternateLeft, alternateRight,
        D'2026.08.01 00:00:00', 1.30500, 1.14500, false);
    assertRejected("alternate", context, alternatePoints,
        alternateLeft, alternateRight, false,
        "peak and bottom do not alternate");

    CArrayObj ratePoints;
    createDownPointList(context, ratePoints);
    ZigZagPoint *ratePoint = ratePoints.At(4);
    ratePoint.rate = 1.19000;
    ZigZagPoint rateLeft(higherContext);
    ZigZagPoint rateRight(higherContext);
    setHigherPoints(rateLeft, rateRight, D'2026.08.01 00:00:00',
        1.30500, 1.14500, false);
    assertRejected("local rate", context, ratePoints,
        rateLeft, rateRight, false, "peak rate direction mismatch");

    CArrayObj directionPoints;
    createDownPointList(context, directionPoints);
    ZigZagPoint directionLeft(higherContext);
    ZigZagPoint directionRight(higherContext);
    setHigherPoints(directionLeft, directionRight,
        D'2026.08.01 00:00:00', 1.30500, 1.14500, false);
    assertRejected("direction", context, directionPoints,
        directionLeft, directionRight, true,
        "higher segment direction mismatch");

    CArrayObj ambiguousPoints;
    createAmbiguousPointList(context, ambiguousPoints);
    ZigZagPoint ambiguousLeft(higherContext);
    ZigZagPoint ambiguousRight(higherContext);
    setHigherPoints(ambiguousLeft, ambiguousRight,
        D'2026.08.04 00:00:00', 1.30000, 1.15000, false);
    assertRejected("ambiguous", context, ambiguousPoints,
        ambiguousLeft, ambiguousRight, false, "boundary pair is ambiguous");
}

/**
 * 失敗後の成功でエラー理由が消去されることを検証する。
 */
void validateErrorReset() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    CArrayObj emptyPoints;
    CArrayObj output;
    ZigZagPoint left(higherContext);
    ZigZagPoint right(higherContext);
    setHigherPoints(left, right, D'2026.08.02 00:00:00',
        1.10000, 1.25000, true);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.build(context, emptyPoints, left, right, true, output);
    assertCondition("error reset reject", !result);
    assertCondition("error reset has message", builder.getErrorMessage() != "");

    CArrayObj validPoints;
    createUpPointList(context, validPoints);
    result = builder.build(context, validPoints, left, right, true, output);
    assertCondition("error reset build", result);
    assertCondition("error reset cleared", builder.getErrorMessage() == "");
}

/**
 * 上位足境界区間のポイント構築Smoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateDownSuccess();
    validateUpSuccess();
    validateWaveRangeSuccess();
    validateWaveRangeConditions();
    validateStrictConditions();
    validateSequenceConditions();
    validateErrorReset();

    if (gFailureCount == 0) {
        Print("ElliotHigherSegmentPointListBuilderSmokeTest PASS");
        return;
    }

    PrintFormat("ElliotHigherSegmentPointListBuilderSmokeTest FAIL count=%d",
        gFailureCount);
}
