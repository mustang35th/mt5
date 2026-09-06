import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import type { ObservationSearchState } from "../api/types";
import { DEFAULT_OBSERVATION_SEARCH_STATE } from "../lib/observationSearchState";
import {
  hasObservationUnappliedChanges,
  observationFilterSummary,
  ObservationFilterPanel,
} from "./ObservationFilterPanel";

const OPTIONS = {
  available: true,
  symbols: ["AUDUSD"],
  source_modes: ["LIVE"],
  analysis_versions: [],
  analysis_profiles: [],
};

function ObservationFilterPanelHarness() {
  const [value, setValue] = useState<ObservationSearchState>(
    DEFAULT_OBSERVATION_SEARCH_STATE,
  );
  return (
    <ObservationFilterPanel
      value={value}
      runs={[]}
      options={OPTIONS}
      busy={false}
      onChange={setValue}
      onSubmit={vi.fn()}
      onReset={() => setValue(DEFAULT_OBSERVATION_SEARCH_STATE)}
    />
  );
}

describe("ObservationFilterPanel", () => {
  it("selects analysis direction and EMA200 independently in one H1 matching field", () => {
    render(<ObservationFilterPanelHarness />);
    const matching = screen.getByRole("combobox", { name: "H1方向との一致" });
    expect(matching).toHaveTextContent("指定なし");
    fireEvent.mouseDown(matching);
    expect(screen.getByRole("option", { name: "分析方向 MN1" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "EMA200 H1" })).toBeInTheDocument();
    expect(screen.queryByRole("option", { name: "EMA200 MN1" })).not.toBeInTheDocument();
    expect(screen.queryByRole("option", { name: "分析方向 H1" })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("option", { name: "分析方向 D1" }));
    fireEvent.click(screen.getByRole("option", { name: "EMA200 H4" }));
    fireEvent.click(screen.getByRole("option", { name: "EMA200 H1" }));
    expect(matching).toHaveTextContent("分析方向 D1 / EMA200 H4・H1");
    expect(screen.getByRole("option", { name: "分析方向 H4" })).toHaveAttribute("aria-selected", "false");
    expect(screen.getByRole("option", { name: "EMA200 D1" })).toHaveAttribute("aria-selected", "false");

    fireEvent.click(screen.getByRole("option", { name: "分析方向 D1" }));
    expect(matching).toHaveTextContent("EMA200 H4・H1");
    expect(matching).not.toHaveTextContent("分析方向");
    fireEvent.click(screen.getByRole("option", { name: "指定なし" }));
    expect(matching).toHaveTextContent("指定なし");
    for (const name of ["分析方向 D1", "EMA200 H4", "EMA200 H1"]) {
      expect(screen.getByRole("option", { name })).toHaveAttribute("aria-selected", "false");
    }
  });

  it("allows EMA-only matching and resets it without changing the FULL preset", () => {
    render(<ObservationFilterPanelHarness />);
    const matching = screen.getByRole("combobox", { name: "H1方向との一致" });
    fireEvent.mouseDown(matching);
    fireEvent.click(screen.getByRole("option", { name: "EMA200 W1" }));
    expect(matching).toHaveTextContent("EMA200 W1");
    expect(screen.getByRole("option", { name: "分析方向 W1" })).toHaveAttribute("aria-selected", "false");
    fireEvent.keyDown(screen.getByRole("listbox"), { key: "Escape" });
    const fullAlignment = screen.getByRole("combobox", { name: "W1～H1＋EMA200一致" });
    expect(fullAlignment).toHaveTextContent("指定なし");
    fireEvent.mouseDown(fullAlignment);
    fireEvent.click(screen.getByRole("option", { name: "完全BUY" }));
    expect(matching).toHaveTextContent("EMA200 W1");
    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(matching).toHaveTextContent("指定なし");
    expect(fullAlignment).toHaveTextContent("指定なし");
  });

  it("summarizes both matching groups and detects only actual EMA selection changes", () => {
    const applied: ObservationSearchState = {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      syncTimeFrames: ["MN1", "D1"],
      emaSyncTimeFrames: ["W1", "H4"],
    };
    expect(observationFilterSummary(applied))
      .toContain("H1方向一致 分析方向 MN1・D1 / EMA200 W1・H4");
    expect(observationFilterSummary(DEFAULT_OBSERVATION_SEARCH_STATE))
      .toContain("H1方向一致 指定なし");
    expect(hasObservationUnappliedChanges({ ...applied, emaSyncTimeFrames: [] }, applied)).toBe(true);
    expect(hasObservationUnappliedChanges({ ...applied, emaSyncTimeFrames: ["W1", "D1"] }, applied)).toBe(true);
    expect(hasObservationUnappliedChanges({
      ...applied,
      syncTimeFrames: ["D1", "MN1"],
      emaSyncTimeFrames: ["H4", "W1"],
    }, applied)).toBe(false);
  });

  it("edits, compares, and resets the GMO target filter", () => {
    render(<ObservationFilterPanelHarness />);

    const gmoTarget = screen.getByRole("combobox", { name: "GMO取引" });
    expect(gmoTarget).toHaveTextContent("すべて");
    fireEvent.mouseDown(gmoTarget);
    fireEvent.click(screen.getByRole("option", { name: "対象外" }));
    expect(gmoTarget).toHaveTextContent("対象外");
    expect(hasObservationUnappliedChanges(
      { ...DEFAULT_OBSERVATION_SEARCH_STATE, gmoTarget: "excluded" },
      DEFAULT_OBSERVATION_SEARCH_STATE,
    )).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(gmoTarget).toHaveTextContent("すべて");
  });

  it("edits, summarizes, compares, and resets the full-alignment filter", () => {
    render(<ObservationFilterPanelHarness />);

    const fullAlignment = screen.getByRole("combobox", {
      name: "W1～H1＋EMA200一致",
    });
    expect(fullAlignment).toHaveTextContent("指定なし");
    fireEvent.mouseDown(fullAlignment);
    expect(screen.getByRole("option", { name: "方向問わず完全一致" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "完全BUY" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "完全SELL" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("option", { name: "方向問わず完全一致" }));

    expect(fullAlignment).toHaveTextContent("方向問わず完全一致");
    expect(hasObservationUnappliedChanges(
      { ...DEFAULT_OBSERVATION_SEARCH_STATE, fullAlignment: "FULL" },
      DEFAULT_OBSERVATION_SEARCH_STATE,
    )).toBe(true);
    expect(observationFilterSummary({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      fullAlignment: "FULL",
    })).toContain("W1～H1＋EMA200 方向問わず完全一致");
    expect(observationFilterSummary({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      fullAlignment: "BUY",
    })).toContain("W1～H1＋EMA200 完全BUY");
    expect(observationFilterSummary({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      fullAlignment: "SELL",
    })).toContain("W1～H1＋EMA200 完全SELL");

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(fullAlignment).toHaveTextContent("指定なし");
  });

  it("switches to consecutive signal display and enables FULL alignment", () => {
    render(<ObservationFilterPanelHarness />);

    const groupMode = screen.getByRole("combobox", { name: "表示単位" });
    const fullAlignment = screen.getByRole("combobox", {
      name: "W1～H1＋EMA200一致",
    });
    expect(groupMode).toHaveTextContent("H1ごと");
    fireEvent.mouseDown(groupMode);
    fireEvent.click(screen.getByRole("option", { name: "連続FULLを1シグナル" }));

    expect(groupMode).toHaveTextContent("連続FULLを1シグナル");
    expect(fullAlignment).toHaveTextContent("方向問わず完全一致");
    expect(hasObservationUnappliedChanges(
      {
        ...DEFAULT_OBSERVATION_SEARCH_STATE,
        groupMode: "signal",
        fullAlignment: "FULL",
      },
      DEFAULT_OBSERVATION_SEARCH_STATE,
    )).toBe(true);
    expect(observationFilterSummary({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      groupMode: "signal",
      fullAlignment: "FULL",
    })).toContain("表示 連続FULLを1シグナル");

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    expect(groupMode).toHaveTextContent("H1ごと");
    expect(fullAlignment).toHaveTextContent("指定なし");
  });
});
