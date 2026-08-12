export function formatInteger(value: number | null | undefined): string {
  return new Intl.NumberFormat("ja-JP", { maximumFractionDigits: 0 }).format(Number(value || 0));
}

export function formatNumber(value: number | null | undefined, digits = 1): string {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "—";
  }
  return new Intl.NumberFormat("ja-JP", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(Number(value));
}

export function formatSignedNumber(
  value: number | null | undefined,
  digits = 1,
): string {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "—";
  }
  const number = Object.is(Number(value), -0) ? 0 : Number(value);
  const formatted = formatNumber(number, digits);
  return number > 0 ? `+${formatted}` : formatted;
}

export function elliottDirectionSymbol(isUptrend: boolean): "▲" | "▼" {
  return isUptrend ? "▲" : "▼";
}

export function formatElliottDirection(isUptrend: boolean): string {
  return `${elliottDirectionSymbol(isUptrend)} ${isUptrend ? "上昇" : "下降"}`;
}

export function displayValue(value: unknown, fallback = "—"): string {
  if (value === null || value === undefined || value === "") {
    return fallback;
  }
  return String(value);
}

export function sideClass(side: unknown): "buy" | "sell" | "neutral" {
  const normalized = String(side || "").toLowerCase();
  if (normalized === "buy") return "buy";
  if (normalized === "sell") return "sell";
  return "neutral";
}
