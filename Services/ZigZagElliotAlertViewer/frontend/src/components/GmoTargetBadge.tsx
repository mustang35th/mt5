interface GmoTargetBadgeProps {
  isTarget: boolean | null | undefined;
  compact?: boolean;
}

function targetState(isTarget: boolean | null | undefined) {
  if (isTarget === true) {
    return {
      className: "target",
      compactLabel: "GMO",
      label: "GMO取引 対象",
    };
  }
  return {
    className: "unknown",
    compactLabel: "GMO不明",
    label: "GMO取引 不明",
  };
}

export function GmoTargetBadge({ isTarget, compact = false }: GmoTargetBadgeProps) {
  if (isTarget === false) return null;

  const state = targetState(isTarget);
  return (
    <span
      aria-label={state.label}
      className={`gmo-target-badge ${state.className}${compact ? " compact" : ""}`}
      title={state.label}
    >
      {compact ? state.compactLabel : state.label}
    </span>
  );
}
