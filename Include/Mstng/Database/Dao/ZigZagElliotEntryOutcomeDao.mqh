//+------------------------------------------------------------------+
//|                          ZigZagElliotEntryOutcomeDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ENTRY_OUTCOME_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ENTRY_OUTCOME_DAO_MQH

#include <Mstng\Database\Entity\ZigZagElliotEntryOutcomeEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliotエントリー後処理の実行情報と結果を別SQLiteへ保存するDAO。
 */
class ZigZagElliotEntryOutcomeDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle Outcome DBのデータベースハンドル。
     */
    ZigZagElliotEntryOutcomeDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 後処理実行テーブル、結果テーブルおよびインデックスを作成する。
     *
     * @return 全データベースオブジェクトを準備できた場合true。
     */
    bool createTables() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.executeSql(
                "PRAGMA foreign_keys = ON",
                "enable foreign keys"
            ) || !this.isForeignKeysEnabled()) {
            return false;
        }

        if (!this.executeSql(
                "PRAGMA busy_timeout = 5000",
                "configure busy timeout"
            )) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS ";
        sql += "zigzag_elliot_entry_outcome_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_key TEXT NOT NULL UNIQUE,";
        sql += "source_database_file_name TEXT NOT NULL,";
        sql += "source_run_id INTEGER NOT NULL,";
        sql += "source_run_uid TEXT NOT NULL,";
        sql += "source_mode TEXT NOT NULL,";
        sql += "source_server TEXT NOT NULL,";
        sql += "source_login INTEGER NOT NULL,";
        sql += "source_program_name TEXT NOT NULL,";
        sql += "source_program_version TEXT NOT NULL,";
        sql += "source_strategy TEXT NOT NULL,";
        sql += "source_strategy_version TEXT NOT NULL,";
        sql += "source_analysis_version TEXT NOT NULL,";
        sql += "source_analysis_input_hash TEXT NOT NULL,";
        sql += "source_input_hash TEXT NOT NULL,";
        sql += "source_tester_from INTEGER NOT NULL,";
        sql += "source_tester_to INTEGER NOT NULL,";
        sql += "source_tester_model TEXT NOT NULL,";
        sql += "horizon_h1_bars INTEGER NOT NULL CHECK(horizon_h1_bars > 0),";
        sql += "price_model TEXT NOT NULL,";
        sql += "evaluation_version TEXT NOT NULL,";
        sql += "status TEXT NOT NULL CHECK(status IN (";
        sql += "'RUNNING', 'COMPLETED', 'FAILED')),";
        sql += "total_count INTEGER NOT NULL CHECK(total_count >= 0),";
        sql += "success_count INTEGER NOT NULL CHECK(success_count >= 0),";
        sql += "failure_count INTEGER NOT NULL CHECK(failure_count >= 0),";
        sql += "started_at INTEGER NOT NULL,";
        sql += "completed_at INTEGER,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "CHECK(success_count + failure_count <= total_count),";
        sql += "CHECK((status = 'RUNNING' AND completed_at IS NULL) OR ";
        sql += "(status IN ('COMPLETED', 'FAILED') ";
        sql += "AND completed_at IS NOT NULL))";
        sql += ")";

        if (!this.executeSql(sql, "entry outcome runs table")) {
            return false;
        }

        sql = "CREATE TABLE IF NOT EXISTS ";
        sql += "zigzag_elliot_entry_outcomes (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "outcome_run_id INTEGER NOT NULL,";
        sql += "source_alert_id INTEGER NOT NULL,";
        sql += "source_run_id INTEGER NOT NULL,";
        sql += "market_signal_key TEXT NOT NULL,";
        sql += "source_server TEXT NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "side TEXT NOT NULL CHECK(side IN ('BUY', 'SELL')),";
        sql += "current_bar_time INTEGER NOT NULL,";
        sql += "entry_time INTEGER NOT NULL,";
        sql += "entry_price REAL NOT NULL,";
        sql += "spread_pips REAL NOT NULL,";
        sql += "stop_loss REAL NOT NULL,";
        sql += "source_risk_pips REAL NOT NULL,";
        sql += "calculated_risk_pips REAL NOT NULL,";
        sql += "horizon_h1_bars INTEGER NOT NULL CHECK(horizon_h1_bars > 0),";
        sql += "evaluation_start_time INTEGER NOT NULL,";
        sql += "evaluation_end_time INTEGER NOT NULL,";
        sql += "is_calculated INTEGER NOT NULL ";
        sql += "CHECK(is_calculated IN (0, 1)),";
        sql += "mfe_pips REAL,";
        sql += "mfe_r REAL,";
        sql += "mae_pips REAL,";
        sql += "mae_r REAL,";
        sql += "profit_pips REAL,";
        sql += "profit_r REAL,";
        sql += "exit_time INTEGER,";
        sql += "exit_price REAL,";
        sql += "exit_reason TEXT NOT NULL,";
        sql += "bars_held_m1 INTEGER,";
        sql += "bars_held_h1 INTEGER,";
        sql += "copied_m1_bars INTEGER NOT NULL CHECK(copied_m1_bars >= 0),";
        sql += "data_status TEXT NOT NULL,";
        sql += "calculation_note TEXT NOT NULL,";
        sql += "is_zero_spread INTEGER NOT NULL ";
        sql += "CHECK(is_zero_spread IN (0, 1)),";
        sql += "is_order_unknown INTEGER NOT NULL ";
        sql += "CHECK(is_order_unknown IN (0, 1)),";
        sql += "price_model TEXT NOT NULL,";
        sql += "evaluation_version TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "FOREIGN KEY(outcome_run_id) REFERENCES ";
        sql += "zigzag_elliot_entry_outcome_runs(id) ON DELETE CASCADE,";
        sql += "UNIQUE(outcome_run_id, source_alert_id),";
        sql += "CHECK((is_calculated = 0 ";
        sql += "AND mfe_pips IS NULL AND mfe_r IS NULL ";
        sql += "AND mae_pips IS NULL AND mae_r IS NULL ";
        sql += "AND profit_pips IS NULL AND profit_r IS NULL ";
        sql += "AND exit_time IS NULL AND exit_price IS NULL ";
        sql += "AND bars_held_m1 IS NULL AND bars_held_h1 IS NULL) OR ";
        sql += "(is_calculated = 1 ";
        sql += "AND mfe_pips IS NOT NULL AND mfe_r IS NOT NULL ";
        sql += "AND mae_pips IS NOT NULL AND mae_r IS NOT NULL ";
        sql += "AND profit_pips IS NOT NULL AND profit_r IS NOT NULL ";
        sql += "AND exit_time IS NOT NULL AND exit_price IS NOT NULL ";
        sql += "AND bars_held_m1 IS NOT NULL ";
        sql += "AND bars_held_h1 IS NOT NULL))";
        sql += ")";

        if (!this.executeSql(sql, "entry outcomes table")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_entry_outcome_runs_source_run ON ";
        sql += "zigzag_elliot_entry_outcome_runs(";
        sql += "source_database_file_name, source_run_id)";

        if (!this.executeSql(sql, "entry outcome source run index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_entry_outcomes_market_signal_key ON ";
        sql += "zigzag_elliot_entry_outcomes(market_signal_key)";

        if (!this.executeSql(sql, "entry outcome market key index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_entry_outcomes_source_run_time ON ";
        sql += "zigzag_elliot_entry_outcomes(";
        sql += "source_run_id, symbol_name, entry_time)";

        if (!this.executeSql(sql, "entry outcome source time index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_entry_outcomes_status ON ";
        sql += "zigzag_elliot_entry_outcomes(data_status, entry_time)";

        if (!this.executeSql(sql, "entry outcome status index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "ZigZagElliot entry outcome tables are ready."
        );

        return true;
    }

    /**
     * runKeyに一致する後処理実行を取得または作成する。
     *
     * 既存Runは同じIDを維持し、RUNNINGおよび件数0へ戻す。
     *
     * @param fromEntity 保存する実行情報。
     * @param fromRunId 取得または作成したRun IDの格納先。
     * @return Runを準備できた場合true。
     */
    bool findOrCreateRun(
        ZigZagElliotEntryOutcomeRunEntity &fromEntity,
        long &fromRunId
    ) {
        fromRunId = 0;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        datetime currentTime = this.getCurrentTime();
        fromEntity.id = 0;
        fromEntity.status = "RUNNING";
        fromEntity.totalCount = 0;
        fromEntity.successCount = 0;
        fromEntity.failureCount = 0;
        fromEntity.completedAt = 0;

        if (fromEntity.startedAt <= 0) {
            fromEntity.startedAt = currentTime;
        }

        if (fromEntity.createdAt <= 0) {
            fromEntity.createdAt = currentTime;
        }

        fromEntity.updatedAt = currentTime;

        if (!this.isRunValid(fromEntity)) {
            this.logger.error(__FUNCTION__, "Entry outcome run is invalid.");

            return false;
        }

        string sql = this.buildRunUpsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        if (!this.bindRun(requestHandle, fromEntity)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "upsert entry outcome run"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted
                || !this.findRunIdByKey(fromEntity.runKey, fromRunId)) {
            return false;
        }

        fromEntity.id = fromRunId;

        return true;
    }

    /**
     * エントリー後処理結果を保存する。
     *
     * 同じRunと参照元Alertの結果は最新の再計算結果へ更新する。
     * isCalculatedが0の場合、結果数値はSQL NULLとして保存する。
     *
     * @param fromEntity 保存対象結果。
     * @return 保存できた場合true。
     */
    bool save(ZigZagElliotEntryOutcomeEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromEntity.id = 0;

        if (fromEntity.createdAt <= 0) {
            fromEntity.createdAt = this.getCurrentTime();
        }

        if (!this.isOutcomeValid(fromEntity)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "Entry outcome is invalid. sourceAlertId=%I64d status=%s",
                    fromEntity.sourceAlertId,
                    fromEntity.dataStatus
                )
            );

            return false;
        }

        bool isCalculated = fromEntity.isCalculated == 1;
        string sql = this.buildOutcomeUpsertSql(isCalculated);
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = false;

        if (isCalculated) {
            isBound = this.bindCalculatedOutcome(requestHandle, fromEntity);
        } else {
            isBound = this.bindUncalculatedOutcome(requestHandle, fromEntity);
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "upsert entry outcome"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted
                || !this.findOutcomeId(
                    fromEntity.outcomeRunId,
                    fromEntity.sourceAlertId,
                    fromEntity.id
                )) {
            return false;
        }

        return true;
    }

    /**
     * 後処理実行を完了状態へ更新する。
     *
     * @param fromRunId 更新対象Run ID。
     * @param fromStatus COMPLETEDまたはFAILED。
     * @param fromTotalCount 評価対象総数。
     * @param fromSuccessCount 評価成功数。
     * @param fromFailureCount 評価失敗数。
     * @return 対象Runを1件更新できた場合true。
     */
    bool completeRun(
        const long fromRunId,
        const string fromStatus,
        const long fromTotalCount,
        const long fromSuccessCount,
        const long fromFailureCount
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromRunId <= 0
                || (fromStatus != "COMPLETED" && fromStatus != "FAILED")
                || fromTotalCount < 0
                || fromSuccessCount < 0
                || fromFailureCount < 0
                || fromSuccessCount + fromFailureCount != fromTotalCount) {
            this.logger.error(__FUNCTION__, "Run completion values are invalid.");

            return false;
        }

        datetime completedAt = this.getCurrentTime();
        string sql = "UPDATE zigzag_elliot_entry_outcome_runs SET ";
        sql += "status = ?1, total_count = ?2, success_count = ?3,";
        sql += " failure_count = ?4, completed_at = ?5, updated_at = ?6 ";
        sql += "WHERE id = ?7";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, fromStatus);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromTotalCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromSuccessCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromFailureCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, completedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, completedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromRunId);
        }

        if (!isBound || index != 7) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "complete entry outcome run"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        long changedCount = 0;

        if (!this.readChanges(changedCount) || changedCount != 1) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "Run completion row count is invalid. runId=%I64d changed=%I64d",
                    fromRunId,
                    changedCount
                )
            );

            return false;
        }

        return true;
    }

private:
    /** Outcome DBのデータベースハンドル。 */
    int databaseHandle;

    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /**
     * 後処理実行のUPSERT文を生成する。
     *
     * @return パラメーター化したUPSERT文。
     */
    string buildRunUpsertSql() {
        string sql = "INSERT INTO zigzag_elliot_entry_outcome_runs (";
        sql += "run_key, source_database_file_name, source_run_id,";
        sql += " source_run_uid, source_mode, source_server, source_login,";
        sql += " source_program_name, source_program_version,";
        sql += " source_strategy, source_strategy_version,";
        sql += " source_analysis_version, source_analysis_input_hash,";
        sql += " source_input_hash, source_tester_from, source_tester_to,";
        sql += " source_tester_model, horizon_h1_bars, price_model,";
        sql += " evaluation_version, status, total_count, success_count,";
        sql += " failure_count, started_at, completed_at, created_at,";
        sql += " updated_at) VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,";
        sql += " ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20,";
        sql += " ?21, ?22, ?23, ?24, ?25, NULL, ?26, ?27) ";
        sql += "ON CONFLICT(run_key) DO UPDATE SET ";
        sql += "source_database_file_name = excluded.source_database_file_name,";
        sql += " source_run_id = excluded.source_run_id,";
        sql += " source_run_uid = excluded.source_run_uid,";
        sql += " source_mode = excluded.source_mode,";
        sql += " source_server = excluded.source_server,";
        sql += " source_login = excluded.source_login,";
        sql += " source_program_name = excluded.source_program_name,";
        sql += " source_program_version = excluded.source_program_version,";
        sql += " source_strategy = excluded.source_strategy,";
        sql += " source_strategy_version = excluded.source_strategy_version,";
        sql += " source_analysis_version = excluded.source_analysis_version,";
        sql += " source_analysis_input_hash = excluded.source_analysis_input_hash,";
        sql += " source_input_hash = excluded.source_input_hash,";
        sql += " source_tester_from = excluded.source_tester_from,";
        sql += " source_tester_to = excluded.source_tester_to,";
        sql += " source_tester_model = excluded.source_tester_model,";
        sql += " horizon_h1_bars = excluded.horizon_h1_bars,";
        sql += " price_model = excluded.price_model,";
        sql += " evaluation_version = excluded.evaluation_version,";
        sql += " status = excluded.status, total_count = 0,";
        sql += " success_count = 0, failure_count = 0,";
        sql += " started_at = excluded.started_at, completed_at = NULL,";
        sql += " updated_at = excluded.updated_at";

        return sql;
    }

    /**
     * 後処理実行UPSERTの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象実行情報。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindRun(
        const int fromRequestHandle,
        ZigZagElliotEntryOutcomeRunEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.runKey);

        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceDatabaseFileName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceRunId);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceRunUid);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceLogin);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceProgramName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceProgramVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceStrategy
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceStrategyVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceAnalysisVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceAnalysisInputHash
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceInputHash
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceTesterFrom
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceTesterTo
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceTesterModel
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.horizonH1Bars
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.priceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.status);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.totalCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.successCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.failureCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.startedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.updatedAt);
        }

        return isBound && index == 27;
    }

    /**
     * 計算済みまたは未計算のOutcome UPSERT文を生成する。
     *
     * @param fromIsCalculated 結果数値を保存する場合true。
     * @return パラメーター化したUPSERT文。
     */
    string buildOutcomeUpsertSql(const bool fromIsCalculated) {
        string sql = "INSERT INTO zigzag_elliot_entry_outcomes (";
        sql += "outcome_run_id, source_alert_id, source_run_id,";
        sql += " market_signal_key, source_server, symbol_name, side,";
        sql += " current_bar_time, entry_time, entry_price, spread_pips,";
        sql += " stop_loss, source_risk_pips, calculated_risk_pips,";
        sql += " horizon_h1_bars, evaluation_start_time,";
        sql += " evaluation_end_time, is_calculated, mfe_pips, mfe_r,";
        sql += " mae_pips, mae_r, profit_pips, profit_r, exit_time,";
        sql += " exit_price, exit_reason, bars_held_m1, bars_held_h1,";
        sql += " copied_m1_bars, data_status, calculation_note,";
        sql += " is_zero_spread, is_order_unknown, price_model,";
        sql += " evaluation_version, created_at) VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,";
        sql += " ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18,";

        if (fromIsCalculated) {
            sql += " ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27,";
            sql += " ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37";
        } else {
            sql += " NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?19,";
            sql += " NULL, NULL, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27";
        }

        sql += ") ON CONFLICT(outcome_run_id, source_alert_id) DO UPDATE SET ";
        sql += "source_run_id = excluded.source_run_id,";
        sql += " market_signal_key = excluded.market_signal_key,";
        sql += " source_server = excluded.source_server,";
        sql += " symbol_name = excluded.symbol_name, side = excluded.side,";
        sql += " current_bar_time = excluded.current_bar_time,";
        sql += " entry_time = excluded.entry_time,";
        sql += " entry_price = excluded.entry_price,";
        sql += " spread_pips = excluded.spread_pips,";
        sql += " stop_loss = excluded.stop_loss,";
        sql += " source_risk_pips = excluded.source_risk_pips,";
        sql += " calculated_risk_pips = excluded.calculated_risk_pips,";
        sql += " horizon_h1_bars = excluded.horizon_h1_bars,";
        sql += " evaluation_start_time = excluded.evaluation_start_time,";
        sql += " evaluation_end_time = excluded.evaluation_end_time,";
        sql += " is_calculated = excluded.is_calculated,";
        sql += " mfe_pips = excluded.mfe_pips, mfe_r = excluded.mfe_r,";
        sql += " mae_pips = excluded.mae_pips, mae_r = excluded.mae_r,";
        sql += " profit_pips = excluded.profit_pips,";
        sql += " profit_r = excluded.profit_r,";
        sql += " exit_time = excluded.exit_time,";
        sql += " exit_price = excluded.exit_price,";
        sql += " exit_reason = excluded.exit_reason,";
        sql += " bars_held_m1 = excluded.bars_held_m1,";
        sql += " bars_held_h1 = excluded.bars_held_h1,";
        sql += " copied_m1_bars = excluded.copied_m1_bars,";
        sql += " data_status = excluded.data_status,";
        sql += " calculation_note = excluded.calculation_note,";
        sql += " is_zero_spread = excluded.is_zero_spread,";
        sql += " is_order_unknown = excluded.is_order_unknown,";
        sql += " price_model = excluded.price_model,";
        sql += " evaluation_version = excluded.evaluation_version,";
        sql += " created_at = excluded.created_at";

        return sql;
    }

    /**
     * Outcome共通先頭パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象結果。
     * @param fromIndex 次に設定するパラメーター位置。
     * @return 全共通先頭パラメーターを設定できた場合true。
     */
    bool bindOutcomePrefix(
        const int fromRequestHandle,
        ZigZagElliotEntryOutcomeEntity &fromEntity,
        int &fromIndex
    ) {
        bool isBound = DatabaseBind(
            fromRequestHandle,
            fromIndex++,
            fromEntity.outcomeRunId
        );

        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.sourceAlertId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.sourceRunId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.marketSignalKey
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.sourceServer
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.side);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.currentBarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.entryTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.entryPrice);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.spreadPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.stopLoss);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.sourceRiskPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.calculatedRiskPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.horizonH1Bars
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.evaluationStartTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.evaluationEndTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.isCalculated
            );
        }

        return isBound && fromIndex == 18;
    }

    /**
     * 計算済みOutcomeの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象結果。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindCalculatedOutcome(
        const int fromRequestHandle,
        ZigZagElliotEntryOutcomeEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = this.bindOutcomePrefix(
            fromRequestHandle,
            fromEntity,
            index
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.mfePips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.mfeR);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.maePips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.maeR);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.profitPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.profitR);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.exitTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.exitPrice);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.exitReason);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barsHeldM1);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.barsHeldH1);
        }

        if (!isBound) {
            return false;
        }

        return this.bindOutcomeSuffix(
            fromRequestHandle,
            fromEntity,
            index,
            37
        );
    }

    /**
     * 未計算Outcomeの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象結果。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindUncalculatedOutcome(
        const int fromRequestHandle,
        ZigZagElliotEntryOutcomeEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = this.bindOutcomePrefix(
            fromRequestHandle,
            fromEntity,
            index
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.exitReason);
        }

        if (!isBound) {
            return false;
        }

        return this.bindOutcomeSuffix(
            fromRequestHandle,
            fromEntity,
            index,
            27
        );
    }

    /**
     * Outcome共通末尾パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象結果。
     * @param fromIndex 次に設定するパラメーター位置。
     * @param fromExpectedCount 全パラメーター設定後の期待件数。
     * @return 全共通末尾パラメーターを設定できた場合true。
     */
    bool bindOutcomeSuffix(
        const int fromRequestHandle,
        ZigZagElliotEntryOutcomeEntity &fromEntity,
        int &fromIndex,
        const int fromExpectedCount
    ) {
        bool isBound = DatabaseBind(
            fromRequestHandle,
            fromIndex++,
            fromEntity.copiedM1Bars
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.dataStatus);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.calculationNote
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.isZeroSpread
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.isOrderUnknown
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.priceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                fromIndex++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, fromIndex++, fromEntity.createdAt);
        }

        return isBound && fromIndex == fromExpectedCount;
    }

    /**
     * runKeyに一致するRun IDを取得する。
     *
     * @param fromRunKey 検索対象runKey。
     * @param fromRunId 取得したRun IDの格納先。
     * @return Run IDを取得できた場合true。
     */
    bool findRunIdByKey(const string fromRunKey, long &fromRunId) {
        fromRunId = 0;
        string sql = "SELECT id FROM zigzag_elliot_entry_outcome_runs ";
        sql += "WHERE run_key = ?1 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseBind(requestHandle, 0, fromRunKey)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromRunId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return fromRunId > 0;
    }

    /**
     * Outcome自然キーに一致するIDを取得する。
     *
     * @param fromOutcomeRunId 後処理実行ID。
     * @param fromSourceAlertId 参照元Alert ID。
     * @param fromOutcomeId 取得したOutcome IDの格納先。
     * @return Outcome IDを取得できた場合true。
     */
    bool findOutcomeId(
        const long fromOutcomeRunId,
        const long fromSourceAlertId,
        long &fromOutcomeId
    ) {
        fromOutcomeId = 0;
        string sql = "SELECT id FROM zigzag_elliot_entry_outcomes ";
        sql += "WHERE outcome_run_id = ?1 AND source_alert_id = ?2 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, fromOutcomeRunId);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromSourceAlertId);
        }

        if (!isBound || index != 2) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromOutcomeId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return fromOutcomeId > 0;
    }

    /**
     * 後処理実行情報が保存可能か確認する。
     *
     * @param fromEntity 確認対象実行情報。
     * @return 保存可能な場合true。
     */
    bool isRunValid(ZigZagElliotEntryOutcomeRunEntity &fromEntity) {
        if (fromEntity.runKey == ""
                || fromEntity.sourceDatabaseFileName == ""
                || fromEntity.sourceRunId <= 0
                || fromEntity.sourceRunUid == ""
                || fromEntity.sourceMode == ""
                || fromEntity.sourceServer == ""
                || fromEntity.sourceProgramName == ""
                || fromEntity.sourceProgramVersion == ""
                || fromEntity.sourceStrategy == ""
                || fromEntity.horizonH1Bars <= 0
                || fromEntity.priceModel == ""
                || fromEntity.evaluationVersion == ""
                || fromEntity.status != "RUNNING"
                || fromEntity.startedAt <= 0
                || fromEntity.createdAt <= 0
                || fromEntity.updatedAt <= 0) {
            return false;
        }

        if (fromEntity.sourceTesterFrom > 0
                && fromEntity.sourceTesterTo > 0
                && fromEntity.sourceTesterTo < fromEntity.sourceTesterFrom) {
            return false;
        }

        return true;
    }

    /**
     * Outcomeが保存可能か確認する。
     *
     * @param fromEntity 確認対象結果。
     * @return 保存可能な場合true。
     */
    bool isOutcomeValid(ZigZagElliotEntryOutcomeEntity &fromEntity) {
        if (fromEntity.outcomeRunId <= 0
                || fromEntity.sourceAlertId <= 0
                || fromEntity.sourceRunId <= 0
                || fromEntity.marketSignalKey == ""
                || fromEntity.sourceServer == ""
                || fromEntity.symbolName == ""
                || (fromEntity.side != "BUY" && fromEntity.side != "SELL")
                || fromEntity.currentBarTime <= 0
                || fromEntity.entryTime <= 0
                || !MathIsValidNumber(fromEntity.entryPrice)
                || fromEntity.entryPrice <= 0.0
                || !MathIsValidNumber(fromEntity.spreadPips)
                || fromEntity.spreadPips < 0.0
                || !MathIsValidNumber(fromEntity.stopLoss)
                || fromEntity.stopLoss <= 0.0
                || !MathIsValidNumber(fromEntity.sourceRiskPips)
                || fromEntity.sourceRiskPips < 0.0
                || !MathIsValidNumber(fromEntity.calculatedRiskPips)
                || fromEntity.calculatedRiskPips < 0.0
                || fromEntity.horizonH1Bars <= 0
                || fromEntity.evaluationStartTime <= 0
                || fromEntity.evaluationEndTime < 0
                || !this.isBoolean(fromEntity.isCalculated)
                || fromEntity.copiedM1Bars < 0
                || fromEntity.dataStatus == ""
                || !this.isBoolean(fromEntity.isZeroSpread)
                || !this.isBoolean(fromEntity.isOrderUnknown)
                || fromEntity.priceModel == ""
                || fromEntity.evaluationVersion == ""
                || fromEntity.createdAt <= 0) {
            return false;
        }

        if (fromEntity.isCalculated == 0) {
            return true;
        }

        if (!MathIsValidNumber(fromEntity.mfePips)
                || fromEntity.mfePips < 0.0
                || !MathIsValidNumber(fromEntity.mfeR)
                || fromEntity.mfeR < 0.0
                || !MathIsValidNumber(fromEntity.maePips)
                || fromEntity.maePips < 0.0
                || !MathIsValidNumber(fromEntity.maeR)
                || fromEntity.maeR < 0.0
                || !MathIsValidNumber(fromEntity.profitPips)
                || !MathIsValidNumber(fromEntity.profitR)
                || fromEntity.evaluationEndTime
                    < fromEntity.evaluationStartTime
                || fromEntity.exitTime < fromEntity.evaluationStartTime
                || fromEntity.exitTime > fromEntity.evaluationEndTime
                || !MathIsValidNumber(fromEntity.exitPrice)
                || fromEntity.exitPrice <= 0.0
                || fromEntity.exitReason == ""
                || fromEntity.barsHeldM1 < 0
                || fromEntity.barsHeldH1 < 0
                || fromEntity.copiedM1Bars <= 0) {
            return false;
        }

        return true;
    }

    /**
     * 0または1か確認する。
     *
     * @param fromValue 確認値。
     * @return 0または1の場合true。
     */
    bool isBoolean(const int fromValue) {
        return fromValue == 0 || fromValue == 1;
    }

    /**
     * 外部キー制約が有効か確認する。
     *
     * @return PRAGMA foreign_keysが1の場合true。
     */
    bool isForeignKeysEnabled() {
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA foreign_keys"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        int isEnabled = 0;
        ResetLastError();

        if (!DatabaseColumnInteger(requestHandle, 0, isEnabled)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnInteger failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (isEnabled != 1) {
            this.logger.error(__FUNCTION__, "Foreign keys are disabled.");

            return false;
        }

        return true;
    }

    /**
     * SQLite changes()を取得する。
     *
     * @param fromChangedCount 変更行数の格納先。
     * @return 変更行数を取得できた場合true。
     */
    bool readChanges(long &fromChangedCount) {
        fromChangedCount = 0;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "SELECT changes()"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromChangedCount)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 現在時刻を取得する。
     *
     * @return 取引サーバー時刻。利用不能時はローカル時刻。
     */
    datetime getCurrentTime() {
        datetime currentTime = TimeCurrent();

        if (currentTime <= 0) {
            currentTime = TimeLocal();
        }

        return currentTime;
    }

    /**
     * 結果行を返さない準備済みリクエストを実行する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromOperationName 操作名。
     * @return 実行できた場合true。
     */
    bool executeRequest(
        const int fromRequestHandle,
        const string fromMethodName,
        const string fromOperationName
    ) {
        ResetLastError();
        bool isRead = DatabaseRead(fromRequestHandle);
        int errorCode = GetLastError();

        if (!isRead && errorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseRead failed. operation=%s error=%d",
                    fromOperationName,
                    errorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * SQLを直接実行する。
     *
     * @param fromSql 実行SQL。
     * @param fromOperationName 操作名。
     * @return 実行できた場合true。
     */
    bool executeSql(
        const string fromSql,
        const string fromOperationName
    ) {
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, fromSql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. operation=%s error=%d",
                    fromOperationName,
                    GetLastError()
                )
            );

            return false;
        }

        return true;
    }

    /**
     * データベースハンドルが使用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 使用可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "Database handle is invalid.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ENTRY_OUTCOME_DAO_MQH
