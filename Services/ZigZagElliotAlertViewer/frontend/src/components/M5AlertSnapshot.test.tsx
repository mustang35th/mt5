import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { AlertCorrectionMetadata, AlertDetail, AlertDetailResponse, AlertPoint, AlertTimeFrame } from "../api/types";
import { M5AlertSnapshot } from "./M5AlertSnapshot";

const frames = [[49153, "MN1"], [32769, "W1"], [16408, "D1"], [16388, "H4"], [16385, "H1"], [15, "M15"], [5, "M5"]] as const;
function fixture() {
  const timeFrames = frames.map(([frame, label], index) => ({
    id: index + 1, alert_id: 81, time_frame: frame, time_frame_text: label, time_frame_order: index,
    is_current_time_frame: frame === 5, is_buy: frame !== 16385, buy_sell_label: "BUY", latest_elliot_label: "1", latest_sub_elliot_label: "i",
    is_wave_uptrend: true, is_wave_confirmed: false, is_wave_motive: true, point_count: 1, wave_count: 5, latest_wave_index: 4,
    is_ema200_available: true, is_ema200_buy: true, is_ema200_sell: false,
    oscillator_count: 3, stochastic_short_count: 2, stochastic_middle_count: -1, stochastic_long_count: 0, gmma_trend_count: 5, gmma_cross_count: -3,
    previous_open: 150, previous_high: 151, previous_low: 149, previous_close: 150.5, current_open: 150.5, current_high: 150.8, current_low: 150.4, current_close: 150.6,
    latest_point_is_added: false, is_fibo_expansion_available: true, fe1618_price: 151.5,
  } as AlertTimeFrame));
  const points = timeFrames.map((row) => ({
    id: row.id, alert_id: 81, alert_timeframe_id: row.id, time_frame: row.time_frame, time_frame_text: row.time_frame_text, time_frame_order: row.time_frame_order,
    point_order: 0, bar_time: 1700000000, bar_time_text: "2023.11.14 22:13:20", rate: 150.1, is_peak: true, elliot_label: "1", sub_elliot_label: "i",
    org_elliot_index: 3, org_elliot_label: "3", pips_diff: 12.5, is_fibonacci_available: false, fibonacci_percent: 0,
    is_fibonacci_expansion_available: true, fibonacci_expansion_percent: 120, is_latest: true, is_signal_reference: row.time_frame === 5, is_added_point: false, is_correct: false,
  } as AlertPoint));
  const corrected = timeFrames.map((row) => ({ ...row, is_buy: true }));
  corrected[6].latest_elliot_label = "3";
  const correctedPoints = points.map((point) => ({ ...point }));
  correctedPoints[6].rate = 150.25;
  correctedPoints[6].elliot_label = "3";
  correctedPoints[6].fibonacci_expansion_percent = 161.8;
  const metadata: AlertCorrectionMetadata = {
    alert_id: 81, correction_status: "APPLIED", correction_time_frame: 16385, original_direction: "SELL", corrected_direction: "BUY", selected_analysis: "CORRECTED",
    selected_alert_text: "▲1-1-3 [H1補正]", selected_current_elliot_label: "3", selected_wave_summary_text: "saved selected waves",
    reference_price: 150.5, is_selected_stop_loss_available: true, selected_stop_loss: 149.75, selected_risk_pips: 75,
    original_lc0: 149.7, original_lc5: 149.65, original_lc10: 149.6, original_lc15: 149.55, original_loss_cut_diff_pips: 80, original_loss_cut_diff_jpy: 800,
    corrected_lc0: 149.8, corrected_lc5: 149.75, corrected_lc10: 149.7, corrected_lc15: 149.65, corrected_loss_cut_diff_pips: 70, corrected_loss_cut_diff_jpy: 700,
    corrected_reference_point_time: 1700000300, original_analysis_text: "RAW FULL TEXT [3副] <script>raw</script>", corrected_analysis_text: "SELECTED FULL TEXT [5副] <img src=x>",
    corrected_elliot_csv_text: "CORRECTED,CSV", comparison_hash: "0123456789ABCDEF", created_at: 1700000500, created_at_text: "saved time",
  };
  const alert = {
    id: 81, run_id: 3, time_frame: 5, time_frame_text: "M5", symbol_name: "USDJPY", side: "BUY", current_bar_time_text: "2023.11.14 22:15:00",
    jst_time_text: "2023.11.15 04:15:00", server_time_text: "2023.11.14 22:15:00", reference_price: 150.5, is_stop_loss_available: true, stop_loss: 149.65, risk_pips: 85,
    signal_count: 1, entry_count: 1, is_entry: true, entry_result: "ENTRY", current_elliot_label: "3", spread_pips: 1.2, alert_text: "RAW ALERT",
    is_currency_strength_enabled: false, is_currency_strength_available: false, currency_strength_status: 0, market_signal_key: "raw-key",
  } as AlertDetail;
  const detail: AlertDetailResponse = { alert, run: { id: 3, source_mode: "TESTER", program_version: "1.44", tester_model: "Every tick" }, w1: null,
    correction: { status: "APPLIED", reason: null, metadata, timeframes: corrected, points: correctedPoints } };
  return { detail, timeFrames, points };
}
function grid() { return screen.getByRole("table", { name: "M5アラート7時間足比較" }); }
function row(frame: string, analysis: string): HTMLElement {
  return grid().querySelector(`[data-timeframe="${frame}"][data-analysis="${analysis}"]`) as HTMLElement;
}
afterEach(cleanup);

describe("M5 Alert corrected snapshots", () => {
  it("shows previous motive subwaves in summary and compares each analysis independently", () => {
    const data = fixture();
    data.detail.correction!.metadata!.original_analysis_text = "H1/SELL/[1副] ▲3/\r\nEMA200/SELL/\r\nM5/BUY/▲3/";
    data.detail.correction!.metadata!.corrected_analysis_text = "H1/BUY/[3副] ▲5/\nEMA200/BUY/\nM5/BUY/[1副] ▲3/";
    render(<M5AlertSnapshot {...data} />);
    expect(within(grid()).getByRole("columnheader", { name: "直前推進波の副次波" })).toBeInTheDocument();
    const cell = (frame: string, analysis: string) => row(frame, analysis).querySelector('[data-column="previous-motive-sub"]');
    expect(cell("H1", "CORRECTED")).toHaveTextContent("3波に副次波あり");
    expect(cell("M5", "CORRECTED")).toHaveTextContent("1波に副次波あり");
    expect(cell("M15", "CORRECTED")).toHaveTextContent("未記録");
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    expect(cell("H1", "ORIGINAL")).toHaveTextContent("1波に副次波あり");
    expect(cell("M5", "ORIGINAL")).toHaveTextContent("記載なし");
    expect(cell("H1", "CORRECTED")).toHaveClass("m5-alert-changed");
    fireEvent.click(screen.getByRole("checkbox", { name: "差がある列のみ" }));
    expect(cell("H1", "CORRECTED")).toHaveTextContent("3波に副次波あり");
  });

  it.each([undefined, "", "M15/BUY/[1副] ▲3/", "M5/BUY/[5副] ▲5/",
    "M5/BUY/[1副] ▲3/\nM5/BUY/[3副] ▲5/", "M5/BUY/", "M5/UNKNOWN/[1副] ▲3/"])(
    "does not infer a subwave from missing or ambiguous saved text: %s", (content) => {
      const data = fixture();
      data.detail.correction!.metadata!.corrected_analysis_text = content as string;
      data.detail.correction!.metadata!.original_analysis_text = "M5/BUY/[1副] ▲3/";
      render(<M5AlertSnapshot {...data} />);
      expect(row("M5", "CORRECTED").querySelector('[data-column="previous-motive-sub"]')).toHaveTextContent("未記録");
    });

  it("shows markers from the original text when correction was not applied", () => {
    const data = fixture();
    data.detail.correction!.status = "NONE";
    data.detail.correction!.metadata!.original_analysis_text = "M5/BUY/[1副] ▲3/";
    render(<M5AlertSnapshot {...data} />);
    expect(row("M5", "ORIGINAL").querySelector('[data-column="previous-motive-sub"]')).toHaveTextContent("1波に副次波あり");
  });
  it("starts from adopted seven frames and keeps SL and entry result fixed when viewing originals", () => {
    const data = fixture();
    render(<M5AlertSnapshot {...data} />);
    expect(screen.getByRole("button", { name: "補正後（採用）" })).toHaveAttribute("aria-pressed", "true");
    expect(Array.from(grid().querySelectorAll("tbody tr")).map((item) => item.getAttribute("data-timeframe"))).toEqual(frames.map((item) => item[1]));
    expect(row("M5", "CORRECTED")).toHaveTextContent("▲3.i");
    expect(row("H1", "CORRECTED")).toHaveTextContent("方向補正");
    const decision = screen.getByRole("region", { name: "保存済みエントリー判定" });
    const sl = screen.getByRole("region", { name: "判定時の損切り候補" });
    expect(decision).toHaveTextContent("ENTRY");
    expect(sl).toHaveTextContent("149.75000");
    fireEvent.click(screen.getByRole("button", { name: "補正前" }));
    expect(row("M5", "ORIGINAL")).toHaveTextContent("▲1.i");
    expect(decision).toHaveTextContent("▲1-1-3 [H1補正]");
    expect(sl).toHaveTextContent("149.75000");
    expect(screen.queryByText("H1 ENTRY CHECK")).not.toBeInTheDocument();
  });

  it("pairs after then before per frame, highlights changed cells and retains directional text colors", () => {
    render(<M5AlertSnapshot {...fixture()} />);
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    expect(Array.from(grid().querySelectorAll("tbody tr")).map((item) => `${item.getAttribute("data-timeframe")}-${item.getAttribute("data-analysis")}`)).toEqual(frames.flatMap((frame) => [`${frame[1]}-CORRECTED`, `${frame[1]}-ORIGINAL`]));
    const h1 = row("H1", "ORIGINAL");
    expect(h1.querySelector('[data-column="direction"]')).toHaveClass("m5-alert-changed");
    expect(h1.querySelector('[data-column="wave"] span')).toHaveClass("m5-alert-sell");
    expect(row("H1", "CORRECTED").querySelector('[data-column="wave"] span')).toHaveClass("m5-alert-buy");
    expect(row("M5", "CORRECTED").querySelector('[data-column="point-rate"]')).toHaveClass("m5-alert-changed");
    expect(row("M5", "CORRECTED").querySelector('[data-column="oscillator_count"]')).not.toHaveClass("m5-alert-changed");
    expect(row("M5", "CORRECTED").querySelector('[data-column="oscillator_count"]')).toHaveTextContent("+3");
    expect(row("M5", "CORRECTED").querySelector('[data-column="gmma_cross_count"] span')).toHaveClass("m5-alert-sell");
  });

  it("shows only changed columns on request and restores all indicators and OHLC", () => {
    render(<M5AlertSnapshot {...fixture()} />);
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "差がある列のみ" }));
    expect(within(grid()).getByRole("columnheader", { name: "分析方向" })).toBeInTheDocument();
    expect(within(grid()).getByRole("columnheader", { name: "最新点価格" })).toBeInTheDocument();
    expect(within(grid()).queryByRole("columnheader", { name: "GMMA Cross" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("checkbox", { name: "差がある列のみ" }));
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    expect(within(grid()).getByRole("columnheader", { name: "直前確定足 open" })).toBeInTheDocument();
    expect(within(grid()).getByRole("columnheader", { name: "取得時点の形成中足 close" })).toBeInTheDocument();
    expect(within(grid()).getByRole("columnheader", { name: "EMA200 傾き pips" })).toBeInTheDocument();
  });

  it("joins points within their own analysis even when parent and point IDs overlap", () => {
    const data = fixture();
    render(<M5AlertSnapshot {...data} />);
    expect(row("M5", "CORRECTED").querySelector('[data-column="point-rate"]')).toHaveTextContent("150.25000");
    expect(row("M5", "CORRECTED").querySelector('[data-column="fibonacci"]')).toHaveTextContent("FE 161.8%");
    fireEvent.click(screen.getByRole("button", { name: "補正前" }));
    expect(row("M5", "ORIGINAL").querySelector('[data-column="point-rate"]')).toHaveTextContent("150.10000");
    expect(row("M5", "ORIGINAL").querySelector('[data-column="fibonacci"]')).toHaveTextContent("FE 120.0%");
  });

  it("uses original Elliott index for F/FE and preserves unknown flags", () => {
    const data = fixture();
    const point = data.detail.correction!.points[6];
    point.org_elliot_index = 2;
    point.is_fibonacci_available = true;
    point.fibonacci_percent = 61.8;
    data.detail.correction!.timeframes[6].is_wave_confirmed = null as unknown as boolean;
    point.is_added_point = null as unknown as boolean;
    render(<M5AlertSnapshot {...data} />);
    const current = row("M5", "CORRECTED");
    expect(current.querySelector('[data-column="fibonacci"]')).toHaveTextContent("F 61.8%");
    expect(current.querySelector('[data-column="state"]')).toHaveTextContent("未記録");
    expect(current.querySelector('[data-column="added"]')).toHaveTextContent("未記録");
  });

  it("does not show unavailable FE distances as zero", () => {
    const data = fixture();
    data.detail.correction!.timeframes[6].is_fibo_expansion_available = false;
    data.detail.correction!.timeframes[6].distance_to_fe2000_pips = 0;
    render(<M5AlertSnapshot {...data} />);
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    expect(row("M5", "CORRECTED").querySelector('[data-column="distance_to_fe2000_pips"]')).toHaveTextContent("利用不可");
  });

  it("preserves unknown EMA direction flags and distinguishes explicit conflicts", () => {
    const data = fixture();
    data.detail.correction!.timeframes[6].is_ema200_buy = null as unknown as boolean;
    data.detail.correction!.timeframes[6].is_ema200_sell = null as unknown as boolean;
    data.detail.correction!.timeframes[5].is_ema200_buy = true;
    data.detail.correction!.timeframes[5].is_ema200_sell = true;
    render(<M5AlertSnapshot {...data} />);
    expect(row("M5", "CORRECTED").querySelector('[data-column="ema-direction"]')).toHaveTextContent("未記録");
    expect(row("M15", "CORRECTED").querySelector('[data-column="ema-direction"]')).toHaveTextContent("不整合");
  });

  it("compares availability changes even when stored FE and EMA numbers are unchanged", () => {
    const data = fixture();
    const original = data.timeFrames[6];
    const corrected = data.detail.correction!.timeframes[6];
    original.is_fibo_expansion_available = false;
    original.is_ema200_available = false;
    for (const item of [original, corrected]) {
      item.distance_to_fe2000_pips = 0;
      item.fe1618_price = 0;
      item.ema200_shift1 = 0;
    }
    render(<M5AlertSnapshot {...data} />);
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    fireEvent.click(screen.getByRole("button", { name: "すべて表示" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "差がある列のみ" }));
    for (const column of ["distance_to_fe2000_pips", "fe1618_price", "ema200_shift1"]) {
      expect(row("M5", "CORRECTED").querySelector(`[data-column="${column}"]`)).toHaveClass("m5-alert-changed");
      expect(row("M5", "ORIGINAL").querySelector(`[data-column="${column}"]`)).toHaveClass("m5-alert-changed");
    }
    expect(row("M5", "ORIGINAL").querySelector('[data-column="distance_to_fe2000_pips"]')).toHaveTextContent("利用不可");
    expect(row("M5", "CORRECTED").querySelector('[data-column="distance_to_fe2000_pips"]')).toHaveTextContent("0.0");
    expect(row("M5", "ORIGINAL").querySelector('[data-column="ema200_shift1"]')).toHaveTextContent("未記録");
    expect(row("M5", "CORRECTED").querySelector('[data-column="ema200_shift1"]')).toHaveTextContent("0.00000");
  });

  it.each(["NONE", "UNRECORDED", "INCOMPLETE"] as const)("disables corrected comparison for %s without inferring adoption", (status) => {
    const data = fixture();
    data.detail.correction!.status = status;
    data.detail.correction!.timeframes = [];
    data.detail.correction!.points = [];
    if (status === "UNRECORDED") data.detail.correction!.metadata = null;
    render(<M5AlertSnapshot {...data} />);
    expect(screen.getByRole("button", { name: "前後比較" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "補正前" })).toBeDisabled();
    expect(row("M5", "ORIGINAL")).toHaveTextContent("▲1.i");
    expect(grid().querySelector('[data-analysis="CORRECTED"]')).toBeNull();
    if (status === "INCOMPLETE") {
      expect(screen.getByRole("status")).toHaveTextContent("採用分析を表示できません");
      expect(screen.getByRole("region", { name: "判定時の損切り候補" })).toHaveTextContent("表示不可");
    }
    if (status === "UNRECORDED") expect(screen.getByRole("status")).toHaveTextContent("採用分析は推定しません");
  });

  it("treats missing correction contract as legacy and missing metadata as incomplete", () => {
    const data = fixture();
    const { rerender } = render(<M5AlertSnapshot {...data} detail={{ ...data.detail, correction: undefined }} />);
    expect(screen.getByRole("status")).toHaveTextContent("補正情報は未記録");
    data.detail.correction!.metadata = null;
    rerender(<M5AlertSnapshot {...data} />);
    expect(screen.getByRole("status")).toHaveTextContent("補正データ不完全");
  });

  it("keeps missing original frame slots instead of borrowing corrected values", () => {
    const data = fixture();
    data.timeFrames = data.timeFrames.filter((item) => item.time_frame !== 15);
    render(<M5AlertSnapshot {...data} />);
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    expect(row("M15", "ORIGINAL")).toHaveTextContent("未記録");
    expect(row("M15", "CORRECTED")).toHaveTextContent("▲1.i");
  });

  it("shows selected full text safely, and both sets of wave points and text in comparison", () => {
    render(<M5AlertSnapshot {...fixture()} />);
    expect(screen.getByText("SELECTED FULL TEXT [5副] <img src=x>")).toBeInTheDocument();
    expect(screen.queryByText("RAW FULL TEXT [3副] <script>raw</script>")).not.toBeInTheDocument();
    expect(document.querySelector(".m5-alert-snapshot img")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    expect(screen.getByText("RAW FULL TEXT [3副] <script>raw</script>")).toBeInTheDocument();
    expect(document.querySelector(".m5-alert-snapshot script")).toBeNull();
    expect(document.querySelectorAll('.m5-alert-point-analysis table')).toHaveLength(14);
  });

  it("resets display selection for another alert", () => {
    const data = fixture();
    const { rerender } = render(<M5AlertSnapshot {...data} />);
    fireEvent.click(screen.getByRole("button", { name: "前後比較" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "差がある列のみ" }));
    const changed = { ...data.detail, alert: { ...data.detail.alert, id: 82 } };
    rerender(<M5AlertSnapshot {...data} detail={changed} />);
    expect(screen.getByRole("button", { name: "補正後（採用）" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("checkbox", { name: "差がある列のみ" })).not.toBeChecked();
  });
});
