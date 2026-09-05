#property strict
#property script_show_inputs

#include <MstngH1Ea\Trade\H1EaProtectionPolicy.mqh>

/** 失敗数。 */
int failureCount = 0;

/**
 * broker送信なしで保護判定の境界値を確認する。
 */
void verify(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("ERROR H1EaProtectionPolicySmokeTest ", fromName);
    }
}

/**
 * 純粋判定だけを実行し注文は一切送信しない。
 */
void OnStart() {
    verify(H1EaProtectionPolicy::protects(true, 1.1, 1.100004, 0.00001), "BUY half tick");
    verify(!H1EaProtectionPolicy::protects(true, 0, 1.1, 0.00001), "SL absent");
    verify(H1EaProtectionPolicy::protects(false, 1.099, 1.1, 0.00001), "SELL stronger");
    verify(!H1EaProtectionPolicy::improves(true, 1.100005, 1.1, 0.00001), "subtick rejected");
    verify(H1EaProtectionPolicy::improves(false, 1.09999, 1.1, 0.00001), "SELL one tick");
    verify(H1EaProtectionPolicy::crossed(true, 1.1, 1.1002, 1.1), "BUY equality cross");
    verify(H1EaProtectionPolicy::crossed(false, 1.1, 1.1002, 1.1002), "SELL equality cross");
    verify(!H1EaProtectionPolicy::canModify(true, 1.1, 1.1002, 1.0998, 0.00001, 0.00001, 20, 10), "extra tick");
    verify(H1EaProtectionPolicy::canModify(true, 1.1, 1.1002, 1.09979, 0.00001, 0.00001, 20, 10), "stops boundary");
    verify(H1EaProtectionPolicy::isUnknownRetcode(TRADE_RETCODE_TIMEOUT), "timeout unknown");
    verify(!H1EaProtectionPolicy::canResolveModify(false, 1.09, 1.1, 0.00001), "old SL not terminal");
    verify(!H1EaProtectionPolicy::canResolveModify(false, 1.11, 1.1, 0.00001), "stronger SL not action proof");
    verify(H1EaProtectionPolicy::canResolveModify(false, 1.1, 1.1, 0.00001), "target reflected");
    verify(H1EaProtectionPolicy::canResolveModify(true, 0.0, 1.1, 0.00001), "terminal absent SL");
    verify(!H1EaProtectionPolicy::isTerminalOrder(ORDER_STATE_PARTIAL), "partial not terminal");
    verify(H1EaProtectionPolicy::closeReason("", "UNKNOWN", "SL") == "UNKNOWN_STOP_LOSS", "unknown source");
    verify(H1EaProtectionPolicy::closeReason("H1_ZIGZAG_TRAIL_CROSSED", "INITIAL_STOP_LOSS", "SL") == "H1_ZIGZAG_TRAIL_CROSSED", "intent priority");
    Print("INFO H1EaProtectionPolicySmokeTest failures=", failureCount);
}
