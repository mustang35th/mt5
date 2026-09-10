import { describe, expect, it } from "vitest";
import type { M5CaptureMetricsState, M5ObservationParent } from "../api/m5Types";
import { m5CaptureLag, m5CaptureSummary, m5CaptureWarnings, m5MetricLabel, m5StoredServerTime } from "./m5CaptureQuality";
import { M5_TIME_FRAMES, m5Boolean, m5DepthLabel, m5Direction, m5EmaLabel, m5FibonacciLabel, m5Number, m5TimeFrameSlots, m5WaveLabel } from "./m5TimeFrame";

const observation: M5ObservationParent = { id: 1, run_id: 1, symbol_name: "CADJPY", anchor_bar_time: 1700000100, anchor_jst_time: 1700021700 };
const state: M5CaptureMetricsState = { tableAvailable: true, rowAvailable: true, missingColumns: [] };

describe("M5 saved-value formatters", () => {
  it("does not coerce NULL, strings, or invalid flags into numeric zero or SELL", () => {
    expect(m5Number(0, 0, " ms")).toBe("0 ms");
    expect(m5Number(null)).toBe("未記録");
    expect(m5Number(Number.POSITIVE_INFINITY)).toBe("不正値");
    expect(m5Number("0")).toBe("不正値");
    expect(m5Boolean(0)).toBe(false);
    expect(m5Boolean(1)).toBe(true);
    expect(m5Boolean(2)).toBeNull();
    expect(m5Direction(null)).toBe("不明");
    expect(m5Direction("false")).toBe("不明");
  });

  it("keeps analysis and wave direction independent and EMA MN1 skipped", () => {
    const row = { time_frame: 5, is_buy: 0, is_wave_uptrend: 1, latest_elliot_label: "3", latest_sub_elliot_label: "iii" };
    expect(m5Direction(row.is_buy)).toBe("SELL");
    expect(m5WaveLabel(row)).toBe("▲3.iii");
    expect(m5EmaLabel({ time_frame: 49153, is_ema200_buy: 0, is_ema200_sell: 0 })).toBe("対象外（MN1）");
    expect(m5EmaLabel({ time_frame: 5, is_ema200_buy: 0, is_ema200_sell: 0 })).toBe("NONE");
    expect(m5EmaLabel({ time_frame: 5, is_ema200_buy: 1, is_ema200_sell: 1 })).toContain("両方向成立");
    expect(m5EmaLabel({ time_frame: 5, is_ema200_buy: null, is_ema200_sell: 0 })).toBe("未記録");
  });

  it("uses original index F/FE rule and does not present unavailable 0%", () => {
    expect(m5FibonacciLabel({ latest_point_org_elliot_index: 2, latest_point_fibonacci_percent: 38.2, latest_point_fibonacci_expansion_percent: 161.8 })).toBe("F 38.2%");
    expect(m5FibonacciLabel({ latest_point_org_elliot_index: 3, latest_point_fibonacci_percent: 38.2, latest_point_fibonacci_expansion_percent: 161.8 })).toBe("FE 161.8%");
    expect(m5FibonacciLabel({ latest_point_org_elliot_index: 2, latest_point_fibonacci_percent: 0 })).toBe("未記録");
    expect(m5FibonacciLabel({ latest_point_org_elliot_index: 1 })).toBe("対象外");
    expect(m5FibonacciLabel({ latest_point_org_elliot_index: null })).toBe("未記録");
    expect(m5DepthLabel({ latest_point_org_elliot_index: 3 })).toBe("対象外");
  });

  it("retains seven slots and warns about duplicates, wrong order, label and anchor", () => {
    const frames = M5_TIME_FRAMES.map(({ id, label }, order) => ({ time_frame: id, time_frame_text: label, time_frame_order: order, is_anchor_time_frame: id === 5 }));
    expect(m5TimeFrameSlots(frames).warnings).toEqual([]);
    const result = m5TimeFrameSlots([
      ...frames.filter((row) => row.time_frame !== 15),
      { ...frames[4], time_frame_order: 0, is_anchor_time_frame: true },
      { time_frame: 9999, time_frame_text: "BAD" },
    ]);
    expect(result.slots.map((slot) => slot.label)).toEqual(["MN1", "W1", "D1", "H4", "H1", "M15", "M5"]);
    expect(result.slots.find((slot) => slot.label === "H1")?.timeFrame).toBeNull();
    expect(result.warnings.join(" ")).toMatch(/重複/);
    expect(result.warnings.join(" ")).toMatch(/M15.*未記録/);
    expect(result.warnings.join(" ")).toMatch(/9999/);
    expect(m5TimeFrameSlots([{ ...frames[0], time_frame_order: 5, is_anchor_time_frame: true, time_frame_text: "M1" }]).warnings.join(" ")).toMatch(/保存順序.*基準足フラグ.*時間足名/);
  });
});

describe("M5 capture quality clocks and availability", () => {
  it("distinguishes absent table, absent row, absent column, NULL, and zero", () => {
    const metric = { analysis_elapsed_ms: 0 };
    expect(m5MetricLabel(metric, state, "analysis_elapsed_ms")).toBe("0 ms");
    expect(m5MetricLabel(metric, { ...state, tableAvailable: false }, "analysis_elapsed_ms")).toContain("テーブルなし");
    expect(m5MetricLabel(metric, { ...state, rowAvailable: false }, "analysis_elapsed_ms")).toContain("行なし");
    expect(m5MetricLabel(metric, { ...state, missingColumns: ["analysis_elapsed_ms"] }, "analysis_elapsed_ms")).toContain("列なし");
    expect(m5MetricLabel({ analysis_elapsed_ms: null }, state, "analysis_elapsed_ms")).toContain("NULL");
    expect(m5MetricLabel({ analysis_attempt_count: 0 }, state, "analysis_attempt_count")).toContain("不正値");
  });

  it("formats original server clocks without local timezone or inferred JST", () => {
    expect(m5StoredServerTime(1700000000001, true)).toBe("2023.11.14 22:13:20.001");
    expect(m5StoredServerTime(1700000000)).toBe("2023.11.14 22:13:20");
    expect(m5StoredServerTime(null)).toBe("未記録");
    expect(m5StoredServerTime(0)).toBe("不正値");
  });

  it("preserves zero and negative lag, flags stale quote and outside capture", () => {
    expect(m5CaptureLag(observation, { capture_market_time: observation.anchor_bar_time }, state)).toBe(0);
    const metric = { capture_market_time: observation.anchor_bar_time - 1, quote_tick_time_msc: observation.anchor_bar_time * 1000 - 1 };
    expect(m5CaptureLag(observation, metric, state)).toBe(-1);
    expect(m5CaptureSummary(observation, metric, state)).toContain("-1秒");
    expect(m5CaptureWarnings(observation, metric, state).join(" ")).toMatch(/時刻逆転.*対象足外.*過去の気配/);
    expect(m5CaptureWarnings(observation, { capture_market_time: observation.anchor_bar_time + 300 }, state)).toContain("取得市場時刻が対象足外");
    expect(m5CaptureLag(observation, null, state)).toBeNull();
  });
});
