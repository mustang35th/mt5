#ifndef MSTNGH1EA_TRADE_H1EATRADEEXECUTOR_MQH
#define MSTNGH1EA_TRADE_H1EATRADEEXECUTOR_MQH

#include <MstngEaCommon\Runtime\EaTradeExecutor.mqh>
#include <MstngH1Ea\Trade\H1EaTradePolicy.mqh>
#include <MstngH1Ea\Trade\H1EaTradeStore.mqh>

/**
 * H1用の既存保存項目型を維持する。
 */
struct H1EaTradeSaveItem {
    /** Event時点の状態。 */
    H1EaTradeEntity trade;

    /** 一意ID確定済みEvent。 */
    H1EaTradeEventEntity event;
};

/**
 * 共通の発注・復元処理を既存H1の公開APIと保存形式へ接続する。
 * Controllerの原子的なsaveEntryと、保存成功後の送信順序を維持する。
 */
class H1EaTradeExecutor : public EaTradeExecutor {
public:
    /**
     * H1保存先を未設定で作成する。
     */
    H1EaTradeExecutor() {
        this.configured = false;
    }

    /**
     * H1の保存先・時間足・識別子を渡す。初期化中の発注は行わない。
     */
    bool initialize(const string fromSymbol, const ulong fromMagic,
            const double fromPipSize, const double fromTickSize,
            const long fromRunId, const string fromRunUid, const string fromContextKey,
            H1EaPersistenceService *fromPersistence) {
        if (this.configured || fromPersistence == NULL || fromRunId <= 0
                || fromPipSize <= 0.0 || fromTickSize <= 0.0) {
            return false;
        }

        if (!this.store.initialize(fromPersistence)) {
            return false;
        }

        EaTradeProfile runtimeProfile;
        H1EaTradePolicy::profile(runtimeProfile);

        this.configured = EaTradeExecutor::initialize(fromSymbol, fromMagic,
            fromPipSize, fromTickSize, fromRunId, fromRunUid, fromContextKey,
            GetPointer(this.store), runtimeProfile, GetPointer(this.h1Policy));

        return this.configured;
    }

    /**
     * 復元した取引を既存のH1保存型へコピーする。送信可否は判定しない。
     */
    bool getRestoredTrade(H1EaTradeEntity &fromTrade, bool &fromActive) {
        EaTradeState commonTrade;
        bool restored = EaTradeExecutor::getRestoredTrade(commonTrade, fromActive);

        H1EaTradeStateMapper::toH1(commonTrade, fromTrade);

        return restored;
    }

    /**
     * H1のDecisionから送信前transactionに必要な取引とイベントを作る。
     */
    void prepareEntry(H1EaDecisionEntity &fromDecision, H1EaTradeEntity &fromTrade,
            H1EaTradeEventEntity &fromEvent) {
        EaEntryRequest request;
        request.side = fromDecision.decision;
        request.requestedVolume = fromDecision.requestedVolume;
        request.initialStopLoss = fromDecision.initialStopLoss;
        request.barTime = fromDecision.h1BarTime;
        request.maxInitialRiskPips = fromDecision.maxInitialRiskPips;

        EaTradeState commonTrade;
        EaTradeEvent event;
        EaTradeExecutor::prepareEntry(request, commonTrade, event);

        H1EaTradeStateMapper::toH1(commonTrade, fromTrade);
        H1EaTradeStateMapper::toH1(event, fromEvent);
    }

    /**
     * 既存saveEntryで採番済みの要求を渡す。未知受付を再送しない。
     */
    void sendEntry(H1EaTradeEntity &fromTrade, H1EaTradeEventEntity &fromEntryRequest) {
        EaTradeState commonTrade;
        EaTradeEvent event;
        H1EaTradeStateMapper::toCommon(fromTrade, commonTrade);
        H1EaTradeStateMapper::toCommon(fromEntryRequest, event);

        EaTradeExecutor::sendEntry(commonTrade, event);

        H1EaTradeStateMapper::toH1(commonTrade, fromTrade);
        H1EaTradeStateMapper::toH1(event, fromEntryRequest);
    }

private:
    /** 共通実行部の初期化完了状態。 */
    bool configured;

    /** 既存H1永続化への接続。 */
    H1EaTradeStore store;

    /** 既存H1戦略・ログへの接続。 */
    H1EaTradePolicy h1Policy;
};

#endif
