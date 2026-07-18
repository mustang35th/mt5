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
#include <Mstng\Database\Dao\CurrencyStrengthPairVoteDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Service\CurrencyStrengthPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthList.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>

input int refreshSeconds = 60;
input int panelXDistance = 12;
input int panelYDistance = 12;
input bool databaseEnabled = true;
input string databaseFileName = "mstng-currency-strength.sqlite";
input bool databaseUseCommonFolder = true;
input bool databaseSaveEveryRefresh = false;
input bool databaseSavePartialRuns = false;
input int databaseRetentionDays = 30;

/** 集計ルール識別子。 */
const string calculationVersion = "pair-direction-raw-v6";

double gHiddenBuffer[];

Logger gLogger;
DrawCurrencyStrengthList *gDrawCurrencyStrengthList;
OscillatorHandleManager *gOscillatorHandleManager;
CurrencyStrengthCalculator *gCurrencyStrengthCalculator;
SqliteDatabase *gCurrencyStrengthDatabase;
CurrencyStrengthPairVoteDao *gCurrencyStrengthPairVoteDao;
CurrencyStrengthResultDao *gCurrencyStrengthResultDao;
CurrencyStrengthRunDao *gCurrencyStrengthRunDao;
CurrencyStrengthPersistenceService *gCurrencyStrengthPersistenceService;
datetime gLastSavedM15BarTime;
datetime gLastDatabaseCleanupTime;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    if (MQLInfoInteger(MQL_TESTER)) {
        Print("CurrencyStrengthElliot does not support Strategy Tester");

        return INIT_FAILED;
    }

    if (refreshSeconds < 1 || databaseRetentionDays < 0) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (databaseEnabled && databaseFileName == "") {
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
        panelYDistance
    );
    gOscillatorHandleManager = new OscillatorHandleManager(PERIOD_M15);
    gCurrencyStrengthCalculator = new CurrencyStrengthCalculator();

    if (gDrawCurrencyStrengthList == NULL
            || gOscillatorHandleManager == NULL
            || gCurrencyStrengthCalculator == NULL) {
        releaseResources();

        return INIT_FAILED;
    }

    gLastSavedM15BarTime = 0;
    gLastDatabaseCleanupTime = 0;

    if (databaseEnabled && !initializeDatabase()) {
        gLogger.error(
            __FUNCTION__,
            "currency strength database initialization failed; persistence disabled"
        );
        releaseDatabaseResources();
    }

    if (!EventSetTimer(refreshSeconds)) {
        gLogger.error(__FUNCTION__, "EventSetTimer failed");
        releaseResources();

        return INIT_FAILED;
    }

    execute();

    return INIT_SUCCEEDED;
}

/**
 * タイマーと保持リソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    EventKillTimer();
    releaseResources();
}

/**
 * タイマーごとに通貨強弱を更新する。
 */
void OnTimer() {
    execute();
}

/**
 * オブジェクト描画専用のため計算本数だけを返す。
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
    return ratesTotal;
}

/**
 * 全28通貨ペアを集計してランキングを更新する。
 */
void execute() {
    if (gCurrencyStrengthCalculator == NULL
            || gOscillatorHandleManager == NULL
            || gDrawCurrencyStrengthList == NULL) {
        return;
    }

    if (!gCurrencyStrengthCalculator.calculate(gOscillatorHandleManager)) {
        gLogger.error(__FUNCTION__, "currency strength calculation failed");

        return;
    }

    if (!gDrawCurrencyStrengthList.draw(gCurrencyStrengthCalculator)) {
        gLogger.error(__FUNCTION__, "currency strength draw failed");
    }

    datetime calculatedAt = TimeCurrent();

    if (calculatedAt <= 0) {
        calculatedAt = TimeLocal();
    }

    datetime m15BarTime = iTime(_Symbol, PERIOD_M15, 0);

    if (shouldSaveDatabase(m15BarTime)) {
        if (gCurrencyStrengthPersistenceService.save(
            calculatedAt,
            m15BarTime,
            calculationVersion,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            ChartID(),
            gCurrencyStrengthCalculator
        )) {
            gLastSavedM15BarTime = m15BarTime;
        } else {
            gLogger.error(__FUNCTION__, "currency strength database save failed");
        }
    }

    cleanupDatabase(calculatedAt);
}

/**
 * 通貨強弱データベースを初期化する。
 *
 * @return 初期化に成功した場合true。
 */
bool initializeDatabase() {
    gCurrencyStrengthDatabase = new SqliteDatabase(
        databaseFileName,
        databaseUseCommonFolder
    );

    if (gCurrencyStrengthDatabase == NULL) {
        return false;
    }

    if (!gCurrencyStrengthDatabase.open()) {
        return false;
    }

    gCurrencyStrengthRunDao = new CurrencyStrengthRunDao(
        gCurrencyStrengthDatabase.getHandle()
    );
    gCurrencyStrengthPairVoteDao = new CurrencyStrengthPairVoteDao(
        gCurrencyStrengthDatabase.getHandle()
    );
    gCurrencyStrengthResultDao = new CurrencyStrengthResultDao(
        gCurrencyStrengthDatabase.getHandle()
    );

    if (gCurrencyStrengthRunDao == NULL
            || gCurrencyStrengthPairVoteDao == NULL
            || gCurrencyStrengthResultDao == NULL) {
        return false;
    }

    gCurrencyStrengthPersistenceService = new CurrencyStrengthPersistenceService(
        gCurrencyStrengthDatabase.getHandle(),
        gCurrencyStrengthRunDao,
        gCurrencyStrengthPairVoteDao,
        gCurrencyStrengthResultDao
    );

    if (gCurrencyStrengthPersistenceService == NULL) {
        return false;
    }

    return gCurrencyStrengthPersistenceService.createTables();
}

/**
 * 現在の集計結果をデータベースへ保存するか判定する。
 *
 * @param fromM15BarTime M15現在足の開始時刻。
 * @return 保存対象の場合true。
 */
bool shouldSaveDatabase(const datetime fromM15BarTime) {
    if (gCurrencyStrengthPersistenceService == NULL
            || gCurrencyStrengthCalculator == NULL
            || fromM15BarTime <= 0) {
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

    return fromM15BarTime != gLastSavedM15BarTime;
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

    if (!gCurrencyStrengthPersistenceService.deleteRunsBefore(cutoff)) {
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

    if (gDrawCurrencyStrengthList != NULL) {
        gDrawCurrencyStrengthList.clear();
        delete gDrawCurrencyStrengthList;
        gDrawCurrencyStrengthList = NULL;
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

    if (gCurrencyStrengthResultDao != NULL) {
        delete gCurrencyStrengthResultDao;
        gCurrencyStrengthResultDao = NULL;
    }

    if (gCurrencyStrengthPairVoteDao != NULL) {
        delete gCurrencyStrengthPairVoteDao;
        gCurrencyStrengthPairVoteDao = NULL;
    }

    if (gCurrencyStrengthRunDao != NULL) {
        delete gCurrencyStrengthRunDao;
        gCurrencyStrengthRunDao = NULL;
    }

    if (gCurrencyStrengthDatabase != NULL) {
        gCurrencyStrengthDatabase.close();
        delete gCurrencyStrengthDatabase;
        gCurrencyStrengthDatabase = NULL;
    }

    gLastSavedM15BarTime = 0;
    gLastDatabaseCleanupTime = 0;
}
