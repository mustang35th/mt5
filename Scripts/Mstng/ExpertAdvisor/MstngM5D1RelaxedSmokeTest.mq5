#property strict

// Compile the real comparison entry point and its actual strategy adapter first.
#define MSTNG_M5_D1_COMPARISON_ENTRY_POINT initializeComparisonFixture
#define OnDeinit deinitializeComparisonFixture
#include "..\..\..\Experts\BacktestComparisons\MstngM5D1Relaxed.mq5"
#undef OnDeinit

// Reuse synthetic analysis builders; the baseline suite is executed separately.
#define OnStart runBaselineFixtureSuite
#include "MstngM5StrategySmokeTest.mq5"
#undef OnStart

/**
 * Supply a corrected snapshot while retaining the real comparison direction checks.
 */
class M5D1SelectedFixture : public M5EaD1RelaxedStrategy {
public:
    /**
     * Apply the ordinary M5 settings to the comparison fixture.
     */
    M5D1SelectedFixture(MarketContext &fromContext, const ExpertAdvisorMtf3In3Config &fromConfig)
        : M5EaD1RelaxedStrategy(fromContext, fromConfig) {
    }

    /**
     * The fixture changes H1 direction and retains its measured oscillator.
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        return PERIOD_H1;
    }

protected:
    /**
     * Avoid history reads by supplying the separately owned selected fixture.
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        return selectedFixture;
    }
};

/**
 * Verify corrected-direction validation with an opposite but valid D1 snapshot.
 */
void verifyRelaxedCorrectedSnapshot(const bool fromIsBuy) {
    ElliotAll *original = createAnalysis(fromIsBuy);
    selectedFixture = createAnalysis(fromIsBuy);
    setDirection(original.getElliot(PERIOD_D1), !fromIsBuy);
    setDirection(original.getElliot(PERIOD_H1), !fromIsBuy);
    setDirection(selectedFixture.getElliot(PERIOD_D1), !fromIsBuy);
    selectedFixture.getElliot(PERIOD_H1).oscillator.isBuy = !fromIsBuy;
    MarketContext context = original.marketContext;
    ExpertAdvisorMtf3In3Config config;
    Mtf3In3M5Policy::apply(config, false, 4);
    SignalCount count(context);
    M5D1SelectedFixture strategy(context, config);
    strategy.analyze(original, GetPointer(count), 1);
    verify(strategy.getAlertResult().isEntry, "corrected H1 accepts opposite valid D1");
    selectedFixture.getElliot(PERIOD_H1).oscillator.isBuy = fromIsBuy;
    strategy.analyze(original, GetPointer(count), 1);
    verify(!strategy.getAlertResult().isJudge, "corrected oscillator preservation still required");
    selectedFixture.getElliot(PERIOD_H1).oscillator.isBuy = !fromIsBuy;
    selectedFixture.getElliot(PERIOD_D1).oscillator.isBuy = fromIsBuy;
    strategy.analyze(original, GetPointer(count), 1);
    verify(!strategy.getAlertResult().isJudge, "selected D1 state validity still required");
    delete selectedFixture;
    selectedFixture = NULL;
    delete original;
}

/**
 * Check the comparison adapter in both directions without history access or orders.
 */
void verifyD1Comparison(const bool fromIsBuy) {
    for (int i = 0; i < 21; i++) {
        ElliotAll *analysis = createAnalysis(fromIsBuy);
        verify(analysis != NULL, "comparison fixture allocation");
        if (analysis == NULL) {
            return;
        }

        setStrength(analysis, fromIsBuy);
        setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy);
        int previousCount = 0;
        switch (i) {
            case 1: analysis.elliotCurrent.getLatestPoint().elliotLabel = "5"; break;
            case 2: analysis.getElliot(PERIOD_M15).getLatestPoint().elliotLabel = "5"; break;
            case 3: analysis.elliotCurrent.oscillator.gmmaTrendCount = 0; break;
            case 4: analysis.elliotCurrent.oscillator.gmmaCrossCount = 0; break;
            case 5: setEma200Direction(analysis.getElliot(PERIOD_H1), !fromIsBuy); break;
            case 6: setEma200Direction(analysis.getElliot(PERIOD_M15), !fromIsBuy); break;
            case 7: setEma200Direction(analysis.elliotCurrent, !fromIsBuy); break;
            case 8: analysis.todayRate.spread = 5.1; break;
            case 9: setStrength(analysis, fromIsBuy, 3); break;
            case 10: analysis.currencyStrengthExecutionInfo.longMediumGapDirection.direction *= -1; break;
            case 11: analysis.elliotCurrent.getLatestPoint().isAddedPoint = true; break;
            case 12: analysis.elliotCurrent.getLatestPoint().fibonacciExpansionPercent = 161.9; break;
            case 13:
                setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
                setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
                break;
            case 14: analysis.getElliot(PERIOD_D1).oscillator.isBuy = fromIsBuy; break;
            case 15:
                setDirection(analysis.getElliot(PERIOD_H4), !fromIsBuy);
                analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
                break;
            case 16:
                setDirection(analysis.getElliot(PERIOD_H1), !fromIsBuy);
                analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
                break;
            case 17:
                setDirection(analysis.getElliot(PERIOD_M15), !fromIsBuy);
                analysis.getElliot(PERIOD_MN1).marketContext.symbolName = "INVALID_FIXTURE";
                break;
            case 18: setDirection(analysis.getElliot(PERIOD_D1), fromIsBuy); break;
            case 19:
                analysis.elliotCurrent.oscillator.ema200.isBuy = false;
                analysis.elliotCurrent.oscillator.ema200.isSell = false;
                analysis.elliotCurrent.oscillator.ema200.buySellLabel = "NONE";
                break;
            case 20: previousCount = 1; break;
        }

        M5EaStrategyDecision adapter;
        M5EaStrategySnapshot result;
        string label = "D1 comparison " + IntegerToString((int)fromIsBuy) + "/" + IntegerToString(i);
        verify(adapter.prepare(analysis, D'2026.09.01 01:00', result)
            && adapter.evaluate(analysis, previousCount, result), label + " evaluated");
        verify(result.isStrategyEntry == (i == 0 || i == 18), label + " known outcome");
        verify(StringFind(result.analysisSnapshotText, "|D1_DIRECTION_REQUIRED#1=0") >= 0,
            label + " comparison snapshot identity");
        if (i == 0) {
            verify(result.isJudge && result.isJudgmentAnalysisAvailable
                && result.correctionTimeFrame == PERIOD_CURRENT && result.signalCount == 1,
                label + " selection and later direction gates both relaxed");
            MarketContext context = analysis.marketContext;
            SignalCount count(context);
            ExpertAdvisorMtf3In3Config config;
            Mtf3In3M5Policy::apply(config, false, 4);
            ExpertAdvisorMTF_3in3 *normal = ExpertAdvisorMtf3In3Factory::create(context, config);
            normal.analyze(analysis, GetPointer(count), 1);
            verify(!normal.getAlertResult().isEntry
                && normal.getJudgmentAnalysisRejectReason() == "M5_D1_DIRECTION_MISMATCH",
                label + " ordinary factory still requires D1");
            delete normal;
        } else if (i == 13) {
            verify(result.reasonCode == "M5_CORRECTION_NOT_APPLICABLE", label + " multiple correction rejected");
        } else if (i == 14) {
            verify(result.reasonCode == "M5_JUDGMENT_INPUT_INVALID", label + " invalid D1 rejected");
        } else if (i >= 15 && i <= 17) {
            verify(result.reasonCode == "M5_CORRECTION_ANALYSIS_FAILED",
                label + " one opposite frame reaches correction analysis");
        } else if (i == 20) {
            verify(result.reasonCode == "SIGNAL_ALREADY_CONSUMED" && result.signalCount == 2,
                label + " signal count retained");
        }

        delete analysis;
    }
}

/**
 * Confirm the real entry point rejects non-tester execution before creating a controller.
 */
void OnStart() {
    verify(!M5EaD1RelaxedFactory::isRuntimeAllowed(), "native smoke is outside tester");
    verify(initializeComparisonFixture() == INIT_FAILED && controller == NULL,
        "live initialization rejected before controller");
    M5EaConfig config;
    verify(StringFind(config.createCanonicalText(),
        "DIRECTION_ALIGNMENT_MODE=D1_OPTIONAL_H4_H1_M15_ONE_CORRECTION") >= 0,
        "comparison config identity");
    verify(M5EaConfig::getStrategyVersion()
        == "M5_ZIGZAG_ELLIOT_STRENGTH_ZIGZAG_SL_D1_OPTIONAL_TEST_V1", "comparison strategy identity");
    verifyD1Comparison(true);
    verifyD1Comparison(false);
    verifyRelaxedCorrectedSnapshot(true);
    verifyRelaxedCorrectedSnapshot(false);
    Print("MstngM5D1RelaxedSmokeTest failures=", failureCount);
}
