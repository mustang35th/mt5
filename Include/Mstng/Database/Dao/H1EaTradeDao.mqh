#ifndef MSTNG_DATABASE_DAO_H1EATRADEDAO_MQH
#define MSTNG_DATABASE_DAO_H1EATRADEDAO_MQH

#include <Mstng\Database\Dao\H1EaSql.mqh>
#include <Mstng\Database\Entity\H1EaTradeEntity.mqh>

/**
 * H1 EA TradeのSQL保存と読み取りを担当する。
 */
class H1EaTradeDao {
public:
    /**
     * 初版の列・整合制約を返す。
     */
    static string createSql() {
        string sql = "CREATE TABLE IF NOT EXISTS h1_ea_trades (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "created_run_id INTEGER NOT NULL,";
        sql += "decision_id INTEGER,";
        sql += "context_key TEXT NOT NULL,";
        sql += "origin TEXT NOT NULL,";
        sql += "status TEXT NOT NULL,";
        sql += "side TEXT NOT NULL,";
        sql += "requested_volume REAL,";
        sql += "requested_stop_loss REAL,";
        sql += "entry_requested_server_time INTEGER,";
        sql += "entry_order_ticket TEXT,";
        sql += "entry_deal_ticket TEXT,";
        sql += "entry_retcode INTEGER,";
        sql += "position_identifier TEXT,";
        sql += "position_ticket TEXT,";
        sql += "opened_at_msc INTEGER,";
        sql += "open_price REAL,";
        sql += "opened_volume REAL,";
        sql += "remaining_entry_volume REAL,";
        sql += "current_stop_loss REAL,";
        sql += "stop_loss_source TEXT NOT NULL,";
        sql += "last_trail_evaluated_h1_bar_time INTEGER,";
        sql += "pending_stop_loss_kind TEXT,";
        sql += "pending_stop_loss_h1_bar_time INTEGER,";
        sql += "pending_stop_loss REAL,";
        sql += "pending_stop_loss_pivot_time INTEGER,";
        sql += "pending_stop_loss_pivot_rate REAL,";
        sql += "pending_stop_loss_latest_time INTEGER,";
        sql += "pending_stop_loss_action_uid TEXT,";
        sql += "last_applied_trail_h1_bar_time INTEGER,";
        sql += "last_applied_trail_stop_loss REAL,";
        sql += "last_applied_trail_pivot_time INTEGER,";
        sql += "last_applied_trail_pivot_rate REAL,";
        sql += "last_applied_trail_latest_time INTEGER,";
        sql += "exit_requested_server_time INTEGER,";
        sql += "exit_order_ticket TEXT,";
        sql += "exit_deal_ticket TEXT,";
        sql += "exit_retcode INTEGER,";
        sql += "closed_at_msc INTEGER,";
        sql += "close_price REAL,";
        sql += "remaining_position_volume REAL,";
        sql += "exit_intent_reason TEXT,";
        sql += "close_reason TEXT,";
        sql += "broker_close_reason TEXT,";
        sql += "profit REAL,";
        sql += "commission REAL,";
        sql += "swap REAL,";
        sql += "fee REAL,";
        sql += "last_error TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "CHECK(origin IN ('NORMAL', 'RECOVERED')),";
        sql += "CHECK(side IN ('BUY', 'SELL')),";
        sql += "CHECK(stop_loss_source IN ( 'NONE', 'INITIAL_STOP_LOSS', 'H1_ZIGZAG_TRAIL', 'EXTERNAL', 'UNKNOWN' )),";
        sql += "CHECK( ( current_stop_loss IS NULL AND stop_loss_source IN ('NONE', 'UNKNOWN') ) OR ( current_stop_loss IS NOT NULL AND current_stop_loss > 0.0 AND stop_loss_source <> 'NONE' ) ),";
        sql += "CHECK(last_trail_evaluated_h1_bar_time IS NULL OR last_trail_evaluated_h1_bar_time > 0),";
        sql += "CHECK(exit_intent_reason IS NULL OR exit_intent_reason IN ( 'INITIAL_STOP_LOSS_CROSSED', 'H1_ZIGZAG_TRAIL_CROSSED' )),";
        sql += "CHECK(close_reason IS NULL OR close_reason IN ( 'INITIAL_STOP_LOSS', 'INITIAL_STOP_LOSS_CROSSED', 'H1_ZIGZAG_TRAIL', 'EXTERNAL_STOP_LOSS', 'UNKNOWN_STOP_LOSS', 'H1_ZIGZAG_TRAIL_CROSSED', 'EXTERNAL_CLOSE', 'UNKNOWN_CLOSE' )),";
        sql += "CHECK(status IN ( 'OPEN_PENDING', 'OPEN_PARTIAL', 'OPEN', 'CLOSE_PENDING', 'CLOSE_PARTIAL', 'CLOSED', 'OPEN_FAILED', 'RECOVERY_REQUIRED' )),";
        sql += "CHECK(pending_stop_loss_kind IS NULL OR pending_stop_loss_kind IN ( 'TRAIL_CANDIDATE', 'INITIAL_RESTORE', 'TRAIL_RESTORE' )),";
        sql += "CHECK(pending_stop_loss IS NULL OR pending_stop_loss_kind IS NOT NULL),";
        sql += "CHECK( ( pending_stop_loss_kind IS NULL AND pending_stop_loss_h1_bar_time IS NULL AND pending_stop_loss IS NULL AND pending_stop_loss_pivot_time IS NULL AND pending_stop_loss_pivot_rate IS NULL AND pending_stop_loss_latest_time IS NULL AND pending_stop_loss_action_uid IS NULL ) OR ( pending_stop_loss_kind = 'INITIAL_RESTORE' AND pending_stop_loss_h1_bar_time IS NULL AND pending_stop_loss IS NOT NULL AND pending_stop_loss > 0.0 AND pending_stop_loss_pivot_time IS NULL AND pending_stop_loss_pivot_rate IS NULL AND pending_stop_loss_latest_time IS NULL ) OR ( pending_stop_loss_kind IN ('TRAIL_CANDIDATE', 'TRAIL_RESTORE') AND pending_stop_loss_h1_bar_time IS NOT NULL AND pending_stop_loss_h1_bar_time > 0 AND pending_stop_loss IS NOT NULL AND pending_stop_loss > 0.0 AND pending_stop_loss_pivot_time IS NOT NULL AND pending_stop_loss_pivot_time > 0 AND pending_stop_loss_pivot_rate IS NOT NULL AND pending_stop_loss_pivot_rate > 0.0 AND pending_stop_loss_latest_time IS NOT NULL AND pending_stop_loss_latest_time > pending_stop_loss_pivot_time ) ),";
        sql += "CHECK( ( last_applied_trail_h1_bar_time IS NULL AND last_applied_trail_stop_loss IS NULL AND last_applied_trail_pivot_time IS NULL AND last_applied_trail_pivot_rate IS NULL AND last_applied_trail_latest_time IS NULL ) OR ( last_applied_trail_h1_bar_time IS NOT NULL AND last_applied_trail_h1_bar_time > 0 AND last_applied_trail_stop_loss IS NOT NULL AND last_applied_trail_stop_loss > 0.0 AND last_applied_trail_pivot_time IS NOT NULL AND last_applied_trail_pivot_time > 0 AND last_applied_trail_pivot_rate IS NOT NULL AND last_applied_trail_pivot_rate > 0.0 AND last_applied_trail_latest_time IS NOT NULL AND last_applied_trail_latest_time > last_applied_trail_pivot_time ) ),";
        sql += "CHECK(pending_stop_loss_action_uid IS NULL OR ( LENGTH(pending_stop_loss_action_uid) > 0 AND pending_stop_loss IS NOT NULL )),";
        sql += "CHECK(pending_stop_loss IS NULL OR status IN ('OPEN', 'RECOVERY_REQUIRED') OR (status = 'OPEN_PARTIAL' AND pending_stop_loss_kind = 'INITIAL_RESTORE')),";
        sql += "CHECK(status <> 'CLOSED' OR ( closed_at_msc IS NOT NULL AND closed_at_msc > 0 AND close_reason IS NOT NULL AND LENGTH(close_reason) > 0 AND broker_close_reason IS NOT NULL AND LENGTH(broker_close_reason) > 0 AND pending_stop_loss IS NULL )),";
        sql += "FOREIGN KEY(created_run_id) REFERENCES h1_ea_runs(id) ON DELETE RESTRICT,";
        sql += "FOREIGN KEY(decision_id) REFERENCES h1_ea_decisions(id) ON DELETE RESTRICT,";
        sql += "CHECK(origin <> 'NORMAL' OR decision_id IS NOT NULL))";
        return sql;
    }

    /**
     * テーブルおよび検索・一意索引を準備する。
     */
    static bool createTable(const int fromHandle) {
        if (!H1EaSql::execute(fromHandle, H1EaTradeDao::createSql())) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_decision ON h1_ea_trades(decision_id) WHERE decision_id IS NOT NULL;")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_active_context ON h1_ea_trades(context_key) WHERE status IN ( 'OPEN_PENDING', 'OPEN_PARTIAL', 'OPEN', 'CLOSE_PENDING', 'CLOSE_PARTIAL', 'RECOVERY_REQUIRED' );")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_trades_position_identifier ON h1_ea_trades(context_key, position_identifier) WHERE position_identifier IS NOT NULL;")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_status_updated ON h1_ea_trades(status, updated_at, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_context_updated ON h1_ea_trades(context_key, updated_at, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_closed ON h1_ea_trades(closed_at_msc, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_trades_pending_stop_loss ON h1_ea_trades(context_key, pending_stop_loss_h1_bar_time, id) WHERE pending_stop_loss IS NOT NULL;")) {
            return false;
        }
        return true;
    }

    /**
     * 全列をSQLの固定順に列挙する。
     */
    static string columns() {
        return "id,created_run_id,decision_id,context_key,origin,status,side,requested_volume,requested_stop_loss,entry_requested_server_time,entry_order_ticket,entry_deal_ticket,entry_retcode,position_identifier,position_ticket,opened_at_msc,open_price,opened_volume,remaining_entry_volume,current_stop_loss,stop_loss_source,last_trail_evaluated_h1_bar_time,pending_stop_loss_kind,pending_stop_loss_h1_bar_time,pending_stop_loss,pending_stop_loss_pivot_time,pending_stop_loss_pivot_rate,pending_stop_loss_latest_time,pending_stop_loss_action_uid,last_applied_trail_h1_bar_time,last_applied_trail_stop_loss,last_applied_trail_pivot_time,last_applied_trail_pivot_rate,last_applied_trail_latest_time,exit_requested_server_time,exit_order_ticket,exit_deal_ticket,exit_retcode,closed_at_msc,close_price,remaining_position_volume,exit_intent_reason,close_reason,broker_close_reason,profit,commission,swap,fee,last_error,created_at,updated_at";
    }

    /**
     * 隔離対象pendingのSQLite実型とSQLリテラルを固定順で取得する。
     */
    static string pendingRawColumns() {
        return "typeof(pending_stop_loss_kind),quote(pending_stop_loss_kind),typeof(pending_stop_loss_h1_bar_time),quote(pending_stop_loss_h1_bar_time),typeof(pending_stop_loss),quote(pending_stop_loss),typeof(pending_stop_loss_pivot_time),quote(pending_stop_loss_pivot_time),typeof(pending_stop_loss_pivot_rate),quote(pending_stop_loss_pivot_rate),typeof(pending_stop_loss_latest_time),quote(pending_stop_loss_latest_time),typeof(pending_stop_loss_action_uid),quote(pending_stop_loss_action_uid)";
    }

    /**
     * SQL NULLをEntityの未取得値へ変換するSELECT列を返す。
     */
    static string selectColumns() {
        return "id,created_run_id,COALESCE(decision_id,0),context_key,origin,status,side,COALESCE(requested_volume,1.7976931348623157e308),COALESCE(requested_stop_loss,0.0),COALESCE(entry_requested_server_time,0),COALESCE(entry_order_ticket,''),COALESCE(entry_deal_ticket,''),COALESCE(entry_retcode,-1),COALESCE(position_identifier,''),COALESCE(position_ticket,''),COALESCE(opened_at_msc,0),COALESCE(open_price,0.0),COALESCE(opened_volume,1.7976931348623157e308),COALESCE(remaining_entry_volume,1.7976931348623157e308),COALESCE(current_stop_loss,0.0),stop_loss_source,COALESCE(last_trail_evaluated_h1_bar_time,0),COALESCE(pending_stop_loss_kind,''),COALESCE(pending_stop_loss_h1_bar_time,0),COALESCE(pending_stop_loss,0.0),COALESCE(pending_stop_loss_pivot_time,0),COALESCE(pending_stop_loss_pivot_rate,0.0),COALESCE(pending_stop_loss_latest_time,0),COALESCE(pending_stop_loss_action_uid,''),COALESCE(last_applied_trail_h1_bar_time,0),COALESCE(last_applied_trail_stop_loss,0.0),COALESCE(last_applied_trail_pivot_time,0),COALESCE(last_applied_trail_pivot_rate,0.0),COALESCE(last_applied_trail_latest_time,0),COALESCE(exit_requested_server_time,0),COALESCE(exit_order_ticket,''),COALESCE(exit_deal_ticket,''),COALESCE(exit_retcode,-1),COALESCE(closed_at_msc,0),COALESCE(close_price,0.0),COALESCE(remaining_position_volume,1.7976931348623157e308),COALESCE(exit_intent_reason,''),COALESCE(close_reason,''),COALESCE(broker_close_reason,''),COALESCE(profit,1.7976931348623157e308),COALESCE(commission,1.7976931348623157e308),COALESCE(swap,1.7976931348623157e308),COALESCE(fee,1.7976931348623157e308),last_error,created_at,updated_at";
    }

    /**
     * Entityの全保存値を固定順に生成する。
     */
    static string values(const H1EaTradeEntity &fromEntity) {
        string values = "";
        values += "NULL";
        values += "," + IntegerToString((long)fromEntity.createdRunId);
        values += "," + H1EaSql::optionalLong(fromEntity.decisionId, 0);
        values += "," + H1EaSql::text(fromEntity.contextKey);
        values += "," + H1EaSql::text(fromEntity.origin);
        values += "," + H1EaSql::text(fromEntity.status);
        values += "," + H1EaSql::text(fromEntity.side);
        values += "," + H1EaSql::real(fromEntity.requestedVolume, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.requestedStopLoss, 0.0);
        values += "," + H1EaSql::optionalLong(fromEntity.entryRequestedServerTime, 0);
        values += "," + H1EaSql::optionalText(fromEntity.entryOrderTicket);
        values += "," + H1EaSql::optionalText(fromEntity.entryDealTicket);
        values += "," + H1EaSql::optionalLong(fromEntity.entryRetcode, -1);
        values += "," + H1EaSql::optionalText(fromEntity.positionIdentifier);
        values += "," + H1EaSql::optionalText(fromEntity.positionTicket);
        values += "," + H1EaSql::optionalLong(fromEntity.openedAtMsc, 0);
        values += "," + H1EaSql::real(fromEntity.openPrice, 0.0);
        values += "," + H1EaSql::real(fromEntity.openedVolume, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.remainingEntryVolume, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.currentStopLoss, 0.0);
        values += "," + H1EaSql::text(fromEntity.stopLossSource);
        values += "," + H1EaSql::optionalLong(fromEntity.lastTrailEvaluatedH1BarTime, 0);
        values += "," + H1EaSql::optionalText(fromEntity.pendingStopLossKind);
        values += "," + H1EaSql::optionalLong(fromEntity.pendingStopLossH1BarTime, 0);
        values += "," + H1EaSql::real(fromEntity.pendingStopLoss, 0.0);
        values += "," + H1EaSql::optionalLong(fromEntity.pendingStopLossPivotTime, 0);
        values += "," + H1EaSql::real(fromEntity.pendingStopLossPivotRate, 0.0);
        values += "," + H1EaSql::optionalLong(fromEntity.pendingStopLossLatestTime, 0);
        values += "," + H1EaSql::optionalText(fromEntity.pendingStopLossActionUid);
        values += "," + H1EaSql::optionalLong(fromEntity.lastAppliedTrailH1BarTime, 0);
        values += "," + H1EaSql::real(fromEntity.lastAppliedTrailStopLoss, 0.0);
        values += "," + H1EaSql::optionalLong(fromEntity.lastAppliedTrailPivotTime, 0);
        values += "," + H1EaSql::real(fromEntity.lastAppliedTrailPivotRate, 0.0);
        values += "," + H1EaSql::optionalLong(fromEntity.lastAppliedTrailLatestTime, 0);
        values += "," + H1EaSql::optionalLong(fromEntity.exitRequestedServerTime, 0);
        values += "," + H1EaSql::optionalText(fromEntity.exitOrderTicket);
        values += "," + H1EaSql::optionalText(fromEntity.exitDealTicket);
        values += "," + H1EaSql::optionalLong(fromEntity.exitRetcode, -1);
        values += "," + H1EaSql::optionalLong(fromEntity.closedAtMsc, 0);
        values += "," + H1EaSql::real(fromEntity.closePrice, 0.0);
        values += "," + H1EaSql::real(fromEntity.remainingPositionVolume, EMPTY_VALUE);
        values += "," + H1EaSql::optionalText(fromEntity.exitIntentReason);
        values += "," + H1EaSql::optionalText(fromEntity.closeReason);
        values += "," + H1EaSql::optionalText(fromEntity.brokerCloseReason);
        values += "," + H1EaSql::real(fromEntity.profit, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.commission, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.swap, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.fee, EMPTY_VALUE);
        values += "," + H1EaSql::text(fromEntity.lastError);
        values += "," + IntegerToString((long)fromEntity.createdAt);
        values += "," + IntegerToString((long)fromEntity.updatedAt);
        return values;
    }

    /**
     * 新規行を挿入し採番済みIDを返す。transactionは呼出元が管理する。
     */
    static bool insert(const int fromHandle, H1EaTradeEntity &fromEntity) {
        string sql = "INSERT INTO h1_ea_trades (" + H1EaTradeDao::columns()
            + ") VALUES (" + H1EaTradeDao::values(fromEntity) + ")";
        if (!H1EaSql::execute(fromHandle, sql)) {
            return false;
        }
        return H1EaSql::scalar(fromHandle, "SELECT last_insert_rowid()", fromEntity.id);
    }

    /**
     * 現在スナップショットを更新する。履歴DecisionとEventは更新しない。
     */
    static bool update(const int fromHandle, const H1EaTradeEntity &fromEntity) {
        string sql = "UPDATE h1_ea_trades SET ";
        sql += "created_run_id=" + IntegerToString((long)fromEntity.createdRunId);
        sql += ",decision_id=" + H1EaSql::optionalLong(fromEntity.decisionId, 0);
        sql += ",context_key=" + H1EaSql::text(fromEntity.contextKey);
        sql += ",origin=" + H1EaSql::text(fromEntity.origin);
        sql += ",status=" + H1EaSql::text(fromEntity.status);
        sql += ",side=" + H1EaSql::text(fromEntity.side);
        sql += ",requested_volume=" + H1EaSql::real(fromEntity.requestedVolume, EMPTY_VALUE);
        sql += ",requested_stop_loss=" + H1EaSql::real(fromEntity.requestedStopLoss, 0.0);
        sql += ",entry_requested_server_time=" + H1EaSql::optionalLong(fromEntity.entryRequestedServerTime, 0);
        sql += ",entry_order_ticket=" + H1EaSql::optionalText(fromEntity.entryOrderTicket);
        sql += ",entry_deal_ticket=" + H1EaSql::optionalText(fromEntity.entryDealTicket);
        sql += ",entry_retcode=" + H1EaSql::optionalLong(fromEntity.entryRetcode, -1);
        sql += ",position_identifier=" + H1EaSql::optionalText(fromEntity.positionIdentifier);
        sql += ",position_ticket=" + H1EaSql::optionalText(fromEntity.positionTicket);
        sql += ",opened_at_msc=" + H1EaSql::optionalLong(fromEntity.openedAtMsc, 0);
        sql += ",open_price=" + H1EaSql::real(fromEntity.openPrice, 0.0);
        sql += ",opened_volume=" + H1EaSql::real(fromEntity.openedVolume, EMPTY_VALUE);
        sql += ",remaining_entry_volume=" + H1EaSql::real(fromEntity.remainingEntryVolume, EMPTY_VALUE);
        sql += ",current_stop_loss=" + H1EaSql::real(fromEntity.currentStopLoss, 0.0);
        sql += ",stop_loss_source=" + H1EaSql::text(fromEntity.stopLossSource);
        sql += ",last_trail_evaluated_h1_bar_time=" + H1EaSql::optionalLong(fromEntity.lastTrailEvaluatedH1BarTime, 0);
        sql += ",pending_stop_loss_kind=" + H1EaSql::optionalText(fromEntity.pendingStopLossKind);
        sql += ",pending_stop_loss_h1_bar_time=" + H1EaSql::optionalLong(fromEntity.pendingStopLossH1BarTime, 0);
        sql += ",pending_stop_loss=" + H1EaSql::real(fromEntity.pendingStopLoss, 0.0);
        sql += ",pending_stop_loss_pivot_time=" + H1EaSql::optionalLong(fromEntity.pendingStopLossPivotTime, 0);
        sql += ",pending_stop_loss_pivot_rate=" + H1EaSql::real(fromEntity.pendingStopLossPivotRate, 0.0);
        sql += ",pending_stop_loss_latest_time=" + H1EaSql::optionalLong(fromEntity.pendingStopLossLatestTime, 0);
        sql += ",pending_stop_loss_action_uid=" + H1EaSql::optionalText(fromEntity.pendingStopLossActionUid);
        sql += ",last_applied_trail_h1_bar_time=" + H1EaSql::optionalLong(fromEntity.lastAppliedTrailH1BarTime, 0);
        sql += ",last_applied_trail_stop_loss=" + H1EaSql::real(fromEntity.lastAppliedTrailStopLoss, 0.0);
        sql += ",last_applied_trail_pivot_time=" + H1EaSql::optionalLong(fromEntity.lastAppliedTrailPivotTime, 0);
        sql += ",last_applied_trail_pivot_rate=" + H1EaSql::real(fromEntity.lastAppliedTrailPivotRate, 0.0);
        sql += ",last_applied_trail_latest_time=" + H1EaSql::optionalLong(fromEntity.lastAppliedTrailLatestTime, 0);
        sql += ",exit_requested_server_time=" + H1EaSql::optionalLong(fromEntity.exitRequestedServerTime, 0);
        sql += ",exit_order_ticket=" + H1EaSql::optionalText(fromEntity.exitOrderTicket);
        sql += ",exit_deal_ticket=" + H1EaSql::optionalText(fromEntity.exitDealTicket);
        sql += ",exit_retcode=" + H1EaSql::optionalLong(fromEntity.exitRetcode, -1);
        sql += ",closed_at_msc=" + H1EaSql::optionalLong(fromEntity.closedAtMsc, 0);
        sql += ",close_price=" + H1EaSql::real(fromEntity.closePrice, 0.0);
        sql += ",remaining_position_volume=" + H1EaSql::real(fromEntity.remainingPositionVolume, EMPTY_VALUE);
        sql += ",exit_intent_reason=" + H1EaSql::optionalText(fromEntity.exitIntentReason);
        sql += ",close_reason=" + H1EaSql::optionalText(fromEntity.closeReason);
        sql += ",broker_close_reason=" + H1EaSql::optionalText(fromEntity.brokerCloseReason);
        sql += ",profit=" + H1EaSql::real(fromEntity.profit, EMPTY_VALUE);
        sql += ",commission=" + H1EaSql::real(fromEntity.commission, EMPTY_VALUE);
        sql += ",swap=" + H1EaSql::real(fromEntity.swap, EMPTY_VALUE);
        sql += ",fee=" + H1EaSql::real(fromEntity.fee, EMPTY_VALUE);
        sql += ",last_error=" + H1EaSql::text(fromEntity.lastError);
        sql += ",created_at=" + IntegerToString((long)fromEntity.createdAt);
        sql += ",updated_at=" + IntegerToString((long)fromEntity.updatedAt);
        sql += " WHERE id=" + IntegerToString(fromEntity.id);
        if (!H1EaSql::execute(fromHandle, sql)) {
            return false;
        }
        long changed = 0;
        return H1EaSql::scalar(fromHandle, "SELECT changes()", changed) && changed == 1;
    }

    /**
     * 現在のSELECT行から全列を取得する。
     */
    static bool read(const int fromRequest, H1EaTradeEntity &fromEntity) {
        fromEntity.reset();
        long integerValue = 0;
        if (!DatabaseColumnLong(fromRequest, 0, fromEntity.id)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 1, fromEntity.createdRunId)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 2, fromEntity.decisionId)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 3, fromEntity.contextKey)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 4, fromEntity.origin)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 5, fromEntity.status)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 6, fromEntity.side)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 7, fromEntity.requestedVolume)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 8, fromEntity.requestedStopLoss)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 9, fromEntity.entryRequestedServerTime)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 10, fromEntity.entryOrderTicket)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 11, fromEntity.entryDealTicket)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 12, integerValue)) {
            return false;
        }
        fromEntity.entryRetcode = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 13, fromEntity.positionIdentifier)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 14, fromEntity.positionTicket)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 15, fromEntity.openedAtMsc)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 16, fromEntity.openPrice)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 17, fromEntity.openedVolume)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 18, fromEntity.remainingEntryVolume)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 19, fromEntity.currentStopLoss)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 20, fromEntity.stopLossSource)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 21, fromEntity.lastTrailEvaluatedH1BarTime)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 22, fromEntity.pendingStopLossKind)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 23, fromEntity.pendingStopLossH1BarTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 24, fromEntity.pendingStopLoss)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 25, fromEntity.pendingStopLossPivotTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 26, fromEntity.pendingStopLossPivotRate)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 27, fromEntity.pendingStopLossLatestTime)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 28, fromEntity.pendingStopLossActionUid)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 29, fromEntity.lastAppliedTrailH1BarTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 30, fromEntity.lastAppliedTrailStopLoss)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 31, fromEntity.lastAppliedTrailPivotTime)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 32, fromEntity.lastAppliedTrailPivotRate)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 33, fromEntity.lastAppliedTrailLatestTime)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 34, fromEntity.exitRequestedServerTime)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 35, fromEntity.exitOrderTicket)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 36, fromEntity.exitDealTicket)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 37, integerValue)) {
            return false;
        }
        fromEntity.exitRetcode = (int)integerValue;
        if (!DatabaseColumnLong(fromRequest, 38, fromEntity.closedAtMsc)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 39, fromEntity.closePrice)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 40, fromEntity.remainingPositionVolume)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 41, fromEntity.exitIntentReason)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 42, fromEntity.closeReason)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 43, fromEntity.brokerCloseReason)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 44, fromEntity.profit)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 45, fromEntity.commission)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 46, fromEntity.swap)) {
            return false;
        }
        if (!DatabaseColumnDouble(fromRequest, 47, fromEntity.fee)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 48, fromEntity.lastError)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 49, fromEntity.createdAt)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 50, fromEntity.updatedAt)) {
            return false;
        }
        return true;
    }

    /**
     * 一件を読み取る。0件とDB障害を区別して返す。
     */
    static bool load(const int fromHandle, const string fromWhere, H1EaTradeEntity &fromEntity, bool &fromFound) {
        fromFound = false;
        int request = DatabasePrepare(fromHandle, "SELECT " + H1EaTradeDao::selectColumns()
            + " FROM h1_ea_trades WHERE " + fromWhere + " LIMIT 1");
        if (request == INVALID_HANDLE) {
            return false;
        }
        ResetLastError();
        if (!DatabaseRead(request)) {
            int errorCode = GetLastError();
            DatabaseFinalize(request);
            return errorCode == ERR_DATABASE_NO_MORE_DATA;
        }
        bool success = H1EaTradeDao::read(request, fromEntity);
        DatabaseFinalize(request);
        fromFound = success;
        return success;
    }
};

#endif
