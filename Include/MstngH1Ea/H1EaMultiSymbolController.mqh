#ifndef MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH
#define MSTNGH1EA_MULTISYMBOLCONTROLLER_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <MstngH1Ea\H1EaController.mqh>
#include <MstngH1Ea\Runtime\H1EaEventTimer.mqh>
#include <MstngH1Ea\Runtime\H1EaMonitorState.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>
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
        this.fastWarmupActive = false;
        this.resetMonitorMetrics();
        this.testerTradeStartTime = 0;
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
        this.testerTradeStartTime = fromTesterTradeStartTime;
        this.resetMonitorMetrics();
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
        this.timerLogger.initialize(_Symbol, 0, this.sessionUid);
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
        if (!this.updateEventTimer(false)) {
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
        ulong timerStartedMicros = GetMicrosecondCount();
        this.fastWarmupActive = this.processFastTesterWarmup();
        if (this.fastWarmupActive) {
            this.lastProtectionClock = 0;
            this.lastProtectionGapMs = 0;
            this.processWarmupPreparation();
            this.recordTimerDuration(timerStartedMicros);
            return;
        }
        // 履歴巡回の順番を待たず、全通貨のLeaseを毎イベント確認する。
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].processPersistencePreparation();
            this.logRestorationState(i);
        }
        this.recordProtectionPass();
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
        if (!this.isBeforeTesterTradeStart()) {
            this.controllers[symbolIndex].restorePreparedDecision();
        }
        if (trailBarTime > 0) {
            this.controllers[symbolIndex].processScheduledTrail(trailBarTime);
        } else if (entrySymbolIndex == symbolIndex && entryBarTime > 0) {
            this.controllers[symbolIndex].processScheduledEntry(entryBarTime, this.eventTimer.isNormalReady());
        }
        this.logRestorationState(symbolIndex);
        this.controllers[symbolIndex].getPreparationState(currentState);
        if (!MQLInfoInteger(MQL_TESTER) && (previousState.status != currentState.status
                || previousState.reason != currentState.reason)) {
            this.logger.info(__FUNCTION__, currentState.symbolName + " " + currentState.status
                + " H1=" + IntegerToString(currentState.h1BarTime) + " " + currentState.reason);
        }
        this.recordTimerDuration(timerStartedMicros);
    }

    /**
     * TickでTesterの周期復帰を確認し、チャート通貨の保護を補助する。分析・Entryは行わない。
     */
    void onTick() {
        if (!this.started || !this.timerStarted) {
            return;
        }
        bool wasFastWarmup = this.fastWarmupActive;
        this.fastWarmupActive = this.processFastTesterWarmup();
        if (this.fastWarmupActive) {
            this.lastProtectionClock = 0;
            this.lastProtectionGapMs = 0;
            return;
        }
        if (wasFastWarmup || !this.eventTimer.isNormalReady()) {
            // 高速終了・Timer復帰失敗時も、他通貨の保護を次のTimer待ちにしない。
            this.recordProtectionPass();
            for (int i = 0; i < ArraySize(this.controllers); i++) {
                this.controllers[i].processPersistencePreparation();
                this.controllers[i].processProtection(iTime(this.controllers[i].getSymbolName(), PERIOD_H1, 0));
            }
            return;
        }
        if (this.chartSymbolIndex < 0) {
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
     * 表示・定期ログ用の状態を集計する。新しいDB照会・broker照合・分析は行わない。
     */
    void getMonitorState(H1EaMonitorState &fromState) {
        fromState.reset();
        if (!this.started) {
            return;
        }
        fromState.sessionUid = this.sessionUid;
        if (MQLInfoInteger(MQL_TESTER)) {
            fromState.sourceMode = "TESTER";
        }
        fromState.serverTime = TimeCurrent();
        fromState.beforeTradeStart = this.isBeforeTesterTradeStart();
        fromState.fastWarmup = this.fastWarmupActive;
        fromState.timerSeconds = this.eventTimer.getSeconds();
        fromState.timerCount = this.timerCount;
        fromState.lastTimerMicros = this.lastTimerMicros;
        fromState.maxTimerMicros = this.maxTimerMicros;
        fromState.lastProtectionGapMs = this.lastProtectionGapMs;
        fromState.maxProtectionGapMs = this.maxProtectionGapMs;
        fromState.memoryMb = MQLInfoInteger(MQL_MEMORY_USED);
        datetime currentBar = (datetime)((long)fromState.serverTime / 3600 * 3600);
        ulong lastAnalysisFinished = 0;
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].getMonitorState(fromState.symbols[i], fromState.beforeTradeStart,
                this.eventTimer.isNormalReady() || (fromState.beforeTradeStart
                    && fromState.fastWarmup && fromState.timerSeconds == 30), currentBar);
            fromState.symbolCount++;
            if (fromState.symbols[i].historyReady) {
                fromState.historyReadyCount++;
            }
            if (fromState.symbols[i].category == "STOPPED") {
                fromState.stoppedCount++;
            } else if (fromState.symbols[i].category == "PREPARING") {
                fromState.preparingCount++;
            } else {
                fromState.watchingCount++;
            }
            if (fromState.symbols[i].activeTrade) {
                fromState.activeTradeCount++;
            }
            fromState.analysisCount += fromState.symbols[i].analysisCount;
            if (fromState.symbols[i].maxAnalysisMicros > fromState.maxAnalysisMicros) {
                fromState.maxAnalysisMicros = fromState.symbols[i].maxAnalysisMicros;
            }
            if (fromState.symbols[i].analysisFinishedMicros > lastAnalysisFinished) {
                lastAnalysisFinished = fromState.symbols[i].analysisFinishedMicros;
                fromState.lastAnalysisMicros = fromState.symbols[i].lastAnalysisMicros;
            }
        }
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
        if (this.started && this.timerCount > 0) {
            this.logRuntimeMetrics(true);
        }
        if (this.timerStarted) {
            EventKillTimer();
            this.timerStarted = false;
        }
        this.eventTimer.reset();
        this.fastWarmupActive = false;
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
    /** 表示・ログ専用のTimer処理回数。 */
    ulong timerCount;
    /** 直近のTimer実時間。 */
    ulong lastTimerMicros;
    /** 起動後の最大Timer実時間。 */
    ulong maxTimerMicros;
    /** 前回の通常保護巡回開始時計。高速準備では0へ戻す。 */
    ulong lastProtectionClock;
    /** 直近の全通貨保護巡回間隔。 */
    ulong lastProtectionGapMs;
    /** 起動後の最大保護巡回間隔。 */
    ulong maxProtectionGapMs;
    /** 次の定期計測ログを出せる巡回時計。 */
    ulong nextMetricsLogTick;
    /** 待機中の計測ログを最後に出したTester内サーバー日。未出力は-1。 */
    long lastWaitingMetricsLogDay;
    /** 履歴待機の全体集約を最後に確認したTester内サーバー日。未確認は-1。 */
    long lastHistorySummaryDay;
    /** 固定28通貨それぞれが所有する独立したController。 */
    H1EaController *controllers[28];
    /** 全通貨の登録を完了したか。 */
    bool started;
    /** この親がTimerを開始したか。 */
    bool timerStarted;
    /** Testerの売買開始日時。0は準備期間なし。 */
    datetime testerTradeStartTime;
    /** 直前イベントで高速準備が安全に成立したか。 */
    bool fastWarmupActive;
    /** 親だけが操作するTimer設定状態。 */
    H1EaEventTimer eventTimer;
    /** session UID単位に記録する親Timerの運用ログ。 */
    H1EaOperationLogger timerLogger;
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
     * 計測値だけを初期化する。売買状態・巡回位置には触れない。
     */
    void resetMonitorMetrics() {
        this.timerCount = 0;
        this.lastTimerMicros = 0;
        this.maxTimerMicros = 0;
        this.lastProtectionClock = 0;
        this.lastProtectionGapMs = 0;
        this.maxProtectionGapMs = 0;
        this.nextMetricsLogTick = 0;
        this.lastWaitingMetricsLogDay = -1;
        this.lastHistorySummaryDay = -1;
    }

    /**
     * 全通貨を保護する巡回の開始間隔を記録する。単一通貨Tick補助は含めない。
     */
    void recordProtectionPass() {
        ulong now = H1EaClock::milliseconds();
        if (this.lastProtectionClock > 0 && now >= this.lastProtectionClock) {
            this.lastProtectionGapMs = now - this.lastProtectionClock;
            if (this.lastProtectionGapMs > this.maxProtectionGapMs) {
                this.maxProtectionGapMs = this.lastProtectionGapMs;
            }
        }
        this.lastProtectionClock = now;
    }

    /**
     * Timerの本処理だけを実時計で計測し、低頻度でログへ残す。
     */
    void recordTimerDuration(const ulong fromStarted) {
        this.timerCount++;
        this.lastTimerMicros = GetMicrosecondCount() - fromStarted;
        if (this.lastTimerMicros > this.maxTimerMicros) {
            this.maxTimerMicros = this.lastTimerMicros;
        }
        this.logRuntimeMetrics(false);
        this.logHistoryWaitSummary();
    }

    /**
     * Tester内のサーバー日ごとに、取得済み履歴状態だけで28通貨の待機を1行に集約する。
     * 初回28イベントは通貨巡回を優先し、履歴の再取得や売買判定は行わない。
     */
    void logHistoryWaitSummary() {
        if (!MQLInfoInteger(MQL_TESTER) || this.timerCount < (ulong)ArraySize(this.controllers)) {
            return;
        }
        long currentDay = (long)TimeCurrent() / 86400;
        if (currentDay == this.lastHistorySummaryDay) {
            return;
        }
        this.lastHistorySummaryDay = currentDay;
        int readyCount = 0;
        int pendingCount = 0;
        int errorCount = 0;
        int missingCounts[5] = {0, 0, 0, 0, 0};
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            H1EaPreparationState state;
            this.controllers[i].getPreparationState(state);
            if (state.historyChecked && state.historyReady) {
                readyCount++;
            }
            if (!state.historyChecked) {
                pendingCount++;
            }
            if (state.status == "ERROR") {
                errorCount++;
            }
            for (int j = 0; j < ArraySize(missingCounts); j++) {
                if (state.historyChecked && (state.historyMissingMask & (1 << j)) != 0) {
                    missingCounts[j]++;
                }
            }
        }
        if (readyCount == ArraySize(this.controllers)) {
            return;
        }
        string message = "HISTORY_WAIT ready=" + IntegerToString(readyCount)
            + "/" + IntegerToString(ArraySize(this.controllers));
        string timeFrames[5] = {"MN1", "W1", "D1", "H4", "H1"};
        for (int i = 0; i < ArraySize(missingCounts); i++) {
            if (missingCounts[i] > 0) {
                message += " " + timeFrames[i] + "不足=" + IntegerToString(missingCounts[i]);
            }
        }
        if (pendingCount > 0) {
            message += " pending=" + IntegerToString(pendingCount);
        }
        if (errorCount > 0) {
            message += " error=" + IntegerToString(errorCount);
        }
        this.timerLogger.info(__FUNCTION__, message);
    }

    /**
     * LIVEは最短1分、Testerはテスト内1時間で状態を確認する。
     * Testerの全通貨準備中・管理取引なしでは日次出力に抑える。終了時は必ず残す。
     */
    void logRuntimeMetrics(const bool fromForce) {
        ulong now = H1EaClock::milliseconds();
        if (!fromForce && now < this.nextMetricsLogTick) {
            return;
        }
        this.nextMetricsLogTick = now + 60000;
        if (MQLInfoInteger(MQL_TESTER)) {
            this.nextMetricsLogTick = now + 3600000;
        }
        H1EaMonitorState state;
        this.getMonitorState(state);
        if (MQLInfoInteger(MQL_TESTER) && state.symbolCount > 0
                && state.preparingCount == state.symbolCount && state.activeTradeCount == 0) {
            long currentDay = (long)state.serverTime / 86400;
            if (!fromForce && currentDay == this.lastWaitingMetricsLogDay) {
                return;
            }
            this.lastWaitingMetricsLogDay = currentDay;
        }
        this.timerLogger.info(__FUNCTION__, "METRICS symbols=" + IntegerToString(state.symbolCount)
            + " historyReady=" + IntegerToString(state.historyReadyCount)
            + " watch=" + IntegerToString(state.watchingCount) + " preparing=" + IntegerToString(state.preparingCount)
            + " stopped=" + IntegerToString(state.stoppedCount) + " managedTrades=" + IntegerToString(state.activeTradeCount)
            + " timerCount=" + H1EaTextUtil::ticket(state.timerCount)
            + " timerMs=" + DoubleToString((double)state.lastTimerMicros / 1000.0, 2)
            + " timerMaxMs=" + DoubleToString((double)state.maxTimerMicros / 1000.0, 2)
            + " analysisCount=" + H1EaTextUtil::ticket(state.analysisCount)
            + " analysisMs=" + DoubleToString((double)state.lastAnalysisMicros / 1000.0, 2)
            + " analysisMaxMs=" + DoubleToString((double)state.maxAnalysisMicros / 1000.0, 2)
            + " protectionGapMs=" + H1EaTextUtil::ticket(state.lastProtectionGapMs)
            + " protectionMaxGapMs=" + H1EaTextUtil::ticket(state.maxProtectionGapMs)
            + " memoryMb=" + IntegerToString(state.memoryMb));
    }

    /**
     * Testerで明示された売買開始日時より前か返す。LIVEと0指定には適用しない。
     */
    bool isBeforeTesterTradeStart() {
        return MQLInfoInteger(MQL_TESTER) && this.testerTradeStartTime > 0
            && TimeCurrent() < this.testerTradeStartTime;
    }

    /**
     * 全通貨の照合済み空状態と口座全体の無保有を確認してから高速化する。
     * 売買開始の30秒前には通常周期へ戻し、開始境界の待ちを短くする。
     */
    bool canUseFastTesterWarmup() {
        if (!this.started || !this.timerStarted || !this.isBeforeTesterTradeStart()
                || TimeCurrent() + 30 >= this.testerTradeStartTime
                || PositionsTotal() != 0 || OrdersTotal() != 0) {
            return false;
        }
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            if (!this.controllers[i].canUseScheduledFastTesterWarmup()) {
                return false;
            }
        }
        return true;
    }

    /**
     * 親Timerを更新する。通常周期の復帰失敗時も、全通貨のDB保守待ちを解除する。
     */
    bool updateEventTimer(const bool fromFastWarmup) {
        bool resetMaintenance = false;
        bool updated = this.eventTimer.update(fromFastWarmup, this.timerLogger, resetMaintenance);
        if (resetMaintenance || (!fromFastWarmup && this.fastWarmupActive)) {
            for (int i = 0; i < ArraySize(this.controllers); i++) {
                if (this.controllers[i] != NULL) {
                    this.controllers[i].resetScheduledMaintenance();
                }
            }
        }
        return updated;
    }

    /**
     * 全通貨が安全な間だけ30秒保守を使用し、保守後も高速化条件を再確認する。
     */
    bool processFastTesterWarmup() {
        bool fastWarmup = this.canUseFastTesterWarmup();
        if (!this.updateEventTimer(fastWarmup)) {
            return false;
        }
        if (!fastWarmup) {
            return false;
        }
        for (int i = 0; i < ArraySize(this.controllers); i++) {
            this.controllers[i].processPersistencePreparation(true);
        }
        if (this.canUseFastTesterWarmup()) {
            return true;
        }
        this.updateEventTimer(false);
        return false;
    }

    /**
     * 安全な高速準備期間は、1イベントで1通貨の履歴だけを確認する。
     * 波動分析・Judge・現在バーのDecision照会は行わない。
     */
    void processWarmupPreparation() {
        int symbolIndex = this.nextSymbolIndex;
        this.nextSymbolIndex = (this.nextSymbolIndex + 1) % ArraySize(this.controllers);
        H1EaPreparationState previousState;
        H1EaPreparationState currentState;
        this.controllers[symbolIndex].getPreparationState(previousState);
        this.controllers[symbolIndex].processPreparation();
        this.controllers[symbolIndex].getPreparationState(currentState);
        if (!MQLInfoInteger(MQL_TESTER) && (previousState.status != currentState.status
                || previousState.reason != currentState.reason)) {
            this.logger.info(__FUNCTION__, currentState.symbolName + " " + currentState.status
                + " H1=" + IntegerToString(currentState.h1BarTime) + " " + currentState.reason);
        }
    }

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
