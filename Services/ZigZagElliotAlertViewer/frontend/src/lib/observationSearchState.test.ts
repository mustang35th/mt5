import { describe, expect, it } from "vitest";
import {
  buildObservationSearchParams,
  DEFAULT_OBSERVATION_SEARCH_STATE,
  readObservationSearchState,
  replaceObservationSearchUrl,
} from "./observationSearchState";

describe("observationSearchState", () => {
  it("restores the H1 observation filters and rejects unsupported values", () => {
    expect(readObservationSearchState(
      "?tab=h1&sourceMode=TESTER&runId=4&symbol=AUDUSD&from=2026-08-01&to=2026-08-10&page=2&pageSize=25&sort=bad&order=asc",
    )).toEqual({
      sourceMode: "TESTER",
      runId: 4,
      symbol: "AUDUSD",
      from: "2026-08-01",
      to: "2026-08-10",
      page: 2,
      pageSize: 25,
      sort: "anchor_jst_time",
      order: "asc",
    });
  });

  it("normalizes the legacy Server-time sort to the JST sort", () => {
    const state = readObservationSearchState("?tab=h1&sort=anchor_bar_time&order=asc");
    expect(state.sort).toBe("anchor_jst_time");
    expect(buildObservationSearchParams(state).get("sort")).toBe("anchor_jst_time");
  });

  it("builds API parameters without the UI tab and keeps the tab in the browser URL", () => {
    const params = buildObservationSearchParams(DEFAULT_OBSERVATION_SEARCH_STATE);
    expect(params.has("tab")).toBe(false);
    expect(params.get("sort")).toBe("anchor_jst_time");
    replaceObservationSearchUrl(DEFAULT_OBSERVATION_SEARCH_STATE);
    const browserParams = new URLSearchParams(window.location.search);
    expect(browserParams.get("tab")).toBe("h1");
    expect(browserParams.get("sourceMode")).toBe("LIVE");
  });
});
