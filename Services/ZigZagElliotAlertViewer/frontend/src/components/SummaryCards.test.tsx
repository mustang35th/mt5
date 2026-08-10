import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SummaryCards } from "./SummaryCards";

describe("SummaryCards", () => {
  it("renders database totals and result rates in one labelled compact region", () => {
    render(<SummaryCards summary={{
      total_count: 157,
      database_total_count: 451,
      buy_count: 98,
      sell_count: 59,
      w1_aligned_count: 103,
      w1_mismatched_count: 54,
      w1_unknown_count: 0,
      run_count: 3,
      symbol_count: 2,
    }} />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(summary).getByText("DB全体: LIVE＋TESTER")).toBeInTheDocument();
    expect(within(summary).getByText("検索該当 / DB全体").nextElementSibling)
      .toHaveTextContent("157/451");
    expect(within(summary).getByText("BUY件数").nextElementSibling).toHaveTextContent("98（62.4%）");
    expect(within(summary).getByText("SELL件数").nextElementSibling).toHaveTextContent("59（37.6%）");
    expect(within(summary).getByText("W1一致件数").nextElementSibling).toHaveTextContent("103（65.6%）");
    expect(within(summary).getByText("W1不一致件数").nextElementSibling).toHaveTextContent("54（34.4%）");
  });

  it("excludes unknown W1 rows from the W1 rate denominator and explains it", () => {
    render(<SummaryCards summary={{
      total_count: 10,
      database_total_count: 20,
      buy_count: 5,
      sell_count: 5,
      w1_aligned_count: 6,
      w1_mismatched_count: 2,
      w1_unknown_count: 2,
      run_count: 1,
      symbol_count: 1,
    }} />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(summary).getByText("W1一致件数").nextElementSibling).toHaveTextContent("6（75.0%）");
    expect(within(summary).getByText("W1不一致件数").nextElementSibling).toHaveTextContent("2（25.0%）");
    expect(within(summary).getByText("W1判定不明 2件は一致率の分母外")).toBeInTheDocument();
  });

  it("does not render invalid percentages for an empty result", () => {
    render(<SummaryCards summary={{
      total_count: 0,
      database_total_count: 0,
      buy_count: 0,
      sell_count: 0,
      w1_aligned_count: 0,
      w1_mismatched_count: 0,
      w1_unknown_count: 0,
      run_count: 0,
      symbol_count: 0,
    }} />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(summary).getByText("検索該当 / DB全体").nextElementSibling)
      .toHaveTextContent("0/0");
    expect(within(summary).getAllByText("（—）")).toHaveLength(4);
    expect(summary).not.toHaveTextContent(/NaN|Infinity/);
  });

  it("shows a missing database total as unknown for an older backend response", () => {
    render(<SummaryCards summary={{
      total_count: 10,
      database_total_count: undefined as unknown as number,
      buy_count: 5,
      sell_count: 5,
      w1_aligned_count: 5,
      w1_mismatched_count: 5,
      w1_unknown_count: 0,
      run_count: 1,
      symbol_count: 1,
    }} />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(summary).getByText("検索該当 / DB全体").nextElementSibling)
      .toHaveTextContent("10/—");
  });

  it("labels retained values while a new summary is loading or has failed", () => {
    const summaryValue = {
      total_count: 10,
      database_total_count: 20,
      buy_count: 5,
      sell_count: 5,
      w1_aligned_count: 5,
      w1_mismatched_count: 5,
      w1_unknown_count: 0,
      run_count: 1,
      symbol_count: 1,
    };
    const view = render(<SummaryCards summary={summaryValue} staleReason="loading" />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(summary).toHaveAttribute("aria-busy", "true");
    expect(within(summary).getByText("更新中・前回集計を表示")).toBeInTheDocument();

    view.rerender(<SummaryCards summary={summaryValue} staleReason="error" />);
    expect(summary).not.toHaveAttribute("aria-busy");
    expect(within(summary).getByText("更新失敗・前回集計を表示")).toBeInTheDocument();
  });
});
