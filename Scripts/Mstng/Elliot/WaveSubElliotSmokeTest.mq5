//+------------------------------------------------------------------+
//|                                      WaveSubElliotSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

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
 * Waveへ検証用ポイントを追加する。
 *
 * @param fromWave 追加先Wave
 * @param fromElliotIndex Elliott波動番号
 * @param fromIsAlphabet アルファベット波の場合true
 * @param fromSubElliotIndex 下位波動番号
 * @param fromSubElliotLabel 下位波動ラベル
 * @return 追加に成功した場合true
 */
bool addPoint(
    Wave &fromWave,
    const int fromElliotIndex,
    const bool fromIsAlphabet,
    const int fromSubElliotIndex,
    const string fromSubElliotLabel
) {
    ZigZagPoint *zigZagPoint = new ZigZagPoint();

    if (zigZagPoint == NULL) {
        return false;
    }

    zigZagPoint.elliotIndex = fromElliotIndex;
    zigZagPoint.isElliotAlphabet = fromIsAlphabet;
    zigZagPoint.subElliotIndex = fromSubElliotIndex;
    zigZagPoint.subElliotLabel = fromSubElliotLabel;

    if (!fromWave.zigZagPointList.Add(zigZagPoint)) {
        delete zigZagPoint;

        return false;
    }

    return true;
}

/**
 * 第3波の下位波動番号またはラベルによる検出を確認する。
 */
void validateSubElliotDetection() {
    Wave indexWave;
    indexWave.isMotive = true;
    assertCondition("add index point",
        addPoint(indexWave, 3, false, 1, ""));
    assertCondition("sub index", indexWave.hasSubElliot(3));

    Wave labelWave;
    labelWave.isMotive = true;
    assertCondition("add label point",
        addPoint(labelWave, 3, false, 0, "iii"));
    assertCondition("sub label", labelWave.hasSubElliot(3));

    Wave bothWave;
    bothWave.isMotive = true;
    assertCondition("add both point",
        addPoint(bothWave, 3, false, 3, "iii"));
    assertCondition("sub index and label", bothWave.hasSubElliot(3));
}

/**
 * 第3波以外の下位波動および未設定状態を除外することを確認する。
 */
void validateSubElliotExclusion() {
    Wave emptyWave;
    emptyWave.isMotive = true;
    assertCondition("empty wave", !emptyWave.hasSubElliot(3));
    assertCondition("invalid target", !emptyWave.hasSubElliot(0));

    Wave noSubWave;
    noSubWave.isMotive = true;
    assertCondition("add no sub point",
        addPoint(noSubWave, 3, false, 0, ""));
    assertCondition("no sub", !noSubWave.hasSubElliot(3));

    Wave otherWave;
    otherWave.isMotive = true;
    assertCondition("add other point",
        addPoint(otherWave, 1, false, 1, "i"));
    assertCondition("other main wave", !otherWave.hasSubElliot(3));

    Wave alphabetWave;
    assertCondition("add alphabet point",
        addPoint(alphabetWave, 3, true, 3, "iii"));
    assertCondition("alphabet C wave", !alphabetWave.hasSubElliot(3));
}

/**
 * 現在第5波と過去第3波の組み合わせを確認する。
 */
void validateCurrentWaveFiveCondition() {
    Wave waveFive;
    waveFive.isMotive = true;
    assertCondition("add wave three sub",
        addPoint(waveFive, 3, false, 3, "iii"));
    assertCondition("add current wave five",
        addPoint(waveFive, 5, false, 0, ""));
    assertCondition(
        "current wave five with wave three sub",
        waveFive.hasSubElliot(5, 3)
    );

    Wave waveFiveWithoutSub;
    waveFiveWithoutSub.isMotive = true;
    assertCondition("add wave three without sub",
        addPoint(waveFiveWithoutSub, 3, false, 0, ""));
    assertCondition("add wave five without sub",
        addPoint(waveFiveWithoutSub, 5, false, 0, ""));
    assertCondition(
        "current wave five without wave three sub",
        !waveFiveWithoutSub.hasSubElliot(5, 3)
    );

    Wave waveFiveWithOtherSub;
    waveFiveWithOtherSub.isMotive = true;
    assertCondition("add wave one sub",
        addPoint(waveFiveWithOtherSub, 1, false, 1, "i"));
    assertCondition("add wave three no sub",
        addPoint(waveFiveWithOtherSub, 3, false, 0, ""));
    assertCondition("add wave five after other sub",
        addPoint(waveFiveWithOtherSub, 5, false, 0, ""));
    assertCondition(
        "other wave sub does not match wave three",
        !waveFiveWithOtherSub.hasSubElliot(5, 3)
    );

    Wave waveThree;
    waveThree.isMotive = true;
    assertCondition("add current wave three",
        addPoint(waveThree, 3, false, 3, "iii"));
    assertCondition(
        "current wave is not five",
        !waveThree.hasSubElliot(5, 3)
    );

    Wave correctionE;
    assertCondition("add correction C",
        addPoint(correctionE, 3, true, 3, "iii"));
    assertCondition("add correction E",
        addPoint(correctionE, 5, true, 0, ""));
    assertCondition(
        "correction E is not numeric wave five",
        !correctionE.hasSubElliot(5, 3)
    );
}

/**
 * Wave下位波動判定のSmoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateSubElliotDetection();
    validateSubElliotExclusion();
    validateCurrentWaveFiveCondition();

    if (gFailureCount == 0) {
        Print("WaveSubElliotSmokeTest PASS");
        return;
    }

    PrintFormat(
        "WaveSubElliotSmokeTest FAIL count=%d",
        gFailureCount
    );
}
