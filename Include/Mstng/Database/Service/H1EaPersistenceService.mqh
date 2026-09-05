#ifndef MSTNG_DATABASE_SERVICE_H1_EA_PERSISTENCE_SERVICE_MQH
#define MSTNG_DATABASE_SERVICE_H1_EA_PERSISTENCE_SERVICE_MQH

#include <Mstng\Database\H1EaDatabaseContext.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * H1 EAのLease・判定・取引履歴を短いtransactionで永続化する。
 * broker送信は担当せず、保存完了を送信側へ明示する。
 */
class H1EaPersistenceService {
public:
    /**
     * 未接続状態で初期化する。
     */
    H1EaPersistenceService() {
        this.lastError = "";
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * DBと初版schemaを準備する。再接続時はfalseでDDLを禁止する。
     */
    bool open(const string fromFileName, const bool fromInitializeSchema = true) {
        if (!this.context.open(fromFileName, fromInitializeSchema)) {
            return this.fail("DATABASE_OPEN_OR_SCHEMA_FAILED");
        }
        this.lastError = "";
        return true;
    }

    /**
     * DBを閉じる。Run終了は明示的にfinishRunで保存する。
     */
    void close() {
        this.context.close();
    }

    /**
     * 接続ハンドルを返す。
     */
    int getHandle() const {
        return this.context.getHandle();
    }

    /**
     * 最後の保存エラーを取得する。
     */
    string getLastError() const {
        return this.lastError;
    }

    /**
     * 期限切れRunの中断と新RunのLease取得を一括保存する。
     */
    bool acquireRun(H1EaRunEntity &fromRun) {
        if (!H1EaSql::isHash(fromRun.runUid) || !H1EaSql::isHash(fromRun.configHash)
                || !H1EaSql::isHash(fromRun.analysisInputHash)
                || fromRun.configHash != H1EaSql::hash(fromRun.configText)
                || fromRun.analysisInputHash != H1EaSql::hash(fromRun.analysisInputText)) {
            return this.fail("RUN_HASH_INVALID");
        }
        if (fromRun.id != 0 || !this.begin()) {
            return this.fail("RUN_ALREADY_ACQUIRED_OR_BEGIN_FAILED");
        }
        H1EaRunEntity candidate = fromRun;
        long now = (long)TimeLocal();
        long activeCount = 0;
        if (!H1EaSql::scalar(this.getHandle(),
                "SELECT COUNT(*) FROM h1_ea_runs WHERE context_key="
                + H1EaSql::text(candidate.contextKey)
                + " AND status='RUNNING' AND lease_expires_at>" + IntegerToString(now), activeCount)) {
            return this.complete(false, "RUN_CONTEXT_READ_FAILED");
        }
        if (activeCount > 0) {
            H1EaSql::execute(this.getHandle(), "ROLLBACK");
            return this.fail("RUN_CONTEXT_ALREADY_ACTIVE");
        }
        candidate.status = "RUNNING";
        candidate.heartbeatAt = now;
        candidate.leaseExpiresAt = now + 60;
        if (candidate.startedAt == 0) {
            candidate.startedAt = now;
        }
        string sql = "UPDATE h1_ea_runs SET status='INTERRUPTED',ended_at="
            + IntegerToString(now) + ",error_text=error_text||'|LEASE_EXPIRED' WHERE context_key="
            + H1EaSql::text(candidate.contextKey)
            + " AND status='RUNNING' AND lease_expires_at<=" + IntegerToString(now);
        bool success = H1EaSql::execute(this.getHandle(), sql)
            && H1EaRunDao::insert(this.getHandle(), candidate);
        if (!this.complete(success, "RUN_LEASE_ACQUIRE_FAILED")) {
            return false;
        }
        fromRun = candidate;
        return true;
    }

    /**
     * 未失効の今回Runだけを更新する。失効Leaseは復活させない。
     */
    bool heartbeat(H1EaRunEntity &fromRun, const datetime fromNow) {
        if (!this.begin()) {
            return false;
        }
        string sql = "UPDATE h1_ea_runs SET heartbeat_at=" + IntegerToString((long)fromNow)
            + ",lease_expires_at=" + IntegerToString((long)fromNow + 60)
            + " WHERE id=" + IntegerToString(fromRun.id)
            + " AND status='RUNNING' AND lease_expires_at>" + IntegerToString((long)fromNow);
        long changed = 0;
        bool success = H1EaSql::execute(this.getHandle(), sql)
            && H1EaSql::scalar(this.getHandle(), "SELECT changes()", changed) && changed == 1;
        if (!this.complete(success, "RUN_LEASE_HEARTBEAT_FAILED")) {
            return false;
        }
        fromRun.heartbeatAt = (long)fromNow;
        fromRun.leaseExpiresAt = (long)fromNow + 60;
        return true;
    }

    /**
     * 指定Runが現在もLeaseを所有しているかDBで確認する。
     */
    bool hasLease(const long fromRunId, const datetime fromNow) {
        long count = 0;
        if (!H1EaSql::scalar(this.getHandle(),
            "SELECT COUNT(*) FROM h1_ea_runs WHERE id=" + IntegerToString(fromRunId)
            + " AND status='RUNNING' AND lease_expires_at>" + IntegerToString((long)fromNow),
            count)) {
            return this.fail("LEASE_READ_FAILED");
        }
        if (count != 1) {
            return this.fail("LEASE_NOT_OWNED");
        }
        this.lastError = "";
        return true;
    }

    /**
     * 初回消費を含むSKIPを確定保存する。既存Decisionは上書きしない。
     */
    bool saveDecision(const long fromRunId, H1EaDecisionEntity &fromDecision) {
        if (!H1EaSql::isHash(fromDecision.snapshotHash)) {
            return this.fail("DECISION_HASH_INVALID");
        }
        if (fromDecision.decision != "SKIP") {
            return this.fail("ENTRY_REQUIRES_ATOMIC_TRADE");
        }
        if (!this.beginOwned(fromRunId, true, fromDecision.contextKey)) {
            return false;
        }
        H1EaDecisionEntity candidate = fromDecision;
        H1EaDecisionEntity existing;
        bool found = false;
        bool success = this.loadDecision(candidate.contextKey, candidate.h1BarTime, existing, found);
        if (success && found) {
            success = existing.snapshotHash == candidate.snapshotHash
                && existing.analysisSnapshotText == candidate.analysisSnapshotText;
            if (success) {
                candidate = existing;
            }
        } else if (success) {
            candidate.runId = fromRunId;
            success = H1EaDecisionDao::insert(this.getHandle(), candidate);
        }
        if (!this.complete(success, "DECISION_SAVE_FAILED")) {
            return false;
        }
        fromDecision = candidate;
        return true;
    }

    /**
     * Decision・OPEN_PENDING・ENTRY_REQUESTを同じLease下で一括保存する。
     */
    bool saveEntry(const long fromRunId, H1EaDecisionEntity &fromDecision,
            H1EaTradeEntity &fromTrade, H1EaTradeEventEntity &fromEvent) {
        if (!H1EaSql::isHash(fromDecision.snapshotHash)) {
            return this.fail("DECISION_HASH_INVALID");
        }
        if ((fromDecision.decision != "BUY" && fromDecision.decision != "SELL")
                || fromTrade.id != 0 || fromEvent.eventType != "ENTRY_REQUEST"
                || fromTrade.status != "OPEN_PENDING"
                || fromTrade.contextKey != fromDecision.contextKey
                || fromTrade.side != fromDecision.decision) {
            return this.fail("ENTRY_SNAPSHOT_INVALID");
        }
        if (!this.beginOwned(fromRunId, true, fromDecision.contextKey)) {
            return false;
        }
        H1EaDecisionEntity decision = fromDecision;
        H1EaTradeEntity trade = fromTrade;
        H1EaTradeEventEntity event = fromEvent;
        decision.runId = fromRunId;
        bool success = H1EaDecisionDao::insert(this.getHandle(), decision);
        if (success) {
            trade.createdRunId = fromRunId;
            trade.decisionId = decision.id;
            success = H1EaTradeDao::insert(this.getHandle(), trade);
        }
        if (success) {
            event.tradeId = trade.id;
            event.runId = fromRunId;
            if (StringFind(event.actionUid, "{TRADE_ID}") >= 0) {
                StringReplace(event.actionUid, "{TRADE_ID}", IntegerToString(trade.id));
                event.eventUid = event.actionUid + "|REQUEST";
            }
            success = this.insertEvent(event);
        }
        if (!this.complete(success, "ENTRY_ATOMIC_SAVE_FAILED")) {
            return false;
        }
        fromDecision = decision;
        fromTrade = trade;
        fromEvent = event;
        return true;
    }

    /**
     * 取引snapshotと監査Eventを原子的に保存する。
     * Lease不要経路はbroker事実の監査専用であり、送信許可を与えない。
     */
    bool saveTradeEvent(const long fromRunId, H1EaTradeEntity &fromTrade,
            H1EaTradeEventEntity &fromEvent, const bool fromRequireLease = true,
            const bool fromReplayQueuedRequest = false) {
        if (!fromRequireLease && (fromEvent.eventType == "ENTRY_REQUEST"
                || fromEvent.eventType == "SL_MODIFY_REQUEST"
                || fromEvent.eventType == "EXIT_REQUEST")) {
            if (!fromReplayQueuedRequest || fromEvent.eventType == "ENTRY_REQUEST") {
                return this.fail("REQUEST_REQUIRES_LEASE");
            }
        }
        if (!this.beginOwned(fromRunId, fromRequireLease, fromTrade.contextKey)) {
            return false;
        }
        H1EaTradeEntity trade = fromTrade;
        H1EaTradeEventEntity event = fromEvent;
        H1EaTradeEventEntity existingEvent;
        if (trade.id > 0 && !this.resolveRecoveryUid(trade, event)) {
            return this.complete(false, "RECOVERY_UID_RESOLUTION_FAILED");
        }
        bool found = false;
        bool success = H1EaTradeEventDao::load(this.getHandle(),
            "event_uid=" + H1EaSql::text(event.eventUid), existingEvent, found);
        if (success && found) {
            bool tradeFound = false;
            success = (trade.id == 0 || existingEvent.tradeId == trade.id)
                && H1EaTradeDao::load(this.getHandle(),
                    "id=" + IntegerToString(existingEvent.tradeId), trade, tradeFound)
                && tradeFound && trade.contextKey == fromTrade.contextKey;
            if (success) {
                event = existingEvent;
            }
        } else if (success) {
            if (trade.id == 0) {
                if (trade.origin != "RECOVERED") {
                    success = false;
                } else {
                    trade.createdRunId = fromRunId;
                    success = H1EaTradeDao::insert(this.getHandle(), trade);
                }
            } else {
                H1EaTradeEntity previous;
                bool tradeFound = false;
                success = H1EaTradeDao::load(this.getHandle(),
                    "id=" + IntegerToString(trade.id), previous, tradeFound)
                    && tradeFound && previous.contextKey == trade.contextKey;
                if (success && previous.status == "CLOSED" && trade.status != "CLOSED") {
                    success = false;
                }
                if (success) {
                    success = H1EaTradeDao::update(this.getHandle(), trade);
                }
            }
            if (success) {
                event.tradeId = trade.id;
                event.runId = fromRunId;
                success = this.resolveRecoveryUid(trade, event) && this.insertEvent(event);
            }
        }
        if (!this.complete(success, "TRADE_EVENT_ATOMIC_SAVE_FAILED")) {
            return false;
        }
        fromTrade = trade;
        fromEvent = event;
        return true;
    }

    /**
     * 保存済みH1バーを確認する。別Runの確定行もそのまま返す。
     */
    bool loadDecision(const string fromContext, const long fromBar,
            H1EaDecisionEntity &fromDecision, bool &fromFound) {
        return H1EaDecisionDao::load(this.getHandle(),
            "context_key=" + H1EaSql::text(fromContext)
            + " AND h1_bar_time=" + IntegerToString(fromBar), fromDecision, fromFound);
    }

    /**
     * active枠を占める取引を読み取る。
     */
    bool loadActiveTrade(const string fromContext,
            H1EaTradeEntity &fromTrade, bool &fromFound) {
        return H1EaTradeDao::load(this.getHandle(),
            "context_key=" + H1EaSql::text(fromContext)
            + " AND status IN ('OPEN_PENDING','OPEN_PARTIAL','OPEN',"
            + "'CLOSE_PENDING','CLOSE_PARTIAL','RECOVERY_REQUIRED')", fromTrade, fromFound);
    }

    /**
     * 型変換前のpending全7列を、SQLite実型・SQL値付きCanonical Textで取得する。
     * 列名の後の長さは型とSQLリテラルを合わせたUTF-8バイト数とする。
     */
    bool loadPendingRaw(const long fromTradeId, string &fromText) {
        fromText = "";
        if (fromTradeId <= 0) {
            return this.fail("PENDING_RAW_TRADE_ID_INVALID");
        }
        int request = DatabasePrepare(this.getHandle(),
            "SELECT " + H1EaTradeDao::pendingRawColumns()
            + " FROM h1_ea_trades WHERE id=" + IntegerToString(fromTradeId));
        if (request == INVALID_HANDLE) {
            return this.fail("PENDING_RAW_READ_FAILED");
        }
        if (!DatabaseRead(request)) {
            DatabaseFinalize(request);
            return this.fail("PENDING_RAW_READ_FAILED");
        }
        string columns[] = {
            "pending_stop_loss_kind", "pending_stop_loss_h1_bar_time", "pending_stop_loss",
            "pending_stop_loss_pivot_time", "pending_stop_loss_pivot_rate",
            "pending_stop_loss_latest_time", "pending_stop_loss_action_uid"
        };
        string canonical = "H1_EA_PENDING_RAW_V1";
        bool success = true;
        for (int i = 0; i < ArraySize(columns); i++) {
            string actualType = "";
            string actualValue = "";
            if (!DatabaseColumnText(request, i * 2, actualType)
                    || !DatabaseColumnText(request, i * 2 + 1, actualValue)) {
                success = false;
                break;
            }
            string value = actualType + ":" + actualValue;
            uchar bytes[];
            int size = StringToCharArray(value, bytes, 0, WHOLE_ARRAY, CP_UTF8);
            if (size < 1) {
                success = false;
                break;
            }
            canonical += "|" + columns[i] + "#" + IntegerToString(size - 1) + "=" + value;
        }
        DatabaseFinalize(request);
        if (!success) {
            return this.fail("PENDING_RAW_READ_FAILED");
        }
        fromText = canonical;
        this.lastError = "";
        return true;
    }

    /**
     * SLまたは注文actionの要求・結果を取得する。
     */
    bool loadEvent(const string fromActionUid, const string fromEventType,
            H1EaTradeEventEntity &fromEvent, bool &fromFound) {
        return H1EaTradeEventDao::load(this.getHandle(),
            "action_uid=" + H1EaSql::text(fromActionUid)
            + " AND event_type=" + H1EaSql::text(fromEventType), fromEvent, fromFound);
    }

    /**
     * 最後の要求Eventを読み取り、再起動時の送信意図を照合する。
     */
    bool loadLatestTradeEvent(const long fromTradeId, const string fromEventType,
            H1EaTradeEventEntity &fromEvent, bool &fromFound) {
        return H1EaTradeEventDao::load(this.getHandle(),
            "trade_id=" + IntegerToString(fromTradeId)
            + " AND event_type=" + H1EaSql::text(fromEventType)
            + " ORDER BY sequence DESC", fromEvent, fromFound);
    }

    /**
     * 検出済みの監査欠落があるコンテキストでは初回回数を推測復元しない。
     */
    bool hasAuditGap(const string fromContext, bool &fromFound) {
        long count = 0;
        bool success = H1EaSql::scalar(this.getHandle(),
            "SELECT COUNT(*) FROM h1_ea_runs WHERE context_key=" + H1EaSql::text(fromContext)
            + " AND error_text LIKE '%AUDIT_STATE_LOST%'", count);
        if (success) {
            fromFound = count > 0;
        }
        return success;
    }

    /**
     * Judge OFFを挟んでも同じシグナルの最終回数を復元する。
     */
    bool loadSignalCount(const string fromContext, const long fromReferenceTime,
            const string fromSide, int &fromCount) {
        long count = 0;
        bool success = H1EaSql::scalar(this.getHandle(),
            "SELECT COALESCE(MAX(signal_count),0) FROM h1_ea_decisions WHERE context_key="
            + H1EaSql::text(fromContext) + " AND signal_reference_time="
            + IntegerToString(fromReferenceTime) + " AND signal_side=" + H1EaSql::text(fromSide)
            + " AND is_judge_matched=1", count);
        if (success && count >= 0 && count <= INT_MAX) {
            fromCount = (int)count;
            return true;
        }
        return false;
    }

    /**
     * 全保存済みシグナルの回数を復元する。
     */
    bool loadSignalCounts(const string fromContext, long &fromTimes[],
            string &fromSides[], int &fromCounts[]) {
        ArrayResize(fromTimes, 0);
        ArrayResize(fromSides, 0);
        ArrayResize(fromCounts, 0);
        int request = DatabasePrepare(this.getHandle(),
            "SELECT signal_reference_time,signal_side,MAX(signal_count) FROM h1_ea_decisions"
            + " WHERE context_key=" + H1EaSql::text(fromContext)
            + " AND is_judge_matched=1 GROUP BY signal_reference_time,signal_side"
            + " ORDER BY signal_reference_time,signal_side");
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool success = true;
        int count = 0;
        while (true) {
            ResetLastError();
            if (!DatabaseRead(request)) {
                success = GetLastError() == ERR_DATABASE_NO_MORE_DATA;
                break;
            }
            long referenceTime = 0;
            long signalCount = 0;
            string side = "";
            if (!DatabaseColumnLong(request, 0, referenceTime)
                    || !DatabaseColumnText(request, 1, side)
                    || !DatabaseColumnLong(request, 2, signalCount)
                    || signalCount < 1 || signalCount > INT_MAX
                    || ArrayResize(fromTimes, count + 1) < 0
                    || ArrayResize(fromSides, count + 1) < 0
                    || ArrayResize(fromCounts, count + 1) < 0) {
                success = false;
                break;
            }
            fromTimes[count] = referenceTime;
            fromSides[count] = side;
            fromCounts[count] = (int)signalCount;
            count++;
        }
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 候補跨ぎ決済を要求した最後のH1バーを復元する。
     */
    bool loadCrossBlockedBar(const string fromContext, datetime &fromBar) {
        long bar = 0;
        bool success = H1EaSql::scalar(this.getHandle(),
            "SELECT COALESCE(MAX((e.server_time/3600)*3600),0)"
            + " FROM h1_ea_trade_events e JOIN h1_ea_trades t ON t.id=e.trade_id"
            + " WHERE t.context_key=" + H1EaSql::text(fromContext)
            + " AND e.event_type='EXIT_REQUEST' AND e.exit_intent_reason IS NOT NULL", bar);
        if (success) {
            fromBar = (datetime)bar;
        }
        return success;
    }

    /**
     * 正常終了・初期化失敗を保存しLeaseを解放する。
     */
    bool finishRun(const long fromRunId, const string fromStatus, const string fromError) {
        if (fromStatus != "STOPPED" && fromStatus != "FAILED") {
            return this.fail("RUN_TERMINAL_STATUS_INVALID");
        }
        if (!this.begin()) {
            return false;
        }
        long now = (long)TimeLocal();
        string sql = "UPDATE h1_ea_runs SET status=" + H1EaSql::text(fromStatus)
            + ",ended_at=" + IntegerToString(now) + ",error_text=" + H1EaSql::text(fromError)
            + " WHERE id=" + IntegerToString(fromRunId) + " AND status='RUNNING'";
        return this.complete(H1EaSql::execute(this.getHandle(), sql), "RUN_FINISH_FAILED");
    }

private:
    /** 接続とschema管理。 */
    H1EaDatabaseContext context;
    /** 最後のエラー識別値。 */
    string lastError;
    /** 運用ログ。 */
    Logger logger;

    /**
     * 書込みtransactionを開始する。
     */
    bool begin() {
        if (!H1EaSql::execute(this.getHandle(), "BEGIN IMMEDIATE")) {
            return this.fail("TRANSACTION_BEGIN_FAILED");
        }
        return true;
    }

    /**
     * 同じtransactionでRunのscopeと必要なLeaseを確認する。
     */
    bool beginOwned(const long fromRunId, const bool fromRequireLease,
            const string fromContext) {
        if (!this.begin()) {
            return false;
        }
        H1EaRunEntity run;
        bool found = false;
        if (!H1EaRunDao::load(this.getHandle(),
                "id=" + IntegerToString(fromRunId), run, found)) {
            return this.complete(false, "RUN_SCOPE_READ_FAILED");
        }
        bool success = found && run.contextKey == fromContext;
        if (success) {
            long successors = 0;
            if (!H1EaSql::scalar(this.getHandle(),
                    "SELECT COUNT(*) FROM h1_ea_runs WHERE context_key="
                    + H1EaSql::text(fromContext) + " AND id>" + IntegerToString(fromRunId), successors)) {
                return this.complete(false, "RUN_SUCCESSOR_READ_FAILED");
            }
            if (successors > 0) {
                H1EaSql::execute(this.getHandle(), "ROLLBACK");
                return this.fail("SNAPSHOT_OWNER_SUPERSEDED");
            }
        }
        if (success && fromRequireLease) {
            success = run.status == "RUNNING" && run.leaseExpiresAt > (long)TimeLocal();
        }
        if (!success) {
            H1EaSql::execute(this.getHandle(), "ROLLBACK");
            return this.fail("RUN_SCOPE_OR_LEASE_LOST");
        }
        return true;
    }

    /**
     * trade内の連番を同じtransactionで採番する。
     */
    bool insertEvent(H1EaTradeEventEntity &fromEvent) {
        long sequence = 0;
        if (!H1EaSql::scalar(this.getHandle(),
                "SELECT COALESCE(MAX(sequence),0)+1 FROM h1_ea_trade_events WHERE trade_id="
                + IntegerToString(fromEvent.tradeId), sequence)) {
            return false;
        }
        fromEvent.sequence = sequence;
        return H1EaTradeEventDao::insert(this.getHandle(), fromEvent);
    }

    /**
     * 新規回復Tradeの採番をcanonical snapshotとUIDへ同じtransactionで反映する。
     */
    bool resolveRecoveryUid(const H1EaTradeEntity &fromTrade, H1EaTradeEventEntity &fromEvent) {
        if (fromEvent.eventType != "RECOVERY" || fromTrade.id <= 0) {
            return true;
        }
        int start = StringFind(fromEvent.message, "H1_EA_RECOVERY_SNAPSHOT_V1");
        if (start < 0) {
            return true;
        }
        string snapshot = StringSubstr(fromEvent.message, start);
        string marker = "|trade_id#1=0|";
        int position = StringFind(snapshot, marker);
        if (position < 0) {
            return true;
        }
        string tradeId = IntegerToString(fromTrade.id);
        string replacement = "|trade_id#" + IntegerToString(StringLen(tradeId)) + "=" + tradeId + "|";
        snapshot = StringSubstr(snapshot, 0, position) + replacement
            + StringSubstr(snapshot, position + StringLen(marker));
        string hash = H1EaSql::hash(snapshot);
        if (hash == "") {
            return false;
        }
        fromEvent.message = StringSubstr(fromEvent.message, 0, start) + snapshot;
        fromEvent.eventUid = "H1_EA_RECOVERY_V1|" + fromTrade.contextKey + "|" + tradeId + "|" + hash;
        return true;
    }

    /**
     * commit失敗を含む途中失敗を必ずrollbackする。
     */
    bool complete(const bool fromSuccess, const string fromReason) {
        if (fromSuccess && H1EaSql::execute(this.getHandle(), "COMMIT")) {
            this.lastError = "";
            return true;
        }
        int errorCode = GetLastError();
        H1EaSql::execute(this.getHandle(), "ROLLBACK");
        return this.fail(fromReason + " error=" + IntegerToString(errorCode));
    }

    /**
     * エラー理由を運用ログへ保存する。
     */
    bool fail(const string fromReason) {
        this.lastError = fromReason;
        this.logger.error(__FUNCTION__, fromReason);
        return false;
    }
};

#endif
