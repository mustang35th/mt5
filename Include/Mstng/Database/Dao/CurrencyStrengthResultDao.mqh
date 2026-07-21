//+------------------------------------------------------------------+
//|                           CurrencyStrengthResultDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH
#define MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH

#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankInfo.mqh>

/**
 * 通貨単位の通貨強弱集計結果をSQLiteへ保存・参照するDAO。
 */
class CurrencyStrengthResultDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    CurrencyStrengthResultDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 通貨別集計結果テーブルとインデックスを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS currency_strength_results (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "run_id INTEGER NOT NULL,";
        sql += "currency_name TEXT NOT NULL,";
        sql += "total_score INTEGER NOT NULL,";
        sql += "total_sample_count INTEGER NOT NULL,";
        sql += "long_medium_term_average_score REAL NOT NULL,";
        sql += "long_medium_term_average_rank INTEGER NOT NULL,";
        sql += "medium_short_term_average_score REAL NOT NULL,";
        sql += "medium_short_term_average_rank INTEGER NOT NULL,";
        sql += "long_term_average_score REAL NOT NULL,";
        sql += "long_term_average_rank INTEGER NOT NULL,";
        sql += "medium_term_average_score REAL NOT NULL,";
        sql += "medium_term_average_rank INTEGER NOT NULL,";
        sql += "short_term_average_score REAL NOT NULL,";
        sql += "short_term_average_rank INTEGER NOT NULL,";
        sql += "mn1_score INTEGER NOT NULL,";
        sql += "w1_score INTEGER NOT NULL,";
        sql += "d1_score INTEGER NOT NULL,";
        sql += "h4_score INTEGER NOT NULL,";
        sql += "h1_score INTEGER NOT NULL,";
        sql += "m15_score INTEGER NOT NULL,";
        sql += "m5_score INTEGER NOT NULL,";
        sql += "mn1_sample_count INTEGER NOT NULL,";
        sql += "w1_sample_count INTEGER NOT NULL,";
        sql += "d1_sample_count INTEGER NOT NULL,";
        sql += "h4_sample_count INTEGER NOT NULL,";
        sql += "h1_sample_count INTEGER NOT NULL,";
        sql += "m15_sample_count INTEGER NOT NULL,";
        sql += "m5_sample_count INTEGER NOT NULL,";
        sql += "updated_at INTEGER NOT NULL,";
        sql += "updated_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ";
        sql += "ON DELETE CASCADE,";
        sql += "UNIQUE(run_id, currency_name)";
        sql += ")";

        if (!this.executeSql(sql, "currency_strength_results table")) {
            return false;
        }

        if (!this.migrateTimeFrameColumns()) {
            return false;
        }

        if (!this.migrateAverageScoreColumns()) {
            return false;
        }

        if (!this.migrateAverageRankColumns()) {
            return false;
        }

        if (!this.migrateUpdatedAtColumns()) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_currency_strength_results_run_currency ";
        sql += "ON currency_strength_results(run_id, currency_name)";

        if (!this.executeSql(sql, "currency strength result index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "currency_strength_results table and index are ready."
        );

        return true;
    }

    /**
     * 通貨別集計結果レコードを1つの準備済みリクエストで保存する。
     *
     * @param fromEntities 保存対象エンティティ配列。
     * @return 全レコードの保存に成功した場合はtrue。
     */
    bool insertAll(CurrencyStrengthResultEntity &fromEntities[]) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        int entityCount = ArraySize(fromEntities);

        if (entityCount == 0) {
            return true;
        }

        string sql = "INSERT INTO currency_strength_results (";
        sql += "run_id, currency_name, total_score, total_sample_count,";
        sql += " long_medium_term_average_score, long_medium_term_average_rank,";
        sql += " medium_short_term_average_score, medium_short_term_average_rank,";
        sql += " long_term_average_score, long_term_average_rank,";
        sql += " medium_term_average_score, medium_term_average_rank,";
        sql += " short_term_average_score, short_term_average_rank,";
        sql += " mn1_score, w1_score, d1_score, h4_score, h1_score,";
        sql += " m15_score, m5_score, mn1_sample_count, w1_sample_count,";
        sql += " d1_sample_count, h4_sample_count, h1_sample_count,";
        sql += " m15_sample_count, m5_sample_count,";
        sql += " updated_at, updated_at_text";
        sql += ") VALUES (";
        sql += "?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,";
        sql += " ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23,";
        sql += " ?24, ?25, ?26, ?27, ?28, ?29, ?30";
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

            if (!this.bindEntity(requestHandle, fromEntities[i])) {
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
     * 指定した集計IDの通貨別結果をすべて削除する。
     *
     * @param fromRunId 削除対象の集計ID。
     * @return 削除処理に成功した場合true。
     */
    bool deleteByRunId(const long fromRunId) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "DELETE FROM currency_strength_results ";
        sql += "WHERE run_id = ?1";

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

        if (!DatabaseBind(requestHandle, 0, fromRunId)) {
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
            "delete results by run id"
        );
        DatabaseFinalize(requestHandle);

        return isExecuted;
    }

    /**
     * 指定時刻以前の最新完全集計から通貨ペアの順位を取得する。
     *
     * 検索処理に成功して対象レコードが存在しない場合もtrueを返し、
     * fromIsFoundへfalseを設定する。
     *
     * @param fromTargetM5BarTime 検索上限となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     * @param fromIsFound 対象レコードを取得した場合true。
     * @return 検索処理に成功した場合true。
     */
    bool findLatestPairRanksAtOrBefore(
        const datetime fromTargetM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthPairRankInfo &fromInfo,
        bool &fromIsFound
    ) {
        fromInfo.reset();
        fromIsFound = false;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromTargetM5BarTime <= 0
                || fromCalculationVersion == ""
                || fromSourceMode == ""
                || fromBaseCurrency == ""
                || fromQuoteCurrency == "") {
            this.logger.error(__FUNCTION__, "search condition is invalid.");

            return false;
        }

        string sql = "SELECT ";
        sql += "runs.id, runs.m5_bar_time, runs.m5_bar_time_text,";
        sql += " runs.updated_at,";
        sql += " base_result.currency_name,";
        sql += " base_result.long_medium_term_average_rank,";
        sql += " base_result.medium_short_term_average_rank,";
        sql += " quote_result.currency_name,";
        sql += " quote_result.long_medium_term_average_rank,";
        sql += " quote_result.medium_short_term_average_rank ";
        sql += "FROM currency_strength_runs runs ";
        sql += "INNER JOIN currency_strength_results base_result ";
        sql += "ON base_result.run_id = runs.id ";
        sql += "INNER JOIN currency_strength_results quote_result ";
        sql += "ON quote_result.run_id = runs.id ";
        sql += "WHERE base_result.currency_name = ?1 ";
        sql += "AND quote_result.currency_name = ?2 ";
        sql += "AND runs.m5_bar_time > 0 ";
        sql += "AND runs.m5_bar_time <= ?3 ";
        sql += "AND runs.calculation_version = ?4 ";
        sql += "AND runs.source_mode = ?5 ";
        sql += "AND runs.source_server = ?6 ";
        sql += "AND runs.source_login = ?7 ";
        sql += "AND runs.is_complete = 1 ";
        sql += "ORDER BY runs.m5_bar_time DESC, ";
        sql += "runs.updated_at DESC, runs.id DESC LIMIT 1";

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
        bool isBound = DatabaseBind(
            requestHandle,
            0,
            fromBaseCurrency
        );

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromQuoteCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromTargetM5BarTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                3,
                fromCalculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 4, fromSourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 5, fromSourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 6, fromSourceLogin);
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
        bool isRead = DatabaseReadBind(requestHandle, fromInfo);
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);

        if (!isRead) {
            if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseReadBind failed. error=%d",
                    readErrorCode
                )
            );

            return false;
        }

        fromIsFound = true;

        return true;
    }

    /**
     * 指定した集計IDの全通貨順位を取得する。
     *
     * 検索処理に成功して対象レコードが存在しない場合もtrueを返し、
     * fromIsFoundへfalseを設定する。
     *
     * @param fromRunId 取得対象の集計ID。
     * @param fromRanks 取得結果の格納先。
     * @param fromIsFound 対象レコードを取得した場合true。
     * @return 検索処理に成功した場合true。
     */
    bool findRanksByRunId(
        const long fromRunId,
        CurrencyStrengthRankInfo &fromRanks[],
        bool &fromIsFound
    ) {
        ArrayResize(fromRanks, 0);
        fromIsFound = false;

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromRunId <= 0) {
            this.logger.error(__FUNCTION__, "search condition is invalid.");

            return false;
        }

        string sql = "SELECT currency_name,";
        sql += " long_medium_term_average_rank,";
        sql += " medium_short_term_average_rank ";
        sql += "FROM currency_strength_results ";
        sql += "WHERE run_id = ?1 ";
        sql += "ORDER BY currency_name ASC";

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

        if (!DatabaseBind(requestHandle, 0, fromRunId)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        while (true) {
            CurrencyStrengthRankInfo rankInfo;
            rankInfo.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, rankInfo);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    fromIsFound = ArraySize(fromRanks) > 0;

                    return true;
                }

                ArrayResize(fromRanks, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseReadBind failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            int rankIndex = ArraySize(fromRanks);

            if (ArrayResize(fromRanks, rankIndex + 1, 8) != rankIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromRanks, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "ArrayResize failed. requested=%d",
                        rankIndex + 1
                    )
                );

                return false;
            }

            fromRanks[rankIndex] = rankInfo;
        }
    }

    /**
     * 指定期間の完全集計から通貨ペアの順位を時刻昇順で取得する。
     *
     * 上限超過を呼び出し元で検知できるように、対象レコードが多い場合は
     * fromMaximumPointCountより1件多く取得する。
     *
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromMaximumPointCount 呼び出し元が受け入れる最大件数。
     * @param fromPoints 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findPairRankPointsInRange(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        const int fromMaximumPointCount,
        CurrencyStrengthPairRankPoint &fromPoints[]
    ) {
        ArrayResize(fromPoints, 0);

        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        if (fromStartM5BarTime <= 0
                || fromEndM5BarTime < fromStartM5BarTime
                || fromCalculationVersion == ""
                || fromSourceMode == ""
                || fromBaseCurrency == ""
                || fromQuoteCurrency == ""
                || fromMaximumPointCount < 0) {
            this.logger.error(__FUNCTION__, "search condition is invalid.");

            return false;
        }

        string sql = "SELECT ";
        sql += "runs.id, runs.m5_bar_time, runs.updated_at,";
        sql += " runs.source_mode,";
        sql += " base_result.long_medium_term_average_rank,";
        sql += " base_result.medium_short_term_average_rank,";
        sql += " quote_result.long_medium_term_average_rank,";
        sql += " quote_result.medium_short_term_average_rank ";
        sql += "FROM currency_strength_runs runs ";
        sql += "INNER JOIN currency_strength_results base_result ";
        sql += "ON base_result.run_id = runs.id ";
        sql += "AND base_result.currency_name = ?1 ";
        sql += "INNER JOIN currency_strength_results quote_result ";
        sql += "ON quote_result.run_id = runs.id ";
        sql += "AND quote_result.currency_name = ?2 ";
        sql += "WHERE runs.m5_bar_time >= ?3 ";
        sql += "AND runs.m5_bar_time <= ?4 ";
        sql += "AND runs.m5_bar_time > 0 ";
        sql += "AND runs.calculation_version = ?5 ";
        sql += "AND runs.source_mode = ?6 ";
        sql += "AND runs.source_server = ?7 ";
        sql += "AND runs.source_login = ?8 ";
        sql += "AND runs.is_complete = 1 ";
        sql += "ORDER BY runs.m5_bar_time ASC LIMIT ?9";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        int readLimit = fromMaximumPointCount + 1;
        ResetLastError();
        bool isBound = DatabaseBind(requestHandle, 0, fromBaseCurrency);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromQuoteCurrency);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromStartM5BarTime);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 3, fromEndM5BarTime);
        }
        if (isBound) {
            isBound = DatabaseBind(
                requestHandle,
                4,
                fromCalculationVersion
            );
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 5, fromSourceMode);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 6, fromSourceServer);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 7, fromSourceLogin);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 8, readLimit);
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

        while (true) {
            CurrencyStrengthPairRankPoint point;
            point.reset();
            ResetLastError();
            bool isRead = DatabaseReadBind(requestHandle, point);
            int readErrorCode = GetLastError();

            if (!isRead) {
                DatabaseFinalize(requestHandle);

                if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }

                ArrayResize(fromPoints, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseReadBind failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            int pointIndex = ArraySize(fromPoints);

            if (ArrayResize(
                fromPoints,
                pointIndex + 1,
                readLimit
            ) != pointIndex + 1) {
                DatabaseFinalize(requestHandle);
                ArrayResize(fromPoints, 0);
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "ArrayResize failed. requested=%d",
                        pointIndex + 1
                    )
                );

                return false;
            }

            fromPoints[pointIndex] = point;
        }
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 既存の通貨別集計結果テーブルへMN1・W1・M5列を追加する。
     *
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool migrateTimeFrameColumns() {
        if (!this.ensureColumn("mn1_score", "INTEGER NOT NULL DEFAULT 0")) {
            return false;
        }

        if (!this.ensureColumn("w1_score", "INTEGER NOT NULL DEFAULT 0")) {
            return false;
        }

        if (!this.ensureColumn(
            "mn1_sample_count",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "w1_sample_count",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn("m5_score", "INTEGER NOT NULL DEFAULT 0")) {
            return false;
        }

        return this.ensureColumn(
            "m5_sample_count",
            "INTEGER NOT NULL DEFAULT 0"
        );
    }

    /**
     * 既存の通貨別集計結果テーブルへ期間別平均スコア列を追加する。
     *
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool migrateAverageScoreColumns() {
        if (!this.ensureColumn(
            "long_term_average_score",
            "REAL NOT NULL DEFAULT 0.0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "long_medium_term_average_score",
            "REAL NOT NULL DEFAULT 0.0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "medium_term_average_score",
            "REAL NOT NULL DEFAULT 0.0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "medium_short_term_average_score",
            "REAL NOT NULL DEFAULT 0.0"
        )) {
            return false;
        }

        return this.ensureColumn(
            "short_term_average_score",
            "REAL NOT NULL DEFAULT 0.0"
        );
    }

    /**
     * 既存の通貨別集計結果テーブルへ期間別平均スコア順位列を追加する。
     *
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool migrateAverageRankColumns() {
        if (!this.ensureColumn(
            "long_term_average_rank",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "long_medium_term_average_rank",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "medium_term_average_rank",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "medium_short_term_average_rank",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        return this.ensureColumn(
            "short_term_average_rank",
            "INTEGER NOT NULL DEFAULT 0"
        );
    }

    /**
     * 既存の通貨別集計結果テーブルへレコード更新時刻列を追加して値を補完する。
     *
     * @return 列追加と既存値の補完に成功した場合はtrue。
     */
    bool migrateUpdatedAtColumns() {
        if (!this.ensureColumn(
            "updated_at",
            "INTEGER NOT NULL DEFAULT 0"
        )) {
            return false;
        }

        if (!this.ensureColumn(
            "updated_at_text",
            "TEXT NOT NULL DEFAULT ''"
        )) {
            return false;
        }

        string sql = "UPDATE currency_strength_results ";
        sql += "SET updated_at = COALESCE((";
        sql += "SELECT updated_at FROM currency_strength_runs ";
        sql += "WHERE currency_strength_runs.id = ";
        sql += "currency_strength_results.run_id";
        sql += "), CAST(strftime('%s', 'now') AS INTEGER)) ";
        sql += "WHERE updated_at = 0";

        if (!this.executeSql(sql, "currency strength result updated at migration")) {
            return false;
        }

        sql = "UPDATE currency_strength_results ";
        sql += "SET updated_at_text = ";
        sql += "strftime('%Y.%m.%d %H:%M:%S', updated_at, 'unixepoch', 'localtime') ";
        sql += "WHERE updated_at_text = ''";

        return this.executeSql(
            sql,
            "currency strength result updated at text migration"
        );
    }

    /**
     * 通貨別集計結果テーブルに指定列が存在することを保証する。
     *
     * @param fromColumnName 確認・追加する列名。
     * @param fromColumnDefinition 追加する列の定義。
     * @return 列の存在確認または追加に成功した場合はtrue。
     */
    bool ensureColumn(
        const string fromColumnName,
        const string fromColumnDefinition
    ) {
        bool hasColumnValue = false;

        if (!this.hasColumn(fromColumnName, hasColumnValue)) {
            return false;
        }

        if (hasColumnValue) {
            return true;
        }

        string sql = "ALTER TABLE currency_strength_results ADD COLUMN ";
        sql += fromColumnName;
        sql += " ";
        sql += fromColumnDefinition;

        return this.executeSql(
            sql,
            StringFormat("currency strength result column %s", fromColumnName)
        );
    }

    /**
     * 通貨別集計結果テーブルに指定列が存在するか確認する。
     *
     * @param fromColumnName 確認する列名。
     * @param fromHasColumn 列が存在する場合にtrueを設定する。
     * @return テーブル情報の取得に成功した場合はtrue。
     */
    bool hasColumn(
        const string fromColumnName,
        bool &fromHasColumn
    ) {
        fromHasColumn = false;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA table_info(currency_strength_results)"
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
     * 通貨別集計結果レコードのパラメーターをバインドする。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity バインド対象エンティティ。
     * @return 全パラメーターのバインドに成功した場合はtrue。
     */
    bool bindEntity(
        const int fromRequestHandle,
        CurrencyStrengthResultEntity &fromEntity
    ) {
        bool isBound = DatabaseBind(fromRequestHandle, 0, fromEntity.runId);

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 1, fromEntity.currencyName);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 2, fromEntity.totalScore);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                3,
                fromEntity.totalSampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                4,
                fromEntity.longMediumTermAverageScore
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                5,
                fromEntity.longMediumTermAverageRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                6,
                fromEntity.mediumShortTermAverageScore
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                7,
                fromEntity.mediumShortTermAverageRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                8,
                fromEntity.longTermAverageScore
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                9,
                fromEntity.longTermAverageRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                10,
                fromEntity.mediumTermAverageScore
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                11,
                fromEntity.mediumTermAverageRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                12,
                fromEntity.shortTermAverageScore
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                13,
                fromEntity.shortTermAverageRank
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 14, fromEntity.mn1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 15, fromEntity.w1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 16, fromEntity.d1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 17, fromEntity.h4Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 18, fromEntity.h1Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 19, fromEntity.m15Score);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 20, fromEntity.m5Score);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                21,
                fromEntity.mn1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                22,
                fromEntity.w1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                23,
                fromEntity.d1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                24,
                fromEntity.h4SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                25,
                fromEntity.h1SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                26,
                fromEntity.m15SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                27,
                fromEntity.m5SampleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, 28, fromEntity.updatedAt);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                29,
                fromEntity.updatedAtText
            );
        }

        return isBound;
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

        // INSERTは結果行を返さないため正常時もNO_MORE_DATAとなる
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

#endif // MSTNG_DATABASE_DAO_CURRENCY_STRENGTH_RESULT_DAO_MQH
