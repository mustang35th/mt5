//+------------------------------------------------------------------+
//|                                                      MstngEa.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: Experts
 * File: MstngEa.mq5
 */

#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.07"

#property strict

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Service\CurrencyStrengthExecutionInfoProvider.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <MstngEa\App\EaContext.mqh>
#include <MstngEa\App\EaController.mqh>
#include <MstngEa\App\StrategyFactory.mqh>
#include <MstngEa\Config\EaConfig.mqh>
#include <MstngEa\Config\H1PositionManagementMode.mqh>
#include <MstngEa\Trade\MagicNumberUtil.mqh>

input group "01. 基本設定"

/** 戦略種別 */
input(name="使用戦略") StrategyType InpStrategyType =
    STRATEGY_TYPE_MTF_3IN3;

/** ロット */
input(name="固定ロット") double InpLotSize = 0.01;

input group "02. 画面表示"

/** パネル再描画間隔ミリ秒 */
input(name="パネル更新間隔（ミリ秒）")
int InpPanelRefreshMilliseconds = 1000;

input group "03. 利益保護・決済（LEGACY）"

/** 利益戻し決済使用 */
input(name="利益戻し決済を使用")
bool InpUseProfitRetracementExit = true;

/** 利益戻し決済開始R倍率 */
input(name="利益戻し監視開始（R）")
double InpProfitRetracementStartR = 1.5;

/** 利益戻し決済戻し率 */
input(name="利益戻し許容率（0.30＝30%）")
double InpProfitRetracementRate = 0.30;

/** 建値移動使用 */
input(name="建値移動を使用") bool InpUseBreakEven = true;

/** 建値移動発動R倍率 */
input(name="建値移動開始（R）") double InpBreakEvenTriggerR = 1.0;

/** 建値移動加算pips */
input(name="建値から追加保護（pips）")
double InpBreakEvenPlusPips = 1.0;

input group "04. 通貨強弱フィルター"

/** 通貨強弱利用 */
input(name="通貨強弱を使用") bool InpUseCurrencyStrength = false;

/** 通貨強弱DB参照プロファイル */
input(name="DB参照元（AUTO推奨）")
CurrencyStrengthRankDatabaseProfile InpCurrencyStrengthDatabaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_AUTO;

/** 通貨強弱DBファイル名 */
input(name="DBファイル名") string InpCurrencyStrengthDatabaseFileName =
    "mstng-currency-strength.sqlite";

/** 通貨強弱DB年単位分割 */
input(name="年別DBを使用")
bool InpCurrencyStrengthDatabaseSplitByYear = true;

/** 通貨強弱DB共通フォルダ使用 */
input(name="Commonフォルダを使用")
bool InpCurrencyStrengthDatabaseUseCommonFolder = true;

/** 通貨強弱DB再取得間隔秒 */
input(name="再取得間隔（秒）") int InpCurrencyStrengthRefreshSeconds = 15;

/** 通貨強弱票重み付け方式 */
input(name="投票方式")
CurrencyStrengthVoteWeightMode InpCurrencyStrengthVoteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

input group "05. 検証出力（MTF_3in3）"

/** MTF_3in3アラート検証CSV出力 */
input(name="Alert検証CSVを出力") bool InpMtf3In3AlertCsvEnabled = false;

input group "06. M5エントリー条件（MTF_3in3）"

/** H1表示波ごとのエントリー回数制限を使用する場合true。 */
input(name="同一H1表示波は1回まで")
bool InpH1DisplayWaveEntryLimitEnabled = false;

input group "07. H1エントリー条件（MTF_3in3）"

/** H1エントリーで使用するW1確認モード。 */
input(name="W1確認") H1W1ConfirmationMode InpH1W1ConfirmationMode =
    H1_W1_CONFIRMATION_OBSERVE_ONLY;

/** H1エントリーで使用するEMA200確認モード。 */
input(name="EMA200確認")
H1Ema200ConfirmationMode InpH1Ema200ConfirmationMode =
    H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED;

input group "08. H1ポジション管理（H1 MTF_3in3）"

/** H1ポジションの決済管理モード。 */
input(name="H1ポジション管理")
H1PositionManagementMode InpH1PositionManagementMode =
    H1_POSITION_MANAGEMENT_LEGACY;

/** H1 ZigZagトレイルのSLバッファー（pips）。 */
input(name="ZigZagトレイル余白（pips）")
double InpH1ZigZagTrailBufferPips = 5.0;

/** シンボル名 */
string g_symbolName;

/** 時間足 */
ENUM_TIMEFRAMES g_timeFrame;

/** Market context */
MarketContext g_marketContext;

/** オシレータハンドルプール */
OscillatorHandlePool *g_oscillatorHandlePool;

/** シグナル回数 */
SignalCount *g_signalCount;

/** EA設定 */
EaConfig *g_eaConfig;

/** EAコンテキスト */
EaContext *g_eaContext;

/** 通貨強弱実行情報取得 */
CurrencyStrengthExecutionInfoProvider *g_currencyStrengthExecutionInfoProvider;

/** EA制御 */
EaController *g_eaController;

/**
 * 初期化
 *
 * @return 初期化結果
 */
int OnInit() {
    if (!isH1PositionManagementModeValid(InpH1PositionManagementMode)) {
        Print("MstngEa H1 position management mode is invalid");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpH1PositionManagementMode
            == H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY
            && (_Period != PERIOD_H1
                || InpStrategyType != STRATEGY_TYPE_MTF_3IN3)) {
        Print("MstngEa H1 ZigZag trail only mode requires H1 MTF_3in3");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpH1PositionManagementMode
            == H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY
            && InpH1ZigZagTrailBufferPips < 0.0) {
        Print("MstngEa H1 ZigZag trail buffer pips must be zero or greater");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!isH1W1ConfirmationModeValid(InpH1W1ConfirmationMode)) {
        Print("MstngEa H1 W1 confirmation mode is invalid");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!isH1Ema200ConfirmationModeValid(
            InpH1Ema200ConfirmationMode
    )) {
        Print("MstngEa H1 EMA200 confirmation mode is invalid");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpUseCurrencyStrength
            && InpCurrencyStrengthDatabaseFileName == "") {
        Print("MstngEa requires currency strength database file name");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpUseCurrencyStrength && InpCurrencyStrengthRefreshSeconds < 0) {
        Print("MstngEa currency strength refresh seconds must be zero or greater");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpUseCurrencyStrength
            && !CurrencyStrengthCalculationProfile::isVoteWeightModeValid(
                InpCurrencyStrengthVoteWeightMode
            )) {
        Print("MstngEa currency strength vote weight mode is invalid");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpUseCurrencyStrength
            && MQLInfoInteger(MQL_TESTER)
            && !InpCurrencyStrengthDatabaseUseCommonFolder) {
        Print("MstngEa requires Common database folder in Strategy Tester");

        return INIT_PARAMETERS_INCORRECT;
    }

    // 基本情報を初期化
    g_symbolName = _Symbol;
    g_timeFrame = _Period;
    g_marketContext = MarketContext(g_symbolName, g_timeFrame);

    // 共有オブジェクトを生成
    g_oscillatorHandlePool = new OscillatorHandlePool(g_marketContext);
    g_oscillatorHandlePool.setTimeframesFromD1To();

    g_signalCount = new SignalCount(g_marketContext);
    g_eaConfig = new EaConfig();
    g_eaConfig.strategyType = InpStrategyType;
    g_eaConfig.lotSize = InpLotSize;
    g_eaConfig.useProfitRetracementExit = InpUseProfitRetracementExit;
    g_eaConfig.profitRetracementStartR = InpProfitRetracementStartR;
    g_eaConfig.profitRetracementRate = InpProfitRetracementRate;
    g_eaConfig.useBreakEven = InpUseBreakEven;
    g_eaConfig.breakEvenTriggerR = InpBreakEvenTriggerR;
    g_eaConfig.breakEvenPlusPips = InpBreakEvenPlusPips;
    g_eaConfig.useCurrencyStrength = InpUseCurrencyStrength;
    g_eaConfig.mtf3In3AlertCsvEnabled = InpMtf3In3AlertCsvEnabled;
    g_eaConfig.h1DisplayWaveEntryLimitEnabled =
        InpH1DisplayWaveEntryLimitEnabled;
    g_eaConfig.h1PositionManagementMode = InpH1PositionManagementMode;
    g_eaConfig.h1ZigZagTrailBufferPips = InpH1ZigZagTrailBufferPips;
    g_eaConfig.h1W1ConfirmationMode = InpH1W1ConfirmationMode;
    g_eaConfig.h1Ema200ConfirmationMode =
        InpH1Ema200ConfirmationMode;

    if (g_eaConfig.h1PositionManagementMode
            == H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY) {
        g_eaConfig.useProfitRetracementExit = false;
        g_eaConfig.useBreakEven = false;
    }

    g_eaContext = new EaContext();

    // コンテキストへ依存を設定
    g_eaContext.marketContext = g_marketContext;
    g_eaContext.symbolName = g_symbolName;
    g_eaContext.timeFrame = g_timeFrame;
    g_eaContext.oscillatorHandlePool = g_oscillatorHandlePool;
    g_eaContext.signalCount = g_signalCount;
    g_eaContext.eaConfig = g_eaConfig;
    g_eaContext.profitRetracementState = new ProfitRetracementState();
    g_eaContext.magicNumber = MagicNumberUtil::build(
        11,
        g_marketContext,
        g_eaConfig.strategyType
    );
    bool isProfitRetracementPersistenceEnabled = !MQLInfoInteger(MQL_TESTER);
    g_eaContext.profitRetracementStateStore = new ProfitRetracementStateStore(
        g_marketContext,
        g_eaContext.magicNumber,
        isProfitRetracementPersistenceEnabled
    );

    if (g_eaContext.profitRetracementStateStore == NULL) {
        Print("MstngEa ProfitRetracementStateStore create failed");
        return INIT_FAILED;
    }

    g_eaContext.operationLogger = new OperationLogger(g_marketContext);

    if (g_eaConfig.useCurrencyStrength) {
        g_currencyStrengthExecutionInfoProvider =
            new CurrencyStrengthExecutionInfoProvider(
                InpCurrencyStrengthDatabaseFileName,
                InpCurrencyStrengthDatabaseSplitByYear,
                InpCurrencyStrengthDatabaseUseCommonFolder,
                InpCurrencyStrengthDatabaseProfile,
                CURRENCY_STRENGTH_RANK_QUERY_MODE_EXACT,
                InpCurrencyStrengthRefreshSeconds,
                InpCurrencyStrengthVoteWeightMode
            );

        if (g_currencyStrengthExecutionInfoProvider == NULL) {
            g_eaContext.operationLogger.error(
                "MstngEa",
                "CurrencyStrengthExecutionInfoProvider create failed"
            );
            return INIT_FAILED;
        }

        g_eaContext.currencyStrengthExecutionInfoProvider =
            g_currencyStrengthExecutionInfoProvider;
    }

    g_eaContext.tradeCsvLogger = new TradeCsvLogger(
        g_marketContext,
        g_eaContext.magicNumber
    );
    g_eaContext.closeTradeCsvLogger = new CloseTradeCsvLogger(
        g_marketContext,
        g_eaContext.magicNumber
    );
    g_eaContext.statusLabelView = new StatusLabelView(0, g_eaConfig.statusLabelName);
    g_eaContext.signalAlertTextView = new SignalAlertTextView(
        0,
        g_eaConfig.statusLabelName + "_SignalAlert"
    );
    g_eaContext.closeProfitTextView = new CloseProfitTextView(
        0,
        g_eaConfig.statusLabelName + "_CloseProfit"
    );
    g_eaContext.elliottInfoPanelView = new ElliottInfoPanelView(
        0,
        g_eaConfig.statusLabelName + "_ElliottInfo"
    );
    g_eaContext.newBarDetector = new NewBarDetector(g_marketContext);
    g_eaContext.positionService = new PositionService(g_marketContext, g_eaContext.magicNumber);
    g_eaContext.tradeExecutor = new TradeExecutor(
        g_marketContext,
        g_eaContext.magicNumber,
        g_eaConfig.lotSize,
        g_eaContext.operationLogger,
        g_eaContext.tradeCsvLogger,
        g_eaContext.closeTradeCsvLogger,
        g_eaContext.closeProfitTextView
    );
    g_eaContext.strategyAdapter = StrategyFactory::create(
        g_eaConfig.strategyType,
        g_marketContext,
        g_signalCount,
        g_eaConfig.h1W1ConfirmationMode,
        g_eaConfig.h1Ema200ConfirmationMode
    );

    // 画面表示を生成
    g_eaContext.statusLabelView.create();
    g_eaContext.elliottInfoPanelView.create();

    // 制御クラスを生成
    g_eaController = new EaController(g_eaContext);

    // パネル再描画タイマーを開始
    EventSetMillisecondTimer(InpPanelRefreshMilliseconds);

    return INIT_SUCCEEDED;
}

/**
 * ティック処理
 */
void OnTick() {

    if (g_eaController == NULL) {
        return;
    }

    // EA制御へ委譲
    g_eaController.onTick();
}



/**
 * タイマー処理
 */
void OnTimer() {

    if (g_eaController == NULL) {
        return;
    }

    // パネル描画を更新
    g_eaController.refreshStatusPanel();
}

/**
 * 取引トランザクション処理
 *
 * @param trans トランザクション
 * @param request 発注要求
 * @param result 発注結果
 */
void OnTradeTransaction(
    const MqlTradeTransaction &trans,
    const MqlTradeRequest &request,
    const MqlTradeResult &result
) {

    if (g_eaContext == NULL) {
        return;
    }

    if (g_eaContext.tradeExecutor == NULL) {
        return;
    }

    // 約定イベントを取引実行へ委譲
    g_eaContext.tradeExecutor.onTradeTransaction(trans, request, result);
}

/**
 * 終了処理
 *
 * @param reason 終了理由
 */
void OnDeinit(const int reason) {

    // タイマーを停止
    EventKillTimer();

    if (g_eaContext != NULL && g_eaContext.statusLabelView != NULL) {
        // ラベルを削除
        g_eaContext.statusLabelView.destroy();
    }

    if (g_eaContext != NULL && g_eaContext.elliottInfoPanelView != NULL) {
        // エリオット情報パネルを削除
        g_eaContext.elliottInfoPanelView.destroy();
    }

    // 生成順の逆順で解放
    delete g_eaController;

    if (g_eaContext != NULL) {
        g_eaContext.currencyStrengthExecutionInfoProvider = NULL;
    }

    delete g_currencyStrengthExecutionInfoProvider;

    if (g_eaContext != NULL) {
        delete g_eaContext.strategyAdapter;
        delete g_eaContext.tradeExecutor;
        delete g_eaContext.positionService;
        delete g_eaContext.newBarDetector;
        delete g_eaContext.elliottInfoPanelView;
        delete g_eaContext.signalAlertTextView;
        delete g_eaContext.closeProfitTextView;
        delete g_eaContext.statusLabelView;
        delete g_eaContext.closeTradeCsvLogger;
        delete g_eaContext.profitRetracementStateStore;
        delete g_eaContext.profitRetracementState;
        delete g_eaContext.tradeCsvLogger;
        delete g_eaContext.operationLogger;
    }

    delete g_eaContext;
    delete g_eaConfig;
    delete g_signalCount;
    delete g_oscillatorHandlePool;
}
