#property strict
#property version "1.00"

#include <MstngM15Ea\Persistence\M15EaPersistenceService.mqh>

/** 成功件数。 */
int passedCount = 0;
/** 失敗件数。 */
int failedCount = 0;

/**
 * 独立DBだけを操作する検証結果を記録する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        passedCount++;
        Print("INFO M15EaPersistenceSmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR M15EaPersistenceSmokeTest FAIL ", fromName);
    }
}

/**
 * brokerや口座を参照せずM15専用Runを構成する。
 */
void prepareRun(M15EaRunEntity &fromRun, const string fromUid) {
    fromRun.runUid = M15EaSql::hash(fromUid);
    fromRun.sourceMode = "TESTER";
    fromRun.contextKey = "M15_EA_CONTEXT_V1|TESTER|" + fromRun.runUid + "|SMOKE";
    fromRun.accountServer = "SMOKE_ONLY";
    fromRun.accountLogin = 1;
    fromRun.symbolName = "EURUSD";
    fromRun.magicNumber = "1201020515";
    fromRun.programVersion = "SMOKE";
    fromRun.strategyVersion = "SMOKE";
    fromRun.analysisVersion = "SMOKE";
    fromRun.analysisInputText = "M15_SMOKE|NO_BROKER_API=1";
    fromRun.analysisInputHash = M15EaSql::hash(fromRun.analysisInputText);
    fromRun.configText = "M15_SMOKE|TIME_FRAME=15";
    fromRun.configHash = M15EaSql::hash(fromRun.configText);
}

/**
 * coreとversion付き診断文字列を持つ初回判定を構成する。
 */
void prepareDecision(M15EaDecisionEntity &fromDecision, const M15EaRunEntity &fromRun,
        const long fromBar, const long fromReference, const string fromSide) {
    fromDecision.reset();
    fromDecision.contextKey = fromRun.contextKey;
    fromDecision.barTime = fromBar;
    fromDecision.evaluatedServerTime = fromBar + 1;
    fromDecision.createdAt = (long)TimeLocal();
    fromDecision.signalReferenceTime = fromReference;
    fromDecision.signalSide = fromSide;
    fromDecision.isJudgeMatched = true;
    fromDecision.signalCount = 1;
    fromDecision.isEntryEvaluated = true;
    fromDecision.isSignalConsumed = true;
    fromDecision.reasonCode = "SMOKE_SKIP";
    fromDecision.maxInitialRiskPips = 200.0;
    fromDecision.analysisSnapshotText = "M15_EA_DECISION_V1|bar=" + IntegerToString(fromBar)
        + "|side=" + fromSide + "|diagnostics=日本語・未取得~";
    fromDecision.snapshotHash = M15EaSql::hash(fromDecision.analysisSnapshotText);
}

/**
 * 確定判定と再起動後のBUY/SELL別回数を確認する。
 */
void verifyDecisions(M15EaPersistenceService &fromService, const M15EaRunEntity &fromRun) {
    M15EaDecisionEntity first;
    prepareDecision(first, fromRun, 90000, 88000, "BUY");
    verify(fromService.saveDecision(fromRun.id, first) && first.id > 0,
        "first M15 decision saved");
    long firstId = first.id;
    verify(fromService.saveDecision(fromRun.id, first) && first.id == firstId,
        "identical decision is idempotent");
    M15EaDecisionEntity conflict = first;
    conflict.analysisSnapshotText += "|changed=1";
    conflict.snapshotHash = M15EaSql::hash(conflict.analysisSnapshotText);
    verify(!fromService.saveDecision(fromRun.id, conflict), "same bar conflict rejected");
    M15EaDecisionEntity second;
    prepareDecision(second, fromRun, 90900, 88000, "BUY");
    second.signalCount = 2;
    second.isEntryEvaluated = false;
    second.isSignalConsumed = false;
    verify(fromService.saveDecision(fromRun.id, second), "900 second next bar count saved");
    M15EaDecisionEntity opposite;
    prepareDecision(opposite, fromRun, 91800, 88000, "SELL");
    verify(fromService.saveDecision(fromRun.id, opposite), "same reference opposite side separate");
    M15EaDecisionEntity badPrefix;
    prepareDecision(badPrefix, fromRun, 92700, 87000, "BUY");
    badPrefix.analysisSnapshotText = "H1_EA_DECISION_V1|invalid=1";
    verify(!fromService.saveDecision(fromRun.id, badPrefix), "H1 diagnostic prefix rejected");
    M15EaDecisionEntity loaded;
    bool found = false;
    verify(fromService.loadDecision(fromRun.contextKey, first.barTime, loaded, found)
        && found && loaded.analysisSnapshotText == first.analysisSnapshotText
        && loaded.snapshotHash == first.snapshotHash && loaded.signalCount == 1,
        "diagnostic Japanese and null markers round trip");
    long times[];
    string sides[];
    int counts[];
    verify(fromService.loadSignalCounts(fromRun.contextKey, times, sides, counts)
        && ArraySize(times) == 2 && times[0] == 88000 && times[1] == 88000
        && sides[0] == "BUY" && counts[0] == 2 && sides[1] == "SELL" && counts[1] == 1,
        "signal counts restore by reference and side");
    verify(fromService.loadSignalCounts("H1_EA_CONTEXT_V1|OTHER", times, sides, counts)
        && ArraySize(times) == 0, "other context has no M15 counts");
}

/**
 * 取引とイベントの原子性、未解決要求、pending保護状態を検証する。
 */
bool verifyTrade(M15EaPersistenceService &fromService, const M15EaRunEntity &fromRun,
        EaTradeState &fromTrade) {
    M15EaDecisionEntity decision;
    prepareDecision(decision, fromRun, 93600, 89000, "BUY");
    decision.decision = "BUY";
    decision.isStrategyEntry = true;
    decision.initialStopLoss = 1.09;
    fromTrade.contextKey = fromRun.contextKey;
    fromTrade.status = "OPEN_PENDING";
    fromTrade.side = "BUY";
    fromTrade.requestedVolume = 0.01;
    fromTrade.requestedStopLoss = 1.09;
    fromTrade.createdAt = (long)TimeLocal();
    fromTrade.updatedAt = fromTrade.createdAt;
    EaTradeEvent event;
    event.eventType = "ENTRY_REQUEST";
    event.actionUid = "M15_ENTRY|{TRADE_ID}";
    event.eventUid = event.actionUid + "|REQUEST";
    // recordedAt欠損でEvent INSERTが失敗し、先行Decision/Tradeもrollbackされる。
    verify(!fromService.saveEntry(fromRun.id, decision, fromTrade, event)
        && decision.id == 0 && fromTrade.id == 0 && event.id == 0,
        "atomic entry failure keeps caller snapshots unchanged");
    long count = -1;
    verify(M15EaSql::scalar(fromService.getHandle(),
        "SELECT COUNT(*) FROM m15_ea_decisions WHERE bar_time=93600", count) && count == 0
        && M15EaSql::scalar(fromService.getHandle(), "SELECT COUNT(*) FROM m15_ea_trades", count)
        && count == 0, "atomic entry failure leaves no decision or trade");
    event.recordedAt = (long)TimeLocal();
    bool saved = fromService.saveEntry(fromRun.id, decision, fromTrade, event);
    verify(saved && fromTrade.id > 0 && event.tradeId == fromTrade.id && event.sequence == 1,
        "entry decision trade event committed together");
    if (!saved) {
        return false;
    }
    string entryAction = event.actionUid;
    verify(StringFind(fromService.unresolvedActionsText(fromTrade.id), entryAction) >= 0,
        "unresolved entry request restored");
    fromTrade.status = "OPEN";
    fromTrade.positionIdentifier = "9001";
    fromTrade.positionTicket = "9002";
    fromTrade.openedAtMsc = 93601000;
    fromTrade.openPrice = 1.10;
    fromTrade.openedVolume = 0.01;
    fromTrade.remainingPositionVolume = 0.01;
    fromTrade.remainingEntryVolume = 0.0;
    fromTrade.currentStopLoss = 1.09;
    fromTrade.stopLossSource = "INITIAL_STOP_LOSS";
    event.reset();
    event.eventType = "ENTRY_RESULT";
    event.actionUid = entryAction;
    event.eventUid = entryAction + "|RESULT";
    event.recordedAt = (long)TimeLocal();
    verify(fromService.saveTradeEvent(fromRun.id, fromTrade, event), "entry result saved");
    verify(fromService.unresolvedActionsText(fromTrade.id) == "", "resolved entry is absent");
    fromTrade.lastTrailEvaluatedBarTime = 94500;
    fromTrade.pendingStopLossKind = "TRAIL_CANDIDATE";
    fromTrade.pendingStopLossBarTime = 94500;
    fromTrade.pendingStopLoss = 1.095;
    fromTrade.pendingStopLossPivotTime = 92700;
    fromTrade.pendingStopLossPivotRate = 1.094;
    fromTrade.pendingStopLossLatestTime = 93600;
    fromTrade.pendingStopLossActionUid = "M15_SL|9001|94500";
    fromTrade.exitIntentReason = "M15_ZIGZAG_TRAIL_CROSSED";
    event.reset();
    event.eventType = "SL_MODIFY_REQUEST";
    event.actionUid = fromTrade.pendingStopLossActionUid;
    event.eventUid = event.actionUid + "|REQUEST";
    event.positionIdentifier = fromTrade.positionIdentifier;
    event.positionTicket = fromTrade.positionTicket;
    event.barTime = fromTrade.pendingStopLossBarTime;
    event.pivotBarTime = fromTrade.pendingStopLossPivotTime;
    event.pivotRate = fromTrade.pendingStopLossPivotRate;
    event.latestPointBarTime = fromTrade.pendingStopLossLatestTime;
    event.stopLoss = fromTrade.pendingStopLoss;
    event.stopLossActionKind = "TRAIL_CANDIDATE";
    event.recordedAt = (long)TimeLocal();
    verify(!fromService.saveTradeEvent(fromRun.id, fromTrade, event, false),
        "fresh request cannot bypass lease");
    verify(fromService.saveTradeEvent(fromRun.id, fromTrade, event), "pending M15 trail request saved");
    long eventId = event.id;
    verify(fromService.saveTradeEvent(fromRun.id, fromTrade, event) && event.id == eventId,
        "same event is idempotent");
    EaTradeState loaded;
    bool found = false;
    verify(fromService.loadActiveTrade(fromRun.contextKey, loaded, found) && found
        && M15EaTradeDao::values(loaded) == M15EaTradeDao::values(fromTrade),
        "shared trade state retains every persisted field");
    string raw = "";
    verify(fromService.loadPendingRaw(fromTrade.id, raw)
        && StringFind(raw, "M15_EA_PENDING_RAW_V1|") == 0
        && StringFind(raw, "pending_stop_loss_bar_time") >= 0
        && StringFind(raw, "94500") >= 0, "pending raw uses M15 neutral bar column");
    event.reset();
    event.eventType = "EXIT_REQUEST";
    event.actionUid = "M15_EXIT|9001";
    event.eventUid = event.actionUid + "|REQUEST";
    event.serverTime = 94799;
    event.exitIntentReason = fromTrade.exitIntentReason;
    event.recordedAt = (long)TimeLocal();
    verify(fromService.saveTradeEvent(fromRun.id, fromTrade, event), "crossed exit intent saved");
    datetime blockedBar = 0;
    verify(fromService.loadCrossBlockedBar(fromRun.contextKey, blockedBar) && blockedBar == 94500,
        "cross block rounds to 900 seconds");
    return true;
}

/**
 * UNKNOWN保護状態とCLOSED約定追記を確認し、監査によるsnapshot巻戻しを拒否する。
 */
void verifyClosedAudit(M15EaPersistenceService &fromService, const M15EaRunEntity &fromRun,
        const EaTradeState &fromOriginal) {
    EaTradeState trade = fromOriginal;
    trade.status = "RECOVERY_REQUIRED";
    trade.currentStopLoss = 0.0;
    trade.stopLossSource = "UNKNOWN";
    trade.remainingPositionVolume = EMPTY_VALUE;
    EaTradeEvent event;
    event.eventType = "RECOVERY";
    event.eventUid = "M15_UNKNOWN_PROTECTION";
    event.recordedAt = (long)TimeLocal();
    verify(fromService.saveTradeEvent(fromRun.id, trade, event, false), "unknown broker state saved for recovery");
    EaTradeState loaded;
    bool found = false;
    verify(fromService.loadActiveTrade(fromRun.contextKey, loaded, found) && found
        && loaded.status == "RECOVERY_REQUIRED" && loaded.currentStopLoss == 0.0
        && loaded.stopLossSource == "UNKNOWN" && loaded.remainingPositionVolume == EMPTY_VALUE,
        "unknown protection and volume remain unavailable after restore");
    trade.status = "CLOSED";
    trade.currentStopLoss = 1.095;
    trade.stopLossSource = "M15_ZIGZAG_TRAIL";
    trade.remainingPositionVolume = 0.0;
    trade.pendingStopLossKind = "";
    trade.pendingStopLossBarTime = 0;
    trade.pendingStopLoss = 0.0;
    trade.pendingStopLossPivotTime = 0;
    trade.pendingStopLossPivotRate = 0.0;
    trade.pendingStopLossLatestTime = 0;
    trade.pendingStopLossActionUid = "";
    trade.closedAtMsc = 95000000;
    trade.closePrice = 1.095;
    trade.closeReason = "M15_ZIGZAG_TRAIL";
    trade.brokerCloseReason = "SL";
    trade.entryDealTicket = "10001";
    trade.lastError = "DEAL_EVENTS_PENDING";
    event.reset();
    event.eventType = "RECOVERY";
    event.eventUid = "M15_CLOSED_PROTECTION";
    event.recordedAt = (long)TimeLocal();
    verify(fromService.saveTradeEvent(fromRun.id, trade, event, false), "closed state saved with audit pending");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, loaded, found)
        && found && loaded.id == trade.id, "closed audit selects missing deal");
    event.reset();
    event.eventType = "DEAL_ADD";
    event.eventSource = "RECONCILIATION";
    event.recordedAt = (long)TimeLocal();
    event.dealTicket = trade.entryDealTicket;
    event.dealScopeKey = "TESTER|" + fromRun.runUid + "|" + event.dealTicket;
    event.eventUid = event.dealScopeKey;
    event.brokerTimeMsc = trade.openedAtMsc;
    event.positionIdentifier = trade.positionIdentifier;
    event.side = "BUY";
    event.brokerReason = "EXPERT";
    EaTradeEvent wrongScope = event;
    wrongScope.positionIdentifier = "OTHER_POSITION";
    verify(!fromService.appendClosedDealEvent(fromRun.id, trade.id, wrongScope),
        "closed deal with different position refused");
    verify(fromService.appendClosedDealEvent(fromRun.id, trade.id, event), "closed deal appended without broker call");
    long savedEventId = event.id;
    verify(fromService.appendClosedDealEvent(fromRun.id, trade.id, event) && event.id == savedEventId,
        "closed deal audit is idempotent");
    verify(fromService.loadClosedTradeByPosition(fromRun.contextKey, trade.positionIdentifier, loaded, found)
        && found && M15EaTradeDao::values(loaded) == M15EaTradeDao::values(trade),
        "closed audit leaves all trade snapshot fields unchanged");
    verify(fromService.completeClosedDealAudit(fromRun.id, trade.id), "closed audit marker cleared");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, loaded, found) && !found,
        "completed audit leaves no missing deal candidate");
    trade.status = "OPEN";
    event.reset();
    event.eventType = "ERROR";
    event.eventUid = "M15_CLOSED_REWIND";
    event.recordedAt = (long)TimeLocal();
    verify(!fromService.saveTradeEvent(fromRun.id, trade, event, false),
        "closed state cannot rewind to open");
}

/**
 * 別接続の共通Storeから保護状態を復元し、所有権交代後の旧Run書込みを拒否する。
 */
void verifyRestoreAndOwnership(const string fromFile, M15EaPersistenceService &fromService,
        M15EaRunEntity &fromRun, const EaTradeState &fromExpected) {
    M15EaPersistenceService reopened;
    verify(reopened.open(fromFile, false), "reconnect validates schema without DDL");
    IEaTradeStore *store = GetPointer(reopened);
    EaTradeState restored;
    bool found = false;
    verify(store.loadActiveTrade(fromRun.contextKey, restored, found) && found
        && M15EaTradeDao::values(restored) == M15EaTradeDao::values(fromExpected)
        && restored.pendingStopLossBarTime == 94500
        && restored.exitIntentReason == "M15_ZIGZAG_TRAIL_CROSSED",
        "fresh common store restores pending protection and exit intent");
    reopened.close();
    verifyClosedAudit(fromService, fromRun, fromExpected);
    verify(fromService.finishRun(fromRun.id, "STOPPED", ""), "first run finishes");
    M15EaRunEntity successor;
    prepareRun(successor, fromRun.runUid + "|successor");
    successor.contextKey = fromRun.contextKey;
    verify(fromService.acquireRun(successor), "successor owns same context");
    EaTradeEvent event;
    event.eventType = "ERROR";
    event.eventUid = "M15_OLD_OWNER_ERROR";
    event.recordedAt = (long)TimeLocal();
    verify(!fromService.saveTradeEvent(fromRun.id, restored, event, false)
        && fromService.getLastError() == "SNAPSHOT_OWNER_SUPERSEDED",
        "old owner cannot overwrite even without lease");
    verify(fromService.finishRun(successor.id, "STOPPED", "AUDIT_STATE_LOST"),
        "audit gap is recorded");
    bool auditGap = false;
    verify(fromService.hasAuditGap(fromRun.contextKey, auditGap) && auditGap,
        "audit gap survives run completion");
}

/**
 * 独立fixtureでH1 DBと未知M15 schemaを拒否し内容を維持する。
 */
void verifySchemaRejection(const string fromFile, const string fromForeignFile) {
    int handle = DatabaseOpen(fromForeignFile, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON);
    verify(handle != INVALID_HANDLE && M15EaSql::execute(handle, "CREATE TABLE h1_ea_runs (id INTEGER, marker TEXT)")
        && M15EaSql::execute(handle, "INSERT INTO h1_ea_runs VALUES (1,'H1_UNCHANGED')")
        && M15EaSql::execute(handle, "PRAGMA user_version=4"), "foreign H1 fixture created");
    if (handle != INVALID_HANDLE) {
        DatabaseClose(handle);
    }
    M15EaPersistenceService service;
    verify(!service.open(fromForeignFile), "existing H1 database refused");
    handle = DatabaseOpen(fromForeignFile, DATABASE_OPEN_READONLY | DATABASE_OPEN_COMMON);
    long count = 0;
    verify(handle != INVALID_HANDLE && M15EaSql::scalar(handle,
        "SELECT COUNT(*) FROM h1_ea_runs WHERE marker='H1_UNCHANGED'", count) && count == 1
        && M15EaSql::scalar(handle, "SELECT COUNT(*) FROM sqlite_schema WHERE name LIKE 'm15_ea_%'", count)
        && count == 0, "rejected H1 fixture unchanged");
    if (handle != INVALID_HANDLE) {
        DatabaseClose(handle);
    }
    handle = DatabaseOpen(fromFile, DATABASE_OPEN_READWRITE | DATABASE_OPEN_COMMON);
    verify(handle != INVALID_HANDLE && M15EaSql::execute(handle, "PRAGMA user_version=2"),
        "unknown version fixture prepared");
    if (handle != INVALID_HANDLE) {
        DatabaseClose(handle);
    }
    verify(!service.open(fromFile), "unknown M15 schema version refused");
    handle = DatabaseOpen(fromFile, DATABASE_OPEN_READWRITE | DATABASE_OPEN_COMMON);
    verify(handle != INVALID_HANDLE && M15EaSql::execute(handle, "PRAGMA user_version=1")
        && M15EaSql::execute(handle, "DROP INDEX idx_m15_ea_trades_active_context"),
        "missing safety index fixture prepared");
    if (handle != INVALID_HANDLE) {
        DatabaseClose(handle);
    }
    verify(!service.open(fromFile), "same version missing safety index refused");
}

/**
 * 今回作成した専用名のDBだけを削除する。
 */
void cleanup(const string fromFile) {
    if (StringFind(fromFile, "m15-ea-persistence-smoke-") != 0
            || StringFind(fromFile, "\\") >= 0 || StringFind(fromFile, "/") >= 0) {
        verify(false, "cleanup path guard");
        return;
    }
    string suffixes[] = {"-wal", "-shm", ""};
    for (int i = 0; i < ArraySize(suffixes); i++) {
        string file = fromFile + suffixes[i];
        if (FileIsExist(file, FILE_COMMON)) {
            verify(FileDelete(file, FILE_COMMON), "cleanup " + suffixes[i]);
        }
    }
}

/**
 * 実注文・口座参照なしでM15永続化を検証する。
 */
void OnStart() {
    string uid = M15EaSql::hash(IntegerToString((long)TimeLocal()) + "|"
        + IntegerToString(ChartID()) + "|" + IntegerToString((long)GetMicrosecondCount()));
    string file = "m15-ea-persistence-smoke-" + uid + ".sqlite";
    string foreignFile = "m15-ea-persistence-smoke-" + uid + "-foreign.sqlite";
    if (uid == "" || FileIsExist(file, FILE_COMMON) || FileIsExist(foreignFile, FILE_COMMON)
            || FileIsExist(file + "-wal", FILE_COMMON) || FileIsExist(file + "-shm", FILE_COMMON)
            || FileIsExist(foreignFile + "-wal", FILE_COMMON) || FileIsExist(foreignFile + "-shm", FILE_COMMON)) {
        verify(false, "unique database names required");
        return;
    }
    M15EaPersistenceService service;
    if (service.open(file)) {
        long version = 0;
        verify(M15EaSql::scalar(service.getHandle(), "PRAGMA user_version", version) && version == 1,
            "M15 schema version 1 created");
        M15EaRunEntity wrongTimeFrame;
        prepareRun(wrongTimeFrame, uid + "|wrong-time-frame");
        wrongTimeFrame.timeFrame = PERIOD_H1;
        verify(!service.acquireRun(wrongTimeFrame) && wrongTimeFrame.id == 0,
            "H1 run rejected by M15 time frame constraint");
        M15EaRunEntity run;
        prepareRun(run, uid);
        if (service.acquireRun(run)) {
            verify(service.hasLease(run.id, TimeLocal()), "M15 run lease acquired");
            M15EaRunEntity duplicate = run;
            duplicate.id = 0;
            duplicate.runUid = M15EaSql::hash(uid + "|duplicate");
            verify(!service.acquireRun(duplicate), "active context lease is exclusive");
            verifyDecisions(service, run);
            EaTradeState trade;
            if (verifyTrade(service, run, trade)) {
                verifyRestoreAndOwnership(file, service, run, trade);
            } else {
                service.finishRun(run.id, "FAILED", "SMOKE_FAILED");
            }
        } else {
            verify(false, "M15 run acquired");
        }
        service.close();
        verifySchemaRejection(file, foreignFile);
    } else {
        verify(false, "M15 database opened");
    }
    cleanup(file);
    cleanup(foreignFile);
    Print("INFO M15EaPersistenceSmokeTest SUMMARY passed=", passedCount, " failed=", failedCount);
}
