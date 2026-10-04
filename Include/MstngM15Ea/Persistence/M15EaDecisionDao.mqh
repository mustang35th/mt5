#ifndef MSTNGM15EA_PERSISTENCE_DECISIONDAO_MQH
#define MSTNGM15EA_PERSISTENCE_DECISIONDAO_MQH

#include <MstngM15Ea\Persistence\M15EaDecisionEntity.mqh>
#include <MstngM15Ea\Persistence\M15EaSql.mqh>

/**
 * M15 EA DecisionのSQL保存と読み取りを担当する。
 */
class M15EaDecisionDao {
public:
    /**
     * M15の判定コアと診断文字列の列・整合制約を返す。
     */
    static string createSql() {
        string sql = "CREATE TABLE IF NOT EXISTS m15_ea_decisions (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "context_key TEXT NOT NULL,";
        sql += "market_signal_key TEXT,";
        sql += "snapshot_hash TEXT NOT NULL,";
        sql += "bar_time INTEGER NOT NULL,";
        sql += "evaluated_server_time INTEGER NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "signal_reference_time INTEGER,";
        sql += "decision TEXT NOT NULL,";
        sql += "reason_code TEXT NOT NULL,";
        sql += "signal_side TEXT,";
        sql += "is_judge_matched INTEGER NOT NULL,";
        sql += "signal_count INTEGER NOT NULL,";
        sql += "entry_count INTEGER NOT NULL,";
        sql += "is_entry_evaluated INTEGER NOT NULL,";
        sql += "is_strategy_entry INTEGER NOT NULL,";
        sql += "is_signal_consumed INTEGER NOT NULL,";
        sql += "spread_pips REAL,";
        sql += "requested_volume REAL,";
        sql += "initial_stop_loss REAL,";
        sql += "initial_risk_pips REAL,";
        sql += "max_initial_risk_pips REAL NOT NULL,";
        sql += "analysis_snapshot_text TEXT NOT NULL,";
        sql += "CHECK(decision IN ('SKIP', 'BUY', 'SELL')),";
        sql += "CHECK(is_judge_matched IN (0, 1)),";
        sql += "CHECK(is_entry_evaluated IN (0, 1)),";
        sql += "CHECK(is_strategy_entry IN (0, 1)),";
        sql += "CHECK(is_signal_consumed IN (0, 1)),";
        sql += "CHECK(entry_count = 1),";
        sql += "CHECK( (is_judge_matched = 0 AND signal_count = 0) OR (is_judge_matched = 1 AND signal_count >= 1) ),";
        sql += "CHECK( (signal_count = 1 AND is_signal_consumed = 1 AND is_entry_evaluated = 1) OR (signal_count <> 1 AND is_signal_consumed = 0 AND is_entry_evaluated = 0) ),";
        sql += "CHECK(is_strategy_entry = 0 OR is_entry_evaluated = 1),";
        sql += "CHECK( is_judge_matched = 0 OR ( signal_reference_time IS NOT NULL AND signal_reference_time > 0 AND signal_side IS NOT NULL AND signal_side IN ('BUY', 'SELL') ) ),";
        sql += "CHECK( decision = 'SKIP' OR ( is_strategy_entry = 1 AND is_signal_consumed = 1 AND decision = signal_side AND initial_stop_loss IS NOT NULL AND initial_stop_loss > 0.0 ) ),";
        sql += "FOREIGN KEY(run_id) REFERENCES m15_ea_runs(id) ON DELETE RESTRICT)";

        return sql;
    }

    /**
     * schema作成と厳密照合で共用する索引定義を返す。
     */
    static bool indexSql(string &fromSql[]) {
        if (ArrayResize(fromSql, 6) != 6) {
            return false;
        }

        fromSql[0] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_decisions_context_bar ON m15_ea_decisions(context_key, bar_time);";
        fromSql[1] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m15_ea_decisions_consumed_signal ON m15_ea_decisions( context_key, signal_reference_time, signal_side ) WHERE is_signal_consumed = 1;";
        fromSql[2] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_decisions_bar ON m15_ea_decisions(bar_time, id);";
        fromSql[3] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_decisions_run_bar ON m15_ea_decisions(run_id, bar_time, id);";
        fromSql[4] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_decisions_result_bar ON m15_ea_decisions(decision, bar_time, id);";
        fromSql[5] = "CREATE INDEX IF NOT EXISTS idx_m15_ea_decisions_reason_bar ON m15_ea_decisions(reason_code, bar_time, id);";

        return true;
    }

    /**
     * 全列をSQLの固定順に列挙する。
     */
    static string columns() {
        return "id,run_id,context_key,market_signal_key,snapshot_hash,bar_time,evaluated_server_time,created_at,signal_reference_time,decision,reason_code,signal_side,is_judge_matched,signal_count,entry_count,is_entry_evaluated,is_strategy_entry,is_signal_consumed,spread_pips,requested_volume,initial_stop_loss,initial_risk_pips,max_initial_risk_pips,analysis_snapshot_text";
    }

    /**
     * SQL NULLをEntityの未取得値へ変換するSELECT列を返す。
     */
    static string selectColumns() {
        return "id,run_id,context_key,COALESCE(market_signal_key,''),snapshot_hash,bar_time,evaluated_server_time,created_at,COALESCE(signal_reference_time,0),decision,reason_code,COALESCE(signal_side,''),is_judge_matched,signal_count,entry_count,is_entry_evaluated,is_strategy_entry,is_signal_consumed,COALESCE(spread_pips,1.7976931348623157e308),COALESCE(requested_volume,1.7976931348623157e308),COALESCE(initial_stop_loss,0.0),COALESCE(initial_risk_pips,0.0),max_initial_risk_pips,analysis_snapshot_text";
    }

    /**
     * Entityの全保存値を固定順に生成する。
     */
    static string values(const M15EaDecisionEntity &fromEntity) {
        string values = "";
        values += "NULL";
        values += "," + IntegerToString((long)fromEntity.runId);
        values += "," + M15EaSql::text(fromEntity.contextKey);
        values += "," + M15EaSql::optionalText(fromEntity.marketSignalKey);
        values += "," + M15EaSql::text(fromEntity.snapshotHash);
        values += "," + IntegerToString((long)fromEntity.barTime);
        values += "," + IntegerToString((long)fromEntity.evaluatedServerTime);
        values += "," + IntegerToString((long)fromEntity.createdAt);
        values += "," + M15EaSql::optionalLong(fromEntity.signalReferenceTime, 0);
        values += "," + M15EaSql::text(fromEntity.decision);
        values += "," + M15EaSql::text(fromEntity.reasonCode);
        values += "," + M15EaSql::optionalText(fromEntity.signalSide);
        values += "," + IntegerToString((long)fromEntity.isJudgeMatched);
        values += "," + IntegerToString((long)fromEntity.signalCount);
        values += "," + IntegerToString((long)fromEntity.entryCount);
        values += "," + IntegerToString((long)fromEntity.isEntryEvaluated);
        values += "," + IntegerToString((long)fromEntity.isStrategyEntry);
        values += "," + IntegerToString((long)fromEntity.isSignalConsumed);
        values += "," + M15EaSql::real(fromEntity.spreadPips, EMPTY_VALUE);
        values += "," + M15EaSql::real(fromEntity.requestedVolume, EMPTY_VALUE);
        values += "," + M15EaSql::real(fromEntity.initialStopLoss, 0.0);
        values += "," + M15EaSql::real(fromEntity.initialRiskPips, 0.0);
        values += "," + M15EaSql::real(fromEntity.maxInitialRiskPips, 0.0);
        values += "," + M15EaSql::text(fromEntity.analysisSnapshotText);

        return values;
    }

    /**
     * 新規行を挿入し採番済みIDを返す。transactionは呼出元が管理する。
     */
    static bool insert(const int fromHandle, M15EaDecisionEntity &fromEntity) {
        if (StringFind(fromEntity.analysisSnapshotText, "M15_EA_DECISION_V1|") != 0) {
            return false;
        }

        string sql = "INSERT INTO m15_ea_decisions (" + M15EaDecisionDao::columns()
            + ") VALUES (" + M15EaDecisionDao::values(fromEntity) + ")";
        if (!M15EaSql::execute(fromHandle, sql)) {
            return false;
        }

        return M15EaSql::scalar(fromHandle, "SELECT last_insert_rowid()", fromEntity.id);
    }

    /**
     * 現在のSELECT行から全列を取得する。
     */
    static bool read(const int fromRequest, M15EaDecisionEntity &fromEntity) {
        fromEntity.reset();

        long integerValue = 0;
        if (!DatabaseColumnLong(fromRequest, 0, fromEntity.id)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 1, fromEntity.runId)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 2, fromEntity.contextKey)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 3, fromEntity.marketSignalKey)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 4, fromEntity.snapshotHash)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 5, fromEntity.barTime)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 6, fromEntity.evaluatedServerTime)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 7, fromEntity.createdAt)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 8, fromEntity.signalReferenceTime)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 9, fromEntity.decision)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 10, fromEntity.reasonCode)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 11, fromEntity.signalSide)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 12, integerValue)) {
            return false;
        }

        fromEntity.isJudgeMatched = (bool)integerValue;
        if (!DatabaseColumnLong(fromRequest, 13, integerValue)) {
            return false;
        }

        fromEntity.signalCount = (int)integerValue;
        if (!DatabaseColumnLong(fromRequest, 14, integerValue)) {
            return false;
        }

        fromEntity.entryCount = (int)integerValue;
        if (!DatabaseColumnLong(fromRequest, 15, integerValue)) {
            return false;
        }

        fromEntity.isEntryEvaluated = (bool)integerValue;
        if (!DatabaseColumnLong(fromRequest, 16, integerValue)) {
            return false;
        }

        fromEntity.isStrategyEntry = (bool)integerValue;
        if (!DatabaseColumnLong(fromRequest, 17, integerValue)) {
            return false;
        }

        fromEntity.isSignalConsumed = (bool)integerValue;
        if (!DatabaseColumnDouble(fromRequest, 18, fromEntity.spreadPips)) {
            return false;
        }

        if (!DatabaseColumnDouble(fromRequest, 19, fromEntity.requestedVolume)) {
            return false;
        }

        if (!DatabaseColumnDouble(fromRequest, 20, fromEntity.initialStopLoss)) {
            return false;
        }

        if (!DatabaseColumnDouble(fromRequest, 21, fromEntity.initialRiskPips)) {
            return false;
        }

        if (!DatabaseColumnDouble(fromRequest, 22, fromEntity.maxInitialRiskPips)) {
            return false;
        }

        return DatabaseColumnText(fromRequest, 23, fromEntity.analysisSnapshotText)
            && StringFind(fromEntity.analysisSnapshotText, "M15_EA_DECISION_V1|") == 0;
    }

    /**
     * 一件を読み取る。0件とDB障害を区別して返す。
     */
    static bool load(const int fromHandle, const string fromWhere, M15EaDecisionEntity &fromEntity, bool &fromFound) {
        fromFound = false;

        int request = DatabasePrepare(fromHandle, "SELECT " + M15EaDecisionDao::selectColumns()
            + " FROM m15_ea_decisions WHERE " + fromWhere + " LIMIT 1");
        if (request == INVALID_HANDLE) {
            return false;
        }

        ResetLastError();
        if (!DatabaseRead(request)) {
            int errorCode = GetLastError();
            DatabaseFinalize(request);
            return errorCode == ERR_DATABASE_NO_MORE_DATA;
        }

        bool success = M15EaDecisionDao::read(request, fromEntity);
        DatabaseFinalize(request);
        fromFound = success;

        return success;
    }

};

#endif
