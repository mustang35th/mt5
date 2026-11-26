#ifndef MSTNGM5EA_TRADE_POLICY_MQH
#define MSTNGM5EA_TRADE_POLICY_MQH

#include <MstngEaCommon\Runtime\EaTradePolicy.mqh>
#include <MstngEaCommon\Runtime\EaZigZagTrailDecision.mqh>
#include <MstngM5Ea\Runtime\M5EaOperationLogger.mqh>

/**
 * M5固有の時間足・保存識別子・トレイル判定・運用ログを維持する。
 */
class M5EaTradePolicy : public IEaTradePolicy {
public:
    /**
     * 既存EAと同じ10pips余白で初期化する。
     */
    M5EaTradePolicy() {
        this.trailStopLossBufferPips = 10.0;
    }

    /**
     * Configで検証済みのトレイル余白を設定する。
     */
    void setTrailStopLossBufferPips(const double fromBufferPips) {
        this.trailStopLossBufferPips = fromBufferPips;
    }

    /**
     * 再起動時の照合に使うM5専用識別子を設定する。
     */
    static void profile(EaTradeProfile &fromProfile) {
        fromProfile.timeFrame = PERIOD_M5;
        fromProfile.actionUidPrefix = "M5_EA_ACTION_V1|";
        fromProfile.trailEvaluationUidPrefix = "M5_EA_TRAIL_EVALUATION_V1|";
        fromProfile.cancelUidPrefix = "M5_EA_CANCEL_V1|";
        fromProfile.dealAuditUidPrefix = "M5_EA_DEAL_AUDIT_PENDING_V1|";
        fromProfile.recoveryUidPrefix = "M5_EA_RECOVERY_V1|";
        fromProfile.recoverySnapshotPrefix = "M5_EA_RECOVERY_SNAPSHOT_V1";
        fromProfile.pendingMemoryPrefix = "M5_EA_PENDING_MEMORY_V1|db_raw_unavailable=1|";
        fromProfile.entryCommentPrefix = "MstngM5EaV1:";
        fromProfile.closeCommentPrefix = "MstngM5C:";
        fromProfile.trailStopLossSource = "M5_ZIGZAG_TRAIL";
        fromProfile.trailCrossedReason = "M5_ZIGZAG_TRAIL_CROSSED";
        fromProfile.pendingBarField = "pending_stop_loss_bar_time";
        fromProfile.lastAppliedTrailBarField = "last_applied_trail_bar_time";
        fromProfile.lastTrailEvaluatedBarField = "last_trail_evaluated_bar_time";
    }

    /**
     * M5専用の運用ログを初期化する。
     */
    virtual void initialize(const string fromSymbol, const ulong fromMagic,
            const string fromRunUid) {
        this.operationLogger.initialize(fromSymbol, fromMagic, fromRunUid);
    }

    /**
     * M5確定ZigZagと設定した余白で候補を判定する。
     */
    virtual bool evaluateTrail(PositionSnapshot &fromPosition, Wave *fromWave,
            const double fromPipSize, const double fromTickSize, EaTrailDecision &fromResult) {
        EaZigZagTrailDecision decision;

        return decision.evaluate(fromPosition, fromWave, PERIOD_M5,
            this.trailStopLossBufferPips, fromPipSize, fromTickSize, fromResult);
    }

    /**
     * broker理由とM5の内部意図を分離した決済分類を返す。
     */
    virtual string closeReason(const string fromIntent, const string fromStopLossSource,
            const string fromBrokerReason) {
        if (fromIntent == "INITIAL_STOP_LOSS_CROSSED" || fromIntent == "M5_ZIGZAG_TRAIL_CROSSED") {
            return fromIntent;
        }

        if (fromBrokerReason == "SL") {
            if (fromStopLossSource == "INITIAL_STOP_LOSS" || fromStopLossSource == "M5_ZIGZAG_TRAIL") {
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
     * M5専用のログ名で記録する。
     */
    virtual void writeLog(const string fromLevel, const string fromMessage) {
        if (fromLevel == "ERROR") {
            this.operationLogger.error("M5EaTradeExecutor", fromMessage);
        } else {
            this.operationLogger.info("M5EaTradeExecutor", fromMessage);
        }
    }

private:
    /** 確定スイングからのトレイル余白。 */
    double trailStopLossBufferPips;

    /** M5専用の運用ログ。 */
    M5EaOperationLogger operationLogger;
};

#endif
