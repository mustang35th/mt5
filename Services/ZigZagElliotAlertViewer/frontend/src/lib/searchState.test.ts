import { describe, expect, it } from "vitest";
import {
  buildSearchParams,
  DEFAULT_SEARCH_STATE,
  readSearchState,
  readViewerTab,
  replaceSearchUrl,
} from "./searchState";

describe("searchState", () => {
  it("restores valid URL values and rejects unsupported sorting", () => {
    const state = readSearchState("?sourceMode=TESTER&runId=3&side=BUY&w1Aligned=unknown&page=2&pageSize=25&sort=bad&order=asc");
    expect(state).toMatchObject({
      sourceMode: "TESTER",
      runId: 3,
      side: "BUY",
      w1Aligned: "unknown",
      page: 2,
      pageSize: 25,
      sort: "jst_time",
      order: "asc",
    });
  });

  it("includes the source mode and omits empty and all-alignment values", () => {
    const params = buildSearchParams(DEFAULT_SEARCH_STATE);
    expect(params.get("sourceMode")).toBe("LIVE");
    expect(params.has("runId")).toBe(false);
    expect(params.has("w1Aligned")).toBe(false);
    expect(params.get("page")).toBe("1");
    expect(params.get("sort")).toBe("jst_time");
  });

  it("falls back when the requested page size is not offered by the UI", () => {
    expect(readSearchState("?pageSize=999").pageSize).toBe(50);
  });

  it("uses LIVE when the source mode is missing or unsupported", () => {
    expect(readSearchState("?runId=3").sourceMode).toBe("LIVE");
    expect(readSearchState("?sourceMode=UNKNOWN").sourceMode).toBe("LIVE");
    expect(buildSearchParams({ ...DEFAULT_SEARCH_STATE, sourceMode: "all" }).get("sourceMode")).toBe("all");
  });

  it("drops URL dates that a date input cannot display", () => {
    const state = readSearchState("?from=2026-02-30&to=2026-08-09T12%3A00");
    expect(state.from).toBe("");
    expect(state.to).toBe("");
  });

  it("uses the alert tab by default and preserves an explicit H1 tab", () => {
    expect(readViewerTab("?sourceMode=LIVE")).toBe("alerts");
    expect(readViewerTab("?tab=h1&sourceMode=LIVE")).toBe("h1");
    window.history.replaceState(null, "", "/?tab=h1");
    replaceSearchUrl(DEFAULT_SEARCH_STATE, "h1");
    expect(new URLSearchParams(window.location.search).get("tab")).toBe("h1");
  });
});
