import type {
  ObservationSearchState,
  ObservationSort,
  SourceMode,
} from "../api/types";

export const DEFAULT_OBSERVATION_SEARCH_STATE: ObservationSearchState = {
  sourceMode: "LIVE",
  runId: null,
  symbol: "",
  from: "",
  to: "",
  pageSize: 50,
  page: 1,
  sort: "anchor_bar_time",
  order: "desc",
};

const SORT_KEYS = new Set<ObservationSort>(["anchor_bar_time", "symbol_name"]);

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
  const sort = params.get("sort") as ObservationSort | null;
  return {
    sourceMode,
    runId: params.has("runId") ? positiveInteger(params.get("runId"), 0) || null : null,
    symbol: params.get("symbol") || "",
    from: dateInputValue(params.get("from")),
    to: dateInputValue(params.get("to")),
    pageSize: [25, 50, 100].includes(requestedPageSize)
      ? requestedPageSize
      : DEFAULT_OBSERVATION_SEARCH_STATE.pageSize,
    page: positiveInteger(params.get("page"), DEFAULT_OBSERVATION_SEARCH_STATE.page),
    sort: sort && SORT_KEYS.has(sort) ? sort : DEFAULT_OBSERVATION_SEARCH_STATE.sort,
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
  if (state.symbol) params.set("symbol", state.symbol);
  if (state.from) params.set("from", state.from);
  if (state.to) params.set("to", state.to);
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
  params.set("tab", "h1");
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}
