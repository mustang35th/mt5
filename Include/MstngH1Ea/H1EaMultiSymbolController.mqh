#ifndef MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH
#define MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <MstngH1Ea\H1EaController.mqh>

/**
 * 固定28通貨のControllerを所有し、1本のTimerで順番に履歴を準備する。
 * 第2段階では準備専用経路だけを使い、DB・取引・子のTimerは開始しない。
 */
class H1EaMultiSymbolController {
public:
    /**
     * 子ControllerとTimerの所有状態を初期化する。
     */
    H1EaMultiSymbolController() {
        this.started = false;
        this.timerStarted = false;
        this.nextSymbolIndex = 0;
        this.lastError = "";
        this.logger.setSymbolNameAndTimeFrame(_Symbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i] = NULL;
        }
    }

    /**
     * 途中失敗を含め、自分が所有する資源だけを解放する。
     */
    ~H1EaMultiSymbolController() {
        this.shutdown(REASON_REMOVE);
    }

    /**
     * 共通リストと全銘柄を確認してから、通貨別Controllerを28個登録する。
     * 履歴取得と分析ハンドル作成はTimer巡回へ委ねる。
     */
    bool initialize() {
        if (this.started) {
            return false;
        }
        this.lastError = "";
        if (_Period != PERIOD_H1) {
            return this.fail("H1_CHART_REQUIRED");
        }
        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            return this.fail("OPTIMIZATION_NOT_SUPPORTED");
        }
        SymbolNameInfoAll symbols;
        symbols.setAll();
        if (symbols.size() != ArraySize(this.controllers)) {
            return this.fail("SYMBOL_COUNT_MISMATCH");
        }
        for (int i = 0; i < symbols.size(); i++) {
            SymbolNameInfo *symbol = symbols.getSymbolNameInfo(i);
            if (symbol == NULL || symbol.symbolName == "" || !symbol.isTarget) {
                return this.fail("INVALID_SYMBOL_LIST");
            }
            for (int j = 0; j < i; j++) {
                SymbolNameInfo *previousSymbol = symbols.getSymbolNameInfo(j);
                if (previousSymbol.symbolName == symbol.symbolName) {
                    return this.fail("DUPLICATE_SYMBOL: " + symbol.symbolName);
                }
            }
            if (!SymbolSelect(symbol.symbolName, true)) {
                return this.fail("SYMBOL_UNAVAILABLE: " + symbol.symbolName);
            }
        }
        for (int i = 0; i < symbols.size(); i++) {
            SymbolNameInfo *symbol = symbols.getSymbolNameInfo(i);
            this.controllers[i] = new H1EaController();
            if (this.controllers[i] == NULL
                    || !this.controllers[i].initializePreparation(symbol.symbolName)) {
                return this.fail("SYMBOL_INITIALIZATION_FAILED: " + symbol.symbolName);
            }
        }
        this.nextSymbolIndex = 0;
        this.started = true;
        this.logger.info(__FUNCTION__, "PREPARATION_ONLY symbols=28 timeFrame=H1 trading=disabled database=disabled");
        return true;
    }

    /**
     * 親だけが1秒Timerを開始する。子のイベント入口は使用しない。
     */
    bool startTimer() {
        if (!this.started) {
            return false;
        }
        if (this.timerStarted) {
            return true;
        }
        ResetLastError();
        if (!EventSetTimer(1)) {
            return this.fail("TIMER_START_FAILED: " + IntegerToString(GetLastError()));
        }
        this.timerStarted = true;
        return true;
    }

    /**
     * 1イベントにつき1通貨を確認し、未準備やエラーでも次の通貨へ進む。
     */
    void onTimer() {
        if (!this.started || !this.timerStarted) {
            return;
        }
        int symbolIndex = this.nextSymbolIndex;
        this.nextSymbolIndex++;
        if (this.nextSymbolIndex >= ArraySize(this.controllers)) {
            this.nextSymbolIndex = 0;
        }
        H1EaPreparationState previousState;
        H1EaPreparationState currentState;
        this.controllers[symbolIndex].getPreparationState(previousState);
        this.controllers[symbolIndex].processPreparation();
        this.controllers[symbolIndex].getPreparationState(currentState);
        if (previousState.status != currentState.status || previousState.reason != currentState.reason) {
            this.logger.info(__FUNCTION__, currentState.symbolName + " " + currentState.status
                + " H1=" + IntegerToString(currentState.h1BarTime) + " " + currentState.reason);
        }
    }

    /**
     * 登録済み通貨数を返す。部分的な初期化を成功扱いしない。
     */
    int getSymbolCount() const {
        if (!this.started) {
            return 0;
        }
        return ArraySize(this.controllers);
    }

    /**
     * 指定通貨の準備状態をコピーする。無効な参照では未登録状態を返す。
     */
    bool getPreparationState(const int fromIndex, H1EaPreparationState &fromState) {
        fromState.reset();
        if (!this.started || fromIndex < 0 || fromIndex >= ArraySize(this.controllers)) {
            return false;
        }
        this.controllers[fromIndex].getPreparationState(fromState);
        return true;
    }

    /**
     * 起動・Timer設定が失敗した理由を返す。
     */
    string getLastError() { return this.lastError; }

    /**
     * 親のTimerを止め、作成済みの全通貨Controllerを一度ずつ解放する。
     */
    void shutdown(const int fromReason) {
        if (this.timerStarted) {
            EventKillTimer();
            this.timerStarted = false;
        }
        this.started = false;
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (this.controllers[i] != NULL) {
                this.controllers[i].shutdown(fromReason);
                delete this.controllers[i];
                this.controllers[i] = NULL;
            }
        }
        this.nextSymbolIndex = 0;
    }

private:
    /** 固定28通貨それぞれが所有する独立したController。 */
    H1EaController *controllers[28];
    /** 全通貨の登録を完了したか。 */
    bool started;
    /** この親がTimerを開始したか。 */
    bool timerStarted;
    /** 次に巡回する通貨の添字。 */
    int nextSymbolIndex;
    /** 最新の失敗理由。終了処理後も保持する。 */
    string lastError;
    /** 全体の起動・状態変化ログ。 */
    Logger logger;

    /**
     * 原因を保持し、途中まで作成した子を解放して初期化を拒否する。
     */
    bool fail(const string fromReason) {
        this.lastError = fromReason;
        this.logger.error(__FUNCTION__, fromReason);
        this.shutdown(REASON_INITFAILED);
        return false;
    }
};

#endif
