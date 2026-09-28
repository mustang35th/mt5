import type { EaValue } from "../api/eaTypes";

/** MT5 server timestamps encode broker calendar fields; do not convert them to the browser timezone. */
export function eaTime(value: number | null | undefined, milliseconds = false): string {
  if (value === null || value === undefined || !Number.isFinite(value) || value <= 0) return "未記録";
  const date = new Date(milliseconds ? value : value * 1000);
  if (!Number.isFinite(date.getTime())) return "未記録";
  return date.toISOString().slice(0, 19).replace("T", " ").replaceAll("-", "/");
}

export function eaNumber(value: number | null | undefined, digits = 2, plus = false): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return `${plus && value > 0 ? "+" : ""}${value.toLocaleString("ja-JP", { maximumFractionDigits: digits })}`;
}

export function eaMoney(value: number | null | undefined, currency: string | null, plus = false): string {
  let digits = 2;
  if (currency && /^[A-Z]{3}$/.test(currency)) {
    try { digits = new Intl.NumberFormat("ja-JP", { style: "currency", currency }).resolvedOptions().maximumFractionDigits ?? 2; } catch { /* Unknown currency: keep precision. */ }
  }
  return eaNumber(value, digits, plus);
}

export function eaValue(value: EaValue | undefined): string {
  if (value === null || value === undefined || value === "") return "未記録";
  if (typeof value === "number") return eaNumber(value, 8);
  if (typeof value === "boolean") return value ? "はい" : "いいえ";
  return value;
}

export function eaState(value: string): string {
  return ({ RECORDING: "記録中", RECORDED: "記録完了", FAILED: "記録エラー", INTERRUPTED: "記録中断", UNRECORDED: "推移未記録" } as Record<string, string>)[value] || value;
}

export function eaTone(value: number | null | undefined): string {
  if (value === null || value === undefined || value === 0) return "";
  return value > 0 ? "ea-buy" : "ea-sell";
}
