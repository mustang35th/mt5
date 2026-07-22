//+------------------------------------------------------------------+
//|                               CurrencyStrengthAllRankHistory.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 16
#property indicator_plots   16
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

#property indicator_label1  "USD Position"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "JPY Position"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrAqua
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "EUR Position"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "GBP Position"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "AUD Position"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

#property indicator_label6  "NZD Position"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrHotPink
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

#property indicator_label7  "CAD Position"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrBlueViolet
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1

#property indicator_label8  "CHF Position"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrBrown
#property indicator_style8  STYLE_SOLID
#property indicator_width8  1

#property indicator_label9  "USD Actual Rank"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "JPY Actual Rank"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "EUR Actual Rank"
#property indicator_type11  DRAW_NONE
#property indicator_label12 "GBP Actual Rank"
#property indicator_type12  DRAW_NONE
#property indicator_label13 "AUD Actual Rank"
#property indicator_type13  DRAW_NONE
#property indicator_label14 "NZD Actual Rank"
#property indicator_type14  DRAW_NONE
#property indicator_label15 "CAD Actual Rank"
#property indicator_type15  DRAW_NONE
#property indicator_label16 "CHF Actual Rank"
#property indicator_type16  DRAW_NONE

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthAllLatestRankLabels.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthAllRankSummaryLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankPeriodLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSourceLabel.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>

/**
 * 全通貨順位履歴に表示する集計期間。
 */
enum CurrencyStrengthAllRankPeriod {
    /** 長中期平均順位を表示する。 */
    CURRENCY_STRENGTH_ALL_RANK_PERIOD_LONG_MEDIUM = 0,

    /** 中短期平均順位を表示する。 */
    CURRENCY_STRENGTH_ALL_RANK_PERIOD_MEDIUM_SHORT = 1
};

input CurrencyStrengthAllRankPeriod rankPeriod =
    CURRENCY_STRENGTH_ALL_RANK_PERIOD_LONG_MEDIUM;
input int historyDays = 30;
input int refreshSeconds = 15;
input int subPanelHeight = 180;
input bool highlightChartCurrencies = true;
input CurrencyStrengthRankDatabaseProfile databaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
input string databaseFileName = "mstng-currency-strength.sqlite";
input bool databaseSplitByYear = true;
input bool databaseUseCommonFolder = true;

double gUsdDisplayRankBuffer[];
double gJpyDisplayRankBuffer[];
double gEurDisplayRankBuffer[];
double gGbpDisplayRankBuffer[];
double gAudDisplayRankBuffer[];
double gNzdDisplayRankBuffer[];
double gCadDisplayRankBuffer[];
double gChfDisplayRankBuffer[];
double gUsdActualRankBuffer[];
double gJpyActualRankBuffer[];
double gEurActualRankBuffer[];
double gGbpActualRankBuffer[];
double gAudActualRankBuffer[];
double gNzdActualRankBuffer[];
double gCadActualRankBuffer[];
double gChfActualRankBuffer[];

Logger gLogger;
CurrencyStrengthYearlyRankQueryService *gRankQueryService = NULL;
DrawCurrencyStrengthAllLatestRankLabels *gLatestRankLabelsDraw = NULL;
DrawCurrencyStrengthAllRankSummaryLabel *gRankSummaryLabelDraw = NULL;
DrawCurrencyStrengthRankPeriodLabel *gRankPeriodLabelDraw = NULL;
DrawCurrencyStrengthRankSourceLabel *gRankSourceLabelDraw = NULL;
CurrencyStrengthAllRankPoint gRankPoints[];
string gBaseCurrency = "";
string gQuoteCurrency = "";
string gCalculationVersion = "";
string gSourceMode = "";
datetime gLastQueryTargetM5BarTime = 0;
datetime gLastDisplayStartM5BarTime = 0;
ulong gLastQueryTickCount = 0;
bool gRankPointCacheReady = false;
bool gRankPeriodLabelReady = false;
bool gRankLabelObjectsPrepared = false;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);

    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthAllRankHistory does not support optimization");

        return INIT_FAILED;
    }

    if (historyDays < 1
            || historyDays > 366
            || refreshSeconds < 1
            || subPanelHeight < 0) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (databaseFileName == "") {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (isTester && !databaseUseCommonFolder) {
        Print(
            "CurrencyStrengthAllRankHistory requires Common database folder "
            + "in Strategy Tester"
        );

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!initializeBuffers()) {
        return INIT_FAILED;
    }

    if (subPanelHeight > 0
            && !IndicatorSetInteger(INDICATOR_HEIGHT, subPanelHeight)) {
        return INIT_FAILED;
    }

    gLogger.setLevel(LOG_INFO);
    gBaseCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    gQuoteCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    StringToUpper(gBaseCurrency);
    StringToUpper(gQuoteCurrency);

    bool useTesterProfile = usesTesterDatabaseProfile(isTester);
    gCalculationVersion =
        CurrencyStrengthCalculationProfile::getCalculationVersion(
            useTesterProfile
        );

    if (usesLiveThenTesterDatabaseProfile()) {
        gSourceMode = "LIVE>TESTER";
    } else {
        gSourceMode = CurrencyStrengthCalculationProfile::getSourceMode(
            useTesterProfile
        );
    }

    configurePlots();
    gRankQueryService = new CurrencyStrengthYearlyRankQueryService(
        databaseFileName,
        databaseSplitByYear,
        databaseUseCommonFolder
    );

    if (gRankQueryService == NULL) {
        return INIT_FAILED;
    }

    string drawObjectSuffix = StringFormat(
        "%d_%I64u",
        (int)rankPeriod,
        GetTickCount64()
    );
    gRankPeriodLabelDraw = new DrawCurrencyStrengthRankPeriodLabel(
        ChartID(),
        drawObjectSuffix
    );
    gLatestRankLabelsDraw = new DrawCurrencyStrengthAllLatestRankLabels(
        ChartID(),
        drawObjectSuffix
    );
    gRankSummaryLabelDraw = new DrawCurrencyStrengthAllRankSummaryLabel(
        ChartID(),
        drawObjectSuffix
    );
    gRankSourceLabelDraw = new DrawCurrencyStrengthRankSourceLabel(
        ChartID(),
        drawObjectSuffix
    );

    if (gRankPeriodLabelDraw == NULL
            || gLatestRankLabelsDraw == NULL
            || gRankSummaryLabelDraw == NULL
            || gRankSourceLabelDraw == NULL) {
        releaseResources();

        return INIT_FAILED;
    }

    ArrayResize(gRankPoints, 0);
    gLastQueryTargetM5BarTime = 0;
    gLastDisplayStartM5BarTime = 0;
    gLastQueryTickCount = 0;
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;

    return INIT_SUCCEEDED;
}

/**
 * インジケーターで使用したリソースを解放する。
 *
 * @param fromReason 終了理由。
 */
void OnDeinit(const int fromReason) {
    releaseResources();
    ArrayFree(gRankPoints);
    gBaseCurrency = "";
    gQuoteCurrency = "";
    gCalculationVersion = "";
    gSourceMode = "";
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;
}

/**
 * DBの全通貨順位履歴をチャート時間へ割り当てる。
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
    if (!gRankLabelObjectsPrepared) {
        gRankLabelObjectsPrepared = clearStaleRankLabelObjects();
    }

    if (!gRankLabelObjectsPrepared) {
        return previousCalculated;
    }

    if (!gRankPeriodLabelReady) {
        gRankPeriodLabelReady = drawRankPeriodLabel();
    }

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
    drawLatestRankLabels(ratesTotal, time);

    return ratesTotal;
}

/**
 * チャート変更時に右端の通貨ラベルを再配置対象にする。
 *
 * @param fromEventId イベントID。
 * @param fromLongParameter long型イベント値。
 * @param fromDoubleParameter double型イベント値。
 * @param fromStringParameter string型イベント値。
 */
void OnChartEvent(
    const int fromEventId,
    const long &fromLongParameter,
    const double &fromDoubleParameter,
    const string &fromStringParameter
) {
    if (fromEventId != CHARTEVENT_CHART_CHANGE) {
        return;
    }

    if (!gRankLabelObjectsPrepared) {
        gRankLabelObjectsPrepared = clearStaleRankLabelObjects();
    }

    if (!gRankLabelObjectsPrepared) {
        return;
    }

    if (gLatestRankLabelsDraw != NULL) {
        gLatestRankLabelsDraw.clear();
    }

    gRankPeriodLabelReady = drawRankPeriodLabel();
}

/**
 * 生成したサービスと描画クラスを解放する。
 */
void releaseResources() {
    if (gRankSourceLabelDraw != NULL) {
        delete gRankSourceLabelDraw;
        gRankSourceLabelDraw = NULL;
    }

    if (gRankSummaryLabelDraw != NULL) {
        delete gRankSummaryLabelDraw;
        gRankSummaryLabelDraw = NULL;
    }

    if (gLatestRankLabelsDraw != NULL) {
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
    }

    if (gRankPeriodLabelDraw != NULL) {
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
    }

    if (gRankQueryService != NULL) {
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;
    }
}

/**
 * 8本の表示バッファと8本の実順位バッファを初期化する。
 *
 * @return 初期化に成功した場合true。
 */
bool initializeBuffers() {
    if (!initializeBuffer(0, gUsdDisplayRankBuffer)
            || !initializeBuffer(1, gJpyDisplayRankBuffer)
            || !initializeBuffer(2, gEurDisplayRankBuffer)
            || !initializeBuffer(3, gGbpDisplayRankBuffer)
            || !initializeBuffer(4, gAudDisplayRankBuffer)
            || !initializeBuffer(5, gNzdDisplayRankBuffer)
            || !initializeBuffer(6, gCadDisplayRankBuffer)
            || !initializeBuffer(7, gChfDisplayRankBuffer)
            || !initializeBuffer(8, gUsdActualRankBuffer)
            || !initializeBuffer(9, gJpyActualRankBuffer)
            || !initializeBuffer(10, gEurActualRankBuffer)
            || !initializeBuffer(11, gGbpActualRankBuffer)
            || !initializeBuffer(12, gAudActualRankBuffer)
            || !initializeBuffer(13, gNzdActualRankBuffer)
            || !initializeBuffer(14, gCadActualRankBuffer)
            || !initializeBuffer(15, gChfActualRankBuffer)) {
        return false;
    }

    for (int i = 0; i < 16; i++) {
        PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
        PlotIndexSetInteger(i, PLOT_SHOW_DATA, i >= 8);
    }

    return true;
}

/**
 * 指定した1次元バッファをインジケーターバッファへ登録する。
 *
 * @param fromIndex バッファ番号。
 * @param fromBuffer 登録する動的配列。
 * @return 登録に成功した場合true。
 */
bool initializeBuffer(const int fromIndex, double &fromBuffer[]) {
    if (!SetIndexBuffer(fromIndex, fromBuffer, INDICATOR_DATA)) {
        return false;
    }

    ArraySetAsSeries(fromBuffer, true);

    return true;
}

/**
 * 全通貨の線名、色、太さを設定する。
 */
void configurePlots() {
    string rankPeriodLabel = getRankPeriodLabel();

    for (int i = 0; i < 8; i++) {
        string currencyName = getCurrencyName(i);
        int lineWidth = 1;

        if (highlightChartCurrencies
                && (currencyName == gBaseCurrency
                    || currencyName == gQuoteCurrency)) {
            lineWidth = 3;
        }

        PlotIndexSetString(
            i,
            PLOT_LABEL,
            currencyName + " " + rankPeriodLabel + " Position"
        );
        PlotIndexSetInteger(
            i,
            PLOT_LINE_COLOR,
            ConstantCurrency::getColor(currencyName)
        );
        PlotIndexSetInteger(i, PLOT_LINE_WIDTH, lineWidth);
        PlotIndexSetString(
            8 + i,
            PLOT_LABEL,
            currencyName + " " + rankPeriodLabel + " Rank"
        );
    }

    IndicatorSetInteger(INDICATOR_DIGITS, 0);
    IndicatorSetString(
        INDICATOR_SHORTNAME,
        StringFormat(
            "Currency Strength All Rank %s %s -1=Top (%d days)",
            gSourceMode,
            rankPeriodLabel,
            historyDays
        )
    );
}

/**
 * 固定順序に対応する通貨コードを取得する。
 *
 * @param fromCurrencyIndex 通貨番号。
 * @return 通貨コード。範囲外の場合は空文字。
 */
string getCurrencyName(const int fromCurrencyIndex) {
    switch (fromCurrencyIndex) {
        case 0:
            return ConstantCurrency::USD;
        case 1:
            return ConstantCurrency::JPY;
        case 2:
            return ConstantCurrency::EUR;
        case 3:
            return ConstantCurrency::GBP;
        case 4:
            return ConstantCurrency::AUD;
        case 5:
            return ConstantCurrency::NZD;
        case 6:
            return ConstantCurrency::CAD;
        case 7:
            return ConstantCurrency::CHF;
    }

    return "";
}

/**
 * 選択中の順位期間を英語表示名へ変換する。
 *
 * @return Long-MediumまたはMedium-Short。
 */
string getRankPeriodLabel() {
    if (rankPeriod == CURRENCY_STRENGTH_ALL_RANK_PERIOD_MEDIUM_SHORT) {
        return "Medium-Short";
    }

    return "Long-Medium";
}

/**
 * 選択中の順位期間をパネル表示名へ変換する。
 *
 * @return 長中期または中短期。
 */
string getRankPeriodDisplayLabel() {
    if (rankPeriod == CURRENCY_STRENGTH_ALL_RANK_PERIOD_MEDIUM_SHORT) {
        return "中短期";
    }

    return "長中期";
}

/**
 * 現在のサブパネルに残っている全通貨順位ラベルを削除する。
 *
 * @return 削除処理に成功した場合true。
 */
bool clearStaleRankLabelObjects() {
    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        return false;
    }

    bool isDeleted = true;

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthAllLatest_",
        subWindow,
        OBJ_TEXT
    ) < 0) {
        isDeleted = false;
    }

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthAllRankSummary_",
        subWindow,
        OBJ_LABEL
    ) < 0) {
        isDeleted = false;
    }

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthRankPeriod_",
        subWindow,
        OBJ_LABEL
    ) < 0) {
        isDeleted = false;
    }

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthRankSource_",
        subWindow,
        OBJ_LABEL
    ) < 0) {
        isDeleted = false;
    }

    if (!isDeleted) {
        gLogger.error(__FUNCTION__, "stale all-rank label cleanup failed");

        return false;
    }

    ChartRedraw(ChartID());

    return true;
}

/**
 * 選択中の順位期間をサブパネル右上へ描画する。
 *
 * @return 描画に成功した場合true。
 */
bool drawRankPeriodLabel() {
    if (gRankPeriodLabelDraw == NULL) {
        return false;
    }

    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        return false;
    }

    return gRankPeriodLabelDraw.draw(
        subWindow,
        getRankPeriodDisplayLabel()
    );
}

/**
 * 最新有効バーの全通貨順位ラベルと概要を描画する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 */
void drawLatestRankLabels(
    const int fromRatesTotal,
    const datetime &fromTime[]
) {
    if (gLatestRankLabelsDraw == NULL || fromRatesTotal <= 0) {
        return;
    }

    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        return;
    }

    int latestBufferIndex = findLatestRankBufferIndex(fromRatesTotal);

    if (latestBufferIndex < 0) {
        int emptyRanks[];
        gLatestRankLabelsDraw.clear();
        drawRankSummaryLabel(subWindow, emptyRanks);
        drawRankSourceLabel(subWindow, "");

        return;
    }

    int ranks[8];

    for (int i = 0; i < 8; i++) {
        ranks[i] = (int)MathRound(
            getActualRankBufferValue(i, latestBufferIndex)
        );
    }

    datetime latestBarTime = fromTime[latestBufferIndex];
    int pointIndex = findRankPointIndex(floorToM5(latestBarTime));

    if (pointIndex >= 0) {
        drawRankSourceLabel(subWindow, gRankPoints[pointIndex].sourceMode);
    } else {
        drawRankSourceLabel(subWindow, "");
    }

    drawRankSummaryLabel(subWindow, ranks);
    int rankOccurrences[9];
    datetime labelTimes[8];
    ArrayInitialize(rankOccurrences, 0);

    for (int i = 0; i < 8; i++) {
        int rank = ranks[i];
        int pixelOffset = 18 + (rankOccurrences[rank] * 48);
        rankOccurrences[rank]++;
        labelTimes[i] = getLatestRankLabelTime(
            subWindow,
            latestBarTime,
            (double)(0 - rank),
            pixelOffset
        );
    }

    if (!gLatestRankLabelsDraw.draw(subWindow, labelTimes, ranks)) {
        gLogger.error(__FUNCTION__, "latest all-rank label draw failed");
    }
}

/**
 * 全通貨実順位が揃う最新バッファ番号を取得する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @return 最新有効バッファ番号。存在しない場合は-1。
 */
int findLatestRankBufferIndex(const int fromRatesTotal) {
    for (int i = 0; i < fromRatesTotal; i++) {
        bool allRanksValid = true;

        for (int j = 0; j < 8; j++) {
            if (!isActualRankBufferValue(
                getActualRankBufferValue(j, i)
            )) {
                allRanksValid = false;

                break;
            }
        }

        if (allRanksValid) {
            return i;
        }
    }

    return -1;
}

/**
 * 最新順位の最上位と最下位を概要ラベルへ描画する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromRanks 全通貨順位。指定されない場合は未取得表示。
 */
void drawRankSummaryLabel(
    const int fromSubWindow,
    const int &fromRanks[]
) {
    if (gRankSummaryLabelDraw == NULL) {
        return;
    }

    string summaryText = "TOP: - / BOTTOM: -";

    if (ArraySize(fromRanks) >= 8) {
        int topRank = 9;
        int bottomRank = 0;

        for (int i = 0; i < 8; i++) {
            if (fromRanks[i] < topRank) {
                topRank = fromRanks[i];
            }

            if (fromRanks[i] > bottomRank) {
                bottomRank = fromRanks[i];
            }
        }

        string topCurrencies = "";
        string bottomCurrencies = "";

        for (int i = 0; i < 8; i++) {
            if (fromRanks[i] == topRank) {
                topCurrencies = appendCurrencyName(
                    topCurrencies,
                    getCurrencyName(i)
                );
            }

            if (fromRanks[i] == bottomRank) {
                bottomCurrencies = appendCurrencyName(
                    bottomCurrencies,
                    getCurrencyName(i)
                );
            }
        }

        summaryText = "TOP: " + topCurrencies
            + " / BOTTOM: " + bottomCurrencies;
    }

    if (!gRankSummaryLabelDraw.draw(
        fromSubWindow,
        summaryText,
        clrWhiteSmoke
    )) {
        gLogger.error(__FUNCTION__, "all-rank summary label draw failed");
    }
}

/**
 * 通貨名一覧へ区切り付きで通貨名を追加する。
 *
 * @param fromCurrentText 現在の一覧文字列。
 * @param fromCurrencyName 追加する通貨名。
 * @return 追加後の文字列。
 */
string appendCurrencyName(
    const string fromCurrentText,
    const string fromCurrencyName
) {
    if (fromCurrentText == "") {
        return fromCurrencyName;
    }

    return fromCurrentText + "," + fromCurrencyName;
}

/**
 * 最新順位の取得元を描画する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromSourceMode 最新順位点の実行モード。
 */
void drawRankSourceLabel(
    const int fromSubWindow,
    const string fromSourceMode
) {
    if (gRankSourceLabelDraw == NULL) {
        return;
    }

    string sourceText = "SOURCE: -";
    color sourceColor = clrDimGray;
    string liveSourceMode =
        CurrencyStrengthCalculationProfile::getSourceMode(false);
    string testerSourceMode =
        CurrencyStrengthCalculationProfile::getSourceMode(true);

    if (fromSourceMode == liveSourceMode) {
        sourceText = "SOURCE: LIVE";
        sourceColor = clrLime;
    } else if (fromSourceMode == testerSourceMode) {
        sourceText = "SOURCE: TESTER";
        sourceColor = clrSilver;
    }

    if (!gRankSourceLabelDraw.draw(
        fromSubWindow,
        sourceText,
        sourceColor
    )) {
        gLogger.error(__FUNCTION__, "all-rank source label draw failed");
    }
}

/**
 * 最新足から指定ピクセル数だけ右側となるラベル時刻を取得する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromBarTime 最新順位を持つバー時刻。
 * @param fromDisplayPosition 順位線の表示位置。
 * @param fromPixelOffset 最新足から右へ離すピクセル数。
 * @return ラベル配置時刻。
 */
datetime getLatestRankLabelTime(
    const int fromSubWindow,
    const datetime fromBarTime,
    const double fromDisplayPosition,
    const int fromPixelOffset
) {
    int barX = 0;
    int barY = 0;

    if (ChartTimePriceToXY(
        ChartID(),
        fromSubWindow,
        fromBarTime,
        fromDisplayPosition,
        barX,
        barY
    )) {
        int resolvedSubWindow = -1;
        datetime resolvedTime = 0;
        double resolvedPosition = 0.0;

        if (ChartXYToTimePrice(
            ChartID(),
            barX + fromPixelOffset,
            barY,
            resolvedSubWindow,
            resolvedTime,
            resolvedPosition
        ) && resolvedSubWindow == fromSubWindow
                && resolvedTime > fromBarTime) {
            return resolvedTime;
        }
    }

    int periodSeconds = PeriodSeconds(_Period);

    if (periodSeconds <= 0) {
        periodSeconds = 60;
    }

    int fallbackBarOffset = 1 + (fromPixelOffset / 48);

    return fromBarTime + (periodSeconds * fallbackBarOffset);
}

/**
 * 指定通貨の実順位バッファ値を取得する。
 *
 * @param fromCurrencyIndex 通貨番号。
 * @param fromBufferIndex バッファ番号。
 * @return 実順位。範囲外の場合は空値。
 */
double getActualRankBufferValue(
    const int fromCurrencyIndex,
    const int fromBufferIndex
) {
    switch (fromCurrencyIndex) {
        case 0:
            return gUsdActualRankBuffer[fromBufferIndex];
        case 1:
            return gJpyActualRankBuffer[fromBufferIndex];
        case 2:
            return gEurActualRankBuffer[fromBufferIndex];
        case 3:
            return gGbpActualRankBuffer[fromBufferIndex];
        case 4:
            return gAudActualRankBuffer[fromBufferIndex];
        case 5:
            return gNzdActualRankBuffer[fromBufferIndex];
        case 6:
            return gCadActualRankBuffer[fromBufferIndex];
        case 7:
            return gChfActualRankBuffer[fromBufferIndex];
    }

    return EMPTY_VALUE;
}

/**
 * データウィンドウ用の実順位が有効か判定する。
 *
 * @param fromValue 判定対象値。
 * @return 1から8の順位の場合true。
 */
bool isActualRankBufferValue(const double fromValue) {
    return fromValue != EMPTY_VALUE
        && fromValue >= 1.0
        && fromValue <= 8.0;
}

/**
 * テスター用DBプロファイルを参照するか判定する。
 *
 * @param fromRuntimeTester ストラテジーテスターで実行中の場合true。
 * @return テスター用DBを参照する場合true。
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
 * LIVE優先・TESTER補完プロファイルか判定する。
 *
 * @return LIVE優先・TESTER補完の場合true。
 */
bool usesLiveThenTesterDatabaseProfile() {
    return databaseProfile
        == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
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
datetime getDisplayStartM5BarTime(
    const datetime fromTargetM5BarTime
) {
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
 * 指定期間の全通貨順位履歴をキャッシュへ反映する。
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

    CurrencyStrengthAllRankPoint queriedPoints[];
    int maximumPointCount = (historyDays * 288) + 2;
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
        CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;

    if (usesLiveThenTesterDatabaseProfile()) {
        queryStatus = gRankQueryService.findAllRankPointsInRangePreferLive(
            queryStartM5BarTime,
            fromTargetM5BarTime,
            gCalculationVersion,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            maximumPointCount,
            queriedPoints
        );
    } else {
        queryStatus = gRankQueryService.findAllRankPointsInRange(
            queryStartM5BarTime,
            fromTargetM5BarTime,
            gCalculationVersion,
            gSourceMode,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            maximumPointCount,
            queriedPoints
        );
    }

    if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
        gLogger.error(
            __FUNCTION__,
            StringFormat(
                "all-rank history query failed. from=%s to=%s",
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
        gLogger.error(__FUNCTION__, "all-rank point cache update failed");

        return false;
    }

    pruneRankPoints(fromDisplayStartM5BarTime);
    gRankPointCacheReady = true;
    fromChangedStartM5BarTime = fromTargetM5BarTime;

    if (initialLoad) {
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "all-rank history loaded. sourceMode=%s points=%d "
                + "from=%s to=%s",
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
 * @param fromPoints 再取得した全通貨順位点。
 * @return 異なる場合true。
 */
bool isCacheRangeChanged(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthAllRankPoint &fromPoints[]
) {
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int cachedTailCount = ArraySize(gRankPoints) - keepCount;
    int queriedPointCount = ArraySize(fromPoints);

    if (cachedTailCount != queriedPointCount) {
        return true;
    }

    for (int i = 0; i < queriedPointCount; i++) {
        CurrencyStrengthAllRankPoint cachedPoint =
            gRankPoints[keepCount + i];
        CurrencyStrengthAllRankPoint queriedPoint = fromPoints[i];

        if (!cachedPoint.isSame(queriedPoint)) {
            return true;
        }
    }

    return false;
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
 * @param fromPoints 置換する全通貨順位点。
 * @return キャッシュ更新に成功した場合true。
 */
bool replaceCacheRange(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthAllRankPoint &fromPoints[]
) {
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int queriedPointCount = ArraySize(fromPoints);
    int nextPointCount = keepCount + queriedPointCount;
    CurrencyStrengthAllRankPoint nextPoints[];

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
 * 表示期間より古い全通貨順位点をキャッシュから削除する。
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
 * 全表示バッファを構築する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
 */
void fillAllBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime
) {
    initializeAllBufferValues();

    for (int i = 0; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromDisplayStartM5BarTime) {
            break;
        }

        setBufferValues(i, barM5Time, fromTargetM5BarTime);
    }
}

/**
 * 全通貨バッファを空値で初期化する。
 */
void initializeAllBufferValues() {
    ArrayInitialize(gUsdDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gJpyDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gEurDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gGbpDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gAudDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gNzdDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gCadDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gChfDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gUsdActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gJpyActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gEurActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gGbpActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gAudActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gNzdActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gCadActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gChfActualRankBuffer, EMPTY_VALUE);
}

/**
 * 新規または再計算対象バーの表示値を設定する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromPreviousCalculated 前回計算済みバー数。
 * @param fromTime チャートバー時刻配列。
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
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
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromChangedStartM5BarTime 変更範囲開始M5時刻。
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
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
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromPreviousStartM5BarTime 前回表示開始M5時刻。
 * @param fromDisplayStartM5BarTime 現在表示開始M5時刻。
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
 * 指定バーへ全8通貨の順位を一括設定する。
 *
 * 一つでも無効な順位があれば全16バッファを空値にする。
 *
 * @param fromBufferIndex 設定対象バッファ番号。
 * @param fromBarM5Time 対応するM5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
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

    CurrencyStrengthAllRankPoint point = gRankPoints[pointIndex];

    if (!point.isValid()) {
        clearBufferValues(fromBufferIndex);

        return;
    }

    int ranks[8];

    for (int i = 0; i < 8; i++) {
        string currencyName = getCurrencyName(i);
        ranks[i] = point.getLongMediumRank(currencyName);

        if (rankPeriod
                == CURRENCY_STRENGTH_ALL_RANK_PERIOD_MEDIUM_SHORT) {
            ranks[i] = point.getMediumShortRank(currencyName);
        }

        if (ranks[i] < 1 || ranks[i] > 8) {
            clearBufferValues(fromBufferIndex);

            return;
        }
    }

    for (int i = 0; i < 8; i++) {
        setDisplayRankBufferValue(
            i,
            fromBufferIndex,
            getDisplayRankValue(ranks[i])
        );
        setActualRankBufferValue(
            i,
            fromBufferIndex,
            getActualRankValue(ranks[i])
        );
    }
}

/**
 * 指定バーの全16バッファを空値へ戻す。
 *
 * @param fromBufferIndex 対象バッファ番号。
 */
void clearBufferValues(const int fromBufferIndex) {
    for (int i = 0; i < 8; i++) {
        setDisplayRankBufferValue(i, fromBufferIndex, EMPTY_VALUE);
        setActualRankBufferValue(i, fromBufferIndex, EMPTY_VALUE);
    }
}

/**
 * 指定通貨の表示順位バッファへ値を設定する。
 *
 * @param fromCurrencyIndex 通貨番号。
 * @param fromBufferIndex バッファ番号。
 * @param fromValue 設定値。
 */
void setDisplayRankBufferValue(
    const int fromCurrencyIndex,
    const int fromBufferIndex,
    const double fromValue
) {
    switch (fromCurrencyIndex) {
        case 0:
            gUsdDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 1:
            gJpyDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 2:
            gEurDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 3:
            gGbpDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 4:
            gAudDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 5:
            gNzdDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 6:
            gCadDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 7:
            gChfDisplayRankBuffer[fromBufferIndex] = fromValue;
            break;
    }
}

/**
 * 指定通貨の実順位バッファへ値を設定する。
 *
 * @param fromCurrencyIndex 通貨番号。
 * @param fromBufferIndex バッファ番号。
 * @param fromValue 設定値。
 */
void setActualRankBufferValue(
    const int fromCurrencyIndex,
    const int fromBufferIndex,
    const double fromValue
) {
    switch (fromCurrencyIndex) {
        case 0:
            gUsdActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 1:
            gJpyActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 2:
            gEurActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 3:
            gGbpActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 4:
            gAudActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 5:
            gNzdActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 6:
            gCadActualRankBuffer[fromBufferIndex] = fromValue;
            break;
        case 7:
            gChfActualRankBuffer[fromBufferIndex] = fromValue;
            break;
    }
}

/**
 * M5時刻が完全一致する全通貨順位点を二分検索する。
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
 * @return 1位を-1、8位を-8とした表示位置。無効時は空値。
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
 * @return 1から8の実順位。無効時は空値。
 */
double getActualRankValue(const int fromRank) {
    if (fromRank < 1 || fromRank > 8) {
        return EMPTY_VALUE;
    }

    return (double)fromRank;
}
