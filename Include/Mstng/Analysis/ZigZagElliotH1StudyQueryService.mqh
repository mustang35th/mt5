//+------------------------------------------------------------------+
//|                        ZigZagElliotH1StudyQueryService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_QUERY_SERVICE_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_QUERY_SERVICE_MQH

#include <Mstng\Analysis\ZigZagElliotH1StudyObservation.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * H1 Observation研究用の読み取り専用Query Service。
 *
 * データベースハンドルの所有権は呼び出し元が保持する。書き込みや
 * スキーマ変更を行わず、DATABASE_OPEN_READONLYで開いたハンドルを使用する。
 * Episodeの生成や連続判定は担当しない。
 */
class ZigZagElliotH1StudyQueryService {
public:
    /**
     * 読み取り専用データベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle 読み取り専用で開いたDBハンドル。
     */
    ZigZagElliotH1StudyQueryService(
        const int fromDatabaseHandle
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.hasSpreadPipsColumn = false;
        this.hasPipSizeColumn = false;
        this.hasRunStatusColumn = false;
        this.schemaInspectionSucceeded = false;
        this.logger.setLevel(LOG_INFO);

        if (this.databaseHandle != INVALID_HANDLE) {
            this.schemaInspectionSucceeded = this.inspectSchema();
        }
    }

    /**
     * Observationを保持するRun一覧をID降順で取得する。
     *
     * @param fromInfos 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findRuns(
        ZigZagElliotH1StudySourceRunInfo &fromInfos[]
    ) {
        ArrayResize(fromInfos, 0);

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = this.getRunSelectSql();
        sql += "WHERE EXISTS (";
        sql += "SELECT 1 FROM zigzag_elliot_observations AS observations ";
        sql += "WHERE observations.run_id = runs.id";
        sql += ") ORDER BY runs.id DESC";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        while (true) {
            ZigZagElliotH1StudySourceRunInfo info;
            info.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, info);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                ArrayResize(fromInfos, 0);
                this.logReadError(__FUNCTION__, readErrorCode);

                return false;
            }

            if (!this.isSourceRunInfoValid(info)) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromInfos, 0);
                this.logger.error(
                    __FUNCTION__,
                    "Observation source run metadata is invalid."
                );

                return false;
            }

            int infoIndex = ArraySize(fromInfos);

            if (ArrayResize(fromInfos, infoIndex + 1, 64) != infoIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromInfos, 0);
                this.logArrayResizeError(__FUNCTION__, infoIndex + 1);

                return false;
            }

            fromInfos[infoIndex] = info;
        }
    }

    /**
     * 指定Runのメタデータを取得する。
     *
     * レコードがない場合も検索成功としてtrueを返し、fromIsFoundへfalseを設定する。
     *
     * @param fromRunId 取得対象Run ID。
     * @param fromInfo 取得結果の格納先。
     * @param fromIsFound 対象Runを取得した場合true。
     * @return 検索処理に成功した場合true。
     */
    bool findRun(
        const long fromRunId,
        ZigZagElliotH1StudySourceRunInfo &fromInfo,
        bool &fromIsFound
    ) {
        fromInfo.reset();
        fromIsFound = false;

        if (!this.isRunSearchReady(fromRunId, __FUNCTION__)) {
            return false;
        }

        string sql = this.getRunSelectSql();
        sql += "WHERE runs.id = ?1 AND EXISTS (";
        sql += "SELECT 1 FROM zigzag_elliot_observations AS observations ";
        sql += "WHERE observations.run_id = runs.id";
        sql += ") ORDER BY runs.id DESC LIMIT 1";
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

        ResetLastError();
        bool isRead = DatabaseReadBind(requestHandle, fromInfo);
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);

        if (!isRead) {
            fromInfo.reset();

            if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            this.logReadError(__FUNCTION__, readErrorCode);

            return false;
        }

        if (!this.isSourceRunInfoValid(fromInfo)
                || fromInfo.runId != fromRunId) {
            fromInfo.reset();
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "Observation source run metadata is invalid. runId=%I64d",
                    fromRunId
                )
            );

            return false;
        }

        fromIsFound = true;

        return true;
    }

    /**
     * 指定Runに含まれるObservation Stream一覧を取得する。
     *
     * @param fromRunId 取得対象Run ID。
     * @param fromStreams 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findStreams(
        const long fromRunId,
        ZigZagElliotH1StudyStreamKey &fromStreams[]
    ) {
        ArrayResize(fromStreams, 0);

        if (!this.isRunSearchReady(fromRunId, __FUNCTION__)) {
            return false;
        }

        string sql = "SELECT DISTINCT observations.run_id,";
        sql += " observations.source_mode, observations.source_server,";
        sql += " observations.symbol_name, observations.anchor_time_frame,";
        sql += " observations.capture_phase, observations.analysis_version,";
        sql += " observations.analysis_input_hash ";
        sql += "FROM zigzag_elliot_observations AS observations ";
        sql += "WHERE observations.run_id = ?1 ";
        sql += "ORDER BY observations.source_mode,";
        sql += " observations.source_server, observations.symbol_name,";
        sql += " observations.anchor_time_frame, observations.capture_phase,";
        sql += " observations.analysis_version,";
        sql += " observations.analysis_input_hash";
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

        while (true) {
            ZigZagElliotH1StudyStreamKey stream;
            stream.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, stream);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                ArrayResize(fromStreams, 0);
                this.logReadError(__FUNCTION__, readErrorCode);

                return false;
            }

            if (!this.isStreamKeyValid(stream) || stream.runId != fromRunId) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromStreams, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "Observation stream key is invalid. runId=%I64d",
                        fromRunId
                    )
                );

                return false;
            }

            int streamIndex = ArraySize(fromStreams);

            if (ArrayResize(
                fromStreams,
                streamIndex + 1,
                64
            ) != streamIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromStreams, 0);
                this.logArrayResizeError(__FUNCTION__, streamIndex + 1);

                return false;
            }

            fromStreams[streamIndex] = stream;
        }
    }

    /**
     * 指定Streamの全親ObservationをH1時刻昇順で取得する。
     *
     * 子時間足はLEFT JOINし、不完全な親Observationも結果から除外しない。
     * Episode生成、連続判定および期間絞り込みは行わない。
     *
     * @param fromStream 取得対象Stream。
     * @param fromRows 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findObservations(
        ZigZagElliotH1StudyStreamKey &fromStream,
        ZigZagElliotH1StudyObservationRow &fromRows[]
    ) {
        ArrayResize(fromRows, 0);

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.isStreamKeyValid(fromStream)) {
            this.logger.error(__FUNCTION__, "Observation stream key is invalid.");

            return false;
        }

        string sql = this.getObservationSelectSql();
        sql += "WHERE observations.run_id = ?1 ";
        sql += "AND observations.source_mode = ?2 ";
        sql += "AND observations.source_server = ?3 ";
        sql += "AND observations.symbol_name = ?4 ";
        sql += "AND observations.anchor_time_frame = ?5 ";
        sql += "AND observations.capture_phase = ?6 ";
        sql += "AND observations.analysis_version = ?7 ";
        sql += "AND observations.analysis_input_hash = ?8 ";
        sql += "ORDER BY observations.anchor_bar_time ASC,";
        sql += " observations.id ASC";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        if (!this.bindStream(requestHandle, fromStream, __FUNCTION__)) {
            DatabaseFinalize(requestHandle);

            return false;
        }

        while (true) {
            ZigZagElliotH1StudyObservationRow row;
            row.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, row);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                ArrayResize(fromRows, 0);
                this.logReadError(__FUNCTION__, readErrorCode);

                return false;
            }

            if (!this.isObservationRowValid(row, fromStream)) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromRows, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "Observation row is invalid. observationId=%I64d",
                        row.observationId
                    )
                );

                return false;
            }

            int rowIndex = ArraySize(fromRows);

            if (ArrayResize(fromRows, rowIndex + 1, 1024) != rowIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromRows, 0);
                this.logArrayResizeError(__FUNCTION__, rowIndex + 1);

                return false;
            }

            fromRows[rowIndex] = row;
        }
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** Observation親にspread_pips列が存在する場合true。 */
    bool hasSpreadPipsColumn;

    /** Observation親にpip_size列が存在する場合true。 */
    bool hasPipSizeColumn;

    /** Runにstatus列が存在する場合true。 */
    bool hasRunStatusColumn;

    /** 必要なスキーマ確認に成功した場合true。 */
    bool schemaInspectionSucceeded;

    /** ロガー。 */
    Logger logger;

    /**
     * 読み取り互換性に必要な任意列を確認する。
     *
     * @return すべてのテーブル情報を取得できた場合true。
     */
    bool inspectSchema() {
        if (!this.inspectColumn(
                "zigzag_elliot_observations",
                "spread_pips",
                this.hasSpreadPipsColumn
            )) {
            return false;
        }

        if (!this.inspectColumn(
                "zigzag_elliot_observations",
                "pip_size",
                this.hasPipSizeColumn
            )) {
            return false;
        }

        return this.inspectColumn(
            "zigzag_elliot_alert_runs",
            "status",
            this.hasRunStatusColumn
        );
    }

    /**
     * 指定テーブルに列が存在するか確認する。
     *
     * @param fromTableName テーブル名。
     * @param fromColumnName 列名。
     * @param fromHasColumn 列が存在する場合true。
     * @return table_infoの読取に成功した場合true。
     */
    bool inspectColumn(
        const string fromTableName,
        const string fromColumnName,
        bool &fromHasColumn
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(" + fromTableName + ")"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabasePrepare failed. table=%s error=%d",
                    fromTableName,
                    GetLastError()
                )
            );

            return false;
        }

        while (true) {
            ResetLastError();

            if (!DatabaseRead(requestHandle)) {
                int readErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. table=%s error=%d",
                        fromTableName,
                        readErrorCode
                    )
                );

                return false;
            }

            string columnName = "";
            ResetLastError();

            if (!DatabaseColumnText(requestHandle, 1, columnName)) {
                int columnErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseColumnText failed. table=%s error=%d",
                        fromTableName,
                        columnErrorCode
                    )
                );

                return false;
            }

            if (columnName == fromColumnName) {
                DatabaseFinalize(requestHandle);
                fromHasColumn = true;

                return true;
            }
        }

        return false;
    }

    /**
     * SourceRunInfoの列順にRun取得SELECTの共通部分を生成する。
     *
     * @return FROM句までを含むSELECT文。
     */
    string getRunSelectSql() {
        string statusExpression = "'LEGACY'";

        if (this.hasRunStatusColumn) {
            statusExpression = "COALESCE(NULLIF(runs.status, ''), 'LEGACY')";
        }

        string sql = "SELECT runs.id, runs.run_uid, runs.schema_version,";
        sql += " runs.source_mode, runs.source, runs.program_name,";
        sql += " runs.program_version, runs.strategy,";
        sql += " runs.strategy_version, runs.analysis_version,";
        sql += " runs.analysis_input_hash, runs.input_hash,";
        sql += " runs.source_server, runs.source_login,";
        sql += " runs.tester_from, runs.tester_to, runs.tester_model,";
        sql += " " + statusExpression + " ";
        sql += "FROM zigzag_elliot_alert_runs AS runs ";

        return sql;
    }

    /**
     * ObservationRowの列順にStream全行取得SELECTを生成する。
     *
     * @return WHERE句を含まないSELECT文。
     */
    string getObservationSelectSql() {
        string spreadAvailableExpression = "0";
        string spreadPipsExpression = "0.0";

        if (this.hasSpreadPipsColumn) {
            spreadAvailableExpression = "CASE WHEN observations.spread_pips ";
            spreadAvailableExpression += "IS NOT NULL ";
            spreadAvailableExpression += "AND observations.spread_pips >= 0 ";
            spreadAvailableExpression += "THEN 1 ELSE 0 END";
            spreadPipsExpression = "CASE WHEN observations.spread_pips ";
            spreadPipsExpression += "IS NOT NULL ";
            spreadPipsExpression += "AND observations.spread_pips >= 0 ";
            spreadPipsExpression += "THEN observations.spread_pips ";
            spreadPipsExpression += "ELSE 0.0 END";
        }

        string pipFallbackExpression = "CASE WHEN ";
        pipFallbackExpression += "INSTR(UPPER(observations.symbol_name), ";
        pipFallbackExpression += "'JPY') > 0 THEN 0.01 ELSE 0.0001 END";
        string pipSizeExpression = pipFallbackExpression;
        string pipSizeSourceExpression = "'SYMBOL_RULE_V1'";

        if (this.hasPipSizeColumn) {
            pipSizeExpression = "CASE WHEN observations.pip_size IS NOT NULL ";
            pipSizeExpression += "AND observations.pip_size > 0 ";
            pipSizeExpression += "THEN observations.pip_size ELSE ";
            pipSizeExpression += pipFallbackExpression + " END";
            pipSizeSourceExpression = "CASE WHEN observations.pip_size ";
            pipSizeSourceExpression += "IS NOT NULL ";
            pipSizeSourceExpression += "AND observations.pip_size > 0 ";
            pipSizeSourceExpression += "THEN 'SOURCE_DB' ";
            pipSizeSourceExpression += "ELSE 'SYMBOL_RULE_V1' END";
        }

        string fullAlignmentExpression = "CASE ";
        fullAlignmentExpression += "WHEN w1.id IS NOT NULL ";
        fullAlignmentExpression += "AND d1.id IS NOT NULL ";
        fullAlignmentExpression += "AND h4.id IS NOT NULL ";
        fullAlignmentExpression += "AND h1.id IS NOT NULL ";
        fullAlignmentExpression += "AND w1.is_buy = 1 AND d1.is_buy = 1 ";
        fullAlignmentExpression += "AND h4.is_buy = 1 AND h1.is_buy = 1 ";
        fullAlignmentExpression += "AND h4.is_ema200_buy = 1 ";
        fullAlignmentExpression += "AND h4.is_ema200_sell = 0 ";
        fullAlignmentExpression += "AND h1.is_ema200_buy = 1 ";
        fullAlignmentExpression += "AND h1.is_ema200_sell = 0 THEN 'BUY' ";
        fullAlignmentExpression += "WHEN w1.id IS NOT NULL ";
        fullAlignmentExpression += "AND d1.id IS NOT NULL ";
        fullAlignmentExpression += "AND h4.id IS NOT NULL ";
        fullAlignmentExpression += "AND h1.id IS NOT NULL ";
        fullAlignmentExpression += "AND w1.is_buy = 0 AND d1.is_buy = 0 ";
        fullAlignmentExpression += "AND h4.is_buy = 0 AND h1.is_buy = 0 ";
        fullAlignmentExpression += "AND h4.is_ema200_buy = 0 ";
        fullAlignmentExpression += "AND h4.is_ema200_sell = 1 ";
        fullAlignmentExpression += "AND h1.is_ema200_buy = 0 ";
        fullAlignmentExpression += "AND h1.is_ema200_sell = 1 THEN 'SELL' ";
        fullAlignmentExpression += "ELSE '' END";

        string sql = "SELECT observations.id, observations.run_id,";
        sql += " observations.source_mode, observations.source_server,";
        sql += " observations.symbol_name, observations.anchor_time_frame,";
        sql += " observations.anchor_time_frame_text,";
        sql += " observations.capture_phase, observations.analysis_version,";
        sql += " observations.analysis_input_hash,";
        sql += " observations.anchor_bar_time,";
        sql += " observations.anchor_bar_time_text,";
        sql += " observations.anchor_jst_time,";
        sql += " observations.anchor_jst_time_text,";
        sql += " " + spreadAvailableExpression + ",";
        sql += " " + spreadPipsExpression + ",";
        sql += " " + pipSizeExpression + ",";
        sql += " " + pipSizeSourceExpression + ",";
        sql += " observations.snapshot_hash, observations.time_frame_count,";
        sql += " CASE WHEN w1.id IS NOT NULL AND d1.id IS NOT NULL ";
        sql += "AND h4.id IS NOT NULL AND h1.id IS NOT NULL ";
        sql += "THEN 1 ELSE 0 END,";
        sql += " CASE WHEN w1.id IS NULL THEN 0 ELSE 1 END,";
        sql += " COALESCE(w1.is_buy, -1),";
        sql += " CASE WHEN d1.id IS NULL THEN 0 ELSE 1 END,";
        sql += " COALESCE(d1.is_buy, -1),";
        sql += " CASE WHEN h4.id IS NULL THEN 0 ELSE 1 END,";
        sql += " COALESCE(h4.is_buy, -1),";
        sql += " COALESCE(h4.is_ema200_buy, -1),";
        sql += " COALESCE(h4.is_ema200_sell, -1),";
        sql += " CASE WHEN h1.id IS NULL THEN 0 ELSE 1 END,";
        sql += " COALESCE(h1.is_buy, -1),";
        sql += " COALESCE(h1.is_ema200_buy, -1),";
        sql += " COALESCE(h1.is_ema200_sell, -1),";
        sql += " COALESCE(h1.current_open, 0.0),";
        sql += " COALESCE(h1.previous_open, 0.0),";
        sql += " COALESCE(h1.previous_high, 0.0),";
        sql += " COALESCE(h1.previous_low, 0.0),";
        sql += " COALESCE(h1.previous_close, 0.0),";
        sql += " CASE WHEN h1.id IS NOT NULL AND h1.atr14_pips > 0 ";
        sql += "THEN 1 ELSE 0 END,";
        sql += " CASE WHEN h1.id IS NOT NULL AND h1.atr14_pips > 0 ";
        sql += "THEN h1.atr14_pips ELSE 0.0 END,";
        sql += " " + fullAlignmentExpression + " ";
        sql += "FROM zigzag_elliot_observations AS observations ";
        sql += "LEFT JOIN zigzag_elliot_observation_timeframes AS w1 ";
        sql += "ON w1.observation_id = observations.id ";
        sql += "AND w1.time_frame_order = 1 ";
        sql += "LEFT JOIN zigzag_elliot_observation_timeframes AS d1 ";
        sql += "ON d1.observation_id = observations.id ";
        sql += "AND d1.time_frame_order = 2 ";
        sql += "LEFT JOIN zigzag_elliot_observation_timeframes AS h4 ";
        sql += "ON h4.observation_id = observations.id ";
        sql += "AND h4.time_frame_order = 3 ";
        sql += "LEFT JOIN zigzag_elliot_observation_timeframes AS h1 ";
        sql += "ON h1.observation_id = observations.id ";
        sql += "AND h1.time_frame_order = 4 ";

        return sql;
    }

    /**
     * Stream検索パラメーターをSQLへ設定する。
     *
     * @param fromRequestHandle SQLリクエストハンドル。
     * @param fromStream 設定対象Stream。
     * @param fromMethodName 呼び出し元メソッド名。
     * @return すべてのパラメーター設定に成功した場合true。
     */
    bool bindStream(
        const int fromRequestHandle,
        ZigZagElliotH1StudyStreamKey &fromStream,
        const string fromMethodName
    ) {
        ResetLastError();
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromStream.runId);

        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                1,
                fromStream.sourceMode
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                2,
                fromStream.sourceServer
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                3,
                fromStream.symbolName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                4,
                fromStream.anchorTimeFrame
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                5,
                fromStream.capturePhase
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                6,
                fromStream.analysisVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                7,
                fromStream.analysisInputHash
            );
        }

        if (isBound) {
            return true;
        }

        this.logBindError(fromMethodName, GetLastError());

        return false;
    }

    /**
     * Source Run情報が最低限の整合性を満たすか判定する。
     *
     * @param fromInfo 判定対象。
     * @return 利用可能な場合true。
     */
    bool isSourceRunInfoValid(
        ZigZagElliotH1StudySourceRunInfo &fromInfo
    ) {
        return fromInfo.runId > 0
            && fromInfo.runUid != ""
            && fromInfo.schemaVersion > 0
            && fromInfo.sourceMode != ""
            && fromInfo.source != ""
            && fromInfo.programName != ""
            && fromInfo.strategy != ""
            && fromInfo.sourceServer != ""
            && fromInfo.status != "";
    }

    /**
     * Streamキーが検索に利用可能か判定する。
     *
     * @param fromStream 判定対象。
     * @return 利用可能な場合true。
     */
    bool isStreamKeyValid(
        ZigZagElliotH1StudyStreamKey &fromStream
    ) {
        return fromStream.runId > 0
            && fromStream.sourceMode != ""
            && fromStream.sourceServer != ""
            && fromStream.symbolName != ""
            && fromStream.anchorTimeFrame > 0
            && fromStream.capturePhase != ""
            && fromStream.analysisVersion != "";
    }

    /**
     * Observation行が要求Streamと一致するか判定する。
     *
     * 不完全な子時間足は有効な読取結果として許可する。
     *
     * @param fromRow 判定対象行。
     * @param fromStream 要求Stream。
     * @return 親行と取得単位が利用可能な場合true。
     */
    bool isObservationRowValid(
        ZigZagElliotH1StudyObservationRow &fromRow,
        ZigZagElliotH1StudyStreamKey &fromStream
    ) {
        if (fromRow.observationId <= 0
                || fromRow.runId != fromStream.runId
                || fromRow.sourceMode != fromStream.sourceMode
                || fromRow.sourceServer != fromStream.sourceServer
                || fromRow.symbolName != fromStream.symbolName
                || fromRow.anchorTimeFrame != fromStream.anchorTimeFrame
                || fromRow.capturePhase != fromStream.capturePhase
                || fromRow.analysisVersion != fromStream.analysisVersion
                || fromRow.analysisInputHash != fromStream.analysisInputHash
                || fromRow.anchorBarTime <= 0
                || fromRow.anchorJstTime <= 0
                || fromRow.snapshotHash == ""
                || fromRow.timeFrameCount <= 0
                || fromRow.pipSize <= 0.0
                || (fromRow.pipSizeSource != "SOURCE_DB"
                    && fromRow.pipSizeSource != "SYMBOL_RULE_V1")) {
            return false;
        }

        if (fromRow.isSpreadAvailable != 0
                && fromRow.isSpreadAvailable != 1) {
            return false;
        }

        if (fromRow.isSpreadAvailable == 1 && fromRow.spreadPips < 0.0) {
            return false;
        }

        return true;
    }

    /**
     * Run IDを使用する検索を開始可能か判定する。
     *
     * @param fromRunId 検索対象Run ID。
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 検索可能な場合true。
     */
    bool isRunSearchReady(
        const long fromRunId,
        const string fromMethodName
    ) {
        if (!this.isDatabaseReady(fromMethodName)) {
            return false;
        }

        if (fromRunId > 0) {
            return true;
        }

        this.logger.error(
            fromMethodName,
            "run ID must be greater than zero."
        );

        return false;
    }

    /**
     * データベースハンドルとスキーマ確認結果を検証する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 検索可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(
                fromMethodName,
                "databaseHandle is INVALID_HANDLE."
            );

            return false;
        }

        if (!this.schemaInspectionSucceeded) {
            this.logger.error(
                fromMethodName,
                "Observation schema inspection failed."
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
            StringFormat(
                "DatabasePrepare failed. error=%d",
                GetLastError()
            )
        );
    }

    /**
     * SQLパラメーター設定失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromErrorCode エラーコード。
     */
    void logBindError(
        const string fromMethodName,
        const int fromErrorCode
    ) {
        this.logger.error(
            fromMethodName,
            StringFormat(
                "DatabaseBind failed. error=%d",
                fromErrorCode
            )
        );
    }

    /**
     * SQL結果読取失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromErrorCode エラーコード。
     */
    void logReadError(
        const string fromMethodName,
        const int fromErrorCode
    ) {
        this.logger.error(
            fromMethodName,
            StringFormat(
                "DatabaseReadBind failed. error=%d",
                fromErrorCode
            )
        );
    }

    /**
     * 配列拡張失敗を記録する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromRequestedSize 要求した要素数。
     */
    void logArrayResizeError(
        const string fromMethodName,
        const int fromRequestedSize
    ) {
        this.logger.error(
            fromMethodName,
            StringFormat(
                "ArrayResize failed. requested=%d",
                fromRequestedSize
            )
        );
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_QUERY_SERVICE_MQH
