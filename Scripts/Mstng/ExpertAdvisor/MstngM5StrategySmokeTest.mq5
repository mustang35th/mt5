#property strict

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3M5Policy.mqh>

/** Number of failed checks. */
int failureCount = 0;

/** Selected analysis injected only for the market-dependent correction test. */
ElliotAll *selectedFixture = NULL;

/** Explicit correction target for the supplied selected analysis. */
ENUM_TIMEFRAMES selectedFixtureTimeFrame = PERIOD_H1;

/**
 * Replace market reanalysis while keeping the actual M5 criteria.
 */
class M5EaCorrectionFixture : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * Enable the same normal-M5 policy as the indicator.
     */
    M5EaCorrectionFixture(MarketContext &fromContext, const int fromRankDifference)
        : ExpertAdvisorMtf3In3M5(fromContext, false, false, true, fromRankDifference) {
    }

    /**
     * Record H1 correction for the supplied selected analysis.
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (selectedFixture != NULL && this.elliotAll == selectedFixture) {
            return selectedFixtureTimeFrame;
        }

        return ExpertAdvisorMtf3In3M5::getCorrectionTimeFrame();
    }

protected:
    /**
     * Use a prepared correction fixture instead of reading market history.
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (selectedFixture != NULL) {
            return selectedFixture;
        }

        return ExpertAdvisorMtf3In3M5::selectJudgmentElliotAll(fromOriginal);
    }
};

/**
 * Exercise the EMA gate directly for missing data and legacy policy boundaries.
 */
class M5EmaGateFixture : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * Select normal or legacy M5 policy without drawing or trade operations.
     */
    M5EmaGateFixture(MarketContext &fromContext, const bool fromNormalPolicy)
        : ExpertAdvisorMtf3In3M5(fromContext, false, false, fromNormalPolicy) {
    }

    /**
     * Check the production gate without retaining the caller-owned analysis.
     */
    bool evaluate(ElliotAll *fromAnalysis, const bool fromIsBuy) {
        this.elliotAll = fromAnalysis;
        this.isBuy = fromIsBuy;
        bool result = this.isTimeFrameEma200ConditionMatched();
        this.elliotAll = NULL;

        return result;
    }
};

/**
 * Preserve factory configuration and substitute only correction reanalysis.
 */
class M5EaFixtureFactory {
public:
    /**
     * Return a caller-owned strategy using the actual configuration.
     */
    static ExpertAdvisorMTF_3in3 *create(MarketContext &fromContext,
        const ExpertAdvisorMtf3In3Config &fromConfig) {
        if (selectedFixture != NULL) {
            return new M5EaCorrectionFixture(fromContext, fromConfig.m5CurrencyStrengthMinimumRankDifference);
        }

        return ExpertAdvisorMtf3In3Factory::create(fromContext, fromConfig);
    }
};

#define ExpertAdvisorMtf3In3Factory M5EaFixtureFactory
#include <MstngM5Ea\Strategy\M5EaStrategy.mqh>
#undef ExpertAdvisorMtf3In3Factory

/**
 * Record failed assertions without orders, mail or indicator drawing.
 */
void verify(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("ERROR MstngM5StrategySmokeTest ", fromName);
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
 * MN1からM5までの全条件を満たす分析結果を生成する。
 *
 * 実際の相場データを読み込まず、公開analyze()の判定経路を検証する。
 * EMA200距離制限の不使用を確認するため距離を大きくし、H1最新点は未確定とする。
 *
 * @param fromIsBuy BUY方向の場合true。
 * @param fromEntryWave M15、M5の最新主波番号。
 * @return 呼び出し側が所有する分析結果。生成失敗時NULL。
 */
ElliotAll *createAnalysis(const bool fromIsBuy, const int fromEntryWave = 3) {
    ElliotAll *analysis = new ElliotAll("EURUSD", PERIOD_M5);
    if (analysis == NULL) {
        return NULL;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
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
        if (timeFrames[i] == PERIOD_M15 || timeFrames[i] == PERIOD_M5) {
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
            point.barTime = D'2026.09.01 00:00' + j * 300;
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
    analysis.elliotCurrent = analysis.getElliot(PERIOD_M5);
    analysis.isAnalysisSucceeded = true;
    analysis.isSendMail = false;
    analysis.isCurrencyStrengthEntryFilterEnabled = false;
    analysis.todayRate.spread = 5.0;
    analysis.todayRate.bid = 1.1015;
    analysis.todayRate.ask = 1.1020;
    return analysis;
}

/**
 * Create exact current-M5 ranks and the long-medium direction used by normal M5.
 */
void setStrength(ElliotAll *fromAnalysis, const bool fromIsBuy, const int fromGap = 4) {
    fromAnalysis.isCurrencyStrengthEntryFilterEnabled = true;
    CurrencyStrengthExecutionInfo strength;
    strength.reset();
    strength.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
    strength.targetM5BarTime = D'2026.09.01 01:00';
    strength.pairRankInfo.m5BarTime = strength.targetM5BarTime;
    strength.pairRankInfo.baseCurrency = "EUR";
    strength.pairRankInfo.quoteCurrency = "USD";
    strength.pairRankInfo.baseLongMediumTermAverageRank = 2;
    strength.pairRankInfo.quoteLongMediumTermAverageRank = 2 + fromGap;
    strength.pairRankInfo.baseMediumShortTermAverageRank = 2;
    strength.pairRankInfo.quoteMediumShortTermAverageRank = 2 + fromGap;
    strength.longMediumGapDirectionFilterEnabled = true;
    strength.longMediumGapDirection.enabled = true;
    strength.longMediumGapDirection.currentAvailable = true;
    strength.longMediumGapDirection.hasPrevious = true;
    strength.longMediumGapDirection.targetM5BarTime = strength.targetM5BarTime;
    strength.longMediumGapDirection.directionChangedAt = strength.targetM5BarTime - 300;
    strength.longMediumGapDirection.direction = 1;
    strength.longMediumGapDirection.currentGap = fromGap;
    if (!fromIsBuy) {
        strength.pairRankInfo.baseLongMediumTermAverageRank = 2 + fromGap;
        strength.pairRankInfo.quoteLongMediumTermAverageRank = 2;
        strength.pairRankInfo.baseMediumShortTermAverageRank = 2 + fromGap;
        strength.pairRankInfo.quoteMediumShortTermAverageRank = 2;
        strength.longMediumGapDirection.direction = -1;
        strength.longMediumGapDirection.currentGap = -fromGap;
    }

    fromAnalysis.currencyStrengthExecutionInfo = strength;
}

/**
 * Compare the adapter with explicit normal-indicator settings and known outcomes.
 */
void verifyParityMatrix(const bool fromIsBuy) {
    for (int i = 0; i < 23; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        if (analysis == NULL) {
            verify(false, "matrix allocation");
            return;
        }

        setStrength(analysis, fromIsBuy);
        int minimumGap = 4;
        bool expectedEntry = i == 0 || i == 10 || i == 17 || i == 20 || i == 21 || i == 22;
        switch (i) {
            case 1: analysis.getElliot(PERIOD_M15).getLatestPoint().elliotLabel = "5"; break;
            case 2: analysis.elliotCurrent.getLatestPoint().elliotLabel = "5"; break;
            case 3: analysis.elliotCurrent.getLatestPoint().fibonacciExpansionPercent = 161.9; break;
            case 4: analysis.elliotCurrent.oscillator.gmmaTrendCount = 0; break;
            case 5: analysis.elliotCurrent.oscillator.gmmaCrossCount = 0; break;
            case 6: analysis.elliotCurrent.getLatestPoint().isAddedPoint = true; break;
            case 7: setEma200Direction(analysis.getElliot(PERIOD_H1), !fromIsBuy); break;
            case 8: analysis.todayRate.spread = 5.1; break;
            case 9: setStrength(analysis, fromIsBuy, 3); break;
            case 10:
                if (fromIsBuy) {
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.baseLongMediumTermAverageRank = 1;
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.quoteLongMediumTermAverageRank = 2;
                } else {
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.baseLongMediumTermAverageRank = 8;
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.quoteLongMediumTermAverageRank = 7;
                }
                break;
            case 11: analysis.currencyStrengthExecutionInfo.longMediumGapDirection.direction *= -1; break;
            case 12:
                analysis.currencyStrengthExecutionInfo.pairRankInfo.baseMediumShortTermAverageRank = 6;
                analysis.currencyStrengthExecutionInfo.pairRankInfo.quoteMediumShortTermAverageRank = 2;
                if (!fromIsBuy) {
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.baseMediumShortTermAverageRank = 2;
                    analysis.currencyStrengthExecutionInfo.pairRankInfo.quoteMediumShortTermAverageRank = 6;
                }
                break;
            case 13: analysis.currencyStrengthExecutionInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND; break;
            case 14: analysis.currencyStrengthExecutionInfo.pairRankInfo.m5BarTime -= 300; break;
            case 15: analysis.currencyStrengthExecutionInfo.longMediumGapDirection.direction = 0; break;
            case 16: analysis.currencyStrengthExecutionInfo.longMediumGapDirection.waiting = true; break;
            case 17: analysis.elliotCurrent.oscillator.ema200.closeEma200DiffPips = 10000.0; break;
            case 18:
                setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy);
                analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
                break;
            case 19:
                setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
                setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
                break;
            case 20: minimumGap = 3; setStrength(analysis, fromIsBuy, 3); break;
            case 21: analysis.elliotCurrent.getLatestPoint().fibonacciExpansionPercent = 161.84; break;
            case 22:
                analysis.getElliot(PERIOD_M15).getLatestPoint().elliotLabel = "1";
                analysis.elliotCurrent.getLatestPoint().elliotLabel = "1";
                analysis.elliotCurrent.getLatestPoint().fibonacciExpansionPercent = 200.0;
                break;
        }

        MarketContext context = analysis.marketContext;
        ExpertAdvisorMtf3In3Config referenceConfig;
        referenceConfig.isDrawArrow = false;
        referenceConfig.m5Mn1AndW1Ema200Required = false;
        referenceConfig.m5D1ToM5EntryPolicyEnabled = true;
        referenceConfig.m5CurrencyStrengthMinimumRankDifference = minimumGap;
        ExpertAdvisorMTF_3in3 *reference = ExpertAdvisorMtf3In3Factory::create(context, referenceConfig);
        SignalCount count(context);
        reference.analyze(analysis, GetPointer(count), 1);
        Mtf3In3AlertResult expected = reference.getAlertResult();
        delete reference;

        M5EaStrategyDecision decision;
        M5EaStrategySnapshot actual;
        string label = "matrix " + IntegerToString((int)fromIsBuy) + "/" + IntegerToString(i);
        verify(decision.prepare(analysis, D'2026.09.01 01:00', actual)
            && decision.evaluate(analysis, 0, actual, minimumGap), label + " evaluated");
        verify(actual.isStrategyEntry == expectedEntry, label + " known entry outcome");
        verify(actual.alertResult.isJudge == expected.isJudge
            && actual.alertResult.isEntry == expected.isEntry
            && actual.alertResult.signalCount == expected.signalCount
            && actual.alertResult.entryResult == expected.entryResult
            && actual.alertResult.currentElliotLabel == expected.currentElliotLabel,
            label + " indicator adapter parity");
        if (i >= 9 && i <= 16 && i != 10) {
            verify(actual.signalCount == 0 && !actual.isSignalConsumed,
                label + " failed strength never consumes first signal");
        }

        if (i == 18) {
            verify(actual.reasonCode == "M5_CORRECTION_ANALYSIS_FAILED",
                label + " D1 direction reason");
        } else if (i == 19) {
            verify(actual.reasonCode == "M5_CORRECTION_NOT_APPLICABLE",
                label + " multiple correction reason");
        }

        delete analysis;
    }
}

/**
 * Persisted original pivot counts prevent duplicate entries after restoration.
 */
void verifyRestoredCount() {
    ElliotAll *analysis = createAnalysis(true);
    M5EaStrategyDecision decision;
    M5EaStrategySnapshot snapshot;
    verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot)
        && decision.evaluate(analysis, 0, snapshot) && snapshot.isStrategyEntry, "first signal enters");
    verify(!decision.evaluate(analysis, 0, snapshot), "prepared snapshot cannot be evaluated twice");
    verify(decision.prepare(analysis, D'2026.09.01 01:05', snapshot)
        && decision.evaluate(analysis, 1, snapshot) && snapshot.signalCount == 2
        && !snapshot.isStrategyEntry && !snapshot.isSignalConsumed
        && snapshot.reasonCode == "SIGNAL_ALREADY_CONSUMED", "restored count prevents duplicate");
    verify(decision.prepare(analysis, D'2026.09.01 01:05', snapshot)
        && !decision.evaluate(analysis, INT_MAX, snapshot), "invalid count rejected");
    delete analysis;
}

/**
 * Corrected SL selection must not replace the original signal identity.
 */
void verifyCorrectedSnapshot(const ENUM_TIMEFRAMES fromCorrectionTimeFrame, const bool fromIsBuy) {
    ElliotAll *original = createAnalysis(fromIsBuy);
    ElliotAll *selected = createAnalysis(fromIsBuy);
    setDirection(original.getElliot(fromCorrectionTimeFrame), !fromIsBuy);
    original.getElliot(fromCorrectionTimeFrame).getLatestWave().isUptrend = !fromIsBuy;
    selected.getElliot(fromCorrectionTimeFrame).oscillator.isBuy = !fromIsBuy;
    ZigZagPoint *sourcePivot = original.elliotCurrent.getLatestPoint2();
    ZigZagPoint *selectedPivot = selected.elliotCurrent.getLatestPoint2();
    selectedPivot.barTime += 300;
    selectedPivot.rate -= 0.001;
    selectedFixtureTimeFrame = fromCorrectionTimeFrame;
    selectedFixture = selected;
    M5EaStrategyDecision decision;
    M5EaStrategySnapshot snapshot;
    verify(decision.prepare(original, D'2026.09.01 01:00', snapshot)
        && decision.evaluate(original, 0, snapshot) && snapshot.isStrategyEntry
        && snapshot.correctionTimeFrame == fromCorrectionTimeFrame, "selected correction enters");
    verify(snapshot.signalReferenceTime == sourcePivot.barTime
        && snapshot.signalReferencePrice == sourcePivot.rate, "original count key preserved");
    verify(snapshot.initialStopLossPivotTime == selectedPivot.barTime
        && snapshot.initialStopLossPivotPrice == selectedPivot.rate, "selected correction supplies SL");
    verify(decision.prepare(original, D'2026.09.01 01:05', snapshot)
        && decision.evaluate(original, 1, snapshot) && !snapshot.isStrategyEntry,
        "correction cannot bypass consumed original key");
    verify(StringFind(snapshot.analysisSnapshotText, "D1_H4_H1_M15_ONE_CORRECTION") >= 0,
        "new direction policy recorded in snapshot");
    selected.getElliot(fromCorrectionTimeFrame).oscillator.isBuy = fromIsBuy;
    verify(decision.prepare(original, D'2026.09.01 01:10', snapshot)
        && decision.evaluate(original, 0, snapshot) && !snapshot.isJudge,
        "correction cannot change measured oscillator direction");
    selected.getElliot(fromCorrectionTimeFrame).oscillator.isBuy = !fromIsBuy;
    setEma200Direction(original.getElliot(PERIOD_H1), !fromIsBuy);
    setEma200Direction(selected.getElliot(PERIOD_H1), !fromIsBuy);
    verify(decision.prepare(original, D'2026.09.01 01:10', snapshot)
        && decision.evaluate(original, 0, snapshot) && !snapshot.isJudge,
        "direction correction cannot bypass opposite measured H1 EMA");
    setEma200Direction(original.getElliot(PERIOD_H1), fromIsBuy);
    setEma200Direction(selected.getElliot(PERIOD_H1), fromIsBuy);
    selected.elliotCurrent.getLatestPoint().elliotLabel = "5";
    verify(decision.prepare(original, D'2026.09.01 01:15', snapshot)
        && decision.evaluate(original, 0, snapshot) && !snapshot.isStrategyEntry,
        "corrected analysis still requires allowed M5 wave");
    selectedFixture = NULL;
    selectedFixtureTimeFrame = PERIOD_H1;
    delete selected;
    delete original;
}

/**
 * Exercise rejection diagnostics through the real selection and adapter paths.
 * Correction failure uses an invalid MN1 symbol, before any market history read.
 */
void verifyJudgmentReasons(const bool fromIsBuy) {
    for (int i = 0; i < 3; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        string expectedReason = "M5_JUDGMENT_INPUT_INVALID";
        if (i == 0) {
            analysis.getElliot(PERIOD_H4).oscillator.isBuy = !fromIsBuy;
        } else if (i == 1) {
            setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
            analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
            expectedReason = "M5_CORRECTION_ANALYSIS_FAILED";
        } else {
            setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy);
            setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
            setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
            expectedReason = "M5_CORRECTION_NOT_APPLICABLE";
        }

        M5EaStrategyDecision decision;
        M5EaStrategySnapshot snapshot;
        verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot)
            && decision.evaluate(analysis, 0, snapshot), "reason fixture evaluated");
        verify(snapshot.reasonCode == expectedReason && !snapshot.isJudgmentAnalysisAvailable,
            "rejection reason copied before strategy deletion");
        verify(!snapshot.isJudge && !snapshot.isStrategyEntry && !snapshot.isSignalConsumed
            && snapshot.signalCount == 0, "rejection preserves signal count and no entry");
        delete analysis;
    }

    ElliotAll *analysis = createAnalysis(fromIsBuy);
    MarketContext context = analysis.marketContext;
    SignalCount count(context);
    ExpertAdvisorMtf3In3M5 strategy(context, false, false, true);
    verify(strategy.getJudgmentAnalysisRejectReason() == "", "initial reason empty");
    setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy);
    setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
    strategy.analyze(analysis, GetPointer(count), 1);
    verify(strategy.getJudgmentAnalysisRejectReason() == "M5_CORRECTION_NOT_APPLICABLE",
        "reused strategy first rejection");
    setDirection(analysis.getElliot(PERIOD_D1), fromIsBuy);
    setDirection(analysis.getElliot(PERIOD_H4), fromIsBuy);
    strategy.analyze(analysis, GetPointer(count), 1);
    verify(strategy.getJudgmentAnalysisRejectReason() == ""
        && strategy.getAlertResult().isEntry, "success clears prior reason");
    setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy);
    setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
    strategy.analyze(analysis, GetPointer(count), 1);
    strategy.analyze(NULL, GetPointer(count), 1);
    verify(strategy.getJudgmentAnalysisRejectReason() == "", "early guard clears prior reason");

    ExpertAdvisorMtf3In3M5 legacy(context, false, false, false);
    setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
    setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
    legacy.analyze(analysis, GetPointer(count), 1);
    verify(legacy.getJudgmentAnalysisRejectReason() == "M5_CORRECTION_NOT_APPLICABLE",
        "legacy multiple reverse frames classified");
    delete analysis;
}

/**
 * Exercise all 16 D1/H4/H1/M15 combinations without reading market history.
 */
void verifyCorrectionSelectionMatrix(const bool fromIsBuy) {
    ENUM_TIMEFRAMES timeFrames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15};
    for (int i = 0; i < 16; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
        int mismatchCount = 0;
        for (int j = 0; j < 4; j++) {
            if ((i & (1 << j)) != 0) {
                setDirection(analysis.getElliot(timeFrames[j]), !fromIsBuy);
                mismatchCount++;
            }
        }

        M5EaStrategyDecision decision;
        M5EaStrategySnapshot snapshot;
        verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot)
            && decision.evaluate(analysis, 0, snapshot), "direction matrix evaluated");
        if (mismatchCount == 0) {
            verify(snapshot.isStrategyEntry && snapshot.correctionTimeFrame == PERIOD_CURRENT,
                "all aligned uses original analysis");
        } else {
            string reason = "M5_CORRECTION_NOT_APPLICABLE";
            if (mismatchCount == 1) {
                reason = "M5_CORRECTION_ANALYSIS_FAILED";
            }

            verify(snapshot.reasonCode == reason && snapshot.signalCount == 0
                && !snapshot.isSignalConsumed, "one correction attempted; multiple corrections rejected");
        }

        delete analysis;
    }
}

/**
 * Verify M5 accepts the D1 reanalysis route while M1 keeps its former scope.
 * Invalid MN1 input stops the accepted route before any market data access.
 */
void verifyD1ReanalysisScope() {
    ElliotAll *original = createAnalysis(true);
    original.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
    ElliotAll corrected("EURUSD", PERIOD_M1);
    verify(!corrected.analyzeWithDirectionCorrection(original, PERIOD_D1, true)
        && corrected.marketContext.timeFrame == PERIOD_M5,
        "M5 D1 route accepted then invalid snapshot rejected");
    original.marketContext.timeFrame = PERIOD_M1;
    ElliotAll unsupported("EURUSD", PERIOD_H1);
    verify(!unsupported.analyzeWithDirectionCorrection(original, PERIOD_D1, true)
        && unsupported.marketContext.timeFrame == PERIOD_H1, "M1 D1 route remains unsupported");
    delete original;
}

/**
 * Check all H1/M15/M5 NONE/BUY/SELL combinations through the real EA adapter.
 */
void verifyH1OnlyEmaMatrix(const bool fromIsBuy) {
    ENUM_TIMEFRAMES timeFrames[] = {PERIOD_H1, PERIOD_M15, PERIOD_M5};
    for (int i = 0; i < 27; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        int combination = i;
        bool expected = false;
        for (int j = 0; j < 3; j++) {
            int state = combination % 3;
            combination /= 3;
            Elliot *elliot = analysis.getElliot(timeFrames[j]);
            setEma200Direction(elliot, state == 1);
            if (state == 0) {
                elliot.oscillator.ema200.isBuy = false;
                elliot.oscillator.ema200.isSell = false;
                elliot.oscillator.ema200.buySellLabel = "NONE";
            }
            if (j == 0) {
                expected = (fromIsBuy && state == 1) || (!fromIsBuy && state == 2);
            }
        }

        M5EaStrategyDecision decision;
        M5EaStrategySnapshot snapshot;
        verify(decision.prepare(analysis, D'2026.09.01 01:00', snapshot)
            && decision.evaluate(analysis, 0, snapshot), "EMA matrix evaluated");
        verify(snapshot.isStrategyEntry == expected, "only H1 controls EMA eligibility");
        verify(StringFind(snapshot.analysisSnapshotText, "EMA200_CONFIRMATION_MODE#7=H1_ONLY") >= 0,
            "H1-only EMA mode persisted");
        for (int j = 1; j < 3; j++) {
            string label = analysis.getElliot(timeFrames[j]).oscillator.ema200.getBuySellLabel();
            string field = "SELECTED_" + EnumToString(timeFrames[j]) + "_EMA200#"
                + IntegerToString(StringLen(label)) + "=" + label;
            verify(StringFind(snapshot.analysisSnapshotText, field) >= 0,
                "lower EMA remains available in saved analysis");
        }

        if (!expected) {
            verify(!snapshot.isJudge && !snapshot.isSignalConsumed && snapshot.signalCount == 0,
                "H1 rejection does not consume signal");
        }

        delete analysis;
    }
}

/**
 * Reject missing and contradictory H1 EMA values while preserving the legacy gate.
 */
void verifyH1EmaInvalidStates(const bool fromIsBuy) {
    MarketContext context("EURUSD", PERIOD_M5);
    M5EmaGateFixture normal(context, true);
    M5EmaGateFixture legacy(context, false);
    verify(!normal.evaluate(NULL, fromIsBuy), "missing analysis rejected");
    for (int i = 0; i < 5; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        Elliot *h1 = analysis.getElliot(PERIOD_H1);
        if (i == 0) {
            h1.oscillator.ema200.isBuy = true;
            h1.oscillator.ema200.isSell = true;
        } else if (i == 1) {
            h1.oscillator.ema200.buySellLabel = "NONE";
        } else if (i == 2) {
            h1.oscillator.ema200.marketContext.timeFrame = PERIOD_M15;
        } else if (i == 3) {
            h1.oscillator.marketContext.timeFrame = PERIOD_M15;
        } else {
            analysis.elliotList.Delete(4);
        }

        verify(!normal.evaluate(analysis, fromIsBuy), "invalid or missing H1 EMA rejected");
        delete analysis;
    }

    ElliotAll *analysis = createAnalysis(fromIsBuy);
    setEma200Direction(analysis.getElliot(PERIOD_M15), !fromIsBuy);
    setEma200Direction(analysis.getElliot(PERIOD_M5), !fromIsBuy);
    verify(normal.evaluate(analysis, fromIsBuy), "normal policy ignores opposite lower EMAs");
    verify(!legacy.evaluate(analysis, fromIsBuy), "legacy policy retains lower EMA requirements");
    delete analysis;
}

/**
 * Use actual strategy decisions and synthetic analysis; never send orders.
 */
void OnStart() {
    M5EaStrategy strategy;
    M5EaStrategySnapshot snapshot;
    verify(!strategy.evaluate(0, snapshot) && strategy.getLastError() == "ANALYSIS_NOT_PREPARED",
        "strategy requires prepared analysis");
    verify(strategy.getWave() == NULL, "unprepared strategy has no wave");
    verifyParityMatrix(true);
    verifyParityMatrix(false);
    verifyH1OnlyEmaMatrix(true);
    verifyH1OnlyEmaMatrix(false);
    verifyH1EmaInvalidStates(true);
    verifyH1EmaInvalidStates(false);
    verifyRestoredCount();
    verifyCorrectedSnapshot(PERIOD_H1, true);
    verifyCorrectedSnapshot(PERIOD_H1, false);
    verifyCorrectedSnapshot(PERIOD_D1, true);
    verifyCorrectedSnapshot(PERIOD_D1, false);
    verifyCorrectionSelectionMatrix(true);
    verifyCorrectionSelectionMatrix(false);
    verifyD1ReanalysisScope();
    verifyJudgmentReasons(true);
    verifyJudgmentReasons(false);
    Print("MstngM5StrategySmokeTest failures=", failureCount);
}
