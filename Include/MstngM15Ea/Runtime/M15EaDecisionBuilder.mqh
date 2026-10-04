#ifndef MSTNGM15EA_RUNTIME_DECISIONBUILDER_MQH
#define MSTNGM15EA_RUNTIME_DECISIONBUILDER_MQH

#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <MstngEaCommon\Runtime\EaTextUtil.mqh>
#include <MstngM15Ea\Persistence\M15EaDecisionEntity.mqh>

/**
 * M15の確定判定と採用分析を、長さ付きの監査文字列へ固定する。
 */
class M15EaDecisionBuilder {
public:
    /**
     * 元の分析診断から毎回組み立て、SKIPへの変更時も二重追加しない。
     * @param fromDiagnostics Strategyが返した元分析・採用分析の診断。
     */
    static bool seal(M15EaDecisionEntity &fromDecision, const int fromDigits,
            const string fromDiagnostics) {
        string text = "M15_EA_DECISION_V1";
        EaTextUtil::appendField(text, "bar_time", IntegerToString(fromDecision.barTime));
        EaTextUtil::appendField(text, "signal_reference_time", IntegerToString(fromDecision.signalReferenceTime));
        EaTextUtil::appendField(text, "signal_side", fromDecision.signalSide);
        EaTextUtil::appendField(text, "decision", fromDecision.decision);
        EaTextUtil::appendField(text, "reason_code", fromDecision.reasonCode);
        EaTextUtil::appendField(text, "is_judge_matched", flag(fromDecision.isJudgeMatched));
        EaTextUtil::appendField(text, "signal_count", IntegerToString(fromDecision.signalCount));
        EaTextUtil::appendField(text, "entry_count", IntegerToString(fromDecision.entryCount));
        EaTextUtil::appendField(text, "is_entry_evaluated", flag(fromDecision.isEntryEvaluated));
        EaTextUtil::appendField(text, "is_strategy_entry", flag(fromDecision.isStrategyEntry));
        EaTextUtil::appendField(text, "is_signal_consumed", flag(fromDecision.isSignalConsumed));
        EaTextUtil::appendField(text, "spread_pips", number(fromDecision.spreadPips, 1));
        EaTextUtil::appendField(text, "requested_volume", number(fromDecision.requestedVolume, 8));
        EaTextUtil::appendField(text, "initial_stop_loss", number(fromDecision.initialStopLoss, fromDigits));
        EaTextUtil::appendField(text, "initial_risk_pips", number(fromDecision.initialRiskPips, 8));
        EaTextUtil::appendField(text, "max_initial_risk_pips", number(fromDecision.maxInitialRiskPips, 1));
        EaTextUtil::appendField(text, "strategy_snapshot", fromDiagnostics);
        EaTextUtil::appendField(text, "analysis_version", ZigZagElliotAnalysisProfile::getAnalysisVersion());
        EaTextUtil::appendField(text, "analysis_input_hash", ZigZagElliotAnalysisProfile::createHash());
        fromDecision.analysisSnapshotText = text;
        fromDecision.snapshotHash = EaTextUtil::hash(text);
        return StringLen(fromDecision.snapshotHash) == 64;
    }

private:
    /**
     * 真偽値を固定表記にする。
     */
    static string flag(const bool fromValue) {
        if (fromValue) {
            return "1";
        }
        return "0";
    }

    /**
     * 未取得値と有効な0を区別する。
     */
    static string number(const double fromValue, const int fromDigits) {
        if (fromValue == EMPTY_VALUE || !MathIsValidNumber(fromValue)) {
            return "~";
        }
        return DoubleToString(fromValue, fromDigits);
    }
};

#endif
