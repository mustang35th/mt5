#ifndef MSTNGH1EA_RUNTIME_DECISIONBUILDER_MQH
#define MSTNGH1EA_RUNTIME_DECISIONBUILDER_MQH

#include <Mstng\Database\Entity\H1EaDecisionEntity.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * 確定Decisionの監査文字列をDBの列順で作成する。
 */
class H1EaDecisionBuilder {
public:
    /**
     * 識別子・保存時刻を含めず、実際の確定値のHashを設定する。
     */
    static bool seal(H1EaDecisionEntity &fromDecision, const int fromDigits) {
        string text = "H1_EA_DECISION_V1";
        append(text, "decision", fromDecision.decision);
        append(text, "reason_code", fromDecision.reasonCode);
        append(text, "signal_side", fromDecision.signalSide);
        append(text, "is_judge_matched", flag(fromDecision.isJudgeMatched));
        append(text, "signal_count", IntegerToString(fromDecision.signalCount));
        append(text, "entry_count", IntegerToString(fromDecision.entryCount));
        append(text, "is_entry_evaluated", flag(fromDecision.isEntryEvaluated));
        append(text, "is_strategy_entry", flag(fromDecision.isStrategyEntry));
        append(text, "is_signal_consumed", flag(fromDecision.isSignalConsumed));
        append(text, "spread_pips", optionalNumber(fromDecision.spreadPips, 1));
        append(text, "requested_volume", optionalNumber(fromDecision.requestedVolume, 2));
        append(text, "initial_stop_loss", optionalPositive(fromDecision.initialStopLoss, fromDigits));
        append(text, "initial_risk_pips", optionalPositive(fromDecision.initialRiskPips, 1));
        append(text, "max_initial_risk_pips", DoubleToString(fromDecision.maxInitialRiskPips, 1));
        append(text, "mn1_direction", fromDecision.mn1Direction);
        append(text, "w1_direction", fromDecision.w1Direction);
        append(text, "d1_direction", fromDecision.d1Direction);
        append(text, "h4_direction", fromDecision.h4Direction);
        append(text, "h1_direction", fromDecision.h1Direction);
        append(text, "h1_wave_direction", fromDecision.h1WaveDirection);
        append(text, "h1_elliot_label", fromDecision.h1ElliotLabel);
        append(text, "h4_elliot_label", fromDecision.h4ElliotLabel);
        append(text, "is_h1_wave_accepted", flag(fromDecision.isH1WaveAccepted));
        append(text, "is_h4_wave_accepted", flag(fromDecision.isH4WaveAccepted));
        append(text, "h1_gmma_trend_count", optionalInteger(fromDecision.h1GmmaTrendCount));
        append(text, "h1_gmma_cross_count", optionalInteger(fromDecision.h1GmmaCrossCount));
        append(text, "h1_ema200_direction", fromDecision.h1Ema200Direction);
        append(text, "h4_ema200_direction", fromDecision.h4Ema200Direction);
        append(text, "w1_ema200_direction", fromDecision.w1Ema200Direction);
        append(text, "h1_direction_alignment_mode", fromDecision.h1DirectionAlignmentMode);
        append(text, "is_h1_direction_alignment_passed", flag(fromDecision.isH1DirectionAlignmentPassed));
        fromDecision.analysisSnapshotText = text;
        append(text, "analysis_version", ZigZagElliotAnalysisProfile::getAnalysisVersion());
        append(text, "analysis_input_hash", ZigZagElliotAnalysisProfile::createHash());
        fromDecision.snapshotHash = H1EaTextUtil::hash(text);
        return StringLen(fromDecision.snapshotHash) == 64;
    }

private:
    /**
     * 未取得文字列を~として追加する。
     */
    static void append(string &fromText, const string fromName, const string fromValue) {
        string value = fromValue;
        if (value == "") {
            value = "~";
        }
        fromText += "|" + fromName + "=" + value;
    }

    /**
     * 真偽値の固定表記。
     */
    static string flag(const bool fromValue) {
        if (fromValue) {
            return "1";
        }
        return "0";
    }

    /**
     * 未取得数値と有効な0を区別する。
     */
    static string optionalNumber(const double fromValue, const int fromDigits) {
        if (fromValue == EMPTY_VALUE || !MathIsValidNumber(fromValue)) {
            return "~";
        }
        return DoubleToString(fromValue, fromDigits);
    }

    /**
     * 任意正値のNULLを表現する。
     */
    static string optionalPositive(const double fromValue, const int fromDigits) {
        if (fromValue <= 0.0) {
            return "~";
        }
        return optionalNumber(fromValue, fromDigits);
    }

    /**
     * 負値を含むGMMA countのNULLを区別する。
     */
    static string optionalInteger(const int fromValue) {
        if (fromValue == INT_MIN) {
            return "~";
        }
        return IntegerToString(fromValue);
    }
};

#endif
