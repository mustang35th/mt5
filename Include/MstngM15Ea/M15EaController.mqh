#ifndef MSTNGM15EA_CONTROLLER_MQH
#define MSTNGM15EA_CONTROLLER_MQH

#include <Mstng\ExpertAdvisor\Runtime\EaClock.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaEntryState.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaInitialStopLossDecision.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTradeExecutor.mqh>
#include <MstngM15Ea\Config\M15EaConfig.mqh>
#include <MstngM15Ea\Persistence\M15EaPersistenceService.mqh>
#include <MstngM15Ea\Runtime\M15EaDecisionBuilder.mqh>
#include <MstngM15Ea\Runtime\M15EaInstanceLock.mqh>
#include <MstngM15Ea\Runtime\M15EaOperationLogger.mqh>
#include <MstngM15Ea\Strategy\M15EaStrategy.mqh>
#include <MstngM15Ea\Trade\M15EaTradePolicy.mqh>

/**
 * M15の判定と専用DBを、共通の回数管理・発注・復元へ接続する。
 * 判定の確定と保存を発注より先に行い、保護処理はEntryと独立して実行する。
 */
class M15EaController {
public:
    /**
     * 発注権限のない未初期化状態を作る。
     */
    M15EaController() {
        this.initializationAttempted = false;
        this.started = false;
        this.timerReady = false;
        this.databaseReady = false;
        this.countsRestored = false;
        this.executorInitialized = false;
        this.auditStateLost = false;
        this.leaseLost = false;
        this.lockAcquiredAt = 0;
        this.nextMaintenanceTick = 0;
        this.nextEntryTick = 0;
        this.lastTrailObservedBar = 0;
        this.lastWarmupBar = 0;
        this.analysisRetryBar = 0;
        this.nextAnalysisRetryTime = 0;
        this.lastAnalysisErrorBar = 0;
        this.lastAnalysisError = "";
    }

    /**
     * 設定・排他・保存状態を準備する。初期化中に注文は送らない。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime = 0,
            const bool fromDirectionCorrectionEnabled = true,
            const double fromH4MaxFibonacciExpansionPercent = 161.8,
            const double fromH1MaxFibonacciExpansionPercent = 161.8) {
        if (this.initializationAttempted) {
            return false;
        }
        this.initializationAttempted = true;
        if (!this.config.initialize(fromSymbol, fromLotSize, fromMaxInitialStopLossPips,
                fromTesterTradeStartTime, fromDirectionCorrectionEnabled,
                fromH4MaxFibonacciExpansionPercent, fromH1MaxFibonacciExpansionPercent)) {
            this.logger.error("M15EaController.initialize", this.config.lastError);
            return false;
        }
        this.logger.initialize(this.config.symbolName, this.config.magicNumber, this.config.runUid);
        if (!this.strategy.initialize(this.config.symbolName, this.config.directionCorrectionEnabled,
                this.config.h4MaxFibonacciExpansionPercent, this.config.h1MaxFibonacciExpansionPercent)) {
            this.logger.error("M15EaController.initialize", this.strategy.getLastError());
            return false;
        }
        if (!this.instanceLock.acquire(this.config.lockScope)) {
            this.logger.error("M15EaController.initialize", "INSTANCE_ALREADY_LOCKED");
            this.strategy.destroy();
            return false;
        }
        this.lockAcquiredAt = TimeLocal();
        this.initializeRun();
        if (StringLen(this.run.configHash) != 64 || StringLen(this.run.analysisInputHash) != 64) {
            this.logger.error("M15EaController.initialize", "CONFIG_HASH_UNAVAILABLE");
            this.strategy.destroy();
            this.instanceLock.release();
            return false;
        }
        this.started = true;
        this.lastTrailObservedBar = iTime(this.config.symbolName, PERIOD_M15, 0);
        this.nextEntryTick = GetTickCount64() + 1000;
        if (!this.connectAndRestore()) {
            this.logger.error("M15EaController.initialize", "DB制限状態: " + this.persistence.getLastError());
        }
        if (this.leaseLost) {
            return false;
        }
        this.nextMaintenanceTick = EaClock::milliseconds() + 5000;
        this.logger.info("M15EaController.initialize", "START " + this.config.contextKey
            + " DB=" + this.config.databaseFileName + " " + this.config.createCanonicalText());
        return true;
    }

    /**
     * Lease保守とLIVE評価用に1秒Timerを一度設定する。
     */
    bool startTimer() {
        if (!this.started) {
            return false;
        }
        if (!this.timerReady) {
            this.timerReady = EventSetTimer(1);
            if (!this.timerReady) {
                this.logger.error("M15EaController.startTimer", "TIMER_START_FAILED");
            }
        }
        return this.timerReady;
    }

    /**
     * SL保護を先に実行し、Testerだけ新規判定を行う。
     */
    void onTick() {
        if (!this.started) {
            return;
        }
        this.maintainPersistence();
        datetime barTime = iTime(this.config.symbolName, PERIOD_M15, 0);
        if (this.executorInitialized) {
            this.updateManagementAuthority();
            this.executor.reconcile();
            this.executor.processPending(barTime);
            this.processTrail(barTime);
        }
        if (this.config.isTester) {
            this.evaluateEntry();
        }
    }

    /**
     * Leaseと保存を保守し、LIVEは初回1秒・以降30秒で判定する。
     */
    void onTimer() {
        if (!this.started) {
            return;
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
     * 約定・注文・SL通知を共通実行部へ渡す。
     */
    void onTradeTransaction(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
        if (this.started && this.executorInitialized) {
            this.executor.onTradeTransaction(fromTransaction, fromRequest, fromResult);
        }
    }

    /**
     * 最後の保存・無発注照合を行い、建玉とbroker SLを残して終了する。
     */
    void shutdown(const int fromReason) {
        this.timerReady = false;
        if (this.started) {
            this.flushDecisions();
            bool tradeQueueSaved = true;
            if (this.executorInitialized) {
                tradeQueueSaved = this.executor.flushPendingEvents();
                this.executor.reconcile();
                tradeQueueSaved = this.executor.flushPendingEvents() && tradeQueueSaved;
                this.executor.setManagementAuthority(false, 0);
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
            } else if (this.executorInitialized && this.executor.hasPendingDealAudit()) {
                status = "FAILED";
                errorText = "DEAL_AUDIT_PENDING: 同contextで約定履歴の再照合が必要です";
            }
            if (errorText != "") {
                this.logger.error("M15EaController.shutdown", errorText);
            }
            if (this.run.id > 0 && !this.persistence.finishRun(this.run.id, status, errorText)) {
                this.logger.error("M15EaController.shutdown", "RUN_END_UNSAVED " + this.persistence.getLastError());
            }
            this.logger.info("M15EaController.shutdown", "STOP reason=" + IntegerToString(fromReason));
        }
        this.started = false;
        this.databaseReady = false;
        this.persistence.close();
        this.strategy.destroy();
        this.instanceLock.release();
    }

private:
    /** 再初期化による保存先の取り違えを防ぐ。 */
    bool initializationAttempted;
    /** 設定と排他取得が完了した場合true。 */
    bool started;
    /** Timer設定成功状態。 */
    bool timerReady;
    /** DBとRunが使用可能な場合true。 */
    bool databaseReady;
    /** 起動時の回数と判定済みバーの復元完了状態。 */
    bool countsRestored;
    /** 共通実行部の接続完了状態。 */
    bool executorInitialized;
    /** 消費回数または監査情報の欠落がある場合true。 */
    bool auditStateLost;
    /** 一度失効した管理権は同Run内で復活させない。 */
    bool leaseLost;
    /** 排他取得時刻。初回DB復旧の期限に使う。 */
    datetime lockAcquiredAt;
    /** 次回DB再接続・保存の試行時刻。 */
    ulong nextMaintenanceTick;
    /** LIVEの次回Entry評価時刻。 */
    ulong nextEntryTick;
    /** 最後に観測したトレイル用M15バー。 */
    datetime lastTrailObservedBar;
    /** 売買開始前に履歴を確認したM15バー。 */
    datetime lastWarmupBar;
    /** Testerで分析を再試行するバー。 */
    datetime analysisRetryBar;
    /** Tester分析の最短再試行時刻。 */
    datetime nextAnalysisRetryTime;
    /** 重複分析エラーログを抑制するバー。 */
    datetime lastAnalysisErrorBar;
    /** 最後の分析エラー。 */
    string lastAnalysisError;
    /** M15専用の設定。 */
    M15EaConfig config;
    /** M15専用運用ログ。 */
    M15EaOperationLogger logger;
    /** M15同一scopeの排他ハンドル。 */
    M15EaInstanceLock instanceLock;
    /** M15専用DBと共通TradeStoreの接続。 */
    M15EaPersistenceService persistence;
    /** 今回のLease所有Run。 */
    M15EaRunEntity run;
    /** M15の分析・既存戦略判定。 */
    M15EaStrategy strategy;
    /** 時間足に依存しない発注・保護・復元。 */
    EaTradeExecutor executor;
    /** M15固有のトレイル・理由・識別子。 */
    M15EaTradePolicy tradePolicy;
    /** 回数とEntryバーの共通管理。 */
    EaEntryState entryState;
    /** 確定したSKIPの保存待ち。遅延発注に使わない。 */
    M15EaDecisionEntity decisionQueue[];

    /**
     * Runへ実行設定と分析設定の正本を保存する。
     */
    void initializeRun() {
        this.run.reset();
        this.run.runUid = this.config.runUid;
        this.run.sourceMode = this.config.sourceMode;
        this.run.contextKey = this.config.contextKey;
        this.run.accountServer = this.config.accountServer;
        this.run.accountLogin = this.config.accountLogin;
        this.run.symbolName = this.config.symbolName;
        this.run.magicNumber = EaTextUtil::ticket(this.config.magicNumber);
        this.run.programVersion = M15EaConfig::getProgramVersion();
        this.run.strategyVersion = M15EaConfig::getStrategyVersion();
        this.run.analysisVersion = ZigZagElliotAnalysisProfile::getAnalysisVersion();
        this.run.analysisInputText = ZigZagElliotAnalysisProfile::createCanonicalText();
        this.run.analysisInputHash = ZigZagElliotAnalysisProfile::createHash();
        this.run.configText = this.config.createCanonicalText();
        this.run.configHash = EaTextUtil::hash(this.run.configText);
        this.run.startedAt = TimeLocal();
    }

    /**
     * 初回だけ回数・判定バー・取引を復元し、再接続でも再送しない。
     */
    bool connectAndRestore() {
        if (this.leaseLost) {
            return false;
        }
        if (this.run.id == 0 && TimeLocal() >= this.lockAcquiredAt + 60) {
            this.leaseLost = true;
            this.logger.error("M15EaController.connectAndRestore", "INITIAL_DB_RECOVERY_DEADLINE_EXPIRED");
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
            datetime currentBar = iTime(this.config.symbolName, PERIOD_M15, 0);
            if (currentBar <= 0) {
                return false;
            }
            M15EaDecisionEntity savedDecision;
            bool found = false;
            if (!this.persistence.loadDecision(this.config.contextKey, currentBar, savedDecision, found)
                    || currentBar != iTime(this.config.symbolName, PERIOD_M15, 0)) {
                return false;
            }
            if (found) {
                this.entryState.finalize(currentBar);
            }
            this.countsRestored = true;
        }
        if (!this.executorInitialized) {
            EaTradeProfile profile;
            M15EaTradePolicy::profile(profile);
            if (!this.executor.initialize(this.config.symbolName, this.config.magicNumber,
                    this.config.pipSize, this.config.tickSize, this.run.id, this.run.runUid,
                    this.config.contextKey, GetPointer(this.persistence), profile, GetPointer(this.tradePolicy))) {
                return false;
            }
            this.executor.setRequireCurrentQuote(true);
            this.executorInitialized = true;
        }
        datetime blockedBar = 0;
        if (!this.persistence.loadCrossBlockedBar(this.config.contextKey, blockedBar)
                || !this.executor.restoreFromDatabase()) {
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
     * 10秒でLease更新、5秒でDB再接続・未保存監査の再試行を行う。
     */
    void maintainPersistence() {
        datetime now = TimeLocal();
        if (this.run.id > 0 && this.run.leaseExpiresAt <= now && !this.leaseLost) {
            this.leaseLost = true;
            this.logger.error("M15EaController.maintainPersistence", "LEASE_EXPIRED");
        }
        if (this.databaseReady && !this.leaseLost && now >= this.run.heartbeatAt + 10) {
            if (!this.persistence.heartbeat(this.run, now)) {
                if (!this.persistence.hasLease(this.run.id, now)
                        && this.persistence.getLastError() == "LEASE_NOT_OWNED") {
                    this.leaseLost = true;
                }
                this.databaseReady = false;
                this.logger.error("M15EaController.maintainPersistence", "HEARTBEAT_FAILED");
            }
        }
        this.updateManagementAuthority();
        if (EaClock::milliseconds() < this.nextMaintenanceTick) {
            return;
        }
        this.nextMaintenanceTick = EaClock::milliseconds() + 5000;
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
     * OS排他と有効なLeaseの両方を共通処理へ渡す。
     */
    void updateManagementAuthority() {
        if (this.executorInitialized) {
            datetime expires = (datetime)this.run.leaseExpiresAt;
            if (this.leaseLost) {
                expires = 0;
            }
            this.executor.setManagementAuthority(this.instanceLock.isHeld(), expires);
        }
    }

    /**
     * 新しいM15バーでトレイルだけを評価し、シグナル回数は消費しない。
     */
    void processTrail(const datetime fromBarTime) {
        if (fromBarTime <= 0 || fromBarTime == this.lastTrailObservedBar) {
            return;
        }
        this.lastTrailObservedBar = fromBarTime;
        if (!this.executor.isTrailEligible(fromBarTime)) {
            return;
        }
        M15EaStrategySnapshot snapshot;
        if (this.strategy.analyze(snapshot)) {
            if (snapshot.barTime != fromBarTime
                    || iTime(this.config.symbolName, PERIOD_M15, 0) != fromBarTime) {
                return;
            }
            this.executor.evaluateTrail(fromBarTime, this.strategy.getWave());
        } else {
            this.executor.evaluateTrail(fromBarTime, NULL, this.strategy.getLastError());
        }
        this.executor.processPending(fromBarTime);
    }

    /**
     * 分析成功バーの初回だけJudgeを確定し、原子的保存成功後に送信する。
     */
    void evaluateEntry() {
        if (this.config.isBeforeTesterTradeStart(TimeCurrent())) {
            this.processTesterWarmup();
            return;
        }
        if (!this.timerReady || !this.countsRestored || !this.executorInitialized || this.run.id <= 0) {
            return;
        }
        datetime barTime = iTime(this.config.symbolName, PERIOD_M15, 0);
        if (barTime <= 0) {
            return;
        }
        datetime expiredBar = this.entryState.observe(barTime);
        if (expiredBar > 0) {
            M15EaDecisionEntity unavailable;
            this.initializeDecision(unavailable, expiredBar);
            unavailable.reasonCode = "ANALYSIS_UNAVAILABLE";
            this.enqueueDecision(unavailable, "");
            this.flushDecisions();
        }
        if (this.entryState.isFinalized(barTime)
                || (this.config.isTester && this.analysisRetryBar == barTime
                    && TimeCurrent() < this.nextAnalysisRetryTime)) {
            return;
        }
        this.analysisRetryBar = 0;
        this.nextAnalysisRetryTime = 0;
        M15EaStrategySnapshot snapshot;
        if (!this.strategy.analyze(snapshot)) {
            if (this.config.isTester) {
                this.analysisRetryBar = barTime;
                this.nextAnalysisRetryTime = TimeCurrent() + 1;
            }
            this.logAnalysisWait(barTime);
            return;
        }
        if (snapshot.barTime != barTime || !this.executor.hasCurrentEntryQuote(barTime)) {
            return;
        }
        this.lastAnalysisError = "";
        int previousCount = this.entryState.getCount(snapshot.signalReferenceTime, snapshot.signalSide);
        if (!this.strategy.evaluate(previousCount, snapshot)) {
            this.logAnalysisWait(barTime);
            return;
        }
        // 方向補正の再分析中にバーや気配が変わった場合も、保存回数を消費しない。
        if (snapshot.barTime != barTime || !this.executor.hasCurrentEntryQuote(barTime)) {
            return;
        }
        M15EaDecisionEntity decision;
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
        if (!M15EaDecisionBuilder::seal(decision, this.config.digits, snapshot.analysisSnapshotText)) {
            this.auditStateLost = true;
            decision.reasonCode = "SNAPSHOT_HASH_UNAVAILABLE";
            this.enqueueDecision(decision, snapshot.analysisSnapshotText);
            return;
        }
        if (decision.decision != "SKIP") {
            EaEntryRequest request;
            request.side = decision.decision;
            request.requestedVolume = decision.requestedVolume;
            request.initialStopLoss = decision.initialStopLoss;
            request.barTime = decision.barTime;
            request.maxInitialRiskPips = decision.maxInitialRiskPips;
            EaTradeState trade;
            EaTradeEvent event;
            this.executor.prepareEntry(request, trade, event);
            if (this.persistence.saveEntry(this.run.id, decision, trade, event)) {
                this.executor.sendEntry(trade, event);
                this.logDecision(decision);
                return;
            }
            decision.reasonCode = "DB_UNAVAILABLE";
            this.databaseReady = false;
        }
        this.enqueueDecision(decision, snapshot.analysisSnapshotText);
        this.flushDecisions();
    }

    /**
     * Tester開始前はM15バーごとの履歴準備だけを行う。
     */
    void processTesterWarmup() {
        datetime barTime = iTime(this.config.symbolName, PERIOD_M15, 0);
        if (barTime <= 0 || barTime == this.lastWarmupBar) {
            return;
        }
        this.lastWarmupBar = barTime;
        if (!this.strategy.prepareHistory(this.config.testerTradeStartTime)) {
            this.logAnalysisWait(barTime);
        }
    }

    /**
     * 同じ分析エラーは同一バーで重複出力しない。
     */
    void logAnalysisWait(const datetime fromBar) {
        string reason = this.strategy.getLastError();
        if (reason == this.lastAnalysisError && fromBar == this.lastAnalysisErrorBar) {
            return;
        }
        this.lastAnalysisError = reason;
        this.lastAnalysisErrorBar = fromBar;
        this.logger.info("M15EaController.evaluateEntry", "M15=" + IntegerToString(fromBar)
            + " " + reason + " " + this.strategy.getHistoryStatusText());
    }

    /**
     * 分析不能バーにも共通の保存項目を設定する。
     */
    void initializeDecision(M15EaDecisionEntity &fromDecision, const datetime fromBar) {
        fromDecision.reset();
        fromDecision.runId = this.run.id;
        fromDecision.contextKey = this.config.contextKey;
        fromDecision.barTime = fromBar;
        fromDecision.evaluatedServerTime = TimeCurrent();
        fromDecision.createdAt = TimeLocal();
        fromDecision.maxInitialRiskPips = this.config.maxInitialStopLossPips;
    }

    /**
     * 元のシグナルキーと既存戦略の確定結果を保存値へ移す。
     */
    void buildDecision(M15EaStrategySnapshot &fromSnapshot, M15EaDecisionEntity &fromDecision) {
        this.initializeDecision(fromDecision, fromSnapshot.barTime);
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
        if (fromDecision.signalReferenceTime > 0 && fromDecision.signalSide != "") {
            fromDecision.marketSignalKey = this.config.accountServer + "|" + this.config.symbolName
                + "|" + IntegerToString(PERIOD_M15) + "|" + IntegerToString(fromDecision.barTime)
                + "|" + IntegerToString(fromDecision.signalReferenceTime) + "|MTF_3in3|" + fromDecision.signalSide;
        }
    }

    /**
     * 戦略成立後、管理権・保有・数量と採用分析のM15初期SLを検証する。
     */
    void applyEntrySafety(M15EaStrategySnapshot &fromSnapshot, M15EaDecisionEntity &fromDecision) {
        if (this.auditStateLost) {
            fromDecision.reasonCode = "AUDIT_STATE_LOST";
            return;
        }
        if (this.leaseLost || !this.databaseReady || ArraySize(this.decisionQueue) > 0
                || this.executor.hasUnsavedEvents()) {
            fromDecision.reasonCode = "DB_UNAVAILABLE";
            return;
        }
        if (!this.executor.hasCurrentEntryQuote(fromSnapshot.barTime)) {
            fromDecision.reasonCode = "ANALYSIS_BAR_OR_QUOTE_CHANGED";
            return;
        }
        string reason = "";
        if (!this.executor.canEnter(fromSnapshot.barTime, reason)) {
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
        EaInitialStopLossResult result;
        EaInitialStopLossDecision initialStopLoss;
        initialStopLoss.evaluate(fromSnapshot.isBuy, fromSnapshot.initialStopLossPivotPrice,
            fromSnapshot.initialStopLossPivotIsHigh, marketTick.bid, marketTick.ask,
            this.config.pipSize, this.config.tickSize, this.config.pointSize,
            SymbolInfoInteger(this.config.symbolName, SYMBOL_TRADE_STOPS_LEVEL),
            this.config.maxInitialStopLossPips, 10.0, result);
        fromDecision.initialStopLoss = result.stopLoss;
        fromDecision.initialRiskPips = result.riskPips;
        if (!result.isAccepted) {
            fromDecision.reasonCode = result.reasonCode;
            return;
        }
        fromDecision.decision = fromSnapshot.signalSide;
        fromDecision.reasonCode = "ENTRY_ACCEPTED";
    }

    /**
     * H1と同じbroker数量制約で固定ロットを正規化する。
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
     * 初回の確定値を最大256件保持する。再保存から発注へ戻さない。
     */
    void enqueueDecision(M15EaDecisionEntity &fromDecision, const string fromDiagnostics) {
        fromDecision.decision = "SKIP";
        if (!M15EaDecisionBuilder::seal(fromDecision, this.config.digits, fromDiagnostics)) {
            this.auditStateLost = true;
        }
        int queueSize = ArraySize(this.decisionQueue);
        if (queueSize >= 256 || ArrayResize(this.decisionQueue, queueSize + 1) != queueSize + 1) {
            this.auditStateLost = true;
            this.logger.error("M15EaController.enqueueDecision", "AUDIT_STATE_LOST QUEUE_OVERFLOW");
            return;
        }
        this.decisionQueue[queueSize] = fromDecision;
        this.logDecision(fromDecision);
    }

    /**
     * Judgeを再評価せず、確定SKIPだけをFIFOで保存する。
     */
    void flushDecisions() {
        if (!this.databaseReady || this.leaseLost || this.run.id <= 0) {
            return;
        }
        while (ArraySize(this.decisionQueue) > 0) {
            if (!this.persistence.saveDecision(this.run.id, this.decisionQueue[0])) {
                this.databaseReady = false;
                this.logger.error("M15EaController.flushDecisions", this.persistence.getLastError());
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
     * DB停止時にも確定値と監査hashを記録する。
     */
    void logDecision(M15EaDecisionEntity &fromDecision) {
        this.logger.info("M15EaController.evaluateEntry", "M15=" + IntegerToString(fromDecision.barTime)
            + " ref=" + IntegerToString(fromDecision.signalReferenceTime)
            + " side=" + fromDecision.signalSide + " count=" + IntegerToString(fromDecision.signalCount)
            + " decision=" + fromDecision.decision + " reason=" + fromDecision.reasonCode
            + " hash=" + fromDecision.snapshotHash);
    }
};

#endif
