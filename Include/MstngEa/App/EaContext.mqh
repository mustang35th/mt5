/**
 * Package: MstngEa.App
 * File: EaContext.mqh
 */

#ifndef MSTNGEA_APP_EACONTEXT_MQH
#define MSTNGEA_APP_EACONTEXT_MQH

#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\Config\EaConfig.mqh>
#include <MstngEa\Domain\ProfitRetracementState.mqh>
#include <MstngEa\Logging\OperationLogger.mqh>
#include <MstngEa\Logging\TradeCsvLogger.mqh>
#include <MstngEa\Logging\CloseTradeCsvLogger.mqh>
#include <MstngEa\Market\NewBarDetector.mqh>
#include <MstngEa\Presentation\ElliottInfoPanelView.mqh>
#include <MstngEa\Presentation\SignalAlertTextView.mqh>
#include <MstngEa\Presentation\CloseProfitTextView.mqh>
#include <MstngEa\Presentation\StatusLabelView.mqh>
#include <MstngEa\Strategy\IStrategyAdapter.mqh>
#include <MstngEa\Trade\PositionService.mqh>
#include <MstngEa\Trade\TradeExecutor.mqh>

/**
 * EA依存集約
 */
class EaContext {
public:
    /** シンボル名 */
    string symbolName;

    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /** オシレータハンドルプール */
    OscillatorHandlePool *oscillatorHandlePool;

    /** シグナル回数 */
    SignalCount *signalCount;

    /** 設定 */
    EaConfig *eaConfig;

    /** 新規バー判定 */
    NewBarDetector *newBarDetector;

    /** 戦略 */
    IStrategyAdapter *strategyAdapter;

    /** ポジション取得 */
    PositionService *positionService;

    /** 売買実行 */
    TradeExecutor *tradeExecutor;

    /** 稼働表示 */
    StatusLabelView *statusLabelView;

    /** シグナル表示 */
    SignalAlertTextView *signalAlertTextView;

    /** エリオット情報表示 */
    ElliottInfoPanelView *elliottInfoPanelView;

    /** 決済損益表示 */
    CloseProfitTextView *closeProfitTextView;

    /** 運用ログ */
    OperationLogger *operationLogger;

    /** 取引CSVログ */
    TradeCsvLogger *tradeCsvLogger;

    /** 決済専用CSVログ */
    CloseTradeCsvLogger *closeTradeCsvLogger;

    /** マジックナンバー */
    ulong magicNumber;

    /** 利益戻し決済状態 */
    ProfitRetracementState *profitRetracementState;

    /** 最終アクション */
    string lastAction;

    /** 最終エラー */
    string lastError;

    /**
     * コンストラクタ
     */
    EaContext() {
        // 初期値を設定
        this.symbolName = "";
        this.timeFrame = PERIOD_CURRENT;
        this.oscillatorHandlePool = NULL;
        this.signalCount = NULL;
        this.eaConfig = NULL;
        this.newBarDetector = NULL;
        this.strategyAdapter = NULL;
        this.positionService = NULL;
        this.tradeExecutor = NULL;
        this.statusLabelView = NULL;
        this.signalAlertTextView = NULL;
        this.elliottInfoPanelView = NULL;
        this.closeProfitTextView = NULL;
        this.operationLogger = NULL;
        this.tradeCsvLogger = NULL;
        this.closeTradeCsvLogger = NULL;
        this.magicNumber = 0;
        this.profitRetracementState = NULL;
        this.lastAction = "";
        this.lastError = "";
    }
};

#endif
