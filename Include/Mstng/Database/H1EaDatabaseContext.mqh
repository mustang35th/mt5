#ifndef MSTNG_DATABASE_H1_EA_DATABASE_CONTEXT_MQH
#define MSTNG_DATABASE_H1_EA_DATABASE_CONTEXT_MQH

#include <Mstng\Database\Dao\H1EaDecisionDao.mqh>
#include <Mstng\Database\Dao\H1EaRunDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeDao.mqh>
#include <Mstng\Database\Dao\H1EaTradeEventDao.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>

/**
 * H1 EA専用接続と初版schemaの検証を管理する。
 */
class H1EaDatabaseContext {
public:
    /**
     * 未接続状態で初期化する。
     */
    H1EaDatabaseContext() {
        this.database = NULL;
    }

    /**
     * 接続リソースを解放する。
     */
    ~H1EaDatabaseContext() {
        this.close();
    }

    /**
     * Common DBを開く。再接続ではDDLを行わず既存schemaだけを検証する。
     */
    bool open(const string fromFileName, const bool fromInitializeSchema = true) {
        this.close();
        this.database = new SqliteDatabase(fromFileName, true);
        if (this.database == NULL || !this.database.open()) {
            this.close();
            return false;
        }
        int handle = this.getHandle();
        if (!H1EaSql::execute(handle, "PRAGMA foreign_keys=ON")
                || !H1EaSql::execute(handle, "PRAGMA busy_timeout=5000")
                || !H1EaSql::execute(handle, "PRAGMA journal_mode=WAL")) {
            this.close();
            return false;
        }
        long foreignKeys = 0;
        long timeout = 0;
        string journalMode = "";
        if (!H1EaSql::scalar(handle, "PRAGMA foreign_keys", foreignKeys)
                || !H1EaSql::scalar(handle, "PRAGMA busy_timeout", timeout)
                || !this.readText("PRAGMA journal_mode", journalMode)
                || foreignKeys != 1 || timeout != 5000 || journalMode != "wal") {
            this.close();
            return false;
        }
        if (!this.prepareSchema(fromInitializeSchema)) {
            this.close();
            return false;
        }
        return true;
    }

    /**
     * 接続を閉じる。DBファイルは削除しない。
     */
    void close() {
        if (this.database != NULL) {
            this.database.close();
            delete this.database;
            this.database = NULL;
        }
    }

    /**
     * 現在のSQLiteハンドルを返す。
     */
    int getHandle() const {
        if (this.database == NULL) {
            return INVALID_HANDLE;
        }
        return this.database.getHandle();
    }

private:
    /** H1専用SQLite接続。 */
    SqliteDatabase *database;

    /**
     * 一件の文字列を正常取得した場合だけtrueを返す。
     */
    bool readText(const string fromSql, string &fromText) {
        int request = DatabasePrepare(this.getHandle(), fromSql);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool success = DatabaseRead(request) && DatabaseColumnText(request, 0, fromText);
        DatabaseFinalize(request);
        return success;
    }

    /**
     * schema原文を比較し、同じversion番号の列・CHECK欠落も拒否する。
     */
    bool matchesSchema(const string fromType, const string fromName, const string fromExpected) {
        string actual = "";
        string expected = fromExpected;
        if (!this.readText("SELECT sql FROM sqlite_schema WHERE type="
                + H1EaSql::text(fromType) + " AND name=" + H1EaSql::text(fromName), actual)) {
            return false;
        }
        StringReplace(expected, "IF NOT EXISTS ", "");
        StringReplace(actual, "IF NOT EXISTS ", "");
        StringReplace(expected, ";", "");
        StringReplace(actual, ";", "");
        return actual == expected;
    }

    /**
     * 保存契約の全table/indexを検証する。
     */
    bool validateSchema() {
        if (!this.matchesSchema("table", "h1_ea_runs", H1EaRunDao::createSql())) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_runs_run_uid", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_runs_run_uid ON h1_ea_runs(run_uid);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_runs_active_context", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_runs_active_context ON h1_ea_runs(context_key) WHERE status = 'RUNNING';")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_runs_source_started", "CREATE INDEX IF NOT EXISTS idx_h1_ea_runs_source_started ON h1_ea_runs(source_mode, started_at, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_runs_context_started", "CREATE INDEX IF NOT EXISTS idx_h1_ea_runs_context_started ON h1_ea_runs(context_key, started_at, id);")) {
            return false;
        }
        if (!this.matchesSchema("table", "h1_ea_decisions", H1EaDecisionDao::createSql())) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_context_bar", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_decisions_context_bar ON h1_ea_decisions(context_key, h1_bar_time);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_consumed_signal", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_decisions_consumed_signal ON h1_ea_decisions( context_key, signal_reference_time, signal_side ) WHERE is_signal_consumed = 1;")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_bar", "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_bar ON h1_ea_decisions(h1_bar_time, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_run_bar", "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_run_bar ON h1_ea_decisions(run_id, h1_bar_time, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_result_bar", "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_result_bar ON h1_ea_decisions(decision, h1_bar_time, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_decisions_reason_bar", "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_reason_bar ON h1_ea_decisions(reason_code, h1_bar_time, id);")) {
            return false;
        }
        if (!this.matchesSchema("table", "h1_ea_trades", H1EaTradeDao::createSql())) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_decision", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_decision ON h1_ea_trades(decision_id) WHERE decision_id IS NOT NULL;")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_active_context", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_active_context ON h1_ea_trades(context_key) WHERE status IN ( 'OPEN_PENDING', 'OPEN_PARTIAL', 'OPEN', 'CLOSE_PENDING', 'CLOSE_PARTIAL', 'RECOVERY_REQUIRED' );")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_position_identifier", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_position_identifier ON h1_ea_trades(context_key, position_identifier) WHERE position_identifier IS NOT NULL;")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_status_updated", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_status_updated ON h1_ea_trades(status, updated_at, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_context_updated", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_context_updated ON h1_ea_trades(context_key, updated_at, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_closed", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_closed ON h1_ea_trades(closed_at_msc, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trades_pending_stop_loss", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_pending_stop_loss ON h1_ea_trades(context_key, pending_stop_loss_h1_bar_time, id) WHERE pending_stop_loss IS NOT NULL;")) {
            return false;
        }
        if (!this.matchesSchema("table", "h1_ea_trade_events", H1EaTradeEventDao::createSql())) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_event_uid", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trade_events_event_uid ON h1_ea_trade_events(event_uid);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_trade_sequence", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trade_events_trade_sequence ON h1_ea_trade_events(trade_id, sequence);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_deal_scope", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trade_events_deal_scope ON h1_ea_trade_events(deal_scope_key) WHERE deal_scope_key IS NOT NULL;")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_action_type", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trade_events_action_type ON h1_ea_trade_events(action_uid, event_type) WHERE action_uid IS NOT NULL;")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_trail_bar", "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trade_events_trail_bar ON h1_ea_trade_events(trade_id, event_type, h1_bar_time) WHERE event_type = 'TRAIL_EVALUATION';")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_trade_time", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trade_events_trade_time ON h1_ea_trade_events(trade_id, broker_time_msc, id);")) {
            return false;
        }
        if (!this.matchesSchema("index", "idx_h1_ea_trade_events_run_recorded", "CREATE INDEX IF NOT EXISTS idx_h1_ea_trade_events_run_recorded ON h1_ea_trade_events(run_id, recorded_at, id);")) {
            return false;
        }
        return true;
    }

    /**
     * DDLとuser_version更新を単一書込transactionへ収める。
     */
    bool prepareSchema(const bool fromInitializeSchema) {
        int handle = this.getHandle();
        if (!H1EaSql::execute(handle, "BEGIN IMMEDIATE")) {
            return false;
        }
        long version = -1;
        bool success = H1EaSql::scalar(handle, "PRAGMA user_version", version);
        if (success && version == 0 && fromInitializeSchema) {
            success = H1EaRunDao::createTable(handle)
                && H1EaDecisionDao::createTable(handle)
                && H1EaTradeDao::createTable(handle)
                && H1EaTradeEventDao::createTable(handle);
            if (success) {
                success = this.validateSchema()
                    && H1EaSql::execute(handle, "PRAGMA user_version=1");
            }
        } else if (success && version == 1) {
            success = this.validateSchema();
        } else {
            success = false;
        }
        if (success && H1EaSql::execute(handle, "COMMIT")) {
            return true;
        }
        H1EaSql::execute(handle, "ROLLBACK");
        return false;
    }
};

#endif
