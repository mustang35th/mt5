//+------------------------------------------------------------------+
//|                                      CurrencyStrengthDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_DAO_MQH
#define MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_DAO_MQH

#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 通貨強弱の集計履歴・票内訳・最終結果をSQLiteへ保存するDAO。
 */
class CurrencyStrengthDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    CurrencyStrengthDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 通貨強弱のテーブル、インデックス、確認用ビューを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTables() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (!this.executeSql(
            "PRAGMA foreign_keys = ON",
            "foreign key setting"
        )) {
            return false;
        }

        if (!this.isForeignKeyEnabled()) {
            return false;
        }

        if (!this.createRunTable()) {
            return false;
        }

        if (!this.createPairVoteTable()) {
            return false;
        }

        if (!this.createResultTable()) {
            return false;
        }

        if (!this.createIndexes()) {
            return false;
        }

        if (!this.createContributionsView()) {
            return false;
        }

        this.logger.info(__FUNCTION__, "Currency strength database objects are ready.");

        return true;
    }

    /**
     * 1回分の集計、票内訳、最終結果を1トランザクションで保存する。
     *
     * 保存成功時は集計IDをfromRunEntity.idへ設定する。
     *
     * @param fromRunEntity 集計エンティティ。
     * @param fromVoteEntities 票内訳エンティティ配列。
     * @param fromResultEntities 最終結果エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool saveSnapshot(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromRunEntity.id = 0;
        fromRunEntity.voteCount = ArraySize(fromVoteEntities);

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

        bool isSaved = this.insertRun(fromRunEntity);
        long runId = 0;

        if (isSaved) {
            isSaved = this.getLastInsertId(runId);
        }

        if (isSaved) {
            fromRunEntity.id = runId;
            this.setVoteRunIds(runId, fromVoteEntities);
            this.setResultRunIds(runId, fromResultEntities);
            isSaved = this.insertPairVotes(fromVoteEntities);
        }

        if (isSaved) {
            isSaved = this.insertResults(fromResultEntities);
        }

        if (!isSaved) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromRunEntity,
                fromVoteEntities,
                fromResultEntities
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(this.databaseHandle)) {
            int commitErrorCode = GetLastError();
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionCommit failed. error=%d",
                    commitErrorCode
                )
            );
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromRunEntity,
                fromVoteEntities,
                fromResultEntities
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Snapshot saved. runId=%I64d votes=%d results=%d",
                fromRunEntity.id,
                ArraySize(fromVoteEntities),
                ArraySize(fromResultEntities)
            )
        );

        return true;
    }

    /**
     * 指定時刻より古い集計を削除する。
     *
     * 外部キーのCASCADEにより、関連する票内訳と最終結果も削除する。
     *
     * @param fromCalculatedAt 削除対象を判定する集計時刻。
     * @return 削除処理に成功した場合はtrue。
     */
    bool deleteRunsBefore(const datetime fromCalculatedAt) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "DELETE FROM currency_strength_runs ";
        sql += "WHERE calculated_at < ?1";

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

        if (!DatabaseBind(requestHandle, 0, fromCalculatedAt)) {
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
            "delete old runs"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 集計テーブルを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createRunTable() {
        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_runs (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "calculated_at INTEGER NOT NULL,";
        sql += "m15_bar_time INTEGER NOT NULL,";
        sql += "calculation_version TEXT NOT NULL,";
        sql += "source_server TEXT NOT NULL,";
        sql += "source_login INTEGER NOT NULL,";
        sql += "source_chart_id INTEGER NOT NULL,";
        sql += "expected_pair_count INTEGER NOT NULL,";
        sql += "valid_pair_count INTEGER NOT NULL,";
        sql += "vote_count INTEGER NOT NULL,";
        sql += "is_complete INTEGER NOT NULL";
        sql += ")";

        return this.executeSql(sql, "currency_strength_runs table");
    }

    /**
     * 票内訳テーブルを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createPairVoteTable() {
        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_pair_votes (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "pair_order INTEGER NOT NULL,";
        sql += "time_frame_order INTEGER NOT NULL,";
        sql += "canonical_symbol_name TEXT NOT NULL,";
        sql += "resolved_symbol_name TEXT NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "time_frame_text TEXT NOT NULL,";
        sql += "bar_time INTEGER NOT NULL,";
        sql += "bar_time_text TEXT NOT NULL,";
        sql += "base_currency TEXT NOT NULL,";
        sql += "quote_currency TEXT NOT NULL,";
        sql += "is_buy INTEGER NOT NULL CHECK(is_buy IN (0, 1)),";
        sql += "oscillator_count INTEGER NOT NULL,";
        sql += "base_score INTEGER NOT NULL CHECK(base_score IN (-1, 1)),";
        sql += "base_score_after INTEGER NOT NULL,";
        sql += "quote_score_after INTEGER NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, pair_order, time_frame_order)";
        sql += ")";

        if (!this.executeSql(sql, "currency_strength_pair_votes table")) {
            return false;
        }

        return this.migratePairVoteTextColumns();
    }

    /**
     * 既存の票内訳テーブルへ表示用文字列列を追加して値を補完する。
     *
     * @return 列追加と既存値の補完に成功した場合はtrue。
     */
    bool migratePairVoteTextColumns() {
        if (!this.ensurePairVoteTextColumn("time_frame_text")) {
            return false;
        }

        if (!this.ensurePairVoteTextColumn("bar_time_text")) {
            return false;
        }

        string sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET time_frame_text = CASE time_frame ";
        sql += StringFormat("WHEN %d THEN 'D1' ", (int)PERIOD_D1);
        sql += StringFormat("WHEN %d THEN 'H4' ", (int)PERIOD_H4);
        sql += StringFormat("WHEN %d THEN 'H1' ", (int)PERIOD_H1);
        sql += StringFormat("WHEN %d THEN 'M15' ", (int)PERIOD_M15);
        sql += "ELSE CAST(time_frame AS TEXT) END ";
        sql += "WHERE time_frame_text = ''";

        if (!this.executeSql(sql, "pair vote time frame text migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_pair_votes ";
        sql += "SET bar_time_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', bar_time, 'unixepoch') ";
        sql += "WHERE bar_time_text = ''";

        return this.executeSql(sql, "pair vote bar time text migration");
    }

    /**
     * 票内訳テーブルに表示用文字列列が存在することを保証する。
     *
     * @param fromColumnName 確認・追加する列名。
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool ensurePairVoteTextColumn(const string fromColumnName) {
        bool hasColumn = false;

        if (!this.hasPairVoteColumn(fromColumnName, hasColumn)) {
            return false;
        }

        if (hasColumn) {
            return true;
        }

        string sql = "ALTER TABLE currency_strength_pair_votes ADD COLUMN ";
        sql += fromColumnName;
        sql += " TEXT NOT NULL DEFAULT ''";

        return this.executeSql(
            sql,
            StringFormat("currency strength pair vote column %s", fromColumnName)
        );
    }

    /**
     * 票内訳テーブルに指定列が存在するか確認する。
     *
     * @param fromColumnName 確認する列名。
     * @param fromHasColumn 列が存在する場合にtrueを設定する。
     * @return テーブル情報の取得に成功した場合はtrue。
     */
    bool hasPairVoteColumn(
        const string fromColumnName,
        bool &fromHasColumn
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(currency_strength_pair_votes)"
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

                if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                    this.logger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseRead failed. error=%d",
                            readErrorCode
                        )
                    );

                    return false;
                }

                return true;
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

            if (columnName == fromColumnName) {
                fromHasColumn = true;
                DatabaseFinalize(requestHandle);

                return true;
            }
        }
    }

    /**
     * 通貨別集計結果テーブルを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createResultTable() {
        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_results (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "currency_name TEXT NOT NULL,";
        sql += "d1_score INTEGER NOT NULL,";
        sql += "h4_score INTEGER NOT NULL,";
        sql += "h1_score INTEGER NOT NULL,";
        sql += "m15_score INTEGER NOT NULL,";
        sql += "total_score INTEGER NOT NULL,";
        sql += "d1_sample_count INTEGER NOT NULL,";
        sql += "h4_sample_count INTEGER NOT NULL,";
        sql += "h1_sample_count INTEGER NOT NULL,";
        sql += "m15_sample_count INTEGER NOT NULL,";
        sql += "total_sample_count INTEGER NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, currency_name)";
        sql += ")";

        return this.executeSql(sql, "currency_strength_results table");
    }

    /**
     * 履歴確認用インデックスを作成する。
     *
     * @return 全インデックスの作成または存在確認に成功した場合はtrue。
     */
    bool createIndexes() {
        string sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_runs_calculated_at ";
        sql += "ON currency_strength_runs(calculated_at)";

        if (!this.executeSql(sql, "currency strength run index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_votes_run_order ";
        sql += "ON currency_strength_pair_votes(";
        sql += "run_id, pair_order, time_frame_order";
        sql += ")";

        if (!this.executeSql(sql, "currency strength vote index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_results_run_currency ";
        sql += "ON currency_strength_results(run_id, currency_name)";

        return this.executeSql(sql, "currency strength result index");
    }

    /**
     * 基軸・決済通貨の票を1通貨1行へ展開する確認用ビューを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createContributionsView() {
        if (!this.executeSql(
            "DROP VIEW IF EXISTS currency_strength_contributions",
            "drop currency_strength_contributions view"
        )) {
            return false;
        }

        string sql = "CREATE VIEW currency_strength_contributions AS ";
        sql += "SELECT v.id AS vote_id,";
        sql += "v.run_id AS run_id,";
        sql += "r.calculated_at AS calculated_at,";
        sql += "r.m15_bar_time AS m15_bar_time,";
        sql += "v.pair_order AS pair_order,";
        sql += "v.time_frame_order AS time_frame_order,";
        sql += "v.canonical_symbol_name AS canonical_symbol_name,";
        sql += "v.resolved_symbol_name AS resolved_symbol_name,";
        sql += "v.time_frame AS time_frame,";
        sql += "v.time_frame_text AS time_frame_text,";
        sql += "v.bar_time AS bar_time,";
        sql += "v.bar_time_text AS bar_time_text,";
        sql += "'BASE' AS currency_side,";
        sql += "v.base_currency AS currency_name,";
        sql += "v.base_score AS score,";
        sql += "v.base_score_after AS score_after,";
        sql += "v.is_buy AS is_buy,";
        sql += "v.oscillator_count AS oscillator_count ";
        sql += "FROM currency_strength_pair_votes v ";
        sql += "INNER JOIN currency_strength_runs r ON r.id = v.run_id ";
        sql += "UNION ALL ";
        sql += "SELECT v.id AS vote_id,";
        sql += "v.run_id AS run_id,";
        sql += "r.calculated_at AS calculated_at,";
        sql += "r.m15_bar_time AS m15_bar_time,";
        sql += "v.pair_order AS pair_order,";
        sql += "v.time_frame_order AS time_frame_order,";
        sql += "v.canonical_symbol_name AS canonical_symbol_name,";
        sql += "v.resolved_symbol_name AS resolved_symbol_name,";
        sql += "v.time_frame AS time_frame,";
        sql += "v.time_frame_text AS time_frame_text,";
        sql += "v.bar_time AS bar_time,";
        sql += "v.bar_time_text AS bar_time_text,";
        sql += "'QUOTE' AS currency_side,";
        sql += "v.quote_currency AS currency_name,";
        sql += "(0 - v.base_score) AS score,";
        sql += "v.quote_score_after AS score_after,";
        sql += "v.is_buy AS is_buy,";
        sql += "v.oscillator_count AS oscillator_count ";
        sql += "FROM currency_strength_pair_votes v ";
        sql += "INNER JOIN currency_strength_runs r ON r.id = v.run_id";

        return this.executeSql(sql, "currency_strength_contributions view");
    }

    /**
     * 集計レコードを保存する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insertRun(CurrencyStrengthRunEntity &fromEntity) {
        string sql = "INSERT INTO currency_strength_runs (";
        sql += "calculated_at, m15_bar_time, calculation_version, source_server,";
        sql += " source_login, source_chart_id, expected_pair_count,";
        sql += " valid_pair_count, vote_count, is_complete";
        sql += ") VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)";

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
            "insert run"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

    /**
     * 票内訳レコードを1つの準備済みリクエストで保存する。
     *
     * @param fromEntities 保存対象エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool insertPairVotes(CurrencyStrengthPairVoteEntity &fromEntities[]) {
        int entityCount = ArraySize(fromEntities);

        if (entityCount == 0) {
            return true;
        }

        string sql = "INSERT INTO currency_strength_pair_votes (";
        sql += "run_id, pair_order, time_frame_order, canonical_symbol_name,";
        sql += " resolved_symbol_name, time_frame, time_frame_text, bar_time,";
        sql += " bar_time_text, base_currency, quote_currency, is_buy,";
        sql += " oscillator_count, base_score, base_score_after,";
        sql += " quote_score_after";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,";
        sql += " ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16";
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

        for (int i = 0; i < entityCount; i++) {
            if (i > 0) {
                ResetLastError();

                if (!DatabaseReset(requestHandle)) {
                    int resetErrorCode = GetLastError();
                    DatabaseFinalize(requestHandle);
                    this.logger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseReset failed. index=%d error=%d",
                            i,
                            resetErrorCode
                        )
                    );

                    return false;
                }
            }

            ResetLastError();

            if (!this.bindPairVote(requestHandle, fromEntities[i])) {
                int bindErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseBind failed. index=%d error=%d",
                        i,
                        bindErrorCode
                    )
                );

                return false;
            }

            if (!this.executeRequest(
                requestHandle,
                __FUNCTION__,
                StringFormat("insert pair vote index=%d", i)
            )) {
                DatabaseFinalize(requestHandle);

                return false;
            }
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 通貨別集計結果レコードを1つの準備済みリクエストで保存する。
     *
     * @param fromEntities 保存対象エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool insertResults(CurrencyStrengthResultEntity &fromEntities[]) {
        int entityCount = ArraySize(fromEntities);

        if (entityCount == 0) {
            return true;
        }

        string sql = "INSERT INTO currency_strength_results (";
        sql += "run_id, currency_name, d1_score, h4_score, h1_score, m15_score,";
        sql += " total_score, d1_sample_count, h4_sample_count, h1_sample_count,";
        sql += " m15_sample_count, total_sample_count";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12";
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

        for (int i = 0; i < entityCount; i++) {
            if (i > 0) {
                ResetLastError();

                if (!DatabaseReset(requestHandle)) {
                    int resetErrorCode = GetLastError();
                    DatabaseFinalize(requestHandle);
                    this.logger.error(
                        __FUNCTION__,
                        StringFormat(
                            "DatabaseReset failed. index=%d error=%d",
                            i,
                            resetErrorCode
                        )
                    );

                    return false;
                }
            }

            ResetLastError();

            if (!this.bindResult(requestHandle, fromEntities[i])) {
                int bindErrorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseBind failed. index=%d error=%d",
                        i,
                        bindErrorCode
                    )
                );

                return false;
            }

            if (!this.executeRequest(
                requestHandle,
                __FUNCTION__,
                StringFormat("insert result index=%d", i)
            )) {
                DatabaseFinalize(requestHandle);

                return false;
            }
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 集計レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bindRun(
        const int fromRequestHandle,
        CurrencyStrengthRunEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(
            fromRequestHandle,
            0,
            fromEntity.calculatedAt
        );

        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                1,
                fromEntity.m15BarTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                2,
                fromEntity.calculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                3,
                fromEntity.sourceServer
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 4, fromEntity.sourceLogin);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 5, fromEntity.sourceChartId);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                6,
                fromEntity.expectedPairCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                7,
                fromEntity.validPairCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 8, fromEntity.voteCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 9, fromEntity.isComplete);
        }

        return isBound;
    }

    /**
     * 票内訳レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bindPairVote(
        const int fromRequestHandle,
        CurrencyStrengthPairVoteEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 1, fromEntity.pairOrder);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                2,
                fromEntity.timeFrameOrder
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                3,
                fromEntity.canonicalSymbolName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                4,
                fromEntity.resolvedSymbolName
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 5, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                6,
                fromEntity.timeFrameText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 7, fromEntity.barTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                8,
                fromEntity.barTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 9, fromEntity.baseCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 10, fromEntity.quoteCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 11, fromEntity.isBuy);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                12,
                fromEntity.oscillatorCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 13, fromEntity.baseScore);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                14,
                fromEntity.baseScoreAfter
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                15,
                fromEntity.quoteScoreAfter
            );
        }

        return isBound;
    }

    /**
     * 通貨別集計結果レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bindResult(
        const int fromRequestHandle,
        CurrencyStrengthResultEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 1, fromEntity.currencyName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 2, fromEntity.d1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 3, fromEntity.h4Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 4, fromEntity.h1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 5, fromEntity.m15Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 6, fromEntity.totalScore);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                7,
                fromEntity.d1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                8,
                fromEntity.h4SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                9,
                fromEntity.h1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                10,
                fromEntity.m15SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                11,
                fromEntity.totalSampleCount
            );
        }

        return isBound;
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
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
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

        // INSERTとDELETEは結果行を返さないため正常時もNO_MORE_DATAとなる
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
     * SQLiteの外部キー制約が有効か確認する。
     *
     * @return 外部キー制約が有効な場合true。
     */
    bool isForeignKeyEnabled() {
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
                StringFormat(
                    "DatabaseColumnInteger failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (isEnabled != 1) {
            this.logger.error(__FUNCTION__, "foreign key setting is disabled.");

            return false;
        }

        return true;
    }

    /**
     * 票内訳配列へ集計IDを設定する。
     *
     * @param fromRunId 集計ID。
     * @param fromEntities 設定対象エンティティ配列。
     */
    void setVoteRunIds(
        const long fromRunId,
        CurrencyStrengthPairVoteEntity &fromEntities[]
    ) {
        int entityCount = ArraySize(fromEntities);

        for (int i = 0; i < entityCount; i++) {
            fromEntities[i].runId = fromRunId;
        }
    }

    /**
     * 通貨別結果配列へ集計IDを設定する。
     *
     * @param fromRunId 集計ID。
     * @param fromEntities 設定対象エンティティ配列。
     */
    void setResultRunIds(
        const long fromRunId,
        CurrencyStrengthResultEntity &fromEntities[]
    ) {
        int entityCount = ArraySize(fromEntities);

        for (int i = 0; i < entityCount; i++) {
            fromEntities[i].runId = fromRunId;
        }
    }

    /**
     * 保存失敗時に集計IDをクリアする。
     *
     * @param fromRunEntity 集計エンティティ。
     * @param fromVoteEntities 票内訳エンティティ配列。
     * @param fromResultEntities 最終結果エンティティ配列。
     */
    void clearSnapshotIds(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        fromRunEntity.id = 0;
        this.setVoteRunIds(0, fromVoteEntities);
        this.setResultRunIds(0, fromResultEntities);
    }

    /**
     * 実行中のトランザクションをロールバックする。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     */
    void rollbackTransaction(const string fromMethodName) {
        ResetLastError();

        if (!DatabaseTransactionRollback(this.databaseHandle)) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseTransactionRollback failed. error=%d",
                    GetLastError()
                )
            );
        }
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

#endif // MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_DAO_MQH
