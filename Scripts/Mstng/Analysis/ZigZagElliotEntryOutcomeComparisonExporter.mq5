//+------------------------------------------------------------------+
//|       ZigZagElliotEntryOutcomeComparisonExporter.mq5             |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"
#property script_show_inputs

#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 比較対象Outcomeの仮想エントリー時刻モデル。
 */
enum ZigZagElliotEntryOutcomeComparisonTimingMode {
    /** H1始値専用モデル。 */
    ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_H1_OPEN_ONLY = 0,

    /** 判定後、最初のM1始値で仮想エントリーするモデル。 */
    ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_NEXT_M1_OPEN = 1
};

/** Outcome DBファイル名。 */
input string outcomeDatabaseFileName =
    "mstng-zigzag-elliot-entry-outcome.sqlite";

/** Outcome Runが参照したAlert DBファイル名。 */
input string sourceDatabaseFileName =
    "mstng-zigzag-elliot-alert.sqlite";

/** 比較対象のAlert Run ID。 */
input long sourceRunId = 0;

/** 比較対象Outcomeの仮想エントリー時刻モデル。 */
input ZigZagElliotEntryOutcomeComparisonTimingMode comparisonTimingMode =
    ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_NEXT_M1_OPEN;

/** DBをTerminal Common Filesから読み取る場合true。 */
input bool databaseUseCommonFolder = true;

/** 出力CSVファイル名。空の場合はRun IDから自動生成する。 */
input string outputCsvFileName = "";

/** CSVをTerminal Common Filesへ出力する場合true。 */
input bool outputUseCommonFolder = true;

/** 比較対象の価格モデル。 */
const string comparisonH1OpenPriceModel = "M1_BID_SPREAD_APPROX_V1";

/** 比較対象の評価ロジックバージョン。 */
const string comparisonH1OpenEvaluationVersion = "INITIAL_SL_HORIZON_V2";

/** 次M1始値モデルの価格評価モデル。 */
const string comparisonNextM1OpenPriceModel =
    "M1_NEXT_OPEN_BID_SPREAD_APPROX_V1";

/** 次M1始値モデルの評価ロジックバージョン。 */
const string comparisonNextM1OpenEvaluationVersion =
    "INITIAL_SL_NEXT_M1_OPEN_HORIZON_V1";

/** 比較CSVのスキーマバージョン。 */
const string comparisonCsvSchemaVersion =
    "ENTRY_OUTCOME_COMPARISON_V1";

/** 比較対象のH1本数。 */
const int comparisonHorizonCount = 4;

/** 比較CSVの列数。 */
const int comparisonCsvFieldCount = 60;

/**
 * 比較対象の価格評価モデルを取得する。
 *
 * @return DB検索およびCSVへ使用する価格評価モデル。
 */
string getComparisonPriceModel() {
    if (comparisonTimingMode
            == ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_H1_OPEN_ONLY) {
        return comparisonH1OpenPriceModel;
    }

    return comparisonNextM1OpenPriceModel;
}

/**
 * 比較対象の評価ロジックバージョンを取得する。
 *
 * @return DB検索およびCSVへ使用する評価ロジックバージョン。
 */
string getComparisonEvaluationVersion() {
    if (comparisonTimingMode
            == ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_H1_OPEN_ONLY) {
        return comparisonH1OpenEvaluationVersion;
    }

    return comparisonNextM1OpenEvaluationVersion;
}

/**
 * 比較対象エントリー時刻モデルの表示名を取得する。
 *
 * @return 設定中モデルの表示名。
 */
string getComparisonTimingModeText() {
    if (comparisonTimingMode
            == ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_H1_OPEN_ONLY) {
        return "H1_OPEN_ONLY";
    }

    return "NEXT_M1_OPEN";
}

/**
 * 比較対象Outcome Runの検証情報。
 */
struct OutcomeComparisonRunInfo {
    /** Outcome Run ID。 */
    long outcomeRunId;

    /** 参照元Alert Run UID。 */
    string sourceRunUid;

    /** 評価対象H1本数。 */
    int horizonH1Bars;

    /** Runが保持する評価対象総数。 */
    long totalCount;

    /** Runが保持する評価成功数。 */
    long successCount;

    /** Runが保持する評価失敗数。 */
    long failureCount;

    /** 実際に保存されているOutcome件数。 */
    long outcomeCount;

    /** 実際に計算済みのOutcome件数。 */
    long calculatedCount;

    /** RunとOutcomeの識別項目不一致件数。 */
    long metadataMismatchCount;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.outcomeRunId = 0;
        this.sourceRunUid = "";
        this.horizonH1Bars = 0;
        this.totalCount = 0;
        this.successCount = 0;
        this.failureCount = 0;
        this.outcomeCount = 0;
        this.calculatedCount = 0;
        this.metadataMismatchCount = 0;
    }
};

/**
 * Outcome DBから読み取る正規化済み比較元行。
 */
struct OutcomeComparisonSourceRow {
    /** Outcome Run ID。 */
    long outcomeRunId;

    /** 参照元Alert ID。 */
    long sourceAlertId;

    /** 参照元Alert Run ID。 */
    long sourceRunId;

    /** 市場シグナル比較キー。 */
    string marketSignalKey;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 対象シンボル。 */
    string symbolName;

    /** BUYまたはSELL。 */
    string side;

    /** シグナルが属するH1バー開始時刻。 */
    datetime currentBarTime;

    /** 仮想エントリー時刻。 */
    datetime entryTime;

    /** 仮想エントリー価格。 */
    double entryPrice;

    /** Alert保存時点のスプレッド。 */
    double spreadPips;

    /** 初期ストップロス価格。 */
    double stopLoss;

    /** Alert DBに保存されたリスク。 */
    double sourceRiskPips;

    /** 後処理で再計算したリスク。 */
    double calculatedRiskPips;

    /** Outcome Run側の評価対象H1本数。 */
    int runHorizonH1Bars;

    /** Outcome側の評価対象H1本数。 */
    int outcomeHorizonH1Bars;

    /** 結果指標を計算できた場合1。 */
    int isCalculated;

    /** 最大有利変動幅のR換算。 */
    double mfeR;

    /** 最大不利変動幅のR換算。 */
    double maeR;

    /** 仮想決済損益のR換算。 */
    double profitR;

    /** 仮想決済理由。 */
    string exitReason;

    /** 保有したH1本数。 */
    int barsHeldH1;

    /** 計算結果または計算不能理由を表す状態。 */
    string dataStatus;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.outcomeRunId = 0;
        this.sourceAlertId = 0;
        this.sourceRunId = 0;
        this.marketSignalKey = "";
        this.sourceServer = "";
        this.symbolName = "";
        this.side = "";
        this.currentBarTime = 0;
        this.entryTime = 0;
        this.entryPrice = 0.0;
        this.spreadPips = 0.0;
        this.stopLoss = 0.0;
        this.sourceRiskPips = 0.0;
        this.calculatedRiskPips = 0.0;
        this.runHorizonH1Bars = 0;
        this.outcomeHorizonH1Bars = 0;
        this.isCalculated = 0;
        this.mfeR = 0.0;
        this.maeR = 0.0;
        this.profitR = 0.0;
        this.exitReason = "";
        this.barsHeldH1 = 0;
        this.dataStatus = "";
    }
};

/**
 * 1期限分の比較結果。
 */
struct OutcomeComparisonHorizonSlot {
    /** 同じ期限で取得したレコード数。 */
    int recordCount;

    /** Outcome Run ID。 */
    long outcomeRunId;

    /** 結果指標を計算できた場合1。 */
    int isCalculated;

    /** 仮想決済損益のR換算。 */
    double profitR;

    /** 最大有利変動幅のR換算。 */
    double mfeR;

    /** 最大不利変動幅のR換算。 */
    double maeR;

    /** 保有したH1本数。 */
    int barsHeldH1;

    /** 仮想決済理由。 */
    string exitReason;

    /** 計算結果または計算不能理由を表す状態。 */
    string dataStatus;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.recordCount = 0;
        this.outcomeRunId = 0;
        this.isCalculated = 0;
        this.profitR = 0.0;
        this.mfeR = 0.0;
        this.maeR = 0.0;
        this.barsHeldH1 = 0;
        this.exitReason = "";
        this.dataStatus = "";
    }
};

/**
 * marketSignalKey単位の6・12・24・48 H1比較結果。
 */
struct OutcomeComparisonRow {
    /** 共通項目を設定済みの場合true。 */
    bool hasCommonValues;

    /** 期限間で共通項目が一致する場合true。 */
    bool isCommonConsistent;

    /** 参照元Alert ID。 */
    long sourceAlertId;

    /** 参照元Alert Run ID。 */
    long sourceRunId;

    /** 市場シグナル比較キー。 */
    string marketSignalKey;

    /** 同じ市場シグナル比較キーを持つAlert件数。 */
    int marketSignalKeyAlertCount;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 対象シンボル。 */
    string symbolName;

    /** BUYまたはSELL。 */
    string side;

    /** シグナルが属するH1バー開始時刻。 */
    datetime currentBarTime;

    /** 仮想エントリー時刻。 */
    datetime entryTime;

    /** 仮想エントリー価格。 */
    double entryPrice;

    /** Alert保存時点のスプレッド。 */
    double spreadPips;

    /** 初期ストップロス価格。 */
    double stopLoss;

    /** Alert DBに保存されたリスク。 */
    double sourceRiskPips;

    /** 後処理で再計算したリスク。 */
    double calculatedRiskPips;

    /** 6 H1結果。 */
    OutcomeComparisonHorizonSlot horizon6;

    /** 12 H1結果。 */
    OutcomeComparisonHorizonSlot horizon12;

    /** 24 H1結果。 */
    OutcomeComparisonHorizonSlot horizon24;

    /** 48 H1結果。 */
    OutcomeComparisonHorizonSlot horizon48;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.hasCommonValues = false;
        this.isCommonConsistent = true;
        this.sourceAlertId = 0;
        this.sourceRunId = 0;
        this.marketSignalKey = "";
        this.marketSignalKeyAlertCount = 0;
        this.sourceServer = "";
        this.symbolName = "";
        this.side = "";
        this.currentBarTime = 0;
        this.entryTime = 0;
        this.entryPrice = 0.0;
        this.spreadPips = 0.0;
        this.stopLoss = 0.0;
        this.sourceRiskPips = 0.0;
        this.calculatedRiskPips = 0.0;
        this.horizon6.reset();
        this.horizon12.reset();
        this.horizon24.reset();
        this.horizon48.reset();
    }
};

/**
 * CSV出力結果の集計。
 */
struct OutcomeComparisonExportSummary {
    /** 出力行数。 */
    int totalCount;

    /** 正常比較行数。 */
    int okCount;

    /** 期限欠損を持つ行数。 */
    int missingCount;

    /** 期限重複または比較キー重複を持つ行数。 */
    int duplicateCount;

    /** 未計算期限を持つ行数。 */
    int uncalculatedCount;

    /** 共通項目不一致を持つ行数。 */
    int inconsistentCount;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.totalCount = 0;
        this.okCount = 0;
        this.missingCount = 0;
        this.duplicateCount = 0;
        this.uncalculatedCount = 0;
        this.inconsistentCount = 0;
    }
};

/**
 * 比較対象のH1本数を配列位置から取得する。
 *
 * @param fromIndex 配列位置。
 * @return 対応するH1本数。範囲外の場合0。
 */
int getComparisonHorizon(const int fromIndex) {
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
 * H1本数に対応する配列位置を取得する。
 *
 * @param fromHorizonH1Bars H1本数。
 * @return 対応する配列位置。対象外の場合-1。
 */
int getComparisonHorizonIndex(const int fromHorizonH1Bars) {
    for (int i = 0; i < comparisonHorizonCount; i++) {
        if (getComparisonHorizon(i) == fromHorizonH1Bars) {
            return i;
        }
    }

    return -1;
}

/**
 * Alert DBファイル名を既定CSV名へ使用可能な文字列にする。
 *
 * @return パス区切り文字などを除去した識別文字列。
 */
string getComparisonSourceDatabaseToken() {
    string token = sourceDatabaseFileName;
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
        token = "source";
    }

    return token;
}

/**
 * Run IDとAlert DB名から既定CSVファイル名を作成する。
 *
 * @return 既定CSVファイル名。
 */
string getDefaultComparisonOutputFileName() {
    return StringFormat(
        "mstng-zigzag-elliot-entry-outcome-comparison-%s-%s-run-%I64d.csv",
        getComparisonSourceDatabaseToken(),
        getComparisonTimingModeText(),
        sourceRunId
    );
}

/**
 * 出力ファイル名がCSV拡張子を持つか判定する。
 *
 * @param fromFileName 出力ファイル名。
 * @return 末尾が.csvの場合true。
 */
bool isComparisonCsvFileName(const string fromFileName) {
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
 * Script入力が実行可能な範囲か確認する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateComparisonInputs(Logger &fromLogger) {
    if (comparisonTimingMode
            != ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_H1_OPEN_ONLY
            && comparisonTimingMode
                != ZIGZAG_ELLIOT_ENTRY_OUTCOME_COMPARISON_NEXT_M1_OPEN) {
        fromLogger.error(__FUNCTION__, "comparisonTimingMode is invalid.");

        return false;
    }

    if (outcomeDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "outcomeDatabaseFileName is empty.");

        return false;
    }

    if (sourceDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "sourceDatabaseFileName is empty.");

        return false;
    }

    if (sourceRunId <= 0) {
        fromLogger.error(__FUNCTION__, "sourceRunId must be positive.");

        return false;
    }

    string resolvedOutputFileName = outputCsvFileName;

    if (resolvedOutputFileName == "") {
        resolvedOutputFileName = getDefaultComparisonOutputFileName();
    }

    if (!isComparisonCsvFileName(resolvedOutputFileName)) {
        fromLogger.error(
            __FUNCTION__,
            "outputCsvFileName must have a .csv extension."
        );

        return false;
    }

    if (StringCompare(
            resolvedOutputFileName,
            outcomeDatabaseFileName,
            false
        ) == 0 && outputUseCommonFolder == databaseUseCommonFolder) {
        fromLogger.error(
            __FUNCTION__,
            "Outcome DB and output CSV must be different files."
        );

        return false;
    }

    if (StringCompare(
            resolvedOutputFileName,
            sourceDatabaseFileName,
            false
        ) == 0 && outputUseCommonFolder == databaseUseCommonFolder) {
        fromLogger.error(
            __FUNCTION__,
            "Alert DB and output CSV must be different files."
        );

        return false;
    }

    return true;
}

/**
 * Outcome検索の共通条件をSQL要求へ設定する。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromLogger ロガー。
 * @param fromMethodName 呼び出し元メソッド名。
 * @return 全パラメーターを設定できた場合true。
 */
bool bindComparisonQueryInputs(
    const int fromRequestHandle,
    Logger &fromLogger,
    const string fromMethodName
) {
    ResetLastError();
    bool isBound = DatabaseBind(
        fromRequestHandle,
        0,
        sourceDatabaseFileName
    );

    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 1, sourceRunId);
    }

    if (isBound) {
        isBound = DatabaseBind(
            fromRequestHandle,
            2,
            getComparisonPriceModel()
        );
    }

    if (isBound) {
        isBound = DatabaseBind(
            fromRequestHandle,
            3,
            getComparisonEvaluationVersion()
        );
    }

    if (isBound) {
        return true;
    }

    int errorCode = GetLastError();
    DatabaseFinalize(fromRequestHandle);
    fromLogger.error(
        fromMethodName,
        StringFormat("DatabaseBind failed. error=%d", errorCode)
    );

    return false;
}

/**
 * 完了済みの比較対象Outcome Runを取得する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfos 取得結果。
 * @param fromLogger ロガー。
 * @return 検索処理に成功した場合true。
 */
bool findComparisonRuns(
    const int fromDatabaseHandle,
    OutcomeComparisonRunInfo &fromRunInfos[],
    Logger &fromLogger
) {
    ArrayResize(fromRunInfos, 0);
    string sql = "SELECT runs.id, runs.source_run_uid,";
    sql += " runs.horizon_h1_bars, runs.total_count,";
    sql += " runs.success_count, runs.failure_count,";
    sql += " COUNT(outcomes.id),";
    sql += " COALESCE(SUM(outcomes.is_calculated), 0),";
    sql += " COALESCE(SUM(CASE WHEN outcomes.id IS NOT NULL AND (";
    sql += "outcomes.source_run_id <> runs.source_run_id OR ";
    sql += "outcomes.horizon_h1_bars <> runs.horizon_h1_bars OR ";
    sql += "outcomes.price_model <> runs.price_model OR ";
    sql += "outcomes.evaluation_version <> runs.evaluation_version";
    sql += ") THEN 1 ELSE 0 END), 0) ";
    sql += "FROM zigzag_elliot_entry_outcome_runs AS runs ";
    sql += "LEFT JOIN zigzag_elliot_entry_outcomes AS outcomes ";
    sql += "ON outcomes.outcome_run_id = runs.id ";
    sql += "WHERE runs.source_database_file_name = ?1 ";
    sql += "AND runs.source_run_id = ?2 ";
    sql += "AND runs.price_model = ?3 ";
    sql += "AND runs.evaluation_version = ?4 ";
    sql += "AND runs.status = 'COMPLETED' ";
    sql += "AND runs.horizon_h1_bars IN (6, 12, 24, 48) ";
    sql += "GROUP BY runs.id, runs.source_run_uid,";
    sql += " runs.horizon_h1_bars, runs.total_count,";
    sql += " runs.success_count, runs.failure_count ";
    sql += "ORDER BY runs.horizon_h1_bars ASC, runs.id ASC";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindComparisonQueryInputs(
            requestHandle,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    while (true) {
        OutcomeComparisonRunInfo runInfo;
        runInfo.reset();
        ResetLastError();
        bool isRead = DatabaseReadBind(requestHandle, runInfo);
        int errorCode = GetLastError();

        if (!isRead) {
            DatabaseFinalize(requestHandle);

            if (errorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            ArrayResize(fromRunInfos, 0);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseReadBind failed. error=%d",
                    errorCode
                )
            );

            return false;
        }

        int runIndex = ArraySize(fromRunInfos);

        if (ArrayResize(
                fromRunInfos,
                runIndex + 1,
                comparisonHorizonCount
            ) != runIndex + 1) {
            DatabaseFinalize(requestHandle);
            ArrayResize(fromRunInfos, 0);
            fromLogger.error(__FUNCTION__, "ArrayResize failed.");

            return false;
        }

        fromRunInfos[runIndex] = runInfo;
    }
}

/**
 * 比較対象Runの一意性とメタデータを検証する。
 *
 * @param fromRunInfos 比較対象Run一覧。
 * @param fromSourceRunUid 共通のAlert Run UID格納先。
 * @param fromLogger ロガー。
 * @return 4期限を安全に比較できる場合true。
 */
bool validateComparisonRuns(
    OutcomeComparisonRunInfo &fromRunInfos[],
    string &fromSourceRunUid,
    Logger &fromLogger
) {
    fromSourceRunUid = "";
    int horizonCounts[];
    ArrayResize(horizonCounts, comparisonHorizonCount);
    ArrayInitialize(horizonCounts, 0);
    int runCount = ArraySize(fromRunInfos);
    bool isValid = true;

    for (int i = 0; i < runCount; i++) {
        int horizonIndex = getComparisonHorizonIndex(
            fromRunInfos[i].horizonH1Bars
        );

        if (horizonIndex < 0) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Unexpected horizon. outcomeRunId=%I64d horizonH1=%d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].horizonH1Bars
                )
            );
            isValid = false;
            continue;
        }

        horizonCounts[horizonIndex]++;

        if (fromRunInfos[i].sourceRunUid == "") {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "sourceRunUid is empty. outcomeRunId=%I64d",
                    fromRunInfos[i].outcomeRunId
                )
            );
            isValid = false;
        } else if (fromSourceRunUid == "") {
            fromSourceRunUid = fromRunInfos[i].sourceRunUid;
        } else if (fromSourceRunUid != fromRunInfos[i].sourceRunUid) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Source Run UID mismatch. outcomeRunId=%I64d expected=%s actual=%s",
                    fromRunInfos[i].outcomeRunId,
                    fromSourceRunUid,
                    fromRunInfos[i].sourceRunUid
                )
            );
            isValid = false;
        }

        if (fromRunInfos[i].totalCount <= 0
                || fromRunInfos[i].successCount < 0
                || fromRunInfos[i].failureCount < 0
                || fromRunInfos[i].successCount
                    + fromRunInfos[i].failureCount
                    != fromRunInfos[i].totalCount) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Outcome Run counts are invalid. outcomeRunId=%I64d total=%I64d success=%I64d failure=%I64d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].totalCount,
                    fromRunInfos[i].successCount,
                    fromRunInfos[i].failureCount
                )
            );
            isValid = false;
        }

        if (fromRunInfos[i].metadataMismatchCount > 0) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Outcome metadata mismatch. outcomeRunId=%I64d count=%I64d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].metadataMismatchCount
                )
            );
            isValid = false;
        }

        if (fromRunInfos[i].outcomeCount
                != fromRunInfos[i].totalCount) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Outcome count mismatch. outcomeRunId=%I64d expected=%I64d actual=%I64d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].totalCount,
                    fromRunInfos[i].outcomeCount
                )
            );
            isValid = false;
        }

        if (fromRunInfos[i].calculatedCount
                != fromRunInfos[i].successCount) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Calculated count mismatch. outcomeRunId=%I64d expected=%I64d actual=%I64d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].successCount,
                    fromRunInfos[i].calculatedCount
                )
            );
            isValid = false;
        }

        if (fromRunInfos[i].failureCount > 0) {
            fromLogger.warn(
                __FUNCTION__,
                StringFormat(
                    "Outcome Run contains uncalculated rows. outcomeRunId=%I64d failure=%I64d",
                    fromRunInfos[i].outcomeRunId,
                    fromRunInfos[i].failureCount
                )
            );
        }
    }

    for (int i = 0; i < comparisonHorizonCount; i++) {
        if (horizonCounts[i] == 1) {
            continue;
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Completed Outcome Run count must be one. horizonH1=%d count=%d",
                getComparisonHorizon(i),
                horizonCounts[i]
            )
        );
        isValid = false;
    }

    return isValid;
}

/**
 * 指定H1本数のOutcome Run IDを取得する。
 *
 * @param fromRunInfos 比較対象Run一覧。
 * @param fromHorizonH1Bars H1本数。
 * @return 対応するOutcome Run ID。存在しない場合0。
 */
long getComparisonOutcomeRunId(
    OutcomeComparisonRunInfo &fromRunInfos[],
    const int fromHorizonH1Bars
) {
    int runCount = ArraySize(fromRunInfos);

    for (int i = 0; i < runCount; i++) {
        if (fromRunInfos[i].horizonH1Bars == fromHorizonH1Bars) {
            return fromRunInfos[i].outcomeRunId;
        }
    }

    return 0;
}

/**
 * 選択した4つのOutcome Runから比較元行を取得する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfos 比較対象Run一覧。
 * @param fromRows 取得結果。
 * @param fromLogger ロガー。
 * @return 検索処理に成功した場合true。
 */
bool findComparisonSourceRows(
    const int fromDatabaseHandle,
    OutcomeComparisonRunInfo &fromRunInfos[],
    OutcomeComparisonSourceRow &fromRows[],
    Logger &fromLogger
) {
    ArrayResize(fromRows, 0);
    string sql = "SELECT outcomes.outcome_run_id,";
    sql += " outcomes.source_alert_id, outcomes.source_run_id,";
    sql += " outcomes.market_signal_key, outcomes.source_server,";
    sql += " outcomes.symbol_name, outcomes.side,";
    sql += " outcomes.current_bar_time, outcomes.entry_time,";
    sql += " outcomes.entry_price, outcomes.spread_pips,";
    sql += " outcomes.stop_loss, outcomes.source_risk_pips,";
    sql += " outcomes.calculated_risk_pips,";
    sql += " runs.horizon_h1_bars, outcomes.horizon_h1_bars,";
    sql += " outcomes.is_calculated,";
    sql += " COALESCE(outcomes.mfe_r, 0.0),";
    sql += " COALESCE(outcomes.mae_r, 0.0),";
    sql += " COALESCE(outcomes.profit_r, 0.0),";
    sql += " outcomes.exit_reason,";
    sql += " COALESCE(outcomes.bars_held_h1, 0),";
    sql += " outcomes.data_status ";
    sql += "FROM zigzag_elliot_entry_outcomes AS outcomes ";
    sql += "INNER JOIN zigzag_elliot_entry_outcome_runs AS runs ";
    sql += "ON runs.id = outcomes.outcome_run_id ";
    sql += "WHERE outcomes.outcome_run_id IN (?1, ?2, ?3, ?4) ";
    sql += "ORDER BY outcomes.market_signal_key ASC,";
    sql += " outcomes.source_alert_id ASC,";
    sql += " runs.horizon_h1_bars ASC, outcomes.id ASC";

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
    bool isBound = true;

    for (int i = 0; i < comparisonHorizonCount; i++) {
        long outcomeRunId = getComparisonOutcomeRunId(
            fromRunInfos,
            getComparisonHorizon(i)
        );

        if (outcomeRunId <= 0
                || !DatabaseBind(requestHandle, i, outcomeRunId)) {
            isBound = false;
            break;
        }
    }

    if (!isBound) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", errorCode)
        );

        return false;
    }

    while (true) {
        OutcomeComparisonSourceRow sourceRow;
        sourceRow.reset();
        ResetLastError();
        bool isRead = DatabaseReadBind(requestHandle, sourceRow);
        int errorCode = GetLastError();

        if (!isRead) {
            DatabaseFinalize(requestHandle);

            if (errorCode == ERR_DATABASE_NO_MORE_DATA) {
                return true;
            }

            ArrayResize(fromRows, 0);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseReadBind failed. error=%d",
                    errorCode
                )
            );

            return false;
        }

        if (sourceRow.outcomeRunId <= 0
                || sourceRow.sourceAlertId <= 0
                || sourceRow.sourceRunId != sourceRunId
                || sourceRow.marketSignalKey == ""
                || sourceRow.sourceServer == ""
                || sourceRow.symbolName == ""
                || (sourceRow.side != "BUY" && sourceRow.side != "SELL")
                || sourceRow.currentBarTime <= 0
                || sourceRow.entryTime <= 0
                || sourceRow.entryPrice <= 0.0
                || sourceRow.stopLoss <= 0.0
                || sourceRow.sourceRiskPips <= 0.0
                || sourceRow.calculatedRiskPips < 0.0
                || (sourceRow.isCalculated == 1
                    && sourceRow.calculatedRiskPips <= 0.0)
                || sourceRow.runHorizonH1Bars
                    != sourceRow.outcomeHorizonH1Bars
                || getComparisonHorizonIndex(
                    sourceRow.runHorizonH1Bars
                ) < 0
                || (sourceRow.isCalculated != 0
                    && sourceRow.isCalculated != 1)) {
            DatabaseFinalize(requestHandle);
            ArrayResize(fromRows, 0);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Outcome row is invalid. outcomeRunId=%I64d alertId=%I64d horizonH1=%d",
                    sourceRow.outcomeRunId,
                    sourceRow.sourceAlertId,
                    sourceRow.runHorizonH1Bars
                )
            );

            return false;
        }

        int rowIndex = ArraySize(fromRows);

        if (ArrayResize(fromRows, rowIndex + 1, 256) != rowIndex + 1) {
            DatabaseFinalize(requestHandle);
            ArrayResize(fromRows, 0);
            fromLogger.error(__FUNCTION__, "ArrayResize failed.");

            return false;
        }

        fromRows[rowIndex] = sourceRow;
    }
}

/**
 * 比較用double値が同一とみなせるか判定する。
 *
 * @param fromLeft 左辺。
 * @param fromRight 右辺。
 * @return 許容差以内の場合true。
 */
bool isComparisonDoubleEqual(
    const double fromLeft,
    const double fromRight
) {
    return MathAbs(fromLeft - fromRight) <= 0.0000000001;
}

/**
 * 比較行へ初回の共通項目を設定する。
 *
 * @param fromComparison 設定先。
 * @param fromSourceRow 比較元行。
 */
void setComparisonCommonValues(
    OutcomeComparisonRow &fromComparison,
    OutcomeComparisonSourceRow &fromSourceRow
) {
    fromComparison.hasCommonValues = true;
    fromComparison.sourceAlertId = fromSourceRow.sourceAlertId;
    fromComparison.sourceRunId = fromSourceRow.sourceRunId;
    fromComparison.marketSignalKey = fromSourceRow.marketSignalKey;
    fromComparison.sourceServer = fromSourceRow.sourceServer;
    fromComparison.symbolName = fromSourceRow.symbolName;
    fromComparison.side = fromSourceRow.side;
    fromComparison.currentBarTime = fromSourceRow.currentBarTime;
    fromComparison.entryTime = fromSourceRow.entryTime;
    fromComparison.entryPrice = fromSourceRow.entryPrice;
    fromComparison.spreadPips = fromSourceRow.spreadPips;
    fromComparison.stopLoss = fromSourceRow.stopLoss;
    fromComparison.sourceRiskPips = fromSourceRow.sourceRiskPips;
    fromComparison.calculatedRiskPips =
        fromSourceRow.calculatedRiskPips;
}

/**
 * 比較行と追加行の共通項目が一致するか判定する。
 *
 * @param fromComparison 比較済み行。
 * @param fromSourceRow 追加する比較元行。
 * @return 全共通項目が一致する場合true。
 */
bool isComparisonCommonMatch(
    OutcomeComparisonRow &fromComparison,
    OutcomeComparisonSourceRow &fromSourceRow
) {
    return fromComparison.sourceAlertId == fromSourceRow.sourceAlertId
        && fromComparison.sourceRunId == fromSourceRow.sourceRunId
        && fromComparison.marketSignalKey == fromSourceRow.marketSignalKey
        && fromComparison.sourceServer == fromSourceRow.sourceServer
        && fromComparison.symbolName == fromSourceRow.symbolName
        && fromComparison.side == fromSourceRow.side
        && fromComparison.currentBarTime == fromSourceRow.currentBarTime
        && fromComparison.entryTime == fromSourceRow.entryTime
        && isComparisonDoubleEqual(
            fromComparison.entryPrice,
            fromSourceRow.entryPrice
        )
        && isComparisonDoubleEqual(
            fromComparison.spreadPips,
            fromSourceRow.spreadPips
        )
        && isComparisonDoubleEqual(
            fromComparison.stopLoss,
            fromSourceRow.stopLoss
        )
        && isComparisonDoubleEqual(
            fromComparison.sourceRiskPips,
            fromSourceRow.sourceRiskPips
        )
        && isComparisonDoubleEqual(
            fromComparison.calculatedRiskPips,
            fromSourceRow.calculatedRiskPips
        );
}

/**
 * 期限別スロットへ比較元行を追加する。
 *
 * 2件目以降は件数だけを増やし、最初の値を上書きしない。
 *
 * @param fromSlot 設定先スロット。
 * @param fromSourceRow 比較元行。
 */
void addComparisonHorizonSlot(
    OutcomeComparisonHorizonSlot &fromSlot,
    OutcomeComparisonSourceRow &fromSourceRow
) {
    fromSlot.recordCount++;

    if (fromSlot.recordCount != 1) {
        return;
    }

    fromSlot.outcomeRunId = fromSourceRow.outcomeRunId;
    fromSlot.isCalculated = fromSourceRow.isCalculated;
    fromSlot.profitR = fromSourceRow.profitR;
    fromSlot.mfeR = fromSourceRow.mfeR;
    fromSlot.maeR = fromSourceRow.maeR;
    fromSlot.barsHeldH1 = fromSourceRow.barsHeldH1;
    fromSlot.exitReason = fromSourceRow.exitReason;
    fromSlot.dataStatus = fromSourceRow.dataStatus;
}

/**
 * 比較行へ正規化済みOutcome 1件を追加する。
 *
 * @param fromComparison 設定先。
 * @param fromSourceRow 比較元行。
 * @param fromLogger ロガー。
 * @return 対象H1本数を追加できた場合true。
 */
bool addComparisonSourceRow(
    OutcomeComparisonRow &fromComparison,
    OutcomeComparisonSourceRow &fromSourceRow,
    Logger &fromLogger
) {
    if (!fromComparison.hasCommonValues) {
        setComparisonCommonValues(fromComparison, fromSourceRow);
    } else if (!isComparisonCommonMatch(
            fromComparison,
            fromSourceRow
        )) {
        fromComparison.isCommonConsistent = false;
    }

    if (fromSourceRow.runHorizonH1Bars == 6) {
        addComparisonHorizonSlot(
            fromComparison.horizon6,
            fromSourceRow
        );

        return true;
    }

    if (fromSourceRow.runHorizonH1Bars == 12) {
        addComparisonHorizonSlot(
            fromComparison.horizon12,
            fromSourceRow
        );

        return true;
    }

    if (fromSourceRow.runHorizonH1Bars == 24) {
        addComparisonHorizonSlot(
            fromComparison.horizon24,
            fromSourceRow
        );

        return true;
    }

    if (fromSourceRow.runHorizonH1Bars == 48) {
        addComparisonHorizonSlot(
            fromComparison.horizon48,
            fromSourceRow
        );

        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Unexpected horizon. marketSignalKey=%s horizonH1=%d",
            fromSourceRow.marketSignalKey,
            fromSourceRow.runHorizonH1Bars
        )
    );

    return false;
}

/**
 * 正規化済みOutcomeをmarketSignalKey・sourceAlertId単位へ集約する。
 *
 * 正常データではmarketSignalKeyとsourceAlertIdは1対1になる。同じ
 * marketSignalKeyを複数Alertが持つ場合は行を混在させず、各行の
 * marketSignalKeyAlertCountを2以上にして明示する。
 *
 * @param fromSourceRows 比較元行一覧。marketSignalKey順。
 * @param fromComparisons 集約結果。
 * @param fromLogger ロガー。
 * @return 集約に成功した場合true。
 */
bool buildOutcomeComparisons(
    OutcomeComparisonSourceRow &fromSourceRows[],
    OutcomeComparisonRow &fromComparisons[],
    Logger &fromLogger
) {
    ArrayResize(fromComparisons, 0);
    int sourceRowCount = ArraySize(fromSourceRows);
    int comparisonIndex = -1;
    string previousMarketSignalKey = "";
    long previousSourceAlertId = 0;

    for (int i = 0; i < sourceRowCount; i++) {
        if (comparisonIndex < 0
                || previousMarketSignalKey
                    != fromSourceRows[i].marketSignalKey
                || previousSourceAlertId
                    != fromSourceRows[i].sourceAlertId) {
            comparisonIndex = ArraySize(fromComparisons);

            if (ArrayResize(
                    fromComparisons,
                    comparisonIndex + 1,
                    256
                ) != comparisonIndex + 1) {
                ArrayResize(fromComparisons, 0);
                fromLogger.error(__FUNCTION__, "ArrayResize failed.");

                return false;
            }

            fromComparisons[comparisonIndex].reset();
            previousMarketSignalKey = fromSourceRows[i].marketSignalKey;
            previousSourceAlertId = fromSourceRows[i].sourceAlertId;
        }

        if (!addComparisonSourceRow(
                fromComparisons[comparisonIndex],
                fromSourceRows[i],
                fromLogger
            )) {
            ArrayResize(fromComparisons, 0);

            return false;
        }
    }

    int comparisonCount = ArraySize(fromComparisons);
    int groupStartIndex = 0;

    while (groupStartIndex < comparisonCount) {
        int groupEndIndex = groupStartIndex + 1;

        while (groupEndIndex < comparisonCount
                && fromComparisons[groupEndIndex].marketSignalKey
                    == fromComparisons[groupStartIndex].marketSignalKey) {
            groupEndIndex++;
        }

        int marketSignalKeyAlertCount =
            groupEndIndex - groupStartIndex;

        for (int i = groupStartIndex; i < groupEndIndex; i++) {
            fromComparisons[i].marketSignalKeyAlertCount =
                marketSignalKeyAlertCount;
        }

        groupStartIndex = groupEndIndex;
    }

    return true;
}

/**
 * 一覧文字列へH1本数を追加する。
 *
 * @param fromList 追加先。
 * @param fromHorizonH1Bars H1本数。
 */
void appendComparisonHorizon(
    string &fromList,
    const int fromHorizonH1Bars
) {
    if (fromList != "") {
        fromList = fromList + "|";
    }

    fromList = fromList + IntegerToString(fromHorizonH1Bars);
}

/**
 * 期限スロットから欠損、重複および未計算一覧を更新する。
 *
 * @param fromSlot 判定対象スロット。
 * @param fromHorizonH1Bars H1本数。
 * @param fromMissingHorizonList 欠損一覧。
 * @param fromDuplicateHorizonList 重複一覧。
 * @param fromUncalculatedHorizonList 未計算一覧。
 */
void appendComparisonSlotIssues(
    OutcomeComparisonHorizonSlot &fromSlot,
    const int fromHorizonH1Bars,
    string &fromMissingHorizonList,
    string &fromDuplicateHorizonList,
    string &fromUncalculatedHorizonList
) {
    if (fromSlot.recordCount <= 0) {
        appendComparisonHorizon(
            fromMissingHorizonList,
            fromHorizonH1Bars
        );

        return;
    }

    if (fromSlot.recordCount > 1) {
        appendComparisonHorizon(
            fromDuplicateHorizonList,
            fromHorizonH1Bars
        );

        return;
    }

    if (fromSlot.isCalculated != 1) {
        appendComparisonHorizon(
            fromUncalculatedHorizonList,
            fromHorizonH1Bars
        );
    }
}

/**
 * 比較行の異常一覧を作成する。
 *
 * @param fromComparison 比較行。
 * @param fromMissingHorizonList 欠損一覧。
 * @param fromDuplicateHorizonList 重複一覧。
 * @param fromUncalculatedHorizonList 未計算一覧。
 * @return 比較状態。
 */
string buildComparisonStatus(
    OutcomeComparisonRow &fromComparison,
    string &fromMissingHorizonList,
    string &fromDuplicateHorizonList,
    string &fromUncalculatedHorizonList
) {
    fromMissingHorizonList = "";
    fromDuplicateHorizonList = "";
    fromUncalculatedHorizonList = "";
    appendComparisonSlotIssues(
        fromComparison.horizon6,
        6,
        fromMissingHorizonList,
        fromDuplicateHorizonList,
        fromUncalculatedHorizonList
    );
    appendComparisonSlotIssues(
        fromComparison.horizon12,
        12,
        fromMissingHorizonList,
        fromDuplicateHorizonList,
        fromUncalculatedHorizonList
    );
    appendComparisonSlotIssues(
        fromComparison.horizon24,
        24,
        fromMissingHorizonList,
        fromDuplicateHorizonList,
        fromUncalculatedHorizonList
    );
    appendComparisonSlotIssues(
        fromComparison.horizon48,
        48,
        fromMissingHorizonList,
        fromDuplicateHorizonList,
        fromUncalculatedHorizonList
    );
    string status = "";

    if (fromComparison.marketSignalKeyAlertCount != 1) {
        status = "DUPLICATE_MARKET_SIGNAL_KEY";
    }

    if (fromMissingHorizonList != "") {
        if (status != "") {
            status = status + "|";
        }

        status = status + "MISSING_HORIZON";
    }

    if (fromDuplicateHorizonList != "") {
        if (status != "") {
            status = status + "|";
        }

        status = status + "DUPLICATE_HORIZON";
    }

    if (fromUncalculatedHorizonList != "") {
        if (status != "") {
            status = status + "|";
        }

        status = status + "UNCALCULATED";
    }

    if (!fromComparison.isCommonConsistent) {
        if (status != "") {
            status = status + "|";
        }

        status = status + "INCONSISTENT_COMMON";
    }

    if (status == "") {
        status = "OK";
    }

    return status;
}

/**
 * 期限別CSVヘッダーを追加する。
 *
 * @param fromHorizonH1Bars H1本数。
 * @param fromValues 設定先配列。
 * @param fromIndex 次に設定する配列位置。
 */
void setComparisonHorizonHeaderValues(
    const int fromHorizonH1Bars,
    string &fromValues[],
    int &fromIndex
) {
    string suffix = IntegerToString(fromHorizonH1Bars) + "h";
    fromValues[fromIndex++] = "outcome_run_id_" + suffix;
    fromValues[fromIndex++] = "record_count_" + suffix;
    fromValues[fromIndex++] = "is_calculated_" + suffix;
    fromValues[fromIndex++] = "profit_r_" + suffix;
    fromValues[fromIndex++] = "mfe_r_" + suffix;
    fromValues[fromIndex++] = "mae_r_" + suffix;
    fromValues[fromIndex++] = "bars_held_h1_" + suffix;
    fromValues[fromIndex++] = "exit_reason_" + suffix;
    fromValues[fromIndex++] = "data_status_" + suffix;
}

/**
 * CSVヘッダーを設定する。
 *
 * @param fromValues 設定先配列。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonHeaderValues(
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, comparisonCsvFieldCount);
    int index = 0;
    fromValues[index++] = "schema_version";
    fromValues[index++] = "source_database_file_name";
    fromValues[index++] = "source_run_id";
    fromValues[index++] = "source_run_uid";
    fromValues[index++] = "evaluation_version";
    fromValues[index++] = "price_model";
    fromValues[index++] = "market_signal_key";
    fromValues[index++] = "market_signal_key_alert_count";
    fromValues[index++] = "source_alert_id";
    fromValues[index++] = "source_server";
    fromValues[index++] = "symbol";
    fromValues[index++] = "side";
    fromValues[index++] = "current_bar_time";
    fromValues[index++] = "entry_time";
    fromValues[index++] = "entry_price";
    fromValues[index++] = "spread_pips";
    fromValues[index++] = "stop_loss";
    fromValues[index++] = "source_risk_pips";
    fromValues[index++] = "calculated_risk_pips";
    setComparisonHorizonHeaderValues(6, fromValues, index);
    setComparisonHorizonHeaderValues(12, fromValues, index);
    setComparisonHorizonHeaderValues(24, fromValues, index);
    setComparisonHorizonHeaderValues(48, fromValues, index);
    fromValues[index++] = "comparison_status";
    fromValues[index++] = "missing_horizons";
    fromValues[index++] = "duplicate_horizons";
    fromValues[index++] = "uncalculated_horizons";
    fromValues[index++] = "common_fields_consistent";

    if (index == comparisonCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV header field count is invalid. expected=%d actual=%d",
            comparisonCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 日時をCSV用文字列へ変換する。
 *
 * @param fromDateTime 日時。
 * @return 日時文字列。未設定の場合は空文字。
 */
string formatComparisonDateTime(const datetime fromDateTime) {
    if (fromDateTime <= 0) {
        return "";
    }

    return TimeToString(fromDateTime, TIME_DATE | TIME_SECONDS);
}

/**
 * 期限別結果をCSV行へ追加する。
 *
 * @param fromSlot 期限別結果。
 * @param fromValues 設定先配列。
 * @param fromIndex 次に設定する配列位置。
 */
void setComparisonHorizonRowValues(
    OutcomeComparisonHorizonSlot &fromSlot,
    string &fromValues[],
    int &fromIndex
) {
    bool isSingleRecord = fromSlot.recordCount == 1;
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = IntegerToString(fromSlot.recordCount);
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";
    fromValues[fromIndex++] = "";

    if (!isSingleRecord) {
        return;
    }

    int firstFieldIndex = fromIndex - 9;
    fromValues[firstFieldIndex] = StringFormat(
        "%I64d",
        fromSlot.outcomeRunId
    );
    fromValues[firstFieldIndex + 2] = IntegerToString(
        fromSlot.isCalculated
    );
    fromValues[firstFieldIndex + 7] = fromSlot.exitReason;
    fromValues[firstFieldIndex + 8] = fromSlot.dataStatus;

    if (fromSlot.isCalculated != 1) {
        return;
    }

    fromValues[firstFieldIndex + 3] = DoubleToString(
        fromSlot.profitR,
        6
    );
    fromValues[firstFieldIndex + 4] = DoubleToString(fromSlot.mfeR, 6);
    fromValues[firstFieldIndex + 5] = DoubleToString(fromSlot.maeR, 6);
    fromValues[firstFieldIndex + 6] = IntegerToString(
        fromSlot.barsHeldH1
    );
}

/**
 * 比較結果をCSV行へ変換する。
 *
 * @param fromSourceRunUid Alert Run UID。
 * @param fromComparison 比較結果。
 * @param fromValues 設定先配列。
 * @param fromStatus 比較状態格納先。
 * @param fromMissingHorizonList 欠損期限格納先。
 * @param fromDuplicateHorizonList 重複期限格納先。
 * @param fromUncalculatedHorizonList 未計算期限格納先。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonRowValues(
    const string fromSourceRunUid,
    OutcomeComparisonRow &fromComparison,
    string &fromValues[],
    string &fromStatus,
    string &fromMissingHorizonList,
    string &fromDuplicateHorizonList,
    string &fromUncalculatedHorizonList,
    Logger &fromLogger
) {
    fromStatus = buildComparisonStatus(
        fromComparison,
        fromMissingHorizonList,
        fromDuplicateHorizonList,
        fromUncalculatedHorizonList
    );
    ArrayResize(fromValues, comparisonCsvFieldCount);
    int index = 0;
    fromValues[index++] = comparisonCsvSchemaVersion;
    fromValues[index++] = sourceDatabaseFileName;
    fromValues[index++] = StringFormat("%I64d", sourceRunId);
    fromValues[index++] = fromSourceRunUid;
    fromValues[index++] = getComparisonEvaluationVersion();
    fromValues[index++] = getComparisonPriceModel();
    fromValues[index++] = fromComparison.marketSignalKey;
    fromValues[index++] = IntegerToString(
        fromComparison.marketSignalKeyAlertCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromComparison.sourceAlertId
    );
    fromValues[index++] = fromComparison.sourceServer;
    fromValues[index++] = fromComparison.symbolName;
    fromValues[index++] = fromComparison.side;
    fromValues[index++] = formatComparisonDateTime(
        fromComparison.currentBarTime
    );
    fromValues[index++] = formatComparisonDateTime(
        fromComparison.entryTime
    );
    fromValues[index++] = DoubleToString(fromComparison.entryPrice, 10);
    fromValues[index++] = DoubleToString(fromComparison.spreadPips, 6);
    fromValues[index++] = DoubleToString(fromComparison.stopLoss, 10);
    fromValues[index++] = DoubleToString(
        fromComparison.sourceRiskPips,
        6
    );
    fromValues[index++] = DoubleToString(
        fromComparison.calculatedRiskPips,
        6
    );
    setComparisonHorizonRowValues(
        fromComparison.horizon6,
        fromValues,
        index
    );
    setComparisonHorizonRowValues(
        fromComparison.horizon12,
        fromValues,
        index
    );
    setComparisonHorizonRowValues(
        fromComparison.horizon24,
        fromValues,
        index
    );
    setComparisonHorizonRowValues(
        fromComparison.horizon48,
        fromValues,
        index
    );
    fromValues[index++] = fromStatus;
    fromValues[index++] = fromMissingHorizonList;
    fromValues[index++] = fromDuplicateHorizonList;
    fromValues[index++] = fromUncalculatedHorizonList;
    fromValues[index++] = IntegerToString(
        (int)fromComparison.isCommonConsistent
    );

    if (index == comparisonCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV data field count is invalid. expected=%d actual=%d",
            comparisonCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 比較状態を出力集計へ反映する。
 *
 * @param fromStatus 比較状態。
 * @param fromMissingHorizonList 欠損期限。
 * @param fromDuplicateHorizonList 重複期限。
 * @param fromUncalculatedHorizonList 未計算期限。
 * @param fromIsMarketSignalKeyUnique 比較キーが1 Alertだけの場合true。
 * @param fromIsCommonConsistent 共通項目一致の場合true。
 * @param fromSummary 集計先。
 */
void updateComparisonExportSummary(
    const string fromStatus,
    const string fromMissingHorizonList,
    const string fromDuplicateHorizonList,
    const string fromUncalculatedHorizonList,
    const bool fromIsMarketSignalKeyUnique,
    const bool fromIsCommonConsistent,
    OutcomeComparisonExportSummary &fromSummary
) {
    fromSummary.totalCount++;

    if (fromStatus == "OK") {
        fromSummary.okCount++;
    }

    if (fromMissingHorizonList != "") {
        fromSummary.missingCount++;
    }

    if (fromDuplicateHorizonList != ""
            || !fromIsMarketSignalKeyUnique) {
        fromSummary.duplicateCount++;
    }

    if (fromUncalculatedHorizonList != "") {
        fromSummary.uncalculatedCount++;
    }

    if (!fromIsCommonConsistent) {
        fromSummary.inconsistentCount++;
    }
}

/**
 * 出力CSVファイル名を取得する。
 *
 * @return 入力値またはRun IDから生成したファイル名。
 */
string getComparisonOutputFileName() {
    if (outputCsvFileName != "") {
        return outputCsvFileName;
    }

    return getDefaultComparisonOutputFileName();
}

/**
 * 比較結果をCSVへ上書き出力する。
 *
 * @param fromSourceRunUid Alert Run UID。
 * @param fromComparisons 比較結果一覧。
 * @param fromSummary 出力集計。
 * @param fromLogger ロガー。
 * @return 全行を出力できた場合true。
 */
bool writeOutcomeComparisonCsv(
    const string fromSourceRunUid,
    OutcomeComparisonRow &fromComparisons[],
    OutcomeComparisonExportSummary &fromSummary,
    Logger &fromLogger
) {
    fromSummary.reset();
    string headerValues[];

    if (!setComparisonHeaderValues(headerValues, fromLogger)) {
        return false;
    }

    string fileName = getComparisonOutputFileName();
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

    int comparisonCount = ArraySize(fromComparisons);

    for (int i = 0; i < comparisonCount; i++) {
        string rowValues[];
        string status = "";
        string missingHorizonList = "";
        string duplicateHorizonList = "";
        string uncalculatedHorizonList = "";

        if (!setComparisonRowValues(
                fromSourceRunUid,
                fromComparisons[i],
                rowValues,
                status,
                missingHorizonList,
                duplicateHorizonList,
                uncalculatedHorizonList,
                fromLogger
            ) || !fileWriter.writeRow(rowValues)) {
            fileWriter.close();
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "CSV row write failed. index=%d marketSignalKey=%s",
                    i,
                    fromComparisons[i].marketSignalKey
                )
            );

            return false;
        }

        updateComparisonExportSummary(
            status,
            missingHorizonList,
            duplicateHorizonList,
            uncalculatedHorizonList,
            fromComparisons[i].marketSignalKeyAlertCount == 1,
            fromComparisons[i].isCommonConsistent,
            fromSummary
        );
    }

    fileWriter.close();

    return true;
}

/**
 * 選択したOutcome Runをログ用文字列へまとめる。
 *
 * @param fromRunInfos 比較対象Run一覧。
 * @return H1本数とOutcome Run IDの一覧。
 */
string buildComparisonRunText(
    OutcomeComparisonRunInfo &fromRunInfos[]
) {
    string result = "";

    for (int i = 0; i < comparisonHorizonCount; i++) {
        int horizonH1Bars = getComparisonHorizon(i);
        long outcomeRunId = getComparisonOutcomeRunId(
            fromRunInfos,
            horizonH1Bars
        );

        if (result != "") {
            result = result + ",";
        }

        result = result + StringFormat(
            "%d:%I64d",
            horizonH1Bars,
            outcomeRunId
        );
    }

    return result;
}

/**
 * 6・12・24・48 H1のOutcome比較CSVを生成する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateComparisonInputs(logger)) {
        return;
    }

    SqliteDatabase outcomeDatabase(
        outcomeDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!outcomeDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Outcome DBを読み取り専用で開けません。");

        return;
    }

    OutcomeComparisonRunInfo runInfos[];

    if (!findComparisonRuns(
            outcomeDatabase.getHandle(),
            runInfos,
            logger
        )) {
        logger.error(__FUNCTION__, "Outcome Runの読取に失敗しました。");

        return;
    }

    string sourceRunUid = "";

    if (!validateComparisonRuns(runInfos, sourceRunUid, logger)) {
        logger.error(
            __FUNCTION__,
            "6／12／24／48 H1の比較対象Runが揃っていません。"
        );

        return;
    }

    OutcomeComparisonSourceRow sourceRows[];

    if (!findComparisonSourceRows(
            outcomeDatabase.getHandle(),
            runInfos,
            sourceRows,
            logger
        )) {
        logger.error(__FUNCTION__, "Outcome結果の読取に失敗しました。");

        return;
    }

    if (ArraySize(sourceRows) <= 0) {
        logger.error(__FUNCTION__, "比較対象Outcomeがありません。");

        return;
    }

    OutcomeComparisonRow comparisons[];

    if (!buildOutcomeComparisons(sourceRows, comparisons, logger)) {
        logger.error(__FUNCTION__, "Outcome結果の横持ち変換に失敗しました。");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Outcome comparison export started. sourceRunId=%I64d outcomeRuns=%s sourceRows=%d comparisonRows=%d priceModel=%s evaluation=%s",
            sourceRunId,
            buildComparisonRunText(runInfos),
            ArraySize(sourceRows),
            ArraySize(comparisons),
            getComparisonPriceModel(),
            getComparisonEvaluationVersion()
        )
    );

    OutcomeComparisonExportSummary summary;

    if (!writeOutcomeComparisonCsv(
            sourceRunUid,
            comparisons,
            summary,
            logger
        )) {
        logger.error(__FUNCTION__, "Outcome比較CSVの出力に失敗しました。");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Outcome comparison export finished. file=%s total=%d ok=%d missing=%d duplicate=%d uncalculated=%d inconsistent=%d",
            getComparisonOutputFileName(),
            summary.totalCount,
            summary.okCount,
            summary.missingCount,
            summary.duplicateCount,
            summary.uncalculatedCount,
            summary.inconsistentCount
        )
    );
}
//+------------------------------------------------------------------+
