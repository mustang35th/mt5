/**
 * Package: Experts
 * File: MstngEa.mq5
 */

#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.02"

#property strict

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\App\EaContext.mqh>
#include <MstngEa\App\EaController.mqh>
#include <MstngEa\App\StrategyFactory.mqh>
#include <MstngEa\Config\EaConfig.mqh>
#include <MstngEa\Trade\MagicNumberUtil.mqh>

/** 戦略種別 */
input StrategyType InpStrategyType = STRATEGY_TYPE_MTF_3IN3;

/** ロット */
input double InpLotSize = 0.01;

/** パネル再描画間隔ミリ秒 */
input int InpPanelRefreshMilliseconds = 1000;

/** 利益戻し決済使用 */
input bool InpUseProfitRetracementExit = true;

/** 利益戻し決済開始R倍率 */
input double InpProfitRetracementStartR = 1.5;

/** 利益戻し決済戻し率 */
input double InpProfitRetracementRate = 0.30;

/** 建値移動使用 */
input bool InpUseBreakEven = true;

/** 建値移動発動R倍率 */
input double InpBreakEvenTriggerR = 1.0;

/** 建値移動加算pips */
input double InpBreakEvenPlusPips = 1.0;

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

/** EA制御 */
EaController *g_eaController;

/**
 * 初期化
 *
 * @return 初期化結果
 */
int OnInit() {
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
    g_eaContext.operationLogger = new OperationLogger(g_marketContext);
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
        g_signalCount
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
        delete g_eaContext.strategyAdapter;
        delete g_eaContext.tradeExecutor;
        delete g_eaContext.positionService;
        delete g_eaContext.newBarDetector;
        delete g_eaContext.elliottInfoPanelView;
        delete g_eaContext.signalAlertTextView;
        delete g_eaContext.closeProfitTextView;
        delete g_eaContext.statusLabelView;
        delete g_eaContext.closeTradeCsvLogger;
        delete g_eaContext.profitRetracementState;
        delete g_eaContext.tradeCsvLogger;
        delete g_eaContext.operationLogger;
    }

    delete g_eaContext;
    delete g_eaConfig;
    delete g_signalCount;
    delete g_oscillatorHandlePool;
}
