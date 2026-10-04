#ifndef MSTNGEACOMMON_RUNTIME_IEATRADESTORE_MQH
#define MSTNGEACOMMON_RUNTIME_IEATRADESTORE_MQH

#include <MstngEaCommon\Runtime\EaTradeEvent.mqh>
#include <MstngEaCommon\Runtime\EaTradeState.mqh>

/**
 * 共通の発注・復元処理が使用する取引保存先の契約。
 * 保存は取引状態とイベントを原子的に扱い、接続ハンドルは公開しない。
 */
class IEaTradeStore {
public:
    /**
     * 派生した保存先を仮想デストラクタで破棄する。
     */
    virtual ~IEaTradeStore() {}

    /**
     * 最後の保存先エラーを返す。
     */
    virtual string getLastError() const = 0;

    /**
     * 現在Runの有効な管理権を確認する。
     */
    virtual bool hasLease(const long fromRunId, const datetime fromNow) = 0;

    /**
     * 取引状態とイベントを同じtransactionで保存する。
     */
    virtual bool saveTradeEvent(const long fromRunId, EaTradeState &fromTrade,
            EaTradeEvent &fromEvent, const bool fromRequireLease = true,
            const bool fromReplayQueuedRequest = false) = 0;

    /**
     * 現contextの管理対象取引を復元する。
     */
    virtual bool loadActiveTrade(const string fromContext,
            EaTradeState &fromTrade, bool &fromFound) = 0;

    /**
     * 約定監査対象の決済済み取引を主キー順に取得する。
     */
    virtual bool loadClosedTradeForDealAudit(const string fromContext, const long fromAfterId,
            EaTradeState &fromTrade, bool &fromFound, const bool fromFullAudit = false) = 0;

    /**
     * 遅延約定に対応する決済済み取引をPosition IDから取得する。
     */
    virtual bool loadClosedTradeByPosition(const string fromContext, const string fromPositionIdentifier,
            EaTradeState &fromTrade, bool &fromFound) = 0;

    /**
     * 決済済み取引へbroker約定事実だけを追記する。
     */
    virtual bool appendClosedDealEvent(const long fromRunId, const long fromTradeId,
            EaTradeEvent &fromEvent) = 0;

    /**
     * 全約定の照合完了後に監査待ちを解除する。
     */
    virtual bool completeClosedDealAudit(const long fromRunId, const long fromTradeId) = 0;

    /**
     * 不整合診断のためpendingの保存値を型変換前の文字列で取得する。
     */
    virtual bool loadPendingRaw(const long fromTradeId, string &fromText) = 0;

    /**
     * 同じactionの要求または結果を取得する。
     */
    virtual bool loadEvent(const string fromActionUid, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) = 0;

    /**
     * 取引内で最後に保存した指定種別のイベントを取得する。
     */
    virtual bool loadLatestTradeEvent(const long fromTradeId, const string fromEventType,
            EaTradeEvent &fromEvent, bool &fromFound) = 0;

    /**
     * 未完了要求をaction UID順の監査文字列で返す。読取失敗は~を返す。
     */
    virtual string unresolvedActionsText(const long fromTradeId) = 0;
};

#endif
