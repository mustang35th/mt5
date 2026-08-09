import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import type { SearchState } from "../api/types";
import { DEFAULT_SEARCH_STATE } from "../lib/searchState";
import { FilterPanel } from "./FilterPanel";

const OPTIONS = {
  symbols: ["AUDUSD"],
  time_frames: ["H1"],
  strategies: ["MTF_3in3"],
  ranks: ["S"],
  entry_results: ["ENTRY"],
};

function FilterPanelHarness() {
  const [value, setValue] = useState<SearchState>(DEFAULT_SEARCH_STATE);
  const [appliedValue, setAppliedValue] = useState<SearchState>(DEFAULT_SEARCH_STATE);
  return (
    <FilterPanel
      value={value}
      appliedValue={appliedValue}
      runs={[]}
      options={OPTIONS}
      busy={false}
      onChange={setValue}
      onSubmit={() => setAppliedValue(value)}
      onReset={() => {
        setValue(DEFAULT_SEARCH_STATE);
        setAppliedValue(DEFAULT_SEARCH_STATE);
      }}
      onExport={vi.fn()}
    />
  );
}

describe("FilterPanel", () => {
  it("collapses accessibly while retaining draft values and showing unapplied changes", () => {
    render(<FilterPanelHarness />);

    const closeButton = screen.getByRole("button", { name: "検索条件を閉じる" });
    const fields = document.getElementById("reactFilterFields");
    expect(closeButton).toHaveAttribute("aria-expanded", "true");
    expect(closeButton).toHaveAttribute("aria-controls", "reactFilterFields");
    expect(fields).not.toHaveAttribute("hidden");

    const keyword = screen.getByPlaceholderText("波動ラベル、タイトル、シグナルキー");
    fireEvent.change(keyword, { target: { value: "wave 3" } });
    fireEvent.click(closeButton);

    const openButton = screen.getByRole("button", { name: "検索条件を開く" });
    expect(openButton).toHaveAttribute("aria-expanded", "false");
    expect(fields).toHaveAttribute("hidden");
    expect(fields).not.toBeVisible();
    expect(screen.getByText("LIVE / 全Run / 全通貨 / BUY＋SELL")).toBeInTheDocument();
    expect(screen.getByText("未検索の変更あり")).toBeInTheDocument();

    fireEvent.click(openButton);
    expect(screen.getByPlaceholderText("波動ラベル、タイトル、シグナルキー"))
      .toHaveValue("wave 3");
    fireEvent.click(screen.getByRole("button", { name: "検索する" }));
    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    expect(screen.queryByText("未検索の変更あり")).not.toBeInTheDocument();
    expect(screen.getByText("LIVE / 全Run / 全通貨 / BUY＋SELL / 絞り込み 1項目"))
      .toBeInTheDocument();
  });
});
