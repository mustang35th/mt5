//+------------------------------------------------------------------+
//|     ElliotHigherSegmentThreeWaveContinuationSmokeTest.mq5      |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

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
 * テスト用ポイントを古い順の一覧へ追加する。
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
 * Waveを生成して一覧へ追加する。
 *
 * @param fromWaveList 追加先Wave一覧
 * @param fromMarketContext 市場コンテキスト
 * @param fromPointList Wave内ポイント一覧。古い順
 * @param fromIsMotive 推進波の場合true
 * @param fromIsUptrend 上昇波の場合true
 * @return 追加に成功した場合true
 */
bool addWave(
    CArrayObj &fromWaveList,
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList,
    const bool fromIsMotive,
    const bool fromIsUptrend
) {
    Wave *wave = new Wave(
        fromMarketContext,
        fromPointList,
        fromIsMotive,
        fromIsUptrend
    );

    if (wave == NULL) {
        return false;
    }

    if (!fromWaveList.Add(wave)) {
        delete wave;
        return false;
    }

    return true;
}

/**
 * 上昇または下降の3Wave入力形状を設定する。
 *
 * @param fromIsUptrend 上昇形状の場合true
 * @param toRates 期待レート配列
 * @param toPeaks 期待山谷配列
 */
void setPointShape(
    const bool fromIsUptrend,
    double &toRates[],
    bool &toPeaks[]
) {
    if (fromIsUptrend) {
        toRates[0] = 1.10000;
        toRates[1] = 1.18000;
        toRates[2] = 1.15000;
        toRates[3] = 1.25000;
        toRates[4] = 1.19000;
        toRates[5] = 1.22000;
        toRates[6] = 1.17000;
        toRates[7] = 1.26000;
        toRates[8] = 1.23000;
        toRates[9] = 1.35000;

        toPeaks[0] = false;
        toPeaks[1] = true;
        toPeaks[2] = false;
        toPeaks[3] = true;
        toPeaks[4] = false;
        toPeaks[5] = true;
        toPeaks[6] = false;
        toPeaks[7] = true;
        toPeaks[8] = false;
        toPeaks[9] = true;
        return;
    }

    toRates[0] = 1.35000;
    toRates[1] = 1.27000;
    toRates[2] = 1.30000;
    toRates[3] = 1.20000;
    toRates[4] = 1.26000;
    toRates[5] = 1.23000;
    toRates[6] = 1.28000;
    toRates[7] = 1.19000;
    toRates[8] = 1.22000;
    toRates[9] = 1.10000;

    toPeaks[0] = true;
    toPeaks[1] = false;
    toPeaks[2] = true;
    toPeaks[3] = false;
    toPeaks[4] = true;
    toPeaks[5] = false;
    toPeaks[6] = true;
    toPeaks[7] = false;
    toPeaks[8] = true;
    toPeaks[9] = false;
}

/**
 * 指定範囲の形状ポイントを生成する。
 *
 * @param fromMarketContext 市場コンテキスト
 * @param fromBaseTime 基準時刻
 * @param fromRates レート配列
 * @param fromPeaks 山谷配列
 * @param fromStartIndex 開始位置
 * @param fromEndIndex 終了位置
 * @param toPointList 生成先ポイント一覧
 * @return 全ポイントの生成に成功した場合true
 */
bool createPointRange(
    MarketContext &fromMarketContext,
    const datetime fromBaseTime,
    const double &fromRates[],
    const bool &fromPeaks[],
    const int fromStartIndex,
    const int fromEndIndex,
    CArrayObj &toPointList
) {
    int periodSeconds = PeriodSeconds(fromMarketContext.timeFrame);

    for (int i = fromStartIndex; i <= fromEndIndex; i++) {
        datetime pointTime = fromBaseTime + (i + 1) * periodSeconds;

        if (!addPoint(
                toPointList,
                fromMarketContext,
                pointTime,
                fromRates[i],
                fromPeaks[i],
                false
            )) {
            return false;
        }
    }

    return true;
}

/**
 * 親方向・逆方向・親方向の3Waveを新しい順で生成する。
 *
 * 各Waveは4ポイントを保持し、隣接Waveは境界を1点ずつ共有する。
 * 統合時は最古Waveの始点と各Waveの終点を0・1・2・3として採用する。
 *
 * @param fromMarketContext 子時間足市場コンテキスト
 * @param fromBaseTime 基準時刻
 * @param fromIsUptrend 親区間が上昇の場合true
 * @param fromIsMotive 親区間が推進波の場合true
 * @param toWaveList 生成先Wave一覧。インデックス0が最新
 * @return 生成に成功した場合true
 */
bool createThreeWaveList(
    MarketContext &fromMarketContext,
    const datetime fromBaseTime,
    const bool fromIsUptrend,
    const bool fromIsMotive,
    CArrayObj &toWaveList
) {
    double rates[10];
    bool peaks[10];
    setPointShape(fromIsUptrend, rates, peaks);

    CArrayObj olderPointList;
    CArrayObj middlePointList;
    CArrayObj newerPointList;

    if (!createPointRange(
            fromMarketContext,
            fromBaseTime,
            rates,
            peaks,
            0,
            3,
            olderPointList
        )
            || !createPointRange(
                fromMarketContext,
                fromBaseTime,
                rates,
                peaks,
                3,
                6,
                middlePointList
            )
            || !createPointRange(
                fromMarketContext,
                fromBaseTime,
                rates,
                peaks,
                6,
                9,
                newerPointList
            )) {
        return false;
    }

    if (!addWave(
            toWaveList,
            fromMarketContext,
            newerPointList,
            fromIsMotive,
            fromIsUptrend
        )
            || !addWave(
                toWaveList,
                fromMarketContext,
                middlePointList,
                fromIsMotive,
                !fromIsUptrend
            )
            || !addWave(
                toWaveList,
                fromMarketContext,
                olderPointList,
                fromIsMotive,
                fromIsUptrend
            )) {
        return false;
    }

    return true;
}

/**
 * 4Wave範囲用の最古Waveを追加する。
 *
 * @param fromMarketContext 子時間足市場コンテキスト
 * @param fromBaseTime 基準時刻
 * @param fromIsMotive 親区間が推進波の場合true
 * @param fromWaveList 追加先Wave一覧
 * @return 追加に成功した場合true
 */
bool addOlderGuardWave(
    MarketContext &fromMarketContext,
    const datetime fromBaseTime,
    const bool fromIsMotive,
    CArrayObj &fromWaveList
) {
    int periodSeconds = PeriodSeconds(fromMarketContext.timeFrame);
    CArrayObj pointList;

    if (!addPoint(
            pointList,
            fromMarketContext,
            fromBaseTime,
            1.20000,
            true,
            false
        )
            || !addPoint(
                pointList,
                fromMarketContext,
                fromBaseTime + periodSeconds,
                1.10000,
                false,
                false
            )) {
        return false;
    }

    return addWave(
        fromWaveList,
        fromMarketContext,
        pointList,
        fromIsMotive,
        false
    );
}

/**
 * 親区間の左右境界を設定する。
 *
 * @param fromLeftPoint 古い側境界
 * @param fromRightPoint 新しい側境界
 * @param fromLeftBarTime 左境界の親バー開始時刻
 * @param fromRightBarTime 右境界の親バー開始時刻
 * @param fromLeftRate 左境界レート
 * @param fromRightRate 右境界レート
 * @param fromIsUptrend 親区間が上昇の場合true
 */
void setHigherPoints(
    ZigZagPoint &fromLeftPoint,
    ZigZagPoint &fromRightPoint,
    const datetime fromLeftBarTime,
    const datetime fromRightBarTime,
    const double fromLeftRate,
    const double fromRightRate,
    const bool fromIsUptrend
) {
    int periodSeconds = PeriodSeconds(
        fromLeftPoint.marketContext.timeFrame
    );

    fromLeftPoint.barTime = fromLeftBarTime;
    fromLeftPoint.barTimeNext = fromLeftBarTime + periodSeconds;
    fromLeftPoint.rate = fromLeftRate;
    fromLeftPoint.isPeak = true;
    fromLeftPoint.isAddedPoint = false;

    fromRightPoint.barTime = fromRightBarTime;
    fromRightPoint.barTimeNext = fromRightBarTime + periodSeconds;
    fromRightPoint.rate = fromRightRate;
    fromRightPoint.isPeak = false;
    fromRightPoint.isAddedPoint = false;

    if (fromIsUptrend) {
        fromLeftPoint.isPeak = false;
        fromRightPoint.isPeak = true;
    }
}

/**
 * ポイント一覧を入力非破壊確認用文字列へ変換する。
 *
 * @param fromPointList 対象ポイント一覧
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

        signature += "|" + TimeToString(
            point.barTime,
            TIME_DATE | TIME_MINUTES
        );
        signature += "," + TimeToString(
            point.barTimeNext,
            TIME_DATE | TIME_MINUTES
        );
        signature += "," + DoubleToString(point.rate, 5);
        signature += "," + IntegerToString((int)point.isPeak);
        signature += "," + IntegerToString((int)point.isAddedPoint);
        signature += "," + point.marketContext.symbolName;
        signature += "," + IntegerToString(
            (int)point.marketContext.timeFrame
        );
        signature += "," + IntegerToString(point.waveBarsFromStart);
        signature += "," + DoubleToString(point.pipsDiff, 1);
        signature += "," + DoubleToString(point.fibonacciPercent, 1);
        signature += "," + IntegerToString((int)point.fiboDepthZone);
        signature += "," + point.fiboDepthZoneLabel;
        signature += "," + DoubleToString(
            point.fibonacciExpansionPercent,
            1
        );
        signature += "," + IntegerToString(
            (int)point.isElliotAlphabet
        );
        signature += "," + IntegerToString(point.elliotIndex);
        signature += "," + point.elliotLabel;
        signature += "," + IntegerToString(point.subElliotIndex);
        signature += "," + point.subElliotLabel;
        signature += "," + IntegerToString(point.orgElliotIndex);
        signature += "," + point.orgElliotLabel;
    }

    return signature;
}

/**
 * Wave一覧を入力非破壊確認用文字列へ変換する。
 *
 * @param fromWaveList 対象Wave一覧
 * @return Wave属性とポイント主要値を連結した文字列
 */
string createWaveListSignature(CArrayObj &fromWaveList) {
    string signature = IntegerToString(fromWaveList.Total());

    for (int i = 0; i < fromWaveList.Total(); i++) {
        Wave *wave = fromWaveList.At(i);

        if (CheckPointer(wave) == POINTER_INVALID) {
            signature += "|INVALID";
            continue;
        }

        signature += "|" + IntegerToString((int)wave.isMotive);
        signature += "," + IntegerToString((int)wave.isUptrend);
        signature += "," + createPointListSignature(
            wave.zigZagPointList
        );
    }

    return signature;
}

/**
 * 出力ポイントが入力Waveのポイントと参照共有していないか検証する。
 *
 * @param fromWaveList 入力Wave一覧
 * @param fromOutputPointList 出力ポイント一覧
 * @return 全出力が入力とは別インスタンスの場合true
 */
bool areOutputPointsCloned(
    CArrayObj &fromWaveList,
    CArrayObj &fromOutputPointList
) {
    for (int i = 0; i < fromOutputPointList.Total(); i++) {
        ZigZagPoint *outputPoint = fromOutputPointList.At(i);

        for (int j = 0; j < fromWaveList.Total(); j++) {
            Wave *wave = fromWaveList.At(j);

            if (CheckPointer(wave) == POINTER_INVALID) {
                return false;
            }

            for (int k = 0; k < wave.zigZagPointList.Total(); k++) {
                ZigZagPoint *inputPoint = wave.zigZagPointList.At(k);

                if (outputPoint == inputPoint) {
                    return false;
                }
            }
        }
    }

    return true;
}

/**
 * 指定時刻の出力ポイント数を取得する。
 *
 * @param fromPointList 対象ポイント一覧
 * @param fromBarTime 対象時刻
 * @return 一致ポイント数
 */
int countPointTime(
    CArrayObj &fromPointList,
    const datetime fromBarTime
) {
    int count = 0;

    for (int i = 0; i < fromPointList.Total(); i++) {
        ZigZagPoint *point = fromPointList.At(i);

        if (CheckPointer(point) != POINTER_INVALID
                && point.barTime == fromBarTime) {
            count++;
        }
    }

    return count;
}

/**
 * 4アンカーのレートを入力Waveへ設定する。
 *
 * 共有境界となる1と2は両方のWaveへ同じ値を設定する。
 *
 * @param fromWaveList 入力Wave一覧
 * @param fromAnchorIndex アンカー位置。0から3
 * @param fromRate 設定レート
 * @return 設定に成功した場合true
 */
bool setAnchorRate(
    CArrayObj &fromWaveList,
    const int fromAnchorIndex,
    const double fromRate
) {
    if (fromWaveList.Total() != 3
            || fromAnchorIndex < 0
            || fromAnchorIndex > 3) {
        return false;
    }

    Wave *newerWave = fromWaveList.At(0);
    Wave *middleWave = fromWaveList.At(1);
    Wave *olderWave = fromWaveList.At(2);

    if (CheckPointer(newerWave) == POINTER_INVALID
            || CheckPointer(middleWave) == POINTER_INVALID
            || CheckPointer(olderWave) == POINTER_INVALID
            || newerWave.zigZagPointList.Total() != 4
            || middleWave.zigZagPointList.Total() != 4
            || olderWave.zigZagPointList.Total() != 4) {
        return false;
    }

    if (fromAnchorIndex == 0) {
        ZigZagPoint *point = olderWave.zigZagPointList.At(0);

        if (CheckPointer(point) == POINTER_INVALID) {
            return false;
        }

        point.rate = fromRate;
        return true;
    }

    if (fromAnchorIndex == 1) {
        ZigZagPoint *olderPoint = olderWave.zigZagPointList.At(3);
        ZigZagPoint *middlePoint = middleWave.zigZagPointList.At(0);

        if (CheckPointer(olderPoint) == POINTER_INVALID
                || CheckPointer(middlePoint) == POINTER_INVALID) {
            return false;
        }

        olderPoint.rate = fromRate;
        middlePoint.rate = fromRate;
        return true;
    }

    if (fromAnchorIndex == 2) {
        ZigZagPoint *middlePoint = middleWave.zigZagPointList.At(3);
        ZigZagPoint *newerPoint = newerWave.zigZagPointList.At(0);

        if (CheckPointer(middlePoint) == POINTER_INVALID
                || CheckPointer(newerPoint) == POINTER_INVALID) {
            return false;
        }

        middlePoint.rate = fromRate;
        newerPoint.rate = fromRate;
        return true;
    }

    ZigZagPoint *point = newerWave.zigZagPointList.At(3);

    if (CheckPointer(point) == POINTER_INVALID) {
        return false;
    }

    point.rate = fromRate;
    return true;
}

/**
 * 入力ポイントへ再構築前の分析値を設定する。
 *
 * @param fromWaveList 入力Wave一覧
 */
void setOldAnalysisValues(CArrayObj &fromWaveList) {
    for (int i = 0; i < fromWaveList.Total(); i++) {
        Wave *wave = fromWaveList.At(i);

        if (CheckPointer(wave) == POINTER_INVALID) {
            continue;
        }

        for (int j = 0; j < wave.zigZagPointList.Total(); j++) {
            ZigZagPoint *point = wave.zigZagPointList.At(j);

            if (CheckPointer(point) == POINTER_INVALID) {
                continue;
            }

            point.waveBarsFromStart = 999;
            point.pipsDiff = 999.9;
            point.fibonacciPercent = 99.9;
            point.fiboDepthZone = FIBO_DEPTH_INVALID;
            point.fiboDepthZoneLabel = "OLD_DEPTH";
            point.fibonacciExpansionPercent = 999.9;
            point.isElliotAlphabet = true;
            point.elliotIndex = 5;
            point.elliotLabel = "OLD_ELLIOT";
            point.subElliotIndex = 5;
            point.subElliotLabel = "OLD_SUB_ELLIOT";
            point.orgElliotIndex = 5;
            point.orgElliotLabel = "OLD_ORG_ELLIOT";
            point.parentWave = wave;
        }
    }
}

/**
 * 4アンカーから旧分析値が除去されているか判定する。
 *
 * @param fromPointList Builder出力ポイント一覧
 * @return 全ポイントの分析値が初期化されている場合true
 */
bool areAnchorAnalysisValuesReset(CArrayObj &fromPointList) {
    if (fromPointList.Total() != 4) {
        return false;
    }

    for (int i = 0; i < fromPointList.Total(); i++) {
        ZigZagPoint *point = fromPointList.At(i);

        if (CheckPointer(point) == POINTER_INVALID
                || point.waveBarsFromStart != 0
                || point.pipsDiff != 0
                || point.fibonacciPercent != 0
                || point.fiboDepthZone != FIBO_DEPTH_UNKNOWN
                || point.fiboDepthZoneLabel != ""
                || point.fibonacciExpansionPercent != 0
                || point.isElliotAlphabet
                || point.elliotIndex != 0
                || point.elliotLabel != ""
                || point.subElliotIndex != 0
                || StringLen(point.subElliotLabel) != 0
                || point.orgElliotIndex != 0
                || point.orgElliotLabel != ""
                || point.parentWave != NULL) {
            return false;
        }
    }

    return true;
}

/**
 * 分析後アンカーの期待Elliottラベルを取得する。
 *
 * @param fromIndex アンカー位置
 * @param fromIsMotive 推進波の場合true
 * @return 数字またはアルファベットの期待ラベル
 */
string getExpectedAnalyzedLabel(
    const int fromIndex,
    const bool fromIsMotive
) {
    if (fromIsMotive) {
        return IntegerToString(fromIndex);
    }

    if (fromIndex == 1) {
        return "A";
    }

    if (fromIndex == 2) {
        return "B";
    }

    if (fromIndex == 3) {
        return "C";
    }

    return "#0";
}

/**
 * 成功時の4アンカー出力を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromMarketContext 子時間足市場コンテキスト
 * @param fromPointList 出力ポイント一覧
 * @param fromBaseTime 基準時刻
 * @param fromIsUptrend 親区間が上昇の場合true
 */
void assertSuccessfulOutput(
    const string fromCaseName,
    MarketContext &fromMarketContext,
    CArrayObj &fromPointList,
    const datetime fromBaseTime,
    const bool fromIsUptrend
) {
    const int expectedPointCount = 4;
    int sourceIndexes[4] = {0, 3, 6, 9};
    assertCondition(
        fromCaseName + " total",
        fromPointList.Total() == expectedPointCount
    );

    if (fromPointList.Total() != expectedPointCount) {
        return;
    }

    double rates[10];
    bool peaks[10];
    setPointShape(fromIsUptrend, rates, peaks);
    int periodSeconds = PeriodSeconds(fromMarketContext.timeFrame);

    for (int i = 0; i < expectedPointCount; i++) {
        ZigZagPoint *point = fromPointList.At(i);
        int sourceIndex = sourceIndexes[i];
        datetime expectedTime = fromBaseTime
            + (sourceIndex + 1) * periodSeconds;
        bool isMatched = CheckPointer(point) != POINTER_INVALID;

        if (isMatched) {
            isMatched = point.barTime == expectedTime
                && point.barTimeNext == expectedTime + periodSeconds
                && point.rate == rates[sourceIndex]
                && point.isPeak == peaks[sourceIndex]
                && !point.isAddedPoint
                && point.marketContext.symbolName
                    == fromMarketContext.symbolName
                && point.marketContext.timeFrame
                    == fromMarketContext.timeFrame;
        }

        assertCondition(
            fromCaseName + " point " + IntegerToString(i),
            isMatched
        );
    }

    assertCondition(
        fromCaseName + " first shared boundary once",
        countPointTime(
            fromPointList,
            fromBaseTime + 4 * periodSeconds
        ) == 1
    );
    assertCondition(
        fromCaseName + " second shared boundary once",
        countPointTime(
            fromPointList,
            fromBaseTime + 7 * periodSeconds
        ) == 1
    );
}

/**
 * 3Wave統合の拒否、出力消去および入力非破壊を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromMarketContext 子時間足市場コンテキスト
 * @param fromWaveList 入力Wave一覧
 * @param fromWaveIndexStart 対象範囲の新しい側Waveインデックス
 * @param fromWaveIndexEnd 対象範囲の古い側Waveインデックス
 * @param fromLeftPoint 親区間の古い側境界
 * @param fromRightPoint 親区間の新しい側境界
 * @param fromIsUptrend 親区間が上昇の場合true
 * @param fromIsMotive 親区間が推進波の場合true
 * @param fromErrorText 期待する失敗理由の一部
 */
void assertRejected(
    const string fromCaseName,
    MarketContext &fromMarketContext,
    CArrayObj &fromWaveList,
    const int fromWaveIndexStart,
    const int fromWaveIndexEnd,
    ZigZagPoint &fromLeftPoint,
    ZigZagPoint &fromRightPoint,
    const bool fromIsUptrend,
    const bool fromIsMotive,
    const string fromErrorText
) {
    string signature = createWaveListSignature(fromWaveList);
    CArrayObj outputPointList;
    addPoint(
        outputPointList,
        fromMarketContext,
        D'2026.07.01 00:00:00',
        1.00000,
        false,
        false
    );
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromThreeWaveContinuationRange(
        fromMarketContext,
        fromWaveList,
        fromWaveIndexStart,
        fromWaveIndexEnd,
        fromLeftPoint,
        fromRightPoint,
        fromIsUptrend,
        fromIsMotive,
        outputPointList
    );

    assertCondition(fromCaseName + " rejected", !result);
    assertCondition(
        fromCaseName + " output cleared",
        outputPointList.Total() == 0
    );
    assertCondition(
        fromCaseName + " error",
        StringFind(builder.getErrorMessage(), fromErrorText) >= 0
    );
    assertCondition(
        fromCaseName + " input unchanged",
        createWaveListSignature(fromWaveList) == signature
    );
}

/**
 * 3Wave統合の受理、4アンカー出力および入力非破壊を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromMarketContext 子時間足市場コンテキスト
 * @param fromWaveList 入力Wave一覧
 * @param fromLeftPoint 親区間の古い側境界
 * @param fromRightPoint 親区間の新しい側境界
 * @param fromIsUptrend 親区間が上昇の場合true
 * @param fromIsMotive 親区間が推進波の場合true
 */
void assertAccepted(
    const string fromCaseName,
    MarketContext &fromMarketContext,
    CArrayObj &fromWaveList,
    ZigZagPoint &fromLeftPoint,
    ZigZagPoint &fromRightPoint,
    const bool fromIsUptrend,
    const bool fromIsMotive
) {
    string signature = createWaveListSignature(fromWaveList);
    CArrayObj outputPointList;
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromThreeWaveContinuationRange(
        fromMarketContext,
        fromWaveList,
        0,
        2,
        fromLeftPoint,
        fromRightPoint,
        fromIsUptrend,
        fromIsMotive,
        outputPointList
    );

    assertCondition(fromCaseName + " accepted", result);
    assertCondition(
        fromCaseName + " error empty",
        builder.getErrorMessage() == ""
    );
    assertCondition(
        fromCaseName + " four anchors",
        outputPointList.Total() == 4
    );
    assertCondition(
        fromCaseName + " cloned",
        areOutputPointsCloned(fromWaveList, outputPointList)
    );
    assertCondition(
        fromCaseName + " input unchanged",
        createWaveListSignature(fromWaveList) == signature
    );
}

/**
 * H4親上昇推進区間のH1三分割を統合できることを検証する。
 */
void validateUpSuccess() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.10 00:00:00';
    CArrayObj waveList;
    CArrayObj outputPointList;
    assertCondition(
        "UP fixture",
        createThreeWaveList(context, baseTime, true, true, waveList)
    );

    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );

    string signature = createWaveListSignature(waveList);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromThreeWaveContinuationRange(
        context,
        waveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        outputPointList
    );

    assertCondition("UP build", result);
    assertCondition("UP error empty", builder.getErrorMessage() == "");
    assertSuccessfulOutput(
        "UP",
        context,
        outputPointList,
        baseTime,
        true
    );
    assertCondition(
        "UP cloned",
        areOutputPointsCloned(waveList, outputPointList)
    );
    assertCondition(
        "UP immutable",
        createWaveListSignature(waveList) == signature
    );
}

/**
 * M15親下降修正区間のM5三分割を統合できることを検証する。
 */
void validateDownSuccess() {
    MarketContext context("TEST", PERIOD_M5, "M5", 5);
    MarketContext higherContext("TEST", PERIOD_M15, "M15", 5);
    datetime baseTime = D'2026.08.11 00:00:00';
    CArrayObj waveList;
    CArrayObj outputPointList;
    assertCondition(
        "DOWN fixture",
        createThreeWaveList(context, baseTime, false, false, waveList)
    );

    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 45 * 60,
        1.35000,
        1.10000,
        false
    );

    string signature = createWaveListSignature(waveList);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromThreeWaveContinuationRange(
        context,
        waveList,
        0,
        2,
        leftPoint,
        rightPoint,
        false,
        false,
        outputPointList
    );

    assertCondition("DOWN build", result);
    assertCondition("DOWN error empty", builder.getErrorMessage() == "");
    assertSuccessfulOutput(
        "DOWN",
        context,
        outputPointList,
        baseTime,
        false
    );
    assertCondition(
        "DOWN cloned",
        areOutputPointsCloned(waveList, outputPointList)
    );
    assertCondition(
        "DOWN immutable",
        createWaveListSignature(waveList) == signature
    );
}

/**
 * 対象範囲が厳密に3Waveであることを検証する。
 */
void validateRangeConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.12 00:00:00';
    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );

    CArrayObj twoWaveList;
    createThreeWaveList(context, baseTime, true, true, twoWaveList);
    assertRejected(
        "RANGE two",
        context,
        twoWaveList,
        0,
        1,
        leftPoint,
        rightPoint,
        true,
        true,
        "three wave continuation range is invalid"
    );

    CArrayObj fourWaveList;
    createThreeWaveList(context, baseTime, true, true, fourWaveList);
    assertCondition(
        "RANGE four fixture",
        addOlderGuardWave(context, baseTime, true, fourWaveList)
    );
    assertCondition("RANGE four total", fourWaveList.Total() == 4);
    assertRejected(
        "RANGE four",
        context,
        fourWaveList,
        0,
        3,
        leftPoint,
        rightPoint,
        true,
        true,
        "three wave continuation range is invalid"
    );
}

/**
 * 方向およびWave種別の不一致が拒否されることを検証する。
 */
void validateWaveAttributeConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.13 00:00:00';
    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );

    CArrayObj directionWaveList;
    createThreeWaveList(context, baseTime, true, true, directionWaveList);
    Wave *directionMiddleWave = directionWaveList.At(1);
    directionMiddleWave.isUptrend = true;
    assertRejected(
        "ATTRIBUTE direction",
        context,
        directionWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "three wave continuation direction mismatch"
    );

    CArrayObj motiveWaveList;
    createThreeWaveList(context, baseTime, true, true, motiveWaveList);
    Wave *motiveMiddleWave = motiveWaveList.At(1);
    motiveMiddleWave.isMotive = false;
    assertRejected(
        "ATTRIBUTE motive",
        context,
        motiveWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "three wave continuation motive type mismatch"
    );

}

/**
 * 共有境界、補完ポイントおよび親境界の不一致を検証する。
 */
void validateBoundaryConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.14 00:00:00';
    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );

    CArrayObj sharedBoundaryWaveList;
    createThreeWaveList(
        context,
        baseTime,
        true,
        true,
        sharedBoundaryWaveList
    );
    Wave *sharedMiddleWave = sharedBoundaryWaveList.At(1);
    ZigZagPoint *sharedPoint = sharedMiddleWave.zigZagPointList.At(0);
    sharedPoint.rate = 1.25100;
    assertRejected(
        "BOUNDARY shared",
        context,
        sharedBoundaryWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "shared wave boundary mismatch"
    );

    CArrayObj addedPointWaveList;
    createThreeWaveList(context, baseTime, true, true, addedPointWaveList);
    Wave *addedOlderWave = addedPointWaveList.At(2);
    ZigZagPoint *addedPoint = addedOlderWave.zigZagPointList.At(2);
    addedPoint.isAddedPoint = true;
    assertRejected(
        "BOUNDARY added",
        context,
        addedPointWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "added point is not allowed"
    );

    CArrayObj higherAddedWaveList;
    createThreeWaveList(context, baseTime, true, true, higherAddedWaveList);
    ZigZagPoint higherAddedLeftPoint(higherContext);
    ZigZagPoint higherAddedRightPoint(higherContext);
    setHigherPoints(
        higherAddedLeftPoint,
        higherAddedRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );
    higherAddedLeftPoint.isAddedPoint = true;
    assertRejected(
        "BOUNDARY higher added",
        context,
        higherAddedWaveList,
        0,
        2,
        higherAddedLeftPoint,
        higherAddedRightPoint,
        true,
        true,
        "three wave continuation higher added point is not allowed"
    );

    CArrayObj parentBoundaryWaveList;
    createThreeWaveList(
        context,
        baseTime,
        true,
        true,
        parentBoundaryWaveList
    );
    ZigZagPoint missingRightPoint(higherContext);
    ZigZagPoint parentLeftPoint(higherContext);
    setHigherPoints(
        parentLeftPoint,
        missingRightPoint,
        baseTime,
        baseTime + 12 * 3600,
        1.10000,
        1.35000,
        true
    );
    assertRejected(
        "BOUNDARY parent",
        context,
        parentBoundaryWaveList,
        0,
        2,
        parentLeftPoint,
        missingRightPoint,
        true,
        true,
        "three wave continuation right boundary not found"
    );
}

/**
 * 時系列および山谷交互の不正が拒否されることを検証する。
 */
void validatePointSequenceConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.15 00:00:00';
    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );

    CArrayObj timeWaveList;
    createThreeWaveList(context, baseTime, true, true, timeWaveList);
    Wave *timeOlderWave = timeWaveList.At(2);
    ZigZagPoint *previousTimePoint = timeOlderWave.zigZagPointList.At(1);
    ZigZagPoint *invalidTimePoint = timeOlderWave.zigZagPointList.At(2);
    invalidTimePoint.barTime = previousTimePoint.barTime;
    invalidTimePoint.barTimeNext = previousTimePoint.barTimeNext;
    assertRejected(
        "SEQUENCE time",
        context,
        timeWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "point time is not strictly ascending"
    );

    CArrayObj peakWaveList;
    createThreeWaveList(context, baseTime, true, true, peakWaveList);
    Wave *peakMiddleWave = peakWaveList.At(1);
    ZigZagPoint *invalidPeakPoint = peakMiddleWave.zigZagPointList.At(1);
    invalidPeakPoint.isPeak = true;
    assertRejected(
        "SEQUENCE peak",
        context,
        peakWaveList,
        0,
        2,
        leftPoint,
        rightPoint,
        true,
        true,
        "peak and bottom do not alternate"
    );
}

/**
 * 4アンカーがダウ理論の継続形状を満たすことを検証する。
 */
void validateAnchorPriceConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.16 00:00:00';

    CArrayObj upOriginWaveList;
    assertCondition(
        "PRICE UP origin fixture",
        createThreeWaveList(
            context,
            baseTime,
            true,
            true,
            upOriginWaveList
        )
            && setAnchorRate(upOriginWaveList, 2, 1.09000)
    );
    ZigZagPoint upOriginLeftPoint(higherContext);
    ZigZagPoint upOriginRightPoint(higherContext);
    setHigherPoints(
        upOriginLeftPoint,
        upOriginRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.35000,
        true
    );
    assertRejected(
        "PRICE UP origin",
        context,
        upOriginWaveList,
        0,
        2,
        upOriginLeftPoint,
        upOriginRightPoint,
        true,
        true,
        "point 2 breaks origin"
    );

    CArrayObj upExtensionWaveList;
    assertCondition(
        "PRICE UP extension fixture",
        createThreeWaveList(
            context,
            baseTime,
            true,
            true,
            upExtensionWaveList
        )
            && setAnchorRate(upExtensionWaveList, 3, 1.25000)
    );
    ZigZagPoint upExtensionLeftPoint(higherContext);
    ZigZagPoint upExtensionRightPoint(higherContext);
    setHigherPoints(
        upExtensionLeftPoint,
        upExtensionRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.10000,
        1.25000,
        true
    );
    assertRejected(
        "PRICE UP extension",
        context,
        upExtensionWaveList,
        0,
        2,
        upExtensionLeftPoint,
        upExtensionRightPoint,
        true,
        true,
        "point 3 does not extend point 1"
    );

    CArrayObj downOriginWaveList;
    assertCondition(
        "PRICE DOWN origin fixture",
        createThreeWaveList(
            context,
            baseTime,
            false,
            true,
            downOriginWaveList
        )
            && setAnchorRate(downOriginWaveList, 2, 1.36000)
    );
    ZigZagPoint downOriginLeftPoint(higherContext);
    ZigZagPoint downOriginRightPoint(higherContext);
    setHigherPoints(
        downOriginLeftPoint,
        downOriginRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.35000,
        1.10000,
        false
    );
    assertRejected(
        "PRICE DOWN origin",
        context,
        downOriginWaveList,
        0,
        2,
        downOriginLeftPoint,
        downOriginRightPoint,
        false,
        true,
        "point 2 breaks origin"
    );

    CArrayObj downExtensionWaveList;
    assertCondition(
        "PRICE DOWN extension fixture",
        createThreeWaveList(
            context,
            baseTime,
            false,
            true,
            downExtensionWaveList
        )
            && setAnchorRate(downExtensionWaveList, 3, 1.20000)
    );
    ZigZagPoint downExtensionLeftPoint(higherContext);
    ZigZagPoint downExtensionRightPoint(higherContext);
    setHigherPoints(
        downExtensionLeftPoint,
        downExtensionRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        1.35000,
        1.20000,
        false
    );
    assertRejected(
        "PRICE DOWN extension",
        context,
        downExtensionWaveList,
        0,
        2,
        downExtensionLeftPoint,
        downExtensionRightPoint,
        false,
        true,
        "point 3 does not extend point 1"
    );
}

/**
 * 新2のFibonacci深さ境界を上下両方向で検証する。
 */
void validateAnchorRetracementConditions() {
    MarketContext context("TEST", PERIOD_H1, "H1", 5);
    MarketContext higherContext("TEST", PERIOD_H4, "H4", 5);
    datetime baseTime = D'2026.08.17 00:00:00';
    double maximumPercent = ZigZagElliotAnalysisProfile
        ::getRecountMaxCorrectionPercent();
    double validPercent = maximumPercent - 0.1;
    double upPoint0Rate = 1.10000;
    double upPoint1Rate = 1.25000;
    double downPoint0Rate = 1.35000;
    double downPoint1Rate = 1.20000;
    double upDeepPoint2Rate = NormalizeDouble(
        upPoint1Rate
            - (upPoint1Rate - upPoint0Rate) * maximumPercent / 100.0,
        context.digits
    );
    double downDeepPoint2Rate = NormalizeDouble(
        downPoint1Rate
            + (downPoint0Rate - downPoint1Rate) * maximumPercent / 100.0,
        context.digits
    );
    double upValidPoint2Rate = NormalizeDouble(
        upPoint1Rate
            - (upPoint1Rate - upPoint0Rate) * validPercent / 100.0,
        context.digits
    );
    double downValidPoint2Rate = NormalizeDouble(
        downPoint1Rate
            + (downPoint0Rate - downPoint1Rate) * validPercent / 100.0,
        context.digits
    );

    CArrayObj upDeepWaveList;
    assertCondition(
        "F2 UP deep fixture",
        createThreeWaveList(
            context,
            baseTime,
            true,
            true,
            upDeepWaveList
        )
            && setAnchorRate(upDeepWaveList, 2, upDeepPoint2Rate)
    );
    ZigZagPoint upDeepLeftPoint(higherContext);
    ZigZagPoint upDeepRightPoint(higherContext);
    setHigherPoints(
        upDeepLeftPoint,
        upDeepRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        upPoint0Rate,
        1.35000,
        true
    );
    assertRejected(
        "F2 UP deep",
        context,
        upDeepWaveList,
        0,
        2,
        upDeepLeftPoint,
        upDeepRightPoint,
        true,
        true,
        "point 2 retracement is too deep"
    );

    CArrayObj downDeepWaveList;
    assertCondition(
        "F2 DOWN deep fixture",
        createThreeWaveList(
            context,
            baseTime,
            false,
            true,
            downDeepWaveList
        )
            && setAnchorRate(downDeepWaveList, 2, downDeepPoint2Rate)
    );
    ZigZagPoint downDeepLeftPoint(higherContext);
    ZigZagPoint downDeepRightPoint(higherContext);
    setHigherPoints(
        downDeepLeftPoint,
        downDeepRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        downPoint0Rate,
        1.10000,
        false
    );
    assertRejected(
        "F2 DOWN deep",
        context,
        downDeepWaveList,
        0,
        2,
        downDeepLeftPoint,
        downDeepRightPoint,
        false,
        true,
        "point 2 retracement is too deep"
    );

    CArrayObj upValidWaveList;
    assertCondition(
        "F2 UP valid fixture",
        createThreeWaveList(
            context,
            baseTime,
            true,
            true,
            upValidWaveList
        )
            && setAnchorRate(upValidWaveList, 2, upValidPoint2Rate)
    );
    ZigZagPoint upValidLeftPoint(higherContext);
    ZigZagPoint upValidRightPoint(higherContext);
    setHigherPoints(
        upValidLeftPoint,
        upValidRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        upPoint0Rate,
        1.35000,
        true
    );
    assertAccepted(
        "F2 UP valid",
        context,
        upValidWaveList,
        upValidLeftPoint,
        upValidRightPoint,
        true,
        true
    );

    CArrayObj downValidWaveList;
    assertCondition(
        "F2 DOWN valid fixture",
        createThreeWaveList(
            context,
            baseTime,
            false,
            true,
            downValidWaveList
        )
            && setAnchorRate(downValidWaveList, 2, downValidPoint2Rate)
    );
    ZigZagPoint downValidLeftPoint(higherContext);
    ZigZagPoint downValidRightPoint(higherContext);
    setHigherPoints(
        downValidLeftPoint,
        downValidRightPoint,
        baseTime,
        baseTime + 8 * 3600,
        downPoint0Rate,
        1.10000,
        false
    );
    assertAccepted(
        "F2 DOWN valid",
        context,
        downValidWaveList,
        downValidLeftPoint,
        downValidRightPoint,
        false,
        true
    );
}

/**
 * 4アンカーからWaveを生成して再分析結果を検証する。
 *
 * @param fromCaseName 検証名
 * @param fromBaseTime 基準時刻
 * @param fromIsUptrend 上昇波の場合true
 * @param fromIsMotive 推進波の場合true
 */
void validateAnalyzedWaveCase(
    const string fromCaseName,
    const datetime fromBaseTime,
    const bool fromIsUptrend,
    const bool fromIsMotive
) {
    MarketContext context(_Symbol, PERIOD_H1, "H1", 5);
    MarketContext higherContext(_Symbol, PERIOD_H4, "H4", 5);
    CArrayObj waveList;
    CArrayObj outputPointList;
    assertCondition(
        fromCaseName + " symbol point",
        context.getPoint() > 0
    );
    assertCondition(
        fromCaseName + " fixture",
        createThreeWaveList(
            context,
            fromBaseTime,
            fromIsUptrend,
            fromIsMotive,
            waveList
        )
    );
    setOldAnalysisValues(waveList);

    double leftRate = 1.35000;
    double rightRate = 1.10000;

    if (fromIsUptrend) {
        leftRate = 1.10000;
        rightRate = 1.35000;
    }

    ZigZagPoint leftPoint(higherContext);
    ZigZagPoint rightPoint(higherContext);
    setHigherPoints(
        leftPoint,
        rightPoint,
        fromBaseTime,
        fromBaseTime + 8 * 3600,
        leftRate,
        rightRate,
        fromIsUptrend
    );

    string signature = createWaveListSignature(waveList);
    ElliotHigherSegmentPointListBuilder builder;
    bool result = builder.buildFromThreeWaveContinuationRange(
        context,
        waveList,
        0,
        2,
        leftPoint,
        rightPoint,
        fromIsUptrend,
        fromIsMotive,
        outputPointList
    );

    assertCondition(fromCaseName + " build", result);
    assertCondition(
        fromCaseName + " error empty",
        builder.getErrorMessage() == ""
    );
    assertCondition(
        fromCaseName + " input unchanged",
        createWaveListSignature(waveList) == signature
    );
    assertCondition(
        fromCaseName + " old analysis reset",
        areAnchorAnalysisValuesReset(outputPointList)
    );
    assertSuccessfulOutput(
        fromCaseName,
        context,
        outputPointList,
        fromBaseTime,
        fromIsUptrend
    );

    if (!result || outputPointList.Total() != 4) {
        return;
    }

    Wave analyzedWave(
        context,
        outputPointList,
        fromIsMotive,
        fromIsUptrend
    );
    analyzedWave.analyze();
    assertCondition(
        fromCaseName + " analyzed total",
        analyzedWave.zigZagPointList.Total() == 4
    );

    if (analyzedWave.zigZagPointList.Total() != 4) {
        return;
    }

    for (int i = 0; i < 4; i++) {
        ZigZagPoint *point = analyzedWave.zigZagPointList.At(i);
        bool isMatched = CheckPointer(point) != POINTER_INVALID;

        if (isMatched) {
            isMatched = point.elliotIndex == i
                && point.elliotLabel
                    == getExpectedAnalyzedLabel(i, fromIsMotive)
                && point.isElliotAlphabet != fromIsMotive
                && point.subElliotIndex == 0
                && StringLen(point.subElliotLabel) == 0
                && point.orgElliotIndex == 0
                && point.orgElliotLabel == ""
                && point.waveBarsFromStart != 999
                && point.pipsDiff != 999.9
                && point.fibonacciPercent != 99.9
                && point.fiboDepthZone != FIBO_DEPTH_INVALID
                && point.fiboDepthZoneLabel != "OLD_DEPTH"
                && point.fibonacciExpansionPercent != 999.9;
        }

        assertCondition(
            fromCaseName + " analyzed point " + IntegerToString(i),
            isMatched
        );
    }

    ZigZagPoint *point0 = analyzedWave.zigZagPointList.At(0);
    ZigZagPoint *point1 = analyzedWave.zigZagPointList.At(1);
    ZigZagPoint *point2 = analyzedWave.zigZagPointList.At(2);
    ZigZagPoint *point3 = analyzedWave.zigZagPointList.At(3);
    bool isDerivedValueValid
        = CheckPointer(point0) != POINTER_INVALID
            && CheckPointer(point1) != POINTER_INVALID
            && CheckPointer(point2) != POINTER_INVALID
            && CheckPointer(point3) != POINTER_INVALID;

    if (isDerivedValueValid) {
        isDerivedValueValid = point0.pipsDiff == 0
            && point0.fibonacciPercent == 0
            && point0.fibonacciExpansionPercent == 0
            && point1.pipsDiff > 0
            && point1.fibonacciPercent == 0
            && point1.fibonacciExpansionPercent == 0
            && point2.pipsDiff > 0
            && point2.fibonacciPercent > 0
            && point2.fibonacciExpansionPercent == 0
            && point3.pipsDiff > 0
            && point3.fibonacciPercent == 0
            && point3.fibonacciExpansionPercent > 0;
    }

    assertCondition(
        fromCaseName + " derived values recalculated",
        isDerivedValueValid
    );

    if (fromIsMotive && CheckPointer(point2) != POINTER_INVALID) {
        assertCondition(
            fromCaseName + " point 2 retracement below limit",
            point2.fibonacciPercent
                < ZigZagElliotAnalysisProfile
                    ::getRecountMaxCorrectionPercent()
        );
    }
}

/**
 * 上下方向の推進波と修正波を4アンカーから再分析できることを検証する。
 */
void validateAnalyzedWaveResults() {
    validateAnalyzedWaveCase(
        "ANALYZE motive UP",
        D'2026.08.18 00:00:00',
        true,
        true
    );
    validateAnalyzedWaveCase(
        "ANALYZE motive DOWN",
        D'2026.08.19 00:00:00',
        false,
        true
    );
    validateAnalyzedWaveCase(
        "ANALYZE correction UP",
        D'2026.08.20 00:00:00',
        true,
        false
    );
    validateAnalyzedWaveCase(
        "ANALYZE correction DOWN",
        D'2026.08.21 00:00:00',
        false,
        false
    );
}

/**
 * 親区間内3Wave継続統合のSmoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateUpSuccess();
    validateDownSuccess();
    validateRangeConditions();
    validateWaveAttributeConditions();
    validateBoundaryConditions();
    validatePointSequenceConditions();
    validateAnchorPriceConditions();
    validateAnchorRetracementConditions();
    validateAnalyzedWaveResults();

    if (gFailureCount == 0) {
        Print("ElliotHigherSegmentThreeWaveContinuationSmokeTest PASS");
        return;
    }

    PrintFormat(
        "ElliotHigherSegmentThreeWaveContinuationSmokeTest FAIL count=%d",
        gFailureCount
    );
}
