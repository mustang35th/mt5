import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { eaApi } from "../api/eaClient";
import type { EaMetadata, EaSample, EaSamplesResponse, EaSession, EaSummary, EaTrade, EaTradeDetail, EaTradesResponse } from "../api/eaTypes";
import { eaTime } from "../lib/eaFormat";
import { eaChartPath, eaIsolatedPoints, H1EaChart } from "./H1EaChart";
import { H1EaResultsView } from "./H1EaResultsView";

const key = `session:${"a".repeat(64)}`;
const session: EaSession = { key, session_uid: "a".repeat(64), legacy: false, source_mode: "TESTER", account_currency: "USD", account_server: "TestServer", program_version: "1.11", run_count: 28, symbols: ["EURUSD", "EURJPY"], started_server_time: 1000, trade_start_time: 1000, ended_server_time: 2000, recording_state: "RECORDED", statistics_available: true, deals_complete: true };
const metadata: EaMetadata = { available: true, status: "READY", reason: null, database: { name: "result.sqlite", key: "db-a", path: "result.sqlite" }, database_key: "db-a", schema_version: 4, recording_supported: true };
const summary: EaSummary = { database_key: "db-a", session, metrics: { closed_trades: 2, known_pnl_trades: 2, open_trades: 0, unknown_pnl_trades: 0, net_profit: 4.25, win_rate: 50, profit_factor: 2.06, wins: 1, losses: 1, breakeven: 0, average_net_profit: 2.125 }, account_statistics: { available: true, initial_deposit: 1000, net_profit: 4.25, equity_drawdown: 12, equity_drawdown_percent: 1.1, mt5_trades: 2 }, max_positions: { value: 2, reference_value: null, quality: "EXACT", reason: null, source: "SESSION_DEALS" }, skip_reasons: [], warnings: [] };
const sample: EaSample = { sequence: 1, server_time: 1000, balance: 1000, equity: 990, margin: 1, free_margin: 989, margin_level: 99000, open_profit: -10, positions: 1, pending_orders: 0, foreign_positions: 0, foreign_orders: 0, segment_id: 0, gap_before: false };
const samples: EaSamplesResponse = { database_key: "db-a", items: [sample, { ...sample, sequence: 2, server_time: 1060, equity: 1004.25 }], total: 2, returned: 2, recorded: true, downsampled: false, sample_interval_seconds: 60, gap_threshold_seconds: 180 };
function trade(id: number, net: number): EaTrade { return { id, symbol_name: id === 1 ? "EURUSD" : "EURJPY", run_uid: `run-${id}`, status: "CLOSED", side: id === 1 ? "BUY" : "SELL", opened_at_msc: 1000000, closed_at_msc: 2000000, requested_volume: 0.01, opened_volume: 0.01, open_price: 1.1, close_price: 1.2, current_stop_loss: 1.15, remaining_position_volume: 0, net_profit: net, profit: net + 2, commission: -1, swap: -1, fee: 0, holding_seconds: 1000, close_reason: "H1_ZIGZAG_TRAIL" }; }
const first = trade(1, 8.25), second = trade(2, -4);
function listing(items = [first, second]): EaTradesResponse { return { database_key: "db-a", items, total: items.length, page: 1, page_size: 25, total_pages: 1 }; }
function detail(item: EaTrade): EaTradeDetail { return { database_key: "db-a", session, trade: item, decision: { decision: item.side, h1_direction: item.side, h1_ema200_direction: item.side, h1_elliot_label: "3.1", h4_elliot_label: "1.3" }, events: [{ id: 1, event_type: "SL_MODIFY_RESULT", server_time: 1500, previous_stop_loss: 1.05, stop_loss: 1.15, confirmed_stop_loss: 1.15, message: "確認済み" }], events_truncated: false, deals: [{ ticket: "18446744073709551615", time_msc: 2000000, deal_type: 1, entry_type: 1, volume: .01, price: 1.2, profit: 10.25, commission: -1, swap: -1, fee: 0 }], deals_recorded: true, deals_truncated: false, previous_id: item.id === 1 ? null : 1, next_id: item.id === 1 ? 2 : null }; }

describe("H1 EA results", () => {
  beforeEach(() => {
    window.history.replaceState(null, "", "/?tab=ea");
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    vi.spyOn(eaApi, "metadata").mockResolvedValue(metadata);
    vi.spyOn(eaApi, "sessions").mockResolvedValue({ database_key: "db-a", items: [session], total: 1, page: 1, page_size: 50 });
    vi.spyOn(eaApi, "summary").mockResolvedValue(summary);
    vi.spyOn(eaApi, "samples").mockResolvedValue(samples);
    vi.spyOn(eaApi, "trades").mockResolvedValue(listing());
    vi.spyOn(eaApi, "detail").mockImplementation(async id => detail(id === 1 ? first : second));
  });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it("loads the session independently, preserves account currency and displays scoped statistics", async () => {
    render(<H1EaResultsView active />);
    expect(await screen.findByRole("button", { name: "EURUSD 取引1の詳細" })).toBeInTheDocument();
    const metrics = screen.getByRole("region", { name: "テスト成績" });
    expect(within(metrics).getByText("+4.25")).toBeInTheDocument();
    expect(within(metrics).getByText("USD · 対象EA")).toBeInTheDocument();
    expect(screen.queryByText("JPY")).not.toBeInTheDocument();
    expect(await screen.findByText("3.1")).toBeInTheDocument();
    expect(eaApi.trades).toHaveBeenCalledWith(key, "db-a", expect.objectContaining({ page_size: 25 }), expect.any(AbortSignal));
  });

  it("keeps full-session metrics while loss filtering and passes the filter to detail navigation", async () => {
    render(<H1EaResultsView active />);
    await screen.findByText("3.1");
    vi.mocked(eaApi.trades).mockResolvedValue(listing([second]));
    fireEvent.change(screen.getByRole("combobox", { name: "損益" }), { target: { value: "loss" } });
    await waitFor(() => expect(eaApi.detail).toHaveBeenLastCalledWith(2, key, "db-a", expect.objectContaining({ profit: "loss", page: 1 }), expect.any(AbortSignal)));
    expect(within(screen.getByRole("region", { name: "テスト成績" })).getByText("+4.25")).toBeInTheDocument();
    expect(eaApi.summary).toHaveBeenCalledTimes(1);
  });

  it("moves to the next detail and uses stored fee and stop-loss columns", async () => {
    render(<H1EaResultsView active />);
    await screen.findByText("3.1");
    fireEvent.click(screen.getByRole("button", { name: "次の取引 →" }));
    await waitFor(() => expect(eaApi.detail).toHaveBeenLastCalledWith(2, key, "db-a", expect.any(Object), expect.any(AbortSignal)));
    await screen.findByText("#2");
    fireEvent.click(screen.getByRole("button", { name: "約定・費用" }));
    expect(screen.getByText("18446744073709551615")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "SL・取引履歴" }));
    expect(screen.getAllByText("1.15")).toHaveLength(2);
    expect(screen.getByText("確認済み")).toBeInTheDocument();
  });

  it("never fills legacy equity, unknown currency or DD with invented zero values", async () => {
    const old = { ...session, legacy: true, account_currency: null, recording_state: "UNRECORDED", statistics_available: false };
    vi.mocked(eaApi.summary).mockResolvedValue({ ...summary, session: old, account_statistics: { available: false, initial_deposit: null, net_profit: null, equity_drawdown: null, equity_drawdown_percent: null, mt5_trades: null }, max_positions: { value: null, reference_value: null, quality: "UNAVAILABLE", reason: null, source: "NONE" } });
    vi.mocked(eaApi.samples).mockResolvedValue({ ...samples, items: [], recorded: false, total: 0, returned: 0 });
    render(<H1EaResultsView active />);
    expect(await screen.findByText(/資産推移は未記録です/)).toBeInTheDocument();
    const metrics = screen.getByRole("region", { name: "テスト成績" });
    expect(within(metrics).getAllByText("未記録")).toHaveLength(2);
    expect(within(metrics).getByText("口座通貨不明 · 対象EA")).toBeInTheDocument();
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
  });

  it("ignores a slow obsolete filter response", async () => {
    render(<H1EaResultsView active />);
    await screen.findByText("3.1");
    let complete!: (value: EaTradesResponse) => void;
    vi.mocked(eaApi.trades).mockImplementationOnce(() => new Promise(resolve => { complete = resolve; })).mockResolvedValueOnce(listing([first]));
    fireEvent.change(screen.getByRole("combobox", { name: "損益" }), { target: { value: "loss" } });
    await waitFor(() => expect(eaApi.trades).toHaveBeenCalledTimes(2));
    fireEvent.change(screen.getByRole("combobox", { name: "損益" }), { target: { value: "win" } });
    await screen.findByRole("button", { name: "EURUSD 取引1の詳細" });
    await act(async () => complete(listing([second])));
    expect(screen.queryByRole("button", { name: "EURJPY 取引2の詳細" })).not.toBeInTheDocument();
  });

  it("shows DB errors without continuing into queries", async () => {
    vi.mocked(eaApi.metadata).mockResolvedValue({ ...metadata, available: false, status: "NOT_FOUND", reason: "指定DBがありません" });
    render(<H1EaResultsView active />);
    expect(await screen.findByText("指定DBがありません")).toBeInTheDocument();
    expect(eaApi.sessions).not.toHaveBeenCalled();
    expect(eaApi.trades).not.toHaveBeenCalled();
  });

  it("does not query an inactive tab", () => {
    render(<H1EaResultsView active={false} />);
    expect(eaApi.metadata).not.toHaveBeenCalled();
  });

  it("keeps successful statistics when only the samples request fails", async () => {
    vi.mocked(eaApi.samples).mockRejectedValue(new Error("推移取得失敗"));
    render(<H1EaResultsView active />);
    expect(await screen.findByText("資産推移：推移取得失敗")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "テスト成績" })).getByText("+4.25")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "EURUSD 取引1の詳細" })).toBeInTheDocument();
  });

  it("allows refresh after leaving a loading tab and returning to an unavailable DB", async () => {
    vi.mocked(eaApi.summary).mockImplementation(() => new Promise(() => {}));
    vi.mocked(eaApi.trades).mockImplementation(() => new Promise(() => {}));
    const view = render(<H1EaResultsView active />);
    await waitFor(() => expect(eaApi.trades).toHaveBeenCalled());
    view.rerender(<H1EaResultsView active={false} />);
    vi.mocked(eaApi.metadata).mockResolvedValue({ ...metadata, available: false, status: "NOT_FOUND", reason: "DBなし" });
    view.rerender(<H1EaResultsView active />);
    await screen.findByText("DBなし");
    expect(screen.getByRole("button", { name: "更新" })).toBeEnabled();
  });
});

describe("EA chart and time integrity", () => {
  it("does not connect missing segments or unavailable numeric values", () => {
    const data = [sample, { ...sample, server_time: 1060 }, { ...sample, server_time: 2000, segment_id: 1, gap_before: true }, { ...sample, server_time: 2060, equity: null }, { ...sample, server_time: 2120, segment_id: 1 }];
    const path = eaChartPath(data, "equity", value => value, value => value);
    expect(path.match(/M/g)).toHaveLength(3);
    expect(path.match(/L/g)).toHaveLength(1);
  });
  it("keeps broker calendar time without browser timezone conversion", () => {
    expect(eaTime(Date.UTC(2026, 8, 28, 15, 35) / 1000)).toBe("2026/09/28 15:35:00");
  });
  it("renders isolated observations instead of invisible move-only paths", () => {
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    const isolated = [sample, { ...sample, sequence: 2, server_time: 3000, gap_before: true, segment_id: 1 }];
    expect(eaIsolatedPoints(isolated, "equity")).toHaveLength(2);
    const view = render(<H1EaChart samples={{ ...samples, items: isolated }} currency="USD" />);
    expect(view.container.querySelectorAll("circle")).toHaveLength(4);
    vi.unstubAllGlobals();
  });
});
