#property strict

#include <Mstng\ExpertAdvisor\Runtime\EaClock.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaDealHistory.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaProtectionPolicy.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTextUtil.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTradePolicy.mqh>
#include <Mstng\ExpertAdvisor\Runtime\IEaTradeStore.mqh>

/** 検証失敗数。 */
int failureCount = 0;
/** fixtureの現在時刻。 */
datetime fixtureNow = D'2026.10.04 12:00:10';
/** fixtureの現在バー。 */
datetime fixtureBar = D'2026.10.04 12:00:00';
/** iTimeへ渡された対象足。 */
ENUM_TIMEFRAMES observedTimeFrame = PERIOD_CURRENT;
/** OrderCheck呼出し数。 */
int checkCount = 0;
/** OrderSend呼出し数。 */
int sendCount = 0;
/** brokerのPosition/Order一覧参照回数。 */
int brokerReadCount = 0;
/** OrderCheck拒否を再現する。 */
bool rejectCheck = false;
/** OrderCheck中のバー変更を再現する。 */
bool changeBarDuringCheck = false;
/** OrderCheck中のLease期限切れを再現する。 */
bool expireLeaseDuringCheck = false;
/** fixtureが受け取った要求。 */
MqlTradeRequest capturedRequest;

/**
 * brokerへ送らず、最終送信要求を保存して明示的な拒否を返す。
 */
bool fakeOrderSend(MqlTradeRequest &fromRequest, MqlTradeResult &fromResult) {
    sendCount++;
    capturedRequest = fromRequest;
    ZeroMemory(fromResult);
    fromResult.retcode = TRADE_RETCODE_REJECT;
    fromResult.comment = "SMOKE_REJECT";
    return false;
}

/**
 * brokerへ照会せず、事前確認後に起きる状態変化を再現する。
 */
bool fakeOrderCheck(MqlTradeRequest &fromRequest, MqlTradeCheckResult &fromResult) {
    checkCount++;
    ZeroMemory(fromResult);
    fromResult.retcode = TRADE_RETCODE_DONE;
    if (changeBarDuringCheck) {
        fixtureBar += 3600;
    }
    if (expireLeaseDuringCheck) {
        fixtureNow += 3600;
    }
    if (rejectCheck) {
        fromResult.retcode = TRADE_RETCODE_INVALID_STOPS;
        fromResult.comment = "SMOKE_INVALID_STOPS";
        return false;
    }
    return true;
}

/**
 * 実口座の状態を使わずhedgingと売買許可を返す。
 */
long fakeAccountInfoInteger(const ENUM_ACCOUNT_INFO_INTEGER fromProperty) {
    if (fromProperty == ACCOUNT_MARGIN_MODE) {
        return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
    }
    return 1;
}

/**
 * fixture内だけで売買可能な端末状態を再現する。
 */
long fakeTerminalInfoInteger(const ENUM_TERMINAL_INFO_INTEGER fromProperty) {
    return 1;
}

/**
 * fixture内だけでtesterとプログラム売買許可を再現する。
 */
int fakeMqlInfoInteger(const ENUM_MQL_INFO_INTEGER fromProperty) {
    return 1;
}

/**
 * 実気配を使用しない。
 */
bool fakeSymbolInfoTick(const string fromSymbol, MqlTick &fromTick) {
    ZeroMemory(fromTick);
    fromTick.bid = 1.1020;
    fromTick.ask = 1.1021;
    fromTick.time = fixtureNow;
    fromTick.time_msc = (long)fixtureNow * 1000;
    return true;
}

/**
 * 最小距離・FOK設定を固定する。
 */
long fakeSymbolInfoInteger(const string fromSymbol, const ENUM_SYMBOL_INFO_INTEGER fromProperty) {
    if (fromProperty == SYMBOL_FILLING_MODE) {
        return SYMBOL_FILLING_FOK;
    }
    if (fromProperty == SYMBOL_DIGITS) {
        return 5;
    }
    return 10;
}

/**
 * point幅を固定する。
 */
double fakeSymbolInfoDouble(const string fromSymbol, const ENUM_SYMBOL_INFO_DOUBLE fromProperty) {
    return 0.00001;
}

/**
 * 時間足を記録してfixtureバーを返す。
 */
datetime fakeTime(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame, const int fromShift) {
    observedTimeFrame = fromTimeFrame;
    return fixtureBar;
}

/**
 * 固定現在時刻を返す。
 */
datetime fakeNow() {
    return fixtureNow;
}

/**
 * 実口座を列挙せず空のbroker状態を返す。
 */
int fakeBrokerTotal() {
    brokerReadCount++;
    return 0;
}

// 依存型のinclude完了後、Executor内のbroker境界だけをfixtureへ置き換える。
#define OrderCheck fakeOrderCheck
#define OrderSend fakeOrderSend
#define AccountInfoInteger fakeAccountInfoInteger
#define TerminalInfoInteger fakeTerminalInfoInteger
#define MQLInfoInteger fakeMqlInfoInteger
#define SymbolInfoTick fakeSymbolInfoTick
#define SymbolInfoInteger fakeSymbolInfoInteger
#define SymbolInfoDouble fakeSymbolInfoDouble
#define iTime fakeTime
#define TimeCurrent fakeNow
#define TimeLocal fakeNow
#define PositionsTotal fakeBrokerTotal
#define OrdersTotal fakeBrokerTotal
#include <Mstng\ExpertAdvisor\Runtime\EaTradeExecutor.mqh>
#undef OrderCheck
#undef OrderSend
#undef AccountInfoInteger
#undef TerminalInfoInteger
#undef MQLInfoInteger
#undef SymbolInfoTick
#undef SymbolInfoInteger
#undef SymbolInfoDouble
#undef iTime
#undef TimeCurrent
#undef TimeLocal
#undef PositionsTotal
#undef OrdersTotal

/**
 * DBを開かず、読込と保存の結果だけを制御する保存先。
 */
class SmokeTradeStore : public IEaTradeStore {
public:
    /** 復元fixture。 */
    EaTradeState storedTrade;
    /** 最後に保存したイベント。 */
    EaTradeEvent savedEvent;
    /** 復元対象の有無。 */
    bool found;
    /** 読込失敗fixture。 */
    bool failLoad;
    /** Event保存失敗fixture。 */
    bool failSave;
    /** 復元呼出し数。 */
    int loadCount;
    /** 保存呼出し数。 */
    int saveCount;

    /**
     * fixtureを初期化する。
     */
    SmokeTradeStore() {
        this.storedTrade.reset();
        this.savedEvent.reset();
        this.found = false;
        this.failLoad = false;
        this.failSave = false;
        this.loadCount = 0;
        this.saveCount = 0;
    }

    /**
     * 保存失敗用の固定エラーを返す。
     */
    virtual string getLastError() const override { return "SMOKE_STORAGE_FAILURE"; }

    /**
     * fixture用のLeaseを返す。
     */
    virtual bool hasLease(const long fromRunId, const datetime fromNow) override { return true; }

    /**
     * 成功した場合だけ状態とイベントを保存する。
     */
    virtual bool saveTradeEvent(const long fromRunId, EaTradeState &fromTrade,
            EaTradeEvent &fromEvent, const bool fromRequireLease = true,
            const bool fromReplayQueuedRequest = false) override {
        this.saveCount++;
        if (this.failSave) {
            return false;
        }
        this.storedTrade = fromTrade;
        this.savedEvent = fromEvent;
        return true;
    }

    /**
     * 実DBを使わず保存済み取引を復元する。
     */
    virtual bool loadActiveTrade(const string fromContext,
            EaTradeState &fromTrade, bool &fromFound) override {
        this.loadCount++;
        fromTrade.reset();
        fromFound = false;
        if (this.failLoad) {
            return false;
        }
        fromTrade = this.storedTrade;
        fromFound = this.found;
        return true;
    }

    /**
     * 使用しない保存先操作は成功扱いにしない。
     */
    virtual bool loadClosedTradeForDealAudit(const string fromContext, const long fromAfterId,
            EaTradeState &fromTrade, bool &fromFound, const bool fromFullAudit = false) override {
        return false;
    }

    /**
     * 使用しない決済済み取引の読込を拒否する。
     */
    virtual bool loadClosedTradeByPosition(const string fromContext, const string fromPositionIdentifier,
            EaTradeState &fromTrade, bool &fromFound) override { return false; }

    /**
     * 使用しない監査イベントの追記を拒否する。
     */
    virtual bool appendClosedDealEvent(const long fromRunId, const long fromTradeId,
            EaTradeEvent &fromEvent) override { return false; }

    /**
     * 使用しない監査完了を拒否する。
     */
    virtual bool completeClosedDealAudit(const long fromRunId, const long fromTradeId) override { return false; }

    /**
     * 使用しない隔離情報の読込を拒否する。
     */
    virtual bool loadPendingRaw(const long fromTradeId, string &fromText) override { return false; }

    /**
     * 使用しないaction読込を拒否する。
     */
    virtual bool loadEvent(const string fromActionUid, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) override { return false; }

    /**
     * 使用しない最新イベント読込を拒否する。
     */
    virtual bool loadLatestTradeEvent(const long fromTradeId, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) override { return false; }

    /**
     * 未実装の監査読込を欠落なしと誤認させない。
     */
    virtual string unresolvedActionsText(const long fromTradeId) override { return "~"; }
};

/**
 * ログ・トレイルにも外部副作用を持たない戦略fixture。
 */
class SmokeTradePolicy : public IEaTradePolicy {
public:
    /**
     * 外部ログを初期化しない。
     */
    virtual void initialize(const string fromSymbol, const ulong fromMagic,
            const string fromRunUid) override {}

    /**
     * この発注テストで使用しないトレイルは拒否する。
     */
    virtual bool evaluateTrail(PositionSnapshot &fromPosition, Wave *fromWave,
            const double fromPipSize, const double fromTickSize, EaTrailDecision &fromResult) override {
        fromResult.reset();
        return false;
    }

    /**
     * この発注テストでは決済理由を作らない。
     */
    virtual string closeReason(const string fromIntent, const string fromStopLossSource,
            const string fromBrokerReason) override { return "SMOKE"; }

    /**
     * 運用ログを生成しない。
     */
    virtual void writeLog(const string fromLevel, const string fromMessage) override {}
};

/**
 * 条件を集計する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (!fromSuccess) {
        failureCount++;
        Print("ERROR EaTradeExecutorSmokeTest FAIL ", fromName);
    }
}

/**
 * broker fixtureを各ケースの初期状態へ戻す。
 */
void resetFixture() {
    fixtureNow = D'2026.10.04 12:00:10';
    fixtureBar = D'2026.10.04 12:00:00';
    observedTimeFrame = PERIOD_CURRENT;
    checkCount = 0;
    sendCount = 0;
    brokerReadCount = 0;
    rejectCheck = false;
    changeBarDuringCheck = false;
    expireLeaseDuringCheck = false;
    ZeroMemory(capturedRequest);
}

/**
 * 保存識別子を運用EAと分離し、対象時間足を明示する。
 */
void prepareProfile(const ENUM_TIMEFRAMES fromTimeFrame, EaTradeProfile &fromProfile) {
    fromProfile.timeFrame = fromTimeFrame;
    fromProfile.actionUidPrefix = "SMOKE_ACTION|";
    fromProfile.trailEvaluationUidPrefix = "SMOKE_TRAIL|";
    fromProfile.cancelUidPrefix = "SMOKE_CANCEL|";
    fromProfile.dealAuditUidPrefix = "SMOKE_DEAL|";
    fromProfile.recoveryUidPrefix = "SMOKE_RECOVERY|";
    fromProfile.recoverySnapshotPrefix = "SMOKE_SNAPSHOT";
    fromProfile.pendingMemoryPrefix = "SMOKE_PENDING";
    fromProfile.entryCommentPrefix = "SmokeEntry:";
    fromProfile.closeCommentPrefix = "SmokeClose:";
    fromProfile.trailStopLossSource = "SMOKE_TRAIL";
    fromProfile.trailCrossedReason = "SMOKE_CROSSED";
    fromProfile.pendingBarField = "pending_bar";
    fromProfile.lastAppliedTrailBarField = "last_applied_bar";
    fromProfile.lastTrailEvaluatedBarField = "last_evaluated_bar";
}

/**
 * 復元失敗の再試行と、pending SLを含む既存取引の復元を確認する。
 */
void verifyRestoration() {
    resetFixture();
    SmokeTradeStore store;
    SmokeTradePolicy policy;
    EaTradeProfile profile;
    prepareProfile(PERIOD_H1, profile);
    EaTradeExecutor executor;
    verify(executor.initialize("SMOKE", 17, 0.0001, 0.00001, 1, "run", "context",
        GetPointer(store), profile, GetPointer(policy)), "restoration initialization");
    store.failLoad = true;
    EaTradeState restored;
    bool active = true;
    verify(!executor.restoreFromDatabase() && !executor.getRestoredTrade(restored, active)
        && !active && restored.id == 0, "failed load never publishes restored state");
    store.failLoad = false;
    store.found = true;
    store.storedTrade.id = 77;
    store.storedTrade.contextKey = "context";
    store.storedTrade.status = "OPEN_PENDING";
    store.storedTrade.side = "BUY";
    store.storedTrade.entryOrderTicket = "9000000001";
    store.storedTrade.pendingStopLossKind = "INITIAL_RESTORE";
    store.storedTrade.pendingStopLoss = 1.1;
    store.storedTrade.pendingStopLossBarTime = (long)fixtureBar;
    store.storedTrade.pendingStopLossActionUid = "saved-pending-action";
    verify(executor.restoreFromDatabase() && executor.getRestoredTrade(restored, active)
        && active && restored.id == 77 && restored.status == "OPEN_PENDING"
        && restored.entryOrderTicket == "9000000001"
        && restored.pendingStopLossKind == "INITIAL_RESTORE"
        && restored.pendingStopLoss == 1.1 && restored.pendingStopLossBarTime == (long)fixtureBar
        && restored.pendingStopLossActionUid == "saved-pending-action",
        "retry preserves pending trade and SL identity");
    store.storedTrade.pendingStopLoss = 0.5;
    verify(executor.restoreFromDatabase() && executor.getRestoredTrade(restored, active)
        && restored.pendingStopLoss == 1.1 && store.loadCount == 2,
        "successful restoration loads once");
    verify(executor.hasActiveTrade() && executor.hasPendingDealAudit()
        && !executor.isIdleForTesterWarmup(), "restored trade awaits broker reconciliation");
    verify(store.saveCount == 0 && checkCount == 0 && sendCount == 0 && brokerReadCount == 0,
        "database-only restoration never consults or modifies broker");
}

/**
 * 注文拒否fixtureで要求内容と重複送信防止を確認する。
 */
void verifyEntry(const ENUM_TIMEFRAMES fromTimeFrame, const bool fromIsBuy,
        const int fromFailureMode) {
    resetFixture();
    SmokeTradeStore store;
    SmokeTradePolicy policy;
    EaTradeProfile profile;
    prepareProfile(fromTimeFrame, profile);
    EaTradeExecutor executor;
    verify(executor.initialize("SMOKE", 17, 0.0001, 0.00001, 1, "run", "context",
        GetPointer(store), profile, GetPointer(policy)), "entry initialization");
    verify(executor.restoreFromDatabase(), "entry starts after database restoration");
    executor.setManagementAuthority(true, fixtureNow + 60);
    executor.setRequireCurrentQuote(true);
    EaEntryRequest decision;
    decision.side = "SELL";
    decision.initialStopLoss = 1.104;
    if (fromIsBuy) {
        decision.side = "BUY";
        decision.initialStopLoss = 1.1;
    }
    decision.requestedVolume = 0.02;
    decision.maxInitialRiskPips = 30.0;
    decision.barTime = (long)fixtureBar;
    EaTradeState trade;
    EaTradeEvent request;
    executor.prepareEntry(decision, trade, request);
    verify(trade.status == "OPEN_PENDING" && trade.side == decision.side
        && trade.requestedStopLoss == decision.initialStopLoss && trade.requestedVolume == 0.02
        && request.eventType == "ENTRY_REQUEST" && request.barTime == decision.barTime,
        "prepared trade and audit retain strategy inputs");
    executor.sendEntry(trade, request);
    verify(sendCount == 0 && checkCount == 0 && store.saveCount == 0,
        "unsaved entry cannot reach broker");
    // 本番のsaveEntryによるID確定をfixtureで表す。実DBへ書き込まない。
    trade.id = 101;
    request.id = 201;
    StringReplace(request.actionUid, "{TRADE_ID}", "101");
    StringReplace(request.eventUid, "{TRADE_ID}", "101");
    rejectCheck = fromFailureMode == 1;
    changeBarDuringCheck = fromFailureMode == 2;
    expireLeaseDuringCheck = fromFailureMode == 3;
    store.failSave = fromFailureMode == 4;
    executor.sendEntry(trade, request);
    verify(trade.status == "OPEN_FAILED" && !executor.hasActiveTrade()
        && observedTimeFrame == fromTimeFrame, "terminal rejection respects configured timeframe");
    int expectedSends = 0;
    if (fromFailureMode == 0 || fromFailureMode == 4) {
        expectedSends = 1;
        verify(capturedRequest.action == TRADE_ACTION_DEAL && capturedRequest.symbol == "SMOKE"
            && capturedRequest.magic == 17 && capturedRequest.volume == 0.02
            && capturedRequest.sl == decision.initialStopLoss && capturedRequest.tp == 0.0
            && capturedRequest.type_filling == ORDER_FILLING_FOK
            && capturedRequest.comment == "SmokeEntry:101", "SL and identity survive order construction");
        if (fromIsBuy) {
            verify(capturedRequest.type == ORDER_TYPE_BUY && capturedRequest.price == 1.1021,
                "BUY uses Ask");
        } else {
            verify(capturedRequest.type == ORDER_TYPE_SELL && capturedRequest.price == 1.1020,
                "SELL uses Bid");
        }
        verify(trade.entryRetcode == TRADE_RETCODE_REJECT
            && trade.lastError == "ORDER_SEND: SMOKE_REJECT", "broker rejection stays explicit");
    } else if (fromFailureMode == 1) {
        verify(StringFind(trade.lastError, "ORDER_CHECK_FAILED:") == 0, "OrderCheck rejects before send");
    } else if (fromFailureMode == 2) {
        verify(trade.lastError == "ENTRY_BAR_EXPIRED", "bar changed after OrderCheck rejects before send");
    } else if (fromFailureMode == 3) {
        verify(trade.lastError == "LEASE_EXPIRED_BEFORE_SEND", "expired lease rejects before send");
    }
    verify(checkCount == 1 && sendCount == expectedSends && store.saveCount == 1,
        "one request produces one result save attempt");
    if (fromFailureMode == 4) {
        verify(executor.hasUnsavedEvents(), "failed result save remains queued");
    } else {
        verify(store.savedEvent.eventType == "ENTRY_RESULT"
            && store.savedEvent.actionUid == request.actionUid
            && store.storedTrade.status == "OPEN_FAILED", "result retains saved request identity");
    }
    trade.status = "OPEN_PENDING";
    executor.sendEntry(trade, request);
    verify(sendCount == expectedSends && checkCount == 1 && store.saveCount == 1,
        "same trade cannot be resent even with caller status restored");
    if (fromFailureMode == 4) {
        verify(!executor.flushPendingEvents() && store.saveCount == 2 && sendCount == 1,
            "failed result flush retries storage without sending another order");
        store.failSave = false;
        verify(executor.flushPendingEvents() && store.saveCount == 3 && sendCount == 1
            && store.savedEvent.eventType == "ENTRY_RESULT"
            && store.savedEvent.actionUid == request.actionUid
            && store.storedTrade.status == "OPEN_FAILED", "queued result eventually saves with original identity");
        verify(executor.flushPendingEvents() && store.saveCount == 3 && sendCount == 1,
            "saved queue is removed exactly once");
    }
}

/**
 * 実注文・口座・DBに触れない発注境界と復元の回帰を実行する。
 */
void OnStart() {
    verifyRestoration();
    verifyEntry(PERIOD_H1, true, 0);
    verifyEntry(PERIOD_M15, false, 0);
    for (int i = 1; i <= 4; i++) {
        verifyEntry(PERIOD_M15, true, i);
    }
    Print("INFO EaTradeExecutorSmokeTest failures=", failureCount);
}
