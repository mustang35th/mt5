#property strict

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3M5Policy.mqh>

/** Number of failed checks. */
int failureCount = 0;

/** Selected analysis injected only for the market-dependent correction test. */
ElliotAll *selectedFixture = NULL;

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
            return PERIOD_H1;
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
            case 18: setDirection(analysis.getElliot(PERIOD_D1), !fromIsBuy); break;
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
void verifyCorrectedSnapshot() {
    ElliotAll *original = createAnalysis(true);
    ElliotAll *selected = createAnalysis(true);
    setDirection(original.getElliot(PERIOD_H1), false);
    original.getElliot(PERIOD_H1).getLatestWave().isUptrend = false;
    selected.getElliot(PERIOD_H1).oscillator.isBuy = false;
    ZigZagPoint *sourcePivot = original.elliotCurrent.getLatestPoint2();
    ZigZagPoint *selectedPivot = selected.elliotCurrent.getLatestPoint2();
    selectedPivot.barTime += 300;
    selectedPivot.rate -= 0.001;
    selectedFixture = selected;
    M5EaStrategyDecision decision;
    M5EaStrategySnapshot snapshot;
    verify(decision.prepare(original, D'2026.09.01 01:00', snapshot)
        && decision.evaluate(original, 0, snapshot) && snapshot.isStrategyEntry
        && snapshot.correctionTimeFrame == PERIOD_H1, "selected correction enters");
    verify(snapshot.signalReferenceTime == sourcePivot.barTime
        && snapshot.signalReferencePrice == sourcePivot.rate, "original count key preserved");
    verify(snapshot.initialStopLossPivotTime == selectedPivot.barTime
        && snapshot.initialStopLossPivotPrice == selectedPivot.rate, "selected correction supplies SL");
    verify(decision.prepare(original, D'2026.09.01 01:05', snapshot)
        && decision.evaluate(original, 1, snapshot) && !snapshot.isStrategyEntry,
        "correction cannot bypass consumed original key");
    selectedFixture = NULL;
    delete selected;
    delete original;
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
    verifyRestoredCount();
    verifyCorrectedSnapshot();
    Print("MstngM5StrategySmokeTest failures=", failureCount);
}
