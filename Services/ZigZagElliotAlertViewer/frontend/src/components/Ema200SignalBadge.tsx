interface Ema200SignalSource {
  time_frame_text: string;
  is_ema200_buy: boolean;
  is_ema200_sell: boolean;
}

interface Ema200SignalState {
  label: string;
  description: string;
  variant: "buy" | "sell" | "warn" | "neutral";
}

interface Ema200SignalBadgeProps {
  timeFrame: Ema200SignalSource;
  available?: boolean;
}

function ema200SignalState(
  timeFrame: Ema200SignalSource,
  available: boolean,
): Ema200SignalState {
  if (!available) {
    return {
      label: "EMA200 記録なし",
      description: "EMA200判定 記録なし",
      variant: "neutral",
    };
  }
  if (timeFrame.time_frame_text.toUpperCase() === "MN1") {
    return {
      label: "EMA200 SKIP",
      description: "EMA200判定 対象外。MN1は計算を省略",
      variant: "neutral",
    };
  }
  if (timeFrame.is_ema200_buy && timeFrame.is_ema200_sell) {
    return {
      label: "EMA200 異常",
      description: "EMA200判定 異常。BUYとSELLが同時に記録されています",
      variant: "warn",
    };
  }
  if (timeFrame.is_ema200_buy) {
    return {
      label: "EMA200 ↑ BUY",
      description: "EMA200判定 BUY",
      variant: "buy",
    };
  }
  if (timeFrame.is_ema200_sell) {
    return {
      label: "EMA200 ↓ SELL",
      description: "EMA200判定 SELL",
      variant: "sell",
    };
  }
  return {
    label: "EMA200 NONE",
    description: "EMA200判定 NONE",
    variant: "neutral",
  };
}

export function Ema200SignalBadge({
  timeFrame,
  available = true,
}: Ema200SignalBadgeProps) {
  const state = ema200SignalState(timeFrame, available);
  return (
    <span
      aria-label={state.description}
      className={`badge ${state.variant} observation-ema200-badge`}
      title={state.description}
    >
      {state.label}
    </span>
  );
}
