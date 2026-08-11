import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AlertDetailDrawer } from "./AlertDetailDrawer";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

function errorResponse(message: string): Response {
  return {
    ok: false,
    status: 500,
    json: async () => ({ error: message }),
  } as Response;
}

function detailPayload(alertId = 74) {
  return {
    alert: {
      id: alertId,
      run_id: 3,
      symbol_name: alertId === 74 ? "AUDUSD" : "USDJPY",
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
      currency_strength_status: 0,
      is_currency_strength_available: false,
      long_medium_rank_difference: 0,
      medium_short_rank_difference: 0,
      market_signal_key: `market-${alertId}`,
      alert_text: "<script>alert('x')</script>",
      is_w1_aligned: null,
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

function timeFrame(id: number, label: string, order: number) {
  return {
    id,
    time_frame_text: label,
    time_frame_order: order,
    buy_sell_label: "BUY",
    is_wave_confirmed: label === "MN1",
    is_wave_motive: true,
    is_wave_uptrend: false,
    wave_trend_label: "DOWN",
    latest_wave_index: 3,
    point_count: 2,
    latest_elliot_label: "3",
    latest_sub_elliot_label: "iii",
    stochastic_main_order_text: "BUY",
    stochastic_main_direction_text: "BUY",
    gmma_trend_count: 0,
    gmma_cross_count: 0,
    is_ema200_buy: false,
    is_ema200_sell: false,
    atr14_pips: 10,
    is_fibo_expansion_available: false,
    distance_to_fe2000_pips: 0,
    current_close: 1.23456,
  };
}

function point(id: number, timeFrame: string, order: number, pointOrder: number) {
  return {
    id,
    time_frame_text: timeFrame,
    time_frame_order: order,
    point_order: pointOrder,
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

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("AlertDetailDrawer", () => {
  it("loads the three detail APIs and renders analysis and wave data without treating zero as missing", async () => {
    const timeFrames = [
      timeFrame(1, "MN1", 0),
      timeFrame(2, "W1", 1),
      timeFrame(3, "D1", 2),
      timeFrame(4, "H4", 3),
      timeFrame(5, "H1", 4),
    ];
    const points = [point(1, "MN1", 0, 0), point(2, "H1", 1, 0)];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/74") return jsonResponse(detailPayload());
      if (path.endsWith("/timeframes")) return jsonResponse({ items: timeFrames, count: timeFrames.length });
      if (path.endsWith("/points")) return jsonResponse({ items: points, count: points.length });
      throw new Error(`unexpected path: ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    const onClose = vi.fn();
    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);

    expect(await screen.findByRole("heading", { name: "AUDUSD BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(screen.getByText("W1不明")).toBeInTheDocument();
    expect(screen.getAllByText("DOWN / 下降 (DOWN)")).toHaveLength(5);
    expect(screen.getByText("0.00000")).toBeInTheDocument();
    expect(screen.getByText(/SL — \/ Risk 50.0 pips/)).toBeInTheDocument();
    expect(screen.getAllByText("未取得").length).toBeGreaterThan(0);
    const cards = screen.getAllByRole("article");
    expect(cards).toHaveLength(5);
    expect(cards.map((card) => card.querySelector(".timeframe-header > strong")?.textContent)).toEqual([
      "MN1",
      "W1",
      "D1",
      "H4",
      "H1",
    ]);
    expect(screen.getByText("最新・基準").closest("tr")).toHaveClass("point-latest", "point-reference");
    expect(screen.getByText("<script>alert('x')</script>")).toBeInTheDocument();
    fireEvent.click(screen.getByText("アラート本文を表示"), { detail: 1 });
    expect(onClose).not.toHaveBeenCalled();
    expect(document.querySelector("img")).toBeNull();
    expect(document.querySelector("script:not([type='module'])")).toBeNull();
    expect(screen.getByRole("button", { name: "詳細を閉じる" })).toHaveFocus();
  });

  it("aborts stale requests and keeps the newest alert detail", async () => {
    let resolveOld!: (response: Response) => void;
    const oldPromise = new Promise<Response>((resolve) => {
      resolveOld = resolve;
    });
    const oldSignals: AbortSignal[] = [];
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input);
      if (path.includes("/74")) {
        if (init?.signal) oldSignals.push(init.signal);
        return oldPromise;
      }
      if (path === "/api/alerts/75") return Promise.resolve(jsonResponse(detailPayload(75)));
      if (path.endsWith("/timeframes")) return Promise.resolve(jsonResponse({ items: [], count: 0 }));
      if (path.endsWith("/points")) return Promise.resolve(jsonResponse({ items: [], count: 0 }));
      return Promise.reject(new Error(`unexpected path: ${path}`));
    });
    vi.stubGlobal("fetch", fetchMock);

    const view = render(<AlertDetailDrawer alertId={74} onClose={vi.fn()} />);
    view.rerender(<AlertDetailDrawer alertId={75} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "USDJPY BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    expect(oldSignals).toHaveLength(3);
    oldSignals.forEach((signal) => expect(signal.aborted).toBe(true));
    resolveOld(jsonResponse(detailPayload(74)));
    await waitFor(() => expect(screen.queryByText("AUDUSD BUY / 2026.07.30 19:00:00")).not.toBeInTheDocument());
  });

  it("closes on cancel and an outside pointer action", () => {
    const onClose = vi.fn();
    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);
    const dialog = screen.getByRole("dialog") as HTMLDialogElement;
    fireEvent(dialog, new Event("cancel", { bubbles: false, cancelable: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
    vi.spyOn(dialog, "getBoundingClientRect").mockReturnValue({
      left: 100,
      right: 900,
      top: 0,
      bottom: 800,
      width: 800,
      height: 800,
      x: 100,
      y: 0,
      toJSON: () => ({}),
    });
    fireEvent.click(dialog, { clientX: 10, clientY: 100, detail: 0 });
    expect(onClose).toHaveBeenCalledTimes(1);
    fireEvent.click(dialog, { clientX: 10, clientY: 100, detail: 1 });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it("shows a detail error without disabling the close action", async () => {
    const onClose = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/74") return errorResponse("detail failed");
      return jsonResponse({ items: [], count: 0 });
    }));

    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);
    expect(await screen.findByRole("alert")).toHaveTextContent("detail failed");
    fireEvent.click(screen.getByRole("button", { name: "詳細を閉じる" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
