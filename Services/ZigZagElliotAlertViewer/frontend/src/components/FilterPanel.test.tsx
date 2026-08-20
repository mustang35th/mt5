import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import type { SearchState } from "../api/types";
import { DEFAULT_SEARCH_STATE } from "../lib/searchState";
import { FilterPanel, hasAlertUnappliedChanges } from "./FilterPanel";

const OPTIONS = {
  symbols: ["AUDUSD"],
  time_frames: ["H1", "M5", "D1"],
  strategies: ["MTF_3in3"],
  ranks: ["S"],
  entry_results: ["ENTRY"],
};

function FilterPanelHarness({
  initialValue = DEFAULT_SEARCH_STATE,
}: {
  initialValue?: SearchState;
  } = {}) {
  const [value, setValue] = useState<SearchState>(initialValue);
  return (
    <FilterPanel
      value={value}
      runs={[]}
      options={OPTIONS}
      busy={false}
      onChange={setValue}
      onSubmit={vi.fn()}
      onReset={() => {
        setValue(DEFAULT_SEARCH_STATE);
      }}
      onExport={vi.fn()}
    />
  );
}

describe("FilterPanel", () => {
  it("retains draft values and resets all fields", () => {
    render(<FilterPanelHarness />);

    const fields = document.getElementById("reactFilterFields");
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
    expect(screen.getByPlaceholderText("波動ラベル、タイトル、シグナルキー"))
      .toHaveValue("wave 3");
    expect(timeFrameSelect).toHaveTextContent("H1・M5");
    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(timeFrameSelect).toHaveTextContent("すべて");
    expect(screen.getByRole("combobox", { name: "GMO取引" })).toHaveValue("all");
    expect(screen.getByRole("combobox", { name: "W1確認" })).toHaveValue("all");
    expect(screen.getByRole("combobox", { name: "W1確認モード" })).toHaveValue("all");
    expect(screen.getByRole("combobox", { name: "H1方向ルール状態" })).toHaveValue("all");
    expect(screen.getByRole("combobox", { name: "H1方向ルールモード" })).toHaveValue("all");
  });

  it("selects exact persisted W1 state and mode values", () => {
    render(<FilterPanelHarness />);

    const state = screen.getByRole("combobox", { name: "W1確認" });
    const mode = screen.getByRole("combobox", { name: "W1確認モード" });
    fireEvent.change(state, { target: { value: "EMA_CONFLICT" } });
    fireEvent.change(mode, { target: { value: "OBSERVE_ONLY" } });
    expect(state).toHaveValue("EMA_CONFLICT");
    expect(mode).toHaveValue("OBSERVE_ONLY");
    expect(screen.getByRole("option", { name: /EMA_CONFLICT/ })).toHaveValue("EMA_CONFLICT");
    expect(screen.getByRole("option", { name: "記録のみ（OBSERVE_ONLY）" }))
      .toHaveValue("OBSERVE_ONLY");
  });

  it("selects exact persisted H1 rule state and mode values", () => {
    render(<FilterPanelHarness />);

    const state = screen.getByRole("combobox", { name: "H1方向ルール状態" });
    const mode = screen.getByRole("combobox", { name: "H1方向ルールモード" });
    fireEvent.change(state, { target: { value: "EMA200_FALLBACK_BUY" } });
    fireEvent.change(mode, {
      target: { value: "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED" },
    });
    expect(state).toHaveValue("EMA200_FALLBACK_BUY");
    expect(mode).toHaveValue("W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED");
    expect(screen.getByRole("option", { name: /EMA200_FALLBACK_BUY/ }))
      .toHaveValue("EMA200_FALLBACK_BUY");
    expect(screen.getByRole("option", { name: /W1～H1一致＋MN1またはW1 EMA200/ }))
      .toHaveValue("W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED");
    expect(hasAlertUnappliedChanges(
      {
        ...DEFAULT_SEARCH_STATE,
        h1DirectionAlignmentState: "EMA200_FALLBACK_BUY",
        h1DirectionAlignmentMode: "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
      },
      DEFAULT_SEARCH_STATE,
    )).toBe(true);
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
    expect(hasAlertUnappliedChanges(
      { ...DEFAULT_SEARCH_STATE, timeFrames: ["M5", "H1"] },
      { ...DEFAULT_SEARCH_STATE, timeFrames: ["H1", "M5"] },
    )).toBe(false);
  });

  it("edits and compares the GMO target filter", () => {
    render(<FilterPanelHarness />);

    const gmoTarget = screen.getByRole("combobox", { name: "GMO取引" });
    fireEvent.change(gmoTarget, { target: { value: "target" } });
    expect(gmoTarget).toHaveValue("target");
    expect(hasAlertUnappliedChanges(
      { ...DEFAULT_SEARCH_STATE, gmoTarget: "target" },
      DEFAULT_SEARCH_STATE,
    )).toBe(true);
  });
});
