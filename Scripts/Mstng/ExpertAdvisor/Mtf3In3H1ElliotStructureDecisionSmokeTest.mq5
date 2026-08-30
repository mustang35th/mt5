//+------------------------------------------------------------------+
//|              Mtf3In3H1ElliotStructureDecisionSmokeTest.mq5     |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>

/** 失敗した検証項目数。 */
int gFailureCount = 0;

/**
 * 数字Elliottポイントを一覧へ追加する。
 *
 * @param fromPointList 追加先ポイント一覧。
 * @param fromMarketContext 市場コンテキスト。
 * @param fromElliotIndex Elliott波動番号。
 * @param fromSubElliotIndex 副次波番号。
 * @param fromSubElliotLabel 副次波ラベル。
 * @return 追加に成功した場合true。
 */
bool addPoint(
    CArrayObj &fromPointList,
    MarketContext &fromMarketContext,
    const int fromElliotIndex,
    const int fromSubElliotIndex,
    const string fromSubElliotLabel
) {
    ZigZagPoint *point = new ZigZagPoint(fromMarketContext);

    if (point == NULL) {
        return false;
    }

    point.elliotIndex = fromElliotIndex;
    point.isElliotAlphabet = false;
    point.setElliotLabel();
    point.subElliotIndex = fromSubElliotIndex;
    point.subElliotLabel = fromSubElliotLabel;

    if (!fromPointList.Add(point)) {
        delete point;

        return false;
    }

    return true;
}

/**
 * BUY方向の推進Waveを持つテスト用Elliotを生成する。
 *
 * @param fromTimeFrame 対象時間足。
 * @param fromCurrentElliotIndex 最新Elliott波動番号。
 * @param fromIncludeWave3 第3波ポイントを含める場合true。
 * @param fromWave3SubElliotIndex 第3波の副次波番号。
 * @param fromWave3SubElliotLabel 第3波の副次波ラベル。
 * @return 呼び出し側が所有するElliot。生成失敗時NULL。
 */
Elliot *createElliot(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const int fromCurrentElliotIndex,
    const bool fromIncludeWave3,
    const int fromWave3SubElliotIndex,
    const string fromWave3SubElliotLabel
) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    elliot.isBuy = true;
    elliot.buySellLabel = "BUY";
    elliot.oscillator.isBuy = true;
    CArrayObj pointList;
    bool isCreated = true;

    if (fromIncludeWave3) {
        isCreated = addPoint(
            pointList,
            elliot.marketContext,
            3,
            fromWave3SubElliotIndex,
            fromWave3SubElliotLabel
        );
    }

    if (isCreated) {
        isCreated = addPoint(
            pointList,
            elliot.marketContext,
            fromCurrentElliotIndex,
            0,
            ""
        );
    }

    if (!isCreated) {
        delete elliot;

        return NULL;
    }

    Wave *wave = new Wave(
        elliot.marketContext,
        pointList,
        true,
        true
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
 * D1、H4およびH1を持つテスト用分析結果を生成する。
 *
 * D1は第1波とし、H4およびH1の推進Waveが親子条件を満たすようにする。
 *
 * @param fromH4ElliotIndex H4の最新Elliott波動番号。
 * @param fromIncludeH4Wave3 H4に第3波ポイントを含める場合true。
 * @param fromH4Wave3SubElliotIndex H4第3波の副次波番号。
 * @param fromH4Wave3SubElliotLabel H4第3波の副次波ラベル。
 * @param fromH1ElliotIndex H1の最新Elliott波動番号。
 * @param fromIncludeH1Wave3 H1に第3波ポイントを含める場合true。
 * @param fromH1Wave3SubElliotIndex H1第3波の副次波番号。
 * @param fromH1Wave3SubElliotLabel H1第3波の副次波ラベル。
 * @return 呼び出し側が所有する分析結果。生成失敗時NULL。
 */
ElliotAll *createElliotAll(
    const int fromH4ElliotIndex,
    const bool fromIncludeH4Wave3,
    const int fromH4Wave3SubElliotIndex,
    const string fromH4Wave3SubElliotLabel,
    const int fromH1ElliotIndex,
    const bool fromIncludeH1Wave3,
    const int fromH1Wave3SubElliotIndex,
    const string fromH1Wave3SubElliotLabel
) {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_H1);
    Elliot *elliotD1 = createElliot(PERIOD_D1, 1, false, 0, "");
    Elliot *elliotH4 = createElliot(
        PERIOD_H4,
        fromH4ElliotIndex,
        fromIncludeH4Wave3,
        fromH4Wave3SubElliotIndex,
        fromH4Wave3SubElliotLabel
    );
    Elliot *elliotH1 = createElliot(
        PERIOD_H1,
        fromH1ElliotIndex,
        fromIncludeH1Wave3,
        fromH1Wave3SubElliotIndex,
        fromH1Wave3SubElliotLabel
    );

    if (elliotAll == NULL
            || elliotD1 == NULL
            || elliotH4 == NULL
            || elliotH1 == NULL) {
        if (elliotD1 != NULL) {
            delete elliotD1;
        }
        if (elliotH4 != NULL) {
            delete elliotH4;
        }
        if (elliotH1 != NULL) {
            delete elliotH1;
        }
        if (elliotAll != NULL) {
            delete elliotAll;
        }

        return NULL;
    }

    if (!elliotAll.elliotList.Add(elliotD1)) {
        delete elliotD1;
        delete elliotH4;
        delete elliotH1;
        delete elliotAll;

        return NULL;
    }

    if (!elliotAll.elliotList.Add(elliotH4)) {
        delete elliotH4;
        delete elliotH1;
        delete elliotAll;

        return NULL;
    }

    if (!elliotAll.elliotList.Add(elliotH1)) {
        delete elliotH1;
        delete elliotAll;

        return NULL;
    }

    elliotAll.elliotCurrent = elliotH1;
    elliotAll.isAnalysisSucceeded = true;

    return elliotAll;
}

/**
 * Structure判定結果を期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromResult 実際の判定結果。
 * @param fromExpectedRank 期待する構造ランク。
 * @param fromExpectedStructureValid 構造有効状態の期待値。
 * @param fromExpectedH4Label H4ラベルの期待値。
 * @param fromExpectedH1Label H1ラベルの期待値。
 * @param fromExpectedRankLabel ランク表示の期待値。
 * @param fromExpectedDisplayLabel 詳細表示の期待値。
 */
void assertStructure(
    const string fromCaseName,
    Mtf3In3H1ElliotStructureResult &fromResult,
    const Mtf3In3H1ElliotStructureRank fromExpectedRank,
    const bool fromExpectedStructureValid,
    const string fromExpectedH4Label,
    const string fromExpectedH1Label,
    const string fromExpectedRankLabel,
    const string fromExpectedDisplayLabel
) {
    bool isMatched = fromResult.rank == fromExpectedRank
        && fromResult.isEvaluated
        && fromResult.isStructureValid == fromExpectedStructureValid
        && fromResult.isLate
        && !fromResult.isDirectionException
        && fromResult.d1WaveType == "MOTIVE"
        && fromResult.d1ElliotLabel == "1"
        && fromResult.h4WaveType == "MOTIVE"
        && fromResult.h4ElliotLabel == fromExpectedH4Label
        && fromResult.h1ElliotLabel == fromExpectedH1Label
        && fromResult.getRankLabel() == fromExpectedRankLabel
        && fromResult.getDisplayLabel() == fromExpectedDisplayLabel;

    if (isMatched) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s rank=%s evaluated=%s valid=%s late=%s dir=%s "
        + "d1=%s/%s h4=%s/%s h1=%s display=%s",
        fromCaseName,
        fromResult.getRankLabel(),
        (string)fromResult.isEvaluated,
        (string)fromResult.isStructureValid,
        (string)fromResult.isLate,
        (string)fromResult.isDirectionException,
        fromResult.d1WaveType,
        fromResult.d1ElliotLabel,
        fromResult.h4WaveType,
        fromResult.h4ElliotLabel,
        fromResult.h1ElliotLabel,
        fromResult.getDisplayLabel()
    );
}

/**
 * 1件のStructure判定を実行して検証する。
 *
 * @param fromCaseName ケース名。
 * @param fromElliotAll 判定対象。検証後に解放する。
 * @param fromExpectedRank 期待する構造ランク。
 * @param fromExpectedStructureValid 構造有効状態の期待値。
 * @param fromExpectedH4Label H4ラベルの期待値。
 * @param fromExpectedH1Label H1ラベルの期待値。
 * @param fromExpectedRankLabel ランク表示の期待値。
 * @param fromExpectedDisplayLabel 詳細表示の期待値。
 */
void validateStructure(
    const string fromCaseName,
    ElliotAll *fromElliotAll,
    const Mtf3In3H1ElliotStructureRank fromExpectedRank,
    const bool fromExpectedStructureValid,
    const string fromExpectedH4Label,
    const string fromExpectedH1Label,
    const string fromExpectedRankLabel,
    const string fromExpectedDisplayLabel
) {
    if (fromElliotAll == NULL) {
        gFailureCount++;
        Print("FAIL " + fromCaseName + " fixture");

        return;
    }

    Mtf3In3H1ElliotStructureDecision decision;
    Mtf3In3H1ElliotStructureResult result;
    decision.evaluate(fromElliotAll, result);
    assertStructure(
        fromCaseName,
        result,
        fromExpectedRank,
        fromExpectedStructureValid,
        fromExpectedH4Label,
        fromExpectedH1Label,
        fromExpectedRankLabel,
        fromExpectedDisplayLabel
    );
    delete fromElliotAll;
}

/**
 * H1第5波の第3波構造によるStructure判定を検証する。
 */
void validateH1WaveFiveCases() {
    validateStructure(
        "H1 wave five without wave three sub",
        createElliotAll(1, false, 0, "", 5, true, 0, ""),
        mtf3In3H1ElliotStructureRankS,
        true,
        "1",
        "5",
        "S",
        "S-LATE"
    );
    validateStructure(
        "H1 wave five with wave three sub",
        createElliotAll(1, false, 0, "", 5, true, 1, ""),
        mtf3In3H1ElliotStructureRankException,
        false,
        "1",
        "5",
        "EXCEPTION",
        "EXCEPTION-LATE"
    );
    validateStructure(
        "H1 wave five missing wave three",
        createElliotAll(1, false, 0, "", 5, false, 0, ""),
        mtf3In3H1ElliotStructureRankException,
        false,
        "1",
        "5",
        "EXCEPTION",
        "EXCEPTION-LATE"
    );
}

/**
 * H4第5波の第3波構造によるStructure判定を検証する。
 */
void validateH4WaveFiveCases() {
    validateStructure(
        "H4 wave five without wave three sub",
        createElliotAll(5, true, 0, "", 1, false, 0, ""),
        mtf3In3H1ElliotStructureRankS,
        true,
        "5",
        "1",
        "S",
        "S-LATE"
    );
    validateStructure(
        "H4 wave five with wave three sub",
        createElliotAll(5, true, 0, "iii", 1, false, 0, ""),
        mtf3In3H1ElliotStructureRankException,
        false,
        "5",
        "1",
        "EXCEPTION",
        "EXCEPTION-LATE"
    );
}

/**
 * H1エントリーのElliott構造判定Smoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateH1WaveFiveCases();
    validateH4WaveFiveCases();

    if (gFailureCount == 0) {
        Print("Mtf3In3H1ElliotStructureDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "Mtf3In3H1ElliotStructureDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
