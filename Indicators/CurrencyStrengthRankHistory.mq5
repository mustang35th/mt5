//+------------------------------------------------------------------+
//|                          CurrencyStrengthRankHistory.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4
#property indicator_minimum -8.5
#property indicator_maximum -0.5
#property indicator_level1  -1.0
#property indicator_level2  -2.0
#property indicator_level3  -3.0
#property indicator_level4  -4.0
#property indicator_level5  -5.0
#property indicator_level6  -6.0
#property indicator_level7  -7.0
#property indicator_level8  -8.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

#property indicator_label1  "Base Rank"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrWhite
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Quote Rank"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrWhite
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "Base Actual Rank"
#property indicator_type3   DRAW_NONE

#property indicator_label4  "Quote Actual Rank"
#property indicator_type4   DRAW_NONE

#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>

/**
 * 通貨強弱順位の参照元DBプロファイル。
 */
enum CurrencyStrengthRankDatabaseProfile {
    /** テスターで保存した過去集計を参照する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER = 0,

    /** ライブ実行で保存した集計を参照する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE = 1,

    /** インジケータの実行環境に合わせて自動選択する。 */
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_AUTO = 2
};

/**
 * サブパネルへ表示する通貨強弱順位の期間。
 */
enum CurrencyStrengthRankPeriod {
    /** 長中期平均順位を表示する。 */
    CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM = 0,

    /** 中短期平均順位を表示する。 */
    CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT = 1
};

input CurrencyStrengthRankPeriod rankPeriod =
    CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM;
input int historyDays = 30;
input int refreshSeconds = 15;
input CurrencyStrengthRankDatabaseProfile databaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER;
input string databaseFileName = "mstng-currency-strength.sqlite";
input bool databaseSplitByYear = true;
input bool databaseUseCommonFolder = true;

double gBaseDisplayRankBuffer[];
double gQuoteDisplayRankBuffer[];
double gBaseActualRankBuffer[];
double gQuoteActualRankBuffer[];

Logger gLogger;
CurrencyStrengthYearlyRankQueryService *gRankQueryService = NULL;
CurrencyStrengthPairRankPoint gRankPoints[];
string gBaseCurrency = "";
string gQuoteCurrency = "";
string gCalculationVersion = "";
string gSourceMode = "";
datetime gLastQueryTargetM5BarTime = 0;
datetime gLastDisplayStartM5BarTime = 0;
ulong gLastQueryTickCount = 0;
bool gRankPointCacheReady = false;

/**
 * インジケータを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);

    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthRankHistory does not support optimization");

        return INIT_FAILED;
    }

    if (historyDays < 1 || historyDays > 366 || refreshSeconds < 1) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (databaseFileName == "") {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (isTester && !databaseUseCommonFolder) {
        Print(
            "CurrencyStrengthRankHistory requires Common database folder "
            + "in Strategy Tester"
        );

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!initializeBuffers()) {
        return INIT_FAILED;
    }

    gLogger.setLevel(LOG_INFO);
    gBaseCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    gQuoteCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

    if (gBaseCurrency == "" || gQuoteCurrency == "") {
        gLogger.error(
            __FUNCTION__,
            StringFormat(
                "symbol currency resolution failed. symbol=%s base=%s quote=%s",
                _Symbol,
                gBaseCurrency,
                gQuoteCurrency
            )
        );

        return INIT_FAILED;
    }

    bool useTesterProfile = usesTesterDatabaseProfile(isTester);
    gCalculationVersion =
        CurrencyStrengthCalculationProfile::getCalculationVersion(
            useTesterProfile
        );
    gSourceMode = CurrencyStrengthCalculationProfile::getSourceMode(
        useTesterProfile
    );
    configurePlots();

    gRankQueryService = new CurrencyStrengthYearlyRankQueryService(
        databaseFileName,
        databaseSplitByYear,
        databaseUseCommonFolder
    );

    if (gRankQueryService == NULL) {
        return INIT_FAILED;
    }

    ArrayResize(gRankPoints, 0);
    gLastQueryTargetM5BarTime = 0;
    gLastDisplayStartM5BarTime = 0;
    gLastQueryTickCount = 0;
    gRankPointCacheReady = false;

    return INIT_SUCCEEDED;
}

/**
 * インジケータで使用したリソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    if (gRankQueryService != NULL) {
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;
    }

    ArrayFree(gRankPoints);
    gCalculationVersion = "";
    gSourceMode = "";
    gRankPointCacheReady = false;
}

/**
 * DBの順位履歴をチャート時間へ割り当てる。
 *
 * @return 計算済みバー数。
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
    if (ratesTotal <= 0 || gRankQueryService == NULL) {
        return 0;
    }

    ArraySetAsSeries(time, true);

    datetime targetM5BarTime = getTargetM5BarTime(time[0]);

    if (targetM5BarTime <= 0) {
        return previousCalculated;
    }

    datetime displayStartM5BarTime = getDisplayStartM5BarTime(
        targetM5BarTime
    );
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
    bool cacheRefreshed = false;
    datetime changedStartM5BarTime = targetM5BarTime;

    if (shouldRefreshRankPoints(targetM5BarTime, isTester)) {
        cacheRefreshed = refreshRankPoints(
            displayStartM5BarTime,
            targetM5BarTime,
            changedStartM5BarTime
        );
    }

    bool fullRefresh = previousCalculated <= 0
        || previousCalculated > ratesTotal
        || gLastDisplayStartM5BarTime <= 0
        || displayStartM5BarTime < gLastDisplayStartM5BarTime;

    if (fullRefresh) {
        fillAllBuffers(
            ratesTotal,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );
    } else {
        fillNewBars(
            ratesTotal,
            previousCalculated,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );

        if (cacheRefreshed) {
            fillChangedBuffers(
                ratesTotal,
                time,
                changedStartM5BarTime,
                displayStartM5BarTime,
                targetM5BarTime
            );
        }

        clearExpiredBuffers(
            ratesTotal,
            time,
            gLastDisplayStartM5BarTime,
            displayStartM5BarTime
        );
    }

    gLastDisplayStartM5BarTime = displayStartM5BarTime;

    return ratesTotal;
}

/**
 * 2本の表示バッファと2本の実順位バッファを初期化する。
 *
 * @return 初期化に成功した場合true。
 */
bool initializeBuffers() {
    if (!SetIndexBuffer(
        0,
        gBaseDisplayRankBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        1,
        gQuoteDisplayRankBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        2,
        gBaseActualRankBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        3,
        gQuoteActualRankBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    ArraySetAsSeries(gBaseDisplayRankBuffer, true);
    ArraySetAsSeries(gQuoteDisplayRankBuffer, true);
    ArraySetAsSeries(gBaseActualRankBuffer, true);
    ArraySetAsSeries(gQuoteActualRankBuffer, true);

    for (int i = 0; i < 4; i++) {
        PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    }

    PlotIndexSetInteger(0, PLOT_SHOW_DATA, false);
    PlotIndexSetInteger(1, PLOT_SHOW_DATA, false);
    PlotIndexSetInteger(2, PLOT_SHOW_DATA, true);
    PlotIndexSetInteger(3, PLOT_SHOW_DATA, true);

    return true;
}

/**
 * 表示中通貨ペアに合わせて線の名前と色を設定する。
 */
void configurePlots() {
    color baseColor = ConstantCurrency::getColor(gBaseCurrency);
    color quoteColor = ConstantCurrency::getColor(gQuoteCurrency);
    string rankPeriodLabel = getRankPeriodLabel();

    PlotIndexSetString(
        0,
        PLOT_LABEL,
        gBaseCurrency + " " + rankPeriodLabel + " Position"
    );
    PlotIndexSetString(
        1,
        PLOT_LABEL,
        gQuoteCurrency + " " + rankPeriodLabel + " Position"
    );
    PlotIndexSetString(
        2,
        PLOT_LABEL,
        gBaseCurrency + " " + rankPeriodLabel + " Rank"
    );
    PlotIndexSetString(
        3,
        PLOT_LABEL,
        gQuoteCurrency + " " + rankPeriodLabel + " Rank"
    );

    PlotIndexSetInteger(0, PLOT_LINE_COLOR, baseColor);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, quoteColor);

    IndicatorSetInteger(INDICATOR_DIGITS, 0);
    IndicatorSetString(
        INDICATOR_SHORTNAME,
        StringFormat(
            "Currency Strength Rank %s/%s %s %s -1=Top (%d days)",
            gBaseCurrency,
            gQuoteCurrency,
            gSourceMode,
            rankPeriodLabel,
            historyDays
        )
    );

    configureRankLevelLabels();
}

/**
 * 負数へ変換した描画位置へ実順位の水平レベル名を設定する。
 */
void configureRankLevelLabels() {
    for (int i = 0; i < 8; i++) {
        int actualRank = i + 1;
        string levelText = StringFormat("Rank %d", actualRank);

        if (actualRank == 1) {
            levelText += " Top";
        }

        IndicatorSetString(INDICATOR_LEVELTEXT, i, levelText);
    }
}

/**
 * 選択中の順位期間を表示文字列へ変換する。
 *
 * @return Long-MediumまたはMedium-Short。
 */
string getRankPeriodLabel() {
    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT) {
        return "Medium-Short";
    }

    return "Long-Medium";
}

/**
 * テスター用DBプロファイルを参照するか判定する。
 *
 * @param fromRuntimeTester ストラテジーテスターで実行中の場合true。
 * @return テスター用DBプロファイルを参照する場合true。
 */
bool usesTesterDatabaseProfile(const bool fromRuntimeTester) {
    if (databaseProfile
            == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER) {
        return true;
    }

    if (databaseProfile == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE) {
        return false;
    }

    return fromRuntimeTester;
}

/**
 * 現在時刻を超えないDB検索上限M5時刻を取得する。
 *
 * @param fromCurrentBarTime 現在チャートバーの開始時刻。
 * @return DB検索上限となるM5バー開始時刻。
 */
datetime getTargetM5BarTime(const datetime fromCurrentBarTime) {
    datetime currentTime = TimeCurrent();

    if (currentTime <= 0) {
        currentTime = fromCurrentBarTime;
    }

    return floorToM5(currentTime);
}

/**
 * 表示開始M5時刻を取得する。
 *
 * @param fromTargetM5BarTime 表示終端となるM5バー時刻。
 * @return 表示開始M5時刻。
 */
datetime getDisplayStartM5BarTime(const datetime fromTargetM5BarTime) {
    long historySeconds = (long)historyDays * 24 * 60 * 60;
    long startSeconds = (long)fromTargetM5BarTime - historySeconds;

    if (startSeconds <= 0) {
        return 0;
    }

    return (datetime)startSeconds;
}

/**
 * 日時をM5バー開始時刻へ切り下げる。
 *
 * @param fromTime 切り下げ対象時刻。
 * @return M5バー開始時刻。
 */
datetime floorToM5(const datetime fromTime) {
    int m5Seconds = PeriodSeconds(PERIOD_M5);

    if (fromTime <= 0 || m5Seconds <= 0) {
        return 0;
    }

    long timeSeconds = (long)fromTime;

    return (datetime)(timeSeconds - (timeSeconds % m5Seconds));
}

/**
 * DB順位履歴を再取得する時刻か判定する。
 *
 * @param fromTargetM5BarTime 現在の検索上限M5時刻。
 * @param fromTester ストラテジーテスターの場合true。
 * @return 再取得する場合true。
 */
bool shouldRefreshRankPoints(
    const datetime fromTargetM5BarTime,
    const bool fromTester
) {
    if (gLastQueryTargetM5BarTime <= 0) {
        return true;
    }

    if (fromTester) {
        return fromTargetM5BarTime != gLastQueryTargetM5BarTime;
    }

    if (fromTargetM5BarTime != gLastQueryTargetM5BarTime) {
        return true;
    }

    ulong currentTickCount = GetTickCount64();
    ulong refreshMilliseconds = (ulong)refreshSeconds * 1000;

    return currentTickCount - gLastQueryTickCount >= refreshMilliseconds;
}

/**
 * 指定期間のDB順位履歴をキャッシュへ反映する。
 *
 * 初回は期間全体、2回目以降はキャッシュ末尾M5を含む範囲を取得する。
 *
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
 * @param fromChangedStartM5BarTime 変更確認範囲の開始M5時刻。
 * @return DB検索に成功した場合true。
 */
bool refreshRankPoints(
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime,
    datetime &fromChangedStartM5BarTime
) {
    gLastQueryTargetM5BarTime = fromTargetM5BarTime;
    gLastQueryTickCount = GetTickCount64();

    datetime queryStartM5BarTime = fromDisplayStartM5BarTime;
    int cachedPointCount = ArraySize(gRankPoints);

    if (gRankPointCacheReady && cachedPointCount > 0) {
        datetime lastCachedM5BarTime =
            gRankPoints[cachedPointCount - 1].m5BarTime;

        if (lastCachedM5BarTime >= fromDisplayStartM5BarTime
                && lastCachedM5BarTime <= fromTargetM5BarTime) {
            queryStartM5BarTime = lastCachedM5BarTime;
        }
    }

    CurrencyStrengthPairRankPoint queriedPoints[];
    int maximumPointCount = (historyDays * 288) + 2;

    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
        gRankQueryService.findPairRankPointsInRange(
            queryStartM5BarTime,
            fromTargetM5BarTime,
            gCalculationVersion,
            gSourceMode,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            gBaseCurrency,
            gQuoteCurrency,
            maximumPointCount,
            queriedPoints
        );

    if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
        gLogger.error(
            __FUNCTION__,
            StringFormat(
                "rank history query failed. from=%s to=%s",
                TimeToString(queryStartM5BarTime, TIME_DATE | TIME_MINUTES),
                TimeToString(fromTargetM5BarTime, TIME_DATE | TIME_MINUTES)
            )
        );

        return false;
    }

    bool initialLoad = !gRankPointCacheReady;
    bool rangeChanged = isCacheRangeChanged(
        queryStartM5BarTime,
        queriedPoints
    );

    if (!replaceCacheRange(queryStartM5BarTime, queriedPoints)) {
        gLogger.error(__FUNCTION__, "rank point cache update failed");

        return false;
    }

    pruneRankPoints(fromDisplayStartM5BarTime);
    gRankPointCacheReady = true;
    fromChangedStartM5BarTime = fromTargetM5BarTime;

    if (initialLoad) {
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "rank history loaded. sourceMode=%s points=%d from=%s to=%s",
                gSourceMode,
                ArraySize(gRankPoints),
                TimeToString(
                    fromDisplayStartM5BarTime,
                    TIME_DATE | TIME_MINUTES
                ),
                TimeToString(
                    fromTargetM5BarTime,
                    TIME_DATE | TIME_MINUTES
                )
            )
        );
    }

    if (rangeChanged) {
        fromChangedStartM5BarTime = queryStartM5BarTime;
    }

    return true;
}

/**
 * 再取得範囲の内容が現在のキャッシュと異なるか判定する。
 *
 * @param fromRangeStartM5BarTime 再取得範囲の開始M5時刻。
 * @param fromPoints 再取得した順位履歴。
 * @return 異なる場合true。
 */
bool isCacheRangeChanged(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthPairRankPoint &fromPoints[]
) {
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int cachedTailCount = ArraySize(gRankPoints) - keepCount;
    int queriedPointCount = ArraySize(fromPoints);

    if (cachedTailCount != queriedPointCount) {
        return true;
    }

    for (int i = 0; i < queriedPointCount; i++) {
        CurrencyStrengthPairRankPoint cachedPoint = gRankPoints[keepCount + i];
        CurrencyStrengthPairRankPoint queriedPoint = fromPoints[i];

        if (!isSameRankPoint(cachedPoint, queriedPoint)) {
            return true;
        }
    }

    return false;
}

/**
 * 2つの順位履歴点が同じか判定する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @return 同じ場合true。
 */
bool isSameRankPoint(
    CurrencyStrengthPairRankPoint &fromLeft,
    CurrencyStrengthPairRankPoint &fromRight
) {
    return fromLeft.runId == fromRight.runId
        && fromLeft.m5BarTime == fromRight.m5BarTime
        && fromLeft.updatedAt == fromRight.updatedAt
        && fromLeft.baseLongMediumTermAverageRank
            == fromRight.baseLongMediumTermAverageRank
        && fromLeft.baseMediumShortTermAverageRank
            == fromRight.baseMediumShortTermAverageRank
        && fromLeft.quoteLongMediumTermAverageRank
            == fromRight.quoteLongMediumTermAverageRank
        && fromLeft.quoteMediumShortTermAverageRank
            == fromRight.quoteMediumShortTermAverageRank;
}

/**
 * 再取得範囲より前にあるキャッシュ件数を取得する。
 *
 * @param fromRangeStartM5BarTime 再取得範囲の開始M5時刻。
 * @return 保持するキャッシュ件数。
 */
int getCacheKeepCount(const datetime fromRangeStartM5BarTime) {
    int pointCount = ArraySize(gRankPoints);
    int keepCount = 0;

    while (keepCount < pointCount
            && gRankPoints[keepCount].m5BarTime < fromRangeStartM5BarTime) {
        keepCount++;
    }

    return keepCount;
}

/**
 * 指定範囲以降のキャッシュを検索結果で置き換える。
 *
 * @param fromRangeStartM5BarTime 置換範囲の開始M5時刻。
 * @param fromPoints 置換する順位履歴。
 * @return キャッシュ更新に成功した場合true。
 */
bool replaceCacheRange(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthPairRankPoint &fromPoints[]
) {
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int queriedPointCount = ArraySize(fromPoints);
    int nextPointCount = keepCount + queriedPointCount;
    CurrencyStrengthPairRankPoint nextPoints[];

    if (ArrayResize(nextPoints, nextPointCount) != nextPointCount) {
        return false;
    }

    for (int i = 0; i < keepCount; i++) {
        nextPoints[i] = gRankPoints[i];
    }

    for (int i = 0; i < queriedPointCount; i++) {
        nextPoints[keepCount + i] = fromPoints[i];
    }

    if (ArrayResize(gRankPoints, nextPointCount) != nextPointCount) {
        return false;
    }

    for (int i = 0; i < nextPointCount; i++) {
        gRankPoints[i] = nextPoints[i];
    }

    return true;
}

/**
 * 表示期間より古い順位履歴点をキャッシュから削除する。
 *
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 */
void pruneRankPoints(const datetime fromDisplayStartM5BarTime) {
    int pointCount = ArraySize(gRankPoints);
    int firstPointIndex = 0;

    while (firstPointIndex < pointCount
            && gRankPoints[firstPointIndex].m5BarTime
                < fromDisplayStartM5BarTime) {
        firstPointIndex++;
    }

    if (firstPointIndex <= 0) {
        return;
    }

    int nextPointCount = pointCount - firstPointIndex;

    for (int i = 0; i < nextPointCount; i++) {
        gRankPoints[i] = gRankPoints[firstPointIndex + i];
    }

    ArrayResize(gRankPoints, nextPointCount);
}

/**
 * 全表示バッファを再構築する。
 */
void fillAllBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime
) {
    ArrayInitialize(gBaseDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gQuoteDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gBaseActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gQuoteActualRankBuffer, EMPTY_VALUE);

    for (int i = 0; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromDisplayStartM5BarTime) {
            break;
        }

        setBufferValues(i, barM5Time, fromTargetM5BarTime);
    }
}

/**
 * 新規・再計算対象バーの表示値を設定する。
 */
void fillNewBars(
    const int fromRatesTotal,
    const int fromPreviousCalculated,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime
) {
    int calculationCount = fromRatesTotal - fromPreviousCalculated + 1;

    if (calculationCount < 1) {
        calculationCount = 1;
    }

    if (calculationCount > fromRatesTotal) {
        calculationCount = fromRatesTotal;
    }

    for (int i = 0; i < calculationCount; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromDisplayStartM5BarTime) {
            clearBufferValues(i);

            continue;
        }

        setBufferValues(i, barM5Time, fromTargetM5BarTime);
    }
}

/**
 * DB再取得で変更された範囲の表示値を更新する。
 */
void fillChangedBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromChangedStartM5BarTime,
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime
) {
    for (int i = 0; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromChangedStartM5BarTime
                || barM5Time < fromDisplayStartM5BarTime) {
            break;
        }

        setBufferValues(i, barM5Time, fromTargetM5BarTime);
    }
}

/**
 * 表示期間から外れたバーを空値へ戻す。
 */
void clearExpiredBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromPreviousStartM5BarTime,
    const datetime fromDisplayStartM5BarTime
) {
    if (fromPreviousStartM5BarTime <= 0
            || fromDisplayStartM5BarTime <= fromPreviousStartM5BarTime) {
        return;
    }

    int boundaryIndex = iBarShift(
        _Symbol,
        _Period,
        fromDisplayStartM5BarTime,
        false
    );

    if (boundaryIndex < 0) {
        return;
    }

    for (int i = boundaryIndex; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromPreviousStartM5BarTime) {
            break;
        }

        if (barM5Time < fromDisplayStartM5BarTime) {
            clearBufferValues(i);
        }
    }
}

/**
 * 指定バーへ対応するM5順位を設定する。
 */
void setBufferValues(
    const int fromBufferIndex,
    const datetime fromBarM5Time,
    const datetime fromTargetM5BarTime
) {
    if (fromBarM5Time <= 0 || fromBarM5Time > fromTargetM5BarTime) {
        clearBufferValues(fromBufferIndex);

        return;
    }

    int pointIndex = findRankPointIndex(fromBarM5Time);

    if (pointIndex < 0) {
        clearBufferValues(fromBufferIndex);

        return;
    }

    CurrencyStrengthPairRankPoint point = gRankPoints[pointIndex];
    int baseRank = point.baseLongMediumTermAverageRank;
    int quoteRank = point.quoteLongMediumTermAverageRank;

    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT) {
        baseRank = point.baseMediumShortTermAverageRank;
        quoteRank = point.quoteMediumShortTermAverageRank;
    }

    gBaseDisplayRankBuffer[fromBufferIndex] = getDisplayRankValue(baseRank);
    gQuoteDisplayRankBuffer[fromBufferIndex] = getDisplayRankValue(quoteRank);
    gBaseActualRankBuffer[fromBufferIndex] = getActualRankValue(baseRank);
    gQuoteActualRankBuffer[fromBufferIndex] = getActualRankValue(quoteRank);
}

/**
 * 指定バーの表示値と実順位を空値へ戻す。
 */
void clearBufferValues(const int fromBufferIndex) {
    gBaseDisplayRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gQuoteDisplayRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gBaseActualRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gQuoteActualRankBuffer[fromBufferIndex] = EMPTY_VALUE;
}

/**
 * M5時刻が完全一致する順位履歴点を二分検索する。
 *
 * @param fromM5BarTime 検索対象M5時刻。
 * @return 一致した配列位置。存在しない場合は-1。
 */
int findRankPointIndex(const datetime fromM5BarTime) {
    int leftIndex = 0;
    int rightIndex = ArraySize(gRankPoints) - 1;

    while (leftIndex <= rightIndex) {
        int middleIndex = leftIndex + ((rightIndex - leftIndex) / 2);
        datetime pointM5BarTime = gRankPoints[middleIndex].m5BarTime;

        if (pointM5BarTime == fromM5BarTime) {
            return middleIndex;
        }

        if (pointM5BarTime < fromM5BarTime) {
            leftIndex = middleIndex + 1;
        } else {
            rightIndex = middleIndex - 1;
        }
    }

    return -1;
}

/**
 * DB順位を1位が上になる表示位置へ変換する。
 *
 * @param fromRank DB順位。
 * @return 1位を-1、8位を-8とした表示位置。それ以外は空値。
 */
double getDisplayRankValue(const int fromRank) {
    if (fromRank < 1 || fromRank > 8) {
        return EMPTY_VALUE;
    }

    return (double)(0 - fromRank);
}

/**
 * DB順位をデータウィンドウ用の実順位へ変換する。
 *
 * @param fromRank DB順位。
 * @return 1～8の場合は実順位、それ以外は空値。
 */
double getActualRankValue(const int fromRank) {
    if (fromRank < 1 || fromRank > 8) {
        return EMPTY_VALUE;
    }

    return (double)fromRank;
}
