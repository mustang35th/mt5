//+------------------------------------------------------------------+
//|                                  CurrencyStrengthRankHistory.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.50"
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   6
#property indicator_minimum -9.5
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

#property indicator_label5  "Rank Signal"
#property indicator_type5   DRAW_COLOR_LINE
#property indicator_color5  clrAqua, clrHotPink, clrDimGray, clrTeal, C'128,50,90'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  5

#property indicator_label6  "Rank Gap Base;Rank Gap Quote"
#property indicator_type6   DRAW_FILLING
#property indicator_color6  C'0,51,51', C'51,21,36'

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Draw\ChartMouseMoveSubscription.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthLatestRankLabels.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankAndRibbon.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankPeriodLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankReloadButton.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSignalLabel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankSourceLabel.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankAndSignal.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * サブパネルへ表示する通貨強弱順位の期間。
 */
enum CurrencyStrengthRankPeriod {
    /** 長中期平均順位を表示する。 */
    CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM = 0, // 長中期

    /** 中短期平均順位を表示する。 */
    CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT = 1 // 中短期
};

/**
 * 選択期間の通貨強弱順位による売買方向。
 *
 * 値は履歴リボンの強調色と同順位色の番号として使用する。
 */
enum CurrencyStrengthRankSignal {
    /** 基軸通貨の順位が上の場合。 */
    CURRENCY_STRENGTH_RANK_SIGNAL_BUY = 0,

    /** 決済通貨の順位が上の場合。 */
    CURRENCY_STRENGTH_RANK_SIGNAL_SELL = 1,

    /** 基軸通貨と決済通貨が同順位の場合。 */
    CURRENCY_STRENGTH_RANK_SIGNAL_NON = 2
};

input group "01. 履歴表示・更新"

/** サブ画面へ表示する通貨強弱順位の期間。 */
input(name="表示する順位") CurrencyStrengthRankPeriod rankPeriod =
    CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM;

/** 現在のサーバーM5時刻からさかのぼる表示日数。DBの保存・削除には影響しない。 */
input(name="履歴の表示日数（1～366日）") int historyDays = 30;

/** サブ画面の高さ。0は高さを指定せず、MT5側のサイズを使用する。 */
input(name="サブ画面の高さ（px・0＝指定なし）") int subPanelHeight = 120;

/** H1未満は長中期の順位差または端順位と中短期の順位差で準備・成立を表示する。H1以上は長中期の順位差4以上または端順位で成立を表示し、同時表示時は最上段を優先する。 */
input(name="メインチャートに強弱帯を表示") bool rankAndRibbonVisible = true;

input group "02. データ参照"

/** 参照する保存済み履歴。LIVE優先では同じM5時刻にLIVEがない場合だけテスター履歴を使用する。 */
input(name="参照する履歴") CurrencyStrengthRankDatabaseProfile databaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;

/** 保存済みの加重・均等データの選択。保存側の計算方式に合わせる。 */
input(name="参照するスコアの計算方式") CurrencyStrengthVoteWeightMode voteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

input group "03. DB参照先"

/** 年別分割時の年付与前のDBファイル名。保存側の設定に合わせる。 */
input(name="DBファイル名（年なし）") string databaseFileName = "mstng-currency-strength.sqlite";

/** サーバー時刻の年ごとに分割されたDBを参照する場合true。保存側の設定に合わせる。 */
input(name="年別DBファイルを参照") bool databaseSplitByYear = true;

/** MT5共通フォルダ内のDBを参照する場合true。保存側の設定に合わせ、テスターでは必須。 */
input(name="MT5共通フォルダから読み込む") bool databaseUseCommonFolder = true;

double gBaseDisplayRankBuffer[];
double gQuoteDisplayRankBuffer[];
double gBaseActualRankBuffer[];
double gQuoteActualRankBuffer[];
double gRankSignalDisplayBuffer[];
double gRankSignalColorBuffer[];

/** 順位差を強調する塗り領域の基軸通貨側の境界。 */
double gBaseRankFillBuffer[];

/** 順位差を強調する塗り領域の決済通貨側の境界。 */
double gQuoteRankFillBuffer[];

/** このインスタンスのラベルと帯の再描画要求をイベントごとにまとめる。 */
ChartRedrawRequest gChartRedrawRequest;

/** 帯詳細用のマウスイベントを同じチャートの利用者間で共有する。 */
ChartMouseMoveSubscription gRankRibbonMouseMoveSubscription;

/** 描画色が同じでも、帯詳細の参照順位や取得元を更新する必要がある場合true。 */
bool gRankRibbonTooltipDirty = false;

Logger gLogger;
CurrencyStrengthYearlyRankQueryService *gRankQueryService = NULL;
DrawCurrencyStrengthLatestRankLabels *gLatestRankLabelsDraw = NULL;

/** メインチャート下端のAND帯描画。 */
DrawCurrencyStrengthRankAndRibbon *gRankAndRibbonDraw = NULL;

DrawCurrencyStrengthRankPeriodLabel *gRankPeriodLabelDraw = NULL;
DrawCurrencyStrengthRankSignalLabel *gRankSignalLabelDraw = NULL;
DrawCurrencyStrengthRankSourceLabel *gRankSourceLabelDraw = NULL;

/** 表示期間全体を再読込する通常チャート専用ボタン。 */
DrawCurrencyStrengthRankReloadButton *gRankReloadButtonDraw = NULL;

/** 再読込ボタンの生成・設定が完了した場合true。 */
bool gRankReloadButtonReady = false;

/** 再読込ボタンの説明と前回操作の結果。 */
string gRankReloadTooltip = "";

/** 前回の手動再読込結果を示すボタン文字色。 */
color gRankReloadColor = clrSilver;

CurrencyStrengthPairRankPoint gRankPoints[];

/** 期限切れの先頭部分を除いた、有効な順位履歴の開始位置。 */
int gRankPointStartIndex = 0;

/** キャッシュへ最後に適用した表示開始M5時刻。DB取得失敗時は更新しない。 */
datetime gRankPointDisplayStartM5BarTime = 0;

/** 初期化時に取得し、M5時刻変換と履歴取得上限の計算で共用する秒数。 */
int gM5Seconds = 0;

string gBaseCurrency = "";
string gQuoteCurrency = "";
string gCalculationVersion = "";
string gSourceMode = "";

/** 同時表示時にAND帯の描画担当を識別するインジケータ名。 */
string gIndicatorShortName = "";

/** 通常チャートのAND帯描画担当を確認済みの場合true。 */
bool gRankAndRibbonOwnerReady = false;

/** 前回の確認でこのインスタンスがAND帯の描画担当だった場合true。 */
bool gRankAndRibbonOwner = false;

datetime gLastQueryTargetM5BarTime = 0;
datetime gLastDisplayStartM5BarTime = 0;
ulong gLastQueryTickCount = 0;
bool gRankPointCacheReady = false;
bool gRankPeriodLabelReady = false;
bool gRankLabelObjectsPrepared = false;

/** 最後に表示バッファを更新したチャート足の開始時刻。 */
datetime gLastCalculatedBarTime = 0;

/** 最新順位ラベルが参照するチャート足の開始時刻。 */
datetime gLatestRankBarTime = 0;

/** 最新順位ラベルに表示する基軸通貨順位。 */
int gLatestBaseRank = 0;

/** 最新順位ラベルに表示する決済通貨順位。 */
int gLatestQuoteRank = 0;

/** 最新順位ラベルが参照する履歴の取得元。 */
string gLatestRankSourceMode = "";

/** DB検索を一度以上実行した場合true。 */
bool gRankQueryAttempted = false;

/** 直近DB検索を開始したSERVER時刻。 */
datetime gLastRankQueryAttemptAt = 0;

/** 正常なDB読込が最後に完了したSERVER時刻。0件成功も含む。 */
datetime gLastRankQuerySuccessAt = 0;

/** 直近DB検索範囲の開始M5時刻。 */
datetime gLastRankQueryStartM5BarTime = 0;

/** 直近DB検索範囲の終了M5時刻。 */
datetime gLastRankQueryEndM5BarTime = 0;

/** 直近のDB検索結果。未取得との区別はgRankQueryAttemptedを使用する。 */
ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS gLastRankQueryStatus =
    CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;

/** 直近のDB検索後に表示キャッシュへの反映が失敗した場合true。 */
bool gRankCacheUpdateFailed = false;

/** 取得状態のSOURCE表示への反映または描画再試行が必要な場合true。 */
bool gRankSourceStatusDirty = true;

/** 最新順位ラベルの再配置または描画再試行が必要な場合true。 */
bool gLatestRankLabelsDirty = false;

/** 座標変換に成功した最新順位ラベルの画面条件。未確認・変換失敗時は空。 */
string gLatestRankPositionKey = "";

/** 同じ画面条件で再利用する基軸通貨ラベルの配置時刻。 */
datetime gCachedBaseLabelTime = 0;

/** 同じ画面条件で再利用する決済通貨ラベルの配置時刻。 */
datetime gCachedQuoteLabelTime = 0;

/** 通常チャートのDB再読込間隔を60秒に固定する。M5新足時は即時再読込する。 */
const int refreshSeconds = 60;

/** 通常チャートで帯の表示・描画担当と描画失敗を再確認する間隔（秒）。 */
const int displayCheckSeconds = 10;

/** 期限切れ履歴をまとめて前詰めする件数。M5足の1日分。 */
const int rankPointCompactThreshold = 288;

/** 履歴配列のメモリ確保時に追加する予備件数。M5足の1日分。 */
const int rankPointReserveCount = 288;

const double rankSignalDisplayPosition = -9.0;

/** 塗り領域、方向バー、帯と右上ラベルの順位差基準。長中期は方向に合う端順位でも強調する。 */
const int rankSignalHighlightDifference = 4;

/**
 * インジケータを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    bool isTester = Util::isStrategyTester();

    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthRankHistory does not support optimization");

        return INIT_FAILED;
    }

    if (historyDays < 1
            || historyDays > 366
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
    gM5Seconds = PeriodSeconds(PERIOD_M5);

    if (gM5Seconds <= 0) {
        gLogger.error(__FUNCTION__, "M5 period seconds resolution failed");

        return INIT_FAILED;
    }

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

    if (gRankPeriodLabelDraw == NULL) {
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gLatestRankLabelsDraw = new DrawCurrencyStrengthLatestRankLabels(
        ChartID(),
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );

    if (gLatestRankLabelsDraw == NULL) {
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    gRankSignalLabelDraw = new DrawCurrencyStrengthRankSignalLabel(
        ChartID(),
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );

    if (gRankSignalLabelDraw == NULL) {
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
        drawObjectSuffix,
        GetPointer(gChartRedrawRequest)
    );

    if (gRankSourceLabelDraw == NULL) {
        delete gRankSignalLabelDraw;
        gRankSignalLabelDraw = NULL;
        delete gLatestRankLabelsDraw;
        gLatestRankLabelsDraw = NULL;
        delete gRankPeriodLabelDraw;
        gRankPeriodLabelDraw = NULL;
        gRankQueryService.close();
        delete gRankQueryService;
        gRankQueryService = NULL;

        return INIT_FAILED;
    }

    if (!isTester) {
        gRankReloadButtonDraw = new DrawCurrencyStrengthRankReloadButton(
            ChartID(), drawObjectSuffix, GetPointer(gChartRedrawRequest)
        );
        if (gRankReloadButtonDraw == NULL) {
            return INIT_FAILED;
        }
    }

    if (rankAndRibbonVisible) {
        gRankAndRibbonDraw = new DrawCurrencyStrengthRankAndRibbon(
            ChartID(),
            drawObjectSuffix,
            GetPointer(gChartRedrawRequest)
        );

        if (gRankAndRibbonDraw == NULL) {
            return INIT_FAILED;
        }
    }

    if (!isTester && !EventSetTimer(displayCheckSeconds)) {
        gLogger.error(__FUNCTION__, "rank history timer initialization failed");

        return INIT_FAILED;
    }

    ArrayResize(gRankPoints, 0);
    gRankPointStartIndex = 0;
    gRankPointDisplayStartM5BarTime = 0;
    gLastQueryTargetM5BarTime = 0;
    gLastDisplayStartM5BarTime = 0;
    gLastQueryTickCount = 0;
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankReloadButtonReady = false;
    gRankReloadTooltip = getRankReloadDescription();
    gRankReloadColor = clrSilver;
    gRankRibbonTooltipDirty = false;
    gRankLabelObjectsPrepared = false;
    gRankAndRibbonOwnerReady = false;
    gRankAndRibbonOwner = false;
    gLastCalculatedBarTime = 0;
    gLatestRankBarTime = 0;
    gLatestBaseRank = 0;
    gLatestQuoteRank = 0;
    gLatestRankSourceMode = "";
    resetRankQueryDisplayStatus();
    gLatestRankLabelsDirty = false;
    gLatestRankPositionKey = "";
    gCachedBaseLabelTime = 0;
    gCachedQuoteLabelTime = 0;

    if (!isTester && rankAndRibbonVisible
            && !gRankRibbonMouseMoveSubscription.acquire(ChartID())) {
        gLogger.error(__FUNCTION__, "rank ribbon mouse event initialization failed");

        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

/**
 * インジケータで使用したリソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    gRankRibbonMouseMoveSubscription.release();
    gRankRibbonTooltipDirty = false;
    EventKillTimer();

    if (gRankReloadButtonDraw != NULL) {
        delete gRankReloadButtonDraw;
        gRankReloadButtonDraw = NULL;
    }

    gRankReloadButtonReady = false;
    resetRankQueryDisplayStatus();

    if (gRankAndRibbonDraw != NULL) {
        delete gRankAndRibbonDraw;
        gRankAndRibbonDraw = NULL;
    }

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
    gRankPointStartIndex = 0;
    gRankPointDisplayStartM5BarTime = 0;
    gM5Seconds = 0;
    gCalculationVersion = "";
    gSourceMode = "";
    gRankPointCacheReady = false;
    gRankPeriodLabelReady = false;
    gRankLabelObjectsPrepared = false;
    gRankAndRibbonOwnerReady = false;
    gRankAndRibbonOwner = false;
    gLatestRankLabelsDirty = false;
    gLatestRankPositionKey = "";
    gCachedBaseLabelTime = 0;
    gCachedQuoteLabelTime = 0;
    gChartRedrawRequest.flush(ChartID());
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
        gChartRedrawRequest.flush(ChartID());

        return previousCalculated;
    }

    if (!gRankPeriodLabelReady) {
        gRankPeriodLabelReady = drawRankPeriodLabel();
    }

    if (!gRankReloadButtonReady) {
        gRankReloadButtonReady = drawRankReloadButton();
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
    bool bufferChanged = false;
    bool sourceChanged = false;
    bool ribbonChanged = false;
    datetime changedStartM5BarTime = targetM5BarTime;

    if (shouldRefreshRankPoints(targetM5BarTime, isTester)) {
        refreshRankPoints(
            displayStartM5BarTime,
            targetM5BarTime,
            changedStartM5BarTime,
            bufferChanged,
            sourceChanged,
            ribbonChanged
        );
    }

    bool fullRefresh = previousCalculated <= 0
        || previousCalculated > ratesTotal
        || gLastDisplayStartM5BarTime <= 0
        || displayStartM5BarTime < gLastDisplayStartM5BarTime;
    bool chartBarChanged = time[0] != gLastCalculatedBarTime
        || ratesTotal != previousCalculated;
    bool displayRangeChanged = displayStartM5BarTime != gLastDisplayStartM5BarTime;

    bool updateBuffers = fullRefresh || bufferChanged || chartBarChanged
        || displayRangeChanged;

    if (fullRefresh) {
        gLatestRankPositionKey = "";
        fillAllBuffers(
            ratesTotal,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );
    } else if (updateBuffers) {
        int updatedBarCount = fillNewBars(
            ratesTotal,
            previousCalculated,
            time,
            displayStartM5BarTime,
            targetM5BarTime
        );

        if (bufferChanged) {
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

    if (updateBuffers) {
        gLastDisplayStartM5BarTime = displayStartM5BarTime;
        gLastCalculatedBarTime = time[0];
        drawLatestRankLabels(ratesTotal, time, displayStartM5BarTime);
    } else if (sourceChanged || gRankSourceStatusDirty) {
        drawLatestRankSourceLabel();
    } else if (gLatestRankLabelsDirty) {
        drawCachedLatestRankLabels();
    }

    if (updateBuffers || ribbonChanged || gRankRibbonTooltipDirty) {
        drawRankAndRibbon(fullRefresh);
    }

    gChartRedrawRequest.flush(ChartID());

    return ratesTotal;
}

/**
 * 通常チャートで10秒ごとに帯の表示・描画担当を確認し、失敗したラベル描画を再試行する。
 * 画面変更・新足・履歴変更時の更新は各イベントで行う。
 */
void OnTimer() {
    gRankAndRibbonOwnerReady = false;

    if (gRankLabelObjectsPrepared) {
        gRankReloadButtonReady = drawRankReloadButton();
    }

    if (gRankLabelObjectsPrepared && gLatestRankLabelsDirty) {
        drawCachedLatestRankLabels();
    } else if (gRankLabelObjectsPrepared && gRankSourceStatusDirty) {
        drawLatestRankSourceLabel();
    }

    drawRankAndRibbon();
    gChartRedrawRequest.flush(ChartID());
}

/**
 * 帯の詳細表示・再読込ボタンの操作と、チャート変更時のラベル・帯の再配置を処理する。
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
    if (fromEventId == CHARTEVENT_MOUSE_MOVE) {
        if (!Util::isStrategyTester() && gRankAndRibbonDraw != NULL
                && gRankPointCacheReady) {
            gRankAndRibbonDraw.handleMouseMove(
                (int)fromLongParameter, (int)fromDoubleParameter, gRankPoints,
                gBaseCurrency, gQuoteCurrency, gRankPointStartIndex
            );
        }

        return;
    }

    if (fromEventId == CHARTEVENT_OBJECT_CLICK
            && gRankReloadButtonDraw != NULL
            && gRankReloadButtonDraw.handleClick(fromStringParameter)) {
        string failureReason = "";
        bool reloaded = reloadRankHistory(failureReason);
        if (gRankSourceStatusDirty) {
            drawLatestRankSourceLabel();
        }

        gRankReloadTooltip = getRankReloadDescription();
        if (reloaded) {
            gRankReloadColor = clrPaleGreen;
            gRankReloadTooltip += "\n前回：再読込成功 SERVER "
                + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
                + StringFormat(" / %d件", getRankPointCount());
        } else {
            gRankReloadColor = clrOrange;
            gRankReloadTooltip += "\n前回：再読込失敗（順位表示は維持）\n" + failureReason;
        }

        gRankReloadButtonReady = drawRankReloadButton();
        gChartRedrawRequest.flush(ChartID());

        return;
    }

    if (fromEventId != CHARTEVENT_CHART_CHANGE) {
        return;
    }

    if (gRankAndRibbonDraw != NULL) {
        gRankAndRibbonDraw.invalidateViewCache();
    }

    gRankAndRibbonOwnerReady = false;

    if (!gRankLabelObjectsPrepared) {
        gRankLabelObjectsPrepared = clearStaleRankLabelObjects();
    }

    if (!gRankLabelObjectsPrepared) {
        gChartRedrawRequest.flush(ChartID());

        return;
    }

    gRankPeriodLabelReady = drawRankPeriodLabel();
    gRankReloadButtonReady = drawRankReloadButton();
    gLatestRankLabelsDirty = true;
    drawCachedLatestRankLabels();
    drawRankAndRibbon();
    gChartRedrawRequest.flush(ChartID());
}

/**
 * 手動再読込ボタンの共通説明を取得する。
 *
 * @return ボタン操作の対象と失敗時の動作。
 */
string getRankReloadDescription() {
    return "このパネルの表示期間全体をDBから再読込します。"
        + "\n後から補完・訂正した履歴も反映します。"
        + "\nDB・チャート足の取得失敗時は現在の順位表示を維持します。";
}

/**
 * 通常チャートの再読込ボタンを描画し、必要な場合だけ前回結果を反映する。
 *
 * @return 描画成功、またはテスターで表示対象外の場合true。
 */
bool drawRankReloadButton() {
    if (Util::isStrategyTester()) {
        return true;
    }

    if (gRankReloadButtonDraw == NULL) {
        return false;
    }

    return gRankReloadButtonDraw.draw(
        ChartWindowFind(), gRankReloadTooltip, gRankReloadColor
    );
}

/**
 * 表示中の全期間を取得し、ティックを待たず順位線・ラベル・帯へ反映する。
 * 必要なチャート足を先に準備し、DB取得成功まで既存キャッシュと表示を維持する。
 *
 * @param fromFailureReason 再読込できなかった場合の表示用説明。
 * @return 履歴取得と表示バッファの更新が完了した場合true。
 */
bool reloadRankHistory(string &fromFailureReason) {
    fromFailureReason = "";
    if (Util::isStrategyTester() || gRankQueryService == NULL
            || !gRankLabelObjectsPrepared || gLastCalculatedBarTime <= 0
            || gM5Seconds <= 0) {
        fromFailureReason = "通常チャートの初回表示が完了してから再操作してください。";

        return false;
    }

    int barCount = ArraySize(gBaseDisplayRankBuffer);
    if (barCount <= 0
            || ArraySize(gQuoteDisplayRankBuffer) != barCount
            || ArraySize(gBaseActualRankBuffer) != barCount
            || ArraySize(gQuoteActualRankBuffer) != barCount
            || ArraySize(gRankSignalDisplayBuffer) != barCount
            || ArraySize(gRankSignalColorBuffer) != barCount
            || ArraySize(gBaseRankFillBuffer) != barCount
            || ArraySize(gQuoteRankFillBuffer) != barCount) {
        fromFailureReason = "表示バッファの準備待ちです。少し待って再操作してください。";

        return false;
    }

    datetime barTimes[];
    ArraySetAsSeries(barTimes, true);
    if (CopyTime(_Symbol, _Period, 0, barCount, barTimes) != barCount
            || barTimes[0] != gLastCalculatedBarTime) {
        fromFailureReason = "チャート足を取得できないか、足の更新待ちです。再操作してください。";

        return false;
    }

    datetime targetM5BarTime = getTargetM5BarTime(barTimes[0]);
    if (targetM5BarTime <= 0) {
        fromFailureReason = "再読込の基準時刻を取得できませんでした。";

        return false;
    }

    datetime displayStartM5BarTime = getDisplayStartM5BarTime(targetM5BarTime);
    bool bufferChanged = false;
    bool sourceChanged = false;
    bool ribbonChanged = false;
    datetime changedStartM5BarTime = displayStartM5BarTime;

    // 差し替えられたDBファイルも開き直す。順位キャッシュは取得成功まで保持する。
    gRankQueryService.close();
    if (!refreshRankPoints(
        displayStartM5BarTime, targetM5BarTime, changedStartM5BarTime,
        bufferChanged, sourceChanged, ribbonChanged, true
    )) {
        fromFailureReason = "DBが見つからないか、履歴の取得・反映に失敗しました。ログを確認してください。";

        return false;
    }

    gLatestRankPositionKey = "";
    fillAllBuffers(barCount, barTimes, displayStartM5BarTime, targetM5BarTime);
    gLastDisplayStartM5BarTime = displayStartM5BarTime;
    gLastCalculatedBarTime = barTimes[0];
    drawLatestRankLabels(barCount, barTimes, displayStartM5BarTime);
    gRankAndRibbonOwnerReady = false;
    drawRankAndRibbon();
    gChartRedrawRequest.request();
    gLogger.info(__FUNCTION__, StringFormat(
        "rank history manually reloaded. points=%d", getRankPointCount()
    ));

    return true;
}

/**
 * 2本の表示バッファ、2本の実順位バッファおよび
 * 選択期間の履歴シグナルと順位差の塗りバッファを初期化する。
 *
 * @return 初期化に成功した場合true。
 */
bool initializeBuffers() {
    // 保存済みチャートの描画設定がある場合もバッファの対応を維持する。
    if (!PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE)
            || !PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE)
            || !PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_COLOR_LINE)
            || !PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_FILLING)) {
        return false;
    }

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

    if (!SetIndexBuffer(
        4,
        gRankSignalDisplayBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        5,
        gRankSignalColorBuffer,
        INDICATOR_COLOR_INDEX
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        6,
        gBaseRankFillBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    if (!SetIndexBuffer(
        7,
        gQuoteRankFillBuffer,
        INDICATOR_DATA
    )) {
        return false;
    }

    ArraySetAsSeries(gBaseRankFillBuffer, true);
    ArraySetAsSeries(gQuoteRankFillBuffer, true);
    ArraySetAsSeries(gBaseDisplayRankBuffer, true);
    ArraySetAsSeries(gQuoteDisplayRankBuffer, true);
    ArraySetAsSeries(gBaseActualRankBuffer, true);
    ArraySetAsSeries(gQuoteActualRankBuffer, true);
    ArraySetAsSeries(gRankSignalDisplayBuffer, true);
    ArraySetAsSeries(gRankSignalColorBuffer, true);

    for (int i = 0; i < 6; i++) {
        PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    }

    PlotIndexSetInteger(0, PLOT_SHOW_DATA, false);
    PlotIndexSetInteger(1, PLOT_SHOW_DATA, false);
    PlotIndexSetInteger(2, PLOT_SHOW_DATA, true);
    PlotIndexSetInteger(3, PLOT_SHOW_DATA, true);
    PlotIndexSetInteger(4, PLOT_SHOW_DATA, false);
    PlotIndexSetInteger(5, PLOT_SHOW_DATA, false);

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
    PlotIndexSetString(
        4,
        PLOT_LABEL,
        rankPeriodLabel + " Signal"
    );

    PlotIndexSetInteger(0, PLOT_LINE_COLOR, baseColor);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, quoteColor);

    string rankAndName = "";

    if (rankAndRibbonVisible) {
        rankAndName = " AND";
    }

    gIndicatorShortName = StringFormat(
        "Currency Strength Rank%s %s/%s %s %s %s -1=Top (%d days)",
        rankAndName,
        gBaseCurrency,
        gQuoteCurrency,
        gSourceMode,
        CurrencyStrengthCalculationProfile::getVoteWeightModeText(voteWeightMode),
        rankPeriodLabel,
        historyDays
    );
    // MT5の表示名上限に合わせ、ChartIndicatorNameとの照合を一致させる。
    gIndicatorShortName = StringSubstr(gIndicatorShortName, 0, 63);
    IndicatorSetInteger(INDICATOR_DIGITS, 0);
    IndicatorSetString(INDICATOR_SHORTNAME, gIndicatorShortName);
}

/**
 * 同じチャートでAND帯を有効にした最上段のインジケータか判定する。
 * 通常チャートはチャート変更・定期確認まで結果を保持し、テスターは都度判定する。
 * 対象未検出や取得失敗の場合は結果を確定せず、次回に再試行する。
 *
 * @return このインスタンスが描画を担当する場合true。
 */
bool isRankAndRibbonOwner() {
    bool useCachedOwner = !Util::isStrategyTester();
    if (useCachedOwner && gRankAndRibbonOwnerReady) {
        return gRankAndRibbonOwner;
    }

    gRankAndRibbonOwnerReady = false;
    gRankAndRibbonOwner = false;
    int currentSubWindow = ChartWindowFind();

    if (currentSubWindow <= 0) {
        return false;
    }

    int windowCount = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);

    for (int i = 1; i < windowCount; i++) {
        int indicatorCount = ChartIndicatorsTotal(ChartID(), i);
        if (indicatorCount < 0) {
            return false;
        }

        for (int j = 0; j < indicatorCount; j++) {
            string indicatorName = ChartIndicatorName(ChartID(), i, j);
            if (indicatorName == "") {
                return false;
            }

            if (StringFind(indicatorName, "Currency Strength Rank AND ") == 0) {
                gRankAndRibbonOwner = i == currentSubWindow
                    && indicatorName == gIndicatorShortName;
                gRankAndRibbonOwnerReady = useCachedOwner;

                return gRankAndRibbonOwner;
            }
        }
    }

    return false;
}

/**
 * 保存済み順位からメインチャート下端のAND帯を更新する。
 *
 * @param fromForce 全再構築など、表示範囲が同じでも再描画する場合true。
 */
void drawRankAndRibbon(const bool fromForce = false) {
    gRankRibbonTooltipDirty = false;
    if (gRankAndRibbonDraw == NULL) {
        return;
    }

    if (!gRankPointCacheReady || !isRankAndRibbonOwner()) {
        gRankAndRibbonDraw.clear();

        return;
    }

    if (!gRankAndRibbonDraw.draw(
        gRankPoints,
        gLastQueryTargetM5BarTime,
        rankSignalHighlightDifference,
        fromForce,
        gRankPointStartIndex
    )) {
        gLogger.error(__FUNCTION__, "rank AND ribbon draw failed");
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
    gChartRedrawRequest.request();

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

    if (ObjectsDeleteAll(
        ChartID(),
        Constant::PREFIX_FIXED + "CurrencyStrengthRankReload_",
        subWindow,
        OBJ_BUTTON
    ) < 0) {
        isDeleted = false;
    }

    if (!isDeleted) {
        gLogger.error(__FUNCTION__, "stale rank label cleanup failed");

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
 * 最新順位線の右側へ順位と通貨名を描画する。
 * 表示開始時刻より古い足に達したら、最新順位の探索を終了する。
 *
 * @param fromRatesTotal チャートのバー総数。
 * @param fromTime チャートバー時刻配列。
 * @param fromDisplayStartM5BarTime M5境界に揃えた表示開始時刻。
 */
void drawLatestRankLabels(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime
) {
    gLatestRankBarTime = 0;
    gLatestBaseRank = 0;
    gLatestQuoteRank = 0;
    gLatestRankSourceMode = "";
    gLatestRankLabelsDirty = true;
    int latestBufferIndex = -1;

    if (getRankPointCount() > 0) {
        for (int i = 0; i < fromRatesTotal; i++) {
            if (fromTime[i] < fromDisplayStartM5BarTime) {
                break;
            }

            if (isActualRankBufferValue(gBaseActualRankBuffer[i])
                    && isActualRankBufferValue(gQuoteActualRankBuffer[i])) {
                latestBufferIndex = i;

                break;
            }
        }
    }

    if (latestBufferIndex >= 0) {
        gLatestBaseRank = (int)MathRound(gBaseActualRankBuffer[latestBufferIndex]);
        gLatestQuoteRank = (int)MathRound(gQuoteActualRankBuffer[latestBufferIndex]);
        gLatestRankBarTime = fromTime[latestBufferIndex];
        int pointIndex = findRankPointIndex(floorToM5(gLatestRankBarTime));

        if (pointIndex >= 0) {
            gLatestRankSourceMode = gRankPoints[pointIndex].sourceMode;
        }
    }

    drawCachedLatestRankLabels();
}

/**
 * 保持した最新順位の時刻から取得元・参照時刻・DB取得状態だけを更新する。
 * 未完了のラベル描画がある場合は、取得元の反映後に全ラベルを再試行する。
 */
void drawLatestRankSourceLabel() {
    string sourceMode = "";

    if (gLatestRankBarTime > 0) {
        int pointIndex = findRankPointIndex(floorToM5(gLatestRankBarTime));

        if (pointIndex >= 0) {
            sourceMode = gRankPoints[pointIndex].sourceMode;
        }
    }

    bool sourceChanged = gLatestRankSourceMode != sourceMode;
    gLatestRankSourceMode = sourceMode;

    if (gLatestRankLabelsDirty) {
        drawCachedLatestRankLabels();

        return;
    }

    if (!sourceChanged && !gRankSourceStatusDirty) {
        return;
    }

    int subWindow = ChartWindowFind();

    if (subWindow <= 0 || !drawRankSourceLabel(subWindow, gLatestRankSourceMode)) {
        gRankSourceStatusDirty = true;
    }
}

/**
 * 保持した最新順位を使ってラベルを再配置する。画面変更時も履歴を走査しない。
 * 同じ画面条件では座標変換に成功した配置時刻を再利用する。
 * 描画または座標変換に失敗した場合は更新待ち状態を維持し、次のイベントで再試行する。
 */
void drawCachedLatestRankLabels() {
    if (gLatestRankLabelsDraw == NULL) {
        gLatestRankPositionKey = "";

        return;
    }

    int subWindow = ChartWindowFind();

    if (subWindow <= 0) {
        gLatestRankPositionKey = "";

        return;
    }

    bool signalDrawn = drawRankSignalLabel(subWindow, gLatestBaseRank, gLatestQuoteRank);
    bool sourceDrawn = drawRankSourceLabel(subWindow, gLatestRankSourceMode);

    if (gLatestRankBarTime <= 0) {
        gLatestRankPositionKey = "";
        gLatestRankLabelsDraw.clear();
        gLatestRankLabelsDirty = !signalDrawn || !sourceDrawn;

        return;
    }

    int baseRank = gLatestBaseRank;
    int quoteRank = gLatestQuoteRank;
    int basePixelOffset = 18;
    int quotePixelOffset = 18;

    if (baseRank == quoteRank) {
        quotePixelOffset = 66;
    }

    string positionKey = getLatestRankLabelPositionKey(subWindow);
    bool reusePosition = positionKey != "" && positionKey == gLatestRankPositionKey;
    bool basePositionResolved = reusePosition;
    bool quotePositionResolved = reusePosition;
    datetime baseLabelTime = gCachedBaseLabelTime;
    datetime quoteLabelTime = gCachedQuoteLabelTime;
    if (!reusePosition) {
        gLatestRankPositionKey = "";
        baseLabelTime = getLatestRankLabelTime(
            subWindow,
            gLatestRankBarTime,
            (double)(0 - baseRank),
            basePixelOffset,
            basePositionResolved
        );
        quoteLabelTime = baseLabelTime;
        quotePositionResolved = basePositionResolved;

        // 同じ横位置は成功した配置時刻を共用し、位置ずらしや失敗時だけ個別に計算する。
        if (quotePixelOffset != basePixelOffset || !basePositionResolved) {
            quoteLabelTime = getLatestRankLabelTime(
                subWindow,
                gLatestRankBarTime,
                (double)(0 - quoteRank),
                quotePixelOffset,
                quotePositionResolved
            );
        }

        if (positionKey != "" && basePositionResolved && quotePositionResolved) {
            gLatestRankPositionKey = positionKey;
            gCachedBaseLabelTime = baseLabelTime;
            gCachedQuoteLabelTime = quoteLabelTime;
        }
    }

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
        gLatestRankLabelsDirty = true;
        gLogger.error(__FUNCTION__, "latest rank label draw failed");

        return;
    }

    gLatestRankLabelsDirty = !signalDrawn || !sourceDrawn
        || !basePositionResolved || !quotePositionResolved;
}

/**
 * 最新順位ラベルの配置時刻を再利用できる画面条件を取得する。
 * 特殊な横縮尺や画面情報の取得失敗時は、従来の座標変換で確認し直す。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @return 画面条件の識別文字列。再利用対象外の場合は空。
 */
string getLatestRankLabelPositionKey(const int fromSubWindow) {
    long chartId = ChartID();
    long scaleFix11 = 0;
    long scalePointsPerBar = 0;
    if (!ChartGetInteger(chartId, CHART_SCALEFIX_11, 0, scaleFix11)
            || !ChartGetInteger(chartId, CHART_SCALE_PT_PER_BAR, 0, scalePointsPerBar)
            || scaleFix11 != 0 || scalePointsPerBar != 0) {
        return "";
    }

    long firstVisibleBar = 0;
    long visibleBars = 0;
    long chartWidth = 0;
    long chartScale = 0;
    long chartShift = 0;
    long windowHeight = 0;
    long windowYDistance = 0;
    double shiftSize = 0.0;
    double priceMin = 0.0;
    double priceMax = 0.0;
    if (!ChartGetInteger(chartId, CHART_FIRST_VISIBLE_BAR, 0, firstVisibleBar)
            || !ChartGetInteger(chartId, CHART_VISIBLE_BARS, 0, visibleBars)
            || !ChartGetInteger(chartId, CHART_WIDTH_IN_PIXELS, 0, chartWidth)
            || !ChartGetInteger(chartId, CHART_SCALE, 0, chartScale)
            || !ChartGetInteger(chartId, CHART_SHIFT, 0, chartShift)
            || !ChartGetInteger(chartId, CHART_HEIGHT_IN_PIXELS, fromSubWindow, windowHeight)
            || !ChartGetInteger(chartId, CHART_WINDOW_YDISTANCE, fromSubWindow, windowYDistance)
            || !ChartGetDouble(chartId, CHART_PRICE_MIN, fromSubWindow, priceMin)
            || !ChartGetDouble(chartId, CHART_PRICE_MAX, fromSubWindow, priceMax)) {
        return "";
    }

    if (chartShift != 0 && !ChartGetDouble(chartId, CHART_SHIFT_SIZE, 0, shiftSize)) {
        return "";
    }

    datetime latestBarTime = iTime(_Symbol, _Period, 0);
    int totalBars = Bars(_Symbol, _Period);
    if (firstVisibleBar < 0 || visibleBars <= 0 || chartWidth <= 0
            || chartScale < 0 || windowHeight <= 0 || windowYDistance < 0
            || latestBarTime <= 0 || totalBars <= 0
            || !MathIsValidNumber(priceMin) || !MathIsValidNumber(priceMax)
            || priceMax <= priceMin || !MathIsValidNumber(shiftSize)) {
        return "";
    }

    return StringFormat(
        "%d/%I64d/%d/%d/%I64d/%d/%I64d/%I64d/%I64d/%I64d/%I64d/%I64d/%I64d/%.17g/%.17g/%.17g",
        fromSubWindow, (long)gLatestRankBarTime, gLatestBaseRank, gLatestQuoteRank,
        (long)latestBarTime, totalBars, firstVisibleBar, visibleBars, chartWidth,
        chartScale, chartShift, windowHeight, windowYDistance, shiftSize, priceMin, priceMax
    );
}

/**
 * 基軸通貨と決済通貨の順位差から売買方向を描画する。
 *
 * 基軸通貨の順位が上の場合はBUY、決済通貨の順位が上の場合はSELLとする。
 * 選択期間の共通強調条件を満たす場合は先頭へ◆を付け、理由をツールチップで示す。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 * @return 描画に成功した場合true。
 */
bool drawRankSignalLabel(
    const int fromSubWindow,
    const int fromBaseRank,
    const int fromQuoteRank
) {
    if (gRankSignalLabelDraw == NULL) {
        return false;
    }

    string signalText = "-";
    color signalColor = clrSilver;

    if (fromBaseRank >= 1
            && fromBaseRank <= 8
            && fromQuoteRank >= 1
            && fromQuoteRank <= 8) {
        int rankDifference = fromQuoteRank - fromBaseRank;
        CurrencyStrengthRankSignal rankSignal = getRankSignal(
            fromBaseRank,
            fromQuoteRank
        );
        signalText = "NON";
        signalColor = clrDimGray;

        if (rankSignal == CURRENCY_STRENGTH_RANK_SIGNAL_BUY) {
            signalText = StringFormat("BUY +%d", rankDifference);
            signalColor = clrAqua;
        } else if (rankSignal == CURRENCY_STRENGTH_RANK_SIGNAL_SELL) {
            signalText = StringFormat("SELL %d", rankDifference);
            signalColor = clrHotPink;
        }

        if (isRankSignalHighlighted(fromBaseRank, fromQuoteRank)) {
            signalText = "◆ " + signalText;
        }
    }

    if (!gRankSignalLabelDraw.draw(
        fromSubWindow,
        signalText,
        signalColor,
        getRankSignalTooltip(fromBaseRank, fromQuoteRank)
    )) {
        gLogger.error(__FUNCTION__, "rank signal label draw failed");

        return false;
    }

    return true;
}

/**
 * DB取得状態の表示記録を初期化する。検索間隔や順位キャッシュは変更しない。
 */
void resetRankQueryDisplayStatus() {
    gRankQueryAttempted = false;
    gLastRankQueryAttemptAt = 0;
    gLastRankQuerySuccessAt = 0;
    gLastRankQueryStartM5BarTime = 0;
    gLastRankQueryEndM5BarTime = 0;
    gLastRankQueryStatus = CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
    gRankCacheUpdateFailed = false;
    gRankSourceStatusDirty = true;
}

/**
 * 表示用のSERVER日時を取得する。
 *
 * @param fromTime 表示する日時。未取得は0。
 * @return 完全な日時、または未取得を示すハイフン。
 */
string getRankQueryTimeText(const datetime fromTime) {
    if (fromTime <= 0) {
        return "-";
    }

    return TimeToString(fromTime, TIME_DATE | TIME_SECONDS);
}

/**
 * 直近のDB取得結果と表示キャッシュへの反映結果を説明する。
 *
 * @return SOURCEツールチップへ表示する結果。
 */
string getRankQueryStatusText() {
    if (!gRankQueryAttempted) {
        return "未取得";
    }

    if (gRankCacheUpdateFailed) {
        return "DB取得成功・表示キャッシュへの反映失敗（旧履歴を保持）";
    }

    if (gLastRankQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
        return "DB取得エラー（旧履歴を保持）";
    }

    if (gLastRankQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
        return "今回の検索範囲の参照DBがありません";
    }

    if (gLastRankQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND) {
        return "取得成功（今回の検索範囲に該当レコードなし）";
    }

    return "取得成功";
}

/**
 * 表示中の順位の時刻とDB取得状態を説明する。
 *
 * @param fromSourceMode 表示中順位の取得元。
 * @param fromM5BarTime 表示中順位が参照するM5時刻。
 * @return 日付を含むSERVER日時と直近取得結果。
 */
string getRankSourceTooltip(const string fromSourceMode, const datetime fromM5BarTime) {
    string sourceMode = fromSourceMode;
    if (sourceMode == "") {
        sourceMode = "-";
    }

    string tooltip = "表示順位の参照元：" + sourceMode
        + "\n表示順位のM5時刻 SERVER：" + getRankQueryTimeText(fromM5BarTime)
        + "\n直近DB取得結果：" + getRankQueryStatusText()
        + "\n直近DB取得試行 SERVER：" + getRankQueryTimeText(gLastRankQueryAttemptAt)
        + "\n最終DB取得成功 SERVER：" + getRankQueryTimeText(gLastRankQuerySuccessAt);
    if (gRankQueryAttempted) {
        tooltip += "\n直近検索範囲 SERVER：" + getRankQueryTimeText(gLastRankQueryStartM5BarTime)
            + " ～ " + getRankQueryTimeText(gLastRankQueryEndM5BarTime);
    }

    tooltip += "\nM1は同じM5内の順位を共用し、H1以上はチャート足開始のM5順位を表示します。";

    return tooltip;
}

/**
 * 最新順位点の取得元・参照時刻・DB取得状態を描画する。
 *
 * @param fromSubWindow 描画対象サブウィンドウ番号。
 * @param fromSourceMode 最新順位点の集計実行モード。
 * @return 描画に成功した場合true。
 */
bool drawRankSourceLabel(
    const int fromSubWindow,
    const string fromSourceMode
) {
    gRankSourceStatusDirty = true;
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

    datetime sourceM5BarTime = floorToM5(gLatestRankBarTime);
    if (sourceM5BarTime > 0 && fromSourceMode != "") {
        sourceText += " / " + TimeToString(sourceM5BarTime, TIME_MINUTES);
    }

    if (gRankCacheUpdateFailed) {
        sourceText += " [反映エラー]";
        sourceColor = clrOrange;
    } else if (gRankQueryAttempted
            && gLastRankQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
        sourceText += " [取得エラー]";
        sourceColor = clrOrange;
    } else if (gRankQueryAttempted
            && gLastRankQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
        sourceText += " [DBなし]";
        sourceColor = clrOrange;
    }

    if (!gRankSourceLabelDraw.draw(
        fromSubWindow,
        sourceText,
        sourceColor,
        getRankSourceTooltip(fromSourceMode, sourceM5BarTime)
    )) {
        gLogger.error(__FUNCTION__, "rank source label draw failed");

        return false;
    }

    gRankSourceStatusDirty = false;

    return true;
}

/**
 * 最新足から指定ピクセル数だけ右側となる時刻を取得する。
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
 * M5の秒数は初期化時に取得した値を共用する。
 *
 * @param fromTime 切り下げ対象時刻。
 * @return M5バー開始時刻。
 */
datetime floorToM5(const datetime fromTime) {
    if (fromTime <= 0 || gM5Seconds <= 0) {
        return 0;
    }

    long timeSeconds = (long)fromTime;

    return (datetime)(timeSeconds - (timeSeconds % gM5Seconds));
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
 * 初回・表示開始の後退・手動再読込時は全期間、それ以外はキャッシュ末尾M5から取得する。
 *
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 * @param fromTargetM5BarTime 表示終端M5時刻。
 * @param fromChangedStartM5BarTime 変更確認範囲の開始M5時刻。
 * @param fromBufferChanged 初回取得、選択期間の順位変更または履歴構成の変更があった場合true。
 * @param fromSourceChanged 取得元または履歴構成の変更があった場合true。
 * @param fromRibbonChanged 帯の判定結果または履歴構成の変更があった場合true。
 * @param fromForceFullRange 手動再読込として全表示期間を取得し、DB不在時も旧履歴を保持する場合true。
 * @return DB検索に成功した場合true。
 */
bool refreshRankPoints(
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime,
    datetime &fromChangedStartM5BarTime,
    bool &fromBufferChanged,
    bool &fromSourceChanged,
    bool &fromRibbonChanged,
    const bool fromForceFullRange = false
) {
    fromBufferChanged = false;
    fromSourceChanged = false;
    fromRibbonChanged = false;

    if (!fromForceFullRange) {
        gLastQueryTargetM5BarTime = fromTargetM5BarTime;
        gLastQueryTickCount = GetTickCount64();
    }

    datetime queryStartM5BarTime = fromDisplayStartM5BarTime;
    int cachedPointCount = getRankPointCount();
    datetime lastCachedM5BarTime = 0;

    if (cachedPointCount > 0) {
        lastCachedM5BarTime =
            gRankPoints[gRankPointStartIndex + cachedPointCount - 1].m5BarTime;
    }

    if (!fromForceFullRange && gRankPointCacheReady && cachedPointCount > 0
            && fromDisplayStartM5BarTime >= gRankPointDisplayStartM5BarTime) {
        if (lastCachedM5BarTime >= fromDisplayStartM5BarTime
                && lastCachedM5BarTime <= fromTargetM5BarTime) {
            queryStartM5BarTime = lastCachedM5BarTime;
        }
    }

    CurrencyStrengthPairRankPoint queriedPoints[];
    // 検索範囲の両端のM5足と従来の余裕1件を含め、DAOの予約容量を抑える。
    long queryRangeSeconds = (long)fromTargetM5BarTime - (long)queryStartM5BarTime;
    int maximumPointCount = (int)(queryRangeSeconds / gM5Seconds) + 2;

    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
        CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;

    gRankQueryAttempted = true;
    gLastRankQueryAttemptAt = TimeCurrent();
    gLastRankQueryStartM5BarTime = queryStartM5BarTime;
    gLastRankQueryEndM5BarTime = fromTargetM5BarTime;
    gRankCacheUpdateFailed = false;
    gRankSourceStatusDirty = true;

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

    gLastRankQueryStatus = queryStatus;
    if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
            || queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND) {
        gLastRankQuerySuccessAt = TimeCurrent();
    }

    if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR
            || (fromForceFullRange
                && queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND)) {
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
    bool rangeBufferChanged = false;
    bool rangeSourceChanged = false;
    bool rangeRibbonChanged = false;
    bool rangeTooltipChanged = false;
    bool rangeChanged = isCacheRangeChanged(
        queryStartM5BarTime,
        queriedPoints,
        rangeBufferChanged,
        rangeSourceChanged,
        rangeRibbonChanged,
        rangeTooltipChanged
    );

    if (rangeChanged && !replaceCacheRange(queryStartM5BarTime, queriedPoints)) {
        gRankCacheUpdateFailed = true;
        gLogger.error(__FUNCTION__, "rank point cache update failed");

        return false;
    }

    if (rangeRibbonChanged && gRankAndRibbonDraw != NULL) {
        datetime changedEndM5BarTime = fromTargetM5BarTime;

        if (lastCachedM5BarTime > changedEndM5BarTime) {
            changedEndM5BarTime = lastCachedM5BarTime;
        }

        // 取得上限の後退で削除された旧末尾も、帯の変更範囲に含める。
        gRankAndRibbonDraw.invalidateDataRange(queryStartM5BarTime, changedEndM5BarTime);
    }

    int pointCountBeforePrune = getRankPointCount();
    pruneRankPoints(fromDisplayStartM5BarTime);
    gRankPointCacheReady = true;
    bool structureChanged = initialLoad || pointCountBeforePrune != getRankPointCount();
    if ((rangeTooltipChanged || structureChanged) && gRankAndRibbonDraw != NULL) {
        gRankAndRibbonDraw.invalidateHoverData();
        gRankRibbonTooltipDirty = true;
    }

    fromBufferChanged = structureChanged || rangeBufferChanged;
    fromSourceChanged = structureChanged || rangeSourceChanged;
    fromRibbonChanged = structureChanged || rangeRibbonChanged;
    fromChangedStartM5BarTime = fromTargetM5BarTime;

    if (initialLoad) {
        gLogger.info(
            __FUNCTION__,
            StringFormat(
                "rank history loaded. sourceMode=%s points=%d from=%s to=%s",
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

    if (rangeBufferChanged) {
        fromChangedStartM5BarTime = queryStartM5BarTime;
    }

    if (fromForceFullRange) {
        gLastQueryTargetM5BarTime = fromTargetM5BarTime;
        gLastQueryTickCount = GetTickCount64();
    }

    return true;
}

/**
 * 再取得範囲の内容が現在のキャッシュと異なるか判定する。
 *
 * @param fromRangeStartM5BarTime 再取得範囲の開始M5時刻。
 * @param fromPoints 再取得した順位履歴。
 * @param fromBufferChanged 件数・M5時刻・選択期間の順位が異なる場合true。
 * @param fromSourceChanged 件数・M5時刻・取得元が異なる場合true。
 * @param fromRibbonChanged 件数・M5時刻・順位の有効性・帯の状態が異なる場合true。
 * @param fromTooltipChanged 件数・M5時刻・両期間の順位・取得元が異なる場合true。
 * @return 管理情報を含めて異なる場合true。
 */
bool isCacheRangeChanged(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthPairRankPoint &fromPoints[],
    bool &fromBufferChanged,
    bool &fromSourceChanged,
    bool &fromRibbonChanged,
    bool &fromTooltipChanged
) {
    fromBufferChanged = false;
    fromSourceChanged = false;
    fromRibbonChanged = false;
    fromTooltipChanged = false;
    int keepCount = getCacheKeepCount(fromRangeStartM5BarTime);
    int cachedTailCount = getRankPointCount() - keepCount;
    int queriedPointCount = ArraySize(fromPoints);
    int replaceStartIndex = gRankPointStartIndex + keepCount;

    if (cachedTailCount != queriedPointCount) {
        fromBufferChanged = true;
        fromSourceChanged = true;
        fromRibbonChanged = true;
        fromTooltipChanged = true;

        return true;
    }

    bool cacheChanged = false;
    bool longMediumOnly = PeriodSeconds(_Period) >= PeriodSeconds(PERIOD_H1);

    for (int i = 0; i < queriedPointCount; i++) {
        if (gRankPoints[replaceStartIndex + i].m5BarTime != fromPoints[i].m5BarTime) {
            fromBufferChanged = true;
            fromSourceChanged = true;
            fromRibbonChanged = true;
            fromTooltipChanged = true;

            return true;
        }

        if (!isSameRankPointDisplay(gRankPoints[replaceStartIndex + i], fromPoints[i])) {
            cacheChanged = true;
            fromTooltipChanged = true;

            if (!fromBufferChanged && !isSameRankPointBuffer(
                gRankPoints[replaceStartIndex + i], fromPoints[i]
            )) {
                fromBufferChanged = true;
            }

            if (gRankPoints[replaceStartIndex + i].sourceMode != fromPoints[i].sourceMode) {
                fromSourceChanged = true;
            }

            if (!fromRibbonChanged && !isSameRankPointRibbon(
                gRankPoints[replaceStartIndex + i], fromPoints[i], longMediumOnly
            )) {
                fromRibbonChanged = true;
            }

            if (fromBufferChanged && fromSourceChanged && fromRibbonChanged) {
                return true;
            }

            // 後続行にある選択期間・取得元・帯の変更も確認する。
            continue;
        }

        // 管理情報だけの変更でも後続の表示内容の比較は続ける。
        if (gRankPoints[replaceStartIndex + i].runId != fromPoints[i].runId
                || gRankPoints[replaceStartIndex + i].updatedAt != fromPoints[i].updatedAt) {
            cacheChanged = true;
        }
    }

    return cacheChanged;
}

/**
 * 2つの順位履歴点が同じか判定する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @return 同じ場合true。
 */
bool isSameRankPoint(
    const CurrencyStrengthPairRankPoint &fromLeft,
    const CurrencyStrengthPairRankPoint &fromRight
) {
    return fromLeft.runId == fromRight.runId
        && fromLeft.updatedAt == fromRight.updatedAt
        && isSameRankPointDisplay(fromLeft, fromRight);
}

/**
 * 2つの順位履歴点の表示に使う内容が同じか判定する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @return M5時刻・順位・取得元が同じ場合true。
 */
bool isSameRankPointDisplay(
    const CurrencyStrengthPairRankPoint &fromLeft,
    const CurrencyStrengthPairRankPoint &fromRight
) {
    return fromLeft.m5BarTime == fromRight.m5BarTime
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
 * 2つの順位履歴点の選択期間の順位が同じか判定する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @return 選択期間の基軸通貨・決済通貨の順位が同じ場合true。
 */
bool isSameRankPointBuffer(
    const CurrencyStrengthPairRankPoint &fromLeft,
    const CurrencyStrengthPairRankPoint &fromRight
) {
    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT) {
        return fromLeft.baseMediumShortTermAverageRank
                == fromRight.baseMediumShortTermAverageRank
            && fromLeft.quoteMediumShortTermAverageRank
                == fromRight.quoteMediumShortTermAverageRank;
    }

    return fromLeft.baseLongMediumTermAverageRank
            == fromRight.baseLongMediumTermAverageRank
        && fromLeft.quoteLongMediumTermAverageRank
            == fromRight.quoteLongMediumTermAverageRank;
}

/**
 * 2つの順位履歴点が、帯の描画に同じ結果を与えるか判定する。
 * 無効順位と有効な待機状態を区別し、開始位置の白色判定を維持する。
 *
 * @param fromLeft 比較対象1。
 * @param fromRight 比較対象2。
 * @param fromLongMediumOnly 長中期のみで帯を判定する場合true。
 * @return M5時刻・順位の有効性・帯の状態が同じ場合true。
 */
bool isSameRankPointRibbon(
    const CurrencyStrengthPairRankPoint &fromLeft,
    const CurrencyStrengthPairRankPoint &fromRight,
    const bool fromLongMediumOnly
) {
    if (fromLeft.m5BarTime != fromRight.m5BarTime) {
        return false;
    }

    bool leftKnown = CurrencyStrengthRankAndSignal::hasValidRibbonRanks(
        fromLeft, fromLongMediumOnly
    );
    bool rightKnown = CurrencyStrengthRankAndSignal::hasValidRibbonRanks(
        fromRight, fromLongMediumOnly
    );

    if (leftKnown != rightKnown) {
        return false;
    }

    if (!leftKnown) {
        return true;
    }

    return CurrencyStrengthRankAndSignal::getRibbonState(
        fromLeft, rankSignalHighlightDifference, fromLongMediumOnly
    ) == CurrencyStrengthRankAndSignal::getRibbonState(
        fromRight, rankSignalHighlightDifference, fromLongMediumOnly
    );
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
 * @param fromPoints 置換する順位履歴。
 * @return キャッシュ更新に成功した場合true。
 */
bool replaceCacheRange(
    const datetime fromRangeStartM5BarTime,
    CurrencyStrengthPairRankPoint &fromPoints[]
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

        if (pointIndex < cachedArraySize
                && isSameRankPoint(gRankPoints[pointIndex], fromPoints[i])) {
            continue;
        }

        gRankPoints[pointIndex] = fromPoints[i];
    }

    return true;
}

/**
 * 表示期間より古い順位履歴点を参照対象から外し、先頭の前詰めをまとめて行う。
 *
 * @param fromDisplayStartM5BarTime 表示開始M5時刻。
 */
void pruneRankPoints(const datetime fromDisplayStartM5BarTime) {
    gRankPointDisplayStartM5BarTime = fromDisplayStartM5BarTime;
    int expiredPointCount = getCacheKeepCount(fromDisplayStartM5BarTime);

    if (expiredPointCount > 0 && gRankAndRibbonDraw != NULL) {
        gRankAndRibbonDraw.invalidateDataRange(
            gRankPoints[gRankPointStartIndex].m5BarTime,
            gRankPoints[gRankPointStartIndex + expiredPointCount - 1].m5BarTime
        );
    }

    gRankPointStartIndex += expiredPointCount;

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
 * 全表示バッファを再構築する。
 */
void fillAllBuffers(
    const int fromRatesTotal,
    const datetime &fromTime[],
    const datetime fromDisplayStartM5BarTime,
    const datetime fromTargetM5BarTime
) {
    // DRAW_FILLINGはEMPTY_VALUEの区間を接続するため、非表示区間には0を使用する。
    ArrayInitialize(gBaseRankFillBuffer, 0.0);
    ArrayInitialize(gQuoteRankFillBuffer, 0.0);
    ArrayInitialize(gBaseDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gQuoteDisplayRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gBaseActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gQuoteActualRankBuffer, EMPTY_VALUE);
    ArrayInitialize(gRankSignalDisplayBuffer, EMPTY_VALUE);
    ArrayInitialize(gRankSignalColorBuffer, EMPTY_VALUE);

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
 * 新規・再計算対象バーの表示値を設定する。
 *
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
 * 同じ更新処理内で同じM5時刻が続く場合は、計算済みの表示値を再利用する。
 * 欠損・無効順位の空値と塗りの0も再利用し、次の更新処理へは持ち越さない。
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

    gBaseDisplayRankBuffer[fromBufferIndex] = gBaseDisplayRankBuffer[fromCachedBufferIndex];
    gQuoteDisplayRankBuffer[fromBufferIndex] = gQuoteDisplayRankBuffer[fromCachedBufferIndex];
    gBaseActualRankBuffer[fromBufferIndex] = gBaseActualRankBuffer[fromCachedBufferIndex];
    gQuoteActualRankBuffer[fromBufferIndex] = gQuoteActualRankBuffer[fromCachedBufferIndex];
    gRankSignalDisplayBuffer[fromBufferIndex] = gRankSignalDisplayBuffer[fromCachedBufferIndex];
    gRankSignalColorBuffer[fromBufferIndex] = gRankSignalColorBuffer[fromCachedBufferIndex];
    gBaseRankFillBuffer[fromBufferIndex] = gBaseRankFillBuffer[fromCachedBufferIndex];
    gQuoteRankFillBuffer[fromBufferIndex] = gQuoteRankFillBuffer[fromCachedBufferIndex];
}

/**
 * 指定バーへ対応するM5順位を設定する。
 *
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

    int baseRank = gRankPoints[pointIndex].baseLongMediumTermAverageRank;
    int quoteRank = gRankPoints[pointIndex].quoteLongMediumTermAverageRank;

    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_MEDIUM_SHORT) {
        baseRank = gRankPoints[pointIndex].baseMediumShortTermAverageRank;
        quoteRank = gRankPoints[pointIndex].quoteMediumShortTermAverageRank;
    }

    if (baseRank < 1
            || baseRank > 8
            || quoteRank < 1
            || quoteRank > 8) {
        clearBufferValues(fromBufferIndex);

        return;
    }

    gBaseDisplayRankBuffer[fromBufferIndex] = getDisplayRankValue(baseRank);
    gQuoteDisplayRankBuffer[fromBufferIndex] = getDisplayRankValue(quoteRank);
    gBaseActualRankBuffer[fromBufferIndex] = getActualRankValue(baseRank);
    gQuoteActualRankBuffer[fromBufferIndex] = getActualRankValue(quoteRank);
    gRankSignalDisplayBuffer[fromBufferIndex] = rankSignalDisplayPosition;
    gRankSignalColorBuffer[fromBufferIndex] = (double)getRankSignalColorIndex(
        baseRank,
        quoteRank
    );

    gBaseRankFillBuffer[fromBufferIndex] = 0.0;
    gQuoteRankFillBuffer[fromBufferIndex] = 0.0;

    if (isRankSignalHighlighted(baseRank, quoteRank)) {
        gBaseRankFillBuffer[fromBufferIndex] = gBaseDisplayRankBuffer[fromBufferIndex];
        gQuoteRankFillBuffer[fromBufferIndex] = gQuoteDisplayRankBuffer[fromBufferIndex];
    }
}

/**
 * 指定バーの表示値と実順位を空値へ戻す。
 */
void clearBufferValues(const int fromBufferIndex) {
    gBaseRankFillBuffer[fromBufferIndex] = 0.0;
    gQuoteRankFillBuffer[fromBufferIndex] = 0.0;
    gBaseDisplayRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gQuoteDisplayRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gBaseActualRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gQuoteActualRankBuffer[fromBufferIndex] = EMPTY_VALUE;
    gRankSignalDisplayBuffer[fromBufferIndex] = EMPTY_VALUE;
    gRankSignalColorBuffer[fromBufferIndex] = EMPTY_VALUE;
}

/**
 * M5時刻が完全一致する順位履歴点を二分検索する。
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
 * 選択期間の基軸通貨と決済通貨の順位から売買方向を取得する。
 *
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 * @return BUY、SELLまたはNON。
 */
CurrencyStrengthRankSignal getRankSignal(
    const int fromBaseRank,
    const int fromQuoteRank
) {
    int rankDifference = fromQuoteRank - fromBaseRank;

    if (rankDifference > 0) {
        return CURRENCY_STRENGTH_RANK_SIGNAL_BUY;
    }

    if (rankDifference < 0) {
        return CURRENCY_STRENGTH_RANK_SIGNAL_SELL;
    }

    return CURRENCY_STRENGTH_RANK_SIGNAL_NON;
}

/**
 * 売買方向と選択期間の共通強調条件から方向バーの色番号を取得する。
 *
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 * @return 強調BUYは0、強調SELLは1、同順位は2、通常BUYは3、通常SELLは4。
 */
int getRankSignalColorIndex(
    const int fromBaseRank,
    const int fromQuoteRank
) {
    CurrencyStrengthRankSignal rankSignal = getRankSignal(
        fromBaseRank,
        fromQuoteRank
    );
    if (!isRankSignalHighlighted(fromBaseRank, fromQuoteRank)) {
        if (rankSignal == CURRENCY_STRENGTH_RANK_SIGNAL_BUY) {
            return 3;
        }

        if (rankSignal == CURRENCY_STRENGTH_RANK_SIGNAL_SELL) {
            return 4;
        }
    }

    return (int)rankSignal;
}

/**
 * 選択期間の塗り・方向バー・◆に使用する共通強調条件を判定する。
 * 長中期は順位差または端順位、中短期は順位差だけを使用する。
 *
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 * @return 強調対象の場合true。同順位と無効順位は対象外。
 */
bool isRankSignalHighlighted(const int fromBaseRank, const int fromQuoteRank) {
    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM) {
        return CurrencyStrengthRankAndSignal::getLongMediumDirection(
            fromBaseRank, fromQuoteRank, rankSignalHighlightDifference
        ) != 0;
    }

    if (fromBaseRank < 1 || fromBaseRank > 8
            || fromQuoteRank < 1 || fromQuoteRank > 8) {
        return false;
    }

    return MathAbs(fromQuoteRank - fromBaseRank) >= rankSignalHighlightDifference;
}

/**
 * 最新の順位と、選択期間の強調条件・成立理由をツールチップへまとめる。
 *
 * @param fromBaseRank 基軸通貨の順位。
 * @param fromQuoteRank 決済通貨の順位。
 * @return 塗り・方向バー・◆に共通する強調条件と最新順位の理由。
 */
string getRankSignalTooltip(const int fromBaseRank, const int fromQuoteRank) {
    string tooltip = getRankPeriodLabel() + "の塗り・方向バー・◆：順位差"
        + (string)rankSignalHighlightDifference + "以上";
    if (rankPeriod == CURRENCY_STRENGTH_RANK_PERIOD_LONG_MEDIUM) {
        tooltip += "、または強い通貨が1位、または弱い通貨が8位";
    }

    if (fromBaseRank < 1 || fromBaseRank > 8
            || fromQuoteRank < 1 || fromQuoteRank > 8) {
        return tooltip + "\n順位未取得";
    }

    int rankDifference = fromQuoteRank - fromBaseRank;
    tooltip += StringFormat("\n%s %d位 / %s %d位（順位差の大きさ%d）",
        gBaseCurrency, fromBaseRank, gQuoteCurrency, fromQuoteRank,
        (int)MathAbs(rankDifference));
    if (!isRankSignalHighlighted(fromBaseRank, fromQuoteRank)) {
        if (rankDifference == 0) {
            return tooltip + "\n同順位のため強調なし";
        }

        return tooltip + "\n強調条件未達";
    }

    if (MathAbs(rankDifference) >= rankSignalHighlightDifference) {
        return tooltip + "\n強調理由：順位差" + (string)rankSignalHighlightDifference + "以上";
    }

    string strongCurrency = gBaseCurrency;
    string weakCurrency = gQuoteCurrency;
    int strongRank = fromBaseRank;
    int weakRank = fromQuoteRank;
    if (rankDifference < 0) {
        strongCurrency = gQuoteCurrency;
        weakCurrency = gBaseCurrency;
        strongRank = fromQuoteRank;
        weakRank = fromBaseRank;
    }

    if (strongRank == 1) {
        tooltip += "\n強調理由：強い通貨（買う" + strongCurrency + "）が1位";
    }
    if (weakRank == 8) {
        tooltip += "\n強調理由：弱い通貨（売る" + weakCurrency + "）が8位";
    }

    return tooltip;
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
