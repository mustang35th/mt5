import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { AlertCorrectionMetadata, AlertCorrectionResponse, AlertDetailResponse, AlertTimeFrame } from "../api/types";
import { AlertDetailDrawer } from "./AlertDetailDrawer";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

function detailPayload(alertId = 74): AlertDetailResponse {
  return {
    alert: {
      id: alertId,
      run_id: 3,
      symbol_name: alertId === 74 ? "AUDUSD" : "USDJPY",
      is_gmo_target: alertId === 74,
      side: "BUY",
      current_bar_time_text: "2026.07.30 19:00:00",
      alert_title: "test <img onerror=alert(1)>",
      jst_time_text: "2026.07.31 01:00:00",
      server_time_text: "2026.07.30 19:00:00",
      reference_price: 0,
      is_stop_loss_available: false,
      stop_loss: 0,
      risk_pips: 50,
      h1_structure_rank: "S",
      is_h1_structure_late: false,
      strategy: "MTF_3in3",
      signal_count: 1,
      entry_count: 1,
      is_judge: true,
      is_entry_count_match: true,
      is_entry_evaluated: true,
      is_entry_wave: true,
      is_ema200_distance_within: true,
      is_alert: true,
      is_entry: true,
      entry_result: "ENTRY",
      current_elliot_label: "3-3-1",
      close_ema200_diff_pips: 10,
      max_close_ema200_diff_pips: 25,
      spread_pips: 1.2,
      is_currency_strength_enabled: false,
      currency_strength_status: 0,
      is_currency_strength_available: false,
      long_medium_rank_difference: 5,
      medium_short_rank_difference: -3,
      market_signal_key: `market-${alertId}`,
      alert_text: "<script>alert('x')</script>",
      is_w1_aligned: null,
      w1_confirmation_mode: "OBSERVE_ONLY",
      w1_confirmation_state: "UNAVAILABLE",
      is_w1_confirmation_available: false,
      is_w1_confirmation_valid: false,
      is_w1_direction_matched: false,
      w1_ema200_direction: "BUY",
      is_w1_ema200_matched: false,
      is_w1_confirmation_passed: false,
      is_w1_confirmation_legacy: false,
      h1_direction_alignment_mode: "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
      h1_direction_alignment_state: "EMA200_FALLBACK_BUY",
      is_h1_direction_alignment_available: true,
      is_h1_direction_alignment_valid: true,
      h1_direction_alignment_direction: "BUY",
      is_h1_mn1_direction_matched: false,
      is_h1_w1_direction_matched: true,
      is_h1_direction_alignment_passed: true,
      is_h1_direction_alignment_legacy: false,
    },
    run: {
      id: 3,
      source_mode: "TESTER",
      program_version: "1.21",
      tester_model: "Open Prices only",
    },
    w1: null,
  };
}

function timeFrame(
  id: number,
  label: string,
  order: number,
  overrides: Partial<AlertTimeFrame> = {},
): AlertTimeFrame {
  return {
    id,
    alert_id: 74,
    time_frame: order,
    time_frame_text: label,
    time_frame_order: order,
    is_current_time_frame: label === "H1",
    is_buy: true,
    buy_sell_label: "BUY",
    wave_count: 4,
    is_wave_confirmed: label === "MN1",
    is_wave_motive: true,
    is_wave_uptrend: false,
    wave_trend_label: "▼",
    previous_last_elliot_label: "2",
    latest_wave_index: 3,
    point_count: 2,
    latest_elliot_index: 3,
    latest_elliot_label: "3",
    latest_sub_elliot_index: 3,
    latest_sub_elliot_label: "iii",
    previous_open: 1.2,
    previous_high: 1.3,
    previous_low: 1.1,
    previous_close: 1.25,
    current_open: 1.25,
    current_high: 1.3,
    current_low: 1.2,
    is_fibo_expansion_available: false,
    fe618_price: 0,
    fe1000_price: 0,
    fe1272_price: 0,
    fe1618_price: 0,
    fe2000_price: 0,
    distance_to_fe2000_pips: 0,
    oscillator_count: 3,
    is_oscillator_buy: true,
    stochastic_main_order: 1,
    stochastic_main_order_text: "BUY",
    stochastic_main_direction_text: "BUY",
    stochastic_short_count: 1,
    stochastic_short_main: 80,
    stochastic_short_signal: 70,
    stochastic_middle_count: 2,
    stochastic_middle_main: 70,
    stochastic_middle_signal: 60,
    stochastic_long_count: 3,
    stochastic_long_main: 60,
    stochastic_long_signal: 50,
    gmma_trend_count: 3,
    gmma_cross_count: -2,
    ema30: 1.24,
    ema60: 1.23,
    ema30_ema60_diff_pips: 10,
    is_ema200_available: true,
    ema200_close1: 1.25,
    ema200_shift1: 1.2,
    ema200_compare: 0.05,
    ema200_slope_pips: 2,
    ema200_close_diff_pips: 5,
    ema200_close_position: 1,
    ema200_slope_direction: 1,
    ema200_up_count: 3,
    ema200_down_count: 0,
    ema200_trend_count: 3,
    is_ema200_buy: false,
    is_ema200_sell: false,
    atr14_pips: 10,
    current_close: 1.23456,
    latest_point_is_added: label === "H4" ? true : label === "H1" ? null : false,
    created_at: 0,
    created_at_text: "2026.07.31 01:00:00",
    ...overrides,
  };
}

function point(id: number, timeFrame: string, order: number, pointOrder: number) {
  return {
    id,
    alert_id: 74,
    alert_timeframe_id: order + 1,
    time_frame: order,
    time_frame_text: timeFrame,
    time_frame_order: order,
    point_order: pointOrder,
    bar_time: id,
    bar_time_text: `2026.01.0${id} 00:00:00`,
    rate: 1.2 + id / 100,
    is_peak: true,
    elliot_label: "3-3-1",
    sub_elliot_label: "iii",
    pips_diff: 0,
    is_fibonacci_available: false,
    fibonacci_percent: 0,
    is_fibonacci_expansion_available: false,
    fibonacci_expansion_percent: 0,
    is_latest: id === 1,
    is_signal_reference: id === 1,
    is_added_point: false,
    is_correct: false,
  };
}


const frameNumbers = [49153, 32769, 16408, 16388, 16385, 15, 5];
const frameLabels = ["MN1", "W1", "D1", "H4", "H1", "M15", "M5"];

function fixture(status: AlertCorrectionResponse["status"] | null = "APPLIED", alertId = 74) {
  const detail = detailPayload(alertId);
  Object.assign(detail.alert, {
    time_frame: 5,
    time_frame_text: "M5",
    current_elliot_label: "3",
    reference_price: 1.25,
    is_stop_loss_available: true,
    stop_loss: 1.15,
    risk_pips: 100,
  });
  const timeFrames = frameLabels.map((label, index) => timeFrame(index + 1, label, index, {
    alert_id: alertId,
    time_frame: frameNumbers[index],
    is_current_time_frame: label === "M5",
    is_buy: status === "NONE" || label !== "H1",
    buy_sell_label: status !== "NONE" && label === "H1" ? "SELL" : "BUY",
    latest_elliot_label: status === "NONE" ? "3" : "2",
    latest_sub_elliot_label: status === "NONE" ? "iii" : "ii",
  }));
  const points = timeFrames.flatMap((row, index) => [0, 1].map((order) => ({
    ...point(index * 2 + order + 1, row.time_frame_text, index, order),
    alert_id: alertId,
    alert_timeframe_id: row.id,
    time_frame: row.time_frame,
    is_latest: order === 1,
    is_signal_reference: row.is_current_time_frame && order === 0,
    elliot_label: row.latest_elliot_label,
    sub_elliot_label: row.latest_sub_elliot_label,
  })));
  if (status !== null) {
    const metadata: AlertCorrectionMetadata = {
      alert_id: alertId,
      correction_status: status === "NONE" ? "NONE" : "APPLIED",
      correction_time_frame: status === "NONE" ? 0 : 16385,
      original_direction: status === "NONE" ? "" : "SELL",
      corrected_direction: status === "NONE" ? "" : "BUY",
      selected_analysis: status === "NONE" ? "ORIGINAL" : "CORRECTED",
      selected_alert_text: `Selected alert ${alertId}`,
      selected_current_elliot_label: "3",
      selected_wave_summary_text: "M5 3 / M15 3 / H1 3",
      reference_price: 1.25,
      is_selected_stop_loss_available: true,
      selected_stop_loss: status === "NONE" ? 1.15 : 1.2,
      selected_risk_pips: status === "NONE" ? 100 : 50,
      original_lc0: 1.155,
      original_lc5: 1.15,
      original_lc10: 1.145,
      original_lc15: 1.14,
      original_loss_cut_diff_pips: 95,
      original_loss_cut_diff_jpy: 950,
      corrected_lc0: status === "NONE" ? 0 : 1.205,
      corrected_lc5: status === "NONE" ? 0 : 1.2,
      corrected_lc10: status === "NONE" ? 0 : 1.195,
      corrected_lc15: status === "NONE" ? 0 : 1.19,
      corrected_loss_cut_diff_pips: status === "NONE" ? 0 : 45,
      corrected_loss_cut_diff_jpy: status === "NONE" ? 0 : 450,
      corrected_reference_point_time: status === "NONE" ? 0 : 1789824000,
      original_analysis_text: `Original analysis ${alertId}`,
      corrected_analysis_text: status === "NONE" ? "" : `Corrected analysis ${alertId}`,
      corrected_elliot_csv_text: status === "NONE" ? "" : "corrected,csv",
      comparison_hash: "0123456789abcdef",
      created_at: 1789824100,
      created_at_text: "2026.09.19 12:01:40",
    };
    detail.correction = {
      status,
      reason: status === "INCOMPLETE" ? "corrected_points_missing" : null,
      metadata: status === "UNRECORDED" ? null : metadata,
      timeframes: status === "APPLIED" ? timeFrames.map((row) => ({
        ...row,
        id: row.id + 100,
        is_buy: true,
        buy_sell_label: "BUY",
        latest_elliot_label: "3",
        latest_sub_elliot_label: "iii",
      })) : [],
      points: status === "APPLIED" ? points.map((row) => ({
        ...row,
        id: row.id + 100,
        alert_timeframe_id: row.alert_timeframe_id + 100,
        elliot_label: "3",
        sub_elliot_label: "iii",
      })) : [],
    };
  }
  return { detail, timeFrames, points };
}

type Fixture = ReturnType<typeof fixture>;
function responseFor(data: Fixture, path: string): Response {
  if (path === `/api/alerts/${data.detail.alert.id}`) return jsonResponse(data.detail);
  if (path === `/api/alerts/${data.detail.alert.id}/timeframes`) {
    return jsonResponse({ items: data.timeFrames, count: data.timeFrames.length });
  }
  if (path === `/api/alerts/${data.detail.alert.id}/points`) {
    return jsonResponse({ items: data.points, count: data.points.length });
  }
  throw new Error(`Unexpected API: ${path}`);
}

function serve(data: Fixture) {
  const mock = vi.fn(async (input: RequestInfo | URL) => responseFor(data, String(input)));
  vi.stubGlobal("fetch", mock);
  return mock;
}

function deferred() {
  let resolve!: (value: Response) => void;
  const promise = new Promise<Response>((done) => { resolve = done; });
  return { promise, resolve };
}

const snapshotName = "M5アラート補正スナップショット";
const h1PanelName = "ZigZagElliot H1エントリー条件";

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("AlertDetailDrawer correction integration", () => {
  it.each(["detail", "comparison"] as const)(
    "opens %s in the adopted M5 analysis and keeps the saved decision when browsing both analyses",
    async (initialView) => {
      const fetchMock = serve(fixture());
      render(<AlertDetailDrawer alertId={74} initialView={initialView} onClose={vi.fn()} />);
      const snapshot = await screen.findByRole("region", { name: snapshotName });
      expect(screen.getByRole("dialog")).toHaveClass("observation-grid-mode");
      expect(screen.queryByRole("region", { name: h1PanelName })).not.toBeInTheDocument();
      expect(within(snapshot).getByRole("button", { name: "補正後（採用）" }))
        .toHaveAttribute("aria-pressed", "true");
      const savedDecision = within(snapshot).getByRole("region", { name: "保存済みエントリー判定" });
      expect(savedDecision).toHaveTextContent("ENTRY");
      const fixedDecisionText = savedDecision.textContent;
      const lossCut = within(snapshot).getByRole("region", { name: "判定時の損切り候補" });
      expect(lossCut).toHaveTextContent("1.20000");
      const fixedLossCutText = lossCut.textContent;
      const table = within(snapshot).getByRole("table", { name: "M5アラート7時間足比較" });
      expect(table.querySelectorAll('tr[data-analysis="CORRECTED"]')).toHaveLength(7);
      expect(table.querySelectorAll('tr[data-analysis="ORIGINAL"]')).toHaveLength(0);
      fireEvent.click(within(snapshot).getByRole("button", { name: "補正前" }));
      expect(table.querySelector('tr[data-timeframe="H1"]')).toHaveTextContent("SELL");
      expect(table.querySelectorAll('tr[data-analysis="ORIGINAL"]')).toHaveLength(7);
      expect(within(snapshot).getByRole("region", { name: "保存済みエントリー判定" }).textContent)
        .toBe(fixedDecisionText);
      expect(within(snapshot).getByRole("region", { name: "判定時の損切り候補" }).textContent)
        .toBe(fixedLossCutText);
      fireEvent.click(within(snapshot).getByRole("button", { name: "前後比較" }));
      expect(table.querySelectorAll('tr[data-analysis="CORRECTED"]')).toHaveLength(7);
      expect(table.querySelectorAll('tr[data-analysis="ORIGINAL"]')).toHaveLength(7);
      expect(within(snapshot).getByRole("region", { name: "保存済みエントリー判定" }).textContent)
        .toBe(fixedDecisionText);
      expect(within(snapshot).getByRole("region", { name: "判定時の損切り候補" }).textContent)
        .toBe(fixedLossCutText);
      expect(fetchMock.mock.calls.map(([path]) => String(path)).sort()).toEqual([
        "/api/alerts/74", "/api/alerts/74/points", "/api/alerts/74/timeframes",
      ]);
    },
  );

  it.each(["NONE", "UNRECORDED", "INCOMPLETE", null] as const)(
    "opens %s without offering an unavailable corrected analysis",
    async (status) => {
      const fetchMock = serve(fixture(status));
      render(<AlertDetailDrawer alertId={74} onClose={vi.fn()} />);
      const snapshot = await screen.findByRole("region", { name: snapshotName });
      const originalLabel = status === "NONE" ? "元分析（採用）" : "元の保存分析";
      expect(within(snapshot).getByRole("button", { name: originalLabel }))
        .toHaveAttribute("aria-pressed", "true");
      expect(within(snapshot).queryByRole("button", { name: "補正後（採用）" }))
        .not.toBeInTheDocument();
      expect(within(snapshot).getByRole("button", { name: "前後比較" })).toBeDisabled();
      expect(within(snapshot).getByRole("button", { name: "補正前" })).toBeDisabled();
      expect(snapshot.querySelectorAll('tr[data-analysis="ORIGINAL"]')).toHaveLength(7);
      expect(screen.queryByRole("region", { name: h1PanelName })).not.toBeInTheDocument();
      expect(fetchMock).toHaveBeenCalledTimes(3);
    },
  );

  it.each(["numeric parent", "text parent", "current timeframe"])(
    "recognizes M5 from %s without relying on a correction record",
    async (evidence) => {
      const data = fixture(null);
      delete data.detail.alert.time_frame;
      delete data.detail.alert.time_frame_text;
      data.timeFrames.forEach((row) => { row.is_current_time_frame = false; });
      if (evidence === "numeric parent") data.detail.alert.time_frame = 5;
      if (evidence === "text parent") data.detail.alert.time_frame_text = "M5";
      if (evidence === "current timeframe") data.timeFrames[6].is_current_time_frame = true;
      serve(data);
      render(<AlertDetailDrawer alertId={74} initialView="comparison" onClose={vi.fn()} />);
      expect(await screen.findByRole("region", { name: snapshotName })).toBeInTheDocument();
      expect(screen.queryByRole("region", { name: h1PanelName })).not.toBeInTheDocument();
    },
  );

  it("keeps H1 on its existing entry-condition panel when M5 is only a child timeframe", async () => {
    const data = fixture(null);
    data.detail.alert.time_frame = 16385;
    data.detail.alert.time_frame_text = "H1";
    data.timeFrames.forEach((row) => { row.is_current_time_frame = row.time_frame_text === "H1"; });
    serve(data);
    render(<AlertDetailDrawer alertId={74} initialView="comparison" onClose={vi.fn()} />);
    expect(await screen.findByRole("region", { name: h1PanelName })).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: snapshotName })).not.toBeInTheDocument();
    expect(screen.getByText("TIMEFRAME COMPARISON")).toBeInTheDocument();
  });

  it("hides a displayed correction until all three responses for the next alert are ready", async () => {
    const oldData = fixture();
    const newData = fixture("NONE", 75);
    const pending = new Map<string, ReturnType<typeof deferred>>();
    const oldSignals: AbortSignal[] = [];
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input);
      if (path.startsWith("/api/alerts/74")) {
        if (init?.signal) oldSignals.push(init.signal);
        return Promise.resolve(responseFor(oldData, path));
      }
      const request = deferred();
      pending.set(path, request);
      return request.promise;
    });
    vi.stubGlobal("fetch", fetchMock);
    const view = render(<AlertDetailDrawer alertId={74} onClose={vi.fn()} />);
    const firstSnapshot = await screen.findByRole("region", { name: snapshotName });
    fireEvent.click(within(firstSnapshot).getByRole("button", { name: "前後比較" }));
    view.rerender(<AlertDetailDrawer alertId={75} onClose={vi.fn()} />);
    expect(screen.queryByRole("region", { name: snapshotName })).not.toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("詳細を読み込んでいます");
    expect(oldSignals).toHaveLength(3);
    oldSignals.forEach((signal) => expect(signal.aborted).toBe(true));
    await act(async () => {
      pending.get("/api/alerts/75")!.resolve(responseFor(newData, "/api/alerts/75"));
      pending.get("/api/alerts/75/timeframes")!.resolve(responseFor(newData, "/api/alerts/75/timeframes"));
    });
    expect(screen.queryByRole("region", { name: snapshotName })).not.toBeInTheDocument();
    await act(async () => {
      pending.get("/api/alerts/75/points")!.resolve(responseFor(newData, "/api/alerts/75/points"));
    });
    const nextSnapshot = await screen.findByRole("region", { name: snapshotName });
    expect(within(nextSnapshot).getByRole("button", { name: "元分析（採用）" }))
      .toHaveAttribute("aria-pressed", "true");
    expect(nextSnapshot).not.toHaveTextContent("Selected alert 74");
    expect(screen.getByRole("heading", { name: /USDJPY BUY/ })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(6);
  });

  it("ignores a late corrected snapshot after a newer alert has completed", async () => {
    const oldData = fixture();
    const newData = fixture("NONE", 75);
    const pending = new Map<string, ReturnType<typeof deferred>>();
    vi.stubGlobal("fetch", vi.fn((input: RequestInfo | URL) => {
      const path = String(input);
      if (path.startsWith("/api/alerts/74")) {
        const request = deferred();
        pending.set(path, request);
        return request.promise;
      }
      return Promise.resolve(responseFor(newData, path));
    }));
    const view = render(<AlertDetailDrawer alertId={74} onClose={vi.fn()} />);
    view.rerender(<AlertDetailDrawer alertId={75} onClose={vi.fn()} />);
    expect(await screen.findByRole("region", { name: snapshotName })).toBeInTheDocument();
    await act(async () => {
      pending.forEach((request, path) => request.resolve(responseFor(oldData, path)));
    });
    await waitFor(() => {
      expect(screen.getByRole("heading", { name: /USDJPY BUY/ })).toBeInTheDocument();
      expect(screen.getByRole("button", { name: "元分析（採用）" })).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "補正後（採用）" })).not.toBeInTheDocument();
    });
  });
});
