//+------------------------------------------------------------------+
//|                                  CurrencyStrengthRankHistory.mq5 |
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

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthLatestRankLabels.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankAlignmentLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankPeriodLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSignalLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSourceLabel.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>

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
input int subPanelHeight = 120;
input CurrencyStrengthRankDatabaseProfile databaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
input string databaseFileName = "mstng-currency-strength.sqlite";
input bool databaseSplitByYear = true;
input bool databaseUseCommonFolder = true;

double gBaseDisplayRankBuffer[];
double gQuoteDisplayRankBuffer[];
double gBaseActualRankBuffer[];
double gQuoteActualRankBuffer[];

Logger gLogger;
CurrencyStrengthYearlyRankQueryService *gRankQueryService = NULL;
DrawCurrencyStrengthLatestRankLabels *gLatestRankLabelsDraw = NULL;
DrawCurrencyStrengthRankAlignmentLabel *gRankAlignmentLabelDraw = NULL;
DrawCurrencyStrengthRankPeriodLabel *gRankPeriodLabelDraw = NULL;
DrawCurrencyStrengthRankSignalLabel *gRankSignalLabelDraw = NULL;
DrawCurrencyStrengthRankSourceLabel *gRankSourceLabelDraw = NULL;
CurrencyStrengthPairRankPoint gRankPoints[];
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
            "CurrencyStrengthRankHistory requires Common database folder "
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

    if (gRankPeriodLabelDraw == NULL) {
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gLatestRankLabelsDraw = new DrawCurrencyStrengthLatestRankLabels(
        ChartID(),
        drawObjectSuffix
    );

    if (gLatestRankLabelsDraw == NULL) {
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gRankAlignmentLabelDraw = new DrawCurrencyStrengthRankAlignmentLabel(
        ChartID(),
        drawObjectSuffix
    );

    if (gRankAlignmentLabelDraw == NULL) {
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gRankSignalLabelDraw = new DrawCurrencyStrengthRankSignalLabel(
        ChartID(),
        drawObjectSuffix
    );

    if (gRankSignalLabelDraw == NULL) {
        delete gRankAlignmentLabelDraw;
        gRankAlignmentLabelDraw = NULL;
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gRankSourceLabelDraw = new DrawCurrencyStrengthRankSourceLabel(
        ChartID(),
        drawObjectSuffix
    );

    if (gRankSourceLabelDraw == NULL) {
        delete gRankSignalLabelDraw;
        gRankSignalLabelDraw = NULL;
        delete gRankAlignmentLabelDraw;
        gRankAlignmentLabelDraw = NULL;
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

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
 * インジケータで使用したリソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    if (gRankSourceLabelDraw != NULL) {
        delete gRankSourceLabelDraw;
        gRankSourceLabelDraw = NULL;
    }

    if (gRankSignalLabelDraw != NULL) {
        delete gRankSignalLabelDraw;
        gRankSignalLabelDraw = NULL;
    }

    if (gLatestRankLabelsDraw != NULL) {
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
    }

    if (gRankAlignmentLabelDraw != NULL) {
        delete gRankAlignmentLabelDraw;
        gRankAlignmentLabelDraw = NULL;
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

    ArrayFree(gRankPoints);
    gCalculationVersion = "";
    gSourceMode = "";
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;
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
 * チャート変更時に期間名ラベルの表示位置を再確認する。
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

    gRankPeriodLabelReady = drawRankPeriodLabel();
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
 * 選択中の順位期間をチャート表示用の日本語へ変換する。
 *
 * @return 長中期または中短期。
 */
string getRankPeriodDisplayLabel() {
    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT) {
        return "中短期";
    }

    return "長中期";
}

/**
 * 現在のサブパネルに残っている旧順位ラベルを削除する。
 *
 * @return サブウィンドウを特定して削除処理を実行した場合true。
 */
bool clearStaleRankLabelObjects() {
    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        return false;
    }

    bool isDeleted = true;

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthLatestBase_",
        subWindow,
        OBJ_TEXT
    ) < 0) {
        isDeleted = false;
    }
    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthLatestQuote_",
        subWindow,
        OBJ_TEXT
    ) < 0) {
        isDeleted = false;
    }
    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthRankAlignment_",
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
        Constant::PREFIX_FIXED + "CurrencyStrengthRankSignal_",
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
        gLogger.error(__FUNCTION__, "stale rank label cleanup failed");

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
 * 最新順位線の右側へ順位と通貨名を描画する。
 *
 * @param fromRatesTotal チャートのバー総数。
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

    if (ArraySize(gRankPoints) == 0) {
        gLatestRankLabelsDraw.clear();
        drawRankSignalLabel(subWindow, 0, 0);
        drawRankAlignmentLabel(subWindow, 0, 0, 0, 0);
        drawRankSourceLabel(subWindow, "");

        return;
    }

    int latestBufferIndex = -1;

    for (int i = 0; i < fromRatesTotal; i++) {
        if (isActualRankBufferValue(gBaseActualRankBuffer[i])
                && isActualRankBufferValue(gQuoteActualRankBuffer[i])) {
            latestBufferIndex = i;

            break;
        }
    }

    if (latestBufferIndex < 0) {
        gLatestRankLabelsDraw.clear();
        drawRankSignalLabel(subWindow, 0, 0);
        drawRankAlignmentLabel(subWindow, 0, 0, 0, 0);
        drawRankSourceLabel(subWindow, "");

        return;
    }

    int baseRank = (int)MathRound(
        gBaseActualRankBuffer[latestBufferIndex]
    );
    int quoteRank = (int)MathRound(
        gQuoteActualRankBuffer[latestBufferIndex]
    );
    drawRankSignalLabel(subWindow, baseRank, quoteRank);
    datetime latestBarTime = fromTime[latestBufferIndex];
    int pointIndex = findRankPointIndex(floorToM5(latestBarTime));

    if (pointIndex >= 0) {
        CurrencyStrengthPairRankPoint point = gRankPoints[pointIndex];
        drawRankAlignmentLabel(
            subWindow,
            point.baseLongMediumTermAverageRank,
            point.quoteLongMediumTermAverageRank,
            point.baseMediumShortTermAverageRank,
            point.quoteMediumShortTermAverageRank
        );
        drawRankSourceLabel(subWindow, point.sourceMode);
    } else {
        drawRankAlignmentLabel(subWindow, 0, 0, 0, 0);
        drawRankSourceLabel(subWindow, "");
    }

    int basePixelOffset = 18;
    int quotePixelOffset = 18;

    if (baseRank == quoteRank) {
        quotePixelOffset = 66;
    }

    datetime baseLabelTime = getLatestRankLabelTime(
        subWindow,
        latestBarTime,
        (double)(0 - baseRank),
        basePixelOffset
    );
    datetime quoteLabelTime = getLatestRankLabelTime(
        subWindow,
        latestBarTime,
        (double)(0 - quoteRank),
        quotePixelOffset
    );

    if (!gLatestRankLabelsDraw.draw(
        subWindow,
        baseLabelTime,
        gBaseCurrency,
        baseRank,
        ConstantCurrency::getColor(gBaseCurrency),
        quoteLabelTime,
        gQuoteCurrency,
        quoteRank,
        ConstantCurrency::getColor(gQuoteCurrency)
    )) {
        gLogger.error(__FUNCTION__, "latest rank label draw failed");
    }
}

/**
 * 基軸通貨と決済通貨の順位差から売買方向を描画する。
 *
 * 基軸通貨の順位が上の場合はBUY、決済通貨の順位が上の場合はSELLとする。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 */
void drawRankSignalLabel(
    const int fromSubWindow,
    const int fromBaseRank,
    const int fromQuoteRank
) {
    if (gRankSignalLabelDraw == NULL) {
        return;
    }

    string signalText = "-";
    color signalColor = clrSilver;

    if (fromBaseRank >= 1
            && fromBaseRank <= 8
            && fromQuoteRank >= 1
            && fromQuoteRank <= 8) {
        int rankDifference = fromQuoteRank - fromBaseRank;

        if (rankDifference > 0) {
            signalText = StringFormat("BUY +%d", rankDifference);
            signalColor = clrAqua;
        } else if (rankDifference < 0) {
            signalText = StringFormat("SELL %d", rankDifference);
            signalColor = clrHotPink;
        }
    }

    if (!gRankSignalLabelDraw.draw(
        fromSubWindow,
        signalText,
        signalColor
    )) {
        gLogger.error(__FUNCTION__, "rank signal label draw failed");
    }
}

/**
 * 長中期と中短期の順位方向一致状態を描画する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromBaseLongMediumRank 基軸通貨の長中期順位。
 * @param fromQuoteLongMediumRank 決済通貨の長中期順位。
 * @param fromBaseMediumShortRank 基軸通貨の中短期順位。
 * @param fromQuoteMediumShortRank 決済通貨の中短期順位。
 */
void drawRankAlignmentLabel(
    const int fromSubWindow,
    const int fromBaseLongMediumRank,
    const int fromQuoteLongMediumRank,
    const int fromBaseMediumShortRank,
    const int fromQuoteMediumShortRank
) {
    if (gRankAlignmentLabelDraw == NULL) {
        return;
    }

    string alignmentText = "-";
    color alignmentColor = clrSilver;

    if (fromBaseLongMediumRank >= 1
            && fromBaseLongMediumRank <= 8
            && fromQuoteLongMediumRank >= 1
            && fromQuoteLongMediumRank <= 8
            && fromBaseMediumShortRank >= 1
            && fromBaseMediumShortRank <= 8
            && fromQuoteMediumShortRank >= 1
            && fromQuoteMediumShortRank <= 8) {
        int longMediumDifference =
            fromQuoteLongMediumRank - fromBaseLongMediumRank;
        int mediumShortDifference =
            fromQuoteMediumShortRank - fromBaseMediumShortRank;

        if (longMediumDifference > 0 && mediumShortDifference > 0) {
            alignmentText = "STRONG BUY";
            alignmentColor = clrAqua;
        } else if (longMediumDifference < 0
                && mediumShortDifference < 0) {
            alignmentText = "STRONG SELL";
            alignmentColor = clrHotPink;
        } else {
            alignmentText = "MIXED";
            alignmentColor = clrGold;
        }
    }

    if (!gRankAlignmentLabelDraw.draw(
        fromSubWindow,
        alignmentText,
        alignmentColor
    )) {
        gLogger.error(__FUNCTION__, "rank alignment label draw failed");
    }
}

/**
 * 最新順位点の取得元を描画する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromSourceMode 最新順位点の集計実行モード。
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
        gLogger.error(__FUNCTION__, "rank source label draw failed");
    }
}

/**
 * 最新足から指定ピクセル数だけ右側となる時刻を取得する。
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

    return fromBarTime + periodSeconds;
}

/**
 * データウィンドウ用順位バッファの値が有効か判定する。
 *
 * @param fromValue 判定対象値。
 * @return 1～8の順位の場合true。
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
 * LIVE優先・TESTER補完プロファイルが選択されているか判定する。
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
        CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;

    if (usesLiveThenTesterDatabaseProfile()) {
        queryStatus = gRankQueryService.findPairRankPointsInRangePreferLive(
            queryStartM5BarTime,
            fromTargetM5BarTime,
            gCalculationVersion,
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoInteger(ACCOUNT_LOGIN),
            gBaseCurrency,
            gQuoteCurrency,
            maximumPointCount,
            queriedPoints
        );
    } else {
        queryStatus = gRankQueryService.findPairRankPointsInRange(
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
    }

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
        && fromLeft.sourceMode == fromRight.sourceMode
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
