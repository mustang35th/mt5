#property strict

#include <MstngM5Ea\Config\M5EaConfig.mqh>

/** Number of failed checks. */
int failureCount = 0;

/**
 * Record validation results without an account connection or order request.
 */
void verify(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("ERROR MstngM5EaConfigSmokeTest ", fromName);
    }
}

/**
 * Every configurable behavior must affect the persisted configuration hash.
 */
void verifyHashCoverage() {
    M5EaConfig baseline;
    string originalHash = EaTextUtil::hash(baseline.createCanonicalText());
    for (int i = 0; i < 13; i++) {
        M5EaConfig changed;
        switch (i) {
            case 0: changed.lotSize = 0.02; break;
            case 1: changed.maxInitialStopLossPips = 99.0; break;
            case 2: changed.initialStopLossBufferPips = 0.0; break;
            case 3: changed.trailStopLossBufferPips = 20.0; break;
            case 4: changed.testerTradeStartTime = D'2026.01.01'; break;
            case 5: changed.currencyStrengthEnabled = false; break;
            case 6: changed.currencyStrengthMinimumRankDifference = 3; break;
            case 7: changed.longMediumGapDirectionEnabled = false; break;
            case 8: changed.currencyStrengthDatabaseFileName = "smoke-alternative.sqlite"; break;
            case 9: changed.currencyStrengthDatabaseSplitByYear = false; break;
            case 10: changed.currencyStrengthDatabaseUseCommonFolder = false; break;
            case 11: changed.currencyStrengthDatabaseProfile = CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER; break;
            case 12: changed.currencyStrengthVoteWeightMode = CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM; break;
        }

        verify(EaTextUtil::hash(changed.createCanonicalText()) != originalHash,
            "setting changes hash " + IntegerToString(i));
    }
}

/**
 * Invalid inputs fail before reaching account or symbol APIs on the M5 chart.
 */
void verifyInputGuards() {
    M5EaConfig config;
    M5EaSettings settings;
    settings.initialStopLossBufferPips = -0.1;
    verify(!config.initialize("EURUSD", settings) && config.lastError == "INVALID_SL_BUFFER_PIPS",
        "negative initial buffer rejected before account access");
    settings.initialStopLossBufferPips = 10.0;
    settings.trailStopLossBufferPips = 0.01;
    verify(!config.initialize("EURUSD", settings) && config.lastError == "INVALID_SL_BUFFER_PIPS",
        "fractional trail buffer rejected before account access");
    settings.trailStopLossBufferPips = 10.0;
    settings.maxInitialStopLossPips = 0.0;
    verify(!config.initialize("EURUSD", settings) && config.lastError == "MAX_INITIAL_SL_UNSET",
        "zero maximum initial risk rejected");
    settings.maxInitialStopLossPips = 100.0;
    settings.currencyStrengthMinimumRankDifference = 8;
    verify(!config.initialize("EURUSD", settings)
        && config.lastError == "INVALID_CURRENCY_STRENGTH_RANK_DIFFERENCE", "rank difference range checked");
    settings.currencyStrengthMinimumRankDifference = 4;
    settings.currencyStrengthDatabaseFileName = "";
    verify(!config.initialize("EURUSD", settings) && config.lastError == "INVALID_CURRENCY_STRENGTH_SOURCE",
        "enabled strength requires a database name");
}

/**
 * Check M5 identity, canonical settings, boundary validation and tester timing.
 */
void OnStart() {
    M5EaSettings settings;
    M5EaConfig config;
    verify(settings.currencyStrengthEnabled && settings.longMediumGapDirectionEnabled
        && settings.currencyStrengthMinimumRankDifference == 4, "normal M5 strength defaults");
    verify(settings.initialStopLossBufferPips == 10.0 && settings.trailStopLossBufferPips == 10.0,
        "independent initial and trail buffer defaults");
    verify(settings.currencyStrengthDatabaseProfile == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER
        && settings.currencyStrengthVoteWeightMode == CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED,
        "normal indicator source and weighting defaults");
    verify(config.databaseFileName == "mstng-m5-ea.sqlite", "dedicated M5 database");
    verify(M5EaConfig::getProgramVersion() == "1.04", "program version");
    MarketContext m5Context("GBPAUD", PERIOD_M5, "M5", 5);
    MarketContext m15Context("GBPAUD", PERIOD_M15, "M15", 5);
    MarketContext h1Context("GBPAUD", PERIOD_H1, "H1", 5);
    ulong magic = MagicNumberUtil::build(14, m5Context, STRATEGY_TYPE_MTF_3IN3);
    verify(magic != 0 && magic != MagicNumberUtil::build(13, m15Context, STRATEGY_TYPE_MTF_3IN3)
        && magic != MagicNumberUtil::build(12, h1Context, STRATEGY_TYPE_MTF_3IN3), "independent M5 magic");
    string canonical = config.createCanonicalText();
    verify(StringFind(canonical, "M5_EA_CONFIG_V1|") == 0, "M5 configuration identity");
    verify(StringFind(canonical, "DIRECTION_ALIGNMENT_MODE=D1_H4_H1_M15_ONE_CORRECTION") >= 0,
        "D1 correction policy identity");
    verify(M5EaConfig::getStrategyVersion() == "M5_ZIGZAG_ELLIOT_STRENGTH_ZIGZAG_SL_D1_CORRECTION_EMA_H1_V3",
        "D1 correction strategy version");
    verify(StringFind(canonical, "|MAIN_WAVE_CONDITION=M15_1_OR_3_AND_M5_1_OR_3|") >= 0,
        "normal M5 wave contract recorded");
    verify(StringFind(canonical, "|EMA200_CONFIRMATION_MODE=H1_ONLY|EMA200_DISTANCE_REQUIRED=0") >= 0,
        "normal M5 EMA direction without distance limit");
    verify(M5EaConfig::isPipsSettingValid(0.0) && M5EaConfig::isPipsSettingValid(10.1),
        "zero and one-decimal buffers supported");
    verify(!M5EaConfig::isPipsSettingValid(-0.1) && !M5EaConfig::isPipsSettingValid(EMPTY_VALUE)
        && !M5EaConfig::isPipsSettingValid(0.01), "invalid pips settings rejected");
    datetime startTime = D'2026.01.01';
    config.isTester = true;
    config.testerTradeStartTime = startTime;
    verify(config.isBeforeTesterTradeStart(startTime - 1)
        && !config.isBeforeTesterTradeStart(startTime), "tester boundary inclusive");
    config.isTester = false;
    verify(!config.isBeforeTesterTradeStart(startTime - 1), "live ignores tester start");
    verifyHashCoverage();
    if (_Period == PERIOD_M5) {
        verifyInputGuards();
    } else {
        verify(false, "run this fixture on M5 to validate startup guards");
    }

    Print("MstngM5EaConfigSmokeTest failures=", failureCount);
}
