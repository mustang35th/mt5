//+------------------------------------------------------------------+
//|                         H1EntryWaveDecisionSmokeTest.mq5         |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\H1EntryWaveDecision.mqh>

/** 失敗した検証項目数。 */
int gFailureCount = 0;

/**
 * テスト用ポイントを一覧へ追加する。
 *
 * @param fromPointList 追加先ポイント一覧。
 * @param fromMarketContext 市場コンテキスト。
 * @param fromElliotIndex Elliott波動番号。
 * @param fromIsAlphabet アルファベット波の場合true。
 * @param fromSubElliotIndex 副次波番号。
 * @param fromSubElliotLabel 副次波ラベル。
 * @return 追加に成功した場合true。
 */
bool addPoint(
    CArrayObj &fromPointList,
    MarketContext &fromMarketContext,
    const int fromElliotIndex,
    const bool fromIsAlphabet,
    const int fromSubElliotIndex,
    const string fromSubElliotLabel
) {
    ZigZagPoint *point = new ZigZagPoint(fromMarketContext);

    if (point == NULL) {
        return false;
    }

    point.elliotIndex = fromElliotIndex;
    point.isElliotAlphabet = fromIsAlphabet;
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
 * 最新Waveを持つテスト用Elliotを生成する。
 *
 * 第5波ケースでは、必要に応じて同じWave内の第3波を先に追加する。
 *
 * @param fromTimeFrame 対象時間足。
 * @param fromIsMotive 推進Waveの場合true。
 * @param fromCurrentElliotIndex 最新Elliott波動番号。
 * @param fromCurrentIsAlphabet 最新ポイントがアルファベット波の場合true。
 * @param fromIncludeWave3 数字の第3波を含める場合true。
 * @param fromWave3SubElliotIndex 第3波の副次波番号。
 * @param fromWave3SubElliotLabel 第3波の副次波ラベル。
 * @param fromCurrentSubElliotIndex 最新波の副次波番号。
 * @param fromCurrentSubElliotLabel 最新波の副次波ラベル。
 * @return 呼び出し側が所有するテスト用Elliot。生成失敗時NULL。
 */
Elliot *createElliot(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const bool fromIsMotive,
    const int fromCurrentElliotIndex,
    const bool fromCurrentIsAlphabet,
    const bool fromIncludeWave3,
    const int fromWave3SubElliotIndex,
    const string fromWave3SubElliotLabel,
    const int fromCurrentSubElliotIndex = 0,
    const string fromCurrentSubElliotLabel = ""
) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    CArrayObj pointList;
    bool isCreated = true;

    if (fromIncludeWave3) {
        isCreated = addPoint(
            pointList,
            elliot.marketContext,
            3,
            false,
            fromWave3SubElliotIndex,
            fromWave3SubElliotLabel
        );
    }

    if (isCreated) {
        isCreated = addPoint(
            pointList,
            elliot.marketContext,
            fromCurrentElliotIndex,
            fromCurrentIsAlphabet,
            fromCurrentSubElliotIndex,
            fromCurrentSubElliotLabel
        );
    }

    if (!isCreated) {
        delete elliot;

        return NULL;
    }

    Wave *wave = new Wave(
        elliot.marketContext,
        pointList,
        fromIsMotive,
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
 * 判定結果をすべての期待値と照合する。
 *
 * @param fromCaseName ケース名。
 * @param fromEvaluateResult evaluate()の戻り値。
 * @param fromResult 実際の判定結果。
 * @param fromExpectedEvaluateResult 期待するevaluate()の戻り値。
 * @param fromExpectedTimeFrame 期待する時間足。
 * @param fromExpectedState 期待する状態。
 * @param fromExpectedElliotLabel 期待する最新Elliottラベル。
 * @param fromExpectedRejectReason 期待する対象外理由。
 * @param fromExpectedAvailable 取得可能状態の期待値。
 * @param fromExpectedEntryLabel エントリーラベル状態の期待値。
 * @param fromExpectedValid 波動構造有効状態の期待値。
 * @param fromExpectedWave5 第5波状態の期待値。
 * @param fromExpectedWave3 第3波存在状態の期待値。
 * @param fromExpectedWave3SubElliot 第3波副次波状態の期待値。
 * @param fromExpectedAllowed エントリー許可状態の期待値。
 */
void assertDecision(
    const string fromCaseName,
    const bool fromEvaluateResult,
    H1EntryWaveResult &fromResult,
    const bool fromExpectedEvaluateResult,
    const ENUM_TIMEFRAMES fromExpectedTimeFrame,
    const string fromExpectedState,
    const string fromExpectedElliotLabel,
    const string fromExpectedRejectReason,
    const bool fromExpectedAvailable,
    const bool fromExpectedEntryLabel,
    const bool fromExpectedValid,
    const bool fromExpectedWave5,
    const bool fromExpectedWave3,
    const bool fromExpectedWave3SubElliot,
    const bool fromExpectedAllowed
) {
    bool isMatched = fromEvaluateResult == fromExpectedEvaluateResult
        && fromResult.timeFrame == fromExpectedTimeFrame
        && fromResult.state == fromExpectedState
        && fromResult.elliotLabel == fromExpectedElliotLabel
        && fromResult.rejectReason == fromExpectedRejectReason
        && fromResult.isAvailable == fromExpectedAvailable
        && fromResult.isEntryLabel == fromExpectedEntryLabel
        && fromResult.isValid == fromExpectedValid
        && fromResult.isWave5 == fromExpectedWave5
        && fromResult.hasWave3 == fromExpectedWave3
        && fromResult.hasWave3SubElliot
            == fromExpectedWave3SubElliot
        && fromResult.isAllowed == fromExpectedAllowed;

    if (isMatched) {
        return;
    }

    gFailureCount++;
    PrintFormat(
        "FAIL %s returned=%s tf=%d state=%s label=%s reason=%s "
        + "available=%s entryLabel=%s valid=%s wave5=%s "
        + "wave3=%s wave3Sub=%s allowed=%s",
        fromCaseName,
        (string)fromEvaluateResult,
        (int)fromResult.timeFrame,
        fromResult.state,
        fromResult.elliotLabel,
        fromResult.rejectReason,
        (string)fromResult.isAvailable,
        (string)fromResult.isEntryLabel,
        (string)fromResult.isValid,
        (string)fromResult.isWave5,
        (string)fromResult.hasWave3,
        (string)fromResult.hasWave3SubElliot,
        (string)fromResult.isAllowed
    );
}

/**
 * 共通理由コードを使用して1件の判定を検証する。
 *
 * @param fromCaseName ケース名。
 * @param fromElliot 判定対象。検証後に解放する。
 * @param fromExpectedTimeFrame 期待する時間足。
 * @param fromExpectedEvaluateResult 期待するevaluate()の戻り値。
 * @param fromExpectedState 期待する状態。
 * @param fromExpectedElliotLabel 期待する最新Elliottラベル。
 * @param fromExpectedRejectReason 期待する対象外理由。
 * @param fromExpectedAvailable 取得可能状態の期待値。
 * @param fromExpectedEntryLabel エントリーラベル状態の期待値。
 * @param fromExpectedValid 波動構造有効状態の期待値。
 * @param fromExpectedWave5 第5波状態の期待値。
 * @param fromExpectedWave3 第3波存在状態の期待値。
 * @param fromExpectedWave3SubElliot 第3波副次波状態の期待値。
 * @param fromExpectedAllowed エントリー許可状態の期待値。
 */
void validateGenericDecision(
    const string fromCaseName,
    Elliot *fromElliot,
    const ENUM_TIMEFRAMES fromExpectedTimeFrame,
    const bool fromExpectedEvaluateResult,
    const string fromExpectedState,
    const string fromExpectedElliotLabel,
    const string fromExpectedRejectReason,
    const bool fromExpectedAvailable,
    const bool fromExpectedEntryLabel,
    const bool fromExpectedValid,
    const bool fromExpectedWave5,
    const bool fromExpectedWave3,
    const bool fromExpectedWave3SubElliot,
    const bool fromExpectedAllowed
) {
    H1EntryWaveDecision decision;
    H1EntryWaveResult result;
    bool isAllowed = decision.evaluate(
        fromElliot,
        fromExpectedTimeFrame,
        result
    );
    assertDecision(
        fromCaseName,
        isAllowed,
        result,
        fromExpectedEvaluateResult,
        fromExpectedTimeFrame,
        fromExpectedState,
        fromExpectedElliotLabel,
        fromExpectedRejectReason,
        fromExpectedAvailable,
        fromExpectedEntryLabel,
        fromExpectedValid,
        fromExpectedWave5,
        fromExpectedWave3,
        fromExpectedWave3SubElliot,
        fromExpectedAllowed
    );

    if (fromElliot != NULL) {
        delete fromElliot;
    }
}

/**
 * 第1波、第3波および有効な第5波の許可を検証する。
 */
void validateAllowedCases() {
    validateGenericDecision(
        "H1 wave one",
        createElliot(PERIOD_H1, true, 1, false, false, 0, ""),
        PERIOD_H1,
        true,
        "ALLOWED_1_OR_3",
        "1",
        "",
        true,
        true,
        true,
        false,
        false,
        false,
        true
    );
    validateGenericDecision(
        "H1 wave three",
        createElliot(PERIOD_H1, true, 3, false, false, 0, ""),
        PERIOD_H1,
        true,
        "ALLOWED_1_OR_3",
        "3",
        "",
        true,
        true,
        true,
        false,
        false,
        false,
        true
    );
    validateGenericDecision(
        "H1 wave five without wave three sub",
        createElliot(PERIOD_H1, true, 5, false, true, 0, ""),
        PERIOD_H1,
        true,
        "ALLOWED_5",
        "5",
        "",
        true,
        true,
        true,
        true,
        true,
        false,
        true
    );
    validateGenericDecision(
        "H1 wave five own sub ignored",
        createElliot(
            PERIOD_H1,
            true,
            5,
            false,
            true,
            0,
            "",
            1,
            "i"
        ),
        PERIOD_H1,
        true,
        "ALLOWED_5",
        "5",
        "",
        true,
        true,
        true,
        true,
        true,
        false,
        true
    );
}

/**
 * 第5波の第3波副次波および構造不正を検証する。
 */
void validateWaveFiveRejectedCases() {
    H1EntryWaveDecision decision;
    H1EntryWaveResult result;
    Elliot *elliot = createElliot(
        PERIOD_H1,
        true,
        5,
        false,
        true,
        1,
        ""
    );
    bool isAllowed = decision.evaluate(
        elliot,
        PERIOD_H1,
        "H1_ELLIOT_UNAVAILABLE",
        "H1_ELLIOT_LABEL_REJECTED",
        "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
        result
    );
    assertDecision(
        "H1 wave three sub index custom reason",
        isAllowed,
        result,
        false,
        PERIOD_H1,
        "WAVE3_SUB_ELLIOT_PRESENT",
        "5",
        "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
        true,
        true,
        true,
        true,
        true,
        true,
        false
    );
    delete elliot;

    validateGenericDecision(
        "H1 wave three sub label",
        createElliot(PERIOD_H1, true, 5, false, true, 0, "iii"),
        PERIOD_H1,
        false,
        "WAVE3_SUB_ELLIOT_PRESENT",
        "5",
        "WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
        true,
        true,
        true,
        true,
        true,
        true,
        false
    );
    validateGenericDecision(
        "H1 wave five missing wave three",
        createElliot(PERIOD_H1, true, 5, false, false, 0, ""),
        PERIOD_H1,
        false,
        "WAVE5_STRUCTURE_INVALID",
        "5",
        "ELLIOT_LABEL_REJECTED",
        true,
        true,
        false,
        true,
        false,
        false,
        false
    );
    validateGenericDecision(
        "H1 non motive wave five",
        createElliot(PERIOD_H1, false, 5, false, true, 0, ""),
        PERIOD_H1,
        false,
        "WAVE5_STRUCTURE_INVALID",
        "5",
        "ELLIOT_LABEL_REJECTED",
        true,
        true,
        false,
        true,
        false,
        false,
        false
    );
}

/**
 * ラベル、取得不能および時間足不一致を検証する。
 */
void validateUnavailableAndLabelCases() {
    validateGenericDecision(
        "H1 correction E",
        createElliot(PERIOD_H1, false, 5, true, false, 0, ""),
        PERIOD_H1,
        false,
        "LABEL_REJECTED",
        "E",
        "ELLIOT_LABEL_REJECTED",
        true,
        false,
        false,
        false,
        false,
        false,
        false
    );
    validateGenericDecision(
        "H1 wave two",
        createElliot(PERIOD_H1, true, 2, false, false, 0, ""),
        PERIOD_H1,
        false,
        "LABEL_REJECTED",
        "2",
        "ELLIOT_LABEL_REJECTED",
        true,
        false,
        false,
        false,
        false,
        false,
        false
    );
    validateGenericDecision(
        "NULL H1",
        NULL,
        PERIOD_H1,
        false,
        "UNAVAILABLE",
        "",
        "ELLIOT_UNAVAILABLE",
        false,
        false,
        false,
        false,
        false,
        false,
        false
    );
    validateGenericDecision(
        "H4 input H1 mismatch",
        createElliot(PERIOD_H4, true, 1, false, false, 0, ""),
        PERIOD_H1,
        false,
        "UNAVAILABLE",
        "",
        "ELLIOT_UNAVAILABLE",
        false,
        false,
        false,
        false,
        false,
        false,
        false
    );

    H1EntryWaveDecision decision;
    H1EntryWaveResult result;
    Elliot *elliot = createElliot(
        PERIOD_H4,
        true,
        5,
        false,
        true,
        0,
        "i"
    );
    bool isAllowed = decision.evaluate(
        elliot,
        PERIOD_H4,
        "H4_ELLIOT_UNAVAILABLE",
        "H4_ELLIOT_LABEL_REJECTED",
        "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
        result
    );
    assertDecision(
        "H4 wave three sub label custom reason",
        isAllowed,
        result,
        false,
        PERIOD_H4,
        "WAVE3_SUB_ELLIOT_PRESENT",
        "5",
        "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
        true,
        true,
        true,
        true,
        true,
        true,
        false
    );
    delete elliot;
}

/**
 * H1およびH4のエントリー波動判定Smoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateAllowedCases();
    validateWaveFiveRejectedCases();
    validateUnavailableAndLabelCases();

    if (gFailureCount == 0) {
        Print("H1EntryWaveDecisionSmokeTest PASS");

        return;
    }

    PrintFormat(
        "H1EntryWaveDecisionSmokeTest FAIL count=%d",
        gFailureCount
    );
}
