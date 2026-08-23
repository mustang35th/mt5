//+------------------------------------------------------------------+
//|                   ZigZagElliotEntryOutcomeBuilder.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Analysis\ZigZagElliotEntryCandidateQueryService.mqh>
#include <Mstng\Analysis\ZigZagElliotEntryHistoryValidator.mqh>
#include <Mstng\Analysis\ZigZagElliotEntryOutcomeCalculator.mqh>
#include <Mstng\Database\Dao\ZigZagElliotEntryOutcomeDao.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\RateUtil.mqh>

/** 参照元Alert DBファイル名。 */
input string sourceDatabaseFileName =
    "mstng-zigzag-elliot-alert.sqlite";

/** 正常完了を確認済みのTESTER Run ID。0の場合は候補一覧だけを表示する。 */
input long sourceRunId = 0;

/** 後処理結果を保存する別DBファイル名。 */
input string outcomeDatabaseFileName =
    "mstng-zigzag-elliot-entry-outcome.sqlite";

/** DBをTerminal Common Filesへ配置する場合true。 */
input bool databaseUseCommonFolder = true;

/** 初期SL未到達時に決済するH1本数。 */
input int horizonH1Bars = 48;

/** 履歴取得の最大試行回数。 */
input int historyRetryCount = 5;

/** 処理前に対象シンボルの履歴同期を待つ最大秒数。 */
input int historyWarmUpTimeoutSeconds = 60;

/** 履歴取得の再試行間隔ミリ秒。 */
input int historyRetryIntervalMilliseconds = 500;

/** 進捗を出力する処理件数間隔。 */
input int progressInterval = 25;

/** M1価格の評価モデル。 */
const string outcomePriceModel = "M1_BID_SPREAD_APPROX_V1";

/** 後処理ロジックのバージョン。 */
const string outcomeEvaluationVersion = "INITIAL_SL_HORIZON_V2";

/** Alert DBと再計算リスクの許容差pips。 */
const double riskTolerancePips = 0.11;

/**
 * シンボル単位の履歴ウォームアップ範囲。
 */
struct OutcomeHistoryRange {
    /** 対象シンボル。 */
    string symbolName;

    /** 最古エントリーH1開始時刻。 */
    datetime earliestEntryTime;

    /** 最新エントリーH1開始時刻。 */
    datetime latestEntryTime;

    /**
     * 未設定状態へ初期化する。
     */
    void reset() {
        this.symbolName = "";
        this.earliestEntryTime = 0;
        this.latestEntryTime = 0;
    }
};

/**
 * 現在時刻を取得する。
 *
 * @return 取引サーバー時刻。利用不能時はローカル時刻。
 */
datetime getOutcomeCurrentTime() {
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
 * Script入力が実行可能な範囲か確認する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateOutcomeInputs(Logger &fromLogger) {
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

    if (horizonH1Bars <= 0) {
        fromLogger.error(__FUNCTION__, "horizonH1Bars must be positive.");

        return false;
    }

    if (historyRetryCount <= 0
            || historyWarmUpTimeoutSeconds <= 0
            || historyRetryIntervalMilliseconds <= 0
            || progressInterval <= 0) {
        fromLogger.error(__FUNCTION__, "History or progress input is invalid.");

        return false;
    }

    return true;
}

/**
 * sourceRunIdへ指定可能な直近Runをログへ表示する。
 *
 * 一覧は選択候補の提示だけに使用し、自動的なRun選択は行わない。
 *
 * @param fromQueryService Alert DB読取サービス。
 * @param fromLogger ロガー。
 * @return 一覧を取得できた場合true。
 */
bool printRecentOutcomeSourceRuns(
    ZigZagElliotEntryCandidateQueryService &fromQueryService,
    Logger &fromLogger
) {
    SourceRunInfo runInfos[];

    if (!fromQueryService.findRecentEligibleRuns(10, runInfos)) {
        return false;
    }

    int runCount = ArraySize(runInfos);

    if (runCount <= 0) {
        fromLogger.warn(
            __FUNCTION__,
            "H1 ENTRYを持つRunが見つかりません。"
        );

        return true;
    }

    fromLogger.info(
        __FUNCTION__,
        "sourceRunIdを指定してください。直近候補を表示します。"
    );

    for (int i = 0; i < runCount; i++) {
        fromLogger.info(
            __FUNCTION__,
            StringFormat(
                "runId=%I64d mode=%s program=%s %s strategy=%s %s analysis=%s started=%s",
                runInfos[i].runId,
                runInfos[i].sourceMode,
                runInfos[i].programName,
                runInfos[i].programVersion,
                runInfos[i].strategy,
                runInfos[i].strategyVersion,
                runInfos[i].analysisVersion,
                TimeToString(
                    runInfos[i].startedAt,
                    TIME_DATE | TIME_SECONDS
                )
            )
        );
    }

    return true;
}

/**
 * 選択Runが最小版の対象条件を満たすか確認する。
 *
 * @param fromRunInfo 選択Run情報。
 * @param fromLogger ロガー。
 * @return TESTERのZigZagElliot MTF_3in3 Runの場合true。
 */
bool validateOutcomeSourceRun(
    SourceRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    if (fromRunInfo.sourceMode != "TESTER") {
        fromLogger.error(
            __FUNCTION__,
            "The minimal builder accepts TESTER runs only."
        );

        return false;
    }

    if (fromRunInfo.source != "ZIGZAG_ELLIOT"
            || fromRunInfo.strategy != "MTF_3in3") {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Unsupported run. source=%s strategy=%s",
                fromRunInfo.source,
                fromRunInfo.strategy
            )
        );

        return false;
    }

    string currentServer = AccountInfoString(ACCOUNT_SERVER);

    if (currentServer == ""
            || currentServer != fromRunInfo.sourceServer) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Trading server mismatch. source=%s current=%s",
                fromRunInfo.sourceServer,
                currentServer
            )
        );

        return false;
    }

    return true;
}

/**
 * シンボル固有のpointとpipサイズを取得する。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromPoint point格納先。
 * @param fromPipSize pipサイズ格納先。
 * @return 取得できた場合true。
 */
bool getOutcomePriceUnits(
    const string fromSymbolName,
    double &fromPoint,
    double &fromPipSize
) {
    fromPoint = 0.0;
    fromPipSize = 0.0;

    if (!SymbolSelect(fromSymbolName, true)) {
        return false;
    }

    MarketContext marketContext(fromSymbolName, PERIOD_H1);
    fromPoint = RateUtil::getPoint(marketContext);
    double pipInPoints = RateUtil::getPipInPoints(marketContext);

    if (!MathIsValidNumber(fromPoint)
            || !MathIsValidNumber(pipInPoints)
            || fromPoint <= 0.0
            || pipInPoints <= 0.0) {
        fromPoint = 0.0;
        fromPipSize = 0.0;

        return false;
    }

    fromPipSize = fromPoint * pipInPoints;

    return MathIsValidNumber(fromPipSize) && fromPipSize > 0.0;
}

/**
 * 指定シンボル・時間足の系列同期状態を取得する。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromTimeFrame 対象時間足。
 * @return 同期済みの場合true。
 */
bool isOutcomeSeriesSynchronized(
    const string fromSymbolName,
    const ENUM_TIMEFRAMES fromTimeFrame
) {
    long synchronized = 0;

    if (!SeriesInfoInteger(
            fromSymbolName,
            fromTimeFrame,
            SERIES_SYNCHRONIZED,
            synchronized
        )) {
        return false;
    }

    return synchronized != 0;
}

/**
 * CopyRates失敗時の系列状態を診断文字列へまとめる。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromTimeFrame 対象時間足。
 * @param fromRequestedFrom 要求開始時刻。
 * @param fromRequestedTo 要求終了時刻。
 * @param fromCopiedCount CopyRates戻り値。
 * @param fromErrorCode CopyRates直後のエラー番号。
 * @return 系列状態の診断文字列。
 */
string buildOutcomeSeriesDiagnosticText(
    const string fromSymbolName,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const datetime fromRequestedFrom,
    const datetime fromRequestedTo,
    const int fromCopiedCount,
    const int fromErrorCode
) {
    long synchronized = 0;
    long barsCount = 0;
    long firstDate = 0;
    long terminalFirstDate = 0;
    long serverFirstDate = 0;
    SeriesInfoInteger(
        fromSymbolName,
        fromTimeFrame,
        SERIES_SYNCHRONIZED,
        synchronized
    );
    SeriesInfoInteger(
        fromSymbolName,
        fromTimeFrame,
        SERIES_BARS_COUNT,
        barsCount
    );
    SeriesInfoInteger(
        fromSymbolName,
        fromTimeFrame,
        SERIES_FIRSTDATE,
        firstDate
    );
    SeriesInfoInteger(
        fromSymbolName,
        fromTimeFrame,
        SERIES_TERMINAL_FIRSTDATE,
        terminalFirstDate
    );
    SeriesInfoInteger(
        fromSymbolName,
        fromTimeFrame,
        SERIES_SERVER_FIRSTDATE,
        serverFirstDate
    );
    long terminalMaxBars = TerminalInfoInteger(TERMINAL_MAXBARS);

    return StringFormat(
        "tf=%s requestedFrom=%s requestedTo=%s copied=%d error=%d synchronized=%I64d bars=%I64d first=%I64d terminalFirst=%I64d serverFirst=%I64d terminalMaxBars=%I64d",
        EnumToString(fromTimeFrame),
        TimeToString(fromRequestedFrom, TIME_DATE | TIME_SECONDS),
        TimeToString(fromRequestedTo, TIME_DATE | TIME_SECONDS),
        fromCopiedCount,
        fromErrorCode,
        synchronized,
        barsCount,
        firstDate,
        terminalFirstDate,
        serverFirstDate,
        terminalMaxBars
    );
}

/**
 * 履歴範囲一覧から指定シンボルを検索する。
 *
 * @param fromSymbolName 検索対象シンボル。
 * @param fromRanges 履歴範囲一覧。
 * @return 一致した配列位置。存在しない場合-1。
 */
int findOutcomeHistoryRangeIndex(
    const string fromSymbolName,
    OutcomeHistoryRange &fromRanges[]
) {
    int rangeCount = ArraySize(fromRanges);

    for (int i = 0; i < rangeCount; i++) {
        if (fromRanges[i].symbolName == fromSymbolName) {
            return i;
        }
    }

    return -1;
}

/**
 * エントリー候補をシンボル単位の履歴範囲へ集約する。
 *
 * @param fromCandidates エントリー候補一覧。
 * @param fromRanges 集約結果。
 * @param fromLogger ロガー。
 * @return 集約に成功した場合true。
 */
bool buildOutcomeHistoryRanges(
    EntryCandidate &fromCandidates[],
    OutcomeHistoryRange &fromRanges[],
    Logger &fromLogger
) {
    ArrayResize(fromRanges, 0);
    int candidateCount = ArraySize(fromCandidates);

    for (int i = 0; i < candidateCount; i++) {
        int rangeIndex = findOutcomeHistoryRangeIndex(
            fromCandidates[i].symbolName,
            fromRanges
        );

        if (rangeIndex < 0) {
            rangeIndex = ArraySize(fromRanges);

            if (ArrayResize(
                    fromRanges,
                    rangeIndex + 1,
                    32
                ) != rangeIndex + 1) {
                ArrayResize(fromRanges, 0);
                fromLogger.error(
                    __FUNCTION__,
                    "History range ArrayResize failed."
                );

                return false;
            }

            fromRanges[rangeIndex].reset();
            fromRanges[rangeIndex].symbolName =
                fromCandidates[i].symbolName;
            fromRanges[rangeIndex].earliestEntryTime =
                fromCandidates[i].currentBarTime;
            fromRanges[rangeIndex].latestEntryTime =
                fromCandidates[i].currentBarTime;

            continue;
        }

        if (fromCandidates[i].currentBarTime
                < fromRanges[rangeIndex].earliestEntryTime) {
            fromRanges[rangeIndex].earliestEntryTime =
                fromCandidates[i].currentBarTime;
        }

        if (fromCandidates[i].currentBarTime
                > fromRanges[rangeIndex].latestEntryTime) {
            fromRanges[rangeIndex].latestEntryTime =
                fromCandidates[i].currentBarTime;
        }
    }

    return true;
}

/**
 * 指定時間足の履歴を要求し、系列同期と対象範囲の利用可能状態を待つ。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromTimeFrame 対象時間足。
 * @param fromRequestedFrom 要求開始時刻。
 * @param fromRequestedTo 要求終了時刻。
 * @param fromLatestRequiredTime 最後に必要なバーの開始時刻。
 * @param fromDeadlineTick 待機終了tick。
 * @param fromRates 取得履歴。
 * @param fromCopiedCount 最後のCopyRates戻り値。
 * @param fromErrorCode 最後のCopyRatesエラー番号。
 * @return 対象範囲が利用可能になった場合true。
 */
bool copyOutcomeWarmUpRates(
    const string fromSymbolName,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const datetime fromRequestedFrom,
    const datetime fromRequestedTo,
    const datetime fromLatestRequiredTime,
    const ulong fromDeadlineTick,
    MqlRates &fromRates[],
    int &fromCopiedCount,
    int &fromErrorCode
) {
    ArrayResize(fromRates, 0);
    ArraySetAsSeries(fromRates, false);
    fromCopiedCount = -1;
    fromErrorCode = 0;
    int h1Seconds = PeriodSeconds(PERIOD_H1);

    while (!IsStopped()) {
        ResetLastError();
        fromCopiedCount = CopyRates(
            fromSymbolName,
            fromTimeFrame,
            fromRequestedFrom,
            fromRequestedTo,
            fromRates
        );
        fromErrorCode = GetLastError();

        if (fromCopiedCount > 0
                && ArraySize(fromRates) == fromCopiedCount
                && isOutcomeSeriesSynchronized(
                    fromSymbolName,
                    fromTimeFrame
                )) {
            datetime firstRateTime = fromRates[0].time;
            datetime lastRateTime =
                fromRates[fromCopiedCount - 1].time;
            bool isStartReady = firstRateTime == fromRequestedFrom;

            if (fromTimeFrame == PERIOD_M1) {
                isStartReady = firstRateTime >= fromRequestedFrom
                    && firstRateTime < fromRequestedFrom + h1Seconds;
            }

            if (isStartReady
                    && lastRateTime >= fromLatestRequiredTime) {
                return true;
            }
        }

        ulong currentTick = GetTickCount64();

        if (currentTick >= fromDeadlineTick) {
            break;
        }

        ulong remainingMilliseconds = fromDeadlineTick - currentTick;
        int waitMilliseconds = historyRetryIntervalMilliseconds;

        if ((ulong)waitMilliseconds > remainingMilliseconds) {
            waitMilliseconds = (int)remainingMilliseconds;
        }

        if (waitMilliseconds > 0) {
            Sleep(waitMilliseconds);
        }
    }

    return false;
}

/**
 * 最新候補から評価対象最終H1と終了時刻を取得する。
 *
 * @param fromH1Rates 最古候補から現在までのH1履歴。
 * @param fromLatestEntryTime 最新候補H1開始時刻。
 * @param fromLastH1Time 評価対象最終H1開始時刻格納先。
 * @param fromHorizonEnd 評価終了時刻格納先。
 * @return 評価対象H1が完成済みの場合true。
 */
bool findOutcomeWarmUpHorizon(
    const MqlRates &fromH1Rates[],
    const datetime fromLatestEntryTime,
    datetime &fromLastH1Time,
    datetime &fromHorizonEnd
) {
    fromLastH1Time = 0;
    fromHorizonEnd = 0;
    int h1RateCount = ArraySize(fromH1Rates);
    int latestEntryIndex = -1;

    for (int i = 0; i < h1RateCount; i++) {
        if (fromH1Rates[i].time == fromLatestEntryTime) {
            latestEntryIndex = i;
            break;
        }
    }

    if (latestEntryIndex < 0) {
        return false;
    }

    int lastH1Index = latestEntryIndex + horizonH1Bars - 1;

    if (lastH1Index < 0 || lastH1Index >= h1RateCount) {
        return false;
    }

    int h1Seconds = PeriodSeconds(PERIOD_H1);

    if (h1Seconds <= 0) {
        return false;
    }

    fromLastH1Time = fromH1Rates[lastH1Index].time;
    fromHorizonEnd = fromLastH1Time + h1Seconds;

    return getOutcomeCurrentTime() >= fromHorizonEnd;
}

/**
 * 1シンボルのH1・M1履歴を処理前に同期する。
 *
 * @param fromRange 対象履歴範囲。
 * @param fromLogger ロガー。
 * @return 対象範囲を利用可能にできた場合true。
 */
bool prepareOutcomeHistoryRange(
    OutcomeHistoryRange &fromRange,
    Logger &fromLogger
) {
    if (!SymbolSelect(fromRange.symbolName, true)) {
        fromLogger.error(
            __FUNCTION__,
            "History warm-up SymbolSelect failed. symbol="
                + fromRange.symbolName
        );

        return false;
    }

    datetime h1RequestedTo = getOutcomeCurrentTime();
    ulong startedTick = GetTickCount64();
    ulong timeoutMilliseconds =
        (ulong)historyWarmUpTimeoutSeconds * 1000;
    ulong deadlineTick = startedTick + timeoutMilliseconds;
    long terminalMaxBars = TerminalInfoInteger(TERMINAL_MAXBARS);
    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "History warm-up started. symbol=%s from=%s to=%s timeoutSeconds=%d terminalMaxBars=%I64d",
            fromRange.symbolName,
            TimeToString(
                fromRange.earliestEntryTime,
                TIME_DATE | TIME_SECONDS
            ),
            TimeToString(h1RequestedTo, TIME_DATE | TIME_SECONDS),
            historyWarmUpTimeoutSeconds,
            terminalMaxBars
        )
    );

    MqlRates h1Rates[];
    int h1CopiedCount = -1;
    int h1ErrorCode = 0;

    if (!copyOutcomeWarmUpRates(
            fromRange.symbolName,
            PERIOD_H1,
            fromRange.earliestEntryTime,
            h1RequestedTo,
            fromRange.latestEntryTime,
            deadlineTick,
            h1Rates,
            h1CopiedCount,
            h1ErrorCode
        )) {
        fromLogger.error(
            __FUNCTION__,
            "History warm-up failed. status=H1_WARMUP_TIMEOUT "
                + buildOutcomeSeriesDiagnosticText(
                    fromRange.symbolName,
                    PERIOD_H1,
                    fromRange.earliestEntryTime,
                    h1RequestedTo,
                    h1CopiedCount,
                    h1ErrorCode
                )
        );

        return false;
    }

    datetime lastRequiredH1Time = 0;
    datetime latestHorizonEnd = 0;

    if (!findOutcomeWarmUpHorizon(
            h1Rates,
            fromRange.latestEntryTime,
            lastRequiredH1Time,
            latestHorizonEnd
        )) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "History warm-up stopped. status=FUTURE_INCOMPLETE symbol=%s latestEntry=%s horizonH1=%d",
                fromRange.symbolName,
                TimeToString(
                    fromRange.latestEntryTime,
                    TIME_DATE | TIME_SECONDS
                ),
                horizonH1Bars
            )
        );

        return false;
    }

    long requiredM1CapacityUpperBound = (long)h1CopiedCount * 60;

    if (terminalMaxBars > 0
            && terminalMaxBars < requiredM1CapacityUpperBound) {
        long capacityUnit = 100000;
        long recommendedMaxBars =
            ((requiredM1CapacityUpperBound + capacityUnit - 1)
                / capacityUnit) * capacityUnit;
        fromLogger.warn(
            __FUNCTION__,
            StringFormat(
                "History warm-up warning. status=TERMINAL_MAX_BARS_MAY_BE_LOW symbol=%s terminalMaxBars=%I64d requiredUpperBound=%I64d recommendedMaxBars=%I64d. CopyRates will verify actual availability. Change Tools > Options > Charts > Max bars in chart and restart MT5 if warm-up fails.",
                fromRange.symbolName,
                terminalMaxBars,
                requiredM1CapacityUpperBound,
                recommendedMaxBars
            )
        );
    }

    MqlRates m1Rates[];
    int m1CopiedCount = -1;
    int m1ErrorCode = 0;
    datetime m1RequestedTo = latestHorizonEnd - 1;

    if (!copyOutcomeWarmUpRates(
            fromRange.symbolName,
            PERIOD_M1,
            fromRange.earliestEntryTime,
            m1RequestedTo,
            lastRequiredH1Time,
            deadlineTick,
            m1Rates,
            m1CopiedCount,
            m1ErrorCode
        )) {
        fromLogger.error(
            __FUNCTION__,
            "History warm-up failed. status=M1_WARMUP_TIMEOUT "
                + buildOutcomeSeriesDiagnosticText(
                    fromRange.symbolName,
                    PERIOD_M1,
                    fromRange.earliestEntryTime,
                    m1RequestedTo,
                    m1CopiedCount,
                    m1ErrorCode
                )
        );

        return false;
    }

    long elapsedMilliseconds =
        (long)(GetTickCount64() - startedTick);
    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "History warm-up completed. symbol=%s h1Copied=%d m1Copied=%d m1To=%s elapsedMs=%I64d",
            fromRange.symbolName,
            h1CopiedCount,
            m1CopiedCount,
            TimeToString(m1RequestedTo, TIME_DATE | TIME_SECONDS),
            elapsedMilliseconds
        )
    );
    ArrayResize(h1Rates, 0);
    ArrayResize(m1Rates, 0);

    return true;
}

/**
 * 全対象シンボルの履歴を処理前に同期する。
 *
 * @param fromCandidates エントリー候補一覧。
 * @param fromLogger ロガー。
 * @return 全対象範囲を利用可能にできた場合true。
 */
bool prepareOutcomeHistory(
    EntryCandidate &fromCandidates[],
    Logger &fromLogger
) {
    OutcomeHistoryRange ranges[];

    if (!buildOutcomeHistoryRanges(
            fromCandidates,
            ranges,
            fromLogger
        )) {
        return false;
    }

    int rangeCount = ArraySize(ranges);

    for (int i = 0; i < rangeCount; i++) {
        if (!prepareOutcomeHistoryRange(ranges[i], fromLogger)) {
            return false;
        }
    }

    return true;
}

/**
 * エントリーH1から指定本数後の評価終了時刻を取得する。
 *
 * CopyRatesで取得した実在H1を評価本数として数える。
 * 評価終了時刻はhorizon本目のH1開始時刻から1時間後とする。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromCurrentBarTime エントリーが属するH1バー開始時刻。
 * @param fromHorizonH1Bars 評価対象H1本数。
 * @param fromH1Rates エントリーH1からの履歴格納先。
 * @param fromHorizonEnd 評価終了時刻格納先。
 * @param fromDataStatus 取得不能理由格納先。
 * @param fromCalculationNote 取得不能の診断情報格納先。
 * @return 評価期間を確定できた場合true。
 */
bool copyOutcomeH1Horizon(
    const string fromSymbolName,
    const datetime fromCurrentBarTime,
    const int fromHorizonH1Bars,
    MqlRates &fromH1Rates[],
    datetime &fromHorizonEnd,
    string &fromDataStatus,
    string &fromCalculationNote
) {
    fromHorizonEnd = 0;
    fromDataStatus = "HISTORY_NOT_READY";
    fromCalculationNote = "";
    ArrayResize(fromH1Rates, 0);
    ArraySetAsSeries(fromH1Rates, false);
    int copiedCount = -1;
    int copyErrorCode = 0;
    datetime requestedTo = 0;

    for (int i = 0; i < historyRetryCount; i++) {
        if (IsStopped()) {
            fromDataStatus = "STOPPED";

            return false;
        }

        datetime currentTime = getOutcomeCurrentTime();
        requestedTo = currentTime;

        if (currentTime <= fromCurrentBarTime) {
            fromDataStatus = "FUTURE_INCOMPLETE";

            return false;
        }

        ResetLastError();
        copiedCount = CopyRates(
            fromSymbolName,
            PERIOD_H1,
            fromCurrentBarTime,
            currentTime,
            fromH1Rates
        );
        copyErrorCode = GetLastError();

        if (copiedCount >= fromHorizonH1Bars
                && ArraySize(fromH1Rates) >= fromHorizonH1Bars
                && fromH1Rates[0].time == fromCurrentBarTime) {
            bool isOrdered = true;

            for (int j = 1; j < fromHorizonH1Bars; j++) {
                if (fromH1Rates[j].time <= fromH1Rates[j - 1].time) {
                    isOrdered = false;
                    break;
                }
            }

            if (!isOrdered) {
                fromDataStatus = "INVALID_H1_TIME_ORDER";

                return false;
            }

            int h1Seconds = PeriodSeconds(PERIOD_H1);
            fromHorizonEnd =
                fromH1Rates[fromHorizonH1Bars - 1].time + h1Seconds;

            if (h1Seconds <= 0 || currentTime < fromHorizonEnd) {
                fromHorizonEnd = 0;
                fromDataStatus = "FUTURE_INCOMPLETE";

                return false;
            }

            fromDataStatus = "READY";

            return true;
        }

        if (i + 1 < historyRetryCount
                && historyRetryIntervalMilliseconds > 0) {
            Sleep(historyRetryIntervalMilliseconds);
        }
    }

    if (isOutcomeSeriesSynchronized(fromSymbolName, PERIOD_H1)
            && copiedCount >= 0) {
        fromDataStatus = "HISTORY_PARTIAL";

        if (copiedCount > 0
                && ArraySize(fromH1Rates) == copiedCount
                && fromH1Rates[0].time == fromCurrentBarTime) {
            fromDataStatus = "FUTURE_INCOMPLETE";
        }
    }

    fromCalculationNote = buildOutcomeSeriesDiagnosticText(
        fromSymbolName,
        PERIOD_H1,
        fromCurrentBarTime,
        requestedTo,
        copiedCount,
        copyErrorCode
    );

    return false;
}

/**
 * エントリー時刻から評価終了までの完成済みM1を取得する。
 *
 * @param fromSymbolName 対象シンボル。
 * @param fromEntryTime エントリー時刻。
 * @param fromHorizonEnd 評価終了時刻。
 * @param fromH1Rates エントリーH1からの履歴。
 * @param fromHorizonH1Bars 評価対象H1本数。
 * @param fromPoint 対象シンボルの1point価格幅。
 * @param fromRates M1格納先。
 * @param fromDataStatus 取得不能理由格納先。
 * @param fromCalculationNote 取得不能の診断情報格納先。
 * @return 最終H1までのM1を取得できた場合true。
 */
bool copyOutcomeM1Rates(
    const string fromSymbolName,
    const datetime fromEntryTime,
    const datetime fromHorizonEnd,
    const MqlRates &fromH1Rates[],
    const int fromHorizonH1Bars,
    const double fromPoint,
    MqlRates &fromRates[],
    string &fromDataStatus,
    string &fromCalculationNote
) {
    ArrayResize(fromRates, 0);
    ArraySetAsSeries(fromRates, false);
    fromDataStatus = "HISTORY_NOT_READY";
    fromCalculationNote = "";
    int copiedCount = -1;
    int copyErrorCode = 0;
    datetime lastIncludedTime = fromHorizonEnd - 1;
    ZigZagElliotEntryHistoryValidationResult validationResult;
    validationResult.reset();

    for (int i = 0; i < historyRetryCount; i++) {
        if (IsStopped()) {
            fromDataStatus = "STOPPED";

            return false;
        }

        ResetLastError();
        copiedCount = CopyRates(
            fromSymbolName,
            PERIOD_M1,
            fromEntryTime,
            lastIncludedTime,
            fromRates
        );
        copyErrorCode = GetLastError();

        if (copiedCount > 0
                && ArraySize(fromRates) == copiedCount) {
            if (ZigZagElliotEntryHistoryValidator::validate(
                    fromH1Rates,
                    fromHorizonH1Bars,
                    fromRates,
                    fromPoint,
                    validationResult
                )) {
                fromDataStatus = "READY";

                return true;
            }

        }

        if (i + 1 < historyRetryCount
                && historyRetryIntervalMilliseconds > 0) {
            Sleep(historyRetryIntervalMilliseconds);
        }
    }

    if (validationResult.dataStatus != "NOT_VALIDATED") {
        fromDataStatus = validationResult.dataStatus;
        fromCalculationNote = validationResult.calculationNote;
    } else if (isOutcomeSeriesSynchronized(fromSymbolName, PERIOD_M1)
            && copiedCount >= 0) {
        fromDataStatus = "HISTORY_PARTIAL";
    }

    string diagnosticText = buildOutcomeSeriesDiagnosticText(
        fromSymbolName,
        PERIOD_M1,
        fromEntryTime,
        lastIncludedTime,
        copiedCount,
        copyErrorCode
    );

    if (fromCalculationNote != "") {
        fromCalculationNote += ";";
    }

    fromCalculationNote += diagnosticText;

    return false;
}

/**
 * エントリー候補からOutcome共通項目を初期化する。
 *
 * @param fromCandidate エントリー候補。
 * @param fromOutcomeRunId 後処理Run ID。
 * @param fromSourceServer 参照元取引サーバー。
 * @param fromEntity 初期化先。
 */
void initializeOutcomeEntity(
    EntryCandidate &fromCandidate,
    const long fromOutcomeRunId,
    const string fromSourceServer,
    ZigZagElliotEntryOutcomeEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.outcomeRunId = fromOutcomeRunId;
    fromEntity.sourceAlertId = fromCandidate.alertId;
    fromEntity.sourceRunId = fromCandidate.runId;
    fromEntity.marketSignalKey = fromCandidate.marketSignalKey;
    fromEntity.sourceServer = fromSourceServer;
    fromEntity.symbolName = fromCandidate.symbolName;
    fromEntity.side = fromCandidate.side;
    fromEntity.currentBarTime = fromCandidate.currentBarTime;
    fromEntity.entryTime = fromCandidate.entryTime;
    fromEntity.entryPrice = fromCandidate.entryPrice;
    fromEntity.spreadPips = fromCandidate.spreadPips;
    fromEntity.stopLoss = fromCandidate.stopLoss;
    fromEntity.sourceRiskPips = fromCandidate.riskPips;
    fromEntity.horizonH1Bars = horizonH1Bars;
    fromEntity.evaluationStartTime = fromCandidate.entryTime;
    fromEntity.evaluationEndTime = 0;
    fromEntity.isCalculated = 0;
    fromEntity.exitReason = "NOT_EVALUATED";
    fromEntity.dataStatus = "NOT_EVALUATED";
    fromEntity.calculationNote = "";
    fromEntity.priceModel = outcomePriceModel;
    fromEntity.evaluationVersion = outcomeEvaluationVersion;
    fromEntity.createdAt = getOutcomeCurrentTime();
}

/**
 * H1保有本数を実在するH1バーのshift差から計算する。
 *
 * @param fromCandidate エントリー候補。
 * @param fromResult M1計算結果。
 * @param fromBarsHeldH1 H1保有本数格納先。
 * @return 計算できた場合true。
 */
bool calculateOutcomeBarsHeldH1(
    EntryCandidate &fromCandidate,
    ZigZagElliotEntryOutcomeResult &fromResult,
    int &fromBarsHeldH1
) {
    fromBarsHeldH1 = 0;

    if (fromResult.exitReason == "HORIZON") {
        fromBarsHeldH1 = horizonH1Bars;

        return true;
    }

    int entryShift = iBarShift(
        fromCandidate.symbolName,
        PERIOD_H1,
        fromCandidate.currentBarTime,
        true
    );
    int exitShift = iBarShift(
        fromCandidate.symbolName,
        PERIOD_H1,
        fromResult.exitTime,
        false
    );

    if (entryShift < 0
            || exitShift < 0
            || entryShift < exitShift) {
        return false;
    }

    fromBarsHeldH1 = entryShift - exitShift + 1;

    return fromBarsHeldH1 > 0
        && fromBarsHeldH1 <= horizonH1Bars;
}

/**
 * 計算結果の補足状態を連結する。
 *
 * @param fromResult M1計算結果。
 * @return 補足状態。補足がない場合は空文字。
 */
string buildOutcomeCalculationNote(
    ZigZagElliotEntryOutcomeResult &fromResult
) {
    string note = "";

    if (fromResult.exitBarOrderUnknown) {
        note = "EXIT_BAR_ORDER_UNKNOWN";
    }

    if (fromResult.zeroSpreadBarCount > 0) {
        if (note != "") {
            note += ";";
        }

        note += StringFormat(
            "ZERO_SPREAD_BARS=%d",
            fromResult.zeroSpreadBarCount
        );
    }

    return note;
}

/**
 * 1件のエントリー候補をM1で後処理する。
 *
 * 計算不能は異常終了にせず、isCalculated=0とdataStatusを設定する。
 *
 * @param fromCandidate エントリー候補。
 * @param fromOutcomeRunId 後処理Run ID。
 * @param fromSourceServer 参照元取引サーバー。
 * @param fromEntity 保存用Outcome。
 */
void evaluateOutcomeCandidate(
    EntryCandidate &fromCandidate,
    const long fromOutcomeRunId,
    const string fromSourceServer,
    ZigZagElliotEntryOutcomeEntity &fromEntity
) {
    initializeOutcomeEntity(
        fromCandidate,
        fromOutcomeRunId,
        fromSourceServer,
        fromEntity
    );

    double point = 0.0;
    double pipSize = 0.0;

    if (!getOutcomePriceUnits(
            fromCandidate.symbolName,
            point,
            pipSize
        )) {
        fromEntity.dataStatus = "SYMBOL_NOT_READY";

        return;
    }

    fromEntity.calculatedRiskPips = MathAbs(
        fromCandidate.entryPrice - fromCandidate.stopLoss
    ) / pipSize;

    if (!MathIsValidNumber(fromEntity.calculatedRiskPips)
            || fromEntity.calculatedRiskPips <= 0.0) {
        fromEntity.calculatedRiskPips = 0.0;
        fromEntity.dataStatus = "INVALID_RISK";

        return;
    }

    double riskDifference = MathAbs(
        fromEntity.calculatedRiskPips - fromCandidate.riskPips
    );

    if (riskDifference > riskTolerancePips) {
        fromEntity.dataStatus = "RISK_MISMATCH";
        fromEntity.calculationNote = StringFormat(
            "source=%.8f calculated=%.8f difference=%.8f",
            fromCandidate.riskPips,
            fromEntity.calculatedRiskPips,
            riskDifference
        );

        return;
    }

    if (((long)fromCandidate.entryTime % 60) != 0) {
        fromEntity.dataStatus = "ENTRY_MINUTE_AMBIGUOUS";

        return;
    }

    if (fromCandidate.entryTime != fromCandidate.currentBarTime) {
        fromEntity.dataStatus = "ENTRY_NOT_H1_OPEN";

        return;
    }

    datetime horizonEnd = 0;
    string historyStatus = "";
    string historyNote = "";
    MqlRates h1Rates[];

    if (!copyOutcomeH1Horizon(
            fromCandidate.symbolName,
            fromCandidate.currentBarTime,
            horizonH1Bars,
            h1Rates,
            horizonEnd,
            historyStatus,
            historyNote
        )) {
        fromEntity.dataStatus = historyStatus;
        fromEntity.calculationNote = historyNote;

        return;
    }

    fromEntity.evaluationEndTime = horizonEnd;
    MqlRates m1Rates[];

    if (!copyOutcomeM1Rates(
            fromCandidate.symbolName,
            fromCandidate.entryTime,
            horizonEnd,
            h1Rates,
            horizonH1Bars,
            point,
            m1Rates,
            historyStatus,
            historyNote
        )) {
        fromEntity.copiedM1Bars = ArraySize(m1Rates);
        fromEntity.dataStatus = historyStatus;
        fromEntity.calculationNote = historyNote;

        return;
    }

    fromEntity.copiedM1Bars = ArraySize(m1Rates);
    ZigZagElliotEntryOutcomeResult result;

    if (!ZigZagElliotEntryOutcomeCalculator::calculate(
            fromCandidate.side,
            fromCandidate.entryPrice,
            fromCandidate.stopLoss,
            pipSize,
            point,
            fromCandidate.entryTime,
            horizonEnd,
            m1Rates,
            result
        )) {
        fromEntity.dataStatus = result.dataStatus;

        return;
    }

    int barsHeldH1 = 0;

    if (!calculateOutcomeBarsHeldH1(
            fromCandidate,
            result,
            barsHeldH1
        )) {
        fromEntity.dataStatus = "H1_BAR_COUNT_FAILED";

        return;
    }

    fromEntity.isCalculated = 1;
    fromEntity.mfePips = result.mfePips;
    fromEntity.mfeR = result.mfeR;
    fromEntity.maePips = result.maePips;
    fromEntity.maeR = result.maeR;
    fromEntity.profitPips = result.profitPips;
    fromEntity.profitR = result.profitR;
    fromEntity.exitTime = result.exitTime;
    fromEntity.exitPrice = result.exitPrice;
    fromEntity.exitReason = result.exitReason;
    fromEntity.barsHeldM1 = result.barsHeldM1;
    fromEntity.barsHeldH1 = barsHeldH1;
    fromEntity.dataStatus = result.dataStatus;
    fromEntity.calculationNote = buildOutcomeCalculationNote(result);

    if (result.zeroSpreadBarCount > 0) {
        fromEntity.isZeroSpread = 1;
    }

    if (result.exitBarOrderUnknown) {
        fromEntity.isOrderUnknown = 1;
    }
}

/**
 * 参照元Runから後処理Run情報を組み立てる。
 *
 * @param fromSourceRunInfo 参照元Run。
 * @param fromEntity 組み立て先。
 */
void buildOutcomeRunEntity(
    SourceRunInfo &fromSourceRunInfo,
    ZigZagElliotEntryOutcomeRunEntity &fromEntity
) {
    fromEntity.reset();
    fromEntity.runKey = StringFormat(
        "%s|%I64d|%s|%s|%s|H1=%d",
        sourceDatabaseFileName,
        fromSourceRunInfo.runId,
        fromSourceRunInfo.runUid,
        outcomePriceModel,
        outcomeEvaluationVersion,
        horizonH1Bars
    );
    fromEntity.sourceDatabaseFileName = sourceDatabaseFileName;
    fromEntity.sourceRunId = fromSourceRunInfo.runId;
    fromEntity.sourceRunUid = fromSourceRunInfo.runUid;
    fromEntity.sourceMode = fromSourceRunInfo.sourceMode;
    fromEntity.sourceServer = fromSourceRunInfo.sourceServer;
    fromEntity.sourceLogin = fromSourceRunInfo.sourceLogin;
    fromEntity.sourceProgramName = fromSourceRunInfo.programName;
    fromEntity.sourceProgramVersion = fromSourceRunInfo.programVersion;
    fromEntity.sourceStrategy = fromSourceRunInfo.strategy;
    fromEntity.sourceStrategyVersion = fromSourceRunInfo.strategyVersion;
    fromEntity.sourceAnalysisVersion = fromSourceRunInfo.analysisVersion;
    fromEntity.sourceAnalysisInputHash =
        fromSourceRunInfo.analysisInputHash;
    fromEntity.sourceInputHash = fromSourceRunInfo.inputHash;
    fromEntity.sourceTesterFrom = fromSourceRunInfo.testerFrom;
    fromEntity.sourceTesterTo = fromSourceRunInfo.testerTo;
    fromEntity.sourceTesterModel = fromSourceRunInfo.testerModel;
    fromEntity.horizonH1Bars = horizonH1Bars;
    fromEntity.priceModel = outcomePriceModel;
    fromEntity.evaluationVersion = outcomeEvaluationVersion;
    fromEntity.startedAt = getOutcomeCurrentTime();
    fromEntity.createdAt = fromEntity.startedAt;
}

/**
 * M1後処理Scriptを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateOutcomeInputs(logger)) {
        return;
    }

    SqliteDatabase sourceDatabase(
        sourceDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!sourceDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Alert DBを読み取り専用で開けません。");

        return;
    }

    ZigZagElliotEntryCandidateQueryService queryService(
        sourceDatabase.getHandle()
    );

    if (sourceRunId == 0) {
        printRecentOutcomeSourceRuns(queryService, logger);

        return;
    }

    SourceRunInfo sourceRunInfo;
    bool isRunFound = false;

    if (!queryService.findRun(
            sourceRunId,
            sourceRunInfo,
            isRunFound
        )) {
        logger.error(__FUNCTION__, "Alert Runの読取に失敗しました。");

        return;
    }

    if (!isRunFound) {
        logger.error(
            __FUNCTION__,
            StringFormat("Alert Runがありません。runId=%I64d", sourceRunId)
        );

        return;
    }

    if (!validateOutcomeSourceRun(sourceRunInfo, logger)) {
        return;
    }

    EntryCandidate candidates[];

    if (!queryService.findEntries(sourceRunId, candidates)) {
        logger.error(__FUNCTION__, "H1 ENTRYの読取に失敗しました。");

        return;
    }

    int totalCount = ArraySize(candidates);
    logger.info(
        __FUNCTION__,
        StringFormat(
            "Outcome build started. sourceRunId=%I64d entries=%d horizonH1=%d program=%s strategy=%s analysis=%s",
            sourceRunId,
            totalCount,
            horizonH1Bars,
            sourceRunInfo.programVersion,
            sourceRunInfo.strategyVersion,
            sourceRunInfo.analysisVersion
        )
    );

    if (!prepareOutcomeHistory(candidates, logger)) {
        logger.error(
            __FUNCTION__,
            "Outcome build stopped because history warm-up failed."
        );

        return;
    }

    SqliteDatabase outcomeDatabase(
        outcomeDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!outcomeDatabase.open()) {
        logger.error(__FUNCTION__, "Outcome DBを開けません。");

        return;
    }

    ZigZagElliotEntryOutcomeDao outcomeDao(outcomeDatabase.getHandle());

    if (!outcomeDao.createTables()) {
        logger.error(__FUNCTION__, "Outcome DBの初期化に失敗しました。");

        return;
    }

    ZigZagElliotEntryOutcomeRunEntity outcomeRunEntity;
    buildOutcomeRunEntity(sourceRunInfo, outcomeRunEntity);
    long outcomeRunId = 0;

    if (!outcomeDao.findOrCreateRun(
            outcomeRunEntity,
            outcomeRunId
        )) {
        logger.error(__FUNCTION__, "Outcome Runの準備に失敗しました。");

        return;
    }

    long successCount = 0;
    long failureCount = 0;
    bool isFatalError = false;

    for (int i = 0; i < totalCount; i++) {
        if (IsStopped()) {
            isFatalError = true;
            break;
        }

        ZigZagElliotEntryOutcomeEntity outcomeEntity;
        evaluateOutcomeCandidate(
            candidates[i],
            outcomeRunId,
            sourceRunInfo.sourceServer,
            outcomeEntity
        );

        if (!outcomeDao.save(outcomeEntity)) {
            logger.error(
                __FUNCTION__,
                StringFormat(
                    "Outcome save failed. alertId=%I64d",
                    candidates[i].alertId
                )
            );
            isFatalError = true;
            break;
        }

        if (outcomeEntity.isCalculated == 1) {
            successCount++;
        } else {
            failureCount++;
            logger.warn(
                __FUNCTION__,
                StringFormat(
                    "Outcome skipped. alertId=%I64d symbol=%s time=%s status=%s note=%s",
                    candidates[i].alertId,
                    candidates[i].symbolName,
                    TimeToString(
                        candidates[i].entryTime,
                        TIME_DATE | TIME_SECONDS
                    ),
                    outcomeEntity.dataStatus,
                    outcomeEntity.calculationNote
                )
            );
        }

        int processedCount = i + 1;

        if (processedCount % progressInterval == 0
                || processedCount == totalCount) {
            logger.info(
                __FUNCTION__,
                StringFormat(
                    "Outcome progress. processed=%d/%d success=%I64d failure=%I64d",
                    processedCount,
                    totalCount,
                    successCount,
                    failureCount
                )
            );
        }
    }

    string completionStatus = "COMPLETED";

    if (isFatalError) {
        completionStatus = "FAILED";
        failureCount = (long)totalCount - successCount;
    }

    if (!outcomeDao.completeRun(
            outcomeRunId,
            completionStatus,
            totalCount,
            successCount,
            failureCount
        )) {
        logger.error(__FUNCTION__, "Outcome Runの完了更新に失敗しました。");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Outcome build finished. status=%s outcomeRunId=%I64d total=%d success=%I64d failure=%I64d output=%s",
            completionStatus,
            outcomeRunId,
            totalCount,
            successCount,
            failureCount,
            outcomeDatabaseFileName
        )
    );
}
