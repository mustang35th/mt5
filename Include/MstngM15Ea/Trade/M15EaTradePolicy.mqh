#ifndef MSTNGM15EA_TRADE_POLICY_MQH
#define MSTNGM15EA_TRADE_POLICY_MQH

#include <MstngEaCommon\Runtime\EaTradePolicy.mqh>
#include <MstngEaCommon\Runtime\EaZigZagTrailDecision.mqh>
#include <MstngM15Ea\Runtime\M15EaOperationLogger.mqh>

/**
 * M15固有の時間足・保存識別子・トレイル判定・運用ログを維持する。
 */
class M15EaTradePolicy : public IEaTradePolicy {
public:
    /**
     * 再起動時の照合に使うM15専用識別子を設定する。
     */
    static void profile(EaTradeProfile &fromProfile) {
        fromProfile.timeFrame = PERIOD_M15;
        fromProfile.actionUidPrefix = "M15_EA_ACTION_V1|";
        fromProfile.trailEvaluationUidPrefix = "M15_EA_TRAIL_EVALUATION_V1|";
        fromProfile.cancelUidPrefix = "M15_EA_CANCEL_V1|";
        fromProfile.dealAuditUidPrefix = "M15_EA_DEAL_AUDIT_PENDING_V1|";
        fromProfile.recoveryUidPrefix = "M15_EA_RECOVERY_V1|";
        fromProfile.recoverySnapshotPrefix = "M15_EA_RECOVERY_SNAPSHOT_V1";
        fromProfile.pendingMemoryPrefix = "M15_EA_PENDING_MEMORY_V1|db_raw_unavailable=1|";
        fromProfile.entryCommentPrefix = "MstngM15EaV1:";
        fromProfile.closeCommentPrefix = "MstngM15C:";
        fromProfile.trailStopLossSource = "M15_ZIGZAG_TRAIL";
        fromProfile.trailCrossedReason = "M15_ZIGZAG_TRAIL_CROSSED";
        fromProfile.pendingBarField = "pending_stop_loss_bar_time";
        fromProfile.lastAppliedTrailBarField = "last_applied_trail_bar_time";
        fromProfile.lastTrailEvaluatedBarField = "last_trail_evaluated_bar_time";
    }

    /**
     * M15専用の運用ログを初期化する。
     */
    virtual void initialize(const string fromSymbol, const ulong fromMagic,
            const string fromRunUid) {
        this.operationLogger.initialize(fromSymbol, fromMagic, fromRunUid);
    }

    /**
     * M15確定ZigZagと10pips余白で候補を判定する。
     */
    virtual bool evaluateTrail(PositionSnapshot &fromPosition, Wave *fromWave,
            const double fromPipSize, const double fromTickSize, EaTrailDecision &fromResult) {
        EaZigZagTrailDecision decision;

        return decision.evaluate(fromPosition, fromWave, PERIOD_M15,
            10.0, fromPipSize, fromTickSize, fromResult);
    }

    /**
     * broker理由とM15の内部意図を分離した決済分類を返す。
     */
    virtual string closeReason(const string fromIntent, const string fromStopLossSource,
            const string fromBrokerReason) {
        if (fromIntent == "INITIAL_STOP_LOSS_CROSSED" || fromIntent == "M15_ZIGZAG_TRAIL_CROSSED") {
            return fromIntent;
        }

        if (fromBrokerReason == "SL") {
            if (fromStopLossSource == "INITIAL_STOP_LOSS" || fromStopLossSource == "M15_ZIGZAG_TRAIL") {
                return fromStopLossSource;
            }

            if (fromStopLossSource == "EXTERNAL") {
                return "EXTERNAL_STOP_LOSS";
            }

            return "UNKNOWN_STOP_LOSS";
        }

        if (fromBrokerReason == "CLIENT" || fromBrokerReason == "MOBILE"
                || fromBrokerReason == "WEB") {
            return "EXTERNAL_CLOSE";
        }

        return "UNKNOWN_CLOSE";
    }

    /**
     * M15専用のログ名で記録する。
     */
    virtual void writeLog(const string fromLevel, const string fromMessage) {
        if (fromLevel == "ERROR") {
            this.operationLogger.error("M15EaTradeExecutor", fromMessage);
        } else {
            this.operationLogger.info("M15EaTradeExecutor", fromMessage);
        }
    }

private:
    /** M15専用の運用ログ。 */
    M15EaOperationLogger operationLogger;
};

#endif
