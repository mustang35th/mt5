import type {
  AnalysisProfileKind,
  ObservationSearchState,
  ObservationSort,
  ObservationSyncTimeFrame,
  SourceMode,
} from "../api/types";

export const OBSERVATION_SYNC_TIME_FRAMES: readonly ObservationSyncTimeFrame[] = [
  "MN1",
  "W1",
  "D1",
  "H4",
];

export const OBSERVATION_JST_TIMES: readonly string[] = Array.from(
  { length: 24 },
  (_, hour) => `${String(hour).padStart(2, "0")}:00`,
);

export const DEFAULT_OBSERVATION_SEARCH_STATE: ObservationSearchState = {
  sourceMode: "LIVE",
  runId: null,
  analysisVersion: "",
  analysisInputHash: "",
  analysisProfileKind: "",
  symbol: "",
  gmoTarget: "all",
  from: "",
  to: "",
  jstTime: "",
  syncTimeFrames: [],
  pageSize: 50,
  page: 1,
  sort: "anchor_jst_time",
  order: "desc",
};

const SORT_KEYS = new Set<ObservationSort>(["anchor_jst_time", "symbol_name"]);

function observationSort(value: string | null): ObservationSort {
  if (value === "anchor_bar_time") return "anchor_jst_time";
  if (value !== null && SORT_KEYS.has(value as ObservationSort)) {
    return value as ObservationSort;
  }
  return DEFAULT_OBSERVATION_SEARCH_STATE.sort;
}

function positiveInteger(value: string | null, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function dateInputValue(value: string | null): string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return "";
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) return "";
  return value;
}

function timeInputValue(value: string | null): string {
  if (!value || !OBSERVATION_JST_TIMES.includes(value)) return "";
  return value;
}

function observationSyncTimeFrames(values: string[]): ObservationSyncTimeFrame[] {
  const requestedValues = new Set(values.map((value) => value.trim().toUpperCase()));
  return OBSERVATION_SYNC_TIME_FRAMES.filter((timeFrame) => requestedValues.has(timeFrame));
}

export function readObservationSearchState(search: string): ObservationSearchState {
  const params = new URLSearchParams(search);
  const requestedSourceMode = params.get("sourceMode");
  const sourceMode: SourceMode = requestedSourceMode === "TESTER" || requestedSourceMode === "all"
    ? requestedSourceMode
    : "LIVE";
  const requestedPageSize = positiveInteger(
    params.get("pageSize"),
    DEFAULT_OBSERVATION_SEARCH_STATE.pageSize,
  );
  const requestedProfileKind = params.get("analysisProfileKind");
  const requestedGmoTarget = params.get("gmoTarget");
  const analysisProfileKind: "" | AnalysisProfileKind = requestedProfileKind === "profile"
    || requestedProfileKind === "legacy"
    ? requestedProfileKind
    : "";
  return {
    sourceMode,
    runId: params.has("runId") ? positiveInteger(params.get("runId"), 0) || null : null,
    analysisVersion: params.get("analysisVersion") || "",
    analysisInputHash: params.get("analysisInputHash") === "all"
      ? ""
      : params.get("analysisInputHash") || "",
    analysisProfileKind,
    symbol: params.get("symbol") || "",
    gmoTarget: requestedGmoTarget === "target" || requestedGmoTarget === "excluded"
      ? requestedGmoTarget
      : "all",
    from: dateInputValue(params.get("from")),
    to: dateInputValue(params.get("to")),
    jstTime: timeInputValue(params.get("jstTime")),
    syncTimeFrames: observationSyncTimeFrames(params.getAll("syncTimeFrame")),
    pageSize: [25, 50, 100].includes(requestedPageSize)
      ? requestedPageSize
      : DEFAULT_OBSERVATION_SEARCH_STATE.pageSize,
    page: positiveInteger(params.get("page"), DEFAULT_OBSERVATION_SEARCH_STATE.page),
    sort: observationSort(params.get("sort")),
    order: params.get("order") === "asc" ? "asc" : "desc",
  };
}

export function buildObservationSearchParams(
  state: ObservationSearchState,
  includePaging = true,
): URLSearchParams {
  const params = new URLSearchParams();
  params.set("sourceMode", state.sourceMode);
  if (state.runId !== null) params.set("runId", String(state.runId));
  if (state.analysisInputHash) {
    if (state.analysisVersion) params.set("analysisVersion", state.analysisVersion);
    params.set("analysisInputHash", state.analysisInputHash);
    if (state.analysisProfileKind) {
      params.set("analysisProfileKind", state.analysisProfileKind);
    }
  }
  if (state.symbol) params.set("symbol", state.symbol);
  if (state.gmoTarget !== "all") params.set("gmoTarget", state.gmoTarget);
  if (state.from) params.set("from", state.from);
  if (state.to) params.set("to", state.to);
  const jstTime = timeInputValue(state.jstTime);
  if (jstTime) params.set("jstTime", jstTime);
  for (const timeFrame of observationSyncTimeFrames(state.syncTimeFrames)) {
    params.append("syncTimeFrame", timeFrame);
  }
  if (includePaging) {
    params.set("page", String(state.page));
    params.set("pageSize", String(state.pageSize));
  }
  params.set("sort", state.sort);
  params.set("order", state.order);
  return params;
}

export function replaceObservationSearchUrl(state: ObservationSearchState): void {
  const params = buildObservationSearchParams(state);
  if (!state.analysisInputHash) params.set("analysisInputHash", "all");
  params.set("tab", "h1");
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}
