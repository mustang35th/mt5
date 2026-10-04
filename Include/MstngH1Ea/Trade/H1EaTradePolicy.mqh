#ifndef MSTNGH1EA_TRADE_POLICY_MQH
#define MSTNGH1EA_TRADE_POLICY_MQH

#include <MstngEa\Strategy\H1ZigZagTrailDecision.mqh>
#include <MstngEaCommon\Runtime\EaTradePolicy.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>
#include <MstngH1Ea\Trade\H1EaProtectionPolicy.mqh>

/**
 * H1固有の時間足・保存識別子・トレイル判定・運用ログを維持する。
 */
class H1EaTradePolicy : public IEaTradePolicy {
public:
    /**
     * 再起動時の照合に使う既存H1識別子を設定する。
     */
    static void profile(EaTradeProfile &fromProfile) {
        fromProfile.timeFrame = PERIOD_H1;
        fromProfile.actionUidPrefix = "H1_EA_ACTION_V1|";
        fromProfile.trailEvaluationUidPrefix = "H1_EA_TRAIL_EVALUATION_V1|";
        fromProfile.cancelUidPrefix = "H1_EA_CANCEL_V1|";
        fromProfile.dealAuditUidPrefix = "H1_EA_DEAL_AUDIT_PENDING_V1|";
        fromProfile.recoveryUidPrefix = "H1_EA_RECOVERY_V1|";
        fromProfile.recoverySnapshotPrefix = "H1_EA_RECOVERY_SNAPSHOT_V1";
        fromProfile.pendingMemoryPrefix = "H1_EA_PENDING_MEMORY_V1|db_raw_unavailable=1|";
        fromProfile.entryCommentPrefix = "MstngH1EaV1:";
        fromProfile.closeCommentPrefix = "MstngH1C:";
        fromProfile.trailStopLossSource = "H1_ZIGZAG_TRAIL";
        fromProfile.trailCrossedReason = "H1_ZIGZAG_TRAIL_CROSSED";
        fromProfile.pendingBarField = "pending_stop_loss_h1_bar_time";
        fromProfile.lastAppliedTrailBarField = "last_applied_trail_h1_bar_time";
        fromProfile.lastTrailEvaluatedBarField = "last_trail_evaluated_h1_bar_time";
    }

    /**
     * 従来と同じH1ログを初期化する。
     */
    virtual void initialize(const string fromSymbol, const ulong fromMagic,
            const string fromRunUid) {
        this.operationLogger.initialize(fromSymbol, fromMagic, fromRunUid);
    }

    /**
     * H1確定ZigZagと従来の10pips余白で候補を判定する。
     */
    virtual bool evaluateTrail(PositionSnapshot &fromPosition, Wave *fromWave,
            const double fromPipSize, const double fromTickSize, EaTrailDecision &fromResult) {
        H1ZigZagTrailDecision decision;
        H1ZigZagTrailDecisionResult result;
        bool accepted = decision.evaluate(fromPosition, fromWave, 10.0, fromPipSize, fromTickSize, result);
        fromResult.shouldModify = result.shouldModify;
        fromResult.targetStopLoss = result.targetStopLoss;
        fromResult.pivotRate = result.pivotRate;
        fromResult.pivotBarTime = result.pivotBarTime;
        fromResult.pivotBarIndex = result.pivotBarIndex;
        fromResult.pivotIsPeak = result.pivotIsPeak;
        fromResult.latestBarTime = result.latestBarTime;
        fromResult.skipReason = result.skipReason;
        return accepted;
    }

    /**
     * H1の既存決済理由を維持する。
     */
    virtual string closeReason(const string fromIntent, const string fromStopLossSource,
            const string fromBrokerReason) {
        return H1EaProtectionPolicy::closeReason(fromIntent, fromStopLossSource, fromBrokerReason);
    }

    /**
     * クラス移設後も従来のログ名で記録する。
     */
    virtual void writeLog(const string fromLevel, const string fromMessage) {
        if (fromLevel == "ERROR") {
            this.operationLogger.error("H1EaTradeExecutor", fromMessage);
        } else {
            this.operationLogger.info("H1EaTradeExecutor", fromMessage);
        }
    }

private:
    /** 既存のH1運用ログ。 */
    H1EaOperationLogger operationLogger;
};

#endif
