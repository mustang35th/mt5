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
      "?tab=h1&sourceMode=TESTER&runId=4&analysisVersion=ELLIOT_MN1_V2&analysisInputHash=profile-hash&analysisProfileKind=profile&symbol=AUDUSD&gmoTarget=excluded&from=2026-08-01&to=2026-08-10&jstTime=07%3A00&syncTimeFrame=D1&syncTimeFrame=MN1&syncTimeFrame=MN1&fullAlignment=BUY&page=2&pageSize=25&sort=bad&order=asc",
    )).toEqual({
      sourceMode: "TESTER",
      runId: 4,
      analysisVersion: "ELLIOT_MN1_V2",
      analysisInputHash: "profile-hash",
      analysisProfileKind: "profile",
      symbol: "AUDUSD",
      gmoTarget: "excluded",
      from: "2026-08-01",
      to: "2026-08-10",
      jstTime: "07:00",
      syncTimeFrames: ["MN1", "D1"],
      fullAlignment: "BUY",
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
    expect(params.has("analysisInputHash")).toBe(false);
    expect(params.has("analysisVersion")).toBe(false);
    expect(params.has("analysisProfileKind")).toBe(false);
    expect(params.has("gmoTarget")).toBe(false);
    expect(params.has("jstTime")).toBe(false);
    expect(params.has("syncTimeFrame")).toBe(false);
    expect(params.has("fullAlignment")).toBe(false);
    expect(params.get("sort")).toBe("anchor_jst_time");
    replaceObservationSearchUrl(DEFAULT_OBSERVATION_SEARCH_STATE);
    const browserParams = new URLSearchParams(window.location.search);
    expect(browserParams.get("tab")).toBe("h1");
    expect(browserParams.get("sourceMode")).toBe("LIVE");
    expect(browserParams.get("analysisInputHash")).toBe("all");
  });

  it("restores and serializes only supported GMO target filters", () => {
    expect(readObservationSearchState("?gmoTarget=target").gmoTarget).toBe("target");
    expect(readObservationSearchState("?gmoTarget=excluded").gmoTarget).toBe("excluded");
    expect(readObservationSearchState("?gmoTarget=TARGET").gmoTarget).toBe("all");
    expect(readObservationSearchState("?gmoTarget=all").gmoTarget).toBe("all");
    const params = buildObservationSearchParams({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      gmoTarget: "excluded",
    });
    expect(params.get("gmoTarget")).toBe("excluded");
  });

  it("keeps an explicit all-profile selection only in the browser URL", () => {
    const state = readObservationSearchState("?tab=h1&analysisInputHash=all");
    expect(state.analysisInputHash).toBe("");
    expect(state.analysisVersion).toBe("");
    expect(state.analysisProfileKind).toBe("");
    expect(buildObservationSearchParams(state).has("analysisInputHash")).toBe(false);
  });

  it("normalizes the fixed JST hour and higher-timeframe synchronization filters", () => {
    const state = readObservationSearchState(
      "?jstTime=23%3A30&syncTimeFrame=h4&syncTimeFrame=bad&syncTimeFrame=w1&syncTimeFrame=H4",
    );
    expect(state.jstTime).toBe("");
    expect(state.syncTimeFrames).toEqual(["W1", "H4"]);

    const params = buildObservationSearchParams({
      ...state,
      jstTime: "23:00",
      syncTimeFrames: ["H4", "MN1", "H4"],
    });
    expect(params.get("jstTime")).toBe("23:00");
    expect(params.getAll("syncTimeFrame")).toEqual(["MN1", "H4"]);
  });

  it("restores and serializes only supported full-alignment filters", () => {
    expect(readObservationSearchState("?fullAlignment=FULL").fullAlignment).toBe("FULL");
    expect(readObservationSearchState("?fullAlignment=BUY").fullAlignment).toBe("BUY");
    expect(readObservationSearchState("?fullAlignment=SELL").fullAlignment).toBe("SELL");
    expect(readObservationSearchState("?fullAlignment=full").fullAlignment).toBe("");
    expect(readObservationSearchState("?fullAlignment=INVALID").fullAlignment).toBe("");

    const params = buildObservationSearchParams({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      fullAlignment: "FULL",
    });
    expect(params.get("fullAlignment")).toBe("FULL");
  });
});
