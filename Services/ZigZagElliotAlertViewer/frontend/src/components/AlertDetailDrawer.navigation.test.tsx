import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { getGridApi } from "ag-grid-community";
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SearchState } from "../api/types";
import { DEFAULT_SEARCH_STATE } from "../lib/searchState";
import { AlertDetailDrawer } from "./AlertDetailDrawer";

const previousLabel = "前のアラート（検索結果順）";
const nextLabel = "次のアラート（検索結果順）";
const gridLabel = "アラート時間足比較スナップショットグリッド";
const search: SearchState = {
  ...DEFAULT_SEARCH_STATE,
  sourceMode: "TESTER",
  runId: 3,
  timeFrames: ["H1", "M5"],
  pageSize: 25,
  page: 2,
  sort: "symbol_name",
  order: "asc",
};

function jsonResponse(payload: unknown, status = 200): Response {
  return { ok: status === 200, status, json: async () => payload } as Response;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolver) => { resolve = resolver; });
  return { promise, resolve };
}

function detailPayload(alertId: number, timeFrame = "H1") {
  return {
    alert: {
      id: alertId, run_id: 3, symbol_name: `SYMBOL${alertId}`, side: "BUY",
      time_frame: timeFrame === "M5" ? 5 : 16385, time_frame_text: timeFrame,
      current_bar_time_text: "2026.07.30 19:00:00", alert_title: `Alert ${alertId}`,
      jst_time_text: "2026.07.31 01:00:00", server_time_text: "2026.07.30 19:00:00",
      reference_price: 1.2, is_stop_loss_available: true, stop_loss: 1.1, risk_pips: 50,
      h1_structure_rank: "S", is_h1_structure_late: false, strategy: "MTF_3in3",
      signal_count: 1, entry_count: 1, is_judge: true, is_entry_count_match: true,
      is_entry_evaluated: true, is_entry_wave: true, is_ema200_distance_within: true,
      is_alert: true, is_entry: true, entry_result: "ENTRY", current_elliot_label: "3-3-1",
      close_ema200_diff_pips: 10, max_close_ema200_diff_pips: 25, spread_pips: 1.2,
      currency_strength_status: 0, is_currency_strength_available: false,
      long_medium_rank_difference: 0, medium_short_rank_difference: 0,
      market_signal_key: `market-${alertId}`, alert_text: "", is_w1_aligned: true,
      w1_confirmation_mode: "DIRECTION_OR_EMA200", w1_confirmation_state: "STRONG",
      is_w1_confirmation_available: true, is_w1_confirmation_valid: true,
      is_w1_direction_matched: true, w1_ema200_direction: "BUY", is_w1_ema200_matched: true,
      is_w1_confirmation_passed: true, is_w1_confirmation_legacy: false,
    },
    run: { id: 3, source_mode: "TESTER", program_version: "1.21", tester_model: "" },
    w1: null,
  };
}

function timeFramesPayload(alertId: number) {
  return {
    items: [{
      id: alertId * 10, alert_id: alertId, time_frame: 16385,
      time_frame_text: "H1", time_frame_order: 4, is_current_time_frame: true,
      is_buy: true, buy_sell_label: "BUY", wave_count: alertId,
      latest_wave_index: 2, latest_elliot_label: "3", latest_sub_elliot_label: "i",
      is_wave_confirmed: true, is_wave_motive: true, is_wave_uptrend: true,
      current_close: alertId, is_ema200_available: false,
    }],
    count: 1,
  };
}

function neighbor(alertId: number) {
  return {
    id: alertId, run_id: 3, symbol_name: `SYMBOL${alertId}`, side: "BUY",
    jst_time_text: "2026.07.31 01:00:00", server_time_text: "2026.07.30 19:00:00",
    time_frame_text: "H1",
  };
}

function navigationPayload(alertId: number) {
  return {
    alert_id: alertId,
    matched: true,
    previous: alertId > 74 ? neighbor(alertId - 1) : null,
    next: alertId < 76 ? neighbor(alertId + 1) : null,
  };
}

function responseFor(path: string) {
  const match = /^\/api\/alerts\/(\d+)(\/[^?]+)?/.exec(path);
  if (!match) {
    throw new Error(`Unexpected request: ${path}`);
  }
  const alertId = Number(match[1]);
  if (match[2] === "/navigation") {
    return jsonResponse(navigationPayload(alertId));
  }
  if (match[2] === "/timeframes") {
    return jsonResponse(timeFramesPayload(alertId));
  }
  if (match[2] === "/points") {
    return jsonResponse({ items: [], count: 0 });
  }
  return jsonResponse(detailPayload(alertId));
}

function DrawerHarness({ onNavigate = vi.fn() }: { onNavigate?: (alertId: number) => void }) {
  const [alertId, setAlertId] = useState<number | null>(74);
  return <AlertDetailDrawer
    alertId={alertId}
    initialView="comparison"
    navigationSearch={search}
    onClose={() => setAlertId(null)}
    onNavigate={(nextId) => {
      onNavigate(nextId);
      setAlertId(nextId);
    }}
  />;
}

beforeEach(() => {
  window.localStorage.clear();
  // JSDOM does not resolve viewport geometry used to clamp restored grid scroll.
  const getComputedStyle = window.getComputedStyle.bind(window);
  vi.spyOn(window, "getComputedStyle").mockImplementation((element, pseudo) => {
    const style = getComputedStyle(element, pseudo);
    if (element.classList.contains("ag-grid-viewport")) {
      style.width = "1440px";
      style.height = "800px";
      style.padding = "0px";
      style.border = "0px solid";
    }
    return style;
  });
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(1_440);
  vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockReturnValue(800);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(1_440);
  vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(800);
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue({
    bottom: 800, height: 800, left: 0, right: 1_440, top: 0, width: 1_440,
    x: 0, y: 0, toJSON: () => ({}),
  });
  vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => responseFor(String(input))));
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("AlertDetailDrawer search navigation", () => {
  it("keeps the comparison grid, column state, widths and scroll while changing snapshots", async () => {
    const pending = deferred<Response>();
    vi.mocked(fetch).mockImplementation(async (input) => {
      if (String(input) === "/api/alerts/75") {
        return pending.promise;
      }
      return responseFor(String(input));
    });
    render(<DrawerHarness />);
    const grid = await screen.findByRole("grid", { name: gridLabel });
    const gridApi = getGridApi(grid)!;
    const body = document.querySelector<HTMLElement>(".drawer-body")!;
    const viewport = document.querySelector<HTMLElement>(".ag-grid-viewport")!;
    fireEvent.click(screen.getByRole("button", { name: "列プリセット: 波動" }));
    await act(async () => {
      gridApi.setColumnWidths([{ key: "wave_direction", newWidth: 287 }]);
      gridApi.setColumnsVisible(["ema200_direction"], false);
    });
    const columnState = gridApi.getColumnState();
    const groupState = gridApi.getColumnGroupState();
    fireEvent.scroll(viewport, { target: { scrollLeft: 320 } });
    fireEvent.scroll(body, { target: { scrollTop: 180 } });
    await waitFor(() => expect(gridApi.getState().scroll?.left).toBe(320));

    expect(screen.getByRole("button", { name: previousLabel })).toBeDisabled();
    const next = screen.getByRole("button", { name: nextLabel });
    expect(next).toHaveTextContent("次 →");
    expect(next).toHaveAttribute("title", expect.stringContaining("SYMBOL75"));
    expect(next).toHaveAttribute("title", expect.stringContaining("BUY"));
    expect(next).toHaveAttribute("title", expect.stringContaining("2026.07.31 01:00:00"));
    fireEvent.click(next);
    expect(screen.getByRole("heading", { name: /SYMBOL74 BUY/ })).toBeInTheDocument();
    expect(screen.getByRole("grid", { name: gridLabel })).toBe(grid);
    expect(screen.getByRole("button", { name: nextLabel })).toBeDisabled();
    expect(screen.getByRole("button", { name: previousLabel })).toBeDisabled();
    expect(body).toHaveAttribute("aria-busy", "true");

    await act(async () => pending.resolve(jsonResponse(detailPayload(75))));
    expect(await screen.findByRole("heading", { name: /SYMBOL75 BUY/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "TF比較" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("grid", { name: gridLabel })).toBe(grid);
    expect(getGridApi(grid)).toBe(gridApi);
    expect(gridApi.getColumnState()).toEqual(columnState);
    expect(gridApi.getColumnGroupState()).toEqual(groupState);
    expect(viewport.scrollLeft).toBe(320);
    expect(body.scrollTop).toBe(180);
    await waitFor(() => expect(grid.querySelector(".ag-row")).toHaveAttribute("row-id", "750"));

    fireEvent.click(screen.getByRole("button", { name: previousLabel }));
    expect(await screen.findByRole("heading", { name: /SYMBOL74 BUY/ })).toBeInTheDocument();
    expect(screen.getByRole("grid", { name: gridLabel })).toBe(grid);
  });

  it("passes the saved search and order to every navigation request and disables the final edge", async () => {
    render(<DrawerHarness />);
    await screen.findByRole("heading", { name: /SYMBOL74 BUY/ });
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    await screen.findByRole("heading", { name: /SYMBOL75 BUY/ });
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    await screen.findByRole("heading", { name: /SYMBOL76 BUY/ });
    expect(screen.getByRole("button", { name: nextLabel })).toBeDisabled();
    expect(screen.getByRole("button", { name: previousLabel })).toBeEnabled();
    const requests = vi.mocked(fetch).mock.calls
      .map(([input]) => new URL(String(input), "http://localhost"))
      .filter((url) => url.pathname.endsWith("/navigation"));
    expect(requests.map((url) => url.pathname)).toEqual([
      "/api/alerts/74/navigation", "/api/alerts/75/navigation", "/api/alerts/76/navigation",
    ]);
    for (const request of requests) {
      expect(request.searchParams.get("sourceMode")).toBe("TESTER");
      expect(request.searchParams.get("runId")).toBe("3");
      expect(request.searchParams.getAll("timeFrame")).toEqual(["H1", "M5"]);
      expect(request.searchParams.get("sort")).toBe("symbol_name");
      expect(request.searchParams.get("order")).toBe("asc");
    }
  });

  it("keeps the previous snapshot after failure, restores selection and permits retry", async () => {
    let failNext = true;
    vi.mocked(fetch).mockImplementation(async (input) => {
      if (String(input) === "/api/alerts/75" && failNext) {
        return jsonResponse({ error: "移動先の読み込みに失敗" }, 500);
      }
      return responseFor(String(input));
    });
    const onNavigate = vi.fn();
    render(<DrawerHarness onNavigate={onNavigate} />);
    const grid = await screen.findByRole("grid", { name: gridLabel });
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    expect(await screen.findByRole("alert")).toHaveTextContent("移動先の読み込みに失敗");
    expect(screen.getByRole("heading", { name: /SYMBOL74 BUY/ })).toBeInTheDocument();
    expect(screen.getByRole("grid", { name: gridLabel })).toBe(grid);
    expect(onNavigate.mock.calls.map(([alertId]) => alertId)).toEqual([75, 74]);
    await waitFor(() => expect(screen.getByRole("button", { name: nextLabel })).toBeEnabled());
    failNext = false;
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    expect(await screen.findByRole("heading", { name: /SYMBOL75 BUY/ })).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByRole("grid", { name: gridLabel })).toBe(grid);
  });

  it("aborts all stale requests and ignores their late results after selection changes and closing", async () => {
    const stale = deferred<Response>();
    const oldSignals: AbortSignal[] = [];
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).startsWith("/api/alerts/74")) {
        oldSignals.push(init!.signal!);
        return stale.promise;
      }
      return responseFor(String(input));
    });
    const props = { initialView: "comparison" as const, navigationSearch: search, onClose: vi.fn(), onNavigate: vi.fn() };
    const view = render(<AlertDetailDrawer {...props} alertId={74} />);
    expect(oldSignals).toHaveLength(4);
    view.rerender(<AlertDetailDrawer {...props} alertId={75} />);
    await screen.findByRole("heading", { name: /SYMBOL75 BUY/ });
    expect(oldSignals.every((signal) => signal.aborted)).toBe(true);
    await act(async () => stale.resolve(jsonResponse(detailPayload(74))));
    expect(screen.queryByRole("heading", { name: /SYMBOL74 BUY/ })).not.toBeInTheDocument();
    const activeSignals = vi.mocked(fetch).mock.calls
      .filter(([input]) => String(input).startsWith("/api/alerts/75"))
      .map(([, init]) => init!.signal!);
    view.rerender(<AlertDetailDrawer {...props} alertId={null} />);
    expect(activeSignals).toHaveLength(4);
    expect(activeSignals.every((signal) => signal.aborted)).toBe(true);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("restores comparison columns and scroll after navigating through an M5 snapshot", async () => {
    vi.mocked(fetch).mockImplementation(async (input) => {
      if (String(input) === "/api/alerts/75") {
        return jsonResponse(detailPayload(75, "M5"));
      }
      return responseFor(String(input));
    });
    render(<DrawerHarness />);
    const originalGrid = await screen.findByRole("grid", { name: gridLabel });
    const originalGridApi = getGridApi(originalGrid)!;
    fireEvent.click(screen.getByRole("button", { name: "列プリセット: 波動" }));
    await act(async () => {
      originalGridApi.setColumnWidths([{ key: "wave_direction", newWidth: 287 }]);
      originalGridApi.setColumnsVisible(["ema200_direction"], false);
    });
    const columnState = originalGridApi.getColumnState();
    const groupState = originalGridApi.getColumnGroupState();
    fireEvent.scroll(document.querySelector(".ag-grid-viewport")!, {
      target: { scrollLeft: 320 },
    });
    await waitFor(() => expect(originalGridApi.getState().scroll?.left).toBe(320));
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    await screen.findByRole("heading", { name: /SYMBOL75 BUY/ });
    expect(screen.getByRole("dialog")).toHaveClass("m5-alert-dialog");
    expect(screen.getByRole("button", { name: nextLabel })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: nextLabel }));
    await screen.findByRole("heading", { name: /SYMBOL76 BUY/ });
    expect(screen.getByRole("button", { name: "TF比較" })).toHaveAttribute("aria-pressed", "true");
    const restoredGrid = await screen.findByRole("grid", { name: gridLabel });
    const restoredGridApi = getGridApi(restoredGrid)!;
    await waitFor(() => {
      expect(restoredGridApi.getColumnState()).toEqual(columnState);
      expect(restoredGridApi.getColumnGroupState()).toEqual(groupState);
      expect(document.querySelector(".ag-grid-viewport")!.scrollLeft).toBe(320);
    });
  });

  it("still displays a successful detail when its navigation request fails", async () => {
    vi.mocked(fetch).mockImplementation(async (input) => {
      if (String(input).includes("/navigation?")) {
        return jsonResponse({ error: "前後のアラートを取得できません" }, 500);
      }
      return responseFor(String(input));
    });
    render(<DrawerHarness />);
    expect(await screen.findByRole("grid", { name: gridLabel })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: /SYMBOL74 BUY/ })).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("前後のアラートを取得できません");
    expect(screen.getByRole("button", { name: previousLabel })).toBeDisabled();
    expect(screen.getByRole("button", { name: nextLabel })).toBeDisabled();
  });

  it("disables both directions if the current alert no longer matches the search", async () => {
    vi.mocked(fetch).mockImplementation(async (input) => {
      if (String(input).includes("/navigation?")) {
        return jsonResponse({ alert_id: 74, matched: false, previous: null, next: null });
      }
      return responseFor(String(input));
    });
    render(<DrawerHarness />);
    await screen.findByRole("heading", { name: /SYMBOL74 BUY/ });
    expect(screen.getByRole("button", { name: previousLabel })).toBeDisabled();
    expect(screen.getByRole("button", { name: nextLabel })).toBeDisabled();
  });
});
