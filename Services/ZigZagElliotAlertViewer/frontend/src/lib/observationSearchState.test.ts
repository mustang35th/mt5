import { describe, expect, it } from "vitest";
import type { ObservationEmaSyncTimeFrame, ObservationSearchState } from "../api/types";
import {
  buildObservationSearchParams,
  DEFAULT_OBSERVATION_SEARCH_STATE,
  OBSERVATION_EMA_SYNC_TIME_FRAMES,
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
      emaSyncTimeFrames: [],
      fullAlignment: "BUY",
      groupMode: "h1",
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
    expect(params.has("emaSyncTimeFrame")).toBe(false);
    expect(params.has("fullAlignment")).toBe(false);
    expect(params.has("groupMode")).toBe(false);
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

  it("keeps EMA synchronization optional for legacy URLs and default searches", () => {
    expect(DEFAULT_OBSERVATION_SEARCH_STATE.emaSyncTimeFrames).toEqual([]);
    expect(readObservationSearchState("").emaSyncTimeFrames).toEqual([]);
    const state = readObservationSearchState(
      "?syncTimeFrame=MN1&syncTimeFrame=D1&fullAlignment=SELL&groupMode=signal",
    );
    expect(state.syncTimeFrames).toEqual(["MN1", "D1"]);
    expect(state.emaSyncTimeFrames).toEqual([]);
    expect(state.fullAlignment).toBe("SELL");
    expect(state.groupMode).toBe("signal");
    expect(buildObservationSearchParams(state).has("emaSyncTimeFrame")).toBe(false);
  });

  it("normalizes repeated EMA parameters independently from analysis-direction synchronization", () => {
    expect(OBSERVATION_EMA_SYNC_TIME_FRAMES).toEqual(["W1", "D1", "H4", "H1"]);
    const state = readObservationSearchState(
      "?syncTimeFrame=MN1&syncTimeFrame=H1&emaSyncTimeFrame=h1&emaSyncTimeFrame=%20w1%20&emaSyncTimeFrame=D1&emaSyncTimeFrame=H4&emaSyncTimeFrame=W1&emaSyncTimeFrame=MN1",
    );
    expect(state.syncTimeFrames).toEqual(["MN1"]);
    expect(state.emaSyncTimeFrames).toEqual(["W1", "D1", "H4", "H1"]);
    expect(state.fullAlignment).toBe("");
    expect(state.groupMode).toBe("h1");
    const params = buildObservationSearchParams(state);
    expect(params.getAll("syncTimeFrame")).toEqual(["MN1"]);
    expect(params.getAll("emaSyncTimeFrame")).toEqual(["W1", "D1", "H4", "H1"]);
  });

  it.each(["MN1", "M5", "M15", "M30", "W2", "", "W1,H4", "PERIOD_H4"])(
    "excludes the unsupported EMA synchronization timeframe %j",
    (timeFrame) => {
      const state = readObservationSearchState(
        `?emaSyncTimeFrame=${encodeURIComponent(timeFrame)}`,
      );
      expect(state.emaSyncTimeFrames).toEqual([]);
      expect(buildObservationSearchParams(state).has("emaSyncTimeFrame")).toBe(false);
    },
  );

  it("also normalizes EMA values on serialization without mutating either selection", () => {
    // Exercise runtime data validation as well as the compile-time timeframe union.
    const emaSyncTimeFrames = ["H1", " h4 ", "MN1", "D1", "bad", "W1", "H1"];
    const state: ObservationSearchState = {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      syncTimeFrames: ["H4", "MN1", "H4"],
      emaSyncTimeFrames: emaSyncTimeFrames as ObservationEmaSyncTimeFrame[],
    };
    const params = buildObservationSearchParams(state);
    expect(params.getAll("syncTimeFrame")).toEqual(["MN1", "H4"]);
    expect(params.getAll("emaSyncTimeFrame")).toEqual(["W1", "D1", "H4", "H1"]);
    expect(state.syncTimeFrames).toEqual(["H4", "MN1", "H4"]);
    expect(emaSyncTimeFrames).toEqual(["H1", " h4 ", "MN1", "D1", "bad", "W1", "H1"]);
  });

  it("keeps both synchronization filters in summary parameters without paging", () => {
    const state: ObservationSearchState = {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      sourceMode: "TESTER",
      runId: 4,
      syncTimeFrames: ["MN1", "D1"],
      emaSyncTimeFrames: ["W1", "H4", "H1"],
      fullAlignment: "BUY",
      groupMode: "signal",
      page: 7,
      pageSize: 100,
    };
    const listParams = buildObservationSearchParams(state);
    const summaryParams = buildObservationSearchParams(state, false);
    expect(summaryParams.getAll("syncTimeFrame")).toEqual(["MN1", "D1"]);
    expect(summaryParams.getAll("emaSyncTimeFrame")).toEqual(["W1", "H4", "H1"]);
    expect(summaryParams.get("sourceMode")).toBe("TESTER");
    expect(summaryParams.get("runId")).toBe("4");
    expect(summaryParams.get("fullAlignment")).toBe("BUY");
    expect(summaryParams.get("groupMode")).toBe("signal");
    expect(summaryParams.has("page")).toBe(false);
    expect(summaryParams.has("pageSize")).toBe(false);
    listParams.delete("page");
    listParams.delete("pageSize");
    expect(summaryParams.toString()).toBe(listParams.toString());
  });

  it("round-trips EMA selection through the browser URL without changing FULL or signal mode", () => {
    const state: ObservationSearchState = {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      syncTimeFrames: ["MN1", "D1"],
      emaSyncTimeFrames: ["W1", "H1"],
      fullAlignment: "SELL",
      groupMode: "signal",
      page: 4,
      sort: "symbol_name",
      order: "asc",
    };
    replaceObservationSearchUrl(state);
    const params = new URLSearchParams(window.location.search);
    expect(params.get("tab")).toBe("h1");
    expect(params.getAll("emaSyncTimeFrame")).toEqual(["W1", "H1"]);
    expect(params.getAll("syncTimeFrame")).toEqual(["MN1", "D1"]);
    expect(readObservationSearchState(window.location.search)).toEqual(state);
  });

  it("removes only the EMA parameters when its selection is cleared", () => {
    const state = readObservationSearchState(
      "?syncTimeFrame=MN1&emaSyncTimeFrame=W1&emaSyncTimeFrame=H1&fullAlignment=FULL&groupMode=signal",
    );
    const params = buildObservationSearchParams({ ...state, emaSyncTimeFrames: [] });
    expect(params.has("emaSyncTimeFrame")).toBe(false);
    expect(params.getAll("syncTimeFrame")).toEqual(["MN1"]);
    expect(params.get("fullAlignment")).toBe("FULL");
    expect(params.get("groupMode")).toBe("signal");
  });

  it("restores and serializes the consecutive signal display mode", () => {
    const signalState = readObservationSearchState("?groupMode=signal");
    expect(signalState.groupMode).toBe("signal");
    expect(signalState.fullAlignment).toBe("FULL");
    expect(readObservationSearchState("?groupMode=SIGNAL").groupMode).toBe("h1");
    expect(readObservationSearchState("?groupMode=invalid").groupMode).toBe("h1");

    const params = buildObservationSearchParams({
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      groupMode: "signal",
      fullAlignment: "FULL",
    });
    expect(params.get("groupMode")).toBe("signal");
    expect(params.get("fullAlignment")).toBe("FULL");
  });
});
