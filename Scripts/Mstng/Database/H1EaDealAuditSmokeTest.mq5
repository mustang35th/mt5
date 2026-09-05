#property strict
#property version "1.00"

#include <Mstng\Database\Dao\H1EaRunDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeDao.mqh>
#include <Mstng\Database\Service\H1EaPersistenceService.mqh>

/** 検証成功件数。 */
int passedCount = 0;
/** 検証失敗件数。 */
int failedCount = 0;

/**
 * broker APIを使用しない監査保存の検証結果を記録する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        passedCount++;
        Print("INFO H1EaDealAuditSmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR H1EaDealAuditSmokeTest FAIL ", fromName);
    }
}

/**
 * 運用口座を参照しない専用Runを構成する。
 */
void prepareRun(H1EaRunEntity &fromRun, const string fromUid) {
    fromRun.runUid = fromUid;
    fromRun.sourceMode = "TESTER";
    fromRun.contextKey = "H1_EA_DEAL_AUDIT_SMOKE|" + fromUid;
    fromRun.accountServer = "SMOKE_ONLY";
    fromRun.accountLogin = 1;
    fromRun.symbolName = "EURUSD";
    fromRun.magicNumber = "1201020501";
    fromRun.programVersion = "SMOKE";
    fromRun.strategyVersion = "SMOKE";
    fromRun.analysisVersion = "SMOKE";
    fromRun.analysisInputText = "H1_EA_DEAL_AUDIT_SMOKE";
    fromRun.analysisInputHash = H1EaSql::hash(fromRun.analysisInputText);
    fromRun.configText = "H1_EA_DEAL_AUDIT_SMOKE|NO_BROKER_API=1";
    fromRun.configHash = H1EaSql::hash(fromRun.configText);
}

/**
 * CLOSED fixtureの全状態を用意する。実際の約定履歴は参照しない。
 */
void prepareTrade(H1EaTradeEntity &fromTrade, const H1EaRunEntity &fromRun,
        const string fromPosition) {
    fromTrade.createdRunId = fromRun.id;
    fromTrade.contextKey = fromRun.contextKey;
    fromTrade.origin = "RECOVERED";
    fromTrade.status = "CLOSED";
    fromTrade.side = "BUY";
    fromTrade.positionIdentifier = fromPosition;
    fromTrade.positionTicket = fromPosition;
    fromTrade.entryDealTicket = "1001";
    fromTrade.exitDealTicket = "1002";
    fromTrade.openedAtMsc = 2000000;
    fromTrade.closedAtMsc = 4000000;
    fromTrade.openPrice = 1.1;
    fromTrade.closePrice = 1.11;
    fromTrade.openedVolume = 0.01;
    fromTrade.remainingPositionVolume = 0.0;
    fromTrade.currentStopLoss = 1.11;
    fromTrade.stopLossSource = "H1_ZIGZAG_TRAIL";
    fromTrade.closeReason = "H1_ZIGZAG_TRAIL";
    fromTrade.brokerCloseReason = "SL";
    fromTrade.profit = 15.0;
    fromTrade.commission = -1.0;
    fromTrade.swap = -2.0;
    fromTrade.fee = 0.0;
    fromTrade.lastError = "DEAL_EVENTS_PENDING";
    fromTrade.createdAt = (long)TimeLocal();
    fromTrade.updatedAt = fromTrade.createdAt;
}

/**
 * 再取得した想定のdeal Eventを専用Runのscopeで構成する。
 */
void prepareDeal(H1EaTradeEventEntity &fromEvent, const H1EaRunEntity &fromRun,
        const H1EaTradeEntity &fromTrade, const bool fromExit) {
    fromEvent.reset();
    fromEvent.tradeId = fromTrade.id;
    fromEvent.eventType = "DEAL_ADD";
    fromEvent.eventSource = "RECONCILIATION";
    fromEvent.recordedAt = (long)TimeLocal();
    fromEvent.transactionType = TRADE_TRANSACTION_DEAL_ADD;
    fromEvent.positionIdentifier = fromTrade.positionIdentifier;
    fromEvent.positionTicket = fromTrade.positionTicket;
    fromEvent.volume = 0.01;
    fromEvent.dealTicket = fromTrade.entryDealTicket;
    fromEvent.brokerTimeMsc = fromTrade.openedAtMsc;
    fromEvent.side = "BUY";
    fromEvent.price = fromTrade.openPrice;
    fromEvent.brokerReason = "EXPERT";
    fromEvent.message = "DEAL_ENTRY_IN";
    if (fromExit) {
        fromEvent.dealTicket = fromTrade.exitDealTicket;
        fromEvent.brokerTimeMsc = fromTrade.closedAtMsc;
        fromEvent.side = "SELL";
        fromEvent.price = fromTrade.closePrice;
        fromEvent.closeReason = fromTrade.closeReason;
        fromEvent.brokerReason = fromTrade.brokerCloseReason;
        fromEvent.message = "DEAL_ENTRY_OUT";
    }
    fromEvent.serverTime = fromEvent.brokerTimeMsc / 1000;
    fromEvent.dealScopeKey = "TESTER|" + fromRun.runUid + "|" + fromEvent.dealTicket;
    fromEvent.eventUid = fromEvent.dealScopeKey;
}

/**
 * DBから再読込した全列を比較し、監査追記による状態巻き戻しを検出する。
 */
bool hasSnapshot(H1EaPersistenceService &fromService, const H1EaTradeEntity &fromExpected) {
    H1EaTradeEntity loaded;
    bool found = false;
    return H1EaTradeDao::load(fromService.getHandle(), "id=" + IntegerToString(fromExpected.id),
        loaded, found) && found && loaded.id == fromExpected.id
        && H1EaTradeDao::values(loaded) == H1EaTradeDao::values(fromExpected);
}

/**
 * 対象TradeのEvent数を確認する。
 */
bool hasEventCount(H1EaPersistenceService &fromService, const long fromTradeId,
        const long fromExpected) {
    long count = -1;
    return H1EaSql::scalar(fromService.getHandle(),
        "SELECT COUNT(*) FROM h1_ea_trade_events WHERE trade_id=" + IntegerToString(fromTradeId),
        count) && count == fromExpected;
}

/**
 * 空ticketと片側欠落の列挙条件、カーソルを確認する。
 */
void verifyCandidateSelection(H1EaPersistenceService &fromService, const H1EaRunEntity &fromRun) {
    H1EaTradeEntity empty;
    prepareTrade(empty, fromRun, "701");
    empty.entryDealTicket = "";
    empty.exitDealTicket = "";
    empty.lastError = "";
    verify(H1EaTradeDao::insert(fromService.getHandle(), empty), "insert NULL ticket fixture");
    H1EaTradeEntity entryMissing;
    prepareTrade(entryMissing, fromRun, "702");
    entryMissing.entryDealTicket = "2001";
    entryMissing.exitDealTicket = "";
    entryMissing.lastError = "";
    verify(H1EaTradeDao::insert(fromService.getHandle(), entryMissing), "insert missing entry fixture");
    H1EaTradeEntity exitMissing;
    prepareTrade(exitMissing, fromRun, "703");
    exitMissing.entryDealTicket = "";
    exitMissing.exitDealTicket = "2002";
    exitMissing.lastError = "";
    verify(H1EaTradeDao::insert(fromService.getHandle(), exitMissing), "insert missing exit fixture");
    H1EaTradeEntity candidate;
    bool found = false;
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found)
        && found && candidate.id == entryMissing.id, "NULL tickets excluded and entry missing selected");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, candidate.id, candidate, found)
        && found && candidate.id == exitMissing.id, "cursor selects next exit missing trade");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, exitMissing.id, candidate, found)
        && !found, "cursor exhaustion is not a read error");
}

/**
 * 別context、対象外ID、active枠および誤ったEventを拒否することを確認する。
 */
void verifyBoundaries(H1EaPersistenceService &fromService, const H1EaRunEntity &fromRun,
        const H1EaTradeEntity &fromTrade) {
    H1EaRunEntity otherRun;
    prepareRun(otherRun, H1EaSql::hash(fromRun.runUid + "|OTHER_CONTEXT"));
    bool acquired = fromService.acquireRun(otherRun);
    verify(acquired, "acquire isolated other context run");
    if (!acquired) {
        return;
    }
    H1EaTradeEventEntity event;
    prepareDeal(event, fromRun, fromTrade, true);
    verify(!fromService.appendClosedDealEvent(otherRun.id, fromTrade.id, event)
        && !fromService.completeClosedDealAudit(otherRun.id, fromTrade.id), "other context rejected");
    event.tradeId = 999999;
    verify(!fromService.appendClosedDealEvent(fromRun.id, 999999, event)
        && !fromService.completeClosedDealAudit(fromRun.id, 999999), "unknown trade ID rejected");
    prepareDeal(event, fromRun, fromTrade, true);
    event.positionIdentifier = "WRONG_POSITION";
    verify(!fromService.appendClosedDealEvent(fromRun.id, fromTrade.id, event), "wrong position rejected");
    prepareDeal(event, fromRun, fromTrade, true);
    event.eventType = "ENTRY_REQUEST";
    verify(!fromService.appendClosedDealEvent(fromRun.id, fromTrade.id, event), "request Event rejected");
    prepareDeal(event, otherRun, fromTrade, true);
    verify(!fromService.appendClosedDealEvent(fromRun.id, fromTrade.id, event), "foreign Tester deal scope rejected");

    H1EaTradeEntity active;
    prepareTrade(active, fromRun, "601");
    active.status = "OPEN";
    active.entryDealTicket = "3001";
    active.exitDealTicket = "3002";
    active.closedAtMsc = 0;
    active.closeReason = "";
    active.brokerCloseReason = "";
    active.remainingPositionVolume = 0.01;
    active.lastError = "";
    verify(H1EaTradeDao::insert(fromService.getHandle(), active), "insert independent active fixture");
    prepareDeal(event, fromRun, active, false);
    verify(!fromService.appendClosedDealEvent(fromRun.id, active.id, event)
        && !fromService.completeClosedDealAudit(fromRun.id, active.id), "active trade rejected");
    prepareDeal(event, fromRun, fromTrade, true);
    verify(fromService.appendClosedDealEvent(fromRun.id, fromTrade.id, event)
        && hasSnapshot(fromService, active) && hasSnapshot(fromService, fromTrade),
        "past duplicate leaves active and closed snapshots unchanged");
    verify(hasEventCount(fromService, fromTrade.id, 2) && hasEventCount(fromService, active.id, 0),
        "rejected operations leave event counts unchanged");
    verify(fromService.finishRun(otherRun.id, "STOPPED", ""), "finish other context run");
}

/**
 * 三つの公開API、原子的失敗、再試行、専用marker解除を検証する。
 */
void verifyAudit(H1EaPersistenceService &fromService, const H1EaRunEntity &fromRun) {
    H1EaTradeEntity trade;
    prepareTrade(trade, fromRun, "501");
    bool inserted = H1EaTradeDao::insert(fromService.getHandle(), trade);
    verify(inserted, "insert closed synthetic trade");
    if (!inserted) {
        return;
    }
    H1EaTradeEntity candidate;
    bool found = false;
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found)
        && found && candidate.id == trade.id, "closed audit candidate restored");
    H1EaTradeEventEntity entry;
    prepareDeal(entry, fromRun, trade, false);
    verify(fromService.appendClosedDealEvent(fromRun.id, trade.id, entry)
        && entry.id > 0 && entry.sequence == 1 && entry.runId == fromRun.id,
        "entry deal appended with service-assigned identity");
    long entryId = entry.id;
    verify(fromService.appendClosedDealEvent(fromRun.id, trade.id, entry)
        && entry.id == entryId && hasEventCount(fromService, trade.id, 1)
        && hasSnapshot(fromService, trade), "same deal is idempotent and snapshot stays unchanged");

    bool triggerCreated = H1EaSql::execute(fromService.getHandle(),
        "CREATE TRIGGER smoke_deal_insert_failure BEFORE INSERT ON h1_ea_trade_events "
        "WHEN NEW.event_type='DEAL_ADD' BEGIN SELECT RAISE(ABORT,'SMOKE_DEAL_INSERT_FAILURE'); END;");
    verify(triggerCreated, "create dedicated insert failure trigger");
    H1EaTradeEventEntity exitEvent;
    prepareDeal(exitEvent, fromRun, trade, true);
    if (triggerCreated) {
        verify(!fromService.appendClosedDealEvent(fromRun.id, trade.id, exitEvent)
            && exitEvent.id == 0 && hasEventCount(fromService, trade.id, 1)
            && hasSnapshot(fromService, trade), "failed insert rolls back and preserves retry identity");
        verify(H1EaSql::execute(fromService.getHandle(), "DROP TRIGGER smoke_deal_insert_failure"),
            "remove dedicated insert failure trigger");
    }
    verify(fromService.appendClosedDealEvent(fromRun.id, trade.id, exitEvent)
        && exitEvent.sequence == 2 && hasEventCount(fromService, trade.id, 2)
        && hasSnapshot(fromService, trade), "same exit UID succeeds after rollback");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found)
        && found && candidate.id == trade.id, "pending marker remains until all-history audit completes");
    verify(fromService.completeClosedDealAudit(fromRun.id, trade.id), "complete closed deal audit");
    trade.lastError = "";
    verify(hasSnapshot(fromService, trade), "completion changes only the pending marker");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found)
        && !found, "complete entry and exit events remove candidate");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found, true)
        && found && candidate.id == trade.id, "startup full audit includes completed endpoint history");
    verify(fromService.loadClosedTradeForDealAudit(fromRun.contextKey, 0, candidate, found, false)
        && !found, "normal retry excludes completed trade without pending marker");
    verify(fromService.loadClosedTradeByPosition(fromRun.contextKey, trade.positionIdentifier,
        candidate, found) && found && candidate.id == trade.id,
        "position lookup finds closed trade after endpoint audit completion");
    verify(fromService.loadClosedTradeByPosition(fromRun.contextKey + "|OTHER", trade.positionIdentifier,
        candidate, found) && !found, "position lookup does not cross context boundaries");
    trade.lastError = "OTHER_AUDIT_ISSUE";
    verify(H1EaSql::execute(fromService.getHandle(), "UPDATE h1_ea_trades SET last_error='OTHER_AUDIT_ISSUE' WHERE id="
        + IntegerToString(trade.id)), "set independent error fixture");
    verify(fromService.completeClosedDealAudit(fromRun.id, trade.id)
        && hasSnapshot(fromService, trade), "completion preserves unrelated errors and financial fields");
    verifyBoundaries(fromService, fromRun, trade);
    verifyCandidateSelection(fromService, fromRun);
}

/**
 * 今回作成した専用DBとsidecarだけを、接続終了後に削除する。
 */
void cleanupDatabase(const string fromFileName) {
    if (StringFind(fromFileName, "h1-ea-deal-audit-smoke-") != 0
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
 * 一意な新規Common DBだけを使用する。broker照合・注文・運用DBへの操作は行わない。
 */
void OnStart() {
    string uid = H1EaSql::hash("H1_EA_DEAL_AUDIT_SMOKE|" + IntegerToString(TimeLocal())
        + "|" + IntegerToString(ChartID()) + "|" + StringFormat("%I64u", GetMicrosecondCount()));
    if (!H1EaSql::isHash(uid)) {
        verify(false, "unique smoke identifier unavailable");
        return;
    }
    string fileName = "h1-ea-deal-audit-smoke-" + uid + ".sqlite";
    if (FileIsExist(fileName, FILE_COMMON) || FileIsExist(fileName + "-wal", FILE_COMMON)
            || FileIsExist(fileName + "-shm", FILE_COMMON)) {
        verify(false, "existing smoke path left untouched");
        return;
    }
    H1EaPersistenceService service;
    bool opened = service.open(fileName);
    verify(opened, "open dedicated new database");
    if (opened) {
        H1EaRunEntity run;
        prepareRun(run, uid);
        bool acquired = service.acquireRun(run);
        verify(acquired, "acquire dedicated run");
        if (acquired) {
            verifyAudit(service, run);
            string status = "STOPPED";
            string errorText = "";
            if (failedCount > 0) {
                status = "FAILED";
                errorText = "SMOKE_ASSERTION_FAILED";
            }
            verify(service.finishRun(run.id, status, errorText), "finish dedicated run");
        }
    }
    service.close();
    cleanupDatabase(fileName);
    Print("INFO H1EaDealAuditSmokeTest completed passed=", passedCount, " failed=", failedCount);
}
