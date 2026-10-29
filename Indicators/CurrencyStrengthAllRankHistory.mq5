//+------------------------------------------------------------------+
//|                               CurrencyStrengthAllRankHistory.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.12"
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
#include <Mstng\Draw\ChartRedrawRequest.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthAllLatestRankLabels.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthAllRankSummaryLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankPeriodLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSourceLabel.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Util\Util.mqh>

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
input CurrencyStrengthVoteWeightMode voteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
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

/** ラベルの変更・削除による再描画要求をイベントごとに集約する。 */
ChartRedrawRequest gChartRedrawRequest;

CurrencyStrengthYearlyRankQueryService *gRankQueryService = NULL;
DrawCurrencyStrengthAllLatestRankLabels *gLatestRankLabelsDraw = NULL;
DrawCurrencyStrengthAllRankSummaryLabel *gRankSummaryLabelDraw = NULL;
DrawCurrencyStrengthRankPeriodLabel *gRankPeriodLabelDraw = NULL;
DrawCurrencyStrengthRankSourceLabel *gRankSourceLabelDraw = NULL;
CurrencyStrengthAllRankPoint gRankPoints[];

/** 期限切れの先頭部分を除いた、参照対象の開始位置。 */
int gRankPointStartIndex = 0;

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

/** 前回計算したチャートの最新バー時刻。 */
datetime gLastCalculatedBarTime = 0;

/** 最新有効順位を表示するチャートバー時刻。 */
datetime gLatestRankBarTime = 0;

/** 最新有効バーの全8通貨順位。 */
int gLatestRanks[8];

/** 最新有効順位の取得元。 */
string gLatestRankSourceMode = "";

/** 最新順位ラベルの再配置・再試行が必要な場合true。 */
bool gLatestRankLabelsDirty = false;

/** 期限切れ履歴の前詰めをまとめる件数。M5の1日分。 */
const int rankPointCompactThreshold = 288;

/** 履歴配列の拡張時に追加確保する予備件数。M5の1日分。 */
const int rankPointReserveCount = 288;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    bool isTester = Util::isStrategyTester();

    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthAllRankHistory does not support optimization");

        return INIT_FAILED;
    }

    if (historyDays < 1
            || historyDays > 366
            || refreshSeconds < 1
            || subPanelHeight < 0
            || !CurrencyStrengthCalculationProfile::isVoteWeightModeValid(
                voteWeightMode
            )) {
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
            useTesterProfile,
            voteWeightMode
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
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );
    gLatestRankLabelsDraw = new DrawCurrencyStrengthAllLatestRankLabels(
        ChartID(),
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );
    gRankSummaryLabelDraw = new DrawCurrencyStrengthAllRankSummaryLabel(
        ChartID(),
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );
    gRankSourceLabelDraw = new DrawCurrencyStrengthRankSourceLabel(
        ChartID(),
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );

    if (gRankPeriodLabelDraw == NULL
            || gLatestRankLabelsDraw == NULL
            || gRankSummaryLabelDraw == NULL
            || gRankSourceLabelDraw == NULL) {
        releaseResources();
        gChartRedrawRequest.flush(ChartID());

        return INIT_FAILED;
    }

    ArrayResize(gRankPoints, 0);
    gRankPointStartIndex = 0;
    gLastQueryTargetM5BarTime = 0;
    gLastDisplayStartM5BarTime = 0;
    gLastQueryTickCount = 0;
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;

    gLastCalculatedBarTime = 0;
    gLatestRankBarTime = 0;
    ArrayInitialize(gLatestRanks, 0);
    gLatestRankSourceMode = "";
    gLatestRankLabelsDirty = false;

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
    gRankPointStartIndex = 0;
    gBaseCurrency = "";
    gQuoteCurrency = "";
    gCalculationVersion = "";
    gSourceMode = "";
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;

    gLastCalculatedBarTime = 0;
    gLatestRankBarTime = 0;
    ArrayInitialize(gLatestRanks, 0);
    gLatestRankSourceMode = "";
    gLatestRankLabelsDirty = false;
    gChartRedrawRequest.flush(ChartID());
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
        gChartRedrawRequest.flush(ChartID());

        return previousCalculated;
    }

    if (!gRankPeriodLabelReady) {
        gRankPeriodLabelReady = drawRankPeriodLabel();
    }

    if (ratesTotal <= 0 || gRankQueryService == NULL) {
        gChartRedrawRequest.flush(ChartID());

        return 0;
    }

    ArraySetAsSeries(time, true);
    datetime targetM5BarTime = getTargetM5BarTime(time[0]);

    if (targetM5BarTime <= 0) {
        gChartRedrawRequest.flush(ChartID());

        return previousCalculated;
    }

    datetime displayStartM5BarTime = getDisplayStartM5BarTime(
        targetM5BarTime
    );
    bool isTester = Util::isStrategyTester();
    bool dataChanged = false;
    datetime changedStartM5BarTime = targetM5BarTime;

    if (shouldRefreshRankPoints(targetM5BarTime, isTester)) {
        refreshRankPoints(
            displayStartM5BarTime,
            targetM5BarTime,
            changedStartM5BarTime,
            dataChanged
        );
    }

    bool fullRefresh = previousCalculated <= 0
        || previousCalculated > ratesTotal
        || gLastDisplayStartM5BarTime <= 0
        || displayStartM5BarTime < gLastDisplayStartM5BarTime;
    bool chartBarChanged = time[0] != gLastCalculatedBarTime
        || ratesTotal != previousCalculated;
    bool displayRangeChanged = displayStartM5BarTime != gLastDisplayStartM5BarTime;

    if (!fullRefresh && !dataChanged && !chartBarChanged && !displayRangeChanged) {
        if (gLatestRankLabelsDirty) {
            drawCachedLatestRankLabels();
        }

        gChartRedrawRequest.flush(ChartID());

        return ratesTotal;
    }

    if (fullRefresh) {
        fillAllBuffers(
            ratesTotal,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );
    } else {
        int updatedBarCount = fillNewBars(
            ratesTotal,
            previousCalculated,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );

        if (dataChanged) {
            fillChangedBuffers(
                ratesTotal,
                time,
                changedStartM5BarTime,
                displayStartM5BarTime,
                targetM5BarTime,
                updatedBarCount
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
    gLastCalculatedBarTime = time[0];
    drawLatestRankLabels(ratesTotal, time, displayStartM5BarTime);
    gChartRedrawRequest.flush(ChartID());

    return ratesTotal;
}

/**
 * チャート変更時に保持した最新順位から右端の通貨ラベルを再配置する。
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
        gChartRedrawRequest.flush(ChartID());

        return;
    }

    if (!gRankLabelObjectsPrepared) {
        gRankLabelObjectsPrepared = clearStaleRankLabelObjects();
    }

    if (!gRankLabelObjectsPrepared) {
        gChartRedrawRequest.flush(ChartID());

        return;
    }

    gRankPeriodLabelReady = drawRankPeriodLabel();
    gLatestRankLabelsDirty = true;
    drawCachedLatestRankLabels();
    gChartRedrawRequest.flush(ChartID());
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
            "Currency Strength All Rank %s %s %s -1=Top (%d days)",
            gSourceMode,
            CurrencyStrengthCalculationProfile::getVoteWeightModeText(
                voteWeightMode
            ),
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
    gChartRedrawRequest.request();

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

    string labelText = getRankPeriodDisplayLabel()
        + " / "
        + CurrencyStrengthCalculationProfile::getVoteWeightModeText(
            voteWeightMode
        );

    return gRankPeriodLabelDraw.draw(
        subWindow,
        labelText
    );
}

/**
 * 最新有効バーの全通貨順位と取得元を保持し、ラベルと概要を描画する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromDisplayStartM5BarTime M5境界に揃えた表示開始時刻。
 */
void drawLatestRankLabels(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime
) {
    gLatestRankBarTime = 0;
    ArrayInitialize(gLatestRanks, 0);
    gLatestRankSourceMode = "";
    gLatestRankLabelsDirty = true;
    int latestBufferIndex = findLatestRankBufferIndex(
        fromRatesTotal, fromTime, fromDisplayStartM5BarTime
    );

    if (latestBufferIndex >= 0) {
        for (int i = 0; i < 8; i++) {
            gLatestRanks[i] = (int)MathRound(
                getActualRankBufferValue(i, latestBufferIndex)
            );
        }

        gLatestRankBarTime = fromTime[latestBufferIndex];
        int pointIndex = findRankPointIndex(floorToM5(gLatestRankBarTime));

        if (pointIndex >= 0) {
            gLatestRankSourceMode = gRankPoints[pointIndex].sourceMode;
        }
    }

    drawCachedLatestRankLabels();
}

/**
 * 保持した最新順位を使ってラベルを再配置し、履歴の探索を省く。
 * 描画または座標変換に失敗した場合は、次のティック・画面変更で再試行する。
 */
void drawCachedLatestRankLabels() {
    if (gLatestRankLabelsDraw == NULL) {
        return;
    }

    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        return;
    }

    bool sourceDrawn = drawRankSourceLabel(subWindow, gLatestRankSourceMode);

    if (gLatestRankBarTime <= 0) {
        int emptyRanks[];
        gLatestRankLabelsDraw.clear();
        bool summaryDrawn = drawRankSummaryLabel(subWindow, emptyRanks);
        gLatestRankLabelsDirty = !sourceDrawn || !summaryDrawn;

        return;
    }

    bool summaryDrawn = drawRankSummaryLabel(subWindow, gLatestRanks);
    int rankOccurrences[9];
    datetime labelTimes[8];
    bool positionsResolved = true;
    ArrayInitialize(rankOccurrences, 0);

    for (int i = 0; i < 8; i++) {
        int rank = gLatestRanks[i];
        int pixelOffset = 18 + (rankOccurrences[rank] * 48);
        rankOccurrences[rank]++;
        bool positionResolved = false;
        labelTimes[i] = getLatestRankLabelTime(
            subWindow,
            gLatestRankBarTime,
            (double)(0 - rank),
            pixelOffset,
            positionResolved
        );
        positionsResolved = positionsResolved && positionResolved;
    }

    if (!gLatestRankLabelsDraw.draw(subWindow, labelTimes, gLatestRanks)) {
        gLogger.error(__FUNCTION__, "latest all-rank label draw failed");

        return;
    }

    gLatestRankLabelsDirty = !sourceDrawn || !summaryDrawn || !positionsResolved;
}

/**
 * 全通貨実順位が揃う最新バッファ番号を取得する。
 * 表示開始時刻より古い足に達したら探索を終了し、履歴がない場合は探索を省く。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime 新しい足から古い足へ並ぶチャートバー時刻配列。
 * @param fromDisplayStartM5BarTime M5境界に揃えた表示開始時刻。
 * @return 最新有効バッファ番号。存在しない場合は-1。
 */
int findLatestRankBufferIndex(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime
) {
    if (getRankPointCount() <= 0) {
        return -1;
    }

    for (int i = 0; i < fromRatesTotal; i++) {
        if (fromTime[i] < fromDisplayStartM5BarTime) {
            break;
        }

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
 * @return 描画に成功した場合true。
 */
bool drawRankSummaryLabel(
    const int fromSubWindow,
    const int &fromRanks[]
) {
    if (gRankSummaryLabelDraw == NULL) {
        return false;
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

        return false;
    }

    return true;
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
 * @return 描画に成功した場合true。
 */
bool drawRankSourceLabel(
    const int fromSubWindow,
    const string fromSourceMode
) {
    if (gRankSourceLabelDraw == NULL) {
        return false;
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

        return false;
    }

    return true;
}

/**
 * 最新足から指定ピクセル数だけ右側となるラベル時刻を取得する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromBarTime 最新順位を持つバー時刻。
 * @param fromDisplayPosition 順位線の表示位置。
 * @param fromPixelOffset 最新足から右へ離すピクセル数。
 * @param fromPositionResolved 座標変換で配置時刻を取得できた場合true。
 * @return ラベル配置時刻。
 */
datetime getLatestRankLabelTime(
    const int fromSubWindow,
    const datetime fromBarTime,
    const double fromDisplayPosition,
    const int fromPixelOffset,
    bool &fromPositionResolved
) {
    fromPositionResolved = false;
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
            fromPositionResolved = true;

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
 * @param fromDataChanged 初回取得、表示に使う履歴の変更または期限切れ削除があった場合true。
 * @return DB検索に成功した場合true。
 */
bool refreshRankPoints(
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime,
    datetime &fromChangedStartM5BarTime,
    bool &fromDataChanged
) {
    fromDataChanged = false;
    gLastQueryTargetM5BarTime = fromTargetM5BarTime;
    gLastQueryTickCount = GetTickCount64();

    datetime queryStartM5BarTime = fromDisplayStartM5BarTime;
    int cachedPointCount = getRankPointCount();

    if (gRankPointCacheReady && cachedPointCount > 0) {
        datetime lastCachedM5BarTime =
            gRankPoints[gRankPointStartIndex + cachedPointCount - 1].m5BarTime;

        if (lastCachedM5BarTime >= fromDisplayStartM5BarTime
                && lastCachedM5BarTime <= fromTargetM5BarTime) {
            queryStartM5BarTime = lastCachedM5BarTime;
        }
    }

    CurrencyStrengthAllRankPoint queriedPoints[];
    // 検索範囲の両端のM5足と従来の余裕1件を含め、DAOの予約容量を抑える。
    long queryRangeSeconds = (long)fromTargetM5BarTime - (long)queryStartM5BarTime;
    int maximumPointCount = (int)(queryRangeSeconds / PeriodSeconds(PERIOD_M5)) + 2;

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
    bool displayRangeChanged = false;
    bool rangeChanged = isCacheRangeChanged(
        queryStartM5BarTime,
        queriedPoints,
        displayRangeChanged
    );

    if (rangeChanged && !replaceCacheRange(queryStartM5BarTime, queriedPoints)) {
        gLogger.error(__FUNCTION__, "all-rank point cache update failed");

        return false;
    }

    int pointCountBeforePrune = getRankPointCount();
    pruneRankPoints(fromDisplayStartM5BarTime);
    gRankPointCacheReady = true;
    fromDataChanged = initialLoad || displayRangeChanged
        || pointCountBeforePrune != getRankPointCount();
    fromChangedStartM5BarTime = fromTargetM5BarTime;

    if (initialLoad) {
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "all-rank history loaded. sourceMode=%s points=%d "
                + "from=%s to=%s",
                gSourceMode,
                getRankPointCount(),
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

    if (displayRangeChanged) {
        fromChangedStartM5BarTime = queryStartM5BarTime;
    }

    return true;
}

/**
 * 再取得範囲の内容が現在のキャッシュと異なるか判定する。
 *
 * @param fromRangeStartM5BarTime 再取得範囲の開始M5時刻。
 * @param fromPoints 再取得した全通貨順位点。
 * @param fromDisplayChanged 件数・M5時刻・順位・取得元・有効性が異なる場合true。
 * @return 管理情報を含めて異なる場合true。
 */
bool isCacheRangeChanged(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthAllRankPoint &fromPoints[],
    bool &fromDisplayChanged
) {
    fromDisplayChanged = false;
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int cachedTailCount = getRankPointCount() - keepCount;
    int queriedPointCount = ArraySize(fromPoints);
    int replaceStartIndex = gRankPointStartIndex + keepCount;

    if (cachedTailCount != queriedPointCount) {
        fromDisplayChanged = true;

        return true;
    }

    bool cacheChanged = false;

    for (int i = 0; i < queriedPointCount; i++) {
        if (gRankPoints[replaceStartIndex + i].isSame(fromPoints[i])) {
            continue;
        }

        cacheChanged = true;

        if (!isSameRankPointDisplay(gRankPoints[replaceStartIndex + i], fromPoints[i])) {
            fromDisplayChanged = true;

            return true;
        }

        // 管理情報だけの変更でも、後続行の表示に使う内容の比較は続ける。
    }

    return cacheChanged;
}

/**
 * 2つの全通貨順位点の表示に使う内容が同じか判定する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @return M5時刻・全順位・取得元・履歴の有効性が同じ場合true。
 */
bool isSameRankPointDisplay(
    const CurrencyStrengthAllRankPoint &fromLeft,
    const CurrencyStrengthAllRankPoint &fromRight
) {
    return fromLeft.m5BarTime == fromRight.m5BarTime
        && fromLeft.sourceMode == fromRight.sourceMode
        && fromLeft.usdLongMediumTermAverageRank == fromRight.usdLongMediumTermAverageRank
        && fromLeft.usdMediumShortTermAverageRank == fromRight.usdMediumShortTermAverageRank
        && fromLeft.jpyLongMediumTermAverageRank == fromRight.jpyLongMediumTermAverageRank
        && fromLeft.jpyMediumShortTermAverageRank == fromRight.jpyMediumShortTermAverageRank
        && fromLeft.eurLongMediumTermAverageRank == fromRight.eurLongMediumTermAverageRank
        && fromLeft.eurMediumShortTermAverageRank == fromRight.eurMediumShortTermAverageRank
        && fromLeft.gbpLongMediumTermAverageRank == fromRight.gbpLongMediumTermAverageRank
        && fromLeft.gbpMediumShortTermAverageRank == fromRight.gbpMediumShortTermAverageRank
        && fromLeft.audLongMediumTermAverageRank == fromRight.audLongMediumTermAverageRank
        && fromLeft.audMediumShortTermAverageRank == fromRight.audMediumShortTermAverageRank
        && fromLeft.nzdLongMediumTermAverageRank == fromRight.nzdLongMediumTermAverageRank
        && fromLeft.nzdMediumShortTermAverageRank == fromRight.nzdMediumShortTermAverageRank
        && fromLeft.cadLongMediumTermAverageRank == fromRight.cadLongMediumTermAverageRank
        && fromLeft.cadMediumShortTermAverageRank == fromRight.cadMediumShortTermAverageRank
        && fromLeft.chfLongMediumTermAverageRank == fromRight.chfLongMediumTermAverageRank
        && fromLeft.chfMediumShortTermAverageRank == fromRight.chfMediumShortTermAverageRank
        && fromLeft.isValid() == fromRight.isValid();
}

/**
 * 期限切れの先頭部分を除いた、有効な順位履歴件数を取得する。
 *
 * @return 有効な順位履歴件数。
 */
int getRankPointCount() {
    return ArraySize(gRankPoints) - gRankPointStartIndex;
}

/**
 * 時刻の昇順を利用し、再取得範囲より前にある有効なキャッシュ件数を二分探索する。
 *
 * @param fromRangeStartM5BarTime 再取得範囲の開始M5時刻。
 * @return 保持するキャッシュ件数。
 */
int getCacheKeepCount(const datetime fromRangeStartM5BarTime) {
    int leftIndex = gRankPointStartIndex;
    int rightIndex = ArraySize(gRankPoints);

    while (leftIndex < rightIndex) {
        int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;

        if (gRankPoints[middleIndex].m5BarTime < fromRangeStartM5BarTime) {
            leftIndex = middleIndex + 1;
        } else {
            rightIndex = middleIndex;
        }
    }

    return leftIndex - gRankPointStartIndex;
}

/**
 * 指定範囲以降のキャッシュへ、変更・追加された履歴点だけを反映する。
 * 保持部分はコピーせず、必要な配列サイズを確保してから検索結果を反映する。
 * メモリ確保時は予備容量を追加し、少量ずつの履歴追加による再確保を減らす。
 *
 * @param fromRangeStartM5BarTime 置換範囲の開始M5時刻。
 * @param fromPoints 置換する全通貨順位点。
 * @return キャッシュ更新に成功した場合true。
 */
bool replaceCacheRange(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthAllRankPoint &fromPoints[]
) {
    int cachedArraySize = ArraySize(gRankPoints);
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int queriedPointCount = ArraySize(fromPoints);
    int replaceStartIndex = gRankPointStartIndex + keepCount;
    int nextArraySize = replaceStartIndex + queriedPointCount;

    if (nextArraySize != cachedArraySize
            && ArrayResize(gRankPoints, nextArraySize, rankPointReserveCount)
                != nextArraySize) {
        return false;
    }

    for (int i = 0; i < queriedPointCount; i++) {
        int pointIndex = replaceStartIndex + i;

        if (pointIndex < cachedArraySize && gRankPoints[pointIndex].isSame(fromPoints[i])) {
            continue;
        }

        gRankPoints[pointIndex] = fromPoints[i];
    }

    return true;
}

/**
 * 表示期間より古い全通貨順位点を参照対象から外し、先頭の前詰めをまとめて行う。
 *
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 */
void pruneRankPoints(const datetime fromDisplayStartM5BarTime) {
    gRankPointStartIndex += getCacheKeepCount(fromDisplayStartM5BarTime);

    if (gRankPointStartIndex <= 0) {
        return;
    }

    int nextPointCount = getRankPointCount();

    if (nextPointCount <= 0) {
        ArrayFree(gRankPoints);
        gRankPointStartIndex = 0;

        return;
    }

    if (gRankPointStartIndex < rankPointCompactThreshold
            && gRankPointStartIndex < nextPointCount) {
        return;
    }

    for (int i = 0; i < nextPointCount; i++) {
        gRankPoints[i] = gRankPoints[gRankPointStartIndex + i];
    }

    if (ArrayResize(gRankPoints, nextPointCount) != nextPointCount) {
        // 縮小失敗時は配列サイズが変わらないため、有効履歴を後ろから元の位置へ戻す。
        for (int i = nextPointCount - 1; i >= 0; i--) {
            gRankPoints[gRankPointStartIndex + i] = gRankPoints[i];
        }

        return;
    }

    gRankPointStartIndex = 0;
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
    datetime cachedM5BarTime = 0;
    int cachedBufferIndex = -1;
    int cachedPointIndex = -1;

    for (int i = 0; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromDisplayStartM5BarTime) {
            break;
        }

        setCachedBufferValues(
            i, barM5Time, fromTargetM5BarTime, cachedM5BarTime, cachedBufferIndex,
            cachedPointIndex
        );
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
 * @return 先頭から更新した件数。表示期限切れでクリアしたバーを含む。
 */
int fillNewBars(
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

    datetime cachedM5BarTime = 0;
    int cachedBufferIndex = -1;
    int cachedPointIndex = -1;

    for (int i = 0; i < calculationCount; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromDisplayStartM5BarTime) {
            clearBufferValues(i);

            continue;
        }

        setCachedBufferValues(
            i, barM5Time, fromTargetM5BarTime, cachedM5BarTime, cachedBufferIndex,
            cachedPointIndex
        );
    }

    return calculationCount;
}

/**
 * DB再取得で変更された範囲のうち、先頭の更新済みバーを除いて表示値を更新する。
 *
 * @param fromRatesTotal チャートバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromChangedStartM5BarTime 変更範囲開始M5時刻。
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
 * @param fromStartBufferIndex 更新開始位置。新規足の更新済み件数を指定する。
 */
void fillChangedBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromChangedStartM5BarTime,
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime,
    const int fromStartBufferIndex = 0
) {
    datetime cachedM5BarTime = 0;
    int cachedBufferIndex = -1;
    int cachedPointIndex = -1;

    for (int i = fromStartBufferIndex; i < fromRatesTotal; i++) {
        datetime barM5Time = floorToM5(fromTime[i]);

        if (barM5Time < fromChangedStartM5BarTime
                || barM5Time < fromDisplayStartM5BarTime) {
            break;
        }

        setCachedBufferValues(
            i, barM5Time, fromTargetM5BarTime, cachedM5BarTime, cachedBufferIndex,
            cachedPointIndex
        );
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
 * 同じ更新処理内で同じM5時刻が続く場合は、計算済みの全16バッファを再利用する。
 * 欠損・無効順位・未来時刻の空値も再利用し、次の更新処理へは持ち越さない。
 *
 * @param fromBufferIndex 設定先のバッファ位置。
 * @param fromBarM5Time 対象バーのM5時刻。
 * @param fromTargetM5BarTime 使用可能なM5時刻の上限。
 * @param fromCachedM5BarTime この更新処理で最後に計算したM5時刻。
 * @param fromCachedBufferIndex 計算済みのバッファ位置。更新処理の開始時は-1。
 * @param fromCachedPointIndex 前回検索した履歴位置。更新処理の開始時は-1。
 */
void setCachedBufferValues(
    const int fromBufferIndex,
    const datetime fromBarM5Time,
    const datetime fromTargetM5BarTime,
    datetime &fromCachedM5BarTime,
    int &fromCachedBufferIndex,
    int &fromCachedPointIndex
) {
    if (fromCachedBufferIndex < 0 || fromCachedM5BarTime != fromBarM5Time) {
        setBufferValues(
            fromBufferIndex, fromBarM5Time, fromTargetM5BarTime, fromCachedPointIndex
        );
        fromCachedM5BarTime = fromBarM5Time;
        fromCachedBufferIndex = fromBufferIndex;

        return;
    }

    gUsdDisplayRankBuffer[fromBufferIndex] = gUsdDisplayRankBuffer[fromCachedBufferIndex];
    gJpyDisplayRankBuffer[fromBufferIndex] = gJpyDisplayRankBuffer[fromCachedBufferIndex];
    gEurDisplayRankBuffer[fromBufferIndex] = gEurDisplayRankBuffer[fromCachedBufferIndex];
    gGbpDisplayRankBuffer[fromBufferIndex] = gGbpDisplayRankBuffer[fromCachedBufferIndex];
    gAudDisplayRankBuffer[fromBufferIndex] = gAudDisplayRankBuffer[fromCachedBufferIndex];
    gNzdDisplayRankBuffer[fromBufferIndex] = gNzdDisplayRankBuffer[fromCachedBufferIndex];
    gCadDisplayRankBuffer[fromBufferIndex] = gCadDisplayRankBuffer[fromCachedBufferIndex];
    gChfDisplayRankBuffer[fromBufferIndex] = gChfDisplayRankBuffer[fromCachedBufferIndex];
    gUsdActualRankBuffer[fromBufferIndex] = gUsdActualRankBuffer[fromCachedBufferIndex];
    gJpyActualRankBuffer[fromBufferIndex] = gJpyActualRankBuffer[fromCachedBufferIndex];
    gEurActualRankBuffer[fromBufferIndex] = gEurActualRankBuffer[fromCachedBufferIndex];
    gGbpActualRankBuffer[fromBufferIndex] = gGbpActualRankBuffer[fromCachedBufferIndex];
    gAudActualRankBuffer[fromBufferIndex] = gAudActualRankBuffer[fromCachedBufferIndex];
    gNzdActualRankBuffer[fromBufferIndex] = gNzdActualRankBuffer[fromCachedBufferIndex];
    gCadActualRankBuffer[fromBufferIndex] = gCadActualRankBuffer[fromCachedBufferIndex];
    gChfActualRankBuffer[fromBufferIndex] = gChfActualRankBuffer[fromCachedBufferIndex];
}

/**
 * 指定バーへ全8通貨の順位を一括設定する。
 *
 * 一つでも無効な順位があれば全16バッファを空値にする。
 *
 * @param fromBufferIndex 設定対象バッファ番号。
 * @param fromBarM5Time 対応するM5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
 * @param fromCachedPointIndex 前回検索した履歴位置。検索結果で更新し、欠損時は-1。
 */
void setBufferValues(
    const int fromBufferIndex,
    const datetime fromBarM5Time,
    const datetime fromTargetM5BarTime,
    int &fromCachedPointIndex
) {
    if (fromBarM5Time <= 0 || fromBarM5Time > fromTargetM5BarTime) {
        fromCachedPointIndex = -1;
        clearBufferValues(fromBufferIndex);

        return;
    }

    int pointIndex = findRankPointIndex(fromBarM5Time, fromCachedPointIndex);
    fromCachedPointIndex = pointIndex;

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
 * 新しい足から古い足へ処理する場合、前回位置の1件前が完全一致すれば再利用する。
 *
 * @param fromM5BarTime 検索対象M5時刻。
 * @param fromPreviousPointIndex 同じ更新処理内の前回検索位置。単発検索や初回は-1。
 * @return 一致した配列位置。存在しない場合は-1。
 */
int findRankPointIndex(
    const datetime fromM5BarTime,
    const int fromPreviousPointIndex = -1
) {
    int leftIndex = gRankPointStartIndex;
    int rightIndex = ArraySize(gRankPoints) - 1;

    if (fromPreviousPointIndex > leftIndex && fromPreviousPointIndex <= rightIndex
            && gRankPoints[fromPreviousPointIndex - 1].m5BarTime == fromM5BarTime) {
        return fromPreviousPointIndex - 1;
    }

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
