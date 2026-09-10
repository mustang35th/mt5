import type { M5CaptureMetrics, M5CaptureMetricsState, M5ObservationParent } from "../api/m5Types";
import { m5Number } from "./m5TimeFrame";

export type M5MetricField = Exclude<keyof M5CaptureMetrics, "observation_id">;

/** Decode the recorded server calendar using UTC accessors, without local-TZ conversion. */
export function m5StoredServerTime(value: unknown, milliseconds = false): string {
  if (value === null || value === undefined) return "未記録";
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return "不正値";
  const date = new Date(milliseconds ? value : value * 1000);
  if (Number.isNaN(date.getTime())) return "不正値";
  const iso = date.toISOString();
  return iso.slice(0, milliseconds ? 23 : 19).replaceAll("-", ".").replace("T", " ");
}

export function m5MetricMissingReason(metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState, field: M5MetricField): string | null {
  if (!state.tableAvailable) return "未記録（品質テーブルなし）";
  if (!state.rowAvailable || metrics === null) return "未記録（品質行なし）";
  if (state.missingColumns.includes(field)) return "未記録（列なし）";
  if (metrics[field] === null) return "未記録（NULL）";
  if (metrics[field] === undefined) return "未記録（値なし）";
  return null;
}

export function m5MetricValue(metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState, field: M5MetricField): number | null {
  if (m5MetricMissingReason(metrics, state, field)) return null;
  const value = metrics?.[field];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export function m5MetricLabel(metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState, field: M5MetricField): string {
  const missing = m5MetricMissingReason(metrics, state, field);
  if (missing) return missing;
  const value = metrics?.[field];
  if (typeof value !== "number" || !Number.isFinite(value)) return "不正値";
  if (field === "quote_tick_time_msc") return `${m5StoredServerTime(value, true)}（${value} ms）`;
  if (field === "capture_market_time") return `${m5StoredServerTime(value)}（${value}）`;
  const unit = field === "analysis_attempt_count" ? "回" : " ms";
  const invalid = !Number.isInteger(value) || value < (field === "analysis_attempt_count" ? 1 : 0);
  return `${m5Number(value, 0, unit)}${invalid ? "（不正値・要確認）" : ""}`;
}

export function m5CaptureLag(observation: M5ObservationParent, metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState): number | null {
  const captured = m5MetricValue(metrics, state, "capture_market_time");
  if (captured === null || captured <= 0 || !Number.isFinite(observation.anchor_bar_time)) return null;
  return captured - observation.anchor_bar_time;
}

export function m5CaptureWarnings(observation: M5ObservationParent, metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState): string[] {
  const warnings: string[] = [];
  const lag = m5CaptureLag(observation, metrics, state);
  const quote = m5MetricValue(metrics, state, "quote_tick_time_msc");
  if (lag !== null && lag < 0) warnings.push("時刻逆転・要確認（市場取得遅れが負値）");
  if (lag !== null && (lag < 0 || lag >= 300)) warnings.push("取得市場時刻が対象足外");
  if (quote !== null && quote > 0 && quote < observation.anchor_bar_time * 1000) warnings.push("過去の気配（対象M5開始より前）");
  if (quote !== null && quote >= (observation.anchor_bar_time + 300) * 1000) warnings.push("採用気配が対象足外");
  const analysis = m5MetricValue(metrics, state, "analysis_elapsed_ms");
  const capture = m5MetricValue(metrics, state, "capture_elapsed_ms");
  if (analysis !== null && capture !== null && capture < analysis) warnings.push("取得時間が解析時間より短い・要確認");
  return warnings;
}

export function m5CaptureSummary(observation: M5ObservationParent, metrics: M5CaptureMetrics | null, state: M5CaptureMetricsState): string {
  const lag = m5CaptureLag(observation, metrics, state);
  return `遅れ ${lag === null ? m5MetricMissingReason(metrics, state, "capture_market_time") || "不正値" : m5Number(lag, 0, "秒")} / 解析 ${m5MetricLabel(metrics, state, "analysis_elapsed_ms")} / 取得 ${m5MetricLabel(metrics, state, "capture_elapsed_ms")} / ${m5MetricLabel(metrics, state, "analysis_attempt_count")}`;
}
