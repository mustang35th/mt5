#property strict

#include <MstngM15Ea\Config\M15EaConfig.mqh>

/** 検証失敗件数。 */
int failureCount = 0;

/**
 * 設定の境界値と識別子を実注文なしで確認する。
 */
void verify(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("ERROR MstngM15EaConfigSmokeTest ", fromName);
    }
}

/**
 * 口座へ接続せず、M15固有の保存契約と既定の判定設定を検証する。
 */
void OnStart() {
    M15EaConfig config;
    verify(config.directionCorrectionEnabled, "direction correction enabled by default");
    verify(config.h4MaxFibonacciExpansionPercent == 161.8
        && config.h1MaxFibonacciExpansionPercent == 161.8, "higher FE defaults");
    verify(config.databaseFileName == "mstng-m15-ea.sqlite", "separate database");
    verify(M15EaConfig::getProgramVersion() == "1.00", "program version");
    verify(M15EaConfig::getStrategyVersion() == "M15_MTF3IN3_EMA4_FE_ZIGZAG10_V1", "strategy version");
    MarketContext m15Context("GBPAUD", PERIOD_M15, "M15", 5);
    MarketContext h1Context("GBPAUD", PERIOD_H1, "H1", 5);
    ulong m15Magic = MagicNumberUtil::build(13, m15Context, STRATEGY_TYPE_MTF_3IN3);
    verify(m15Magic != 0 && m15Magic != MagicNumberUtil::build(12, h1Context, STRATEGY_TYPE_MTF_3IN3),
        "H1 magic separation");
    string canonical = config.createCanonicalText();
    verify(StringFind(canonical, "M15_EA_CONFIG_V1|") == 0, "M15 config identity");
    verify(StringFind(canonical, "|H4_MAX_FE_PERCENT=161.8|H1_MAX_FE_PERCENT=161.8") >= 0,
        "explicit higher FE settings");
    verify(StringFind(canonical, "|GMMA_TIME_FRAME=M15|ZIGZAG_CONFIRMED_REQUIRED=1") >= 0,
        "M15 GMMA and confirmed ZigZag");
    verify(StringFind(canonical, "|LIVE_EVALUATION_INTERVAL_SECONDS=30") >= 0, "30-second evaluation");
    string originalHash = EaTextUtil::hash(canonical);
    config.directionCorrectionEnabled = false;
    verify(EaTextUtil::hash(config.createCanonicalText()) != originalHash, "correction affects config hash");
    config.directionCorrectionEnabled = true;
    config.h4MaxFibonacciExpansionPercent = 0.0;
    verify(EaTextUtil::hash(config.createCanonicalText()) != originalHash, "H4 FE affects config hash");
    config.h4MaxFibonacciExpansionPercent = 161.8;
    config.h1MaxFibonacciExpansionPercent = 100.0;
    verify(EaTextUtil::hash(config.createCanonicalText()) != originalHash, "H1 FE affects config hash");
    verify(M15EaConfig::isFibonacciExpansionLimitValid(0.0), "zero disables FE");
    verify(M15EaConfig::isFibonacciExpansionLimitValid(161.84), "FE uses one decimal comparison");
    verify(!M15EaConfig::isFibonacciExpansionLimitValid(-1.0), "negative FE rejected");
    verify(!M15EaConfig::isFibonacciExpansionLimitValid(EMPTY_VALUE), "unavailable FE rejected");
    verify(!M15EaConfig::isFibonacciExpansionLimitValid(0.01), "positive FE rounding to zero rejected");
    datetime startTime = D'2026.01.01 00:00';
    config.isTester = true;
    config.testerTradeStartTime = startTime;
    verify(config.isBeforeTesterTradeStart(startTime - 1), "tester before start blocked");
    verify(!config.isBeforeTesterTradeStart(startTime), "tester start inclusive");
    config.isTester = false;
    verify(!config.isBeforeTesterTradeStart(startTime - 1), "live ignores tester restriction");
    Print("MstngM15EaConfigSmokeTest failures=", failureCount);
}
