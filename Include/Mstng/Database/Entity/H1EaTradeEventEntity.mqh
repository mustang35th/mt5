#ifndef MSTNG_DATABASE_ENTITY_H1_EA_TRADE_EVENT_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_H1_EA_TRADE_EVENT_ENTITY_MQH

/**
 * H1 EA TradeEventの保存スナップショット。
 * 任意文字列は空文字、任意正値は0、数量・損益はEMPTY_VALUEをNULLとして扱う。
 */
struct H1EaTradeEventEntity {
    /** 主キー。 */
    long id;
    /** Trade外部キー。 */
    long tradeId;
    /** Eventを保存したRunの外部キー。 */
    long runId;
    /** 冪等保存用の一意ID。 */
    string eventUid;
    /** 同じEntry、ExitまたはSL変更試行の要求と結果を関連付けるID。 */
    string actionUid;
    /** 同一Trade内の1始まり連番。 */
    long sequence;
    /** Event種別。 */
    string eventType;
    /** EA、CALLBACKまたはRECONCILIATION。 */
    string eventSource;
    /** 要求時などのbroker server時刻。 */
    long serverTime;
    /** brokerが提供したorder/deal時刻。 */
    long brokerTimeMsc;
    /** TimeLocal()による保存時刻。 */
    long recordedAt;
    /** MqlTradeTransaction.type。 */
    int transactionType;
    /** Order Ticket。 */
    string orderTicket;
    /** Deal Ticket。 */
    string dealTicket;
    /** 実行scopeを含むDeal一意キー。 */
    string dealScopeKey;
    /** Position ID。 */
    string positionIdentifier;
    /** SL変更またはEvent対象のPosition Ticket。 */
    string positionTicket;
    /** BUYまたはSELL。 */
    string side;
    /** 要求または約定数量。 */
    double volume;
    /** 要求または約定価格。 */
    double price;
    /** トレイル評価対象H1バー時刻。 */
    long h1BarTime;
    /** トレイル基準ZigZag点時刻。 */
    long pivotBarTime;
    /** トレイル基準ZigZag点価格。 */
    double pivotRate;
    /** 基準点の確定確認に使用した最新点時刻。 */
    long latestPointBarTime;
    /** SL変更前にbrokerで確認したSL。 */
    double previousStopLoss;
    /** トレイル評価候補または保護SL変更要求値。 */
    double stopLoss;
    /** SL_MODIFY_RESULTでbrokerから再取得した実SL。 */
    double confirmedStopLoss;
    /** SL_MODIFY_RESULTでSLありなら1、SLなしを正常取得した場合は0。 */
    int isConfirmedStopLossPresent;
    /** SL変更要求・結果のTRAIL_CANDIDATE、INITIAL_RESTOREまたはTRAIL_RESTORE。 */
    string stopLossActionKind;
    /** Event時点のSL設定元。 */
    string stopLossSource;
    /** トレイル非採用理由。採用時はNULL。 */
    string trailSkipReason;
    /** 注文結果retcode。 */
    int retcode;
    /** EA内部の決済理由。 */
    string exitIntentReason;
    /** EA側で正規化した最終決済分類。 */
    string closeReason;
    /** DEAL_REASONまたはorder理由。 */
    string brokerReason;
    /** Recoveryで検出した不整合コード。 */
    string recoveryIssueCode;
    /** 構造不正pendingのclear前Canonical Text。 */
    string quarantinedPendingText;
    /** 補足。通常は空文字。 */
    string message;

    /**
     * 未取得値と有効な0を区別して初期化する。
     */
    H1EaTradeEventEntity() {
        this.reset();
    }

    /**
     * 保存前の未取得状態へ戻す。
     */
    void reset() {
        this.id = 0;
        this.tradeId = 0;
        this.runId = 0;
        this.eventUid = "";
        this.actionUid = "";
        this.sequence = 0;
        this.eventType = "";
        this.eventSource = "EA";
        this.serverTime = 0;
        this.brokerTimeMsc = 0;
        this.recordedAt = 0;
        this.transactionType = -1;
        this.orderTicket = "";
        this.dealTicket = "";
        this.dealScopeKey = "";
        this.positionIdentifier = "";
        this.positionTicket = "";
        this.side = "";
        this.volume = EMPTY_VALUE;
        this.price = 0.0;
        this.h1BarTime = 0;
        this.pivotBarTime = 0;
        this.pivotRate = 0.0;
        this.latestPointBarTime = 0;
        this.previousStopLoss = 0.0;
        this.stopLoss = 0.0;
        this.confirmedStopLoss = 0.0;
        this.isConfirmedStopLossPresent = -1;
        this.stopLossActionKind = "";
        this.stopLossSource = "NONE";
        this.trailSkipReason = "";
        this.retcode = -1;
        this.exitIntentReason = "";
        this.closeReason = "";
        this.brokerReason = "";
        this.recoveryIssueCode = "";
        this.quarantinedPendingText = "";
        this.message = "";
    }
};

#endif
