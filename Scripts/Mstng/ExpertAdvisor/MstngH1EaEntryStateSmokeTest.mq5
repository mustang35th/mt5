#property strict

#include <MstngH1Ea\Config\H1EaConfig.mqh>
#include <MstngH1Ea\Runtime\H1EaDecisionBuilder.mqh>
#include <MstngH1Ea\Runtime\H1EaEntryState.mqh>

/** 失敗件数。 */
int failureCount = 0;

/**
 * 実注文に依存しない状態遷移を確認する。
 */
void check(const bool fromPassed, const string fromName) {
    if (!fromPassed) {
        failureCount++;
        Print("[ERROR] ", fromName);
    }
}

/**
 * 同じGateを使う純粋な状態テスト用ハーネス。
 * 実Controllerの実行検証ではなく、Gate配線は別の静的テストで確認する。
 */
datetime observeAfterTesterStart(H1EaConfig &fromConfig, H1EaEntryState &fromState,
        const datetime fromTime, const datetime fromH1Bar) {
    if (fromConfig.isBeforeTesterTradeStart(fromTime)) {
        return 0;
    }
    return fromState.observe(fromH1Bar);
}

/**
 * 開始前のH1を観測・確定せず、開始バーへ未消費状態で進む契約を確認する。
 */
void checkTesterWarmupState() {
    H1EaConfig config;
    config.isTester = true;
    config.testerTradeStartTime = D'2026.01.01 00:00';
    H1EaEntryState state;
    datetime firstTradeBar = config.testerTradeStartTime;
    long referenceTime = (long)(firstTradeBar - 86400);
    for (int i = 3; i > 0; i--) {
        datetime warmupBar = firstTradeBar - i * 3600;
        check(observeAfterTesterStart(config, state, warmupBar, warmupBar) == 0,
            "warmup does not expire an Entry bar");
        check(!state.isFinalized(warmupBar), "warmup does not finalize an Entry bar");
    }
    check(observeAfterTesterStart(config, state, firstTradeBar - 1, firstTradeBar - 3600) == 0,
        "last warmup tick has no expired Decision");
    check(state.getCount(referenceTime, "BUY") == 0, "warmup BUY Judge count stays zero");
    check(state.getCount(referenceTime, "SELL") == 0, "warmup SELL Judge count stays zero");
    check(observeAfterTesterStart(config, state, firstTradeBar, firstTradeBar) == 0,
        "start does not create ANALYSIS_UNAVAILABLE for a warmup bar");
    check(!state.isFinalized(firstTradeBar), "first tradable H1 is not consumed");
    check(state.recordCount(referenceTime, "BUY", 1), "pre-start pivot can have first Judge after start");
    check(state.getCount(referenceTime, "BUY") == 1, "first post-start Judge is count one");
    state.finalize(firstTradeBar);
    check(observeAfterTesterStart(config, state, firstTradeBar + 1, firstTradeBar) == 0
        && state.isFinalized(firstTradeBar), "ordinary same-bar finalization remains effective");

    H1EaEntryState midBarState;
    config.testerTradeStartTime = firstTradeBar + 1800;
    check(observeAfterTesterStart(config, midBarState, firstTradeBar + 1799, firstTradeBar) == 0,
        "mid-H1 start blocks its preceding tick");
    check(observeAfterTesterStart(config, midBarState, firstTradeBar + 1800, firstTradeBar) == 0
        && !midBarState.isFinalized(firstTradeBar) && midBarState.getCount(referenceTime, "BUY") == 0,
        "mid-H1 start leaves current H1 eligible without backfill");
}

/**
 * 分析再試行・回数復元・保存待ちの非再評価を確認する。
 */
void OnStart() {
    checkTesterWarmupState();
    H1EaEntryState state;
    long times[] = {100};
    string sides[] = {"BUY"};
    int counts[] = {1};
    check(state.restore(times, sides, counts), "restore consumed SKIP");
    check(state.getCount(100, "BUY") == 1, "restored count");
    check(state.getCount(100, "SELL") == 0, "opposite side independent");
    check(state.observe(3600) == 0, "first in-progress bar");
    check(!state.isFinalized(3600), "analysis failure is retryable");
    check(state.observe(3600) == 0, "same failed bar not finalized");
    check(state.observe(7200) == 3600, "only observed failed bar expires");
    state.finalize(7200);
    check(state.isFinalized(7200), "DB-save-pending bar finalized");
    check(state.observe(14400) == 0, "no backfill unobserved bars");
    check(state.recordCount(100, "BUY", 2), "later Judge increments");
    check(!state.recordCount(100, "BUY", 1), "count never resets");
    check(state.getCount(100, "BUY") == 2, "Judge OFF retains count");
    H1EaDecisionEntity decision;
    decision.reasonCode = "DB_UNAVAILABLE";
    decision.maxInitialRiskPips = 75.0;
    decision.isJudgeMatched = true;
    decision.signalCount = 1;
    decision.isEntryEvaluated = true;
    decision.isSignalConsumed = true;
    decision.isStrategyEntry = true;
    decision.signalSide = "BUY";
    check(H1EaDecisionBuilder::seal(decision, 5), "snapshot hash");
    string originalHash = decision.snapshotHash;
    decision.createdAt = 1000;
    decision.runId = 20;
    check(H1EaDecisionBuilder::seal(decision, 5) && decision.snapshotHash == originalHash,
        "save retry preserves snapshot hash");
    decision.reasonCode = "POSITION_EXISTS";
    check(H1EaDecisionBuilder::seal(decision, 5) && decision.snapshotHash != originalHash,
        "final reason affects snapshot hash");
    Print("[INFO] MstngH1EaEntryStateSmokeTest failures=", failureCount);
}
