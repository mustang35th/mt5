#property strict

#include <MstngH1Ea\Trade\H1EaTradeExecutor.mqh>

/**
 * 接続やbroker送信を行わず初期状態がfail-closedであることを確認する。
 */
void OnStart() {
    H1EaTradeExecutor executor;
    string reason;
    bool failed = executor.canEnter(TimeCurrent(), reason);
    if (failed || reason != "DB_UNAVAILABLE" || !executor.hasActiveTrade()
            || executor.isTrailEligible(TimeCurrent()) || executor.hasUnsavedEvents()
            || executor.isIdleForTesterWarmup()) {
        Print("ERROR H1EaTradeExecutorSmokeTest unsafe initial state");
        return;
    }
    executor.reconcile();
    executor.processPending(TimeCurrent());
    executor.evaluateTrail(TimeCurrent(), NULL);
    executor.setManagementAuthority(true, TimeLocal() + 60);
    if (executor.isIdleForTesterWarmup()) {
        Print("ERROR H1EaTradeExecutorSmokeTest unloaded warmup state accepted");
        return;
    }
    Print("INFO H1EaTradeExecutorSmokeTest failures=0");
}
