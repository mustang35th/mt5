//+------------------------------------------------------------------+
//|            ZigZagElliotH1StudyOutcomeDatabaseSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Database\Dao\ZigZagElliotH1StudyOutcomeDao.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** Smoke Test専用データベースファイル名。 */
const string databaseFileName =
    "mstng-zigzag-elliot-h1-study-outcome-smoke-test.sqlite";

/** Common Filesを使用しない固定設定。 */
const bool databaseUseCommonFolder = false;

/**
 * Smoke Test専用ファイル名か確認する。
 *
 * @return 専用ファイル名の場合true。
 */
bool isDedicatedDatabaseFile() {
    return databaseFileName
        == "mstng-zigzag-elliot-h1-study-outcome-smoke-test.sqlite";
}

/**
 * 存在するSmoke Test用ファイルを削除する。
 *
 * @param fromFileName 削除対象ファイル名。
 * @return 不在または削除できた場合true。
 */
bool deleteTestFile(const string fromFileName) {
    if (!FileIsExist(fromFileName, 0)) {
        return true;
    }

    ResetLastError();

    if (FileDelete(fromFileName, 0)) {
        return true;
    }

    PrintFormat(
        "Smoke test file deletion failed. file=%s error=%d",
        fromFileName,
        GetLastError()
    );

    return false;
}

/**
 * DB本体とSQLite補助ファイルを安全に削除する。
 *
 * @return 全ファイルが不在または削除できた場合true。
 */
bool deleteTestDatabaseFiles() {
    if (!isDedicatedDatabaseFile()) {
        Print("Refusing to delete a non-dedicated smoke test database.");

        return false;
    }

    bool isDeleted = deleteTestFile(databaseFileName);

    if (!deleteTestFile(databaseFileName + "-journal")) {
        isDeleted = false;
    }
    if (!deleteTestFile(databaseFileName + "-wal")) {
        isDeleted = false;
    }
    if (!deleteTestFile(databaseFileName + "-shm")) {
        isDeleted = false;
    }

    return isDeleted;
}

/**
 * 指定SQLの先頭列をlongとして取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 実行SQL。
 * @param fromValue 取得値の格納先。
 * @param fromLogger ロガー。
 * @return 取得できた場合true。
 */
bool readLong(
    const int fromDatabaseHandle,
    const string fromSql,
    long &fromValue,
    Logger &fromLogger
) {
    fromValue = 0;
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
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

    if (!DatabaseColumnLong(requestHandle, 0, fromValue)) {
        int columnErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseColumnLong failed. error=%d",
                columnErrorCode
            )
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 3テーブルの行数を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunCount 期待Run数。
 * @param fromEntryCount 期待Entry数。
 * @param fromOutcomeCount 期待Outcome数。
 * @param fromLogger ロガー。
 * @return 全件数が一致する場合true。
 */
bool verifyCounts(
    const int fromDatabaseHandle,
    const long fromRunCount,
    const long fromEntryCount,
    const long fromOutcomeCount,
    Logger &fromLogger
) {
    long runCount = 0;
    long entryCount = 0;
    long outcomeCount = 0;

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcome_runs",
            runCount,
            fromLogger
        ) || !readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_h1_study_entries",
            entryCount,
            fromLogger
        ) || !readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcomes",
            outcomeCount,
            fromLogger
        )) {
        return false;
    }

    if (runCount == fromRunCount
            && entryCount == fromEntryCount
            && outcomeCount == fromOutcomeCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Count mismatch. runs=%I64d/%I64d entries=%I64d/%I64d outcomes=%I64d/%I64d",
            runCount,
            fromRunCount,
            entryCount,
            fromEntryCount,
            outcomeCount,
            fromOutcomeCount
        )
    );

    return false;
}

/**
 * 3テーブルが作成されていることを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 3テーブルが存在する場合true。
 */
bool verifyTables(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    long tableCount = 0;
    string sql = "SELECT COUNT(*) FROM sqlite_master ";
    sql += "WHERE type = 'table' AND name IN (";
    sql += "'zigzag_elliot_h1_study_outcome_runs',";
    sql += "'zigzag_elliot_h1_study_entries',";
    sql += "'zigzag_elliot_h1_study_outcomes')";

    return readLong(
            fromDatabaseHandle,
            sql,
            tableCount,
            fromLogger
        ) && tableCount == 3;
}

/**
 * 制約違反SQLが失敗することを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 制約違反させるSQL。
 * @param fromCaseName ケース名。
 * @param fromLogger ロガー。
 * @return SQLが拒否された場合true。
 */
bool verifySqlFailure(
    const int fromDatabaseHandle,
    const string fromSql,
    const string fromCaseName,
    Logger &fromLogger
) {
    ResetLastError();

    if (!DatabaseExecute(fromDatabaseHandle, fromSql)) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        "Constraint SQL unexpectedly succeeded. case=" + fromCaseName
    );

    return false;
}

/**
 * Smoke Test用研究Runを初期化する。
 *
 * @param fromRunKey 研究条件キー。
 * @param fromEntity 初期化対象。
 */
void initializeRun(
    const string fromRunKey,
    ZigZagElliotH1StudyOutcomeRunEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.runKey = fromRunKey;
    fromEntity.sourceDatabaseFileName = "h1-study-source-smoke.sqlite";
    fromEntity.sourceRunId = 101;
    fromEntity.sourceRunUid = "h1-study-source-run-smoke-v1";
    fromEntity.sourceMode = "TESTER";
    fromEntity.sourceServer = "h1-study-smoke-server";
    fromEntity.sourceLogin = 100001;
    fromEntity.sourceProgramName = "ZigZagElliotH1ObservationAll";
    fromEntity.sourceProgramVersion = "1.02-smoke";
    fromEntity.sourceStrategy = "H1_OBSERVATION_ALL";
    fromEntity.sourceStrategyVersion = "H1_OBSERVATION_ALL_V3";
    fromEntity.sourceAnalysisVersion = "ZZE_ANALYSIS_SMOKE_V1";
    fromEntity.sourceAnalysisInputHash = "analysis-input-hash-smoke";
    fromEntity.sourceInputHash = "program-input-hash-smoke";
    fromEntity.sourceTesterFrom = D'2024.01.01 00:00:00';
    fromEntity.sourceTesterTo = D'2025.12.31 23:59:59';
    fromEntity.sourceTesterModel = "OPEN_PRICES";
    fromEntity.studyFromJstTime = D'2024.01.01 00:00:00';
    fromEntity.studyToJstTime = D'2026.01.01 00:00:00';
    fromEntity.signalRuleVersion = "FULL_ALIGNMENT_EPISODE_V1";
    fromEntity.entryPriceModel = "NEXT_H1_OPEN_V1";
    fromEntity.spreadModel = "ENTRY_SPREAD_ONCE_V1";
    fromEntity.evaluationVersion = "H1_FIXED_HORIZONS_V1";
    fromEntity.horizonsText = "6,12,24,48";
    fromEntity.startedAt = D'2026.08.28 12:00:00';
    fromEntity.createdAt = fromEntity.startedAt;
}

/**
 * Smoke Test用研究Entryを初期化する。
 *
 * @param fromRunId Outcome Run ID。
 * @param fromConfirmationH1Count 連続確認本数。
 * @param fromEntity 初期化対象。
 */
void initializeEntry(
    const long fromRunId,
    const int fromConfirmationH1Count,
    ZigZagElliotH1StudyEntryEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.outcomeRunId = fromRunId;
    fromEntity.sourceRunId = 101;
    fromEntity.signalStartObservationId = 1001;
    fromEntity.signalEndObservationId = 1003;
    fromEntity.confirmationObservationId = 1000 + fromConfirmationH1Count;
    fromEntity.entryObservationId = 1001 + fromConfirmationH1Count;
    fromEntity.sourceMode = "TESTER";
    fromEntity.sourceServer = "h1-study-smoke-server";
    fromEntity.symbolName = "AUDUSD";
    fromEntity.anchorTimeFrame = (int)PERIOD_H1;
    fromEntity.capturePhase = "BAR_OPEN_FIRST_SUCCESS";
    fromEntity.analysisVersion = "ZZE_ANALYSIS_SMOKE_V1";
    fromEntity.analysisInputHash = "analysis-input-hash-smoke";
    fromEntity.side = "BUY";
    fromEntity.episodeH1Count = 3;
    fromEntity.confirmationH1Count = fromConfirmationH1Count;
    fromEntity.isResearchEligible = 1;
    fromEntity.eligibilityStatus = "ELIGIBLE";
    fromEntity.signalStartTime = D'2024.01.02 00:00:00';
    fromEntity.signalEndTime = D'2024.01.02 02:00:00';
    fromEntity.confirmationTime = fromEntity.signalStartTime
        + (fromConfirmationH1Count - 1) * 3600;
    fromEntity.entryTime = fromEntity.confirmationTime + 3600;
    fromEntity.signalStartJstTime = D'2024.01.02 09:00:00';
    fromEntity.confirmationJstTime = fromEntity.signalStartJstTime
        + (fromConfirmationH1Count - 1) * 3600;
    fromEntity.entryJstTime = fromEntity.confirmationJstTime + 3600;
    fromEntity.entryPrice = 0.68123;
    fromEntity.isSpreadAvailable = 1;
    fromEntity.spreadPips = 1.4;
    fromEntity.isPipSizeAvailable = 1;
    fromEntity.pipSize = 0.0001;
    fromEntity.pipSizeSource = "OBSERVATION";
    fromEntity.isEntryAtrAvailable = 1;
    fromEntity.entryAtr14Pips = 42.5;
    fromEntity.entryStatus = "READY";
    fromEntity.calculationNote = "smoke-entry";
    fromEntity.signalRuleVersion = "FULL_ALIGNMENT_EPISODE_V1";
    fromEntity.entryPriceModel = "NEXT_H1_OPEN_V1";
    fromEntity.spreadModel = "ENTRY_SPREAD_ONCE_V1";
    fromEntity.evaluationVersion = "H1_FIXED_HORIZONS_V1";
    fromEntity.createdAt = D'2026.08.28 12:00:01';
}

/**
 * Smoke Test用Outcomeを初期化する。
 *
 * 12Hだけ未計算とし、SQL NULL保存を検証する。
 *
 * @param fromEntryId Entry ID。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromEntity 初期化対象。
 */
void initializeOutcome(
    const long fromEntryId,
    const int fromHorizonH1Bars,
    ZigZagElliotH1StudyOutcomeEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.entryId = fromEntryId;
    fromEntity.horizonH1Bars = fromHorizonH1Bars;
    fromEntity.evaluatedH1Bars = fromHorizonH1Bars;
    fromEntity.dataStatus = "READY";
    fromEntity.calculationNote = "smoke-outcome";
    fromEntity.priceModel = "H1_BID_OHLC_V1";
    fromEntity.spreadModel = "ENTRY_SPREAD_ONCE_V1";
    fromEntity.evaluationVersion = "H1_FIXED_HORIZONS_V1";
    fromEntity.createdAt = D'2026.08.28 12:00:02';

    if (fromHorizonH1Bars == 12) {
        fromEntity.isCalculated = 0;
        fromEntity.evaluatedH1Bars = 8;
        fromEntity.dataStatus = "H1_HISTORY_INCOMPLETE";

        return;
    }

    fromEntity.isCalculated = 1;
    fromEntity.evaluationEndObservationId = 2000 + fromHorizonH1Bars;
    fromEntity.evaluationEndTime = D'2024.01.02 01:00:00'
        + fromHorizonH1Bars * 3600;
    fromEntity.exitPrice = 0.68123
        + (double)fromHorizonH1Bars * 0.0001;
    fromEntity.grossProfitPips = (double)fromHorizonH1Bars;
    fromEntity.netProfitPips = fromEntity.grossProfitPips - 1.4;
    fromEntity.grossProfitAtr =
        fromEntity.grossProfitPips / 42.5;
    fromEntity.netProfitAtr = fromEntity.netProfitPips / 42.5;
    fromEntity.mfePips = fromEntity.grossProfitPips + 3.0;
    fromEntity.maePips = 2.0;
    fromEntity.maxProfitH1Bars = fromHorizonH1Bars - 1;
}

/**
 * Entryと6、12、24、48H Outcomeを1トランザクションで保存する。
 *
 * @param fromDao Outcome DAO。
 * @param fromEntry 保存対象Entry。
 * @param fromEntryId 保存後Entry IDの格納先。
 * @param fromOutcomeIds 保存後Outcome ID一覧。
 * @return 5行をコミットできた場合true。
 */
bool saveEntryAndOutcomes(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    ZigZagElliotH1StudyEntryEntity &fromEntry,
    long &fromEntryId,
    long &fromOutcomeIds[]
) {
    fromEntryId = 0;
    ArrayResize(fromOutcomeIds, 0);

    if (!fromDao.beginTransaction()) {
        return false;
    }

    if (!fromDao.saveEntry(fromEntry)) {
        fromDao.rollbackTransaction();

        return false;
    }

    fromEntryId = fromEntry.id;
    int horizons[4] = {6, 12, 24, 48};
    ArrayResize(fromOutcomeIds, 4);

    for (int i = 0; i < 4; i++) {
        ZigZagElliotH1StudyOutcomeEntity outcome;
        initializeOutcome(fromEntry.id, horizons[i], outcome);

        if (!fromDao.saveOutcome(outcome)) {
            fromDao.rollbackTransaction();
            fromEntryId = 0;
            ArrayResize(fromOutcomeIds, 0);

            return false;
        }

        fromOutcomeIds[i] = outcome.id;
    }

    if (!fromDao.commitTransaction()) {
        fromDao.rollbackTransaction();
        fromEntryId = 0;
        ArrayResize(fromOutcomeIds, 0);

        return false;
    }

    return true;
}

/**
 * 12H未計算Outcomeの結果指標がSQL NULLか確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全結果指標がNULLの場合true。
 */
bool verifyUncalculatedOutcomeNulls(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    long nullCount = 0;
    string sql = "SELECT COUNT(*) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes ";
    sql += "WHERE horizon_h1_bars = 12 AND is_calculated = 0 ";
    sql += "AND evaluation_end_observation_id IS NULL ";
    sql += "AND evaluation_end_time IS NULL AND exit_price IS NULL ";
    sql += "AND gross_profit_pips IS NULL AND net_profit_pips IS NULL ";
    sql += "AND gross_profit_atr IS NULL AND net_profit_atr IS NULL ";
    sql += "AND mfe_pips IS NULL AND mae_pips IS NULL ";
    sql += "AND max_profit_h1_bars IS NULL";

    return readLong(
            fromDatabaseHandle,
            sql,
            nullCount,
            fromLogger
        ) && nullCount == 1;
}

/**
 * 計算済みOutcome値と4期間の存在を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 期待値と一致する場合true。
 */
bool verifyCalculatedOutcomes(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    long matchedCount = 0;
    string sql = "SELECT COUNT(*) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes ";
    sql += "WHERE horizon_h1_bars IN (6, 12, 24, 48) ";
    sql += "AND ((horizon_h1_bars = 12 ";
    sql += "AND is_calculated = 0 AND evaluated_h1_bars = 8) OR ";
    sql += "(horizon_h1_bars <> 12 AND is_calculated = 1 ";
    sql += "AND evaluated_h1_bars = horizon_h1_bars ";
    sql += "AND ABS(gross_profit_pips - horizon_h1_bars) < 0.0000001 ";
    sql += "AND ABS(net_profit_pips - (horizon_h1_bars - 1.4)) ";
    sql += "< 0.0000001))";

    return readLong(
            fromDatabaseHandle,
            sql,
            matchedCount,
            fromLogger
        ) && matchedCount == 4;
}

/**
 * EntryとOutcomeの自然キーUPSERTがIDと件数を維持するか確認する。
 *
 * @param fromDao Outcome DAO。
 * @param fromRunId Outcome Run ID。
 * @param fromFirstEntryId 初回Entry ID。
 * @param fromFirstOutcomeIds 初回Outcome ID一覧。
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return IDと件数が維持された場合true。
 */
bool verifyEntryOutcomeIdempotency(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    const long fromRunId,
    const long fromFirstEntryId,
    const long &fromFirstOutcomeIds[],
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    ZigZagElliotH1StudyEntryEntity entry;
    initializeEntry(fromRunId, 1, entry);
    entry.calculationNote = "smoke-entry-updated";
    long secondEntryId = 0;
    long secondOutcomeIds[];

    if (!saveEntryAndOutcomes(
            fromDao,
            entry,
            secondEntryId,
            secondOutcomeIds
        ) || secondEntryId != fromFirstEntryId
            || ArraySize(fromFirstOutcomeIds) != 4
            || ArraySize(secondOutcomeIds) != 4) {
        return false;
    }

    for (int i = 0; i < 4; i++) {
        if (secondOutcomeIds[i] != fromFirstOutcomeIds[i]) {
            return false;
        }
    }

    return verifyCounts(fromDatabaseHandle, 1, 1, 4, fromLogger);
}

/**
 * Entry＋Outcomeのロールバックを確認する。
 *
 * @param fromDao Outcome DAO。
 * @param fromRunId Outcome Run ID。
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return ロールバック後の件数が維持された場合true。
 */
bool verifyRollback(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    const long fromRunId,
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    if (!fromDao.beginTransaction()) {
        return false;
    }

    ZigZagElliotH1StudyEntryEntity entry;
    initializeEntry(fromRunId, 2, entry);

    if (!fromDao.saveEntry(entry)) {
        fromDao.rollbackTransaction();

        return false;
    }

    ZigZagElliotH1StudyOutcomeEntity outcome;
    initializeOutcome(entry.id, 6, outcome);

    if (!fromDao.saveOutcome(outcome)
            || !fromDao.rollbackTransaction()) {
        return false;
    }

    return verifyCounts(fromDatabaseHandle, 1, 1, 4, fromLogger);
}

/**
 * DAOがOutcome整合性違反とEMPTY_VALUEを拒否することを確認する。
 *
 * @param fromDao Outcome DAO。
 * @param fromRunId Outcome Run ID。
 * @param fromEntryId Entry ID。
 * @return 全不正値が拒否された場合true。
 */
bool verifyDaoValidation(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    const long fromRunId,
    const long fromEntryId
) {
    ZigZagElliotH1StudyOutcomeEntity outcome;
    initializeOutcome(fromEntryId, 6, outcome);
    outcome.dataStatus = "FUTURE_INCOMPLETE";

    if (fromDao.saveOutcome(outcome)) {
        return false;
    }

    initializeOutcome(fromEntryId, 12, outcome);
    outcome.dataStatus = "READY";

    if (fromDao.saveOutcome(outcome)) {
        return false;
    }

    initializeOutcome(fromEntryId, 6, outcome);
    outcome.mfePips = 0.0;
    outcome.maxProfitH1Bars = 1;

    if (fromDao.saveOutcome(outcome)) {
        return false;
    }

    initializeOutcome(fromEntryId, 6, outcome);
    outcome.maxProfitH1Bars = 0;

    if (fromDao.saveOutcome(outcome)) {
        return false;
    }

    initializeOutcome(fromEntryId, 6, outcome);
    outcome.exitPrice = EMPTY_VALUE;

    if (fromDao.saveOutcome(outcome)) {
        return false;
    }

    ZigZagElliotH1StudyEntryEntity entry;
    initializeEntry(fromRunId, 2, entry);
    entry.entryPrice = EMPTY_VALUE;

    return !fromDao.saveEntry(entry);
}

/**
 * 外部キーとCHECK制約が不正更新を拒否することを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromCalculatedOutcomeId 計算済みOutcome ID。
 * @param fromUncalculatedOutcomeId 未計算Outcome ID。
 * @param fromLogger ロガー。
 * @return 全不正更新が拒否された場合true。
 */
bool verifyConstraints(
    const int fromDatabaseHandle,
    const long fromCalculatedOutcomeId,
    const long fromUncalculatedOutcomeId,
    Logger &fromLogger
) {
    string invalidHorizonSql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET horizon_h1_bars = 7 WHERE id = %I64d",
        fromCalculatedOutcomeId
    );
    string invalidForeignKeySql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET entry_id = 999999999 WHERE id = %I64d",
        fromCalculatedOutcomeId
    );
    string invalidCalculatedStatusSql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET data_status = 'FUTURE_INCOMPLETE' WHERE id = %I64d",
        fromCalculatedOutcomeId
    );
    string invalidUncalculatedStatusSql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET data_status = 'READY' WHERE id = %I64d",
        fromUncalculatedOutcomeId
    );
    string invalidPositiveMfeSql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET max_profit_h1_bars = 0 WHERE id = %I64d",
        fromCalculatedOutcomeId
    );
    string invalidZeroMfeSql = StringFormat(
        "UPDATE zigzag_elliot_h1_study_outcomes SET mfe_pips = 0, max_profit_h1_bars = 1 WHERE id = %I64d",
        fromCalculatedOutcomeId
    );

    return verifySqlFailure(
            fromDatabaseHandle,
            invalidHorizonSql,
            "horizon check",
            fromLogger
        ) && verifySqlFailure(
            fromDatabaseHandle,
            invalidForeignKeySql,
            "entry foreign key",
            fromLogger
        ) && verifySqlFailure(
            fromDatabaseHandle,
            invalidCalculatedStatusSql,
            "calculated status consistency",
            fromLogger
        ) && verifySqlFailure(
            fromDatabaseHandle,
            invalidUncalculatedStatusSql,
            "uncalculated status consistency",
            fromLogger
        ) && verifySqlFailure(
            fromDatabaseHandle,
            invalidPositiveMfeSql,
            "positive MFE max profit bar consistency",
            fromLogger
        ) && verifySqlFailure(
            fromDatabaseHandle,
            invalidZeroMfeSql,
            "zero MFE max profit bar consistency",
            fromLogger
        );
}

/**
 * 完了件数とFAILED専用更新を確認する。
 *
 * @param fromDao Outcome DAO。
 * @param fromRunId 完了対象Run ID。
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 両状態を確認できた場合true。
 */
bool verifyRunCompletion(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    const long fromRunId,
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    const long missingRunId = 999999999;

    if (fromDao.completeRun(
            missingRunId,
            "COMPLETED",
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ) || fromDao.failRun(
            missingRunId,
            D'2026.08.28 12:29:00'
        )) {
        return false;
    }

    if (!fromDao.completeRun(
            fromRunId,
            "COMPLETED",
            1,
            1,
            1,
            1,
            4,
            3,
            1
        )) {
        return false;
    }

    long completedCount = 0;
    string completedSql = "SELECT COUNT(*) ";
    completedSql += "FROM zigzag_elliot_h1_study_outcome_runs ";
    completedSql += StringFormat("WHERE id = %I64d ", fromRunId);
    completedSql += "AND status = 'COMPLETED' ";
    completedSql += "AND source_stream_count = 1 ";
    completedSql += "AND total_signal_count = 1 ";
    completedSql += "AND total_entry_count = 1 ";
    completedSql += "AND research_eligible_entry_count = 1 ";
    completedSql += "AND total_outcome_count = 4 ";
    completedSql += "AND calculated_outcome_count = 3 ";
    completedSql += "AND failed_outcome_count = 1 ";
    completedSql += "AND completed_at IS NOT NULL";

    if (!readLong(
            fromDatabaseHandle,
            completedSql,
            completedCount,
            fromLogger
        ) || completedCount != 1) {
        return false;
    }

    ZigZagElliotH1StudyOutcomeRunEntity failedRun;
    initializeRun("h1-study-outcome-smoke-failed-v1", failedRun);
    long failedRunId = 0;

    if (!fromDao.findOrCreateRun(failedRun, failedRunId)
            || !fromDao.failRun(
                failedRunId,
                D'2026.08.28 12:30:00'
            )) {
        return false;
    }

    long failedCount = 0;
    string failedSql = "SELECT COUNT(*) ";
    failedSql += "FROM zigzag_elliot_h1_study_outcome_runs ";
    failedSql += StringFormat("WHERE id = %I64d ", failedRunId);
    failedSql += "AND status = 'FAILED' ";
    failedSql += "AND completed_at = ";
    failedSql += IntegerToString((int)D'2026.08.28 12:30:00');

    return readLong(
            fromDatabaseHandle,
            failedSql,
            failedCount,
            fromLogger
        ) && failedCount == 1;
}

/**
 * DAOのDDL、保存、冪等性、NULLおよび制約を検証する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全検証に成功した場合true。
 */
bool runSmokeTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    ZigZagElliotH1StudyOutcomeDao dao(fromDatabaseHandle);

    if (!dao.createTables()
            || !dao.createTables()
            || !verifyTables(fromDatabaseHandle, fromLogger)) {
        return false;
    }

    ZigZagElliotH1StudyOutcomeRunEntity run;
    initializeRun("h1-study-outcome-smoke-v1", run);
    long runId = 0;

    if (!dao.findOrCreateRun(run, runId)
            || !dao.deleteRunChildren(runId)) {
        return false;
    }

    ZigZagElliotH1StudyEntryEntity entry;
    initializeEntry(runId, 1, entry);
    long firstEntryId = 0;
    long firstOutcomeIds[];

    if (!saveEntryAndOutcomes(
            dao,
            entry,
            firstEntryId,
            firstOutcomeIds
        ) || !verifyCounts(fromDatabaseHandle, 1, 1, 4, fromLogger)
            || !verifyUncalculatedOutcomeNulls(
                fromDatabaseHandle,
                fromLogger
            ) || !verifyCalculatedOutcomes(
                fromDatabaseHandle,
                fromLogger
            )) {
        return false;
    }

    long repeatedRunId = 0;

    if (!dao.findOrCreateRun(run, repeatedRunId)
            || repeatedRunId != runId
            || !verifyEntryOutcomeIdempotency(
                dao,
                runId,
                firstEntryId,
                firstOutcomeIds,
                fromDatabaseHandle,
                fromLogger
            ) || !verifyRollback(
                dao,
                runId,
                fromDatabaseHandle,
                fromLogger
            ) || !verifyDaoValidation(
                dao,
                runId,
                firstEntryId
            ) || ArraySize(firstOutcomeIds) != 4
            || !verifyConstraints(
                fromDatabaseHandle,
                firstOutcomeIds[0],
                firstOutcomeIds[1],
                fromLogger
            )) {
        return false;
    }

    if (!dao.deleteRunChildren(runId)
            || !verifyCounts(fromDatabaseHandle, 1, 0, 0, fromLogger)) {
        return false;
    }

    initializeEntry(runId, 1, entry);
    long finalEntryId = 0;
    long finalOutcomeIds[];

    if (!saveEntryAndOutcomes(
            dao,
            entry,
            finalEntryId,
            finalOutcomeIds
        ) || !verifyCounts(fromDatabaseHandle, 1, 1, 4, fromLogger)
            || !verifyRunCompletion(
                dao,
                runId,
                fromDatabaseHandle,
                fromLogger
            ) || !verifyCounts(fromDatabaseHandle, 2, 1, 4, fromLogger)) {
        return false;
    }

    return true;
}

/**
 * H1推移研究Outcome DBのSmoke Testを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!deleteTestDatabaseFiles()) {
        logger.error(__FUNCTION__, "Initial smoke database deletion failed.");

        return;
    }

    SqliteDatabase database(databaseFileName, databaseUseCommonFolder);
    bool isPassed = false;

    if (database.open()) {
        isPassed = runSmokeTest(database.getHandle(), logger);
    }

    database.close();
    bool isDeleted = deleteTestDatabaseFiles();

    if (isPassed && isDeleted) {
        logger.info(
            __FUNCTION__,
            "ZigZagElliot H1 study outcome database smoke test passed."
        );

        return;
    }

    logger.error(
        __FUNCTION__,
        StringFormat(
            "ZigZagElliot H1 study outcome database smoke test failed. passed=%d deleted=%d",
            (int)isPassed,
            (int)isDeleted
        )
    );
}
