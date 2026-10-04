#ifndef MSTNGM15EA_PERSISTENCE_TRADEEVENTDAO_MQH
#define MSTNGM15EA_PERSISTENCE_TRADEEVENTDAO_MQH

#include <MstngEaCommon\Runtime\EaTradeEvent.mqh>
#include <MstngM15Ea\Persistence\M15EaSql.mqh>

/**
 * M15 EA TradeEventのSQL保存と読み取りを担当する。
 */
class M15EaTradeEventDao {
public:
    /**
     * 初版の列・整合制約を返す。
     */
    static string createSql() {
        string sql = "CREATE TABLE IF NOT EXISTS m15_ea_trade_events (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "trade_id INTEGER NOT NULL,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "event_uid TEXT NOT NULL,";
        sql += "action_uid TEXT,";
        sql += "sequence INTEGER NOT NULL,";
        sql += "event_type TEXT NOT NULL,";
        sql += "event_source TEXT NOT NULL,";
        sql += "server_time INTEGER,";
        sql += "broker_time_msc INTEGER,";
        sql += "recorded_at INTEGER NOT NULL,";
        sql += "transaction_type INTEGER,";
        sql += "order_ticket TEXT,";
        sql += "deal_ticket TEXT,";
        sql += "deal_scope_key TEXT,";
        sql += "position_identifier TEXT,";
        sql += "position_ticket TEXT,";
        sql += "side TEXT,";
        sql += "volume REAL,";
        sql += "price REAL,";
        sql += "bar_time INTEGER,";
        sql += "pivot_bar_time INTEGER,";
        sql += "pivot_rate REAL,";
        sql += "latest_point_bar_time INTEGER,";
        sql += "previous_stop_loss REAL,";
        sql += "stop_loss REAL,";
        sql += "confirmed_stop_loss REAL,";
        sql += "is_confirmed_stop_loss_present INTEGER,";
        sql += "stop_loss_action_kind TEXT,";
        sql += "stop_loss_source TEXT,";
        sql += "trail_skip_reason TEXT,";
        sql += "retcode INTEGER,";
        sql += "exit_intent_reason TEXT,";
        sql += "close_reason TEXT,";
        sql += "broker_reason TEXT,";
        sql += "recovery_issue_code TEXT,";
        sql += "quarantined_pending_text TEXT,";
        sql += "message TEXT NOT NULL,";
        sql += "CHECK(event_type IN ( 'ENTRY_REQUEST', 'ENTRY_RESULT', 'TRAIL_EVALUATION', 'SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT', 'DEAL_ADD', 'EXIT_REQUEST', 'EXIT_RESULT', 'RECOVERY', 'ERROR' )),";
        sql += "CHECK(event_source IN ('EA', 'CALLBACK', 'RECONCILIATION')),";
        sql += "CHECK(LENGTH(event_uid) > 0),";
        sql += "CHECK(sequence > 0),";
        sql += "CHECK(recorded_at > 0),";
        sql += "CHECK(side IS NULL OR side IN ('BUY', 'SELL')),";
        sql += "CHECK(stop_loss_source IS NULL OR stop_loss_source IN ( 'NONE', 'INITIAL_STOP_LOSS', 'M15_ZIGZAG_TRAIL', 'EXTERNAL', 'UNKNOWN' )),";
        sql += "CHECK(stop_loss_action_kind IS NULL OR stop_loss_action_kind IN ( 'TRAIL_CANDIDATE', 'INITIAL_RESTORE', 'TRAIL_RESTORE' )),";
        sql += "CHECK( ( pivot_bar_time IS NULL AND pivot_rate IS NULL AND latest_point_bar_time IS NULL ) OR ( pivot_bar_time IS NOT NULL AND pivot_bar_time > 0 AND pivot_rate IS NOT NULL AND pivot_rate > 0.0 AND latest_point_bar_time IS NOT NULL AND latest_point_bar_time > pivot_bar_time ) ),";
        sql += "CHECK(exit_intent_reason IS NULL OR exit_intent_reason IN ( 'INITIAL_STOP_LOSS_CROSSED', 'M15_ZIGZAG_TRAIL_CROSSED' )),";
        sql += "CHECK(close_reason IS NULL OR close_reason IN ( 'INITIAL_STOP_LOSS', 'INITIAL_STOP_LOSS_CROSSED', 'M15_ZIGZAG_TRAIL', 'EXTERNAL_STOP_LOSS', 'UNKNOWN_STOP_LOSS', 'M15_ZIGZAG_TRAIL_CROSSED', 'EXTERNAL_CLOSE', 'UNKNOWN_CLOSE' )),";
        sql += "CHECK(event_type <> 'TRAIL_EVALUATION' OR ( bar_time IS NOT NULL AND bar_time > 0 AND ( ( trail_skip_reason IS NULL AND stop_loss IS NOT NULL AND stop_loss > 0.0 AND pivot_bar_time IS NOT NULL AND pivot_bar_time > 0 AND pivot_rate IS NOT NULL AND pivot_rate > 0.0 AND latest_point_bar_time IS NOT NULL AND latest_point_bar_time > pivot_bar_time ) OR ( trail_skip_reason IS NOT NULL AND LENGTH(trail_skip_reason) > 0 ) ) )),";
        sql += "CHECK(event_type NOT IN ( 'ENTRY_REQUEST', 'ENTRY_RESULT', 'SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT', 'EXIT_REQUEST', 'EXIT_RESULT' ) OR ( action_uid IS NOT NULL AND LENGTH(action_uid) > 0 )),";
        sql += "CHECK(action_uid IS NULL OR event_type IN ( 'ENTRY_REQUEST', 'ENTRY_RESULT', 'SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT', 'EXIT_REQUEST', 'EXIT_RESULT' )),";
        sql += "CHECK(event_type NOT IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT') OR ( action_uid IS NOT NULL AND LENGTH(action_uid) > 0 AND position_identifier IS NOT NULL AND LENGTH(position_identifier) > 0 AND position_ticket IS NOT NULL AND LENGTH(position_ticket) > 0 AND stop_loss IS NOT NULL AND stop_loss > 0.0 AND stop_loss_action_kind IS NOT NULL )),";
        sql += "CHECK(event_type NOT IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT') OR ( ( stop_loss_action_kind = 'INITIAL_RESTORE' AND bar_time IS NULL AND pivot_bar_time IS NULL AND pivot_rate IS NULL AND latest_point_bar_time IS NULL ) OR ( stop_loss_action_kind IN ('TRAIL_CANDIDATE', 'TRAIL_RESTORE') AND bar_time IS NOT NULL AND bar_time > 0 AND pivot_bar_time IS NOT NULL AND pivot_bar_time > 0 AND pivot_rate IS NOT NULL AND pivot_rate > 0.0 AND latest_point_bar_time IS NOT NULL AND latest_point_bar_time > pivot_bar_time ) )),";
        sql += "CHECK(event_type = 'SL_MODIFY_RESULT' OR ( confirmed_stop_loss IS NULL AND is_confirmed_stop_loss_present IS NULL )),";
        sql += "CHECK(event_type <> 'SL_MODIFY_RESULT' OR ( is_confirmed_stop_loss_present IS NOT NULL AND ( ( is_confirmed_stop_loss_present = 1 AND confirmed_stop_loss IS NOT NULL AND confirmed_stop_loss > 0.0 ) OR ( is_confirmed_stop_loss_present = 0 AND confirmed_stop_loss IS NULL ) ) )),";
        sql += "CHECK(event_type IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT') OR stop_loss_action_kind IS NULL),";
        sql += "CHECK( ( recovery_issue_code IS NULL AND quarantined_pending_text IS NULL ) OR ( event_type = 'RECOVERY' AND recovery_issue_code IS NOT NULL AND LENGTH(recovery_issue_code) > 0 AND quarantined_pending_text IS NOT NULL AND LENGTH(quarantined_pending_text) > 0 ) ),";
        sql += "CHECK(event_type <> 'DEAL_ADD' OR ( deal_ticket IS NOT NULL AND LENGTH(deal_ticket) > 0 AND deal_scope_key IS NOT NULL AND LENGTH(deal_scope_key) > 0 AND broker_time_msc IS NOT NULL AND broker_time_msc > 0 AND position_identifier IS NOT NULL AND LENGTH(position_identifier) > 0 AND side IS NOT NULL AND broker_reason IS NOT NULL AND LENGTH(broker_reason) > 0 )),";
        sql += "FOREIGN KEY(trade_id) REFERENCES m15_ea_trades(id) ON DELETE RESTRICT,";
        sql += "FOREIGN KEY(run_id) REFERENCES m15_ea_runs(id) ON DELETE RESTRICT)";
        return sql;
    }

    /**
     * schema作成と厳密照合で共用する索引定義を返す。
     */
    static bool indexSql(string &fromSql[]) {
        if (ArrayResize(fromSql, 7) != 7) {
            return false;
        }
        fromSql[0] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_trade_events_event_uid ON m15_ea_trade_events(event_uid);";
        fromSql[1] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_trade_events_trade_sequence ON m15_ea_trade_events(trade_id, sequence);";
        fromSql[2] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_trade_events_deal_scope ON m15_ea_trade_events(deal_scope_key) WHERE deal_scope_key IS NOT NULL;";
        fromSql[3] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_trade_events_action_type ON m15_ea_trade_events(action_uid, event_type) WHERE action_uid IS NOT NULL;";
        fromSql[4] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_trade_events_trail_bar ON m15_ea_trade_events(trade_id, event_type, bar_time) WHERE event_type = 'TRAIL_EVALUATION';";
        fromSql[5] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_trade_events_trade_time ON m15_ea_trade_events(trade_id, broker_time_msc, id);";
        fromSql[6] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_trade_events_run_recorded ON m15_ea_trade_events(run_id, recorded_at, id);";
        return true;
    }

    /**
     * 全列をSQLの固定順に列挙する。
     */
    static string columns() {
        return "id,trade_id,run_id,event_uid,action_uid,sequence,event_type,event_source,server_time,broker_time_msc,recorded_at,transaction_type,order_ticket,deal_ticket,deal_scope_key,position_identifier,position_ticket,side,volume,price,bar_time,pivot_bar_time,pivot_rate,latest_point_bar_time,previous_stop_loss,stop_loss,confirmed_stop_loss,is_confirmed_stop_loss_present,stop_loss_action_kind,stop_loss_source,trail_skip_reason,retcode,exit_intent_reason,close_reason,broker_reason,recovery_issue_code,quarantined_pending_text,message";
    }

    /**
     * SQL NULLをEntityの未取得値へ変換するSELECT列を返す。
     */
    static string selectColumns() {
        return "id,trade_id,run_id,event_uid,COALESCE(action_uid,''),sequence,event_type,event_source,COALESCE(server_time,0),COALESCE(broker_time_msc,0),recorded_at,COALESCE(transaction_type,-1),COALESCE(order_ticket,''),COALESCE(deal_ticket,''),COALESCE(deal_scope_key,''),COALESCE(position_identifier,''),COALESCE(position_ticket,''),COALESCE(side,''),COALESCE(volume,1.7976931348623157e308),COALESCE(price,0.0),COALESCE(bar_time,0),COALESCE(pivot_bar_time,0),COALESCE(pivot_rate,0.0),COALESCE(latest_point_bar_time,0),COALESCE(previous_stop_loss,0.0),COALESCE(stop_loss,0.0),COALESCE(confirmed_stop_loss,0.0),COALESCE(is_confirmed_stop_loss_present,-1),COALESCE(stop_loss_action_kind,''),COALESCE(stop_loss_source,''),COALESCE(trail_skip_reason,''),COALESCE(retcode,-1),COALESCE(exit_intent_reason,''),COALESCE(close_reason,''),COALESCE(broker_reason,''),COALESCE(recovery_issue_code,''),COALESCE(quarantined_pending_text,''),message";
    }

    /**
     * Entityの全保存値を固定順に生成する。
     */
    static string values(const EaTradeEvent &fromEntity) {
        string values = "";
        values += "NULL";
        values += "," + IntegerToString((long)fromEntity.tradeId);
        values += "," + IntegerToString((long)fromEntity.runId);
        values += "," + M15EaSql::text(fromEntity.eventUid);
        values += "," + M15EaSql::optionalText(fromEntity.actionUid);
        values += "," + IntegerToString((long)fromEntity.sequence);
        values += "," + M15EaSql::text(fromEntity.eventType);
        values += "," + M15EaSql::text(fromEntity.eventSource);
        values += "," + M15EaSql::optionalLong(fromEntity.serverTime, 0);
        values += "," + M15EaSql::optionalLong(fromEntity.brokerTimeMsc, 0);
        values += "," + IntegerToString((long)fromEntity.recordedAt);
        values += "," + M15EaSql::optionalLong(fromEntity.transactionType, -1);
        values += "," + M15EaSql::optionalText(fromEntity.orderTicket);
        values += "," + M15EaSql::optionalText(fromEntity.dealTicket);
        values += "," + M15EaSql::optionalText(fromEntity.dealScopeKey);
        values += "," + M15EaSql::optionalText(fromEntity.positionIdentifier);
        values += "," + M15EaSql::optionalText(fromEntity.positionTicket);
        values += "," + M15EaSql::optionalText(fromEntity.side);
        values += "," + M15EaSql::real(fromEntity.volume, EMPTY_VALUE);
        values += "," + M15EaSql::real(fromEntity.price, 0.0);
        values += "," + M15EaSql::optionalLong(fromEntity.barTime, 0);
        values += "," + M15EaSql::optionalLong(fromEntity.pivotBarTime, 0);
        values += "," + M15EaSql::real(fromEntity.pivotRate, 0.0);
        values += "," + M15EaSql::optionalLong(fromEntity.latestPointBarTime, 0);
        values += "," + M15EaSql::real(fromEntity.previousStopLoss, 0.0);
        values += "," + M15EaSql::real(fromEntity.stopLoss, 0.0);
        values += "," + M15EaSql::real(fromEntity.confirmedStopLoss, 0.0);
        values += "," + M15EaSql::optionalLong(fromEntity.isConfirmedStopLossPresent, -1);
        values += "," + M15EaSql::optionalText(fromEntity.stopLossActionKind);
        values += "," + M15EaSql::optionalText(fromEntity.stopLossSource);
        values += "," + M15EaSql::optionalText(fromEntity.trailSkipReason);
        values += "," + M15EaSql::optionalLong(fromEntity.retcode, -1);
        values += "," + M15EaSql::optionalText(fromEntity.exitIntentReason);
        values += "," + M15EaSql::optionalText(fromEntity.closeReason);
        values += "," + M15EaSql::optionalText(fromEntity.brokerReason);
        values += "," + M15EaSql::optionalText(fromEntity.recoveryIssueCode);
        values += "," + M15EaSql::optionalText(fromEntity.quarantinedPendingText);
        values += "," + M15EaSql::text(fromEntity.message);
        return values;
    }

    /**
     * 新規行を挿入し採番済みIDを返す。transactionは呼出元が管理する。
     */
    static bool insert(const int fromHandle, EaTradeEvent &fromEntity) {
        string sql = "INSERT INTO m15_ea_trade_events (" + M15EaTradeEventDao::columns()
            + ") VALUES (" + M15EaTradeEventDao::values(fromEntity) + ")";
        if (!M15EaSql::execute(fromHandle, sql)) {
            return false;
        }
        return M15EaSql::scalar(fromHandle, "SELECT last_insert_rowid()", fromEntity.id);
    }

    /**
     * 現在のSELECT行から全列を取得する。
     */
    static bool read(const int fromRequest, EaTradeEvent &fromEntity) {
        fromEntity.reset();
        long integerValue = 0;
        if (!DatabaseColumnLong(fromRequest, 0, fromEntity.id)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 1, fromEntity.tradeId)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 2, fromEntity.runId)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 3, fromEntity.eventUid)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 4, fromEntity.actionUid)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 5, fromEntity.sequence)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 6, fromEntity.eventType)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 7, fromEntity.eventSource)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 8, fromEntity.serverTime)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 9, fromEntity.brokerTimeMsc)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 10, fromEntity.recordedAt)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 11, integerValue)) {
            return false;
        }
        fromEntity.transactionType = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 12, fromEntity.orderTicket)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 13, fromEntity.dealTicket)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 14, fromEntity.dealScopeKey)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 15, fromEntity.positionIdentifier)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 16, fromEntity.positionTicket)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 17, fromEntity.side)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 18, fromEntity.volume)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 19, fromEntity.price)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 20, fromEntity.barTime)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 21, fromEntity.pivotBarTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 22, fromEntity.pivotRate)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 23, fromEntity.latestPointBarTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 24, fromEntity.previousStopLoss)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 25, fromEntity.stopLoss)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 26, fromEntity.confirmedStopLoss)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 27, integerValue)) {
            return false;
        }
        fromEntity.isConfirmedStopLossPresent = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 28, fromEntity.stopLossActionKind)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 29, fromEntity.stopLossSource)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 30, fromEntity.trailSkipReason)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 31, integerValue)) {
            return false;
        }
        fromEntity.retcode = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 32, fromEntity.exitIntentReason)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 33, fromEntity.closeReason)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 34, fromEntity.brokerReason)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 35, fromEntity.recoveryIssueCode)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 36, fromEntity.quarantinedPendingText)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 37, fromEntity.message)) {
            return false;
        }
        return true;
    }

    /**
     * 一件を読み取る。0件とDB障害を区別して返す。
     */
    static bool load(const int fromHandle, const string fromWhere, EaTradeEvent &fromEntity, bool &fromFound) {
        fromFound = false;
        int request = DatabasePrepare(fromHandle, "SELECT " + M15EaTradeEventDao::selectColumns()
            + " FROM m15_ea_trade_events WHERE " + fromWhere + " LIMIT 1");
        if (request == INVALID_HANDLE) {
            return false;
        }
        ResetLastError();
        if (!DatabaseRead(request)) {
            int errorCode = GetLastError();
            DatabaseFinalize(request);
            return errorCode == ERR_DATABASE_NO_MORE_DATA;
        }
        bool success = M15EaTradeEventDao::read(request, fromEntity);
        DatabaseFinalize(request);
        fromFound = success;
        return success;
    }
};

#endif
