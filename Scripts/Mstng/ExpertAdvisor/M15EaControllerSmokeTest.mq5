#property strict
#property version "1.00"

#include <MstngEaCommon\Runtime\EaClock.mqh>
#include <MstngEaCommon\Runtime\EaEntryState.mqh>
#include <MstngEaCommon\Runtime\EaInitialStopLossDecision.mqh>
#include <MstngEaCommon\Runtime\EaTradeExecutor.mqh>
#include <MstngM15Ea\Config\M15EaConfig.mqh>
#include <MstngM15Ea\Persistence\M15EaPersistenceService.mqh>
#include <MstngM15Ea\Runtime\M15EaDecisionBuilder.mqh>
#include <MstngM15Ea\Runtime\M15EaInstanceLock.mqh>
#include <MstngM15Ea\Runtime\M15EaOperationLogger.mqh>
#include <MstngM15Ea\Strategy\M15EaStrategy.mqh>
#include <MstngM15Ea\Trade\M15EaTradePolicy.mqh>

/** 成功件数。 */
int passedCount = 0;
/** 失敗件数。 */
int failedCount = 0;
/** fixtureの現在時刻。 */
datetime fixtureNow;
/** fixtureのM15バー。 */
datetime fixtureBar;
/** fixtureの保守用単調時刻。 */
ulong fixtureMilliseconds;
/** Strategyが返す制御済み結果。 */
M15EaStrategySnapshot fixtureSnapshot;
/** Strategyへ渡された復元済み回数。 */
int observedPreviousCounts[];
/** 保存した判定。 */
M15EaDecisionEntity savedDecisions[];
/** 発注準備へ渡された実Controllerの要求。 */
EaEntryRequest preparedRequest;
/** 起動時に復元する回数。 */
int restoredCount;
/** 現在バーの判定をDBで復元する場合true。 */
bool restoreCurrentBar;
/** 原子的Entry保存を失敗させる場合true。 */
bool rejectEntrySave;
/** 確定SKIP保存を失敗させる場合true。 */
bool rejectDecisionSave;
/** Strategy評価中に気配を失効させる場合true。 */
bool expireQuoteDuringEvaluate;
/** 現在の気配を無効として返す場合true。 */
bool quoteUnavailable;
/** 分析回数。 */
int analyzeCount;
/** 売買開始前の履歴準備回数。 */
int historyCount;
/** 原子的Entry保存試行回数。 */
int entrySaveCount;
/** 確定SKIP保存試行回数。 */
int decisionSaveCount;
/** Executor送信境界の呼出回数。実注文は行わない。 */
int sendCount;
/** 永続化再接続回数。 */
int openCount;
/** 全境界の順序番号。 */
int operationSequence;
/** 最後にEntryを保存完了した順序。 */
int committedSequence;
/** 最後に送信境界へ入った順序。 */
int sentSequence;
/** 送信境界が未保存データを受け取った場合true。 */
bool sentBeforeCommit;

/**
 * ケースの結果を記録する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        passedCount++;
        Print("INFO M15EaControllerSmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR M15EaControllerSmokeTest FAIL ", fromName);
    }
}

/**
 * brokerを参照せず、Controllerだけに固定価格を返す。
 */
bool fixtureSymbolInfoTick(const string fromSymbol, MqlTick &fromTick) {
    ZeroMemory(fromTick);
    fromTick.bid = 1.1000;
    fromTick.ask = 1.1002;
    fromTick.time = fixtureNow;
    fromTick.time_msc = (long)fixtureNow * 1000;
    return true;
}

/**
 * 数量の最小・最大・刻みを固定する。
 */
double fixtureSymbolInfoDouble(const string fromSymbol, const ENUM_SYMBOL_INFO_DOUBLE fromProperty) {
    if (fromProperty == SYMBOL_VOLUME_MAX) {
        return 10.0;
    }
    return 0.01;
}

/**
 * SL最小距離を10pointに固定する。
 */
long fixtureSymbolInfoInteger(const string fromSymbol, const ENUM_SYMBOL_INFO_INTEGER fromProperty) {
    return 10;
}

/**
 * 履歴を参照せずfixtureのM15バーだけを返す。
 */
datetime fixtureTime(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame, const int fromShift) {
    if (fromTimeFrame != PERIOD_M15 || fromShift != 0) {
        return 0;
    }
    return fixtureBar;
}

/**
 * Timerを登録せず、Controller内の準備完了だけを許可する。
 */
bool fixtureSetTimer(const int fromSeconds) { return fromSeconds == 1; }

/**
 * Controller用時刻を固定する。
 */
datetime fixtureCurrentTime() { return fixtureNow; }

/**
 * Controller用単調時刻を固定する。
 */
ulong fixtureTickCount() { return fixtureMilliseconds; }

/**
 * 共通時計の呼出も同じfixture時刻へ揃える。
 */
class ControllerSmokeClock {
public:
    /**
     * ケースで指定した単調時刻を返す。
     */
    static ulong milliseconds() { return fixtureMilliseconds; }
};

/**
 * 実Configの値型と純粋メソッドを使い、口座・シンボル参照を置換する。
 */
class ControllerSmokeConfig : public M15EaConfig {
public:
    /**
     * ファイル名も実在しない識別子にし、外部状態を初期化しない。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime,
            const bool fromDirectionCorrectionEnabled, const double fromH4Limit, const double fromH1Limit) {
        this.symbolName = fromSymbol;
        this.accountServer = "CONTROLLER_SMOKE_ONLY";
        this.accountLogin = 1;
        this.magicNumber = 130015;
        this.lotSize = fromLotSize;
        this.maxInitialStopLossPips = fromMaxInitialStopLossPips;
        this.pointSize = 0.00001;
        this.tickSize = 0.00001;
        this.pipSize = 0.0001;
        this.digits = 5;
        this.isTester = true;
        this.sourceMode = "TESTER";
        this.testerTradeStartTime = fromTesterTradeStartTime;
        this.runUid = EaTextUtil::hash("M15_CONTROLLER_SMOKE");
        this.contextKey = "M15_CONTROLLER_SMOKE|MEMORY_ONLY";
        this.lockScope = this.contextKey;
        this.databaseFileName = "MEMORY_ONLY_NO_DATABASE";
        this.directionCorrectionEnabled = fromDirectionCorrectionEnabled;
        this.h4MaxFibonacciExpansionPercent = fromH4Limit;
        this.h1MaxFibonacciExpansionPercent = fromH1Limit;
        return true;
    }
};

/**
 * 実Lockのファイル操作を行わない所有権fixture。
 */
class ControllerSmokeLock {
public:
    /** fixtureの所有状態。 */
    bool held;
    /**
     * 未取得状態を作る。
     */
    ControllerSmokeLock() { this.held = false; }
    /**
     * メモリ上だけで取得する。
     */
    bool acquire(const string fromScope) { this.held = true; return true; }
    /**
     * メモリ上の状態を返す。
     */
    bool isHeld() const { return this.held; }
    /**
     * メモリ上の所有状態を戻す。
     */
    void release() { this.held = false; }
};

/**
 * ファイル出力を行わない運用ログfixture。
 */
class ControllerSmokeLogger {
public:
    /**
     * 実ファイルの準備を行わない。
     */
    void initialize(const string fromSymbol, const ulong fromMagic, const string fromUid) {}
    /**
     * 成否は検証ケースが直接記録する。
     */
    void info(const string fromMethod, const string fromMessage) {}
    /**
     * 想定された失敗経路のログを実ファイルへ出さない。
     */
    void error(const string fromMethod, const string fromMessage) {}
};

/**
 * Strategyの境界だけを置換し、Controllerから渡された回数を観測する。
 */
class ControllerSmokeStrategy {
public:
    /**
     * 指標ハンドルを作成せず初期化を許可する。
     */
    bool initialize(const string fromSymbol, const bool fromCorrection,
            const double fromH4Limit, const double fromH1Limit) { return true; }
    /**
     * 外部リソースを所有しない。
     */
    void destroy() {}
    /**
     * 売買開始前の履歴準備だけを数える。
     */
    bool prepareHistory(const datetime fromEnd) { historyCount++; return true; }
    /**
     * ケースの制御済み分析を返す。
     */
    bool analyze(M15EaStrategySnapshot &fromSnapshot) {
        analyzeCount++;
        fromSnapshot = fixtureSnapshot;
        fromSnapshot.barTime = fixtureBar;
        fromSnapshot.evaluatedTime = fixtureNow;
        return true;
    }
    /**
     * 回数アルゴリズムは複製せず、入力を記録してケースの確定結果を返す。
     */
    bool evaluate(const int fromPreviousCount, M15EaStrategySnapshot &fromSnapshot) {
        int size = ArraySize(observedPreviousCounts);
        if (ArrayResize(observedPreviousCounts, size + 1) != size + 1) {
            return false;
        }
        observedPreviousCounts[size] = fromPreviousCount;
        if (expireQuoteDuringEvaluate) {
            quoteUnavailable = true;
        }
        return true;
    }
    /**
     * トレイルは本テスト対象外なのでWaveを生成しない。
     */
    Wave *getWave() { return NULL; }
    /**
     * 外部分析エラーは使用しない。
     */
    string getLastError() const { return "FIXTURE"; }
    /**
     * 外部履歴状態は使用しない。
     */
    string getHistoryStatusText() const { return "FIXTURE"; }
};

/**
 * DBを開かず、保存境界と復元データを制御する。
 */
class ControllerSmokePersistence {
public:
    /**
     * 接続試行だけを数える。
     */
    bool open(const string fromFile, const bool fromInitialize) { openCount++; return true; }
    /**
     * DBリソースは所有しない。
     */
    void close() {}
    /**
     * 固定Runと有効Leaseを返す。
     */
    bool acquireRun(M15EaRunEntity &fromRun) {
        fromRun.id = 1;
        fromRun.heartbeatAt = fixtureNow;
        fromRun.leaseExpiresAt = fixtureNow + 60;
        return true;
    }
    /**
     * fixture中は有効Leaseを返す。
     */
    bool hasLease(const long fromRunId, const datetime fromNow) { return true; }
    /**
     * 再接続テスト用の固定エラーを返す。
     */
    string getLastError() const { return "FIXTURE_SAVE_FAILED"; }
    /**
     * 指定された1シグナルの復元値だけを返す。
     */
    bool loadSignalCounts(const string fromContext, long &fromTimes[], string &fromSides[], int &fromCounts[]) {
        int size = 0;
        if (restoredCount > 0) {
            size = 1;
        }
        if (ArrayResize(fromTimes, size) != size || ArrayResize(fromSides, size) != size
                || ArrayResize(fromCounts, size) != size) {
            return false;
        }
        if (size == 1) {
            fromTimes[0] = fixtureSnapshot.signalReferenceTime;
            fromSides[0] = fixtureSnapshot.signalSide;
            fromCounts[0] = restoredCount;
        }
        return true;
    }
    /**
     * 監査欠落なしを返す。
     */
    bool hasAuditGap(const string fromContext, bool &fromFound) { fromFound = false; return true; }
    /**
     * 起動時の現在バー確定状態を制御する。
     */
    bool loadDecision(const string fromContext, const long fromBar,
            M15EaDecisionEntity &fromDecision, bool &fromFound) {
        fromDecision.reset();
        fromDecision.barTime = fromBar;
        fromFound = restoreCurrentBar;
        return true;
    }
    /**
     * 初期状態に跨ぎ禁止バーを設けない。
     */
    bool loadCrossBlockedBar(const string fromContext, datetime &fromBar) { fromBar = 0; return true; }
    /**
     * ケース内時刻の進行に合わせてLeaseを更新する。
     */
    bool heartbeat(M15EaRunEntity &fromRun, const datetime fromNow) {
        fromRun.heartbeatAt = fromNow;
        fromRun.leaseExpiresAt = fromNow + 60;
        return true;
    }
    /**
     * 外部DBへ終了状態を書かない。
     */
    bool finishRun(const long fromId, const string fromStatus, const string fromError) { return true; }
    /**
     * 原子的保存成功だけに採番し、送信より先に完了したことを記録する。
     */
    bool saveEntry(const long fromRunId, M15EaDecisionEntity &fromDecision,
            EaTradeState &fromTrade, EaTradeEvent &fromEvent) {
        entrySaveCount++;
        operationSequence++;
        if (rejectEntrySave) {
            return false;
        }
        fromDecision.id = entrySaveCount;
        fromTrade.id = entrySaveCount;
        fromEvent.id = entrySaveCount;
        fromEvent.tradeId = fromTrade.id;
        committedSequence = operationSequence;
        return this.recordDecision(fromDecision);
    }
    /**
     * 再保存された確定SKIPを保持する。
     */
    bool saveDecision(const long fromRunId, M15EaDecisionEntity &fromDecision) {
        decisionSaveCount++;
        if (rejectDecisionSave) {
            return false;
        }
        return this.recordDecision(fromDecision);
    }
private:
    /**
     * 最終保存値をコピーして検証へ渡す。
     */
    bool recordDecision(const M15EaDecisionEntity &fromDecision) {
        int size = ArraySize(savedDecisions);
        if (ArrayResize(savedDecisions, size + 1) != size + 1) {
            return false;
        }
        savedDecisions[size] = fromDecision;
        return true;
    }
};

/**
 * 発注境界を観測するだけのExecutor。broker APIを呼び出さない。
 */
class ControllerSmokeExecutor {
public:
    /**
     * 接続を受け取るだけで保存先やpolicyを実行しない。
     */
    bool initialize(const string fromSymbol, const ulong fromMagic, const double fromPip,
            const double fromTick, const long fromRunId, const string fromRunUid, const string fromContext,
            ControllerSmokePersistence *fromStore, const EaTradeProfile &fromProfile,
            M15EaTradePolicy *fromPolicy) { return true; }
    /**
     * 気配モードを実システムへ反映しない。
     */
    void setRequireCurrentQuote(const bool fromRequire) {}
    /**
     * DB参照は別smokeで検証し、ここでは成功を返す。
     */
    bool restoreFromDatabase() { return true; }
    /**
     * fixtureの禁止バーを受け取る。
     */
    void setBlockedEntryBar(const datetime fromBar) {}
    /**
     * fixtureの管理権を受け取る。
     */
    void setManagementAuthority(const bool fromHeld, const datetime fromExpires) {}
    /**
     * 取引保存待ちを持たない。
     */
    bool flushPendingEvents() { return true; }
    /**
     * broker照合を行わない。
     */
    void reconcile() {}
    /**
     * brokerへの保護操作を行わない。
     */
    void processPending(const datetime fromBar) {}
    /**
     * Entryテスト中はトレイル対象を持たない。
     */
    bool isTrailEligible(const datetime fromBar) { return false; }
    /**
     * トレイル側へ実処理を漏らさない。
     */
    void evaluateTrail(const datetime fromBar, Wave *fromWave, const string fromReason = "") {}
    /**
     * 外部取引通知を処理しない。
     */
    void onTradeTransaction(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {}
    /**
     * 気配はケース中常に対象M15バーと一致する。
     */
    bool hasCurrentEntryQuote(const datetime fromBar) { return !quoteUnavailable && fromBar == fixtureBar; }
    /**
     * 共通Executorの発注制限は別smokeで検証する。
     */
    bool canEnter(const datetime fromBar, string &fromReason) { return true; }
    /**
     * ケース中は取引Eventの未保存状態を作らない。
     */
    bool hasUnsavedEvents() const { return false; }
    /**
     * ケース中は約定監査待ちを作らない。
     */
    bool hasPendingDealAudit() const { return false; }
    /**
     * 実Controllerが作った要求を、未採番の取引へ移す。
     */
    void prepareEntry(const EaEntryRequest &fromRequest, EaTradeState &fromTrade, EaTradeEvent &fromEvent) {
        preparedRequest = fromRequest;
        fromTrade.reset();
        fromTrade.status = "OPEN_PENDING";
        fromTrade.side = fromRequest.side;
        fromTrade.requestedStopLoss = fromRequest.initialStopLoss;
        fromEvent.reset();
        fromEvent.eventType = "ENTRY_REQUEST";
    }
    /**
     * 送信境界の順序と採番を検証し、実注文を一切送らない。
     */
    void sendEntry(EaTradeState &fromTrade, EaTradeEvent &fromEvent) {
        sendCount++;
        sentSequence = ++operationSequence;
        if (committedSequence <= 0 || committedSequence >= sentSequence
                || fromTrade.id <= 0 || fromEvent.id <= 0 || fromEvent.tradeId != fromTrade.id) {
            sentBeforeCommit = true;
        }
    }
};

// 依存型は上で事前loadし、実Controller本体の境界だけをfixtureへ差し替える。
#define EaClock ControllerSmokeClock
#define EaTradeExecutor ControllerSmokeExecutor
#define M15EaConfig ControllerSmokeConfig
#define M15EaInstanceLock ControllerSmokeLock
#define M15EaOperationLogger ControllerSmokeLogger
#define M15EaPersistenceService ControllerSmokePersistence
#define M15EaStrategy ControllerSmokeStrategy
#define EventSetTimer fixtureSetTimer
#define GetTickCount64 fixtureTickCount
#define iTime fixtureTime
#define SymbolInfoDouble fixtureSymbolInfoDouble
#define SymbolInfoInteger fixtureSymbolInfoInteger
#define SymbolInfoTick fixtureSymbolInfoTick
#define TimeCurrent fixtureCurrentTime
#define TimeLocal fixtureCurrentTime
#include <MstngM15Ea\M15EaController.mqh>
#undef EaClock
#undef EaTradeExecutor
#undef M15EaConfig
#undef M15EaInstanceLock
#undef M15EaOperationLogger
#undef M15EaPersistenceService
#undef M15EaStrategy
#undef EventSetTimer
#undef GetTickCount64
#undef iTime
#undef SymbolInfoDouble
#undef SymbolInfoInteger
#undef SymbolInfoTick
#undef TimeCurrent
#undef TimeLocal

/**
 * ケース間で外部状態を共有せず、元キーと補正後SLを異なる値にする。
 */
void resetFixture() {
    fixtureBar = D'2026.10.05 12:00:00';
    fixtureNow = fixtureBar + 10;
    fixtureMilliseconds = 10000;
    fixtureSnapshot.reset();
    fixtureSnapshot.isBuy = true;
    fixtureSnapshot.signalSide = "BUY";
    fixtureSnapshot.signalReferenceTime = fixtureBar - 1800;
    fixtureSnapshot.signalReferencePrice = 1.08;
    fixtureSnapshot.signalReferenceIsHigh = true;
    fixtureSnapshot.initialStopLossPivotTime = fixtureBar - 900;
    fixtureSnapshot.initialStopLossPivotPrice = 1.095;
    fixtureSnapshot.initialStopLossPivotIsHigh = false;
    fixtureSnapshot.isJudge = true;
    fixtureSnapshot.signalCount = 1;
    fixtureSnapshot.isEntryEvaluated = true;
    fixtureSnapshot.isStrategyEntry = true;
    fixtureSnapshot.isSignalConsumed = true;
    fixtureSnapshot.reasonCode = "STRATEGY_ENTRY";
    fixtureSnapshot.analysisSnapshotText = "M15_EA_ANALYSIS_V1|SOURCE_PIVOT=1.08|SELECTED_PIVOT=1.095";
    fixtureSnapshot.correctionTimeFrame = PERIOD_H1;
    ArrayResize(observedPreviousCounts, 0);
    ArrayResize(savedDecisions, 0);
    restoredCount = 0;
    restoreCurrentBar = false;
    rejectEntrySave = false;
    rejectDecisionSave = false;
    expireQuoteDuringEvaluate = false;
    quoteUnavailable = false;
    analyzeCount = 0;
    historyCount = 0;
    entrySaveCount = 0;
    decisionSaveCount = 0;
    sendCount = 0;
    openCount = 0;
    operationSequence = 0;
    committedSequence = 0;
    sentSequence = 0;
    sentBeforeCommit = false;
}

/**
 * 次のM15バーを観測するが、Lease判定用の経過時刻は短いままにする。
 */
void nextBar() {
    fixtureBar += 900;
    fixtureMilliseconds += 1000;
}

/**
 * 保存→送信順、補正後pivotの実SL計算、同バーと回数消費を確認する。
 */
void verifyEntryConnection() {
    resetFixture();
    M15EaController controller;
    verify(controller.initialize("EURUSD", 0.01, 100.0) && controller.startTimer(), "entry fixture initialized");
    controller.onTick();
    verify(entrySaveCount == 1 && sendCount == 1 && !sentBeforeCommit
        && committedSequence > 0 && sentSequence > committedSequence, "atomic save precedes send");
    verify(MathAbs(preparedRequest.initialStopLoss - 1.094) < 0.00000001
        && preparedRequest.side == "BUY" && preparedRequest.barTime == fixtureBar,
        "selected correction pivot and direction feed real initial SL calculation");
    verify(ArraySize(savedDecisions) == 1 && savedDecisions[0].signalReferenceTime == fixtureSnapshot.signalReferenceTime
        && savedDecisions[0].signalCount == 1 && savedDecisions[0].isSignalConsumed,
        "original signal key consumed once despite selected pivot difference");
    controller.onTick();
    verify(analyzeCount == 1 && ArraySize(observedPreviousCounts) == 1 && sendCount == 1,
        "same finalized bar does not evaluate or send twice");
    nextBar();
    fixtureSnapshot.signalCount = 2;
    fixtureSnapshot.isEntryEvaluated = false;
    fixtureSnapshot.isStrategyEntry = false;
    fixtureSnapshot.isSignalConsumed = false;
    fixtureSnapshot.reasonCode = "SIGNAL_ALREADY_CONSUMED";
    controller.onTick();
    verify(ArraySize(observedPreviousCounts) == 2 && observedPreviousCounts[0] == 0
        && observedPreviousCounts[1] == 1 && entrySaveCount == 1 && sendCount == 1,
        "next bar receives consumed count and does not send again");
    controller.shutdown(REASON_REMOVE);
}

/**
 * 原子的Entry保存が失敗した後は、DB復旧時も確定SKIPだけを再保存する。
 */
void verifySaveFailure() {
    resetFixture();
    rejectEntrySave = true;
    M15EaController controller;
    verify(controller.initialize("EURUSD", 0.01, 100.0) && controller.startTimer(), "save failure fixture initialized");
    controller.onTick();
    verify(entrySaveCount == 1 && sendCount == 0 && ArraySize(savedDecisions) == 0,
        "failed atomic entry never reaches send");
    rejectEntrySave = false;
    rejectDecisionSave = true;
    fixtureMilliseconds += 6000;
    controller.onTick();
    verify(openCount == 2 && decisionSaveCount == 1 && sendCount == 0 && analyzeCount == 1,
        "first retry only attempts finalized SKIP save");
    rejectDecisionSave = false;
    fixtureMilliseconds += 6000;
    controller.onTick();
    verify(openCount == 3 && decisionSaveCount == 2 && ArraySize(savedDecisions) == 1
        && savedDecisions[0].decision == "SKIP" && savedDecisions[0].reasonCode == "DB_UNAVAILABLE"
        && savedDecisions[0].signalCount == 1 && savedDecisions[0].isSignalConsumed
        && sendCount == 0 && entrySaveCount == 1 && analyzeCount == 1,
        "recovered persistence retains first consumption without delayed entry");
    controller.shutdown(REASON_REMOVE);
}

/**
 * Tester開始前には履歴だけを準備し、開始後の初回は未消費として評価する。
 */
void verifyBeforeStart() {
    resetFixture();
    datetime start = fixtureNow + 20;
    M15EaController controller;
    verify(controller.initialize("EURUSD", 0.01, 100.0, start) && controller.startTimer(),
        "warmup fixture initialized");
    controller.onTick();
    controller.onTick();
    verify(historyCount == 1 && analyzeCount == 0 && ArraySize(observedPreviousCounts) == 0
        && entrySaveCount == 0 && decisionSaveCount == 0 && sendCount == 0,
        "pre-start only prepares history once per bar without consuming judge");
    fixtureNow = start;
    controller.onTick();
    verify(ArraySize(observedPreviousCounts) == 1 && observedPreviousCounts[0] == 0
        && entrySaveCount == 1 && sendCount == 1, "trade start evaluates unconsumed first signal");
    controller.shutdown(REASON_REMOVE);
}

/**
 * 現在バーの確定行と回数の復元後は、そのバーを再評価しない。
 */
void verifyRestoredBar() {
    resetFixture();
    restoreCurrentBar = true;
    restoredCount = 1;
    M15EaController controller;
    verify(controller.initialize("EURUSD", 0.01, 100.0) && controller.startTimer(), "restore fixture initialized");
    controller.onTick();
    verify(analyzeCount == 0 && ArraySize(observedPreviousCounts) == 0
        && sendCount == 0 && entrySaveCount == 0, "restored current bar is not reevaluated");
    nextBar();
    fixtureSnapshot.signalCount = 2;
    fixtureSnapshot.isEntryEvaluated = false;
    fixtureSnapshot.isStrategyEntry = false;
    fixtureSnapshot.isSignalConsumed = false;
    fixtureSnapshot.reasonCode = "SIGNAL_ALREADY_CONSUMED";
    controller.onTick();
    verify(ArraySize(observedPreviousCounts) == 1 && observedPreviousCounts[0] == 1
        && sendCount == 0 && ArraySize(savedDecisions) == 1 && savedDecisions[0].signalCount == 2,
        "next M15 bar uses restored signal count");
    controller.shutdown(REASON_REMOVE);
}

/**
 * 補正分析中に気配が変化した場合、同じバーの再試行へ回数を残す。
 */
void verifyQuoteChangesDuringEvaluation() {
    resetFixture();
    expireQuoteDuringEvaluate = true;
    M15EaController controller;
    verify(controller.initialize("EURUSD", 0.01, 100.0) && controller.startTimer(),
        "evaluation quote change fixture initialized");
    controller.onTick();
    verify(analyzeCount == 1 && ArraySize(observedPreviousCounts) == 1
        && observedPreviousCounts[0] == 0 && entrySaveCount == 0 && decisionSaveCount == 0 && sendCount == 0,
        "quote lost during strategy evaluation does not consume or persist a decision");
    expireQuoteDuringEvaluate = false;
    quoteUnavailable = false;
    controller.onTick();
    verify(analyzeCount == 2 && ArraySize(observedPreviousCounts) == 2
        && observedPreviousCounts[1] == 0 && entrySaveCount == 1 && sendCount == 1,
        "same bar retries with unconsumed count after quote returns");
    controller.shutdown(REASON_REMOVE);
}

/**
 * 実Controllerと共通の回数・SL・canonical処理を外部副作用なしで確認する。
 */
void OnStart() {
    verifyEntryConnection();
    verifySaveFailure();
    verifyBeforeStart();
    verifyRestoredBar();
    verifyQuoteChangesDuringEvaluation();
    Print("INFO M15EaControllerSmokeTest SUMMARY passed=", passedCount, " failed=", failedCount);
}
