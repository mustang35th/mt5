import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type {
  ObservationDetailParent,
  ObservationDetailTimeFrame,
} from "../api/types";
import { ObservationDetailDrawer } from "./ObservationDetailDrawer";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

function errorResponse(message: string, status = 500): Response {
  return {
    ok: false,
    status,
    json: async () => ({ error: message }),
  } as Response;
}

function observation(id = 41): ObservationDetailParent {
  return {
    id,
    run_id: 7,
    run_uid: "run-7",
    source_mode: "TESTER",
    source: "ZigZagElliot",
    source_server: "MetaQuotes-Demo",
    symbol_name: id === 41 ? "CADJPY" : "EURUSD",
    is_gmo_target: id === 41,
    anchor_bar_time: 1_786_384_800,
    anchor_bar_time_text: "2026.08.10 05:00:00",
    anchor_jst_time: 1_786_406_400,
    anchor_jst_time_text: "2026.08.10 11:00:00",
    anchor_time_frame: 16_385,
    anchor_time_frame_text: "H1",
    capture_phase: "BAR_OPEN_FIRST_SUCCESS",
    analysis_version: "2.0",
    analysis_input_hash: "analysis-hash",
    snapshot_hash: "snapshot-hash",
    time_frame_count: 5,
    created_at: 1_786_406_401,
    created_at_text: "2026.08.10 11:00:01",
    program_name: "ZigZagElliot",
    program_version: "1.30",
    strategy: "MTF_3in3",
    strategy_version: "1.0",
    tester_from: 1_672_531_200,
    tester_to: 1_786_406_400,
    tester_model: "Open Prices only",
    started_at: 1_786_320_000,
    started_at_text: "2026.08.09 11:00:00",
  };
}

function timeFrame(id: number, label: string, order: number): ObservationDetailTimeFrame {
  return {
    id,
    observation_id: 41,
    time_frame: 16_385 + order,
    time_frame_text: label,
    time_frame_order: order,
    is_anchor_time_frame: label === "H1",
    is_buy: true,
    buy_sell_label: "BUY",
    wave_count: 3,
    latest_wave_index: 2,
    is_wave_confirmed: label !== "H1",
    is_wave_motive: true,
    is_wave_uptrend: label === "MN1",
    wave_trend_label: "Бе",
    previous_last_elliot_label: "A",
    point_count: 4,
    latest_elliot_index: 3,
    latest_elliot_label: "3",
    latest_sub_elliot_index: 1,
    latest_sub_elliot_label: "i",
    latest_point_time: 1_786_384_800,
    latest_point_time_text: `2026.08.10 05:0${order}:00`,
    latest_point_jst_time: 1_786_406_400,
    latest_point_jst_time_text: `2026.08.10 11:0${order}:00`,
    latest_point_rate: 105.12345 + order,
    previous_open: 105.1,
    previous_high: 105.3,
    previous_low: 105.0,
    previous_close: 105.2,
    current_open: 105.2,
    current_high: 105.4,
    current_low: 105.1,
    current_close: 105.35,
    is_fibo_expansion_available: true,
    fe618_price: 105.5,
    fe1000_price: 105.7,
    fe1272_price: 105.9,
    fe1618_price: 106.1,
    fe2000_price: 106.3,
    distance_to_fe2000_pips: 95.0,
    oscillator_count: 2,
    is_oscillator_buy: true,
    stochastic_main_order: 1,
    stochastic_main_order_text: "短期>中期>長期",
    stochastic_main_direction_text: "BUY",
    stochastic_short_count: 3,
    stochastic_short_main: 75.12,
    stochastic_short_signal: 70.34,
    stochastic_middle_count: 2,
    stochastic_middle_main: 65.12,
    stochastic_middle_signal: 60.34,
    stochastic_long_count: 1,
    stochastic_long_main: 55.12,
    stochastic_long_signal: 50.34,
    gmma_trend_count: 4,
    gmma_cross_count: 1,
    ema30: 105.25,
    ema60: 105.15,
    ema30_ema60_diff_pips: 10.0,
    atr14_pips: 32.5,
    ema200_close1: 105.2,
    ema200_shift1: 104.9,
    ema200_compare: 104.8,
    ema200_slope_pips: 2.5,
    ema200_close_diff_pips: 30.0,
    ema200_close_position: 1,
    ema200_slope_direction: 1,
    ema200_up_count: 5,
    ema200_down_count: 0,
    ema200_trend_count: 5,
    is_ema200_buy: true,
    is_ema200_sell: false,
    created_at: 1_786_406_401,
    created_at_text: `2026.08.10 11:00:0${order}`,
  };
}

function detailPayload(id = 41) {
  return {
    available: true,
    observation: observation(id),
    time_frames: [
      timeFrame(4, "H4", 3),
      timeFrame(1, "MN1", 0),
      timeFrame(5, "H1", 4),
      timeFrame(3, "D1", 2),
      timeFrame(2, "W1", 1),
    ],
  };
}

function detailPayloadWithM5() {
  const payload = detailPayload();
  return {
    ...payload,
    observation: {
      ...payload.observation,
      time_frame_count: 6,
    },
    time_frames: [
      timeFrame(6, "M5", 5),
      ...payload.time_frames,
    ],
  };
}

function provideGridLayoutSize() {
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(1_440);
  vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockReturnValue(800);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(1_440);
  vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(800);
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue({
    bottom: 800,
    height: 800,
    left: 0,
    right: 1_440,
    top: 0,
    width: 1_440,
    x: 0,
    y: 0,
    toJSON: () => ({}),
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("ObservationDetailDrawer", () => {
  it("renders the stored detail values and orders the five timeframe cards", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(detailPayload()));
    vi.stubGlobal("fetch", fetchMock);
    const onClose = vi.fn();

    render(<ObservationDetailDrawer observationId={41} onClose={onClose} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/observations/41",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );
    expect(screen.getByText("JST 2026.08.10 11:00:00 / Server 2026.08.10 05:00:00")).toBeInTheDocument();
    expect(screen.getByText("Run 7")).toBeInTheDocument();
    expect(screen.getByLabelText("GMO取引 対象")).toBeInTheDocument();
    expect(screen.getAllByText("▲ 上昇")).toHaveLength(1);
    expect(screen.getAllByText("▼ 下降")).toHaveLength(4);
    expect(screen.getAllByText("▲3 [3] / i [1]")).toHaveLength(1);
    expect(screen.getAllByText("▼3 [3] / i [1]")).toHaveLength(4);
    expect(screen.queryByText("Бе")).not.toBeInTheDocument();
    expect(screen.getAllByText(/O 105\.10000 \/ H 105\.30000/)).toHaveLength(5);
    expect(screen.getAllByText("105.50000 / 105.70000")).toHaveLength(5);
    expect(screen.getAllByText("count +3 / Main 75.12 / Signal 70.34")).toHaveLength(5);
    expect(screen.getAllByText("BUY / count +2")).toHaveLength(5);
    expect(screen.getAllByText("+4 / +1")).toHaveLength(5);
    expect(screen.getAllByText("+10.0 pips")).toHaveLength(5);
    expect(screen.getAllByText("対象外（MN1は計算省略）")).toHaveLength(3);
    expect(screen.getAllByText("終値が上（距離 +30.0 pips）")).toHaveLength(4);
    expect(screen.getAllByText("上向き（+2.5 pips）")).toHaveLength(4);
    expect(screen.getAllByText("上昇優勢 +5（上昇 5回 / 下降 0回）")).toHaveLength(4);
    expect(screen.getAllByText("105.25000 / 105.15000")).toHaveLength(5);
    expect(screen.queryByRole("table")).not.toBeInTheDocument();

    const cards = screen.getAllByRole("article");
    expect(cards.map((card) => card.getAttribute("aria-label"))).toEqual([
      "MN1 時間足詳細",
      "W1 時間足詳細",
      "D1 時間足詳細",
      "H4 時間足詳細",
      "H1 時間足詳細",
    ]);
    expect(within(cards[0]).getByLabelText("EMA200判定 対象外。MN1は計算を省略"))
      .toHaveTextContent("EMA200 SKIP");
    expect(within(cards[4]).getByLabelText("EMA200判定 BUY"))
      .toHaveTextContent("EMA200 ↑ BUY");
    expect(screen.getByText("analysis-hash")).not.toBeVisible();
    fireEvent.click(screen.getByText("監査情報を表示"), { detail: 1 });
    expect(screen.getByText("analysis-hash")).toBeVisible();
    expect(screen.getByRole("button", { name: "H1観測詳細を閉じる" })).toHaveFocus();
  });

  it("switches between cards and the full-screen grid without refetching", async () => {
    provideGridLayoutSize();
    const fetchMock = vi.fn(async () => jsonResponse(detailPayload()));
    vi.stubGlobal("fetch", fetchMock);

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    const dialog = screen.getByRole("dialog");
    const cardButton = screen.getByRole("button", { name: "カード表示" });
    const gridButton = screen.getByRole("button", { name: "全画面グリッド" });

    expect(cardButton).toHaveAttribute("aria-pressed", "true");
    expect(gridButton).toHaveAttribute("aria-pressed", "false");
    expect(dialog).not.toHaveClass("observation-grid-mode");
    expect(screen.getAllByRole("article")).toHaveLength(5);
    expect(screen.queryByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" })).not.toBeInTheDocument();

    fireEvent.click(gridButton);

    expect(cardButton).toHaveAttribute("aria-pressed", "false");
    expect(gridButton).toHaveAttribute("aria-pressed", "true");
    expect(dialog).toHaveClass("observation-grid-mode");
    expect(screen.getByLabelText("GMO取引 対象")).toBeInTheDocument();
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    await waitFor(() => {
      const hasValue = (columnId: string, expected: string) => Array.from(
        grid.querySelectorAll<HTMLElement>(`.ag-cell[col-id="${columnId}"]`),
      ).some((cell) => cell.textContent?.includes(expected));
      expect(hasValue("oscillator", "BUY / count +2")).toBe(true);
      expect(hasValue("elliott_sub", "▲3 [3] / i [1]")).toBe(true);
      expect(hasValue("elliott_sub", "▼3 [3] / i [1]")).toBe(true);
      expect(hasValue("wave_direction", "▲ 上昇")).toBe(true);
      expect(hasValue("wave_direction", "▼ 下降")).toBe(true);
      expect(hasValue("stochastic_short", "count +3 / Main 75.12 / Signal 70.34")).toBe(true);
      expect(hasValue("gmma_trend_cross", "+4 / +1")).toBe(true);
      expect(hasValue("ema30_ema60_diff_pips", "+10.0 pips")).toBe(true);
      expect(hasValue("ema200_slope_distance", "+2.5 / +30.0 pips")).toBe(true);
      expect(hasValue("ema200_position_slope_code", "+1 / +1")).toBe(true);
      expect(hasValue("ema200_counts", "5 / 0 / +5")).toBe(true);

      const skipBadge = within(grid).getByLabelText("EMA200判定 対象外。MN1は計算を省略");
      expect(skipBadge).toHaveTextContent("EMA200 SKIP");
      expect(skipBadge).toHaveClass("badge", "neutral", "observation-ema200-badge");
      expect(skipBadge.closest(".ag-cell")).toHaveAttribute("col-id", "ema200_direction");

      const buyBadges = within(grid).getAllByLabelText("EMA200判定 BUY");
      expect(buyBadges).toHaveLength(4);
      for (const buyBadge of buyBadges) {
        expect(buyBadge).toHaveTextContent("EMA200 ↑ BUY");
        expect(buyBadge).toHaveClass("badge", "buy", "observation-ema200-badge");
        expect(buyBadge.closest(".ag-cell")).toHaveAttribute("col-id", "ema200_direction");
      }

      const headerColumnIds = Array.from(
        grid.querySelectorAll<HTMLElement>(".ag-header-cell[col-id]"),
      ).map((header) => header.getAttribute("col-id"));
      const directionIndex = headerColumnIds.indexOf("buy_sell_label");
      expect(directionIndex).toBeGreaterThanOrEqual(0);
      expect(headerColumnIds[directionIndex + 1]).toBe("ema200_direction");
    });
    expect(screen.queryByRole("article")).not.toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(1);

    fireEvent.click(cardButton);

    expect(cardButton).toHaveAttribute("aria-pressed", "true");
    expect(gridButton).toHaveAttribute("aria-pressed", "false");
    expect(dialog).not.toHaveClass("observation-grid-mode");
    expect(screen.queryByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" })).not.toBeInTheDocument();
    expect(screen.getAllByRole("article")).toHaveLength(5);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("renders future timeframe rows dynamically in stored order", async () => {
    provideGridLayoutSize();
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayloadWithM5())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));

    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    expect((await within(grid).findAllByRole("rowheader")).map((cell) => cell.textContent)).toEqual([
      "MN1",
      "W1",
      "D1",
      "H4",
      "H1基準足",
      "M5",
    ]);
  });

  it("keeps only the timeframe column pinned on narrow screens", async () => {
    provideGridLayoutSize();
    vi.spyOn(window, "matchMedia").mockImplementation((query: string): MediaQueryList => ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      addListener: () => undefined,
      removeListener: () => undefined,
      dispatchEvent: () => true,
    }));
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayload())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));

    await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    const region = screen.getByRole("region", { name: "時間足別 H1新規足スナップショットグリッド" });
    await waitFor(() => {
      const pinnedAreas = region.querySelectorAll<HTMLElement>(".ag-grid-pinned-left-cells");
      const timeFrameCells = region.querySelectorAll<HTMLElement>('.ag-cell[col-id="time_frame_text"]');
      const directionCells = region.querySelectorAll<HTMLElement>('.ag-cell[col-id="buy_sell_label"]');
      const ema200Cells = region.querySelectorAll<HTMLElement>('.ag-cell[col-id="ema200_direction"]');
      const elliottCells = region.querySelectorAll<HTMLElement>('.ag-cell[col-id="elliott_sub"]');
      expect(pinnedAreas.length).toBeGreaterThan(0);
      expect(Array.from(pinnedAreas).every((area) => area.style.width === "132px")).toBe(true);
      expect(timeFrameCells.length).toBeGreaterThan(0);
      expect(Array.from(timeFrameCells).every((cell) => cell.classList.contains("ag-cell-last-left-pinned"))).toBe(true);
      expect(Array.from(directionCells).some((cell) => cell.classList.contains("ag-cell-last-left-pinned"))).toBe(false);
      expect(Array.from(ema200Cells).some((cell) => cell.classList.contains("ag-cell-last-left-pinned"))).toBe(false);
      expect(Array.from(elliottCells).some((cell) => cell.classList.contains("ag-cell-last-left-pinned"))).toBe(false);
    });
  });

  it("shows the optional-table unavailable state", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse({
      available: false,
      observation: null,
      time_frames: [],
    })));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} />);

    expect(await screen.findByText("H1観測DBはまだ利用されていません")).toHaveAttribute("role", "status");
    expect(screen.queryByRole("article")).not.toBeInTheDocument();
  });

  it("shows a 404 detail error without disabling close", async () => {
    const onClose = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async () => errorResponse("observation was not found", 404)));

    render(<ObservationDetailDrawer observationId={404} onClose={onClose} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("observation was not found");
    fireEvent.click(screen.getByRole("button", { name: "H1観測詳細を閉じる" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("aborts the stale detail request when the observation ID changes", async () => {
    let resolveOld!: (response: Response) => void;
    const oldRequest = new Promise<Response>((resolve) => {
      resolveOld = resolve;
    });
    const oldSignals: AbortSignal[] = [];
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === "/api/observations/41") {
        if (init?.signal) oldSignals.push(init.signal);
        return oldRequest;
      }
      if (String(input) === "/api/observations/42") {
        return Promise.resolve(jsonResponse(detailPayload(42)));
      }
      return Promise.reject(new Error(`unexpected path: ${String(input)}`));
    });
    vi.stubGlobal("fetch", fetchMock);

    const view = render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} />);
    view.rerender(<ObservationDetailDrawer observationId={42} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "EURUSD / 2026.08.10 11:00:00" })).toBeInTheDocument();
    expect(oldSignals).toHaveLength(1);
    expect(oldSignals[0].aborted).toBe(true);
    resolveOld(jsonResponse(detailPayload(41)));
    await waitFor(() => {
      expect(screen.queryByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).not.toBeInTheDocument();
    });
  });

  it("closes on cancel and only on a pointer backdrop click", () => {
    const onClose = vi.fn();
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(() => undefined)));
    render(<ObservationDetailDrawer observationId={41} onClose={onClose} />);
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
});
