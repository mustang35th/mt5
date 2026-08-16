import type {
  H1DirectionAlignmentDiagnostics,
  H1DirectionAlignmentMode,
  H1DirectionAlignmentState,
} from "../api/types";

const STATE_DESCRIPTIONS: Record<H1DirectionAlignmentState, string> = {
  NOT_EVALUATED: "旧レコードのためH1方向一致は未記録",
  NOT_APPLICABLE: "H1以外のため方向一致の対象外",
  D1_TO_H1: "現行のD1・H4・H1一致を使用",
  FULL_BUY: "MN1からH1まですべてBUY",
  FULL_SELL: "MN1からH1まですべてSELL",
  MN1_MISMATCH: "MN1だけH1方向と不一致",
  W1_MISMATCH: "W1だけH1方向と不一致",
  MN1_W1_MISMATCH: "MN1とW1がH1方向と不一致",
  UNAVAILABLE: "必要な時間足の分析結果を取得できない",
  INVALID: "方向一致の分析結果または設定が不正",
};

const STATE_SHORT_LABELS: Record<H1DirectionAlignmentState, string> = {
  NOT_EVALUATED: "未記録",
  NOT_APPLICABLE: "対象外",
  D1_TO_H1: "D1～H1",
  FULL_BUY: "全足BUY",
  FULL_SELL: "全足SELL",
  MN1_MISMATCH: "MN1不一致",
  W1_MISMATCH: "W1不一致",
  MN1_W1_MISMATCH: "MN1・W1不一致",
  UNAVAILABLE: "取得不可",
  INVALID: "不正",
};

const MODE_LABELS: Record<H1DirectionAlignmentMode, string> = {
  D1_TO_H1: "D1～H1",
  MN1_TO_H1_OBSERVE: "MN1～H1・記録のみ",
  MN1_TO_H1_REQUIRED: "MN1～H1・必須",
  INVALID: "不正",
};

function stateVariant(state: H1DirectionAlignmentState): string {
  if (state === "FULL_BUY" || state === "FULL_SELL" || state === "D1_TO_H1") {
    return "good";
  }
  if (
    state === "MN1_MISMATCH"
    || state === "W1_MISMATCH"
    || state === "MN1_W1_MISMATCH"
    || state === "UNAVAILABLE"
    || state === "INVALID"
  ) {
    return "warn";
  }
  return "neutral";
}

export function h1DirectionAlignmentModeLabel(
  mode: H1DirectionAlignmentMode,
): string {
  return MODE_LABELS[mode] || mode;
}

export function h1DirectionAlignmentStateDescription(
  state: H1DirectionAlignmentState,
): string {
  return STATE_DESCRIPTIONS[state] || state;
}

function observeEvaluationText(
  alignment: H1DirectionAlignmentDiagnostics,
): string {
  if (alignment.h1_direction_alignment_state === "UNAVAILABLE") {
    return "取得不可・記録のみのためエントリー制限なし";
  }
  if (alignment.h1_direction_alignment_state === "INVALID") {
    return "不正・記録のみのためエントリー制限なし";
  }
  return `${alignment.is_h1_direction_alignment_passed ? "全足一致" : "全足不一致"}・記録のみのためエントリー制限なし`;
}

export function H1DirectionAlignmentBadge({
  alignment,
  compact = false,
}: {
  alignment: H1DirectionAlignmentDiagnostics;
  compact?: boolean;
}) {
  const legacy = alignment.is_h1_direction_alignment_legacy
    || alignment.h1_direction_alignment_state === "NOT_EVALUATED";
  const stateText = legacy
    ? "Legacy / 未記録"
    : compact
      ? STATE_SHORT_LABELS[alignment.h1_direction_alignment_state]
      : `${alignment.h1_direction_alignment_state} / ${STATE_SHORT_LABELS[alignment.h1_direction_alignment_state]}`;
  const modeText = legacy
    ? null
    : h1DirectionAlignmentModeLabel(alignment.h1_direction_alignment_mode);
  const evaluationText = legacy
    ? "ルール評価未記録"
    : alignment.h1_direction_alignment_state === "NOT_APPLICABLE"
      ? "H1以外のためルール評価対象外"
    : alignment.h1_direction_alignment_mode === "MN1_TO_H1_OBSERVE"
      ? observeEvaluationText(alignment)
      : `ルール評価${alignment.is_h1_direction_alignment_passed ? "通過" : "不通過"}`;
  const modeAccessibleText = legacy ? "mode未記録" : `mode ${modeText}`;
  const title = `${alignment.h1_direction_alignment_state}、${h1DirectionAlignmentStateDescription(alignment.h1_direction_alignment_state)}。${modeAccessibleText}。${evaluationText}`;

  return (
    <span
      aria-label={title}
      className={`badge-row${compact ? " h1-direction-alignment-badges-compact" : ""}`}
      title={title}
    >
      <span className={`badge ${stateVariant(alignment.h1_direction_alignment_state)}`}>
        {stateText}
      </span>
      {modeText && (
        <span className="badge neutral">
          {compact ? modeText : `mode: ${modeText}`}
        </span>
      )}
    </span>
  );
}
