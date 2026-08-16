//+------------------------------------------------------------------+
//|                                         ZigZagElliotAlertDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_DAO_MQH

#include <Mstng\Database\Dao\ZigZagElliotAlertH1DirectionAlignmentMigration.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertW1ConfirmationMigration.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliotアラート本体をSQLiteへ保存するDAO。
 */
class ZigZagElliotAlertDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    ZigZagElliotAlertDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * アラートテーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_alerts (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "event_uid TEXT NOT NULL,";
        sql += "market_signal_key TEXT NOT NULL,";
        sql += "snapshot_hash TEXT NOT NULL,";
        sql += "server_time INTEGER NOT NULL,";
        sql += "server_time_text TEXT NOT NULL,";
        sql += "jst_time INTEGER NOT NULL,";
        sql += "jst_time_text TEXT NOT NULL,";
        sql += "current_bar_time INTEGER NOT NULL,";
        sql += "current_bar_time_text TEXT NOT NULL,";
        sql += "signal_reference_point_time INTEGER NOT NULL,";
        sql += "signal_reference_point_time_text TEXT NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "time_frame_text TEXT NOT NULL,";
        sql += "magic_number TEXT NOT NULL,";
        sql += "strategy TEXT NOT NULL,";
        sql += "side TEXT NOT NULL CHECK(side IN ('BUY', 'SELL')),";
        sql += "is_judge INTEGER NOT NULL CHECK(is_judge IN (0, 1)),";
        sql += "signal_count INTEGER NOT NULL,";
        sql += "entry_count INTEGER NOT NULL,";
        sql += "is_entry_count_match INTEGER NOT NULL ";
        sql += "CHECK(is_entry_count_match IN (0, 1)),";
        sql += "is_entry_evaluated INTEGER NOT NULL ";
        sql += "CHECK(is_entry_evaluated IN (0, 1)),";
        sql += "is_alert INTEGER NOT NULL CHECK(is_alert IN (0, 1)),";
        sql += "is_entry INTEGER NOT NULL CHECK(is_entry IN (0, 1)),";
        sql += "entry_result TEXT NOT NULL,";
        sql += "is_send_mail INTEGER NOT NULL CHECK(is_send_mail IN (0, 1)),";
        sql += "current_elliot_label TEXT NOT NULL,";
        sql += "is_entry_wave INTEGER NOT NULL CHECK(is_entry_wave IN (0, 1)),";
        sql += "close_ema200_diff_pips REAL NOT NULL,";
        sql += "max_close_ema200_diff_pips REAL NOT NULL,";
        sql += "is_ema200_distance_within INTEGER NOT NULL ";
        sql += "CHECK(is_ema200_distance_within IN (0, 1)),";
        sql += "w1_confirmation_mode TEXT NOT NULL DEFAULT 'OFF' ";
        sql += "CHECK(w1_confirmation_mode IN ('OFF', 'OBSERVE_ONLY',";
        sql += " 'DIRECTION_OR_EMA200', 'DIRECTION_AND_EMA200')),";
        sql += "w1_confirmation_state TEXT NOT NULL DEFAULT 'NOT_EVALUATED' ";
        sql += "CHECK(w1_confirmation_state IN ('NOT_EVALUATED',";
        sql += " 'NOT_APPLICABLE', 'OFF', 'UNAVAILABLE', 'INVALID',";
        sql += " 'STRONG', 'DIRECTION_ONLY', 'EMA_CONFLICT', 'EMA_ONLY',";
        sql += " 'REJECT_NONE', 'REJECT')),";
        sql += "is_w1_confirmation_available INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_w1_confirmation_available IN (0, 1)),";
        sql += "is_w1_confirmation_valid INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_w1_confirmation_valid IN (0, 1)),";
        sql += "is_w1_direction_matched INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_w1_direction_matched IN (0, 1)),";
        sql += "w1_ema200_direction TEXT NOT NULL DEFAULT 'NONE' ";
        sql += "CHECK(w1_ema200_direction IN ('BUY', 'SELL', 'NONE')),";
        sql += "is_w1_ema200_matched INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_w1_ema200_matched IN (0, 1)),";
        sql += "is_w1_confirmation_passed INTEGER NOT NULL DEFAULT 1 ";
        sql += "CHECK(is_w1_confirmation_passed IN (0, 1)),";
        sql += "h1_direction_alignment_mode TEXT NOT NULL ";
        sql += "DEFAULT 'D1_TO_H1' CHECK(h1_direction_alignment_mode IN (";
        sql += "'D1_TO_H1', 'MN1_TO_H1_OBSERVE',";
        sql += " 'MN1_TO_H1_REQUIRED', 'INVALID')),";
        sql += "h1_direction_alignment_state TEXT NOT NULL ";
        sql += "DEFAULT 'NOT_EVALUATED' CHECK(h1_direction_alignment_state IN (";
        sql += "'NOT_EVALUATED', 'NOT_APPLICABLE', 'D1_TO_H1',";
        sql += " 'FULL_BUY', 'FULL_SELL', 'MN1_MISMATCH', 'W1_MISMATCH',";
        sql += " 'MN1_W1_MISMATCH', 'UNAVAILABLE', 'INVALID')),";
        sql += "is_h1_direction_alignment_available INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_h1_direction_alignment_available IN (0, 1)),";
        sql += "is_h1_direction_alignment_valid INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_h1_direction_alignment_valid IN (0, 1)),";
        sql += "h1_direction_alignment_direction TEXT NOT NULL DEFAULT 'NONE' ";
        sql += "CHECK(h1_direction_alignment_direction IN (";
        sql += "'BUY', 'SELL', 'NONE')),";
        sql += "is_h1_mn1_direction_matched INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_h1_mn1_direction_matched IN (0, 1)),";
        sql += "is_h1_w1_direction_matched INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_h1_w1_direction_matched IN (0, 1)),";
        sql += "is_h1_direction_alignment_passed INTEGER NOT NULL DEFAULT 0 ";
        sql += "CHECK(is_h1_direction_alignment_passed IN (0, 1)),";
        sql += "spread_pips REAL NOT NULL,";
        sql += "is_currency_strength_enabled INTEGER NOT NULL ";
        sql += "CHECK(is_currency_strength_enabled IN (0, 1)),";
        sql += "currency_strength_status INTEGER NOT NULL,";
        sql += "is_currency_strength_available INTEGER NOT NULL ";
        sql += "CHECK(is_currency_strength_available IN (0, 1)),";
        sql += "currency_strength_calculation_version TEXT NOT NULL,";
        sql += "currency_strength_run_id INTEGER NOT NULL,";
        sql += "currency_strength_source_mode TEXT NOT NULL,";
        sql += "currency_strength_target_m5_bar_time INTEGER NOT NULL,";
        sql += "currency_strength_m5_bar_time INTEGER NOT NULL,";
        sql += "base_currency TEXT NOT NULL,";
        sql += "base_long_medium_rank INTEGER NOT NULL,";
        sql += "base_medium_short_rank INTEGER NOT NULL,";
        sql += "quote_currency TEXT NOT NULL,";
        sql += "quote_long_medium_rank INTEGER NOT NULL,";
        sql += "quote_medium_short_rank INTEGER NOT NULL,";
        sql += "long_medium_rank_difference INTEGER NOT NULL,";
        sql += "medium_short_rank_difference INTEGER NOT NULL,";
        sql += "reference_price REAL NOT NULL,";
        sql += "is_stop_loss_available INTEGER NOT NULL ";
        sql += "CHECK(is_stop_loss_available IN (0, 1)),";
        sql += "stop_loss REAL NOT NULL,";
        sql += "risk_pips REAL NOT NULL,";
        sql += "h1_structure_rank TEXT NOT NULL,";
        sql += "is_h1_structure_valid INTEGER NOT NULL ";
        sql += "CHECK(is_h1_structure_valid IN (0, 1)),";
        sql += "is_h1_structure_late INTEGER NOT NULL ";
        sql += "CHECK(is_h1_structure_late IN (0, 1)),";
        sql += "is_h1_direction_exception INTEGER NOT NULL ";
        sql += "CHECK(is_h1_direction_exception IN (0, 1)),";
        sql += "alert_title TEXT NOT NULL,";
        sql += "alert_text TEXT NOT NULL,";
        sql += "wave_summary_text TEXT NOT NULL,";
        sql += "elliot_csv_text TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES zigzag_elliot_alert_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, event_uid),";
        sql += "UNIQUE(run_id, symbol_name, time_frame, magic_number, strategy,";
        sql += " current_bar_time, signal_reference_point_time, side)";
        sql += ")";

        if (!this.executeSql(sql, "zigzag_elliot_alerts table")) {
            return false;
        }

        if (!ZigZagElliotAlertH1DirectionAlignmentMigration::execute(
                this.databaseHandle
            )
                || !ZigZagElliotAlertW1ConfirmationMigration::execute(
                this.databaseHandle
            )) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alerts_market_signal_key ";
        sql += "ON zigzag_elliot_alerts(market_signal_key)";

        if (!this.executeSql(sql, "zigzag elliot alert market key index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alerts_symbol_bar ";
        sql += "ON zigzag_elliot_alerts(symbol_name, time_frame,";
        sql += " current_bar_time)";

        if (!this.executeSql(sql, "zigzag elliot alert symbol bar index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alerts_strategy_side_time ";
        sql += "ON zigzag_elliot_alerts(strategy, side, server_time)";

        if (!this.executeSql(sql, "zigzag elliot alert strategy index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alerts_entry_result_time ";
        sql += "ON zigzag_elliot_alerts(entry_result, server_time)";

        if (!this.executeSql(sql, "zigzag elliot alert entry result index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "zigzag_elliot_alerts table and indexes are ready."
        );

        return true;
    }

    /**
     * アラート本体を保存する。
     *
     * 保存成功時はアラートIDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insert(ZigZagElliotAlertEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromEntity.id = 0;
        string sql = this.buildInsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        if (!this.bindEntity(requestHandle, fromEntity)) {
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
            "insert alert"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        return this.getLastInsertId(fromEntity.id);
    }

    /**
     * アラート自然キーに一致するIDと保存済みハッシュを取得する。
     *
     * 該当レコードが存在しない場合はIDとハッシュを初期値へ設定してtrueを返す。
     *
     * @param fromEntity 検索自然キーを保持するエンティティ。
     * @param fromAlertId 取得したアラートIDの格納先。
     * @param fromSnapshotHash 取得したスナップショットハッシュの格納先。
     * @return 検索処理に成功した場合はtrue。
     */
    bool findByNaturalKey(
        ZigZagElliotAlertEntity &fromEntity,
        long &fromAlertId,
        string &fromSnapshotHash
    ) {
        fromAlertId = 0;
        fromSnapshotHash = "";

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "SELECT id, snapshot_hash ";
        sql += "FROM zigzag_elliot_alerts WHERE run_id = ?1 ";
        sql += "AND symbol_name = ?2 AND time_frame = ?3 ";
        sql += "AND magic_number = ?4 AND strategy = ?5 ";
        sql += "AND current_bar_time = ?6 ";
        sql += "AND signal_reference_point_time = ?7 AND side = ?8 ";
        sql += "ORDER BY id DESC LIMIT 1";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 3, fromEntity.magicNumber);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 4, fromEntity.strategy);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 5, fromEntity.currentBarTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                6,
                fromEntity.signalReferencePointTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 7, fromEntity.side);
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

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromAlertId)
                || !DatabaseColumnText(requestHandle, 1, fromSnapshotHash)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumn read failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * アラートINSERT文を生成する。
     *
     * @return パラメーター化したINSERT文。
     */
    string buildInsertSql() {
        string sql = "INSERT INTO zigzag_elliot_alerts (";
        sql += "run_id, event_uid, market_signal_key, snapshot_hash,";
        sql += " server_time, server_time_text, jst_time, jst_time_text,";
        sql += " current_bar_time, current_bar_time_text,";
        sql += " signal_reference_point_time, signal_reference_point_time_text,";
        sql += " symbol_name, time_frame, time_frame_text, magic_number,";
        sql += " strategy, side, is_judge, signal_count, entry_count,";
        sql += " is_entry_count_match, is_entry_evaluated, is_alert, is_entry,";
        sql += " entry_result, is_send_mail, current_elliot_label, is_entry_wave,";
        sql += " close_ema200_diff_pips, max_close_ema200_diff_pips,";
        sql += " is_ema200_distance_within, w1_confirmation_mode,";
        sql += " w1_confirmation_state, is_w1_confirmation_available,";
        sql += " is_w1_confirmation_valid, is_w1_direction_matched,";
        sql += " w1_ema200_direction, is_w1_ema200_matched,";
        sql += " is_w1_confirmation_passed, h1_direction_alignment_mode,";
        sql += " h1_direction_alignment_state,";
        sql += " is_h1_direction_alignment_available,";
        sql += " is_h1_direction_alignment_valid,";
        sql += " h1_direction_alignment_direction,";
        sql += " is_h1_mn1_direction_matched,";
        sql += " is_h1_w1_direction_matched,";
        sql += " is_h1_direction_alignment_passed, spread_pips,";
        sql += " is_currency_strength_enabled, currency_strength_status,";
        sql += " is_currency_strength_available,";
        sql += " currency_strength_calculation_version, currency_strength_run_id,";
        sql += " currency_strength_source_mode,";
        sql += " currency_strength_target_m5_bar_time,";
        sql += " currency_strength_m5_bar_time, base_currency,";
        sql += " base_long_medium_rank, base_medium_short_rank, quote_currency,";
        sql += " quote_long_medium_rank, quote_medium_short_rank,";
        sql += " long_medium_rank_difference, medium_short_rank_difference,";
        sql += " reference_price, is_stop_loss_available, stop_loss, risk_pips,";
        sql += " h1_structure_rank, is_h1_structure_valid, is_h1_structure_late,";
        sql += " is_h1_direction_exception, alert_title, alert_text,";
        sql += " wave_summary_text, elliot_csv_text, created_at, created_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,";
        sql += " ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23,";
        sql += " ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34,";
        sql += " ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45,";
        sql += " ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56,";
        sql += " ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67,";
        sql += " ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78,";
        sql += " ?79";
        sql += ")";

        return sql;
    }

    /**
     * アラートINSERTパラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象エンティティ。
     * @return 全パラメーターを設定できた場合はtrue。
     */
    bool bindEntity(
        const int fromRequestHandle,
        ZigZagElliotAlertEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.eventUid);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.marketSignalKey);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.snapshotHash);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.serverTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.serverTimeText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.jstTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.jstTimeText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentBarTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentBarTimeText);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalReferencePointTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.signalReferencePointTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.timeFrameText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.magicNumber);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.strategy);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.side);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isJudge);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.signalCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEntryCountMatch);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEntryEvaluated);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isAlert);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEntry);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.entryResult);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isSendMail);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentElliotLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEntryWave);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.closeEma200DiffPips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.maxCloseEma200DiffPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isEma200DistanceWithin
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.w1ConfirmationMode
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.w1ConfirmationState
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isW1ConfirmationAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isW1ConfirmationValid
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isW1DirectionMatched
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.w1Ema200Direction
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isW1Ema200Matched
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isW1ConfirmationPassed
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.h1DirectionAlignmentMode
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.h1DirectionAlignmentState
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1DirectionAlignmentAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1DirectionAlignmentValid
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.h1DirectionAlignmentDirection
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1Mn1DirectionMatched
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1W1DirectionMatched
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1DirectionAlignmentPassed
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadPips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isCurrencyStrengthEnabled
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthStatus
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isCurrencyStrengthAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthCalculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthRunId
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthSourceMode
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthTargetM5BarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.currencyStrengthM5BarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.baseCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.baseLongMediumRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.baseMediumShortRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.quoteCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.quoteLongMediumRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.quoteMediumShortRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.longMediumRankDifference
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.mediumShortRankDifference
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.referencePrice);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isStopLossAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.stopLoss);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.riskPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.h1StructureRank);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1StructureValid
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1StructureLate
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isH1DirectionException
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.alertTitle);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.alertText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.waveSummaryText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.elliotCsvText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAtText);
        }

        return isBound && index == 79;
    }

    /**
     * 直前に追加したレコードIDを取得する。
     *
     * @param fromInsertId 取得したIDの格納先。
     * @return IDを取得できた場合はtrue。
     */
    bool getLastInsertId(long &fromInsertId) {
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "SELECT last_insert_rowid()"
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

        if (!DatabaseColumnLong(requestHandle, 0, fromInsertId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (fromInsertId <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("Invalid insert id. id=%I64d", fromInsertId)
            );

            return false;
        }

        return true;
    }

    /**
     * 結果行を返さない準備済みリクエストを実行する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合はtrue。
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
     * @return 実行に成功した場合はtrue。
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
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合はtrue。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_DAO_MQH
