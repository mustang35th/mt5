#ifndef MSTNG_DATABASE_DAO_H1EADECISIONDAO_MQH
#define MSTNG_DATABASE_DAO_H1EADECISIONDAO_MQH

#include <Mstng\Database\Dao\H1EaSql.mqh>
#include <Mstng\Database\Entity\H1EaDecisionEntity.mqh>

/**
 * H1 EA DecisionのSQL保存と読み取りを担当する。
 */
class H1EaDecisionDao {
public:
    /**
     * 初版の列・整合制約を返す。
     */
    static string createSql() {
        string sql = "CREATE TABLE IF NOT EXISTS h1_ea_decisions (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "context_key TEXT NOT NULL,";
        sql += "market_signal_key TEXT,";
        sql += "snapshot_hash TEXT NOT NULL,";
        sql += "h1_bar_time INTEGER NOT NULL,";
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
        sql += "mn1_direction TEXT,";
        sql += "w1_direction TEXT,";
        sql += "d1_direction TEXT,";
        sql += "h4_direction TEXT,";
        sql += "h1_direction TEXT,";
        sql += "h1_wave_direction TEXT,";
        sql += "h1_elliot_label TEXT,";
        sql += "h4_elliot_label TEXT,";
        sql += "is_h1_wave_accepted INTEGER NOT NULL,";
        sql += "is_h4_wave_accepted INTEGER NOT NULL,";
        sql += "h1_gmma_trend_count INTEGER,";
        sql += "h1_gmma_cross_count INTEGER,";
        sql += "h1_ema200_direction TEXT,";
        sql += "h4_ema200_direction TEXT,";
        sql += "w1_ema200_direction TEXT,";
        sql += "h1_direction_alignment_mode TEXT NOT NULL,";
        sql += "is_h1_direction_alignment_passed INTEGER NOT NULL,";
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
        sql += "CHECK(is_h1_wave_accepted IN (0,1)),";
        sql += "CHECK(is_h4_wave_accepted IN (0,1)),";
        sql += "CHECK(is_h1_direction_alignment_passed IN (0,1)),";
        sql += "FOREIGN KEY(run_id) REFERENCES h1_ea_runs(id) ON DELETE RESTRICT)";
        return sql;
    }

    /**
     * テーブルおよび検索・一意索引を準備する。
     */
    static bool createTable(const int fromHandle) {
        if (!H1EaSql::execute(fromHandle, H1EaDecisionDao::createSql())) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_decisions_context_bar ON h1_ea_decisions(context_key, h1_bar_time);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE UNIQUE INDEX IF NOT EXISTS idx_h1_ea_decisions_consumed_signal ON h1_ea_decisions( context_key, signal_reference_time, signal_side ) WHERE is_signal_consumed = 1;")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_bar ON h1_ea_decisions(h1_bar_time, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_run_bar ON h1_ea_decisions(run_id, h1_bar_time, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_result_bar ON h1_ea_decisions(decision, h1_bar_time, id);")) {
            return false;
        }
        if (!H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_decisions_reason_bar ON h1_ea_decisions(reason_code, h1_bar_time, id);")) {
            return false;
        }
        return true;
    }

    /**
     * 全列をSQLの固定順に列挙する。
     */
    static string columns() {
        return "id,run_id,context_key,market_signal_key,snapshot_hash,h1_bar_time,evaluated_server_time,created_at,signal_reference_time,decision,reason_code,signal_side,is_judge_matched,signal_count,entry_count,is_entry_evaluated,is_strategy_entry,is_signal_consumed,spread_pips,requested_volume,initial_stop_loss,initial_risk_pips,max_initial_risk_pips,mn1_direction,w1_direction,d1_direction,h4_direction,h1_direction,h1_wave_direction,h1_elliot_label,h4_elliot_label,is_h1_wave_accepted,is_h4_wave_accepted,h1_gmma_trend_count,h1_gmma_cross_count,h1_ema200_direction,h4_ema200_direction,w1_ema200_direction,h1_direction_alignment_mode,is_h1_direction_alignment_passed,analysis_snapshot_text";
    }

    /**
     * SQL NULLをEntityの未取得値へ変換するSELECT列を返す。
     */
    static string selectColumns() {
        return "id,run_id,context_key,COALESCE(market_signal_key,''),snapshot_hash,h1_bar_time,evaluated_server_time,created_at,COALESCE(signal_reference_time,0),decision,reason_code,COALESCE(signal_side,''),is_judge_matched,signal_count,entry_count,is_entry_evaluated,is_strategy_entry,is_signal_consumed,COALESCE(spread_pips,1.7976931348623157e308),COALESCE(requested_volume,1.7976931348623157e308),COALESCE(initial_stop_loss,0.0),COALESCE(initial_risk_pips,0.0),max_initial_risk_pips,COALESCE(mn1_direction,''),COALESCE(w1_direction,''),COALESCE(d1_direction,''),COALESCE(h4_direction,''),COALESCE(h1_direction,''),COALESCE(h1_wave_direction,''),COALESCE(h1_elliot_label,''),COALESCE(h4_elliot_label,''),is_h1_wave_accepted,is_h4_wave_accepted,COALESCE(h1_gmma_trend_count,-2147483648),COALESCE(h1_gmma_cross_count,-2147483648),COALESCE(h1_ema200_direction,''),COALESCE(h4_ema200_direction,''),COALESCE(w1_ema200_direction,''),h1_direction_alignment_mode,is_h1_direction_alignment_passed,analysis_snapshot_text";
    }

    /**
     * Entityの全保存値を固定順に生成する。
     */
    static string values(const H1EaDecisionEntity &fromEntity) {
        string values = "";
        values += "NULL";
        values += "," + IntegerToString((long)fromEntity.runId);
        values += "," + H1EaSql::text(fromEntity.contextKey);
        values += "," + H1EaSql::optionalText(fromEntity.marketSignalKey);
        values += "," + H1EaSql::text(fromEntity.snapshotHash);
        values += "," + IntegerToString((long)fromEntity.h1BarTime);
        values += "," + IntegerToString((long)fromEntity.evaluatedServerTime);
        values += "," + IntegerToString((long)fromEntity.createdAt);
        values += "," + H1EaSql::optionalLong(fromEntity.signalReferenceTime, 0);
        values += "," + H1EaSql::text(fromEntity.decision);
        values += "," + H1EaSql::text(fromEntity.reasonCode);
        values += "," + H1EaSql::optionalText(fromEntity.signalSide);
        values += "," + IntegerToString((long)fromEntity.isJudgeMatched);
        values += "," + IntegerToString((long)fromEntity.signalCount);
        values += "," + IntegerToString((long)fromEntity.entryCount);
        values += "," + IntegerToString((long)fromEntity.isEntryEvaluated);
        values += "," + IntegerToString((long)fromEntity.isStrategyEntry);
        values += "," + IntegerToString((long)fromEntity.isSignalConsumed);
        values += "," + H1EaSql::real(fromEntity.spreadPips, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.requestedVolume, EMPTY_VALUE);
        values += "," + H1EaSql::real(fromEntity.initialStopLoss, 0.0);
        values += "," + H1EaSql::real(fromEntity.initialRiskPips, 0.0);
        values += "," + H1EaSql::real(fromEntity.maxInitialRiskPips, 0.0);
        values += "," + H1EaSql::optionalText(fromEntity.mn1Direction);
        values += "," + H1EaSql::optionalText(fromEntity.w1Direction);
        values += "," + H1EaSql::optionalText(fromEntity.d1Direction);
        values += "," + H1EaSql::optionalText(fromEntity.h4Direction);
        values += "," + H1EaSql::optionalText(fromEntity.h1Direction);
        values += "," + H1EaSql::optionalText(fromEntity.h1WaveDirection);
        values += "," + H1EaSql::optionalText(fromEntity.h1ElliotLabel);
        values += "," + H1EaSql::optionalText(fromEntity.h4ElliotLabel);
        values += "," + IntegerToString((long)fromEntity.isH1WaveAccepted);
        values += "," + IntegerToString((long)fromEntity.isH4WaveAccepted);
        values += "," + H1EaSql::optionalLong(fromEntity.h1GmmaTrendCount, INT_MIN);
        values += "," + H1EaSql::optionalLong(fromEntity.h1GmmaCrossCount, INT_MIN);
        values += "," + H1EaSql::optionalText(fromEntity.h1Ema200Direction);
        values += "," + H1EaSql::optionalText(fromEntity.h4Ema200Direction);
        values += "," + H1EaSql::optionalText(fromEntity.w1Ema200Direction);
        values += "," + H1EaSql::text(fromEntity.h1DirectionAlignmentMode);
        values += "," + IntegerToString((long)fromEntity.isH1DirectionAlignmentPassed);
        values += "," + H1EaSql::text(fromEntity.analysisSnapshotText);
        return values;
    }

    /**
     * 新規行を挿入し採番済みIDを返す。transactionは呼出元が管理する。
     */
    static bool insert(const int fromHandle, H1EaDecisionEntity &fromEntity) {
        string sql = "INSERT INTO h1_ea_decisions (" + H1EaDecisionDao::columns()
            + ") VALUES (" + H1EaDecisionDao::values(fromEntity) + ")";
        if (!H1EaSql::execute(fromHandle, sql)) {
            return false;
        }
        return H1EaSql::scalar(fromHandle, "SELECT last_insert_rowid()", fromEntity.id);
    }

    /**
     * 現在のSELECT行から全列を取得する。
     */
    static bool read(const int fromRequest, H1EaDecisionEntity &fromEntity) {
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
        if (!DatabaseColumnLong(fromRequest, 5, fromEntity.h1BarTime)) {
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
        if (!DatabaseColumnText(fromRequest, 23, fromEntity.mn1Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 24, fromEntity.w1Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 25, fromEntity.d1Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 26, fromEntity.h4Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 27, fromEntity.h1Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 28, fromEntity.h1WaveDirection)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 29, fromEntity.h1ElliotLabel)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 30, fromEntity.h4ElliotLabel)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 31, integerValue)) {
            return false;
        }
        fromEntity.isH1WaveAccepted = (bool)integerValue;
        if (!DatabaseColumnLong(fromRequest, 32, integerValue)) {
            return false;
        }
        fromEntity.isH4WaveAccepted = (bool)integerValue;
        if (!DatabaseColumnLong(fromRequest, 33, integerValue)) {
            return false;
        }
        fromEntity.h1GmmaTrendCount = (int)integerValue;
        if (!DatabaseColumnLong(fromRequest, 34, integerValue)) {
            return false;
        }
        fromEntity.h1GmmaCrossCount = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 35, fromEntity.h1Ema200Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 36, fromEntity.h4Ema200Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 37, fromEntity.w1Ema200Direction)) {
            return false;
        }
        if (!DatabaseColumnText(fromRequest, 38, fromEntity.h1DirectionAlignmentMode)) {
            return false;
        }
        if (!DatabaseColumnLong(fromRequest, 39, integerValue)) {
            return false;
        }
        fromEntity.isH1DirectionAlignmentPassed = (bool)integerValue;
        if (!DatabaseColumnText(fromRequest, 40, fromEntity.analysisSnapshotText)) {
            return false;
        }
        return true;
    }

    /**
     * 一件を読み取る。0件とDB障害を区別して返す。
     */
    static bool load(const int fromHandle, const string fromWhere, H1EaDecisionEntity &fromEntity, bool &fromFound) {
        fromFound = false;
        int request = DatabasePrepare(fromHandle, "SELECT " + H1EaDecisionDao::selectColumns()
            + " FROM h1_ea_decisions WHERE " + fromWhere + " LIMIT 1");
        if (request == INVALID_HANDLE) {
            return false;
        }
        ResetLastError();
        if (!DatabaseRead(request)) {
            int errorCode = GetLastError();
            DatabaseFinalize(request);
            return errorCode == ERR_DATABASE_NO_MORE_DATA;
        }
        bool success = H1EaDecisionDao::read(request, fromEntity);
        DatabaseFinalize(request);
        fromFound = success;
        return success;
    }
};

#endif
