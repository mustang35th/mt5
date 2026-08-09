export type AlertSide = "BUY" | "SELL";
export type W1Alignment = "all" | "aligned" | "mismatched" | "unknown";
export type SortOrder = "asc" | "desc";
export type AlertSort =
  | "jst_time"
  | "symbol_name"
  | "side"
  | "h1_structure_rank"
  | "is_w1_aligned"
  | "risk_pips"
  | "entry_result";

export interface SearchState {
  runId: number | null;
  q: string;
  symbol: string;
  side: "" | AlertSide;
  rank: string;
  w1Aligned: W1Alignment;
  from: string;
  to: string;
  pageSize: number;
  page: number;
  sort: AlertSort;
  order: SortOrder;
}

export interface HealthResponse {
  status: "ok";
  database: string;
  journal_mode: string;
  alert_count: number;
}

export interface RunItem {
  id: number;
  run_uid: string;
  source_mode: string;
  program_name: string;
  program_version: string;
  strategy: string;
  strategy_version: string;
  analysis_version: string;
  started_at_text: string;
  alert_count: number;
  first_alert_time_text: string | null;
  last_alert_time_text: string | null;
  symbols: string | null;
}

export interface RunsResponse {
  items: RunItem[];
  count: number;
}

export interface OptionsResponse {
  symbols: string[];
  time_frames: string[];
  strategies: string[];
  ranks: string[];
  entry_results: string[];
}

export interface AlertListItem {
  id: number;
  run_id: number;
  jst_time_text: string;
  server_time_text: string;
  symbol_name: string;
  time_frame_text: string;
  strategy: string;
  side: AlertSide;
  signal_count: number;
  entry_count: number;
  is_entry: boolean;
  entry_result: string;
  current_elliot_label: string;
  risk_pips: number;
  spread_pips: number;
  h1_structure_rank: string;
  is_h1_structure_late: boolean;
  alert_title: string;
  mn1_side: string | null;
  w1_side: string | null;
  d1_side: string | null;
  h4_side: string | null;
  h1_side: string | null;
  is_w1_aligned: boolean | null;
}

export interface AlertsResponse {
  items: AlertListItem[];
  total: number;
  page: number;
  page_size: number;
  page_count: number;
}

export interface SummaryResponse {
  total_count: number;
  buy_count: number;
  sell_count: number;
  w1_aligned_count: number;
  w1_mismatched_count: number;
  w1_unknown_count: number;
  run_count: number;
  symbol_count: number;
}

export interface ApiErrorResponse {
  error?: string;
  detail?: string;
}
