#ifndef MSTNG_M5_OBSERVATION_HISTORY_READER_MQH
#define MSTNG_M5_OBSERVATION_HISTORY_READER_MQH

#include <Mstng\Database\Query\ZigZagElliotM5ObservationHistoryData.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * M5観測DBの保存波動を読み取り専用で取得する。
 * Run選択と7足取得は同一読取トランザクションで行い、再分析やDDLを実行しない。
 */
class ZigZagElliotM5ObservationHistoryReader {
public:
    /**
     * 未接続状態を初期化する。
     */
    ZigZagElliotM5ObservationHistoryReader() {
        this.database = NULL;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 所有する読取接続を解放する。
     */
    ~ZigZagElliotM5ObservationHistoryReader() {
        this.close();
    }

    /**
     * 既存のM5観測DBを読み取り専用で開く。
     */
    bool open(const string fromFileName, const bool fromUseCommonFolder, string &fromError) {
        this.close();
        fromError = "";
        if (fromFileName == "") {
            fromError = "M5観測DBファイル名が指定されていません。";

            return false;
        }

        this.database = new SqliteDatabase(fromFileName, fromUseCommonFolder);
        if (this.database == NULL || !this.database.openReadOnly()) {
            fromError = "M5観測DBを読み取り専用で開けません。";
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
     * 指定Runを優先し、同じ分析設定の過去Runで欠損時刻を補った半開区間を取得する。
     * Run0は表示範囲によらず既知時刻までに記録がある最新Runを選ぶ。
     * 同一バーの重複、形式不整合、2000件超過は一部表示せずエラーにする。
     */
    bool selectRecords(
        const string fromSymbol, const string fromSourceMode, const string fromSourceServer,
        const long fromRequestedRunId, const datetime fromStartTime, const datetime fromEndTime,
        const datetime fromKnownTime, long &fromResolvedRunId,
        M5ObservationHistoryRecord &fromRecords[], string &fromError
    ) {
        ArrayFree(fromRecords);
        fromResolvedRunId = 0;
        fromError = "";
        if (this.database == NULL || !this.database.isOpen()) {
            fromError = "M5観測DBが開かれていません。";

            return false;
        }

        if (fromSymbol == "" || fromSourceServer == ""
                || (fromSourceMode != "LIVE" && fromSourceMode != "TESTER")
                || fromRequestedRunId < 0 || fromStartTime < 0
                || fromEndTime <= fromStartTime || fromKnownTime <= 0) {
            fromError = "M5観測の通貨・実行元・Run・日時範囲が不正です。";

            return false;
        }

        ResetLastError();
        if (!DatabaseExecute(this.database.getHandle(), "BEGIN")) {
            this.databaseError("begin snapshot", fromError);

            return false;
        }

        string observationColumns = "";
        string frameColumns = "";
        string metricsColumns = "";
        long runId = 0;
        string analysisVersion = "";
        string analysisHash = "";
        bool success = this.inspectColumns(observationColumns, frameColumns, metricsColumns, fromError);
        if (success) {
            success = this.selectRun(fromSymbol, fromSourceMode, fromSourceServer,
                fromRequestedRunId, fromKnownTime, metricsColumns,
                runId, analysisVersion, analysisHash, fromError);
        }
        if (success && runId > 0) {
            success = this.loadRecords(fromSymbol, fromSourceMode, fromSourceServer,
                runId, fromStartTime, fromEndTime, fromKnownTime,
                observationColumns, frameColumns, metricsColumns,
                analysisVersion, analysisHash, fromRecords, fromError);
        }

        if (success) {
            ResetLastError();
            success = DatabaseExecute(this.database.getHandle(), "COMMIT");
            if (!success) {
                this.databaseError("commit snapshot", fromError);
            }
        }
        if (!success) {
            DatabaseExecute(this.database.getHandle(), "ROLLBACK");
            ArrayFree(fromRecords);

            return false;
        }

        fromResolvedRunId = runId;

        return true;
    }

private:
    /** 読み取り専用接続。 */
    SqliteDatabase *database;

    /** 読取失敗の診断ロガー。 */
    Logger logger;

    /**
     * 必須列を確認し、旧DBの任意列有無を保持する。
     */
    bool inspectColumns(string &fromObservationColumns, string &fromFrameColumns,
            string &fromMetricsColumns, string &fromError) {
        string runColumns = "";
        if (!this.tableColumns("zigzag_elliot_alert_runs", runColumns, fromError)
                || !this.tableColumns("zigzag_elliot_observations", fromObservationColumns, fromError)
                || !this.tableColumns("zigzag_elliot_observation_timeframes", fromFrameColumns, fromError)
                || !this.tableColumns("zigzag_elliot_observation_capture_metrics", fromMetricsColumns, fromError)) {
            return false;
        }

        if (!this.hasColumns(runColumns,
                "id,schema_version,strategy,strategy_version,source_mode,source_server,analysis_version,analysis_input_hash,analysis_input_text")
                || !this.hasColumns(fromObservationColumns,
                    "id,run_id,source_mode,source_server,symbol_name,anchor_time_frame,anchor_bar_time,capture_phase,analysis_version,analysis_input_hash,time_frame_count")
                || !this.hasColumns(fromFrameColumns,
                    "id,observation_id,time_frame,time_frame_order,is_anchor_time_frame,latest_elliot_label,latest_sub_elliot_index,latest_sub_elliot_label,is_wave_uptrend,is_buy,is_wave_confirmed,latest_point_time,latest_point_rate")
                || (fromMetricsColumns != "," && !this.hasColumns(fromMetricsColumns, "observation_id"))) {
            fromError = "M5観測DBの必須テーブル・列が不足しています。";

            return false;
        }

        return true;
    }

    /**
     * 指定列がすべて存在することを確認する。
     */
    bool hasColumns(const string fromColumns, const string fromRequired) {
        string names[];
        int count = StringSplit(fromRequired, ',', names);
        for (int i = 0; i < count; i++) {
            if (StringFind(fromColumns, "," + names[i] + ",") < 0) {
                return false;
            }
        }

        return true;
    }

    /**
     * 未実装の旧列をSQL NULLへ置き換える。
     */
    string optionalColumn(const string fromColumns, const string fromName, const string fromAlias) {
        if (StringFind(fromColumns, "," + fromName + ",") < 0) {
            return "NULL";
        }

        return fromAlias + fromName;
    }

    /**
     * 品質表の観測ID索引で保存取得時刻を取得する。全表集計は行わない。
     */
    string captureExpression(const string fromMetricsColumns) {
        if (!this.hasColumns(fromMetricsColumns, "observation_id,capture_market_time")) {
            return "NULL";
        }

        return "(SELECT MAX(capture_market_time) FROM zigzag_elliot_observation_capture_metrics "
            + "WHERE observation_id=o.id)";
    }

    /**
     * 同じ観測IDの品質行数を索引で取得し、破損DBの重複を検査できるようにする。
     */
    string metricsCountExpression(const string fromMetricsColumns) {
        if (fromMetricsColumns == ",") {
            return "NULL";
        }

        return "(SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics WHERE observation_id=o.id)";
    }

    /**
     * 表示範囲とは独立した互換Runの選択SQLを生成する。
     */
    string buildRunSql(const string fromMetricsColumns) {
        string capture = this.captureExpression(fromMetricsColumns);
        string sql = "SELECT r.id,r.analysis_version,r.analysis_input_hash FROM zigzag_elliot_alert_runs r ";
        sql += "WHERE r.source_mode=?2 AND r.source_server=?3 AND (?4=0 OR r.id=?4) ";
        sql += "AND r.schema_version=1 AND r.strategy='M5_OBSERVATION_ALL' ";
        sql += "AND r.strategy_version='M5_OBSERVATION_ALL_V1' ";
        sql += "AND substr(r.analysis_input_text,1,26)='M5_OBSERVATION_PROFILE_V1|' ";
        sql += "AND r.analysis_version<>'' AND r.analysis_input_hash<>'' ";
        sql += "AND EXISTS (SELECT 1 FROM zigzag_elliot_observations o WHERE o.run_id=r.id ";
        sql += "AND o.symbol_name=?1 AND o.source_mode=r.source_mode AND o.source_server=r.source_server ";
        sql += "AND o.anchor_time_frame=5 AND o.anchor_bar_time>0 AND o.anchor_bar_time<=?5 ";
        sql += "AND (" + capture + " IS NULL OR " + capture + "<=?5)) ";
        sql += "ORDER BY r.id DESC LIMIT 1";

        return sql;
    }

    /**
     * 同じ設定の対象Run以前からM5時刻ごとに最新Runを選び、保存7足を一括取得する。
     * 同じRun・時刻の重複は残して検査し、2001件目で表示上限超過を検出する。
     */
    string buildRecordsSql(const string fromObservationColumns, const string fromFrameColumns,
            const string fromMetricsColumns) {
        string capture = this.captureExpression(fromMetricsColumns);
        string sql = "WITH compatible_runs AS (SELECT r.id FROM zigzag_elliot_alert_runs r ";
        sql += "JOIN zigzag_elliot_alert_runs target ON target.id=?1 ";
        sql += "WHERE r.id<=target.id AND r.source_mode=?3 AND r.source_server=?4 ";
        sql += "AND r.schema_version=target.schema_version AND r.strategy=target.strategy ";
        sql += "AND r.strategy_version=target.strategy_version AND r.analysis_version=target.analysis_version ";
        sql += "AND r.analysis_input_hash=target.analysis_input_hash ";
        sql += "AND r.analysis_input_text=target.analysis_input_text), ";
        sql += "candidates AS (SELECT o.*," + capture + " AS recorded_capture_time,";
        sql += this.metricsCountExpression(fromMetricsColumns) + " AS recorded_metric_count ";
        sql += "FROM zigzag_elliot_observations o JOIN compatible_runs r ON r.id=o.run_id ";
        sql += "WHERE o.symbol_name=?2 AND o.source_mode=?3 AND o.source_server=?4 ";
        sql += "AND o.anchor_bar_time>=?5 AND o.anchor_bar_time<?6 AND o.anchor_bar_time<=?7 ";
        sql += "AND (" + capture + " IS NULL OR " + capture + "<=?7)), ";
        sql += "preferred AS (SELECT anchor_bar_time,MAX(run_id) AS run_id FROM candidates GROUP BY anchor_bar_time), ";
        sql += "selected AS (SELECT o.* FROM candidates o JOIN preferred p ";
        sql += "ON p.anchor_bar_time=o.anchor_bar_time AND p.run_id=o.run_id ";
        sql += "ORDER BY o.anchor_bar_time,o.id LIMIT 2001) ";
        sql += "SELECT o.id,o.run_id,o.anchor_bar_time,";
        sql += this.optionalColumn(fromObservationColumns, "anchor_jst_time", "o.");
        sql += ",o.recorded_capture_time,o.recorded_metric_count,f.id,f.time_frame,f.time_frame_order,";
        sql += "f.latest_elliot_label,f.latest_sub_elliot_index,f.latest_sub_elliot_label,";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_org_elliot_label", "f.");
        sql += ",f.is_wave_uptrend,f.is_buy,f.is_wave_confirmed,";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_is_added", "f.");
        sql += ",f.latest_point_time,f.latest_point_rate,o.anchor_time_frame,o.capture_phase,";
        sql += "o.time_frame_count,o.analysis_version,o.analysis_input_hash,f.is_anchor_time_frame,";
        sql += this.optionalColumn(fromFrameColumns, "is_ema200_buy", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "is_ema200_sell", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "is_price_movement_valid", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "price_movement_level", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "price_movement_activity_ratio", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_org_elliot_index", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "previous_motive_sub_elliot_index", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_pips_diff", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_fibonacci_percent", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_fibonacci_expansion_percent", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "latest_point_jst_time", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "gmma_trend_count", "f.") + ",";
        sql += this.optionalColumn(fromFrameColumns, "gmma_cross_count", "f.");
        sql += " FROM selected o LEFT JOIN zigzag_elliot_observation_timeframes f ON f.observation_id=o.id ";
        sql += "ORDER BY o.anchor_bar_time,o.id,f.time_frame_order,f.id";

        return sql;
    }

    /**
     * 最新の互換Runを一つ選ぶ。明示したRunが一致しない場合は他Runへ切り替えない。
     */
    bool selectRun(const string fromSymbol, const string fromSourceMode, const string fromSourceServer,
            const long fromRequestedRunId, const datetime fromKnownTime, const string fromMetricsColumns,
            long &fromRunId, string &fromAnalysisVersion, string &fromAnalysisHash, string &fromError) {
        int request = this.prepare(this.buildRunSql(fromMetricsColumns), fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }

        bool success = DatabaseBind(request, 0, fromSymbol)
            && DatabaseBind(request, 1, fromSourceMode) && DatabaseBind(request, 2, fromSourceServer)
            && DatabaseBind(request, 3, fromRequestedRunId) && DatabaseBind(request, 4, (long)fromKnownTime);
        if (!success) {
            this.databaseError("bind run", fromError);
        }

        bool hasRow = false;
        if (success) {
            success = this.readNext(request, hasRow, fromError);
        }
        if (success && hasRow) {
            success = this.readLongValue(request, 0, fromRunId) && fromRunId > 0
                && this.readTextValue(request, 1, fromAnalysisVersion) && fromAnalysisVersion != ""
                && this.readTextValue(request, 2, fromAnalysisHash) && fromAnalysisHash != "";
            if (!success) {
                fromError = "M5観測Runの識別情報が不正です。";
            }
        } else if (success && fromRequestedRunId > 0) {
            fromError = "指定Runに一致するM5観測がありません。通貨・実行元・形式を確認してください。";
            success = false;
        }

        DatabaseFinalize(request);

        return success;
    }

    /**
     * 対象Runと互換の過去Runから、時刻ごとの親観測と子7足を一つの要求で取得する。
     */
    bool loadRecords(const string fromSymbol, const string fromSourceMode, const string fromSourceServer,
            const long fromRunId, const datetime fromStartTime, const datetime fromEndTime,
            const datetime fromKnownTime, const string fromObservationColumns, const string fromFrameColumns,
            const string fromMetricsColumns, const string fromAnalysisVersion, const string fromAnalysisHash,
            M5ObservationHistoryRecord &fromRecords[], string &fromError) {
        int request = this.prepare(this.buildRecordsSql(fromObservationColumns, fromFrameColumns, fromMetricsColumns), fromError);
        if (request == INVALID_HANDLE) {
            return false;
        }

        bool success = DatabaseBind(request, 0, fromRunId) && DatabaseBind(request, 1, fromSymbol)
            && DatabaseBind(request, 2, fromSourceMode) && DatabaseBind(request, 3, fromSourceServer)
            && DatabaseBind(request, 4, (long)fromStartTime) && DatabaseBind(request, 5, (long)fromEndTime)
            && DatabaseBind(request, 6, (long)fromKnownTime);
        if (!success) {
            this.databaseError("bind observations", fromError);
        }

        bool hasRow = false;
        while (success) {
            if (!this.readNext(request, hasRow, fromError)) {
                success = false;
                break;
            }
            if (!hasRow) {
                break;
            }

            success = this.appendRow(request, fromRunId, fromKnownTime,
                fromAnalysisVersion, fromAnalysisHash, fromRecords, fromError);
        }

        DatabaseFinalize(request);

        return success;
    }

    /**
     * 親観測の切替時に上限・重複・保存メタデータを検証して7足を格納する。
     */
    bool appendRow(const int fromRequest, const long fromRunId, const datetime fromKnownTime,
            const string fromAnalysisVersion, const string fromAnalysisHash,
            M5ObservationHistoryRecord &fromRecords[], string &fromError) {
        long observationId = 0;
        if (!this.readLongValue(fromRequest, 0, observationId) || observationId <= 0) {
            fromError = "M5観測IDが不正です。";

            return false;
        }

        int count = ArraySize(fromRecords);
        if (count == 0 || fromRecords[count - 1].id != observationId) {
            if (count >= 2000) {
                fromError = "表示範囲のM5観測が2000件を超えています。チャート表示範囲を狭めてください。";

                return false;
            }

            M5ObservationHistoryRecord record;
            record.clear();
            if (!this.readParent(fromRequest, fromRunId, fromKnownTime,
                    fromAnalysisVersion, fromAnalysisHash, record, fromError)) {
                return false;
            }

            if (count > 0 && fromRecords[count - 1].barTime == record.barTime) {
                fromError = "同じRun・M5時刻の観測が重複しています。";

                return false;
            }

            if (ArrayResize(fromRecords, count + 1) != count + 1) {
                fromError = "M5観測表示のメモリを確保できません。";

                return false;
            }

            fromRecords[count] = record;
            count++;
        }

        if (DatabaseColumnType(fromRequest, 6) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        return this.readFrame(fromRequest, fromRecords[count - 1], fromError);
    }

    /**
     * 親観測の時刻とRunに対する整合を確認する。
     */
    bool readParent(const int fromRequest, const long fromRunId, const datetime fromKnownTime,
            const string fromAnalysisVersion, const string fromAnalysisHash,
            M5ObservationHistoryRecord &fromRecord, string &fromError) {
        long anchorTimeFrame = 0;
        long timeFrameCount = 0;
        long metricsCount = 0;
        string capturePhase = "";
        string analysisVersion = "";
        string analysisHash = "";
        if (!this.readLongValue(fromRequest, 0, fromRecord.id)
                || !this.readLongValue(fromRequest, 1, fromRecord.runId)
                || fromRecord.runId <= 0 || fromRecord.runId > fromRunId
                || !this.readTimeValue(fromRequest, 2, fromRecord.barTime) || fromRecord.barTime <= 0
                || fromRecord.barTime > fromKnownTime
                || !this.readOptionalTime(fromRequest, 3, fromRecord.jstTime)
                || !this.readOptionalTime(fromRequest, 4, fromRecord.captureTime)
                || fromRecord.captureTime > fromKnownTime
                || !this.readLongValue(fromRequest, 19, anchorTimeFrame) || anchorTimeFrame != PERIOD_M5
                || !this.readTextValue(fromRequest, 20, capturePhase) || capturePhase != "BAR_OPEN_FIRST_SUCCESS"
                || !this.readLongValue(fromRequest, 21, timeFrameCount) || timeFrameCount != 7
                || !this.readTextValue(fromRequest, 22, analysisVersion) || analysisVersion != fromAnalysisVersion
                || !this.readTextValue(fromRequest, 23, analysisHash) || analysisHash != fromAnalysisHash) {
            fromError = "M5観測の保存時刻・Run・分析情報が不正です。";

            return false;
        }

        if (DatabaseColumnType(fromRequest, 5) != DATABASE_FIELD_TYPE_NULL
                && (!this.readLongValue(fromRequest, 5, metricsCount) || metricsCount < 0 || metricsCount > 1)) {
            fromError = "M5観測の取得品質行が重複または不正です。";

            return false;
        }

        if (fromRecord.captureTime > 0 && fromRecord.captureTime < fromRecord.barTime) {
            fromError = "M5観測の取得時刻が基準足より前です。";

            return false;
        }

        fromRecord.isPreviousRun = fromRecord.runId < fromRunId;

        return true;
    }

    /**
     * 保存された時間足と順序を検証し、欠損と重複を区別する。
     */
    bool readFrame(const int fromRequest, M5ObservationHistoryRecord &fromRecord, string &fromError) {
        long frameId = 0;
        long timeFrame = 0;
        long order = 0;
        long subIndex = 0;
        long anchorFlag = 0;
        if (!this.readLongValue(fromRequest, 6, frameId) || frameId <= 0
                || !this.readLongValue(fromRequest, 7, timeFrame)
                || !this.readLongValue(fromRequest, 8, order) || order < 0 || order > 6
                || fromRecord.frames[(int)order].timeFrame != timeFrame
                || fromRecord.frames[(int)order].hasData
                || !this.readLongValue(fromRequest, 24, anchorFlag)
                || (order == 6 && anchorFlag != 1) || (order != 6 && anchorFlag != 0)) {
            fromError = "M5観測の時間足行が重複または不正です。";

            return false;
        }

        M5ObservationHistoryFrame frame;
        frame.clear();
        frame.timeFrame = (int)timeFrame;
        if (!this.readTextValue(fromRequest, 9, frame.mainWave) || frame.mainWave == ""
                || !this.readLongValue(fromRequest, 10, subIndex) || subIndex < 0
                || !this.readTextValue(fromRequest, 11, frame.subWave)
                || !this.readFlag(fromRequest, 13, frame.isUptrend)
                || !this.readFlag(fromRequest, 14, frame.isBuy)
                || !this.readFlag(fromRequest, 15, frame.isConfirmed)
                || !this.readTimeValue(fromRequest, 17, frame.pointTime) || frame.pointTime <= 0) {
            fromError = "M5観測の波動ラベル・方向・確定状態が不正です。";

            return false;
        }

        if (subIndex == 0) {
            frame.subWave = "";
        } else if (frame.subWave == "") {
            fromError = "M5観測の副次波ラベルが不足しています。";

            return false;
        }
        if (DatabaseColumnType(fromRequest, 12) != DATABASE_FIELD_TYPE_NULL
                && !this.readTextValue(fromRequest, 12, frame.originalWave)) {
            fromError = "M5観測の元主波ラベルが不正です。";

            return false;
        }

        if (DatabaseColumnType(fromRequest, 16) != DATABASE_FIELD_TYPE_NULL
                && !this.readFlag(fromRequest, 16, frame.isAdded)) {
            fromError = "M5観測の補完ポイント状態が不正です。";

            return false;
        }

        if (DatabaseColumnType(fromRequest, 18) != DATABASE_FIELD_TYPE_NULL) {
            if (!this.readDoubleValue(fromRequest, 18, frame.pointRate) || frame.pointRate <= 0.0) {
                fromError = "M5観測のポイント価格が不正です。";

                return false;
            }

            frame.hasPointRate = true;
        }

        if (!this.readFrameDetails(fromRequest, frame, fromError)) {
            return false;
        }

        frame.hasData = true;
        fromRecord.frames[(int)order] = frame;

        return true;
    }

    /**
     * 表形式の詳細表示に使う任意列を取得し、旧DBの欠損を未記録のまま保持する。
     */
    bool readFrameDetails(const int fromRequest, M5ObservationHistoryFrame &fromFrame,
            string &fromError) {
        if (!this.readOptionalFlag(fromRequest, 25, fromFrame.isEma200Buy)
                || !this.readOptionalFlag(fromRequest, 26, fromFrame.isEma200Sell)) {
            fromError = "M5観測のEMA200方向が不正です。";

            return false;
        }

        if (!this.readOptionalFlag(fromRequest, 27, fromFrame.isPriceMovementValid)
                || !this.readOptionalInteger(fromRequest, 28, 3, fromFrame.priceMovementLevel)
                || !this.readOptionalDouble(fromRequest, 29, fromFrame.priceMovementActivityRatio,
                    fromFrame.hasPriceMovementActivityRatio)
                || (fromFrame.hasPriceMovementActivityRatio && fromFrame.priceMovementActivityRatio < 0.0)) {
            fromError = "M5観測の値動き判定が不正です。";

            return false;
        }

        if (!this.readOptionalInteger(fromRequest, 30, INT_MAX, fromFrame.originalWaveIndex)
                || !this.readOptionalInteger(fromRequest, 31, 3, fromFrame.previousMotiveSubElliotIndex)
                || fromFrame.previousMotiveSubElliotIndex == 2
                || !this.readOptionalDouble(fromRequest, 32, fromFrame.pointPipsDiff, fromFrame.hasPointPipsDiff)
                || !this.readOptionalDouble(fromRequest, 33, fromFrame.pointFibonacciPercent,
                    fromFrame.hasPointFibonacciPercent)
                || !this.readOptionalDouble(fromRequest, 34, fromFrame.pointFibonacciExpansionPercent,
                    fromFrame.hasPointFibonacciExpansionPercent)
                || !this.readOptionalTime(fromRequest, 35, fromFrame.pointJstTime)) {
            fromError = "M5観測の元波動・値幅・フィボナッチ・日本時刻が不正です。";

            return false;
        }

        if (!this.readOptionalSignedInteger(fromRequest, 36, fromFrame.gmmaTrendCount,
                fromFrame.hasGmmaTrendCount)
                || !this.readOptionalSignedInteger(fromRequest, 37, fromFrame.gmmaCrossCount,
                    fromFrame.hasGmmaCrossCount)) {
            fromError = "M5観測のGMMA継続数が不正です。";

            return false;
        }

        return true;
    }

    /**
     * 内部エラーをログへ記録し、画面へ短い理由を返す。
     */
    void databaseError(const string fromOperation, string &fromError) {
        int errorCode = GetLastError();
        this.logger.error(__FUNCTION__, StringFormat("M5 observation history read failed. operation=%s error=%d", fromOperation, errorCode));
        fromError = "M5観測DBの読み取りに失敗しました。";
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
     * 行終端とDB読取失敗を区別する。
     */
    bool readNext(const int fromRequest, bool &fromHasRow, string &fromError) {
        ResetLastError();
        fromHasRow = DatabaseRead(fromRequest);
        if (fromHasRow) {
            return true;
        }

        if (GetLastError() == ERR_DATABASE_NO_MORE_DATA) {
            return true;
        }

        this.databaseError("read next", fromError);

        return false;
    }

    /**
     * SQLite INTEGERを型変換せず取得する。
     */
    bool readLongValue(const int fromRequest, const int fromColumn, long &fromValue) {
        return DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_INTEGER
            && DatabaseColumnLong(fromRequest, fromColumn, fromValue);
    }

    /**
     * 保存フラグの0・1だけを許可する。
     */
    bool readFlag(const int fromRequest, const int fromColumn, int &fromValue) {
        long value = 0;
        if (!this.readLongValue(fromRequest, fromColumn, value) || (value != 0 && value != 1)) {
            return false;
        }

        fromValue = (int)value;

        return true;
    }

    /**
     * 未記録フラグを-1とし、記録がある場合は0・1だけを取得する。
     */
    bool readOptionalFlag(const int fromRequest, const int fromColumn, int &fromValue) {
        fromValue = -1;
        if (DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        return this.readFlag(fromRequest, fromColumn, fromValue);
    }

    /**
     * 未記録番号を-1とし、記録がある場合は型変換せず非負の整数を取得する。
     */
    bool readOptionalInteger(const int fromRequest, const int fromColumn, const int fromMaximum,
            int &fromValue) {
        fromValue = -1;
        if (DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        long value = 0;
        if (!this.readLongValue(fromRequest, fromColumn, value) || value < 0 || value > fromMaximum) {
            return false;
        }

        fromValue = (int)value;

        return true;
    }

    /**
     * 任意の符号付き整数の有無を分離し、未記録と保存済みのゼロ・負数を区別する。
     */
    bool readOptionalSignedInteger(const int fromRequest, const int fromColumn, int &fromValue,
            bool &fromHasValue) {
        fromValue = 0;
        fromHasValue = false;
        if (DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        long value = 0;
        if (!this.readLongValue(fromRequest, fromColumn, value) || value < INT_MIN || value > INT_MAX) {
            return false;
        }

        fromValue = (int)value;
        fromHasValue = true;

        return true;
    }

    /**
     * 保存された非負の日時を取得する。
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
     * 未記録日時を0のまま残す。
     */
    bool readOptionalTime(const int fromRequest, const int fromColumn, datetime &fromValue) {
        fromValue = 0;
        if (DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        return this.readTimeValue(fromRequest, fromColumn, fromValue);
    }

    /**
     * 保存された有限数だけを取得する。
     */
    bool readDoubleValue(const int fromRequest, const int fromColumn, double &fromValue) {
        ENUM_DATABASE_FIELD_TYPE fieldType = DatabaseColumnType(fromRequest, fromColumn);

        return (fieldType == DATABASE_FIELD_TYPE_INTEGER || fieldType == DATABASE_FIELD_TYPE_FLOAT)
            && DatabaseColumnDouble(fromRequest, fromColumn, fromValue) && MathIsValidNumber(fromValue);
    }

    /**
     * 任意数値の有無を分離し、未記録と保存済みのゼロを区別する。
     */
    bool readOptionalDouble(const int fromRequest, const int fromColumn, double &fromValue,
            bool &fromHasValue) {
        fromValue = 0.0;
        fromHasValue = false;
        if (DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_NULL) {
            return true;
        }

        if (!this.readDoubleValue(fromRequest, fromColumn, fromValue)) {
            return false;
        }

        fromHasValue = true;

        return true;
    }

    /**
     * SQLite TEXTを型変換せず取得する。
     */
    bool readTextValue(const int fromRequest, const int fromColumn, string &fromValue) {
        return DatabaseColumnType(fromRequest, fromColumn) == DATABASE_FIELD_TYPE_TEXT
            && DatabaseColumnText(fromRequest, fromColumn, fromValue);
    }

    /**
     * 固定テーブル名の列一覧を読み取る。存在しない場合はカンマだけを返す。
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

            string name = "";
            if (!this.readTextValue(request, 1, name)) {
                fromError = "M5観測DBの列情報が不正です。";
                success = false;
                break;
            }

            fromColumns += name + ",";
        }

        DatabaseFinalize(request);

        return success;
    }
};

#endif // MSTNG_M5_OBSERVATION_HISTORY_READER_MQH
