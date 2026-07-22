//+------------------------------------------------------------------+
//|                                       CurrencyStrengthElliot.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "CurrencyStrengthHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyPersistenceService.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthEntryCandidateList.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthList.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>
#include <Mstng\Strength\CurrencyStrengthSortType.mqh>

/**
 * 通貨強弱集計の実行結果。
 */
enum CurrencyStrengthExecutionStatus {
    currencyStrengthExecutionSucceeded = 0,
    currencyStrengthExecutionNotReady = 1,
    currencyStrengthExecutionFailed = 2
};

input int refreshSeconds = 60;
input int panelXDistance = 12;
input int panelYDistance = 12;
input bool showEntryCandidates = true;
input int entryCandidateMaxCount = 10;
input int entryCandidateMinRankDifference = 2;
input CurrencyStrengthSortType sortType = CURRENCY_STRENGTH_SORT_TOTAL;
input bool databaseEnabled = true;
input string databaseFileName = "mstng-currency-strength.sqlite";
input bool databaseSplitByYear = true;
input bool databaseUseCommonFolder = true;
input bool databaseSaveEveryRefresh = false;
input bool databaseSavePartialRuns = false;
input datetime databaseSaveStartTime = D'2026.07.16 00:00';
input int databaseRetentionDays = 30;

/** テスター診断ログを約1日ごとに出力するM5足数。 */
const int testerDiagnosticLogIntervalBars = 288;
/** 通貨ランキングパネル左端から候補一覧左端までの距離。 */
const int entryCandidatePanelXOffset = 1012;

double gHiddenBuffer[];

Logger gLogger;
DrawCurrencyStrengthEntryCandidateList *gDrawCurrencyStrengthEntryCandidateList = NULL;
DrawCurrencyStrengthList *gDrawCurrencyStrengthList;
OscillatorHandleManager *gOscillatorHandleManager;
CurrencyStrengthCalculator *gCurrencyStrengthCalculator;
CurrencyStrengthEntryCandidateList *gCurrencyStrengthEntryCandidateList = NULL;
CurrencyStrengthYearlyPersistenceService *gCurrencyStrengthPersistenceService;
datetime gFirstTargetM5BarTime;
datetime gLastLiveAttemptM5BarTime;
datetime gLastTesterAttemptM5BarTime;
datetime gLastProcessedM5BarTime;
datetime gPendingTesterM5BarTime;
datetime gTesterWarmUpPreparedAt;
datetime gLastSavedM5BarTime;
datetime gLastDatabaseCleanupTime;
int gTesterWarmUpAttemptCount;
int gTesterRetryWaitCount;
int gTesterPersistedSnapshotCount;
string gLastRetryPreparationFailureReason;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);

    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthElliot does not support optimization");

        return INIT_FAILED;
    }

    if (isTester && _Period != PERIOD_M5) {
        Print("CurrencyStrengthElliot requires M5 in Strategy Tester");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (refreshSeconds < 1
            || databaseRetentionDays < 0
            || (showEntryCandidates
                && (entryCandidateMaxCount < 1
                    || entryCandidateMaxCount > 28
                    || entryCandidateMinRankDifference < 1
                    || entryCandidateMinRankDifference > 7))) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (databaseEnabled && databaseFileName == "") {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (isTester && databaseEnabled && !databaseUseCommonFolder) {
        Print("CurrencyStrengthElliot requires Common database folder in Strategy Tester");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!SetIndexBuffer(0, gHiddenBuffer, INDICATOR_DATA)) {
        return INIT_FAILED;
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "Elliot Currency Strength");

    MarketContext context(_Symbol, PERIOD_M15);
    gLogger.setLevel(LOG_INFO);
    gLogger.setMarketContext(context);

    gDrawCurrencyStrengthList = new DrawCurrencyStrengthList(
        0,
        panelXDistance,
        panelYDistance,
        sortType
    );
    gOscillatorHandleManager = new OscillatorHandleManager(PERIOD_M15);
    gCurrencyStrengthCalculator = new CurrencyStrengthCalculator();

    if (showEntryCandidates) {
        gDrawCurrencyStrengthEntryCandidateList =
            new DrawCurrencyStrengthEntryCandidateList(
                0,
                panelXDistance + entryCandidatePanelXOffset,
                panelYDistance,
                entryCandidateMaxCount
            );
        gCurrencyStrengthEntryCandidateList =
            new CurrencyStrengthEntryCandidateList();
    }

    if (gDrawCurrencyStrengthList == NULL
            || gOscillatorHandleManager == NULL
            || gCurrencyStrengthCalculator == NULL
            || (showEntryCandidates
                && (gDrawCurrencyStrengthEntryCandidateList == NULL
                    || gCurrencyStrengthEntryCandidateList == NULL))) {
        releaseResources();

        return INIT_FAILED;
    }

    gFirstTargetM5BarTime = 0;
    gLastLiveAttemptM5BarTime = 0;
    gLastTesterAttemptM5BarTime = 0;
    gLastProcessedM5BarTime = 0;
    gPendingTesterM5BarTime = 0;
    gTesterWarmUpPreparedAt = 0;
    gLastSavedM5BarTime = 0;
    gLastDatabaseCleanupTime = 0;
    gTesterWarmUpAttemptCount = 0;
    gTesterRetryWaitCount = 0;
    gTesterPersistedSnapshotCount = 0;
    gLastRetryPreparationFailureReason = "";

    if (isTester) {
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "tester database save window initialized. from=%s",
                getOptionalTimeText(databaseSaveStartTime, "TEST_START")
            )
        );
    }

    if (databaseEnabled && !initializeDatabase()) {
        gLogger.error(__FUNCTION__, "currency strength database initialization failed");
        releaseDatabaseResources();

        if (isTester) {
            releaseResources();

            return INIT_FAILED;
        }
    }

    if (!isTester) {
        if (!EventSetTimer(refreshSeconds)) {
            gLogger.error(__FUNCTION__, "EventSetTimer failed");
            releaseResources();

            return INIT_FAILED;
        }

        processLiveSnapshot(true);
    }

    return INIT_SUCCEEDED;
}

/**
 * タイマーと保持リソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    EventKillTimer();

    if (MQLInfoInteger(MQL_TESTER)) {
        logTesterSnapshotSummary();
    }

    releaseResources();
}

/**
 * タイマーごとに通貨強弱を更新する。
 */
void OnTimer() {
    if (MQLInfoInteger(MQL_TESTER)) {
        return;
    }

    processLiveSnapshot(true);
}

/**
 * テスターでは新しいM5足ごとに通貨強弱を集計する。
 *
 * @return 計算済み本数。
 */
int OnCalculate(
    const int ratesTotal,
    const int previousCalculated,
    const datetime &time[],
    const double &open[],
    const double &high[],
    const double &low[],
    const double &close[],
    const long &tickVolume[],
    const long &volume[],
    const int &spread[]
) {
    if (!MQLInfoInteger(MQL_TESTER)) {
        processLiveSnapshot(false);

        return ratesTotal;
    }

    processTesterSnapshots();

    return ratesTotal;
}

/**
 * LIVEの現在M5足を集計する。
 *
 * 新規M5足は最初のティックで実行する。
 * タイマーからの呼び出しでは、同じM5足でも定期更新と失敗再試行を行う。
 *
 * @param fromForceRefresh 同じM5足でも定期更新する場合true。
 */
void processLiveSnapshot(const bool fromForceRefresh) {
    if (MQLInfoInteger(MQL_TESTER)) {
        return;
    }

    datetime currentM5BarTime = iTime(_Symbol, PERIOD_M5, 0);

    if (currentM5BarTime <= 0) {
        return;
    }

    if (!fromForceRefresh
            && currentM5BarTime == gLastLiveAttemptM5BarTime) {
        return;
    }

    gLastLiveAttemptM5BarTime = currentM5BarTime;
    execute(currentM5BarTime);
}

/**
 * テスターの未処理M5スナップショットを古い順に保存する。
 */
void processTesterSnapshots() {
    datetime currentM5BarTime = iTime(_Symbol, PERIOD_M5, 0);

    if (currentM5BarTime <= 0) {
        return;
    }

    if (currentM5BarTime == gLastTesterAttemptM5BarTime) {
        return;
    }

    gLastTesterAttemptM5BarTime = currentM5BarTime;

    if (databaseEnabled
            && databaseSaveStartTime > 0
            && currentM5BarTime < databaseSaveStartTime) {
        prepareTesterWarmUp(currentM5BarTime);

        return;
    }

    if (gFirstTargetM5BarTime <= 0) {
        gFirstTargetM5BarTime = currentM5BarTime;
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "tester snapshot processing started. firstM5=%s warmUpPreparedAt=%s",
                TimeToString(
                    gFirstTargetM5BarTime,
                    TIME_DATE | TIME_MINUTES
                ),
                getOptionalTimeText(gTesterWarmUpPreparedAt, "NONE")
            )
        );
    }

    int startShift = -1;

    if (gLastProcessedM5BarTime > 0) {
        int lastProcessedShift = iBarShift(
            _Symbol,
            PERIOD_M5,
            gLastProcessedM5BarTime,
            true
        );

        if (lastProcessedShift > 0) {
            startShift = lastProcessedShift - 1;
        }
    } else {
        startShift = iBarShift(
            _Symbol,
            PERIOD_M5,
            gFirstTargetM5BarTime,
            true
        );
    }

    for (int i = startShift; i >= 0; i--) {
        datetime targetM5BarTime = iTime(_Symbol, PERIOD_M5, i);

        if (targetM5BarTime <= 0) {
            break;
        }

        CurrencyStrengthExecutionStatus executionStatus = execute(
            targetM5BarTime
        );

        if (executionStatus != currencyStrengthExecutionSucceeded) {
            gPendingTesterM5BarTime = targetM5BarTime;

            if (executionStatus == currencyStrengthExecutionNotReady
                    && i > 0) {
                logTesterSnapshotRetryWait(targetM5BarTime);
            }

            break;
        }

        if (gPendingTesterM5BarTime == targetM5BarTime) {
            gPendingTesterM5BarTime = 0;
        }

        gLastProcessedM5BarTime = targetM5BarTime;
    }
}

/**
 * DB保存開始前に系列とストキャスハンドルを一度準備する。
 *
 * @param fromM5BarTime ウォームアップ中のM5足開始時刻。
 */
void prepareTesterWarmUp(const datetime fromM5BarTime) {
    if (gTesterWarmUpPreparedAt > 0
            || gCurrencyStrengthCalculator == NULL
            || gOscillatorHandleManager == NULL) {
        return;
    }

    gTesterWarmUpAttemptCount++;

    if (!gCurrencyStrengthCalculator.calculateAt(
        gOscillatorHandleManager,
        _Symbol,
        fromM5BarTime
    )) {
        if (gTesterWarmUpAttemptCount == 1
                || gTesterWarmUpAttemptCount
                    % testerDiagnosticLogIntervalBars == 0) {
            gLogger.info(
                __FUNCTION__,
                StringFormat(
                    "tester warm-up is waiting. m5=%s attempt=%d reason=%s",
                    TimeToString(fromM5BarTime, TIME_DATE | TIME_MINUTES),
                    gTesterWarmUpAttemptCount,
                    getPreparationFailureReason()
                )
            );
        }

        return;
    }

    gTesterWarmUpPreparedAt = fromM5BarTime;
    gLogger.info(
        __FUNCTION__,
        StringFormat(
            "tester warm-up resources initialized. m5=%s pairs=%d/%d reason=%s",
            TimeToString(fromM5BarTime, TIME_DATE | TIME_MINUTES),
            gCurrencyStrengthCalculator.validPairCount,
            gCurrencyStrengthCalculator.getExpectedPairCount(),
            getPreparationFailureReason()
        )
    );
}

/**
 * 再確認後も未準備だったM5スナップショットの再試行待ちを記録する。
 *
 * @param fromM5BarTime 再試行対象のM5足開始時刻。
 */
void logTesterSnapshotRetryWait(const datetime fromM5BarTime) {
    gTesterRetryWaitCount++;
    string reason = getPreparationFailureReason();
    bool shouldLog = (
        gTesterRetryWaitCount == 1
            || gTesterRetryWaitCount
                % testerDiagnosticLogIntervalBars == 0
    );
    gLastRetryPreparationFailureReason = reason;

    if (!shouldLog) {
        return;
    }

    gLogger.error(
        __FUNCTION__,
        StringFormat(
            "tester snapshot waiting for next M5 retry. m5=%s retryWaits=%d pairs=%d/%d votes=%d reason=%s",
            TimeToString(fromM5BarTime, TIME_DATE | TIME_MINUTES),
            gTesterRetryWaitCount,
            gCurrencyStrengthCalculator.validPairCount,
            gCurrencyStrengthCalculator.getExpectedPairCount(),
            gCurrencyStrengthCalculator.getPairVoteCount(),
            reason
        )
    );
}

/**
 * 直近集計の準備不足理由をログ用文字列として取得する。
 *
 * @return 準備不足理由。不明な場合はUNKNOWN。
 */
string getPreparationFailureReason() {
    if (gCurrencyStrengthCalculator == NULL) {
        return "calculator is NULL";
    }

    string reason = gCurrencyStrengthCalculator.getLastPreparationFailureReason();

    if (reason == "") {
        return "UNKNOWN";
    }

    return reason;
}

/**
 * テスター集計の終了サマリーを出力する。
 */
void logTesterSnapshotSummary() {
    string retryReason = gLastRetryPreparationFailureReason;

    if (retryReason == "") {
        retryReason = "NONE";
    }

    gLogger.info(
        __FUNCTION__,
        StringFormat(
            "tester snapshot summary. persisted=%d retryWaits=%d lastProcessedM5=%s pendingM5=%s warmUpPreparedAt=%s lastRetryReason=%s",
            gTesterPersistedSnapshotCount,
            gTesterRetryWaitCount,
            getOptionalTimeText(gLastProcessedM5BarTime, "NONE"),
            getOptionalTimeText(gPendingTesterM5BarTime, "NONE"),
            getOptionalTimeText(gTesterWarmUpPreparedAt, "NONE"),
            retryReason
        )
    );
}

/**
 * 0を任意の代替文字列として日時を表示する。
 *
 * @param fromTime 表示対象日時。
 * @param fromEmptyText 日時が0の場合の表示文字列。
 * @return 日時または代替文字列。
 */
string getOptionalTimeText(
    const datetime fromTime,
    const string fromEmptyText
) {
    if (fromTime <= 0) {
        return fromEmptyText;
    }

    return TimeToString(fromTime, TIME_DATE | TIME_MINUTES);
}

/**
 * 全28通貨ペアを集計してランキングを更新する。
 *
 * @param fromM5BarTime 保存対象のM5足開始時刻。0の場合は現在足を使用する。
 * @return 成功、未準備、または処理失敗。
 */
CurrencyStrengthExecutionStatus execute(const datetime fromM5BarTime) {
    if (gCurrencyStrengthCalculator == NULL
            || gOscillatorHandleManager == NULL
            || gDrawCurrencyStrengthList == NULL) {
        return currencyStrengthExecutionFailed;
    }

    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
    datetime m5BarTime = fromM5BarTime;

    if (m5BarTime <= 0) {
        m5BarTime = iTime(_Symbol, PERIOD_M5, 0);
    }

    bool isCalculated = gCurrencyStrengthCalculator.calculateAt(
        gOscillatorHandleManager,
        _Symbol,
        m5BarTime
    );

    if (!isCalculated) {
        if (!isTester) {
            gLogger.error(__FUNCTION__, "currency strength calculation failed");

            return currencyStrengthExecutionFailed;
        }

        if (gCurrencyStrengthCalculator.hasLastCalculationFatalError()) {
            return currencyStrengthExecutionFailed;
        }

        return currencyStrengthExecutionNotReady;
    }

    if (!isTester || MQLInfoInteger(MQL_VISUAL_MODE)) {
        if (!gDrawCurrencyStrengthList.draw(gCurrencyStrengthCalculator)) {
            gLogger.error(__FUNCTION__, "currency strength draw failed");
        }

        if (showEntryCandidates
                && gCurrencyStrengthEntryCandidateList != NULL
                && gDrawCurrencyStrengthEntryCandidateList != NULL) {
            if (!gCurrencyStrengthEntryCandidateList.build(
                gCurrencyStrengthCalculator,
                entryCandidateMinRankDifference
            )) {
                gLogger.error(
                    __FUNCTION__,
                    "currency strength entry candidate build failed"
                );
                gDrawCurrencyStrengthEntryCandidateList.clear();
            } else if (!gDrawCurrencyStrengthEntryCandidateList.draw(
                gCurrencyStrengthEntryCandidateList
            )) {
                gLogger.error(
                    __FUNCTION__,
                    "currency strength entry candidate draw failed"
                );
            }
        }
    }

    datetime calculatedAt = TimeCurrent();

    if (isTester) {
        calculatedAt = m5BarTime;
    } else if (calculatedAt <= 0) {
        calculatedAt = TimeLocal();
    }

    bool saveDatabase = shouldSaveDatabase(m5BarTime);
    bool isComplete = (
        gCurrencyStrengthCalculator.validPairCount
            == gCurrencyStrengthCalculator.getExpectedPairCount()
    );

    if (isTester) {
        if (!databaseEnabled) {
            if (isComplete) {
                return currencyStrengthExecutionSucceeded;
            }

            return currencyStrengthExecutionNotReady;
        }

        if (gCurrencyStrengthPersistenceService == NULL
                || m5BarTime <= 0) {
            return currencyStrengthExecutionFailed;
        }

        if (!databaseSavePartialRuns && !isComplete) {
            return currencyStrengthExecutionNotReady;
        }

        saveDatabase = true;
    }

    if (saveDatabase) {
        string activeCalculationVersion =
            CurrencyStrengthCalculationProfile::getCalculationVersion(
                isTester
            );
        string sourceMode = CurrencyStrengthCalculationProfile::getSourceMode(
            isTester
        );

        if (gCurrencyStrengthPersistenceService.save(
            calculatedAt,
            m5BarTime,
            activeCalculationVersion,
            sourceMode,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            ChartID(),
            gCurrencyStrengthCalculator
        )) {
            gLastSavedM5BarTime = m5BarTime;

            if (isTester) {
                gTesterPersistedSnapshotCount++;
            }
        } else {
            gLogger.error(__FUNCTION__, "currency strength database save failed");

            if (isTester) {
                return currencyStrengthExecutionFailed;
            }
        }
    }

    if (isTester) {
        if (databaseSavePartialRuns && databaseEnabled) {
            return currencyStrengthExecutionSucceeded;
        }

        if (isComplete) {
            return currencyStrengthExecutionSucceeded;
        }

        return currencyStrengthExecutionNotReady;
    }

    cleanupDatabase(calculatedAt);

    return currencyStrengthExecutionSucceeded;
}

/**
 * 通貨強弱データベースを初期化する。
 *
 * @return 初期化に成功した場合true。
 */
bool initializeDatabase() {
    gCurrencyStrengthPersistenceService = new CurrencyStrengthYearlyPersistenceService(
        databaseFileName,
        databaseSplitByYear,
        databaseUseCommonFolder
    );

    if (gCurrencyStrengthPersistenceService == NULL) {
        return false;
    }

    datetime initialM5BarTime = 0;

    if (MQLInfoInteger(MQL_TESTER) && databaseSaveStartTime > 0) {
        initialM5BarTime = databaseSaveStartTime;
    }

    if (initialM5BarTime <= 0) {
        initialM5BarTime = iTime(_Symbol, PERIOD_M5, 0);
    }

    if (initialM5BarTime <= 0) {
        initialM5BarTime = TimeCurrent();
    }

    if (initialM5BarTime <= 0) {
        initialM5BarTime = TimeLocal();
    }

    return gCurrencyStrengthPersistenceService.openFor(initialM5BarTime);
}

/**
 * 現在の集計結果をデータベースへ保存するか判定する。
 *
 * @param fromM5BarTime M5現在足の開始時刻。
 * @return 保存対象の場合true。
 */
bool shouldSaveDatabase(const datetime fromM5BarTime) {
    if (gCurrencyStrengthPersistenceService == NULL
            || gCurrencyStrengthCalculator == NULL
            || fromM5BarTime <= 0) {
        return false;
    }

    if (!databaseSavePartialRuns
            && gCurrencyStrengthCalculator.validPairCount
                != gCurrencyStrengthCalculator.getExpectedPairCount()) {
        return false;
    }

    if (databaseSaveEveryRefresh) {
        return true;
    }

    return fromM5BarTime != gLastSavedM5BarTime;
}

/**
 * 保持期間を超えた通貨強弱集計を1日1回削除する。
 *
 * @param fromCalculatedAt 現在時刻。
 */
void cleanupDatabase(const datetime fromCalculatedAt) {
    if (gCurrencyStrengthPersistenceService == NULL
            || databaseRetentionDays <= 0
            || fromCalculatedAt <= 0) {
        return;
    }

    if (gLastDatabaseCleanupTime > 0
            && fromCalculatedAt - gLastDatabaseCleanupTime < 86400) {
        return;
    }

    long retentionSeconds = (long)databaseRetentionDays * 86400;
    datetime cutoff = (datetime)((long)fromCalculatedAt - retentionSeconds);

    if (!gCurrencyStrengthPersistenceService.deleteRunsBefore(
        cutoff,
        CurrencyStrengthCalculationProfile::getSourceMode(false)
    )) {
        gLogger.error(__FUNCTION__, "old currency strength run deletion failed");

        return;
    }

    gLastDatabaseCleanupTime = fromCalculatedAt;
}

/**
 * 保持している描画、集計およびハンドル管理クラスを解放する。
 */
void releaseResources() {
    releaseDatabaseResources();

    gFirstTargetM5BarTime = 0;
    gLastLiveAttemptM5BarTime = 0;
    gLastTesterAttemptM5BarTime = 0;
    gLastProcessedM5BarTime = 0;
    gPendingTesterM5BarTime = 0;
    gTesterWarmUpPreparedAt = 0;
    gTesterWarmUpAttemptCount = 0;
    gTesterRetryWaitCount = 0;
    gTesterPersistedSnapshotCount = 0;
    gLastRetryPreparationFailureReason = "";

    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        gDrawCurrencyStrengthEntryCandidateList.clear();
        delete gDrawCurrencyStrengthEntryCandidateList;
        gDrawCurrencyStrengthEntryCandidateList = NULL;
    }

    if (gDrawCurrencyStrengthList != NULL) {
        gDrawCurrencyStrengthList.clear();
        delete gDrawCurrencyStrengthList;
        gDrawCurrencyStrengthList = NULL;
    }

    if (gCurrencyStrengthEntryCandidateList != NULL) {
        delete gCurrencyStrengthEntryCandidateList;
        gCurrencyStrengthEntryCandidateList = NULL;
    }

    if (gCurrencyStrengthCalculator != NULL) {
        delete gCurrencyStrengthCalculator;
        gCurrencyStrengthCalculator = NULL;
    }

    if (gOscillatorHandleManager != NULL) {
        delete gOscillatorHandleManager;
        gOscillatorHandleManager = NULL;
    }
}

/**
 * 通貨強弱データベース関連リソースを解放する。
 */
void releaseDatabaseResources() {
    if (gCurrencyStrengthPersistenceService != NULL) {
        delete gCurrencyStrengthPersistenceService;
        gCurrencyStrengthPersistenceService = NULL;
    }

    gLastSavedM5BarTime = 0;
    gLastDatabaseCleanupTime = 0;
}
