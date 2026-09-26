import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { m5Api } from "../api/m5Client";
import type { M5DetailResponse } from "../api/m5Types";
import { M5_TIME_FRAMES } from "../lib/m5TimeFrame";
import { TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY } from "../lib/timeFrameComparisonPreferences";
import { M5ObservationDetailDrawer } from "./M5ObservationDetailDrawer";
import { M5TimeFrameComparison } from "./M5TimeFrameComparison";

function detail(id = 41, databaseKey = "m5-db-A"): M5DetailResponse {
  return {
    databaseKey,
    observation: { id, run_id: 7, symbol_name: "CADJPY", source_mode: "TESTER", source_server: "Test-Server", anchor_time_frame: 5,
      anchor_bar_time: 1700000100, anchor_bar_time_text: "2023.11.14 22:15:00", anchor_jst_time: 1700025300, anchor_jst_time_text: "2023.11.15 05:15:00",
      spread_pips: 0, pip_size: .01, time_frame_count: 7, analysis_version: "ELLIOT_MN1_V6", analysis_input_hash: "a".repeat(64),
      snapshot_hash: "0123456789ABCDEF", capture_phase: "BAR_OPEN_FIRST_SUCCESS", created_at: 1700000101, created_at_text: "2023.11.14 22:15:01" },
    run: { id: 7, source_mode: "TESTER", run_uid: "run-7", program_name: "ZigZagElliotM5ObservationAll", program_version: "1.02",
      strategy: "M5_OBSERVATION_ALL", strategy_version: "M5_OBSERVATION_ALL_V1", observation_count: 28, first_observation_jst_time: 1700025300, last_observation_jst_time: 1700025300 },
    timeframes: M5_TIME_FRAMES.map(({ id: timeFrame, label }, order) => ({ id: order + 1, observation_id: id, time_frame: timeFrame, time_frame_text: label,
      time_frame_order: order, is_anchor_time_frame: timeFrame === 5 ? 1 : 0, is_buy: timeFrame === 5 ? 0 : 1,
      latest_elliot_label: "3", latest_sub_elliot_label: "iii", is_wave_uptrend: 1, is_wave_confirmed: 0, is_wave_motive: 1,
      latest_point_is_added: 0, is_ema200_buy: 0, is_ema200_sell: 1, gmma_trend_count: 0, gmma_cross_count: -1,
      stochastic_main_order_text: "S>M>L", stochastic_main_direction_text: "UP", atr14_pips: 0,
      latest_point_org_elliot_index: 3, latest_point_org_elliot_label: "3", latest_point_fibonacci_expansion_percent: 161.8,
      latest_point_is_peak: 1, latest_point_wave_bars_from_start: 0, latest_point_pips_diff: 0,
      previous_open: 100, previous_high: 102, previous_low: 99, previous_close: 101,
      current_open: 101, current_high: 101, current_low: 101, current_close: 101 })),
    captureMetrics: { observation_id: id, quote_tick_time_msc: 1700000100000, capture_market_time: 1700000100, analysis_elapsed_ms: 0, capture_elapsed_ms: 0, analysis_attempt_count: 1 },
    captureMetricsState: { tableAvailable: true, rowAvailable: true, missingColumns: [] },
    navigation: { older: { id: 40, anchor_bar_time: 1699827300, anchor_bar_time_text: "2023.11.12 22:15:00", anchor_jst_time: 1699852500,
      anchor_jst_time_text: "2023.11.13 05:15:00", gap_seconds: 172800 }, newer: null },
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((accept) => { resolve = accept; });
  return { promise, resolve };
}

it("requests M15 navigation and treats a 15-minute step as normal", async () => {
  const response = detail();
  response.navigation.older!.gap_seconds = 900;
  const request = vi.spyOn(m5Api, "detail").mockResolvedValue(response);
  const view = render(<M5ObservationDetailDrawer {...props} displayInterval={15} />);
  await screen.findByText("表示間隔 M15");
  expect(request).toHaveBeenCalledWith(41, "m5-db-A", expect.any(AbortSignal), 15);
  expect(screen.queryByText(/時刻差/)).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /前の観測 JST/ }));
  expect(props.onNavigate).toHaveBeenCalledWith(40);
  const pending = deferred<M5DetailResponse>();
  request.mockReturnValueOnce(pending.promise);
  view.rerender(<M5ObservationDetailDrawer {...props} displayInterval={5} />);
  expect(screen.queryByRole("button", { name: /前の観測 JST/ })).not.toBeInTheDocument();
  await act(async () => pending.resolve(response));
  await screen.findByText("表示間隔 M5");
  expect(request).toHaveBeenLastCalledWith(41, "m5-db-A", expect.any(AbortSignal), 5);
  expect(screen.getByText(/900秒/)).toBeInTheDocument();
});

it.each([[60, "H1"], [240, "H4"], [1440, "D1"]] as const)("uses %s for detail navigation and labels it %s", async (interval, label) => {
  const response = detail();
  response.navigation.older!.gap_seconds = interval * 60;
  const request = vi.spyOn(m5Api, "detail").mockResolvedValue(response);
  render(<M5ObservationDetailDrawer {...props} displayInterval={interval} />);
  await screen.findByText(`表示間隔 ${label}`);
  expect(request).toHaveBeenCalledWith(41, "m5-db-A", expect.any(AbortSignal), interval);
  expect(screen.queryByText(/時刻差/)).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: /前の観測 JST/ })).toHaveAttribute("title", expect.stringContaining(`表示間隔 ${label}`));
});

const props = { observationId: 41, databaseKey: "m5-db-A", databaseName: "m5-study.sqlite", onClose: vi.fn(), onNavigate: vi.fn() };

beforeEach(() => { localStorage.clear(); localStorage.setItem("m5Observation.detailView.v1", JSON.stringify("normal")); vi.clearAllMocks(); });
afterEach(() => { cleanup(); vi.restoreAllMocks(); document.body.classList.remove("drawer-open"); });

describe("M5 observation detail", () => {
  it("opens comparison first, keeps seven ordered rows, shows independent SELL and zero quality", async () => {
    const request = vi.spyOn(m5Api, "detail").mockResolvedValue(detail());
    render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    expect(request).toHaveBeenCalledWith(41, "m5-db-A", expect.any(AbortSignal), 5);
    const table = within(screen.getByRole("region", { name: "7時間足比較表" })).getByRole("table");
    expect(Array.from(table.querySelectorAll("tbody tr")).map((row) => row.getAttribute("data-timeframe"))).toEqual(["MN1", "W1", "D1", "H4", "H1", "M15", "M5"]);
    expect(within(table.querySelector('[data-timeframe="M5"]') as HTMLElement).getByText("SELL", { selector: ".badge" })).toBeInTheDocument();
    expect(screen.getAllByText("▲3.iii")).toHaveLength(7);
    expect(screen.getAllByText("基準足")).toHaveLength(1);
    expect(screen.getByText("対象外（MN1）")).toBeInTheDocument();
    const quality = screen.getByRole("region", { name: "M5取得品質" });
    expect(within(quality).getByText("0秒")).toBeInTheDocument();
    expect(within(quality).getAllByText("0 ms")).toHaveLength(2);
    expect(screen.getByText("TIMEFRAME COMPARISON").compareDocumentPosition(screen.getByText("CAPTURE QUALITY")) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.queryByText(/ENTRY|FULL BUY|FULL SELL/)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "次の観測なし" })).toBeDisabled();
    expect(screen.getByTitle("Server 2023.11.14 22:15:00")).toHaveTextContent("Server 2023.11.14 22:15:00");
    const navigation = screen.getByRole("navigation", { name: "同一Run・通貨の前後観測" });
    expect(navigation.parentElement).toHaveClass("m5-detail-context");
    expect(navigation.parentElement?.firstElementChild).toBe(navigation);
    expect(within(navigation).getByRole("button", { name: /前の観測 JST/ })).toHaveTextContent("← 前");
    expect(within(navigation).getByRole("button", { name: /前の観測 JST/ })).toHaveAttribute("title", expect.stringContaining("JST 2023.11.13 05:15:00"));
    expect(screen.getByText(/172,800秒/)).toHaveTextContent("休場・欠損は断定不可");
    fireEvent.click(screen.getByRole("button", { name: /前の観測 JST/ }));
    expect(props.onNavigate).toHaveBeenCalledWith(40);
  });

  it("places the strength reference above the grid and keeps it in normal view", async () => {
    const value = detail();
    value.currencyStrength = { status: "FOUND", databaseName: "strength-2023.sqlite", calculationMode: "UNIFORM",
      calculationVersion: "pair-direction-closed-v1", targetM5BarTime: 1700000100, actualM5BarTime: 1700000100,
      runId: 42, sourceMode: "TESTER", baseCurrency: "CAD", quoteCurrency: "JPY", periods: [
        { label: "長中期", baseRank: 2, quoteRank: 7, rankDifference: 5, direction: "BUY" },
        { label: "中短期", baseRank: 1, quoteRank: 6, rankDifference: 5, direction: "BUY" },
      ] };
    localStorage.setItem("m5Observation.detailView.v1", JSON.stringify("grid"));
    vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    render(<M5ObservationDetailDrawer {...props} />);
    const strength = await screen.findByRole("region", { name: "通貨強弱（観測時刻・別DB参照）" });
    const grid = screen.getByRole("region", { name: "M5全画面時間足比較" });
    expect(strength.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(within(strength).getAllByText("+5")).toHaveLength(2);
    fireEvent.click(screen.getByRole("button", { name: "通常表示" }));
    expect(screen.getByRole("region", { name: "通貨強弱（観測時刻・別DB参照）" })).toBeInTheDocument();
  });

  it("preserves missing slots and exposes saved F/FE and forming OHLC only on expansion", async () => {
    const value = detail();
    value.timeframes = value.timeframes.filter((row) => row.time_frame !== 15);
    value.timeframes[0].time_frame_order = 6;
    value.timeframes[0].is_anchor_time_frame = 1;
    vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    expect(screen.getByRole("alert")).toHaveTextContent("M15: 子行が未記録");
    expect(screen.getByRole("alert")).toHaveTextContent("基準足フラグ不整合");
    expect(document.querySelectorAll(".m5-comparison tbody tr")).toHaveLength(7);
    fireEvent.click(screen.getByRole("button", { name: "最新ZigZag Point" }));
    expect(screen.getAllByText("FE 161.8%")).toHaveLength(6);
    fireEvent.click(screen.getByRole("button", { name: "OHLC" }));
    expect(screen.getByText(/現在足OHLCは取得時点の途中経過/)).toBeInTheDocument();
    expect(localStorage.getItem("m5Observation.comparisonSections.v1")).toContain('"ohlc":true');
    expect(localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY)).toBeNull();
  });

  it("reports absent quality table and never substitutes created_at for capture time", async () => {
    const value = detail();
    value.captureMetrics = null;
    value.captureMetricsState = { tableAvailable: false, rowAvailable: false, missingColumns: [] };
    vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    render(<M5ObservationDetailDrawer {...props} />);
    const quality = await screen.findByRole("region", { name: "M5取得品質" });
    expect(within(quality).getByText("未記録：品質テーブルがありません。")).toBeInTheDocument();
    expect(within(quality).queryByText("0秒")).not.toBeInTheDocument();
    expect(within(quality).queryByText("2023.11.14 22:15:01")).not.toBeInTheDocument();
    fireEvent.click(screen.getByText("RECORD INFO"));
    expect(screen.getByText(/created_atはFIFO追加前/)).toHaveTextContent("DB commit完了時刻・収集終了日時ではありません");
    fireEvent.click(screen.getByRole("button", { name: "M5観測詳細を閉じる" }));
    expect(props.onClose).toHaveBeenCalledOnce();
  });

  it("discards superseded IDs even if the aborted old request resolves later", async () => {
    const old = deferred<M5DetailResponse>();
    vi.spyOn(m5Api, "detail").mockImplementation((id) => id === 41 ? old.promise : Promise.resolve(detail(id)));
    const { rerender } = render(<M5ObservationDetailDrawer {...props} />);
    rerender(<M5ObservationDetailDrawer {...props} observationId={42} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    await act(async () => old.resolve({ ...detail(), observation: { ...detail().observation, symbol_name: "WRONG-OLD" } }));
    expect(screen.queryByText(/WRONG-OLD/)).not.toBeInTheDocument();
    expect(screen.getByText("Observation ID").nextSibling).toHaveTextContent("42");
  });

  it("does not reuse same numeric ID from another database and rejects a wrong DB response", async () => {
    const next = deferred<M5DetailResponse>();
    vi.spyOn(m5Api, "detail").mockImplementation((_id, key) => key === "m5-db-A" ? Promise.resolve(detail()) : next.promise);
    const { rerender } = render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    rerender(<M5ObservationDetailDrawer {...props} databaseKey="m5-db-B" databaseName="other.sqlite" />);
    expect(screen.queryByText("TIMEFRAME COMPARISON")).not.toBeInTheDocument();
    await act(async () => next.resolve(detail()));
    expect(await screen.findByRole("alert")).toHaveTextContent("接続DBまたは観測IDが変わりました");
    expect(screen.queryByText("CAPTURE QUALITY")).not.toBeInTheDocument();
  });

  it("does not fetch inactive details, aborts on tab hide, and preserves an error instead of empty data", async () => {
    const pending = deferred<M5DetailResponse>();
    const request = vi.spyOn(m5Api, "detail").mockReturnValue(pending.promise);
    const { rerender } = render(<M5ObservationDetailDrawer {...props} active={false} />);
    expect(request).not.toHaveBeenCalled();
    rerender(<M5ObservationDetailDrawer {...props} active />);
    await waitFor(() => expect(request).toHaveBeenCalledOnce());
    const signal = request.mock.calls[0][2];
    rerender(<M5ObservationDetailDrawer {...props} active={false} />);
    expect(signal?.aborted).toBe(true);
    await act(async () => pending.resolve(detail()));
    expect(screen.queryByText("TIMEFRAME COMPARISON")).not.toBeInTheDocument();
    request.mockRejectedValue(new Error("一時読取失敗"));
    rerender(<M5ObservationDetailDrawer {...props} active />);
    expect(await screen.findByRole("alert")).toHaveTextContent("更新失敗：一時読取失敗");
    expect(screen.queryByText("0件")).not.toBeInTheDocument();
  });
});

describe("M5 comparison preference isolation", () => {
  it("restores expansion after remount without touching existing H1 preferences", () => {
    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, "preserved-H1-settings");
    const first = render(<M5TimeFrameComparison timeFrames={detail().timeframes} />);
    fireEvent.click(screen.getByRole("button", { name: "OHLC" }));
    fireEvent.click(screen.getByRole("button", { name: "指標詳細" }));
    first.unmount();
    render(<M5TimeFrameComparison timeFrames={detail().timeframes} />);
    expect(screen.getByRole("button", { name: "OHLC" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "指標詳細" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "最新ZigZag Point" })).toHaveAttribute("aria-pressed", "false");
    expect(localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY)).toBe("preserved-H1-settings");
  });

  it("ignores malformed storage instead of coercing truthy text into expansion", () => {
    localStorage.setItem("m5Observation.comparisonSections.v1", '{"point":"true","ohlc":1,"indicators":true}');
    render(<M5TimeFrameComparison timeFrames={[]} />);
    expect(screen.getByRole("button", { name: "最新ZigZag Point" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "OHLC" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "指標詳細" })).toHaveAttribute("aria-pressed", "true");
    expect(document.querySelectorAll(".m5-comparison tbody tr")).toHaveLength(7);
  });

  it("continues in memory when browser storage cannot be read or written", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new Error("denied"); });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("denied"); });
    render(<M5TimeFrameComparison timeFrames={detail().timeframes} />);
    expect(screen.getByRole("button", { name: "OHLC" })).toHaveAttribute("aria-pressed", "false");
    fireEvent.click(screen.getByRole("button", { name: "OHLC" }));
    expect(screen.getByRole("button", { name: "OHLC" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByText(/現在足OHLCは取得時点の途中経過/)).toBeInTheDocument();
  });
});

describe("M5 full-screen detail grid", () => {
  it("colors each cell by its own direction and leaves neutral values and prices uncolored", async () => {
    localStorage.removeItem("m5Observation.detailView.v1");
    const value = detail();
    Object.assign(value.timeframes.find((row) => row.time_frame === 5)!, {
      oscillator_count: 2, stochastic_short_count: -3, stochastic_middle_count: 0,
      stochastic_long_count: null, latest_point_rate: 101.25, latest_point_pips_diff: 12.3,
      ema200_slope_pips: 0.01, ema200_close_diff_pips: -1.2, ema30_ema60_diff_pips: 2.3,
    });
    vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    render(<M5ObservationDetailDrawer {...props} />);
    const table = await screen.findByRole("table", { name: "M5詳細7時間足比較" });
    const cell = (label: string) => {
      const headers = Array.from(table.querySelectorAll("thead tr:last-child th"));
      return table.querySelector('[data-timeframe="M5"]')!.children[headers.findIndex((header) => header.textContent === label)].querySelector("span")!;
    };
    expect(cell("分析方向")).toHaveClass("m5-sell");
    expect(cell("Elliott / Sub")).toHaveClass("m5-sell");
    expect(cell("Elliott / Sub")).toHaveTextContent("▲3.iii");
    expect(cell("Oscillator Count")).toHaveTextContent("+2");
    expect(cell("Oscillator Count")).toHaveClass("m5-buy");
    expect(cell("Stochastic 短期 Count")).toHaveClass("m5-sell");
    for (const label of ["Stochastic 中期 Count", "Stochastic 長期 Count", "最新点価格", "pips差", "Wave状態", "直前推進波の副次波", "最新点の取得種別", "F / FE（元番号に対応）"]) {
      expect(cell(label)).not.toHaveClass("m5-buy", "m5-sell");
    }
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    expect(cell("Wave方向")).toHaveClass("m5-buy");
    expect(cell("傾き pips")).toHaveTextContent("0.0");
    expect(cell("傾き pips")).not.toHaveClass("m5-buy", "m5-sell");
    expect(cell("終値距離 pips")).toHaveClass("m5-sell");
    expect(cell("EMA30–60距離 pips")).toHaveClass("m5-buy");
  });

  it("shows detailed saved fields without another request and keeps M5 preferences separate", async () => {
    localStorage.removeItem("m5Observation.detailView.v1");
    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, "preserved-H1-settings");
    const value = detail();
    value.observation.anchor_jst_time = value.observation.anchor_bar_time + 3600;
    value.observation.anchor_jst_time_text = "2023.11.14 23:15:00";
    const request = vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    const first = render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByRole("table", { name: "M5詳細7時間足比較" });
    expect(screen.getByTitle("Server 2023.11.14 22:15:00")).toHaveTextContent(/^Server 22:15:00$/);
    expect(screen.getByRole("navigation", { name: "同一Run・通貨の前後観測" }).parentElement).toHaveClass("m5-detail-context");
    expect(screen.getByRole("button", { name: "全画面グリッド" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const table = screen.getByRole("table", { name: "M5詳細7時間足比較" });
    expect(Array.from(table.querySelectorAll("tbody tr")).map((row) => row.getAttribute("data-timeframe"))).toEqual(["MN1", "W1", "D1", "H4", "H1", "M15", "M5"]);
    const summaryLabels = ["時間足", "分析方向", "EMA200方向", "Elliott / Sub", "Wave状態", "直前推進波の副次波", "最新点の取得種別",
      "F / FE（元番号に対応）", "pips差", "最新点価格", "Oscillator Count", "Stochastic 短期 Count", "Stochastic 中期 Count", "Stochastic 長期 Count", "GMMA Trend", "GMMA Cross"];
    const columnLabels = () => Array.from(table.querySelectorAll("thead tr:last-child th")).map((header) => header.textContent);
    expect(columnLabels()).toEqual(summaryLabels);
    expect(Array.from(table.querySelectorAll("tbody tr")).every((row) => row.children.length === 16)).toBe(true);
    expect(within(table).getByRole("columnheader", { name: "Wave状態" })).toHaveAttribute("title", expect.stringContaining("\n形成中：最新Waveは未確定です。"));
    expect(table.querySelector("td[title]")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "その他指標" }));
    expect(screen.getByRole("button", { name: "すべて表示" })).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    expect(columnLabels().filter((label) => summaryLabels.includes(label!))).toEqual(summaryLabels);
    expect(within(table).getByRole("columnheader", { name: "取得時点の形成中足 Close" })).toBeInTheDocument();
    expect(within(table).getByRole("columnheader", { name: "Stochastic 長期 Signal" })).toBeInTheDocument();
    expect(within(table).getAllByText("FE 161.8%")).toHaveLength(7);
    expect(table.querySelector('[data-timeframe="M5"] .m5-snapshot-key-1')).toHaveTextContent("SELL");
    expect(screen.getByRole("region", { name: "M5保存情報" }).querySelector("details")).toHaveAttribute("open");
    expect(screen.getByText("a".repeat(64), { selector: "code" })).toBeVisible();
    expect(request).toHaveBeenCalledOnce();
    fireEvent.click(screen.getByRole("button", { name: "要点のみ" }));
    expect(columnLabels()).toEqual(summaryLabels);
    expect(localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY)).toBe("preserved-H1-settings");
    first.unmount();
    render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByRole("table", { name: "M5詳細7時間足比較" });
    expect(screen.getByRole("button", { name: "全画面グリッド" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByRole("button", { name: "通常表示" }));
    expect(screen.getByText("TIMEFRAME COMPARISON")).toBeInTheDocument();
  });

  it("expands the selected column group and distinguishes absent, duplicate, zero and unavailable values", async () => {
    const value = detail();
    value.timeframes = value.timeframes.filter((row) => row.time_frame !== 15);
    value.timeframes.push({ ...value.timeframes[1] });
    const m5 = value.timeframes.find((row) => row.time_frame === 5)!;
    m5.is_fibo_expansion_available = 0;
    m5.fe2000_price = 123;
    m5.ema200_close1 = NaN;
    m5.previous_motive_sub_elliot_index = 3;
    value.timeframes.find((row) => row.time_frame === 16385)!.previous_motive_sub_elliot_index = 1;
    value.timeframes.find((row) => row.time_frame === 16408)!.previous_motive_sub_elliot_index = 0;
    value.timeframes.find((row) => row.time_frame === 16388)!.previous_motive_sub_elliot_index = 2;
    vi.spyOn(m5Api, "detail").mockResolvedValue(value);
    render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    const table = screen.getByRole("table", { name: "M5詳細7時間足比較" });
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    const headers = Array.from(table.querySelectorAll("thead tr:last-child th"));
    const cell = (frame: string, label: string) => table.querySelector(`[data-timeframe="${frame}"]`)!.children[headers.findIndex((header) => header.textContent === label)];
    expect(cell("M5", "Close1")).toHaveTextContent("不正値");
    expect(cell("M5", "直前推進波の副次波")).toHaveTextContent("3波に副次波あり");
    expect(cell("H1", "直前推進波の副次波")).toHaveTextContent("1波に副次波あり");
    expect(cell("D1", "直前推進波の副次波")).toHaveTextContent("該当なし");
    expect(cell("MN1", "直前推進波の副次波")).toHaveTextContent("未記録");
    expect(cell("H4", "直前推進波の副次波")).toHaveTextContent("不正値");
    expect(within(table).getByRole("columnheader", { name: "直前推進波の副次波" })).toHaveAttribute("title", expect.stringContaining("現在2・3波：1波の副次波を確認\n"));
    expect(cell("M5", "直前推進波の副次波")).not.toHaveAttribute("title");
    expect(cell("MN1", "Close1")).toHaveTextContent("対象外（MN1）");
    expect(cell("M5", "FE 200%価格")).toHaveTextContent("利用不可");
    expect(cell("H1", "FE 200%価格")).toHaveTextContent("未記録");
    expect(cell("M5", "ATR14 pips")).toHaveTextContent("0.0");
    expect(cell("M15", "分析方向")).toHaveTextContent("未記録・足構成を要確認");
    expect(cell("W1", "分析方向")).toHaveTextContent("未記録・足構成を要確認");
    fireEvent.click(screen.getByRole("button", { name: "要点のみ" }));
    expect(within(table).queryByRole("columnheader", { name: "Close1" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /^EMA200$/ }));
    expect(within(table).getByRole("columnheader", { name: "Close1" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "要点のみ" })).toHaveAttribute("aria-expanded", "true");
  });

  it("restores grid and body scroll after navigation while withholding the previous observation", async () => {
    const next = deferred<M5DetailResponse>();
    vi.spyOn(m5Api, "detail").mockImplementation((id) => id === 41 ? Promise.resolve(detail()) : next.promise);
    const { rerender } = render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByText("TIMEFRAME COMPARISON");
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    fireEvent.scroll(screen.getByRole("region", { name: "M5全画面グリッド" }), { target: { scrollLeft: 900, scrollTop: 40 } });
    fireEvent.scroll(document.querySelector(".m5-detail-dialog .drawer-body")!, { target: { scrollTop: 100 } });
    rerender(<M5ObservationDetailDrawer {...props} observationId={40} />);
    expect(screen.queryByRole("table", { name: "M5詳細7時間足比較" })).not.toBeInTheDocument();
    await act(async () => next.resolve(detail(40)));
    const grid = await screen.findByRole("region", { name: "M5全画面グリッド" });
    expect(grid.scrollLeft).toBe(900);
    expect(grid.scrollTop).toBe(40);
    expect(document.querySelector(".m5-detail-dialog .drawer-body")!.scrollTop).toBe(100);
    expect(screen.getByText("Observation ID").nextSibling).toHaveTextContent("40");
  });

  it("allows switching and closing when preference storage is unavailable", async () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new Error("denied"); });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("denied"); });
    vi.spyOn(m5Api, "detail").mockResolvedValue(detail());
    render(<M5ObservationDetailDrawer {...props} />);
    await screen.findByRole("table", { name: "M5詳細7時間足比較" });
    fireEvent.click(screen.getByRole("button", { name: "通常表示" }));
    expect(screen.getByText("TIMEFRAME COMPARISON")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "全画面グリッド" }));
    expect(screen.getByRole("table", { name: "M5詳細7時間足比較" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "M5観測詳細を閉じる" }));
    expect(props.onClose).toHaveBeenCalledOnce();
  });
});
