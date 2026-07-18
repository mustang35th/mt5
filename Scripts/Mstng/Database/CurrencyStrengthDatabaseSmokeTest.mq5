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
 * @param fromEntity 初期化対象エンティティ。
 */
void initializeRunEntity(
    const datetime fromCalculatedAt,
    CurrencyStrengthRunEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.calculatedAt = fromCalculatedAt;
    fromEntity.m15BarTime = fromCalculatedAt;
    fromEntity.calculationVersion = "pair-direction-raw-v2-smoke-test";
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
 * USDJPYのBUY票エンティティを初期化する。
 *
 * @param fromTimeFrameOrder 時間足の集計順。
 * @param fromTimeFrame 時間足。
 * @param fromBarTime 判定対象のバー時刻。
 * @param fromEntity 初期化対象エンティティ。
 */
void initializePairVoteEntity(
    const int fromTimeFrameOrder,
    const ENUM_TIMEFRAMES fromTimeFrame,
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
    fromEntity.isBuy = 1;
    fromEntity.oscillatorCount = 2;
    fromEntity.baseScore = 1;
    fromEntity.baseScoreAfter = 1;
    fromEntity.quoteScoreAfter = -1;
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
    fromEntity.h1Score = fromScore;
    fromEntity.m15Score = fromScore;
    fromEntity.totalScore = fromScore * 6;
    fromEntity.mn1SampleCount = 1;
    fromEntity.w1SampleCount = 1;
    fromEntity.d1SampleCount = 1;
    fromEntity.h4SampleCount = 1;
    fromEntity.h1SampleCount = 1;
    fromEntity.m15SampleCount = 1;
    fromEntity.totalSampleCount = 6;
    fromEntity.updatedAt = 0;
    fromEntity.updatedAtText = "";
}

/**
 * 指定した集計IDに関連するレコード件数を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromTableName テーブルまたはビュー名。
 * @param fromIdColumnName 集計ID列名。
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
    sql += " WHERE " + fromIdColumnName + " = ?1";

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

    if (!DatabaseBind(requestHandle, 0, fromRunId)) {
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
 * @param fromMismatchCount 不一致件数の格納先。
 * @param fromLogger ロガー。
 * @return 件数を取得できた場合true。
 */
bool readResultMismatchCount(
    const int fromDatabaseHandle,
    const long fromRunId,
    long &fromMismatchCount,
    Logger &fromLogger
) {
    string sql = "SELECT COUNT(*) FROM currency_strength_results ";
    sql += "WHERE run_id = ?1 AND (";
    sql += "mn1_score <> d1_score OR w1_score <> d1_score OR ";
    sql += "h4_score <> d1_score OR h1_score <> d1_score OR ";
    sql += "m15_score <> d1_score OR total_score <> d1_score * 6 OR ";
    sql += "mn1_sample_count <> 1 OR w1_sample_count <> 1 OR ";
    sql += "d1_sample_count <> 1 OR h4_sample_count <> 1 OR ";
    sql += "h1_sample_count <> 1 OR m15_sample_count <> 1 OR ";
    sql += "total_sample_count <> 6 OR ";
    sql += "(currency_name = 'USD' AND d1_score <> 1) OR ";
    sql += "(currency_name = 'JPY' AND d1_score <> -1) OR ";
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
 * 指定した集計の先頭票から時間足・バー時刻文字列を取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 集計ID。
 * @param fromTimeFrameText 時間足文字列の格納先。
 * @param fromBarTimeText バー時刻文字列の格納先。
 * @param fromLogger ロガー。
 * @return 文字列を取得できた場合true。
 */
bool readFirstVoteText(
    const int fromDatabaseHandle,
    const long fromRunId,
    string &fromTimeFrameText,
    string &fromBarTimeText,
    Logger &fromLogger
) {
    string sql = "SELECT time_frame_text, bar_time_text ";
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

    if (!isRead) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnText failed. error=%d", columnErrorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
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

    datetime calculatedAt = TimeLocal();
    CurrencyStrengthRunEntity runEntity;
    initializeRunEntity(calculatedAt, runEntity);

    CurrencyStrengthPairVoteEntity voteEntities[];
    ArrayResize(voteEntities, 6);
    initializePairVoteEntity(0, PERIOD_MN1, calculatedAt, voteEntities[0]);
    initializePairVoteEntity(1, PERIOD_W1, calculatedAt, voteEntities[1]);
    initializePairVoteEntity(2, PERIOD_D1, calculatedAt, voteEntities[2]);
    initializePairVoteEntity(3, PERIOD_H4, calculatedAt, voteEntities[3]);
    initializePairVoteEntity(4, PERIOD_H1, calculatedAt, voteEntities[4]);
    initializePairVoteEntity(5, PERIOD_M15, calculatedAt, voteEntities[5]);

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

    long runCount = 0;
    long voteCount = 0;
    long resultCount = 0;
    long contributionCount = 0;
    long runUpdatedAtMismatchCount = 0;
    long voteUpdatedAtMismatchCount = 0;
    long resultUpdatedAtMismatchCount = 0;
    long resultMismatchCount = 0;
    string timeFrameText = "";
    string barTimeText = "";
    string expectedUpdatedAtText = TimeToString(
        runEntity.updatedAt,
        TIME_DATE | TIME_SECONDS
    );
    bool isCountRead = readRecordCount(
        database.getHandle(),
        "currency_strength_runs",
        "id",
        runEntity.id,
        runCount,
        logger
    );

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
            logger
        );
    }

    if (isCountRead) {
        isCountRead = readResultMismatchCount(
            database.getHandle(),
            runEntity.id,
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
            || runCount != 1
            || voteCount != 6
            || resultCount != 2
            || contributionCount != 12
            || timeFrameText != "MN1"
            || runEntity.updatedAt <= 0
            || runEntity.updatedAtText != expectedUpdatedAtText
            || runUpdatedAtMismatchCount != 0
            || voteUpdatedAtMismatchCount != 0
            || resultUpdatedAtMismatchCount != 0
            || resultMismatchCount != 0
            || barTimeText != TimeToString(
                calculatedAt,
                TIME_DATE | TIME_SECONDS
            )) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Currency strength database smoke test mismatch. runId=%I64d runs=%I64d votes=%I64d results=%I64d contributions=%I64d timeFrameText=%s barTimeText=%s updatedAtText=%s runUpdatedAtMismatch=%I64d voteUpdatedAtMismatch=%I64d resultUpdatedAtMismatch=%I64d resultMismatch=%I64d",
                runEntity.id,
                runCount,
                voteCount,
                resultCount,
                contributionCount,
                timeFrameText,
                barTimeText,
                runEntity.updatedAtText,
                runUpdatedAtMismatchCount,
                voteUpdatedAtMismatchCount,
                resultUpdatedAtMismatchCount,
                resultMismatchCount
            )
        );
        database.close();

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Currency strength database smoke test passed. fileName=%s runId=%I64d votes=%I64d results=%I64d contributions=%I64d timeFrameText=%s barTimeText=%s updatedAtText=%s",
            database.getFileName(),
            runEntity.id,
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
