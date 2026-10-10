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

/**
 * Format a saved wall-clock value without applying the browser's time zone.
 */
function formatSavedWallClock(fromMilliseconds: number): string | null {
  const date = new Date(fromMilliseconds);
  const year = date.getUTCFullYear();
  if (!Number.isFinite(date.getTime()) || year < 1 || year > 9999) {
    return null;
  }

  return date.toISOString().slice(0, 19).replaceAll("-", ".").replace("T", " ");
}

/**
 * Parse the saved MQL date format and reject normalized, nonexistent dates.
 */
function parseSavedWallClock(fromValue: string): number | null {
  if (!/^\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}$/.test(fromValue)) {
    return null;
  }

  const milliseconds = Date.parse(`${fromValue.replaceAll(".", "-").replace(" ", "T")}Z`);
  if (formatSavedWallClock(milliseconds) !== fromValue) {
    return null;
  }

  return milliseconds;
}

/**
 * Convert the alert's bar start using its saved server-to-JST offset.
 * The judgment time supplies only the offset; its seconds do not replace the bar start.
 * Preserve a valid saved server bar time even when JST cannot be derived.
 */
export function formatAlertBarTimes(
  fromCurrentBarTime: string,
  fromServerTime: string,
  fromJstTime: string,
): { jst: string; server: string } {
  const barTime = parseSavedWallClock(fromCurrentBarTime);
  if (barTime === null) {
    return { jst: "未記録", server: "未記録" };
  }

  const server = fromCurrentBarTime;
  const unavailable = { jst: "未記録", server };
  const serverTime = parseSavedWallClock(fromServerTime);
  const jstTime = parseSavedWallClock(fromJstTime);
  if (serverTime === null || jstTime === null) {
    return unavailable;
  }

  const jstOffset = jstTime - serverTime;
  if (Math.abs(jstOffset) > 24 * 60 * 60 * 1000) {
    return unavailable;
  }

  const barJst = barTime + jstOffset;
  const jst = formatSavedWallClock(barJst);
  if (jst === null) {
    return unavailable;
  }

  return { jst, server };
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
