/** Real AG Grid component contracts in jsdom; not a browser visual/layout test. */
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { M5ObservationItem } from "../api/m5Types";
import { M5_DENSITY_KEY, M5_LAYOUT_KEY } from "../lib/m5ObservationPreferences";
import { M5_TIME_FRAMES } from "../lib/m5TimeFrame";
import { M5ObservationTable } from "./M5ObservationTable";

function observation(id = 1, symbol = "EURUSD"): M5ObservationItem {
  return {
    id, run_id: 7, symbol_name: symbol, source_mode: "TESTER", source_server: "Test-Server",
    anchor_time_frame: 5, anchor_time_frame_text: "M5", anchor_bar_time: 1700000100,
    anchor_bar_time_text: "2023.11.14 22:15:00", anchor_jst_time: 1700025300,
    anchor_jst_time_text: "2023.11.15 05:15:00", spread_pips: 0, pip_size: .0001,
    timeframes: M5_TIME_FRAMES.map(({ id: frame, label }, order) => ({
      id: id * 10 + order, observation_id: id, time_frame: frame, time_frame_text: label,
      time_frame_order: order, is_anchor_time_frame: frame === 5 ? 1 : 0,
      is_buy: frame === 5 ? 0 : 1, latest_elliot_label: "3", latest_sub_elliot_label: "iii",
      is_wave_uptrend: 1, is_ema200_buy: 1, is_ema200_sell: 0,
    })),
    captureMetrics: { observation_id: id, quote_tick_time_msc: 1700000100000,
      capture_market_time: 1700000100, analysis_elapsed_ms: 0, capture_elapsed_ms: 0, analysis_attempt_count: 1 },
    captureMetricsState: { tableAvailable: true, rowAvailable: true, missingColumns: [] },
  };
}

const props = { databaseKey: "m5-A", loading: false, sort: "anchor_jst_time" as const,
  order: "desc" as const, onSort: vi.fn(), onOpenDetail: vi.fn() };

function cell(container: HTMLElement, id: number, column: string, databaseKey = "m5-A"): HTMLElement | null {
  return container.querySelector(`[row-id="${databaseKey}:${id}"] [col-id="${column}"]`);
}

beforeEach(() => { localStorage.clear(); vi.clearAllMocks(); });
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

describe("M5ObservationTable with AG Grid", () => {
  it("renders seven saved summaries and keeps M5 SELL despite H1 BUY", async () => {
    const { container } = render(<M5ObservationTable {...props} items={[observation()]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    await waitFor(() => expect(cell(container, 1, "tf_M5")).toHaveTextContent("SELL"));
    expect(cell(container, 1, "m5_direction")).toHaveTextContent("SELL");
    expect(cell(container, 1, "tf_H1")).toHaveTextContent("BUY");
    expect(cell(container, 1, "tf_M5")).toHaveTextContent("▲3.iii");
    for (const { label } of M5_TIME_FRAMES) expect(cell(container, 1, `tf_${label}`)).not.toBeNull();
    expect(cell(container, 1, "tf_MN1")).toHaveTextContent("対象外（MN1）");
    expect(cell(container, 1, "spread_pips")).toHaveTextContent("0.0p");
    expect(cell(container, 1, "quality")).toHaveTextContent("遅れ 0秒 / 解析 0 ms / 取得 0 ms / 1回");
    expect(cell(container, 1, "quality")?.querySelector("[title]")?.getAttribute("title")).toContain("DB保存待ちは含みません");
    expect(screen.queryByText(/FULL BUY|FULL SELL|ENTRY|通貨強弱/)).not.toBeInTheDocument();
  });

  it("delegates global sorting and details without sorting current page rows locally", async () => {
    const { container } = render(<M5ObservationTable {...props} items={[observation(1, "EURUSD"), observation(2, "AUDUSD")]} />);
    await screen.findByRole("button", { name: /AUDUSD .* の詳細/ });
    fireEvent.click(screen.getByRole("button", { name: "通貨で昇順に並べ替え" }));
    expect(props.onSort).toHaveBeenLastCalledWith("symbol_name");
    fireEvent.click(screen.getByRole("button", { name: "JST日時で昇順に並べ替え" }));
    expect(props.onSort).toHaveBeenLastCalledWith("anchor_jst_time");
    expect(container.querySelector('[row-id="m5-A:1"]')).toHaveAttribute("row-index", "0");
    expect(container.querySelector('[row-id="m5-A:2"]')).toHaveAttribute("row-index", "1");
    // Pinning may replace the first rendered cell; use the currently attached button.
    const trigger = screen.getByRole("button", { name: /AUDUSD .* の詳細/ });
    fireEvent.click(trigger);
    expect(props.onOpenDetail).toHaveBeenCalledWith(2, trigger);
  });

  it("uses database identity in row keys even when numeric observation IDs coincide", async () => {
    const { container, rerender } = render(<M5ObservationTable {...props} items={[observation()]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    expect(container.querySelector('[row-id="m5-A:1"]')).not.toBeNull();
    rerender(<M5ObservationTable {...props} databaseKey="m5-B" items={[observation(1, "NZDUSD")]} />);
    await screen.findByRole("button", { name: /NZDUSD .* の詳細/ });
    await waitFor(() => expect(container.querySelector('[row-id="m5-B:1"]')).not.toBeNull());
    expect(container.querySelector('[row-id="m5-A:1"]')).toBeNull();
    expect(cell(container, 1, "symbol_name", "m5-B")).toHaveTextContent("NZDUSD");
  });

  it("keeps missing or duplicate foot slots and shows unknown direction and missing quality", async () => {
    const item = observation();
    item.timeframes = item.timeframes.filter((row) => row.time_frame !== 15);
    item.timeframes.push({ ...item.timeframes.find((row) => row.time_frame === 16385)! });
    item.timeframes.find((row) => row.time_frame === 5)!.is_buy = 2;
    item.spread_pips = null;
    item.captureMetrics = null;
    item.captureMetricsState = { tableAvailable: false, rowAvailable: false, missingColumns: [] };
    const { container } = render(<M5ObservationTable {...props} items={[item]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    await waitFor(() => expect(cell(container, 1, "tf_M15")).toHaveTextContent("未記録"));
    expect(cell(container, 1, "tf_H1")).toHaveTextContent("未記録");
    expect(cell(container, 1, "tf_H1")?.querySelector("[title]")?.getAttribute("title")).toContain("重複");
    expect(cell(container, 1, "m5_direction")).toHaveTextContent("不明");
    expect(cell(container, 1, "spread_pips")).toHaveTextContent("未記録");
    expect(cell(container, 1, "quality")).toHaveTextContent("品質テーブルなし");
    for (const { label } of M5_TIME_FRAMES) expect(cell(container, 1, `tf_${label}`)).not.toBeNull();
  });

  it("persists and restores M5 density and optional columns", async () => {
    const first = render(<M5ObservationTable {...props} items={[observation()]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    await waitFor(() => expect(cell(first.container, 1, "tf_H4")).not.toBeNull());
    fireEvent.change(screen.getByRole("combobox", { name: "M5行密度" }), { target: { value: "comfortable" } });
    fireEvent.click(screen.getByText("表示設定"));
    fireEvent.click(screen.getByRole("checkbox", { name: /^H4$/ }));
    await waitFor(() => expect(cell(first.container, 1, "tf_H4")).toBeNull());
    expect(JSON.parse(localStorage.getItem(M5_DENSITY_KEY)!)).toBe("comfortable");
    expect(JSON.parse(localStorage.getItem(M5_LAYOUT_KEY)!)).toEqual(expect.arrayContaining([
      expect.objectContaining({ colId: "tf_H4", hide: true }),
    ]));
    first.unmount();
    const second = render(<M5ObservationTable {...props} items={[observation()]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    expect(screen.getByRole("combobox", { name: "M5行密度" })).toHaveValue("comfortable");
    expect(cell(second.container, 1, "tf_H4")).toBeNull();
    expect(cell(second.container, 1, "anchor_jst_time")).not.toBeNull();
    expect(cell(second.container, 1, "symbol_name")).not.toBeNull();
    expect(cell(second.container, 1, "detail")).not.toBeNull();
  });

  it("pins context/detail on wide layout and unpins them when the media query becomes narrow", async () => {
    let wide = true;
    const listeners = new Set<() => void>();
    vi.spyOn(window, "matchMedia").mockImplementation((query) => ({
      get matches() { return query === "(min-width: 761px)" && wide; },
      media: query, onchange: null,
      addEventListener: (_type: string, listener: () => void) => { listeners.add(listener); },
      removeEventListener: (_type: string, listener: () => void) => { listeners.delete(listener); },
      addListener: (listener: () => void) => { listeners.add(listener); },
      removeListener: (listener: () => void) => { listeners.delete(listener); },
      dispatchEvent: () => true,
    } as unknown as MediaQueryList));
    const { container } = render(<M5ObservationTable {...props} items={[observation()]} />);
    await screen.findByRole("button", { name: /EURUSD .* の詳細/ });
    const left = (column: string) => container.querySelector(`.ag-header-row .ag-grid-pinned-left-cells [col-id="${column}"]`);
    const right = () => container.querySelector('.ag-header-row .ag-grid-pinned-right-cells [col-id="detail"]');
    await waitFor(() => expect(left("anchor_jst_time")).not.toBeNull());
    expect(left("symbol_name")).not.toBeNull();
    expect(left("m5_direction")).not.toBeNull();
    expect(right()).not.toBeNull();
    act(() => { wide = false; listeners.forEach((listener) => listener()); });
    await waitFor(() => expect(left("anchor_jst_time")).toBeNull());
    expect(left("symbol_name")).toBeNull();
    expect(left("m5_direction")).toBeNull();
    expect(right()).toBeNull();
    expect(container.querySelector('.ag-header-row .ag-grid-scrolling-cells [col-id="detail"]')).not.toBeNull();
  });
});
