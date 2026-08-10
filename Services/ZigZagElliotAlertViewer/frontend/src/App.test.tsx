import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import { REFRESH_INTERVAL_STORAGE_KEY } from "./lib/refreshSettings";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

let observationAvailable = true;

function observationTimeFrame(timeFrame: string, index: number) {
  return {
    id: 100 + index,
    observation_id: 9,
    time_frame: index + 1,
    time_frame_text: timeFrame,
    time_frame_order: index,
    is_anchor_time_frame: timeFrame === "H1",
    is_buy: index % 2 === 0,
    buy_sell_label: index % 2 === 0 ? "BUY" : "SELL",
    wave_count: 2,
    latest_wave_index: 1,
    is_wave_confirmed: true,
    is_wave_motive: true,
    is_wave_uptrend: index % 2 === 0,
    wave_trend_label: "Бе",
    previous_last_elliot_label: "2",
    point_count: 4,
    latest_elliot_index: 3,
    latest_elliot_label: "3",
    latest_sub_elliot_index: 1,
    latest_sub_elliot_label: "3-1",
    latest_point_time: 1786309200,
    latest_point_time_text: "2026.08.10 01:00:00",
    latest_point_rate: 1.23456,
    current_close: 1.235,
    stochastic_main_order_text: "SHORT>MIDDLE>LONG",
    stochastic_main_direction_text: "BUY",
    gmma_trend_count: 3,
    gmma_cross_count: 0,
    atr14_pips: 12.3,
    is_ema200_buy: true,
    is_ema200_sell: false,
  };
}

function observationsResponse() {
  return {
    available: observationAvailable,
    total: observationAvailable ? 1 : 0,
    page: 1,
    page_size: 50,
    page_count: observationAvailable ? 1 : 0,
    items: observationAvailable ? [{
      id: 9,
      run_id: 3,
      run_uid: "run-3",
      source_mode: "TESTER",
      source_server: "Test-Server",
      symbol_name: "AUDUSD",
      anchor_bar_time: 1786309200,
      anchor_bar_time_text: "2026.08.10 01:00:00",
      anchor_time_frame: 16385,
      anchor_time_frame_text: "H1",
      capture_phase: "BAR_OPEN_FIRST_SUCCESS",
      analysis_version: "1",
      analysis_input_hash: "input-hash",
      snapshot_hash: "snapshot-hash",
      time_frame_count: 5,
      created_at: 1786309201,
      created_at_text: "2026.08.10 01:00:01",
      time_frames: ["MN1", "W1", "D1", "H4", "H1"].map(observationTimeFrame),
    }] : [],
  };
}

describe("App", () => {
  beforeEach(() => {
    observationAvailable = true;
    window.history.replaceState(null, "", "/");
    window.localStorage.clear();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/health") {
        return jsonResponse({ status: "ok", database: "test.sqlite", journal_mode: "wal", alert_count: 1 });
      }
      if (path === "/api/runs") {
        return jsonResponse({
          count: 3,
          items: [
            {
              id: 4,
              run_uid: "run-4",
              source_mode: "LIVE",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: "1",
              started_at_text: "2026.08.01 00:00:00",
              alert_count: 0,
              first_alert_time_text: null,
              last_alert_time_text: null,
              symbols: null,
            },
            {
              id: 3,
              run_uid: "run-3",
              source_mode: "TESTER",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: "1",
              started_at_text: "2022.01.01 00:00:00",
              alert_count: 1,
              first_alert_time_text: "2026.07.30 19:00:00",
              last_alert_time_text: "2026.07.30 19:00:00",
              symbols: "AUDUSD",
            },
            {
              id: 2,
              run_uid: "run-2",
              source_mode: "TESTER",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: "1",
              started_at_text: "2022.01.01 00:00:00",
              alert_count: 0,
              first_alert_time_text: null,
              last_alert_time_text: null,
              symbols: null,
            },
          ],
        });
      }
      if (path === "/api/options") {
        return jsonResponse({ symbols: ["AUDUSD"], time_frames: ["H1", "M5", "D1"], strategies: ["MTF_3in3"], ranks: ["S"], entry_results: ["ENTRY"] });
      }
      if (path === "/api/observation-options") {
        return jsonResponse({
          available: observationAvailable,
          symbols: observationAvailable ? ["AUDUSD"] : [],
          source_modes: observationAvailable ? ["TESTER"] : [],
          analysis_versions: observationAvailable ? ["1"] : [],
        });
      }
      if (path.startsWith("/api/observations?")) {
        return jsonResponse(observationsResponse());
      }
      if (path.startsWith("/api/observation-summary?")) {
        return jsonResponse({
          available: observationAvailable,
          total_count: observationAvailable ? 1 : 0,
          live_count: 0,
          tester_count: observationAvailable ? 1 : 0,
          run_count: observationAvailable ? 1 : 0,
          symbol_count: observationAvailable ? 1 : 0,
          first_anchor_bar_time: observationAvailable ? 1786309200 : null,
          first_anchor_bar_time_text: observationAvailable ? "2026.08.10 01:00:00" : null,
          last_anchor_bar_time: observationAvailable ? 1786309200 : null,
          last_anchor_bar_time_text: observationAvailable ? "2026.08.10 01:00:00" : null,
        });
      }
      if (path === "/api/alerts/74") {
        return jsonResponse({
          alert: {
            id: 74, run_id: 4, symbol_name: "AUDUSD", side: "BUY",
            current_bar_time_text: "2026.07.30 19:00:00", alert_title: "AUDUSD alert",
            jst_time_text: "2026.07.31 01:00:00", server_time_text: "2026.07.30 19:00:00",
            reference_price: 1.2, is_stop_loss_available: true, stop_loss: 1.1, risk_pips: 50,
            h1_structure_rank: "S", is_h1_structure_late: false, strategy: "MTF_3in3",
            signal_count: 1, entry_count: 1, is_judge: true, is_entry_count_match: true,
            is_entry_evaluated: true, is_entry_wave: true, is_ema200_distance_within: true,
            is_alert: true, is_entry: true, entry_result: "ENTRY", current_elliot_label: "3-3-1",
            close_ema200_diff_pips: 10, max_close_ema200_diff_pips: 25, spread_pips: 1.2,
            currency_strength_status: 0, is_currency_strength_available: false,
            long_medium_rank_difference: 0, medium_short_rank_difference: 0,
            market_signal_key: "market-74", alert_text: "", is_w1_aligned: true,
          },
          run: { id: 4, source_mode: "LIVE", program_version: "1.21", tester_model: "" },
          w1: null,
        });
      }
      if (path === "/api/alerts/74/timeframes" || path === "/api/alerts/74/points") {
        return jsonResponse({ items: [], count: 0 });
      }
      if (path.startsWith("/api/alerts?")) {
        return jsonResponse({
          total: 1,
          page: 1,
          page_size: 50,
          page_count: 1,
          items: [{
            id: 74,
            run_id: 4,
            source_mode: "LIVE",
            jst_time_text: "2026.07.31 01:00:00",
            server_time_text: "2026.07.30 19:00:00",
            symbol_name: "AUDUSD",
            time_frame_text: "H1",
            strategy: "MTF_3in3",
            side: "BUY",
            signal_count: 1,
            entry_count: 1,
            is_entry: true,
            entry_result: "ENTRY",
            current_elliot_label: "3-3-1",
            risk_pips: 50,
            spread_pips: 1.2,
            h1_structure_rank: "S",
            is_h1_structure_late: false,
            alert_title: "AUDUSD alert",
            mn1_side: "BUY",
            w1_side: "BUY",
            d1_side: "BUY",
            h4_side: "BUY",
            h1_side: "BUY",
            is_w1_aligned: true,
          }],
        });
      }
      if (path.startsWith("/api/summary?")) {
        return jsonResponse({ total_count: 1, database_total_count: 451, buy_count: 1, sell_count: 0, w1_aligned_count: 1, w1_mismatched_count: 0, w1_unknown_count: 0, run_count: 1, symbol_count: 1 });
      }
      return jsonResponse({ error: `unexpected path: ${path}` });
    }));
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("defaults to all LIVE runs without falling back to a TESTER run", async () => {
    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    expect(screen.getByRole("tabpanel")).toHaveClass("viewer-tab-panel");
    expect(screen.getByRole("link", { name: "従来画面" })).toHaveAttribute("href", "/legacy/");
    expect((await screen.findAllByText("AUDUSD")).length).toBeGreaterThan(0);
    expect(await screen.findByText("一致")).toBeInTheDocument();
    const resultSummary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(resultSummary).getByText("検索該当 / DB全体").nextElementSibling)
      .toHaveTextContent("1/451");
    await waitFor(() => {
      const fetchMock = vi.mocked(fetch);
      expect(fetchMock.mock.calls.some(([path]) => {
        const requestedPath = String(path);
        return requestedPath.startsWith("/api/alerts?sourceMode=LIVE")
          && !requestedPath.includes("runId=");
      })).toBe(true);
    });
    const parameters = new URLSearchParams(window.location.search);
    expect(parameters.get("sourceMode")).toBe("LIVE");
    expect(parameters.has("runId")).toBe(false);
  });

  it("opens the H1 view directly with Server time and five timeframe comparisons", async () => {
    window.history.replaceState(
      null,
      "",
      "/?tab=h1&sourceMode=TESTER&runId=3&symbol=AUDUSD&from=2026-08-01&to=2026-08-10",
    );
    render(<App />);

    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    expect(screen.getByRole("tabpanel")).toHaveClass("viewer-tab-panel");
    expect(await screen.findByRole("columnheader", { name: /Server日時/ })).toBeInTheDocument();
    for (const timeFrame of ["MN1", "W1", "D1", "H4", "H1"]) {
      expect(screen.getByRole("columnheader", { name: timeFrame })).toBeInTheDocument();
    }
    expect(screen.getAllByText(/上昇|下降/).length).toBeGreaterThanOrEqual(5);
    expect(screen.queryByText("Бе")).not.toBeInTheDocument();
    expect(screen.getByText(/最新点 2026\.08\.10 01:00:00/)).toBeInTheDocument();
    expect(screen.getByLabelText("開始日（Server）")).toHaveValue("2026-08-01");
    expect(screen.getByLabelText("終了日（Server）")).toHaveValue("2026-08-10");
    expect(new URLSearchParams(window.location.search).get("tab")).toBe("h1");

    const calls = vi.mocked(fetch).mock.calls.map(([path]) => String(path));
    expect(calls.some((path) => path.startsWith("/api/observations?sourceMode=TESTER"))).toBe(true);
    expect(calls.some((path) => path.startsWith("/api/alerts?"))).toBe(false);

    fireEvent.click(within(screen.getByRole("columnheader", { name: /Server日時/ }))
      .getByRole("button", { name: /Server日時/ }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("tab")).toBe("h1");
      expect(parameters.get("sort")).toBe("anchor_bar_time");
      expect(parameters.get("order")).toBe("asc");
    });
  });

  it("keeps each filter panel collapsed independently when switching tabs", async () => {
    render(<App />);

    const alertCloseButton = await screen.findByRole("button", { name: "検索条件を閉じる" });
    fireEvent.click(alertCloseButton);
    expect(screen.getByRole("button", { name: "検索条件を開く" })).toHaveAttribute("aria-expanded", "false");

    fireEvent.click(screen.getByRole("tab", { name: "H1推移" }));
    const observationCloseButton = await screen.findByRole("button", { name: "検索条件を閉じる" });
    expect(observationCloseButton).toHaveAttribute("aria-expanded", "true");
    fireEvent.click(observationCloseButton);
    expect(screen.getByRole("button", { name: "検索条件を開く" })).toHaveAttribute("aria-expanded", "false");

    fireEvent.click(screen.getByRole("tab", { name: "アラート一覧" }));
    expect(await screen.findByRole("button", { name: "検索条件を開く" })).toHaveAttribute("aria-expanded", "false");

    fireEvent.click(screen.getByRole("tab", { name: "H1推移" }));
    expect(await screen.findByRole("button", { name: "検索条件を開く" })).toHaveAttribute("aria-expanded", "false");
  });

  it("shows an unused state when the observation tables do not exist", async () => {
    observationAvailable = false;
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE");
    render(<App />);
    expect(await screen.findByText("H1観測はまだ利用されていません")).toBeInTheDocument();
    expect(screen.getByText("H1観測DB 未利用")).toBeInTheDocument();
  });

  it("drops an observation Run that does not match the explicit source mode", async () => {
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE&runId=3");
    render(<App />);
    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sourceMode")).toBe("LIVE");
      expect(parameters.has("runId")).toBe(false);
    });
    const observationCalls = vi.mocked(fetch).mock.calls
      .map(([path]) => String(path))
      .filter((path) => path.startsWith("/api/observations?"));
    expect(observationCalls.length).toBeGreaterThan(0);
    expect(observationCalls.every((path) => !path.includes("runId="))).toBe(true);
  });

  it("infers TESTER for a legacy URL containing only runId", async () => {
    window.history.replaceState(null, "", "/?runId=3");
    render(<App />);

    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sourceMode")).toBe("TESTER");
      expect(parameters.get("runId")).toBe("3");
    });
    await waitFor(() => {
      const fetchMock = vi.mocked(fetch);
      expect(fetchMock.mock.calls.some(([path]) => {
        const requestedPath = String(path);
        return requestedPath.startsWith("/api/alerts?sourceMode=TESTER&runId=3");
      })).toBe(true);
    });
  });

  it("filters Run choices by mode and clears runId when the mode changes", async () => {
    window.history.replaceState(null, "", "/?sourceMode=TESTER&runId=3");
    render(<App />);

    const modeSelect = await screen.findByLabelText("実行モード");
    const runSelect = screen.getByLabelText("実行Run") as HTMLSelectElement;
    await waitFor(() => expect(runSelect.value).toBe("3"));
    expect(within(runSelect).getByRole("option", { name: /TESTER｜Run 3/ })).toBeInTheDocument();
    expect(within(runSelect).queryByRole("option", { name: /LIVE｜Run 4/ })).not.toBeInTheDocument();

    fireEvent.change(modeSelect, { target: { value: "LIVE" } });
    expect(runSelect.value).toBe("");
    expect(within(runSelect).getByRole("option", { name: /LIVE｜Run 4/ })).toBeInTheDocument();
    expect(within(runSelect).queryByRole("option", { name: /TESTER｜Run 3/ })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    const parameters = new URLSearchParams(window.location.search);
    expect(parameters.get("sourceMode")).toBe("LIVE");
    expect(parameters.has("runId")).toBe(false);
  });

  it("applies and resets multiple alert time frame filters", async () => {
    render(<App />);

    const timeFrameSelect = await screen.findByRole("combobox", { name: "時間足" });
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "H1" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "M5" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(timeFrameSelect).toHaveTextContent("H1・M5");
    expect(new URLSearchParams(window.location.search).has("timeFrame")).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "検索する" }));
    await waitFor(() => {
      expect(new URLSearchParams(window.location.search).getAll("timeFrame")).toEqual(["H1", "M5"]);
      const requestedPaths = vi.mocked(fetch).mock.calls.map(([path]) => String(path));
      for (const prefix of ["/api/alerts?", "/api/summary?"]) {
        expect(requestedPaths.some((path) => (
          path.startsWith(prefix)
          && new URL(path, "http://localhost").searchParams.getAll("timeFrame").join(",") === "H1,M5"
        ))).toBe(true);
      }
    });

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    await waitFor(() => {
      expect(timeFrameSelect).toHaveTextContent("すべて");
      expect(new URLSearchParams(window.location.search).has("timeFrame")).toBe(false);
    });
  });

  it("opens an alert detail and restores focus to its trigger after closing", async () => {
    render(<App />);
    const detailButton = await screen.findByRole("button", { name: "AUDUSD BUY 2026.07.31 01:00:00 の詳細を表示" });
    detailButton.focus();
    fireEvent.click(detailButton);
    expect(await screen.findByRole("heading", { name: "AUDUSD BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    const dialog = screen.getByRole("dialog");
    fireEvent(dialog, new Event("cancel", { bubbles: false, cancelable: true }));
    await waitFor(() => expect(detailButton).toHaveFocus());
  });

  it("uses a grid header to request whole-result server sorting", async () => {
    render(<App />);
    const firstHeader = await screen.findByRole("columnheader", { name: "通貨" });
    fireEvent.click(within(firstHeader).getByRole("button", { name: "通貨" }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sort")).toBe("symbol_name");
      expect(parameters.get("order")).toBe("desc");
      expect(parameters.get("page")).toBe("1");
    });

    const secondHeader = screen.getByRole("columnheader", { name: /通貨/ });
    fireEvent.click(within(secondHeader).getByRole("button", { name: /通貨/ }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sort")).toBe("symbol_name");
      expect(parameters.get("order")).toBe("asc");
    });
  });

  it("persists the selected interval and supports a manual refresh", async () => {
    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();

    const intervalSelect = screen.getByLabelText("自動更新間隔");
    fireEvent.change(intervalSelect, { target: { value: "30" } });
    expect(window.localStorage.getItem(REFRESH_INTERVAL_STORAGE_KEY)).toBe("30");
    expect(screen.getByText("30秒ごとに自動更新")).toBeInTheDocument();

    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;
    const summaryCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/summary?"),
    ).length;
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await waitFor(() => {
      expect(vi.mocked(fetch).mock.calls.filter(
        ([path]) => String(path).startsWith("/api/alerts?"),
      )).toHaveLength(alertCallsBefore + 1);
      expect(vi.mocked(fetch).mock.calls.filter(
        ([path]) => String(path).startsWith("/api/summary?"),
      )).toHaveLength(summaryCallsBefore + 1);
    });
    expect(screen.queryByText("一覧最終確認 —")).not.toBeInTheDocument();
  });

  it("refreshes LIVE results on the stored interval without polling TESTER results", async () => {
    window.localStorage.setItem(REFRESH_INTERVAL_STORAGE_KEY, "5");
    const scheduledRefreshes: Array<() => void> = [];
    const nativeSetTimeout = window.setTimeout.bind(window);
    const timerSpy = vi.spyOn(window, "setTimeout");
    timerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        scheduledRefreshes.push(handler as () => void);
        return 9001;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof timerSpy.mockImplementation>[0]);

    const liveView = render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    await waitFor(() => expect(scheduledRefreshes.length).toBeGreaterThan(0));
    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;
    await act(async () => {
      scheduledRefreshes[0]();
      await Promise.resolve();
    });
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    )).toHaveLength(alertCallsBefore + 1));

    liveView.unmount();
    timerSpy.mockRestore();
    window.history.replaceState(null, "", "/?sourceMode=TESTER&runId=3");
    const testerTimers: Array<() => void> = [];
    const testerTimerSpy = vi.spyOn(window, "setTimeout");
    testerTimerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        testerTimers.push(handler as () => void);
        return 9002;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof testerTimerSpy.mockImplementation>[0]);
    render(<App />);
    expect(await screen.findByText("接続済み・TESTER 1件")).toBeInTheDocument();
    expect(screen.getByText("LIVE表示中のみ自動更新")).toBeInTheDocument();
    expect(testerTimers).toHaveLength(0);
  });

  it("pauses while hidden and refreshes immediately when the tab becomes visible", async () => {
    window.localStorage.setItem(REFRESH_INTERVAL_STORAGE_KEY, "5");
    let visibilityState: DocumentVisibilityState = "hidden";
    vi.spyOn(document, "visibilityState", "get").mockImplementation(() => visibilityState);
    const scheduledRefreshes: Array<() => void> = [];
    const nativeSetTimeout = window.setTimeout.bind(window);
    const timerSpy = vi.spyOn(window, "setTimeout");
    timerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        scheduledRefreshes.push(handler as () => void);
        return 9003;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof timerSpy.mockImplementation>[0]);

    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    expect(screen.getByText("タブ非表示中は停止")).toBeInTheDocument();
    expect(scheduledRefreshes).toHaveLength(0);
    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;

    visibilityState = "visible";
    fireEvent(document, new Event("visibilitychange"));
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    )).toHaveLength(alertCallsBefore + 1));
    expect(scheduledRefreshes.length).toBeGreaterThan(0);
  });
});
