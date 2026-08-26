import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type {
  ObservationDetailNavigation,
  ObservationDetailParent,
  ObservationDetailTimeFrame,
  ObservationNavigationItem,
} from "../api/types";
import { TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY } from "../lib/timeFrameComparisonPreferences";
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
    spread_pips: 1.2,
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

function navigationItem(
  id: number,
  jstTimeText: string,
  serverTimeText: string,
  runId = 7,
): ObservationNavigationItem {
  return {
    id,
    run_id: runId,
    anchor_jst_time: 1_786_406_400 + ((id - 41) * 3_600),
    anchor_jst_time_text: jstTimeText,
    anchor_bar_time: 1_786_384_800 + ((id - 41) * 3_600),
    anchor_bar_time_text: serverTimeText,
  };
}

const DEFAULT_NAVIGATION: ObservationDetailNavigation = {
  older: navigationItem(40, "2026.08.10 10:00:00", "2026.08.10 04:00:00", 6),
  newer: navigationItem(42, "2026.08.10 12:00:00", "2026.08.10 06:00:00", 8),
};

function detailPayload(
  id = 41,
  navigation: ObservationDetailNavigation = DEFAULT_NAVIGATION,
) {
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
    navigation,
  };
}

function detailPayloadAt(
  id: number,
  jstTimeText: string,
  serverTimeText: string,
  navigation: ObservationDetailNavigation,
) {
  const payload = detailPayload(id, navigation);
  return {
    ...payload,
    observation: {
      ...payload.observation,
      symbol_name: "CADJPY",
      anchor_jst_time_text: jstTimeText,
      anchor_bar_time_text: serverTimeText,
    },
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

function NavigationHarness({
  onNavigate,
}: {
  onNavigate: (observationId: number) => void;
}) {
  const [observationId, setObservationId] = useState(41);
  return (
    <ObservationDetailDrawer
      observationId={observationId}
      onClose={vi.fn()}
      onNavigate={(nextObservationId) => {
        onNavigate(nextObservationId);
        setObservationId(nextObservationId);
      }}
    />
  );
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

const COMPARISON_KEY_COLUMN_IDS = [
  "time_frame_text",
  "buy_sell_label",
  "ema200_direction",
  "elliott_sub",
] as const;

const COLUMN_GROUP_IDS = {
  wave: [
    "wave_direction",
    "wave_state",
    "wave_type",
    "wave_count_latest_index",
    "previous_last_elliot_label",
    "point_count",
  ],
  price: [
    "latest_point_jst_time_text",
    "latest_point_time_text",
    "latest_point_rate",
    "previous_ohlc",
    "current_ohlc",
  ],
  fibo_expansion: [
    "fibo_expansion_status",
    "fe618_fe1000",
    "fe1272_fe1618",
    "fe2000_price",
    "distance_to_fe2000_pips",
  ],
  oscillator_stochastic: [
    "oscillator",
    "stochastic",
    "stochastic_short",
    "stochastic_middle",
    "stochastic_long",
  ],
  trend_ema: [
    "gmma_trend_cross",
    "ema30_ema60",
    "ema30_ema60_diff_pips",
    "atr14_pips",
    "ema200_close1_shift1",
    "ema200_compare",
    "ema200_slope_distance",
    "ema200_position_slope_code",
    "ema200_counts",
  ],
} as const;

type ColumnGroupId = keyof typeof COLUMN_GROUP_IDS;

const COLUMN_GROUP_LABELS: Record<ColumnGroupId, string> = {
  wave: "波動",
  price: "最新ポイント・価格",
  fibo_expansion: "Fibo / FE",
  oscillator_stochastic: "Oscillator / Stochastic",
  trend_ema: "Trend / EMA",
};

const COLUMN_GROUP_REPRESENTATIVES: Record<ColumnGroupId, string> = {
  wave: "wave_direction",
  price: "latest_point_rate",
  fibo_expansion: "fibo_expansion_status",
  oscillator_stochastic: "oscillator",
  trend_ema: "gmma_trend_cross",
};

function displayedColumnIds(grid: HTMLElement): string[] {
  return Array.from(
    grid.querySelectorAll<HTMLElement>(".ag-header-cell[col-id]"),
  ).flatMap((header) => {
    const columnId = header.getAttribute("col-id");
    return columnId ? [columnId] : [];
  });
}

function expectedColumnIds(openGroups: readonly ColumnGroupId[]): string[] {
  const openGroupSet = new Set<ColumnGroupId>(openGroups);
  const columns: string[] = [...COMPARISON_KEY_COLUMN_IDS];
  for (const groupId of Object.keys(COLUMN_GROUP_IDS) as ColumnGroupId[]) {
    if (openGroupSet.has(groupId)) {
      columns.push(...COLUMN_GROUP_IDS[groupId]);
    } else {
      columns.push(COLUMN_GROUP_REPRESENTATIVES[groupId]);
    }
  }
  return columns;
}

function columnGroupHeader(grid: HTMLElement, groupId: ColumnGroupId): HTMLElement {
  const header = Array.from(
    grid.querySelectorAll<HTMLElement>(".ag-header-group-cell"),
  ).find((item) => item.querySelector(".ag-header-group-text")?.textContent
    === COLUMN_GROUP_LABELS[groupId]);
  if (!header) throw new Error(`column group header not found: ${groupId}`);
  return header;
}

async function expectColumnLayout(
  grid: HTMLElement,
  openGroups: readonly ColumnGroupId[],
): Promise<void> {
  await waitFor(() => {
    expect(displayedColumnIds(grid)).toEqual(expectedColumnIds(openGroups));
    for (const groupId of Object.keys(COLUMN_GROUP_IDS) as ColumnGroupId[]) {
      expect(columnGroupHeader(grid, groupId)).toHaveAttribute(
        "aria-expanded",
        String(openGroups.includes(groupId)),
      );
    }
  });
}

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("ObservationDetailDrawer", () => {
  it("renders the stored detail values and orders the five timeframe cards", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(detailPayload()));
    vi.stubGlobal("fetch", fetchMock);
    const onClose = vi.fn();

    render(<ObservationDetailDrawer observationId={41} onClose={onClose} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/observations/41",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );
    expect(screen.getByText("JST 2026.08.10 11:00:00 / Server 2026.08.10 05:00:00")).toBeInTheDocument();
    expect(screen.getByText("Run 7")).toBeInTheDocument();
    expect(screen.getByText("1.2 pips")).toBeInTheDocument();
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

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

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
    expect(screen.getByText("Spread 1.2 pips")).toBeInTheDocument();
    expect(screen.getByLabelText("GMO取引 対象")).toBeInTheDocument();
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    await expectColumnLayout(grid, []);
    expect(screen.getByRole("button", { name: "列プリセット: 要点のみ" }))
      .toHaveAttribute("aria-pressed", "true");
    await waitFor(() => {
      const hasValue = (columnId: string, expected: string) => Array.from(
        grid.querySelectorAll<HTMLElement>(`.ag-cell[col-id="${columnId}"]`),
      ).some((cell) => cell.textContent?.includes(expected));
      expect(hasValue("oscillator", "BUY / count +2")).toBe(true);
      expect(hasValue("elliott_sub", "▲3 [3] / i [1]")).toBe(true);
      expect(hasValue("elliott_sub", "▼3 [3] / i [1]")).toBe(true);
      expect(hasValue("wave_direction", "▲ 上昇")).toBe(true);
      expect(hasValue("wave_direction", "▼ 下降")).toBe(true);
      expect(hasValue("gmma_trend_cross", "+4 / +1")).toBe(true);

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

    fireEvent.click(screen.getByRole("button", { name: "列プリセット: すべて展開" }));
    await expectColumnLayout(grid, [
      "wave",
      "price",
      "fibo_expansion",
      "oscillator_stochastic",
      "trend_ema",
    ]);
    await waitFor(() => {
      const hasValue = (columnId: string, expected: string) => Array.from(
        grid.querySelectorAll<HTMLElement>(`.ag-cell[col-id="${columnId}"]`),
      ).some((cell) => cell.textContent?.includes(expected));
      expect(hasValue("stochastic_short", "count +3 / Main 75.12 / Signal 70.34")).toBe(true);
      expect(hasValue("ema30_ema60_diff_pips", "+10.0 pips")).toBe(true);
      expect(hasValue("ema200_slope_distance", "+2.5 / +30.0 pips")).toBe(true);
      expect(hasValue("ema200_position_slope_code", "+1 / +1")).toBe(true);
      expect(hasValue("ema200_counts", "5 / 0 / +5")).toBe(true);
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

  it("distinguishes an unrecorded spread from a valid zero spread", async () => {
    const legacyPayload = detailPayload();
    legacyPayload.observation.spread_pips = null;
    const zeroPayload = detailPayload();
    zeroPayload.observation.spread_pips = 0;
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(legacyPayload))
      .mockResolvedValueOnce(jsonResponse(zeroPayload));
    vi.stubGlobal("fetch", fetchMock);

    const { rerender } = render(
      <ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />,
    );

    expect(await screen.findByText("未記録")).toBeInTheDocument();

    rerender(
      <ObservationDetailDrawer observationId={42} onClose={vi.fn()} onNavigate={vi.fn()} />,
    );

    expect(await screen.findByText("0.0 pips")).toBeInTheDocument();
  });

  it("colors Elliott wave values independently from the analysis direction", async () => {
    provideGridLayoutSize();
    const payload = detailPayload();
    const mn1TimeFrame = payload.time_frames.find(
      (item) => item.time_frame_text === "MN1",
    );
    const h1TimeFrame = payload.time_frames.find(
      (item) => item.time_frame_text === "H1",
    );
    if (!mn1TimeFrame || !h1TimeFrame) {
      throw new Error("Elliott wave test fixtures not found");
    }
    Object.assign(mn1TimeFrame, {
      is_buy: false,
      buy_sell_label: "SELL",
      is_wave_uptrend: true,
    });
    Object.assign(h1TimeFrame, {
      is_buy: true,
      buy_sell_label: "BUY",
      is_wave_uptrend: false,
    });
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(payload)));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    fireEvent.click(screen.getByRole("button", { name: "列プリセット: すべて展開" }));
    await expectColumnLayout(grid, [
      "wave",
      "price",
      "fibo_expansion",
      "oscillator_stochastic",
      "trend_ema",
    ]);

    const cellAtTimeFrame = (
      timeFrameLabel: string,
      columnId: string,
    ): HTMLElement => {
      const timeFrameCell = Array.from(
        grid.querySelectorAll<HTMLElement>('.ag-cell[col-id="time_frame_text"]'),
      ).find((cell) => cell.textContent?.includes(timeFrameLabel));
      const rowIndex = timeFrameCell?.closest<HTMLElement>(".ag-row")
        ?.getAttribute("row-index");
      if (rowIndex === null || rowIndex === undefined) {
        throw new Error(`row not found: ${timeFrameLabel}`);
      }
      const cell = grid.querySelector<HTMLElement>(
        `.ag-row[row-index="${rowIndex}"] .ag-cell[col-id="${columnId}"]`,
      );
      if (!cell) throw new Error(`cell not found: ${timeFrameLabel}/${columnId}`);
      return cell;
    };
    const expectWaveTone = (
      timeFrameLabel: string,
      columnId: string,
      expectedText: string,
      expectedTone: "uptrend" | "downtrend",
    ): void => {
      const cell = cellAtTimeFrame(timeFrameLabel, columnId);
      expect(cell).toHaveTextContent(expectedText);
      const waveValue = cell.querySelector<HTMLElement>(
        ".snapshot-elliott-wave-value",
      );
      expect(waveValue).not.toBeNull();
      expect(waveValue).toHaveTextContent(expectedText);
      expect(waveValue).toHaveClass(expectedTone);
      expect(waveValue).not.toHaveClass("positive");
      expect(waveValue).not.toHaveClass("negative");
      expect(cell.querySelector(".snapshot-signed-value")).toBeNull();
    };

    await waitFor(() => {
      expectWaveTone("MN1", "elliott_sub", "▲3 [3] / i [1]", "uptrend");
      expectWaveTone("MN1", "wave_direction", "▲ 上昇", "uptrend");
      expectWaveTone("H1", "elliott_sub", "▼3 [3] / i [1]", "downtrend");
      expectWaveTone("H1", "wave_direction", "▼ 下降", "downtrend");

      const mn1Analysis = cellAtTimeFrame("MN1", "buy_sell_label");
      expect(mn1Analysis).toHaveTextContent("SELL");
      expect(mn1Analysis.querySelector(".badge")).toHaveClass("sell");
      const h1Analysis = cellAtTimeFrame("H1", "buy_sell_label");
      expect(h1Analysis).toHaveTextContent("BUY");
      expect(h1Analysis.querySelector(".badge")).toHaveClass("buy");

      for (const columnId of [
        "buy_sell_label",
        "wave_state",
        "wave_type",
        "wave_count_latest_index",
        "previous_last_elliot_label",
        "point_count",
        "latest_point_jst_time_text",
        "latest_point_time_text",
        "latest_point_rate",
        "previous_ohlc",
        "current_ohlc",
        "fibo_expansion_status",
        "fe618_fe1000",
        "fe1272_fe1618",
        "fe2000_price",
        "distance_to_fe2000_pips",
      ]) {
        const cells = grid.querySelectorAll<HTMLElement>(
          `.ag-cell[col-id="${columnId}"]`,
        );
        expect(cells.length).toBeGreaterThan(0);
        for (const cell of cells) {
          expect(cell.querySelector(".snapshot-elliott-wave-value")).toBeNull();
        }
      }
    });
  });

  it("colors only directional signed values in the timeframe comparison grid", async () => {
    provideGridLayoutSize();
    const payload = detailPayload();
    const h1TimeFrame = payload.time_frames.find(
      (item) => item.time_frame_text === "H1",
    );
    if (!h1TimeFrame) throw new Error("H1 test fixture not found");
    Object.assign(h1TimeFrame, {
      oscillator_count: -2,
      stochastic_short_count: -3,
      stochastic_middle_count: 0,
      stochastic_long_count: 1,
      gmma_trend_count: -4,
      gmma_cross_count: 0,
      ema30_ema60_diff_pips: -10,
      ema200_slope_pips: -2.5,
      ema200_close_diff_pips: 0,
      ema200_close_position: 2,
      ema200_slope_direction: -1,
      ema200_up_count: 5,
      ema200_down_count: 7,
      ema200_trend_count: -2,
    });
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(payload)));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    fireEvent.click(screen.getByRole("button", { name: "列プリセット: すべて展開" }));
    await expectColumnLayout(grid, [
      "wave",
      "price",
      "fibo_expansion",
      "oscillator_stochastic",
      "trend_ema",
    ]);

    const cellWithText = (columnId: string, expected: string): HTMLElement => {
      const cell = Array.from(
        grid.querySelectorAll<HTMLElement>(`.ag-cell[col-id="${columnId}"]`),
      ).find((item) => item.textContent === expected);
      if (!cell) throw new Error(`cell not found: ${columnId}=${expected}`);
      return cell;
    };
    const signedTokens = (cell: HTMLElement): HTMLElement[] => Array.from(
      cell.querySelectorAll<HTMLElement>(".snapshot-signed-value"),
    );

    await waitFor(() => {
      const oscillator = cellWithText("oscillator", "BUY / count -2");
      expect(signedTokens(oscillator)).toHaveLength(1);
      expect(signedTokens(oscillator)[0]).toHaveClass("negative");

      const stochasticShort = cellWithText(
        "stochastic_short",
        "count -3 / Main 75.12 / Signal 70.34",
      );
      expect(signedTokens(stochasticShort)).toHaveLength(1);
      expect(signedTokens(stochasticShort)[0]).toHaveTextContent("-3");
      expect(signedTokens(stochasticShort)[0]).toHaveClass("negative");

      const stochasticMiddle = cellWithText(
        "stochastic_middle",
        "count 0 / Main 65.12 / Signal 60.34",
      );
      expect(signedTokens(stochasticMiddle)).toHaveLength(1);
      expect(signedTokens(stochasticMiddle)[0]).toHaveClass("neutral");

      const stochasticLong = cellWithText(
        "stochastic_long",
        "count +1 / Main 55.12 / Signal 50.34",
      );
      expect(signedTokens(stochasticLong)).toHaveLength(1);
      expect(signedTokens(stochasticLong)[0]).toHaveClass("positive");

      const gmma = cellWithText("gmma_trend_cross", "-4 / 0");
      expect(signedTokens(gmma).map((token) => token.classList.item(1)))
        .toEqual(["negative", "neutral"]);

      const emaDiff = cellWithText("ema30_ema60_diff_pips", "-10.0 pips");
      expect(signedTokens(emaDiff)).toHaveLength(1);
      expect(signedTokens(emaDiff)[0]).toHaveClass("negative");

      const emaSlopeDistance = cellWithText(
        "ema200_slope_distance",
        "-2.5 / 0.0 pips",
      );
      expect(signedTokens(emaSlopeDistance).map((token) => token.classList.item(1)))
        .toEqual(["negative", "neutral"]);

      const emaCodes = cellWithText("ema200_position_slope_code", "+2 / -1");
      expect(signedTokens(emaCodes).map((token) => token.classList.item(1)))
        .toEqual(["neutral", "negative"]);

      const emaCounts = cellWithText("ema200_counts", "5 / 7 / -2");
      expect(signedTokens(emaCounts)).toHaveLength(1);
      expect(signedTokens(emaCounts)[0]).toHaveTextContent("-2");
      expect(signedTokens(emaCounts)[0]).toHaveClass("negative");

      for (const columnId of [
        "stochastic",
        "ema30_ema60",
        "atr14_pips",
        "ema200_close1_shift1",
        "ema200_compare",
        "latest_point_rate",
        "fe618_fe1000",
        "distance_to_fe2000_pips",
      ]) {
        const cells = grid.querySelectorAll<HTMLElement>(`.ag-cell[col-id="${columnId}"]`);
        expect(cells.length).toBeGreaterThan(0);
        for (const cell of cells) {
          expect(signedTokens(cell)).toHaveLength(0);
        }
      }
    });
  });

  it("disables navigation when an older runtime omits navigation metadata", async () => {
    provideGridLayoutSize();
    const payload = detailPayload();
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse({
      available: payload.available,
      observation: payload.observation,
      time_frames: payload.time_frames,
    })));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const navigation = await screen.findByRole("navigation", { name: "CADJPYの観測時刻を移動" });
    const olderButton = within(navigation).getByRole("button", { name: "前の観測の情報はありません" });
    const newerButton = within(navigation).getByRole("button", { name: "次の観測の情報はありません" });
    expect(olderButton).toBeDisabled();
    expect(olderButton).toHaveTextContent("情報なし");
    expect(newerButton).toBeDisabled();
    expect(newerButton).toHaveTextContent("情報なし");
  });

  it("moves between timestamped observations while preserving the comparison grid", async () => {
    provideGridLayoutSize();
    let resolveOlder!: (response: Response) => void;
    const olderRequest = new Promise<Response>((resolve) => {
      resolveOlder = resolve;
    });
    const olderPayload = detailPayloadAt(
      40,
      "2026.08.10 10:00:00",
      "2026.08.10 04:00:00",
      {
        older: null,
        newer: navigationItem(41, "2026.08.10 11:00:00", "2026.08.10 05:00:00"),
      },
    );
    olderPayload.time_frames = olderPayload.time_frames.map((item) => ({
      ...item,
      observation_id: 40,
      is_buy: item.time_frame_text === "H1" ? false : item.is_buy,
      buy_sell_label: item.time_frame_text === "H1" ? "SELL" : item.buy_sell_label,
    }));
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      if (String(input) === "/api/observations/41") {
        return Promise.resolve(jsonResponse(detailPayload()));
      }
      if (String(input) === "/api/observations/40") return olderRequest;
      return Promise.reject(new Error(`unexpected path: ${String(input)}`));
    });
    vi.stubGlobal("fetch", fetchMock);
    const onNavigate = vi.fn();

    render(<NavigationHarness onNavigate={onNavigate} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    const navigation = screen.getByRole("navigation", { name: "CADJPYの観測時刻を移動" });
    const olderButton = within(navigation).getByRole("button", {
      name: "前の観測。JST 2026.08.10 10:00:00、Server 2026.08.10 04:00:00、Run 6",
    });
    const newerButton = within(navigation).getByRole("button", {
      name: "次の観測。JST 2026.08.10 12:00:00、Server 2026.08.10 06:00:00、Run 8",
    });
    expect(olderButton).toHaveTextContent("JST 2026.08.10 10:00:00");
    expect(newerButton).toHaveTextContent("JST 2026.08.10 12:00:00");
    expect(olderButton).toBeEnabled();
    expect(newerButton).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "列プリセット: EMA200検証" }));
    await expectColumnLayout(grid, ["trend_ema"]);
    fireEvent.click(olderButton);

    expect(onNavigate).toHaveBeenCalledWith(40);
    expect(await screen.findByText("観測を読み込んでいます…")).toHaveAttribute("aria-hidden", "true");
    expect(screen.getByText("JST 2026.08.10 10:00:00の観測を読み込んでいます"))
      .toHaveAttribute("role", "status");
    expect(olderButton).toBeDisabled();
    expect(newerButton).toBeDisabled();
    expect(screen.getByRole("button", { name: "H1観測詳細を閉じる" })).toBeEnabled();
    expect(screen.getByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" })).toBe(grid);
    expect(screen.getByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();

    resolveOlder(jsonResponse(olderPayload));

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 10:00:00" })).toBeInTheDocument();
    const updatedGrid = screen.getByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    expect(updatedGrid).toBe(grid);
    await expectColumnLayout(updatedGrid, ["trend_ema"]);
    await waitFor(() => {
      const directionCells = Array.from(
        updatedGrid.querySelectorAll<HTMLElement>('.ag-cell[col-id="buy_sell_label"]'),
      );
      expect(directionCells.some((cell) => cell.textContent?.includes("SELL"))).toBe(true);
    });
    const oldestButton = screen.getByRole("button", { name: "前の観測はありません" });
    expect(oldestButton).toBeDisabled();
    expect(oldestButton).toHaveTextContent("最古");
    expect(screen.getByRole("button", {
      name: "次の観測。JST 2026.08.10 11:00:00、Server 2026.08.10 05:00:00、Run 7",
    })).toBeEnabled();
    expect(screen.getByText("CADJPY JST 2026.08.10 10:00:00を表示しました")).toHaveClass("visually-hidden");
    expect(screen.getByRole("dialog")).toHaveClass("observation-grid-mode");
  });

  it("keeps the current comparison visible when observation navigation fails", async () => {
    provideGridLayoutSize();
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/observations/41") {
        return jsonResponse(detailPayload());
      }
      if (String(input) === "/api/observations/40") {
        return errorResponse("navigation failed", 500);
      }
      throw new Error(`unexpected path: ${String(input)}`);
    });
    vi.stubGlobal("fetch", fetchMock);
    const onNavigate = vi.fn();

    render(<NavigationHarness onNavigate={onNavigate} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    fireEvent.click(screen.getByRole("button", {
      name: "前の観測。JST 2026.08.10 10:00:00、Server 2026.08.10 04:00:00、Run 6",
    }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "navigation failed。現在の観測を表示しています",
    );
    expect(screen.getByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    expect(screen.getByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" })).toBe(grid);
    expect(screen.getByRole("button", {
      name: "前の観測。JST 2026.08.10 10:00:00、Server 2026.08.10 04:00:00、Run 6",
    })).toBeEnabled();
    await waitFor(() => expect(onNavigate.mock.calls.map(([id]) => id)).toEqual([40, 41]));
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("switches every desktop column preset while keeping four comparison columns pinned", async () => {
    provideGridLayoutSize();
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayload())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });

    const presetCases: Array<{ label: string; openGroups: ColumnGroupId[] }> = [
      { label: "要点のみ", openGroups: [] },
      { label: "波動", openGroups: ["wave"] },
      { label: "価格・Fibo", openGroups: ["price", "fibo_expansion"] },
      { label: "オシレーター", openGroups: ["oscillator_stochastic"] },
      { label: "EMA200検証", openGroups: ["trend_ema"] },
      {
        label: "すべて展開",
        openGroups: [
          "wave",
          "price",
          "fibo_expansion",
          "oscillator_stochastic",
          "trend_ema",
        ],
      },
    ];

    for (const presetCase of presetCases) {
      const button = screen.getByRole("button", {
        name: `列プリセット: ${presetCase.label}`,
      });
      fireEvent.click(button);
      await expectColumnLayout(grid, presetCase.openGroups);
      expect(button).toHaveAttribute("aria-pressed", "true");
    }

    const pinnedHeaderIds = Array.from(
      grid.querySelectorAll<HTMLElement>(
        ".ag-header .ag-grid-pinned-left-cells .ag-header-cell[col-id]",
      ),
    ).flatMap((header) => {
      const columnId = header.getAttribute("col-id");
      return columnId ? [columnId] : [];
    });
    expect(pinnedHeaderIds).toEqual(COMPARISON_KEY_COLUMN_IDS);
  });

  it("opens and closes a column group manually and persists the state", async () => {
    provideGridLayoutSize();
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayload())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    await expectColumnLayout(grid, []);

    const closedIcon = columnGroupHeader(grid, "wave")
      .querySelector<HTMLElement>(".ag-header-expand-icon-collapsed");
    expect(closedIcon).not.toBeNull();
    fireEvent.click(closedIcon as HTMLElement);

    await expectColumnLayout(grid, ["wave"]);
    await waitFor(() => {
      const stored = JSON.parse(
        localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY) ?? "",
      );
      expect(stored.groups).toEqual({
        wave: true,
        price: false,
        fibo_expansion: false,
        oscillator_stochastic: false,
        trend_ema: false,
      });
    });

    const openHeader = columnGroupHeader(grid, "wave");
    openHeader.focus();
    fireEvent.keyDown(openHeader, { code: "Enter", key: "Enter" });

    await expectColumnLayout(grid, []);
    await waitFor(() => {
      expect(screen.getByRole("button", { name: "列プリセット: 要点のみ" }))
        .toHaveAttribute("aria-pressed", "true");
    });
  });

  it("restores allowed group state and clears it when column display is reset", async () => {
    provideGridLayoutSize();
    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, JSON.stringify({
      version: 1,
      groups: {
        wave: false,
        price: true,
        fibo_expansion: false,
        oscillator_stochastic: false,
        trend_ema: true,
        removed_group: true,
      },
    }));
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayload())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    await expectColumnLayout(grid, ["price", "trend_ema"]);
    for (const button of screen.getAllByRole("button", { name: /列プリセット:/ })) {
      expect(button).toHaveAttribute("aria-pressed", "false");
    }

    fireEvent.click(screen.getByRole("button", { name: "列表示をリセット" }));

    await expectColumnLayout(grid, []);
    await waitFor(() => {
      expect(localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY)).toBeNull();
    });
    expect(screen.getByRole("button", { name: "列プリセット: 要点のみ" }))
      .toHaveAttribute("aria-pressed", "true");
  });

  it("renders future timeframe rows dynamically in stored order", async () => {
    provideGridLayoutSize();
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse(detailPayloadWithM5())));

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

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
    fireEvent.click(screen.getByRole("button", { name: "列プリセット: すべて展開" }));
    await expectColumnLayout(grid, [
      "wave",
      "price",
      "fibo_expansion",
      "oscillator_stochastic",
      "trend_ema",
    ]);
    expect((await within(grid).findAllByRole("rowheader")).map((cell) => cell.textContent)).toContain("M5");
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

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "CADJPY / 2026.08.10 11:00:00" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));

    const grid = await screen.findByRole("grid", { name: "時間足別 H1新規足スナップショットグリッド" });
    const region = screen.getByRole("region", { name: "時間足別 H1新規足スナップショットグリッド" });
    const presetSelect = screen.getByRole("combobox", { name: "列プリセット" });
    expect(presetSelect).toHaveValue("essentials");
    expect(screen.queryByRole("button", { name: "列プリセット: 要点のみ" })).not.toBeInTheDocument();
    fireEvent.change(presetSelect, { target: { value: "ema200" } });
    await expectColumnLayout(grid, ["trend_ema"]);
    expect(presetSelect).toHaveValue("ema200");
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

    render(<ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />);

    expect(await screen.findByText("H1観測DBはまだ利用されていません")).toHaveAttribute("role", "status");
    expect(screen.queryByRole("article")).not.toBeInTheDocument();
  });

  it("shows a 404 detail error without disabling close", async () => {
    const onClose = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async () => errorResponse("observation was not found", 404)));

    render(<ObservationDetailDrawer observationId={404} onClose={onClose} onNavigate={vi.fn()} />);

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

    const view = render(
      <ObservationDetailDrawer observationId={41} onClose={vi.fn()} onNavigate={vi.fn()} />,
    );
    view.rerender(
      <ObservationDetailDrawer observationId={42} onClose={vi.fn()} onNavigate={vi.fn()} />,
    );

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
    render(<ObservationDetailDrawer observationId={41} onClose={onClose} onNavigate={vi.fn()} />);
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
