import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { AlertDetail } from "../api/types";
import { evaluateCurrencyStrengthSnapshot } from "../lib/currencyStrengthSnapshot";
import { CurrencyStrengthSnapshotPanel } from "./CurrencyStrengthSnapshotPanel";

function alertSnapshot(
  fromOverrides: Partial<AlertDetail> = {},
): AlertDetail {
  return {
    side: "BUY",
    is_currency_strength_enabled: true,
    currency_strength_status: 3,
    is_currency_strength_available: true,
    currency_strength_calculation_version: "weighted-v1",
    currency_strength_run_id: 42,
    currency_strength_source_mode: "LIVE",
    currency_strength_target_m5_bar_time: 1_788_192_000,
    currency_strength_m5_bar_time: 1_788_192_000,
    base_currency: "AUD",
    base_long_medium_rank: 2,
    base_medium_short_rank: 3,
    quote_currency: "USD",
    quote_long_medium_rank: 7,
    quote_medium_short_rank: 6,
    long_medium_rank_difference: 5,
    medium_short_rank_difference: 3,
    ...fromOverrides,
  } as AlertDetail;
}

describe("CurrencyStrengthSnapshotPanel", () => {
  it("shows a BUY snapshot that passed every saved Entry condition", () => {
    const alert = alertSnapshot();
    expect(evaluateCurrencyStrengthSnapshot(alert)).toMatchObject({
      entryUsage: "使用",
      judgement: "OK",
      direction: "BUY一致",
      freshness: "EXACT",
    });

    render(<CurrencyStrengthSnapshotPanel alert={alert} />);

    const panel = screen.getByRole("region", {
      name: "通貨強弱（Alert保存時点）",
    });
    expect(within(panel).getByRole("heading", {
      name: "通貨強弱（Alert保存時点）",
    })).toBeInTheDocument();
    expect(within(panel).getByText("Entry条件: 使用")).toBeInTheDocument();
    expect(within(panel).getByText("判定: OK")).toBeInTheDocument();
    expect(within(panel).getByText("BUY一致")).toHaveClass("buy");
    expect(within(panel).getByText("LIVE")).toBeInTheDocument();
    expect(within(panel).getByText("EXACT")).toBeInTheDocument();

    const longMedium = within(panel).getByRole("article", {
      name: "長中期の通貨強弱",
    });
    expect(within(longMedium).getByText("AUD 2位")).toBeInTheDocument();
    expect(within(longMedium).getByText("USD 7位")).toBeInTheDocument();
    expect(within(longMedium).getByText("差 +5")).toBeInTheDocument();
    expect(within(longMedium).getByText("BUY")).toBeInTheDocument();

    const mediumShort = within(panel).getByRole("article", {
      name: "中短期の通貨強弱",
    });
    expect(within(mediumShort).getByText("AUD 3位")).toBeInTheDocument();
    expect(within(mediumShort).getByText("USD 6位")).toBeInTheDocument();
    expect(within(mediumShort).getByText("差 +3")).toBeInTheDocument();
    expect(within(panel).getAllByText("2026.08.31 16:00")).toHaveLength(2);
    expect(within(panel).getByText("42")).toBeInTheDocument();
    expect(within(panel).getByText("weighted-v1")).toBeInTheDocument();
  });

  it("shows MIXED and NG when the two periods point in different directions", () => {
    const alert = alertSnapshot({
      medium_short_rank_difference: -3,
    });
    const snapshot = evaluateCurrencyStrengthSnapshot(alert);
    expect(snapshot.direction).toBe("MIXED");
    expect(snapshot.judgement).toBe("NG");

    render(<CurrencyStrengthSnapshotPanel alert={alert} />);

    expect(screen.getByText("MIXED")).toBeInTheDocument();
    expect(screen.getByText("判定: NG")).toBeInTheDocument();
  });

  it("shows STALE and NG when the actual M5 differs from the target", () => {
    const alert = alertSnapshot({
      currency_strength_m5_bar_time: 1_788_191_700,
    });
    const snapshot = evaluateCurrencyStrengthSnapshot(alert);
    expect(snapshot.freshness).toBe("STALE");
    expect(snapshot.judgement).toBe("NG");

    render(<CurrencyStrengthSnapshotPanel alert={alert} />);

    expect(screen.getByText("STALE")).toBeInTheDocument();
    expect(screen.getByText("判定: NG")).toBeInTheDocument();
  });

  it("keeps an enabled Legacy record unknown when M5 times were not saved", () => {
    const alert = alertSnapshot({
      currency_strength_target_m5_bar_time: undefined,
      currency_strength_m5_bar_time: undefined,
    });

    expect(evaluateCurrencyStrengthSnapshot(alert)).toMatchObject({
      entryUsage: "使用",
      judgement: "不明",
      direction: "BUY一致",
      freshness: "不明",
    });
  });

  it("does not interpret zero sentinels or unavailable data as fresh", () => {
    expect(evaluateCurrencyStrengthSnapshot(alertSnapshot({
      currency_strength_target_m5_bar_time: 0,
      currency_strength_m5_bar_time: 0,
    }))).toMatchObject({
      judgement: "不明",
      freshness: "不明",
    });

    expect(evaluateCurrencyStrengthSnapshot(alertSnapshot({
      is_currency_strength_available: false,
      currency_strength_m5_bar_time: 0,
    }))).toMatchObject({
      judgement: "NG",
      direction: "利用不可",
      freshness: "不明",
    });
  });

  it("shows the saved values as reference when the Entry filter was off", () => {
    const alert = alertSnapshot({ is_currency_strength_enabled: false });
    const snapshot = evaluateCurrencyStrengthSnapshot(alert);
    expect(snapshot.entryUsage).toBe("参考");
    expect(snapshot.judgement).toBe("参考");

    render(<CurrencyStrengthSnapshotPanel alert={alert} />);

    expect(screen.getByText("Entry条件: 参考")).toBeInTheDocument();
    expect(screen.getByText("判定: 参考")).toBeInTheDocument();
  });

  it("keeps Legacy records unknown without interpreting missing fields", () => {
    const alert = alertSnapshot({
      is_currency_strength_enabled: undefined,
      is_currency_strength_available: false,
      currency_strength_calculation_version: undefined,
      currency_strength_run_id: undefined,
      currency_strength_source_mode: undefined,
      currency_strength_target_m5_bar_time: undefined,
      currency_strength_m5_bar_time: undefined,
      base_currency: undefined,
      base_long_medium_rank: undefined,
      base_medium_short_rank: undefined,
      quote_currency: undefined,
      quote_long_medium_rank: undefined,
      quote_medium_short_rank: undefined,
    });
    const snapshot = evaluateCurrencyStrengthSnapshot(alert);
    expect(snapshot).toMatchObject({
      entryUsage: "不明",
      judgement: "不明",
      direction: "利用不可",
      freshness: "不明",
      sourceMode: "—",
    });

    render(<CurrencyStrengthSnapshotPanel alert={alert} />);

    expect(screen.getByText("Entry条件: 不明")).toBeInTheDocument();
    expect(screen.getByText("判定: 不明")).toBeInTheDocument();
    expect(screen.getAllByText("利用不可")).toHaveLength(3);
    expect(screen.getAllByText("不明")).not.toHaveLength(0);
  });
});
