#ifndef MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH
#define MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <MstngH1Ea\H1EaController.mqh>
#include <MstngH1Ea\Runtime\H1EaTradeTransactionRouter.mqh>

/**
 * 固定28通貨のControllerを所有し、1本のTimerで順番に履歴を準備する。
 * 全通貨の保護を優先し、トレイルまたはEntryを1イベント1分析で巡回する。子Timerは開始しない。
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
        this.nextTrailSymbolIndex = 0;
        this.nextEntrySymbolIndex = 0;
        this.entryScheduleHour = 0;
        this.consecutiveTrailTasks = 0;
        this.chartSymbolIndex = -1;
        this.lastError = "";
        this.sessionUid = "";
        this.logger.setSymbolNameAndTimeFrame(_Symbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i] = NULL;
            this.lastRestorationStatus[i] = "";
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
    bool initialize(const double fromLotSize, const double fromMaxInitialStopLossPips,
            const datetime fromTesterTradeStartTime) {
        if (this.started) {
            return false;
        }
        this.lastError = "";
        this.sessionUid = "";
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
        string sourceMode = "LIVE";
        string databaseFileName = "mstng-h1-ea.sqlite";
        if (MQLInfoInteger(MQL_TESTER)) {
            sourceMode = "TESTER";
            databaseFileName = "mstng-h1-ea-tester.sqlite";
        }
        this.sessionUid = H1EaTextUtil::hash("H1_EA_SESSION_V1|" + sourceMode + "|"
            + AccountInfoString(ACCOUNT_SERVER) + "|" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
            + "|" + IntegerToString(ChartID()) + "|" + IntegerToString(TimeLocal())
            + "|" + H1EaTextUtil::ticket(GetTickCount64()) + "|" + H1EaTextUtil::ticket(GetMicrosecondCount()));
        if (!H1EaSql::isHash(this.sessionUid)) {
            return this.fail("SESSION_HASH_UNAVAILABLE");
        }
        for (int i = 0; i < symbols.size(); i++) {
            SymbolNameInfo *symbol = symbols.getSymbolNameInfo(i);
            if (symbol.symbolName == _Symbol) {
                this.chartSymbolIndex = i;
            }
            this.controllers[i] = new H1EaController();
            if (this.controllers[i] == NULL
                    || !this.controllers[i].initializePreparation(symbol.symbolName)) {
                return this.fail("SYMBOL_INITIALIZATION_FAILED: " + symbol.symbolName);
            }
            if (!this.controllers[i].initializePersistencePreparation(fromLotSize,
                    fromMaxInitialStopLossPips, fromTesterTradeStartTime, this.sessionUid)) {
                H1EaRestorationState state;
                this.controllers[i].getRestorationState(state);
                return this.fail("SYMBOL_CONFIGURATION_OR_LOCK_FAILED: " + symbol.symbolName + " " + state.reason);
            }
        }
        // 全Lock取得後、親だけがschema移行を行う。子は既存schemaへ接続するだけ。
        H1EaDatabaseContext database;
        if (!database.open(databaseFileName, true)) {
            return this.fail("DATABASE_SCHEMA_PREPARATION_FAILED");
        }
        database.close();
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (!this.controllers[i].startPersistencePreparation()) {
                H1EaRestorationState state;
                this.controllers[i].getRestorationState(state);
                return this.fail("SYMBOL_RESTORE_FAILED: " + state.run.symbolName + " " + state.reason);
            }
            // 起動処理が長引いても、先に登録したRunのLeaseを失効させない。
            for (int j = 0; j <= i; j++) {
                this.controllers[j].processPersistencePreparation();
                H1EaRestorationState state;
                this.controllers[j].getRestorationState(state);
                if (!state.databaseReady || state.status == "LEASE_LOST") {
                    return this.fail("STARTUP_LEASE_OR_DATABASE_FAILED: " + state.run.symbolName);
                }
            }
        }
        this.nextSymbolIndex = 0;
        this.started = true;
        this.logger.info(__FUNCTION__, "MULTI_SYMBOL_ENTRY symbols=28 timeFrame=H1 entry=waiting session=" + this.sessionUid);
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
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (!this.controllers[i].canEnableProtection()) {
                return this.fail("PROTECTION_INITIALIZATION_NOT_READY: " + this.controllers[i].getSymbolName());
            }
        }
        ResetLastError();
        if (!EventSetTimer(1)) {
            return this.fail("TIMER_START_FAILED: " + IntegerToString(GetLastError()));
        }
        this.timerStarted = true;
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].enableProtection();
            this.controllers[i].enableEntry();
        }
        return true;
    }

    /**
     * 全通貨の保護を先に実行し、重い履歴準備とトレイル/Entry分析は最大1通貨へ制限する。
     */
    void onTimer() {
        if (!this.started || !this.timerStarted) {
            return;
        }
        // 履歴巡回の順番を待たず、全通貨のLeaseを毎イベント確認する。
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].processPersistencePreparation();
            this.logRestorationState(i);
        }
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            datetime barTime = iTime(this.controllers[i].getSymbolName(), PERIOD_H1, 0);
            this.controllers[i].processProtection(barTime);
        }
        // 毎時の開始通貨はサーバー時刻で決め、再テストでも同じ順序にする。
        datetime scheduleHour = (datetime)((long)TimeCurrent() / 3600);
        if (scheduleHour != this.entryScheduleHour) {
            this.entryScheduleHour = scheduleHour;
            this.nextEntrySymbolIndex = (int)((long)scheduleHour % ArraySize(this.controllers));
        }
        int entrySymbolIndex = -1;
        datetime entryBarTime = 0;
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            int candidateIndex = (this.nextEntrySymbolIndex + i) % ArraySize(this.controllers);
            datetime candidateBar = this.controllers[candidateIndex].getPendingEntryBar();
            H1EaPreparationState candidateState;
            this.controllers[candidateIndex].getPreparationState(candidateState);
            // H1未取得通貨の準備も同じ巡回へ含め、Entry待ちが多いときの放置を防ぐ。
            bool preparationPending = !candidateState.resourcesInitialized || candidateState.h1BarTime <= 0;
            if (entrySymbolIndex < 0 && (candidateBar > 0 || preparationPending)) {
                entrySymbolIndex = candidateIndex;
                entryBarTime = candidateBar;
            }
        }
        int symbolIndex = -1;
        datetime trailBarTime = 0;
        // トレイル分析が続く場合も、3タスク目にはEntryまたは履歴へ枠を渡す。
        if (this.consecutiveTrailTasks < 2) {
            for (int i = 0; i < ArraySize(this.controllers); i++) {
                int candidateIndex = (this.nextTrailSymbolIndex + i) % ArraySize(this.controllers);
                trailBarTime = this.controllers[candidateIndex].getPendingTrailBar();
                if (trailBarTime > 0) {
                    symbolIndex = candidateIndex;
                    this.nextTrailSymbolIndex = (candidateIndex + 1) % ArraySize(this.controllers);
                    break;
                }
            }
        }
        if (symbolIndex >= 0) {
            this.consecutiveTrailTasks++;
        } else if (entrySymbolIndex >= 0) {
            symbolIndex = entrySymbolIndex;
            this.nextEntrySymbolIndex = (entrySymbolIndex + 1) % ArraySize(this.controllers);
            this.consecutiveTrailTasks = 0;
        }
        if (symbolIndex < 0) {
            symbolIndex = this.nextSymbolIndex;
            this.nextSymbolIndex++;
            if (this.nextSymbolIndex >= ArraySize(this.controllers)) {
                this.nextSymbolIndex = 0;
            }
            this.consecutiveTrailTasks = 0;
        }
        H1EaPreparationState previousState;
        H1EaPreparationState currentState;
        this.controllers[symbolIndex].getPreparationState(previousState);
        this.controllers[symbolIndex].processPreparation();
        this.controllers[symbolIndex].restorePreparedDecision();
        if (trailBarTime > 0) {
            this.controllers[symbolIndex].processScheduledTrail(trailBarTime);
        } else if (entrySymbolIndex == symbolIndex && entryBarTime > 0) {
            this.controllers[symbolIndex].processScheduledEntry(entryBarTime, this.timerStarted);
        }
        this.logRestorationState(symbolIndex);
        this.controllers[symbolIndex].getPreparationState(currentState);
        if (previousState.status != currentState.status || previousState.reason != currentState.reason) {
            this.logger.info(__FUNCTION__, currentState.symbolName + " " + currentState.status
                + " H1=" + IntegerToString(currentState.h1BarTime) + " " + currentState.reason);
        }
    }

    /**
     * チャート通貨だけTickで保護を補助する。分析・Entry・Timer変更は行わない。
     */
    void onTick() {
        if (!this.started || !this.timerStarted || this.chartSymbolIndex < 0) {
            return;
        }
        H1EaController *symbolController = this.controllers[this.chartSymbolIndex];
        symbolController.processPersistencePreparation();
        symbolController.processProtection(iTime(symbolController.getSymbolName(), PERIOD_H1, 0));
    }

    /**
     * 通知の銘柄・記憶済み識別子・broker ticketの順に対象を特定して軽量受付する。
     * 帰属不明時は全通貨へ照合予約を出す。ここで分析・照合・送信は行わない。
     */
    void onTradeTransaction(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
        if (!this.started || !this.timerStarted) {
            return;
        }
        string symbol = H1EaTradeTransactionRouter::explicitSymbol(fromTransaction, fromRequest);
        if (symbol != "") {
            int symbolIndex = this.findSymbolIndex(symbol);
            if (symbolIndex >= 0) {
                this.controllers[symbolIndex].queueTradeTransaction(fromTransaction, fromRequest, fromResult);
            }
            return;
        }
        int matchedIndex = -1;
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (this.controllers[i].matchesTradeTransaction(fromTransaction, fromRequest, fromResult)) {
                if (matchedIndex >= 0) {
                    this.requestAllReconciliation();
                    return;
                }
                matchedIndex = i;
            }
        }
        if (matchedIndex >= 0) {
            this.controllers[matchedIndex].queueTradeTransaction(fromTransaction, fromRequest, fromResult);
            return;
        }
        symbol = H1EaTradeTransactionRouter::resolveSymbol(fromTransaction, fromRequest, fromResult);
        if (symbol != "") {
            int symbolIndex = this.findSymbolIndex(symbol);
            if (symbolIndex >= 0) {
                this.controllers[symbolIndex].queueTradeTransaction(fromTransaction, fromRequest, fromResult);
            }
            return;
        }
        this.requestAllReconciliation();
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
     * 指定通貨のDB復元状態を返す。売買可能状態とは区別する。
     */
    bool getRestorationState(const int fromIndex, H1EaRestorationState &fromState) {
        fromState.reset();
        if (!this.started || fromIndex < 0 || fromIndex >= ArraySize(this.controllers)) {
            return false;
        }
        this.controllers[fromIndex].getRestorationState(fromState);
        return true;
    }

    /**
     * 全28通貨をまとめた起動IDを返す。
     */
    string getSessionUid() { return this.sessionUid; }

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
        this.nextTrailSymbolIndex = 0;
        this.nextEntrySymbolIndex = 0;
        this.entryScheduleHour = 0;
        this.consecutiveTrailTasks = 0;
        this.chartSymbolIndex = -1;
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
    /** 次に優先確認するトレイル対象の添字。 */
    int nextTrailSymbolIndex;
    /** Entry候補を巡回する次の通貨。毎時の開始位置から順に進める。 */
    int nextEntrySymbolIndex;
    /** 巡回開始位置を決めたサーバー時刻の時間番号。 */
    datetime entryScheduleHour;
    /** 連続する重いトレイル処理の数。2回でEntry/履歴へ譲る。 */
    int consecutiveTrailTasks;
    /** Tick補助対象。チャート通貨が対象外なら-1。 */
    int chartSymbolIndex;
    /** 最新の失敗理由。終了処理後も保持する。 */
    string lastError;
    /** 28通貨共通の起動ID。設定hashやLIVE復元キーには含めない。 */
    string sessionUid;
    /** 同一のDB待機ログを繰り返さないための通貨別状態。 */
    string lastRestorationStatus[28];
    /** 全体の起動・状態変化ログ。 */
    Logger logger;

    /**
     * 登録銘柄との完全一致だけで振り分ける。
     */
    int findSymbolIndex(const string fromSymbol) {
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (this.controllers[i].getSymbolName() == fromSymbol) {
                return i;
            }
        }
        return -1;
    }

    /**
     * 帰属不明時は予約のみ全通貨へ渡し、実際の照合はTimer/Tickへ回す。
     */
    void requestAllReconciliation() {
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].requestTradeReconciliation();
        }
    }

    /**
     * 復元状態の変化だけを記録する。pending状態はDBからの読取値として扱う。
     */
    void logRestorationState(const int fromIndex) {
        H1EaRestorationState state;
        this.controllers[fromIndex].getRestorationState(state);
        string status = state.status + " " + state.reason;
        if (this.lastRestorationStatus[fromIndex] == status) {
            return;
        }
        this.lastRestorationStatus[fromIndex] = status;
        string message = state.run.symbolName + " " + status + " run=" + IntegerToString(state.run.id)
            + " trade=" + IntegerToString(state.trade.id) + " pending=" + state.trade.pendingStopLossKind;
        if (state.status == "LEASE_LOST" || state.status == "AUDIT_STATE_LOST") {
            this.logger.error(__FUNCTION__, message);
        } else {
            this.logger.info(__FUNCTION__, message);
        }
    }

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
