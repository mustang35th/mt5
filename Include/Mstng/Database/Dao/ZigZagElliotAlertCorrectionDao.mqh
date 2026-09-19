#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_CORRECTION_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_CORRECTION_DAO_MQH

#include <Mstng\Database\Entity\ZigZagElliotAlertCorrectionEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * アラートの補正比較情報を親と1対1で保存するDAO。
 *
 * トランザクションと構造検証はアラート保存サービスが管理する。
 */
class ZigZagElliotAlertCorrectionDao {
public:
    /**
     * 保存先ハンドルを指定する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     */
    ZigZagElliotAlertCorrectionDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 補正メタ情報テーブルを追加する。既存アラートは変更しない。
     *
     * @return 作成または存在確認に成功した場合true。
     */
    bool createTable() {
        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_alert_corrections (";
        sql += "alert_id INTEGER PRIMARY KEY CHECK(alert_id > 0),";
        sql += "correction_status TEXT NOT NULL CHECK(correction_status IN ('NONE', 'APPLIED')),";
        sql += "correction_time_frame INTEGER NOT NULL CHECK(correction_time_frame IN (0, 16385, 16388)),";
        sql += "original_direction TEXT NOT NULL CHECK(original_direction IN ('', 'BUY', 'SELL')),";
        sql += "corrected_direction TEXT NOT NULL CHECK(corrected_direction IN ('', 'BUY', 'SELL')),";
        sql += "selected_analysis TEXT NOT NULL CHECK(selected_analysis IN ('ORIGINAL', 'CORRECTED')),";
        sql += "selected_alert_text TEXT NOT NULL,";
        sql += "selected_current_elliot_label TEXT NOT NULL,";
        sql += "selected_wave_summary_text TEXT NOT NULL,";
        sql += "reference_price REAL NOT NULL,";
        sql += "is_selected_stop_loss_available INTEGER NOT NULL CHECK(is_selected_stop_loss_available IN (0, 1)),";
        sql += "selected_stop_loss REAL NOT NULL,";
        sql += "selected_risk_pips REAL NOT NULL,";
        sql += "original_lc0 REAL NOT NULL,";
        sql += "original_lc5 REAL NOT NULL,";
        sql += "original_lc10 REAL NOT NULL,";
        sql += "original_lc15 REAL NOT NULL,";
        sql += "original_loss_cut_diff_pips REAL NOT NULL,";
        sql += "original_loss_cut_diff_jpy REAL NOT NULL,";
        sql += "corrected_lc0 REAL NOT NULL,";
        sql += "corrected_lc5 REAL NOT NULL,";
        sql += "corrected_lc10 REAL NOT NULL,";
        sql += "corrected_lc15 REAL NOT NULL,";
        sql += "corrected_loss_cut_diff_pips REAL NOT NULL,";
        sql += "corrected_loss_cut_diff_jpy REAL NOT NULL,";
        sql += "corrected_reference_point_time INTEGER NOT NULL CHECK(corrected_reference_point_time >= 0),";
        sql += "original_analysis_text TEXT NOT NULL,";
        sql += "corrected_analysis_text TEXT NOT NULL,";
        sql += "corrected_elliot_csv_text TEXT NOT NULL,";
        sql += "comparison_hash TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(alert_id) REFERENCES zigzag_elliot_alerts(id) ON DELETE CASCADE,";
        sql += "CHECK((correction_status = 'NONE' AND correction_time_frame = 0 ";
        sql += "AND original_direction = '' AND corrected_direction = '' ";
        sql += "AND selected_analysis = 'ORIGINAL' AND selected_stop_loss = original_lc5 ";
        sql += "AND corrected_lc0 = 0 AND corrected_lc5 = 0 AND corrected_lc10 = 0 ";
        sql += "AND corrected_lc15 = 0 AND corrected_loss_cut_diff_pips = 0 ";
        sql += "AND corrected_loss_cut_diff_jpy = 0 AND corrected_reference_point_time = 0 ";
        sql += "AND corrected_analysis_text = '' AND corrected_elliot_csv_text = '') ";
        sql += "OR (correction_status = 'APPLIED' AND correction_time_frame IN (16385, 16388) ";
        sql += "AND original_direction IN ('BUY', 'SELL') AND corrected_direction IN ('BUY', 'SELL') ";
        sql += "AND original_direction <> corrected_direction AND selected_analysis = 'CORRECTED' ";
        sql += "AND selected_stop_loss = corrected_lc5 AND corrected_reference_point_time > 0))";
        sql += ")";
        if (this.databaseHandle == INVALID_HANDLE) {
            return false;
        }
        ResetLastError();
        if (!DatabaseExecute(this.databaseHandle, sql)) {
            this.logger.error(__FUNCTION__, StringFormat(
                "create correction table failed. error=%d", GetLastError()
            ));
            return false;
        }
        return true;
    }

    /**
     * 採番済みアラートへ補正比較情報を保存する。
     *
     * 重複更新は行わず、親の重複は保存サービスで先に判定する。
     *
     * @param fromEntity 保存対象の補正比較情報。
     * @return 保存成功時true。
     */
    bool insert(ZigZagElliotAlertCorrectionEntity &fromEntity) {
        if (this.databaseHandle == INVALID_HANDLE || fromEntity.alertId <= 0) {
            return false;
        }
        string sql = "INSERT INTO zigzag_elliot_alert_corrections (";
        sql += "alert_id,";
        sql += "correction_status,";
        sql += "correction_time_frame,";
        sql += "original_direction,";
        sql += "corrected_direction,";
        sql += "selected_analysis,";
        sql += "selected_alert_text,";
        sql += "selected_current_elliot_label,";
        sql += "selected_wave_summary_text,";
        sql += "reference_price,";
        sql += "is_selected_stop_loss_available,";
        sql += "selected_stop_loss,";
        sql += "selected_risk_pips,";
        sql += "original_lc0,";
        sql += "original_lc5,";
        sql += "original_lc10,";
        sql += "original_lc15,";
        sql += "original_loss_cut_diff_pips,";
        sql += "original_loss_cut_diff_jpy,";
        sql += "corrected_lc0,";
        sql += "corrected_lc5,";
        sql += "corrected_lc10,";
        sql += "corrected_lc15,";
        sql += "corrected_loss_cut_diff_pips,";
        sql += "corrected_loss_cut_diff_jpy,";
        sql += "corrected_reference_point_time,";
        sql += "original_analysis_text,";
        sql += "corrected_analysis_text,";
        sql += "corrected_elliot_csv_text,";
        sql += "comparison_hash,";
        sql += "created_at,";
        sql += "created_at_text) VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ";
        sql += "?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ";
        sql += "?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ";
        sql += "?31, ?32)";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);
        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat(
                "DatabasePrepare failed. error=%d", GetLastError()
            ));
            return false;
        }
        bool isBound = this.bindEntity(requestHandle, fromEntity);
        if (!isBound) {
            int errorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(__FUNCTION__, StringFormat(
                "DatabaseBind failed. error=%d", errorCode
            ));
            return false;
        }
        ResetLastError();
        bool isRead = DatabaseRead(requestHandle);
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        if (!isRead && errorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(__FUNCTION__, StringFormat(
                "insert correction failed. error=%d", errorCode
            ));
            return false;
        }
        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;
    /** ロガー。 */
    Logger logger;

    /**
     * 補正比較情報をINSERTパラメーターへ設定する。
     *
     * @param fromRequestHandle 準備済みSQLハンドル。
     * @param fromEntity 保存対象。
     * @return 全項目設定に成功した場合true。
     */
    bool bindEntity(
        const int fromRequestHandle,
        ZigZagElliotAlertCorrectionEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = true;
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.alertId);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctionStatus);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctionTimeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalDirection);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedDirection);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedAnalysis);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedAlertText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedCurrentElliotLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedWaveSummaryText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.referencePrice);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isSelectedStopLossAvailable);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedStopLoss);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.selectedRiskPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLc0);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLc5);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLc10);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLc15);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLossCutDiffPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalLossCutDiffJpy);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLc0);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLc5);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLc10);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLc15);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLossCutDiffPips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedLossCutDiffJpy);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, (long)fromEntity.correctedReferencePointTime);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.originalAnalysisText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedAnalysisText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.correctedElliotCsvText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.comparisonHash);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, (long)fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAtText);
        }
        return isBound && index == 32;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_CORRECTION_DAO_MQH
