import type { M5TimeFrame } from "../api/m5Types";

export const M5_TIME_FRAMES = [
  { id: 49153, label: "MN1" }, { id: 32769, label: "W1" },
  { id: 16408, label: "D1" }, { id: 16388, label: "H4" },
  { id: 16385, label: "H1" }, { id: 15, label: "M15" }, { id: 5, label: "M5" },
] as const;

export function m5Boolean(value: unknown): boolean | null {
  if (value === true || value === 1) return true;
  if (value === false || value === 0) return false;
  return null;
}

export function m5Text(value: unknown): string {
  if (value === null || value === undefined || value === "") return "未記録";
  return String(value);
}

export function m5Number(value: unknown, digits = 1, unit = "", signed = false): string {
  if (value === null || value === undefined) return "未記録";
  if (typeof value !== "number" || !Number.isFinite(value)) return "不正値";
  return `${new Intl.NumberFormat("ja-JP", { minimumFractionDigits: digits, maximumFractionDigits: digits, signDisplay: signed ? "exceptZero" : "auto" }).format(value)}${unit}`;
}

export function m5Direction(value: unknown): "BUY" | "SELL" | "不明" {
  const flag = m5Boolean(value);
  if (flag === true) return "BUY";
  if (flag === false) return "SELL";
  return "不明";
}

export function m5FlagLabel(value: unknown, yes: string, no: string): string {
  const flag = m5Boolean(value);
  if (flag === null) return "未記録";
  return flag ? yes : no;
}

export function m5PreviousMotiveSubLabel(value: unknown): string {
  if (value === null || value === undefined) return "未記録";
  if (value === 0) return "該当なし";
  if (value === 1 || value === 3) return `${value}波に副次波あり`;
  return "不正値";
}

export function m5WaveLabel(timeFrame: M5TimeFrame): string {
  const direction = m5Boolean(timeFrame.is_wave_uptrend);
  const arrow = direction === null ? "? " : direction ? "▲" : "▼";
  const main = m5Text(timeFrame.latest_elliot_label);
  const sub = timeFrame.latest_sub_elliot_label;
  return `${arrow}${main}${typeof sub === "string" && sub.trim() ? `.${sub}` : ""}`;
}

export function m5EmaLabel(timeFrame: M5TimeFrame): string {
  if (timeFrame.time_frame === 49153) return "対象外（MN1）";
  const buy = m5Boolean(timeFrame.is_ema200_buy);
  const sell = m5Boolean(timeFrame.is_ema200_sell);
  if (buy === null || sell === null) return "未記録";
  if (buy && sell) return "BUY＋SELL（両方向成立）";
  if (buy) return "BUY";
  if (sell) return "SELL";
  return "NONE";
}

/** Match the existing saved original Elliott-index F/FE rule; never recalculate. */
export function m5FibonacciLabel(timeFrame: M5TimeFrame): string {
  const index = timeFrame.latest_point_org_elliot_index;
  if (typeof index !== "number" || !Number.isInteger(index)) return "未記録";
  if (index <= 1) return "対象外";
  const isF = index % 2 === 0;
  const value = isF ? timeFrame.latest_point_fibonacci_percent : timeFrame.latest_point_fibonacci_expansion_percent;
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return "未記録";
  return `${isF ? "F" : "FE"} ${m5Number(value, 1, "%")}`;
}

export function m5DepthLabel(timeFrame: M5TimeFrame): string {
  const index = timeFrame.latest_point_org_elliot_index;
  if (typeof index !== "number" || !Number.isInteger(index)) return "未記録";
  if (index <= 1 || index % 2 !== 0) return "対象外";
  if (m5FibonacciLabel(timeFrame) === "未記録") return "未記録";
  const label = typeof timeFrame.latest_point_fibo_depth_zone_label === "string" ? timeFrame.latest_point_fibo_depth_zone_label.trim() : "";
  const code = timeFrame.latest_point_fibo_depth_zone;
  const hasCode = typeof code === "number" && Number.isFinite(code);
  if (!label && !hasCode) return "未記録";
  return `${label}${hasCode ? ` [${m5Number(code, 0)}]` : ""}`.trim();
}

export interface M5TimeFrameSlot {
  id: number;
  label: string;
  timeFrame: M5TimeFrame | null;
  warning: string;
}

/** Keep seven fixed slots even when the stored footprint is incomplete/invalid. */
export function m5TimeFrameSlots(timeFrames: readonly M5TimeFrame[]): { slots: M5TimeFrameSlot[]; warnings: string[] } {
  const warnings: string[] = [];
  const allowed = new Set<number>(M5_TIME_FRAMES.map((item) => item.id));
  for (const row of timeFrames) {
    if (typeof row.time_frame !== "number" || !allowed.has(row.time_frame)) {
      warnings.push(`不正な時間足ID: ${m5Text(row.time_frame)}`);
    }
  }
  const slots = M5_TIME_FRAMES.map((item, order) => {
    const rows = timeFrames.filter((row) => row.time_frame === item.id);
    let warning = "";
    let timeFrame: M5TimeFrame | null = rows.length === 1 ? rows[0] : null;
    if (rows.length === 0) warning = `${item.label}: 子行が未記録`;
    else if (rows.length > 1) warning = `${item.label}: 子行が重複（${rows.length}行）`;
    else if (timeFrame) {
      const reasons: string[] = [];
      if (timeFrame.time_frame_order !== order) reasons.push(`保存順序 ${m5Text(timeFrame.time_frame_order)} / 期待 ${order}`);
      if (m5Boolean(timeFrame.is_anchor_time_frame) !== (item.id === 5)) reasons.push("基準足フラグ不整合");
      if (timeFrame.time_frame_text !== item.label) reasons.push(`時間足名 ${m5Text(timeFrame.time_frame_text)}`);
      if (reasons.length) warning = `${item.label}: ${reasons.join("、")}`;
    }
    if (warning) warnings.push(warning);
    return { ...item, timeFrame, warning };
  });
  return { slots, warnings };
}
