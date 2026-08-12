import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import type { ObservationSearchState } from "../api/types";
import { DEFAULT_OBSERVATION_SEARCH_STATE } from "../lib/observationSearchState";
import {
  hasObservationUnappliedChanges,
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
});
