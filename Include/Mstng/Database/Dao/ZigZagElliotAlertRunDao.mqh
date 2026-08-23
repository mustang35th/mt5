//+------------------------------------------------------------------+
//|                                      ZigZagElliotAlertRunDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_RUN_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_RUN_DAO_MQH

#include <Mstng\Database\Dao\ZigZagElliotAlertRunAnalysisProfileMigration.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertRunExecutionProgressMigration.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliotアラート実行情報をSQLiteへ保存するDAO。
 */
class ZigZagElliotAlertRunDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    ZigZagElliotAlertRunDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * アラート実行テーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_alert_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_uid TEXT NOT NULL,";
        sql += "schema_version INTEGER NOT NULL CHECK(schema_version > 0),";
        sql += "source_mode TEXT NOT NULL,";
        sql += "source TEXT NOT NULL,";
        sql += "program_name TEXT NOT NULL,";
        sql += "program_version TEXT NOT NULL,";
        sql += "strategy TEXT NOT NULL,";
        sql += "strategy_version TEXT NOT NULL,";
        sql += "analysis_version TEXT NOT NULL,";
        sql += "analysis_input_text TEXT NOT NULL DEFAULT '',";
        sql += "analysis_input_hash TEXT NOT NULL DEFAULT '',";
        sql += "source_server TEXT NOT NULL,";
        sql += "source_login INTEGER NOT NULL,";
        sql += "source_chart_id INTEGER NOT NULL,";
        sql += "terminal_build INTEGER NOT NULL,";
        sql += "tester_from INTEGER NOT NULL,";
        sql += "tester_to INTEGER NOT NULL,";
        sql += "tester_model TEXT NOT NULL,";
        sql += "input_text TEXT NOT NULL,";
        sql += "input_hash TEXT NOT NULL,";
        sql += "started_at INTEGER NOT NULL,";
        sql += "started_at_text TEXT NOT NULL,";
        sql += "market_started_at INTEGER NOT NULL,";
        sql += "market_started_at_text TEXT NOT NULL,";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "status TEXT NOT NULL DEFAULT 'LEGACY',";
        sql += "evaluation_started_at INTEGER NOT NULL DEFAULT 0,";
        sql += "last_completed_h1_bar_time INTEGER NOT NULL DEFAULT 0,";
        sql += "evaluated_h1_count INTEGER NOT NULL DEFAULT 0,";
        sql += "saved_alert_count INTEGER NOT NULL DEFAULT 0,";
        sql += "completed_at INTEGER NOT NULL DEFAULT 0,";
        sql += "error_text TEXT NOT NULL DEFAULT ''";
        sql += ")";

        if (!this.executeSql(sql, "zigzag_elliot_alert_runs table")) {
            return false;
        }

        if (!ZigZagElliotAlertRunAnalysisProfileMigration::execute(
                this.databaseHandle
            )) {
            return false;
        }

        if (!ZigZagElliotAlertRunExecutionProgressMigration::execute(
                this.databaseHandle
            )) {
            return false;
        }

        sql = "CREATE UNIQUE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alert_runs_run_uid ";
        sql += "ON zigzag_elliot_alert_runs(run_uid)";

        if (!this.executeSql(sql, "zigzag elliot alert run UID index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_alert_runs_started_at ";
        sql += "ON zigzag_elliot_alert_runs(started_at)";

        if (!this.executeSql(sql, "zigzag elliot alert run time index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "zigzag_elliot_alert_runs table and indexes are ready."
        );

        return true;
    }

    /**
     * アラート実行情報を保存する。
     *
     * 保存成功時は実行IDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insert(ZigZagElliotAlertRunEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromEntity.status == NULL || fromEntity.status == "") {
            fromEntity.status = "LEGACY";
        }

        if (fromEntity.errorText == NULL) {
            fromEntity.errorText = "";
        }

        fromEntity.id = 0;
        string sql = "INSERT INTO zigzag_elliot_alert_runs (";
        sql += "run_uid, schema_version, source_mode, source, program_name,";
        sql += " program_version, strategy, strategy_version, analysis_version,";
        sql += " analysis_input_text, analysis_input_hash, source_server,";
        sql += " source_login, source_chart_id, terminal_build,";
        sql += " tester_from, tester_to, tester_model, input_text, input_hash,";
        sql += " started_at, started_at_text, market_started_at,";
        sql += " market_started_at_text, created_at, created_at_text,";
        sql += " status, evaluation_started_at,";
        sql += " last_completed_h1_bar_time, evaluated_h1_count,";
        sql += " saved_alert_count, completed_at, error_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,";
        sql += " ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23,";
        sql += " ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33";
        sql += ")";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromEntity.runUid);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromEntity.schemaVersion);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromEntity.sourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 3, fromEntity.source);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 4, fromEntity.programName);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 5, fromEntity.programVersion);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 6, fromEntity.strategy);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 7, fromEntity.strategyVersion);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 8, fromEntity.analysisVersion);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 9, fromEntity.analysisInputText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 10, fromEntity.analysisInputHash);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 11, fromEntity.sourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 12, fromEntity.sourceLogin);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 13, fromEntity.sourceChartId);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 14, fromEntity.terminalBuild);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 15, fromEntity.testerFrom);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 16, fromEntity.testerTo);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 17, fromEntity.testerModel);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 18, fromEntity.inputText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 19, fromEntity.inputHash);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 20, fromEntity.startedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 21, fromEntity.startedAtText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 22, fromEntity.marketStartedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 23, fromEntity.marketStartedAtText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 24, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 25, fromEntity.createdAtText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 26, fromEntity.status);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                27,
                fromEntity.evaluationStartedAt
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                28,
                fromEntity.lastCompletedH1BarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                29,
                fromEntity.evaluatedH1Count
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                30,
                fromEntity.savedAlertCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 31, fromEntity.completedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 32, fromEntity.errorText);
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
            "insert alert run"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        return this.getLastInsertId(fromEntity.id);
    }

    /**
     * Run実行状態、進捗およびテスター再現情報を更新する。
     *
     * @param fromEntity 更新対象Runと実行進捗。
     * @return 更新処理に成功した場合true。
     */
    bool updateExecutionProgress(
        ZigZagElliotAlertRunEntity &fromEntity
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromEntity.errorText == NULL) {
            fromEntity.errorText = "";
        }

        if (fromEntity.testerModel == NULL) {
            fromEntity.testerModel = "";
        }

        if (fromEntity.id <= 0
                || fromEntity.status == ""
                || fromEntity.testerFrom < 0
                || fromEntity.testerTo < 0
                || (fromEntity.testerFrom > 0
                    && fromEntity.testerTo > 0
                    && fromEntity.testerTo < fromEntity.testerFrom)
                || fromEntity.evaluationStartedAt < 0
                || fromEntity.lastCompletedH1BarTime < 0
                || fromEntity.evaluatedH1Count < 0
                || fromEntity.savedAlertCount < 0
                || fromEntity.completedAt < 0) {
            this.logger.error(
                __FUNCTION__,
                "Run execution progress value is invalid."
            );

            return false;
        }

        string sql = "UPDATE zigzag_elliot_alert_runs SET status = ?1,";
        sql += " evaluation_started_at = ?2,";
        sql += " last_completed_h1_bar_time = ?3,";
        sql += " evaluated_h1_count = ?4, saved_alert_count = ?5,";
        sql += " completed_at = ?6, error_text = ?7,";
        sql += " tester_from = ?8, tester_to = ?9, tester_model = ?10";
        sql += " WHERE id = ?11";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromEntity.status);

        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                1,
                fromEntity.evaluationStartedAt
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                2,
                fromEntity.lastCompletedH1BarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                3,
                fromEntity.evaluatedH1Count
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                4,
                fromEntity.savedAlertCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 5, fromEntity.completedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 6, fromEntity.errorText);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 7, fromEntity.testerFrom);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 8, fromEntity.testerTo);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 9, fromEntity.testerModel);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 10, fromEntity.id);
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
            "update alert run execution progress"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

    /**
     * 実行UIDに一致する実行IDを取得する。
     *
     * 該当レコードが存在しない場合はfromRunIdへ0を設定してtrueを返す。
     *
     * @param fromRunUid 実行UID。
     * @param fromRunId 取得した実行IDの格納先。
     * @return 検索処理に成功した場合はtrue。
     */
    bool findIdByRunUid(const string fromRunUid, long &fromRunId) {
        fromRunId = 0;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "SELECT id FROM zigzag_elliot_alert_runs ";
        sql += "WHERE run_uid = ?1 ORDER BY id DESC LIMIT 1";

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

        if (!DatabaseBind(requestHandle, 0, fromRunUid)) {
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

        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

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

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_ALERT_RUN_DAO_MQH
