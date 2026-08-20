import type {
  AlertSort,
  H1DirectionAlignmentMode,
  H1DirectionAlignmentState,
  SearchState,
  SourceMode,
  ViewerTab,
  W1ConfirmationMode,
  W1ConfirmationState,
} from "../api/types";

export const DEFAULT_SEARCH_STATE: SearchState = {
  sourceMode: "LIVE",
  runId: null,
  q: "",
  symbol: "",
  gmoTarget: "all",
  timeFrames: [],
  side: "",
  rank: "",
  w1Aligned: "all",
  w1ConfirmationMode: "all",
  w1ConfirmationState: "all",
  h1DirectionAlignmentMode: "all",
  h1DirectionAlignmentState: "all",
  from: "",
  to: "",
  pageSize: 50,
  page: 1,
  sort: "jst_time",
  order: "desc",
};

const SORT_KEYS = new Set<AlertSort>([
  "jst_time",
  "symbol_name",
  "time_frame",
  "side",
  "h1_structure_rank",
  "is_w1_aligned",
  "w1_confirmation_state",
  "risk_pips",
  "entry_result",
]);

const W1_CONFIRMATION_MODES = new Set<W1ConfirmationMode>([
  "OFF",
  "OBSERVE_ONLY",
  "DIRECTION_OR_EMA200",
  "DIRECTION_AND_EMA200",
]);

const W1_CONFIRMATION_STATES = new Set<W1ConfirmationState>([
  "NOT_EVALUATED",
  "NOT_APPLICABLE",
  "OFF",
  "UNAVAILABLE",
  "INVALID",
  "STRONG",
  "DIRECTION_ONLY",
  "EMA_CONFLICT",
  "EMA_ONLY",
  "REJECT_NONE",
  "REJECT",
]);

const H1_DIRECTION_ALIGNMENT_MODES = new Set<H1DirectionAlignmentMode>([
  "D1_TO_H1",
  "MN1_TO_H1_OBSERVE",
  "MN1_TO_H1_REQUIRED",
  "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
  "INVALID",
]);

const H1_DIRECTION_ALIGNMENT_STATES = new Set<H1DirectionAlignmentState>([
  "NOT_EVALUATED",
  "NOT_APPLICABLE",
  "D1_TO_H1",
  "FULL_BUY",
  "FULL_SELL",
  "MN1_MISMATCH",
  "W1_MISMATCH",
  "MN1_W1_MISMATCH",
  "EMA200_FALLBACK_BUY",
  "EMA200_FALLBACK_SELL",
  "MN1_EMA200_MISMATCH",
  "UNAVAILABLE",
  "INVALID",
]);

function positiveInteger(value: string | null, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function dateInputValue(value: string | null): string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return "";
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    return "";
  }
  return value;
}

export function readSearchState(search: string): SearchState {
  const params = new URLSearchParams(search);
  const requestedSourceMode = params.get("sourceMode");
  const sourceMode: SourceMode = requestedSourceMode === "TESTER" || requestedSourceMode === "all"
    ? requestedSourceMode
    : "LIVE";
  const side = params.get("side");
  const alignment = params.get("w1Aligned");
  const confirmationMode = params.get("w1ConfirmationMode") as W1ConfirmationMode | null;
  const confirmationState = params.get("w1ConfirmationState") as W1ConfirmationState | null;
  const h1AlignmentMode = params.get("h1DirectionAlignmentMode") as H1DirectionAlignmentMode | null;
  const h1AlignmentState = params.get("h1DirectionAlignmentState") as H1DirectionAlignmentState | null;
  const requestedGmoTarget = params.get("gmoTarget");
  const sort = params.get("sort") as AlertSort | null;
  const requestedPageSize = positiveInteger(params.get("pageSize"), DEFAULT_SEARCH_STATE.pageSize);
  const pageSize = [25, 50, 100].includes(requestedPageSize)
    ? requestedPageSize
    : DEFAULT_SEARCH_STATE.pageSize;
  const timeFrames = [...new Set(
    params.getAll("timeFrame").map((timeFrame) => timeFrame.trim()).filter(Boolean),
  )];
  return {
    sourceMode,
    runId: params.has("runId") ? positiveInteger(params.get("runId"), 0) || null : null,
    q: params.get("q") || "",
    symbol: params.get("symbol") || "",
    gmoTarget: requestedGmoTarget === "target" || requestedGmoTarget === "excluded"
      ? requestedGmoTarget
      : "all",
    timeFrames,
    side: side === "BUY" || side === "SELL" ? side : "",
    rank: params.get("rank") || "",
    w1Aligned:
      alignment === "aligned" || alignment === "mismatched" || alignment === "unknown"
        ? alignment
        : "all",
    w1ConfirmationMode: confirmationMode && W1_CONFIRMATION_MODES.has(confirmationMode)
      ? confirmationMode
      : "all",
    w1ConfirmationState: confirmationState && W1_CONFIRMATION_STATES.has(confirmationState)
      ? confirmationState
      : "all",
    h1DirectionAlignmentMode: h1AlignmentMode && H1_DIRECTION_ALIGNMENT_MODES.has(h1AlignmentMode)
      ? h1AlignmentMode
      : "all",
    h1DirectionAlignmentState: h1AlignmentState && H1_DIRECTION_ALIGNMENT_STATES.has(h1AlignmentState)
      ? h1AlignmentState
      : "all",
    from: dateInputValue(params.get("from")),
    to: dateInputValue(params.get("to")),
    pageSize,
    page: positiveInteger(params.get("page"), DEFAULT_SEARCH_STATE.page),
    sort: sort && SORT_KEYS.has(sort) ? sort : DEFAULT_SEARCH_STATE.sort,
    order: params.get("order") === "asc" ? "asc" : "desc",
  };
}

export function readViewerTab(search: string): ViewerTab {
  return new URLSearchParams(search).get("tab") === "h1" ? "h1" : "alerts";
}

export function buildSearchParams(
  state: SearchState,
  includePaging = true,
  includeSorting = true,
): URLSearchParams {
  const params = new URLSearchParams();
  params.set("sourceMode", state.sourceMode);
  if (state.runId !== null) params.set("runId", String(state.runId));
  if (state.q.trim()) params.set("q", state.q.trim());
  if (state.symbol) params.set("symbol", state.symbol);
  if (state.gmoTarget !== "all") params.set("gmoTarget", state.gmoTarget);
  for (const timeFrame of new Set(state.timeFrames.map((value) => value.trim()).filter(Boolean))) {
    params.append("timeFrame", timeFrame);
  }
  if (state.side) params.set("side", state.side);
  if (state.rank) params.set("rank", state.rank);
  if (state.w1Aligned !== "all") params.set("w1Aligned", state.w1Aligned);
  if (state.w1ConfirmationMode !== "all") {
    params.set("w1ConfirmationMode", state.w1ConfirmationMode);
  }
  if (state.w1ConfirmationState !== "all") {
    params.set("w1ConfirmationState", state.w1ConfirmationState);
  }
  if (state.h1DirectionAlignmentMode !== "all") {
    params.set("h1DirectionAlignmentMode", state.h1DirectionAlignmentMode);
  }
  if (state.h1DirectionAlignmentState !== "all") {
    params.set("h1DirectionAlignmentState", state.h1DirectionAlignmentState);
  }
  if (state.from) params.set("from", state.from);
  if (state.to) params.set("to", state.to);
  if (includePaging) {
    params.set("page", String(state.page));
    params.set("pageSize", String(state.pageSize));
  }
  if (includeSorting) {
    params.set("sort", state.sort);
    params.set("order", state.order);
  }
  return params;
}

export function replaceSearchUrl(state: SearchState, tab: ViewerTab = "alerts"): void {
  const params = buildSearchParams(state);
  if (tab === "h1") params.set("tab", "h1");
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}
