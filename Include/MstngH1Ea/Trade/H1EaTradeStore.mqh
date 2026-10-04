#ifndef MSTNGH1EA_TRADE_H1EATRADESTORE_MQH
#define MSTNGH1EA_TRADE_H1EATRADESTORE_MQH

#include <Mstng\Database\Service\H1EaPersistenceService.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTextUtil.mqh>
#include <Mstng\ExpertAdvisor\Runtime\IEaTradeStore.mqh>
#include <MstngH1Ea\Trade\H1EaTradeStateMapper.mqh>

/**
 * 共通の取引保存契約を既存H1のPersistenceServiceへ接続する。
 * 保存先の所有権は呼出元に残し、DBスキーマと保存値を変更しない。
 */
class H1EaTradeStore : public IEaTradeStore {
public:
    /**
     * 保存先未設定で初期化する。
     */
    H1EaTradeStore() {
        this.persistence = NULL;
    }

    /**
     * 呼出元が保持するH1保存先を一度だけ設定する。
     */
    bool initialize(H1EaPersistenceService *fromPersistence) {
        if (this.persistence != NULL || fromPersistence == NULL) {
            return false;
        }
        this.persistence = fromPersistence;
        return true;
    }

    /**
     * 既存保存先のエラー文字列をそのまま返す。
     */
    virtual string getLastError() const {
        if (this.persistence == NULL) {
            return "TRADE_STORE_UNAVAILABLE";
        }
        return this.persistence.getLastError();
    }

    /**
     * 現在Runの管理権を既存保存先で確認する。
     */
    virtual bool hasLease(const long fromRunId, const datetime fromNow) {
        if (this.persistence == NULL) {
            return false;
        }
        return this.persistence.hasLease(fromRunId, fromNow);
    }

    /**
     * 既存の原子的保存を呼び、採番と読戻しを成功・失敗とも返す。
     */
    virtual bool saveTradeEvent(const long fromRunId, EaTradeState &fromTrade,
            EaTradeEvent &fromEvent, const bool fromRequireLease = true,
            const bool fromReplayQueuedRequest = false) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEntity trade;
        H1EaTradeEventEntity event;
        H1EaTradeStateMapper::toH1(fromTrade, trade);
        H1EaTradeStateMapper::toH1(fromEvent, event);
        bool success = this.persistence.saveTradeEvent(fromRunId, trade, event,
            fromRequireLease, fromReplayQueuedRequest);
        H1EaTradeStateMapper::toCommon(trade, fromTrade);
        H1EaTradeStateMapper::toCommon(event, fromEvent);
        return success;
    }

    /**
     * 現contextの管理対象取引を既存保存先から復元する。
     */
    virtual bool loadActiveTrade(const string fromContext,
            EaTradeState &fromTrade, bool &fromFound) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEntity trade;
        H1EaTradeStateMapper::toH1(fromTrade, trade);
        bool success = this.persistence.loadActiveTrade(fromContext, trade, fromFound);
        H1EaTradeStateMapper::toCommon(trade, fromTrade);
        return success;
    }

    /**
     * 既存の監査対象選択条件と復元結果を維持する。
     */
    virtual bool loadClosedTradeForDealAudit(const string fromContext, const long fromAfterId,
            EaTradeState &fromTrade, bool &fromFound, const bool fromFullAudit = false) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEntity trade;
        H1EaTradeStateMapper::toH1(fromTrade, trade);
        bool success = this.persistence.loadClosedTradeForDealAudit(fromContext, fromAfterId,
            trade, fromFound, fromFullAudit);
        H1EaTradeStateMapper::toCommon(trade, fromTrade);
        return success;
    }

    /**
     * 同context・Position IDの決済済み取引を取得する。
     */
    virtual bool loadClosedTradeByPosition(const string fromContext, const string fromPositionIdentifier,
            EaTradeState &fromTrade, bool &fromFound) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEntity trade;
        H1EaTradeStateMapper::toH1(fromTrade, trade);
        bool success = this.persistence.loadClosedTradeByPosition(fromContext, fromPositionIdentifier,
            trade, fromFound);
        H1EaTradeStateMapper::toCommon(trade, fromTrade);
        return success;
    }

    /**
     * 決済済み約定イベントを追記し、採番済み結果を返す。
     */
    virtual bool appendClosedDealEvent(const long fromRunId, const long fromTradeId,
            EaTradeEvent &fromEvent) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEventEntity event;
        H1EaTradeStateMapper::toH1(fromEvent, event);
        bool success = this.persistence.appendClosedDealEvent(fromRunId, fromTradeId, event);
        H1EaTradeStateMapper::toCommon(event, fromEvent);
        return success;
    }

    /**
     * 照合済みの決済取引から監査待ちだけを解除する。
     */
    virtual bool completeClosedDealAudit(const long fromRunId, const long fromTradeId) {
        if (this.persistence == NULL) {
            return false;
        }
        return this.persistence.completeClosedDealAudit(fromRunId, fromTradeId);
    }

    /**
     * 不正pendingを隔離する既存の保存値文字列を取得する。
     */
    virtual bool loadPendingRaw(const long fromTradeId, string &fromText) {
        if (this.persistence == NULL) {
            return false;
        }
        return this.persistence.loadPendingRaw(fromTradeId, fromText);
    }

    /**
     * 同じactionの要求または結果を旧保存形式から読み戻す。
     */
    virtual bool loadEvent(const string fromActionUid, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEventEntity event;
        H1EaTradeStateMapper::toH1(fromEvent, event);
        bool success = this.persistence.loadEvent(fromActionUid, fromEventType, event, fromFound);
        H1EaTradeStateMapper::toCommon(event, fromEvent);
        return success;
    }

    /**
     * 取引内で最後の指定種別イベントを旧保存形式から読み戻す。
     */
    virtual bool loadLatestTradeEvent(const long fromTradeId, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) {
        if (this.persistence == NULL) {
            return false;
        }
        H1EaTradeEventEntity event;
        H1EaTradeStateMapper::toH1(fromEvent, event);
        bool success = this.persistence.loadLatestTradeEvent(fromTradeId, fromEventType, event, fromFound);
        H1EaTradeStateMapper::toCommon(event, fromEvent);
        return success;
    }

    /**
     * 既存SQLと文字列形式で未完了要求をaction UID順に返す。
     */
    virtual string unresolvedActionsText(const long fromTradeId) {
        if (this.persistence == NULL) {
            return "~";
        }
        string sql = "SELECT requested.action_uid FROM h1_ea_trade_events requested WHERE requested.trade_id="
            + IntegerToString(fromTradeId)
            + " AND requested.event_type IN ('ENTRY_REQUEST','SL_MODIFY_REQUEST','EXIT_REQUEST')"
            + " AND NOT EXISTS(SELECT 1 FROM h1_ea_trade_events resolved WHERE resolved.action_uid=requested.action_uid"
            + " AND resolved.event_type=REPLACE(requested.event_type,'_REQUEST','_RESULT')) ORDER BY requested.action_uid";
        int handle = DatabasePrepare(this.persistence.getHandle(), sql);
        if (handle == INVALID_HANDLE) {
            return "~";
        }
        string result = "";
        while (DatabaseRead(handle)) {
            string actionUid;
            if (!DatabaseColumnText(handle, 0, actionUid)) {
                DatabaseFinalize(handle);
                return "~";
            }
            EaTextUtil::appendField(result, "action_uid", actionUid);
        }
        DatabaseFinalize(handle);
        return result;
    }

private:
    /** 呼出元が所有するH1の保存先。 */
    H1EaPersistenceService *persistence;
};

#endif
