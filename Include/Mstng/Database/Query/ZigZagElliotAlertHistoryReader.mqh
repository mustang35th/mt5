#ifndef MSTNG_DATABASE_QUERY_ZIGZAG_ELLIOT_ALERT_HISTORY_READER_MQH
#define MSTNG_DATABASE_QUERY_ZIGZAG_ELLIOT_ALERT_HISTORY_READER_MQH

#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * M5の保存済み分析と、M5・H1のアラートラベルを読み取り専用で取得する。
 * 元分析と補正分析は同じ読取トランザクションで検証する。
 */
class ZigZagElliotAlertHistoryReader {
public:
    /**
     * 未接続状態を初期化する。
     */
    ZigZagElliotAlertHistoryReader() {
        this.database = NULL;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 読取接続を解放する。
     */
    ~ZigZagElliotAlertHistoryReader() {
        this.close();
    }

    /**
     * 既存ファイルを読み取り専用で開く。ファイル作成やDDLは行わない。
     */
    bool open(const string fromFileName, const bool fromUseCommonFolder, string &fromError) {
        this.close();
        fromError = "";
        if (fromFileName == "") {
            fromError = "Alert DBファイル名が指定されていません。";
            return false;
        }
        this.database = new SqliteDatabase(fromFileName, fromUseCommonFolder);
        if (this.database == NULL || !this.database.openReadOnly()) {
            fromError = "Alert DBを読み取り専用で開けません。";
            this.close();
            return false;
        }
        return true;
    }

    /**
     * このReaderが所有する接続だけを閉じる。
     */
    void close() {
        if (this.database != NULL) {
            delete this.database;
            this.database = NULL;
        }
    }

    /**
     * 同じ条件に一致する一つのRunのアラートIDをバー時刻順で取得する。
     * 開始は含み終了は含まない。日時0は無制限、Run0は最新の一致Run。
     */
    bool selectAlerts(
        const string fromSymbol, const long fromRunId,
        const datetime fromStartTime, const datetime fromEndTime,
        const bool fromEntryOnly, long &fromResolvedRunId,
        long &fromAlertIds[], string &fromError
    ) {
        ArrayFree(fromAlertIds);
        fromResolvedRunId = fromRunId;
        fromError = "";
        if (!this.isOpen(fromError)) {
            return false;
        }
        if (fromSymbol == "" || fromRunId < 0 || fromStartTime < 0 || fromEndTime < 0
                || (fromEndTime > 0 && fromEndTime <= fromStartTime)) {
            fromError = "通貨・Run・日時範囲の指定が不正です。";
            return false;
        }
        string sql = "WITH candidates AS (SELECT id,run_id,current_bar_time ";
        sql += "FROM zigzag_elliot_alerts WHERE symbol_name=?1 AND time_frame=5 AND is_alert=1 ";
        sql += "AND (?2=0 OR run_id=?2) AND (?3=0 OR current_bar_time>=?3) ";
        sql += "AND (?4=0 OR current_bar_time<?4) AND (?5=0 OR is_entry=1)) ";
        sql += "SELECT id,run_id FROM candidates WHERE run_id=(SELECT MAX(run_id) FROM candidates) ";
        sql += "ORDER BY current_bar_time,id";
        int request = this.prepare(sql, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        if (!DatabaseBind(request, 0, fromSymbol) || !DatabaseBind(request, 1, fromRunId)
                || !DatabaseBind(request, 2, (long)fromStartTime)
                || !DatabaseBind(request, 3, (long)fromEndTime)
                || !DatabaseBind(request, 4, (int)fromEntryOnly)) {
            this.databaseError("bind alert filters", fromError);
            DatabaseFinalize(request);
            return false;
        }
        bool success = true;
        bool hasRow = false;
        while (true) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }
            long alertId = 0;
            long runId = 0;
            if (!this.readLongValue(request, 0, alertId) || !this.readLongValue(request, 1, runId)
                    || alertId <= 0 || runId <= 0) {
                fromError = "アラート一覧の識別情報が不正です。";
                success = false;
                break;
            }
            int count = ArraySize(fromAlertIds);
            if (ArrayResize(fromAlertIds, count + 1) != count + 1) {
                fromError = "アラート一覧のメモリを確保できません。";
                success = false;
                break;
            }
            fromAlertIds[count] = alertId;
            fromResolvedRunId = runId;
        }
        DatabaseFinalize(request);
        if (!success) {
            ArrayFree(fromAlertIds);
            fromResolvedRunId = 0;
        }
        return success;
    }

    /**
     * 同じ検索条件で全ラベルを一括取得する。波動ポイントや詳細分析は読み取らない。
     * 表示値が不足する行もIDを残し、前後移動による詳細確認を可能にする。
     * 任意の実行モード・サーバー・既知時刻はRun選択前に適用する。空文字と0は制限なし。
     * 全RunではRun ID指定を使わず、解決Run IDは0。H1は保存元分析を採用する。
     */
    bool selectMarkers(
        const string fromSymbol, const long fromRunId,
        const datetime fromStartTime, const datetime fromEndTime,
        const bool fromEntryOnly, long &fromResolvedRunId,
        long &fromAlertIds[], ZigZagElliotAlertHistoryMarker &fromMarkers[], string &fromError,
        const string fromSourceMode = "", const string fromSourceServer = "",
        const datetime fromKnownTime = 0, const ENUM_TIMEFRAMES fromTimeFrame = PERIOD_M5,
        const bool fromAllRuns = false
    ) {
        ArrayFree(fromAlertIds);
        ArrayFree(fromMarkers);
        long requestedRunId = fromRunId;
        if (fromAllRuns) {
            requestedRunId = 0;
        }
        fromResolvedRunId = requestedRunId;
        fromError = "";
        if (!this.isOpen(fromError)) {
            return false;
        }
        if (fromSymbol == "" || fromRunId < 0 || fromStartTime < 0 || fromEndTime < 0 || fromKnownTime < 0
                || (fromEndTime > 0 && fromEndTime <= fromStartTime)
                || (fromTimeFrame != PERIOD_M5 && fromTimeFrame != PERIOD_H1)) {
            fromError = "通貨・Run・日時範囲の指定が不正です。";
            return false;
        }
        string correctionColumns = "";
        if (!this.tableColumns("zigzag_elliot_alert_corrections", correctionColumns, fromError)) {
            return false;
        }
        string correctionProjection = "NULL,'',0,'','',''";
        string correctionJoin = "";
        if (fromTimeFrame == PERIOD_H1) {
            correctionProjection = "'NONE',a.alert_text,0,'','','ORIGINAL'";
        } else if (correctionColumns != ",") {
            string reason = "";
            if (this.projection("zigzag_elliot_alert_corrections",
                    "correction_status,selected_alert_text,correction_time_frame,original_direction,corrected_direction,selected_analysis",
                    "c.", false, correctionProjection, reason, fromError)) {
                correctionJoin = " LEFT JOIN zigzag_elliot_alert_corrections c ON c.alert_id=a.id";
            } else {
                if (fromError != "") {
                    return false;
                }
                correctionProjection = "'INCOMPLETE','',0,'','',''";
            }
        }
        string originalFrames = "";
        string correctedFrames = "";
        if (!this.markerFrameSource("zigzag_elliot_alert_timeframes", false, originalFrames, fromError)
                || (fromTimeFrame == PERIOD_M5
                    && !this.markerFrameSource("zigzag_elliot_alert_corrected_timeframes", true, correctedFrames, fromError))) {
            return false;
        }
        string frameFilter = " WHERE alert_id IN (SELECT id FROM selected)";
        if (originalFrames != "") {
            originalFrames += frameFilter;
        }
        if (correctedFrames != "") {
            correctedFrames += frameFilter;
        }
        string frameSource = originalFrames;
        if (correctedFrames != "") {
            if (frameSource != "") {
                frameSource += " UNION ALL ";
            }
            frameSource += correctedFrames;
        }
        if (frameSource == "") {
            frameSource = "SELECT NULL AS alert_id,0 AS corrected,NULL AS time_frame,NULL AS is_buy,"
                + "NULL AS is_ema200_buy,NULL AS is_ema200_sell,NULL AS latest_elliot_label,"
                + "NULL AS latest_sub_elliot_index,NULL AS latest_sub_elliot_label,NULL AS is_wave_confirmed WHERE 0";
        }
        string selectedFrameKind = "0";
        if (correctionJoin != "") {
            selectedFrameKind = "CASE WHEN c.correction_status='APPLIED' AND c.selected_analysis='CORRECTED' THEN 1 ELSE 0 END";
        }
        string sql = "WITH candidates AS (SELECT id,run_id,current_bar_time,server_time,jst_time,side,is_entry,entry_result,alert_text FROM zigzag_elliot_alerts ";
        sql += "WHERE symbol_name=?1 AND time_frame=?9 AND is_alert=1 ";
        sql += "AND (?2=0 OR run_id=?2) AND (?3=0 OR current_bar_time>=?3) ";
        sql += "AND (?4=0 OR current_bar_time<?4) AND (?5=0 OR is_entry=1) ";
        sql += "AND (?6='' OR EXISTS(SELECT 1 FROM zigzag_elliot_alert_runs r WHERE r.id=run_id AND r.source_mode=?6)) ";
        sql += "AND (?7='' OR EXISTS(SELECT 1 FROM zigzag_elliot_alert_runs r WHERE r.id=run_id AND r.source_server=?7)) ";
        sql += "AND (?8=0 OR (current_bar_time<=?8 AND server_time<=?8))) ";
        sql += ",selected AS (SELECT * FROM candidates WHERE ?10=1 OR run_id=(SELECT MAX(run_id) FROM candidates)) ";
        sql += "SELECT a.id,a.run_id,a.current_bar_time,a.server_time,a.jst_time,a.side,a.is_entry,a.entry_result,a.alert_text,";
        sql += "(SELECT CASE WHEN COUNT(*)=1 THEN current_open ELSE NULL END ";
        sql += "FROM zigzag_elliot_alert_timeframes WHERE alert_id=a.id AND time_frame=?9),";
        sql += correctionProjection + ",tf.time_frame,tf.is_buy,tf.is_ema200_buy,tf.is_ema200_sell,"
            + "tf.latest_elliot_label,tf.latest_sub_elliot_index,tf.latest_sub_elliot_label,tf.is_wave_confirmed";
        sql += " FROM selected a" + correctionJoin;
        sql += " LEFT JOIN (" + frameSource + ") tf ON tf.alert_id=a.id AND tf.corrected=" + selectedFrameKind;
        sql += " ORDER BY a.current_bar_time,a.id,tf.time_frame";
        int request = this.prepare(sql, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        if (!DatabaseBind(request, 0, fromSymbol) || !DatabaseBind(request, 1, requestedRunId)
                || !DatabaseBind(request, 2, (long)fromStartTime)
                || !DatabaseBind(request, 3, (long)fromEndTime)
                || !DatabaseBind(request, 4, (int)fromEntryOnly)
                || !DatabaseBind(request, 5, fromSourceMode)
                || !DatabaseBind(request, 6, fromSourceServer)
                || !DatabaseBind(request, 7, (long)fromKnownTime)
                || !DatabaseBind(request, 8, (int)fromTimeFrame)
                || !DatabaseBind(request, 9, (int)fromAllRuns)) {
            this.databaseError("bind alert filters", fromError);
            DatabaseFinalize(request);
            return false;
        }
        bool success = true;
        bool hasRow = false;
        while (true) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }
            long alertId = 0;
            long runId = 0;
            if (!this.readLongValue(request, 0, alertId) || !this.readLongValue(request, 1, runId)
                    || alertId <= 0 || runId <= 0) {
                fromError = "アラート一覧の識別情報が不正です。";
                success = false;
                break;
            }
            int count = ArraySize(fromAlertIds);
            if (count > 0 && fromAlertIds[count - 1] == alertId) {
                this.readMarkerWave(request, fromMarkers[count - 1]);
                continue;
            }
            if (ArrayResize(fromAlertIds, count + 1, 256) != count + 1
                    || ArrayResize(fromMarkers, count + 1, 256) != count + 1) {
                fromError = "アラート一覧のメモリを確保できません。";
                success = false;
                break;
            }
            fromAlertIds[count] = alertId;
            this.readMarker(request, alertId, fromMarkers[count], fromTimeFrame);
            this.readMarkerWave(request, fromMarkers[count]);
            if (!fromAllRuns) {
                fromResolvedRunId = runId;
            }
        }
        DatabaseFinalize(request);
        if (!success) {
            ArrayFree(fromAlertIds);
            ArrayFree(fromMarkers);
            fromResolvedRunId = 0;
        }
        return success;
    }

    /**
     * 一つのアラートの元分析と補正分析を同じ保存状態から読み取る。
     */
    bool loadSnapshot(const long fromAlertId, ZigZagElliotAlertHistorySnapshot &fromSnapshot, string &fromError) {
        fromSnapshot.clear();
        fromError = "";
        if (!this.isOpen(fromError)) {
            return false;
        }
        if (fromAlertId <= 0) {
            fromError = "アラートIDが不正です。";
            return false;
        }
        ResetLastError();
        if (!DatabaseExecute(this.database.getHandle(), "BEGIN")) {
            this.databaseError("begin snapshot", fromError);
            return false;
        }
        bool success = this.loadSnapshotRows(fromAlertId, fromSnapshot, fromError);
        if (success) {
            ResetLastError();
            success = DatabaseExecute(this.database.getHandle(), "COMMIT");
            if (!success) {
                this.databaseError("end snapshot", fromError);
            }
        }
        if (!success) {
            DatabaseExecute(this.database.getHandle(), "ROLLBACK");
            fromSnapshot.clear();
        }
        return success;
    }

private:
    /** 所有する読取専用接続。 */
    SqliteDatabase *database;
    /** 内部DB診断用ロガー。 */
    Logger logger;

    /**
     * 一覧のラベル用保存値を検証する。採用文字が欠損した補正を元分析で代用しない。
     */
    void readMarker(const int fromRequest, const long fromAlertId, ZigZagElliotAlertHistoryMarker &fromMarker,
            const ENUM_TIMEFRAMES fromTimeFrame) {
        ZeroMemory(fromMarker);
        for (int i = 0; i < ArraySize(fromMarker.waves); i++) {
            fromMarker.waves[i].clear();
        }
        fromMarker.alertId = fromAlertId;
        fromMarker.timeFrame = fromTimeFrame;
        fromMarker.correctionStatus = "UNRECORDED";
        if (!this.readTimeValue(fromRequest, 2, fromMarker.barTime)
                || !this.readTimeValue(fromRequest, 3, fromMarker.serverTime)
                || !this.readTimeValue(fromRequest, 4, fromMarker.jstTime)
                || !this.readTextValue(fromRequest, 5, fromMarker.side)
                || !this.readIntValue(fromRequest, 6, fromMarker.isEntry, true)
                || !this.readTextValue(fromRequest, 7, fromMarker.entryResult)
                || !this.readTextValue(fromRequest, 8, fromMarker.text)
                || !this.readDoubleValue(fromRequest, 9, fromMarker.price)
                || fromMarker.barTime <= 0 || fromMarker.serverTime <= 0
                || fromMarker.price <= 0 || fromMarker.price == EMPTY_VALUE
                || (fromMarker.side != "BUY" && fromMarker.side != "SELL")) {
            return;
        }
        if (DatabaseColumnType(fromRequest, 10) == DATABASE_FIELD_TYPE_NULL) {
            fromMarker.correctionText = "補正情報未記録・元分析";
            if (fromMarker.text != "") {
                fromMarker.text += " [元分析]";
                fromMarker.available = true;
            }
            return;
        }
        string status = "";
        string selectedAnalysis = "";
        string selectedText = "";
        string originalDirection = "";
        string correctedDirection = "";
        int correctionTimeFrame = 0;
        if (!this.readTextValue(fromRequest, 10, status)
                || !this.readTextValue(fromRequest, 11, selectedText)
                || !this.readIntValue(fromRequest, 12, correctionTimeFrame)
                || !this.readTextValue(fromRequest, 13, originalDirection)
                || !this.readTextValue(fromRequest, 14, correctedDirection)
                || !this.readTextValue(fromRequest, 15, selectedAnalysis) || selectedText == "") {
            return;
        }
        if (status == "NONE" && selectedAnalysis == "ORIGINAL" && correctionTimeFrame == 0
                && originalDirection == "" && correctedDirection == "") {
            fromMarker.correctionText = "補正なし・元分析採用";
        } else if (status == "APPLIED" && selectedAnalysis == "CORRECTED"
                && (correctionTimeFrame == PERIOD_H1 || correctionTimeFrame == PERIOD_H4)
                && (originalDirection == "BUY" || originalDirection == "SELL")
                && originalDirection != correctedDirection && correctedDirection == fromMarker.side) {
            string frame = "H1";
            if (correctionTimeFrame == PERIOD_H4) {
                frame = "H4";
            }
            fromMarker.correctionText = frame + " " + originalDirection + "→" + correctedDirection;
        } else {
            return;
        }
        fromMarker.correctionStatus = status;
        fromMarker.text = selectedText;
        fromMarker.available = true;
    }

    /**
     * 全ラベル用の時間足概要を構成する。旧形式で欠けた列をSELLや未確定へ変換しない。
     */
    bool markerFrameSource(const string fromTable, const bool fromCorrected, string &fromSql, string &fromError) {
        fromSql = "";
        string columns = "";
        if (!this.tableColumns(fromTable, columns, fromError)) {
            return false;
        }
        if (StringFind(columns, ",alert_id,") < 0 || StringFind(columns, ",time_frame,") < 0) {
            return true;
        }
        string fields[] = {"time_frame", "is_buy", "is_ema200_buy", "is_ema200_sell", "latest_elliot_label",
            "latest_sub_elliot_index", "latest_sub_elliot_label", "is_wave_confirmed"};
        fromSql = "SELECT alert_id," + IntegerToString((int)fromCorrected) + " AS corrected";
        for (int i = 0; i < ArraySize(fields); i++) {
            fromSql += ",";
            if (StringFind(columns, "," + fields[i] + ",") >= 0) {
                fromSql += fields[i];
            } else {
                fromSql += "NULL AS " + fields[i];
            }
        }
        fromSql += " FROM " + fromTable;
        return true;
    }

    /**
     * 選択した元または補正テーブルの一行だけから概要を読む。
     */
    void readMarkerWave(const int fromRequest, ZigZagElliotAlertHistoryMarker &fromMarker) {
        if (!fromMarker.available) {
            return;
        }
        int timeFrame = 0;
        if (!this.readIntValue(fromRequest, 16, timeFrame)) {
            return;
        }
        int frames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        int index = -1;
        for (int i = 0; i < ArraySize(frames); i++) {
            if (frames[i] == timeFrame) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            return;
        }
        if (fromMarker.waves[index].recorded) {
            fromMarker.waves[index].clear();
            fromMarker.waves[index].recorded = true;
            return;
        }
        fromMarker.waves[index].recorded = true;
        int flag = 0;
        if (this.readIntValue(fromRequest, 17, flag, true)) {
            fromMarker.waves[index].direction = "S";
            if (flag == 1) {
                fromMarker.waves[index].direction = "B";
            }
        }
        int emaBuy = 0;
        int emaSell = 0;
        if (timeFrame != PERIOD_MN1 && this.readIntValue(fromRequest, 18, emaBuy, true)
                && this.readIntValue(fromRequest, 19, emaSell, true)) {
            if (emaBuy == 1 && emaSell == 0) {
                fromMarker.waves[index].emaDirection = "B";
            } else if (emaBuy == 0 && emaSell == 1) {
                fromMarker.waves[index].emaDirection = "S";
            }
        }
        this.readTextValue(fromRequest, 20, fromMarker.waves[index].wave);
        int subIndex = 0;
        if (this.readIntValue(fromRequest, 21, subIndex) && subIndex > 0) {
            this.readTextValue(fromRequest, 22, fromMarker.waves[index].subWave);
        }
        if (this.readIntValue(fromRequest, 23, flag, true)) {
            fromMarker.waves[index].state = "未";
            if (flag == 1) {
                fromMarker.waves[index].state = "確";
            }
        }
    }

    /**
     * 接続状態を確認する。
     */
    bool isOpen(string &fromError) {
        if (this.database == NULL || !this.database.isOpen()) {
            fromError = "Alert DBが開かれていません。";
            return false;
        }
        return true;
    }

    /**
     * 内部エラーはログへ記録し、画面には短い理由を返す。
     */
    void databaseError(const string fromOperation, string &fromError) {
        int errorCode = GetLastError();
        this.logger.error(__FUNCTION__, StringFormat("alert history read failed. operation=%s error=%d", fromOperation, errorCode));
        fromError = "Alert DBの読み取りに失敗しました。";
    }

    /**
     * 固定SQLを準備する。
     */
    int prepare(const string fromSql, string &fromError) {
        ResetLastError();
        int request = DatabasePrepare(this.database.getHandle(), fromSql);
        if (request == INVALID_HANDLE) {
            this.databaseError("prepare", fromError);
        }
        return request;
    }

    /**
     * 行終端と実際の読取失敗を区別する。
     */
    bool readNext(const int fromRequest, bool &fromHasRow, string &fromError) {
        ResetLastError();
        fromHasRow = DatabaseRead(fromRequest);
        if (fromHasRow) {
            return true;
        }
        int errorCode = GetLastError();
        if (errorCode == ERR_DATABASE_NO_MORE_DATA) {
            return true;
        }
        this.databaseError("read next", fromError);
        return false;
    }

    /**
     * INTEGERを型変換で補完せず読み取る。
     */
    bool readLongValue(const int fromRequest, const int fromColumn, long &fromValue) {
        return DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_INTEGER
            && DatabaseColumnLong(fromRequest, fromColumn, fromValue);
    }

    /**
     * 32bit整数と状態フラグの範囲を検証する。
     */
    bool readIntValue(const int fromRequest, const int fromColumn, int &fromValue, const bool fromFlag = false) {
        long value = 0;
        if (!this.readLongValue(fromRequest, fromColumn, value) || value < -2147483648 || value > 2147483647) {
            return false;
        }
        if (fromFlag && value != 0 && value != 1) {
            return false;
        }
        fromValue = (int)value;
        return true;
    }

    /**
     * 保存された整数日時を読み取る。
     */
    bool readTimeValue(const int fromRequest, const int fromColumn, datetime &fromValue) {
        long value = 0;
        if (!this.readLongValue(fromRequest, fromColumn, value) || value < 0) {
            return false;
        }
        fromValue = (datetime)value;
        return true;
    }

    /**
     * NULLや非有限値を価格の0へ変換しない。
     */
    bool readDoubleValue(const int fromRequest, const int fromColumn, double &fromValue) {
        ENUM_DATABASE_FIELD_TYPE fieldType = DatabaseColumnType(fromRequest, fromColumn);
        return (fieldType == DATABASE_FIELD_TYPE_INTEGER || fieldType == DATABASE_FIELD_TYPE_FLOAT)
            && DatabaseColumnDouble(fromRequest, fromColumn, fromValue) && MathIsValidNumber(fromValue);
    }

    /**
     * TEXTを型変換で補完せず読み取る。
     */
    bool readTextValue(const int fromRequest, const int fromColumn, string &fromValue) {
        return DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_TEXT
            && DatabaseColumnText(fromRequest, fromColumn, fromValue);
    }

    /**
     * 固定テーブル名の列一覧を読み取る。存在しない場合は空文字。
     */
    bool tableColumns(const string fromTable, string &fromColumns, string &fromError) {
        fromColumns = ",";
        int request = this.prepare("PRAGMA table_info(" + fromTable + ")", fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool success = true;
        bool hasRow = false;
        while (true) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }
            string columnName = "";
            if (!this.readTextValue(request, 1, columnName)) {
                fromError = "DBの列情報を確認できません。";
                success = false;
                break;
            }
            fromColumns += columnName + ",";
        }
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 必須列を確認し固定順のSELECT列を構成する。欠損理由はDBエラーと分離する。
     */
    bool projection(const string fromTable, const string fromRequired, const string fromAlias,
                    const bool fromAllowLegacyEma, string &fromProjection, string &fromReason, string &fromError) {
        fromProjection = "";
        fromReason = "";
        string columns = "";
        if (!this.tableColumns(fromTable, columns, fromError)) {
            return false;
        }
        string required[];
        int count = StringSplit(fromRequired, ',', required);
        for (int i = 0; i < count; i++) {
            if (i > 0) {
                fromProjection += ",";
            }
            if (StringFind(columns, "," + required[i] + ",") >= 0) {
                fromProjection += fromAlias + required[i];
            } else if (fromAllowLegacyEma && (required[i] == "is_ema200_buy" || required[i] == "is_ema200_sell")) {
                fromProjection += "0 AS " + required[i];
            } else {
                fromReason = "保存形式に必要な項目がありません: " + required[i];
                return false;
            }
        }
        return true;
    }

    /**
     * IDをバインドしたSELECTを準備する。
     */
    int prepareIdQuery(const string fromSql, const long fromId, string &fromError) {
        int request = this.prepare(fromSql, fromError);
        if (request != INVALID_HANDLE && !DatabaseBind(request, 0, fromId)) {
            this.databaseError("bind id", fromError);
            DatabaseFinalize(request);
            return INVALID_HANDLE;
        }
        return request;
    }

    /**
     * 親AlertとRunを一意に特定する。
     */
    bool loadParents(const long fromAlertId, ZigZagElliotAlertHistorySnapshot &fromSnapshot, string &fromError) {
        string columns = "";
        string reason = "";
        if (!this.projection("zigzag_elliot_alerts", this.getAlertColumns(), "", false, columns, reason, fromError)) {
            if (fromError == "") {
                fromError = "元アラート: " + reason;
            }
            return false;
        }
        int request = this.prepareIdQuery("SELECT " + columns + " FROM zigzag_elliot_alerts WHERE id=?", fromAlertId, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool hasRow = false;
        bool success = this.readNext(request, hasRow, fromError);
        if (success && (!hasRow || !this.readAlert(request, fromSnapshot.alert))) {
            fromError = "元アラートが存在しないか保存値が不正です。";
            success = false;
        }
        if (success && (!this.readNext(request, hasRow, fromError) || hasRow)) {
            if (fromError == "") {
                fromError = "元アラートの識別子が重複しています。";
            }
            success = false;
        }
        DatabaseFinalize(request);
        if (!success) {
            return false;
        }
        if (fromSnapshot.alert.id != fromAlertId || fromSnapshot.alert.runId <= 0
                || fromSnapshot.alert.timeFrame != PERIOD_M5 || fromSnapshot.alert.timeFrameText != "M5"
                || fromSnapshot.alert.isAlert != 1 || fromSnapshot.alert.symbolName == ""
                || (fromSnapshot.alert.side != "BUY" && fromSnapshot.alert.side != "SELL")
                || fromSnapshot.alert.currentBarTime <= 0 || fromSnapshot.alert.serverTime <= 0
                || fromSnapshot.alert.referencePrice <= 0 || fromSnapshot.alert.riskPips < 0
                || fromSnapshot.alert.isStopLossAvailable != (int)(fromSnapshot.alert.stopLoss > 0)
                || (fromSnapshot.alert.isStopLossAvailable == 0 && fromSnapshot.alert.riskPips != 0)) {
            fromError = "元アラートの時間足・方向・日時・価格が不正です。";
            return false;
        }
        if (!this.projection("zigzag_elliot_alert_runs", this.getRunColumns(), "", false, columns, reason, fromError)) {
            if (fromError == "") {
                fromError = "Run: " + reason;
            }
            return false;
        }
        request = this.prepareIdQuery("SELECT " + columns + " FROM zigzag_elliot_alert_runs WHERE id=?", fromSnapshot.alert.runId, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        success = this.readNext(request, hasRow, fromError);
        if (success && (!hasRow || !this.readRun(request, fromSnapshot.run))) {
            fromError = "保存元Runが存在しないか保存値が不正です。";
            success = false;
        }
        if (success && (!this.readNext(request, hasRow, fromError) || hasRow)) {
            if (fromError == "") {
                fromError = "保存元Runの識別子が重複しています。";
            }
            success = false;
        }
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 元と補正それぞれのテーブルだけを結合して分析行を取得する。
     */
    bool loadAnalysis(const long fromAlertId, const bool fromCorrected,
                      ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[], ZigZagElliotAlertPointEntity &fromPoints[],
                      string &fromReason, string &fromError) {
        ArrayFree(fromTimeFrames);
        ArrayFree(fromPoints);
        fromReason = "";
        string frameTable = "zigzag_elliot_alert_timeframes";
        string pointTable = "zigzag_elliot_alert_points";
        if (fromCorrected) {
            frameTable = "zigzag_elliot_alert_corrected_timeframes";
            pointTable = "zigzag_elliot_alert_corrected_points";
        }
        string frameProjection = "";
        string pointProjection = "";
        if (!this.projection(frameTable, this.getTimeFrameColumns(), "", true, frameProjection, fromReason, fromError)
                || !this.projection(pointTable, this.getPointColumns(), "p.", false, pointProjection, fromReason, fromError)) {
            return fromError == "";
        }
        int request = this.prepareIdQuery("SELECT " + frameProjection + " FROM " + frameTable
            + " WHERE alert_id=? ORDER BY time_frame_order,id", fromAlertId, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool hasRow = false;
        bool success = true;
        while (true) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }
            ZigZagElliotAlertTimeFrameEntity entity;
            if (!this.readTimeFrame(request, entity)) {
                fromReason = "時間足の保存値または型が不正です。";
                continue;
            }
            int count = ArraySize(fromTimeFrames);
            if (ArrayResize(fromTimeFrames, count + 1) != count + 1) {
                fromError = "時間足のメモリを確保できません。";
                success = false;
                break;
            }
            fromTimeFrames[count] = entity;
        }
        DatabaseFinalize(request);
        if (!success) {
            return false;
        }
        request = this.prepareIdQuery("SELECT " + pointProjection + ",tf.time_frame FROM " + frameTable
            + " tf INNER JOIN " + pointTable + " p ON p.alert_timeframe_id=tf.id WHERE tf.alert_id=?"
            + " ORDER BY tf.time_frame_order,p.point_order,p.id", fromAlertId, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        while (true) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }
            ZigZagElliotAlertPointEntity entity;
            if (!this.readPoint(request, entity)
                    || !this.readIntValue(request, DatabaseColumnsCount(request) - 1, entity.timeFrame)) {
                fromReason = "波動ポイントの保存値または型が不正です。";
                continue;
            }
            int count = ArraySize(fromPoints);
            if (ArrayResize(fromPoints, count + 1) != count + 1) {
                fromError = "波動ポイントのメモリを確保できません。";
                success = false;
                break;
            }
            fromPoints[count] = entity;
        }
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 7足・ポイントの所属・最新点・SL基準点を検証する。
     */
    bool validateAnalysis(ZigZagElliotAlertEntity &fromAlert,
                          ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[], ZigZagElliotAlertPointEntity &fromPoints[],
                          const datetime fromReferenceTime, const double fromReferenceRate,
                          const bool fromCheckReferenceRate, string &fromReason) {
        int frames[] = {49153, 32769, 16408, 16388, 16385, 15, 5};
        string labels[] = {"MN1", "W1", "D1", "H4", "H1", "M15", "M5"};
        if (ArraySize(fromTimeFrames) != 7) {
            fromReason = "MN1からM5までの7時間足が揃っていません。";
            return false;
        }
        int pointIndex = 0;
        int references = 0;
        for (int i = 0; i < 7; i++) {
            ZigZagElliotAlertTimeFrameEntity frame = fromTimeFrames[i];
            string direction = "SELL";
            if (frame.isBuy == 1) {
                direction = "BUY";
            }
            if (frame.id <= 0 || frame.alertId != fromAlert.id || frame.timeFrame != frames[i]
                    || frame.timeFrameText != labels[i] || frame.timeFrameOrder != i
                    || frame.isCurrentTimeFrame != (int)(i == 6) || frame.buySellLabel != direction
                    || (i == 6 && direction != fromAlert.side) || frame.pointCount <= 0) {
                fromReason = "時間足の識別子・方向・ポイント数が不整合です。";
                return false;
            }
            for (int j = 0; j < i; j++) {
                if (frame.id == fromTimeFrames[j].id) {
                    fromReason = "時間足の識別子が重複しています。";
                    return false;
                }
            }
            int latestCount = 0;
            for (int j = 0; j < frame.pointCount; j++) {
                if (pointIndex >= ArraySize(fromPoints)) {
                    fromReason = "波動ポイントが不足しています。";
                    return false;
                }
                ZigZagElliotAlertPointEntity point = fromPoints[pointIndex];
                if (point.id <= 0 || point.alertTimeFrameId != frame.id || point.timeFrame != frame.timeFrame
                        || point.pointOrder != j || point.barTime <= 0 || point.rate <= 0) {
                    fromReason = "波動ポイントの所属・順序・日時・価格が不整合です。";
                    return false;
                }
                for (int k = 0; k < pointIndex; k++) {
                    if (point.id == fromPoints[k].id) {
                        fromReason = "波動ポイントの識別子が重複しています。";
                        return false;
                    }
                }
                if (point.isLatest == 1) {
                    latestCount++;
                    if (j != frame.pointCount - 1 || point.elliotIndex != frame.latestElliotIndex
                            || point.elliotLabel != frame.latestElliotLabel
                            || point.subElliotIndex != frame.latestSubElliotIndex
                            || point.subElliotLabel != frame.latestSubElliotLabel) {
                        fromReason = "最新ポイントと時間足の波動情報が一致しません。";
                        return false;
                    }
                }
                if (point.isSignalReference == 1) {
                    references++;
                    if (i != 6 || point.barTime != fromReferenceTime
                            || (fromCheckReferenceRate && !this.samePrice(point.rate, fromReferenceRate))) {
                        fromReason = "損切り基準ポイントが保存値と一致しません。";
                        return false;
                    }
                }
                pointIndex++;
            }
            if (latestCount != 1) {
                fromReason = "最新ポイントを一意に特定できません。";
                return false;
            }
        }
        if (pointIndex != ArraySize(fromPoints) || references != 1) {
            fromReason = "波動ポイント件数または損切り基準点の数が不整合です。";
            return false;
        }
        return true;
    }

    /**
     * 保存価格を倍精度の誤差範囲で比較する。
     */
    bool samePrice(const double fromLeft, const double fromRight) {
        return MathAbs(fromLeft - fromRight) <= MathMax(1.0e-10, MathMax(MathAbs(fromLeft), MathAbs(fromRight)) * 1.0e-12);
    }

    /**
     * 補正メタデータを読み取る。テーブルや行がない場合は未記録。
     */
    bool loadCorrection(ZigZagElliotAlertHistorySnapshot &fromSnapshot, string &fromError) {
        string tableColumns = "";
        if (!this.tableColumns("zigzag_elliot_alert_corrections", tableColumns, fromError)) {
            return false;
        }
        if (tableColumns == ",") {
            return true;
        }
        string columns = "";
        if (!this.projection("zigzag_elliot_alert_corrections", this.getCorrectionColumns(), "", false,
                columns, fromSnapshot.correctionReason, fromError)) {
            fromSnapshot.correctionStatus = "INCOMPLETE";
            return fromError == "";
        }
        int request = this.prepareIdQuery("SELECT " + columns + " FROM zigzag_elliot_alert_corrections WHERE alert_id=?",
            fromSnapshot.alert.id, fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool hasRow = false;
        bool success = this.readNext(request, hasRow, fromError);
        if (success && hasRow) {
            if (!this.readCorrection(request, fromSnapshot.correction)) {
                fromSnapshot.correctionStatus = "INCOMPLETE";
                fromSnapshot.correctionReason = "補正情報の保存値または型が不正です。";
            } else {
                fromSnapshot.correctionStatus = fromSnapshot.correction.correctionStatus;
            }
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
            } else if (hasRow) {
                fromSnapshot.correctionStatus = "INCOMPLETE";
                fromSnapshot.correctionReason = "補正情報の識別子が重複しています。";
            }
        }
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 補正の状態・方向・SLと元Alertの対応を確認する。
     */
    bool validateCorrection(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        ZigZagElliotAlertCorrectionEntity correction = fromSnapshot.correction;
        ZigZagElliotAlertEntity alert = fromSnapshot.alert;
        if ((correction.correctionStatus != "APPLIED" && correction.correctionStatus != "NONE")
                || correction.alertId != alert.id || correction.comparisonHash == ""
                || correction.originalAnalysisText == "" || correction.selectedAlertText == ""
                || correction.selectedWaveSummaryText == "" || correction.createdAt <= 0
                || correction.selectedCurrentElliotLabel != alert.currentElliotLabel
                || !this.samePrice(correction.referencePrice, alert.referencePrice)
                || !this.samePrice(correction.originalLc5, alert.stopLoss) || correction.selectedRiskPips < 0
                || correction.isSelectedStopLossAvailable != (int)(correction.referencePrice > 0 && correction.selectedStopLoss > 0)
                || (correction.isSelectedStopLossAvailable == 0 && correction.selectedRiskPips != 0)) {
            fromSnapshot.correctionReason = "元アラートと補正の状態・価格・波動情報が不整合です。";
            return false;
        }
        if (correction.correctionStatus == "NONE") {
            if (correction.selectedAnalysis != "ORIGINAL" || correction.correctionTimeFrame != 0
                    || correction.originalDirection != "" || correction.correctedDirection != ""
                    || correction.correctedReferencePointTime != 0 || correction.correctedAnalysisText != ""
                    || correction.correctedElliotCsvText != "" || correction.correctedLc0 != 0
                    || correction.correctedLc5 != 0 || correction.correctedLc10 != 0 || correction.correctedLc15 != 0
                    || correction.correctedLossCutDiffPips != 0 || correction.correctedLossCutDiffJpy != 0
                    || !this.samePrice(correction.selectedStopLoss, correction.originalLc5)
                    || !this.samePrice(correction.selectedRiskPips, alert.riskPips)) {
                fromSnapshot.correctionReason = "補正なしの記録に補正後の値が混在しています。";
                return false;
            }
            return true;
        }
        if (correction.selectedAnalysis != "CORRECTED"
                || (correction.correctionTimeFrame != PERIOD_H1 && correction.correctionTimeFrame != PERIOD_H4)
                || (correction.originalDirection != "BUY" && correction.originalDirection != "SELL")
                || correction.originalDirection == correction.correctedDirection || correction.correctedDirection != alert.side
                || !this.samePrice(correction.selectedStopLoss, correction.correctedLc5)
                || correction.correctedReferencePointTime <= 0 || correction.correctedAnalysisText == ""
                || correction.correctedElliotCsvText == "") {
            fromSnapshot.correctionReason = "補正した時間足・方向・採用損切りが不整合です。";
            return false;
        }
        return true;
    }

    /**
     * 一括読取を行い、壊れた分析配列は表示対象から除く。
     */
    bool loadSnapshotRows(const long fromAlertId, ZigZagElliotAlertHistorySnapshot &fromSnapshot, string &fromError) {
        if (!this.loadParents(fromAlertId, fromSnapshot, fromError)) {
            return false;
        }
        if (!this.loadAnalysis(fromAlertId, false, fromSnapshot.originalTimeFrames, fromSnapshot.originalPoints,
                fromSnapshot.originalReason, fromError)) {
            return false;
        }
        if (fromSnapshot.originalReason == "") {
            fromSnapshot.originalAvailable = this.validateAnalysis(fromSnapshot.alert, fromSnapshot.originalTimeFrames,
                fromSnapshot.originalPoints, fromSnapshot.alert.signalReferencePointTime, 0, false, fromSnapshot.originalReason);
        }
        if (!this.loadCorrection(fromSnapshot, fromError)) {
            return false;
        }
        if (fromSnapshot.correctionStatus != "UNRECORDED" && fromSnapshot.correctionStatus != "INCOMPLETE") {
            if (!this.validateCorrection(fromSnapshot)) {
                fromSnapshot.correctionStatus = "INCOMPLETE";
            } else {
                if (fromSnapshot.originalAvailable
                        && !this.validateAnalysis(fromSnapshot.alert, fromSnapshot.originalTimeFrames,
                            fromSnapshot.originalPoints, fromSnapshot.alert.signalReferencePointTime,
                            fromSnapshot.correction.originalLc0, true, fromSnapshot.originalReason)) {
                    fromSnapshot.originalAvailable = false;
                    fromSnapshot.correctionStatus = "INCOMPLETE";
                    fromSnapshot.correctionReason = "補正前: " + fromSnapshot.originalReason;
                }
                if (fromSnapshot.correctionStatus == "INCOMPLETE") {
                    ArrayFree(fromSnapshot.originalTimeFrames);
                    ArrayFree(fromSnapshot.originalPoints);
                    return true;
                }
                if (!this.loadAnalysis(fromAlertId, true, fromSnapshot.correctedTimeFrames, fromSnapshot.correctedPoints,
                        fromSnapshot.correctionReason, fromError)) {
                    return false;
                }
                if (fromSnapshot.correctionReason != "") {
                    fromSnapshot.correctionStatus = "INCOMPLETE";
                } else if (fromSnapshot.correctionStatus == "NONE") {
                    if (fromSnapshot.originalAvailable
                            && fromSnapshot.originalTimeFrames[6].latestElliotLabel
                                != fromSnapshot.correction.selectedCurrentElliotLabel) {
                        fromSnapshot.correctionStatus = "INCOMPLETE";
                        fromSnapshot.correctionReason = "採用したM5波動ラベルが元分析と一致しません。";
                    } else if (ArraySize(fromSnapshot.correctedTimeFrames) > 0 || ArraySize(fromSnapshot.correctedPoints) > 0) {
                        fromSnapshot.correctionStatus = "INCOMPLETE";
                        fromSnapshot.correctionReason = "補正なしの記録に補正後の分析が混在しています。";
                    }
                } else {
                    this.validateComparison(fromSnapshot);
                }
            }
        }
        if (!fromSnapshot.originalAvailable) {
            ArrayFree(fromSnapshot.originalTimeFrames);
            ArrayFree(fromSnapshot.originalPoints);
        }
        if (fromSnapshot.correctionStatus != "APPLIED") {
            ArrayFree(fromSnapshot.correctedTimeFrames);
            ArrayFree(fromSnapshot.correctedPoints);
        }
        return true;
    }

    /**
     * 元分析と補正分析を検証し、H4/H1の指定片足だけの方向変更を確認する。
     */
    void validateComparison(ZigZagElliotAlertHistorySnapshot &fromSnapshot) {
        fromSnapshot.correctionStatus = "INCOMPLETE";
        if (!fromSnapshot.originalAvailable) {
            fromSnapshot.correctionReason = "補正前: " + fromSnapshot.originalReason;
            return;
        }
        string reason = "";
        if (!this.validateAnalysis(fromSnapshot.alert, fromSnapshot.originalTimeFrames, fromSnapshot.originalPoints,
                fromSnapshot.alert.signalReferencePointTime, fromSnapshot.correction.originalLc0, true, reason)) {
            fromSnapshot.originalAvailable = false;
            fromSnapshot.originalReason = reason;
            fromSnapshot.correctionReason = "補正前: " + reason;
            return;
        }
        if (!this.validateAnalysis(fromSnapshot.alert, fromSnapshot.correctedTimeFrames, fromSnapshot.correctedPoints,
                fromSnapshot.correction.correctedReferencePointTime, fromSnapshot.correction.correctedLc0, true, reason)) {
            fromSnapshot.correctionReason = "補正後: " + reason;
            return;
        }
        for (int i = 0; i < 7; i++) {
            ZigZagElliotAlertTimeFrameEntity original = fromSnapshot.originalTimeFrames[i];
            ZigZagElliotAlertTimeFrameEntity corrected = fromSnapshot.correctedTimeFrames[i];
            bool valid = original.isBuy == corrected.isBuy;
            if (original.timeFrame == fromSnapshot.correction.correctionTimeFrame) {
                valid = original.buySellLabel == fromSnapshot.correction.originalDirection
                    && corrected.buySellLabel == fromSnapshot.correction.correctedDirection;
            } else if (original.timeFrame == PERIOD_H4 || original.timeFrame == PERIOD_H1) {
                valid = valid && original.buySellLabel == fromSnapshot.alert.side;
            }
            if (!valid) {
                fromSnapshot.correctionReason = "指定したH4またはH1以外にも方向変更があります。";
                return;
            }
        }
        if (fromSnapshot.correctedTimeFrames[6].latestElliotLabel != fromSnapshot.correction.selectedCurrentElliotLabel) {
            fromSnapshot.correctionReason = "採用したM5波動ラベルが一致しません。";
            return;
        }
        fromSnapshot.correctionStatus = "APPLIED";
    }

    /**
     * Alertの読取列を固定順で取得する。
     */
    string getAlertColumns() {
        return "id,run_id,server_time,server_time_text,jst_time,jst_time_text,current_bar_time,current_bar_time_text,signal_reference_point_time,signal_reference_point_time_text,symbol_name,time_frame,time_frame_text,side,is_alert,is_entry,entry_result,signal_count,entry_count,is_entry_evaluated,current_elliot_label,reference_price,is_stop_loss_available,stop_loss,risk_pips,spread_pips,alert_title,alert_text,wave_summary_text";
    }

    /**
     * Alertの列型と値を確認して読み取る。
     */
    bool readAlert(const int fromRequest, ZigZagElliotAlertEntity &fromEntity) {
        ZeroMemory(fromEntity);
        return this.readLongValue(fromRequest, 0, fromEntity.id)
            && this.readLongValue(fromRequest, 1, fromEntity.runId)
            && this.readTimeValue(fromRequest, 2, fromEntity.serverTime)
            && this.readTextValue(fromRequest, 3, fromEntity.serverTimeText)
            && this.readTimeValue(fromRequest, 4, fromEntity.jstTime)
            && this.readTextValue(fromRequest, 5, fromEntity.jstTimeText)
            && this.readTimeValue(fromRequest, 6, fromEntity.currentBarTime)
            && this.readTextValue(fromRequest, 7, fromEntity.currentBarTimeText)
            && this.readTimeValue(fromRequest, 8, fromEntity.signalReferencePointTime)
            && this.readTextValue(fromRequest, 9, fromEntity.signalReferencePointTimeText)
            && this.readTextValue(fromRequest, 10, fromEntity.symbolName)
            && this.readIntValue(fromRequest, 11, fromEntity.timeFrame)
            && this.readTextValue(fromRequest, 12, fromEntity.timeFrameText)
            && this.readTextValue(fromRequest, 13, fromEntity.side)
            && this.readIntValue(fromRequest, 14, fromEntity.isAlert, true)
            && this.readIntValue(fromRequest, 15, fromEntity.isEntry, true)
            && this.readTextValue(fromRequest, 16, fromEntity.entryResult)
            && this.readIntValue(fromRequest, 17, fromEntity.signalCount)
            && this.readIntValue(fromRequest, 18, fromEntity.entryCount)
            && this.readIntValue(fromRequest, 19, fromEntity.isEntryEvaluated, true)
            && this.readTextValue(fromRequest, 20, fromEntity.currentElliotLabel)
            && this.readDoubleValue(fromRequest, 21, fromEntity.referencePrice)
            && this.readIntValue(fromRequest, 22, fromEntity.isStopLossAvailable, true)
            && this.readDoubleValue(fromRequest, 23, fromEntity.stopLoss)
            && this.readDoubleValue(fromRequest, 24, fromEntity.riskPips)
            && this.readDoubleValue(fromRequest, 25, fromEntity.spreadPips)
            && this.readTextValue(fromRequest, 26, fromEntity.alertTitle)
            && this.readTextValue(fromRequest, 27, fromEntity.alertText)
            && this.readTextValue(fromRequest, 28, fromEntity.waveSummaryText);
    }

    /**
     * Runの読取列を固定順で取得する。
     */
    string getRunColumns() {
        return "id,run_uid,schema_version,source_mode,source,source_server,program_name,program_version,strategy,strategy_version,input_text,started_at,started_at_text";
    }

    /**
     * Runの列型と値を確認して読み取る。
     */
    bool readRun(const int fromRequest, ZigZagElliotAlertRunEntity &fromEntity) {
        ZeroMemory(fromEntity);
        return this.readLongValue(fromRequest, 0, fromEntity.id)
            && this.readTextValue(fromRequest, 1, fromEntity.runUid)
            && this.readIntValue(fromRequest, 2, fromEntity.schemaVersion)
            && this.readTextValue(fromRequest, 3, fromEntity.sourceMode)
            && this.readTextValue(fromRequest, 4, fromEntity.source)
            && this.readTextValue(fromRequest, 5, fromEntity.sourceServer)
            && this.readTextValue(fromRequest, 6, fromEntity.programName)
            && this.readTextValue(fromRequest, 7, fromEntity.programVersion)
            && this.readTextValue(fromRequest, 8, fromEntity.strategy)
            && this.readTextValue(fromRequest, 9, fromEntity.strategyVersion)
            && this.readTextValue(fromRequest, 10, fromEntity.inputText)
            && this.readTimeValue(fromRequest, 11, fromEntity.startedAt)
            && this.readTextValue(fromRequest, 12, fromEntity.startedAtText);
    }

    /**
     * Correctionの読取列を固定順で取得する。
     */
    string getCorrectionColumns() {
        return "alert_id,correction_status,correction_time_frame,original_direction,corrected_direction,selected_analysis,selected_alert_text,selected_current_elliot_label,selected_wave_summary_text,reference_price,is_selected_stop_loss_available,selected_stop_loss,selected_risk_pips,original_lc0,original_lc5,original_lc10,original_lc15,original_loss_cut_diff_pips,original_loss_cut_diff_jpy,corrected_lc0,corrected_lc5,corrected_lc10,corrected_lc15,corrected_loss_cut_diff_pips,corrected_loss_cut_diff_jpy,corrected_reference_point_time,original_analysis_text,corrected_analysis_text,corrected_elliot_csv_text,comparison_hash,created_at,created_at_text";
    }

    /**
     * Correctionの列型と値を確認して読み取る。
     */
    bool readCorrection(const int fromRequest, ZigZagElliotAlertCorrectionEntity &fromEntity) {
        ZeroMemory(fromEntity);
        return this.readLongValue(fromRequest, 0, fromEntity.alertId)
            && this.readTextValue(fromRequest, 1, fromEntity.correctionStatus)
            && this.readIntValue(fromRequest, 2, fromEntity.correctionTimeFrame)
            && this.readTextValue(fromRequest, 3, fromEntity.originalDirection)
            && this.readTextValue(fromRequest, 4, fromEntity.correctedDirection)
            && this.readTextValue(fromRequest, 5, fromEntity.selectedAnalysis)
            && this.readTextValue(fromRequest, 6, fromEntity.selectedAlertText)
            && this.readTextValue(fromRequest, 7, fromEntity.selectedCurrentElliotLabel)
            && this.readTextValue(fromRequest, 8, fromEntity.selectedWaveSummaryText)
            && this.readDoubleValue(fromRequest, 9, fromEntity.referencePrice)
            && this.readIntValue(fromRequest, 10, fromEntity.isSelectedStopLossAvailable, true)
            && this.readDoubleValue(fromRequest, 11, fromEntity.selectedStopLoss)
            && this.readDoubleValue(fromRequest, 12, fromEntity.selectedRiskPips)
            && this.readDoubleValue(fromRequest, 13, fromEntity.originalLc0)
            && this.readDoubleValue(fromRequest, 14, fromEntity.originalLc5)
            && this.readDoubleValue(fromRequest, 15, fromEntity.originalLc10)
            && this.readDoubleValue(fromRequest, 16, fromEntity.originalLc15)
            && this.readDoubleValue(fromRequest, 17, fromEntity.originalLossCutDiffPips)
            && this.readDoubleValue(fromRequest, 18, fromEntity.originalLossCutDiffJpy)
            && this.readDoubleValue(fromRequest, 19, fromEntity.correctedLc0)
            && this.readDoubleValue(fromRequest, 20, fromEntity.correctedLc5)
            && this.readDoubleValue(fromRequest, 21, fromEntity.correctedLc10)
            && this.readDoubleValue(fromRequest, 22, fromEntity.correctedLc15)
            && this.readDoubleValue(fromRequest, 23, fromEntity.correctedLossCutDiffPips)
            && this.readDoubleValue(fromRequest, 24, fromEntity.correctedLossCutDiffJpy)
            && this.readTimeValue(fromRequest, 25, fromEntity.correctedReferencePointTime)
            && this.readTextValue(fromRequest, 26, fromEntity.originalAnalysisText)
            && this.readTextValue(fromRequest, 27, fromEntity.correctedAnalysisText)
            && this.readTextValue(fromRequest, 28, fromEntity.correctedElliotCsvText)
            && this.readTextValue(fromRequest, 29, fromEntity.comparisonHash)
            && this.readTimeValue(fromRequest, 30, fromEntity.createdAt)
            && this.readTextValue(fromRequest, 31, fromEntity.createdAtText);
    }

    /**
     * TimeFrameの読取列を固定順で取得する。
     */
    string getTimeFrameColumns() {
        return "id,alert_id,time_frame,time_frame_text,time_frame_order,is_current_time_frame,is_buy,buy_sell_label,wave_count,latest_wave_index,is_wave_confirmed,is_wave_motive,is_wave_uptrend,wave_trend_label,previous_last_elliot_label,point_count,latest_elliot_index,latest_elliot_label,latest_sub_elliot_index,latest_sub_elliot_label,previous_open,previous_high,previous_low,previous_close,current_open,current_high,current_low,current_close,is_fibo_expansion_available,fe618_price,fe1000_price,fe1272_price,fe1618_price,fe2000_price,distance_to_fe2000_pips,oscillator_count,is_oscillator_buy,stochastic_short_count,stochastic_middle_count,stochastic_long_count,gmma_trend_count,gmma_cross_count,ema200_shift1,is_ema200_buy,is_ema200_sell";
    }

    /**
     * TimeFrameの列型と値を確認して読み取る。
     */
    bool readTimeFrame(const int fromRequest, ZigZagElliotAlertTimeFrameEntity &fromEntity) {
        ZeroMemory(fromEntity);
        return this.readLongValue(fromRequest, 0, fromEntity.id)
            && this.readLongValue(fromRequest, 1, fromEntity.alertId)
            && this.readIntValue(fromRequest, 2, fromEntity.timeFrame)
            && this.readTextValue(fromRequest, 3, fromEntity.timeFrameText)
            && this.readIntValue(fromRequest, 4, fromEntity.timeFrameOrder)
            && this.readIntValue(fromRequest, 5, fromEntity.isCurrentTimeFrame, true)
            && this.readIntValue(fromRequest, 6, fromEntity.isBuy, true)
            && this.readTextValue(fromRequest, 7, fromEntity.buySellLabel)
            && this.readIntValue(fromRequest, 8, fromEntity.waveCount)
            && this.readIntValue(fromRequest, 9, fromEntity.latestWaveIndex)
            && this.readIntValue(fromRequest, 10, fromEntity.isWaveConfirmed, true)
            && this.readIntValue(fromRequest, 11, fromEntity.isWaveMotive, true)
            && this.readIntValue(fromRequest, 12, fromEntity.isWaveUptrend, true)
            && this.readTextValue(fromRequest, 13, fromEntity.waveTrendLabel)
            && this.readTextValue(fromRequest, 14, fromEntity.previousLastElliotLabel)
            && this.readIntValue(fromRequest, 15, fromEntity.pointCount)
            && this.readIntValue(fromRequest, 16, fromEntity.latestElliotIndex)
            && this.readTextValue(fromRequest, 17, fromEntity.latestElliotLabel)
            && this.readIntValue(fromRequest, 18, fromEntity.latestSubElliotIndex)
            && this.readTextValue(fromRequest, 19, fromEntity.latestSubElliotLabel)
            && this.readDoubleValue(fromRequest, 20, fromEntity.previousOpen)
            && this.readDoubleValue(fromRequest, 21, fromEntity.previousHigh)
            && this.readDoubleValue(fromRequest, 22, fromEntity.previousLow)
            && this.readDoubleValue(fromRequest, 23, fromEntity.previousClose)
            && this.readDoubleValue(fromRequest, 24, fromEntity.currentOpen)
            && this.readDoubleValue(fromRequest, 25, fromEntity.currentHigh)
            && this.readDoubleValue(fromRequest, 26, fromEntity.currentLow)
            && this.readDoubleValue(fromRequest, 27, fromEntity.currentClose)
            && this.readIntValue(fromRequest, 28, fromEntity.isFiboExpansionAvailable, true)
            && this.readDoubleValue(fromRequest, 29, fromEntity.fe618Price)
            && this.readDoubleValue(fromRequest, 30, fromEntity.fe1000Price)
            && this.readDoubleValue(fromRequest, 31, fromEntity.fe1272Price)
            && this.readDoubleValue(fromRequest, 32, fromEntity.fe1618Price)
            && this.readDoubleValue(fromRequest, 33, fromEntity.fe2000Price)
            && this.readDoubleValue(fromRequest, 34, fromEntity.distanceToFe2000Pips)
            && this.readIntValue(fromRequest, 35, fromEntity.oscillatorCount)
            && this.readIntValue(fromRequest, 36, fromEntity.isOscillatorBuy, true)
            && this.readIntValue(fromRequest, 37, fromEntity.stochasticShortCount)
            && this.readIntValue(fromRequest, 38, fromEntity.stochasticMiddleCount)
            && this.readIntValue(fromRequest, 39, fromEntity.stochasticLongCount)
            && this.readIntValue(fromRequest, 40, fromEntity.gmmaTrendCount)
            && this.readIntValue(fromRequest, 41, fromEntity.gmmaCrossCount)
            && this.readDoubleValue(fromRequest, 42, fromEntity.ema200Shift1)
            && this.readIntValue(fromRequest, 43, fromEntity.isEma200Buy, true)
            && this.readIntValue(fromRequest, 44, fromEntity.isEma200Sell, true);
    }

    /**
     * Pointの読取列を固定順で取得する。
     */
    string getPointColumns() {
        return "id,alert_timeframe_id,point_order,is_latest,is_signal_reference,rate,bar_index,bar_time,bar_time_text,is_bar_time_next_available,bar_time_next,wave_bars_from_start,is_peak,is_added_point,pips_diff,is_fibonacci_available,fibonacci_percent,is_fibonacci_expansion_available,fibonacci_expansion_percent,is_elliot_alphabet,elliot_index,elliot_label,is_sub_elliot_available,sub_elliot_index,sub_elliot_label,is_original_elliot_available,org_elliot_index,org_elliot_label,is_correct";
    }

    /**
     * Pointの列型と値を確認して読み取る。
     */
    bool readPoint(const int fromRequest, ZigZagElliotAlertPointEntity &fromEntity) {
        ZeroMemory(fromEntity);
        return this.readLongValue(fromRequest, 0, fromEntity.id)
            && this.readLongValue(fromRequest, 1, fromEntity.alertTimeFrameId)
            && this.readIntValue(fromRequest, 2, fromEntity.pointOrder)
            && this.readIntValue(fromRequest, 3, fromEntity.isLatest, true)
            && this.readIntValue(fromRequest, 4, fromEntity.isSignalReference, true)
            && this.readDoubleValue(fromRequest, 5, fromEntity.rate)
            && this.readIntValue(fromRequest, 6, fromEntity.barIndex)
            && this.readTimeValue(fromRequest, 7, fromEntity.barTime)
            && this.readTextValue(fromRequest, 8, fromEntity.barTimeText)
            && this.readIntValue(fromRequest, 9, fromEntity.isBarTimeNextAvailable, true)
            && this.readTimeValue(fromRequest, 10, fromEntity.barTimeNext)
            && this.readIntValue(fromRequest, 11, fromEntity.waveBarsFromStart)
            && this.readIntValue(fromRequest, 12, fromEntity.isPeak, true)
            && this.readIntValue(fromRequest, 13, fromEntity.isAddedPoint, true)
            && this.readDoubleValue(fromRequest, 14, fromEntity.pipsDiff)
            && this.readIntValue(fromRequest, 15, fromEntity.isFibonacciAvailable, true)
            && this.readDoubleValue(fromRequest, 16, fromEntity.fibonacciPercent)
            && this.readIntValue(fromRequest, 17, fromEntity.isFibonacciExpansionAvailable, true)
            && this.readDoubleValue(fromRequest, 18, fromEntity.fibonacciExpansionPercent)
            && this.readIntValue(fromRequest, 19, fromEntity.isElliotAlphabet, true)
            && this.readIntValue(fromRequest, 20, fromEntity.elliotIndex)
            && this.readTextValue(fromRequest, 21, fromEntity.elliotLabel)
            && this.readIntValue(fromRequest, 22, fromEntity.isSubElliotAvailable, true)
            && this.readIntValue(fromRequest, 23, fromEntity.subElliotIndex)
            && this.readTextValue(fromRequest, 24, fromEntity.subElliotLabel)
            && this.readIntValue(fromRequest, 25, fromEntity.isOriginalElliotAvailable, true)
            && this.readIntValue(fromRequest, 26, fromEntity.orgElliotIndex)
            && this.readTextValue(fromRequest, 27, fromEntity.orgElliotLabel)
            && this.readIntValue(fromRequest, 28, fromEntity.isCorrect, true);
    }

};

#endif
