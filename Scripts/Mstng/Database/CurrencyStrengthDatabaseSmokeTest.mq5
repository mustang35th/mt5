//+------------------------------------------------------------------+
//|                            CurrencyStrengthDatabaseSmokeTest.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Database\Dao\CurrencyStrengthPairVoteDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Database\Service\CurrencyStrengthPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/** 動作確認用データベースファイル名。 */
input string databaseFileName = "mstng-currency-strength-smoke-test.sqlite";

/** 共有フォルダ使用有無。 */
input bool useCommonFolder = true;

/** 実行前に既存テーブルとビューを再作成する場合true。 */
input bool recreateDatabaseObjects = true;

/**
 * 通貨強弱の既存テーブルとビューを削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全オブジェクトを削除できた場合true。
 */
bool dropDatabaseObjects(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sqlList[4];
    sqlList[0] = "DROP VIEW IF EXISTS currency_strength_contributions";
    sqlList[1] = "DROP TABLE IF EXISTS currency_strength_pair_votes";
    sqlList[2] = "DROP TABLE IF EXISTS currency_strength_results";
    sqlList[3] = "DROP TABLE IF EXISTS currency_strength_runs";

    for (int i = 0; i < ArraySize(sqlList); i++) {
        ResetLastError();

        if (!DatabaseExecute(fromDatabaseHandle, sqlList[i])) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. index=%d error=%d",
                    i,
                    GetLastError()
                )
            );

            return false;
        }
    }

    return true;
}

/**
 * 通貨強弱の集計エンティティを初期化する。
 *
 * @param fromCalculatedAt 集計時刻。
 * @param fromM5BarTime M5足開始時刻。
 * @param fromEntity 初期化対象エンティティ。
 */
void initializeRunEntity(
    const datetime fromCalculatedAt,
    const datetime fromM5BarTime,
    CurrencyStrengthRunEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.calculatedAt = fromCalculatedAt;
    fromEntity.m5BarTime = fromM5BarTime;
    fromEntity.m5BarTimeText = TimeToString(
        fromM5BarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.calculationVersion = "pair-direction-raw-v6-smoke-test";
    fromEntity.sourceMode = "TESTER";
    fromEntity.sourceServer = AccountInfoString(ACCOUNT_SERVER);
    fromEntity.sourceLogin = (long)AccountInfoInteger(ACCOUNT_LOGIN);
    fromEntity.sourceChartId = ChartID();
    fromEntity.expectedPairCount = 1;
    fromEntity.validPairCount = 1;
    fromEntity.voteCount = 0;
    fromEntity.isComplete = 1;
    fromEntity.updatedAt = 0;
    fromEntity.updatedAtText = "";
}

/**
 * USDJPYの票エンティティを初期化する。
 *
 * @param fromTimeFrameOrder 時間足の集計順。
 * @param fromTimeFrame 時間足。
 * @param fromIsBuy BUY票の場合true。
 * @param fromBarTime 判定対象のバー時刻。
 * @param fromEntity 初期化対象エンティティ。
 */
void initializePairVoteEntity(
    const int fromTimeFrameOrder,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const bool fromIsBuy,
    const datetime fromBarTime,
    CurrencyStrengthPairVoteEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.runId = 0;
    fromEntity.pairOrder = 0;
    fromEntity.timeFrameOrder = fromTimeFrameOrder;
    fromEntity.canonicalSymbolName = "USDJPY";
    fromEntity.resolvedSymbolName = "USDJPY";
    fromEntity.timeFrame = (int)fromTimeFrame;
    fromEntity.timeFrameText = TimeUtil::convertTimeFrameToString(fromTimeFrame);
    fromEntity.barTime = fromBarTime;
    fromEntity.barTimeText = TimeToString(
        fromBarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.baseCurrency = "USD";
    fromEntity.quoteCurrency = "JPY";
    fromEntity.isBuy = 0;
    fromEntity.oscillatorCount = -2;
    fromEntity.baseScore = -1;

    if (fromIsBuy) {
        fromEntity.isBuy = 1;
        fromEntity.oscillatorCount = 2;
        fromEntity.baseScore = 1;
    }

    fromEntity.baseScoreAfter = fromEntity.baseScore;
    fromEntity.quoteScoreAfter = 0 - fromEntity.baseScore;
    fromEntity.updatedAt = 0;
    fromEntity.updatedAtText = "";
}

/**
 * 通貨別の集計結果エンティティを初期化する。
 *
 * @param fromCurrencyName 通貨名。
 * @param fromScore 各時間足の未正規化合計。
 * @param fromEntity 初期化対象エンティティ。
 */
void initializeResultEntity(
    const string fromCurrencyName,
    const int fromScore,
    CurrencyStrengthResultEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.runId = 0;
    fromEntity.currencyName = fromCurrencyName;
    fromEntity.mn1Score = fromScore;
    fromEntity.w1Score = fromScore;
    fromEntity.d1Score = fromScore;
    fromEntity.h4Score = fromScore;
    fromEntity.h1Score = 0 - fromScore;
    fromEntity.m15Score = fromScore;
    fromEntity.m5Score = 0 - fromScore;
    fromEntity.totalScore = fromScore * 3;
    fromEntity.mn1SampleCount = 1;
    fromEntity.w1SampleCount = 1;
    fromEntity.d1SampleCount = 1;
    fromEntity.h4SampleCount = 1;
    fromEntity.h1SampleCount = 1;
    fromEntity.m15SampleCount = 1;
    fromEntity.m5SampleCount = 1;
    fromEntity.totalSampleCount = 7;
    fromEntity.longMediumTermAverageScore = (double)(fromScore * 3) / 5.0;
    fromEntity.longMediumTermAverageRank = 2;
    fromEntity.mediumShortTermAverageScore = (double)fromScore / 5.0;
    fromEntity.mediumShortTermAverageRank = 2;
    fromEntity.longTermAverageScore = (double)fromScore;
    fromEntity.longTermAverageRank = 2;
    fromEntity.mediumTermAverageScore = (double)fromScore / 3.0;
    fromEntity.mediumTermAverageRank = 2;
    fromEntity.shortTermAverageScore = (double)(0 - fromScore) / 3.0;
    fromEntity.shortTermAverageRank = 1;

    if (fromScore > 0) {
        fromEntity.longTermAverageRank = 1;
        fromEntity.mediumTermAverageRank = 1;
        fromEntity.shortTermAverageRank = 2;
        fromEntity.longMediumTermAverageRank = 1;
        fromEntity.mediumShortTermAverageRank = 1;
    }

    fromEntity.updatedAt = 0;
    fromEntity.updatedAtText = "";
}

/**
 * 指定した集計IDに関連するレコード件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromTableName テーブルまたはビュー名。
 * @param fromIdColumnName 集計ID列名。空文字の場合はテーブル全件を取得する。
 * @param fromRunId 集計ID。
 * @param fromRecordCount 取得した件数の格納先。
 * @param fromLogger ロガー。
 * @return 件数を取得できた場合はtrue。
 */
bool readRecordCount(
    const int fromDatabaseHandle,
    const string fromTableName,
    const string fromIdColumnName,
    const long fromRunId,
    long &fromRecordCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM " + fromTableName;
    bool hasIdCondition = StringLen(fromIdColumnName) > 0;

    if (hasIdCondition) {
        sql += " WHERE " + fromIdColumnName + " = ?1";
    }

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabasePrepare failed. tableName=%s error=%d",
                fromTableName,
                GetLastError()
            )
        );

        return false;
    }

    ResetLastError();

    if (hasIdCondition && !DatabaseBind(requestHandle, 0, fromRunId)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseBind failed. tableName=%s error=%d",
                fromTableName,
                bindErrorCode
            )
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseRead failed. tableName=%s error=%d",
                fromTableName,
                readErrorCode
            )
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromRecordCount)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseColumnLong failed. tableName=%s error=%d",
                fromTableName,
                columnErrorCode
            )
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * M5スナップショット自然キーに一致するRun件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromM5BarTime M5足開始時刻。
 * @param fromCalculationVersion 集計ルール識別子。
 * @param fromSourceMode 集計実行モード。
 * @param fromSourceServer 集計元サーバー名。
 * @param fromSourceLogin 集計元ログイン番号。
 * @param fromRecordCount 取得した件数の格納先。
 * @param fromLogger ロガー。
 * @return 件数を取得できた場合true。
 */
bool readSnapshotRunCount(
    const int fromDatabaseHandle,
    const datetime fromM5BarTime,
    const string fromCalculationVersion,
    const string fromSourceMode,
    const string fromSourceServer,
    const long fromSourceLogin,
    long &fromRecordCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM currency_strength_runs ";
    sql += "WHERE m5_bar_time = ?1 AND calculation_version = ?2 ";
    sql += "AND source_mode = ?3 ";
    sql += "AND source_server = ?4 AND source_login = ?5";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    bool isBound = DatabaseBind(requestHandle, 0, fromM5BarTime);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 1, fromCalculationVersion);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 2, fromSourceMode);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 3, fromSourceServer);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 4, fromSourceLogin);
    }

    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromRecordCount)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 更新後Runの保存値と期待値が異なる件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 集計ID。
 * @param fromCalculatedAt 集計時刻。
 * @param fromM5BarTime M5足開始時刻。
 * @param fromM5BarTimeText M5足開始時刻文字列。
 * @param fromSourceMode 集計実行モード。
 * @param fromSourceChartId 保存元チャートID。
 * @param fromMismatchCount 不一致件数の格納先。
 * @param fromLogger ロガー。
 * @return 件数を取得できた場合true。
 */
bool readRunValueMismatchCount(
    const int fromDatabaseHandle,
    const long fromRunId,
    const datetime fromCalculatedAt,
    const datetime fromM5BarTime,
    const string fromM5BarTimeText,
    const string fromSourceMode,
    const long fromSourceChartId,
    long &fromMismatchCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM currency_strength_runs ";
    sql += "WHERE id = ?1 AND (calculated_at <> ?2 OR m5_bar_time <> ?3 ";
    sql += "OR m5_bar_time_text <> ?4 OR source_mode <> ?5 ";
    sql += "OR source_chart_id <> ?6)";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    bool isBound = DatabaseBind(requestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 1, fromCalculatedAt);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 2, fromM5BarTime);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 3, fromM5BarTimeText);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 4, fromSourceMode);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 5, fromSourceChartId);
    }

    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromMismatchCount)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 指定した集計内で期待する更新時刻と異なるレコード件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromTableName テーブル名。
 * @param fromIdColumnName 集計ID列名。
 * @param fromRunId 集計ID。
 * @param fromUpdatedAt 期待するレコード更新時刻。
 * @param fromUpdatedAtText 期待するレコード更新時刻表示文字列。
 * @param fromMismatchCount 不一致件数の格納先。
 * @param fromLogger ロガー。
 * @return 不一致件数を取得できた場合true。
 */
bool readUpdatedAtMismatchCount(
    const int fromDatabaseHandle,
    const string fromTableName,
    const string fromIdColumnName,
    const long fromRunId,
    const datetime fromUpdatedAt,
    const string fromUpdatedAtText,
    long &fromMismatchCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM " + fromTableName;
    sql += " WHERE " + fromIdColumnName + " = ?1";
    sql += " AND (updated_at <> ?2 OR updated_at_text <> ?3)";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabasePrepare failed. tableName=%s error=%d",
                fromTableName,
                GetLastError()
            )
        );

        return false;
    }

    bool isBound = DatabaseBind(requestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 1, fromUpdatedAt);
    }
    if (isBound) {
        isBound = DatabaseBind(requestHandle, 2, fromUpdatedAtText);
    }

    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseBind failed. tableName=%s error=%d",
                fromTableName,
                bindErrorCode
            )
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseRead failed. tableName=%s error=%d",
                fromTableName,
                readErrorCode
            )
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromMismatchCount)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseColumnLong failed. tableName=%s error=%d",
                fromTableName,
                columnErrorCode
            )
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 指定した集計内で期待する通貨別結果と異なるレコード件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 集計ID。
 * @param fromUsdScore USDの期待スコア。
 * @param fromMismatchCount 不一致件数の格納先。
 * @param fromLogger ロガー。
 * @return 件数を取得できた場合true。
 */
bool readResultMismatchCount(
    const int fromDatabaseHandle,
    const long fromRunId,
    const int fromUsdScore,
    long &fromMismatchCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM currency_strength_results ";
    sql += "WHERE run_id = ?1 AND (";
    sql += "mn1_score <> d1_score OR w1_score <> d1_score OR ";
    sql += "h4_score <> d1_score OR h1_score <> 0 - d1_score OR ";
    sql += "m15_score <> d1_score OR m5_score <> 0 - d1_score OR ";
    sql += "total_score <> d1_score * 3 OR ";
    sql += "mn1_sample_count <> 1 OR w1_sample_count <> 1 OR ";
    sql += "d1_sample_count <> 1 OR h4_sample_count <> 1 OR ";
    sql += "h1_sample_count <> 1 OR m15_sample_count <> 1 OR ";
    sql += "m5_sample_count <> 1 OR total_sample_count <> 7 OR ";
    sql += "ABS(long_term_average_score - ";
    sql += "(mn1_score + w1_score + d1_score) / 3.0) > 0.000001 OR ";
    sql += "ABS(medium_term_average_score - ";
    sql += "(d1_score + h4_score + h1_score) / 3.0) > 0.000001 OR ";
    sql += "ABS(short_term_average_score - ";
    sql += "(h1_score + m15_score + m5_score) / 3.0) > 0.000001 OR ";
    sql += "ABS(long_medium_term_average_score - ";
    sql += "(mn1_score + w1_score + d1_score + h4_score + h1_score) ";
    sql += "/ 5.0) > 0.000001 OR ";
    sql += "ABS(medium_short_term_average_score - ";
    sql += "(d1_score + h4_score + h1_score + m15_score + m5_score) ";
    sql += "/ 5.0) > 0.000001 OR ";
    sql += "(d1_score > 0 AND (long_term_average_rank <> 1 OR ";
    sql += "medium_term_average_rank <> 1 OR short_term_average_rank <> 2 OR ";
    sql += "long_medium_term_average_rank <> 1 OR ";
    sql += "medium_short_term_average_rank <> 1)) OR ";
    sql += "(d1_score < 0 AND (long_term_average_rank <> 2 OR ";
    sql += "medium_term_average_rank <> 2 OR short_term_average_rank <> 1 OR ";
    sql += "long_medium_term_average_rank <> 2 OR ";
    sql += "medium_short_term_average_rank <> 2)) OR ";
    sql += "(currency_name = 'USD' AND d1_score <> ?2) OR ";
    sql += "(currency_name = 'JPY' AND d1_score <> 0 - ?2) OR ";
    sql += "currency_name NOT IN ('USD', 'JPY'))";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    bool isBound = DatabaseBind(requestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 1, fromUsdScore);
    }

    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromMismatchCount)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 指定した集計の先頭票から表示文字列と判定値を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 集計ID。
 * @param fromTimeFrameText 時間足文字列の格納先。
 * @param fromBarTimeText バー時刻文字列の格納先。
 * @param fromIsBuy BUY判定値の格納先。
 * @param fromOscillatorCount オシレーター値の格納先。
 * @param fromLogger ロガー。
 * @return 文字列を取得できた場合true。
 */
bool readFirstVoteText(
    const int fromDatabaseHandle,
    const long fromRunId,
    string &fromTimeFrameText,
    string &fromBarTimeText,
    long &fromIsBuy,
    long &fromOscillatorCount,
    Logger &fromLogger
) {
    string sql = "SELECT time_frame_text, bar_time_text, is_buy, oscillator_count ";
    sql += "FROM currency_strength_pair_votes ";
    sql += "WHERE run_id = ?1 ";
    sql += "ORDER BY pair_order, time_frame_order LIMIT 1";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseBind(requestHandle, 0, fromRunId)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    ResetLastError();
    bool isRead = DatabaseColumnText(requestHandle, 0, fromTimeFrameText);

    if (isRead) {
        isRead = DatabaseColumnText(requestHandle, 1, fromBarTimeText);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, fromIsBuy);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 3, fromOscillatorCount);
    }

    if (!isRead) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn failed. error=%d", columnErrorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * DBオブジェクトの列順が期待どおりか確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromObjectName テーブルまたはビュー名。
 * @param fromExpectedColumnNames 期待する列名一覧。
 * @param fromLogger ロガー。
 * @return 列順が一致する場合true。
 */
bool verifyColumnOrder(
    const int fromDatabaseHandle,
    const string fromObjectName,
    const string &fromExpectedColumnNames[],
    Logger &fromLogger
) {
    string sql = "PRAGMA table_info(" + fromObjectName + ")";
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabasePrepare failed. object=%s error=%d",
                fromObjectName,
                GetLastError()
            )
        );

        return false;
    }

    int columnIndex = 0;

    while (true) {
        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. object=%s error=%d",
                        fromObjectName,
                        readErrorCode
                    )
                );

                return false;
            }

            if (columnIndex != ArraySize(fromExpectedColumnNames)) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "column count mismatch. object=%s expected=%d actual=%d",
                        fromObjectName,
                        ArraySize(fromExpectedColumnNames),
                        columnIndex
                    )
                );

                return false;
            }

            return true;
        }

        string columnName = "";

        if (!DatabaseColumnText(requestHandle, 1, columnName)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnText failed. object=%s error=%d",
                    fromObjectName,
                    columnErrorCode
                )
            );

            return false;
        }

        if (columnIndex >= ArraySize(fromExpectedColumnNames)
                || columnName != fromExpectedColumnNames[columnIndex]) {
            string expectedColumnName = "NONE";

            if (columnIndex < ArraySize(fromExpectedColumnNames)) {
                expectedColumnName = fromExpectedColumnNames[columnIndex];
            }

            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "column order mismatch. object=%s index=%d expected=%s actual=%s",
                    fromObjectName,
                    columnIndex,
                    expectedColumnName,
                    columnName
                )
            );

            return false;
        }

        columnIndex++;
    }
}

/**
 * 新規通貨強弱DBの列順を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全DBオブジェクトの列順が一致する場合true。
 */
bool verifyNewDatabaseColumnOrders(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string runColumnNames[15];
    runColumnNames[0] = "id";
    runColumnNames[1] = "m5_bar_time";
    runColumnNames[2] = "m5_bar_time_text";
    runColumnNames[3] = "calculated_at";
    runColumnNames[4] = "source_mode";
    runColumnNames[5] = "calculation_version";
    runColumnNames[6] = "is_complete";
    runColumnNames[7] = "valid_pair_count";
    runColumnNames[8] = "expected_pair_count";
    runColumnNames[9] = "vote_count";
    runColumnNames[10] = "source_server";
    runColumnNames[11] = "source_login";
    runColumnNames[12] = "source_chart_id";
    runColumnNames[13] = "updated_at";
    runColumnNames[14] = "updated_at_text";

    if (!verifyColumnOrder(
        fromDatabaseHandle,
        "currency_strength_runs",
        runColumnNames,
        fromLogger
    )) {
        return false;
    }

    string voteColumnNames[19];
    voteColumnNames[0] = "id";
    voteColumnNames[1] = "run_id";
    voteColumnNames[2] = "canonical_symbol_name";
    voteColumnNames[3] = "resolved_symbol_name";
    voteColumnNames[4] = "pair_order";
    voteColumnNames[5] = "time_frame";
    voteColumnNames[6] = "time_frame_text";
    voteColumnNames[7] = "time_frame_order";
    voteColumnNames[8] = "bar_time";
    voteColumnNames[9] = "bar_time_text";
    voteColumnNames[10] = "is_buy";
    voteColumnNames[11] = "oscillator_count";
    voteColumnNames[12] = "base_currency";
    voteColumnNames[13] = "base_score";
    voteColumnNames[14] = "base_score_after";
    voteColumnNames[15] = "quote_currency";
    voteColumnNames[16] = "quote_score_after";
    voteColumnNames[17] = "updated_at";
    voteColumnNames[18] = "updated_at_text";

    if (!verifyColumnOrder(
        fromDatabaseHandle,
        "currency_strength_pair_votes",
        voteColumnNames,
        fromLogger
    )) {
        return false;
    }

    string resultColumnNames[31];
    resultColumnNames[0] = "id";
    resultColumnNames[1] = "run_id";
    resultColumnNames[2] = "currency_name";
    resultColumnNames[3] = "total_score";
    resultColumnNames[4] = "total_sample_count";
    resultColumnNames[5] = "long_medium_term_average_score";
    resultColumnNames[6] = "long_medium_term_average_rank";
    resultColumnNames[7] = "medium_short_term_average_score";
    resultColumnNames[8] = "medium_short_term_average_rank";
    resultColumnNames[9] = "long_term_average_score";
    resultColumnNames[10] = "long_term_average_rank";
    resultColumnNames[11] = "medium_term_average_score";
    resultColumnNames[12] = "medium_term_average_rank";
    resultColumnNames[13] = "short_term_average_score";
    resultColumnNames[14] = "short_term_average_rank";
    resultColumnNames[15] = "mn1_score";
    resultColumnNames[16] = "w1_score";
    resultColumnNames[17] = "d1_score";
    resultColumnNames[18] = "h4_score";
    resultColumnNames[19] = "h1_score";
    resultColumnNames[20] = "m15_score";
    resultColumnNames[21] = "m5_score";
    resultColumnNames[22] = "mn1_sample_count";
    resultColumnNames[23] = "w1_sample_count";
    resultColumnNames[24] = "d1_sample_count";
    resultColumnNames[25] = "h4_sample_count";
    resultColumnNames[26] = "h1_sample_count";
    resultColumnNames[27] = "m15_sample_count";
    resultColumnNames[28] = "m5_sample_count";
    resultColumnNames[29] = "updated_at";
    resultColumnNames[30] = "updated_at_text";

    if (!verifyColumnOrder(
        fromDatabaseHandle,
        "currency_strength_results",
        resultColumnNames,
        fromLogger
    )) {
        return false;
    }

    string contributionColumnNames[22];
    contributionColumnNames[0] = "run_id";
    contributionColumnNames[1] = "m5_bar_time";
    contributionColumnNames[2] = "m5_bar_time_text";
    contributionColumnNames[3] = "source_mode";
    contributionColumnNames[4] = "currency_name";
    contributionColumnNames[5] = "currency_side";
    contributionColumnNames[6] = "score";
    contributionColumnNames[7] = "score_after";
    contributionColumnNames[8] = "canonical_symbol_name";
    contributionColumnNames[9] = "resolved_symbol_name";
    contributionColumnNames[10] = "time_frame";
    contributionColumnNames[11] = "time_frame_text";
    contributionColumnNames[12] = "bar_time";
    contributionColumnNames[13] = "bar_time_text";
    contributionColumnNames[14] = "is_buy";
    contributionColumnNames[15] = "oscillator_count";
    contributionColumnNames[16] = "pair_order";
    contributionColumnNames[17] = "time_frame_order";
    contributionColumnNames[18] = "vote_id";
    contributionColumnNames[19] = "calculated_at";
    contributionColumnNames[20] = "updated_at";
    contributionColumnNames[21] = "updated_at_text";

    return verifyColumnOrder(
        fromDatabaseHandle,
        "currency_strength_contributions",
        contributionColumnNames,
        fromLogger
    );
}

/**
 * 通貨強弱SQLite動作確認スクリプトを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);
    SqliteDatabase database(databaseFileName, useCommonFolder);

    if (!database.open()) {
        logger.error(__FUNCTION__, "Currency strength database smoke test failed at open.");

        return;
    }

    if (recreateDatabaseObjects
            && !dropDatabaseObjects(database.getHandle(), logger)) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at dropDatabaseObjects."
        );
        database.close();

        return;
    }

    CurrencyStrengthRunDao runDao(database.getHandle());
    CurrencyStrengthPairVoteDao pairVoteDao(database.getHandle());
    CurrencyStrengthResultDao resultDao(database.getHandle());
    CurrencyStrengthPersistenceService persistenceService(
        database.getHandle(),
        GetPointer(runDao),
        GetPointer(pairVoteDao),
        GetPointer(resultDao)
    );

    if (!persistenceService.createTables()) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at createTables."
        );
        database.close();

        return;
    }

    if (recreateDatabaseObjects
            && !verifyNewDatabaseColumnOrders(
                database.getHandle(),
                logger
            )) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at column order."
        );
        database.close();

        return;
    }

    datetime firstCalculatedAt = TimeLocal();

    if (firstCalculatedAt <= 0) {
        logger.error(__FUNCTION__, "Currency strength database smoke test failed at TimeLocal.");
        database.close();

        return;
    }

    long firstCalculatedAtValue = (long)firstCalculatedAt;
    datetime m5BarTime = (datetime)(
        firstCalculatedAtValue - firstCalculatedAtValue % 900
    );
    CurrencyStrengthRunEntity runEntity;
    initializeRunEntity(
        firstCalculatedAt,
        m5BarTime,
        runEntity
    );

    CurrencyStrengthPairVoteEntity voteEntities[];
    ArrayResize(voteEntities, 7);
    initializePairVoteEntity(0, PERIOD_MN1, true, m5BarTime, voteEntities[0]);
    initializePairVoteEntity(1, PERIOD_W1, true, m5BarTime, voteEntities[1]);
    initializePairVoteEntity(2, PERIOD_D1, true, m5BarTime, voteEntities[2]);
    initializePairVoteEntity(3, PERIOD_H4, true, m5BarTime, voteEntities[3]);
    initializePairVoteEntity(4, PERIOD_H1, false, m5BarTime, voteEntities[4]);
    initializePairVoteEntity(5, PERIOD_M15, true, m5BarTime, voteEntities[5]);
    initializePairVoteEntity(6, PERIOD_M5, false, m5BarTime, voteEntities[6]);

    CurrencyStrengthResultEntity resultEntities[];
    ArrayResize(resultEntities, 2);
    initializeResultEntity("USD", 1, resultEntities[0]);
    initializeResultEntity("JPY", -1, resultEntities[1]);

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    )) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at saveSnapshot."
        );
        database.close();

        return;
    }

    long firstRunId = runEntity.id;
    datetime firstUpdatedAt = runEntity.updatedAt;

    if (firstRunId <= 0 || firstUpdatedAt <= 0) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed after first saveSnapshot."
        );
        database.close();

        return;
    }

    Sleep(1100);

    datetime secondCalculatedAt = TimeLocal();

    if (secondCalculatedAt <= firstCalculatedAt) {
        secondCalculatedAt = firstCalculatedAt + 1;
    }

    initializeRunEntity(
        secondCalculatedAt,
        m5BarTime,
        runEntity
    );
    runEntity.sourceChartId = ChartID() + 1;

    initializePairVoteEntity(0, PERIOD_MN1, false, m5BarTime, voteEntities[0]);
    initializePairVoteEntity(1, PERIOD_W1, false, m5BarTime, voteEntities[1]);
    initializePairVoteEntity(2, PERIOD_D1, false, m5BarTime, voteEntities[2]);
    initializePairVoteEntity(3, PERIOD_H4, false, m5BarTime, voteEntities[3]);
    initializePairVoteEntity(4, PERIOD_H1, true, m5BarTime, voteEntities[4]);
    initializePairVoteEntity(5, PERIOD_M15, false, m5BarTime, voteEntities[5]);
    initializePairVoteEntity(6, PERIOD_M5, true, m5BarTime, voteEntities[6]);
    initializeResultEntity("USD", -1, resultEntities[0]);
    initializeResultEntity("JPY", 1, resultEntities[1]);

    datetime secondSaveStartedAt = TimeGMT();

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    )) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at second saveSnapshot."
        );
        database.close();

        return;
    }

    datetime secondSaveEndedAt = TimeGMT();

    long totalRunCount = 0;
    long snapshotRunCount = 0;
    long runCount = 0;
    long voteCount = 0;
    long resultCount = 0;
    long contributionCount = 0;
    long runUpdatedAtMismatchCount = 0;
    long voteUpdatedAtMismatchCount = 0;
    long resultUpdatedAtMismatchCount = 0;
    long runValueMismatchCount = 0;
    long resultMismatchCount = 0;
    long firstVoteIsBuy = 0;
    long firstVoteOscillatorCount = 0;
    string timeFrameText = "";
    string barTimeText = "";
    bool isCountRead = readRecordCount(
        database.getHandle(),
        "currency_strength_runs",
        "",
        0,
        totalRunCount,
        logger
    );

    if (isCountRead) {
        isCountRead = readSnapshotRunCount(
            database.getHandle(),
            runEntity.m5BarTime,
            runEntity.calculationVersion,
            runEntity.sourceMode,
            runEntity.sourceServer,
            runEntity.sourceLogin,
            snapshotRunCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readRecordCount(
            database.getHandle(),
            "currency_strength_runs",
            "id",
            runEntity.id,
            runCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readRunValueMismatchCount(
            database.getHandle(),
            runEntity.id,
            secondCalculatedAt,
            m5BarTime,
            runEntity.m5BarTimeText,
            runEntity.sourceMode,
            runEntity.sourceChartId,
            runValueMismatchCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readRecordCount(
            database.getHandle(),
            "currency_strength_pair_votes",
            "run_id",
            runEntity.id,
            voteCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readUpdatedAtMismatchCount(
            database.getHandle(),
            "currency_strength_runs",
            "id",
            runEntity.id,
            runEntity.updatedAt,
            runEntity.updatedAtText,
            runUpdatedAtMismatchCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readUpdatedAtMismatchCount(
            database.getHandle(),
            "currency_strength_pair_votes",
            "run_id",
            runEntity.id,
            runEntity.updatedAt,
            runEntity.updatedAtText,
            voteUpdatedAtMismatchCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readUpdatedAtMismatchCount(
            database.getHandle(),
            "currency_strength_results",
            "run_id",
            runEntity.id,
            runEntity.updatedAt,
            runEntity.updatedAtText,
            resultUpdatedAtMismatchCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readFirstVoteText(
            database.getHandle(),
            runEntity.id,
            timeFrameText,
            barTimeText,
            firstVoteIsBuy,
            firstVoteOscillatorCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readResultMismatchCount(
            database.getHandle(),
            runEntity.id,
            -1,
            resultMismatchCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readRecordCount(
            database.getHandle(),
            "currency_strength_results",
            "run_id",
            runEntity.id,
            resultCount,
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readRecordCount(
            database.getHandle(),
            "currency_strength_contributions",
            "run_id",
            runEntity.id,
            contributionCount,
            logger
        );
    }

    if (!isCountRead) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at SELECT COUNT."
        );
        database.close();

        return;
    }

    if (runEntity.id <= 0
            || runEntity.id != firstRunId
            || (recreateDatabaseObjects && totalRunCount != 1)
            || snapshotRunCount != 1
            || runCount != 1
            || voteCount != 7
            || resultCount != 2
            || contributionCount != 14
            || timeFrameText != "MN1"
            || firstVoteIsBuy != 0
            || firstVoteOscillatorCount != -2
            || runEntity.updatedAt <= 0
            || runEntity.updatedAt <= firstUpdatedAt
            || secondSaveStartedAt <= 0
            || secondSaveEndedAt < secondSaveStartedAt
            || runEntity.updatedAt < secondSaveStartedAt
            || runEntity.updatedAt > secondSaveEndedAt
            || StringLen(runEntity.updatedAtText) == 0
            || runEntity.m5BarTime != m5BarTime
            || runEntity.m5BarTimeText != TimeToString(
                m5BarTime,
                TIME_DATE | TIME_SECONDS
            )
            || runUpdatedAtMismatchCount != 0
            || voteUpdatedAtMismatchCount != 0
            || resultUpdatedAtMismatchCount != 0
            || runValueMismatchCount != 0
            || resultMismatchCount != 0
            || barTimeText != TimeToString(
                m5BarTime,
                TIME_DATE | TIME_SECONDS
            )) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Currency strength database smoke test mismatch. firstRunId=%I64d runId=%I64d totalRuns=%I64d snapshotRuns=%I64d runs=%I64d votes=%I64d results=%I64d contributions=%I64d firstVoteIsBuy=%I64d firstVoteOscillatorCount=%I64d timeFrameText=%s barTimeText=%s updatedAtText=%s runValueMismatch=%I64d runUpdatedAtMismatch=%I64d voteUpdatedAtMismatch=%I64d resultUpdatedAtMismatch=%I64d resultMismatch=%I64d",
                firstRunId,
                runEntity.id,
                totalRunCount,
                snapshotRunCount,
                runCount,
                voteCount,
                resultCount,
                contributionCount,
                firstVoteIsBuy,
                firstVoteOscillatorCount,
                timeFrameText,
                barTimeText,
                runEntity.updatedAtText,
                runValueMismatchCount,
                runUpdatedAtMismatchCount,
                voteUpdatedAtMismatchCount,
                resultUpdatedAtMismatchCount,
                resultMismatchCount
            )
        );
        database.close();

        return;
    }

    long sameM5RunId = runEntity.id;
    datetime nextM5BarTime = m5BarTime + PeriodSeconds(PERIOD_M5);
    initializeRunEntity(
        secondCalculatedAt + PeriodSeconds(PERIOD_M5),
        nextM5BarTime,
        runEntity
    );
    initializePairVoteEntity(
        0,
        PERIOD_MN1,
        true,
        nextM5BarTime,
        voteEntities[0]
    );
    initializePairVoteEntity(
        1,
        PERIOD_W1,
        true,
        nextM5BarTime,
        voteEntities[1]
    );
    initializePairVoteEntity(
        2,
        PERIOD_D1,
        true,
        nextM5BarTime,
        voteEntities[2]
    );
    initializePairVoteEntity(
        3,
        PERIOD_H4,
        true,
        nextM5BarTime,
        voteEntities[3]
    );
    initializePairVoteEntity(
        4,
        PERIOD_H1,
        false,
        nextM5BarTime,
        voteEntities[4]
    );
    initializePairVoteEntity(
        5,
        PERIOD_M15,
        true,
        nextM5BarTime,
        voteEntities[5]
    );
    initializePairVoteEntity(
        6,
        PERIOD_M5,
        false,
        nextM5BarTime,
        voteEntities[6]
    );
    initializeResultEntity("USD", 1, resultEntities[0]);
    initializeResultEntity("JPY", -1, resultEntities[1]);

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    )) {
        logger.error(
            __FUNCTION__,
            "Currency strength database smoke test failed at next M5 save."
        );
        database.close();

        return;
    }

    long nextM5SnapshotRunCount = 0;
    long finalTotalRunCount = 0;
    bool isNextM5Verified = readSnapshotRunCount(
        database.getHandle(),
        runEntity.m5BarTime,
        runEntity.calculationVersion,
        runEntity.sourceMode,
        runEntity.sourceServer,
        runEntity.sourceLogin,
        nextM5SnapshotRunCount,
        logger
    );

    if (isNextM5Verified) {
        isNextM5Verified = readRecordCount(
            database.getHandle(),
            "currency_strength_runs",
            "",
            0,
            finalTotalRunCount,
            logger
        );
    }

    if (!isNextM5Verified
            || runEntity.id <= 0
            || runEntity.id == sameM5RunId
            || nextM5SnapshotRunCount != 1
            || (recreateDatabaseObjects && finalTotalRunCount != 2)) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Currency strength next M5 verification failed. sameM5RunId=%I64d nextM5RunId=%I64d snapshotRuns=%I64d totalRuns=%I64d",
                sameM5RunId,
                runEntity.id,
                nextM5SnapshotRunCount,
                finalTotalRunCount
            )
        );
        database.close();

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Currency strength database smoke test passed. fileName=%s runId=%I64d saves=3 totalRuns=%I64d nextM5SnapshotRuns=%I64d votes=%I64d results=%I64d contributions=%I64d timeFrameText=%s barTimeText=%s updatedAtText=%s averages=5 ranks=5",
            database.getFileName(),
            runEntity.id,
            finalTotalRunCount,
            nextM5SnapshotRunCount,
            voteCount,
            resultCount,
            contributionCount,
            timeFrameText,
            barTimeText,
            runEntity.updatedAtText
        )
    );

    database.close();
}
