import { beforeEach, describe, expect, it } from "vitest";
import { DEFAULT_M5_SEARCH, M5_JST_TIMES, buildM5SearchParams, latestM5Range, m5DateTime,
  readM5Search, replaceM5SearchUrl, validM5DateTime, validateM5Search } from "./m5ObservationSearchState";

describe("M5 observation search", () => {
  beforeEach(() => window.history.replaceState(null, "", "/react/"));
  it("does not inherit H1/alert Run, filters or page", () => {
    expect(readM5Search("?tab=h1&sourceMode=LIVE&runId=99&page=5&from=2026-09-08T06:00"))
      .toEqual(DEFAULT_M5_SEARCH);
  });
  it("starts TESTER, one Run selected later by metadata, 50 rows latest-first", () => {
    expect(readM5Search("?tab=m5")).toEqual(DEFAULT_M5_SEARCH);
  });
  it("accepts exactly 288 five-minute times and validates calendar dates", () => {
    expect(M5_JST_TIMES).toHaveLength(288);
    expect(M5_JST_TIMES.at(-1)).toBe("23:55");
    expect(validM5DateTime("2026-09-08T06:05")).toBe(true);
    expect(validM5DateTime("2026-09-08T06:01")).toBe(false);
    expect(validM5DateTime("2026-02-30T06:00")).toBe(false);
    expect(validM5DateTime("2026-09-08T24:00")).toBe(false);
  });
  it("uses stored JST wall time and a half-open 24h window including the last bar", () => {
    const last = Date.parse("2026-09-09T05:55:00Z") / 1000;
    expect(m5DateTime(last)).toBe("2026-09-09T05:55");
    expect(latestM5Range(last)).toEqual({ from: "2026-09-08T06:00", to: "2026-09-09T06:00" });
    expect(latestM5Range(null)).toEqual({ from: "", to: "" });
  });
  it("requires Run and a nonempty correctly ordered range", () => {
    expect(validateM5Search(DEFAULT_M5_SEARCH)).toContain("Run");
    expect(validateM5Search({ ...DEFAULT_M5_SEARCH, runId: 1 })).toContain("5分刻み");
    const base = { ...DEFAULT_M5_SEARCH, runId: 1, from: "2026-09-08T06:00", to: "2026-09-08T06:00" };
    expect(validateM5Search(base)).toContain("より後");
    expect(validateM5Search({ ...base, to: "2026-09-08T06:05" })).toBe("");
  });
  it("round-trips DB identity and fixed LIVE range while excluding UI fields from API params", () => {
    const search = { ...DEFAULT_M5_SEARCH, sourceMode: "LIVE" as const, databaseKey: "m5:new", runId: 3,
      from: "2026-09-08T06:00", to: "2026-09-09T06:00", jstTime: "12:35", pageSize: 100 as const, page: 2 };
    replaceM5SearchUrl(search);
    expect(readM5Search(window.location.search)).toEqual(search);
    const api = buildM5SearchParams(search);
    expect(api.has("databaseKey")).toBe(false);
    expect(api.has("followLatest")).toBe(false);
    expect(api.has("tab")).toBe(false);
    expect(api.get("jstTime")).toBe("12:35");
  });
  it("does not follow old pages or symbol sorting even if URL requests followLatest", () => {
    expect(readM5Search("?tab=m5&sourceMode=LIVE&followLatest=1&page=2").followLatest).toBe(false);
    expect(readM5Search("?tab=m5&sourceMode=LIVE&followLatest=1&sort=symbol_name").followLatest).toBe(false);
    expect(readM5Search("?tab=m5&sourceMode=LIVE").followLatest).toBe(true);
    expect(readM5Search("?tab=m5&sourceMode=TESTER&followLatest=1").followLatest).toBe(false);
  });
  it("rejects unsupported page sizes, sort, time and noninteger Run", () => {
    expect(readM5Search("?tab=m5&pageSize=500&sort=full&page=-3&runId=1.5&jstTime=12:01"))
      .toMatchObject({ pageSize: 50, sort: "anchor_jst_time", page: 1, runId: null, jstTime: "" });
  });
});
