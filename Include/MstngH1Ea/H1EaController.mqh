#ifndef MSTNGH1EA_CONTROLLER_MQH
#define MSTNGH1EA_CONTROLLER_MQH

#include <Mstng\Database\Service\H1EaPersistenceService.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>
#include <MstngH1Ea\Config\H1EaConfig.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaDecisionBuilder.mqh>
#include <MstngH1Ea\Runtime\H1EaEntryState.mqh>
#include <MstngH1Ea\Runtime\H1EaEventTimer.mqh>
#include <MstngH1Ea\Runtime\H1EaInstanceLock.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>
#include <MstngH1Ea\Runtime\H1EaPreparationState.mqh>
#include <MstngH1Ea\Strategy\H1EaInitialStopLossDecision.mqh>
#include <MstngH1Ea\Strategy\H1EaStrategy.mqh>
#include <MstngH1Ea\Trade\H1EaTradeExecutor.mqh>

/**
 * 既存H1戦略の評価周期と、独立したZigZag保護SL管理を調停する。
 * 単一通貨イベント入口はLIVEのTimer EntryとTick保護を維持する。
 * 通貨別処理の入口はTimerを操作せず、外部スケジュールからも呼び出せる。
 */
class H1EaController {
public:
    /**
     * broker送信権限のない未初期化状態を作る。
     */
    H1EaController() {
        this.started = false;
        this.databaseReady = false;
        this.countsRestored = false;
        this.executorInitialized = false;
        this.auditStateLost = false;
        this.leaseLost = false;
        this.nextMaintenanceTick = 0;
        this.nextEntryTick = 0;
        this.lockAcquiredAt = 0;
        this.lastTrailObservedBar = 0;
        this.lastWarmupBar = 0;
        this.testerWarmupActive = false;
        this.lastAnalysisLogText = "";
        this.lastAnalysisLogTime = 0;
        this.lastAnalysisErrorBar = 0;
        this.analysisRetryBar = 0;
        this.nextAnalysisRetryTime = 0;
    }

    /**
     * 設定と排他Lockを取得してRunを復元する。ここでは発注しない。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime = 0) {
        if (this.preparationState.registered) {
            return false;
        }
        if (!this.config.initialize(fromSymbol, fromLotSize, fromMaxInitialStopLossPips,
                fromTesterTradeStartTime)) {
            this.logger.error("H1EaController.initialize", this.config.lastError);
            return false;
        }
        this.logger.initialize(this.config.symbolName, this.config.magicNumber, this.config.runUid);
        if (!this.strategy.initialize(this.config.symbolName)) {
            this.logger.error("H1EaController.initialize", this.strategy.getLastError());
            return false;
        }
        if (!this.instanceLock.acquire(this.config.lockScope)) {
            this.logger.error("H1EaController.initialize", "INSTANCE_ALREADY_LOCKED");
            this.strategy.destroy();
            return false;
        }
        this.lockAcquiredAt = TimeLocal();
        this.initializeRun();
        if (StringLen(this.run.configHash) != 64 || StringLen(this.run.analysisInputHash) != 64) {
            this.logger.error("H1EaController.initialize", "CONFIG_HASH_UNAVAILABLE");
            this.strategy.destroy();
            this.instanceLock.release();
            return false;
        }
        this.started = true;
        this.lastTrailObservedBar = iTime(this.config.symbolName, PERIOD_H1, 0);
        this.nextEntryTick = GetTickCount64() + 1000;
        if (!this.connectAndRestore()) {
            this.logger.error("H1EaController.initialize", "DB制限状態: " + this.persistence.getLastError());
        }
        if (this.leaseLost) {
            this.shutdown(REASON_INITFAILED);
            return false;
        }
        this.nextMaintenanceTick = H1EaClock::milliseconds() + 5000;
        this.logger.info("H1EaController.initialize", "START " + this.config.contextKey
            + " DB=" + this.config.databaseFileName + " " + this.config.createCanonicalText());
        return true;
    }

    /**
     * 外部巡回用に通貨だけを登録する。DB・Lock・取引機能は初期化しない。
     * 分析リソースの作成は最初の巡回に委ね、28通貨の同期作業をOnInitへ集中させない。
     *
     * @param fromSymbol 事前確認済みのbrokerシンボル名。
     * @return 他の起動経路を使用しておらず、登録できた場合true。
     */
    bool initializePreparation(const string fromSymbol) {
        if (this.started || this.preparationState.registered || fromSymbol == "") {
            return false;
        }
        this.preparationState.reset();
        this.preparationState.symbolName = fromSymbol;
        this.preparationState.registered = true;
        this.preparationState.status = "REGISTERED";
        return true;
    }

    /**
     * この通貨の履歴を準備する。波動分析・Judge・SignalCountの更新は行わない。
     * 準備済みの同一H1は省略し、未準備なら次の巡回で再確認する。
     */
    void processPreparation() {
        if (this.started || !this.preparationState.registered) {
            return;
        }
        datetime barTime = iTime(this.preparationState.symbolName, PERIOD_H1, 0);
        if (this.preparationState.historyReady && barTime > 0
                && barTime == this.preparationState.h1BarTime) {
            return;
        }
        this.preparationState.historyReady = false;
        this.preparationState.h1BarTime = barTime;
        if (!this.preparationState.resourcesInitialized) {
            if (!this.strategy.initialize(this.preparationState.symbolName)) {
                this.preparationState.status = "ERROR";
                this.preparationState.reason = this.strategy.getLastError();
                return;
            }
            this.preparationState.resourcesInitialized = true;
        }
        if (!this.strategy.prepareHistory()) {
            this.preparationState.status = "WAIT_HISTORY";
            this.preparationState.reason = this.strategy.getLastError();
            return;
        }
        if (barTime <= 0 || barTime != iTime(this.preparationState.symbolName, PERIOD_H1, 0)) {
            this.preparationState.status = "WAIT_HISTORY";
            this.preparationState.reason = "H1_BAR_UNAVAILABLE_OR_CHANGED";
            return;
        }
        this.preparationState.historyReady = true;
        this.preparationState.status = "READY";
        this.preparationState.reason = "";
    }

    /**
     * 読み取り用の準備状態コピーを返す。呼び出し元から内部状態を変更できない。
     */
    void getPreparationState(H1EaPreparationState &fromState) {
        fromState = this.preparationState;
    }

    /**
     * 起動時の状態に合わせてイベントタイマーを開始する。
     */
    bool startTimer() {
        if (!this.started) {
            return false;
        }
        return this.updateEventTimer(this.canUseFastTesterWarmup());
    }

    /**
     * Tick側で照合・SL管理を行い、TesterだけEntryを評価する。
     * リスクのないTester準備中は履歴確認と低頻度のLease維持だけを行う。
     */
    void onTick() {
        if (!this.started) {
            return;
        }
        bool fastWarmup = this.canUseFastTesterWarmup();
        if (!this.updateEventTimer(fastWarmup)) {
            fastWarmup = false;
        }
        if (fastWarmup) {
            this.processMaintenance(true);
            if (this.canUseFastTesterWarmup()) {
                this.processWarmup();
                return;
            }
            this.updateEventTimer(false);
        }
        this.processMaintenance();
        datetime barTime = iTime(this.config.symbolName, PERIOD_H1, 0);
        this.processProtection(barTime);
        this.processTrail(barTime);
        if (this.config.isTester) {
            this.processEntry(this.eventTimer.isNormalReady());
        }
    }

    /**
     * 通常1秒、リスクのないTester準備中は30秒TimerでLeaseを維持する。
     * LIVEの初回1秒・以降30秒評価は変更しない。
     */
    void onTimer() {
        if (!this.started) {
            return;
        }
        bool fastWarmup = this.canUseFastTesterWarmup();
        if (!this.updateEventTimer(fastWarmup)) {
            fastWarmup = false;
        }
        if (fastWarmup) {
            this.processMaintenance(true);
            if (this.canUseFastTesterWarmup()) {
                return;
            }
            this.updateEventTimer(false);
        }
        this.processMaintenance();
        this.processTradeReconciliation();
        if (!this.config.isTester && GetTickCount64() >= this.nextEntryTick) {
            this.nextEntryTick = GetTickCount64() + 30000;
            this.processEntry(this.eventTimer.isNormalReady());
        }
    }

    /**
     * 通貨単位のDB・Lease保守を実行する。Timerは変更しない。
     *
     * @param fromFastWarmup 高速保守を希望する場合true。安全条件を再確認する。
     */
    void processMaintenance(const bool fromFastWarmup = false) {
        if (!this.started) {
            return;
        }
        if (fromFastWarmup && this.canUseFastTesterWarmup()) {
            this.maintainFastTesterWarmup();
            return;
        }
        this.maintainPersistence();
    }

    /**
     * 通貨単位の管理権限を更新し、brokerの取引状態を照合する。
     */
    void processTradeReconciliation() {
        if (!this.started || !this.executorInitialized) {
            return;
        }
        this.updateManagementAuthority();
        this.executor.reconcile();
    }

    /**
     * 通貨単位の照合と保護SL・候補跨ぎ処理を実行する。波動分析は行わない。
     *
     * @param fromBarTime この通貨で取得した現在H1バー。取得不能時は0。
     */
    void processProtection(const datetime fromBarTime) {
        if (!this.started || !this.executorInitialized) {
            return;
        }
        this.processTradeReconciliation();
        this.executor.processPending(fromBarTime);
    }

    /**
     * 通貨単位のH1新規バーでトレイルを評価する。Entry状態は変更しない。
     *
     * @param fromBarTime 保護処理と共通の、この通貨の現在H1バー。
     */
    void processTrail(const datetime fromBarTime) {
        if (!this.started || !this.executorInitialized) {
            return;
        }
        if (fromBarTime > 0 && fromBarTime != this.lastTrailObservedBar) {
            this.lastTrailObservedBar = fromBarTime;
            if (this.executor.isTrailEligible(fromBarTime)) {
                H1EaStrategySnapshot trailSnapshot;
                if (this.strategy.analyze(trailSnapshot)) {
                    this.executor.evaluateTrail(fromBarTime, this.strategy.getWave());
                } else {
                    this.executor.evaluateTrail(fromBarTime, NULL, this.strategy.getLastError());
                }
                this.executor.processPending(fromBarTime);
            }
        }
    }

    /**
     * 外部スケジュールから通貨単位のEntry評価を実行する。Timerは変更しない。
     *
     * @param fromNormalTimerReady 呼び出し元の通常Timer設定が成功済みの場合true。
     */
    void processEntry(const bool fromNormalTimerReady) {
        if (!this.started) {
            return;
        }
        this.evaluateEntry(fromNormalTimerReady);
    }

    /**
     * Tester売買開始前の履歴準備を実行する。Judge回数は消費しない。
     */
    void processWarmup() {
        if (!this.started || !this.config.isBeforeTesterTradeStart(TimeCurrent())) {
            return;
        }
        this.processTesterWarmup();
    }

    /**
     * Tester売買開始前かつ、DB・排他・照合済み取引状態がすべて安全な場合だけ軽量化する。
     * ポジション・注文の総数は他銘柄も含め、存在時は保守的に通常管理へ戻す。
     */
    bool canUseFastTesterWarmup() {
        if (!this.started || !this.config.isBeforeTesterTradeStart(TimeCurrent())
                || !this.databaseReady || !this.countsRestored || !this.executorInitialized
                || this.auditStateLost || this.leaseLost || !this.instanceLock.isHeld()
                || this.run.id <= 0 || this.run.leaseExpiresAt <= TimeLocal()
                || ArraySize(this.decisionQueue) > 0) {
            return false;
        }
        return this.executor.isIdleForTesterWarmup()
            && PositionsTotal() == 0 && OrdersTotal() == 0;
    }

    /**
     * broker通知は発注の戻り値より優先して履歴へ照合する。
     */
    void onTradeTransaction(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
        if (this.started && this.executorInitialized) {
            this.executor.onTradeTransaction(fromTransaction, fromRequest, fromResult);
        }
    }

    /**
     * 保存を試みてLeaseとLockを解放する。保有ポジションは閉じない。
     */
    void shutdown(const int fromReason) {
        if (this.preparationState.registered) {
            this.strategy.destroy();
            this.preparationState.reset();
            return;
        }
        if (this.started) {
            this.flushDecisions();
            bool tradeQueueSaved = true;
            if (this.executorInitialized) {
                tradeQueueSaved = this.executor.flushPendingEvents();
                // 注文を送らない最終照合を行い、決済明細の未完了も検出する。
                this.executor.reconcile();
                tradeQueueSaved = this.executor.flushPendingEvents() && tradeQueueSaved;
            }
            string status = "STOPPED";
            string errorText = "";
            if (fromReason == REASON_INITFAILED) {
                status = "FAILED";
                errorText = "INITIALIZATION_FAILED";
            }
            if (ArraySize(this.decisionQueue) > 0 || !tradeQueueSaved || this.auditStateLost) {
                status = "FAILED";
                errorText = "AUDIT_STATE_LOST: 未保存Decision/Eventを完全復元できません";
                this.logger.error("H1EaController.shutdown", errorText);
            } else if (this.executorInitialized && this.executor.hasPendingDealAudit()) {
                status = "FAILED";
                errorText = "DEAL_AUDIT_PENDING: 約定明細の保存確認が未完了です。同contextで履歴再照合が必要です";
                this.logger.error("H1EaController.shutdown", errorText);
            }
            if (this.run.id > 0 && !this.persistence.finishRun(this.run.id, status, errorText)) {
                this.logger.error("H1EaController.shutdown", "RUN_END_UNSAVED " + errorText);
            }
            this.logger.info("H1EaController.shutdown", "STOP reason=" + IntegerToString(fromReason));
        }
        this.started = false;
        this.persistence.close();
        this.strategy.destroy();
        this.instanceLock.release();
    }

private:
    /** DB・取引を使用しない外部巡回用の通貨別準備状態。 */
    H1EaPreparationState preparationState;
    /** 有効設定。 */
    H1EaConfig config;
    /** DBに依存しない運用ログ。 */
    H1EaOperationLogger logger;
    /** DB障害中も保持する排他Lock。 */
    H1EaInstanceLock instanceLock;
    /** Runと取引の永続化。 */
    H1EaPersistenceService persistence;
    /** 今回のRunと最後に確認したLease。 */
    H1EaRunEntity run;
    /** 既存H1判定の分析アダプター。 */
    H1EaStrategy strategy;
    /** brokerとの取引整合。 */
    H1EaTradeExecutor executor;
    /** トレイルとは分離したEntry消費状態。 */
    H1EaEntryState entryState;
    /** 保存だけを再試行する確定SKIP。上限256件。 */
    H1EaDecisionEntity decisionQueue[];
    /** 初期化済み。 */
    bool started;
    /** 現在DBを利用可能。 */
    bool databaseReady;
    /** 全回数の復元完了。 */
    bool countsRestored;
    /** Executorへ依存を設定済み。 */
    bool executorInitialized;
    /** 既知の監査欠落では新規Entryを永久停止する。 */
    bool auditStateLost;
    /** 失効したLeaseを同じRunで復活させない。 */
    bool leaseLost;
    /** 次のDB再接続・キュー処理時刻。 */
    ulong nextMaintenanceTick;
    /** LIVE Entryの次回評価時刻。 */
    ulong nextEntryTick;
    /** 初回DB接続待ちの安全期限の基準。 */
    datetime lockAcquiredAt;
    /** トレイル専用の観測バー。 */
    datetime lastTrailObservedBar;
    /** Testerの開始前分析だけに使う観測バー。Entry状態と共有しない。 */
    datetime lastWarmupBar;
    /** Testerの売買開始前期間を観測済み。 */
    bool testerWarmupActive;
    /** 最後に出力した分析待機理由。毎Tickの同一ログを抑制する。 */
    string lastAnalysisLogText;
    /** 最後に分析待機理由を出力したサーバー時刻。 */
    datetime lastAnalysisLogTime;
    /** 履歴待機以外の分析エラーを最後に出力したH1バー。 */
    datetime lastAnalysisErrorBar;
    /** TesterのEntry分析に失敗したH1バー。トレイルやLIVEと共有しない。 */
    datetime analysisRetryBar;
    /** Tester内時刻での次回Entry分析時刻。成功時・H1切替時に解除する。 */
    datetime nextAnalysisRetryTime;
    /** 単一通貨イベント入口のTimer管理。通貨別処理からは操作しない。 */
    H1EaEventTimer eventTimer;

    /**
     * 準備中30秒・通常1秒へ切り替える。更新失敗を成功扱いせず新規Entryを保留する。
     * 既存ポジションのTick起点の保護はTimer復旧待ちでも止めない。
     */
    bool updateEventTimer(const bool fromFastWarmup) {
        bool resetMaintenance = false;
        bool updated = this.eventTimer.update(fromFastWarmup, this.logger, resetMaintenance);
        if (resetMaintenance) {
            // Timer設定失敗時も高速期間の保守待ちを解除する。
            this.nextMaintenanceTick = 0;
        }
        return updated;
    }

    /**
     * 空のTester準備期間だけ、DB更新とキュー確認を最短30秒間隔にまとめる。
     * Leaseの有効期限60秒や失効時の停止条件は緩和しない。
     */
    void maintainFastTesterWarmup() {
        if (TimeLocal() >= this.run.heartbeatAt + 30) {
            this.maintainPersistence(true);
        }
    }

    /**
     * 登録前Runの固定設定を作成する。
     */
    void initializeRun() {
        this.run.reset();
        this.run.runUid = this.config.runUid;
        this.run.sourceMode = this.config.sourceMode;
        this.run.contextKey = this.config.contextKey;
        this.run.accountServer = this.config.accountServer;
        this.run.accountLogin = this.config.accountLogin;
        this.run.symbolName = this.config.symbolName;
        this.run.magicNumber = H1EaTextUtil::ticket(this.config.magicNumber);
        this.run.programVersion = H1EaConfig::getProgramVersion();
        this.run.strategyVersion = H1EaConfig::getStrategyVersion();
        this.run.analysisVersion = ZigZagElliotAnalysisProfile::getAnalysisVersion();
        this.run.analysisInputText = ZigZagElliotAnalysisProfile::createCanonicalText();
        this.run.analysisInputHash = ZigZagElliotAnalysisProfile::createHash();
        this.run.configText = this.config.createCanonicalText();
        this.run.configHash = H1EaTextUtil::hash(this.run.configText);
        this.run.startedAt = TimeLocal();
    }

    /**
     * DBを再接続し、初回だけRun・消費済みSKIP・保護状態を復元する。
     */
    bool connectAndRestore() {
        if (this.leaseLost) {
            return false;
        }
        if (this.run.id == 0 && TimeLocal() >= this.lockAcquiredAt + 60) {
            this.leaseLost = true;
            this.logger.error("H1EaController.connectAndRestore", "INITIAL_DB_RECOVERY_DEADLINE_EXPIRED");
            return false;
        }
        if (!this.persistence.open(this.config.databaseFileName, this.run.id == 0)) {
            return false;
        }
        if (this.run.id == 0 && !this.persistence.acquireRun(this.run)) {
            if (this.persistence.getLastError() == "RUN_CONTEXT_ALREADY_ACTIVE") {
                this.leaseLost = true;
            }
            return false;
        }
        if (!this.persistence.hasLease(this.run.id, TimeLocal())) {
            if (this.persistence.getLastError() == "LEASE_NOT_OWNED") {
                this.leaseLost = true;
            }
            return false;
        }
        if (!this.countsRestored) {
            long referenceTimes[];
            string sides[];
            int counts[];
            bool hasGap = false;
            if (!this.persistence.loadSignalCounts(this.config.contextKey, referenceTimes, sides, counts)
                    || !this.entryState.restore(referenceTimes, sides, counts)
                    || !this.persistence.hasAuditGap(this.config.contextKey, hasGap)) {
                return false;
            }
            this.auditStateLost = hasGap;
            datetime currentBar = iTime(this.config.symbolName, PERIOD_H1, 0);
            if (currentBar <= 0) {
                return false;
            }
            H1EaDecisionEntity savedDecision;
            bool found = false;
            if (currentBar > 0 && !this.persistence.loadDecision(this.config.contextKey,
                    currentBar, savedDecision, found)) {
                return false;
            }
            if (found) {
                this.entryState.finalize(currentBar);
            }
            this.countsRestored = true;
        }
        if (!this.executorInitialized) {
            if (!this.executor.initialize(this.config.symbolName, this.config.magicNumber,
                    this.config.pipSize, this.config.tickSize, this.run.id, this.run.runUid,
                    this.config.contextKey, GetPointer(this.persistence))) {
                return false;
            }
            this.executorInitialized = true;
        }
        datetime blockedBar = 0;
        if (!this.persistence.loadCrossBlockedBar(this.config.contextKey, blockedBar)) {
            return false;
        }
        this.executor.setBlockedEntryBar(blockedBar);
        this.databaseReady = true;
        this.updateManagementAuthority();
        this.executor.flushPendingEvents();
        this.executor.reconcile();
        return true;
    }

    /**
     * 通常10秒、空のTester準備中だけ30秒ごとにLeaseを更新する。
     * 通常のDB再試行は最短5秒間隔とする。
     */
    void maintainPersistence(const bool fromFastWarmup = false) {
        int heartbeatSeconds = 10;
        ulong maintenanceMilliseconds = 5000;
        if (fromFastWarmup) {
            heartbeatSeconds = 30;
            maintenanceMilliseconds = 30000;
        }
        datetime now = TimeLocal();
        if (this.run.id > 0 && this.run.leaseExpiresAt <= now && !this.leaseLost) {
            this.leaseLost = true;
            this.logger.error("H1EaController.maintainPersistence", "LEASE_EXPIRED: broker SL以外の操作を停止");
        }
        bool heartbeatDue = this.databaseReady && !this.leaseLost
            && now >= this.run.heartbeatAt + heartbeatSeconds;
        if (heartbeatDue && !this.persistence.heartbeat(this.run, now)) {
            if (!this.persistence.hasLease(this.run.id, now)
                    && this.persistence.getLastError() == "LEASE_NOT_OWNED") {
                this.leaseLost = true;
            }
            this.databaseReady = false;
            this.logger.error("H1EaController.maintainPersistence", "HEARTBEAT_FAILED");
        }
        this.updateManagementAuthority();
        if (H1EaClock::milliseconds() < this.nextMaintenanceTick) {
            return;
        }
        this.nextMaintenanceTick = H1EaClock::milliseconds() + maintenanceMilliseconds;
        if (!this.databaseReady && !this.leaseLost) {
            this.connectAndRestore();
        }
        if (this.databaseReady) {
            this.flushDecisions();
            if (this.executorInitialized) {
                this.executor.flushPendingEvents();
            }
        }
    }

    /**
     * Lockと既知Leaseの両方が有効な期間だけ保護操作を許可する。
     */
    void updateManagementAuthority() {
        if (!this.executorInitialized) {
            return;
        }
        datetime expires = (datetime)this.run.leaseExpiresAt;
        if (this.leaseLost) {
            expires = 0;
        }
        this.executor.setManagementAuthority(this.instanceLock.isHeld(), expires);
    }

    /**
     * 対象バーの最初の分析成功時だけJudge・Entryを確定する。
     */
    void evaluateEntry(const bool fromNormalTimerReady) {
        if (this.config.isBeforeTesterTradeStart(TimeCurrent())) {
            this.processTesterWarmup();
            return;
        }
        if (this.testerWarmupActive) {
            this.testerWarmupActive = false;
            this.logger.info("H1EaController.evaluateEntry", "TESTER_TRADE_PERIOD_STARTED start="
                + TimeToString(this.config.testerTradeStartTime, TIME_DATE | TIME_SECONDS)
                + " current=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
        }
        if (!fromNormalTimerReady) {
            return;
        }
        if (!this.countsRestored || this.run.id <= 0) {
            return;
        }
        datetime barTime = iTime(this.config.symbolName, PERIOD_H1, 0);
        if (barTime <= 0) {
            return;
        }
        datetime expiredBar = this.entryState.observe(barTime);
        if (expiredBar > 0) {
            H1EaDecisionEntity unavailable;
            this.initializeDecision(unavailable, expiredBar);
            unavailable.reasonCode = "ANALYSIS_UNAVAILABLE";
            this.enqueueDecision(unavailable);
            this.flushDecisions();
        }
        if (this.entryState.isFinalized(barTime)) {
            return;
        }
        if (this.config.isTester && this.analysisRetryBar == barTime
                && TimeCurrent() < this.nextAnalysisRetryTime) {
            return;
        }
        this.analysisRetryBar = 0;
        this.nextAnalysisRetryTime = 0;
        H1EaStrategySnapshot snapshot;
        if (!this.strategy.analyze(snapshot)) {
            // 未準備の同一H1だけ最短1秒で再試行し、判定回数はまだ消費しない。
            if (this.config.isTester) {
                this.analysisRetryBar = barTime;
                this.nextAnalysisRetryTime = TimeCurrent() + 1;
            }
            this.logAnalysisWait(barTime);
            return;
        }
        this.clearAnalysisWait();
        if (snapshot.h1BarTime != barTime) {
            this.logger.error("H1EaController.evaluateEntry", "ANALYSIS_BAR_CHANGED: Judge未消費で再試行");
            return;
        }
        int previousCount = this.entryState.getCount(snapshot.signalReferenceTime, snapshot.signalSide);
        if (!this.strategy.evaluate(previousCount, snapshot)) {
            this.logger.error("H1EaController.evaluateEntry", this.strategy.getLastError());
            return;
        }
        H1EaDecisionEntity decision;
        this.buildDecision(snapshot, decision);
        if (decision.isJudgeMatched && !this.entryState.recordCount(
                decision.signalReferenceTime, decision.signalSide, decision.signalCount)) {
            this.auditStateLost = true;
            decision.reasonCode = "AUDIT_STATE_LOST";
        }
        this.entryState.finalize(barTime);
        if (decision.isStrategyEntry) {
            this.applyEntrySafety(snapshot, decision);
        }
        if (!H1EaDecisionBuilder::seal(decision, this.config.digits)) {
            this.auditStateLost = true;
            decision.decision = "SKIP";
            decision.reasonCode = "SNAPSHOT_HASH_UNAVAILABLE";
            this.enqueueDecision(decision);
            return;
        }
        if (decision.decision != "SKIP") {
            H1EaTradeEntity trade;
            H1EaTradeEventEntity event;
            this.executor.prepareEntry(decision, trade, event);
            if (this.persistence.saveEntry(this.run.id, decision, trade, event)) {
                this.executor.sendEntry(trade, event);
                this.logDecision(decision);
                return;
            }
            decision.decision = "SKIP";
            decision.reasonCode = "DB_UNAVAILABLE";
            this.databaseReady = false;
        }
        this.enqueueDecision(decision);
        this.flushDecisions();
    }

    /**
     * 売買開始前はH1ごとの履歴確認だけを行い、波動分析・Judge・Decisionを作らない。
     */
    void processTesterWarmup() {
        if (!this.testerWarmupActive) {
            this.testerWarmupActive = true;
            this.logger.info("H1EaController.processTesterWarmup", "TESTER_WARMUP start="
                + TimeToString(this.config.testerTradeStartTime, TIME_DATE | TIME_SECONDS)
                + " 履歴確認のみ・波動分析・発注・Judge回数消費・Decision保存なし");
        }
        datetime barTime = iTime(this.config.symbolName, PERIOD_H1, 0);
        if (barTime <= 0 || barTime == this.lastWarmupBar) {
            return;
        }
        this.lastWarmupBar = barTime;
        if (!this.strategy.prepareHistory()) {
            this.logAnalysisWait(barTime);
            return;
        }
        this.clearAnalysisWait(true);
    }

    /**
     * 履歴待機はINFOで最大1時間に1回、変化がない場合は1日に1回だけ出力する。
     * その他の分析エラーも同一理由・同一H1バーで重複出力しない。
     */
    void logAnalysisWait(const datetime fromBar) {
        string reason = this.strategy.getLastError();
        string message = reason;
        datetime now = TimeCurrent();
        if (reason == "ANALYSIS_HISTORY_UNAVAILABLE") {
            message += " " + this.strategy.getHistoryStatusText();
            long elapsedSeconds = (long)(now - this.lastAnalysisLogTime);
            if (this.lastAnalysisLogText != "" && elapsedSeconds >= 0
                    && elapsedSeconds < 86400
                    && (message == this.lastAnalysisLogText || elapsedSeconds < 3600)) {
                return;
            }
            this.logger.info("H1EaController.logAnalysisWait", "H1=" + IntegerToString(fromBar)
                + " " + message);
        } else {
            if (message == this.lastAnalysisLogText && fromBar == this.lastAnalysisErrorBar) {
                return;
            }
            this.lastAnalysisErrorBar = fromBar;
            this.logger.error("H1EaController.logAnalysisWait", "H1=" + IntegerToString(fromBar)
                + " " + message);
        }
        this.lastAnalysisLogText = message;
        this.lastAnalysisLogTime = now;
    }

    /**
     * 分析再開を1回だけ通知し、次の障害を初回から記録できるようにする。
     */
    void clearAnalysisWait(const bool fromHistoryOnly = false) {
        if (this.lastAnalysisLogText != "") {
            string readyCode = "ANALYSIS_READY";
            if (fromHistoryOnly) {
                readyCode = "HISTORY_READY";
            }
            this.logger.info("H1EaController.clearAnalysisWait", readyCode + " "
                + this.strategy.getHistoryStatusText());
        }
        this.lastAnalysisLogText = "";
        this.lastAnalysisLogTime = 0;
        this.lastAnalysisErrorBar = 0;
    }

    /**
     * 分析不能時にも使える未判定行の共通項目を設定する。
     */
    void initializeDecision(H1EaDecisionEntity &fromDecision, const datetime fromBar) {
        fromDecision.reset();
        fromDecision.runId = this.run.id;
        fromDecision.contextKey = this.config.contextKey;
        fromDecision.h1BarTime = fromBar;
        fromDecision.evaluatedServerTime = TimeCurrent();
        fromDecision.createdAt = TimeLocal();
        fromDecision.maxInitialRiskPips = this.config.maxInitialStopLossPips;
        fromDecision.h1DirectionAlignmentMode =
            "H1_DIRECTION_ALIGNMENT_"
            + getH1DirectionAlignmentModeText(
                Mtf3In3H1Policy::getDirectionAlignmentMode()
            );
    }

    /**
     * 戦略診断値とEA発注可否を混同せずEntityへ移す。
     */
    void buildDecision(H1EaStrategySnapshot &fromSnapshot, H1EaDecisionEntity &fromDecision) {
        this.initializeDecision(fromDecision, fromSnapshot.h1BarTime);
        fromDecision.evaluatedServerTime = fromSnapshot.evaluatedTime;
        fromDecision.signalReferenceTime = fromSnapshot.signalReferenceTime;
        fromDecision.signalSide = fromSnapshot.signalSide;
        fromDecision.reasonCode = fromSnapshot.reasonCode;
        fromDecision.isJudgeMatched = fromSnapshot.isJudge;
        fromDecision.signalCount = fromSnapshot.signalCount;
        fromDecision.isEntryEvaluated = fromSnapshot.isEntryEvaluated;
        fromDecision.isStrategyEntry = fromSnapshot.isStrategyEntry;
        fromDecision.isSignalConsumed = fromSnapshot.isSignalConsumed;
        fromDecision.spreadPips = fromSnapshot.spreadPips;
        fromDecision.mn1Direction = fromSnapshot.mn1Direction;
        fromDecision.w1Direction = fromSnapshot.w1Direction;
        fromDecision.d1Direction = fromSnapshot.d1Direction;
        fromDecision.h4Direction = fromSnapshot.h4Direction;
        fromDecision.h1Direction = fromSnapshot.h1Direction;
        fromDecision.h1WaveDirection = fromSnapshot.h1WaveDirection;
        fromDecision.h1ElliotLabel = fromSnapshot.h1ElliotLabel;
        fromDecision.h4ElliotLabel = fromSnapshot.h4ElliotLabel;
        fromDecision.isH1WaveAccepted = fromSnapshot.isH1WaveAccepted && fromSnapshot.isEntryEvaluated;
        fromDecision.isH4WaveAccepted = fromSnapshot.isH4WaveAccepted && fromSnapshot.isEntryEvaluated;
        fromDecision.h1GmmaTrendCount = fromSnapshot.h1GmmaTrendCount;
        fromDecision.h1GmmaCrossCount = fromSnapshot.h1GmmaCrossCount;
        fromDecision.h1Ema200Direction = fromSnapshot.h1Ema200Direction;
        fromDecision.h4Ema200Direction = fromSnapshot.h4Ema200Direction;
        fromDecision.w1Ema200Direction = fromSnapshot.w1Ema200Direction;
        fromDecision.d1Ema200Direction = fromSnapshot.d1Ema200Direction;
        fromDecision.isEma200ConfirmationPassed = fromSnapshot.isEma200ConfirmationPassed;
        fromDecision.hasEma200ConfirmationDiagnostics = true;
        fromDecision.isH1DirectionAlignmentPassed = fromSnapshot.isH1DirectionAlignmentPassed;
        if (fromDecision.signalReferenceTime > 0 && fromDecision.signalSide != "") {
            fromDecision.marketSignalKey = this.config.accountServer + "|" + this.config.symbolName
                + "|" + IntegerToString(PERIOD_H1) + "|" + IntegerToString(fromDecision.h1BarTime)
                + "|" + IntegerToString(fromDecision.signalReferenceTime) + "|MTF_3in3|"
                + fromDecision.signalSide;
        }
    }

    /**
     * 初回消費後にだけ保有制限・DB・ロット・初期SLを確認する。
     */
    void applyEntrySafety(H1EaStrategySnapshot &fromSnapshot, H1EaDecisionEntity &fromDecision) {
        if (this.auditStateLost) {
            fromDecision.reasonCode = "AUDIT_STATE_LOST";
            return;
        }
        if (this.leaseLost || !this.databaseReady || ArraySize(this.decisionQueue) > 0
                || !this.executorInitialized || this.executor.hasUnsavedEvents()) {
            fromDecision.reasonCode = "DB_UNAVAILABLE";
            return;
        }
        if (iTime(this.config.symbolName, PERIOD_H1, 0) != fromSnapshot.h1BarTime) {
            fromDecision.reasonCode = "ANALYSIS_BAR_CHANGED";
            return;
        }
        string reason = "";
        if (!this.executor.canEnter(fromSnapshot.h1BarTime, reason)) {
            fromDecision.reasonCode = reason;
            return;
        }
        double volume = 0.0;
        if (!this.normalizeVolume(volume)) {
            fromDecision.reasonCode = "INVALID_VOLUME";
            return;
        }
        fromDecision.requestedVolume = volume;
        MqlTick marketTick;
        if (!SymbolInfoTick(this.config.symbolName, marketTick)) {
            fromDecision.reasonCode = "PRICE_UNAVAILABLE";
            return;
        }
        H1EaInitialStopLossResult stopLoss;
        H1EaInitialStopLossDecision initialStopLossDecision;
        initialStopLossDecision.evaluate(fromSnapshot.isBuy, fromSnapshot.signalReferencePrice,
            fromSnapshot.signalReferenceIsHigh, marketTick.bid, marketTick.ask,
            this.config.pipSize, this.config.tickSize, this.config.pointSize,
            SymbolInfoInteger(this.config.symbolName, SYMBOL_TRADE_STOPS_LEVEL),
            this.config.maxInitialStopLossPips, stopLoss);
        fromDecision.initialStopLoss = stopLoss.stopLoss;
        fromDecision.initialRiskPips = stopLoss.riskPips;
        if (!stopLoss.isAccepted) {
            fromDecision.reasonCode = stopLoss.reasonCode;
            return;
        }
        fromDecision.decision = fromSnapshot.signalSide;
        fromDecision.reasonCode = "ENTRY_ACCEPTED";
    }

    /**
     * brokerの最小・最大・stepへ固定ロットを正規化する。
     */
    bool normalizeVolume(double &fromVolume) {
        double minimum = SymbolInfoDouble(this.config.symbolName, SYMBOL_VOLUME_MIN);
        double maximum = SymbolInfoDouble(this.config.symbolName, SYMBOL_VOLUME_MAX);
        double step = SymbolInfoDouble(this.config.symbolName, SYMBOL_VOLUME_STEP);
        if (!MathIsValidNumber(minimum) || !MathIsValidNumber(maximum)
                || !MathIsValidNumber(step) || minimum <= 0.0 || maximum < minimum || step <= 0.0) {
            return false;
        }
        double requested = MathMax(minimum, MathMin(maximum, this.config.lotSize));
        fromVolume = NormalizeDouble(MathFloor(requested / step + 0.00000001) * step, 8);
        return fromVolume >= minimum - 0.00000001 && fromVolume <= maximum + 0.00000001;
    }

    /**
     * 確定値を最大256件まで保持する。復旧後の注文へ変換しない。
     */
    void enqueueDecision(H1EaDecisionEntity &fromDecision) {
        fromDecision.decision = "SKIP";
        if (!H1EaDecisionBuilder::seal(fromDecision, this.config.digits)) {
            this.auditStateLost = true;
        }
        int queueSize = ArraySize(this.decisionQueue);
        if (queueSize >= 256 || ArrayResize(this.decisionQueue, queueSize + 1) != queueSize + 1) {
            this.auditStateLost = true;
            this.logger.error("H1EaController.enqueueDecision", "AUDIT_STATE_LOST QUEUE_OVERFLOW H1="
                + IntegerToString(fromDecision.h1BarTime) + " hash=" + fromDecision.snapshotHash);
            return;
        }
        this.decisionQueue[queueSize] = fromDecision;
        this.logDecision(fromDecision);
    }

    /**
     * Judge回数・Entryを再評価せず、最初の確定値だけをFIFOで保存する。
     */
    void flushDecisions() {
        if (!this.databaseReady || this.leaseLost || this.run.id <= 0) {
            return;
        }
        while (ArraySize(this.decisionQueue) > 0) {
            if (!this.persistence.saveDecision(this.run.id, this.decisionQueue[0])) {
                this.databaseReady = false;
                this.logger.error("H1EaController.flushDecisions", this.persistence.getLastError());
                return;
            }
            int queueSize = ArraySize(this.decisionQueue);
            for (int i = 1; i < queueSize; i++) {
                this.decisionQueue[i - 1] = this.decisionQueue[i];
            }
            ArrayResize(this.decisionQueue, queueSize - 1);
        }
    }

    /**
     * DB停止中にも最初に確定した判定と識別値を残す。
     */
    void logDecision(H1EaDecisionEntity &fromDecision) {
        this.logger.info("H1EaController.evaluateEntry", "H1=" + IntegerToString(fromDecision.h1BarTime)
            + " ref=" + IntegerToString(fromDecision.signalReferenceTime)
            + " side=" + fromDecision.signalSide + " count=" + IntegerToString(fromDecision.signalCount)
            + " decision=" + fromDecision.decision + " reason=" + fromDecision.reasonCode
            + " hash=" + fromDecision.snapshotHash);
    }
};

#endif
