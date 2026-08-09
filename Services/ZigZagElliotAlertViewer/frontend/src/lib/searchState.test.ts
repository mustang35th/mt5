import { describe, expect, it } from "vitest";
import { buildSearchParams, DEFAULT_SEARCH_STATE, readSearchState } from "./searchState";

describe("searchState", () => {
  it("restores valid URL values and rejects unsupported sorting", () => {
    const state = readSearchState("?runId=3&side=BUY&w1Aligned=unknown&page=2&pageSize=25&sort=bad&order=asc");
    expect(state).toMatchObject({
      runId: 3,
      side: "BUY",
      w1Aligned: "unknown",
      page: 2,
      pageSize: 25,
      sort: "jst_time",
      order: "asc",
    });
  });

  it("omits empty and all-alignment values", () => {
    const params = buildSearchParams(DEFAULT_SEARCH_STATE);
    expect(params.has("runId")).toBe(false);
    expect(params.has("w1Aligned")).toBe(false);
    expect(params.get("page")).toBe("1");
    expect(params.get("sort")).toBe("jst_time");
  });

  it("falls back when the requested page size is not offered by the UI", () => {
    expect(readSearchState("?pageSize=999").pageSize).toBe(50);
  });

  it("drops URL dates that a date input cannot display", () => {
    const state = readSearchState("?from=2026-02-30&to=2026-08-09T12%3A00");
    expect(state.from).toBe("");
    expect(state.to).toBe("");
  });
});
