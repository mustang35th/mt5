#ifndef MSTNGH1EA_CONTROLLER_MQH
#define MSTNGH1EA_CONTROLLER_MQH

#include <Mstng\Database\Service\H1EaPersistenceService.mqh>
#include <MstngH1Ea\Config\H1EaConfig.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaDecisionBuilder.mqh>
#include <MstngH1Ea\Runtime\H1EaEntryState.mqh>
#include <MstngH1Ea\Runtime\H1EaInstanceLock.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>
#include <MstngH1Ea\Strategy\H1EaInitialStopLossDecision.mqh>
#include <MstngH1Ea\Strategy\H1EaStrategy.mqh>
#include <MstngH1Ea\Trade\H1EaTradeExecutor.mqh>

/**
 * 既存H1戦略の評価周期と、独立したZigZag保護SL管理を調停する。
 * LIVEではTimerだけがEntryを開始し、保護操作はTickだけが開始する。
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
        this.timerSeconds = 0;
        this.nextTimerRetryTick = 0;
    }

    /**
     * 設定と排他Lockを取得してRunを復元する。ここでは発注しない。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime = 0) {
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
     * 起動時の状態に合わせてイベントタイマーを開始する。
     */
    bool startTimer() {
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
            this.maintainFastTesterWarmup();
            if (this.canUseFastTesterWarmup()) {
                this.processTesterWarmup();
                return;
            }
            this.updateEventTimer(false);
        }
        this.maintainPersistence();
        datetime barTime = iTime(this.config.symbolName, PERIOD_H1, 0);
        if (this.executorInitialized) {
            this.updateManagementAuthority();
            this.executor.reconcile();
            this.executor.processPending(barTime);
            if (barTime > 0 && barTime != this.lastTrailObservedBar) {
                this.lastTrailObservedBar = barTime;
                if (this.executor.isTrailEligible(barTime)) {
                    H1EaStrategySnapshot trailSnapshot;
                    if (this.strategy.analyze(trailSnapshot)) {
                        this.executor.evaluateTrail(barTime, this.strategy.getWave());
                    } else {
                        this.executor.evaluateTrail(barTime, NULL, this.strategy.getLastError());
                    }
                    this.executor.processPending(barTime);
                }
            }
        }
        if (this.config.isTester) {
            this.evaluateEntry();
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
            this.maintainFastTesterWarmup();
            if (this.canUseFastTesterWarmup()) {
                return;
            }
            this.updateEventTimer(false);
        }
        this.maintainPersistence();
        if (this.executorInitialized) {
            this.updateManagementAuthority();
            this.executor.reconcile();
        }
        if (!this.config.isTester && GetTickCount64() >= this.nextEntryTick) {
            this.nextEntryTick = GetTickCount64() + 30000;
            this.evaluateEntry();
        }
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
        if (this.started) {
            this.flushDecisions();
            bool tradeQueueSaved = true;
            if (this.executorInitialized) {
                tradeQueueSaved = this.executor.flushPendingEvents();
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
    /** 設定成功を確認済みのTimer秒数。0は未設定または更新失敗。 */
    int timerSeconds;
    /** Timer設定失敗時の次回試行時刻。最短5秒で再試行する。 */
    ulong nextTimerRetryTick;

    /**
     * Tester売買開始前かつ、DB・排他・照合済み取引状態がすべて安全な場合だけ軽量化する。
     * ポジション・注文の総数は他銘柄も含め、存在時は保守的に通常管理へ戻す。
     */
    bool canUseFastTesterWarmup() {
        if (!this.config.isBeforeTesterTradeStart(TimeCurrent())
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
     * 準備中30秒・通常1秒へ切り替える。更新失敗を成功扱いせず新規Entryを保留する。
     * 既存ポジションのTick起点の保護はTimer復旧待ちでも止めない。
     */
    bool updateEventTimer(const bool fromFastWarmup) {
        int requiredSeconds = 1;
        if (fromFastWarmup) {
            requiredSeconds = 30;
        }
        if (this.timerSeconds == requiredSeconds) {
            return true;
        }
        if (H1EaClock::milliseconds() < this.nextTimerRetryTick) {
            return false;
        }
        if (requiredSeconds == 1) {
            // 高速期間の30秒待ちをDB復旧・未保存イベント処理へ持ち込まない。
            this.nextMaintenanceTick = 0;
        }
        ResetLastError();
        if (!EventSetTimer(requiredSeconds)) {
            int errorCode = GetLastError();
            this.timerSeconds = 0;
            this.nextTimerRetryTick = H1EaClock::milliseconds() + 5000;
            this.logger.error("H1EaController.updateEventTimer", "TIMER_UPDATE_FAILED seconds="
                + IntegerToString(requiredSeconds) + " error=" + IntegerToString(errorCode));
            return false;
        }
        this.timerSeconds = requiredSeconds;
        this.nextTimerRetryTick = 0;
        this.logger.info("H1EaController.updateEventTimer", "TIMER_SECONDS="
            + IntegerToString(this.timerSeconds));
        return true;
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
    void evaluateEntry() {
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
        if (this.timerSeconds != 1) {
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
        H1EaStrategySnapshot snapshot;
        if (!this.strategy.analyze(snapshot)) {
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
            "H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED";
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
