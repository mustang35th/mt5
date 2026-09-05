#property version "1.00"
#property script_show_inputs

#include <MstngH1Ea\Strategy\H1EaStrategy.mqh>

/** 検証失敗数。 */
int failureCount = 0;

/**
 * 期待条件を確認する。
 */
void assertCondition(const string fromName, const bool fromCondition) {
    if (!fromCondition) {
        failureCount++;
        Print("FAIL " + fromName);
    }
}

/**
 * フィクスチャの方向と整合するオシレーター状態を設定する。
 */
void setDirection(Elliot *fromElliot, const bool fromIsBuy) {
    fromElliot.isBuy = fromIsBuy;
    fromElliot.oscillator.isBuy = fromIsBuy;
    fromElliot.buySellLabel = "SELL";
    fromElliot.oscillator.gmmaTrendCount = -2;
    fromElliot.oscillator.gmmaCrossCount = -2;
    fromElliot.oscillator.ema200.isBuy = fromIsBuy;
    fromElliot.oscillator.ema200.isSell = !fromIsBuy;
    fromElliot.oscillator.ema200.buySellLabel = "SELL";

    if (fromIsBuy) {
        fromElliot.buySellLabel = "BUY";
        fromElliot.oscillator.gmmaTrendCount = 2;
        fromElliot.oscillator.gmmaCrossCount = 2;
        fromElliot.oscillator.ema200.buySellLabel = "BUY";
    }
}

/**
 * 市場データを取得せず第5波の分析フィクスチャを作成する。
 */
Elliot *createElliot(const ENUM_TIMEFRAMES fromTimeFrame, const bool fromIsBuy) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    setDirection(elliot, fromIsBuy);
    CArrayObj points;

    for (int i = 0; i <= 5; i++) {
        ZigZagPoint *point = new ZigZagPoint(elliot.marketContext);

        if (point == NULL) {
            delete elliot;

            return NULL;
        }

        point.rate = 1.1000 + 0.0002 * i;
        point.barTime = D'2026.09.01 00:00' + 3600 * i;
        point.barIndex = 6 - i;
        point.isPeak = (i % 2 == 1);
        point.isAddedPoint = false;
        point.elliotIndex = i;
        point.isElliotAlphabet = false;
        point.setElliotLabel();
        point.subElliotIndex = 0;
        point.subElliotLabel = "";

        if (!fromIsBuy) {
            point.rate = 1.1020 - 0.0002 * i;
            point.isPeak = !point.isPeak;
        }

        if (!points.Add(point)) {
            delete point;
            delete elliot;

            return NULL;
        }
    }

    Wave *wave = new Wave(elliot.marketContext, points, true, fromIsBuy);

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
 * 通常版と同じ5時間足の検証用スナップショットを生成する。
 */
ElliotAll *createAnalysis(const bool fromIsBuy) {
    ElliotAll *analysis = new ElliotAll("EURUSD", PERIOD_H1);

    if (analysis == NULL) {
        return NULL;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1
    };

    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = createElliot(timeFrames[i], fromIsBuy);

        if (elliot == NULL || !analysis.elliotList.Add(elliot)) {
            if (elliot != NULL) {
                delete elliot;
            }

            delete analysis;

            return NULL;
        }

        if (timeFrames[i] == PERIOD_H1) {
            analysis.elliotCurrent = elliot;
        }
    }

    analysis.todayRate.bid = 1.1010;
    analysis.todayRate.ask = 1.1015;
    analysis.todayRate.spread = 5.0;
    analysis.isAnalysisSucceeded = true;
    analysis.isSendMail = false;
    analysis.isMailValidationFileEnabled = false;
    analysis.isH1DisplayWaveEntryLimitEnabled = false;
    analysis.isCurrencyStrengthEntryFilterEnabled = false;

    return analysis;
}

/**
 * 同じ分析と回数をFactory直接呼び出しと新Adapterへ与えて比較する。
 */
void validateCase(
    const string fromName,
    ElliotAll *fromAnalysis,
    const int fromPreviousCount,
    const bool fromExpectedJudge,
    const bool fromExpectedEntry,
    const string fromExpectedReason
) {
    H1EaStrategyDecision decision;
    H1EaStrategySnapshot snapshot;

    if (!decision.prepare(fromAnalysis, D'2026.09.01 06:00', snapshot)) {
        assertCondition(fromName + " prepare", false);

        return;
    }

    MarketContext context("EURUSD", PERIOD_H1);
    SignalCount count(context);
    count.restoreCount(snapshot.signalReferenceTime, snapshot.isBuy, fromPreviousCount);
    ExpertAdvisorMTF_3in3 *existing = ExpertAdvisorMtf3In3Factory::create(
        context, false, H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
        H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
    );

    if (existing == NULL) {
        assertCondition(fromName + " existing Factory", false);

        return;
    }

    existing.analyze(fromAnalysis, GetPointer(count), 1);
    Mtf3In3AlertResult expected = existing.getAlertResult();
    delete existing;
    assertCondition(fromName + " evaluate", decision.evaluate(fromAnalysis, fromPreviousCount, snapshot));
    assertCondition(fromName + " same Judge", expected.isJudge == snapshot.isJudge);
    assertCondition(fromName + " same Entry", expected.isEntry == snapshot.isStrategyEntry);
    assertCondition(fromName + " same count", expected.signalCount == snapshot.signalCount);
    assertCondition(fromName + " same Entry evaluated", expected.isEntryEvaluated == snapshot.isEntryEvaluated);
    assertCondition(fromName + " expected Judge", snapshot.isJudge == fromExpectedJudge);
    assertCondition(fromName + " expected Entry", snapshot.isStrategyEntry == fromExpectedEntry);
    assertCondition(fromName + " expected reason", snapshot.reasonCode == fromExpectedReason);
    assertCondition(fromName + " consumed only first Judge", snapshot.isSignalConsumed
        == (fromExpectedJudge && fromPreviousCount == 0));
    assertCondition(fromName + " cannot evaluate snapshot twice", !decision.evaluate(fromAnalysis, fromPreviousCount, snapshot));
}

/**
 * BUY/SELL対称の判定と初回波動NG後の消費維持を検証する。
 */
void validateDirection(const bool fromIsBuy) {
    ElliotAll *analysis = createAnalysis(fromIsBuy);

    if (analysis == NULL) {
        assertCondition("analysis fixture", false);

        return;
    }

    validateCase("baseline wave5 Spread5", analysis, 0, true, true, "STRATEGY_ENTRY");
    validateCase("consumed previous signal", analysis, 1, true, false, "SIGNAL_ALREADY_CONSUMED");
    analysis.todayRate.spread = 5.01;
    validateCase("Spread excess no consume", analysis, 0, false, false, "SPREAD_TOO_WIDE");
    analysis.todayRate.spread = 5.0;

    Elliot *elliotH1 = analysis.getElliot(PERIOD_H1);
    Elliot *elliotH4 = analysis.getElliot(PERIOD_H4);
    Elliot *elliotW1 = analysis.getElliot(PERIOD_W1);
    Elliot *elliotMn1 = analysis.getElliot(PERIOD_MN1);
    ZigZagPoint *wave3 = elliotH1.getLatestWave().zigZagPointList.At(3);
    wave3.subElliotLabel = "iii";
    validateCase("H1 wave3 sub consumes", analysis, 0, true, false, "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED");
    wave3.subElliotLabel = "";
    validateCase("later wave OK no delayed Entry", analysis, 1, true, false, "SIGNAL_ALREADY_CONSUMED");
    wave3 = elliotH4.getLatestWave().zigZagPointList.At(3);
    wave3.subElliotIndex = 1;
    validateCase("H4 wave3 sub consumes", analysis, 0, true, false, "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED");
    wave3.subElliotIndex = 0;

    setDirection(elliotMn1, !fromIsBuy);
    validateCase("MN1 opposite W1 EMA alternative", analysis, 0, true, true, "STRATEGY_ENTRY");
    elliotW1.oscillator.ema200.isBuy = false;
    elliotW1.oscillator.ema200.isSell = false;
    elliotW1.oscillator.ema200.buySellLabel = "NONE";
    validateCase("MN1 opposite EMA NONE rejects", analysis, 0, false, false, "DIRECTION_ALIGNMENT_REJECTED");
    setDirection(elliotMn1, fromIsBuy);
    validateCase("MN1 aligned EMA NONE permitted", analysis, 0, true, true, "STRATEGY_ENTRY");
    setDirection(elliotW1, !fromIsBuy);
    validateCase("W1 opposite rejects", analysis, 0, false, false, "DIRECTION_ALIGNMENT_REJECTED");
    setDirection(elliotW1, fromIsBuy);
    elliotH1.oscillator.gmmaTrendCount = 0;
    validateCase("Judge OFF does not undo count", analysis, 2, false, false, "H1_GMMA_TREND_REJECTED");
    setDirection(elliotH1, fromIsBuy);
    validateCase("Judge ON after OFF keeps count", analysis, 2, true, false, "SIGNAL_ALREADY_CONSUMED");
    elliotH1.oscillator.ema200.closeEma200DiffPips = 100000.0;
    validateCase("EMA200 distance disabled", analysis, 0, true, true, "STRATEGY_ENTRY");
    delete analysis;
}

/**
 * 発注・市場分析なしで互換性、回数復元と未準備ガードを確認する。
 */
void OnStart() {
    MarketContext context("EURUSD", PERIOD_H1);
    SignalCount signalCount(context);
    datetime referenceTime = D'2026.09.01 00:00';
    assertCondition("restore zero", signalCount.restoreCount(referenceTime, true, 0));
    assertCondition("first Judge", signalCount.addCount(referenceTime, true) == 1);
    assertCondition("restore consumed SKIP", signalCount.restoreCount(referenceTime, true, 1));
    assertCondition("next Judge stays consumed", signalCount.addCount(referenceTime, true) == 2);
    assertCondition("opposite direction independent", signalCount.addCount(referenceTime, false) == 1);
    assertCondition("restore high count constant work", signalCount.restoreCount(referenceTime, true, 100000000));
    assertCondition("high count increments", signalCount.addCount(referenceTime, true) == 100000001);
    assertCondition("negative count rejects", !signalCount.restoreCount(referenceTime, true, -1));
    assertCondition("invalid reference rejects", !signalCount.restoreCount(0, true, 2));
    H1EaStrategyDecision decision;
    H1EaStrategySnapshot snapshot;
    assertCondition("missing analysis retryable", !decision.prepare(NULL, referenceTime, snapshot));
    assertCondition("missing analysis consumes nothing", !snapshot.isSignalConsumed && snapshot.signalCount == 0);
    assertCondition("count overflow rejects", !decision.evaluate(NULL, INT_MAX, snapshot)
        && snapshot.reasonCode == "SIGNAL_COUNT_INVALID");
    H1EaStrategy strategy;
    assertCondition("unprepared evaluate rejects", !strategy.evaluate(0, snapshot));
    assertCondition("unprepared Wave null", strategy.getWave() == NULL);
    validateDirection(true);
    validateDirection(false);
    PrintFormat("MstngH1StrategySmokeTest completed failures=%d", failureCount);
}
