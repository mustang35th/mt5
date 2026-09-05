#ifndef MSTNGH1EA_TRADE_H1EATRADEEXECUTOR_MQH
#define MSTNGH1EA_TRADE_H1EATRADEEXECUTOR_MQH

#include <Mstng\Database\Service\H1EaPersistenceService.mqh>
#include <MstngEa\Domain\PositionSnapshot.mqh>
#include <MstngEa\Strategy\H1ZigZagTrailDecision.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>
#include <MstngH1Ea\Trade\H1EaProtectionPolicy.mqh>

/**
 * 取引状態と監査Eventを同じ順序で再保存するメモリ項目。
 */
struct H1EaTradeSaveItem {
    /** Event時点の状態。 */
    H1EaTradeEntity trade;
    /** 一意ID確定済みEvent。 */
    H1EaTradeEventEntity event;
};

/**
 * H1専用の発注・broker照合・保護SL管理。
 * Decisionは書き換えず、送信要求を確定してからbrokerへ送る。
 */
class H1EaTradeExecutor {
public:
    /**
     * 初期状態ではbroker送信権限を持たない。
     */
    H1EaTradeExecutor() {
        this.persistence = NULL;
        this.active = false;
        this.initialized = false;
        this.loaded = false;
        this.idleReconciled = false;
        this.lockHeld = false;
        this.knownLeaseExpires = 0;
        this.blockedEntryBar = 0;
        this.actionSequence = 0;
        this.lastSendTick = 0;
        this.queueOverflow = false;
        this.externalStopLoss = 0.0;
        this.lastRecoveryUid = "";
        this.lastDispatchedTradeId = 0;
        this.recoveryCommitPending = false;
        this.orderReadFailed = false;
        this.entryCancelAttempted = false;
        this.cancelTurn = true;
        this.exitActionUid = "";
        this.confirmedModifyActionUid = "";
        this.confirmedModifyRetcode = -1;
        this.pendingModifyRequestId = 0;
        this.pendingStored = false;
        this.ownershipLost = false;
        this.entryH1Bar = 0;
    }

    /**
     * 依存と実行scopeを設定する。初期化中の発注は行わない。
     */
    bool initialize(const string fromSymbol, const ulong fromMagic,
            const double fromPipSize, const double fromTickSize,
            const long fromRunId, const string fromRunUid, const string fromContextKey,
            H1EaPersistenceService *fromPersistence) {
        if (this.initialized || fromPersistence == NULL || fromRunId <= 0
                || fromPipSize <= 0.0 || fromTickSize <= 0.0) {
            return false;
        }
        this.symbolName = fromSymbol;
        this.magicNumber = fromMagic;
        this.pipSize = fromPipSize;
        this.tickSize = fromTickSize;
        this.runId = fromRunId;
        this.runUid = fromRunUid;
        this.contextKey = fromContextKey;
        this.persistence = fromPersistence;
        this.operationLogger.initialize(fromSymbol, fromMagic, fromRunUid);
        this.initialized = true;
        return true;
    }

    /**
     * Controllerが確認したLockとLease安全期限だけを利用する。
     */
    void setManagementAuthority(const bool fromLockHeld, const datetime fromLeaseExpires) {
        this.lockHeld = fromLockHeld;
        this.knownLeaseExpires = fromLeaseExpires;
    }

    /**
     * 再起動から復元した同一バー反転禁止を取り込む。
     */
    void setBlockedEntryBar(const datetime fromBarTime) {
        if (fromBarTime > this.blockedEntryBar) {
            this.blockedEntryBar = fromBarTime;
        }
    }

    /**
     * 保有・発注中・復旧待ちもactiveとして扱う。
     */
    bool hasActiveTrade() {
        return this.active || !this.loaded;
    }

    /**
     * 保存待ち中は新規注文を停止する。
     */
    bool hasUnsavedEvents() {
        return ArraySize(this.saveQueue) > 0 || this.queueOverflow;
    }

    /**
     * Tester準備中の軽量経路に使える、取引履歴を持たない空状態を確認する。
     * メモリだけを参照し、現在の全注文・全Position・Lease期限はControllerが別途確認する。
     */
    bool isIdleForTesterWarmup() const {
        if (!this.initialized || !this.loaded || !this.idleReconciled || this.persistence == NULL
                || this.runId <= 0 || !this.lockHeld || this.knownLeaseExpires <= 0
                || this.active || this.ownershipLost || this.queueOverflow || ArraySize(this.saveQueue) > 0
                || this.recoveryCommitPending || this.orderReadFailed || this.pendingStored) {
            return false;
        }
        if (this.trade.id != 0 || this.trade.status != "" || this.trade.lastError != ""
                || this.trade.positionIdentifier != "" || this.trade.positionTicket != ""
                || this.trade.entryOrderTicket != "" || this.trade.exitOrderTicket != ""
                || this.entryActionUid != "" || this.exitActionUid != ""
                || this.entryH1Bar != 0 || this.lastDispatchedTradeId != 0 || this.entryCancelAttempted
                || this.pendingModifyRequestId != 0 || this.confirmedModifyActionUid != ""
                || this.confirmedModifyRetcode != -1) {
            return false;
        }
        return this.trade.pendingStopLossKind == "" && this.trade.pendingStopLossActionUid == ""
            && this.trade.pendingStopLoss == 0.0 && this.trade.pendingStopLossH1BarTime == 0
            && this.trade.pendingStopLossPivotTime == 0 && this.trade.pendingStopLossPivotRate == 0.0
            && this.trade.pendingStopLossLatestTime == 0;
    }

    /**
     * Eventと当時の状態をFIFOで再保存する。再送はしない。
     */
    bool flushPendingEvents() {
        if (this.persistence == NULL) {
            return false;
        }
        while (ArraySize(this.saveQueue) > 0) {
            if (!this.persistence.saveTradeEvent(this.runId, this.saveQueue[0].trade,
                    this.saveQueue[0].event, false, true)) {
                string failure = this.persistence.getLastError();
                if (failure == "SNAPSHOT_OWNER_SUPERSEDED" || failure == "RUN_SCOPE_OR_LEASE_LOST"
                        || failure == "LEASE_NOT_OWNED") {
                    this.ownershipLost = true;
                    this.knownLeaseExpires = 0;
                }
                return false;
            }
            if (this.trade.id == 0 && this.trade.contextKey == this.saveQueue[0].trade.contextKey) {
                this.trade.id = this.saveQueue[0].trade.id;
            }
            int queueSize = ArraySize(this.saveQueue);
            for (int i = 1; i < queueSize; i++) {
                if (this.saveQueue[i].trade.id == 0
                        && this.saveQueue[i].trade.contextKey == this.saveQueue[0].trade.contextKey
                        && this.saveQueue[i].trade.positionIdentifier != ""
                        && this.saveQueue[i].trade.positionIdentifier == this.saveQueue[0].trade.positionIdentifier) {
                    this.saveQueue[i].trade.id = this.saveQueue[0].trade.id;
                    this.saveQueue[i].event.tradeId = this.saveQueue[0].trade.id;
                }
            }
            for (int i = 1; i < queueSize; i++) {
                this.saveQueue[i - 1] = this.saveQueue[i];
            }
            ArrayResize(this.saveQueue, queueSize - 1);
        }
        this.recoveryCommitPending = false;
        return !this.queueOverflow;
    }

    /**
     * 発注直前まで有効な市場・保有・Leaseを要求する。
     */
    bool canEnter(const datetime fromH1Bar, string &fromReason) {
        fromReason = "";
        if (!this.loaded || !this.initialized || !this.lockHeld || this.ownershipLost || this.hasUnsavedEvents()) {
            fromReason = "DB_UNAVAILABLE";
            return false;
        }
        if (!this.persistence.hasLease(this.runId, TimeLocal())) {
            if (this.persistence.getLastError() == "LEASE_NOT_OWNED") {
                this.ownershipLost = true;
                this.knownLeaseExpires = 0;
            }
            fromReason = "LEASE_UNAVAILABLE";
            return false;
        }
        if (fromH1Bar == this.blockedEntryBar) {
            fromReason = "SAME_BAR_EXIT_BLOCKED";
            return false;
        }
        PositionSnapshot position;
        int positionCount = 0;
        if (!this.readPosition(position, positionCount)) {
            fromReason = "POSITION_UNAVAILABLE";
            return false;
        }
        if (this.active || positionCount > 0 || this.hasOwnOrders()) {
            fromReason = "POSITION_OR_ORDER_EXISTS";
            return false;
        }
        if (!this.tradeEnvironmentReady()) {
            fromReason = "TRADING_UNAVAILABLE";
            return false;
        }
        MqlTick marketTick;
        if (!this.readTick(marketTick)) {
            fromReason = "PRICE_UNAVAILABLE";
            return false;
        }
        return true;
    }

    /**
     * 正規化済みSL・数量を送信前transactionへ渡す。
     */
    void prepareEntry(H1EaDecisionEntity &fromDecision, H1EaTradeEntity &fromTrade,
            H1EaTradeEventEntity &fromEvent) {
        fromTrade.reset();
        fromTrade.createdRunId = this.runId;
        fromTrade.contextKey = this.contextKey;
        fromTrade.origin = "NORMAL";
        fromTrade.status = "OPEN_PENDING";
        fromTrade.side = fromDecision.decision;
        fromTrade.requestedVolume = fromDecision.requestedVolume;
        fromTrade.requestedStopLoss = fromDecision.initialStopLoss;
        fromTrade.entryRequestedServerTime = TimeCurrent();
        fromTrade.createdAt = TimeLocal();
        fromTrade.updatedAt = fromTrade.createdAt;
        this.newEvent("ENTRY_REQUEST", fromEvent);
        this.actionSequence++;
        fromEvent.actionUid = "H1_EA_ACTION_V1|" + this.runUid + "|{TRADE_ID}|ENTRY|"
            + IntegerToString(this.actionSequence);
        fromEvent.eventUid = fromEvent.actionUid + "|REQUEST";
        fromEvent.positionIdentifier = "";
        fromEvent.positionTicket = "";
        fromEvent.stopLossSource = "NONE";
        fromEvent.side = fromTrade.side;
        fromEvent.volume = fromTrade.requestedVolume;
        fromEvent.stopLoss = fromTrade.requestedStopLoss;
        fromEvent.h1BarTime = fromDecision.h1BarTime;
        fromEvent.message = "MAX_INITIAL_RISK_PIPS=" + DoubleToString(fromDecision.maxInitialRiskPips, 8);
        this.entryMaximumRisk = fromDecision.maxInitialRiskPips;
        this.entryH1Bar = (datetime)fromDecision.h1BarTime;
    }

    /**
     * saveEntry成功直後だけ呼ぶ。未知受付の再送はしない。
     */
    void sendEntry(H1EaTradeEntity &fromTrade, H1EaTradeEventEntity &fromEntryRequest) {
        if (fromTrade.id <= 0 || fromEntryRequest.id <= 0 || fromTrade.status != "OPEN_PENDING"
                || this.lastDispatchedTradeId == fromTrade.id) {
            return;
        }
        this.lastDispatchedTradeId = fromTrade.id;
        this.trade = fromTrade;
        this.active = true;
        this.entryActionUid = fromEntryRequest.actionUid;
        this.externalStopLoss = 0.0;
        this.entryCancelAttempted = false;
        this.exitActionUid = "";
        MqlTradeRequest request;
        MqlTradeResult result;
        MqlTradeCheckResult check;
        ZeroMemory(request);
        ZeroMemory(result);
        ZeroMemory(check);
        string reason;
        if (!this.buildEntryRequest(request, reason)) {
            this.trade.status = "OPEN_FAILED";
            this.trade.lastError = reason;
        } else if (!OrderCheck(request, check)
                || (check.retcode != 0 && check.retcode != TRADE_RETCODE_DONE)) {
            this.trade.status = "OPEN_FAILED";
            this.trade.lastError = "ORDER_CHECK_FAILED: " + check.comment;
            result.retcode = check.retcode;
        } else {
            // 同一transactionで確認したLeaseの安全期限を送信直前にも確認する。
            if (!this.hasManagementAuthority()) {
                this.trade.status = "OPEN_FAILED";
                this.trade.lastError = "LEASE_EXPIRED_BEFORE_SEND";
            } else if (iTime(this.symbolName, PERIOD_H1, 0) != this.entryH1Bar) {
                this.trade.status = "OPEN_FAILED";
                this.trade.lastError = "ENTRY_BAR_EXPIRED";
            } else {
                bool sent = OrderSend(request, result);
                this.trade.entryRetcode = (int)result.retcode;
                if (result.order > 0) {
                    this.trade.entryOrderTicket = H1EaTextUtil::ticket(result.order);
                }
                if (result.deal > 0) {
                    this.trade.entryDealTicket = H1EaTextUtil::ticket(result.deal);
                }
                if (!H1EaProtectionPolicy::isAcceptedRetcode(result.retcode)
                        && !H1EaProtectionPolicy::isUnknownRetcode(result.retcode)) {
                    this.trade.status = "OPEN_FAILED";
                }
                if (!sent || this.trade.status == "OPEN_FAILED") {
                    this.trade.lastError = "ORDER_SEND: " + result.comment;
                }
            }
        }
        this.trade.entryRetcode = (int)result.retcode;
        H1EaTradeEventEntity event;
        this.newEvent("ENTRY_RESULT", event);
        event.actionUid = fromEntryRequest.actionUid;
        event.eventUid = event.actionUid + "|RESULT";
        event.retcode = (int)result.retcode;
        event.orderTicket = this.trade.entryOrderTicket;
        event.dealTicket = this.trade.entryDealTicket;
        event.volume = this.trade.requestedVolume;
        event.stopLoss = this.trade.requestedStopLoss;
        event.message = this.trade.lastError;
        this.saveEvent(event, false);
        fromTrade = this.trade;
        if (this.trade.status == "OPEN_FAILED") {
            this.active = false;
        } else {
            this.reconcile();
        }
    }

    /**
     * broker事実を照合するだけで注文・変更・決済は送らない。
     */
    void reconcile() {
        this.idleReconciled = false;
        if (!this.initialized) {
            return;
        }
        if (!this.loaded) {
            if (!this.persistence.loadActiveTrade(this.contextKey, this.trade, this.active)) {
                return;
            }
            this.loaded = true;
            this.pendingStored = this.active;
        }
        PositionSnapshot position;
        int positionCount = 0;
        if (!this.readPosition(position, positionCount)) {
            if (this.active) {
                this.requireRecovery("BROKER_POSITION_UNAVAILABLE");
            }
            return;
        }
        if (positionCount > 1) {
            if (this.active) {
                this.requireRecovery("MULTIPLE_OWN_POSITIONS");
            }
            return;
        }
        if (!this.active) {
            if (!position.hasPosition) {
                this.idleReconciled = true;
                return;
            }
            this.createRecoveryTrade(position);
            return;
        }
        if (!this.pendingStructureValid()) {
            H1EaTradeEventEntity event;
            this.newEvent("RECOVERY", event);
            event.recoveryIssueCode = "INVALID_PENDING_STRUCTURE";
            string rawPending;
            if (this.pendingStored && this.persistence.loadPendingRaw(this.trade.id, rawPending)) {
                event.quarantinedPendingText = rawPending;
            } else {
                event.quarantinedPendingText = "H1_EA_PENDING_MEMORY_V1|db_raw_unavailable=1|" + this.pendingText();
            }
            this.clearPending();
            this.trade.status = "RECOVERY_REQUIRED";
            this.trade.lastError = "INVALID_PENDING_STRUCTURE";
            this.recoveryEvent(event);
            return;
        }
        if (position.hasPosition) {
            string identifier = H1EaTextUtil::ticket(position.identifier);
            if ((this.trade.positionIdentifier != "" && this.trade.positionIdentifier != identifier)
                    || (position.isBuy != (this.trade.side == "BUY"))) {
                this.requireRecovery("POSITION_IDENTITY_MISMATCH");
                return;
            }
            if (this.trade.positionIdentifier == "" && !this.matchEntryPosition(position)) {
                this.requireRecovery("ENTRY_POSITION_UNMATCHED");
                return;
            }
            this.trade.positionIdentifier = identifier;
            this.trade.positionTicket = H1EaTextUtil::ticket(position.ticket);
            this.trade.openedAtMsc = position.openTimeMilliseconds;
            this.trade.openPrice = position.openPrice;
            bool positionVolumeChanged = this.trade.remainingPositionVolume != position.volume;
            this.trade.remainingPositionVolume = position.volume;
            if (this.trade.openedVolume == EMPTY_VALUE || this.trade.openedVolume < position.volume) {
                this.trade.openedVolume = position.volume;
            }
            bool needsDealRecovery = this.trade.status != "OPEN" || this.trade.entryDealTicket == ""
                || positionVolumeChanged;
            bool wasRecovery = this.trade.status == "RECOVERY_REQUIRED";
            bool entryOrderActive = this.entryOrderIsActive();
            if (this.orderReadFailed) {
                this.requireRecovery("BROKER_ORDER_UNAVAILABLE");
                return;
            }
            if (this.trade.status == "OPEN_PENDING" || this.trade.status == "OPEN_PARTIAL"
                    || this.trade.status == "RECOVERY_REQUIRED") {
                if (this.trade.exitIntentReason != "") {
                    this.trade.status = "CLOSE_PARTIAL";
                } else if (entryOrderActive) {
                    this.trade.status = "OPEN_PARTIAL";
                } else if (this.trade.lastError == "UNEXPECTED_INOUT_DEAL"
                        || (this.trade.origin == "RECOVERED" && this.trade.requestedStopLoss <= 0.0)) {
                    this.trade.status = "RECOVERY_REQUIRED";
                } else {
                    this.trade.status = "OPEN";
                }
            }
            if (this.trade.exitIntentReason != "" && this.trade.openedVolume != EMPTY_VALUE
                    && position.volume < this.trade.openedVolume - 0.00000001) {
                this.trade.status = "CLOSE_PARTIAL";
            }
            this.syncStopLoss(position);
            if (this.trade.exitIntentReason != "") {
                this.reconcileCloseOrder();
            }
            if (needsDealRecovery) {
                this.aggregateDeals(false);
            }
            H1EaTradeEventEntity event;
            this.newEvent("RECOVERY", event);
            if (wasRecovery && this.trade.status != "RECOVERY_REQUIRED") {
                this.recoveryCommitPending = true;
            }
            this.recoveryEvent(event);
        } else {
            this.reconcileMissingPosition();
        }
    }

    /**
     * H1新規バーの分析を実施する必要があるか返す。
     */
    bool isTrailEligible(const datetime fromH1Bar) {
        return this.active && this.trade.status == "OPEN"
            && fromH1Bar > 0 && this.trade.lastTrailEvaluatedH1BarTime != fromH1Bar;
    }

    /**
     * 新規バーのH1分析から候補と見送りを一度だけ記録する。
     */
    void evaluateTrail(const datetime fromH1Bar, Wave *fromWave,
            const string fromAnalysisFailureReason = "") {
        if (!this.isTrailEligible(fromH1Bar)) {
            return;
        }
        H1EaTradeEventEntity event;
        this.newEvent("TRAIL_EVALUATION", event);
        event.eventUid = "H1_EA_TRAIL_EVALUATION_V1|" + this.contextKey + "|"
            + IntegerToString(this.trade.id) + "|" + IntegerToString(fromH1Bar);
        event.h1BarTime = fromH1Bar;
        PositionSnapshot position;
        int positionCount = 0;
        H1ZigZagTrailDecisionResult result;
        result.reset();
        if (this.trade.pendingStopLossKind == "INITIAL_RESTORE") {
            event.trailSkipReason = "INITIAL_STOP_LOSS_RESTORE_PENDING";
        } else if (this.trade.pendingStopLossActionUid != "") {
            event.trailSkipReason = "SL_MODIFY_ACTION_PENDING";
        } else if (fromAnalysisFailureReason != "") {
            event.trailSkipReason = fromAnalysisFailureReason;
        } else if (!this.readPosition(position, positionCount) || positionCount != 1) {
            event.trailSkipReason = "INVALID_POSITION";
        } else {
            H1ZigZagTrailDecision decision;
            if (!decision.evaluate(position, fromWave, 10.0, this.pipSize, this.tickSize, result)) {
                event.trailSkipReason = result.skipReason;
            } else if (this.trade.pendingStopLoss > 0.0
                    && !H1EaProtectionPolicy::improves(position.isBuy, result.targetStopLoss,
                        this.trade.pendingStopLoss, this.tickSize)) {
                event.trailSkipReason = "PENDING_NOT_IMPROVED";
            } else {
                this.trade.pendingStopLossKind = "TRAIL_CANDIDATE";
                this.trade.pendingStopLossH1BarTime = fromH1Bar;
                this.trade.pendingStopLoss = result.targetStopLoss;
                this.trade.pendingStopLossPivotTime = result.pivotBarTime;
                this.trade.pendingStopLossPivotRate = result.pivotRate;
                this.trade.pendingStopLossLatestTime = result.latestBarTime;
                this.copyPendingToEvent(event, false);
            }
        }
        this.trade.lastTrailEvaluatedH1BarTime = fromH1Bar;
        this.saveEvent(event, false);
    }

    /**
     * tick側だけから呼び、既存リスク低減を1秒以上の間隔で送信する。
     */
    void processPending(const datetime fromH1Bar) {
        if (!this.active || this.trade.status == "RECOVERY_REQUIRED" || this.recoveryCommitPending
                || !this.hasManagementAuthority() || this.queueOverflow) {
            return;
        }
        if (this.lastSendTick > 0 && H1EaClock::milliseconds() - this.lastSendTick < 1000) {
            return;
        }
        if (this.trade.status == "OPEN_PARTIAL"
                && this.trade.pendingStopLossKind != "INITIAL_RESTORE") {
            this.cancelEntryRemainder();
            return;
        }
        if (this.trade.status == "CLOSE_PENDING" || this.trade.status == "CLOSE_PARTIAL") {
            bool entryActive = this.entryOrderIsActive();
            if (this.orderReadFailed) {
                this.requireRecovery("BROKER_ORDER_UNAVAILABLE");
                return;
            }
            if (entryActive && this.cancelTurn) {
                this.cancelTurn = false;
                this.cancelEntryRemainder();
                return;
            }
            this.cancelTurn = true;
            this.retryClose(fromH1Bar);
            return;
        }
        if ((this.trade.status != "OPEN" && this.trade.status != "OPEN_PARTIAL")
                || this.trade.pendingStopLoss <= 0.0
                || this.trade.pendingStopLossActionUid != "") {
            return;
        }
        if (!this.pendingStructureValid()) {
            this.reconcile();
            return;
        }
        PositionSnapshot position;
        int positionCount = 0;
        if (!this.readPosition(position, positionCount) || positionCount != 1
                || H1EaTextUtil::ticket(position.identifier) != this.trade.positionIdentifier) {
            this.requireRecovery("PENDING_POSITION_UNAVAILABLE");
            return;
        }
        if (H1EaProtectionPolicy::protects(position.isBuy, position.stopLoss,
                this.trade.pendingStopLoss, this.tickSize)) {
            this.syncStopLoss(position);
            H1EaTradeEventEntity event;
            this.newEvent("RECOVERY", event);
            this.recoveryEvent(event);
            return;
        }
        MqlTick marketTick;
        if (!this.readTick(marketTick)) {
            return;
        }
        if (H1EaProtectionPolicy::crossed(position.isBuy, marketTick.bid, marketTick.ask,
                this.trade.pendingStopLoss)) {
            // 部分Entryでは先に残注文取消を要求し、その後も残注文を監視する。
            if (this.trade.status == "OPEN_PARTIAL" && !this.entryCancelAttempted) {
                this.cancelEntryRemainder();
                return;
            }
            this.beginClose(position, fromH1Bar);
            return;
        }
        double point = SymbolInfoDouble(this.symbolName, SYMBOL_POINT);
        long stops = SymbolInfoInteger(this.symbolName, SYMBOL_TRADE_STOPS_LEVEL);
        long freeze = SymbolInfoInteger(this.symbolName, SYMBOL_TRADE_FREEZE_LEVEL);
        if (!H1EaProtectionPolicy::canModify(position.isBuy, marketTick.bid, marketTick.ask,
                this.trade.pendingStopLoss, point, this.tickSize, stops, freeze)) {
            return;
        }
        this.modifyStopLoss(position);
    }

    /**
     * 各dealをPOSITION_IDENTIFIERへ結合する。金額は履歴から再集計する。
     */
    void onTradeTransaction(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
        if (!this.initialized) {
            return;
        }
        if (this.active && fromTransaction.type == TRADE_TRANSACTION_REQUEST
                && fromRequest.action == TRADE_ACTION_SLTP
                && fromRequest.position == H1EaTextUtil::parseTicket(this.trade.positionTicket)
                && fromRequest.magic != this.magicNumber
                && H1EaProtectionPolicy::isAcceptedRetcode(fromResult.retcode)) {
            this.externalStopLoss = fromRequest.sl;
        }
        if (this.active && this.trade.pendingStopLossActionUid != ""
                && this.pendingModifyRequestId > 0 && fromTransaction.type == TRADE_TRANSACTION_REQUEST
                && fromResult.request_id == this.pendingModifyRequestId
                && fromRequest.action == TRADE_ACTION_SLTP && fromRequest.magic == this.magicNumber
                && !H1EaProtectionPolicy::isUnknownRetcode(fromResult.retcode)
                && fromResult.retcode != TRADE_RETCODE_PLACED) {
            this.confirmedModifyActionUid = this.trade.pendingStopLossActionUid;
            this.confirmedModifyRetcode = (int)fromResult.retcode;
        }
        this.reconcile();
        if (fromTransaction.type != TRADE_TRANSACTION_DEAL_ADD || !this.active
                || fromTransaction.deal == 0 || !HistoryDealSelect(fromTransaction.deal)) {
            return;
        }
        string identifier = H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(fromTransaction.deal, DEAL_POSITION_ID));
        if (identifier != this.trade.positionIdentifier) {
            return;
        }
        this.recordDeal(fromTransaction.deal, "CALLBACK");
        this.aggregateDeals(false);
        this.reconcile();
    }

private:
    /** DB。 */
    H1EaPersistenceService *persistence;
    /** DBと独立した運用ログ。 */
    H1EaOperationLogger operationLogger;
    /** 現在Trade。 */
    H1EaTradeEntity trade;
    /** 保存待ちFIFO。 */
    H1EaTradeSaveItem saveQueue[];
    /** シンボル。 */
    string symbolName;
    /** Magic。 */
    ulong magicNumber;
    /** pip幅。 */
    double pipSize;
    /** tick幅。 */
    double tickSize;
    /** Run。 */
    long runId;
    /** Run UID。 */
    string runUid;
    /** context。 */
    string contextKey;
    /** 初期化済み。 */
    bool initialized;
    /** DB初回読込済み。 */
    bool loaded;
    /** 最後のbroker照合で自EAのTradeとPositionがないことを確認済み。 */
    bool idleReconciled;
    /** active状態。 */
    bool active;
    /** 排他Lock保持。 */
    bool lockHeld;
    /** 既知Lease期限。 */
    datetime knownLeaseExpires;
    /** 同一バー発注禁止。 */
    datetime blockedEntryBar;
    /** Run内action連番。 */
    long actionSequence;
    /** 最終送信のプロセス時刻。 */
    ulong lastSendTick;
    /** キュー欠落を検出。 */
    bool queueOverflow;
    /** Entry要求action。 */
    string entryActionUid;
    /** Entry時の最大幅。 */
    double entryMaximumRisk;
    /** 保存待ちで次のバーへ繰り越さない判定対象H1バー。 */
    datetime entryH1Bar;
    /** 外部変更と積極的に確認したSL。 */
    double externalStopLoss;
    /** 同一brokerスナップショットの再保存抑止。 */
    string lastRecoveryUid;
    /** プロセス内のEntry再呼出しを拒否する。 */
    long lastDispatchedTradeId;
    /** RECOVERY_REQUIRED解除のcommit前はbroker送信しない。 */
    bool recoveryCommitPending;
    /** 注文列挙の失敗を「注文なし」と混同しない。 */
    bool orderReadFailed;
    /** 部分Entryの取消を一度は要求したか。 */
    bool entryCancelAttempted;
    /** 決済中も残Entry取消と残量決済を交互に進める。 */
    bool cancelTurn;
    /** 最後の決済要求の一意識別。 */
    string exitActionUid;
    /** brokerから終端応答を確認したSL action。 */
    string confirmedModifyActionUid;
    /** 終端SL応答コード。 */
    int confirmedModifyRetcode;
    /** 同一プロセス内でcallbackへ照合するbroker request ID。 */
    uint pendingModifyRequestId;
    /** メモリpendingが保存済みDB列と一致している場合true。 */
    bool pendingStored;
    /** 確認済み所有権喪失は古いheartbeat値で解除しない。 */
    bool ownershipLost;

    /**
     * 非DBの送信権限を確認する。起動時未取得Leaseは許可しない。
     */
    bool hasManagementAuthority() {
        return !this.ownershipLost && this.lockHeld && this.knownLeaseExpires > TimeLocal() && this.runId > 0;
    }

    /**
     * 市場注文を許可する口座・端末状態を確認する。
     */
    bool tradeEnvironmentReady() {
        return AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING
            && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
            && MQLInfoInteger(MQL_TRADE_ALLOWED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
            && (MQLInfoInteger(MQL_TESTER) || TerminalInfoInteger(TERMINAL_CONNECTED));
    }

    /**
     * Bid/Ask未取得をゼロ価格と混同しない。
     */
    bool readTick(MqlTick &fromTick) {
        return SymbolInfoTick(this.symbolName, fromTick) && fromTick.bid > 0.0
            && fromTick.ask >= fromTick.bid && MathIsValidNumber(fromTick.ask);
    }

    /**
     * hedging口座の自EAポジションを一意に選ぶ。
     */
    bool readPosition(PositionSnapshot &fromPosition, int &fromCount) {
        fromPosition.hasPosition = false;
        fromCount = 0;
        for (int i = 0; i < PositionsTotal(); i++) {
            ulong ticket = PositionGetTicket(i);
            if (ticket == 0) {
                return false;
            }
            if (PositionGetString(POSITION_SYMBOL) != this.symbolName) {
                continue;
            }
            ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != this.magicNumber
                    && (!this.active || H1EaTextUtil::ticket(identifier) != this.trade.positionIdentifier)) {
                continue;
            }
            fromCount++;
            double actualStopLoss = 0.0;
            if (!PositionGetDouble(POSITION_SL, actualStopLoss) || !MathIsValidNumber(actualStopLoss)) {
                return false;
            }
            fromPosition.hasPosition = true;
            fromPosition.ticket = ticket;
            fromPosition.identifier = identifier;
            fromPosition.isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            fromPosition.volume = PositionGetDouble(POSITION_VOLUME);
            fromPosition.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            fromPosition.openTimeMilliseconds = PositionGetInteger(POSITION_TIME_MSC);
            fromPosition.stopLoss = actualStopLoss;
            if (identifier == 0 || fromPosition.volume <= 0.0 || fromPosition.openPrice <= 0.0) {
                return false;
            }
        }
        return true;
    }

    /**
     * 自EAの未完了注文があれば新規を禁止する。
     */
    bool hasOwnOrders() {
        for (int i = 0; i < OrdersTotal(); i++) {
            if (OrderGetTicket(i) == 0) {
                return true;
            }
            if (OrderGetString(ORDER_SYMBOL) == this.symbolName
                    && (ulong)OrderGetInteger(ORDER_MAGIC) == this.magicNumber) {
                return true;
            }
        }
        return false;
    }

    /**
     * broker対応fillingを選び、market executionでRETURNを使わない。
     */
    ENUM_ORDER_TYPE_FILLING fillingType() {
        long filling = SymbolInfoInteger(this.symbolName, SYMBOL_FILLING_MODE);
        if ((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
            return ORDER_FILLING_FOK;
        }
        if ((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
            return ORDER_FILLING_IOC;
        }
        return ORDER_FILLING_RETURN;
    }

    /**
     * 必須SLと最新価格での最大リスクを再検証する。
     */
    bool buildEntryRequest(MqlTradeRequest &fromRequest, string &fromReason) {
        if (this.entryH1Bar <= 0 || iTime(this.symbolName, PERIOD_H1, 0) != this.entryH1Bar) {
            fromReason = "ENTRY_BAR_EXPIRED";
            return false;
        }
        MqlTick marketTick;
        PositionSnapshot position;
        int count = 0;
        fromReason = "ENTRY_SAFETY_CHANGED";
        if (!this.tradeEnvironmentReady() || !this.readTick(marketTick)
                || !this.readPosition(position, count) || count != 0 || this.hasOwnOrders()
                || this.trade.requestedStopLoss <= 0.0 || this.entryMaximumRisk <= 0.0) {
            return false;
        }
        bool isBuy = this.trade.side == "BUY";
        double price = marketTick.bid;
        double distance = this.trade.requestedStopLoss - price;
        double stopDistance = this.trade.requestedStopLoss - marketTick.ask;
        if (isBuy) {
            price = marketTick.ask;
            distance = price - this.trade.requestedStopLoss;
            stopDistance = marketTick.bid - this.trade.requestedStopLoss;
        }
        double required = (double)SymbolInfoInteger(this.symbolName, SYMBOL_TRADE_STOPS_LEVEL)
            * SymbolInfoDouble(this.symbolName, SYMBOL_POINT);
        if (distance <= 0.0 || distance / this.pipSize > this.entryMaximumRisk + 0.000001
                || stopDistance < required || (marketTick.ask - marketTick.bid) / this.pipSize > 5.0 + 0.000001) {
            fromReason = "ENTRY_PRICE_SL_OR_SPREAD_CHANGED";
            return false;
        }
        fromRequest.action = TRADE_ACTION_DEAL;
        fromRequest.symbol = this.symbolName;
        fromRequest.magic = this.magicNumber;
        fromRequest.volume = this.trade.requestedVolume;
        fromRequest.sl = this.trade.requestedStopLoss;
        fromRequest.tp = 0.0;
        fromRequest.price = price;
        fromRequest.deviation = 10;
        fromRequest.type = ORDER_TYPE_SELL;
        if (isBuy) {
            fromRequest.type = ORDER_TYPE_BUY;
        }
        fromRequest.type_filling = this.fillingType();
        fromRequest.comment = this.entryComment();
        return true;
    }

    /**
     * 再起動でEntry要求とorderを対応付ける短いコメント。
     */
    string entryComment() {
        return "MstngH1EaV1:" + IntegerToString(this.trade.id);
    }

    /**
     * Eventの共通監査列を初期化する。
     */
    void newEvent(const string fromType, H1EaTradeEventEntity &fromEvent) {
        fromEvent.reset();
        fromEvent.tradeId = this.trade.id;
        fromEvent.runId = this.runId;
        fromEvent.eventType = fromType;
        fromEvent.serverTime = TimeCurrent();
        fromEvent.recordedAt = TimeLocal();
        fromEvent.side = this.trade.side;
        fromEvent.positionIdentifier = this.trade.positionIdentifier;
        fromEvent.positionTicket = this.trade.positionTicket;
        fromEvent.stopLossSource = this.trade.stopLossSource;
    }

    /**
     * 送信actionをプロセス内単調連番で確定する。
     */
    void newAction(const string fromType, H1EaTradeEventEntity &fromEvent) {
        this.newEvent(fromType + "_REQUEST", fromEvent);
        this.actionSequence++;
        fromEvent.actionUid = "H1_EA_ACTION_V1|" + this.runUid + "|"
            + IntegerToString(this.trade.id) + "|" + fromType + "|" + IntegerToString(this.actionSequence);
        fromEvent.eventUid = fromEvent.actionUid + "|REQUEST";
    }

    /**
     * Eventと状態の保存失敗を同じUIDでキューへ残す。
     */
    bool saveEvent(H1EaTradeEventEntity &fromEvent, const bool fromRequest) {
        this.trade.updatedAt = TimeLocal();
        fromEvent.tradeId = this.trade.id;
        bool saved = false;
        if (ArraySize(this.saveQueue) == 0) {
            // 重複Eventの読戻しで最新メモリ状態を古いDB状態へ巻き戻さない。
            H1EaTradeEntity storedTrade = this.trade;
            saved = this.persistence.saveTradeEvent(this.runId, storedTrade, fromEvent, fromRequest);
            if (saved && this.trade.id == 0) {
                this.trade.id = storedTrade.id;
            }
            if (saved) {
                this.pendingStored = storedTrade.pendingStopLossKind == this.trade.pendingStopLossKind
                    && storedTrade.pendingStopLoss == this.trade.pendingStopLoss
                    && storedTrade.pendingStopLossH1BarTime == this.trade.pendingStopLossH1BarTime
                    && storedTrade.pendingStopLossPivotTime == this.trade.pendingStopLossPivotTime
                    && storedTrade.pendingStopLossPivotRate == this.trade.pendingStopLossPivotRate
                    && storedTrade.pendingStopLossLatestTime == this.trade.pendingStopLossLatestTime
                    && storedTrade.pendingStopLossActionUid == this.trade.pendingStopLossActionUid;
            }
        }
        if (saved) {
            this.writeLog("INFO", fromEvent.eventType + " " + fromEvent.eventUid + " " + fromEvent.message);
            return true;
        }
        string failure = this.persistence.getLastError();
        if (failure == "LEASE_NOT_OWNED" || failure == "RUN_SCOPE_OR_LEASE_LOST"
                || failure == "SNAPSHOT_OWNER_SUPERSEDED") {
            this.knownLeaseExpires = 0;
            this.ownershipLost = true;
            this.writeLog("ERROR", "LEASE_LOST " + fromEvent.eventUid);
            return false;
        }
        int size = ArraySize(this.saveQueue);
        for (int i = 0; i < size; i++) {
            if (this.saveQueue[i].event.eventUid == fromEvent.eventUid) {
                return !fromRequest || this.hasManagementAuthority();
            }
        }
        if (size >= 256 || ArrayResize(this.saveQueue, size + 1) != size + 1) {
            this.queueOverflow = true;
            this.writeLog("ERROR", "EVENT_QUEUE_FULL " + fromEvent.eventUid);
            return false;
        }
        this.saveQueue[size].trade = this.trade;
        this.saveQueue[size].event = fromEvent;
        this.pendingStored = false;
        this.writeLog("ERROR", "EVENT_QUEUED " + fromEvent.eventUid + " " + this.persistence.getLastError());
        return !fromRequest || this.hasManagementAuthority();
    }

    /**
     * 保護候補の列を一括解除する。
     */
    void clearPending() {
        this.pendingStored = false;
        this.trade.pendingStopLossKind = "";
        this.trade.pendingStopLossH1BarTime = 0;
        this.trade.pendingStopLoss = 0.0;
        this.trade.pendingStopLossPivotTime = 0;
        this.trade.pendingStopLossPivotRate = 0.0;
        this.trade.pendingStopLossLatestTime = 0;
        this.trade.pendingStopLossActionUid = "";
    }

    /**
     * candidate情報を送信・評価Eventへ残す。
     */
    void copyPendingToEvent(H1EaTradeEventEntity &fromEvent, const bool fromModify) {
        fromEvent.stopLoss = this.trade.pendingStopLoss;
        fromEvent.h1BarTime = this.trade.pendingStopLossH1BarTime;
        fromEvent.pivotBarTime = this.trade.pendingStopLossPivotTime;
        fromEvent.pivotRate = this.trade.pendingStopLossPivotRate;
        fromEvent.latestPointBarTime = this.trade.pendingStopLossLatestTime;
        if (fromModify) {
            fromEvent.stopLossActionKind = this.trade.pendingStopLossKind;
        }
    }

    /**
     * 構造不正なpendingは送信せず隔離する。
     */
    bool pendingStructureValid() {
        if (this.trade.pendingStopLossKind == "") {
            return this.trade.pendingStopLoss == 0.0 && this.trade.pendingStopLossH1BarTime == 0
                && this.trade.pendingStopLossPivotTime == 0 && this.trade.pendingStopLossPivotRate == 0.0
                && this.trade.pendingStopLossLatestTime == 0 && this.trade.pendingStopLossActionUid == "";
        }
        if (!MathIsValidNumber(this.trade.pendingStopLoss) || this.trade.pendingStopLoss <= 0.0
                || this.tickSize <= 0.0 || this.pipSize <= 0.0) {
            return false;
        }
        double tickCount = this.trade.pendingStopLoss / this.tickSize;
        if (MathAbs(tickCount - MathRound(tickCount)) > 0.000001) {
            return false;
        }
        if (this.trade.pendingStopLossKind == "INITIAL_RESTORE") {
            return this.trade.pendingStopLossH1BarTime == 0 && this.trade.pendingStopLossPivotTime == 0
                && this.trade.pendingStopLossPivotRate == 0.0 && this.trade.pendingStopLossLatestTime == 0;
        }
        return (this.trade.pendingStopLossKind == "TRAIL_CANDIDATE" || this.trade.pendingStopLossKind == "TRAIL_RESTORE")
            && this.trade.pendingStopLossH1BarTime > 0 && this.trade.pendingStopLossPivotTime > 0
            && this.trade.pendingStopLossPivotRate > 0.0
            && this.trade.pendingStopLossLatestTime > this.trade.pendingStopLossPivotTime;
    }

    /**
     * 隔離前の各pending列を値付きで保持する。
     */
    string pendingText() {
        return "pending_stop_loss_kind:TEXT=" + this.trade.pendingStopLossKind
            + "|pending_stop_loss_h1_bar_time:INTEGER=" + IntegerToString(this.trade.pendingStopLossH1BarTime)
            + "|pending_stop_loss:REAL=" + DoubleToString(this.trade.pendingStopLoss, 8)
            + "|pending_stop_loss_pivot_time:INTEGER=" + IntegerToString(this.trade.pendingStopLossPivotTime)
            + "|pending_stop_loss_pivot_rate:REAL=" + DoubleToString(this.trade.pendingStopLossPivotRate, 8)
            + "|pending_stop_loss_latest_time:INTEGER=" + IntegerToString(this.trade.pendingStopLossLatestTime)
            + "|pending_stop_loss_action_uid:TEXT=" + this.trade.pendingStopLossActionUid;
    }

    /**
     * 元のEntry注文が有効か確認し残数量を取得する。
     */
    bool entryOrderIsActive() {
        this.orderReadFailed = false;
        for (int i = 0; i < OrdersTotal(); i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                this.orderReadFailed = true;
                return true;
            }
            if (OrderGetString(ORDER_SYMBOL) != this.symbolName
                    || (ulong)OrderGetInteger(ORDER_MAGIC) != this.magicNumber) {
                continue;
            }
            if (H1EaTextUtil::ticket(ticket) == this.trade.entryOrderTicket
                    || OrderGetString(ORDER_COMMENT) == this.entryComment()) {
                this.trade.entryOrderTicket = H1EaTextUtil::ticket(ticket);
                this.trade.remainingEntryVolume = OrderGetDouble(ORDER_VOLUME_CURRENT);
                return true;
            }
        }
        this.trade.remainingEntryVolume = 0.0;
        return false;
    }

    /**
     * Position由来のEntryを保存済み注文intentへ照合する。
     */
    bool matchEntryPosition(PositionSnapshot &fromPosition) {
        if (this.trade.origin == "RECOVERED") {
            return true;
        }
        ulong entryOrder = H1EaTextUtil::parseTicket(this.trade.entryOrderTicket);
        if (entryOrder > 0 && OrderSelect(entryOrder)
                && OrderGetString(ORDER_SYMBOL) == this.symbolName
                && (ulong)OrderGetInteger(ORDER_MAGIC) == this.magicNumber
                && (ulong)OrderGetInteger(ORDER_POSITION_ID) == fromPosition.identifier) {
            return true;
        }
        // 応答欠落でticket未保存でも、まだ履歴へ移っていない部分注文を照合する。
        for (int i = 0; i < OrdersTotal(); i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                return false;
            }
            if (OrderGetString(ORDER_SYMBOL) == this.symbolName
                    && (ulong)OrderGetInteger(ORDER_MAGIC) == this.magicNumber
                    && OrderGetString(ORDER_COMMENT) == this.entryComment()
                    && (ulong)OrderGetInteger(ORDER_POSITION_ID) == fromPosition.identifier) {
                this.trade.entryOrderTicket = H1EaTextUtil::ticket(ticket);
                return true;
            }
        }
        ulong entryDeal = H1EaTextUtil::parseTicket(this.trade.entryDealTicket);
        if (entryDeal > 0 && HistoryDealSelect(entryDeal)
                && (ulong)HistoryDealGetInteger(entryDeal, DEAL_POSITION_ID) == fromPosition.identifier
                && HistoryDealGetString(entryDeal, DEAL_SYMBOL) == this.symbolName
                && (ulong)HistoryDealGetInteger(entryDeal, DEAL_MAGIC) == this.magicNumber) {
            this.trade.entryOrderTicket = H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(entryDeal, DEAL_ORDER));
            return true;
        }
        if (!HistorySelectByPosition(fromPosition.identifier)) {
            return false;
        }
        for (int i = 0; i < HistoryOrdersTotal(); i++) {
            ulong ticket = HistoryOrderGetTicket(i);
            if (ticket == 0 || HistoryOrderGetString(ticket, ORDER_SYMBOL) != this.symbolName
                    || (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != this.magicNumber) {
                continue;
            }
            if (H1EaTextUtil::ticket(ticket) == this.trade.entryOrderTicket
                    || HistoryOrderGetString(ticket, ORDER_COMMENT) == this.entryComment()) {
                this.trade.entryOrderTicket = H1EaTextUtil::ticket(ticket);
                return true;
            }
        }
        return false;
    }

    /**
     * EntryのDB要求が存在する場合だけ初期SLの設定元を証明する。
     */
    bool hasEntryAction() {
        if (this.entryActionUid != "") {
            return true;
        }
        H1EaTradeEventEntity event;
        bool found = false;
        if (this.persistence.loadLatestTradeEvent(this.trade.id, "ENTRY_REQUEST", event, found) && found) {
            this.entryActionUid = event.actionUid;
            return this.entryActionUid != "";
        }
        return false;
    }

    /**
     * broker SLの由来を価格だけから推測しない。
     */
    string identifyStopLoss(const double fromActual) {
        if (fromActual <= 0.0) {
            return "NONE";
        }
        if (this.externalStopLoss > 0.0
                && MathAbs(fromActual - this.externalStopLoss) <= this.tickSize * 0.5) {
            return "EXTERNAL";
        }
        if (this.trade.currentStopLoss > 0.0
                && MathAbs(fromActual - this.trade.currentStopLoss) <= this.tickSize * 0.5
                && this.trade.stopLossSource != "NONE") {
            return this.trade.stopLossSource;
        }
        if (this.trade.requestedStopLoss > 0.0
                && MathAbs(fromActual - this.trade.requestedStopLoss) <= this.tickSize * 0.5
                && this.trade.lastAppliedTrailStopLoss <= 0.0 && this.hasEntryAction()) {
            return "INITIAL_STOP_LOSS";
        }
        return "UNKNOWN";
    }

    /**
     * 未完了SL要求を先に解決し、削除・緩和された保護水準を復元する。
     */
    void syncStopLoss(PositionSnapshot &fromPosition) {
        string source = this.identifyStopLoss(fromPosition.stopLoss);
        if (this.trade.pendingStopLossActionUid != "") {
            if (H1EaProtectionPolicy::canResolveModify(
                    this.confirmedModifyActionUid == this.trade.pendingStopLossActionUid,
                    fromPosition.stopLoss, this.trade.pendingStopLoss, this.tickSize)) {
                this.resolveModifyResult(fromPosition, "RECONCILIATION", this.confirmedModifyRetcode);
            } else {
                // 古いSLを読めても、遅延中の変更要求が不成立とは断定しない。
                this.trade.status = "RECOVERY_REQUIRED";
                this.trade.lastError = "SL_ACCEPTANCE_UNRESOLVED";
            }
            return;
        }
        this.trade.currentStopLoss = fromPosition.stopLoss;
        this.trade.stopLossSource = source;
        if (this.trade.status != "OPEN" && this.trade.status != "OPEN_PARTIAL") {
            return;
        }
        if (this.trade.pendingStopLoss > 0.0 && H1EaProtectionPolicy::protects(fromPosition.isBuy,
                fromPosition.stopLoss, this.trade.pendingStopLoss, this.tickSize)) {
            this.clearPending();
        }
        double protectedLevel = this.trade.requestedStopLoss;
        string restoreKind = "INITIAL_RESTORE";
        if (this.trade.status == "OPEN" && this.trade.lastAppliedTrailStopLoss > 0.0 && (protectedLevel <= 0.0
                || H1EaProtectionPolicy::protects(fromPosition.isBuy,
                    this.trade.lastAppliedTrailStopLoss, protectedLevel, this.tickSize))) {
            protectedLevel = this.trade.lastAppliedTrailStopLoss;
            restoreKind = "TRAIL_RESTORE";
        }
        if (this.trade.pendingStopLoss > 0.0 && (protectedLevel <= 0.0
                || H1EaProtectionPolicy::protects(fromPosition.isBuy,
                    this.trade.pendingStopLoss, protectedLevel, this.tickSize))) {
            return;
        }
        if (protectedLevel <= 0.0 || H1EaProtectionPolicy::protects(fromPosition.isBuy,
                fromPosition.stopLoss, protectedLevel, this.tickSize)) {
            return;
        }
        this.clearPending();
        this.trade.pendingStopLossKind = restoreKind;
        this.trade.pendingStopLoss = protectedLevel;
        if (restoreKind == "TRAIL_RESTORE") {
            this.trade.pendingStopLossH1BarTime = this.trade.lastAppliedTrailH1BarTime;
            this.trade.pendingStopLossPivotTime = this.trade.lastAppliedTrailPivotTime;
            this.trade.pendingStopLossPivotRate = this.trade.lastAppliedTrailPivotRate;
            this.trade.pendingStopLossLatestTime = this.trade.lastAppliedTrailLatestTime;
        }
    }

    /**
     * broker再取得に成功したSL変更actionだけ結果を確定する。
     */
    void resolveModifyResult(PositionSnapshot &fromPosition, const string fromSource,
            const int fromRetcode, const bool fromAllowOwnSource = true) {
        H1EaTradeEventEntity event;
        this.newEvent("SL_MODIFY_RESULT", event);
        event.eventSource = fromSource;
        event.actionUid = this.trade.pendingStopLossActionUid;
        event.eventUid = event.actionUid + "|RESULT";
        this.copyPendingToEvent(event, true);
        event.retcode = fromRetcode;
        event.confirmedStopLoss = fromPosition.stopLoss;
        event.isConfirmedStopLossPresent = 0;
        if (fromPosition.stopLoss > 0.0) {
            event.isConfirmedStopLossPresent = 1;
        }
        string source = this.identifyStopLoss(fromPosition.stopLoss);
        bool protectedEnough = H1EaProtectionPolicy::protects(fromPosition.isBuy,
            fromPosition.stopLoss, this.trade.pendingStopLoss, this.tickSize);
        bool actionProven = false;
        H1EaTradeEventEntity request;
        bool found = false;
        if (this.persistence.loadEvent(event.actionUid, "SL_MODIFY_REQUEST", request, found) && found) {
            actionProven = request.positionIdentifier == this.trade.positionIdentifier
                && MathAbs(request.stopLoss - fromPosition.stopLoss) <= this.tickSize * 0.5;
        }
        if (!actionProven) {
            for (int i = 0; i < ArraySize(this.saveQueue); i++) {
                if (this.saveQueue[i].event.actionUid == event.actionUid
                        && this.saveQueue[i].event.eventType == "SL_MODIFY_REQUEST") {
                    actionProven = MathAbs(this.saveQueue[i].event.stopLoss - fromPosition.stopLoss) <= this.tickSize * 0.5;
                    break;
                }
            }
        }
        if (protectedEnough && actionProven && fromAllowOwnSource) {
            if (this.trade.pendingStopLossKind == "INITIAL_RESTORE") {
                source = "INITIAL_STOP_LOSS";
            } else {
                source = "H1_ZIGZAG_TRAIL";
                this.trade.lastAppliedTrailH1BarTime = this.trade.pendingStopLossH1BarTime;
                this.trade.lastAppliedTrailStopLoss = this.trade.pendingStopLoss;
                this.trade.lastAppliedTrailPivotTime = this.trade.pendingStopLossPivotTime;
                this.trade.lastAppliedTrailPivotRate = this.trade.pendingStopLossPivotRate;
                this.trade.lastAppliedTrailLatestTime = this.trade.pendingStopLossLatestTime;
            }
        }
        this.trade.currentStopLoss = fromPosition.stopLoss;
        this.trade.stopLossSource = source;
        event.stopLossSource = source;
        if (protectedEnough) {
            this.clearPending();
        } else {
            this.trade.pendingStopLossActionUid = "";
            event.message = "BROKER_SL_NOT_APPLIED";
        }
        this.confirmedModifyActionUid = "";
        this.confirmedModifyRetcode = -1;
        this.pendingModifyRequestId = 0;
        if (this.trade.status == "RECOVERY_REQUIRED") {
            this.trade.status = "OPEN";
        }
        this.saveEvent(event, false);
    }

    /**
     * 識別・SL取得不能ではResultを作らずactionを残す。
     */
    void modifyStopLoss(PositionSnapshot &fromPosition) {
        H1EaTradeEventEntity event;
        this.newAction("SL_MODIFY", event);
        this.copyPendingToEvent(event, true);
        event.previousStopLoss = fromPosition.stopLoss;
        this.trade.pendingStopLossActionUid = event.actionUid;
        if (!this.saveEvent(event, true) || !this.hasManagementAuthority()) {
            return;
        }
        // DB待ち中の手動変更・価格変動を反映し、古いSLで保護を緩めない。
        PositionSnapshot currentPosition;
        int currentCount = 0;
        MqlTick currentTick;
        if (!this.readPosition(currentPosition, currentCount) || currentCount != 1
                || currentPosition.identifier != fromPosition.identifier || !this.readTick(currentTick)) {
            this.requireRecovery("SL_PRE_SEND_BROKER_UNAVAILABLE");
            return;
        }
        if (H1EaProtectionPolicy::protects(currentPosition.isBuy, currentPosition.stopLoss,
                event.stopLoss, this.tickSize)) {
            this.resolveModifyResult(currentPosition, "RECONCILIATION", 0, false);
            return;
        }
        if (currentPosition.ticket != fromPosition.ticket) {
            this.resolveModifyResult(currentPosition, "RECONCILIATION", (int)TRADE_RETCODE_PRICE_CHANGED, false);
            return;
        }
        if (H1EaProtectionPolicy::crossed(currentPosition.isBuy, currentTick.bid, currentTick.ask, event.stopLoss)) {
            this.resolveModifyResult(currentPosition, "RECONCILIATION", (int)TRADE_RETCODE_PRICE_CHANGED, false);
            this.beginClose(currentPosition, iTime(this.symbolName, PERIOD_H1, 0));
            return;
        }
        if (!H1EaProtectionPolicy::canModify(currentPosition.isBuy, currentTick.bid, currentTick.ask,
                event.stopLoss, SymbolInfoDouble(this.symbolName, SYMBOL_POINT), this.tickSize,
                SymbolInfoInteger(this.symbolName, SYMBOL_TRADE_STOPS_LEVEL),
                SymbolInfoInteger(this.symbolName, SYMBOL_TRADE_FREEZE_LEVEL))) {
            this.resolveModifyResult(currentPosition, "RECONCILIATION", (int)TRADE_RETCODE_INVALID_STOPS, false);
            return;
        }
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);
        request.action = TRADE_ACTION_SLTP;
        request.symbol = this.symbolName;
        request.magic = this.magicNumber;
        request.position = currentPosition.ticket;
        request.sl = event.stopLoss;
        // TPは本EAでは設定しないが、外部から設定済みのTPを勝手に解除しない。
        if (!PositionSelectByTicket(currentPosition.ticket) || !PositionGetDouble(POSITION_TP, request.tp)) {
            this.requireRecovery("SL_PRE_SEND_POSITION_CHANGED");
            return;
        }
        this.lastSendTick = H1EaClock::milliseconds();
        if (!this.hasManagementAuthority()) {
            return;
        }
        bool sent = OrderSend(request, result);
        this.pendingModifyRequestId = result.request_id;
        if (!H1EaProtectionPolicy::isUnknownRetcode(result.retcode) && result.retcode != TRADE_RETCODE_PLACED) {
            this.confirmedModifyActionUid = event.actionUid;
            this.confirmedModifyRetcode = (int)result.retcode;
        }
        PositionSnapshot confirmed;
        int count = 0;
        if (!this.readPosition(confirmed, count) || count != 1
                || confirmed.identifier != fromPosition.identifier) {
            this.requireRecovery("SL_RESULT_BROKER_UNAVAILABLE");
            return;
        }
        if (!sent) {
            this.trade.lastError = "SL_MODIFY_SEND: " + result.comment;
        }
        if (!H1EaProtectionPolicy::canResolveModify(this.confirmedModifyActionUid == event.actionUid,
                confirmed.stopLoss, event.stopLoss, this.tickSize)) {
            this.requireRecovery("SL_ACCEPTANCE_UNRESOLVED");
            return;
        }
        this.resolveModifyResult(confirmed, "EA", (int)result.retcode);
    }

    /**
     * 候補を跨いだ内部理由を保存し、全量決済を開始する。
     */
    void beginClose(PositionSnapshot &fromPosition, const datetime fromH1Bar) {
        this.trade.exitIntentReason = "H1_ZIGZAG_TRAIL_CROSSED";
        if (this.trade.pendingStopLossKind == "INITIAL_RESTORE") {
            this.trade.exitIntentReason = "INITIAL_STOP_LOSS_CROSSED";
        }
        H1EaTradeEventEntity event;
        this.newAction("EXIT", event);
        this.exitActionUid = event.actionUid;
        this.copyPendingToEvent(event, false);
        event.h1BarTime = fromH1Bar;
        event.exitIntentReason = this.trade.exitIntentReason;
        event.volume = fromPosition.volume;
        this.trade.status = "CLOSE_PENDING";
        this.trade.exitRequestedServerTime = TimeCurrent();
        this.trade.exitRetcode = -1;
        this.trade.exitOrderTicket = "";
        this.clearPending();
        this.setBlockedEntryBar(fromH1Bar);
        if (!this.saveEvent(event, true) || !this.hasManagementAuthority()) {
            return;
        }
        this.sendClose(fromPosition, event);
    }

    /**
     * 部分決済の残量を終端注文確認後だけ再送する。
     */
    void retryClose(const datetime fromH1Bar) {
        if (this.hasActiveCloseOrder()) {
            return;
        }
        bool mayRetry = false;
        if (this.trade.exitRetcode >= 0
                && !H1EaProtectionPolicy::isUnknownRetcode((uint)this.trade.exitRetcode)
                && !H1EaProtectionPolicy::isAcceptedRetcode((uint)this.trade.exitRetcode)) {
            mayRetry = true;
        }
        if (this.trade.exitOrderTicket != "") {
            ulong orderTicket = H1EaTextUtil::parseTicket(this.trade.exitOrderTicket);
            if (HistoryOrderSelect(orderTicket)) {
                mayRetry = H1EaProtectionPolicy::isTerminalOrder(HistoryOrderGetInteger(orderTicket, ORDER_STATE));
            }
        }
        if (!mayRetry) {
            // 無応答・再起動前未送信を推測で再送しない。
            return;
        }
        PositionSnapshot position;
        int count = 0;
        if (!this.readPosition(position, count) || count != 1
                || H1EaTextUtil::ticket(position.identifier) != this.trade.positionIdentifier) {
            this.reconcile();
            return;
        }
        H1EaTradeEventEntity event;
        this.newAction("EXIT", event);
        this.exitActionUid = event.actionUid;
        event.h1BarTime = fromH1Bar;
        event.exitIntentReason = this.trade.exitIntentReason;
        event.volume = position.volume;
        this.trade.status = "CLOSE_PENDING";
        this.trade.exitRequestedServerTime = TimeCurrent();
        this.trade.exitRetcode = -1;
        this.trade.exitOrderTicket = "";
        this.setBlockedEntryBar(fromH1Bar);
        if (!this.saveEvent(event, true) || !this.hasManagementAuthority()) {
            return;
        }
        this.sendClose(position, event);
    }

    /**
     * 同じPositionへの有効決済注文を確認する。
     */
    bool hasActiveCloseOrder() {
        for (int i = 0; i < OrdersTotal(); i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                return true;
            }
            if (OrderGetString(ORDER_SYMBOL) != this.symbolName) {
                continue;
            }
            if (H1EaTextUtil::ticket((ulong)OrderGetInteger(ORDER_POSITION_ID)) == this.trade.positionIdentifier
                    && H1EaTextUtil::ticket(ticket) != this.trade.entryOrderTicket) {
                // 他の決済注文は待機対象だが、現在actionの終端証拠へ流用しない。
                if (this.exitActionUid != "" && (ulong)OrderGetInteger(ORDER_MAGIC) == this.magicNumber
                        && OrderGetString(ORDER_COMMENT) == this.closeComment(this.exitActionUid)) {
                    this.trade.exitOrderTicket = H1EaTextUtil::ticket(ticket);
                }
                return true;
            }
        }
        return false;
    }

    /**
     * Runをまたいでも曖昧にならない短い決済コメント。
     */
    string closeComment(const string fromActionUid) {
        return "MstngH1C:" + StringSubstr(H1EaTextUtil::hash(fromActionUid), 0, 20);
    }

    /**
     * 応答欠落後の決済注文を最後の要求へ一意に対応付ける。
     */
    void reconcileCloseOrder() {
        H1EaTradeEventEntity requested;
        bool found = false;
        // 書込みだけ失敗するDBでは、永続行より新しい未保存intentが存在し得る。
        for (int i = ArraySize(this.saveQueue) - 1; i >= 0; i--) {
            if (this.saveQueue[i].trade.id == this.trade.id
                    && this.saveQueue[i].event.eventType == "EXIT_REQUEST"
                    && (this.exitActionUid == "" || this.saveQueue[i].event.actionUid == this.exitActionUid)) {
                requested = this.saveQueue[i].event;
                found = true;
                break;
            }
        }
        if (!found) {
            if (this.exitActionUid != "") {
                // 現在actionが既知なら、別の古い「最新DB行」へ戻さない。
                if (!this.persistence.loadEvent(this.exitActionUid, "EXIT_REQUEST", requested, found) || !found) {
                    return;
                }
            } else if (!this.persistence.loadLatestTradeEvent(this.trade.id, "EXIT_REQUEST", requested, found) || !found) {
                return;
            }
        }
        if (this.exitActionUid != "" && requested.actionUid != this.exitActionUid) {
            return;
        }
        this.exitActionUid = requested.actionUid;
        string comment = this.closeComment(requested.actionUid);
        ulong matched = 0;
        for (int i = 0; i < OrdersTotal(); i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                return;
            }
            if (OrderGetString(ORDER_SYMBOL) == this.symbolName
                    && (ulong)OrderGetInteger(ORDER_MAGIC) == this.magicNumber
                    && OrderGetString(ORDER_COMMENT) == comment
                    && H1EaTextUtil::ticket((ulong)OrderGetInteger(ORDER_POSITION_ID)) == this.trade.positionIdentifier) {
                matched = ticket;
                break;
            }
        }
        if (matched == 0 && this.selectTradeHistory()) {
            for (int i = 0; i < HistoryOrdersTotal(); i++) {
                ulong ticket = HistoryOrderGetTicket(i);
                if (HistoryOrderGetString(ticket, ORDER_SYMBOL) == this.symbolName
                        && (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) == this.magicNumber
                        && HistoryOrderGetString(ticket, ORDER_COMMENT) == comment
                        && H1EaTextUtil::ticket((ulong)HistoryOrderGetInteger(ticket, ORDER_POSITION_ID)) == this.trade.positionIdentifier) {
                    matched = ticket;
                    break;
                }
            }
        }
        if (matched == 0) {
            return;
        }
        this.trade.exitOrderTicket = H1EaTextUtil::ticket(matched);
        H1EaTradeEventEntity existing;
        bool resultFound = false;
        if (!this.persistence.loadEvent(requested.actionUid, "EXIT_RESULT", existing, resultFound) || resultFound) {
            return;
        }
        H1EaTradeEventEntity event;
        this.newEvent("EXIT_RESULT", event);
        event.actionUid = requested.actionUid;
        event.eventUid = event.actionUid + "|RESULT";
        event.eventSource = "RECONCILIATION";
        event.orderTicket = this.trade.exitOrderTicket;
        event.exitIntentReason = this.trade.exitIntentReason;
        event.message = "BROKER_ORDER_MATCHED_TO_EXIT_REQUEST";
        this.saveEvent(event, false);
    }

    /**
     * 確定したEXIT_REQUESTだけをbrokerへ送る。
     */
    void sendClose(PositionSnapshot &fromPosition, H1EaTradeEventEntity &fromEvent) {
        PositionSnapshot currentPosition;
        int positionCount = 0;
        if (!this.readPosition(currentPosition, positionCount) || positionCount != 1
                || currentPosition.identifier != fromPosition.identifier || this.hasActiveCloseOrder()) {
            // 送信済みと推測せず、Position消滅・他注文を照合するまで保持する。
            this.requireRecovery("CLOSE_PRE_SEND_POSITION_CHANGED");
            return;
        }
        MqlTick marketTick;
        if (!this.readTick(marketTick)) {
            this.trade.lastError = "CLOSE_PRICE_UNAVAILABLE";
            this.trade.exitRetcode = (int)TRADE_RETCODE_PRICE_OFF;
        } else {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);
            request.action = TRADE_ACTION_DEAL;
            request.symbol = this.symbolName;
            request.magic = this.magicNumber;
            request.position = currentPosition.ticket;
            request.volume = currentPosition.volume;
            request.deviation = 10;
            request.type_filling = this.fillingType();
            request.comment = this.closeComment(fromEvent.actionUid);
            request.type = ORDER_TYPE_BUY;
            request.price = marketTick.ask;
            if (currentPosition.isBuy) {
                request.type = ORDER_TYPE_SELL;
                request.price = marketTick.bid;
            }
            this.lastSendTick = H1EaClock::milliseconds();
            if (!this.hasManagementAuthority()) {
                return;
            }
            bool sent = OrderSend(request, result);
            this.trade.exitRetcode = (int)result.retcode;
            if (result.order > 0) {
                this.trade.exitOrderTicket = H1EaTextUtil::ticket(result.order);
            }
            if (result.deal > 0) {
                this.trade.exitDealTicket = H1EaTextUtil::ticket(result.deal);
            }
            if (!sent || !H1EaProtectionPolicy::isAcceptedRetcode(result.retcode)) {
                this.trade.lastError = "CLOSE_SEND: " + result.comment;
            }
        }
        H1EaTradeEventEntity event;
        this.newEvent("EXIT_RESULT", event);
        event.actionUid = fromEvent.actionUid;
        event.eventUid = event.actionUid + "|RESULT";
        event.retcode = this.trade.exitRetcode;
        event.orderTicket = this.trade.exitOrderTicket;
        event.dealTicket = this.trade.exitDealTicket;
        event.exitIntentReason = this.trade.exitIntentReason;
        event.volume = currentPosition.volume;
        event.message = this.trade.lastError;
        this.saveEvent(event, false);
        this.reconcile();
    }

    /**
     * 部分Entryの残注文を取消し、不足数量を追加しない。
     */
    void cancelEntryRemainder() {
        if (!this.entryOrderIsActive()) {
            this.reconcile();
            return;
        }
        if (this.orderReadFailed || this.trade.entryOrderTicket == "") {
            this.requireRecovery("ENTRY_CANCEL_ORDER_UNAVAILABLE");
            return;
        }
        H1EaTradeEventEntity event;
        this.newEvent("ERROR", event);
        this.actionSequence++;
        event.eventUid = "H1_EA_CANCEL_V1|" + this.runUid + "|"
            + IntegerToString(this.trade.id) + "|" + IntegerToString(this.actionSequence) + "|REQUEST";
        event.orderTicket = this.trade.entryOrderTicket;
        event.message = "ENTRY_REMAINDER_CANCEL_REQUEST";
        if (!this.saveEvent(event, true) || !this.hasManagementAuthority()) {
            return;
        }
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);
        request.action = TRADE_ACTION_REMOVE;
        request.order = H1EaTextUtil::parseTicket(this.trade.entryOrderTicket);
        request.symbol = this.symbolName;
        request.magic = this.magicNumber;
        this.lastSendTick = H1EaClock::milliseconds();
        this.entryCancelAttempted = true;
        if (!this.hasManagementAuthority()) {
            return;
        }
        bool sent = OrderSend(request, result);
        event.id = 0;
        event.sequence = 0;
        StringReplace(event.eventUid, "|REQUEST", "|RESULT");
        event.retcode = (int)result.retcode;
        event.message = "ENTRY_REMAINDER_CANCEL_RESULT " + result.comment;
        if (!sent) {
            this.trade.lastError = event.message;
        }
        this.saveEvent(event, false);
        this.reconcile();
    }

    /**
     * DBにない自EA Positionは履歴事実だけから回復行を作る。
     */
    void createRecoveryTrade(PositionSnapshot &fromPosition) {
        this.entryActionUid = "";
        this.externalStopLoss = 0.0;
        this.trade.reset();
        this.trade.createdRunId = this.runId;
        this.trade.contextKey = this.contextKey;
        this.trade.origin = "RECOVERED";
        this.trade.status = "RECOVERY_REQUIRED";
        this.trade.side = "SELL";
        if (fromPosition.isBuy) {
            this.trade.side = "BUY";
        }
        this.trade.positionIdentifier = H1EaTextUtil::ticket(fromPosition.identifier);
        this.trade.positionTicket = H1EaTextUtil::ticket(fromPosition.ticket);
        this.trade.openedAtMsc = fromPosition.openTimeMilliseconds;
        this.trade.openPrice = fromPosition.openPrice;
        this.trade.openedVolume = fromPosition.volume;
        this.trade.remainingPositionVolume = fromPosition.volume;
        this.trade.currentStopLoss = fromPosition.stopLoss;
        this.trade.stopLossSource = "NONE";
        if (fromPosition.stopLoss > 0.0) {
            this.trade.stopLossSource = "UNKNOWN";
        }
        this.trade.createdAt = TimeLocal();
        this.active = true;
        this.recoveryCommitPending = true;
        bool historyFound = this.aggregateDeals(false);
        if (historyFound && this.trade.requestedStopLoss > 0.0) {
            this.trade.status = "OPEN";
            this.syncStopLoss(fromPosition);
        } else {
            this.trade.lastError = "RECOVERED_INITIAL_SL_UNAVAILABLE";
        }
        H1EaTradeEventEntity event;
        this.newEvent("RECOVERY", event);
        this.recoveryEvent(event);
        if (this.trade.id > 0) {
            this.aggregateDeals(false);
        }
    }

    /**
     * Position消滅を注文・約定履歴へ照合して終端状態を確定する。
     */
    void reconcileMissingPosition() {
        if (this.entryOrderIsActive()) {
            if (this.orderReadFailed) {
                this.requireRecovery("BROKER_ORDER_UNAVAILABLE");
                return;
            }
            if (this.trade.positionIdentifier != "") {
                // 決済後も残Entryが有効ならCLOSEDにせず取消を継続する。
                this.trade.status = "OPEN_PARTIAL";
                this.trade.remainingPositionVolume = 0.0;
                this.clearPending();
                H1EaTradeEventEntity event;
                this.newEvent("RECOVERY", event);
                this.recoveryEvent(event);
            } else {
                this.trade.status = "OPEN_PENDING";
            }
            return;
        }
        if (this.trade.positionIdentifier != "") {
            if (this.trade.exitIntentReason != "") {
                this.reconcileCloseOrder();
            }
            if (this.aggregateDeals(true)) {
                return;
            }
            this.requireRecovery("POSITION_AND_EXIT_HISTORY_UNAVAILABLE");
            return;
        }
        if (this.trade.entryOrderTicket == "" && this.trade.entryRequestedServerTime > 0
                && HistorySelect((datetime)MathMax(0, this.trade.entryRequestedServerTime - 60), TimeCurrent() + 60)) {
            for (int i = 0; i < HistoryOrdersTotal(); i++) {
                ulong ticket = HistoryOrderGetTicket(i);
                if (HistoryOrderGetString(ticket, ORDER_SYMBOL) == this.symbolName
                        && (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) == this.magicNumber
                        && HistoryOrderGetString(ticket, ORDER_COMMENT) == this.entryComment()) {
                    this.trade.entryOrderTicket = H1EaTextUtil::ticket(ticket);
                    break;
                }
            }
        }
        ulong entryOrder = H1EaTextUtil::parseTicket(this.trade.entryOrderTicket);
        if (entryOrder > 0 && HistoryOrderSelect(entryOrder)) {
            ulong identifier = (ulong)HistoryOrderGetInteger(entryOrder, ORDER_POSITION_ID);
            if (identifier > 0) {
                this.trade.positionIdentifier = H1EaTextUtil::ticket(identifier);
                if (this.aggregateDeals(true)) {
                    return;
                }
            }
            long state = HistoryOrderGetInteger(entryOrder, ORDER_STATE);
            if (H1EaProtectionPolicy::isTerminalOrder(state) && state != ORDER_STATE_FILLED
                    && identifier == 0) {
                this.trade.status = "OPEN_FAILED";
                H1EaTradeEventEntity event;
                this.newEvent("RECOVERY", event);
                event.message = "ENTRY_TERMINAL_WITHOUT_FILL";
                this.recoveryEvent(event);
                this.active = false;
                return;
            }
        }
        // 受付不明のOPENは再送せず、履歴が揃うまでactive枠を保持する。
        this.requireRecovery("ENTRY_ACCEPTANCE_UNRESOLVED");
    }

    /**
     * broker定義のdeal理由を保存用文字列へ変換する。
     */
    string brokerReason(const long fromReason) {
        string result = EnumToString((ENUM_DEAL_REASON)fromReason);
        StringReplace(result, "DEAL_REASON_", "");
        return result;
    }

    /**
     * 単一dealの通知を一意なbrokerキーで追記する。
     */
    void recordDeal(const ulong fromTicket, const string fromSource) {
        if (this.trade.id <= 0) {
            return;
        }
        H1EaTradeEventEntity event;
        this.newEvent("DEAL_ADD", event);
        event.eventSource = fromSource;
        event.transactionType = TRADE_TRANSACTION_DEAL_ADD;
        event.dealTicket = H1EaTextUtil::ticket(fromTicket);
        event.orderTicket = H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(fromTicket, DEAL_ORDER));
        event.positionIdentifier = H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(fromTicket, DEAL_POSITION_ID));
        event.brokerTimeMsc = HistoryDealGetInteger(fromTicket, DEAL_TIME_MSC);
        if (event.brokerTimeMsc <= 0) {
            return;
        }
        event.dealScopeKey = "LIVE|" + AccountInfoString(ACCOUNT_SERVER) + "|"
            + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + event.dealTicket;
        if (MQLInfoInteger(MQL_TESTER)) {
            event.dealScopeKey = "TESTER|" + this.runUid + "|" + event.dealTicket;
        }
        event.eventUid = event.dealScopeKey;
        event.side = "SELL";
        if (HistoryDealGetInteger(fromTicket, DEAL_TYPE) == DEAL_TYPE_BUY) {
            event.side = "BUY";
        }
        event.volume = HistoryDealGetDouble(fromTicket, DEAL_VOLUME);
        event.price = HistoryDealGetDouble(fromTicket, DEAL_PRICE);
        event.brokerReason = this.brokerReason(HistoryDealGetInteger(fromTicket, DEAL_REASON));
        long entry = HistoryDealGetInteger(fromTicket, DEAL_ENTRY);
        event.message = EnumToString((ENUM_DEAL_ENTRY)entry);
        if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT) {
            event.exitIntentReason = this.trade.exitIntentReason;
            event.closeReason = H1EaProtectionPolicy::closeReason(this.trade.exitIntentReason,
                this.trade.stopLossSource, event.brokerReason);
            if (this.trade.exitIntentReason == "" && event.brokerReason == "EXPERT"
                    && (ulong)HistoryDealGetInteger(fromTicket, DEAL_MAGIC) != this.magicNumber) {
                event.closeReason = "EXTERNAL_CLOSE";
            }
        }
        this.saveEvent(event, false);
    }

    /**
     * Positionに属する全dealを再集計し、通知の重複で加算しない。
     */
    bool aggregateDeals(const bool fromPositionAbsent) {
        ulong identifier = H1EaTextUtil::parseTicket(this.trade.positionIdentifier);
        if (identifier == 0 || !HistorySelectByPosition(identifier)) {
            return false;
        }
        double entryVolume = 0.0;
        double exitVolume = 0.0;
        double entryValue = 0.0;
        double exitValue = 0.0;
        double profit = 0.0;
        double commission = 0.0;
        double swap = 0.0;
        double fee = 0.0;
        long firstTime = 0;
        long lastTime = 0;
        ulong firstDeal = 0;
        ulong lastDeal = 0;
        string lastReason = "";
        ulong tickets[];
        int total = HistoryDealsTotal();
        if (ArrayResize(tickets, total) != total) {
            this.trade.lastError = "DEAL_HISTORY_MEMORY_UNAVAILABLE";
            this.trade.status = "RECOVERY_REQUIRED";
            return false;
        }
        for (int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (ticket == 0) {
                this.trade.lastError = "DEAL_HISTORY_UNAVAILABLE";
                this.trade.status = "RECOVERY_REQUIRED";
                return false;
            }
            tickets[i] = ticket;
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            commission += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            swap += HistoryDealGetDouble(ticket, DEAL_SWAP);
            fee += HistoryDealGetDouble(ticket, DEAL_FEE);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            if (type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) {
                continue;
            }
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            long timeMsc = HistoryDealGetInteger(ticket, DEAL_TIME_MSC);
            if (entry == DEAL_ENTRY_IN) {
                entryVolume += volume;
                entryValue += volume * price;
                if (firstTime == 0 || timeMsc < firstTime) {
                    firstTime = timeMsc;
                    firstDeal = ticket;
                }
            } else if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) {
                exitVolume += volume;
                exitValue += volume * price;
                if (timeMsc >= lastTime) {
                    lastTime = timeMsc;
                    lastDeal = ticket;
                    lastReason = this.brokerReason(HistoryDealGetInteger(ticket, DEAL_REASON));
                }
            } else if (entry == DEAL_ENTRY_INOUT) {
                // hedgingでは想定外。反転を推測して数量を二重計上しない。
                this.trade.lastError = "UNEXPECTED_INOUT_DEAL";
                this.trade.status = "RECOVERY_REQUIRED";
            }
        }
        if (entryVolume <= 0.0) {
            return false;
        }
        this.trade.openPrice = entryValue / entryVolume;
        this.trade.openedVolume = entryVolume;
        this.trade.openedAtMsc = firstTime;
        this.trade.entryDealTicket = H1EaTextUtil::ticket(firstDeal);
        this.trade.profit = profit;
        this.trade.commission = commission;
        this.trade.swap = swap;
        this.trade.fee = fee;
        ulong initialOrder = (ulong)HistoryDealGetInteger(firstDeal, DEAL_ORDER);
        this.trade.entryOrderTicket = H1EaTextUtil::ticket(initialOrder);
        if (this.trade.requestedStopLoss <= 0.0 && initialOrder > 0) {
            this.trade.requestedStopLoss = HistoryOrderGetDouble(initialOrder, ORDER_SL);
        }
        if (exitVolume > 0.0) {
            this.trade.closePrice = exitValue / exitVolume;
            this.trade.exitDealTicket = H1EaTextUtil::ticket(lastDeal);
            this.trade.brokerCloseReason = lastReason;
        }
        if (fromPositionAbsent && exitVolume + 0.00000001 >= entryVolume && lastTime > 0) {
            this.trade.closedAtMsc = lastTime;
            this.trade.remainingPositionVolume = 0.0;
            this.trade.closeReason = H1EaProtectionPolicy::closeReason(this.trade.exitIntentReason,
                this.trade.stopLossSource, lastReason);
            if (this.trade.exitIntentReason == "" && lastReason == "EXPERT"
                    && (ulong)HistoryDealGetInteger(lastDeal, DEAL_MAGIC) != this.magicNumber) {
                this.trade.closeReason = "EXTERNAL_CLOSE";
            }
            this.trade.status = "CLOSED";
            this.clearPending();
        }
        for (int i = 0; i < total; i++) {
            this.recordDeal(tickets[i], "RECONCILIATION");
        }
        if (this.trade.status == "CLOSED") {
            H1EaTradeEventEntity event;
            this.newEvent("RECOVERY", event);
            event.closeReason = this.trade.closeReason;
            event.brokerReason = this.trade.brokerCloseReason;
            this.recoveryEvent(event);
            this.active = false;
            return true;
        }
        return !fromPositionAbsent;
    }

    /**
     * 不明状態ではbroker照合以外を停止する。
     */
    void requireRecovery(const string fromReason) {
        this.trade.status = "RECOVERY_REQUIRED";
        this.trade.lastError = fromReason;
        H1EaTradeEventEntity event;
        this.newEvent("RECOVERY", event);
        event.message = fromReason;
        this.recoveryEvent(event);
    }

    /**
     * NULLと空文字を区別する保存契約の文字列表現。
     */
    string optionalText(const string fromValue) {
        if (fromValue == "") {
            return "~";
        }
        return fromValue;
    }

    /**
     * 任意の正時刻・識別数値を文字列へ変換する。
     */
    string optionalInteger(const long fromValue) {
        if (fromValue <= 0) {
            return "~";
        }
        return IntegerToString(fromValue);
    }

    /**
     * 価格の桁数をシンボルのDigitsに固定する。
     */
    string optionalPrice(const double fromValue) {
        if (fromValue <= 0.0 || fromValue == EMPTY_VALUE) {
            return "~";
        }
        return DoubleToString(fromValue, (int)SymbolInfoInteger(this.symbolName, SYMBOL_DIGITS));
    }

    /**
     * 有効な数量0と未取得値を区別する。
     */
    string optionalVolume(const double fromValue) {
        if (fromValue == EMPTY_VALUE) {
            return "~";
        }
        return DoubleToString(fromValue, 8);
    }

    /**
     * PositionまたはEntry要求scopeのbroker履歴を選択する。
     */
    bool selectTradeHistory() {
        if (this.trade.positionIdentifier != "") {
            return HistorySelectByPosition(H1EaTextUtil::parseTicket(this.trade.positionIdentifier));
        }
        if (this.trade.entryRequestedServerTime > 0) {
            return HistorySelect((datetime)MathMax(0, this.trade.entryRequestedServerTime - 60), TimeCurrent() + 60);
        }
        return false;
    }

    /**
     * 履歴選択に複数取引が含まれる場合に現在のscopeだけを残す。
     */
    bool historyOrderBelongs(const ulong fromTicket) {
        if (HistoryOrderGetString(fromTicket, ORDER_SYMBOL) != this.symbolName) {
            return false;
        }
        if (this.trade.positionIdentifier != "") {
            return H1EaTextUtil::ticket((ulong)HistoryOrderGetInteger(fromTicket, ORDER_POSITION_ID))
                == this.trade.positionIdentifier;
        }
        return (ulong)HistoryOrderGetInteger(fromTicket, ORDER_MAGIC) == this.magicNumber
            && (H1EaTextUtil::ticket(fromTicket) == this.trade.entryOrderTicket
                || HistoryOrderGetString(fromTicket, ORDER_COMMENT) == this.entryComment());
    }

    /**
     * ticket昇順の現在注文スナップショットを作る。
     */
    string activeOrdersText() {
        ulong tickets[];
        for (int i = 0; i < OrdersTotal(); i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                return "~";
            }
            if (OrderGetString(ORDER_SYMBOL) != this.symbolName
                    || ((ulong)OrderGetInteger(ORDER_MAGIC) != this.magicNumber
                        && H1EaTextUtil::ticket((ulong)OrderGetInteger(ORDER_POSITION_ID)) != this.trade.positionIdentifier)) {
                continue;
            }
            int size = ArraySize(tickets);
            if (ArrayResize(tickets, size + 1) != size + 1) {
                return "~";
            }
            tickets[size] = ticket;
        }
        ArraySort(tickets);
        string result = "";
        for (int i = 0; i < ArraySize(tickets); i++) {
            if (!OrderSelect(tickets[i])) {
                return "~";
            }
            string item = "ORDER_V1";
            H1EaTextUtil::appendField(item, "ticket", H1EaTextUtil::ticket(tickets[i]));
            H1EaTextUtil::appendField(item, "position_id", H1EaTextUtil::ticket((ulong)OrderGetInteger(ORDER_POSITION_ID)));
            H1EaTextUtil::appendField(item, "state", IntegerToString(OrderGetInteger(ORDER_STATE)));
            H1EaTextUtil::appendField(item, "type", IntegerToString(OrderGetInteger(ORDER_TYPE)));
            H1EaTextUtil::appendField(item, "volume", DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 8));
            H1EaTextUtil::appendField(item, "price", this.optionalPrice(OrderGetDouble(ORDER_PRICE_OPEN)));
            H1EaTextUtil::appendField(item, "sl", this.optionalPrice(OrderGetDouble(ORDER_SL)));
            H1EaTextUtil::appendField(item, "setup_msc", IntegerToString(OrderGetInteger(ORDER_TIME_SETUP_MSC)));
            H1EaTextUtil::appendField(result, "order", item);
        }
        return result;
    }

    /**
     * ticket昇順の履歴注文スナップショットを作る。
     */
    string historyOrdersText() {
        if (!this.selectTradeHistory()) {
            return "~";
        }
        ulong tickets[];
        for (int i = 0; i < HistoryOrdersTotal(); i++) {
            ulong ticket = HistoryOrderGetTicket(i);
            if (!this.historyOrderBelongs(ticket)) {
                continue;
            }
            int size = ArraySize(tickets);
            if (ArrayResize(tickets, size + 1) != size + 1) {
                return "~";
            }
            tickets[size] = ticket;
        }
        ArraySort(tickets);
        string result = "";
        for (int i = 0; i < ArraySize(tickets); i++) {
            ulong ticket = tickets[i];
            string item = "ORDER_V1";
            H1EaTextUtil::appendField(item, "ticket", H1EaTextUtil::ticket(ticket));
            H1EaTextUtil::appendField(item, "position_id", H1EaTextUtil::ticket((ulong)HistoryOrderGetInteger(ticket, ORDER_POSITION_ID)));
            H1EaTextUtil::appendField(item, "state", IntegerToString(HistoryOrderGetInteger(ticket, ORDER_STATE)));
            H1EaTextUtil::appendField(item, "type", IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TYPE)));
            H1EaTextUtil::appendField(item, "volume", DoubleToString(HistoryOrderGetDouble(ticket, ORDER_VOLUME_CURRENT), 8));
            H1EaTextUtil::appendField(item, "price", this.optionalPrice(HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN)));
            H1EaTextUtil::appendField(item, "sl", this.optionalPrice(HistoryOrderGetDouble(ticket, ORDER_SL)));
            H1EaTextUtil::appendField(item, "setup_msc", IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP_MSC)));
            H1EaTextUtil::appendField(item, "done_msc", IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TIME_DONE_MSC)));
            H1EaTextUtil::appendField(result, "order", item);
        }
        return result;
    }

    /**
     * ticket昇順の約定事実を回復UIDに含める。
     */
    string dealsText() {
        if (!this.selectTradeHistory()) {
            return "~";
        }
        ulong tickets[];
        for (int i = 0; i < HistoryDealsTotal(); i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != this.symbolName) {
                continue;
            }
            if (this.trade.positionIdentifier != "") {
                if (H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID)) != this.trade.positionIdentifier) {
                    continue;
                }
            } else if (H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_ORDER)) != this.trade.entryOrderTicket) {
                continue;
            }
            int size = ArraySize(tickets);
            if (ArrayResize(tickets, size + 1) != size + 1) {
                return "~";
            }
            tickets[size] = ticket;
        }
        ArraySort(tickets);
        string result = "";
        for (int i = 0; i < ArraySize(tickets); i++) {
            ulong ticket = tickets[i];
            string item = "DEAL_V1";
            H1EaTextUtil::appendField(item, "ticket", H1EaTextUtil::ticket(ticket));
            H1EaTextUtil::appendField(item, "order", H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_ORDER)));
            H1EaTextUtil::appendField(item, "position_id", H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID)));
            H1EaTextUtil::appendField(item, "entry", IntegerToString(HistoryDealGetInteger(ticket, DEAL_ENTRY)));
            H1EaTextUtil::appendField(item, "type", IntegerToString(HistoryDealGetInteger(ticket, DEAL_TYPE)));
            H1EaTextUtil::appendField(item, "volume", DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 8));
            H1EaTextUtil::appendField(item, "price", this.optionalPrice(HistoryDealGetDouble(ticket, DEAL_PRICE)));
            H1EaTextUtil::appendField(item, "time_msc", IntegerToString(HistoryDealGetInteger(ticket, DEAL_TIME_MSC)));
            H1EaTextUtil::appendField(item, "reason", IntegerToString(HistoryDealGetInteger(ticket, DEAL_REASON)));
            H1EaTextUtil::appendField(item, "profit", DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 8));
            H1EaTextUtil::appendField(item, "commission", DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 8));
            H1EaTextUtil::appendField(item, "swap", DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 8));
            H1EaTextUtil::appendField(item, "fee", DoubleToString(HistoryDealGetDouble(ticket, DEAL_FEE), 8));
            H1EaTextUtil::appendField(result, "deal", item);
        }
        return result;
    }

    /**
     * 未完了要求はaction UID昇順で保存する。
     */
    string unresolvedActionsText() {
        string sql = "SELECT requested.action_uid FROM h1_ea_trade_events requested WHERE requested.trade_id="
            + IntegerToString(this.trade.id)
            + " AND requested.event_type IN ('ENTRY_REQUEST','SL_MODIFY_REQUEST','EXIT_REQUEST')"
            + " AND NOT EXISTS(SELECT 1 FROM h1_ea_trade_events resolved WHERE resolved.action_uid=requested.action_uid"
            + " AND resolved.event_type=REPLACE(requested.event_type,'_REQUEST','_RESULT')) ORDER BY requested.action_uid";
        int handle = DatabasePrepare(this.persistence.getHandle(), sql);
        if (handle == INVALID_HANDLE) {
            return "~";
        }
        string result = "";
        while (DatabaseRead(handle)) {
            string actionUid;
            if (!DatabaseColumnText(handle, 0, actionUid)) {
                DatabaseFinalize(handle);
                return "~";
            }
            H1EaTextUtil::appendField(result, "action_uid", actionUid);
        }
        DatabaseFinalize(handle);
        return result;
    }

    /**
     * 同じbroker・pending・action状態は同じ回復UIDへ畳み込む。
     */
    void recoveryEvent(H1EaTradeEventEntity &fromEvent) {
        fromEvent.eventSource = "RECONCILIATION";
        string snapshot = "H1_EA_RECOVERY_SNAPSHOT_V1";
        H1EaTextUtil::appendField(snapshot, "context_key", this.contextKey);
        H1EaTextUtil::appendField(snapshot, "trade_id", IntegerToString(this.trade.id));
        H1EaTextUtil::appendField(snapshot, "status", this.trade.status);
        H1EaTextUtil::appendField(snapshot, "position_identifier", this.optionalText(this.trade.positionIdentifier));
        H1EaTextUtil::appendField(snapshot, "position_ticket", this.optionalText(this.trade.positionTicket));
        H1EaTextUtil::appendField(snapshot, "side", this.trade.side);
        H1EaTextUtil::appendField(snapshot, "position_volume", this.optionalVolume(this.trade.remainingPositionVolume));
        H1EaTextUtil::appendField(snapshot, "current_stop_loss", this.optionalPrice(this.trade.currentStopLoss));
        H1EaTextUtil::appendField(snapshot, "stop_loss_source", this.trade.stopLossSource);
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_kind", this.optionalText(this.trade.pendingStopLossKind));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_h1_bar_time", this.optionalInteger(this.trade.pendingStopLossH1BarTime));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss", this.optionalPrice(this.trade.pendingStopLoss));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_pivot_time", this.optionalInteger(this.trade.pendingStopLossPivotTime));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_pivot_rate", this.optionalPrice(this.trade.pendingStopLossPivotRate));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_latest_time", this.optionalInteger(this.trade.pendingStopLossLatestTime));
        H1EaTextUtil::appendField(snapshot, "pending_stop_loss_action_uid", this.optionalText(this.trade.pendingStopLossActionUid));
        H1EaTextUtil::appendField(snapshot, "last_applied_trail_h1_bar_time", this.optionalInteger(this.trade.lastAppliedTrailH1BarTime));
        H1EaTextUtil::appendField(snapshot, "last_applied_trail_stop_loss", this.optionalPrice(this.trade.lastAppliedTrailStopLoss));
        H1EaTextUtil::appendField(snapshot, "last_applied_trail_pivot_time", this.optionalInteger(this.trade.lastAppliedTrailPivotTime));
        H1EaTextUtil::appendField(snapshot, "last_applied_trail_pivot_rate", this.optionalPrice(this.trade.lastAppliedTrailPivotRate));
        H1EaTextUtil::appendField(snapshot, "last_applied_trail_latest_time", this.optionalInteger(this.trade.lastAppliedTrailLatestTime));
        H1EaTextUtil::appendField(snapshot, "last_trail_evaluated_h1_bar_time", this.optionalInteger(this.trade.lastTrailEvaluatedH1BarTime));
        H1EaTextUtil::appendField(snapshot, "active_orders", this.activeOrdersText());
        H1EaTextUtil::appendField(snapshot, "history_orders", this.historyOrdersText());
        H1EaTextUtil::appendField(snapshot, "deals", this.dealsText());
        H1EaTextUtil::appendField(snapshot, "unresolved_actions", this.unresolvedActionsText());
        H1EaTextUtil::appendField(snapshot, "recovery_issue_code", this.optionalText(fromEvent.recoveryIssueCode));
        H1EaTextUtil::appendField(snapshot, "quarantined_pending_text", this.optionalText(fromEvent.quarantinedPendingText));
        fromEvent.eventUid = "H1_EA_RECOVERY_V1|" + this.contextKey + "|"
            + IntegerToString(this.trade.id) + "|" + H1EaTextUtil::hash(snapshot);
        if (fromEvent.eventUid == this.lastRecoveryUid) {
            return;
        }
        fromEvent.stopLossSource = this.trade.stopLossSource;
        fromEvent.message += " " + snapshot;
        if (this.saveEvent(fromEvent, false)) {
            this.lastRecoveryUid = fromEvent.eventUid;
            if (ArraySize(this.saveQueue) == 0) {
                this.recoveryCommitPending = false;
            }
        }
    }

    /**
     * DB障害中もCommonのテキストログへ記録する。
     */
    void writeLog(const string fromLevel, const string fromMessage) {
        if (fromLevel == "ERROR") {
            this.operationLogger.error("H1EaTradeExecutor", fromMessage);
        } else {
            this.operationLogger.info("H1EaTradeExecutor", fromMessage);
        }
    }
};

#endif
