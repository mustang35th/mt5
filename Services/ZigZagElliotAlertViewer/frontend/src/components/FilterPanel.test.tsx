import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import type { SearchState } from "../api/types";
import { DEFAULT_SEARCH_STATE } from "../lib/searchState";
import { FilterPanel } from "./FilterPanel";

const OPTIONS = {
  symbols: ["AUDUSD"],
  time_frames: ["H1", "M5", "D1"],
  strategies: ["MTF_3in3"],
  ranks: ["S"],
  entry_results: ["ENTRY"],
};

function FilterPanelHarness({
  initialValue = DEFAULT_SEARCH_STATE,
  initialAppliedValue = initialValue,
}: {
  initialValue?: SearchState;
  initialAppliedValue?: SearchState;
} = {}) {
  const [value, setValue] = useState<SearchState>(initialValue);
  const [appliedValue, setAppliedValue] = useState<SearchState>(initialAppliedValue);
  const [expanded, setExpanded] = useState(true);
  return (
    <FilterPanel
      value={value}
      appliedValue={appliedValue}
      runs={[]}
      options={OPTIONS}
      busy={false}
      expanded={expanded}
      onChange={setValue}
      onExpandedChange={setExpanded}
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
    const timeFrameSelect = screen.getByRole("combobox", { name: "時間足" });
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "H1" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "M5" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    closeButton.focus();
    fireEvent.click(closeButton);

    const openButton = screen.getByRole("button", { name: "検索条件を開く" });
    expect(openButton).toHaveFocus();
    expect(openButton).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("button", { name: "条件をリセット" })).not.toBeInTheDocument();
    expect(fields).toHaveAttribute("hidden");
    expect(fields).not.toBeVisible();
    expect(screen.getByText("LIVE / 全Run / 全通貨 / 全時間足 / BUY＋SELL")).toBeInTheDocument();
    expect(screen.getByText("未検索の変更あり")).toBeInTheDocument();

    fireEvent.click(openButton);
    expect(screen.getByRole("button", { name: "条件をリセット" })).toBeInTheDocument();
    expect(screen.getByPlaceholderText("波動ラベル、タイトル、シグナルキー"))
      .toHaveValue("wave 3");
    expect(timeFrameSelect).toHaveTextContent("H1・M5");
    fireEvent.click(screen.getByRole("button", { name: "検索" }));
    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    expect(screen.queryByText("未検索の変更あり")).not.toBeInTheDocument();
    expect(screen.getByText("LIVE / 全Run / 全通貨 / H1・M5 / BUY＋SELL / 絞り込み 1項目"))
      .toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "検索条件を開く" }));
    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(timeFrameSelect).toHaveTextContent("すべて");
  });

  it("marks all as selected and preserves an unknown URL value while editing", () => {
    const initialValue = { ...DEFAULT_SEARCH_STATE, timeFrames: ["M2"] };
    render(<FilterPanelHarness initialValue={initialValue} />);

    const timeFrameSelect = screen.getByRole("combobox", { name: "時間足" });
    expect(timeFrameSelect).toHaveTextContent("M2");
    fireEvent.mouseDown(timeFrameSelect);
    expect(screen.getByRole("option", { name: "すべて" })).toHaveAttribute("aria-selected", "false");
    expect(screen.getByRole("option", { name: "M2" })).toHaveAttribute("aria-selected", "true");

    fireEvent.click(screen.getByRole("option", { name: "H1" }));
    expect(timeFrameSelect).toHaveTextContent("M2・H1");
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    fireEvent.mouseDown(timeFrameSelect);
    expect(screen.getByRole("option", { name: "M2" })).toHaveAttribute("aria-selected", "true");

    fireEvent.click(screen.getByRole("option", { name: "すべて" }));
    expect(timeFrameSelect).toHaveTextContent("すべて");
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    fireEvent.mouseDown(timeFrameSelect);
    expect(screen.getByRole("option", { name: "すべて" })).toHaveAttribute("aria-selected", "true");
  });

  it("does not report reordered time frames as an unapplied change", () => {
    render(
      <FilterPanelHarness
        initialValue={{ ...DEFAULT_SEARCH_STATE, timeFrames: ["M5", "H1"] }}
        initialAppliedValue={{ ...DEFAULT_SEARCH_STATE, timeFrames: ["H1", "M5"] }}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    expect(screen.queryByText("未検索の変更あり")).not.toBeInTheDocument();
  });
});
