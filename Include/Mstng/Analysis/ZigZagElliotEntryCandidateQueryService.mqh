//+------------------------------------------------------------------+
//|               ZigZagElliotEntryCandidateQueryService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_QUERY_SERVICE_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_QUERY_SERVICE_MQH

#include <Mstng\Analysis\ZigZagElliotEntryCandidate.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliot Alert DBからH1エントリー候補を読み取るサービス。
 *
 * データベースハンドルの所有権は呼び出し元が保持する。書き込みや
 * スキーマ変更を行わず、DATABASE_OPEN_READONLYで開いたハンドルを使用する。
 */
class ZigZagElliotEntryCandidateQueryService {
public:
    /**
     * 読み取り専用データベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle 読み取り専用で開いたDBハンドル。
     */
    ZigZagElliotEntryCandidateQueryService(
        const int fromDatabaseHandle
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.hasRunStatusColumn = false;
        this.runStatusColumnInspectionSucceeded = false;
        this.logger.setLevel(LOG_INFO);

        if (this.databaseHandle != INVALID_HANDLE) {
            this.runStatusColumnInspectionSucceeded =
                this.inspectRunStatusColumn();
        }
    }

    /**
     * 指定したRunのメタデータを取得する。
     *
     * レコードが存在しない場合も検索成功としてtrueを返し、
     * fromIsFoundへfalseを設定する。status列が存在する場合はLEGACYまたは
     * COMPLETEDのRunだけを取得する。
     *
     * @param fromRunId 取得対象のRun ID。
     * @param fromInfo 取得結果の格納先。
     * @param fromIsFound 対象Runを取得した場合true。
     * @return 検索処理に成功した場合true。
     */
    bool findRun(
        const long fromRunId,
        SourceRunInfo &fromInfo,
        bool &fromIsFound
    ) {
        fromInfo.reset();
        fromIsFound = false;

        if (!this.isSearchReady(fromRunId, __FUNCTION__)) {
            return false;
        }

        string sql = this.getRunSelectSql();
        sql += "WHERE runs.id = ?1 ";
        sql += this.getEligibleRunStatusCondition();
        sql += "ORDER BY runs.id DESC LIMIT 1";

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
                    "source run metadata is invalid. requestedRunId=%I64d",
                    fromRunId
                )
            );

            return false;
        }

        fromIsFound = true;

        return true;
    }

    /**
     * エントリー候補を保持する直近Run一覧を取得する。
     *
     * RunはID降順で返す。status列が存在する場合はLEGACYまたは
     * COMPLETEDのRunだけを取得する。
     *
     * @param fromLimit 最大取得件数。1～100。
     * @param fromRequireH1Open H1始値と判定時刻の一致を必須にする場合true。
     * @param fromInfos 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findRecentEligibleRuns(
        const int fromLimit,
        const bool fromRequireH1Open,
        SourceRunInfo &fromInfos[]
    ) {
        ArrayResize(fromInfos, 0);

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromLimit < 1 || fromLimit > 100) {
            this.logger.error(
                __FUNCTION__,
                "search limit must be between 1 and 100."
            );

            return false;
        }

        string sql = this.getRunSelectSql();
        sql += "WHERE runs.source_mode = 'TESTER' ";
        sql += "AND runs.source = 'ZIGZAG_ELLIOT' ";
        sql += "AND runs.strategy = 'MTF_3in3' ";
        sql += this.getEligibleRunStatusCondition();
        sql += "AND EXISTS (";
        sql += "SELECT 1 FROM zigzag_elliot_alerts AS alerts ";
        sql += "WHERE alerts.run_id = runs.id ";
        sql += "AND alerts.time_frame_text = 'H1' ";
        sql += "AND alerts.is_alert = 1 ";
        sql += "AND alerts.is_entry = 1 ";
        sql += "AND alerts.entry_result = 'ENTRY' ";
        sql += "AND alerts.is_stop_loss_available = 1 ";

        if (fromRequireH1Open) {
            sql += "AND alerts.server_time = alerts.current_bar_time ";
            sql += "AND (alerts.server_time % 60) = 0 ";
        } else {
            sql += "AND alerts.server_time >= alerts.current_bar_time ";
            sql += "AND alerts.server_time <= alerts.current_bar_time + 3540 ";
        }

        sql += ") ORDER BY runs.id DESC LIMIT ?1";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logPrepareError(__FUNCTION__);

            return false;
        }

        ResetLastError();

        if (!DatabaseBind(requestHandle, 0, fromLimit)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logBindError(__FUNCTION__, bindErrorCode);

            return false;
        }

        while (true) {
            SourceRunInfo info;
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
                    "source run metadata is invalid."
                );

                return false;
            }

            int infoIndex = ArraySize(fromInfos);

            if (ArrayResize(
                fromInfos,
                infoIndex + 1,
                fromLimit
            ) != infoIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromInfos, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "ArrayResize failed. requested=%d",
                        infoIndex + 1
                    )
                );

                return false;
            }

            fromInfos[infoIndex] = info;
        }
    }

    /**
     * 指定RunのH1エントリー候補を判定時刻昇順で取得する。
     *
     * 取得対象はアラート、エントリーおよび初期SLが利用可能な
     * ENTRYレコードに限定する。レコードがない場合は空配列でtrueを返す。
     *
     * @param fromRunId 取得対象のRun ID。
     * @param fromRequireH1Open H1始値と判定時刻の一致を必須にする場合true。
     * @param fromEntries 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findEntries(
        const long fromRunId,
        const bool fromRequireH1Open,
        EntryCandidate &fromEntries[]
    ) {
        ArrayResize(fromEntries, 0);

        if (!this.isSearchReady(fromRunId, __FUNCTION__)) {
            return false;
        }

        string sql = "SELECT alerts.id, alerts.run_id,";
        sql += " alerts.market_signal_key, alerts.server_time,";
        sql += " alerts.current_bar_time, alerts.symbol_name, alerts.side,";
        sql += " alerts.reference_price, alerts.stop_loss,";
        sql += " alerts.risk_pips, alerts.spread_pips ";
        sql += "FROM zigzag_elliot_alerts AS alerts ";
        sql += "INNER JOIN zigzag_elliot_alert_runs AS runs ";
        sql += "ON runs.id = alerts.run_id ";
        sql += "WHERE alerts.run_id = ?1 ";
        sql += this.getEligibleRunStatusCondition();
        sql += "AND alerts.time_frame_text = 'H1' ";
        sql += "AND alerts.is_alert = 1 ";
        sql += "AND alerts.is_entry = 1 ";
        sql += "AND alerts.entry_result = 'ENTRY' ";
        sql += "AND alerts.is_stop_loss_available = 1 ";

        if (fromRequireH1Open) {
            sql += "AND alerts.server_time = alerts.current_bar_time ";
            sql += "AND (alerts.server_time % 60) = 0 ";
        } else {
            sql += "AND alerts.server_time >= alerts.current_bar_time ";
            sql += "AND alerts.server_time <= alerts.current_bar_time + 3540 ";
        }

        sql += "ORDER BY alerts.server_time ASC, alerts.id ASC";

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
            EntryCandidate candidate;
            candidate.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, candidate);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                ArrayResize(fromEntries, 0);
                this.logReadError(__FUNCTION__, readErrorCode);

                return false;
            }

            if (!this.isEntryCandidateValid(candidate, fromRunId)) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromEntries, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "entry candidate is invalid. alertId=%I64d runId=%I64d",
                        candidate.alertId,
                        candidate.runId
                    )
                );

                return false;
            }

            int entryIndex = ArraySize(fromEntries);

            if (ArrayResize(
                fromEntries,
                entryIndex + 1,
                64
            ) != entryIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromEntries, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "ArrayResize failed. requested=%d",
                        entryIndex + 1
                    )
                );

                return false;
            }

            fromEntries[entryIndex] = candidate;
        }
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** Runテーブルにstatus列が存在する場合true。 */
    bool hasRunStatusColumn;

    /** Runテーブルのstatus列確認に成功した場合true。 */
    bool runStatusColumnInspectionSucceeded;

    /** ロガー。 */
    Logger logger;

    /**
     * Runテーブルのstatus列有無を確認する。
     *
     * @return テーブル情報の取得に成功した場合true。
     */
    bool inspectRunStatusColumn() {
        this.hasRunStatusColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(zigzag_elliot_alert_runs)"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
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
                        "DatabaseRead failed. error=%d",
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
                        "DatabaseColumnText failed. error=%d",
                        columnErrorCode
                    )
                );

                return false;
            }

            if (columnName == "status") {
                DatabaseFinalize(requestHandle);
                this.hasRunStatusColumn = true;

                return true;
            }
        }

        return false;
    }

    /**
     * Outcome対象Runのstatus絞り込み条件を取得する。
     *
     * @return status列がある場合はSQL条件、ない場合は空文字。
     */
    string getEligibleRunStatusCondition() {
        if (!this.hasRunStatusColumn) {
            return "";
        }

        return "AND runs.status IN ('LEGACY', 'COMPLETED') ";
    }

    /**
     * SourceRunInfoの列順にRun取得SELECTの共通部分を生成する。
     *
     * @return FROM句までを含むSELECT文。
     */
    string getRunSelectSql() {
        string sql = "SELECT runs.id, runs.run_uid, runs.schema_version,";
        sql += " runs.source_mode, runs.source, runs.program_name,";
        sql += " runs.program_version, runs.strategy,";
        sql += " runs.strategy_version, runs.analysis_version,";
        sql += " runs.source_server, runs.source_login,";
        sql += " runs.source_chart_id, runs.terminal_build,";
        sql += " runs.tester_from, runs.tester_to, runs.tester_model,";
        sql += " runs.input_text, runs.input_hash, runs.started_at,";
        sql += " runs.started_at_text, runs.market_started_at,";
        sql += " runs.market_started_at_text, runs.created_at,";
        sql += " runs.created_at_text, runs.analysis_input_text,";
        sql += " runs.analysis_input_hash ";
        sql += "FROM zigzag_elliot_alert_runs AS runs ";

        return sql;
    }

    /**
     * Runメタデータが最低限の整合性を満たすか判定する。
     *
     * @param fromInfo 判定対象。
     * @return 利用可能な場合true。
     */
    bool isSourceRunInfoValid(SourceRunInfo &fromInfo) {
        return fromInfo.runId > 0
            && fromInfo.runUid != ""
            && fromInfo.schemaVersion > 0
            && fromInfo.sourceMode != ""
            && fromInfo.source != ""
            && fromInfo.programName != ""
            && fromInfo.strategy != "";
    }

    /**
     * エントリー候補が後処理へ渡せる状態か判定する。
     *
     * @param fromCandidate 判定対象。
     * @param fromRunId 要求したRun ID。
     * @return 利用可能な場合true。
     */
    bool isEntryCandidateValid(
        EntryCandidate &fromCandidate,
        const long fromRunId
    ) {
        if (fromCandidate.alertId <= 0
                || fromCandidate.runId != fromRunId
                || fromCandidate.marketSignalKey == ""
                || fromCandidate.entryTime <= 0
                || fromCandidate.currentBarTime <= 0
                || fromCandidate.symbolName == ""
                || fromCandidate.entryPrice <= 0.0
                || fromCandidate.stopLoss <= 0.0
                || fromCandidate.riskPips <= 0.0
                || fromCandidate.spreadPips < 0.0) {
            return false;
        }

        if (fromCandidate.side == "BUY") {
            return fromCandidate.stopLoss < fromCandidate.entryPrice;
        }

        if (fromCandidate.side == "SELL") {
            return fromCandidate.stopLoss > fromCandidate.entryPrice;
        }

        return false;
    }

    /**
     * Run IDを使用する検索を開始可能か判定する。
     *
     * @param fromRunId 検索対象Run ID。
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 検索可能な場合true。
     */
    bool isSearchReady(
        const long fromRunId,
        const string fromMethodName
    ) {
        if (!this.isDatabaseReady(fromMethodName)) {
            return false;
        }

        if (fromRunId <= 0) {
            this.logger.error(
                fromMethodName,
                "run ID must be greater than zero."
            );

            return false;
        }

        return true;
    }

    /**
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(
                fromMethodName,
                "databaseHandle is INVALID_HANDLE."
            );

            return false;
        }

        if (!this.runStatusColumnInspectionSucceeded) {
            this.logger.error(
                fromMethodName,
                "Run status column inspection failed."
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
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_QUERY_SERVICE_MQH
