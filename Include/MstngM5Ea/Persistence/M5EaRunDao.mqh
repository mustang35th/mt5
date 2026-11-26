#ifndef MSTNGM5EA_PERSISTENCE_RUNDAO_MQH
#define MSTNGM5EA_PERSISTENCE_RUNDAO_MQH

#include <MstngM5Ea\Persistence\M5EaRunEntity.mqh>
#include <MstngM5Ea\Persistence\M5EaSql.mqh>

/**
 * M5 EA RunのSQL保存と読み取りを担当する。
 */
class M5EaRunDao {
public:
    /**
     * 共通起動IDを含む列・整合制約を返す。
     */
    static string createSql() {
        string sql = "CREATE TABLE IF NOT EXISTS m5_ea_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_uid TEXT NOT NULL,";
        sql += "schema_version INTEGER NOT NULL,";
        sql += "source_mode TEXT NOT NULL,";
        sql += "context_key TEXT NOT NULL,";
        sql += "account_server TEXT NOT NULL,";
        sql += "account_login INTEGER NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "magic_number TEXT NOT NULL,";
        sql += "program_version TEXT NOT NULL,";
        sql += "strategy_version TEXT NOT NULL,";
        sql += "analysis_version TEXT NOT NULL,";
        sql += "analysis_input_text TEXT NOT NULL,";
        sql += "analysis_input_hash TEXT NOT NULL,";
        sql += "config_text TEXT NOT NULL,";
        sql += "config_hash TEXT NOT NULL,";
        sql += "started_at INTEGER NOT NULL,";
        sql += "ended_at INTEGER,";
        sql += "heartbeat_at INTEGER NOT NULL,";
        sql += "lease_expires_at INTEGER NOT NULL,";
        sql += "status TEXT NOT NULL,";
        sql += "error_text TEXT NOT NULL,";
        sql += " session_uid TEXT CHECK(session_uid IS NULL OR (length(session_uid)=64 AND session_uid NOT GLOB '*[^0-9a-f]*')),";
        sql += "CHECK(source_mode IN ('LIVE', 'TESTER')),";
        sql += "CHECK(status IN ('RUNNING', 'STOPPED', 'FAILED', 'INTERRUPTED')),";
        sql += "CHECK(heartbeat_at > 0),";
        sql += "CHECK(lease_expires_at >= heartbeat_at),";
        sql += "CHECK(schema_version = 1),";
        sql += "CHECK(time_frame = 5))";

        return sql;
    }

    /**
     * schema作成と厳密照合で共用する索引定義を返す。
     */
    static bool indexSql(string &fromSql[]) {
        if (ArrayResize(fromSql, 5) != 5) {
            return false;
        }

        fromSql[0] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m5_ea_runs_run_uid ON m5_ea_runs(run_uid);";
        fromSql[1] = "CREATE UNIQUE INDEX IF NOT EXISTS idx_m5_ea_runs_active_context ON m5_ea_runs(context_key) WHERE status = 'RUNNING';";
        fromSql[2] = "CREATE INDEX IF NOT EXISTS idx_m5_ea_runs_source_started ON m5_ea_runs(source_mode, started_at, id);";
        fromSql[3] = "CREATE INDEX IF NOT EXISTS idx_m5_ea_runs_context_started ON m5_ea_runs(context_key, started_at, id);";
        fromSql[4] = "CREATE INDEX IF NOT EXISTS idx_m5_ea_runs_session_symbol ON m5_ea_runs(session_uid, symbol_name, id);";

        return true;
    }

    /**
     * 全列をSQLの固定順に列挙する。
     */
    static string columns() {
        return "id,run_uid,schema_version,source_mode,context_key,account_server,account_login,symbol_name,time_frame,magic_number,program_version,strategy_version,analysis_version,analysis_input_text,analysis_input_hash,config_text,config_hash,started_at,ended_at,heartbeat_at,lease_expires_at,status,error_text,session_uid";
    }

    /**
     * SQL NULLをEntityの未取得値へ変換するSELECT列を返す。
     */
    static string selectColumns() {
        return "id,run_uid,schema_version,source_mode,context_key,account_server,account_login,symbol_name,time_frame,magic_number,program_version,strategy_version,analysis_version,analysis_input_text,analysis_input_hash,config_text,config_hash,started_at,COALESCE(ended_at,0),heartbeat_at,lease_expires_at,status,error_text,COALESCE(session_uid,'')";
    }

    /**
     * Entityの全保存値を固定順に生成する。
     */
    static string values(const M5EaRunEntity &fromEntity) {
        string values = "";
        values += "NULL";
        values += "," + M5EaSql::text(fromEntity.runUid);
        values += "," + IntegerToString((long)fromEntity.schemaVersion);
        values += "," + M5EaSql::text(fromEntity.sourceMode);
        values += "," + M5EaSql::text(fromEntity.contextKey);
        values += "," + M5EaSql::text(fromEntity.accountServer);
        values += "," + IntegerToString((long)fromEntity.accountLogin);
        values += "," + M5EaSql::text(fromEntity.symbolName);
        values += "," + IntegerToString((long)fromEntity.timeFrame);
        values += "," + M5EaSql::text(fromEntity.magicNumber);
        values += "," + M5EaSql::text(fromEntity.programVersion);
        values += "," + M5EaSql::text(fromEntity.strategyVersion);
        values += "," + M5EaSql::text(fromEntity.analysisVersion);
        values += "," + M5EaSql::text(fromEntity.analysisInputText);
        values += "," + M5EaSql::text(fromEntity.analysisInputHash);
        values += "," + M5EaSql::text(fromEntity.configText);
        values += "," + M5EaSql::text(fromEntity.configHash);
        values += "," + IntegerToString((long)fromEntity.startedAt);
        values += "," + M5EaSql::optionalLong(fromEntity.endedAt, 0);
        values += "," + IntegerToString((long)fromEntity.heartbeatAt);
        values += "," + IntegerToString((long)fromEntity.leaseExpiresAt);
        values += "," + M5EaSql::text(fromEntity.status);
        values += "," + M5EaSql::text(fromEntity.errorText);
        values += "," + M5EaSql::optionalText(fromEntity.sessionUid);

        return values;
    }

    /**
     * 新規行を挿入し採番済みIDを返す。transactionは呼出元が管理する。
     */
    static bool insert(const int fromHandle, M5EaRunEntity &fromEntity) {
        string sql = "INSERT INTO m5_ea_runs (" + M5EaRunDao::columns()
            + ") VALUES (" + M5EaRunDao::values(fromEntity) + ")";
        if (!M5EaSql::execute(fromHandle, sql)) {
            return false;
        }

        return M5EaSql::scalar(fromHandle, "SELECT last_insert_rowid()", fromEntity.id);
    }

    /**
     * 現在スナップショットを更新する。履歴DecisionとEventは更新しない。
     */
    static bool update(const int fromHandle, const M5EaRunEntity &fromEntity) {
        string sql = "UPDATE m5_ea_runs SET ";
        sql += "run_uid=" + M5EaSql::text(fromEntity.runUid);
        sql += ",schema_version=" + IntegerToString((long)fromEntity.schemaVersion);
        sql += ",source_mode=" + M5EaSql::text(fromEntity.sourceMode);
        sql += ",context_key=" + M5EaSql::text(fromEntity.contextKey);
        sql += ",account_server=" + M5EaSql::text(fromEntity.accountServer);
        sql += ",account_login=" + IntegerToString((long)fromEntity.accountLogin);
        sql += ",symbol_name=" + M5EaSql::text(fromEntity.symbolName);
        sql += ",time_frame=" + IntegerToString((long)fromEntity.timeFrame);
        sql += ",magic_number=" + M5EaSql::text(fromEntity.magicNumber);
        sql += ",program_version=" + M5EaSql::text(fromEntity.programVersion);
        sql += ",strategy_version=" + M5EaSql::text(fromEntity.strategyVersion);
        sql += ",analysis_version=" + M5EaSql::text(fromEntity.analysisVersion);
        sql += ",analysis_input_text=" + M5EaSql::text(fromEntity.analysisInputText);
        sql += ",analysis_input_hash=" + M5EaSql::text(fromEntity.analysisInputHash);
        sql += ",config_text=" + M5EaSql::text(fromEntity.configText);
        sql += ",config_hash=" + M5EaSql::text(fromEntity.configHash);
        sql += ",started_at=" + IntegerToString((long)fromEntity.startedAt);
        sql += ",ended_at=" + M5EaSql::optionalLong(fromEntity.endedAt, 0);
        sql += ",heartbeat_at=" + IntegerToString((long)fromEntity.heartbeatAt);
        sql += ",lease_expires_at=" + IntegerToString((long)fromEntity.leaseExpiresAt);
        sql += ",status=" + M5EaSql::text(fromEntity.status);
        sql += ",error_text=" + M5EaSql::text(fromEntity.errorText);
        sql += ",session_uid=" + M5EaSql::optionalText(fromEntity.sessionUid);
        sql += " WHERE id=" + IntegerToString(fromEntity.id);

        if (!M5EaSql::execute(fromHandle, sql)) {
            return false;
        }

        long changed = 0;

        return M5EaSql::scalar(fromHandle, "SELECT changes()", changed) && changed == 1;
    }

    /**
     * 現在のSELECT行から全列を取得する。
     */
    static bool read(const int fromRequest, M5EaRunEntity &fromEntity) {
        fromEntity.reset();

        long integerValue = 0;
        if (!DatabaseColumnLong(fromRequest, 0, fromEntity.id)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 1, fromEntity.runUid)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 2, integerValue)) {
            return false;
        }

        fromEntity.schemaVersion = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 3, fromEntity.sourceMode)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 4, fromEntity.contextKey)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 5, fromEntity.accountServer)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 6, fromEntity.accountLogin)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 7, fromEntity.symbolName)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 8, integerValue)) {
            return false;
        }

        fromEntity.timeFrame = (int)integerValue;
        if (!DatabaseColumnText(fromRequest, 9, fromEntity.magicNumber)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 10, fromEntity.programVersion)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 11, fromEntity.strategyVersion)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 12, fromEntity.analysisVersion)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 13, fromEntity.analysisInputText)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 14, fromEntity.analysisInputHash)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 15, fromEntity.configText)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 16, fromEntity.configHash)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 17, fromEntity.startedAt)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 18, fromEntity.endedAt)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 19, fromEntity.heartbeatAt)) {
            return false;
        }

        if (!DatabaseColumnLong(fromRequest, 20, fromEntity.leaseExpiresAt)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 21, fromEntity.status)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 23, fromEntity.sessionUid)) {
            return false;
        }

        if (!DatabaseColumnText(fromRequest, 22, fromEntity.errorText)) {
            return false;
        }

        return true;
    }

    /**
     * 一件を読み取る。0件とDB障害を区別して返す。
     */
    static bool load(const int fromHandle, const string fromWhere, M5EaRunEntity &fromEntity, bool &fromFound) {
        fromFound = false;

        int request = DatabasePrepare(fromHandle, "SELECT " + M5EaRunDao::selectColumns()
            + " FROM m5_ea_runs WHERE " + fromWhere + " LIMIT 1");
        if (request == INVALID_HANDLE) {
            return false;
        }

        ResetLastError();
        if (!DatabaseRead(request)) {
            int errorCode = GetLastError();
            DatabaseFinalize(request);
            return errorCode == ERR_DATABASE_NO_MORE_DATA;
        }

        bool success = M5EaRunDao::read(request, fromEntity);
        DatabaseFinalize(request);
        fromFound = success;

        return success;
    }
};

#endif
