#ifndef MSTNGH1EA_TRADE_H1EATRADESTATEMAPPER_MQH
#define MSTNGH1EA_TRADE_H1EATRADESTATEMAPPER_MQH

#include <Mstng\Database\Entity\H1EaTradeEntity.mqh>
#include <Mstng\Database\Entity\H1EaTradeEventEntity.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTradeEvent.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTradeState.mqh>

/**
 * H1保存形式と共通の取引状態・イベントを全項目で相互変換する。
 * 時間足を表す項目名だけを変え、未取得値と保存済み識別子を保持する。
 */
class H1EaTradeStateMapper {
public:
    /**
     * H1の取引状態を共通形式へ変換する。
     */
    static void toCommon(const H1EaTradeEntity &fromSource, EaTradeState &fromTarget) {
        fromTarget.id = fromSource.id;
        fromTarget.createdRunId = fromSource.createdRunId;
        fromTarget.decisionId = fromSource.decisionId;
        fromTarget.contextKey = fromSource.contextKey;
        fromTarget.origin = fromSource.origin;
        fromTarget.status = fromSource.status;
        fromTarget.side = fromSource.side;
        fromTarget.requestedVolume = fromSource.requestedVolume;
        fromTarget.requestedStopLoss = fromSource.requestedStopLoss;
        fromTarget.entryRequestedServerTime = fromSource.entryRequestedServerTime;
        fromTarget.entryOrderTicket = fromSource.entryOrderTicket;
        fromTarget.entryDealTicket = fromSource.entryDealTicket;
        fromTarget.entryRetcode = fromSource.entryRetcode;
        fromTarget.positionIdentifier = fromSource.positionIdentifier;
        fromTarget.positionTicket = fromSource.positionTicket;
        fromTarget.openedAtMsc = fromSource.openedAtMsc;
        fromTarget.openPrice = fromSource.openPrice;
        fromTarget.openedVolume = fromSource.openedVolume;
        fromTarget.remainingEntryVolume = fromSource.remainingEntryVolume;
        fromTarget.currentStopLoss = fromSource.currentStopLoss;
        fromTarget.stopLossSource = fromSource.stopLossSource;
        fromTarget.lastTrailEvaluatedBarTime = fromSource.lastTrailEvaluatedH1BarTime;
        fromTarget.pendingStopLossKind = fromSource.pendingStopLossKind;
        fromTarget.pendingStopLossBarTime = fromSource.pendingStopLossH1BarTime;
        fromTarget.pendingStopLoss = fromSource.pendingStopLoss;
        fromTarget.pendingStopLossPivotTime = fromSource.pendingStopLossPivotTime;
        fromTarget.pendingStopLossPivotRate = fromSource.pendingStopLossPivotRate;
        fromTarget.pendingStopLossLatestTime = fromSource.pendingStopLossLatestTime;
        fromTarget.pendingStopLossActionUid = fromSource.pendingStopLossActionUid;
        fromTarget.lastAppliedTrailBarTime = fromSource.lastAppliedTrailH1BarTime;
        fromTarget.lastAppliedTrailStopLoss = fromSource.lastAppliedTrailStopLoss;
        fromTarget.lastAppliedTrailPivotTime = fromSource.lastAppliedTrailPivotTime;
        fromTarget.lastAppliedTrailPivotRate = fromSource.lastAppliedTrailPivotRate;
        fromTarget.lastAppliedTrailLatestTime = fromSource.lastAppliedTrailLatestTime;
        fromTarget.exitRequestedServerTime = fromSource.exitRequestedServerTime;
        fromTarget.exitOrderTicket = fromSource.exitOrderTicket;
        fromTarget.exitDealTicket = fromSource.exitDealTicket;
        fromTarget.exitRetcode = fromSource.exitRetcode;
        fromTarget.closedAtMsc = fromSource.closedAtMsc;
        fromTarget.closePrice = fromSource.closePrice;
        fromTarget.remainingPositionVolume = fromSource.remainingPositionVolume;
        fromTarget.exitIntentReason = fromSource.exitIntentReason;
        fromTarget.closeReason = fromSource.closeReason;
        fromTarget.brokerCloseReason = fromSource.brokerCloseReason;
        fromTarget.profit = fromSource.profit;
        fromTarget.commission = fromSource.commission;
        fromTarget.swap = fromSource.swap;
        fromTarget.fee = fromSource.fee;
        fromTarget.lastError = fromSource.lastError;
        fromTarget.createdAt = fromSource.createdAt;
        fromTarget.updatedAt = fromSource.updatedAt;
    }

    /**
     * 共通の取引状態を既存H1保存形式へ変換する。
     */
    static void toH1(const EaTradeState &fromSource, H1EaTradeEntity &fromTarget) {
        fromTarget.id = fromSource.id;
        fromTarget.createdRunId = fromSource.createdRunId;
        fromTarget.decisionId = fromSource.decisionId;
        fromTarget.contextKey = fromSource.contextKey;
        fromTarget.origin = fromSource.origin;
        fromTarget.status = fromSource.status;
        fromTarget.side = fromSource.side;
        fromTarget.requestedVolume = fromSource.requestedVolume;
        fromTarget.requestedStopLoss = fromSource.requestedStopLoss;
        fromTarget.entryRequestedServerTime = fromSource.entryRequestedServerTime;
        fromTarget.entryOrderTicket = fromSource.entryOrderTicket;
        fromTarget.entryDealTicket = fromSource.entryDealTicket;
        fromTarget.entryRetcode = fromSource.entryRetcode;
        fromTarget.positionIdentifier = fromSource.positionIdentifier;
        fromTarget.positionTicket = fromSource.positionTicket;
        fromTarget.openedAtMsc = fromSource.openedAtMsc;
        fromTarget.openPrice = fromSource.openPrice;
        fromTarget.openedVolume = fromSource.openedVolume;
        fromTarget.remainingEntryVolume = fromSource.remainingEntryVolume;
        fromTarget.currentStopLoss = fromSource.currentStopLoss;
        fromTarget.stopLossSource = fromSource.stopLossSource;
        fromTarget.lastTrailEvaluatedH1BarTime = fromSource.lastTrailEvaluatedBarTime;
        fromTarget.pendingStopLossKind = fromSource.pendingStopLossKind;
        fromTarget.pendingStopLossH1BarTime = fromSource.pendingStopLossBarTime;
        fromTarget.pendingStopLoss = fromSource.pendingStopLoss;
        fromTarget.pendingStopLossPivotTime = fromSource.pendingStopLossPivotTime;
        fromTarget.pendingStopLossPivotRate = fromSource.pendingStopLossPivotRate;
        fromTarget.pendingStopLossLatestTime = fromSource.pendingStopLossLatestTime;
        fromTarget.pendingStopLossActionUid = fromSource.pendingStopLossActionUid;
        fromTarget.lastAppliedTrailH1BarTime = fromSource.lastAppliedTrailBarTime;
        fromTarget.lastAppliedTrailStopLoss = fromSource.lastAppliedTrailStopLoss;
        fromTarget.lastAppliedTrailPivotTime = fromSource.lastAppliedTrailPivotTime;
        fromTarget.lastAppliedTrailPivotRate = fromSource.lastAppliedTrailPivotRate;
        fromTarget.lastAppliedTrailLatestTime = fromSource.lastAppliedTrailLatestTime;
        fromTarget.exitRequestedServerTime = fromSource.exitRequestedServerTime;
        fromTarget.exitOrderTicket = fromSource.exitOrderTicket;
        fromTarget.exitDealTicket = fromSource.exitDealTicket;
        fromTarget.exitRetcode = fromSource.exitRetcode;
        fromTarget.closedAtMsc = fromSource.closedAtMsc;
        fromTarget.closePrice = fromSource.closePrice;
        fromTarget.remainingPositionVolume = fromSource.remainingPositionVolume;
        fromTarget.exitIntentReason = fromSource.exitIntentReason;
        fromTarget.closeReason = fromSource.closeReason;
        fromTarget.brokerCloseReason = fromSource.brokerCloseReason;
        fromTarget.profit = fromSource.profit;
        fromTarget.commission = fromSource.commission;
        fromTarget.swap = fromSource.swap;
        fromTarget.fee = fromSource.fee;
        fromTarget.lastError = fromSource.lastError;
        fromTarget.createdAt = fromSource.createdAt;
        fromTarget.updatedAt = fromSource.updatedAt;
    }

    /**
     * H1の取引イベントを共通形式へ変換する。
     */
    static void toCommon(const H1EaTradeEventEntity &fromSource, EaTradeEvent &fromTarget) {
        fromTarget.id = fromSource.id;
        fromTarget.tradeId = fromSource.tradeId;
        fromTarget.runId = fromSource.runId;
        fromTarget.eventUid = fromSource.eventUid;
        fromTarget.actionUid = fromSource.actionUid;
        fromTarget.sequence = fromSource.sequence;
        fromTarget.eventType = fromSource.eventType;
        fromTarget.eventSource = fromSource.eventSource;
        fromTarget.serverTime = fromSource.serverTime;
        fromTarget.brokerTimeMsc = fromSource.brokerTimeMsc;
        fromTarget.recordedAt = fromSource.recordedAt;
        fromTarget.transactionType = fromSource.transactionType;
        fromTarget.orderTicket = fromSource.orderTicket;
        fromTarget.dealTicket = fromSource.dealTicket;
        fromTarget.dealScopeKey = fromSource.dealScopeKey;
        fromTarget.positionIdentifier = fromSource.positionIdentifier;
        fromTarget.positionTicket = fromSource.positionTicket;
        fromTarget.side = fromSource.side;
        fromTarget.volume = fromSource.volume;
        fromTarget.price = fromSource.price;
        fromTarget.barTime = fromSource.h1BarTime;
        fromTarget.pivotBarTime = fromSource.pivotBarTime;
        fromTarget.pivotRate = fromSource.pivotRate;
        fromTarget.latestPointBarTime = fromSource.latestPointBarTime;
        fromTarget.previousStopLoss = fromSource.previousStopLoss;
        fromTarget.stopLoss = fromSource.stopLoss;
        fromTarget.confirmedStopLoss = fromSource.confirmedStopLoss;
        fromTarget.isConfirmedStopLossPresent = fromSource.isConfirmedStopLossPresent;
        fromTarget.stopLossActionKind = fromSource.stopLossActionKind;
        fromTarget.stopLossSource = fromSource.stopLossSource;
        fromTarget.trailSkipReason = fromSource.trailSkipReason;
        fromTarget.retcode = fromSource.retcode;
        fromTarget.exitIntentReason = fromSource.exitIntentReason;
        fromTarget.closeReason = fromSource.closeReason;
        fromTarget.brokerReason = fromSource.brokerReason;
        fromTarget.recoveryIssueCode = fromSource.recoveryIssueCode;
        fromTarget.quarantinedPendingText = fromSource.quarantinedPendingText;
        fromTarget.message = fromSource.message;
    }

    /**
     * 共通の取引イベントを既存H1保存形式へ変換する。
     */
    static void toH1(const EaTradeEvent &fromSource, H1EaTradeEventEntity &fromTarget) {
        fromTarget.id = fromSource.id;
        fromTarget.tradeId = fromSource.tradeId;
        fromTarget.runId = fromSource.runId;
        fromTarget.eventUid = fromSource.eventUid;
        fromTarget.actionUid = fromSource.actionUid;
        fromTarget.sequence = fromSource.sequence;
        fromTarget.eventType = fromSource.eventType;
        fromTarget.eventSource = fromSource.eventSource;
        fromTarget.serverTime = fromSource.serverTime;
        fromTarget.brokerTimeMsc = fromSource.brokerTimeMsc;
        fromTarget.recordedAt = fromSource.recordedAt;
        fromTarget.transactionType = fromSource.transactionType;
        fromTarget.orderTicket = fromSource.orderTicket;
        fromTarget.dealTicket = fromSource.dealTicket;
        fromTarget.dealScopeKey = fromSource.dealScopeKey;
        fromTarget.positionIdentifier = fromSource.positionIdentifier;
        fromTarget.positionTicket = fromSource.positionTicket;
        fromTarget.side = fromSource.side;
        fromTarget.volume = fromSource.volume;
        fromTarget.price = fromSource.price;
        fromTarget.h1BarTime = fromSource.barTime;
        fromTarget.pivotBarTime = fromSource.pivotBarTime;
        fromTarget.pivotRate = fromSource.pivotRate;
        fromTarget.latestPointBarTime = fromSource.latestPointBarTime;
        fromTarget.previousStopLoss = fromSource.previousStopLoss;
        fromTarget.stopLoss = fromSource.stopLoss;
        fromTarget.confirmedStopLoss = fromSource.confirmedStopLoss;
        fromTarget.isConfirmedStopLossPresent = fromSource.isConfirmedStopLossPresent;
        fromTarget.stopLossActionKind = fromSource.stopLossActionKind;
        fromTarget.stopLossSource = fromSource.stopLossSource;
        fromTarget.trailSkipReason = fromSource.trailSkipReason;
        fromTarget.retcode = fromSource.retcode;
        fromTarget.exitIntentReason = fromSource.exitIntentReason;
        fromTarget.closeReason = fromSource.closeReason;
        fromTarget.brokerReason = fromSource.brokerReason;
        fromTarget.recoveryIssueCode = fromSource.recoveryIssueCode;
        fromTarget.quarantinedPendingText = fromSource.quarantinedPendingText;
        fromTarget.message = fromSource.message;
    }

};

#endif
