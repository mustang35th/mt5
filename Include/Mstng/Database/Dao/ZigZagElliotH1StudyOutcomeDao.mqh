//+------------------------------------------------------------------+
//|                        ZigZagElliotH1StudyOutcomeDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_DAO_MQH

#include <Mstng\Database\Entity\ZigZagElliotH1StudyOutcomeEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * H1推移研究のRun、Entryおよび将来成績を別SQLiteへ保存するDAO。
 */
class ZigZagElliotH1StudyOutcomeDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle Outcome DBのデータベースハンドル。
     */
    ZigZagElliotH1StudyOutcomeDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.isTransactionActive = false;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * H1推移研究Outcomeの3テーブルとインデックスを作成する。
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
        sql += "zigzag_elliot_h1_study_outcome_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_key TEXT NOT NULL UNIQUE,";
        sql += "source_database_file_name TEXT NOT NULL,";
        sql += "source_run_id INTEGER NOT NULL CHECK(source_run_id > 0),";
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
        sql += "source_tester_from INTEGER NOT NULL ";
        sql += "CHECK(source_tester_from >= 0),";
        sql += "source_tester_to INTEGER NOT NULL ";
        sql += "CHECK(source_tester_to >= 0),";
        sql += "source_tester_model TEXT NOT NULL,";
        sql += "study_from_jst_time INTEGER NOT NULL ";
        sql += "CHECK(study_from_jst_time > 0),";
        sql += "study_to_jst_time INTEGER NOT NULL ";
        sql += "CHECK(study_to_jst_time > study_from_jst_time),";
        sql += "signal_rule_version TEXT NOT NULL,";
        sql += "entry_price_model TEXT NOT NULL,";
        sql += "spread_model TEXT NOT NULL,";
        sql += "evaluation_version TEXT NOT NULL,";
        sql += "horizons_text TEXT NOT NULL,";
        sql += "status TEXT NOT NULL ";
        sql += "CHECK(status IN ('RUNNING', 'COMPLETED', 'FAILED')),";
        sql += "source_stream_count INTEGER NOT NULL ";
        sql += "CHECK(source_stream_count >= 0),";
        sql += "total_signal_count INTEGER NOT NULL ";
        sql += "CHECK(total_signal_count >= 0),";
        sql += "total_entry_count INTEGER NOT NULL ";
        sql += "CHECK(total_entry_count >= 0),";
        sql += "research_eligible_entry_count INTEGER NOT NULL ";
        sql += "CHECK(research_eligible_entry_count >= 0),";
        sql += "total_outcome_count INTEGER NOT NULL ";
        sql += "CHECK(total_outcome_count >= 0),";
        sql += "calculated_outcome_count INTEGER NOT NULL ";
        sql += "CHECK(calculated_outcome_count >= 0),";
        sql += "failed_outcome_count INTEGER NOT NULL ";
        sql += "CHECK(failed_outcome_count >= 0),";
        sql += "started_at INTEGER NOT NULL,";
        sql += "completed_at INTEGER,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "CHECK(source_tester_from = 0 OR source_tester_to = 0 OR ";
        sql += "source_tester_to >= source_tester_from),";
        sql += "CHECK(research_eligible_entry_count <= total_entry_count),";
        sql += "CHECK(calculated_outcome_count + failed_outcome_count ";
        sql += "<= total_outcome_count),";
        sql += "CHECK(status = 'RUNNING' OR ";
        sql += "total_outcome_count = total_entry_count * 4),";
        sql += "CHECK(status = 'RUNNING' OR ";
        sql += "calculated_outcome_count + failed_outcome_count ";
        sql += "= total_outcome_count),";
        sql += "CHECK((status = 'RUNNING' AND completed_at IS NULL) OR ";
        sql += "(status IN ('COMPLETED', 'FAILED') ";
        sql += "AND completed_at IS NOT NULL))";
        sql += ")";

        if (!this.executeSql(sql, "H1 study outcome runs table")) {
            return false;
        }

        sql = "CREATE TABLE IF NOT EXISTS ";
        sql += "zigzag_elliot_h1_study_entries (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "outcome_run_id INTEGER NOT NULL,";
        sql += "source_run_id INTEGER NOT NULL CHECK(source_run_id > 0),";
        sql += "signal_start_observation_id INTEGER NOT NULL ";
        sql += "CHECK(signal_start_observation_id > 0),";
        sql += "signal_end_observation_id INTEGER NOT NULL ";
        sql += "CHECK(signal_end_observation_id > 0),";
        sql += "confirmation_observation_id INTEGER NOT NULL ";
        sql += "CHECK(confirmation_observation_id > 0),";
        sql += "entry_observation_id INTEGER NOT NULL ";
        sql += "CHECK(entry_observation_id >= 0),";
        sql += "source_mode TEXT NOT NULL,";
        sql += "source_server TEXT NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "anchor_time_frame INTEGER NOT NULL ";
        sql += "CHECK(anchor_time_frame > 0),";
        sql += "capture_phase TEXT NOT NULL,";
        sql += "analysis_version TEXT NOT NULL,";
        sql += "analysis_input_hash TEXT NOT NULL,";
        sql += "side TEXT NOT NULL CHECK(side IN ('BUY', 'SELL')),";
        sql += "episode_h1_count INTEGER NOT NULL ";
        sql += "CHECK(episode_h1_count > 0),";
        sql += "confirmation_h1_count INTEGER NOT NULL ";
        sql += "CHECK(confirmation_h1_count IN (1, 2, 3)),";
        sql += "is_left_censored INTEGER NOT NULL ";
        sql += "CHECK(is_left_censored IN (0, 1)),";
        sql += "is_right_censored INTEGER NOT NULL ";
        sql += "CHECK(is_right_censored IN (0, 1)),";
        sql += "has_data_gap_before INTEGER NOT NULL ";
        sql += "CHECK(has_data_gap_before IN (0, 1)),";
        sql += "has_data_gap_after INTEGER NOT NULL ";
        sql += "CHECK(has_data_gap_after IN (0, 1)),";
        sql += "is_research_eligible INTEGER NOT NULL ";
        sql += "CHECK(is_research_eligible IN (0, 1)),";
        sql += "eligibility_status TEXT NOT NULL,";
        sql += "signal_start_time INTEGER NOT NULL ";
        sql += "CHECK(signal_start_time > 0),";
        sql += "signal_end_time INTEGER NOT NULL CHECK(signal_end_time > 0),";
        sql += "confirmation_time INTEGER NOT NULL ";
        sql += "CHECK(confirmation_time > 0),";
        sql += "entry_time INTEGER NOT NULL CHECK(entry_time >= 0),";
        sql += "signal_start_jst_time INTEGER NOT NULL ";
        sql += "CHECK(signal_start_jst_time > 0),";
        sql += "confirmation_jst_time INTEGER NOT NULL ";
        sql += "CHECK(confirmation_jst_time > 0),";
        sql += "entry_jst_time INTEGER NOT NULL CHECK(entry_jst_time >= 0),";
        sql += "entry_price REAL NOT NULL CHECK(entry_price >= 0),";
        sql += "is_spread_available INTEGER NOT NULL ";
        sql += "CHECK(is_spread_available IN (0, 1)),";
        sql += "spread_pips REAL NOT NULL CHECK(spread_pips >= 0),";
        sql += "is_pip_size_available INTEGER NOT NULL ";
        sql += "CHECK(is_pip_size_available IN (0, 1)),";
        sql += "pip_size REAL NOT NULL CHECK(pip_size >= 0),";
        sql += "pip_size_source TEXT NOT NULL,";
        sql += "is_entry_atr_available INTEGER NOT NULL ";
        sql += "CHECK(is_entry_atr_available IN (0, 1)),";
        sql += "entry_atr14_pips REAL NOT NULL CHECK(entry_atr14_pips >= 0),";
        sql += "entry_status TEXT NOT NULL,";
        sql += "calculation_note TEXT NOT NULL,";
        sql += "signal_rule_version TEXT NOT NULL,";
        sql += "entry_price_model TEXT NOT NULL,";
        sql += "spread_model TEXT NOT NULL,";
        sql += "evaluation_version TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "FOREIGN KEY(outcome_run_id) REFERENCES ";
        sql += "zigzag_elliot_h1_study_outcome_runs(id) ON DELETE CASCADE,";
        sql += "UNIQUE(outcome_run_id, signal_start_observation_id,";
        sql += " confirmation_h1_count),";
        sql += "CHECK(confirmation_h1_count <= episode_h1_count),";
        sql += "CHECK(signal_end_time >= signal_start_time),";
        sql += "CHECK(confirmation_time >= signal_start_time ";
        sql += "AND confirmation_time <= signal_end_time),";
        sql += "CHECK(confirmation_jst_time >= signal_start_jst_time),";
        sql += "CHECK((entry_observation_id = 0 AND entry_time = 0 ";
        sql += "AND entry_jst_time = 0 AND entry_price = 0) OR ";
        sql += "(entry_observation_id > 0 AND entry_time > confirmation_time ";
        sql += "AND entry_jst_time > confirmation_jst_time ";
        sql += "AND entry_price > 0)),";
        sql += "CHECK((is_spread_available = 0 AND spread_pips = 0) OR ";
        sql += "is_spread_available = 1),";
        sql += "CHECK((is_pip_size_available = 0 AND pip_size = 0) OR ";
        sql += "(is_pip_size_available = 1 AND pip_size > 0)),";
        sql += "CHECK((is_entry_atr_available = 0 ";
        sql += "AND entry_atr14_pips = 0) OR ";
        sql += "(is_entry_atr_available = 1 AND entry_atr14_pips > 0)),";
        sql += "CHECK(is_research_eligible = 0 OR ";
        sql += "(is_left_censored = 0 AND has_data_gap_before = 0 ";
        sql += "AND entry_observation_id > 0 ";
        sql += "AND is_spread_available = 1 ";
        sql += "AND is_pip_size_available = 1 ";
        sql += "AND is_entry_atr_available = 1))";
        sql += ")";

        if (!this.executeSql(sql, "H1 study entries table")) {
            return false;
        }

        sql = "CREATE TABLE IF NOT EXISTS ";
        sql += "zigzag_elliot_h1_study_outcomes (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "entry_id INTEGER NOT NULL,";
        sql += "horizon_h1_bars INTEGER NOT NULL ";
        sql += "CHECK(horizon_h1_bars IN (6, 12, 24, 48)),";
        sql += "is_calculated INTEGER NOT NULL ";
        sql += "CHECK(is_calculated IN (0, 1)),";
        sql += "evaluation_end_observation_id INTEGER,";
        sql += "evaluation_end_time INTEGER,";
        sql += "exit_price REAL,";
        sql += "gross_profit_pips REAL,";
        sql += "net_profit_pips REAL,";
        sql += "gross_profit_atr REAL,";
        sql += "net_profit_atr REAL,";
        sql += "mfe_pips REAL,";
        sql += "mae_pips REAL,";
        sql += "max_profit_h1_bars INTEGER,";
        sql += "evaluated_h1_bars INTEGER NOT NULL ";
        sql += "CHECK(evaluated_h1_bars >= 0),";
        sql += "data_status TEXT NOT NULL,";
        sql += "calculation_note TEXT NOT NULL,";
        sql += "price_model TEXT NOT NULL,";
        sql += "spread_model TEXT NOT NULL,";
        sql += "evaluation_version TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "FOREIGN KEY(entry_id) REFERENCES ";
        sql += "zigzag_elliot_h1_study_entries(id) ON DELETE CASCADE,";
        sql += "UNIQUE(entry_id, horizon_h1_bars),";
        sql += "CHECK(evaluated_h1_bars <= horizon_h1_bars),";
        sql += "CHECK((is_calculated = 0 ";
        sql += "AND evaluation_end_observation_id IS NULL ";
        sql += "AND evaluation_end_time IS NULL AND exit_price IS NULL ";
        sql += "AND gross_profit_pips IS NULL AND net_profit_pips IS NULL ";
        sql += "AND gross_profit_atr IS NULL AND net_profit_atr IS NULL ";
        sql += "AND mfe_pips IS NULL AND mae_pips IS NULL ";
        sql += "AND max_profit_h1_bars IS NULL) OR ";
        sql += "(is_calculated = 1 ";
        sql += "AND evaluation_end_observation_id IS NOT NULL ";
        sql += "AND evaluation_end_observation_id > 0 ";
        sql += "AND evaluation_end_time IS NOT NULL ";
        sql += "AND evaluation_end_time > 0 AND exit_price IS NOT NULL ";
        sql += "AND exit_price > 0 AND gross_profit_pips IS NOT NULL ";
        sql += "AND net_profit_pips IS NOT NULL ";
        sql += "AND gross_profit_atr IS NOT NULL ";
        sql += "AND net_profit_atr IS NOT NULL AND mfe_pips IS NOT NULL ";
        sql += "AND mfe_pips >= 0 AND mae_pips IS NOT NULL ";
        sql += "AND mae_pips >= 0 AND max_profit_h1_bars IS NOT NULL ";
        sql += "AND max_profit_h1_bars >= 0 ";
        sql += "AND max_profit_h1_bars <= horizon_h1_bars ";
        sql += "AND ((mfe_pips = 0 AND max_profit_h1_bars = 0) OR ";
        sql += "(mfe_pips > 0 AND max_profit_h1_bars >= 1)) ";
        sql += "AND evaluated_h1_bars = horizon_h1_bars))";
        sql += ",CHECK((is_calculated = 1 AND data_status = 'READY') OR ";
        sql += "(is_calculated = 0 AND data_status <> 'READY'))";
        sql += ")";

        if (!this.executeSql(sql, "H1 study outcomes table")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_h1_study_outcome_runs_source ON ";
        sql += "zigzag_elliot_h1_study_outcome_runs(";
        sql += "source_database_file_name, source_run_id)";

        if (!this.executeSql(sql, "H1 study outcome source run index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS idx_h1_study_entries_source_time ";
        sql += "ON zigzag_elliot_h1_study_entries(";
        sql += "source_run_id, symbol_name, signal_start_time)";

        if (!this.executeSql(sql, "H1 study entry source time index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS idx_h1_study_entries_eligibility ";
        sql += "ON zigzag_elliot_h1_study_entries(";
        sql += "is_research_eligible, confirmation_h1_count, side, entry_time)";

        if (!this.executeSql(sql, "H1 study entry eligibility index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS idx_h1_study_outcomes_horizon ";
        sql += "ON zigzag_elliot_h1_study_outcomes(";
        sql += "horizon_h1_bars, is_calculated, data_status)";

        if (!this.executeSql(sql, "H1 study outcome horizon index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "ZigZagElliot H1 study outcome tables are ready."
        );

        return true;
    }

    /**
     * runKeyに一致する研究Runを取得または作成する。
     *
     * 既存Runは同じIDを維持し、RUNNINGおよび件数0へ戻す。
     *
     * @param fromEntity 保存する研究Run。
     * @param fromRunId 取得または作成したRun IDの格納先。
     * @return Runを準備できた場合true。
     */
    bool findOrCreateRun(
        ZigZagElliotH1StudyOutcomeRunEntity &fromEntity,
        long &fromRunId
    ) {
        fromRunId = 0;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        datetime currentTime = this.getCurrentTime();
        fromEntity.id = 0;
        fromEntity.status = "RUNNING";
        fromEntity.sourceStreamCount = 0;
        fromEntity.totalSignalCount = 0;
        fromEntity.totalEntryCount = 0;
        fromEntity.researchEligibleEntryCount = 0;
        fromEntity.totalOutcomeCount = 0;
        fromEntity.calculatedOutcomeCount = 0;
        fromEntity.failedOutcomeCount = 0;
        fromEntity.completedAt = 0;

        if (fromEntity.startedAt <= 0) {
            fromEntity.startedAt = currentTime;
        }
        if (fromEntity.createdAt <= 0) {
            fromEntity.createdAt = currentTime;
        }

        fromEntity.updatedAt = currentTime;

        if (!this.isRunValid(fromEntity)) {
            this.logger.error(__FUNCTION__, "H1 study outcome run is invalid.");

            return false;
        }

        string sql = this.buildRunUpsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        if (!this.bindRun(requestHandle, fromEntity)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "upsert H1 study outcome run"
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
     * 指定Runの既存EntryとOutcomeを削除する。
     *
     * Outcomeは外部キーのON DELETE CASCADEで削除される。
     *
     * @param fromRunId 対象研究Run ID。
     * @return 削除SQLを実行できた場合true。
     */
    bool deleteRunChildren(const long fromRunId) {
        if (!this.isDatabaseReady(__FUNCTION__) || fromRunId <= 0) {
            return false;
        }

        string sql = "DELETE FROM zigzag_elliot_h1_study_entries ";
        sql += "WHERE outcome_run_id = ?1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        ResetLastError();

        if (!DatabaseBind(requestHandle, 0, fromRunId)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "delete H1 study run children"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

    /**
     * Entryと4期間Outcomeを原子的に保存するトランザクションを開始する。
     *
     * @return 開始できた場合true。
     */
    bool beginTransaction() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (this.isTransactionActive) {
            this.logger.error(__FUNCTION__, "Transaction is already active.");

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionBegin(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionBegin failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        this.isTransactionActive = true;

        return true;
    }

    /**
     * 研究用Entryを保存する。
     *
     * 自然キー重複時は最新の抽出結果へ更新し、保存後のIDを設定する。
     *
     * @param fromEntity 保存対象Entry。
     * @return 保存できた場合true。
     */
    bool saveEntry(ZigZagElliotH1StudyEntryEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromEntity.id = 0;

        if (fromEntity.createdAt <= 0) {
            fromEntity.createdAt = this.getCurrentTime();
        }

        if (!this.isEntryValid(fromEntity)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 study entry is invalid. observationId=%I64d confirmation=%d",
                    fromEntity.signalStartObservationId,
                    fromEntity.confirmationH1Count
                )
            );

            return false;
        }

        string sql = this.buildEntryUpsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        if (!this.bindEntry(requestHandle, fromEntity)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "upsert H1 study entry"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted
                || !this.findEntryId(
                    fromEntity.outcomeRunId,
                    fromEntity.signalStartObservationId,
                    fromEntity.confirmationH1Count,
                    fromEntity.id
                )) {
            return false;
        }

        return true;
    }

    /**
     * 研究用Entryの1期間分の将来成績を保存する。
     *
     * 同じEntryと評価期間は最新結果へ更新する。未計算時は結果指標を
     * SQL NULLとして保存する。
     *
     * @param fromEntity 保存対象Outcome。
     * @return 保存できた場合true。
     */
    bool saveOutcome(ZigZagElliotH1StudyOutcomeEntity &fromEntity) {
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
                    "H1 study outcome is invalid. entryId=%I64d horizon=%d",
                    fromEntity.entryId,
                    fromEntity.horizonH1Bars
                )
            );

            return false;
        }

        bool isCalculated = fromEntity.isCalculated == 1;
        string sql = this.buildOutcomeUpsertSql(isCalculated);
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

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
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "upsert H1 study outcome"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted
                || !this.findOutcomeId(
                    fromEntity.entryId,
                    fromEntity.horizonH1Bars,
                    fromEntity.id
                )) {
            return false;
        }

        return true;
    }

    /**
     * 現在のトランザクションをコミットする。
     *
     * @return コミットできた場合true。
     */
    bool commitTransaction() {
        if (!this.isDatabaseReady(__FUNCTION__)
                || !this.isTransactionActive) {
            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionCommit failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        this.isTransactionActive = false;

        return true;
    }

    /**
     * 現在のトランザクションをロールバックする。
     *
     * @return ロールバックできた場合true。
     */
    bool rollbackTransaction() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.isTransactionActive) {
            return true;
        }

        ResetLastError();

        if (!DatabaseTransactionRollback(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionRollback failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        this.isTransactionActive = false;

        return true;
    }

    /**
     * 致命的な中断後に研究RunをFAILEDへ更新する。
     *
     * Entry保存トランザクションをロールバックした後に呼び出し、
     * RUNNINGのまま残さないために使用する。
     *
     * @param fromRunId 更新対象Run ID。
     * @param fromCompletedAt 完了時刻。0以下の場合は現在時刻を使用する。
     * @return 対象Runを1件更新できた場合true。
     */
    bool failRun(
        const long fromRunId,
        const datetime fromCompletedAt
    ) {
        if (!this.isDatabaseReady(__FUNCTION__) || fromRunId <= 0) {
            return false;
        }

        datetime completedAt = fromCompletedAt;

        if (completedAt <= 0) {
            completedAt = this.getCurrentTime();
        }

        string sql = "UPDATE zigzag_elliot_h1_study_outcome_runs SET ";
        sql += "status = 'FAILED', completed_at = ?1, updated_at = ?2 ";
        sql += "WHERE id = ?3";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, completedAt);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, completedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromRunId);
        }

        if (!isBound || index != 3) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "fail H1 study outcome run"
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
                    "Run failure row count is invalid. runId=%I64d changed=%I64d",
                    fromRunId,
                    changedCount
                )
            );

            return false;
        }

        return true;
    }

    /**
     * 研究Runを完了状態へ更新する。
     *
     * @param fromRunId 更新対象Run ID。
     * @param fromStatus COMPLETEDまたはFAILED。
     * @param fromSourceStreamCount 読み取ったStream数。
     * @param fromTotalSignalCount 連続シグナル総数。
     * @param fromTotalEntryCount Entry総数。
     * @param fromResearchEligibleEntryCount 研究利用可能Entry数。
     * @param fromTotalOutcomeCount Outcome総数。
     * @param fromCalculatedOutcomeCount 計算成功Outcome数。
     * @param fromFailedOutcomeCount 計算不能Outcome数。
     * @return 1件更新できた場合true。
     */
    bool completeRun(
        const long fromRunId,
        const string fromStatus,
        const long fromSourceStreamCount,
        const long fromTotalSignalCount,
        const long fromTotalEntryCount,
        const long fromResearchEligibleEntryCount,
        const long fromTotalOutcomeCount,
        const long fromCalculatedOutcomeCount,
        const long fromFailedOutcomeCount
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromRunId <= 0
                || (fromStatus != "COMPLETED" && fromStatus != "FAILED")
                || fromSourceStreamCount < 0
                || fromTotalSignalCount < 0
                || fromTotalEntryCount < 0
                || fromResearchEligibleEntryCount < 0
                || fromResearchEligibleEntryCount > fromTotalEntryCount
                || fromTotalOutcomeCount < 0
                || fromTotalOutcomeCount != fromTotalEntryCount * 4
                || fromCalculatedOutcomeCount < 0
                || fromFailedOutcomeCount < 0
                || fromCalculatedOutcomeCount + fromFailedOutcomeCount
                    != fromTotalOutcomeCount) {
            this.logger.error(__FUNCTION__, "Run completion values are invalid.");

            return false;
        }

        datetime completedAt = this.getCurrentTime();
        string sql = "UPDATE zigzag_elliot_h1_study_outcome_runs SET ";
        sql += "status = ?1, source_stream_count = ?2,";
        sql += " total_signal_count = ?3, total_entry_count = ?4,";
        sql += " research_eligible_entry_count = ?5,";
        sql += " total_outcome_count = ?6, calculated_outcome_count = ?7,";
        sql += " failed_outcome_count = ?8, completed_at = ?9,";
        sql += " updated_at = ?10 WHERE id = ?11";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, fromStatus);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromSourceStreamCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromTotalSignalCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromTotalEntryCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                index++,
                fromResearchEligibleEntryCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromTotalOutcomeCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                index++,
                fromCalculatedOutcomeCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromFailedOutcomeCount);
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

        if (!isBound || index != 11) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "complete H1 study outcome run"
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

    /** トランザクション実行中の場合true。 */
    bool isTransactionActive;

    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /**
     * 研究RunのUPSERT文を生成する。
     *
     * @return パラメーター化したUPSERT文。
     */
    string buildRunUpsertSql() {
        string sql = "INSERT INTO zigzag_elliot_h1_study_outcome_runs (";
        sql += "run_key, source_database_file_name, source_run_id,";
        sql += " source_run_uid, source_mode, source_server, source_login,";
        sql += " source_program_name, source_program_version,";
        sql += " source_strategy, source_strategy_version,";
        sql += " source_analysis_version, source_analysis_input_hash,";
        sql += " source_input_hash, source_tester_from, source_tester_to,";
        sql += " source_tester_model, study_from_jst_time, study_to_jst_time,";
        sql += " signal_rule_version, entry_price_model, spread_model,";
        sql += " evaluation_version, horizons_text, status,";
        sql += " source_stream_count, total_signal_count, total_entry_count,";
        sql += " research_eligible_entry_count, total_outcome_count,";
        sql += " calculated_outcome_count, failed_outcome_count, started_at,";
        sql += " completed_at, created_at, updated_at) VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,";
        sql += " ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20,";
        sql += " ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30,";
        sql += " ?31, ?32, ?33, NULL, ?34, ?35) ";
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
        sql += " study_from_jst_time = excluded.study_from_jst_time,";
        sql += " study_to_jst_time = excluded.study_to_jst_time,";
        sql += " signal_rule_version = excluded.signal_rule_version,";
        sql += " entry_price_model = excluded.entry_price_model,";
        sql += " spread_model = excluded.spread_model,";
        sql += " evaluation_version = excluded.evaluation_version,";
        sql += " horizons_text = excluded.horizons_text,";
        sql += " status = 'RUNNING', source_stream_count = 0,";
        sql += " total_signal_count = 0, total_entry_count = 0,";
        sql += " research_eligible_entry_count = 0, total_outcome_count = 0,";
        sql += " calculated_outcome_count = 0, failed_outcome_count = 0,";
        sql += " started_at = excluded.started_at, completed_at = NULL,";
        sql += " updated_at = excluded.updated_at";

        return sql;
    }

    /**
     * 研究Run UPSERTの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象研究Run。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindRun(
        const int fromRequestHandle,
        ZigZagElliotH1StudyOutcomeRunEntity &fromEntity
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
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceStrategy);
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
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceInputHash);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceTesterFrom);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceTesterTo);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.sourceTesterModel
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.studyFromJstTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.studyToJstTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalRuleVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryPriceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.horizonsText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.status);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceStreamCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.totalSignalCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.totalEntryCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.researchEligibleEntryCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.totalOutcomeCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.calculatedOutcomeCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.failedOutcomeCount);
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

        return isBound && index == 35;
    }

    /**
     * Entry UPSERT文を生成する。
     *
     * @return パラメーター化したUPSERT文。
     */
    string buildEntryUpsertSql() {
        string sql = "INSERT INTO zigzag_elliot_h1_study_entries (";
        sql += "outcome_run_id, source_run_id, signal_start_observation_id,";
        sql += " signal_end_observation_id, confirmation_observation_id,";
        sql += " entry_observation_id, source_mode, source_server,";
        sql += " symbol_name, anchor_time_frame, capture_phase,";
        sql += " analysis_version, analysis_input_hash, side,";
        sql += " episode_h1_count, confirmation_h1_count,";
        sql += " is_left_censored, is_right_censored,";
        sql += " has_data_gap_before, has_data_gap_after,";
        sql += " is_research_eligible, eligibility_status,";
        sql += " signal_start_time, signal_end_time, confirmation_time,";
        sql += " entry_time, signal_start_jst_time, confirmation_jst_time,";
        sql += " entry_jst_time, entry_price, is_spread_available,";
        sql += " spread_pips, is_pip_size_available, pip_size,";
        sql += " pip_size_source, is_entry_atr_available, entry_atr14_pips,";
        sql += " entry_status, calculation_note, signal_rule_version,";
        sql += " entry_price_model, spread_model, evaluation_version,";
        sql += " created_at) VALUES (";

        for (int i = 1; i <= 44; i++) {
            if (i > 1) {
                sql += ", ";
            }

            sql += "?" + IntegerToString(i);
        }

        sql += ") ON CONFLICT(outcome_run_id, signal_start_observation_id,";
        sql += " confirmation_h1_count) DO UPDATE SET ";
        sql += "source_run_id = excluded.source_run_id,";
        sql += " signal_end_observation_id = excluded.signal_end_observation_id,";
        sql += " confirmation_observation_id = excluded.confirmation_observation_id,";
        sql += " entry_observation_id = excluded.entry_observation_id,";
        sql += " source_mode = excluded.source_mode,";
        sql += " source_server = excluded.source_server,";
        sql += " symbol_name = excluded.symbol_name,";
        sql += " anchor_time_frame = excluded.anchor_time_frame,";
        sql += " capture_phase = excluded.capture_phase,";
        sql += " analysis_version = excluded.analysis_version,";
        sql += " analysis_input_hash = excluded.analysis_input_hash,";
        sql += " side = excluded.side,";
        sql += " episode_h1_count = excluded.episode_h1_count,";
        sql += " is_left_censored = excluded.is_left_censored,";
        sql += " is_right_censored = excluded.is_right_censored,";
        sql += " has_data_gap_before = excluded.has_data_gap_before,";
        sql += " has_data_gap_after = excluded.has_data_gap_after,";
        sql += " is_research_eligible = excluded.is_research_eligible,";
        sql += " eligibility_status = excluded.eligibility_status,";
        sql += " signal_start_time = excluded.signal_start_time,";
        sql += " signal_end_time = excluded.signal_end_time,";
        sql += " confirmation_time = excluded.confirmation_time,";
        sql += " entry_time = excluded.entry_time,";
        sql += " signal_start_jst_time = excluded.signal_start_jst_time,";
        sql += " confirmation_jst_time = excluded.confirmation_jst_time,";
        sql += " entry_jst_time = excluded.entry_jst_time,";
        sql += " entry_price = excluded.entry_price,";
        sql += " is_spread_available = excluded.is_spread_available,";
        sql += " spread_pips = excluded.spread_pips,";
        sql += " is_pip_size_available = excluded.is_pip_size_available,";
        sql += " pip_size = excluded.pip_size,";
        sql += " pip_size_source = excluded.pip_size_source,";
        sql += " is_entry_atr_available = excluded.is_entry_atr_available,";
        sql += " entry_atr14_pips = excluded.entry_atr14_pips,";
        sql += " entry_status = excluded.entry_status,";
        sql += " calculation_note = excluded.calculation_note,";
        sql += " signal_rule_version = excluded.signal_rule_version,";
        sql += " entry_price_model = excluded.entry_price_model,";
        sql += " spread_model = excluded.spread_model,";
        sql += " evaluation_version = excluded.evaluation_version,";
        sql += " created_at = excluded.created_at";

        return sql;
    }

    /**
     * Entry UPSERTの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象Entry。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindEntry(
        const int fromRequestHandle,
        ZigZagElliotH1StudyEntryEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(
            fromRequestHandle,
            index++,
            fromEntity.outcomeRunId
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceRunId);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalStartObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalEndObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.confirmationObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.entryObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.anchorTimeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.capturePhase);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.analysisVersion);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.analysisInputHash
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.side);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.episodeH1Count);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.confirmationH1Count
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isLeftCensored);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isRightCensored);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.hasDataGapBefore);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.hasDataGapAfter);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isResearchEligible
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.eligibilityStatus
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.signalStartTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.signalEndTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.confirmationTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalStartJstTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.confirmationJstTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryJstTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryPrice);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isSpreadAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadPips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isPipSizeAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.pipSize);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.pipSizeSource);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isEntryAtrAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryAtr14Pips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryStatus);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.calculationNote);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalRuleVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryPriceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }

        return isBound && index == 44;
    }

    /**
     * Outcome UPSERT文を生成する。
     *
     * @param fromIsCalculated 結果指標を保存する場合true。
     * @return パラメーター化したUPSERT文。
     */
    string buildOutcomeUpsertSql(const bool fromIsCalculated) {
        string sql = "INSERT INTO zigzag_elliot_h1_study_outcomes (";
        sql += "entry_id, horizon_h1_bars, is_calculated,";
        sql += " evaluation_end_observation_id, evaluation_end_time,";
        sql += " exit_price, gross_profit_pips, net_profit_pips,";
        sql += " gross_profit_atr, net_profit_atr, mfe_pips, mae_pips,";
        sql += " max_profit_h1_bars, evaluated_h1_bars, data_status,";
        sql += " calculation_note, price_model, spread_model,";
        sql += " evaluation_version, created_at) VALUES (";
        sql += "?1, ?2, ?3,";

        if (fromIsCalculated) {
            sql += " ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13,";
            sql += " ?14, ?15, ?16, ?17, ?18, ?19, ?20";
        } else {
            sql += " NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,";
            sql += " NULL, NULL, ?4, ?5, ?6, ?7, ?8, ?9, ?10";
        }

        sql += ") ON CONFLICT(entry_id, horizon_h1_bars) DO UPDATE SET ";
        sql += "is_calculated = excluded.is_calculated,";
        sql += " evaluation_end_observation_id ";
        sql += "= excluded.evaluation_end_observation_id,";
        sql += " evaluation_end_time = excluded.evaluation_end_time,";
        sql += " exit_price = excluded.exit_price,";
        sql += " gross_profit_pips = excluded.gross_profit_pips,";
        sql += " net_profit_pips = excluded.net_profit_pips,";
        sql += " gross_profit_atr = excluded.gross_profit_atr,";
        sql += " net_profit_atr = excluded.net_profit_atr,";
        sql += " mfe_pips = excluded.mfe_pips,";
        sql += " mae_pips = excluded.mae_pips,";
        sql += " max_profit_h1_bars = excluded.max_profit_h1_bars,";
        sql += " evaluated_h1_bars = excluded.evaluated_h1_bars,";
        sql += " data_status = excluded.data_status,";
        sql += " calculation_note = excluded.calculation_note,";
        sql += " price_model = excluded.price_model,";
        sql += " spread_model = excluded.spread_model,";
        sql += " evaluation_version = excluded.evaluation_version,";
        sql += " created_at = excluded.created_at";

        return sql;
    }

    /**
     * 計算済みOutcomeの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象Outcome。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindCalculatedOutcome(
        const int fromRequestHandle,
        ZigZagElliotH1StudyOutcomeEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.horizonH1Bars);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isCalculated);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationEndObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationEndTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.exitPrice);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.grossProfitPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.netProfitPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.grossProfitAtr);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.netProfitAtr);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.mfePips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.maePips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.maxProfitH1Bars
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.evaluatedH1Bars);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.dataStatus);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.calculationNote);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.priceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }

        return isBound && index == 20;
    }

    /**
     * 未計算Outcomeの全パラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象Outcome。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindUncalculatedOutcome(
        const int fromRequestHandle,
        ZigZagElliotH1StudyOutcomeEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.horizonH1Bars);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isCalculated);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.evaluatedH1Bars);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.dataStatus);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.calculationNote);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.priceModel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadModel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.evaluationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }

        return isBound && index == 10;
    }

    /**
     * runKeyから研究Run IDを取得する。
     *
     * @param fromRunKey 検索するrunKey。
     * @param fromRunId 取得したIDの格納先。
     * @return 1件取得できた場合true。
     */
    bool findRunIdByKey(const string fromRunKey, long &fromRunId) {
        fromRunId = 0;
        string sql = "SELECT id FROM zigzag_elliot_h1_study_outcome_runs ";
        sql += "WHERE run_key = ?1 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        ResetLastError();

        if (!DatabaseBind(requestHandle, 0, fromRunKey)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        return this.readSingleId(requestHandle, fromRunId, __FUNCTION__);
    }

    /**
     * Entry自然キーからIDを取得する。
     *
     * @param fromRunId Outcome Run ID。
     * @param fromSignalStartObservationId シグナル開始Observation ID。
     * @param fromConfirmationH1Count 連続確認本数。
     * @param fromEntryId 取得したEntry IDの格納先。
     * @return 1件取得できた場合true。
     */
    bool findEntryId(
        const long fromRunId,
        const long fromSignalStartObservationId,
        const int fromConfirmationH1Count,
        long &fromEntryId
    ) {
        fromEntryId = 0;
        string sql = "SELECT id FROM zigzag_elliot_h1_study_entries ";
        sql += "WHERE outcome_run_id = ?1 ";
        sql += "AND signal_start_observation_id = ?2 ";
        sql += "AND confirmation_h1_count = ?3 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, fromRunId);

        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                index++,
                fromSignalStartObservationId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                index++,
                fromConfirmationH1Count
            );
        }

        if (!isBound || index != 3) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        return this.readSingleId(requestHandle, fromEntryId, __FUNCTION__);
    }

    /**
     * Outcome自然キーからIDを取得する。
     *
     * @param fromEntryId Entry ID。
     * @param fromHorizonH1Bars 評価H1本数。
     * @param fromOutcomeId 取得したOutcome IDの格納先。
     * @return 1件取得できた場合true。
     */
    bool findOutcomeId(
        const long fromEntryId,
        const int fromHorizonH1Bars,
        long &fromOutcomeId
    ) {
        fromOutcomeId = 0;
        string sql = "SELECT id FROM zigzag_elliot_h1_study_outcomes ";
        sql += "WHERE entry_id = ?1 AND horizon_h1_bars = ?2 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        int index = 0;
        bool isBound = DatabaseBind(requestHandle, index++, fromEntryId);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, index++, fromHorizonH1Bars);
        }

        if (!isBound || index != 2) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        return this.readSingleId(requestHandle, fromOutcomeId, __FUNCTION__);
    }

    /**
     * 1列1行のIDを読み取る。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromId 取得値の格納先。
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 正のIDを取得できた場合true。
     */
    bool readSingleId(
        const int fromRequestHandle,
        long &fromId,
        const string fromMethodName
    ) {
        ResetLastError();

        if (!DatabaseRead(fromRequestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(fromRequestHandle);
            this.logReadError(fromMethodName, readErrorCode);

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(fromRequestHandle, 0, fromId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(fromRequestHandle);
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(fromRequestHandle);

        return fromId > 0;
    }

    /**
     * 研究Runが保存可能か確認する。
     *
     * @param fromEntity 確認対象研究Run。
     * @return 保存可能な場合true。
     */
    bool isRunValid(ZigZagElliotH1StudyOutcomeRunEntity &fromEntity) {
        if (fromEntity.runKey == ""
                || fromEntity.sourceDatabaseFileName == ""
                || fromEntity.sourceRunId <= 0
                || fromEntity.sourceRunUid == ""
                || fromEntity.sourceMode == ""
                || fromEntity.sourceServer == ""
                || fromEntity.sourceProgramName == ""
                || fromEntity.sourceProgramVersion == ""
                || fromEntity.sourceStrategy == ""
                || fromEntity.sourceStrategyVersion == ""
                || fromEntity.sourceAnalysisVersion == ""
                || fromEntity.studyFromJstTime <= 0
                || fromEntity.studyToJstTime <= fromEntity.studyFromJstTime
                || fromEntity.signalRuleVersion == ""
                || fromEntity.entryPriceModel == ""
                || fromEntity.spreadModel == ""
                || fromEntity.evaluationVersion == ""
                || fromEntity.horizonsText == ""
                || fromEntity.status != "RUNNING"
                || fromEntity.sourceStreamCount != 0
                || fromEntity.totalSignalCount != 0
                || fromEntity.totalEntryCount != 0
                || fromEntity.researchEligibleEntryCount != 0
                || fromEntity.totalOutcomeCount != 0
                || fromEntity.calculatedOutcomeCount != 0
                || fromEntity.failedOutcomeCount != 0
                || fromEntity.startedAt <= 0
                || fromEntity.completedAt != 0
                || fromEntity.createdAt <= 0
                || fromEntity.updatedAt <= 0) {
            return false;
        }

        if (fromEntity.sourceTesterFrom < 0
                || fromEntity.sourceTesterTo < 0
                || (fromEntity.sourceTesterFrom > 0
                    && fromEntity.sourceTesterTo > 0
                    && fromEntity.sourceTesterTo < fromEntity.sourceTesterFrom)) {
            return false;
        }

        return true;
    }

    /**
     * 研究用Entryが保存可能か確認する。
     *
     * @param fromEntity 確認対象Entry。
     * @return 保存可能な場合true。
     */
    bool isEntryValid(ZigZagElliotH1StudyEntryEntity &fromEntity) {
        if (fromEntity.outcomeRunId <= 0
                || fromEntity.sourceRunId <= 0
                || fromEntity.signalStartObservationId <= 0
                || fromEntity.signalEndObservationId <= 0
                || fromEntity.confirmationObservationId <= 0
                || fromEntity.entryObservationId < 0
                || fromEntity.sourceMode == ""
                || fromEntity.sourceServer == ""
                || fromEntity.symbolName == ""
                || fromEntity.anchorTimeFrame <= 0
                || fromEntity.capturePhase == ""
                || fromEntity.analysisVersion == ""
                || (fromEntity.side != "BUY" && fromEntity.side != "SELL")
                || fromEntity.episodeH1Count <= 0
                || fromEntity.confirmationH1Count < 1
                || fromEntity.confirmationH1Count > 3
                || fromEntity.confirmationH1Count > fromEntity.episodeH1Count
                || !this.isBoolean(fromEntity.isLeftCensored)
                || !this.isBoolean(fromEntity.isRightCensored)
                || !this.isBoolean(fromEntity.hasDataGapBefore)
                || !this.isBoolean(fromEntity.hasDataGapAfter)
                || !this.isBoolean(fromEntity.isResearchEligible)
                || fromEntity.eligibilityStatus == ""
                || fromEntity.signalStartTime <= 0
                || fromEntity.signalEndTime < fromEntity.signalStartTime
                || fromEntity.confirmationTime < fromEntity.signalStartTime
                || fromEntity.confirmationTime > fromEntity.signalEndTime
                || fromEntity.signalStartJstTime <= 0
                || fromEntity.confirmationJstTime
                    < fromEntity.signalStartJstTime
                || !MathIsValidNumber(fromEntity.entryPrice)
                || fromEntity.entryPrice == EMPTY_VALUE
                || fromEntity.entryPrice < 0.0
                || !this.isBoolean(fromEntity.isSpreadAvailable)
                || !MathIsValidNumber(fromEntity.spreadPips)
                || fromEntity.spreadPips == EMPTY_VALUE
                || fromEntity.spreadPips < 0.0
                || !this.isBoolean(fromEntity.isPipSizeAvailable)
                || !MathIsValidNumber(fromEntity.pipSize)
                || fromEntity.pipSize == EMPTY_VALUE
                || fromEntity.pipSize < 0.0
                || fromEntity.pipSizeSource == ""
                || !this.isBoolean(fromEntity.isEntryAtrAvailable)
                || !MathIsValidNumber(fromEntity.entryAtr14Pips)
                || fromEntity.entryAtr14Pips == EMPTY_VALUE
                || fromEntity.entryAtr14Pips < 0.0
                || fromEntity.entryStatus == ""
                || fromEntity.signalRuleVersion == ""
                || fromEntity.entryPriceModel == ""
                || fromEntity.spreadModel == ""
                || fromEntity.evaluationVersion == ""
                || fromEntity.createdAt <= 0) {
            return false;
        }

        bool hasEntry = fromEntity.entryObservationId > 0;

        if ((!hasEntry
                    && (fromEntity.entryTime != 0
                        || fromEntity.entryJstTime != 0
                        || fromEntity.entryPrice != 0.0))
                || (hasEntry
                    && (fromEntity.entryTime <= fromEntity.confirmationTime
                        || fromEntity.entryJstTime
                            <= fromEntity.confirmationJstTime
                        || fromEntity.entryPrice <= 0.0))) {
            return false;
        }

        if ((fromEntity.isSpreadAvailable == 0
                    && fromEntity.spreadPips != 0.0)
                || (fromEntity.isPipSizeAvailable == 0
                    && fromEntity.pipSize != 0.0)
                || (fromEntity.isPipSizeAvailable == 1
                    && fromEntity.pipSize <= 0.0)
                || (fromEntity.isEntryAtrAvailable == 0
                    && fromEntity.entryAtr14Pips != 0.0)
                || (fromEntity.isEntryAtrAvailable == 1
                    && fromEntity.entryAtr14Pips <= 0.0)) {
            return false;
        }

        if (fromEntity.isResearchEligible == 1
                && (fromEntity.isLeftCensored == 1
                    || fromEntity.hasDataGapBefore == 1
                    || !hasEntry
                    || fromEntity.isSpreadAvailable == 0
                    || fromEntity.isPipSizeAvailable == 0
                    || fromEntity.isEntryAtrAvailable == 0)) {
            return false;
        }

        return true;
    }

    /**
     * 1期間分のOutcomeが保存可能か確認する。
     *
     * @param fromEntity 確認対象Outcome。
     * @return 保存可能な場合true。
     */
    bool isOutcomeValid(ZigZagElliotH1StudyOutcomeEntity &fromEntity) {
        if (fromEntity.entryId <= 0
                || !this.isHorizonValid(fromEntity.horizonH1Bars)
                || !this.isBoolean(fromEntity.isCalculated)
                || fromEntity.evaluatedH1Bars < 0
                || fromEntity.evaluatedH1Bars > fromEntity.horizonH1Bars
                || fromEntity.dataStatus == ""
                || (fromEntity.isCalculated == 1
                    && fromEntity.dataStatus != "READY")
                || (fromEntity.isCalculated == 0
                    && fromEntity.dataStatus == "READY")
                || fromEntity.exitPrice == EMPTY_VALUE
                || fromEntity.grossProfitPips == EMPTY_VALUE
                || fromEntity.netProfitPips == EMPTY_VALUE
                || fromEntity.grossProfitAtr == EMPTY_VALUE
                || fromEntity.netProfitAtr == EMPTY_VALUE
                || fromEntity.mfePips == EMPTY_VALUE
                || fromEntity.maePips == EMPTY_VALUE
                || fromEntity.priceModel == ""
                || fromEntity.spreadModel == ""
                || fromEntity.evaluationVersion == ""
                || fromEntity.createdAt <= 0) {
            return false;
        }

        if (fromEntity.isCalculated == 0) {
            return true;
        }

        if (fromEntity.evaluationEndObservationId <= 0
                || fromEntity.evaluationEndTime <= 0
                || !MathIsValidNumber(fromEntity.exitPrice)
                || fromEntity.exitPrice <= 0.0
                || !MathIsValidNumber(fromEntity.grossProfitPips)
                || !MathIsValidNumber(fromEntity.netProfitPips)
                || !MathIsValidNumber(fromEntity.grossProfitAtr)
                || !MathIsValidNumber(fromEntity.netProfitAtr)
                || !MathIsValidNumber(fromEntity.mfePips)
                || fromEntity.mfePips < 0.0
                || !MathIsValidNumber(fromEntity.maePips)
                || fromEntity.maePips < 0.0
                || fromEntity.maxProfitH1Bars < 0
                || fromEntity.maxProfitH1Bars > fromEntity.horizonH1Bars
                || (fromEntity.mfePips == 0.0
                    && fromEntity.maxProfitH1Bars != 0)
                || (fromEntity.mfePips > 0.0
                    && fromEntity.maxProfitH1Bars < 1)
                || fromEntity.evaluatedH1Bars != fromEntity.horizonH1Bars) {
            return false;
        }

        return true;
    }

    /**
     * 研究対象の評価期間か確認する。
     *
     * @param fromHorizonH1Bars 評価H1本数。
     * @return 6、12、24または48の場合true。
     */
    bool isHorizonValid(const int fromHorizonH1Bars) {
        return fromHorizonH1Bars == 6
            || fromHorizonH1Bars == 12
            || fromHorizonH1Bars == 24
            || fromHorizonH1Bars == 48;
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
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logReadError(__FUNCTION__, readErrorCode);

            return false;
        }

        long isEnabled = 0;
        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, isEnabled)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (isEnabled == 1) {
            return true;
        }

        this.logger.error(__FUNCTION__, "SQLite foreign keys are disabled.");

        return false;
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
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logReadError(__FUNCTION__, readErrorCode);

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromChangedCount)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
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
        datetime currentTime = TimeTradeServer();
        datetime lastQuoteTime = TimeCurrent();

        if (lastQuoteTime > currentTime) {
            currentTime = lastQuoteTime;
        }
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
     * @param fromSql SQL文字列。
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
     * SQL準備失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     */
    void logPrepareError(const string fromMethodName) {
        this.logger.error(
            fromMethodName,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );
    }

    /**
     * SQLパラメーター設定失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromErrorCode エラー番号。
     */
    void logBindError(
        const string fromMethodName,
        const int fromErrorCode
    ) {
        this.logger.error(
            fromMethodName,
            StringFormat("DatabaseBind failed. error=%d", fromErrorCode)
        );
    }

    /**
     * SQL読取失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromErrorCode エラー番号。
     */
    void logReadError(
        const string fromMethodName,
        const int fromErrorCode
    ) {
        this.logger.error(
            fromMethodName,
            StringFormat("DatabaseRead failed. error=%d", fromErrorCode)
        );
    }

    /**
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "Database handle is invalid.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_DAO_MQH
