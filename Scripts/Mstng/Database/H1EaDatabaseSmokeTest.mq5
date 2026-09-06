#property version "1.00"

#include <Mstng\Database\Dao\H1EaDecisionDao.mqh>
#include <Mstng\Database\Dao\H1EaRunDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeEventDao.mqh>
#include <Mstng\Database\Service\H1EaPersistenceService.mqh>
#include <MstngH1Ea\Runtime\H1EaDecisionBuilder.mqh>

/** 検証成功件数。 */
int passedCount = 0;
/** 検証失敗件数。 */
int failedCount = 0;
/** 移行時に新モードへ置き換えてはいけない旧Run設定。 */
const string legacyEmaModeConfigText = "ZIGZAG_SL_BUFFER_PIPS=10.0"
    "|H1_EMA200_CONFIRMATION_MODE=H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED";

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
 * 診断値の保存・再読込・再sealでcanonicalとhashが変わらないことを確認する。
 */
void verifyDecisionRoundTrip(H1EaPersistenceService &fromService, const long fromRunId,
        H1EaDecisionEntity &fromDecision, const string fromName) {
    verify(H1EaDecisionBuilder::seal(fromDecision, 5), fromName + " seal");
    string expectedText = fromDecision.analysisSnapshotText;
    string expectedHash = fromDecision.snapshotHash;
    verify(H1EaDecisionBuilder::seal(fromDecision, 5)
        && fromDecision.analysisSnapshotText == expectedText
        && fromDecision.snapshotHash == expectedHash, fromName + " repeated seal stable");
    if (!fromService.saveDecision(fromRunId, fromDecision)) {
        verify(false, fromName + " save");
        return;
    }
    H1EaDecisionEntity loaded;
    bool found = false;
    bool success = fromService.loadDecision(fromDecision.contextKey, fromDecision.h1BarTime, loaded, found);
    verify(success && found && loaded.d1Ema200Direction == fromDecision.d1Ema200Direction
        && loaded.isEma200ConfirmationPassed == fromDecision.isEma200ConfirmationPassed
        && loaded.hasEma200ConfirmationDiagnostics == fromDecision.hasEma200ConfirmationDiagnostics
        && loaded.analysisSnapshotText == expectedText && loaded.snapshotHash == expectedHash,
        fromName + " DAO restores optional diagnostics");
    if (success && found) {
        long dedicatedMatches = 0;
        verify(H1EaSql::scalar(fromService.getHandle(),
            "SELECT COUNT(*) FROM h1_ea_decisions WHERE id=" + IntegerToString(loaded.id)
            + " AND d1_ema200_direction IS " + H1EaSql::optionalText(fromDecision.d1Ema200Direction),
            dedicatedMatches) && dedicatedMatches == 1,
            fromName + " dedicated column preserves NULL and direction");
        verify(H1EaDecisionBuilder::seal(loaded, 5)
            && loaded.analysisSnapshotText == expectedText && loaded.snapshotHash == expectedHash,
            fromName + " DAO roundtrip seal stable");
    }
}

/**
 * 保存値を変更せず専用列だけを差し替え、textとの不一致をDAOが拒否することを確認する。
 */
void verifyMismatchedDecisionColumn(H1EaPersistenceService &fromService,
        const long fromDecisionId, const string fromColumnSql, const string fromName) {
    string columns = H1EaDecisionDao::selectColumns();
    verify(StringReplace(columns, "COALESCE(d1_ema200_direction,'')", fromColumnSql) == 1,
        fromName + " dedicated SELECT fixture");
    int request = DatabasePrepare(fromService.getHandle(), "SELECT " + columns
        + " FROM h1_ea_decisions WHERE id=" + IntegerToString(fromDecisionId));
    if (request == INVALID_HANDLE) {
        verify(false, fromName + " SELECT prepared");
        return;
    }
    H1EaDecisionEntity loaded;
    verify(DatabaseRead(request) && !H1EaDecisionDao::read(request, loaded),
        fromName + " column text mismatch rejected");
    DatabaseFinalize(request);
}

/**
 * 保存行を書き換えずSELECTの診断テキストだけを差し替えてDAOの拒否動作を確認する。
 */
void verifyInvalidDecisionDiagnostic(H1EaPersistenceService &fromService, const long fromDecisionId,
        const string fromText, const string fromName) {
    string columns = H1EaDecisionDao::selectColumns();
    StringReplace(columns, "analysis_snapshot_text", H1EaSql::text(fromText));
    int request = DatabasePrepare(fromService.getHandle(), "SELECT " + columns
        + " FROM h1_ea_decisions WHERE id=" + IntegerToString(fromDecisionId));
    if (request == INVALID_HANDLE) {
        verify(false, fromName + " fixture select");
        return;
    }
    H1EaDecisionEntity loaded;
    loaded.d1Ema200Direction = "BUY";
    loaded.isEma200ConfirmationPassed = true;
    loaded.hasEma200ConfirmationDiagnostics = true;
    bool selected = DatabaseRead(request);
    bool success = false;
    if (selected) {
        success = H1EaDecisionDao::read(request, loaded);
    }
    DatabaseFinalize(request);
    verify(selected && !success && loaded.d1Ema200Direction == ""
        && !loaded.isEma200ConfirmationPassed && !loaded.hasEma200ConfirmationDiagnostics,
        fromName + " rejected without fabricated diagnostics");
}

/**
 * 旧形式の未取得と新形式のNONE・falseを区別し、D1診断をhash対象として検証する。
 */
void verifyDecisionDiagnostics(H1EaPersistenceService &fromService, const long fromRunId) {
    H1EaDecisionEntity legacy;
    prepareDecision(legacy, 36000, 1000);
    verifyDecisionRoundTrip(fromService, fromRunId, legacy, "legacy diagnostic absent");
    verify(StringFind(legacy.analysisSnapshotText, "|d1_ema200_direction=") < 0
        && StringFind(legacy.analysisSnapshotText, "|is_ema200_confirmation_passed=") < 0,
        "legacy canonical has no new keys");

    H1EaDecisionEntity matched;
    prepareDecision(matched, 39600, 1100);
    matched.d1Ema200Direction = "BUY";
    matched.isEma200ConfirmationPassed = true;
    matched.hasEma200ConfirmationDiagnostics = true;
    verifyDecisionRoundTrip(fromService, fromRunId, matched, "EMA200 BUY matched");
    verify(matched.snapshotHash != legacy.snapshotHash,
        "additional diagnostics change otherwise identical snapshot hash");
    H1EaDecisionEntity changed = matched;
    changed.d1Ema200Direction = "SELL";
    verify(H1EaDecisionBuilder::seal(changed, 5) && changed.snapshotHash != matched.snapshotHash,
        "D1 direction is included in snapshot hash");
    changed = matched;
    changed.isEma200ConfirmationPassed = false;
    verify(H1EaDecisionBuilder::seal(changed, 5) && changed.snapshotHash != matched.snapshotHash,
        "EMA200 boolean is included in snapshot hash");

    H1EaDecisionEntity rejected;
    prepareDecision(rejected, 43200, 1200);
    rejected.d1Ema200Direction = "SELL";
    rejected.hasEma200ConfirmationDiagnostics = true;
    verifyDecisionRoundTrip(fromService, fromRunId, rejected, "EMA200 SELL rejected");
    verify(rejected.isEma200ConfirmationPassed == false && rejected.hasEma200ConfirmationDiagnostics,
        "evaluated false differs from legacy unavailable");

    H1EaDecisionEntity none;
    prepareDecision(none, 46800, 1300);
    none.d1Ema200Direction = "NONE";
    none.hasEma200ConfirmationDiagnostics = true;
    verifyDecisionRoundTrip(fromService, fromRunId, none, "EMA200 NONE evaluated");
    H1EaDecisionEntity unavailable;
    prepareDecision(unavailable, 50400, 1400);
    unavailable.hasEma200ConfirmationDiagnostics = true;
    verifyDecisionRoundTrip(fromService, fromRunId, unavailable, "EMA200 direction unavailable");
    verify(StringFind(unavailable.analysisSnapshotText, "|d1_ema200_direction=~|") >= 0
        && none.snapshotHash != unavailable.snapshotHash, "NULL direction differs from NONE");

    string prefix = legacy.analysisSnapshotText;
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|d1_ema200_direction=BUY", "missing boolean");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|is_ema200_confirmation_passed=0", "missing direction");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|d1_ema200_direction=BUY|is_ema200_confirmation_passed=2", "invalid boolean");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|d1_ema200_direction=NULL|is_ema200_confirmation_passed=0", "invalid NULL spelling");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|d1_ema200_direction=|is_ema200_confirmation_passed=0", "empty encoded direction");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        matched.analysisSnapshotText + "|d1_ema200_direction=SELL", "duplicate direction");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        matched.analysisSnapshotText + "|is_ema200_confirmation_passed=0", "duplicate boolean");
    verifyInvalidDecisionDiagnostic(fromService, legacy.id,
        prefix + "|d1_ema200_direction_extra=BUY|is_ema200_confirmation_passed=0", "exact direction key required");
    verifyMismatchedDecisionColumn(fromService, matched.id, "'SELL'", "BUY text SELL column");
    verifyMismatchedDecisionColumn(fromService, matched.id, "''", "BUY text NULL column");
    verifyMismatchedDecisionColumn(fromService, legacy.id, "'BUY'", "legacy text BUY column");
    verifyMismatchedDecisionColumn(fromService, none.id, "''", "NONE text NULL column");
    H1EaDecisionEntity duplicateMismatch = matched;
    duplicateMismatch.d1Ema200Direction = "SELL";
    verify(!fromService.saveDecision(fromRunId, duplicateMismatch),
        "same hash and text cannot hide different dedicated column");
    H1EaDecisionEntity original;
    bool originalFound = false;
    verify(fromService.loadDecision(matched.contextKey, matched.h1BarTime, original, originalFound)
        && originalFound && original.d1Ema200Direction == "BUY"
        && original.snapshotHash == matched.snapshotHash
        && original.analysisSnapshotText == matched.analysisSnapshotText,
        "mismatched idempotent save preserves original row");
    H1EaDecisionEntity inconsistent;
    prepareDecision(inconsistent, 54000, 1500);
    inconsistent.d1Ema200Direction = "BUY";
    inconsistent.hasEma200ConfirmationDiagnostics = true;
    verify(H1EaDecisionBuilder::seal(inconsistent, 5), "mismatch insert fixture seal");
    inconsistent.d1Ema200Direction = "SELL";
    verify(!fromService.saveDecision(fromRunId, inconsistent) && inconsistent.id == 0,
        "column text mismatch cannot insert or allocate ID");
    long inserted = -1;
    verify(H1EaSql::scalar(fromService.getHandle(),
        "SELECT COUNT(*) FROM h1_ea_decisions WHERE h1_bar_time=54000", inserted)
        && inserted == 0, "column text mismatch leaves no row");
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
    verifyDecisionDiagnostics(fromService, run.id);

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
 * この実行で新規作成できる一意名だけを返す。既存のDB・sidecarには触れない。
 */
string newSmokeFileName(const string fromPurpose) {
    string fileName = "mstng-h1-ea-smoke-" + IntegerToString((long)TimeLocal())
        + "-" + IntegerToString((long)GetTickCount64()) + "-" + fromPurpose + ".sqlite";
    if (FileIsExist(fileName, FILE_COMMON) || FileIsExist(fileName + "-wal", FILE_COMMON)
            || FileIsExist(fileName + "-shm", FILE_COMMON)) {
        verify(false, "temporary file or sidecar already exists: " + fileName);
        return "";
    }
    return fileName;
}

/**
 * 全接続を閉じた後、この実行が新規作成した専用DBだけを除去する。
 */
void cleanupSmokeFile(const string fromFileName) {
    if (fromFileName == "") {
        return;
    }
    string suffixes[] = {"", "-wal", "-shm"};
    for (int i = 0; i < ArraySize(suffixes); i++) {
        string target = fromFileName + suffixes[i];
        if (FileIsExist(target, FILE_COMMON)) {
            verify(FileDelete(target, FILE_COMMON), "remove owned smoke file " + target);
        }
    }
}

/**
 * 公開された旧CREATEで専用fixtureを作り、実運用DBを使わず移行元を再現する。
 */
bool prepareLegacyFixture(const string fromFileName, const string fromKind,
        H1EaDecisionEntity &fromExpected[]) {
    SqliteDatabase database(fromFileName, true);
    if (!database.open()) {
        return false;
    }
    int handle = database.getHandle();
    bool success = H1EaRunDao::createTable(handle)
        && H1EaSql::execute(handle, H1EaDecisionDao::createLegacySql())
        && H1EaDecisionDao::createTable(handle)
        && H1EaTradeDao::createTable(handle)
        && H1EaTradeEventDao::createTable(handle)
        && H1EaSql::execute(handle, "PRAGMA user_version=1");
    H1EaRunEntity run;
    prepareRun(run, "LEGACY_D1_" + fromKind);
    run.configText = legacyEmaModeConfigText;
    run.configHash = H1EaSql::hash(run.configText);
    run.startedAt = (long)TimeLocal();
    run.heartbeatAt = run.startedAt;
    run.leaseExpiresAt = run.startedAt + 3600;
    run.status = "STOPPED";
    if (fromKind == "ACTIVE" || fromKind == "EXPIRED") {
        run.status = "RUNNING";
    }
    if (fromKind == "EXPIRED") {
        run.heartbeatAt = 1;
        run.leaseExpiresAt = 1;
    }
    if (success) {
        success = H1EaRunDao::insert(handle, run);
    }
    int fixtureCount = 5;
    if (fromKind == "BATCH" || fromKind == "BATCH_INVALID") {
        fixtureCount = 133;
    }
    if (success) {
        success = ArrayResize(fromExpected, fixtureCount) == fixtureCount;
    }
    string directions[] = {"", "BUY", "SELL", "NONE", ""};
    for (int i = 0; success && i < ArraySize(fromExpected); i++) {
        fromExpected[i].reset();
        prepareDecision(fromExpected[i], 3600 * (i + 1), 100 + i);
        fromExpected[i].runId = run.id;
        fromExpected[i].d1Ema200Direction = directions[i % ArraySize(directions)];
        fromExpected[i].hasEma200ConfirmationDiagnostics = i > 0;
        fromExpected[i].isEma200ConfirmationPassed = i % ArraySize(directions) == 1;
        success = H1EaDecisionBuilder::seal(fromExpected[i], 5);
        if (i == fixtureCount - 1 && fromKind == "DUPLICATE") {
            fromExpected[i].analysisSnapshotText += "|d1_ema200_direction=BUY";
        } else if (i == fixtureCount - 1 && (fromKind == "INVALID" || fromKind == "BATCH_INVALID")) {
            StringReplace(fromExpected[i].analysisSnapshotText,
                "|is_ema200_confirmation_passed=0", "|is_ema200_confirmation_passed=2");
        } else if (i == fixtureCount - 1 && fromKind == "MISSING") {
            StringReplace(fromExpected[i].analysisSnapshotText,
                "|is_ema200_confirmation_passed=0", "");
        }
        string columns = H1EaDecisionDao::columns();
        success = success && StringReplace(columns, ",d1_ema200_direction", "") == 1;
        string values = H1EaDecisionDao::values(fromExpected[i]);
        string suffix = "," + H1EaSql::optionalText(fromExpected[i].d1Ema200Direction);
        values = StringSubstr(values, 0, StringLen(values) - StringLen(suffix));
        success = success && H1EaSql::execute(handle,
            "INSERT INTO h1_ea_decisions (" + columns + ") VALUES (" + values + ")")
            && H1EaSql::scalar(handle, "SELECT last_insert_rowid()", fromExpected[i].id);
    }
    if (success && fromKind == "SCHEMA") {
        success = H1EaSql::execute(handle, "DROP INDEX idx_h1_ea_decisions_reason_bar");
    }
    if (success && fromKind == "TRIGGER") {
        success = H1EaSql::execute(handle,
            "CREATE TRIGGER smoke_d1_update AFTER UPDATE ON H1_EA_DECISIONS BEGIN SELECT 1; END;");
    }
    database.close();
    return success;
}

/**
 * 失敗した移行がschema、既存値、snapshot hashを変更していないことを確認する。
 */
void verifyLegacyUnchanged(const string fromFileName,
        H1EaDecisionEntity &fromExpected[], const string fromName) {
    SqliteDatabase database(fromFileName, true);
    if (!database.openReadOnly()) {
        verify(false, fromName + " read-only audit");
        return;
    }
    int handle = database.getHandle();
    long value = -1;
    verify(H1EaSql::scalar(handle, "PRAGMA user_version", value) && value == 1,
        fromName + " version remains 1");
    verify(H1EaSql::scalar(handle, "SELECT COUNT(*) FROM pragma_table_info('h1_ea_decisions')", value)
        && value == 41, fromName + " ALTER rolled back to 41 columns");
    verify(H1EaSql::scalar(handle, "SELECT COUNT(*) FROM h1_ea_decisions", value)
        && value == ArraySize(fromExpected), fromName + " all old rows remain");
    for (int i = 0; i < ArraySize(fromExpected); i++) {
        verify(H1EaSql::scalar(handle, "SELECT COUNT(*) FROM h1_ea_decisions WHERE id="
            + IntegerToString(fromExpected[i].id) + " AND snapshot_hash="
            + H1EaSql::text(fromExpected[i].snapshotHash) + " AND analysis_snapshot_text="
            + H1EaSql::text(fromExpected[i].analysisSnapshotText), value) && value == 1,
            fromName + " unchanged text and hash " + IntegerToString(i));
    }
    database.close();
}

/**
 * 初回接続だけの実移行と、再接続・異常schema・更新失敗の安全境界を確認する。
 */
void verifyLegacyMigration(const string fromKind, const bool fromExpectedSuccess) {
    string fileName = newSmokeFileName("migration-" + fromKind);
    if (fileName == "") {
        return;
    }
    H1EaDecisionEntity expected[];
    bool prepared = prepareLegacyFixture(fileName, fromKind, expected);
    verify(prepared, fromKind + " legacy fixture");
    if (!prepared) {
        cleanupSmokeFile(fileName);
        return;
    }
    H1EaPersistenceService service;
    verify(!service.open(fileName, false), fromKind + " reconnect cannot migrate v1");
    service.close();
    verifyLegacyUnchanged(fileName, expected, fromKind + " reconnect");
    bool opened = service.open(fileName);
    verify(opened == fromExpectedSuccess, fromKind + " initialization migration result");
    if (opened) {
        long value = -1;
        verify(H1EaSql::scalar(service.getHandle(), "PRAGMA user_version", value) && value == 2,
            fromKind + " physical schema version 2");
        verify(H1EaSql::scalar(service.getHandle(), "SELECT COUNT(*) FROM h1_ea_runs WHERE schema_version=1", value)
            && value == 1, fromKind + " original Run schema version preserved");
        verify(H1EaSql::scalar(service.getHandle(),
            "SELECT COUNT(*) FROM h1_ea_runs WHERE config_text=" + H1EaSql::text(legacyEmaModeConfigText)
            + " AND config_hash=" + H1EaSql::text(H1EaSql::hash(legacyEmaModeConfigText)), value)
            && value == 1, fromKind + " legacy EMA mode and config hash unchanged");
        for (int i = 0; i < ArraySize(expected); i++) {
            H1EaDecisionEntity loaded;
            bool found = false;
            verify(service.loadDecision(expected[i].contextKey, expected[i].h1BarTime, loaded, found)
                && found && loaded.id == expected[i].id
                && loaded.d1Ema200Direction == expected[i].d1Ema200Direction
                && loaded.hasEma200ConfirmationDiagnostics == expected[i].hasEma200ConfirmationDiagnostics
                && loaded.isEma200ConfirmationPassed == expected[i].isEma200ConfirmationPassed
                && loaded.analysisSnapshotText == expected[i].analysisSnapshotText
                && loaded.snapshotHash == expected[i].snapshotHash,
                fromKind + " backfill without recalculation " + IntegerToString(i));
        }
        long schemaCookie = -1;
        verify(H1EaSql::scalar(service.getHandle(), "PRAGMA schema_version", schemaCookie),
            fromKind + " migrated schema cookie");
        service.close();
        verify(service.open(fileName), fromKind + " v2 initialization idempotent");
        verify(H1EaSql::scalar(service.getHandle(), "PRAGMA schema_version", value) && value == schemaCookie,
            fromKind + " v2 initialization no DDL");
        service.close();
        verify(service.open(fileName, false), fromKind + " v2 reconnect");
        verify(H1EaSql::scalar(service.getHandle(), "PRAGMA schema_version", value) && value == schemaCookie,
            fromKind + " v2 reconnect no DDL");
    }
    service.close();
    if (!opened) {
        verifyLegacyUnchanged(fileName, expected, fromKind + " failed migration");
    }
    cleanupSmokeFile(fileName);
}

/**
 * H1 EA専用SQLite契約のスモークテスト。
 */
void OnStart() {
    string fileName = newSmokeFileName("current");
    if (fileName == "") {
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
    cleanupSmokeFile(fileName);
    verifyLegacyMigration("VALID", true);
    verifyLegacyMigration("BATCH", true);
    verifyLegacyMigration("EXPIRED", true);
    verifyLegacyMigration("ACTIVE", false);
    verifyLegacyMigration("TRIGGER", false);
    verifyLegacyMigration("SCHEMA", false);
    verifyLegacyMigration("DUPLICATE", false);
    verifyLegacyMigration("INVALID", false);
    verifyLegacyMigration("BATCH_INVALID", false);
    verifyLegacyMigration("MISSING", false);
    Print("INFO H1EaDatabaseSmokeTest completed passed=", passedCount, " failed=", failedCount);
}
