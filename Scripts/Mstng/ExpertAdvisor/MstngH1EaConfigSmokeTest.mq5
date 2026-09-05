#property script_show_inputs
#property strict

#include <MstngH1Ea\Config\H1EaConfig.mqh>
#include <MstngH1Ea\Runtime\H1EaInstanceLock.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>

/** 検証失敗件数。 */
int failureCount = 0;

/**
 * 実注文を行わず設定・Hashの固定契約を確認する。
 */
void assertEqual(const string fromActual, const string fromExpected, const string fromName) {
    if (fromActual != fromExpected) {
        failureCount++;
        Print("[ERROR] ", fromName, " actual=", fromActual, " expected=", fromExpected);
    }
}

/**
 * 設定判定の境界値を実注文なしで確認する。
 */
void check(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("[ERROR] ", fromName);
    }
}

/**
 * 設定値と識別子のSmokeTest。EAの初期化・broker送信は呼ばない。
 */
void OnStart() {
    assertEqual(H1EaTextUtil::hash("abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256");
    assertEqual(H1EaTextUtil::ticket(H1EaTextUtil::parseTicket("18446744073709551615")),
        "18446744073709551615", "unsigned ticket maximum roundtrip");
    assertEqual(H1EaTextUtil::ticket(H1EaTextUtil::parseTicket("9223372036854775808")),
        "9223372036854775808", "ticket above signed boundary");
    assertEqual(H1EaTextUtil::ticket(H1EaTextUtil::parseTicket("18446744073709551616")),
        "0", "ticket overflow rejected");
    assertEqual(H1EaTextUtil::ticket(H1EaTextUtil::parseTicket("-1")), "0", "negative ticket rejected");
    MarketContext marketContext("GBPAUD", PERIOD_H1, "H1", 5);
    assertEqual(H1EaTextUtil::ticket(MagicNumberUtil::build(12, marketContext, STRATEGY_TYPE_MTF_3IN3)),
        "1204050501", "magic code 12");
    H1EaConfig config;
    config.lotSize = 0.01;
    config.maxInitialStopLossPips = 75.0;
    config.isTester = false;
    config.testerTradeStartTime = 0;
    string expected = "H1_EA_CONFIG_V1|LOT_SIZE=0.01000000|MAX_INITIAL_SL_PIPS=75.0"
        "|ZIGZAG_SL_BUFFER_PIPS=10.0|MAX_SPREAD_PIPS=5.0|ANALYSIS_START_TIME_FRAME=MN1"
        "|H1_DIRECTION_ALIGNMENT_MODE=H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
        "|H1_W1_CONFIRMATION_MODE=H1_W1_CONFIRMATION_OBSERVE_ONLY"
        "|H1_EMA200_CONFIRMATION_MODE=H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED"
        "|H1_DISPLAY_WAVE_ENTRY_LIMIT_ENABLED=0|CURRENCY_STRENGTH_ENTRY_FILTER_ENABLED=0"
        "|ENTRY_COUNT=1|LIVE_FIRST_EVALUATION_SECONDS=1|LIVE_EVALUATION_INTERVAL_SECONDS=30"
        "|TESTER_EVALUATION_TRIGGER=TICK|TESTER_TRADE_START_TIME=0";
    assertEqual(config.createCanonicalText(), expected, "canonical config");
    string unrestrictedHash = H1EaTextUtil::hash(config.createCanonicalText());
    datetime startTime = D'2026.01.01 00:00';
    config.isTester = true;
    config.testerTradeStartTime = startTime;
    check(config.isBeforeTesterTradeStart(startTime - 1), "tester blocked immediately before start");
    check(!config.isBeforeTesterTradeStart(startTime), "tester allowed exactly at start");
    check(!config.isBeforeTesterTradeStart(startTime + 1), "tester allowed after start");
    string expectedRestricted = expected;
    StringReplace(expectedRestricted, "|TESTER_TRADE_START_TIME=0",
        "|TESTER_TRADE_START_TIME=" + IntegerToString(startTime));
    assertEqual(config.createCanonicalText(), expectedRestricted, "tester start canonical seconds");
    string restrictedHash = H1EaTextUtil::hash(config.createCanonicalText());
    check(StringLen(restrictedHash) == 64 && restrictedHash != unrestrictedHash,
        "tester start affects config hash");
    config.testerTradeStartTime = startTime + 3600;
    check(H1EaTextUtil::hash(config.createCanonicalText()) != restrictedHash,
        "changed tester start affects config hash");
    config.testerTradeStartTime = 0;
    check(!config.isBeforeTesterTradeStart(startTime - 86400), "zero disables tester start restriction");
    assertEqual(config.createCanonicalText(), expected, "zero restores unrestricted canonical");
    config.isTester = false;
    config.testerTradeStartTime = startTime;
    check(!config.isBeforeTesterTradeStart(startTime - 1), "LIVE ignores tester start restriction");
    Print("[INFO] MstngH1EaConfigSmokeTest failures=", failureCount);
}
