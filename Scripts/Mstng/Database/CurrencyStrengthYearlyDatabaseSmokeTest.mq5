//+------------------------------------------------------------------+
//|                      CurrencyStrengthYearlyDatabaseSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Database\CurrencyStrengthDatabaseFileResolver.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyPersistenceService.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/** 動作確認用データベースのベースファイル名。 */
input string databaseFileName =
    "mstng-currency-strength-yearly-smoke-test.sqlite";

/** 共有フォルダ使用有無。 */
input bool useCommonFolder = true;

/**
 * 通貨強弱の集計エンティティを初期化する。
 *
 * @param fromCalculatedAt 集計時刻。
 * @param fromM5BarTime M5足開始時刻。
 * @param fromSourceChartId 保存元チャートID。
 * @param fromEntity 初期化対象エンティティ。
 */
void initializeRunEntity(
    const datetime fromCalculatedAt,
    const datetime fromM5BarTime,
    const long fromSourceChartId,
    CurrencyStrengthRunEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.calculatedAt = fromCalculatedAt;
    fromEntity.m5BarTime = fromM5BarTime;
    fromEntity.m5BarTimeText = TimeToString(
        fromM5BarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.calculationVersion = "yearly-smoke-v1";
    fromEntity.sourceMode = "TESTER";
    fromEntity.sourceServer = "yearly-smoke";
    fromEntity.sourceLogin = 1;
    fromEntity.sourceChartId = fromSourceChartId;
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
    fromEntity.timeFrameText = TimeUtil::convertTimeFrameToString(
        fromTimeFrame
    );
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
    fromEntity.longMediumTermAverageRank = 8;
    fromEntity.mediumShortTermAverageScore = (double)fromScore / 5.0;
    fromEntity.mediumShortTermAverageRank = 7;

    if (fromScore > 0) {
        fromEntity.longMediumTermAverageRank = 1;
        fromEntity.mediumShortTermAverageRank = 2;
    }

    fromEntity.longTermAverageScore = (double)fromScore;
    fromEntity.longTermAverageRank = 1;
    fromEntity.mediumTermAverageScore = (double)fromScore / 3.0;
    fromEntity.mediumTermAverageRank = 1;
    fromEntity.shortTermAverageScore = (double)(0 - fromScore) / 3.0;
    fromEntity.shortTermAverageRank = 2;
    fromEntity.updatedAt = 0;
    fromEntity.updatedAtText = "";
}

/**
 * 年別スナップショットの子エンティティを初期化する。
 *
 * @param fromM5BarTime M5足開始時刻。
 * @param fromIsBuy BUY票の場合true。
 * @param fromVoteEntities 票内訳エンティティ一覧。
 * @param fromResultEntities 通貨別結果エンティティ一覧。
 */
void initializeChildEntities(
    const datetime fromM5BarTime,
    const bool fromIsBuy,
    CurrencyStrengthPairVoteEntity &fromVoteEntities[],
    CurrencyStrengthResultEntity &fromResultEntities[]
) {
    ArrayResize(fromVoteEntities, 7);
    initializePairVoteEntity(
        0,
        PERIOD_MN1,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[0]
    );
    initializePairVoteEntity(
        1,
        PERIOD_W1,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[1]
    );
    initializePairVoteEntity(
        2,
        PERIOD_D1,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[2]
    );
    initializePairVoteEntity(
        3,
        PERIOD_H4,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[3]
    );
    initializePairVoteEntity(
        4,
        PERIOD_H1,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[4]
    );
    initializePairVoteEntity(
        5,
        PERIOD_M15,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[5]
    );
    initializePairVoteEntity(
        6,
        PERIOD_M5,
        fromIsBuy,
        fromM5BarTime,
        fromVoteEntities[6]
    );

    int usdScore = -1;

    if (fromIsBuy) {
        usdScore = 1;
    }

    ArrayResize(fromResultEntities, 2);
    initializeResultEntity("USD", usdScore, fromResultEntities[0]);
    initializeResultEntity("JPY", 0 - usdScore, fromResultEntities[1]);
}

/**
 * 指定DBの件数とRun値を読み取る。
 *
 * @param fromFileName 対象DBファイル名。
 * @param fromRunCount Run件数の格納先。
 * @param fromVoteCount PairVote件数の格納先。
 * @param fromResultCount Result件数の格納先。
 * @param fromContributionCount Contribution件数の格納先。
 * @param fromSourceChartId 保存元チャートIDの格納先。
 * @param fromCalculatedAt 集計時刻の格納先。
 * @param fromFirstVoteIsBuy 先頭票のBUYフラグ格納先。
 * @param fromUsdMn1Score USDのMN1スコア格納先。
 * @param fromLogger ロガー。
 * @return 読み取りに成功した場合true。
 */
bool readDatabaseSummary(
    const string fromFileName,
    long &fromRunCount,
    long &fromVoteCount,
    long &fromResultCount,
    long &fromContributionCount,
    long &fromSourceChartId,
    long &fromCalculatedAt,
    long &fromFirstVoteIsBuy,
    long &fromUsdMn1Score,
    Logger &fromLogger
) {
    SqliteDatabase database(fromFileName, useCommonFolder);

    if (!database.open()) {
        return false;
    }

    string sql =
        "SELECT "
        "(SELECT COUNT(*) FROM currency_strength_runs), "
        "(SELECT COUNT(*) FROM currency_strength_pair_votes), "
        "(SELECT COUNT(*) FROM currency_strength_results), "
        "(SELECT COUNT(*) FROM currency_strength_contributions), "
        "(SELECT source_chart_id FROM currency_strength_runs "
        " WHERE source_mode = 'TESTER' LIMIT 1), "
        "(SELECT calculated_at FROM currency_strength_runs "
        " WHERE source_mode = 'TESTER' LIMIT 1), "
        "(SELECT pair_vote.is_buy "
        " FROM currency_strength_pair_votes pair_vote "
        " INNER JOIN currency_strength_runs run ON run.id = pair_vote.run_id "
        " WHERE run.source_mode = 'TESTER' "
        " AND pair_vote.pair_order = 0 "
        " AND pair_vote.time_frame_order = 0 LIMIT 1), "
        "(SELECT result.mn1_score "
        " FROM currency_strength_results result "
        " INNER JOIN currency_strength_runs run ON run.id = result.run_id "
        " WHERE run.source_mode = 'TESTER' "
        " AND result.currency_name = 'USD' LIMIT 1)";
    ResetLastError();
    int requestHandle = DatabasePrepare(database.getHandle(), sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );
        database.close();

        return false;
    }

    bool isRead = DatabaseRead(requestHandle);

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 0, fromRunCount);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 1, fromVoteCount);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, fromResultCount);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            3,
            fromContributionCount
        );
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 4, fromSourceChartId);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 5, fromCalculatedAt);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 6, fromFirstVoteIsBuy);
    }

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 7, fromUsdMn1Score);
    }

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("database summary read failed. error=%d", GetLastError())
        );
    }

    DatabaseFinalize(requestHandle);
    database.close();

    return isRead;
}

/**
 * 既存の年別SmokeTest DBを削除する。
 *
 * @param fromFileName 対象DBファイル名。
 * @return 削除または不存在を確認できた場合true。
 */
bool deleteTestDatabase(const string fromFileName) {
    int fileFlags = 0;

    if (useCommonFolder) {
        fileFlags = FILE_COMMON;
    }

    if (!FileIsExist(fromFileName, fileFlags)) {
        return true;
    }

    ResetLastError();

    return FileDelete(fromFileName, fileFlags);
}

/**
 * 通貨ペア順位の取得結果を検証する。
 *
 * @param fromInfo 取得した通貨ペア順位。
 * @param fromM5BarTime 期待するM5バー時刻。
 * @param fromBaseLongMediumRank 期待する基軸通貨の長中期順位。
 * @param fromBaseMediumShortRank 期待する基軸通貨の中短期順位。
 * @param fromQuoteLongMediumRank 期待する決済通貨の長中期順位。
 * @param fromQuoteMediumShortRank 期待する決済通貨の中短期順位。
 * @return 全項目が期待値と一致する場合true。
 */
bool verifyPairRankInfo(
    const CurrencyStrengthPairRankInfo &fromInfo,
    const datetime fromM5BarTime,
    const int fromBaseLongMediumRank,
    const int fromBaseMediumShortRank,
    const int fromQuoteLongMediumRank,
    const int fromQuoteMediumShortRank
) {
    return fromInfo.m5BarTime == fromM5BarTime
        && fromInfo.baseCurrency == "USD"
        && fromInfo.baseLongMediumTermAverageRank
            == fromBaseLongMediumRank
        && fromInfo.baseMediumShortTermAverageRank
            == fromBaseMediumShortRank
        && fromInfo.quoteCurrency == "JPY"
        && fromInfo.quoteLongMediumTermAverageRank
            == fromQuoteLongMediumRank
        && fromInfo.quoteMediumShortTermAverageRank
            == fromQuoteMediumShortRank;
}

/**
 * 年別通貨強弱SQLite動作確認スクリプトを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);
    datetime year2025M5BarTime = D'2025.12.31 23:55';
    datetime year2026M5BarTime = D'2026.01.01 00:00';
    string year2025FileName = "";
    string year2026FileName = "";
    string year2027FileName = "";
    string unsplitFileName = "";

    if (!CurrencyStrengthDatabaseFileResolver::resolveFileName(
        databaseFileName,
        true,
        year2025M5BarTime,
        year2025FileName
    ) || !CurrencyStrengthDatabaseFileResolver::resolveFileName(
        databaseFileName,
        true,
        year2026M5BarTime,
        year2026FileName
    ) || !CurrencyStrengthDatabaseFileResolver::resolveFileName(
        databaseFileName,
        false,
        year2026M5BarTime,
        unsplitFileName
    ) || !CurrencyStrengthDatabaseFileResolver::resolveFileNameForYear(
        databaseFileName,
        2027,
        year2027FileName
    ) || year2025FileName == year2026FileName
            || unsplitFileName != databaseFileName) {
        logger.error(__FUNCTION__, "Yearly database file resolution failed.");

        return;
    }

    if (databaseFileName
            == "mstng-currency-strength-yearly-smoke-test.sqlite"
            && (year2025FileName
                != "mstng-currency-strength-yearly-smoke-test-2025.sqlite"
                || year2026FileName
                    != "mstng-currency-strength-yearly-smoke-test-2026.sqlite")) {
        logger.error(__FUNCTION__, "Yearly database file name is invalid.");

        return;
    }

    if (!deleteTestDatabase(year2025FileName)
            || !deleteTestDatabase(year2026FileName)
            || !deleteTestDatabase(year2027FileName)) {
        logger.error(__FUNCTION__, "Yearly smoke test database deletion failed.");

        return;
    }

    CurrencyStrengthYearlyPersistenceService persistenceService(
        databaseFileName,
        true,
        useCommonFolder
    );
    CurrencyStrengthRunEntity runEntity;
    CurrencyStrengthPairVoteEntity voteEntities[];
    CurrencyStrengthResultEntity resultEntities[];
    datetime year2025CalculatedAt = D'2026.01.01 00:00';
    initializeRunEntity(
        year2025CalculatedAt,
        year2025M5BarTime,
        202501,
        runEntity
    );
    initializeChildEntities(
        year2025M5BarTime,
        true,
        voteEntities,
        resultEntities
    );

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    )) {
        logger.error(__FUNCTION__, "2025 snapshot save failed.");

        return;
    }

    long year2025RunId = runEntity.id;
    initializeRunEntity(
        D'2026.01.01 00:00',
        year2026M5BarTime,
        202601,
        runEntity
    );
    initializeChildEntities(
        year2026M5BarTime,
        true,
        voteEntities,
        resultEntities
    );

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    )) {
        logger.error(__FUNCTION__, "2026 snapshot save failed.");

        return;
    }

    long year2026RunId = runEntity.id;
    year2025CalculatedAt = D'2026.01.01 00:05';
    initializeRunEntity(
        year2025CalculatedAt,
        year2025M5BarTime,
        202502,
        runEntity
    );
    initializeChildEntities(
        year2025M5BarTime,
        false,
        voteEntities,
        resultEntities
    );

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    ) || runEntity.id != year2025RunId) {
        logger.error(__FUNCTION__, "2025 snapshot upsert failed.");

        return;
    }

    initializeRunEntity(
        D'2026.01.01 00:10',
        year2025M5BarTime,
        202503,
        runEntity
    );
    runEntity.sourceMode = "LIVE";
    initializeChildEntities(
        year2025M5BarTime,
        true,
        voteEntities,
        resultEntities
    );

    if (!persistenceService.saveSnapshot(
        runEntity,
        voteEntities,
        resultEntities
    ) || runEntity.id == year2025RunId) {
        logger.error(__FUNCTION__, "2025 LIVE snapshot save failed.");

        return;
    }

    long year2025LiveRunId = runEntity.id;

    persistenceService.close();
    CurrencyStrengthYearlyRankQueryService rankQueryService(
        databaseFileName,
        true,
        useCommonFolder
    );
    CurrencyStrengthPairRankInfo pairRankInfo;
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS rankQueryStatus =
        rankQueryService.findLatestPairRanksAtOrBefore(
            year2025M5BarTime,
            "yearly-smoke-v1",
            "TESTER",
            "yearly-smoke",
            1,
            "USD",
            "JPY",
            pairRankInfo
        );
    bool isRankVerified = rankQueryStatus
            == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
        && rankQueryService.getActiveYear() == 2025
        && pairRankInfo.runId == year2025RunId
        && verifyPairRankInfo(pairRankInfo, year2025M5BarTime, 8, 7, 1, 2);

    if (isRankVerified) {
        rankQueryStatus = rankQueryService.findLatestPairRanksAtOrBefore(
            year2026M5BarTime,
            "yearly-smoke-v1",
            "TESTER",
            "yearly-smoke",
            1,
            "USD",
            "JPY",
            pairRankInfo
        );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && rankQueryService.getActiveYear() == 2026
            && pairRankInfo.runId == year2026RunId
            && verifyPairRankInfo(
                pairRankInfo,
                year2026M5BarTime,
                1,
                2,
                8,
                7
            );
    }

    int fileFlags = 0;

    if (useCommonFolder) {
        fileFlags = FILE_COMMON;
    }

    bool year2027FileDidNotExist = !FileIsExist(
        year2027FileName,
        fileFlags
    );

    if (isRankVerified && year2027FileDidNotExist) {
        rankQueryStatus = rankQueryService.findLatestPairRanksAtOrBefore(
            D'2027.01.01 00:00',
            "yearly-smoke-v1",
            "TESTER",
            "yearly-smoke",
            1,
            "USD",
            "JPY",
            pairRankInfo
        );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && rankQueryService.getActiveYear() == 2026
            && pairRankInfo.runId == year2026RunId
            && verifyPairRankInfo(
                pairRankInfo,
                year2026M5BarTime,
                1,
                2,
                8,
                7
            )
            && !FileIsExist(year2027FileName, fileFlags);
    } else {
        isRankVerified = false;
    }

    if (isRankVerified) {
        rankQueryStatus =
            rankQueryService.findLatestPairRanksAtOrBeforePreferLive(
                year2025M5BarTime,
                "yearly-smoke-v1",
                "yearly-smoke",
                1,
                "USD",
                "JPY",
                pairRankInfo
            );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && pairRankInfo.runId == year2025LiveRunId
            && verifyPairRankInfo(
                pairRankInfo,
                year2025M5BarTime,
                1,
                2,
                8,
                7
            );
    }

    if (isRankVerified) {
        rankQueryStatus =
            rankQueryService.findLatestPairRanksAtOrBeforePreferLive(
                year2026M5BarTime,
                "yearly-smoke-v1",
                "yearly-smoke",
                1,
                "USD",
                "JPY",
                pairRankInfo
            );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && pairRankInfo.runId == year2026RunId
            && verifyPairRankInfo(
                pairRankInfo,
                year2026M5BarTime,
                1,
                2,
                8,
                7
            );
    }

    CurrencyStrengthPairRankPoint rankPoints[];

    if (isRankVerified) {
        rankQueryStatus = rankQueryService.findPairRankPointsInRange(
            year2025M5BarTime,
            year2026M5BarTime,
            "yearly-smoke-v1",
            "TESTER",
            "yearly-smoke",
            1,
            "USD",
            "JPY",
            2,
            rankPoints
        );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && ArraySize(rankPoints) == 2
            && rankPoints[0].runId == year2025RunId
            && rankPoints[0].m5BarTime == year2025M5BarTime
            && rankPoints[0].baseLongMediumTermAverageRank == 8
            && rankPoints[0].baseMediumShortTermAverageRank == 7
            && rankPoints[0].quoteLongMediumTermAverageRank == 1
            && rankPoints[0].quoteMediumShortTermAverageRank == 2
            && rankPoints[1].runId == year2026RunId
            && rankPoints[1].m5BarTime == year2026M5BarTime
            && rankPoints[1].baseLongMediumTermAverageRank == 1
            && rankPoints[1].baseMediumShortTermAverageRank == 2
            && rankPoints[1].quoteLongMediumTermAverageRank == 8
            && rankPoints[1].quoteMediumShortTermAverageRank == 7;
    }

    if (isRankVerified) {
        rankQueryStatus =
            rankQueryService.findPairRankPointsInRangePreferLive(
                year2025M5BarTime,
                year2026M5BarTime,
                "yearly-smoke-v1",
                "yearly-smoke",
                1,
                "USD",
                "JPY",
                2,
                rankPoints
            );
        isRankVerified = rankQueryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            && ArraySize(rankPoints) == 2
            && rankPoints[0].runId == year2025LiveRunId
            && rankPoints[0].m5BarTime == year2025M5BarTime
            && rankPoints[0].baseLongMediumTermAverageRank == 1
            && rankPoints[0].baseMediumShortTermAverageRank == 2
            && rankPoints[0].quoteLongMediumTermAverageRank == 8
            && rankPoints[0].quoteMediumShortTermAverageRank == 7
            && rankPoints[1].runId == year2026RunId
            && rankPoints[1].m5BarTime == year2026M5BarTime
            && rankPoints[1].baseLongMediumTermAverageRank == 1
            && rankPoints[1].baseMediumShortTermAverageRank == 2
            && rankPoints[1].quoteLongMediumTermAverageRank == 8
            && rankPoints[1].quoteMediumShortTermAverageRank == 7;
    }

    if (!isRankVerified) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Yearly rank query verification failed. status=%d activeYear=%d m5=%s",
                (int)rankQueryStatus,
                rankQueryService.getActiveYear(),
                TimeToString(pairRankInfo.m5BarTime, TIME_DATE | TIME_MINUTES)
            )
        );
        rankQueryService.close();

        return;
    }

    rankQueryService.close();
    long year2025RunCount = 0;
    long year2025VoteCount = 0;
    long year2025ResultCount = 0;
    long year2025ContributionCount = 0;
    long year2025SourceChartId = 0;
    long actualYear2025CalculatedAt = 0;
    long year2025FirstVoteIsBuy = 0;
    long year2025UsdMn1Score = 0;
    long year2026RunCount = 0;
    long year2026VoteCount = 0;
    long year2026ResultCount = 0;
    long year2026ContributionCount = 0;
    long year2026SourceChartId = 0;
    long actualYear2026CalculatedAt = 0;
    long year2026FirstVoteIsBuy = 0;
    long year2026UsdMn1Score = 0;
    bool isVerified = readDatabaseSummary(
        year2025FileName,
        year2025RunCount,
        year2025VoteCount,
        year2025ResultCount,
        year2025ContributionCount,
        year2025SourceChartId,
        actualYear2025CalculatedAt,
        year2025FirstVoteIsBuy,
        year2025UsdMn1Score,
        logger
    );

    if (isVerified) {
        isVerified = readDatabaseSummary(
            year2026FileName,
            year2026RunCount,
            year2026VoteCount,
            year2026ResultCount,
            year2026ContributionCount,
            year2026SourceChartId,
            actualYear2026CalculatedAt,
            year2026FirstVoteIsBuy,
            year2026UsdMn1Score,
            logger
        );
    }

    isVerified = isVerified
        && year2025RunCount == 2
        && year2025VoteCount == 14
        && year2025ResultCount == 4
        && year2025ContributionCount == 28
        && year2025SourceChartId == 202502
        && actualYear2025CalculatedAt == (long)year2025CalculatedAt
        && year2025FirstVoteIsBuy == 0
        && year2025UsdMn1Score == -1
        && year2026RunCount == 1
        && year2026VoteCount == 7
        && year2026ResultCount == 2
        && year2026ContributionCount == 14
        && year2026SourceChartId == 202601
        && actualYear2026CalculatedAt == (long)D'2026.01.01 00:00'
        && year2026FirstVoteIsBuy == 1
        && year2026UsdMn1Score == 1;

    if (!isVerified) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Yearly database verification failed. 2025=%I64d/%I64d/%I64d/%I64d/%I64d 2026=%I64d/%I64d/%I64d/%I64d/%I64d",
                year2025RunCount,
                year2025VoteCount,
                year2025ResultCount,
                year2025ContributionCount,
                year2025SourceChartId,
                year2026RunCount,
                year2026VoteCount,
                year2026ResultCount,
                year2026ContributionCount,
                year2026SourceChartId
            )
        );

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Yearly database smoke test passed. files=%s,%s",
            year2025FileName,
            year2026FileName
        )
    );
}
