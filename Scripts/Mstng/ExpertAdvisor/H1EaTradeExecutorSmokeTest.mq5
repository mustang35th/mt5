#property strict

#include <MstngH1Ea\Trade\H1EaTradeExecutor.mqh>

/** 検証失敗件数。 */
int failedCount = 0;

/**
 * 公開APIの検証結果を記録する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        Print("INFO H1EaTradeExecutorSmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR H1EaTradeExecutorSmokeTest FAIL ", fromName);
    }
}

/**
 * DB未接続・未初期化は高速化を許可しない。
 */
void verifyUninitialized() {
    H1EaTradeExecutor executor;
    string reason;
    bool failed = executor.canEnter(TimeCurrent(), reason);
    verify(!failed && reason == "DB_UNAVAILABLE" && executor.hasActiveTrade()
        && !executor.isTrailEligible(TimeCurrent()) && !executor.hasUnsavedEvents()
        && !executor.isIdleForTesterWarmup(), "unsafe initial state rejected");
    executor.reconcile();
    executor.processPending(TimeCurrent());
    executor.evaluateTrail(TimeCurrent(), NULL);
    executor.setManagementAuthority(true, TimeLocal() + 60);
    verify(!executor.isIdleForTesterWarmup(), "authority alone does not initialize executor");
}

/**
 * 専用DBのRunだけを準備し、運用Run・運用設定を使用しない。
 */
void prepareRun(H1EaRunEntity &fromRun, const string fromUid) {
    fromRun.runUid = fromUid;
    fromRun.sourceMode = "TESTER";
    fromRun.contextKey = "H1_EA_EXECUTOR_SMOKE|" + fromUid;
    fromRun.accountServer = "SMOKE_ONLY";
    fromRun.accountLogin = 1;
    fromRun.symbolName = _Symbol;
    fromRun.magicNumber = "1204010501";
    fromRun.programVersion = "SMOKE";
    fromRun.strategyVersion = "SMOKE";
    fromRun.analysisVersion = "SMOKE";
    fromRun.analysisInputText = "H1_EA_EXECUTOR_SMOKE";
    fromRun.analysisInputHash = H1EaSql::hash(fromRun.analysisInputText);
    fromRun.configText = "H1_EA_EXECUTOR_SMOKE|NO_BROKER_SEND=1";
    fromRun.configHash = H1EaSql::hash(fromRun.configText);
}

/**
 * 実注文は送らず、既存のinitialize・reconcileで空状態の陽性経路を確認する。
 */
void verifyFreshIdle(H1EaPersistenceService &fromService, H1EaRunEntity &fromRun) {
    if (PositionsTotal() != 0 || OrdersTotal() != 0) {
        verify(false, "empty account required before reconciliation");
        return;
    }
    H1EaTradeEntity absent;
    bool found = true;
    bool loaded = fromService.loadActiveTrade(fromRun.contextKey, absent, found);
    verify(loaded && !found && absent.id == 0 && absent.status == "",
        "fresh database has no active trade");
    if (!loaded || found) {
        return;
    }
    H1EaTradeExecutor executor;
    bool initialized = executor.initialize(_Symbol, 1204010501, 0.0001, 0.00001,
        fromRun.id, fromRun.runUid, fromRun.contextKey, GetPointer(fromService));
    verify(initialized, "initialize with dedicated database");
    if (!initialized) {
        return;
    }
    executor.setManagementAuthority(true, (datetime)fromRun.leaseExpiresAt);
    verify(!executor.isIdleForTesterWarmup(), "initialized but not reconciled is rejected");
    verify(fromService.hasLease(fromRun.id, TimeLocal()), "dedicated run has valid lease");
    executor.reconcile();
    verify(!executor.hasActiveTrade() && !executor.hasUnsavedEvents(),
        "reconciliation loads empty trade state");
    verify(executor.isIdleForTesterWarmup(), "reconciled empty executor permits fast warmup");

    executor.setManagementAuthority(false, (datetime)fromRun.leaseExpiresAt);
    verify(!executor.isIdleForTesterWarmup(), "missing lock is rejected");
    executor.setManagementAuthority(true, 0);
    verify(!executor.isIdleForTesterWarmup(), "controller invalidated lease is rejected");
    executor.setManagementAuthority(true, (datetime)fromRun.leaseExpiresAt);
    verify(executor.isIdleForTesterWarmup(), "valid authority restores idle eligibility");
    executor.reconcile();
    verify(executor.isIdleForTesterWarmup(), "repeated empty reconciliation remains eligible");
    verify(PositionsTotal() == 0 && OrdersTotal() == 0, "account remains empty");
    long tradeCount = -1;
    long eventCount = -1;
    verify(H1EaSql::scalar(fromService.getHandle(), "SELECT COUNT(*) FROM h1_ea_trades", tradeCount)
        && H1EaSql::scalar(fromService.getHandle(), "SELECT COUNT(*) FROM h1_ea_trade_events", eventCount)
        && tradeCount == 0 && eventCount == 0, "no trade or event written by idle reconciliation");
}

/**
 * 今回作成した専用DBとそのsidecarだけを、接続終了後に削除する。
 */
void cleanupSmokeDatabase(const string fromFileName) {
    if (StringFind(fromFileName, "h1-ea-executor-smoke-") != 0
            || StringFind(fromFileName, "\\") >= 0 || StringFind(fromFileName, "/") >= 0) {
        verify(false, "cleanup refuses non-smoke path");
        return;
    }
    string suffixes[] = {"-wal", "-shm", ""};
    for (int i = 0; i < ArraySize(suffixes); i++) {
        string fileName = fromFileName + suffixes[i];
        if (FileIsExist(fileName, FILE_COMMON)) {
            verify(FileDelete(fileName, FILE_COMMON), "cleanup " + fileName);
        }
    }
}

/**
 * 空口座で専用DBを使う公開API回帰。Runを終了し、自身の生成物だけを片付ける。
 * PersistenceはWALを要求するためin-memory DBではなく一意なCommon DBを使用する。
 */
void verifyFreshDatabase() {
    if (PositionsTotal() != 0 || OrdersTotal() != 0) {
        verify(false, "empty account required; dedicated database not created");
        return;
    }
    string seed = "H1_EA_EXECUTOR_SMOKE|" + IntegerToString(TimeLocal())
        + "|" + IntegerToString(ChartID()) + "|" + H1EaTextUtil::ticket(GetMicrosecondCount());
    string uid = H1EaSql::hash(seed);
    if (!H1EaSql::isHash(uid)) {
        verify(false, "unique smoke identifier unavailable");
        return;
    }
    string fileName = "h1-ea-executor-smoke-" + uid + ".sqlite";
    if (FileIsExist(fileName, FILE_COMMON) || FileIsExist(fileName + "-wal", FILE_COMMON)
            || FileIsExist(fileName + "-shm", FILE_COMMON)) {
        verify(false, "existing smoke path left untouched: " + fileName);
        return;
    }
    H1EaPersistenceService service;
    H1EaRunEntity run;
    bool opened = service.open(fileName);
    verify(opened, "open dedicated smoke database");
    if (opened) {
        prepareRun(run, uid);
        bool acquired = service.acquireRun(run);
        verify(acquired, "acquire dedicated smoke run");
        if (acquired) {
            verifyFreshIdle(service, run);
            string status = "STOPPED";
            string errorText = "";
            if (failedCount > 0) {
                status = "FAILED";
                errorText = "SMOKE_ASSERTION_FAILED";
            }
            verify(service.finishRun(run.id, status, errorText), "finish dedicated smoke run");
        }
    }
    if (service.getLastError() != "") {
        Print("ERROR H1EaTradeExecutorSmokeTest database detail: ", service.getLastError());
    }
    service.close();
    cleanupSmokeDatabase(fileName);
}

/**
 * 未初期化の陰性と、DBロード・空口座照合後の陽性を実注文なしで検証する。
 */
void OnStart() {
    verifyUninitialized();
    verifyFreshDatabase();
    Print("INFO H1EaTradeExecutorSmokeTest failures=", failedCount);
}
