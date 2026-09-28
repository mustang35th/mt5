export type EaValue = string | number | boolean | null;
export type EaRecord = Record<string, EaValue>;

export interface EaMetadata {
  available: boolean;
  status: string;
  reason: string | null;
  database: { path: string; name: string; key: string } | null;
  database_key: string;
  schema_version: number | null;
  recording_supported: boolean;
}

export interface EaSession {
  key: string;
  session_uid: string | null;
  legacy: boolean;
  source_mode: string;
  account_currency: string | null;
  account_server: string;
  program_version: string;
  run_count: number;
  symbols: string[];
  started_server_time: number | null;
  trade_start_time: number | null;
  ended_server_time: number | null;
  recording_state: string;
  statistics_available: boolean;
  deals_complete: boolean;
  config_texts?: string[];
  error_text?: string | null;
  leverage?: number | null;
  initial_balance?: number | null;
}

export interface EaSessionsResponse {
  database_key: string;
  items: EaSession[];
  total: number;
  page: number;
  page_size: number;
}

export interface EaSummary {
  database_key: string;
  session: EaSession;
  metrics: {
    closed_trades: number;
    known_pnl_trades: number;
    open_trades: number;
    unknown_pnl_trades: number;
    net_profit: number | null;
    win_rate: number | null;
    profit_factor: number | null;
    wins: number;
    losses: number;
    breakeven: number;
    average_net_profit: number | null;
  };
  account_statistics: {
    available: boolean;
    initial_deposit: number | null;
    net_profit: number | null;
    equity_drawdown: number | null;
    equity_drawdown_percent: number | null;
    mt5_trades: number | null;
  };
  max_positions: {
    value: number | null;
    reference_value: number | null;
    quality: "EXACT" | "REFERENCE" | "UNAVAILABLE";
    reason: string | null;
    source: string;
  };
  skip_reasons: { reason_code: string; count: number }[];
  warnings: string[];
}

export interface EaSample {
  sequence: number;
  server_time: number;
  balance: number | null;
  equity: number | null;
  margin: number | null;
  free_margin: number | null;
  margin_level: number | null;
  open_profit: number | null;
  positions: number | null;
  pending_orders: number | null;
  foreign_positions: number | null;
  foreign_orders: number | null;
  segment_id: number;
  gap_before: boolean;
}

export interface EaSamplesResponse {
  database_key: string;
  items: EaSample[];
  total: number;
  returned: number;
  recorded: boolean;
  downsampled: boolean;
  sample_interval_seconds: number | null;
  gap_threshold_seconds: number;
}

export interface EaTrade extends EaRecord {
  id: number;
  symbol_name: string;
  run_uid: string;
  status: string;
  side: string;
  opened_at_msc: number | null;
  closed_at_msc: number | null;
  requested_volume: number | null;
  opened_volume: number | null;
  open_price: number | null;
  close_price: number | null;
  current_stop_loss: number | null;
  remaining_position_volume: number | null;
  net_profit: number | null;
  profit: number | null;
  commission: number | null;
  swap: number | null;
  fee: number | null;
  holding_seconds: number | null;
  close_reason: string | null;
}

export type EaSort = "opened_at_msc" | "closed_at_msc" | "net_profit" | "symbol_name" | "id";
export interface EaTradeSearch {
  symbol: string;
  profit: "all" | "win" | "loss";
  status: "all" | "closed" | "open";
  page: number;
  page_size: number;
  sort: EaSort;
  direction: "asc" | "desc";
}

export interface EaTradesResponse {
  database_key: string;
  items: EaTrade[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface EaTradeDetail {
  database_key: string;
  session: EaSession;
  trade: EaTrade;
  decision: EaRecord | null;
  events: EaRecord[];
  events_truncated: boolean;
  deals: EaRecord[];
  deals_recorded: boolean;
  deals_truncated: boolean;
  previous_id: number | null;
  next_id: number | null;
}
