#property strict

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>

/** 検証失敗件数。 */
int failureCount = 0;
/** 補正後の採用分析を指定する非所有fixture。 */
ElliotAll *selectedFixture = NULL;

/**
 * 相場依存の補正生成だけを固定し、M15の全判定条件は実装を使用する。
 */
class M15EaCorrectionFixture : public ExpertAdvisorMtf3In3M15 {
public:
    /**
     * 明示した補正・FE設定を既存戦略へ渡す。
     */
    M15EaCorrectionFixture(MarketContext &fromContext, const bool fromCorrection,
            const double fromH4Limit, const double fromH1Limit)
            : ExpertAdvisorMtf3In3M15(fromContext, false, fromCorrection, fromH4Limit, fromH1Limit) {
    }

    /**
     * fixture採用時だけH1補正として診断する。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (selectedFixture != NULL && this.elliotAll == selectedFixture) {
            return PERIOD_H1;
        }
        return ExpertAdvisorMtf3In3M15::getCorrectionTimeFrame();
    }

protected:
    /**
     * 再分析の市場参照だけを置き換える。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (selectedFixture != NULL) {
            return selectedFixture;
        }
        return ExpertAdvisorMtf3In3M15::selectJudgmentElliotAll(fromOriginal);
    }
};

/**
 * Factoryの引数受け渡しを保ったまま補正分析fixtureを注入する。
 */
class M15EaFixtureFactory {
public:
    /**
     * 呼び出し元が破棄する検証用戦略を返す。
     */
    static ExpertAdvisorMTF_3in3 *create(MarketContext &fromContext, const bool fromDraw,
            const H1W1ConfirmationMode fromW1Mode, const H1DirectionAlignmentMode fromDirectionMode,
            const H1Ema200ConfirmationMode fromEmaMode, const bool fromCorrection,
            const double fromH4Limit, const double fromH1Limit) {
        if (selectedFixture != NULL) {
            return new M15EaCorrectionFixture(fromContext, fromCorrection, fromH4Limit, fromH1Limit);
        }
        return ExpertAdvisorMtf3In3Factory::create(fromContext, fromDraw,
            fromW1Mode, fromDirectionMode, fromEmaMode, fromCorrection, fromH4Limit, fromH1Limit);
    }
};

#define ExpertAdvisorMtf3In3Factory M15EaFixtureFactory
#include <MstngM15Ea\Strategy\M15EaStrategy.mqh>
#undef ExpertAdvisorMtf3In3Factory

/**
 * 失敗した検証だけを記録する。
 */
void verify(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("ERROR MstngM15StrategySmokeTest ", fromName);
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
            point.orgElliotIndex = j;
            point.orgElliotLabel = IntegerToString(j);
            point.fibonacciExpansionPercent = 150.0;
            point.barIndex = waveIndex - j;
            point.isPeak = (j % 2 == 1) == fromIsBuy;
            point.rate = 1.1000;
            if (point.isPeak) {
                point.rate = 1.1030;
            }
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
    analysis.todayRate.bid = 1.1015;
    analysis.todayRate.ask = 1.1020;
    return analysis;
}

/**
 * 補正なしBUY/SELLの回数復元と1回評価、H1 GMMA非参照を検証する。
 */
void verifyEntryAndCount(const bool fromIsBuy) {
    ElliotAll *analysis = createAnalysis(fromIsBuy, 3);
    if (analysis == NULL) {
        verify(false, "entry fixture allocation");
        return;
    }
    analysis.getElliot(PERIOD_H1).oscillator.gmmaTrendCount = 0;
    analysis.getElliot(PERIOD_H1).oscillator.gmmaCrossCount = 0;
    M15EaStrategyDecision decision;
    M15EaStrategySnapshot snapshot;
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "entry prepare");
    verify(snapshot.initialStopLossPivotTime == 0 && !snapshot.isEntryEvaluated, "prepare does not judge or select SL");
    verify(decision.evaluate(analysis, 0, snapshot), "first evaluation");
    verify(snapshot.isJudge && snapshot.isStrategyEntry && snapshot.isSignalConsumed
        && snapshot.signalCount == 1 && snapshot.isEntryEvaluated, "first entry with H1 GMMA ignored");
    verify(snapshot.initialStopLossPivotTime == snapshot.signalReferenceTime
        && snapshot.initialStopLossPivotPrice == snapshot.signalReferencePrice, "uncorrected selected SL");
    verify(snapshot.correctionTimeFrame == PERIOD_CURRENT, "uncorrected metadata");
    verify(StringFind(snapshot.analysisSnapshotText, "SELECTED_PERIOD_M15_GMMA_TREND") >= 0,
        "selected M15 diagnostic saved");
    verify(!decision.evaluate(analysis, 0, snapshot), "same prepared snapshot evaluated once");
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "duplicate prepare");
    verify(decision.evaluate(analysis, 1, snapshot), "restored count evaluated");
    verify(snapshot.isJudge && snapshot.signalCount == 2 && !snapshot.isStrategyEntry
        && !snapshot.isSignalConsumed && !snapshot.isEntryEvaluated
        && snapshot.reasonCode == "SIGNAL_ALREADY_CONSUMED", "restored count prevents duplicate");
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "invalid count prepare");
    verify(!decision.evaluate(analysis, INT_MAX, snapshot)
        && snapshot.reasonCode == "SIGNAL_COUNT_INVALID", "invalid count rejected");
    delete analysis;
}

/**
 * M15確定・H4/H1 FEを満たすまでは回数を消費せず、待機後の初回を許可する。
 */
void verifyJudgeWaits() {
    ElliotAll *analysis = createAnalysis(true, 3);
    if (analysis == NULL) {
        verify(false, "wait fixture allocation");
        return;
    }
    M15EaStrategyDecision decision;
    M15EaStrategySnapshot snapshot;
    analysis.elliotCurrent.getLatestPoint().isAddedPoint = true;
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "pending prepare");
    verify(decision.evaluate(analysis, 0, snapshot) && !snapshot.isJudge
        && snapshot.signalCount == 0 && !snapshot.isSignalConsumed, "M15 pending does not consume");
    analysis.elliotCurrent.getLatestPoint().isAddedPoint = false;
    ENUM_TIMEFRAMES higherTimeFrames[] = { PERIOD_H4, PERIOD_H1 };
    for (int i = 0; i < ArraySize(higherTimeFrames); i++) {
        ZigZagPoint *latest = analysis.getElliot(higherTimeFrames[i]).getLatestPoint();
        latest.fibonacciExpansionPercent = 161.9;
        verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "FE prepare");
        verify(decision.evaluate(analysis, 0, snapshot) && !snapshot.isJudge
            && snapshot.signalCount == 0 && !snapshot.isSignalConsumed, "FE over limit does not consume");
        latest.fibonacciExpansionPercent = 161.84;
        verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "FE boundary prepare");
        verify(decision.evaluate(analysis, 0, snapshot) && snapshot.isStrategyEntry,
            "FE rounded 161.8 accepted as first entry");
        latest.fibonacciExpansionPercent = 150.0;
    }
    setDirection(analysis.getElliot(PERIOD_D1), false);
    setDirection(analysis.getElliot(PERIOD_H4), false);
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot), "two mismatch prepare");
    verify(decision.evaluate(analysis, 0, snapshot) && !snapshot.isJudge
        && !snapshot.isJudgmentAnalysisAvailable && snapshot.signalCount == 0
        && snapshot.initialStopLossPivotTime == 0, "two mismatches reject without SL or consumption");
    delete analysis;
}

/**
 * 補正後の起点が変わっても元の回数キーを保持し、採用SLとFE診断をコピーする。
 */
void verifyCorrectedSnapshot() {
    ElliotAll *original = createAnalysis(true, 3);
    ElliotAll *selected = createAnalysis(true, 3);
    if (original == NULL || selected == NULL) {
        verify(false, "correction fixture allocation");
        delete original;
        delete selected;
        return;
    }
    setDirection(original.getElliot(PERIOD_H1), false);
    original.getElliot(PERIOD_H1).getLatestWave().isUptrend = false;
    selected.getElliot(PERIOD_H1).oscillator.isBuy = false;
    original.getElliot(PERIOD_H4).getLatestPoint().fibonacciExpansionPercent = 200.0;
    ZigZagPoint *sourcePivot = original.elliotCurrent.getLatestPoint2();
    ZigZagPoint *selectedPivot = selected.elliotCurrent.getLatestPoint2();
    selectedPivot.barTime += 900;
    selectedPivot.rate -= 0.001;
    selectedFixture = selected;
    M15EaStrategyDecision decision;
    M15EaStrategySnapshot snapshot;
    verify(decision.prepare(original, D'2026.09.01 01:00', snapshot), "correction prepare");
    verify(decision.evaluate(original, 0, snapshot), "correction evaluate");
    verify(snapshot.isStrategyEntry && snapshot.signalCount == 1
        && snapshot.correctionTimeFrame == PERIOD_H1, "corrected entry uses selected FE");
    verify(snapshot.signalReferenceTime == sourcePivot.barTime
        && snapshot.signalReferencePrice == sourcePivot.rate, "original signal key preserved");
    verify(snapshot.initialStopLossPivotTime == selectedPivot.barTime
        && snapshot.initialStopLossPivotPrice == selectedPivot.rate
        && snapshot.initialStopLossPivotIsHigh == selectedPivot.isPeak, "selected M15 SL copied");
    verify(StringFind(snapshot.analysisSnapshotText, "SOURCE_PERIOD_H4_FE_PERCENT#12=200.00000000") >= 0
        && StringFind(snapshot.analysisSnapshotText, "SELECTED_PERIOD_H4_FE_PERCENT#12=150.00000000") >= 0,
        "source and selected FE values saved");
    verify(decision.prepare(original, D'2026.09.01 01:00', snapshot), "corrected duplicate prepare");
    verify(decision.evaluate(original, 1, snapshot) && !snapshot.isStrategyEntry
        && snapshot.signalCount == 2, "selected pivot does not bypass restored original key");
    selectedFixture = NULL;
    delete selected;
    delete original;
}

/**
 * EAの注文・保存・通知を呼ばず、実M15判定とアダプターの契約を検証する。
 */
void OnStart() {
    M15EaStrategy strategy;
    M15EaStrategySnapshot snapshot;
    snapshot.reset();
    verify(!strategy.evaluate(0, snapshot) && strategy.getLastError() == "ANALYSIS_NOT_PREPARED",
        "strategy requires prepared analysis");
    verify(strategy.getWave() == NULL, "unprepared strategy has no wave");
    verify(!strategy.initialize("EURUSD", true, -1.0, 161.8)
        && strategy.getLastError() == "INVALID_HIGHER_FE_LIMIT", "invalid FE rejected before history access");
    verifyEntryAndCount(true);
    verifyEntryAndCount(false);
    verifyJudgeWaits();
    verifyCorrectedSnapshot();
    Print("MstngM15StrategySmokeTest failures=", failureCount);
}
