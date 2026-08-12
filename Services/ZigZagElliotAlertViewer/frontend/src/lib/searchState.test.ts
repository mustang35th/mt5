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
    const state = readSearchState("?sourceMode=TESTER&runId=3&gmoTarget=target&timeFrame=H1&side=BUY&w1Aligned=unknown&page=2&pageSize=25&sort=bad&order=asc");
    expect(state).toMatchObject({
      sourceMode: "TESTER",
      runId: 3,
      gmoTarget: "target",
      timeFrames: ["H1"],
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
    expect(params.has("timeFrame")).toBe(false);
    expect(params.has("gmoTarget")).toBe(false);
    expect(params.has("w1Aligned")).toBe(false);
    expect(params.get("page")).toBe("1");
    expect(params.get("sort")).toBe("jst_time");
  });

  it("restores and serializes only supported GMO target filters", () => {
    expect(readSearchState("?gmoTarget=target").gmoTarget).toBe("target");
    expect(readSearchState("?gmoTarget=excluded").gmoTarget).toBe("excluded");
    expect(readSearchState("?gmoTarget=TARGET").gmoTarget).toBe("all");
    expect(readSearchState("?gmoTarget=all").gmoTarget).toBe("all");
    expect(buildSearchParams({ ...DEFAULT_SEARCH_STATE, gmoTarget: "target" }).get("gmoTarget"))
      .toBe("target");
    expect(buildSearchParams({ ...DEFAULT_SEARCH_STATE, gmoTarget: "excluded" }).get("gmoTarget"))
      .toBe("excluded");
  });

  it("restores legacy and repeated alert time frame filters", () => {
    expect(readSearchState("?timeFrame=H1").timeFrames).toEqual(["H1"]);

    const state = readSearchState("?timeFrame=M5&timeFrame=H1&timeFrame=M5");
    expect(state.timeFrames).toEqual(["M5", "H1"]);
    const params = buildSearchParams(state);
    expect(params.getAll("timeFrame")).toEqual(["M5", "H1"]);
    const exportParams = buildSearchParams(state, false, true);
    expect(exportParams.getAll("timeFrame")).toEqual(["M5", "H1"]);
    expect(exportParams.has("page")).toBe(false);
    expect(exportParams.has("pageSize")).toBe(false);
  });

  it("restores and serializes time frame sorting", () => {
    const state = readSearchState("?sort=time_frame&order=asc");
    expect(state.sort).toBe("time_frame");
    expect(state.order).toBe("asc");
    const params = buildSearchParams(state);
    expect(params.get("sort")).toBe("time_frame");
    expect(params.get("order")).toBe("asc");
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
