//+------------------------------------------------------------------+
//|                                       CurrencyStrengthElliot.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.32"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "CurrencyStrengthHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Calendar\EconomicCalendarSchedule.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyPersistenceService.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthDailyRangeList.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthEntryCandidateList.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthList.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankComparison.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRegionRankComparison.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthSnapshotHeader.mqh>
#include <Mstng\Draw\DrawEconomicCalendarSchedule.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Strength\CurrencyStrengthDailyRangeList.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>
#include <Mstng\Strength\CurrencyStrengthH1EmaProvider.mqh>
#include <Mstng\Strength\CurrencyStrengthM1EmaProvider.mqh>
#include <Mstng\Strength\CurrencyStrengthSortType.mqh>
#include <Mstng\Strength\CurrencyStrengthTrendContinuationProvider.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 通貨強弱集計の実行結果。
 */
enum CurrencyStrengthExecutionStatus {
    currencyStrengthExecutionSucceeded = 0,
    currencyStrengthExecutionNotReady = 1,
    currencyStrengthExecutionFailed = 2
};

input group "01. 画面表示"

/** 長中期と中短期の順位を接続する比較パネルを表示する場合true。 */
input(name="順位比較を表示") bool showRankComparison = true;

/** 通貨順位比較の左に、地域の平均順位比較も表示する場合true。 */
input(name="地域順位比較を表示（順位比較ON時）") bool showRegionRankComparison = true;

/** MN1からM5までの時間足別スコア列を表示する場合true。 */
input(name="時間足別スコアを表示（MN1～M5）") bool showTimeFrameScores = true;

/** 通貨強弱ランキングの並び替え基準。 */
input(name="ランキングの並び順") CurrencyStrengthSortType sortType =
    CURRENCY_STRENGTH_SORT_TOTAL;

/** パネルのチャート左端からの距離。単位はピクセル。 */
input(name="表示位置：左から（px）") int panelXDistance = 12;

/** パネルのチャート上端からの距離。単位はピクセル。 */
input(name="表示位置：上から（px）") int panelYDistance = 32;

input group "02. 候補一覧"

/** 通貨強弱順位による売買候補一覧を表示する場合true。 */
input(name="売買候補一覧を表示") bool showEntryCandidates = true;

/** 売買候補一覧の最大表示件数。 */
input(name="候補の最大表示件数") int entryCandidateMaxCount = 10;

/** 候補に必要な最小順位差。長中期・中短期とも方向に合う1位・8位でも通過する。 */
input(name="候補に必要な順位差（1～7・各期間は端順位可）") int entryCandidateMinRankDifference = 2;

input group "03. 計算・更新"

/** オシレーター一致度に応じたスコアの重み付け方式。 */
input(name="スコアの計算方式") CurrencyStrengthVoteWeightMode voteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

/** LIVEのタイマー更新間隔。M5新足でも更新し、TESTERには適用しない。 */
input(name="通常チャートの更新間隔（秒）") int refreshSeconds = 60;

input group "04. DB保存"

/** 通貨強弱の集計結果をデータベースへ保存する場合true。 */
input(name="集計結果をDBに保存") bool databaseEnabled = true;

/** 年別分割時の年付与前のデータベースファイル名。 */
input(name="DBファイル名") string databaseFileName = "mstng-currency-strength.sqlite";

/** 保存対象M5足のサーバー時刻の年ごとにDBファイルを分ける場合true。 */
input(name="DBファイルを年ごとに分ける") bool databaseSplitByYear = true;

/** MT5共通フォルダへDBを保存する場合true。TESTERでは必須。 */
input(name="MT5共通フォルダに保存") bool databaseUseCommonFolder = true;

input group "05. DB詳細設定"

/** LIVEで保存済みの同じM5足も更新のたびに再保存する場合true。 */
input(name="同じM5足も再保存（LIVE）") bool databaseSaveEveryRefresh = false;

/** 全28通貨ペアが揃っていない集計結果も保存する場合true。 */
input(name="一部ペアが未取得でも保存") bool databaseSavePartialRuns = false;

/** TESTERのDB保存開始サーバー時刻。0は開始日時を制限しない。 */
input(name="テスター保存開始日時（サーバー時刻）")
datetime databaseSaveStartTime = D'2026.07.16 00:00';

/** LIVEデータの保持日数。0は削除せず、TESTERデータは対象外。 */
input(name="LIVEデータの保持日数（0＝削除なし）") int databaseRetentionDays = 0;

/** テスター診断ログを約1日ごとに出力するM5足数。 */
const int testerDiagnosticLogIntervalBars = 288;
/** ZigZagElliotと揃えるMN1履歴のウォームアップ必要本数。 */
const int testerMonthlyHistoryWarmUpBars = 61;
/** ZigZagElliotと揃えるW1以下履歴のウォームアップ必要本数。 */
const int testerStandardHistoryWarmUpBars = 206;
/** 隣接する表示パネル間の間隔。 */
const int panelGap = 12;
/** 共通日時欄24pxとパネル上側の余白4px。 */
const int snapshotHeaderOffset = 28;
/** JST・SRVの秒付き日時が収まる共通日時欄の幅。 */
const int snapshotHeaderWidth = 500;
/** 上段スコアと、その直下の日足値幅の間隔。 */
const int stackedPanelGap = 4;

double gHiddenBuffer[];

Logger gLogger;
DrawCurrencyStrengthEntryCandidateList *gDrawCurrencyStrengthEntryCandidateList = NULL;
DrawCurrencyStrengthList *gDrawCurrencyStrengthList;
DrawCurrencyStrengthRankComparison *gDrawCurrencyStrengthRankComparison = NULL;
DrawCurrencyStrengthRegionRankComparison *gDrawCurrencyStrengthRegionRankComparison = NULL;
DrawCurrencyStrengthSnapshotHeader *gDrawCurrencyStrengthSnapshotHeader = NULL;

/** 日足の元値幅・円換算値幅を表示する右端パネル。 */
DrawCurrencyStrengthDailyRangeList *gDrawCurrencyStrengthDailyRangeList = NULL;

/** 日足値幅一覧専用の取得結果。通貨強弱判定・DB保存とは独立する。 */
CurrencyStrengthDailyRangeList *gCurrencyStrengthDailyRangeList = NULL;

/** 日足値幅の右隣に経済指標の予定を表示する。 */
DrawEconomicCalendarSchedule *gDrawEconomicCalendarSchedule = NULL;

/** 経済指標の取得結果。通貨強弱集計とは独立して5分間保持する。 */
EconomicCalendarSchedule *gEconomicCalendarSchedule = NULL;

OscillatorHandleManager *gOscillatorHandleManager;
CurrencyStrengthCalculator *gCurrencyStrengthCalculator;
CurrencyStrengthEntryCandidateList *gCurrencyStrengthEntryCandidateList = NULL;
CurrencyStrengthH1EmaProvider *gCurrencyStrengthH1EmaProvider = NULL;
CurrencyStrengthM1EmaProvider *gCurrencyStrengthM1EmaProvider = NULL;

/** 継続モードで必要になったときだけ生成する履歴取得担当。 */
CurrencyStrengthTrendContinuationProvider *gCurrencyStrengthTrendContinuationProvider = NULL;

/** 最新候補を構築したM5集計時刻。0は候補未準備。 */
datetime gEntryCandidateM5BarTime = 0;

/** 最新候補のM1 EMA200を確認したサーバー時刻の分。0は候補未準備。 */
datetime gLastEntryCandidateM1Minute = 0;

bool gEntryCandidateSnapshotReady = false;

/** スコア再展開に利用できる集計結果を保持している場合true。 */
bool gScoreSnapshotReady = false;

/** 全パネル左端からスコアパネルまでの固定距離。 */
int gScorePanelOffset = 0;

/** 初期化後に、保存チャート由来の旧スコア・日足値幅描画を一度確認する。 */
bool gScoreOrphanCleanupPending = true;

/** AND強調のユーザー設定。一時的な集計・描画失敗では解除しない。 */
bool gReadyHighlightRequested = false;

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
int gLastTesterHistoryWarmUpProgress;
int gTesterRetryWaitCount;
int gTesterPersistedSnapshotCount;
string gLastRetryPreparationFailureReason;

/** LIVEの直近実集計を識別する改訂番号。 */
ulong gLiveTimingRevision = 0;

/** LIVEの直近calculateAtを計測済みの場合true。 */
bool gLiveCalculationMeasured = false;

/** LIVEの直近calculateAtの所要ミリ秒。 */
double gLiveCalculationMilliseconds = 0.0;

/** LIVEの直近execute全体の所要ミリ秒。 */
double gLiveExecutionMilliseconds = 0.0;

/** LIVEの直近executeの終了状態。 */
CurrencyStrengthExecutionStatus gLiveTimingStatus = currencyStrengthExecutionNotReady;

/** LIVEのTimer全体を計測済みの場合true。 */
bool gLiveTimerMeasured = false;

/** 診断反映を含む直近完了Timerの所要ミリ秒。 */
double gLiveTimerMilliseconds = 0.0;

/** 直近完了Timer内の診断ヘッダー反映の所要ミリ秒。 */
double gLiveTimerHeaderMilliseconds = 0.0;

/** 初期化後のLIVE集計時間の最大ミリ秒。 */
double gMaxLiveCalculationMilliseconds = 0.0;

/** 初期化後のLIVE更新全体時間の最大ミリ秒。 */
double gMaxLiveExecutionMilliseconds = 0.0;

/** 初期化後のLIVE Timer全体時間の最大ミリ秒。 */
double gMaxLiveTimerMilliseconds = 0.0;

/** 初期化後のLIVE診断ヘッダー反映時間の最大ミリ秒。 */
double gMaxLiveHeaderMilliseconds = 0.0;

/** LIVEの計測ログを出力済みの場合true。 */
bool gLiveTimingLogged = false;

/** LIVE計測ログを最後に出力した単調増加ミリ秒。 */
ulong gLastLiveTimingLogTick = 0;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    DrawChartRedrawBatch redrawBatch;
    bool isTester = Util::isStrategyTester();

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
            || !CurrencyStrengthCalculationProfile::isVoteWeightModeValid(
                voteWeightMode
            )
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

    string voteWeightModeText =
        CurrencyStrengthCalculationProfile::getVoteWeightModeText(
            voteWeightMode
        );
    IndicatorSetString(
        INDICATOR_SHORTNAME,
        "Elliot Currency Strength " + voteWeightModeText
    );

    MarketContext context(_Symbol, PERIOD_M15);
    gLogger.setLevel(LOG_INFO);
    gLogger.setMarketContext(context);

    int nextPanelXDistance = panelXDistance;
    int contentYDistance = panelYDistance + snapshotHeaderOffset;
    if (showRankComparison && showRegionRankComparison) {
        gDrawCurrencyStrengthRegionRankComparison = new DrawCurrencyStrengthRegionRankComparison(
            0,
            nextPanelXDistance,
            contentYDistance,
            voteWeightModeText
        );
        if (gDrawCurrencyStrengthRegionRankComparison != NULL) {
            nextPanelXDistance += gDrawCurrencyStrengthRegionRankComparison.getPanelWidth()
                + panelGap;
        }
    }

    if (showRankComparison) {
        gDrawCurrencyStrengthRankComparison = new DrawCurrencyStrengthRankComparison(
            0,
            nextPanelXDistance,
            contentYDistance,
            voteWeightModeText
        );
        if (gDrawCurrencyStrengthRankComparison != NULL) {
            nextPanelXDistance += gDrawCurrencyStrengthRankComparison.getPanelWidth()
                + panelGap;
        }
    }

    if (showEntryCandidates) {
        gDrawCurrencyStrengthEntryCandidateList =
            new DrawCurrencyStrengthEntryCandidateList(
                0,
                nextPanelXDistance,
                contentYDistance,
                entryCandidateMaxCount,
                voteWeightModeText
            );
        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            nextPanelXDistance += gDrawCurrencyStrengthEntryCandidateList.getPanelWidth()
                + panelGap;
        }

        gCurrencyStrengthEntryCandidateList =
            new CurrencyStrengthEntryCandidateList();
        gCurrencyStrengthH1EmaProvider = new CurrencyStrengthH1EmaProvider();
        gCurrencyStrengthM1EmaProvider = new CurrencyStrengthM1EmaProvider();
    }

    nextPanelXDistance = MathMax(nextPanelXDistance, panelXDistance + snapshotHeaderWidth + panelGap);
    gDrawCurrencyStrengthList = new DrawCurrencyStrengthList(
        0,
        nextPanelXDistance,
        panelYDistance,
        sortType,
        voteWeightModeText,
        showTimeFrameScores
    );
    gScorePanelOffset = nextPanelXDistance - panelXDistance;
    gScoreSnapshotReady = false;
    gScoreOrphanCleanupPending = true;
    loadScoreDisplaySettings();
    if (gDrawCurrencyStrengthList != NULL) {
        gDrawCurrencyStrengthDailyRangeList = new DrawCurrencyStrengthDailyRangeList(
            0,
            nextPanelXDistance,
            panelYDistance + gDrawCurrencyStrengthList.getPanelHeight() + stackedPanelGap,
            voteWeightModeText
        );
        gCurrencyStrengthDailyRangeList = new CurrencyStrengthDailyRangeList();
        loadDailyRangeDisplaySettings();
        if (gDrawCurrencyStrengthDailyRangeList != NULL) {
            gDrawEconomicCalendarSchedule = new DrawEconomicCalendarSchedule(
                0,
                nextPanelXDistance + gDrawCurrencyStrengthDailyRangeList.getPanelWidth() + panelGap,
                panelYDistance + gDrawCurrencyStrengthList.getPanelHeight() + stackedPanelGap,
                voteWeightModeText
            );
            gEconomicCalendarSchedule = new EconomicCalendarSchedule();
            loadEconomicCalendarDisplaySettings();
        }
    }

    gOscillatorHandleManager = new OscillatorHandleManager(PERIOD_M15);
    gCurrencyStrengthCalculator = new CurrencyStrengthCalculator(
        voteWeightMode
    );

    if (gDrawCurrencyStrengthList != NULL) {
        gDrawCurrencyStrengthSnapshotHeader = new DrawCurrencyStrengthSnapshotHeader(
            0,
            panelXDistance,
            panelYDistance,
            getSnapshotHeaderWidth(),
            voteWeightModeText
        );
    }

    if (gDrawCurrencyStrengthList == NULL
            || gDrawCurrencyStrengthDailyRangeList == NULL
            || gCurrencyStrengthDailyRangeList == NULL
            || gDrawEconomicCalendarSchedule == NULL
            || gEconomicCalendarSchedule == NULL
            || gDrawCurrencyStrengthSnapshotHeader == NULL
            || (showRankComparison && gDrawCurrencyStrengthRankComparison == NULL)
            || (showRankComparison && showRegionRankComparison
                && gDrawCurrencyStrengthRegionRankComparison == NULL)
            || gOscillatorHandleManager == NULL
            || gCurrencyStrengthCalculator == NULL
            || (showEntryCandidates
                && (gDrawCurrencyStrengthEntryCandidateList == NULL
                    || gCurrencyStrengthEntryCandidateList == NULL
                    || gCurrencyStrengthH1EmaProvider == NULL
                    || gCurrencyStrengthM1EmaProvider == NULL))) {
        releaseResources();

        return INIT_FAILED;
    }

    gReadyHighlightRequested = showRankComparison && showEntryCandidates;
    loadEntryDisplaySettings();
    gFirstTargetM5BarTime = 0;
    gLastLiveAttemptM5BarTime = 0;
    gLastTesterAttemptM5BarTime = 0;
    gLastProcessedM5BarTime = 0;
    gPendingTesterM5BarTime = 0;
    gTesterWarmUpPreparedAt = 0;
    gLastSavedM5BarTime = 0;
    gLastDatabaseCleanupTime = 0;
    gTesterWarmUpAttemptCount = 0;
    gLastTesterHistoryWarmUpProgress = -1;
    gTesterRetryWaitCount = 0;
    gTesterPersistedSnapshotCount = 0;
    gLastRetryPreparationFailureReason = "";

    resetLiveTiming();

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

    if (!isTester || MQLInfoInteger(MQL_VISUAL_MODE)) {
        drawScorePanel();
        if (!gDrawCurrencyStrengthSnapshotHeader.draw(
            0,
            0,
            gCurrencyStrengthCalculator.getExpectedPairCount()
        )) {
            gLogger.error(__FUNCTION__, "currency strength snapshot header draw failed");
            gDrawCurrencyStrengthSnapshotHeader.clear();
        }
    }

    if (!isTester) {
        if (!EventSetTimer(refreshSeconds)) {
            gLogger.error(__FUNCTION__, "EventSetTimer failed");
            releaseResources();

            return INIT_FAILED;
        }

        processLiveSnapshot(true, "INIT");
        redrawBatch.finish();
        drawDailyRangePanel(true);
    }

    return INIT_SUCCEEDED;
}

/**
 * タイマーと保持リソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    DrawChartRedrawBatch redrawBatch;
    EventKillTimer();

    if (Util::isStrategyTester()) {
        logTesterSnapshotSummary();
    }

    releaseResources();
}

/**
 * タイマーごとに通貨強弱を更新する。
 */
void OnTimer() {
    if (Util::isStrategyTester()) {
        return;
    }

    ulong timerStartMicroseconds = GetMicrosecondCount();
    ulong timingRevision = gLiveTimingRevision;
    cleanupOrphanedScorePanels();
    processLiveSnapshot(true, "TIMER");
    drawDailyRangePanel(true);
    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        gDrawCurrencyStrengthEntryCandidateList.refreshNewMarkers();
    }

    double headerMilliseconds = 0.0;
    if (gLiveTimingRevision != timingRevision) {
        // このTimerの全体時間は、診断反映を終えてから次回表示用に保持する。
        headerMilliseconds = updateLiveTimingTooltip("TIMER");
    }

    gLiveTimerMilliseconds = (double)(GetMicrosecondCount() - timerStartMicroseconds) / 1000.0;
    gMaxLiveTimerMilliseconds = MathMax(gMaxLiveTimerMilliseconds, gLiveTimerMilliseconds);
    gLiveTimerHeaderMilliseconds = headerMilliseconds;
    gLiveTimerMeasured = true;
    if (gLiveTimingRevision != timingRevision) {
        logLiveTiming("TIMER", headerMilliseconds);
    }
}

/**
 * 日足値幅一覧・スコア開閉・地域・通貨名・候補ペア・各表示条件のクリックを処理する。
 *
 * @param fromEventId チャートイベントID。
 * @param fromLongValue 整数イベント引数。
 * @param fromDoubleValue 実数イベント引数。
 * @param fromStringValue クリックしたチャートオブジェクト名。
 */
void OnChartEvent(
    const int fromEventId,
    const long &fromLongValue,
    const double &fromDoubleValue,
    const string &fromStringValue
) {
    if (fromEventId != CHARTEVENT_OBJECT_CLICK) {
        return;
    }

    DrawChartRedrawBatch redrawBatch;
    bool clearedOtherScoreInstances = cleanupOrphanedScorePanels();
    if (gDrawCurrencyStrengthList != NULL
            && gDrawCurrencyStrengthList.handleToggleClick(fromStringValue, clearedOtherScoreInstances)) {
        updateSnapshotHeaderWidth();
        drawScorePanel();
        redrawBatch.finish();
        saveScoreDisplaySettings();

        return;
    }

    if (gDrawCurrencyStrengthDailyRangeList != NULL) {
        bool wasCollapsed = gDrawCurrencyStrengthDailyRangeList.isCollapsed();
        if (gDrawCurrencyStrengthDailyRangeList.handleObjectClick(
                fromStringValue, clearedOtherScoreInstances)) {
            updateSnapshotHeaderWidth();
            drawDailyRangePanel(wasCollapsed && !gDrawCurrencyStrengthDailyRangeList.isCollapsed());
            redrawBatch.finish();
            saveDailyRangeDisplaySettings();

            return;
        }
    }

    if (gDrawEconomicCalendarSchedule != NULL) {
        bool wasCollapsed = gDrawEconomicCalendarSchedule.isCollapsed();
        if (gDrawEconomicCalendarSchedule.handleObjectClick(
                fromStringValue, clearedOtherScoreInstances)) {
            drawEconomicCalendarPanel(false);
            redrawBatch.finish();
            saveEconomicCalendarDisplaySettings();
            if (wasCollapsed && !gDrawEconomicCalendarSchedule.isCollapsed()) {
                drawEconomicCalendarPanel(true);
            }

            return;
        }
    }

    if (gDrawCurrencyStrengthEntryCandidateList != NULL
            && (gDrawCurrencyStrengthEntryCandidateList.handleFilterClick(fromStringValue)
                || gDrawCurrencyStrengthEntryCandidateList.handleEmaModeClick(fromStringValue)
                || gDrawCurrencyStrengthEntryCandidateList.handleContinuationModeClick(fromStringValue))) {
        saveEntryDisplaySettings();
        refreshEntryContinuation();
        bool isDrawn = gDrawCurrencyStrengthEntryCandidateList.draw(
            gCurrencyStrengthEntryCandidateList, false
        );
        synchronizePairSelection(gEntryCandidateSnapshotReady && isDrawn);

        return;
    }

    if (gDrawCurrencyStrengthRankComparison == NULL) {
        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            gDrawCurrencyStrengthEntryCandidateList.isReadyHighlightClick(fromStringValue);
        }

        return;
    }

    if (gDrawCurrencyStrengthRegionRankComparison != NULL
            && gDrawCurrencyStrengthRegionRankComparison.handleObjectClick(fromStringValue)) {
        string regionCurrencies[];
        gDrawCurrencyStrengthRegionRankComparison.getSelectedCurrencies(regionCurrencies);
        gDrawCurrencyStrengthRankComparison.setRegionHighlight(
            gDrawCurrencyStrengthRegionRankComparison.getSelectedRegionName(), regionCurrencies
        );

        return;
    }

    if (gDrawCurrencyStrengthRankComparison.handleObjectClick(fromStringValue)) {
        gReadyHighlightRequested = false;
        saveEntryDisplaySettings();
        if (gDrawCurrencyStrengthRegionRankComparison != NULL) {
            gDrawCurrencyStrengthRegionRankComparison.clearSelection();
            DrawChartRedrawBatch::request(0);
        }

        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            gDrawCurrencyStrengthEntryCandidateList.setReadyHighlightEnabled(
                gReadyHighlightRequested
            );
            gDrawCurrencyStrengthEntryCandidateList.setSelectedSymbol("");
        }

        return;
    }

    if (gDrawCurrencyStrengthEntryCandidateList == NULL) {
        return;
    }

    if (gDrawCurrencyStrengthEntryCandidateList.isReadyHighlightClick(fromStringValue)) {
        gReadyHighlightRequested = !gReadyHighlightRequested;
        saveEntryDisplaySettings();
        clearRegionSelection();
        synchronizePairSelection(gEntryCandidateSnapshotReady);

        return;
    }

    string symbolName = "";
    if (gDrawCurrencyStrengthEntryCandidateList.getClickedSymbol(
            fromStringValue, symbolName)
            && gDrawCurrencyStrengthRankComparison.togglePairSelection(symbolName)) {
        gReadyHighlightRequested = false;
        saveEntryDisplaySettings();
        if (gDrawCurrencyStrengthRegionRankComparison != NULL) {
            gDrawCurrencyStrengthRegionRankComparison.clearSelection();
            DrawChartRedrawBatch::request(0);
        }

        gDrawCurrencyStrengthEntryCandidateList.setReadyHighlightEnabled(
            gReadyHighlightRequested
        );
        gDrawCurrencyStrengthEntryCandidateList.setSelectedSymbol(
            gDrawCurrencyStrengthRankComparison.getSelectedPair()
        );
    }
}

/**
 * チャートと計算方式ごとの表示設定保存キーを取得する。
 * 銘柄・時間足の変更後も同じチャートの設定を引き継ぐ。
 *
 * @return 端末グローバル変数名。同一チャート・同一計算方式では共通。
 */
string getEntryDisplaySettingsKey() {
    return "Mstng.CSE.Ui.v1." + IntegerToString(ChartID())
        + "." + IntegerToString((int)voteWeightMode);
}

/**
 * 初回描画前に、ユーザーが操作した候補一覧の表示設定を復元する。
 * 未保存・不正な保存値・テスターでは既定値を維持する。
 */
void loadEntryDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthEntryCandidateList == NULL) {
        return;
    }

    double savedValue = 0;
    if (!GlobalVariableGet(getEntryDisplaySettingsKey(), savedValue)
            || !MathIsValidNumber(savedValue)
            || savedValue < 0 || savedValue > 27
            || savedValue != MathFloor(savedValue)
            || (((int)savedValue & 15) > 11)) {
        return;
    }

    // 既存の下位4ビットを保持し、継続モードは追加の第5ビットへ保存する。
    int settings = (int)savedValue;
    CurrencyStrengthEntryEmaMode emaMode = (CurrencyStrengthEntryEmaMode)((settings & 12) / 4);
    gDrawCurrencyStrengthEntryCandidateList.restoreDisplaySettings(
        (settings & 1) != 0, emaMode
    );
    gDrawCurrencyStrengthEntryCandidateList.setContinuationMode((settings & 16) != 0);
    gReadyHighlightRequested = (settings & 2) != 0;
}

/**
 * ユーザー操作後の表示設定を端末へ保存する。
 * 取得待ちによる一時的な強調OFFは使わず、ユーザーの要求値を保持する。
 * 通常更新・終了処理では呼び出さず、同じ保存値なら書き込みを省く。
 */
void saveEntryDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthEntryCandidateList == NULL) {
        return;
    }

    int settings = (int)gDrawCurrencyStrengthEntryCandidateList.getEmaMode() * 4;
    if (gDrawCurrencyStrengthEntryCandidateList.isAndOnly()) {
        settings += 1;
    }

    if (gReadyHighlightRequested) {
        settings += 2;
    }

    if (gDrawCurrencyStrengthEntryCandidateList.isContinuationMode()) {
        settings += 16;
    }

    string settingsKey = getEntryDisplaySettingsKey();
    double previousValue = 0;
    if (GlobalVariableGet(settingsKey, previousValue) && previousValue == settings) {
        return;
    }

    if (GlobalVariableSet(settingsKey, settings) == 0) {
        gLogger.error(__FUNCTION__, StringFormat(
            "entry candidate display settings save failed. error=%d", GetLastError()
        ));

        return;
    }

    GlobalVariablesFlush();
}

/**
 * スコア開閉専用の保存キーを取得する。候補一覧の設定とは分離する。
 *
 * @return チャートIDと計算方式で区別した端末グローバル変数名。
 */
string getScoreDisplaySettingsKey() {
    return "Mstng.CSE.ScoreUi.v1." + IntegerToString(ChartID())
        + "." + IntegerToString((int)voteWeightMode);
}

/**
 * 初回描画前にスコアの開閉状態を復元する。
 * 未保存・不正値・テスターでは初期の展開状態を維持する。
 */
void loadScoreDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthList == NULL) {
        return;
    }

    double savedValue = 0;
    if (!GlobalVariableGet(getScoreDisplaySettingsKey(), savedValue)
            || !MathIsValidNumber(savedValue)
            || (savedValue != 0 && savedValue != 1)) {
        return;
    }

    gDrawCurrencyStrengthList.setCollapsed(savedValue == 1);
}

/**
 * 見出しクリックで変更した開閉状態だけを保存する。
 * 通常更新・取得失敗・終了処理からは書き込まない。
 */
void saveScoreDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthList == NULL) {
        return;
    }

    int settings = 0;
    if (gDrawCurrencyStrengthList.isCollapsed()) {
        settings = 1;
    }

    string settingsKey = getScoreDisplaySettingsKey();
    double previousValue = 0;
    if (GlobalVariableGet(settingsKey, previousValue) && previousValue == settings) {
        return;
    }

    if (GlobalVariableSet(settingsKey, settings) == 0) {
        gLogger.error(__FUNCTION__, StringFormat(
            "currency strength score display settings save failed. error=%d", GetLastError()
        ));

        return;
    }

    GlobalVariablesFlush();
}

/**
 * 稼働中の同系統インジケーターが一つの場合だけ、保存チャート由来の旧描画を除去する。
 * OnInitでは自己登録が完了していないため、通常Timerまたはクリックから一度だけ確認する。
 * 複数配置・一覧取得失敗・未登録時は他インスタンスの描画を削除しない。
 *
 * @return 単独配置を確認して旧描画を整理できた場合true。
 */
bool cleanupOrphanedScorePanels() {
    if (!gScoreOrphanCleanupPending || Util::isStrategyTester()
            || gDrawCurrencyStrengthList == NULL || gDrawCurrencyStrengthSnapshotHeader == NULL) {
        return false;
    }

    int total = ChartIndicatorsTotal(0, 0);
    if (total < 0) {
        return false;
    }

    int instanceCount = 0;
    for (int i = 0; i < total; i++) {
        string indicatorName = ChartIndicatorName(0, 0, i);
        if (indicatorName == "") {
            return false;
        }

        if (StringFind(indicatorName, "Elliot Currency Strength ") == 0) {
            instanceCount++;
        }
    }

    if (instanceCount == 0) {
        return false;
    }

    if (instanceCount > 1) {
        gScoreOrphanCleanupPending = false;

        return false;
    }

    DrawChartRedrawBatch redrawBatch;
    bool scoreCleared = gDrawCurrencyStrengthList.clearOtherInstances();
    bool headerCleared = gDrawCurrencyStrengthSnapshotHeader.clearOtherInstances();
    bool dailyRangeCleared = true;
    if (gDrawCurrencyStrengthDailyRangeList != NULL) {
        dailyRangeCleared = gDrawCurrencyStrengthDailyRangeList.clearOtherInstances();
    }

    bool rankCleared = true;
    if (gDrawCurrencyStrengthRankComparison != NULL) {
        rankCleared = gDrawCurrencyStrengthRankComparison.clearOtherInstances();
    }

    bool regionCleared = true;
    if (gDrawCurrencyStrengthRegionRankComparison != NULL) {
        regionCleared = gDrawCurrencyStrengthRegionRankComparison.clearOtherInstances();
    }

    bool calendarCleared = true;
    if (gDrawEconomicCalendarSchedule != NULL) {
        calendarCleared = gDrawEconomicCalendarSchedule.clearOtherInstances();
    }

    bool entryCleared = true;
    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        entryCleared = gDrawCurrencyStrengthEntryCandidateList.clearOtherInstances();
    }

    if (!scoreCleared || !headerCleared || !dailyRangeCleared || !rankCleared
            || !regionCleared || !calendarCleared || !entryCleared) {
        return false;
    }

    gScoreOrphanCleanupPending = false;

    return true;
}

/**
 * JST・SRVの日時表示に必要な共通日時欄の固定幅を取得する。
 *
 * @return 共通日時欄の幅。
 */
int getSnapshotHeaderWidth() {
    return snapshotHeaderWidth;
}

/**
 * 共通日時欄の固定幅を反映する。
 * 反映失敗は通常更新で再試行する。
 */
void updateSnapshotHeaderWidth() {
    if (gDrawCurrencyStrengthSnapshotHeader != NULL
            && !gDrawCurrencyStrengthSnapshotHeader.setWidth(getSnapshotHeaderWidth())) {
        gLogger.error(__FUNCTION__, "currency strength snapshot header width update failed");
    }
}

/**
 * 保持中の集計結果でスコアを描画する。再計算や候補の状態更新は行わない。
 * 未集計・直近集計失敗時は、途中の値を使わず開閉できる集計待ちを表示する。
 */
void drawScorePanel() {
    if (gDrawCurrencyStrengthList == NULL) {
        return;
    }

    CurrencyStrengthCalculator *calculator = NULL;
    if (gScoreSnapshotReady) {
        calculator = gCurrencyStrengthCalculator;
    }

    if (!gDrawCurrencyStrengthList.draw(calculator)) {
        gLogger.error(__FUNCTION__, "currency strength draw failed");
    }

    // 確定したスコアの高さで位置を更新し、集計待ちへの切替時も同じ描画内で移動する。
    drawDailyRangePanel(false);
}

/**
 * 日足値幅一覧だけの開閉・並び順設定キーを取得する。
 *
 * @return チャートと計算方式ごとに独立した保存キー。
 */
string getDailyRangeDisplaySettingsKey() {
    return "Mstng.CSE.RangeUi.v1." + IntegerToString(ChartID())
        + "." + IntegerToString((int)voteWeightMode);
}

/**
 * 通常チャートで保存済みの日足値幅一覧の表示設定を復元する。
 */
void loadDailyRangeDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthDailyRangeList == NULL) {
        return;
    }

    double savedValue = 0;
    if (!GlobalVariableGet(getDailyRangeDisplaySettingsKey(), savedValue)
            || !MathIsValidNumber(savedValue) || savedValue < 0 || savedValue > 7
            || savedValue != MathFloor(savedValue)) {
        return;
    }

    int settings = (int)savedValue;
    gDrawCurrencyStrengthDailyRangeList.setCollapsed((settings & 1) != 0);
    gDrawCurrencyStrengthDailyRangeList.setSortByJpy((settings & 2) != 0);
    gDrawCurrencyStrengthDailyRangeList.setAverageMode((settings & 4) != 0);
}

/**
 * 日足値幅一覧のユーザー操作による開閉・並び順・当日/平均モードを保存する。
 * ページ移動だけで設定値が変わらない場合は保存しない。
 */
void saveDailyRangeDisplaySettings() {
    if (Util::isStrategyTester() || gDrawCurrencyStrengthDailyRangeList == NULL) {
        return;
    }

    int settings = 0;
    if (gDrawCurrencyStrengthDailyRangeList.isCollapsed()) {
        settings += 1;
    }

    if (gDrawCurrencyStrengthDailyRangeList.isSortByJpy()) {
        settings += 2;
    }

    if (gDrawCurrencyStrengthDailyRangeList.isAverageMode()) {
        settings += 4;
    }

    string settingsKey = getDailyRangeDisplaySettingsKey();
    double previousValue = 0;
    if (GlobalVariableGet(settingsKey, previousValue) && previousValue == settings) {
        return;
    }

    if (GlobalVariableSet(settingsKey, settings) == 0) {
        gLogger.error(__FUNCTION__, StringFormat(
            "currency strength daily range display settings save failed. error=%d", GetLastError()
        ));

        return;
    }

    GlobalVariablesFlush();
}

/**
 * 日足値幅一覧の表示を更新する。閉状態では取得せず見出しだけ維持する。
 * 通貨強弱集計の成否とは独立し、並び順・ページ・移動だけなら保持結果を使用する。
 * テスターでは現在時点の日足・換算レートを取得しない。
 *
 * @param fromRefresh 日足と換算レートの再取得を許可する場合true。
 */
void drawDailyRangePanel(const bool fromRefresh) {
    if (gDrawCurrencyStrengthDailyRangeList == NULL) {
        return;
    }

    bool isTester = Util::isStrategyTester();
    if (isTester && !MQLInfoInteger(MQL_VISUAL_MODE)) {
        return;
    }

    if (gDrawCurrencyStrengthList != NULL
            && !gDrawCurrencyStrengthDailyRangeList.setPosition(
                panelXDistance + gScorePanelOffset,
                panelYDistance + gDrawCurrencyStrengthList.getPanelHeight() + stackedPanelGap)) {
        gLogger.error(__FUNCTION__, "currency strength daily range position update failed");
    }

    CurrencyStrengthDailyRangeList *rangeList = NULL;
    if (!isTester) {
        rangeList = gCurrencyStrengthDailyRangeList;
        if (fromRefresh && rangeList != NULL && !gDrawCurrencyStrengthDailyRangeList.isCollapsed()) {
            rangeList.update(_Symbol);
        }
    }

    if (!gDrawCurrencyStrengthDailyRangeList.draw(rangeList)) {
        gLogger.error(__FUNCTION__, "currency strength daily range draw failed");
    }

    drawEconomicCalendarPanel(fromRefresh);
}

/**
 * 経済指標パネルの開閉・重要度・祝日設定の保存キーを取得する。
 *
 * @return チャートと計算方式ごとの保存キー。
 */
string getEconomicCalendarDisplaySettingsKey() {
    return "Mstng.CSE.CalendarUi.v1." + IntegerToString(ChartID())
        + "." + IntegerToString((int)voteWeightMode);
}

/**
 * 通常チャートの経済指標パネルの表示設定を復元する。
 */
void loadEconomicCalendarDisplaySettings() {
    if (Util::isStrategyTester() || gDrawEconomicCalendarSchedule == NULL) {
        return;
    }

    double savedValue = 0;
    if (!GlobalVariableGet(getEconomicCalendarDisplaySettingsKey(), savedValue)
            || !MathIsValidNumber(savedValue) || savedValue < 0 || savedValue > 7
            || savedValue != MathFloor(savedValue)) {
        return;
    }

    int settings = (int)savedValue;
    gDrawEconomicCalendarSchedule.setCollapsed((settings & 1) != 0);
    gDrawEconomicCalendarSchedule.setIncludeModerate((settings & 2) != 0);
    // 祝日OFFを保存するため、従来の保存値0～3は祝日ONとして復元する。
    gDrawEconomicCalendarSchedule.setIncludeHolidays((settings & 4) == 0);
}

/**
 * 経済指標パネルの開閉・重要度・祝日設定が変わった場合だけ保存する。
 */
void saveEconomicCalendarDisplaySettings() {
    if (Util::isStrategyTester() || gDrawEconomicCalendarSchedule == NULL) {
        return;
    }

    int settings = 0;
    if (gDrawEconomicCalendarSchedule.isCollapsed()) {
        settings += 1;
    }

    if (gDrawEconomicCalendarSchedule.isIncludeModerate()) {
        settings += 2;
    }

    if (!gDrawEconomicCalendarSchedule.isIncludeHolidays()) {
        settings += 4;
    }

    string settingsKey = getEconomicCalendarDisplaySettingsKey();
    double previousValue = 0;
    if (GlobalVariableGet(settingsKey, previousValue) && previousValue == settings) {
        return;
    }

    if (GlobalVariableSet(settingsKey, settings) == 0) {
        gLogger.error(__FUNCTION__, StringFormat(
            "economic calendar display settings save failed. error=%d", GetLastError()
        ));

        return;
    }

    GlobalVariablesFlush();
}

/**
 * 日足値幅の右へ経済指標を配置し、開状態だけ取得・表示を更新する。
 * 取得間隔は取得クラスで制限し、クリック時は保持データで即座に描画する。
 *
 * @param fromRefresh 予定の再取得を許可する場合true。
 */
void drawEconomicCalendarPanel(const bool fromRefresh) {
    if (gDrawEconomicCalendarSchedule == NULL || gDrawCurrencyStrengthDailyRangeList == NULL
            || gDrawCurrencyStrengthList == NULL) {
        return;
    }

    bool isTester = Util::isStrategyTester();
    if (isTester && !MQLInfoInteger(MQL_VISUAL_MODE)) {
        return;
    }

    if (!gDrawEconomicCalendarSchedule.setPosition(
            panelXDistance + gScorePanelOffset
                + gDrawCurrencyStrengthDailyRangeList.getPanelWidth() + panelGap,
            panelYDistance + gDrawCurrencyStrengthList.getPanelHeight() + stackedPanelGap)) {
        gLogger.error(__FUNCTION__, "economic calendar position update failed");
    }

    EconomicCalendarSchedule *schedule = NULL;
    if (!isTester) {
        schedule = gEconomicCalendarSchedule;
        if (fromRefresh && schedule != NULL && !gDrawEconomicCalendarSchedule.isCollapsed()) {
            schedule.update();
        }
    }

    if (!gDrawEconomicCalendarSchedule.draw(schedule)) {
        gLogger.error(__FUNCTION__, "economic calendar draw failed");
    }
}

/**
 * 地域強調のみを解除し、手動・READYの選択状態は保持する。
 */
void clearRegionSelection() {
    if (gDrawCurrencyStrengthRegionRankComparison == NULL) {
        return;
    }

    gDrawCurrencyStrengthRegionRankComparison.clearSelection();
    if (gDrawCurrencyStrengthRankComparison != NULL) {
        string regionCurrencies[];
        gDrawCurrencyStrengthRankComparison.setRegionHighlight("", regionCurrencies);
    }
}

/**
 * 最新候補に合わせてペア選択・AND強調とクリック可否を同期する。
 * 表示上限より下の候補も検索し、通貨名からの手動選択は候補の増減で解除しない。
 * AND強調は表示中のREADYかつ選択したEMA200条件が同方向の候補だけを対象にする。
 * ON/OFF設定を保持し、取得・描画待ちでは強調だけを止め、正常表示時に再開する。
 *
 * @param fromCandidatesReady 最新候補一覧の構築と描画に成功した場合true。
 */
void synchronizePairSelection(const bool fromCandidatesReady) {
    bool canSelectPair = fromCandidatesReady
        && gDrawCurrencyStrengthRankComparison != NULL
        && gDrawCurrencyStrengthRankComparison.isRankingReady();
    gEntryCandidateSnapshotReady = canSelectPair;
    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        gDrawCurrencyStrengthEntryCandidateList.setPairSelectionEnabled(
            canSelectPair
        );
    }

    if (gDrawCurrencyStrengthRankComparison == NULL) {
        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            gDrawCurrencyStrengthEntryCandidateList.setReadyHighlightEnabled(false);
            gDrawCurrencyStrengthEntryCandidateList.setSelectedSymbol("");
        }

        return;
    }

    string readySymbols[];
    bool canHighlightReady = gReadyHighlightRequested && canSelectPair
        && gDrawCurrencyStrengthEntryCandidateList != NULL;
    if (canHighlightReady) {
        gDrawCurrencyStrengthEntryCandidateList.getDisplayedReadySymbols(readySymbols);
    }

    gDrawCurrencyStrengthRankComparison.setReadyHighlight(canHighlightReady, readySymbols);

    string selectedPair = gDrawCurrencyStrengthRankComparison.getSelectedPair();
    if (selectedPair != "") {
        bool isCandidate = false;
        if (fromCandidatesReady
                && gCurrencyStrengthEntryCandidateList != NULL
                && gCurrencyStrengthEntryCandidateList.isRankingReady()) {
            for (int i = 0; i < gCurrencyStrengthEntryCandidateList.size(); i++) {
                CurrencyStrengthEntryCandidate candidate;
                if (gCurrencyStrengthEntryCandidateList.get(i, candidate)
                        && candidate.symbolName == selectedPair) {
                    isCandidate = true;
                    break;
                }
            }
        }

        if (!isCandidate) {
            gDrawCurrencyStrengthRankComparison.clearPairSelection();
        }
    }

    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        gDrawCurrencyStrengthEntryCandidateList.setReadyHighlightEnabled(
            gReadyHighlightRequested
        );
        gDrawCurrencyStrengthEntryCandidateList.setSelectedSymbol(
            gDrawCurrencyStrengthRankComparison.getSelectedPair()
        );
    }
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
    if (!Util::isStrategyTester()) {
        processLiveSnapshot(false);
        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            gDrawCurrencyStrengthEntryCandidateList.refreshNewMarkers();
        }

        return ratesTotal;
    }

    processTesterSnapshots();
    if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
        gDrawCurrencyStrengthEntryCandidateList.refreshNewMarkers();
    }

    return ratesTotal;
}

/**
 * LIVEの現在M5足を集計する。
 *
 * 新規M5足は最初のティックで実行する。
 * タイマーからの呼び出しでは、同じM5足でも定期更新と失敗再試行を行う。
 *
 * @param fromForceRefresh 同じM5足でも定期更新する場合true。
 * @param fromTrigger 診断用の呼出元。INIT・TIMER・TICK。
 */
void processLiveSnapshot(const bool fromForceRefresh, const string fromTrigger = "TICK") {
    if (Util::isStrategyTester()) {
        return;
    }

    datetime currentM5BarTime = iTime(_Symbol, PERIOD_M5, 0);

    if (currentM5BarTime <= 0) {
        return;
    }

    if (!fromForceRefresh
            && currentM5BarTime == gLastLiveAttemptM5BarTime) {
        refreshEntryCandidateM1(TimeCurrent());

        return;
    }

    gLastLiveAttemptM5BarTime = currentM5BarTime;
    gLiveCalculationMeasured = false;
    gLiveCalculationMilliseconds = 0.0;
    ulong executionStartMicroseconds = GetMicrosecondCount();
    gLiveTimingStatus = execute(currentM5BarTime);
    gLiveExecutionMilliseconds =
        (double)(GetMicrosecondCount() - executionStartMicroseconds) / 1000.0;
    gMaxLiveExecutionMilliseconds = MathMax(gMaxLiveExecutionMilliseconds, gLiveExecutionMilliseconds);
    gLiveTimingRevision++;

    if (fromTrigger != "TIMER") {
        double headerMilliseconds = updateLiveTimingTooltip(fromTrigger);
        logLiveTiming(fromTrigger, headerMilliseconds);
    }
}

/**
 * LIVE診断値を未計測へ戻す。
 */
void resetLiveTiming() {
    gLiveTimingRevision = 0;
    gLiveCalculationMeasured = false;
    gLiveCalculationMilliseconds = 0.0;
    gLiveExecutionMilliseconds = 0.0;
    gLiveTimingStatus = currencyStrengthExecutionNotReady;
    gLiveTimerMeasured = false;
    gLiveTimerMilliseconds = 0.0;
    gLiveTimerHeaderMilliseconds = 0.0;
    gMaxLiveCalculationMilliseconds = 0.0;
    gMaxLiveExecutionMilliseconds = 0.0;
    gMaxLiveTimerMilliseconds = 0.0;
    gMaxLiveHeaderMilliseconds = 0.0;
    gLiveTimingLogged = false;
    gLastLiveTimingLogTick = 0;
}

/**
 * 直近実集計の結果を診断用の文字列で返す。
 *
 * @return SUCCEEDED・NOT_READY・FAILED。
 */
string getLiveTimingResult() {
    if (gLiveTimingStatus == currencyStrengthExecutionSucceeded) {
        return "SUCCEEDED";
    }

    if (gLiveTimingStatus == currencyStrengthExecutionNotReady) {
        return "NOT_READY";
    }

    return "FAILED";
}

/**
 * 直近実集計と直近完了Timerの計測値を既存ヘッダーの説明へ反映する。
 * Timer内から呼ぶ場合、Timer全体・同診断反映は前回完了分を表示する。
 *
 * @param fromTrigger INIT・TIMER・TICK。
 * @return 説明文の生成と反映にかかったミリ秒。
 */
double updateLiveTimingTooltip(const string fromTrigger) {
    if (gDrawCurrencyStrengthSnapshotHeader == NULL) {
        return 0.0;
    }

    ulong headerStartMicroseconds = GetMicrosecondCount();
    string calculationText = "--";
    if (gLiveCalculationMeasured) {
        calculationText = DoubleToString(gLiveCalculationMilliseconds, 1);
    }

    string timerText = "--";
    string timerHeaderText = "--";
    if (gLiveTimerMeasured) {
        timerText = DoubleToString(gLiveTimerMilliseconds, 1);
        timerHeaderText = DoubleToString(gLiveTimerHeaderMilliseconds, 1);
    }

    string tooltip = StringFormat(
        "集計 %sms / 更新全体 %.1fms\n直近完了Timer %sms / 同診断反映 %sms\n最終 %s %s",
        calculationText, gLiveExecutionMilliseconds,
        timerText, timerHeaderText, fromTrigger, getLiveTimingResult()
    );
    gDrawCurrencyStrengthSnapshotHeader.updateTimingTooltip(tooltip);

    double headerMilliseconds = (double)(GetMicrosecondCount() - headerStartMicroseconds) / 1000.0;
    gMaxLiveHeaderMilliseconds = MathMax(gMaxLiveHeaderMilliseconds, headerMilliseconds);

    return headerMilliseconds;
}

/**
 * 実集計が発生した回だけ、最大60秒に1回のINFO診断を出力する。
 * Timer内では診断反映を含む計測完了後に呼び、ログ出力自体は計測しない。
 *
 * @param fromTrigger INIT・TIMER・TICK。
 * @param fromHeaderMilliseconds 今回の診断ヘッダー反映の所要ミリ秒。
 */
void logLiveTiming(const string fromTrigger, const double fromHeaderMilliseconds) {
    ulong currentTick = GetTickCount64();
    if (gLiveTimingLogged && currentTick >= gLastLiveTimingLogTick
            && currentTick - gLastLiveTimingLogTick < 60000) {
        return;
    }

    gLiveTimingLogged = true;
    gLastLiveTimingLogTick = currentTick;
    string calculationText = "--";
    if (gLiveCalculationMeasured) {
        calculationText = DoubleToString(gLiveCalculationMilliseconds, 1);
    }

    string timerText = "--";
    if (gLiveTimerMeasured) {
        timerText = DoubleToString(gLiveTimerMilliseconds, 1);
    }

    gLogger.info(__FUNCTION__, StringFormat(
        "CSE_TIMING trigger=%s result=%s bar=%s calcMs=%s executeMs=%.1f completedTimerMs=%s headerMs=%.1f maxCalcMs=%.1f maxExecuteMs=%.1f maxTimerMs=%.1f maxHeaderMs=%.1f",
        fromTrigger, getLiveTimingResult(),
        TimeToString(gLastLiveAttemptM5BarTime, TIME_DATE | TIME_SECONDS),
        calculationText, gLiveExecutionMilliseconds, timerText, fromHeaderMilliseconds,
        gMaxLiveCalculationMilliseconds, gMaxLiveExecutionMilliseconds,
        gMaxLiveTimerMilliseconds, gMaxLiveHeaderMilliseconds
    ));
}

/**
 * 継続モードでだけ履歴を参照し、現在候補へ3時間の継続判定を付与する。
 * 通常モード・テスター・集計待ちでは履歴検索を行わない。
 */
void refreshEntryContinuation() {
    if (gDrawCurrencyStrengthEntryCandidateList == NULL || gCurrencyStrengthEntryCandidateList == NULL
            || !gDrawCurrencyStrengthEntryCandidateList.isContinuationMode()) {
        return;
    }

    gDrawCurrencyStrengthEntryCandidateList.setContinuationStatus("");
    if (Util::isStrategyTester()) {
        gCurrencyStrengthEntryCandidateList.clearContinuation();
        gDrawCurrencyStrengthEntryCandidateList.setContinuationStatus("通常チャート専用");

        return;
    }

    if (!gScoreSnapshotReady || gEntryCandidateM5BarTime <= 0
            || !gCurrencyStrengthEntryCandidateList.isRankingReady()) {
        gCurrencyStrengthEntryCandidateList.clearContinuation();
        gDrawCurrencyStrengthEntryCandidateList.setContinuationStatus("集計待ち");

        return;
    }

    if (gCurrencyStrengthTrendContinuationProvider == NULL) {
        gCurrencyStrengthTrendContinuationProvider = new CurrencyStrengthTrendContinuationProvider(
            databaseFileName, databaseSplitByYear, databaseUseCommonFolder, voteWeightMode,
            AccountInfoString(ACCOUNT_SERVER), AccountInfoInteger(ACCOUNT_LOGIN));
    }

    if (gCurrencyStrengthTrendContinuationProvider == NULL
            || !gCurrencyStrengthTrendContinuationProvider.update(
                gCurrencyStrengthEntryCandidateList, gEntryCandidateM5BarTime)) {
        gCurrencyStrengthEntryCandidateList.clearContinuation();
        gDrawCurrencyStrengthEntryCandidateList.setContinuationStatus("履歴取得失敗");
    }
}

/**
 * LIVEの分が進んだ場合、候補のM1 EMA200と連動表示だけを更新する。
 * 通貨強弱の再集計とDB保存は行わない。
 *
 * @param fromTargetTime 最新確定足を選ぶ基準のサーバー時刻。
 */
void refreshEntryCandidateM1(const datetime fromTargetTime) {
    if (Util::isStrategyTester()
            || fromTargetTime <= 0
            || gLastEntryCandidateM1Minute <= 0
            || gCurrencyStrengthEntryCandidateList == NULL
            || gCurrencyStrengthM1EmaProvider == NULL
            || gDrawCurrencyStrengthEntryCandidateList == NULL
            || !gCurrencyStrengthEntryCandidateList.isRankingReady()) {
        return;
    }

    datetime targetMinute = fromTargetTime - fromTargetTime % 60;
    if (targetMinute == gLastEntryCandidateM1Minute) {
        return;
    }

    if (!gCurrencyStrengthEntryCandidateList.updateM1Ema(
        gCurrencyStrengthM1EmaProvider, fromTargetTime
    )) {
        gLogger.debug(__FUNCTION__, "currency strength M1 EMA200 is not ready");
    }

    gLastEntryCandidateM1Minute = targetMinute;
    refreshEntryContinuation();
    DrawChartRedrawBatch redrawBatch;
    bool isDrawn = gDrawCurrencyStrengthEntryCandidateList.draw(
        gCurrencyStrengthEntryCandidateList
    );
    synchronizePairSelection(isDrawn);
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

    if (!isTesterHistoryWarmUpReady(currentM5BarTime)) {
        return;
    }

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
 * 時間足ごとのテスター履歴ウォームアップ必要本数を取得する。
 *
 * @param fromTimeFrame 判定対象の時間足。
 * @return ウォームアップに必要な価格バー数。
 */
int getRequiredTesterHistoryWarmUpBars(
    const ENUM_TIMEFRAMES fromTimeFrame
) {
    if (fromTimeFrame == PERIOD_MN1) {
        return testerMonthlyHistoryWarmUpBars;
    }

    return testerStandardHistoryWarmUpBars;
}

/**
 * テスター基準シンボルの集計対象系列をM5から上位足の順に同期する。
 *
 * @return 全集計対象系列が同期済みの場合true。
 */
bool isTesterHistorySeriesSynchronized() {
    if (gCurrencyStrengthCalculator == NULL) {
        return false;
    }

    ENUM_TIMEFRAMES unsynchronizedTimeFrames[];
    int timeFrameCount = gCurrencyStrengthCalculator.getTimeFrameCount();
    int unsynchronizedCount = 0;

    ArrayResize(unsynchronizedTimeFrames, 0);

    // Open Pricesでは基準シンボルもM5から上位足の順に参照する。
    for (int i = timeFrameCount - 1; i >= 0; i--) {
        ENUM_TIMEFRAMES timeFrame =
            gCurrencyStrengthCalculator.getTimeFrame(i);

        if (WarmUpSeriesUtil::isSeriesSynchronized(
                _Symbol,
                timeFrame
            )) {
            continue;
        }

        if (ArrayResize(
            unsynchronizedTimeFrames,
            unsynchronizedCount + 1
        ) != unsynchronizedCount + 1) {
            return false;
        }

        unsynchronizedTimeFrames[unsynchronizedCount] = timeFrame;
        unsynchronizedCount++;
    }

    if (unsynchronizedCount <= 0) {
        return true;
    }

    WarmUpSeriesUtil::warmUp(
        _Symbol,
        unsynchronizedTimeFrames,
        testerStandardHistoryWarmUpBars
    );

    return false;
}

/**
 * テスター基準シンボルの全集計対象時間足に必要な価格バー数があるか判定する。
 *
 * 全時間足で最も低い達成率を進捗率とし、変化した場合だけINFOへ
 * 出力する。全28ペアの系列とストキャスハンドルの準備完了は、
 * 履歴到達後の既存リソースウォームアップと再試行へ委ねる。
 *
 * @param fromM5BarTime 現在のテスターM5足開始時刻。
 * @return 基準シンボルの価格バー数が十分な場合true。
 */
bool isTesterHistoryWarmUpReady(const datetime fromM5BarTime) {
    if (!Util::isStrategyTester()) {
        return true;
    }

    if (gCurrencyStrengthCalculator == NULL
            || !isTesterHistorySeriesSynchronized()) {
        return false;
    }

    int timeFrameCount = gCurrencyStrengthCalculator.getTimeFrameCount();

    if (timeFrameCount <= 0) {
        return false;
    }

    bool isReady = true;
    int overallProgress = 100;
    ENUM_TIMEFRAMES bottleneckTimeFrame = PERIOD_CURRENT;
    int bottleneckProgressBars = 0;
    int bottleneckAvailableBars = 0;
    int bottleneckRequiredBars = 0;
    string insufficientDetails = "";
    string allBarDetails = "";

    // Open Pricesの初回参照制約に合わせ、M5から上位足の順に判定する。
    for (int i = timeFrameCount - 1; i >= 0; i--) {
        ENUM_TIMEFRAMES timeFrame =
            gCurrencyStrengthCalculator.getTimeFrame(i);
        int requiredBars = getRequiredTesterHistoryWarmUpBars(timeFrame);
        int availableBars = Bars(_Symbol, timeFrame);
        int progressBars = availableBars;

        if (progressBars < 0) {
            progressBars = 0;
        }

        if (progressBars > requiredBars) {
            progressBars = requiredBars;
        }

        int timeFrameProgress = progressBars * 100 / requiredBars;

        if (bottleneckTimeFrame == PERIOD_CURRENT
                || (long)progressBars * bottleneckRequiredBars
                    < (long)bottleneckProgressBars * requiredBars) {
            bottleneckTimeFrame = timeFrame;
            bottleneckProgressBars = progressBars;
            bottleneckAvailableBars = availableBars;
            bottleneckRequiredBars = requiredBars;
        }

        if (timeFrameProgress < overallProgress) {
            overallProgress = timeFrameProgress;
        }

        if (allBarDetails != "") {
            allBarDetails += ", ";
        }

        allBarDetails += StringFormat(
            "%s:%d/%d",
            TimeUtil::convertTimeFrameToString(timeFrame),
            availableBars,
            requiredBars
        );

        if (availableBars >= requiredBars) {
            continue;
        }

        isReady = false;

        if (insufficientDetails != "") {
            insufficientDetails += ", ";
        }

        insufficientDetails += StringFormat(
            "%s:%d/%d",
            TimeUtil::convertTimeFrameToString(timeFrame),
            availableBars,
            requiredBars
        );
    }

    if (overallProgress != gLastTesterHistoryWarmUpProgress) {
        if (isReady) {
            gLogger.info(
                __FUNCTION__,
                StringFormat(
                    "tester currency strength history warm-up completed. simulatedTime=%s referenceSymbol=%s progress=100%% bars=%s",
                    TimeToString(
                        fromM5BarTime,
                        TIME_DATE | TIME_MINUTES
                    ),
                    _Symbol,
                    allBarDetails
                )
            );
        } else {
            gLogger.info(
                __FUNCTION__,
                StringFormat(
                    "tester currency strength history warm-up progress. simulatedTime=%s referenceSymbol=%s progress=%d%% bottleneck=%s bars=%d/%d insufficient=%s",
                    TimeToString(
                        fromM5BarTime,
                        TIME_DATE | TIME_MINUTES
                    ),
                    _Symbol,
                    overallProgress,
                    TimeUtil::convertTimeFrameToString(
                        bottleneckTimeFrame
                    ),
                    bottleneckAvailableBars,
                    bottleneckRequiredBars,
                    insufficientDetails
                )
            );
        }

        gLastTesterHistoryWarmUpProgress = overallProgress;
    }

    return isReady;
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

    bool isCalculated = gCurrencyStrengthCalculator.calculateAt(
        gOscillatorHandleManager,
        _Symbol,
        fromM5BarTime
    );
    bool isComplete = (
        gCurrencyStrengthCalculator.validPairCount
            == gCurrencyStrengthCalculator.getExpectedPairCount()
    );
    bool isPrepared = isCalculated && isComplete;

    if (!isPrepared) {
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
    gLastEntryCandidateM1Minute = 0;
    gScoreSnapshotReady = false;

    if (gCurrencyStrengthCalculator == NULL
            || gOscillatorHandleManager == NULL
            || gDrawCurrencyStrengthList == NULL) {
        if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
            gDrawCurrencyStrengthEntryCandidateList.suspendAndTracking();
        }

        return currencyStrengthExecutionFailed;
    }

    bool isTester = Util::isStrategyTester();
    datetime m5BarTime = fromM5BarTime;

    if (m5BarTime <= 0) {
        m5BarTime = iTime(_Symbol, PERIOD_M5, 0);
    }

    ulong calculationStartMicroseconds = 0;
    if (!isTester) {
        calculationStartMicroseconds = GetMicrosecondCount();
    }

    bool isCalculated = gCurrencyStrengthCalculator.calculateAt(
        gOscillatorHandleManager,
        _Symbol,
        m5BarTime
    );
    gScoreSnapshotReady = isCalculated;
    if (!isTester) {
        gLiveCalculationMilliseconds =
            (double)(GetMicrosecondCount() - calculationStartMicroseconds) / 1000.0;
        gMaxLiveCalculationMilliseconds = MathMax(gMaxLiveCalculationMilliseconds, gLiveCalculationMilliseconds);
        gLiveCalculationMeasured = true;
    }

    DrawChartRedrawBatch redrawBatch;
    bool isDrawingEnabled = !isTester || MQLInfoInteger(MQL_VISUAL_MODE);
    if (isDrawingEnabled && gDrawCurrencyStrengthSnapshotHeader != NULL) {
        updateSnapshotHeaderWidth();
        if (!gDrawCurrencyStrengthSnapshotHeader.draw(
            m5BarTime,
            gCurrencyStrengthCalculator.validPairCount,
            gCurrencyStrengthCalculator.getExpectedPairCount()
        )) {
            gLogger.error(__FUNCTION__, "currency strength snapshot header draw failed");
            gDrawCurrencyStrengthSnapshotHeader.clear();
        }
    }

    bool isRankComparisonDrawn = false;
    if (isDrawingEnabled && gDrawCurrencyStrengthRankComparison != NULL) {
        isRankComparisonDrawn = gDrawCurrencyStrengthRankComparison.draw(
            gCurrencyStrengthCalculator,
            m5BarTime
        );
        if (!isRankComparisonDrawn) {
            gLogger.error(__FUNCTION__, "currency strength rank comparison draw failed");
            gDrawCurrencyStrengthRankComparison.clear();
        }
    }

    if (isDrawingEnabled && gDrawCurrencyStrengthRegionRankComparison != NULL) {
        if (!gDrawCurrencyStrengthRegionRankComparison.draw(gDrawCurrencyStrengthRankComparison)) {
            gLogger.error(__FUNCTION__, "currency strength region rank comparison draw failed");
            gDrawCurrencyStrengthRegionRankComparison.clear();
            clearRegionSelection();
        }

        DrawChartRedrawBatch::request(0);
    }

    if (!isCalculated) {
        if (isDrawingEnabled) {
            drawScorePanel();
            if (gDrawCurrencyStrengthEntryCandidateList != NULL) {
                gDrawCurrencyStrengthEntryCandidateList.suspendAndTracking();
            }

            synchronizePairSelection(false);
        }

        if (!isTester) {
            gLogger.error(__FUNCTION__, "currency strength calculation failed");

            return currencyStrengthExecutionFailed;
        }

        if (gCurrencyStrengthCalculator.hasLastCalculationFatalError()) {
            return currencyStrengthExecutionFailed;
        }

        return currencyStrengthExecutionNotReady;
    }

    if (isDrawingEnabled) {
        drawScorePanel();

        bool areCandidatesReady = false;
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
                gDrawCurrencyStrengthEntryCandidateList.suspendAndTracking();
                gDrawCurrencyStrengthEntryCandidateList.clear();
            } else {
                gEntryCandidateM5BarTime = m5BarTime;
                if (!gCurrencyStrengthEntryCandidateList.updateH1Ema(
                    gCurrencyStrengthCalculator,
                    gCurrencyStrengthH1EmaProvider,
                    m5BarTime
                )) {
                    gLogger.debug(__FUNCTION__, "currency strength H1 EMA200 is not ready");
                }

                if (!isTester) {
                    datetime m1TargetTime = TimeCurrent();
                    if (!gCurrencyStrengthEntryCandidateList.updateM1Ema(
                        gCurrencyStrengthM1EmaProvider, m1TargetTime
                    )) {
                        gLogger.debug(__FUNCTION__, "currency strength M1 EMA200 is not ready");
                    }

                    gLastEntryCandidateM1Minute = m1TargetTime - m1TargetTime % 60;
                }

                refreshEntryContinuation();
                if (!gDrawCurrencyStrengthEntryCandidateList.draw(
                    gCurrencyStrengthEntryCandidateList
                )) {
                    gLogger.error(
                        __FUNCTION__,
                        "currency strength entry candidate draw failed"
                    );
                } else {
                    areCandidatesReady = gCurrencyStrengthEntryCandidateList.isRankingReady();
                }
            }
        }

        synchronizePairSelection(areCandidatesReady && isRankComparisonDrawn);
    }

    redrawBatch.finish();

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
                isTester,
                voteWeightMode
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

    if (Util::isStrategyTester() && databaseSaveStartTime > 0) {
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
    resetLiveTiming();

    gFirstTargetM5BarTime = 0;
    gLastLiveAttemptM5BarTime = 0;
    gLastTesterAttemptM5BarTime = 0;
    gLastProcessedM5BarTime = 0;
    gPendingTesterM5BarTime = 0;
    gTesterWarmUpPreparedAt = 0;
    gTesterWarmUpAttemptCount = 0;
    gLastTesterHistoryWarmUpProgress = -1;
    gTesterRetryWaitCount = 0;
    gTesterPersistedSnapshotCount = 0;
    gLastRetryPreparationFailureReason = "";

    if (gDrawCurrencyStrengthSnapshotHeader != NULL) {
        gDrawCurrencyStrengthSnapshotHeader.clear();
        delete gDrawCurrencyStrengthSnapshotHeader;
        gDrawCurrencyStrengthSnapshotHeader = NULL;
    }

    if (gDrawCurrencyStrengthRegionRankComparison != NULL) {
        gDrawCurrencyStrengthRegionRankComparison.clear();
        delete gDrawCurrencyStrengthRegionRankComparison;
        gDrawCurrencyStrengthRegionRankComparison = NULL;
    }

    if (gDrawCurrencyStrengthRankComparison != NULL) {
        gDrawCurrencyStrengthRankComparison.clear();
        delete gDrawCurrencyStrengthRankComparison;
        gDrawCurrencyStrengthRankComparison = NULL;
    }

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

    if (gDrawCurrencyStrengthDailyRangeList != NULL) {
        gDrawCurrencyStrengthDailyRangeList.clear();
        delete gDrawCurrencyStrengthDailyRangeList;
        gDrawCurrencyStrengthDailyRangeList = NULL;
    }

    if (gDrawEconomicCalendarSchedule != NULL) {
        delete gDrawEconomicCalendarSchedule;
        gDrawEconomicCalendarSchedule = NULL;
    }

    if (gEconomicCalendarSchedule != NULL) {
        delete gEconomicCalendarSchedule;
        gEconomicCalendarSchedule = NULL;
    }

    if (gCurrencyStrengthDailyRangeList != NULL) {
        delete gCurrencyStrengthDailyRangeList;
        gCurrencyStrengthDailyRangeList = NULL;
    }

    if (gCurrencyStrengthTrendContinuationProvider != NULL) {
        delete gCurrencyStrengthTrendContinuationProvider;
        gCurrencyStrengthTrendContinuationProvider = NULL;
    }

    gEntryCandidateM5BarTime = 0;
    if (gCurrencyStrengthEntryCandidateList != NULL) {
        delete gCurrencyStrengthEntryCandidateList;
        gCurrencyStrengthEntryCandidateList = NULL;
    }

    if (gCurrencyStrengthH1EmaProvider != NULL) {
        delete gCurrencyStrengthH1EmaProvider;
        gCurrencyStrengthH1EmaProvider = NULL;
    }

    if (gCurrencyStrengthM1EmaProvider != NULL) {
        delete gCurrencyStrengthM1EmaProvider;
        gCurrencyStrengthM1EmaProvider = NULL;
    }

    gLastEntryCandidateM1Minute = 0;
    gEntryCandidateSnapshotReady = false;
    gScoreSnapshotReady = false;
    gScorePanelOffset = 0;
    gScoreOrphanCleanupPending = true;
    gReadyHighlightRequested = false;

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
