//+------------------------------------------------------------------+
//|                                   ZigZagElliotObservationDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_DAO_MQH

#include <Mstng\Database\Dao\ZigZagElliotObservationJstMigration.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationSpreadMigration.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliot観測本体をSQLiteへ保存するDAO。
 */
class ZigZagElliotObservationDao {
public:
    /**
     * データベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     */
    ZigZagElliotObservationDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 観測本体テーブルと検索用インデックスを作成する。
     *
     * @return 作成に成功した場合true。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS zigzag_elliot_observations (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "source_mode TEXT NOT NULL ";
        sql += "CHECK(source_mode IN ('LIVE', 'TESTER')),";
        sql += "source_server TEXT NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "anchor_time_frame INTEGER NOT NULL ";
        sql += "CHECK(anchor_time_frame > 0),";
        sql += "anchor_time_frame_text TEXT NOT NULL,";
        sql += "anchor_bar_time INTEGER NOT NULL CHECK(anchor_bar_time > 0),";
        sql += "anchor_bar_time_text TEXT NOT NULL,";
        sql += "anchor_jst_time INTEGER NOT NULL CHECK(anchor_jst_time > 0),";
        sql += "anchor_jst_time_text TEXT NOT NULL,";
        sql += "capture_phase TEXT NOT NULL ";
        sql += "CHECK(capture_phase = 'BAR_OPEN_FIRST_SUCCESS'),";
        sql += "spread_pips REAL ";
        sql += "CHECK(spread_pips IS NULL OR spread_pips >= 0),";
        sql += "analysis_version TEXT NOT NULL,";
        sql += "analysis_input_hash TEXT NOT NULL,";
        sql += "snapshot_hash TEXT NOT NULL,";
        sql += "time_frame_count INTEGER NOT NULL CHECK(time_frame_count > 0),";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES zigzag_elliot_alert_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(source_mode, source_server, symbol_name,";
        sql += " anchor_time_frame, anchor_bar_time, capture_phase,";
        sql += " analysis_version, analysis_input_hash)";
        sql += ")";

        if (!this.executeSql(sql, "zigzag_elliot_observations table")) {
            return false;
        }

        if (!ZigZagElliotObservationJstMigration::execute(
                this.databaseHandle,
                "zigzag_elliot_observations",
                "anchor_bar_time",
                "anchor_jst_time",
                "anchor_jst_time_text"
            )) {
            return false;
        }

        if (!ZigZagElliotObservationSpreadMigration::execute(
                this.databaseHandle
            )) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_run_id ";
        sql += "ON zigzag_elliot_observations(run_id)";

        if (!this.executeSql(sql, "zigzag elliot observation run index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_mode_bar ";
        sql += "ON zigzag_elliot_observations(source_mode, anchor_bar_time)";

        if (!this.executeSql(sql, "zigzag elliot observation mode bar index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_mode_jst ";
        sql += "ON zigzag_elliot_observations(source_mode, anchor_jst_time)";

        if (!this.executeSql(sql, "zigzag elliot observation mode JST index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_jst_id ";
        sql += "ON zigzag_elliot_observations(anchor_jst_time, id)";

        if (!this.executeSql(sql, "zigzag elliot observation JST ID index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_mode_symbol_bar ";
        sql += "ON zigzag_elliot_observations(";
        sql += "source_mode, symbol_name, anchor_time_frame, anchor_bar_time)";

        if (!this.executeSql(sql, "zigzag elliot observation symbol index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_mode_symbol_jst ";
        sql += "ON zigzag_elliot_observations(";
        sql += "source_mode, symbol_name, anchor_time_frame, anchor_jst_time)";

        if (!this.executeSql(
                sql,
                "zigzag elliot observation symbol JST index"
            )) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_mode_profile_jst ";
        sql += "ON zigzag_elliot_observations(";
        sql += "source_mode, analysis_input_hash, anchor_jst_time, id)";
        sql += " WHERE analysis_input_hash <> ''";

        if (!this.executeSql(
                sql,
                "zigzag elliot observation analysis profile JST index"
            )) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observations_profile_jst ";
        sql += "ON zigzag_elliot_observations(";
        sql += "analysis_input_hash, anchor_jst_time, id)";
        sql += " WHERE analysis_input_hash <> ''";

        if (!this.executeSql(
                sql,
                "zigzag elliot observation global profile JST index"
            )) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "zigzag_elliot_observations table and indexes are ready."
        );

        return true;
    }

    /**
     * 観測本体を保存し、自然キー重複時は既存行を変更しない。
     *
     * 新規保存時はIDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @param fromIsInserted 新規保存した場合trueを設定する。
     * @return SQL実行と保存有無の取得に成功した場合true。
     */
    bool insertOnConflictDoNothing(
        ZigZagElliotObservationEntity &fromEntity,
        bool &fromIsInserted
    ) {
        fromEntity.id = 0;
        fromIsInserted = false;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

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
            "insert observation"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted || !this.getChanges(fromIsInserted)) {
            return false;
        }

        if (!fromIsInserted) {
            return true;
        }

        return this.getLastInsertId(fromEntity.id);
    }

    /**
     * 観測自然キーに一致する保存済み情報を取得する。
     *
     * 該当行がない場合は出力値を初期値へ設定してtrueを返す。
     *
     * @param fromEntity 検索自然キーを保持するエンティティ。
     * @param fromObservationId 取得した観測IDの格納先。
     * @param fromRunId 取得した実行情報IDの格納先。
     * @param fromSnapshotHash 取得した内容ハッシュの格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findByNaturalKey(
        ZigZagElliotObservationEntity &fromEntity,
        long &fromObservationId,
        long &fromRunId,
        string &fromSnapshotHash
    ) {
        fromObservationId = 0;
        fromRunId = 0;
        fromSnapshotHash = "";

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "SELECT id, run_id, snapshot_hash ";
        sql += "FROM zigzag_elliot_observations WHERE source_mode = ?1 ";
        sql += "AND source_server = ?2 AND symbol_name = ?3 ";
        sql += "AND anchor_time_frame = ?4 AND anchor_bar_time = ?5 ";
        sql += "AND capture_phase = ?6 AND analysis_version = ?7 ";
        sql += "AND analysis_input_hash = ?8 LIMIT 1";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        if (!this.bindNaturalKey(requestHandle, fromEntity)) {
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

        if (!DatabaseColumnLong(requestHandle, 0, fromObservationId)
                || !DatabaseColumnLong(requestHandle, 1, fromRunId)
                || !DatabaseColumnText(requestHandle, 2, fromSnapshotHash)) {
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
     * 観測本体INSERT文を生成する。
     *
     * @return パラメーター化したINSERT文。
     */
    string buildInsertSql() {
        string sql = "INSERT INTO zigzag_elliot_observations (";
        sql += "run_id, source_mode, source_server, symbol_name,";
        sql += " anchor_time_frame, anchor_time_frame_text,";
        sql += " anchor_bar_time, anchor_bar_time_text,";
        sql += " anchor_jst_time, anchor_jst_time_text, capture_phase,";
        sql += " spread_pips, analysis_version, analysis_input_hash,";
        sql += " snapshot_hash,";
        sql += " time_frame_count, created_at, created_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,";
        sql += " ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18";
        sql += ") ON CONFLICT(";
        sql += "source_mode, source_server, symbol_name,";
        sql += " anchor_time_frame, anchor_bar_time, capture_phase,";
        sql += " analysis_version, analysis_input_hash";
        sql += ") DO NOTHING";

        return sql;
    }

    /**
     * 観測本体INSERTパラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象エンティティ。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindEntity(
        const int fromRequestHandle,
        ZigZagElliotObservationEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.runId);

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
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorTimeFrame
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorTimeFrameText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorBarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorBarTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorJstTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorJstTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.capturePhase);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.spreadPips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.analysisVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.analysisInputHash
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.snapshotHash);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.timeFrameCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.createdAtText
            );
        }

        return isBound && index == 18;
    }

    /**
     * 観測自然キーパラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 検索対象エンティティ。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindNaturalKey(
        const int fromRequestHandle,
        ZigZagElliotObservationEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(
            fromRequestHandle,
            index++,
            fromEntity.sourceMode
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.sourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorTimeFrame
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.anchorBarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.capturePhase);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.analysisVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.analysisInputHash
            );
        }

        return isBound && index == 8;
    }

    /**
     * 直前のSQLで変更された行数から新規保存有無を取得する。
     *
     * @param fromIsInserted 変更行数が1の場合trueを設定する。
     * @return 変更行数を取得できた場合true。
     */
    bool getChanges(bool &fromIsInserted) {
        fromIsInserted = false;
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

        long changedCount = 0;
        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, changedCount)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (changedCount < 0 || changedCount > 1) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("Invalid changed row count. count=%I64d", changedCount)
            );

            return false;
        }

        fromIsInserted = changedCount == 1;

        return true;
    }

    /**
     * 直前に追加したレコードIDを取得する。
     *
     * @param fromInsertId 取得したIDの格納先。
     * @return IDを取得できた場合true。
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
     * @return 実行に成功した場合true。
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
     * @return 実行に成功した場合true。
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
     * @return 利用可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_DAO_MQH
