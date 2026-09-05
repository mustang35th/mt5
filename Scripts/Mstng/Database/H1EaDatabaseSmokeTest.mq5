#property version "1.00"

#include <Mstng\Database\Dao\H1EaDecisionDao.mqh>
#include <Mstng\Database\Dao\H1EaRunDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeEventDao.mqh>
#include <Mstng\Database\Service\H1EaPersistenceService.mqh>

/** 検証成功件数。 */
int passedCount = 0;
/** 検証失敗件数。 */
int failedCount = 0;

/**
 * 実口座への注文を行わないDB検証の結果を記録する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        passedCount++;
        Print("INFO H1EaDatabaseSmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR H1EaDatabaseSmokeTest FAIL ", fromName);
    }
}

/**
 * スモーク専用Runを構成する。
 */
void prepareRun(H1EaRunEntity &fromRun, const string fromUid) {
    fromRun.runUid = H1EaSql::hash(fromUid);
    fromRun.sourceMode = "TESTER";
    fromRun.contextKey = "H1_EA_SMOKE_CONTEXT";
    fromRun.accountServer = "SMOKE_ONLY";
    fromRun.accountLogin = 1;
    fromRun.symbolName = "EURUSD";
    fromRun.magicNumber = "1201020501";
    fromRun.programVersion = "SMOKE";
    fromRun.strategyVersion = "SMOKE";
    fromRun.analysisVersion = "SMOKE";
    fromRun.analysisInputText = "SMOKE";
    fromRun.analysisInputHash = H1EaSql::hash(fromRun.analysisInputText);
    fromRun.configText = "ZIGZAG_SL_BUFFER_PIPS=10.0";
    fromRun.configHash = H1EaSql::hash(fromRun.configText);
}

/**
 * 波動NGで初回消費するSKIPを構成する。
 */
void prepareDecision(H1EaDecisionEntity &fromDecision, const long fromBar,
        const long fromReference) {
    fromDecision.contextKey = "H1_EA_SMOKE_CONTEXT";
    fromDecision.snapshotHash = H1EaSql::hash("SMOKE|" + IntegerToString(fromBar));
    fromDecision.h1BarTime = fromBar;
    fromDecision.evaluatedServerTime = fromBar + 1;
    fromDecision.createdAt = (long)TimeLocal();
    fromDecision.signalReferenceTime = fromReference;
    fromDecision.reasonCode = "H1_WAVE_REJECTED";
    fromDecision.signalSide = "BUY";
    fromDecision.isJudgeMatched = true;
    fromDecision.signalCount = 1;
    fromDecision.isEntryEvaluated = true;
    fromDecision.isSignalConsumed = true;
    fromDecision.maxInitialRiskPips = 200.0;
    fromDecision.h1DirectionAlignmentMode = "SMOKE";
    fromDecision.analysisSnapshotText = "SMOKE|" + IntegerToString(fromBar);
}

/**
 * pendingトレイルのまとまりを解除する。
 */
void clearPending(H1EaTradeEntity &fromTrade) {
    fromTrade.pendingStopLossKind = "";
    fromTrade.pendingStopLossH1BarTime = 0;
    fromTrade.pendingStopLoss = 0.0;
    fromTrade.pendingStopLossPivotTime = 0;
    fromTrade.pendingStopLossPivotRate = 0.0;
    fromTrade.pendingStopLossLatestTime = 0;
    fromTrade.pendingStopLossActionUid = "";
}

/**
 * Run・Decision・Trade・Eventの永続化境界を検証する。
 */
void verifyPersistence(H1EaPersistenceService &fromService) {
    H1EaRunEntity run;
    prepareRun(run, "SMOKE_RUN_1");
    verify(fromService.acquireRun(run) && run.id > 0, "acquire run");
    H1EaRunEntity duplicateRun;
    prepareRun(duplicateRun, "SMOKE_RUN_2");
    verify(!fromService.acquireRun(duplicateRun) && duplicateRun.id == 0, "active lease exclusive");
    verify(fromService.heartbeat(run, TimeLocal()), "heartbeat");

    H1EaDecisionEntity skip;
    prepareDecision(skip, 3600, 100);
    verify(fromService.saveDecision(run.id, skip), "consumed wave NG SKIP");
    long firstId = skip.id;
    verify(fromService.saveDecision(run.id, skip) && skip.id == firstId, "same snapshot idempotent");
    skip.snapshotHash = "OTHER";
    verify(!fromService.saveDecision(run.id, skip), "immutable snapshot");

    H1EaDecisionEntity duplicateSignal;
    prepareDecision(duplicateSignal, 7200, 100);
    verify(!fromService.saveDecision(run.id, duplicateSignal), "consumed signal unique");
    duplicateSignal.signalCount = 2;
    duplicateSignal.isEntryEvaluated = false;
    duplicateSignal.isSignalConsumed = false;
    duplicateSignal.reasonCode = "SIGNAL_ALREADY_CONSUMED";
    verify(fromService.saveDecision(run.id, duplicateSignal), "later Judge count stored");
    int count = 0;
    verify(fromService.loadSignalCount(run.contextKey, 100, "BUY", count) && count == 2,
        "Judge count restored without reset");

    H1EaDecisionEntity entry;
    prepareDecision(entry, 10800, 200);
    entry.decision = "BUY";
    entry.isStrategyEntry = true;
    entry.initialStopLoss = 1.1;
    H1EaTradeEntity trade;
    trade.contextKey = run.contextKey;
    trade.status = "OPEN_PENDING";
    trade.side = "BUY";
    trade.requestedVolume = 0.01;
    trade.requestedStopLoss = 1.1;
    trade.createdAt = (long)TimeLocal();
    trade.updatedAt = trade.createdAt;
    H1EaTradeEventEntity request;
    request.eventType = "ENTRY_REQUEST";
    request.recordedAt = (long)TimeLocal();
    request.eventUid = "INVALID";
    verify(!fromService.saveEntry(run.id, entry, trade, request)
        && entry.id == 0 && trade.id == 0 && request.id == 0, "entry rollback leaves no IDs");
    H1EaDecisionEntity loaded;
    bool found = true;
    verify(fromService.loadDecision(run.contextKey, entry.h1BarTime, loaded, found) && !found,
        "entry rollback leaves no Decision");
    request.actionUid = "H1_EA_ACTION_V1|SMOKE_RUN_1|{TRADE_ID}|ENTRY|1";
    verify(fromService.saveEntry(run.id, entry, trade, request)
        && StringFind(request.actionUid, "{TRADE_ID}") < 0, "atomic entry and action ID");
    verify(!fromService.saveEntry(run.id, entry, trade, request), "committed entry not resubmitted");

    H1EaTradeEntity current;
    verify(fromService.loadActiveTrade(run.contextKey, current, found) && found
        && current.id == trade.id, "active trade restored");
    string pendingRaw = "";
    verify(fromService.loadPendingRaw(trade.id, pendingRaw)
        && StringFind(pendingRaw, "|pending_stop_loss#9=null:NULL") >= 0,
        "quarantine keeps actual NULL type and value");
    trade.status = "OPEN";
    trade.positionIdentifier = "123";
    trade.positionTicket = "456";
    trade.openedAtMsc = 1000;
    trade.openedVolume = 0.01;
    trade.remainingEntryVolume = 0.0;
    trade.currentStopLoss = 1.1;
    trade.stopLossSource = "INITIAL_STOP_LOSS";
    H1EaTradeEntity partial = trade;
    partial.status = "OPEN_PARTIAL";
    partial.pendingStopLossKind = "INITIAL_RESTORE";
    partial.pendingStopLoss = partial.requestedStopLoss;
    H1EaTradeEventEntity initialRestore;
    initialRestore.eventUid = "SMOKE_PARTIAL_INITIAL_RESTORE";
    initialRestore.eventType = "RECOVERY";
    initialRestore.recordedAt = (long)TimeLocal();
    verify(fromService.saveTradeEvent(run.id, partial, initialRestore),
        "partial entry permits initial protection restore only");
    trade.lastTrailEvaluatedH1BarTime = 14400;
    trade.pendingStopLossKind = "TRAIL_CANDIDATE";
    trade.pendingStopLossH1BarTime = 14400;
    trade.pendingStopLoss = 1.2;
    trade.pendingStopLossPivotTime = 2000;
    trade.pendingStopLossPivotRate = 1.201;
    trade.pendingStopLossLatestTime = 3000;
    H1EaTradeEventEntity evaluation;
    evaluation.eventUid = "SMOKE_TRAIL_BAR";
    evaluation.eventType = "TRAIL_EVALUATION";
    evaluation.recordedAt = (long)TimeLocal();
    evaluation.h1BarTime = 14400;
    evaluation.stopLoss = 1.2;
    evaluation.pivotBarTime = 2000;
    evaluation.pivotRate = 1.201;
    evaluation.latestPointBarTime = 3000;
    verify(fromService.saveTradeEvent(run.id, trade, evaluation), "atomic pending trail evaluation");
    long eventSequence = evaluation.sequence;
    verify(fromService.saveTradeEvent(run.id, trade, evaluation)
        && evaluation.sequence == eventSequence, "trail event idempotent");

    H1EaTradeEventEntity modify;
    modify.eventUid = "SMOKE_MODIFY|REQUEST";
    modify.actionUid = "SMOKE_MODIFY";
    modify.eventType = "SL_MODIFY_REQUEST";
    modify.recordedAt = (long)TimeLocal();
    modify.positionIdentifier = trade.positionIdentifier;
    modify.positionTicket = trade.positionTicket;
    modify.h1BarTime = trade.pendingStopLossH1BarTime;
    modify.pivotBarTime = trade.pendingStopLossPivotTime;
    modify.pivotRate = trade.pendingStopLossPivotRate;
    modify.latestPointBarTime = trade.pendingStopLossLatestTime;
    modify.stopLoss = trade.pendingStopLoss;
    modify.stopLossActionKind = trade.pendingStopLossKind;
    trade.pendingStopLossActionUid = modify.actionUid;
    verify(fromService.saveTradeEvent(run.id, trade, modify), "atomic modify intent");
    H1EaTradeEventEntity result = modify;
    result.id = 0;
    result.eventUid = "SMOKE_MODIFY|RESULT";
    result.eventType = "SL_MODIFY_RESULT";
    verify(!fromService.saveTradeEvent(run.id, trade, result), "unavailable SL is not a Result");
    result.isConfirmedStopLossPresent = 1;
    result.confirmedStopLoss = 1.2;
    trade.currentStopLoss = 1.2;
    trade.stopLossSource = "H1_ZIGZAG_TRAIL";
    trade.lastAppliedTrailH1BarTime = trade.pendingStopLossH1BarTime;
    trade.lastAppliedTrailStopLoss = trade.pendingStopLoss;
    trade.lastAppliedTrailPivotTime = trade.pendingStopLossPivotTime;
    trade.lastAppliedTrailPivotRate = trade.pendingStopLossPivotRate;
    trade.lastAppliedTrailLatestTime = trade.pendingStopLossLatestTime;
    clearPending(trade);
    verify(fromService.saveTradeEvent(run.id, trade, result) && trade.status == "OPEN",
        "applied trail keeps position OPEN");

    H1EaTradeEventEntity closeEvent;
    closeEvent.eventUid = "SMOKE_CLOSE";
    closeEvent.eventType = "RECOVERY";
    closeEvent.recordedAt = (long)TimeLocal();
    trade.status = "CLOSED";
    verify(!fromService.saveTradeEvent(run.id, trade, closeEvent), "CLOSED needs broker evidence");
    trade.closedAtMsc = 200000;
    trade.closeReason = "H1_ZIGZAG_TRAIL";
    trade.brokerCloseReason = "SL";
    trade.remainingPositionVolume = 0.0;
    trade.profit = 0.0;
    trade.commission = 0.0;
    trade.swap = 0.0;
    trade.fee = 0.0;
    verify(fromService.saveTradeEvent(run.id, trade, closeEvent), "closed financial snapshot");
    verify(fromService.loadActiveTrade(run.contextKey, current, found) && !found, "closed releases active slot");

    H1EaTradeEntity recovered;
    recovered.contextKey = run.contextKey;
    recovered.origin = "RECOVERED";
    recovered.status = "RECOVERY_REQUIRED";
    recovered.side = "SELL";
    recovered.positionIdentifier = "789";
    recovered.createdAt = (long)TimeLocal();
    recovered.updatedAt = recovered.createdAt;
    H1EaTradeEventEntity recovery;
    recovery.eventType = "RECOVERY";
    recovery.recordedAt = (long)TimeLocal();
    string snapshot = "H1_EA_RECOVERY_SNAPSHOT_V1|trade_id#1=0|status#17=RECOVERY_REQUIRED";
    recovery.eventUid = "H1_EA_RECOVERY_V1|" + run.contextKey + "|0|" + H1EaSql::hash(snapshot);
    recovery.message = snapshot;
    verify(fromService.saveTradeEvent(run.id, recovered, recovery, false) && recovered.id > 0
        && StringFind(recovery.message, "|trade_id#1=0|") < 0,
        "recovered ID embedded before canonical hash");
    string expectedUid = "H1_EA_RECOVERY_V1|" + run.contextKey + "|" + IntegerToString(recovered.id)
        + "|" + H1EaSql::hash(recovery.message);
    verify(recovery.eventUid == expectedUid, "recovery hash includes allocated ID");
    verify(fromService.finishRun(run.id, "STOPPED", ""), "normal Run stop");
    verify(fromService.acquireRun(duplicateRun), "new Run inherits context");
    H1EaTradeEventEntity oldAudit;
    oldAudit.eventUid = "SMOKE_OLD_RUN_AUDIT";
    oldAudit.eventType = "ERROR";
    oldAudit.recordedAt = (long)TimeLocal();
    verify(!fromService.saveTradeEvent(run.id, trade, oldAudit, false)
        && fromService.getLastError() == "SNAPSHOT_OWNER_SUPERSEDED",
        "old Run cannot rewind newer owner snapshot");
    verify(fromService.loadSignalCount(run.contextKey, 100, "BUY", count) && count == 2,
        "restart retains consumed SKIP");
    verify(H1EaSql::execute(fromService.getHandle(),
        "UPDATE h1_ea_runs SET heartbeat_at=1,lease_expires_at=1 WHERE id="
        + IntegerToString(duplicateRun.id)), "simulate own expired lease");
    oldAudit.eventUid = "SMOKE_EXPIRED_OWN_AUDIT";
    verify(fromService.saveTradeEvent(duplicateRun.id, trade, oldAudit, false),
        "own expired Run may retain broker audit without send authority");
    verify(fromService.finishRun(duplicateRun.id, "STOPPED", ""), "second Run stop");
}

/**
 * H1 EA専用SQLite契約のスモークテスト。
 */
void OnStart() {
    string fileName = "mstng-h1-ea-smoke-" + IntegerToString((long)TimeLocal())
        + "-" + IntegerToString((long)GetTickCount64()) + ".sqlite";
    if (FileIsExist(fileName, FILE_COMMON)) {
        Print("ERROR H1EaDatabaseSmokeTest temporary file already exists: ", fileName);
        return;
    }
    H1EaPersistenceService service;
    bool opened = service.open(fileName);
    verify(opened, "schema and PRAGMA setup");
    if (opened) {
        verifyPersistence(service);
        service.close();
        verify(service.open(fileName, false), "reconnect verifies schema without DDL");
        service.close();
        SqliteDatabase readOnly(fileName, true);
        verify(readOnly.openReadOnly(), "read-only connection");
        readOnly.close();
    }
    service.close();
    // この実行で新規作成した一意名のスモークDBだけを削除する。
    if (FileIsExist(fileName, FILE_COMMON)) {
        FileDelete(fileName, FILE_COMMON);
    }
    if (FileIsExist(fileName + "-wal", FILE_COMMON)) {
        FileDelete(fileName + "-wal", FILE_COMMON);
    }
    if (FileIsExist(fileName + "-shm", FILE_COMMON)) {
        FileDelete(fileName + "-shm", FILE_COMMON);
    }
    Print("INFO H1EaDatabaseSmokeTest completed passed=", passedCount, " failed=", failedCount);
}
