import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { M5CurrencyStrength } from "../api/m5Types";
import { M5CurrencyStrengthPanel } from "./M5CurrencyStrengthPanel";

afterEach(cleanup);
function snapshot(): M5CurrencyStrength {
  return { status: "FOUND", databaseName: "mstng-currency-strength-2026.sqlite", calculationMode: "UNIFORM",
    calculationVersion: "pair-direction-closed-v1", targetM5BarTime: 1700000100, actualM5BarTime: 1700000100,
    runId: 42, sourceMode: "TESTER", baseCurrency: "EUR", quoteCurrency: "JPY", periods: [
      { label: "長中期", baseRank: 2, quoteRank: 7, rankDifference: 5, direction: "BUY" },
      { label: "中短期", baseRank: 1, quoteRank: 6, rankDifference: 5, direction: "BUY" },
    ] };
}
describe("M5 currency strength reference", () => {
  it("shows signed differences and BUY alignment without an Entry verdict", () => {
    render(<M5CurrencyStrengthPanel snapshot={snapshot()} direction="BUY" />);
    expect(screen.getByText("M5方向と一致")).toHaveClass("buy");
    expect(screen.getAllByText("+5")).toHaveLength(2);
    expect(screen.getByRole("heading")).toHaveAttribute("title", expect.stringContaining("\n長中期"));
    expect(screen.queryByText(/Entry条件|エントリーOK/)).not.toBeInTheDocument();
    expect(screen.getByText(/参照元：mstng-currency-strength-2026.sqlite/)).toBeInTheDocument();
  });
  it("distinguishes SELL, mixed and tied ranks", () => {
    const value = snapshot();
    value.periods[0] = { label: "長中期", baseRank: 7, quoteRank: 2, rankDifference: -5, direction: "SELL" };
    const { rerender } = render(<M5CurrencyStrengthPanel snapshot={value} direction="BUY" />);
    expect(screen.getByText("混在")).toBeInTheDocument();
    expect(screen.getByText("-5")).toHaveClass("sell");
    value.periods[1] = { ...value.periods[0], label: "中短期" };
    rerender(<M5CurrencyStrengthPanel snapshot={value} direction="BUY" />);
    expect(screen.getByText("M5方向と逆")).toHaveClass("sell");
    value.periods = value.periods.map((period) => ({ ...period, baseRank: 2, quoteRank: 2, rankDifference: 0, direction: "TIE" }));
    rerender(<M5CurrencyStrengthPanel snapshot={value} direction="BUY" />);
    expect(within(screen.getByRole("table")).getAllByText("同順位")).toHaveLength(2);
    expect(screen.queryByText("+0")).not.toBeInTheDocument();
  });
  it("clears previous ranks when navigation yields no matching record", () => {
    const value = snapshot();
    const { rerender } = render(<M5CurrencyStrengthPanel snapshot={value} direction="BUY" />);
    rerender(<M5CurrencyStrengthPanel snapshot={{ ...value, status: "RECORD_NOT_FOUND", periods: [] }} direction="BUY" />);
    expect(screen.getByText("該当なし")).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
    expect(screen.queryByText("M5方向と一致")).not.toBeInTheDocument();
  });
  it("supports unavailable references and old API responses", () => {
    const { rerender } = render(<M5CurrencyStrengthPanel direction="不明" />);
    expect(screen.getByText("未取得")).toBeInTheDocument();
    rerender(<M5CurrencyStrengthPanel snapshot={{ ...snapshot(), status: "ERROR", periods: [] }} direction="BUY" />);
    expect(screen.getByText("通貨強弱の取得失敗")).toBeInTheDocument();
  });
});
