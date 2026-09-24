import type { ObservationDetailTimeFrame, ObservationListItem, RunItem } from "./types";

export type M5SourceMode = "TESTER" | "LIVE";
export type M5DisplayInterval = 5 | 15;
export type M5Sort = "anchor_jst_time" | "symbol_name";
type NullableRaw<T> = { [K in keyof T]?: NonNullable<T[K]> extends boolean ? boolean | number | null : T[K] | null };
export type M5TimeFrame = NullableRaw<ObservationDetailTimeFrame> & {
  previous_motive_sub_elliot_index?: number | null;
};
export type M5ObservationParent = NullableRaw<Omit<ObservationListItem, "time_frames">> & {
  id: number;
  run_id: number;
  symbol_name: string;
  anchor_bar_time: number;
  anchor_jst_time: number;
};
export interface M5CaptureMetrics {
  observation_id?: number;
  quote_tick_time_msc?: number | null;
  capture_market_time?: number | null;
  analysis_elapsed_ms?: number | null;
  capture_elapsed_ms?: number | null;
  analysis_attempt_count?: number | null;
}
export interface M5CaptureMetricsState {
  tableAvailable: boolean;
  rowAvailable: boolean;
  missingColumns: string[];
}
export interface M5ObservationItem extends M5ObservationParent {
  timeframes: M5TimeFrame[];
  captureMetrics: M5CaptureMetrics | null;
  captureMetricsState: M5CaptureMetricsState;
}
export type M5Run = Partial<RunItem> & {
  id: number;
  source_mode: string;
  observation_count: number;
  first_observation_jst_time: number | null;
  last_observation_jst_time: number | null;
};
export interface M5DatabaseIdentity { name: string; path: string; key: string }
export interface M5Metadata {
  available: boolean;
  status: string;
  reason: string | null;
  database: M5DatabaseIdentity | null;
  sourceMode: M5SourceMode;
  effectiveRunId: number | null;
  runs: M5Run[];
  symbols: string[];
  range: { first: number | null; last: number | null };
  capabilities: { captureMetricsTable: boolean; captureMetricsColumns: string[] };
}
export interface M5SearchState {
  sourceMode: M5SourceMode;
  runId: number | null;
  databaseKey: string;
  symbol: string;
  from: string;
  to: string;
  jstTime: string;
  displayInterval: M5DisplayInterval;
  page: number;
  pageSize: 50 | 100 | 200;
  sort: M5Sort;
  order: "asc" | "desc";
  followLatest: boolean;
}
export interface M5ListResponse {
  databaseKey: string;
  items: M5ObservationItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}
export interface M5NavigationItem {
  id: number;
  anchor_bar_time: number;
  anchor_bar_time_text: string;
  anchor_jst_time: number;
  anchor_jst_time_text: string;
  gap_seconds: number;
}
export interface M5DetailResponse {
  currencyStrength?: M5CurrencyStrength;
  databaseKey: string;
  observation: M5ObservationParent;
  run: M5Run;
  timeframes: M5TimeFrame[];
  captureMetrics: M5CaptureMetrics | null;
  captureMetricsState: M5CaptureMetricsState;
  navigation: { older: M5NavigationItem | null; newer: M5NavigationItem | null };
}

export interface M5CurrencyStrength {
  status: "FOUND" | "NOT_CONFIGURED" | "DATABASE_NOT_FOUND" | "IDENTITY_UNAVAILABLE"
    | "UNSUPPORTED_SYMBOL" | "RECORD_NOT_FOUND" | "AMBIGUOUS" | "INVALID_DATA" | "ERROR";
  databaseName: string | null;
  calculationMode: "UNIFORM" | "WEIGHTED";
  calculationVersion: string;
  targetM5BarTime: number;
  actualM5BarTime: number | null;
  runId: number | null;
  sourceMode: string | null;
  baseCurrency: string | null;
  quoteCurrency: string | null;
  periods: Array<{
    label: string;
    baseRank: number;
    quoteRank: number;
    rankDifference: number;
    direction: "BUY" | "SELL" | "TIE";
  }>;
}
