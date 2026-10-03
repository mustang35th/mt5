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

/** Return the saved pre-recount label only when the main label changed. */
export function elliottOriginalSuffix(mainLabel: unknown, originalLabel: unknown): string {
  if (typeof mainLabel !== "string" || typeof originalLabel !== "string") return "";
  const main = mainLabel.trim();
  const original = originalLabel.trim();
  if (!main || !original || main === original) return "";
  return `[${original}]`;
}

/** Format saved observation labels without inferring missing original values. */
export function formatElliottLabel(
  mainLabel: unknown,
  subLabel: unknown,
  originalLabel: unknown,
  fallback = "—",
): string {
  const main = (typeof mainLabel === "string" ? mainLabel.trim() : "") || fallback;
  const sub = typeof subLabel === "string" ? subLabel.trim() : "";
  return `${main}${sub ? `.${sub}` : ""}${elliottOriginalSuffix(mainLabel, originalLabel)}`;
}

export function sideClass(side: unknown): "buy" | "sell" | "neutral" {
  const normalized = String(side || "").toLowerCase();
  if (normalized === "buy") return "buy";
  if (normalized === "sell") return "sell";
  return "neutral";
}
