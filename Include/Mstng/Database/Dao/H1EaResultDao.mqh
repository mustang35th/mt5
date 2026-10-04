#ifndef MSTNG_DATABASE_DAO_H1EARESULTDAO_MQH
#define MSTNG_DATABASE_DAO_H1EARESULTDAO_MQH

#include <Mstng\Database\Dao\H1EaSql.mqh>

/**
 * 複数通貨H1 EAの口座推移・約定・テスター結果の保存schemaを定義する。
 */
class H1EaResultDao {
public:
    /**
     * 起動単位の保存状態とテスター集計を保持するテーブルを定義する。
     */
    static string createSessionSql() {
        string sql = "CREATE TABLE IF NOT EXISTS h1_ea_sessions (";
        sql += "session_uid TEXT NOT NULL PRIMARY KEY,";
        sql += "source_mode TEXT NOT NULL,";
        sql += "account_currency TEXT NOT NULL,";
        sql += "account_server TEXT NOT NULL,";
        sql += "leverage INTEGER NOT NULL,";
        sql += "program_version TEXT NOT NULL,";
        sql += "started_server_time INTEGER NOT NULL,";
        sql += "trade_start_time INTEGER NOT NULL,";
        sql += "ended_server_time INTEGER,";
        sql += "initial_balance REAL NOT NULL,";
        sql += "sample_interval_seconds INTEGER NOT NULL,";
        sql += "recording_state TEXT NOT NULL,";
        sql += "statistics_available INTEGER NOT NULL,";
        sql += "deals_complete INTEGER NOT NULL,";
        sql += "initial_deposit REAL,";
        sql += "net_profit REAL,";
        sql += "equity_drawdown REAL,";
        sql += "equity_drawdown_percent REAL,";
        sql += "mt5_trades INTEGER,";
        sql += "error_text TEXT,";
        sql += "recorded_at INTEGER NOT NULL,";
        sql += "finished_at INTEGER,";
        sql += "CHECK(length(session_uid)=64 AND session_uid NOT GLOB '*[^0-9a-f]*'),";
        sql += "CHECK(source_mode IN ('LIVE', 'TESTER')),";
        sql += "CHECK(length(account_currency)>0 AND length(account_server)>0 AND length(program_version)>0),";
        sql += "CHECK(leverage>=0 AND started_server_time>0 AND trade_start_time>=0),";
        sql += "CHECK(ended_server_time IS NULL OR ended_server_time>=started_server_time),";
        sql += "CHECK(sample_interval_seconds>0),";
        sql += "CHECK(recording_state IN ('RECORDING', 'RECORDED', 'FAILED', 'INTERRUPTED')),";
        sql += "CHECK(statistics_available IN (0,1) AND deals_complete IN (0,1)),";
        sql += "CHECK(equity_drawdown IS NULL OR equity_drawdown>=0),";
        sql += "CHECK(equity_drawdown_percent IS NULL OR equity_drawdown_percent>=0),";
        sql += "CHECK(mt5_trades IS NULL OR mt5_trades>=0),";
        sql += "CHECK(recorded_at>0 AND (finished_at IS NULL OR finished_at>=recorded_at)),";
        sql += "CHECK(recording_state!='RECORDED' OR (statistics_available=1 AND deals_complete=1 AND ended_server_time IS NOT NULL AND finished_at IS NOT NULL)))";

        return sql;
    }

    /**
     * 口座全体の定期・建玉変化時スナップショットを定義する。
     */
    static string createSampleSql() {
        string sql = "CREATE TABLE IF NOT EXISTS h1_ea_account_samples (";
        sql += "session_uid TEXT NOT NULL,";
        sql += "sequence INTEGER NOT NULL,";
        sql += "server_time INTEGER NOT NULL,";
        sql += "reason TEXT NOT NULL,";
        sql += "balance REAL NOT NULL,";
        sql += "equity REAL NOT NULL,";
        sql += "margin REAL NOT NULL,";
        sql += "free_margin REAL NOT NULL,";
        sql += "margin_level REAL NOT NULL,";
        sql += "open_profit REAL NOT NULL,";
        sql += "positions INTEGER NOT NULL,";
        sql += "pending_orders INTEGER NOT NULL,";
        sql += "foreign_positions INTEGER NOT NULL,";
        sql += "foreign_orders INTEGER NOT NULL,";
        sql += "PRIMARY KEY(session_uid,sequence),";
        sql += "FOREIGN KEY(session_uid) REFERENCES h1_ea_sessions(session_uid),";
        sql += "CHECK(sequence>0 AND server_time>0 AND length(reason)>0),";
        sql += "CHECK(margin>=0 AND margin_level>=0),";
        sql += "CHECK(positions>=0 AND pending_orders>=0 AND foreign_positions>=0 AND foreign_orders>=0))";

        return sql;
    }

    /**
     * 約定を起動ID・ticket単位で重複なく保持するテーブルを定義する。
     */
    static string createDealSql() {
        string sql = "CREATE TABLE IF NOT EXISTS h1_ea_deals (";
        sql += "session_uid TEXT NOT NULL,";
        sql += "ticket TEXT NOT NULL,";
        sql += "time_msc INTEGER NOT NULL,";
        sql += "position_identifier TEXT NOT NULL,";
        sql += "symbol TEXT NOT NULL,";
        sql += "magic_number TEXT NOT NULL,";
        sql += "deal_type INTEGER NOT NULL,";
        sql += "entry_type INTEGER NOT NULL,";
        sql += "volume REAL NOT NULL,";
        sql += "price REAL NOT NULL,";
        sql += "profit REAL NOT NULL,";
        sql += "commission REAL NOT NULL,";
        sql += "swap REAL NOT NULL,";
        sql += "fee REAL NOT NULL,";
        sql += "reason INTEGER NOT NULL,";
        sql += "PRIMARY KEY(session_uid,ticket),";
        sql += "FOREIGN KEY(session_uid) REFERENCES h1_ea_sessions(session_uid),";
        sql += "CHECK(length(ticket)>0 AND ticket NOT GLOB '*[^0-9]*'),";
        sql += "CHECK(length(position_identifier)>0 AND position_identifier NOT GLOB '*[^0-9]*'),";
        sql += "CHECK(length(magic_number)>0 AND magic_number NOT GLOB '*[^0-9]*'),";
        sql += "CHECK(time_msc>0 AND deal_type>=0 AND entry_type>=0 AND reason>=0),";
        sql += "CHECK(volume>=0 AND price>=0))";

        return sql;
    }

    /**
     * 保存先と一覧・時系列読取用の索引を作る。transactionは呼出元が管理する。
     */
    static bool createTables(const int fromHandle) {
        return H1EaSql::execute(fromHandle, H1EaResultDao::createSessionSql())
            && H1EaSql::execute(fromHandle, H1EaResultDao::createSampleSql())
            && H1EaSql::execute(fromHandle, H1EaResultDao::createDealSql())
            && H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_sessions_source_started ON h1_ea_sessions(source_mode,started_server_time,session_uid);")
            && H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_account_samples_time ON h1_ea_account_samples(session_uid,server_time,sequence);")
            && H1EaSql::execute(fromHandle, "CREATE INDEX IF NOT EXISTS idx_h1_ea_deals_time ON h1_ea_deals(session_uid,time_msc,ticket);");
    }
};

#endif
