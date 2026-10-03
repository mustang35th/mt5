//+------------------------------------------------------------------+
//|                  ExpertAdvisorMtf3In3M15EntrySmokeTest.mq5         |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M15.mqh>

/** 失敗した検証項目数。 */
int gFailureCount = 0;

/**
 * 条件を検証し、失敗した項目を記録する。
 *
 * @param fromCaseName 検証名。
 * @param fromCondition 期待する条件。
 */
void assertCondition(const string fromCaseName, const bool fromCondition) {
    if (!fromCondition) {
        gFailureCount++;
        Print("FAIL " + fromCaseName);
    }
}

/**
 * 波動分析とオシレーターの方向を揃える。
 *
 * @param fromElliot 設定対象。
 * @param fromIsBuy BUY方向の場合true。
 */
void setDirection(Elliot *fromElliot, const bool fromIsBuy) {
    fromElliot.isBuy = fromIsBuy;
    fromElliot.oscillator.isBuy = fromIsBuy;
    fromElliot.buySellLabel = "SELL";
    if (fromIsBuy) {
        fromElliot.buySellLabel = "BUY";
    }
}

/**
 * EMA200の方向フラグと表示値を揃える。
 *
 * @param fromElliot 設定対象。
 * @param fromIsBuy BUY方向の場合true。
 */
void setEma200Direction(Elliot *fromElliot, const bool fromIsBuy) {
    fromElliot.oscillator.ema200.isBuy = fromIsBuy;
    fromElliot.oscillator.ema200.isSell = !fromIsBuy;
    fromElliot.oscillator.ema200.buySellLabel = "SELL";
    if (fromIsBuy) {
        fromElliot.oscillator.ema200.buySellLabel = "BUY";
    }
}

/**
 * MN1からM15までの全条件を満たす分析結果を生成する。
 *
 * 実際の相場データを読み込まず、公開analyze()の判定経路を検証する。
 * EMA200距離は旧M15上限を超える値にし、H1最新点は未確定とする。
 *
 * @param fromIsBuy BUY方向の場合true。
 * @param fromEntryWave H4、H1、M15の最新波動番号。
 * @return 呼び出し側が所有する分析結果。生成失敗時NULL。
 */
ElliotAll *createAnalysis(const bool fromIsBuy, const int fromEntryWave = 5) {
    ElliotAll *analysis = new ElliotAll("EURUSD", PERIOD_M15);
    if (analysis == NULL) {
        return NULL;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = new Elliot("EURUSD", timeFrames[i]);
        if (elliot == NULL || !analysis.elliotList.Add(elliot)) {
            if (elliot != NULL) {
                delete elliot;
            }
            delete analysis;
            return NULL;
        }
        setDirection(elliot, fromIsBuy);
        setEma200Direction(elliot, fromIsBuy);
        elliot.oscillator.gmmaTrendCount = -2;
        elliot.oscillator.gmmaCrossCount = -2;
        if (fromIsBuy) {
            elliot.oscillator.gmmaTrendCount = 2;
            elliot.oscillator.gmmaCrossCount = 2;
        }
        elliot.oscillator.ema200.closeEma200DiffPips = 1000.0;

        int waveIndex = 2;
        if (timeFrames[i] == PERIOD_H4 || timeFrames[i] == PERIOD_H1
                || timeFrames[i] == PERIOD_M15) {
            waveIndex = fromEntryWave;
        }
        CArrayObj points;
        for (int j = 0; j <= waveIndex; j++) {
            ZigZagPoint *point = new ZigZagPoint(elliot.marketContext);
            if (point == NULL || !points.Add(point)) {
                if (point != NULL) {
                    delete point;
                }
                delete analysis;
                return NULL;
            }
            point.elliotIndex = j;
            point.isElliotAlphabet = false;
            point.setElliotLabel();
            point.subElliotIndex = 0;
            point.subElliotLabel = "";
            point.isAddedPoint = false;
            point.barTime = D'2026.09.01 00:00' + j * 900;
        }
        Wave *wave = new Wave(elliot.marketContext, points, true, fromIsBuy);
        if (wave == NULL || !elliot.waveList.Add(wave)) {
            if (wave != NULL) {
                delete wave;
            }
            delete analysis;
            return NULL;
        }
    }
    Elliot *elliotH1 = analysis.getElliot(PERIOD_H1);
    ZigZagPoint *pointH1 = elliotH1.getLatestPoint();
    pointH1.isAddedPoint = true;
    analysis.elliotCurrent = analysis.getElliot(PERIOD_M15);
    analysis.isAnalysisSucceeded = true;
    analysis.isSendMail = false;
    analysis.isCurrencyStrengthEntryFilterEnabled = false;
    analysis.todayRate.spread = 5.0;
    return analysis;
}

/**
 * 初回ENTRYの成立と、待機中に回数を消費していないことを確認する。
 *
 * @param fromCaseName 検証名。
 * @param fromExpertAdvisor 判定済みの戦略。
 */
void assertFirstEntry(
    const string fromCaseName,
    ExpertAdvisorMtf3In3M15 &fromExpertAdvisor
) {
    Mtf3In3AlertResult result = fromExpertAdvisor.getAlertResult();
    assertCondition(fromCaseName + " ENTRY", result.isEntry && result.isAlert
        && result.isEntryEvaluated && result.entryResult == "ENTRY");
    assertCondition(fromCaseName + " first count", result.signalCount == 1);
}

/**
 * 指定した1条件だけを不成立にする。
 *
 * @param fromAnalysis 変更する分析結果。
 * @param fromTimeFrame 対象時間足。
 * @param fromFault 不成立にする条件名。
 * @param fromIsBuy 元のエントリー方向。
 */
void applyFault(
    ElliotAll *fromAnalysis,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const string fromFault,
    const bool fromIsBuy
) {
    Elliot *elliot = fromAnalysis.getElliot(fromTimeFrame);
    Wave *wave = elliot.getLatestWave();
    ZigZagPoint *point = elliot.getLatestPoint();
    ZigZagPoint *wave3 = wave.zigZagPointList.At(3);
    if (fromFault == "DIRECTION") {
        setDirection(elliot, !fromIsBuy);
    } else if (fromFault == "WAVE_DIRECTION") {
        wave.isUptrend = !fromIsBuy;
    } else if (fromFault == "EMA200") {
        setEma200Direction(elliot, !fromIsBuy);
    } else if (fromFault == "GMMA_TREND") {
        elliot.oscillator.gmmaTrendCount /= 2;
    } else if (fromFault == "GMMA_CROSS") {
        elliot.oscillator.gmmaCrossCount /= 2;
    } else if (fromFault == "UNCONFIRMED") {
        point.isAddedPoint = true;
    } else if (fromFault == "WAVE2") {
        point.elliotIndex = 2;
        point.setElliotLabel();
    } else if (fromFault == "WAVE5_SUB_INDEX") {
        wave3.subElliotIndex = 1;
    } else if (fromFault == "WAVE5_SUB_LABEL") {
        wave3.subElliotLabel = "iii";
    } else if (fromFault == "WAVE5_WITHOUT_WAVE3") {
        wave3.elliotIndex = 2;
        wave3.setElliotLabel();
    } else if (fromFault == "WAVE5_NOT_MOTIVE") {
        wave.isMotive = false;
    } else if (fromFault == "SPREAD") {
        fromAnalysis.todayRate.spread = 5.1;
    } else if (fromFault == "MN1_AND_W1_EMA200") {
        setDirection(fromAnalysis.getElliot(PERIOD_MN1), !fromIsBuy);
        setEma200Direction(fromAnalysis.getElliot(PERIOD_W1), !fromIsBuy);
    } else {
        assertCondition("unknown fault " + fromFault, false);
    }
}

/**
 * 不成立後、同じM15起点の条件成立時に初回ENTRYできることを検証する。
 *
 * @param fromTimeFrame 不成立にする時間足。
 * @param fromFault 不成立にする条件名。
 * @param fromIsBuy BUY方向の場合true。
 */
void validateWaitAndRetry(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const string fromFault,
    const bool fromIsBuy
) {
    string caseName = EnumToString(fromTimeFrame) + " " + fromFault
        + " buy=" + (string)fromIsBuy;
    ElliotAll *waiting = createAnalysis(fromIsBuy);
    ElliotAll *ready = createAnalysis(fromIsBuy);
    if (waiting == NULL || ready == NULL) {
        assertCondition(caseName + " fixture", false);
        delete waiting;
        delete ready;
        return;
    }
    applyFault(waiting, fromTimeFrame, fromFault, fromIsBuy);
    MarketContext context("EURUSD", PERIOD_M15);
    SignalCount signalCount(context);
    ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
    expertAdvisor.analyze(waiting, GetPointer(signalCount));
    assertCondition(caseName + " wait", !expertAdvisor.isEntry);
    expertAdvisor.analyze(waiting, GetPointer(signalCount));
    assertCondition(caseName + " repeat wait", !expertAdvisor.isEntry);
    expertAdvisor.analyze(ready, GetPointer(signalCount));
    assertFirstEntry(caseName + " retry", expertAdvisor);
    expertAdvisor.analyze(ready, GetPointer(signalCount));
    assertCondition(caseName + " duplicate", !expertAdvisor.isEntry);
    delete waiting;
    delete ready;
}

/**
 * 1波、3波、有効5波のBUY・SELLと上位足のOR条件を検証する。
 */
void validateAcceptedCases() {
    int waveIndices[] = { 1, 3, 5 };
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < ArraySize(waveIndices); j++) {
            ElliotAll *analysis = createAnalysis(i == 0, waveIndices[j]);
            if (analysis == NULL) {
                assertCondition("accepted fixture", false);
                continue;
            }
            MarketContext context("EURUSD", PERIOD_M15);
            SignalCount signalCount(context);
            ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
            expertAdvisor.analyze(analysis, GetPointer(signalCount));
            assertFirstEntry("wave=" + IntegerToString(waveIndices[j])
                + " buy=" + (string)(i == 0), expertAdvisor);
            delete analysis;
        }
    }
    for (int i = 0; i < 2; i++) {
        ElliotAll *analysis = createAnalysis(true);
        if (analysis == NULL) {
            assertCondition("higher alternative fixture", false);
            continue;
        }
        if (i == 0) {
            setDirection(analysis.getElliot(PERIOD_MN1), false);
        } else {
            setEma200Direction(analysis.getElliot(PERIOD_W1), false);
        }
        MarketContext context("EURUSD", PERIOD_M15);
        SignalCount signalCount(context);
        ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
        expertAdvisor.analyze(analysis, GetPointer(signalCount));
        assertFirstEntry("higher alternative=" + IntegerToString(i), expertAdvisor);
        delete analysis;
    }
}

/**
 * H1のGMMAが中立または反対方向でもM15のENTRYを許可する。
 */
void validateH1GmmaIgnored() {
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        for (int j = 0; j < 2; j++) {
            ElliotAll *analysis = createAnalysis(isBuy);
            if (analysis == NULL) {
                assertCondition("H1 GMMA ignored fixture", false);
                continue;
            }
            Elliot *elliotH1 = analysis.getElliot(PERIOD_H1);
            elliotH1.oscillator.gmmaTrendCount *= -j;
            elliotH1.oscillator.gmmaCrossCount *= -j;
            MarketContext context("EURUSD", PERIOD_M15);
            SignalCount signalCount(context);
            ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
            expertAdvisor.analyze(analysis, GetPointer(signalCount));
            assertFirstEntry("H1 GMMA ignored case=" + IntegerToString(j)
                + " buy=" + (string)isBuy, expertAdvisor);
            delete analysis;
        }
    }
}

/**
 * M15確定待ちの間にもH1条件を再確認し、回復後だけENTRYする。
 */
void validateHigherConditionWhileWaiting() {
    ElliotAll *analysis = createAnalysis(true);
    if (analysis == NULL) {
        assertCondition("higher wait fixture", false);
        return;
    }
    MarketContext context("EURUSD", PERIOD_M15);
    SignalCount signalCount(context);
    ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
    ZigZagPoint *pointM15 = analysis.elliotCurrent.getLatestPoint();
    Elliot *elliotH1 = analysis.getElliot(PERIOD_H1);
    pointM15.isAddedPoint = true;
    expertAdvisor.analyze(analysis, GetPointer(signalCount));
    assertCondition("pending M15", !expertAdvisor.isEntry);
    pointM15.isAddedPoint = false;
    setEma200Direction(elliotH1, false);
    expertAdvisor.analyze(analysis, GetPointer(signalCount));
    assertCondition("H1 lost while M15 confirmed", !expertAdvisor.isEntry);
    setEma200Direction(elliotH1, true);
    expertAdvisor.analyze(analysis, GetPointer(signalCount));
    assertFirstEntry("H1 restored", expertAdvisor);
    delete analysis;
}

/**
 * 同じ起点の重複を拒否し、新起点または反対方向を別シグナルとして扱う。
 */
void validateSignalIdentity() {
    ElliotAll *buyAnalysis = createAnalysis(true);
    ElliotAll *sellAnalysis = createAnalysis(false);
    if (buyAnalysis == NULL || sellAnalysis == NULL) {
        assertCondition("signal identity fixture", false);
        delete buyAnalysis;
        delete sellAnalysis;
        return;
    }
    MarketContext context("EURUSD", PERIOD_M15);
    SignalCount signalCount(context);
    ExpertAdvisorMtf3In3M15 expertAdvisor(context, false, false);
    expertAdvisor.analyze(buyAnalysis, GetPointer(signalCount));
    assertFirstEntry("original BUY", expertAdvisor);
    expertAdvisor.analyze(buyAnalysis, GetPointer(signalCount));
    assertCondition("same origin duplicate", !expertAdvisor.isEntry);
    expertAdvisor.analyze(sellAnalysis, GetPointer(signalCount));
    assertFirstEntry("same origin opposite direction", expertAdvisor);
    ZigZagPoint *origin = buyAnalysis.elliotCurrent.getLatestPoint2();
    origin.barTime += 900;
    expertAdvisor.analyze(buyAnalysis, GetPointer(signalCount));
    assertFirstEntry("next M15 origin", expertAdvisor);
    delete buyAnalysis;
    delete sellAnalysis;
}

/**
 * H1条件にM15確定条件を加えた公開ENTRY経路の回帰検証を実行する。
 */
void OnStart() {
    gFailureCount = 0;
    validateAcceptedCases();
    validateH1GmmaIgnored();
    validateHigherConditionWhileWaiting();
    validateSignalIdentity();

    ENUM_TIMEFRAMES directionFrames[] = { PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15 };
    ENUM_TIMEFRAMES emaFrames[] = { PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15 };
    ENUM_TIMEFRAMES entryFrames[] = { PERIOD_H4, PERIOD_H1, PERIOD_M15 };
    ENUM_TIMEFRAMES timingFrames[] = { PERIOD_H1, PERIOD_M15 };
    string waveFaults[] = {
        "WAVE2", "WAVE5_SUB_INDEX", "WAVE5_SUB_LABEL",
        "WAVE5_WITHOUT_WAVE3", "WAVE5_NOT_MOTIVE"
    };
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        for (int j = 0; j < ArraySize(directionFrames); j++) {
            validateWaitAndRetry(directionFrames[j], "DIRECTION", isBuy);
        }
        for (int j = 0; j < ArraySize(emaFrames); j++) {
            validateWaitAndRetry(emaFrames[j], "EMA200", isBuy);
        }
        for (int j = 0; j < ArraySize(entryFrames); j++) {
            for (int k = 0; k < ArraySize(waveFaults); k++) {
                validateWaitAndRetry(entryFrames[j], waveFaults[k], isBuy);
            }
        }
        for (int j = 0; j < ArraySize(timingFrames); j++) {
            validateWaitAndRetry(timingFrames[j], "WAVE_DIRECTION", isBuy);
        }
        validateWaitAndRetry(PERIOD_M15, "GMMA_TREND", isBuy);
        validateWaitAndRetry(PERIOD_M15, "GMMA_CROSS", isBuy);
        validateWaitAndRetry(PERIOD_M15, "UNCONFIRMED", isBuy);
        validateWaitAndRetry(PERIOD_M15, "SPREAD", isBuy);
        validateWaitAndRetry(PERIOD_MN1, "MN1_AND_W1_EMA200", isBuy);
    }
    if (gFailureCount == 0) {
        Print("ExpertAdvisorMtf3In3M15EntrySmokeTest PASS");
        return;
    }
    PrintFormat("ExpertAdvisorMtf3In3M15EntrySmokeTest FAIL count=%d", gFailureCount);
}
