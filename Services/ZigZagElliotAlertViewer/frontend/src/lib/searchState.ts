import type { AlertSort, SearchState } from "../api/types";

export const DEFAULT_SEARCH_STATE: SearchState = {
  runId: null,
  q: "",
  symbol: "",
  side: "",
  rank: "",
  w1Aligned: "all",
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
  "side",
  "h1_structure_rank",
  "is_w1_aligned",
  "risk_pips",
  "entry_result",
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
  const side = params.get("side");
  const alignment = params.get("w1Aligned");
  const sort = params.get("sort") as AlertSort | null;
  const requestedPageSize = positiveInteger(params.get("pageSize"), DEFAULT_SEARCH_STATE.pageSize);
  const pageSize = [25, 50, 100].includes(requestedPageSize)
    ? requestedPageSize
    : DEFAULT_SEARCH_STATE.pageSize;
  return {
    runId: params.has("runId") ? positiveInteger(params.get("runId"), 0) || null : null,
    q: params.get("q") || "",
    symbol: params.get("symbol") || "",
    side: side === "BUY" || side === "SELL" ? side : "",
    rank: params.get("rank") || "",
    w1Aligned:
      alignment === "aligned" || alignment === "mismatched" || alignment === "unknown"
        ? alignment
        : "all",
    from: dateInputValue(params.get("from")),
    to: dateInputValue(params.get("to")),
    pageSize,
    page: positiveInteger(params.get("page"), DEFAULT_SEARCH_STATE.page),
    sort: sort && SORT_KEYS.has(sort) ? sort : DEFAULT_SEARCH_STATE.sort,
    order: params.get("order") === "asc" ? "asc" : "desc",
  };
}

export function buildSearchParams(
  state: SearchState,
  includePaging = true,
  includeSorting = true,
): URLSearchParams {
  const params = new URLSearchParams();
  if (state.runId !== null) params.set("runId", String(state.runId));
  if (state.q.trim()) params.set("q", state.q.trim());
  if (state.symbol) params.set("symbol", state.symbol);
  if (state.side) params.set("side", state.side);
  if (state.rank) params.set("rank", state.rank);
  if (state.w1Aligned !== "all") params.set("w1Aligned", state.w1Aligned);
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

export function replaceSearchUrl(state: SearchState): void {
  const params = buildSearchParams(state);
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}
