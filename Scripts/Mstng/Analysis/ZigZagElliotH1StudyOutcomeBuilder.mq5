//+------------------------------------------------------------------+
//|                ZigZagElliotH1StudyOutcomeBuilder.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Analysis\ZigZagElliotH1StudyOutcomeCalculator.mqh>
#include <Mstng\Analysis\ZigZagElliotH1StudyQueryService.mqh>
#include <Mstng\Database\Dao\ZigZagElliotH1StudyOutcomeDao.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** 参照元H1推移DBファイル名。 */
input string sourceDatabaseFileName =
    "mstng-zigzag-elliot-h1-study-2024-2025-r1.sqlite";

/** 参照元Observation Run ID。0の場合は1件だけ存在するRunを自動選択する。 */
input long sourceRunId = 0;

/** 研究結果を保存する別DBファイル名。 */
input string outcomeDatabaseFileName =
    "mstng-zigzag-elliot-h1-study-outcome-2024-2025-r1.sqlite";

/** DBをTerminal Common Filesへ配置する場合true。 */
input bool databaseUseCommonFolder = true;

/** 研究対象Episode開始JSTの下限。 */
input datetime studyFromJstTime = D'2024.01.01 00:00:00';

/** 研究対象Episode開始JSTの対象外上限。 */
input datetime studyToJstTime = D'2026.01.01 00:00:00';

/** 進捗を出力するEntry件数間隔。 */
input int progressInterval = 100;

/** 連続シグナル判定ルールバージョン。 */
const string studySignalRuleVersion = "FULL_ALIGNMENT_EPISODE_V1";

/** 研究用エントリー価格モデル。 */
const string studyEntryPriceModel = "NEXT_H1_OPEN_V1";

/** H1価格評価モデル。 */
const string studyOutcomePriceModel = "H1_BID_OHLC_V1";

/** Spread控除モデル。 */
const string studySpreadModel = "ENTRY_SPREAD_ONCE_V1";

/** 将来成績計算ロジックバージョン。 */
const string studyEvaluationVersion = "H1_FIXED_HORIZONS_V1";

/** 評価期間一覧のCanonical Text。 */
const string studyHorizonsText = "6,12,24,48";

/**
 * H1推移研究Outcome構築件数。
 */
struct ZigZagElliotH1StudyBuildCounters {
    /** 読み取ったStream数。 */
    long sourceStreamCount;

    /** 研究期間内のEpisode数。 */
    long totalSignalCount;

    /** 保存したEntry数。 */
    long totalEntryCount;

    /** 基本研究集計へ使用可能なEntry数。 */
    long researchEligibleEntryCount;

    /** 保存したOutcome数。 */
    long totalOutcomeCount;

    /** 計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** 計算不能Outcome数。 */
    long failedOutcomeCount;

    /**
     * 全件数を0へ初期化する。
     */
    void reset() {
        this.sourceStreamCount = 0;
        this.totalSignalCount = 0;
        this.totalEntryCount = 0;
        this.researchEligibleEntryCount = 0;
        this.totalOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
    }
};

/**
 * 現在時刻を取得する。
 *
 * @return 取引サーバー時刻。利用不能時はローカル時刻。
 */
datetime getStudyCurrentTime() {
    datetime currentTime = TimeTradeServer();
    datetime lastQuoteTime = TimeCurrent();

    if (lastQuoteTime > currentTime) {
        currentTime = lastQuoteTime;
    }

    if (currentTime <= 0) {
        currentTime = TimeLocal();
    }

    return currentTime;
}

/**
 * 正の有限値か判定する。
 *
 * @param fromValue 判定値。
 * @return 正の有限値の場合true。
 */
bool isPositiveStudyNumber(const double fromValue) {
    return MathIsValidNumber(fromValue)
        && fromValue != EMPTY_VALUE
        && fromValue > 0.0;
}

/**
 * 0以上の有限値か判定する。
 *
 * @param fromValue 判定値。
 * @return 0以上の有限値の場合true。
 */
bool isNonNegativeStudyNumber(const double fromValue) {
    return MathIsValidNumber(fromValue)
        && fromValue != EMPTY_VALUE
        && fromValue >= 0.0;
}

/**
 * Script入力を検証する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateStudyInputs(Logger &fromLogger) {
    if (sourceDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "sourceDatabaseFileName is empty.");

        return false;
    }

    if (outcomeDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "outcomeDatabaseFileName is empty.");

        return false;
    }

    if (StringCompare(
            sourceDatabaseFileName,
            outcomeDatabaseFileName,
            false
        ) == 0) {
        fromLogger.error(
            __FUNCTION__,
            "Source DB and Outcome DB must be different files."
        );

        return false;
    }

    if (sourceRunId < 0) {
        fromLogger.error(__FUNCTION__, "sourceRunId must not be negative.");

        return false;
    }

    if (studyFromJstTime <= 0
            || studyToJstTime <= studyFromJstTime) {
        fromLogger.error(__FUNCTION__, "Study JST range is invalid.");

        return false;
    }

    if (progressInterval <= 0) {
        fromLogger.error(__FUNCTION__, "progressInterval must be positive.");

        return false;
    }

    return true;
}

/**
 * 入力値に従って参照元Runを選択する。
 *
 * sourceRunIdが0の場合、Observationを持つRunが1件だけなら
 * 自動選択する。0件または複数件の場合はエラーとする。
 *
 * @param fromQueryService 参照元DB Query Service。
 * @param fromRunInfo 選択したRun情報。
 * @param fromLogger ロガー。
 * @return Runを選択できた場合true。
 */
bool selectStudySourceRun(
    ZigZagElliotH1StudyQueryService &fromQueryService,
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();

    if (sourceRunId > 0) {
        bool isFound = false;

        if (!fromQueryService.findRun(
                sourceRunId,
                fromRunInfo,
                isFound
            )) {
            fromLogger.error(__FUNCTION__, "Source Run read failed.");

            return false;
        }

        if (!isFound) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Source Run was not found. runId=%I64d",
                    sourceRunId
                )
            );

            return false;
        }

        return true;
    }

    ZigZagElliotH1StudySourceRunInfo runInfos[];

    if (!fromQueryService.findRuns(runInfos)) {
        fromLogger.error(__FUNCTION__, "Source Run list read failed.");

        return false;
    }

    int runCount = ArraySize(runInfos);

    if (runCount != 1) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "sourceRunId=0 requires exactly one Run. count=%d",
                runCount
            )
        );

        for (int i = 0; i < runCount; i++) {
            fromLogger.info(
                __FUNCTION__,
                StringFormat(
                    "Source Run candidate. runId=%I64d uid=%s status=%s",
                    runInfos[i].runId,
                    runInfos[i].runUid,
                    runInfos[i].status
                )
            );
        }

        return false;
    }

    fromRunInfo = runInfos[0];
    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "Source Run was selected automatically. runId=%I64d uid=%s",
            fromRunInfo.runId,
            fromRunInfo.runUid
        )
    );

    return true;
}

/**
 * Outcome Run保存に必要な参照元Run項目を検証する。
 *
 * @param fromRunInfo 参照元Run情報。
 * @param fromLogger ロガー。
 * @return 必須項目が利用可能な場合true。
 */
bool validateStudySourceRun(
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    if (fromRunInfo.runId <= 0
            || fromRunInfo.runUid == ""
            || fromRunInfo.sourceMode == ""
            || fromRunInfo.sourceServer == ""
            || fromRunInfo.programName == ""
            || fromRunInfo.programVersion == ""
            || fromRunInfo.strategy == ""
            || fromRunInfo.strategyVersion == ""
            || fromRunInfo.analysisVersion == "") {
        fromLogger.error(
            __FUNCTION__,
            "Source Run metadata required by Outcome DB is incomplete."
        );

        return false;
    }

    if (fromRunInfo.status != "LEGACY"
            && fromRunInfo.status != "COMPLETED") {
        fromLogger.error(
            __FUNCTION__,
            "Source Run status is not eligible. status="
                + fromRunInfo.status
        );

        return false;
    }

    return true;
}

/**
 * 参照元RunからOutcome Runを組み立てる。
 *
 * @param fromRunInfo 参照元Run情報。
 * @param fromEntity 組み立て先。
 */
void buildStudyOutcomeRunEntity(
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    ZigZagElliotH1StudyOutcomeRunEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.runKey = StringFormat(
        "%s|%I64d|%s|%I64d|%I64d|%s|%s|%s|%s|%s|%s",
        sourceDatabaseFileName,
        fromRunInfo.runId,
        fromRunInfo.runUid,
        (long)studyFromJstTime,
        (long)studyToJstTime,
        studySignalRuleVersion,
        studyEntryPriceModel,
        studyOutcomePriceModel,
        studySpreadModel,
        studyEvaluationVersion,
        studyHorizonsText
    );
    fromEntity.sourceDatabaseFileName = sourceDatabaseFileName;
    fromEntity.sourceRunId = fromRunInfo.runId;
    fromEntity.sourceRunUid = fromRunInfo.runUid;
    fromEntity.sourceMode = fromRunInfo.sourceMode;
    fromEntity.sourceServer = fromRunInfo.sourceServer;
    fromEntity.sourceLogin = fromRunInfo.sourceLogin;
    fromEntity.sourceProgramName = fromRunInfo.programName;
    fromEntity.sourceProgramVersion = fromRunInfo.programVersion;
    fromEntity.sourceStrategy = fromRunInfo.strategy;
    fromEntity.sourceStrategyVersion = fromRunInfo.strategyVersion;
    fromEntity.sourceAnalysisVersion = fromRunInfo.analysisVersion;
    fromEntity.sourceAnalysisInputHash = fromRunInfo.analysisInputHash;
    fromEntity.sourceInputHash = fromRunInfo.inputHash;
    fromEntity.sourceTesterFrom = fromRunInfo.testerFrom;
    fromEntity.sourceTesterTo = fromRunInfo.testerTo;
    fromEntity.sourceTesterModel = fromRunInfo.testerModel;
    fromEntity.studyFromJstTime = studyFromJstTime;
    fromEntity.studyToJstTime = studyToJstTime;
    fromEntity.signalRuleVersion = studySignalRuleVersion;
    fromEntity.entryPriceModel = studyEntryPriceModel;
    fromEntity.spreadModel = studySpreadModel;
    fromEntity.evaluationVersion = studyEvaluationVersion;
    fromEntity.horizonsText = studyHorizonsText;
    fromEntity.startedAt = getStudyCurrentTime();
    fromEntity.createdAt = fromEntity.startedAt;
}

/**
 * Episode直前の観測完全性からGap有無を判定する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @return 直前行があり、非連続または必要時間足欠損の場合1。
 */
int getStudyDataGapBefore(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeStartIndex
) {
    if (fromEpisodeStartIndex <= 0) {
        return 0;
    }

    ZigZagElliotH1StudyObservationRow previousRow =
        fromRows[fromEpisodeStartIndex - 1];
    ZigZagElliotH1StudyObservationRow startRow =
        fromRows[fromEpisodeStartIndex];

    if (!ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
            previousRow.anchorBarTime,
            startRow.anchorBarTime
        ) || previousRow.isRequiredTimeFramesComplete != 1) {
        return 1;
    }

    return 0;
}

/**
 * Episode直後の観測完全性からGap有無を判定する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeEndIndex Episode終了位置。
 * @return 直後行があり、非連続または必要時間足欠損の場合1。
 */
int getStudyDataGapAfter(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeEndIndex
) {
    int rowCount = ArraySize(fromRows);

    if (fromEpisodeEndIndex < 0
            || fromEpisodeEndIndex + 1 >= rowCount) {
        return 0;
    }

    ZigZagElliotH1StudyObservationRow endRow =
        fromRows[fromEpisodeEndIndex];
    ZigZagElliotH1StudyObservationRow nextRow =
        fromRows[fromEpisodeEndIndex + 1];

    if (!ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
            endRow.anchorBarTime,
            nextRow.anchorBarTime
        ) || nextRow.isRequiredTimeFramesComplete != 1) {
        return 1;
    }

    return 0;
}

/**
 * Entry観測値をEntityへ設定する。
 *
 * @param fromEntryRow Entry候補の直後親行。
 * @param fromEntity 設定先Entry。
 */
void setStudyEntryObservationValues(
    ZigZagElliotH1StudyObservationRow &fromEntryRow,
    ZigZagElliotH1StudyEntryEntity &fromEntity
) {
    bool hasEntryPrice = fromEntryRow.isH1Available == 1
        && isPositiveStudyNumber(fromEntryRow.currentOpen);
    bool hasSpread = fromEntryRow.isSpreadAvailable == 1
        && isNonNegativeStudyNumber(fromEntryRow.spreadPips);
    bool hasPipSize = isPositiveStudyNumber(fromEntryRow.pipSize)
        && fromEntryRow.pipSizeSource != "";
    bool hasEntryAtr = fromEntryRow.isAtr14Available == 1
        && isPositiveStudyNumber(fromEntryRow.atr14Pips);

    if (hasEntryPrice) {
        fromEntity.entryObservationId = fromEntryRow.observationId;
        fromEntity.entryTime = fromEntryRow.anchorBarTime;
        fromEntity.entryJstTime = fromEntryRow.anchorJstTime;
        fromEntity.entryPrice = fromEntryRow.currentOpen;
    }

    if (hasSpread) {
        fromEntity.isSpreadAvailable = 1;
        fromEntity.spreadPips = fromEntryRow.spreadPips;
    }

    if (hasPipSize) {
        fromEntity.isPipSizeAvailable = 1;
        fromEntity.pipSize = fromEntryRow.pipSize;
        fromEntity.pipSizeSource = fromEntryRow.pipSizeSource;
    }

    if (hasEntryAtr) {
        fromEntity.isEntryAtrAvailable = 1;
        fromEntity.entryAtr14Pips = fromEntryRow.atr14Pips;
    }
}

/**
 * Entry観測値の状態を取得する。
 *
 * @param fromEntryRow Entry候補の直後親行。
 * @return READYまたは利用不能理由。
 */
string getStudyEntryObservationStatus(
    ZigZagElliotH1StudyObservationRow &fromEntryRow
) {
    if (fromEntryRow.isH1Available != 1) {
        return "ENTRY_H1_MISSING";
    }

    if (!isPositiveStudyNumber(fromEntryRow.currentOpen)) {
        return "ENTRY_PRICE_INVALID";
    }

    if (fromEntryRow.isSpreadAvailable != 1) {
        return "ENTRY_SPREAD_MISSING";
    }

    if (!isNonNegativeStudyNumber(fromEntryRow.spreadPips)) {
        return "ENTRY_SPREAD_INVALID";
    }

    if (!isPositiveStudyNumber(fromEntryRow.pipSize)) {
        return "PIP_SIZE_INVALID";
    }

    if (fromEntryRow.pipSizeSource == "") {
        return "PIP_SIZE_SOURCE_MISSING";
    }

    if (fromEntryRow.isAtr14Available != 1) {
        return "ENTRY_ATR_MISSING";
    }

    if (!isPositiveStudyNumber(fromEntryRow.atr14Pips)) {
        return "ENTRY_ATR_INVALID";
    }

    return "READY";
}

/**
 * Episodeの指定確認本数からEntry Entityを組み立てる。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @param fromEpisodeEndIndex Episode終了位置。
 * @param fromConfirmationH1Count 連続確認本数。
 * @param fromSide BUYまたはSELL。
 * @param fromOutcomeRunId Outcome Run ID。
 * @param fromEntryIndex 計算に使用可能な直後親行位置。利用不能時は-1。
 * @param fromEntity 組み立て先Entry。
 */
void buildStudyEntryEntity(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeStartIndex,
    const int fromEpisodeEndIndex,
    const int fromConfirmationH1Count,
    const string fromSide,
    const long fromOutcomeRunId,
    int &fromEntryIndex,
    ZigZagElliotH1StudyEntryEntity &fromEntity
) {
    fromEntity.reset();
    fromEntryIndex = -1;
    int confirmationIndex = fromEpisodeStartIndex
        + fromConfirmationH1Count - 1;
    int rowCount = ArraySize(fromRows);
    ZigZagElliotH1StudyObservationRow startRow =
        fromRows[fromEpisodeStartIndex];
    ZigZagElliotH1StudyObservationRow endRow =
        fromRows[fromEpisodeEndIndex];
    ZigZagElliotH1StudyObservationRow confirmationRow =
        fromRows[confirmationIndex];
    int episodeH1Count = fromEpisodeEndIndex
        - fromEpisodeStartIndex + 1;

    fromEntity.outcomeRunId = fromOutcomeRunId;
    fromEntity.sourceRunId = startRow.runId;
    fromEntity.signalStartObservationId = startRow.observationId;
    fromEntity.signalEndObservationId = endRow.observationId;
    fromEntity.confirmationObservationId =
        confirmationRow.observationId;
    fromEntity.sourceMode = startRow.sourceMode;
    fromEntity.sourceServer = startRow.sourceServer;
    fromEntity.symbolName = startRow.symbolName;
    fromEntity.anchorTimeFrame = startRow.anchorTimeFrame;
    fromEntity.capturePhase = startRow.capturePhase;
    fromEntity.analysisVersion = startRow.analysisVersion;
    fromEntity.analysisInputHash = startRow.analysisInputHash;
    fromEntity.side = fromSide;
    fromEntity.episodeH1Count = episodeH1Count;
    fromEntity.confirmationH1Count = fromConfirmationH1Count;
    fromEntity.isLeftCensored = 0;

    if (fromEpisodeStartIndex == 0) {
        fromEntity.isLeftCensored = 1;
    }

    fromEntity.isRightCensored = 0;

    if (fromEpisodeEndIndex + 1 >= rowCount) {
        fromEntity.isRightCensored = 1;
    }

    fromEntity.hasDataGapBefore = getStudyDataGapBefore(
        fromRows,
        fromEpisodeStartIndex
    );
    fromEntity.hasDataGapAfter = getStudyDataGapAfter(
        fromRows,
        fromEpisodeEndIndex
    );
    fromEntity.signalStartTime = startRow.anchorBarTime;
    fromEntity.signalEndTime = endRow.anchorBarTime;
    fromEntity.confirmationTime = confirmationRow.anchorBarTime;
    fromEntity.signalStartJstTime = startRow.anchorJstTime;
    fromEntity.confirmationJstTime = confirmationRow.anchorJstTime;
    fromEntity.pipSizeSource = "NOT_AVAILABLE";
    fromEntity.signalRuleVersion = studySignalRuleVersion;
    fromEntity.entryPriceModel = studyEntryPriceModel;
    fromEntity.spreadModel = studySpreadModel;
    fromEntity.evaluationVersion = studyEvaluationVersion;
    fromEntity.createdAt = getStudyCurrentTime();

    int nextIndex = confirmationIndex + 1;

    if (nextIndex >= rowCount) {
        fromEntity.entryStatus = "NEXT_H1_MISSING";
        fromEntity.calculationNote = StringFormat(
            "CONFIRMATION_OBSERVATION_ID=%I64d;NEXT_PARENT=NONE",
            confirmationRow.observationId
        );
    } else {
        ZigZagElliotH1StudyObservationRow nextRow = fromRows[nextIndex];

        if (!ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
                confirmationRow.anchorBarTime,
                nextRow.anchorBarTime
            )) {
            fromEntity.entryStatus = "NEXT_H1_GAP";
            fromEntity.calculationNote = StringFormat(
                "CONFIRMATION_OBSERVATION_ID=%I64d;NEXT_PARENT_OBSERVATION_ID=%I64d;NEXT_PARENT_TIME=%s",
                confirmationRow.observationId,
                nextRow.observationId,
                TimeToString(
                    nextRow.anchorBarTime,
                    TIME_DATE | TIME_SECONDS
                )
            );
        } else {
            fromEntryIndex = nextIndex;
            setStudyEntryObservationValues(nextRow, fromEntity);
            fromEntity.entryStatus = getStudyEntryObservationStatus(nextRow);
            fromEntity.calculationNote = StringFormat(
                "CONFIRMATION_OBSERVATION_ID=%I64d;NEXT_PARENT_OBSERVATION_ID=%I64d;ENTRY_STATUS=%s;PIP_SIZE_SOURCE=%s",
                confirmationRow.observationId,
                nextRow.observationId,
                fromEntity.entryStatus,
                fromEntity.pipSizeSource
            );
        }
    }

    fromEntity.eligibilityStatus = "ELIGIBLE";
    fromEntity.isResearchEligible = 1;

    if (fromEntity.isLeftCensored == 1) {
        fromEntity.eligibilityStatus = "LEFT_CENSORED";
        fromEntity.isResearchEligible = 0;
    } else if (fromEntity.hasDataGapBefore == 1) {
        fromEntity.eligibilityStatus = "DATA_GAP_BEFORE";
        fromEntity.isResearchEligible = 0;
    } else if (fromEntity.entryStatus != "READY") {
        fromEntity.eligibilityStatus = "ENTRY_UNAVAILABLE";
        fromEntity.isResearchEligible = 0;
    }

    fromEntity.calculationNote += StringFormat(
        ";ELIGIBILITY_STATUS=%s;RIGHT_CENSORED=%d;DATA_GAP_AFTER=%d",
        fromEntity.eligibilityStatus,
        fromEntity.isRightCensored,
        fromEntity.hasDataGapAfter
    );
}

/**
 * Calculator結果から1期間のOutcome Entityを組み立てる。
 *
 * @param fromEntryId 保存済みEntry ID。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromResult Calculator結果。
 * @param fromEntity 組み立て先Outcome。
 */
void buildStudyOutcomeEntity(
    const long fromEntryId,
    const int fromHorizonH1Bars,
    ZigZagElliotH1StudyOutcomeCalculationResult &fromResult,
    ZigZagElliotH1StudyOutcomeEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.entryId = fromEntryId;
    fromEntity.horizonH1Bars = fromHorizonH1Bars;
    fromEntity.isCalculated = fromResult.isCalculated;
    fromEntity.evaluationEndObservationId = fromResult.endObsId;
    fromEntity.evaluationEndTime = fromResult.endTime;
    fromEntity.exitPrice = fromResult.exitPrice;
    fromEntity.grossProfitPips = fromResult.grossProfitPips;
    fromEntity.netProfitPips = fromResult.spreadAdjustedProfitPips;
    fromEntity.grossProfitAtr = fromResult.grossProfitAtr;
    fromEntity.netProfitAtr = fromResult.spreadAdjustedProfitAtr;
    fromEntity.mfePips = fromResult.mfePips;
    fromEntity.maePips = fromResult.maePips;
    fromEntity.maxProfitH1Bars = fromResult.maxProfitH1Bars;
    fromEntity.evaluatedH1Bars = fromResult.evaluatedH1Bars;
    fromEntity.dataStatus = fromResult.dataStatus;
    fromEntity.calculationNote = fromResult.note;
    fromEntity.priceModel = studyOutcomePriceModel;
    fromEntity.spreadModel = studySpreadModel;
    fromEntity.evaluationVersion = studyEvaluationVersion;
    fromEntity.createdAt = getStudyCurrentTime();
}

/**
 * Episodeから1、2、3本連続確認Entryと4期間Outcomeを保存する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @param fromEpisodeEndIndex Episode終了位置。
 * @param fromSide BUYまたはSELL。
 * @param fromOutcomeRunId Outcome Run ID。
 * @param fromDao 保存先DAO。
 * @param fromCounters 実行件数。
 * @param fromLogger ロガー。
 * @return 全EntryとOutcomeを保存できた場合true。
 */
bool saveStudyEpisode(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeStartIndex,
    const int fromEpisodeEndIndex,
    const string fromSide,
    const long fromOutcomeRunId,
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    ZigZagElliotH1StudyBuildCounters &fromCounters,
    Logger &fromLogger
) {
    int episodeH1Count = fromEpisodeEndIndex
        - fromEpisodeStartIndex + 1;
    int confirmationLimit = episodeH1Count;

    if (confirmationLimit > 3) {
        confirmationLimit = 3;
    }

    int horizons[4] = {6, 12, 24, 48};

    for (int i = 1; i <= confirmationLimit; i++) {
        if (IsStopped()) {
            fromLogger.error(__FUNCTION__, "Study build was stopped.");

            return false;
        }

        int entryIndex = -1;
        ZigZagElliotH1StudyEntryEntity entryEntity;
        buildStudyEntryEntity(
            fromRows,
            fromEpisodeStartIndex,
            fromEpisodeEndIndex,
            i,
            fromSide,
            fromOutcomeRunId,
            entryIndex,
            entryEntity
        );

        if (!fromDao.saveEntry(entryEntity)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Entry save failed. signalObservationId=%I64d confirmation=%d",
                    entryEntity.signalStartObservationId,
                    i
                )
            );

            return false;
        }

        fromCounters.totalEntryCount++;

        if (entryEntity.isResearchEligible == 1) {
            fromCounters.researchEligibleEntryCount++;
        }

        for (int j = 0; j < 4; j++) {
            if (IsStopped()) {
                fromLogger.error(__FUNCTION__, "Study build was stopped.");

                return false;
            }

            ZigZagElliotH1StudyOutcomeCalculationResult result;
            result.reset();

            if (entryIndex >= 0) {
                ZigZagElliotH1StudyOutcomeCalculator::calculate(
                    fromRows,
                    entryIndex,
                    fromSide,
                    horizons[j],
                    result
                );
            } else {
                result.dataStatus = entryEntity.entryStatus;
                result.note = entryEntity.calculationNote;
            }

            ZigZagElliotH1StudyOutcomeEntity outcomeEntity;
            buildStudyOutcomeEntity(
                entryEntity.id,
                horizons[j],
                result,
                outcomeEntity
            );

            if (!fromDao.saveOutcome(outcomeEntity)) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "Outcome save failed. entryId=%I64d horizon=%d",
                        entryEntity.id,
                        horizons[j]
                    )
                );

                return false;
            }

            fromCounters.totalOutcomeCount++;

            if (outcomeEntity.isCalculated == 1) {
                fromCounters.calculatedOutcomeCount++;
            } else {
                fromCounters.failedOutcomeCount++;
            }
        }

        if (fromCounters.totalEntryCount % (long)progressInterval == 0) {
            fromLogger.info(
                __FUNCTION__,
                StringFormat(
                    "Study progress. streams=%I64d signals=%I64d entries=%I64d eligible=%I64d outcomes=%I64d calculated=%I64d failed=%I64d",
                    fromCounters.sourceStreamCount,
                    fromCounters.totalSignalCount,
                    fromCounters.totalEntryCount,
                    fromCounters.researchEligibleEntryCount,
                    fromCounters.totalOutcomeCount,
                    fromCounters.calculatedOutcomeCount,
                    fromCounters.failedOutcomeCount
                )
            );
        }
    }

    return true;
}

/**
 * 1Streamの全親行でEpisodeを確定し、期間内Episodeを保存する。
 *
 * @param fromStream 取得対象Stream。
 * @param fromQueryService 参照元DB Query Service。
 * @param fromOutcomeRunId Outcome Run ID。
 * @param fromDao 保存先DAO。
 * @param fromCounters 実行件数。
 * @param fromLogger ロガー。
 * @return Streamを処理できた場合true。
 */
bool processStudyStream(
    ZigZagElliotH1StudyStreamKey &fromStream,
    ZigZagElliotH1StudyQueryService &fromQueryService,
    const long fromOutcomeRunId,
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    ZigZagElliotH1StudyBuildCounters &fromCounters,
    Logger &fromLogger
) {
    ZigZagElliotH1StudyObservationRow rows[];

    if (!fromQueryService.findObservations(fromStream, rows)) {
        fromLogger.error(
            __FUNCTION__,
            "Observation read failed. symbol=" + fromStream.symbolName
        );

        return false;
    }

    fromCounters.sourceStreamCount++;
    int rowCount = ArraySize(rows);
    int rowIndex = 0;

    while (rowIndex < rowCount) {
        if (IsStopped()) {
            fromLogger.error(__FUNCTION__, "Study build was stopped.");

            return false;
        }

        string side =
            ZigZagElliotH1StudyOutcomeCalculator::classifyFullAlignmentSide(
                rows[rowIndex]
            );

        if (side == "") {
            rowIndex++;
            continue;
        }

        int episodeStartIndex = rowIndex;
        int episodeEndIndex = rowIndex;

        while (episodeEndIndex + 1 < rowCount) {
            int nextIndex = episodeEndIndex + 1;
            string nextSide =
                ZigZagElliotH1StudyOutcomeCalculator::classifyFullAlignmentSide(
                    rows[nextIndex]
                );

            if (nextSide != side
                    || !ZigZagElliotH1StudyOutcomeCalculator::
                        isConsecutiveMarketH1(
                            rows[episodeEndIndex].anchorBarTime,
                            rows[nextIndex].anchorBarTime
                        )) {
                break;
            }

            episodeEndIndex = nextIndex;
        }

        datetime episodeStartJstTime =
            rows[episodeStartIndex].anchorJstTime;

        if (episodeStartJstTime >= studyFromJstTime
                && episodeStartJstTime < studyToJstTime) {
            fromCounters.totalSignalCount++;

            if (!saveStudyEpisode(
                    rows,
                    episodeStartIndex,
                    episodeEndIndex,
                    side,
                    fromOutcomeRunId,
                    fromDao,
                    fromCounters,
                    fromLogger
                )) {
                return false;
            }
        }

        rowIndex = episodeEndIndex + 1;
    }

    return true;
}

/**
 * 構築失敗後に保存トランザクションをロールバックする。
 *
 * @param fromDao 保存先DAO。
 * @param fromLogger ロガー。
 */
void rollbackStudyBuild(
    ZigZagElliotH1StudyOutcomeDao &fromDao,
    Logger &fromLogger
) {
    if (!fromDao.rollbackTransaction()) {
        fromLogger.error(__FUNCTION__, "Outcome transaction rollback failed.");

        return;
    }

    fromLogger.error(
        __FUNCTION__,
        "Outcome build was rolled back. Previous completed result was kept."
    );
}

/**
 * H1推移研究のEpisode、Entryおよび将来成績を構築する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateStudyInputs(logger)) {
        return;
    }

    SqliteDatabase sourceDatabase(
        sourceDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!sourceDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Source DB could not be opened read-only.");

        return;
    }

    ZigZagElliotH1StudyQueryService queryService(
        sourceDatabase.getHandle()
    );
    ZigZagElliotH1StudySourceRunInfo sourceRunInfo;

    if (!selectStudySourceRun(queryService, sourceRunInfo, logger)
            || !validateStudySourceRun(sourceRunInfo, logger)) {
        return;
    }

    ZigZagElliotH1StudyStreamKey streams[];

    if (!queryService.findStreams(sourceRunInfo.runId, streams)) {
        logger.error(__FUNCTION__, "Observation Stream list read failed.");

        return;
    }

    int streamCount = ArraySize(streams);

    if (streamCount <= 0) {
        logger.error(__FUNCTION__, "Source Run has no Observation Stream.");

        return;
    }

    for (int i = 0; i < streamCount; i++) {
        if (streams[i].anchorTimeFrame != PERIOD_H1) {
            logger.error(
                __FUNCTION__,
                StringFormat(
                    "Non-H1 Stream is not supported. symbol=%s anchorTimeFrame=%d",
                    streams[i].symbolName,
                    streams[i].anchorTimeFrame
                )
            );

            return;
        }
    }

    SqliteDatabase outcomeDatabase(
        outcomeDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!outcomeDatabase.open()) {
        logger.error(__FUNCTION__, "Outcome DB could not be opened.");

        return;
    }

    ZigZagElliotH1StudyOutcomeDao outcomeDao(
        outcomeDatabase.getHandle()
    );

    if (!outcomeDao.createTables()) {
        logger.error(__FUNCTION__, "Outcome DB initialization failed.");

        return;
    }

    ZigZagElliotH1StudyOutcomeRunEntity runEntity;
    buildStudyOutcomeRunEntity(sourceRunInfo, runEntity);

    if (!outcomeDao.beginTransaction()) {
        logger.error(__FUNCTION__, "Outcome transaction could not be started.");

        return;
    }

    long outcomeRunId = 0;

    if (!outcomeDao.findOrCreateRun(runEntity, outcomeRunId)
            || !outcomeDao.deleteRunChildren(outcomeRunId)) {
        logger.error(__FUNCTION__, "Outcome Run could not be prepared.");
        rollbackStudyBuild(outcomeDao, logger);

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Study build started. sourceRunId=%I64d outcomeRunId=%I64d streams=%d JST=[%s,%s) signalRule=%s entryModel=%s priceModel=%s spreadModel=%s evaluation=%s",
            sourceRunInfo.runId,
            outcomeRunId,
            streamCount,
            TimeToString(studyFromJstTime, TIME_DATE | TIME_SECONDS),
            TimeToString(studyToJstTime, TIME_DATE | TIME_SECONDS),
            studySignalRuleVersion,
            studyEntryPriceModel,
            studyOutcomePriceModel,
            studySpreadModel,
            studyEvaluationVersion
        )
    );

    ZigZagElliotH1StudyBuildCounters counters;
    counters.reset();

    for (int i = 0; i < streamCount; i++) {
        if (!processStudyStream(
                streams[i],
                queryService,
                outcomeRunId,
                outcomeDao,
                counters,
                logger
            )) {
            rollbackStudyBuild(outcomeDao, logger);

            return;
        }
    }

    if (!outcomeDao.completeRun(
            outcomeRunId,
            "COMPLETED",
            counters.sourceStreamCount,
            counters.totalSignalCount,
            counters.totalEntryCount,
            counters.researchEligibleEntryCount,
            counters.totalOutcomeCount,
            counters.calculatedOutcomeCount,
            counters.failedOutcomeCount
        )) {
        logger.error(__FUNCTION__, "Outcome Run completion update failed.");
        rollbackStudyBuild(outcomeDao, logger);

        return;
    }

    if (!outcomeDao.commitTransaction()) {
        logger.error(__FUNCTION__, "Outcome transaction commit failed.");
        rollbackStudyBuild(outcomeDao, logger);

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Study build finished. status=COMPLETED outcomeRunId=%I64d streams=%I64d signals=%I64d entries=%I64d eligible=%I64d outcomes=%I64d calculated=%I64d failed=%I64d output=%s",
            outcomeRunId,
            counters.sourceStreamCount,
            counters.totalSignalCount,
            counters.totalEntryCount,
            counters.researchEligibleEntryCount,
            counters.totalOutcomeCount,
            counters.calculatedOutcomeCount,
            counters.failedOutcomeCount,
            outcomeDatabaseFileName
        )
    );
}
