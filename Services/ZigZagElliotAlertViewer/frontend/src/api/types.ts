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

export interface AlertDetail {
  id: number;
  run_id: number;
  symbol_name: string;
  side: AlertSide;
  current_bar_time_text: string;
  alert_title: string;
  jst_time_text: string;
  server_time_text: string;
  reference_price: number;
  is_stop_loss_available: boolean;
  stop_loss: number;
  risk_pips: number;
  h1_structure_rank: string;
  is_h1_structure_late: boolean;
  strategy: string;
  signal_count: number;
  entry_count: number;
  is_judge: boolean;
  is_entry_count_match: boolean;
  is_entry_evaluated: boolean;
  is_entry_wave: boolean;
  is_ema200_distance_within: boolean;
  is_alert: boolean;
  is_entry: boolean;
  entry_result: string;
  current_elliot_label: string;
  close_ema200_diff_pips: number;
  max_close_ema200_diff_pips: number;
  spread_pips: number;
  currency_strength_status: number;
  is_currency_strength_available: boolean;
  long_medium_rank_difference: number;
  medium_short_rank_difference: number;
  market_signal_key: string;
  alert_text: string;
  is_w1_aligned: boolean | null;
}

export interface AlertRunDetail {
  id: number;
  source_mode: string;
  program_version: string;
  tester_model: string;
}

export interface W1Summary {
  w1_timeframe_id: number;
  w1_is_buy: boolean;
  w1_side: string;
  w1_elliot_label: string;
  w1_sub_elliot_label: string;
  w1_is_wave_confirmed: boolean;
  w1_is_wave_motive: boolean;
  w1_is_wave_uptrend: boolean;
  w1_wave_trend: string;
}

export interface AlertDetailResponse {
  alert: AlertDetail;
  run: AlertRunDetail | null;
  w1: W1Summary | null;
}

export interface AlertTimeFrame {
  id: number;
  time_frame_text: string;
  time_frame_order: number;
  buy_sell_label: string;
  is_wave_confirmed: boolean;
  is_wave_motive: boolean;
  is_wave_uptrend: boolean;
  wave_trend_label: string;
  latest_wave_index: number;
  point_count: number;
  latest_elliot_label: string;
  latest_sub_elliot_label: string;
  stochastic_main_order_text: string;
  stochastic_main_direction_text: string;
  gmma_trend_count: number;
  gmma_cross_count: number;
  is_ema200_buy: boolean;
  is_ema200_sell: boolean;
  atr14_pips: number;
  is_fibo_expansion_available: boolean;
  distance_to_fe2000_pips: number;
  current_close: number;
}

export interface TimeFramesResponse {
  items: AlertTimeFrame[];
  count: number;
}

export interface AlertPoint {
  id: number;
  time_frame_text: string;
  time_frame_order: number;
  point_order: number;
  bar_time_text: string;
  rate: number;
  is_peak: boolean;
  elliot_label: string;
  sub_elliot_label: string;
  pips_diff: number;
  is_fibonacci_available: boolean;
  fibonacci_percent: number;
  is_fibonacci_expansion_available: boolean;
  fibonacci_expansion_percent: number;
  is_latest: boolean;
  is_signal_reference: boolean;
  is_added_point: boolean;
  is_correct: boolean;
}

export interface PointsResponse {
  items: AlertPoint[];
  count: number;
}

export interface ApiErrorResponse {
  error?: string;
  detail?: string;
}
