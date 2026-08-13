import type {
  W1ConfirmationDiagnostics,
  W1ConfirmationMode,
  W1ConfirmationState,
} from "../api/types";

const STATE_DESCRIPTIONS: Record<W1ConfirmationState, string> = {
  NOT_EVALUATED: "旧レコードのためW1確認は未記録",
  NOT_APPLICABLE: "H1以外のためW1確認の対象外",
  OFF: "W1確認は無効",
  UNAVAILABLE: "W1分析結果を取得できない",
  INVALID: "W1分析結果が不正",
  STRONG: "W1分析方向とW1 EMA200がともに一致",
  DIRECTION_ONLY: "W1分析方向は一致、W1 EMA200はNONE",
  EMA_CONFLICT: "W1分析方向は一致、W1 EMA200は明示的に逆方向",
  EMA_ONLY: "W1分析方向は不一致、W1 EMA200だけ一致",
  REJECT_NONE: "W1分析方向は不一致、W1 EMA200はNONE",
  REJECT: "W1分析方向とW1 EMA200がともに不一致",
};

const STATE_SHORT_LABELS: Record<W1ConfirmationState, string> = {
  NOT_EVALUATED: "未記録",
  NOT_APPLICABLE: "対象外",
  OFF: "無効",
  UNAVAILABLE: "取得不可",
  INVALID: "不正",
  STRONG: "両方一致",
  DIRECTION_ONLY: "方向のみ",
  EMA_CONFLICT: "方向一致・EMA逆",
  EMA_ONLY: "EMAのみ",
  REJECT_NONE: "方向不一致・EMAなし",
  REJECT: "両方不一致",
};

const MODE_LABELS: Record<W1ConfirmationMode, string> = {
  OFF: "OFF",
  OBSERVE_ONLY: "記録のみ",
  DIRECTION_OR_EMA200: "OR",
  DIRECTION_AND_EMA200: "AND",
};

function stateVariant(state: W1ConfirmationState): string {
  if (state === "STRONG" || state === "DIRECTION_ONLY") return "good";
  if (
    state === "EMA_CONFLICT"
    || state === "EMA_ONLY"
    || state === "REJECT_NONE"
    || state === "REJECT"
    || state === "UNAVAILABLE"
    || state === "INVALID"
  ) return "warn";
  return "neutral";
}

export function w1ConfirmationModeLabel(mode: W1ConfirmationMode): string {
  return MODE_LABELS[mode] || mode;
}

export function w1ConfirmationStateDescription(state: W1ConfirmationState): string {
  return STATE_DESCRIPTIONS[state] || state;
}

export function W1ConfirmationBadge({
  confirmation,
  compact = false,
}: {
  confirmation: W1ConfirmationDiagnostics;
  compact?: boolean;
}) {
  const legacy = confirmation.is_w1_confirmation_legacy
    || confirmation.w1_confirmation_state === "NOT_EVALUATED";
  const stateText = legacy
    ? "Legacy / 未記録"
    : compact
      ? STATE_SHORT_LABELS[confirmation.w1_confirmation_state]
      : `${confirmation.w1_confirmation_state} / ${STATE_SHORT_LABELS[confirmation.w1_confirmation_state]}`;
  const modeText = legacy ? null : w1ConfirmationModeLabel(confirmation.w1_confirmation_mode);
  const evaluationText = legacy
    ? "ルール評価未記録"
    : confirmation.w1_confirmation_mode === "OBSERVE_ONLY"
      ? `${confirmation.is_w1_confirmation_passed ? "OR評価通過" : "OR評価不通過"}・記録のみのためエントリー制限なし`
      : `ルール評価${confirmation.is_w1_confirmation_passed ? "通過" : "不通過"}`;
  const modeAccessibleText = legacy ? "mode未記録" : `mode ${modeText}`;
  const title = `${confirmation.w1_confirmation_state}、${w1ConfirmationStateDescription(confirmation.w1_confirmation_state)}。${modeAccessibleText}。${evaluationText}`;

  return (
    <span
      aria-label={title}
      className={`badge-row${compact ? " w1-confirmation-badges-compact" : ""}`}
      title={title}
    >
      <span className={`badge ${stateVariant(confirmation.w1_confirmation_state)}`}>
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
