//+------------------------------------------------------------------+
//|              ZigZagElliotH1StudyBaselineExporter.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** H1推移研究Outcome DBファイル名。 */
input string outcomeDatabaseFileName =
    "mstng-zigzag-elliot-h1-study-outcome-2024-2025-r1.sqlite";

/** 集計対象Outcome Run ID。0の場合は完了Runを自動選択する。 */
input long outcomeRunId = 0;

/** Outcome DBをTerminal Common Filesから読み取る場合true。 */
input bool databaseUseCommonFolder = true;

/** 出力CSVファイル名。空の場合はDB名とRun IDから自動生成する。 */
input string outputCsvFileName = "";

/** CSVをTerminal Common Filesへ出力する場合true。 */
input bool outputUseCommonFolder = true;

/** 基準成績CSVのスキーマバージョン。 */
const string baselineCsvSchemaVersion = "H1_STUDY_BASELINE_V1";

/** 基準成績CSVの列数。 */
const int baselineCsvFieldCount = 48;

/** 集計方向数。 */
const int baselineSideScopeCount = 3;

/** 連続確認本数の種類数。 */
const int baselineConfirmationCount = 3;

/** 評価期間の種類数。 */
const int baselineHorizonCount = 4;

/** 出力対象グループ数。 */
const int baselineExpectedRowCount = 36;

/** 完了済みOutcome Runの基準集計用情報。 */
struct ZigZagElliotH1StudyBaselineRunInfo {
    /** Outcome Run ID。 */
    long id;

    /** Outcome Runの一意キー。 */
    string runKey;

    /** 参照元H1推移DBファイル名。 */
    string sourceDatabaseFileName;

    /** 参照元H1推移Run ID。 */
    long sourceRunId;

    /** 参照元H1推移Run UID。 */
    string sourceRunUid;

    /** 研究対象開始JST。 */
    datetime studyFromJstTime;

    /** 研究対象終了JSTの対象外境界。 */
    datetime studyToJstTime;

    /** 連続シグナル判定ルールバージョン。 */
    string signalRuleVersion;

    /** 研究用エントリー価格モデル。 */
    string entryPriceModel;

    /** Outcome価格モデル。 */
    string outcomePriceModel;

    /** Spread控除モデル。 */
    string spreadModel;

    /** 将来成績計算ロジックバージョン。 */
    string evaluationVersion;

    /** 評価期間一覧。 */
    string horizonsText;

    /** Run状態。 */
    string status;

    /** Runへ記録されたEntry総数。 */
    long totalEntryCount;

    /** Runへ記録された研究対象Entry数。 */
    long researchEligibleEntryCount;

    /** Runへ記録されたOutcome総数。 */
    long totalOutcomeCount;

    /** Runへ記録された計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** Runへ記録された計算不能Outcome数。 */
    long failedOutcomeCount;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.runKey = "";
        this.sourceDatabaseFileName = "";
        this.sourceRunId = 0;
        this.sourceRunUid = "";
        this.studyFromJstTime = 0;
        this.studyToJstTime = 0;
        this.signalRuleVersion = "";
        this.entryPriceModel = "";
        this.outcomePriceModel = "";
        this.spreadModel = "";
        this.evaluationVersion = "";
        this.horizonsText = "";
        this.status = "";
        this.totalEntryCount = 0;
        this.researchEligibleEntryCount = 0;
        this.totalOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
    }
};

/** 1グループの基準成績。 */
struct ZigZagElliotH1StudyBaselineRow {
    /** ALL、BUYまたはSELL。 */
    string sideScope;

    /** 連続確認H1本数。 */
    int confirmationH1Count;

    /** 評価H1本数。 */
    int horizonH1Bars;

    /** 研究対象外を含む候補Entry数。 */
    long candidateEntryCount;

    /** 研究対象外Entry数。 */
    long ineligibleEntryCount;

    /** 研究対象Entry数。 */
    long eligibleEntryCount;

    /** 研究対象Entryに存在するOutcome数。 */
    long eligibleOutcomeCount;

    /** 計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** 計算不能Outcome数。 */
    long failedOutcomeCount;

    /** 存在しないOutcome数。 */
    long missingOutcomeCount;

    /** 将来H1 Gapによる計算不能数。 */
    long futureH1GapCount;

    /** 将来H1 Gap以外による計算不能数。 */
    long otherFailureCount;

    /** 研究対象に対する計算成功率。 */
    double calculationCoveragePercent;

    /** 研究対象に対する将来H1 Gap率。 */
    double dataGapRatePercent;

    /** Spread控除後損益が正の件数。 */
    long winningCount;

    /** Spread控除後損益が負の件数。 */
    long losingCount;

    /** Spread控除後損益が0の件数。 */
    long breakevenCount;

    /** 計算成功Outcomeに対する勝率。 */
    double winRatePercent;

    /** 成績統計を計算可能な場合true。 */
    bool isStatisticsAvailable;

    /** Spread控除後損益の合計。 */
    double netProfitSumPips;

    /** 方向別損益の平均。 */
    double averageGrossProfitPips;

    /** Spread控除後損益の平均。 */
    double averageNetProfitPips;

    /** Spread控除後損益の中央値。 */
    double medianNetProfitPips;

    /** 正のSpread控除後損益合計。 */
    double winningNetProfitSumPips;

    /** 負のSpread控除後損益の絶対値合計。 */
    double losingNetProfitAbsSumPips;

    /** Profit Factor。 */
    double profitFactor;

    /** AVAILABLE、INFINITE_NO_LOSS、NO_VARIATIONまたはNO_SAMPLE。 */
    string profitFactorStatus;

    /** MFE平均。 */
    double averageMfePips;

    /** MAE平均。 */
    double averageMaePips;

    /** 方向別損益のATR換算平均。 */
    double averageGrossProfitAtr;

    /** Spread控除後損益のATR換算平均。 */
    double averageNetProfitAtr;

    /** 最大利益へ最初に到達するまでのH1本数平均。 */
    double averageMaxProfitH1Bars;

    /** 研究対象Entryの取得時Spread平均。 */
    double averageEntrySpreadPips;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.sideScope = "";
        this.confirmationH1Count = 0;
        this.horizonH1Bars = 0;
        this.candidateEntryCount = 0;
        this.ineligibleEntryCount = 0;
        this.eligibleEntryCount = 0;
        this.eligibleOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
        this.missingOutcomeCount = 0;
        this.futureH1GapCount = 0;
        this.otherFailureCount = 0;
        this.calculationCoveragePercent = 0.0;
        this.dataGapRatePercent = 0.0;
        this.winningCount = 0;
        this.losingCount = 0;
        this.breakevenCount = 0;
        this.winRatePercent = 0.0;
        this.isStatisticsAvailable = false;
        this.netProfitSumPips = 0.0;
        this.averageGrossProfitPips = 0.0;
        this.averageNetProfitPips = 0.0;
        this.medianNetProfitPips = 0.0;
        this.winningNetProfitSumPips = 0.0;
        this.losingNetProfitAbsSumPips = 0.0;
        this.profitFactor = 0.0;
        this.profitFactorStatus = "NO_SAMPLE";
        this.averageMfePips = 0.0;
        this.averageMaePips = 0.0;
        this.averageGrossProfitAtr = 0.0;
        this.averageNetProfitAtr = 0.0;
        this.averageMaxProfitH1Bars = 0.0;
        this.averageEntrySpreadPips = 0.0;
    }
};

/**
 * 集計方向を配列位置から取得する。
 *
 * @param fromIndex 配列位置。
 * @return ALL、BUY、SELLのいずれか。範囲外は空文字。
 */
string getBaselineSideScope(const int fromIndex) {
    if (fromIndex == 0) {
        return "ALL";
    }

    if (fromIndex == 1) {
        return "BUY";
    }

    if (fromIndex == 2) {
        return "SELL";
    }

    return "";
}

/**
 * 連続確認本数を配列位置から取得する。
 *
 * @param fromIndex 配列位置。
 * @return 1、2または3。範囲外は0。
 */
int getBaselineConfirmationH1Count(const int fromIndex) {
    if (fromIndex >= 0 && fromIndex < baselineConfirmationCount) {
        return fromIndex + 1;
    }

    return 0;
}

/**
 * 評価H1本数を配列位置から取得する。
 *
 * @param fromIndex 配列位置。
 * @return 6、12、24または48。範囲外は0。
 */
int getBaselineHorizonH1Bars(const int fromIndex) {
    if (fromIndex == 0) {
        return 6;
    }

    if (fromIndex == 1) {
        return 12;
    }

    if (fromIndex == 2) {
        return 24;
    }

    if (fromIndex == 3) {
        return 48;
    }

    return 0;
}

/**
 * ファイル名がCSV拡張子を持つか確認する。
 *
 * @param fromFileName 確認対象。
 * @return 末尾が.csvの場合true。
 */
bool isBaselineCsvFileName(const string fromFileName) {
    int fileNameLength = StringLen(fromFileName);

    if (fileNameLength < 5) {
        return false;
    }

    return StringCompare(
        StringSubstr(fromFileName, fileNameLength - 4),
        ".csv",
        false
    ) == 0;
}

/**
 * Script入力を検証する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateBaselineInputs(Logger &fromLogger) {
    if (outcomeDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "outcomeDatabaseFileName is empty.");

        return false;
    }

    if (outcomeRunId < 0) {
        fromLogger.error(__FUNCTION__, "outcomeRunId must not be negative.");

        return false;
    }

    if (outputCsvFileName != ""
            && !isBaselineCsvFileName(outputCsvFileName)) {
        fromLogger.error(
            __FUNCTION__,
            "outputCsvFileName must have a .csv extension."
        );

        return false;
    }

    if (outputCsvFileName != ""
            && StringCompare(
                outputCsvFileName,
                outcomeDatabaseFileName,
                false
            ) == 0
            && outputUseCommonFolder == databaseUseCommonFolder) {
        fromLogger.error(
            __FUNCTION__,
            "Outcome DB and output CSV must be different files."
        );

        return false;
    }

    return true;
}

/**
 * 現在行からRun情報を読み取る。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRunInfo 読取先。
 * @param fromLogger ロガー。
 * @return 全列を読み取れた場合true。
 */
bool readBaselineRunInfo(
    const int fromRequestHandle,
    ZigZagElliotH1StudyBaselineRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();
    long studyFromJstTimeValue = 0;
    long studyToJstTimeValue = 0;
    bool isRead = DatabaseColumnLong(fromRequestHandle, 0, fromRunInfo.id);

    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            1,
            fromRunInfo.runKey
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            2,
            fromRunInfo.sourceDatabaseFileName
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            3,
            fromRunInfo.sourceRunId
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            4,
            fromRunInfo.sourceRunUid
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            5,
            studyFromJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            6,
            studyToJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            7,
            fromRunInfo.signalRuleVersion
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            8,
            fromRunInfo.entryPriceModel
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            9,
            fromRunInfo.spreadModel
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            10,
            fromRunInfo.evaluationVersion
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            11,
            fromRunInfo.horizonsText
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            12,
            fromRunInfo.status
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            13,
            fromRunInfo.totalEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            14,
            fromRunInfo.researchEligibleEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            15,
            fromRunInfo.totalOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            16,
            fromRunInfo.calculatedOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            17,
            fromRunInfo.failedOutcomeCount
        );
    }

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn read failed. error=%d", GetLastError())
        );

        return false;
    }

    fromRunInfo.studyFromJstTime = (datetime)studyFromJstTimeValue;
    fromRunInfo.studyToJstTime = (datetime)studyToJstTimeValue;

    return true;
}

/**
 * 集計対象の完了Runを選択する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfo 選択結果。
 * @param fromLogger ロガー。
 * @return 1件のRunを選択できた場合true。
 */
bool selectBaselineRun(
    const int fromDatabaseHandle,
    ZigZagElliotH1StudyBaselineRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();
    string sql = "SELECT id, run_key, source_database_file_name,";
    sql += " source_run_id, source_run_uid, study_from_jst_time,";
    sql += " study_to_jst_time, signal_rule_version, entry_price_model,";
    sql += " spread_model, evaluation_version, horizons_text, status,";
    sql += " total_entry_count, research_eligible_entry_count,";
    sql += " total_outcome_count, calculated_outcome_count,";
    sql += " failed_outcome_count ";
    sql += "FROM zigzag_elliot_h1_study_outcome_runs ";
    sql += "WHERE status = 'COMPLETED' AND (?1 = 0 OR id = ?1) ";
    sql += "ORDER BY id ASC";

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

    if (!DatabaseBind(requestHandle, 0, outcomeRunId)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    int runCount = 0;

    while (true) {
        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            break;
        }

        runCount++;

        if (runCount > 1) {
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                "outcomeRunId=0 requires exactly one completed Run."
            );

            return false;
        }

        if (!readBaselineRunInfo(requestHandle, fromRunInfo, fromLogger)) {
            DatabaseFinalize(requestHandle);

            return false;
        }
    }

    if (runCount != 1) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Completed Outcome Run was not selected. requested=%I64d",
                outcomeRunId
            )
        );

        return false;
    }

    if (fromRunInfo.id <= 0
            || fromRunInfo.runKey == ""
            || fromRunInfo.sourceDatabaseFileName == ""
            || fromRunInfo.sourceRunId <= 0
            || fromRunInfo.sourceRunUid == ""
            || fromRunInfo.studyFromJstTime <= 0
            || fromRunInfo.studyToJstTime <= fromRunInfo.studyFromJstTime
            || fromRunInfo.signalRuleVersion == ""
            || fromRunInfo.entryPriceModel == ""
            || fromRunInfo.spreadModel == ""
            || fromRunInfo.evaluationVersion == ""
            || fromRunInfo.horizonsText != "6,12,24,48"
            || fromRunInfo.status != "COMPLETED") {
        fromLogger.error(
            __FUNCTION__,
            "Selected Outcome Run metadata is invalid."
        );

        return false;
    }

    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "Completed Outcome Run was selected. outcomeRunId=%I64d sourceRunId=%I64d",
            fromRunInfo.id,
            fromRunInfo.sourceRunId
        )
    );

    return true;
}

/**
 * Runカウンタと保存行の整合性を検証する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfo 選択したRun。
 * @param fromLogger ロガー。
 * @return 基準集計に使用可能な場合true。
 */
bool validateBaselineRunData(
    const int fromDatabaseHandle,
    ZigZagElliotH1StudyBaselineRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    string sql = "SELECT ";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(is_research_eligible), 0) ";
    sql += "FROM zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1),";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(o.is_calculated), 0) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(1 - o.is_calculated), 0) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COUNT(*) FROM (SELECT e.id FROM ";
    sql += "zigzag_elliot_h1_study_entries AS e LEFT JOIN ";
    sql += "zigzag_elliot_h1_study_outcomes AS o ON o.entry_id = e.id ";
    sql += "WHERE e.outcome_run_id = ?1 GROUP BY e.id ";
    sql += "HAVING COUNT(o.id) <> 4)),";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "JOIN zigzag_elliot_h1_study_outcome_runs AS r ";
    sql += "ON r.id = e.outcome_run_id WHERE e.outcome_run_id = ?1 AND (";
    sql += "e.signal_rule_version <> r.signal_rule_version OR ";
    sql += "e.entry_price_model <> r.entry_price_model OR ";
    sql += "e.spread_model <> r.spread_model OR ";
    sql += "e.evaluation_version <> r.evaluation_version OR ";
    sql += "o.spread_model <> r.spread_model OR ";
    sql += "o.evaluation_version <> r.evaluation_version OR ";
    sql += "o.price_model = '' OR ";
    sql += "(o.is_calculated = 1 AND o.data_status <> 'READY') OR ";
    sql += "(o.is_calculated = 0 AND o.data_status = 'READY'))),";
    sql += "(SELECT COUNT(DISTINCT o.price_model) FROM ";
    sql += "zigzag_elliot_h1_study_outcomes AS o JOIN ";
    sql += "zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(MIN(o.price_model), '') FROM ";
    sql += "zigzag_elliot_h1_study_outcomes AS o JOIN ";
    sql += "zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1)";

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

    if (!DatabaseBind(requestHandle, 0, fromRunInfo.id)) {
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

    long entryCount = 0;
    long eligibleEntryCount = 0;
    long outcomeCount = 0;
    long calculatedCount = 0;
    long failedCount = 0;
    long incompleteEntryCount = 0;
    long metadataMismatchCount = 0;
    long priceModelCount = 0;
    string outcomePriceModel = "";
    bool isRead = DatabaseColumnLong(requestHandle, 0, entryCount);

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 1, eligibleEntryCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, outcomeCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 3, calculatedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 4, failedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 5, incompleteEntryCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 6, metadataMismatchCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 7, priceModelCount);
    }
    if (isRead) {
        isRead = DatabaseColumnText(requestHandle, 8, outcomePriceModel);
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn read failed. error=%d", columnErrorCode)
        );

        return false;
    }

    bool isConsistent = entryCount == fromRunInfo.totalEntryCount
        && eligibleEntryCount == fromRunInfo.researchEligibleEntryCount
        && outcomeCount == fromRunInfo.totalOutcomeCount
        && calculatedCount == fromRunInfo.calculatedOutcomeCount
        && failedCount == fromRunInfo.failedOutcomeCount
        && incompleteEntryCount == 0
        && metadataMismatchCount == 0
        && priceModelCount == 1
        && outcomePriceModel != "";

    if (!isConsistent) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Outcome Run data mismatch. entries=%I64d/%I64d eligible=%I64d/%I64d outcomes=%I64d/%I64d calculated=%I64d/%I64d failed=%I64d/%I64d incomplete=%I64d metadata=%I64d priceModels=%I64d",
                entryCount,
                fromRunInfo.totalEntryCount,
                eligibleEntryCount,
                fromRunInfo.researchEligibleEntryCount,
                outcomeCount,
                fromRunInfo.totalOutcomeCount,
                calculatedCount,
                fromRunInfo.calculatedOutcomeCount,
                failedCount,
                fromRunInfo.failedOutcomeCount,
                incompleteEntryCount,
                metadataMismatchCount,
                priceModelCount
            )
        );

        return false;
    }

    fromRunInfo.outcomePriceModel = outcomePriceModel;

    return true;
}

/**
 * 基準成績集計SQLへ共通条件を設定する。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromSideScope ALL、BUYまたはSELL。
 * @param fromConfirmationH1Count 連続確認H1本数。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromLogger ロガー。
 * @param fromMethodName 呼び出し元メソッド名。
 * @return 全条件を設定できた場合true。
 */
bool bindBaselineGroupInputs(
    const int fromRequestHandle,
    const long fromRunId,
    const string fromSideScope,
    const int fromConfirmationH1Count,
    const int fromHorizonH1Bars,
    Logger &fromLogger,
    const string fromMethodName
) {
    ResetLastError();
    bool isBound = DatabaseBind(fromRequestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 1, fromSideScope);
    }
    if (isBound) {
        isBound = DatabaseBind(
            fromRequestHandle,
            2,
            fromConfirmationH1Count
        );
    }
    if (isBound) {
        isBound = DatabaseBind(
            fromRequestHandle,
            3,
            fromHorizonH1Bars
        );
    }

    if (isBound) {
        return true;
    }

    int bindErrorCode = GetLastError();
    DatabaseFinalize(fromRequestHandle);
    fromLogger.error(
        fromMethodName,
        StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
    );

    return false;
}

/**
 * 1グループのSpread控除後損益中央値を取得する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromRow 対象グループ。
 * @param fromMedian 読取先中央値。
 * @param fromLogger ロガー。
 * @return 中央値を取得できた場合true。
 */
bool findBaselineMedian(
    const int fromDatabaseHandle,
    const long fromRunId,
    ZigZagElliotH1StudyBaselineRow &fromRow,
    double &fromMedian,
    Logger &fromLogger
) {
    fromMedian = 0.0;

    if (fromRow.calculatedOutcomeCount <= 0) {
        return true;
    }

    string sql = "SELECT AVG(values_row.net_profit_pips) FROM (";
    sql += "SELECT o.net_profit_pips FROM ";
    sql += "zigzag_elliot_h1_study_entries AS e JOIN ";
    sql += "zigzag_elliot_h1_study_outcomes AS o ON o.entry_id = e.id ";
    sql += "WHERE e.outcome_run_id = ?1 ";
    sql += "AND (?2 = 'ALL' OR e.side = ?2) ";
    sql += "AND e.confirmation_h1_count = ?3 ";
    sql += "AND o.horizon_h1_bars = ?4 ";
    sql += "AND e.is_research_eligible = 1 AND o.is_calculated = 1 ";
    sql += "ORDER BY o.net_profit_pips ASC, o.id ASC ";
    sql += "LIMIT ?5 OFFSET ?6) AS values_row";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindBaselineGroupInputs(
            requestHandle,
            fromRunId,
            fromRow.sideScope,
            fromRow.confirmationH1Count,
            fromRow.horizonH1Bars,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    int medianValueCount = 1;

    if (fromRow.calculatedOutcomeCount % 2 == 0) {
        medianValueCount = 2;
    }

    long medianOffset = (fromRow.calculatedOutcomeCount - 1) / 2;
    ResetLastError();
    bool isBound = DatabaseBind(requestHandle, 4, medianValueCount);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 5, medianOffset);
    }

    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("Median DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("Median DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    ResetLastError();
    bool isRead = DatabaseColumnDouble(requestHandle, 0, fromMedian);
    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Median DatabaseColumnDouble failed. error=%d",
                columnErrorCode
            )
        );

        return false;
    }

    return true;
}

/**
 * 1グループの基準成績を集計する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromSideScope ALL、BUYまたはSELL。
 * @param fromConfirmationH1Count 連続確認H1本数。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromRow 集計結果。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool aggregateBaselineRow(
    const int fromDatabaseHandle,
    const long fromRunId,
    const string fromSideScope,
    const int fromConfirmationH1Count,
    const int fromHorizonH1Bars,
    ZigZagElliotH1StudyBaselineRow &fromRow,
    Logger &fromLogger
) {
    fromRow.reset();
    fromRow.sideScope = fromSideScope;
    fromRow.confirmationH1Count = fromConfirmationH1Count;
    fromRow.horizonH1Bars = fromHorizonH1Bars;
    string sql = "SELECT COUNT(e.id),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 0 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.id IS NOT NULL THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.id IS NOT NULL AND o.is_calculated = 0 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.data_status = 'FUTURE_H1_GAP' THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 AND o.net_profit_pips > 0 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 AND o.net_profit_pips < 0 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 AND o.net_profit_pips = 0 ";
    sql += "THEN 1 ELSE 0 END), 0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.net_profit_pips ";
    sql += "ELSE 0.0 END), 0.0),";
    sql += "COALESCE(SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 AND o.net_profit_pips > 0 ";
    sql += "THEN o.net_profit_pips ELSE 0.0 END), 0.0),";
    sql += "COALESCE(-SUM(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 AND o.net_profit_pips < 0 ";
    sql += "THEN o.net_profit_pips ELSE 0.0 END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.gross_profit_pips END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.net_profit_pips END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.mfe_pips END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.mae_pips END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.gross_profit_atr END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.net_profit_atr END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "AND o.is_calculated = 1 THEN o.max_profit_h1_bars END), 0.0),";
    sql += "COALESCE(AVG(CASE WHEN e.is_research_eligible = 1 ";
    sql += "THEN e.spread_pips END), 0.0) ";
    sql += "FROM zigzag_elliot_h1_study_entries AS e LEFT JOIN ";
    sql += "zigzag_elliot_h1_study_outcomes AS o ON o.entry_id = e.id ";
    sql += "AND o.horizon_h1_bars = ?4 ";
    sql += "WHERE e.outcome_run_id = ?1 ";
    sql += "AND (?2 = 'ALL' OR e.side = ?2) ";
    sql += "AND e.confirmation_h1_count = ?3";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindBaselineGroupInputs(
            requestHandle,
            fromRunId,
            fromSideScope,
            fromConfirmationH1Count,
            fromHorizonH1Bars,
            fromLogger,
            __FUNCTION__
        )) {
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

    bool isRead = DatabaseColumnLong(
        requestHandle,
        0,
        fromRow.candidateEntryCount
    );

    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            1,
            fromRow.ineligibleEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            2,
            fromRow.eligibleEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            3,
            fromRow.eligibleOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            4,
            fromRow.calculatedOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            5,
            fromRow.failedOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            6,
            fromRow.futureH1GapCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 7, fromRow.winningCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 8, fromRow.losingCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            9,
            fromRow.breakevenCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            10,
            fromRow.netProfitSumPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            11,
            fromRow.winningNetProfitSumPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            12,
            fromRow.losingNetProfitAbsSumPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            13,
            fromRow.averageGrossProfitPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            14,
            fromRow.averageNetProfitPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            15,
            fromRow.averageMfePips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            16,
            fromRow.averageMaePips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            17,
            fromRow.averageGrossProfitAtr
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            18,
            fromRow.averageNetProfitAtr
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            19,
            fromRow.averageMaxProfitH1Bars
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            requestHandle,
            20,
            fromRow.averageEntrySpreadPips
        );
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn read failed. error=%d", columnErrorCode)
        );

        return false;
    }

    fromRow.missingOutcomeCount = fromRow.eligibleEntryCount
        - fromRow.eligibleOutcomeCount;
    fromRow.otherFailureCount = fromRow.failedOutcomeCount
        - fromRow.futureH1GapCount;
    fromRow.isStatisticsAvailable =
        fromRow.calculatedOutcomeCount > 0;

    if (fromRow.eligibleEntryCount > 0) {
        fromRow.calculationCoveragePercent = 100.0
            * (double)fromRow.calculatedOutcomeCount
            / (double)fromRow.eligibleEntryCount;
        fromRow.dataGapRatePercent = 100.0
            * (double)fromRow.futureH1GapCount
            / (double)fromRow.eligibleEntryCount;
    }

    if (fromRow.isStatisticsAvailable) {
        fromRow.winRatePercent = 100.0
            * (double)fromRow.winningCount
            / (double)fromRow.calculatedOutcomeCount;
    }

    if (fromRow.calculatedOutcomeCount <= 0) {
        fromRow.profitFactorStatus = "NO_SAMPLE";
    } else if (fromRow.losingNetProfitAbsSumPips > 0.0) {
        fromRow.profitFactorStatus = "AVAILABLE";
        fromRow.profitFactor = fromRow.winningNetProfitSumPips
            / fromRow.losingNetProfitAbsSumPips;
    } else if (fromRow.winningNetProfitSumPips > 0.0) {
        fromRow.profitFactorStatus = "INFINITE_NO_LOSS";
    } else {
        fromRow.profitFactorStatus = "NO_VARIATION";
    }

    bool isConsistent = fromRow.candidateEntryCount
            == fromRow.ineligibleEntryCount + fromRow.eligibleEntryCount
        && fromRow.eligibleOutcomeCount
            == fromRow.calculatedOutcomeCount + fromRow.failedOutcomeCount
        && fromRow.missingOutcomeCount >= 0
        && fromRow.otherFailureCount >= 0
        && fromRow.calculatedOutcomeCount
            == fromRow.winningCount
                + fromRow.losingCount
                + fromRow.breakevenCount;

    if (!isConsistent) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Baseline group count mismatch. side=%s confirmation=%d horizon=%d candidate=%I64d ineligible=%I64d eligible=%I64d outcomes=%I64d calculated=%I64d failed=%I64d wins=%I64d losses=%I64d flat=%I64d",
                fromSideScope,
                fromConfirmationH1Count,
                fromHorizonH1Bars,
                fromRow.candidateEntryCount,
                fromRow.ineligibleEntryCount,
                fromRow.eligibleEntryCount,
                fromRow.eligibleOutcomeCount,
                fromRow.calculatedOutcomeCount,
                fromRow.failedOutcomeCount,
                fromRow.winningCount,
                fromRow.losingCount,
                fromRow.breakevenCount
            )
        );

        return false;
    }

    if (!findBaselineMedian(
            fromDatabaseHandle,
            fromRunId,
            fromRow,
            fromRow.medianNetProfitPips,
            fromLogger
        )) {
        return false;
    }

    return true;
}

/**
 * 36グループの基準成績を構築する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromRows 構築結果。
 * @param fromLogger ロガー。
 * @return 全グループを構築できた場合true。
 */
bool buildBaselineRows(
    const int fromDatabaseHandle,
    const long fromRunId,
    ZigZagElliotH1StudyBaselineRow &fromRows[],
    Logger &fromLogger
) {
    ArrayResize(fromRows, baselineExpectedRowCount);
    int rowIndex = 0;

    for (int i = 0; i < baselineConfirmationCount; i++) {
        int confirmationH1Count = getBaselineConfirmationH1Count(i);

        for (int j = 0; j < baselineHorizonCount; j++) {
            int horizonH1Bars = getBaselineHorizonH1Bars(j);

            for (int k = 0; k < baselineSideScopeCount; k++) {
                string sideScope = getBaselineSideScope(k);

                if (!aggregateBaselineRow(
                        fromDatabaseHandle,
                        fromRunId,
                        sideScope,
                        confirmationH1Count,
                        horizonH1Bars,
                        fromRows[rowIndex],
                        fromLogger
                    )) {
                    return false;
                }

                rowIndex++;
            }
        }
    }

    if (rowIndex == baselineExpectedRowCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Baseline row count mismatch. expected=%d actual=%d",
            baselineExpectedRowCount,
            rowIndex
        )
    );

    return false;
}

/**
 * DBファイル名から既定CSV名用の識別子を作る。
 *
 * @return ファイル名として使用可能な識別子。
 */
string getBaselineDatabaseToken() {
    string token = outcomeDatabaseFileName;
    StringReplace(token, "mstng-zigzag-elliot-h1-study-outcome-", "");
    StringReplace(token, ".sqlite", "");
    StringReplace(token, ".db", "");
    StringReplace(token, "\\", "-");
    StringReplace(token, "/", "-");
    StringReplace(token, ":", "-");
    StringReplace(token, "*", "-");
    StringReplace(token, "?", "-");
    StringReplace(token, "\"", "-");
    StringReplace(token, "<", "-");
    StringReplace(token, ">", "-");
    StringReplace(token, "|", "-");
    StringReplace(token, ".", "-");

    if (StringLen(token) > 80) {
        token = StringSubstr(token, 0, 80);
    }

    if (token == "") {
        token = "outcome";
    }

    return token;
}

/**
 * 実際のCSV出力ファイル名を取得する。
 *
 * @param fromRunId Outcome Run ID。
 * @return 入力値または自動生成名。
 */
string getBaselineOutputFileName(const long fromRunId) {
    if (outputCsvFileName != "") {
        return outputCsvFileName;
    }

    return StringFormat(
        "mstng-zigzag-elliot-h1-study-baseline-%s-run-%I64d.csv",
        getBaselineDatabaseToken(),
        fromRunId
    );
}

/**
 * CSVヘッダーを構築する。
 *
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setBaselineHeaderValues(
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, baselineCsvFieldCount);
    int index = 0;
    fromValues[index++] = "csv_schema_version";
    fromValues[index++] = "outcome_database_file_name";
    fromValues[index++] = "outcome_run_id";
    fromValues[index++] = "run_key";
    fromValues[index++] = "source_database_file_name";
    fromValues[index++] = "source_run_id";
    fromValues[index++] = "source_run_uid";
    fromValues[index++] = "study_from_jst_time";
    fromValues[index++] = "study_to_jst_time";
    fromValues[index++] = "signal_rule_version";
    fromValues[index++] = "entry_price_model";
    fromValues[index++] = "outcome_price_model";
    fromValues[index++] = "spread_model";
    fromValues[index++] = "evaluation_version";
    fromValues[index++] = "horizons_text";
    fromValues[index++] = "side_scope";
    fromValues[index++] = "confirmation_h1_count";
    fromValues[index++] = "horizon_h1_bars";
    fromValues[index++] = "candidate_entry_count";
    fromValues[index++] = "ineligible_entry_count";
    fromValues[index++] = "eligible_entry_count";
    fromValues[index++] = "eligible_outcome_count";
    fromValues[index++] = "calculated_outcome_count";
    fromValues[index++] = "failed_outcome_count";
    fromValues[index++] = "missing_outcome_count";
    fromValues[index++] = "future_h1_gap_count";
    fromValues[index++] = "other_failure_count";
    fromValues[index++] = "calculation_coverage_percent";
    fromValues[index++] = "data_gap_rate_percent";
    fromValues[index++] = "winning_count";
    fromValues[index++] = "losing_count";
    fromValues[index++] = "breakeven_count";
    fromValues[index++] = "win_rate_percent";
    fromValues[index++] = "is_statistics_available";
    fromValues[index++] = "net_profit_sum_pips";
    fromValues[index++] = "average_gross_profit_pips";
    fromValues[index++] = "average_net_profit_pips";
    fromValues[index++] = "median_net_profit_pips";
    fromValues[index++] = "winning_net_profit_sum_pips";
    fromValues[index++] = "losing_net_profit_abs_sum_pips";
    fromValues[index++] = "profit_factor";
    fromValues[index++] = "profit_factor_status";
    fromValues[index++] = "average_mfe_pips";
    fromValues[index++] = "average_mae_pips";
    fromValues[index++] = "average_gross_profit_atr";
    fromValues[index++] = "average_net_profit_atr";
    fromValues[index++] = "average_max_profit_h1_bars";
    fromValues[index++] = "average_entry_spread_pips";

    if (index == baselineCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV header field count mismatch. expected=%d actual=%d",
            baselineCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 利用可能なdouble値をCSV文字列へ変換する。
 *
 * @param fromValue 数値。
 * @param fromIsAvailable 利用可能な場合true。
 * @param fromDigits 小数桁数。
 * @return 利用不能時は空文字、それ以外は数値文字列。
 */
string formatBaselineOptionalDouble(
    const double fromValue,
    const bool fromIsAvailable,
    const int fromDigits
) {
    if (!fromIsAvailable) {
        return "";
    }

    return DoubleToString(fromValue, fromDigits);
}

/**
 * CSVデータ行を構築する。
 *
 * @param fromRunInfo Outcome Run情報。
 * @param fromRow 基準成績。
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setBaselineRowValues(
    ZigZagElliotH1StudyBaselineRunInfo &fromRunInfo,
    ZigZagElliotH1StudyBaselineRow &fromRow,
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, baselineCsvFieldCount);
    int index = 0;
    bool isRateAvailable = fromRow.eligibleEntryCount > 0;
    bool isProfitFactorAvailable =
        fromRow.profitFactorStatus == "AVAILABLE";
    fromValues[index++] = baselineCsvSchemaVersion;
    fromValues[index++] = outcomeDatabaseFileName;
    fromValues[index++] = StringFormat("%I64d", fromRunInfo.id);
    fromValues[index++] = fromRunInfo.runKey;
    fromValues[index++] = fromRunInfo.sourceDatabaseFileName;
    fromValues[index++] = StringFormat("%I64d", fromRunInfo.sourceRunId);
    fromValues[index++] = fromRunInfo.sourceRunUid;
    fromValues[index++] = TimeToString(
        fromRunInfo.studyFromJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = TimeToString(
        fromRunInfo.studyToJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = fromRunInfo.signalRuleVersion;
    fromValues[index++] = fromRunInfo.entryPriceModel;
    fromValues[index++] = fromRunInfo.outcomePriceModel;
    fromValues[index++] = fromRunInfo.spreadModel;
    fromValues[index++] = fromRunInfo.evaluationVersion;
    fromValues[index++] = fromRunInfo.horizonsText;
    fromValues[index++] = fromRow.sideScope;
    fromValues[index++] = IntegerToString(fromRow.confirmationH1Count);
    fromValues[index++] = IntegerToString(fromRow.horizonH1Bars);
    fromValues[index++] = StringFormat("%I64d", fromRow.candidateEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.ineligibleEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.eligibleEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.eligibleOutcomeCount);
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.calculatedOutcomeCount
    );
    fromValues[index++] = StringFormat("%I64d", fromRow.failedOutcomeCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.missingOutcomeCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.futureH1GapCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.otherFailureCount);
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.calculationCoveragePercent,
        isRateAvailable,
        6
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.dataGapRatePercent,
        isRateAvailable,
        6
    );
    fromValues[index++] = StringFormat("%I64d", fromRow.winningCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.losingCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.breakevenCount);
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.winRatePercent,
        fromRow.isStatisticsAvailable,
        6
    );
    fromValues[index++] = IntegerToString(
        (int)fromRow.isStatisticsAvailable
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.netProfitSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageGrossProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageNetProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.medianNetProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.winningNetProfitSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.losingNetProfitAbsSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.profitFactor,
        isProfitFactorAvailable,
        8
    );
    fromValues[index++] = fromRow.profitFactorStatus;
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageMfePips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageMaePips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageGrossProfitAtr,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageNetProfitAtr,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageMaxProfitH1Bars,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatBaselineOptionalDouble(
        fromRow.averageEntrySpreadPips,
        isRateAvailable,
        8
    );

    if (index == baselineCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV data field count mismatch. expected=%d actual=%d",
            baselineCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 基準成績をCSVへ上書き出力する。
 *
 * @param fromRunInfo Outcome Run情報。
 * @param fromRows 基準成績一覧。
 * @param fromLogger ロガー。
 * @return 全行を出力できた場合true。
 */
bool writeBaselineCsv(
    ZigZagElliotH1StudyBaselineRunInfo &fromRunInfo,
    ZigZagElliotH1StudyBaselineRow &fromRows[],
    Logger &fromLogger
) {
    string headerValues[];

    if (!setBaselineHeaderValues(headerValues, fromLogger)) {
        return false;
    }

    string fileName = getBaselineOutputFileName(fromRunInfo.id);
    CsvFileWriter fileWriter(
        fileName,
        outputUseCommonFolder,
        ",",
        false,
        true,
        "",
        CSV_FILE_WRITE_MODE_OVERWRITE
    );

    if (!fileWriter.writeHeader(headerValues, false)) {
        fileWriter.close();
        fromLogger.error(
            __FUNCTION__,
            "CSV header write failed. file=" + fileName
        );

        return false;
    }

    int rowCount = ArraySize(fromRows);

    for (int i = 0; i < rowCount; i++) {
        string rowValues[];

        if (!setBaselineRowValues(
                fromRunInfo,
                fromRows[i],
                rowValues,
                fromLogger
            ) || !fileWriter.writeRow(rowValues)) {
            fileWriter.close();
            fromLogger.error(
                __FUNCTION__,
                StringFormat("CSV row write failed. index=%d", i)
            );

            return false;
        }
    }

    fileWriter.close();

    return true;
}

/**
 * ALL行から研究対象Outcomeの総数を集計する。
 *
 * @param fromRows 基準成績一覧。
 * @param fromEligibleOutcomeCount 研究対象Outcome総数。
 * @param fromCalculatedOutcomeCount 計算成功Outcome総数。
 * @param fromFailedOutcomeCount 計算不能Outcome総数。
 */
void summarizeBaselineRows(
    ZigZagElliotH1StudyBaselineRow &fromRows[],
    long &fromEligibleOutcomeCount,
    long &fromCalculatedOutcomeCount,
    long &fromFailedOutcomeCount
) {
    fromEligibleOutcomeCount = 0;
    fromCalculatedOutcomeCount = 0;
    fromFailedOutcomeCount = 0;
    int rowCount = ArraySize(fromRows);

    for (int i = 0; i < rowCount; i++) {
        if (fromRows[i].sideScope != "ALL") {
            continue;
        }

        fromEligibleOutcomeCount += fromRows[i].eligibleOutcomeCount;
        fromCalculatedOutcomeCount += fromRows[i].calculatedOutcomeCount;
        fromFailedOutcomeCount += fromRows[i].failedOutcomeCount;
    }
}

/**
 * 1／2／3本確認×6／12／24／48H1×ALL／BUY／SELLを集計する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateBaselineInputs(logger)) {
        return;
    }

    SqliteDatabase outcomeDatabase(
        outcomeDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!outcomeDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Outcome DB could not be opened read-only.");

        return;
    }

    ZigZagElliotH1StudyBaselineRunInfo runInfo;

    if (!selectBaselineRun(
            outcomeDatabase.getHandle(),
            runInfo,
            logger
        ) || !validateBaselineRunData(
            outcomeDatabase.getHandle(),
            runInfo,
            logger
        )) {
        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Baseline aggregation started. outcomeRunId=%I64d sourceRunId=%I64d scopes=ALL,BUY,SELL confirmations=1,2,3 horizons=%s",
            runInfo.id,
            runInfo.sourceRunId,
            runInfo.horizonsText
        )
    );

    ZigZagElliotH1StudyBaselineRow rows[];

    if (!buildBaselineRows(
            outcomeDatabase.getHandle(),
            runInfo.id,
            rows,
            logger
        )) {
        logger.error(__FUNCTION__, "Baseline aggregation failed.");

        return;
    }

    if (!writeBaselineCsv(runInfo, rows, logger)) {
        logger.error(__FUNCTION__, "Baseline CSV export failed.");

        return;
    }

    long eligibleOutcomeCount = 0;
    long calculatedOutcomeCount = 0;
    long failedOutcomeCount = 0;
    summarizeBaselineRows(
        rows,
        eligibleOutcomeCount,
        calculatedOutcomeCount,
        failedOutcomeCount
    );
    logger.info(
        __FUNCTION__,
        StringFormat(
            "Baseline export finished. file=%s rows=%d eligibleEntries=%I64d eligibleOutcomes=%I64d calculated=%I64d failed=%I64d",
            getBaselineOutputFileName(runInfo.id),
            ArraySize(rows),
            runInfo.researchEligibleEntryCount,
            eligibleOutcomeCount,
            calculatedOutcomeCount,
            failedOutcomeCount
        )
    );
}
//+------------------------------------------------------------------+
