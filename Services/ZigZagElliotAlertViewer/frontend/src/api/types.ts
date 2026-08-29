export type AlertSide = "BUY" | "SELL";
export type SourceMode = "LIVE" | "TESTER" | "all";
export type AnalysisProfileKind = "profile" | "legacy";
export type ViewerTab = "alerts" | "h1";
export type W1Alignment = "all" | "aligned" | "mismatched" | "unknown";
export type W1ConfirmationMode =
  | "OFF"
  | "OBSERVE_ONLY"
  | "DIRECTION_OR_EMA200"
  | "DIRECTION_AND_EMA200";
export type W1ConfirmationState =
  | "NOT_EVALUATED"
  | "NOT_APPLICABLE"
  | "OFF"
  | "UNAVAILABLE"
  | "INVALID"
  | "STRONG"
  | "DIRECTION_ONLY"
  | "EMA_CONFLICT"
  | "EMA_ONLY"
  | "REJECT_NONE"
  | "REJECT";
export type W1ConfirmationModeFilter = "all" | W1ConfirmationMode;
export type W1ConfirmationStateFilter = "all" | W1ConfirmationState;
export type H1DirectionAlignmentMode =
  | "D1_TO_H1"
  | "MN1_TO_H1_OBSERVE"
  | "MN1_TO_H1_REQUIRED"
  | "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
  | "INVALID";
export type H1DirectionAlignmentState =
  | "NOT_EVALUATED"
  | "NOT_APPLICABLE"
  | "D1_TO_H1"
  | "FULL_BUY"
  | "FULL_SELL"
  | "MN1_MISMATCH"
  | "W1_MISMATCH"
  | "MN1_W1_MISMATCH"
  | "EMA200_FALLBACK_BUY"
  | "EMA200_FALLBACK_SELL"
  | "MN1_EMA200_MISMATCH"
  | "UNAVAILABLE"
  | "INVALID";
export type H1DirectionAlignmentModeFilter = "all" | H1DirectionAlignmentMode;
export type H1DirectionAlignmentStateFilter = "all" | H1DirectionAlignmentState;
export type GmoTargetFilter = "all" | "target" | "excluded";
export type SortOrder = "asc" | "desc";
export type AlertSort =
  | "jst_time"
  | "symbol_name"
  | "time_frame"
  | "side"
  | "h1_structure_rank"
  | "is_w1_aligned"
  | "w1_confirmation_state"
  | "risk_pips"
  | "entry_result";

export interface SearchState {
  sourceMode: SourceMode;
  runId: number | null;
  q: string;
  symbol: string;
  gmoTarget: GmoTargetFilter;
  timeFrames: string[];
  side: "" | AlertSide;
  rank: string;
  w1Aligned: W1Alignment;
  w1ConfirmationMode: W1ConfirmationModeFilter;
  w1ConfirmationState: W1ConfirmationStateFilter;
  h1DirectionAlignmentMode: H1DirectionAlignmentModeFilter;
  h1DirectionAlignmentState: H1DirectionAlignmentStateFilter;
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
  observation_available?: boolean;
  observation_count?: number;
  analysis_profile_available?: boolean;
  analysis_profile_reason?: string | null;
  w1_confirmation_available?: boolean;
  w1_confirmation_reason?: string | null;
  h1_direction_alignment_available?: boolean;
  h1_direction_alignment_reason?: string | null;
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
  observation_count?: number;
  first_observation_time_text?: string | null;
  last_observation_time_text?: string | null;
  first_observation_jst_time?: number | null;
  first_observation_jst_time_text?: string | null;
  last_observation_jst_time?: number | null;
  last_observation_jst_time_text?: string | null;
  observation_symbols?: string | null;
  analysis_input_text?: string | null;
  analysis_input_hash?: string | null;
  analysis_profile_is_legacy?: boolean;
}

export interface RunsResponse {
  items: RunItem[];
  count: number;
  analysis_profile_available?: boolean;
  analysis_profile_reason?: string | null;
}

export interface OptionsResponse {
  symbols: string[];
  time_frames: string[];
  strategies: string[];
  ranks: string[];
  entry_results: string[];
  w1_confirmation_modes?: W1ConfirmationMode[];
  w1_confirmation_states?: W1ConfirmationState[];
  w1_confirmation_available?: boolean;
  h1_direction_alignment_modes?: H1DirectionAlignmentMode[];
  h1_direction_alignment_states?: H1DirectionAlignmentState[];
  h1_direction_alignment_available?: boolean;
}

export interface W1ConfirmationDiagnostics {
  w1_confirmation_mode: W1ConfirmationMode;
  w1_confirmation_state: W1ConfirmationState;
  is_w1_confirmation_available: boolean;
  is_w1_confirmation_valid: boolean;
  is_w1_direction_matched: boolean;
  w1_ema200_direction: "BUY" | "SELL" | "NONE";
  is_w1_ema200_matched: boolean;
  is_w1_confirmation_passed: boolean;
  is_w1_confirmation_legacy: boolean;
}

export interface H1DirectionAlignmentDiagnostics {
  h1_direction_alignment_mode: H1DirectionAlignmentMode;
  h1_direction_alignment_state: H1DirectionAlignmentState;
  is_h1_direction_alignment_available: boolean;
  is_h1_direction_alignment_valid: boolean;
  h1_direction_alignment_direction: "BUY" | "SELL" | "NONE";
  is_h1_mn1_direction_matched: boolean;
  is_h1_w1_direction_matched: boolean;
  is_h1_direction_alignment_passed: boolean;
  is_h1_direction_alignment_legacy: boolean;
}

export interface AlertListItem extends W1ConfirmationDiagnostics, H1DirectionAlignmentDiagnostics {
  id: number;
  run_id: number;
  source_mode: string;
  jst_time_text: string;
  server_time_text: string;
  symbol_name: string;
  is_gmo_target?: boolean;
  time_frame_text: string;
  strategy: string;
  side: AlertSide;
  is_ema200_available?: boolean;
  is_ema200_buy?: boolean;
  is_ema200_sell?: boolean;
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
  mn1_is_ema200_available?: boolean;
  mn1_is_ema200_buy?: boolean;
  mn1_is_ema200_sell?: boolean;
  w1_side: string | null;
  w1_is_ema200_available?: boolean;
  w1_is_ema200_buy?: boolean;
  w1_is_ema200_sell?: boolean;
  d1_side: string | null;
  d1_is_ema200_available?: boolean;
  d1_is_ema200_buy?: boolean;
  d1_is_ema200_sell?: boolean;
  h4_side: string | null;
  h4_is_ema200_available?: boolean;
  h4_is_ema200_buy?: boolean;
  h4_is_ema200_sell?: boolean;
  h1_side: string | null;
  h1_is_ema200_available?: boolean;
  h1_is_ema200_buy?: boolean;
  h1_is_ema200_sell?: boolean;
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
  database_total_count: number;
  buy_count: number;
  sell_count: number;
  w1_aligned_count: number;
  w1_mismatched_count: number;
  w1_unknown_count: number;
  run_count: number;
  symbol_count: number;
}

export interface AlertDetail extends W1ConfirmationDiagnostics, H1DirectionAlignmentDiagnostics {
  id: number;
  run_id: number;
  symbol_name: string;
  is_gmo_target?: boolean;
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
  is_currency_strength_enabled?: boolean;
  currency_strength_status: number;
  is_currency_strength_available: boolean;
  currency_strength_calculation_version?: string;
  currency_strength_run_id?: number;
  currency_strength_source_mode?: string;
  currency_strength_target_m5_bar_time?: number;
  currency_strength_m5_bar_time?: number;
  base_currency?: string;
  base_long_medium_rank?: number;
  base_medium_short_rank?: number;
  quote_currency?: string;
  quote_long_medium_rank?: number;
  quote_medium_short_rank?: number;
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

export type AlertTimeFrame = Omit<
  ObservationDetailTimeFrame,
  | "observation_id"
  | "is_anchor_time_frame"
  | "latest_point_time"
  | "latest_point_time_text"
  | "latest_point_jst_time"
  | "latest_point_jst_time_text"
  | "latest_point_rate"
> & {
  alert_id: number;
  is_current_time_frame: boolean;
  is_ema200_available: boolean;
  raw_csv_text?: string;
};

export interface TimeFramesResponse {
  items: AlertTimeFrame[];
  count: number;
}

export interface AlertPoint {
  id: number;
  alert_id: number;
  alert_timeframe_id: number;
  time_frame: number;
  time_frame_text: string;
  time_frame_order: number;
  point_order: number;
  bar_time: number;
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

export type ObservationSort = "anchor_jst_time" | "symbol_name";

export type ObservationSyncTimeFrame = "MN1" | "W1" | "D1" | "H4";

export type ObservationFullAlignment = "" | "FULL" | "BUY" | "SELL";
export type ObservationGroupMode = "h1" | "signal";

export interface ObservationSearchState {
  sourceMode: SourceMode;
  runId: number | null;
  analysisVersion: string;
  analysisInputHash: string;
  analysisProfileKind: "" | AnalysisProfileKind;
  symbol: string;
  gmoTarget: GmoTargetFilter;
  from: string;
  to: string;
  jstTime: string;
  syncTimeFrames: ObservationSyncTimeFrame[];
  fullAlignment: ObservationFullAlignment;
  groupMode: ObservationGroupMode;
  pageSize: number;
  page: number;
  sort: ObservationSort;
  order: SortOrder;
}

export interface ObservationTimeFrame {
  id: number;
  observation_id: number;
  time_frame: number;
  time_frame_text: string;
  time_frame_order: number;
  is_anchor_time_frame: boolean;
  is_buy: boolean;
  buy_sell_label: string;
  wave_count: number;
  latest_wave_index: number;
  is_wave_confirmed: boolean;
  is_wave_motive: boolean;
  is_wave_uptrend: boolean;
  wave_trend_label: string;
  previous_last_elliot_label: string;
  point_count: number;
  latest_elliot_index: number;
  latest_elliot_label: string;
  latest_sub_elliot_index: number;
  latest_sub_elliot_label: string;
  latest_point_time: number;
  latest_point_time_text: string;
  latest_point_jst_time: number;
  latest_point_jst_time_text: string;
  latest_point_rate: number;
  current_close: number;
  stochastic_main_order_text: string;
  stochastic_main_direction_text: string;
  gmma_trend_count: number;
  gmma_cross_count: number;
  atr14_pips: number;
  is_ema200_buy: boolean;
  is_ema200_sell: boolean;
}

export interface ObservationListItem {
  id: number;
  run_id: number;
  run_uid: string;
  source_mode: string;
  source_server: string;
  symbol_name: string;
  is_gmo_target?: boolean;
  anchor_bar_time: number;
  anchor_bar_time_text: string;
  anchor_jst_time: number;
  anchor_jst_time_text: string;
  anchor_time_frame: number;
  anchor_time_frame_text: string;
  capture_phase: string;
  spread_pips: number | null;
  pip_size: number | null;
  analysis_version: string;
  analysis_input_hash: string;
  analysis_input_text?: string | null;
  analysis_profile_is_legacy?: boolean;
  snapshot_hash: string;
  time_frame_count: number;
  created_at: number;
  created_at_text: string;
  time_frames: ObservationTimeFrame[];
  signal_rule_version?: "FULL_ALIGNMENT_EPISODE_V1";
  signal_side?: AlertSide;
  signal_start_observation_id?: number;
  signal_end_observation_id?: number;
  signal_end_anchor_bar_time?: number;
  signal_end_anchor_bar_time_text?: string;
  signal_end_anchor_jst_time?: number;
  signal_end_anchor_jst_time_text?: string;
  signal_h1_count?: number;
  signal_is_left_censored?: boolean;
  signal_is_right_censored?: boolean;
  signal_has_data_gap_before?: boolean;
  signal_has_data_gap_after?: boolean;
}

export interface ObservationDetailParent extends Omit<ObservationListItem, "time_frames"> {
  source: string;
  program_name: string;
  program_version: string;
  strategy: string;
  strategy_version: string;
  tester_from: number | null;
  tester_to: number | null;
  tester_model: string | null;
  started_at: number;
  started_at_text: string;
}

export interface ObservationDetailTimeFrame extends ObservationTimeFrame {
  previous_open: number;
  previous_high: number;
  previous_low: number;
  previous_close: number;
  current_open: number;
  current_high: number;
  current_low: number;
  is_fibo_expansion_available: boolean;
  fe618_price: number;
  fe1000_price: number;
  fe1272_price: number;
  fe1618_price: number;
  fe2000_price: number;
  distance_to_fe2000_pips: number;
  oscillator_count: number;
  is_oscillator_buy: boolean;
  stochastic_main_order: number;
  stochastic_short_count: number;
  stochastic_short_main: number;
  stochastic_short_signal: number;
  stochastic_middle_count: number;
  stochastic_middle_main: number;
  stochastic_middle_signal: number;
  stochastic_long_count: number;
  stochastic_long_main: number;
  stochastic_long_signal: number;
  ema30: number;
  ema60: number;
  ema30_ema60_diff_pips: number;
  ema200_close1: number;
  ema200_shift1: number;
  ema200_compare: number;
  ema200_slope_pips: number;
  ema200_close_diff_pips: number;
  ema200_close_position: number;
  ema200_slope_direction: number;
  ema200_up_count: number;
  ema200_down_count: number;
  ema200_trend_count: number;
  created_at: number;
  created_at_text: string;
}

export interface ObservationNavigationItem {
  id: number;
  run_id: number;
  anchor_jst_time: number;
  anchor_jst_time_text: string;
  anchor_bar_time: number;
  anchor_bar_time_text: string;
}

export interface ObservationDetailNavigation {
  older: ObservationNavigationItem | null;
  newer: ObservationNavigationItem | null;
}

export interface ObservationDetailResponse {
  available: boolean;
  observation: ObservationDetailParent | null;
  time_frames: ObservationDetailTimeFrame[];
  navigation?: ObservationDetailNavigation;
}

export interface ObservationsResponse {
  available: boolean;
  items: ObservationListItem[];
  total: number;
  page: number;
  page_size: number;
  page_count: number;
  grouped?: boolean;
}

export interface ObservationOptionsResponse {
  available: boolean;
  symbols: string[];
  source_modes: string[];
  analysis_versions: string[];
  analysis_profile_available?: boolean;
  analysis_profile_reason?: string | null;
  analysis_profiles?: ObservationAnalysisProfile[];
  default_analysis_input_hash?: string | null;
  default_analysis_input_hashes?: ObservationAnalysisProfileDefaults;
  default_analysis_profile_keys?: ObservationAnalysisProfileDefaults;
  default_analysis_profiles?: ObservationAnalysisProfileItemDefaults;
}

export interface ObservationAnalysisProfile {
  profile_key: string;
  analysis_profile_kind: AnalysisProfileKind;
  analysis_input_hash: string;
  analysis_input_text: string | null;
  analysis_version: string;
  observation_count: number;
  last_anchor_jst_time: number | null;
  last_anchor_jst_time_text: string | null;
  source_modes: string[];
  is_legacy: boolean;
}

export interface ObservationAnalysisProfileDefaults {
  all: string | null;
  LIVE: string | null;
  TESTER: string | null;
}

export interface ObservationAnalysisProfileItemDefaults {
  all: ObservationAnalysisProfile | null;
  LIVE: ObservationAnalysisProfile | null;
  TESTER: ObservationAnalysisProfile | null;
}

export interface ObservationSummaryResponse {
  available: boolean;
  total_count: number;
  live_count: number;
  tester_count: number;
  run_count: number;
  symbol_count: number;
  first_anchor_bar_time: number | null;
  first_anchor_bar_time_text: string | null;
  last_anchor_bar_time: number | null;
  last_anchor_bar_time_text: string | null;
  first_anchor_jst_time: number | null;
  first_anchor_jst_time_text: string | null;
  last_anchor_jst_time: number | null;
  last_anchor_jst_time_text: string | null;
  analysis_profile_count?: number;
  legacy_profile_observation_count?: number;
  matched_observation_count?: number;
  signal_buy_count?: number;
  signal_sell_count?: number;
  grouped?: boolean;
}

export interface ApiErrorResponse {
  error?: string;
  detail?: string;
}
