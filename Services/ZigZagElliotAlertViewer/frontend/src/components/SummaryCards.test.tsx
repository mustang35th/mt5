import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SummaryCards } from "./SummaryCards";

describe("SummaryCards", () => {
  it("renders every result count in one labelled compact region", () => {
    render(<SummaryCards summary={{
      total_count: 157,
      buy_count: 98,
      sell_count: 59,
      w1_aligned_count: 103,
      w1_mismatched_count: 54,
      w1_unknown_count: 0,
      run_count: 3,
      symbol_count: 2,
    }} />);

    const summary = screen.getByRole("region", { name: "検索結果集計" });
    expect(within(summary).getByText("総件数").nextElementSibling).toHaveTextContent("157");
    expect(within(summary).getByText("BUY").nextElementSibling).toHaveTextContent("98");
    expect(within(summary).getByText("SELL").nextElementSibling).toHaveTextContent("59");
    expect(within(summary).getByText("W1一致").nextElementSibling).toHaveTextContent("103");
    expect(within(summary).getByText("W1不一致").nextElementSibling).toHaveTextContent("54");
  });
});
