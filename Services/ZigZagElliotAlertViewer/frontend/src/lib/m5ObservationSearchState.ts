import { M5_DISPLAY_INTERVAL_KEY, readM5Preference } from "./m5ObservationPreferences";
import type { M5DisplayInterval, M5SearchState } from "../api/m5Types";

export const DEFAULT_M5_SEARCH: M5SearchState = {
  sourceMode: "TESTER", runId: null, databaseKey: "", symbol: "", from: "", to: "", jstTime: "",
  displayInterval: 5, page: 1, pageSize: 50, sort: "anchor_jst_time", order: "desc", followLatest: false,
};
export const M5_JST_TIMES = Array.from({ length: 288 }, (_, index) =>
  `${String(Math.floor(index / 12)).padStart(2, "0")}:${String(index % 12 * 5).padStart(2, "0")}`);

export const M5_DISPLAY_INTERVALS = [
  { value: 5, label: "M5", text: "M5（5分）" },
  { value: 15, label: "M15", text: "M15（15分）" },
  { value: 60, label: "H1", text: "H1（1時間）" },
  { value: 240, label: "H4", text: "H4（4時間）" },
  { value: 1440, label: "D1", text: "D1（1日）" },
] as const;
export function m5DisplayIntervalLabel(value: M5DisplayInterval): string {
  return M5_DISPLAY_INTERVALS.find((interval) => interval.value === value)!.label;
}
export function validM5DisplayInterval(value: unknown): value is M5DisplayInterval {
  return M5_DISPLAY_INTERVALS.some((interval) => interval.value === value);
}
export function m5JstTimes(displayInterval: M5DisplayInterval): string[] {
  return M5_JST_TIMES.filter((time) => Number(time.slice(-2)) % displayInterval === 0);
}

/** Stored JST epochs are wall-clock values: UTC methods avoid browser timezone conversion. */
export function m5DateTime(epoch: number | null | undefined): string {
  if (epoch === null || epoch === undefined || !Number.isFinite(epoch) || epoch <= 0) return "";
  const date = new Date(epoch * 1000);
  return Number.isNaN(date.getTime()) ? "" : date.toISOString().slice(0, 16);
}
export function validM5DateTime(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return false;
  const parsed = Date.parse(`${value}:00Z`);
  return Number.isFinite(parsed) && new Date(parsed).toISOString().slice(0, 16) === value
    && Number(value.slice(-2)) % 5 === 0;
}
export function latestM5Range(last: number | null | undefined): { from: string; to: string } {
  if (last === null || last === undefined || !Number.isFinite(last) || last <= 0) return { from: "", to: "" };
  return { from: m5DateTime(last + 300 - 86400), to: m5DateTime(last + 300) };
}
export function validateM5Search(search: M5SearchState): string {
  if (search.runId === null) return "Runを選択してください。";
  if (!validM5DateTime(search.from) || !validM5DateTime(search.to)) return "開始・終了JSTを5分刻みで入力してください。";
  if (search.from >= search.to) return "終了JSTは開始JSTより後にしてください（終了は含まない）。";
  if (search.jstTime && !M5_JST_TIMES.includes(search.jstTime)) return "JST時刻は5分刻みで入力してください。";
  if (!validM5DisplayInterval(search.displayInterval)) return "表示間隔はM5・M15・H1・H4・D1から選択してください。";
  if (search.jstTime && !m5JstTimes(search.displayInterval).includes(search.jstTime)) return "JST時刻を表示間隔に合わせて選択してください。";
  return "";
}
function positive(value: string | null, fallback: number): number {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}
export function readM5Search(search: string): M5SearchState {
  const params = new URLSearchParams(search);
  const storedInterval = readM5Preference(M5_DISPLAY_INTERVAL_KEY, 5, validM5DisplayInterval);
  if (params.get("tab") !== "m5") return { ...DEFAULT_M5_SEARCH, displayInterval: storedInterval };
  const requestedInterval = Number(params.get("displayInterval"));
  const displayInterval = params.has("displayInterval")
    ? (validM5DisplayInterval(requestedInterval) ? requestedInterval : 5) : storedInterval;
  const pageSize = positive(params.get("pageSize"), 50);
  const from = params.get("from") || "";
  const to = params.get("to") || "";
  const sourceMode = params.get("sourceMode") === "LIVE" ? "LIVE" : "TESTER";
  const sort = params.get("sort") === "symbol_name" ? "symbol_name" : "anchor_jst_time";
  const order = params.get("order") === "asc" ? "asc" : "desc";
  const page = positive(params.get("page"), 1);
  return {
    ...DEFAULT_M5_SEARCH, sourceMode, sort, order, page, displayInterval,
    runId: positive(params.get("runId"), 0) || null,
    databaseKey: params.get("databaseKey") || "",
    symbol: params.get("symbol") || "",
    from: validM5DateTime(from) ? from : "", to: validM5DateTime(to) ? to : "",
    jstTime: m5JstTimes(displayInterval).includes(params.get("jstTime") || "") ? params.get("jstTime")! : "",
    pageSize: pageSize === 100 || pageSize === 200 ? pageSize : 50,
    followLatest: sourceMode === "LIVE" && sort === "anchor_jst_time" && order === "desc" && page === 1
      && (params.get("followLatest") === "1" || (!from && !to)),
  };
}
export function buildM5SearchParams(search: M5SearchState): URLSearchParams {
  const params = new URLSearchParams({ sourceMode: search.sourceMode, from: search.from, to: search.to,
    displayInterval: String(search.displayInterval), page: String(search.page), pageSize: String(search.pageSize), sort: search.sort, order: search.order });
  if (search.runId !== null) params.set("runId", String(search.runId));
  if (search.symbol) params.set("symbol", search.symbol);
  if (search.jstTime) params.set("jstTime", search.jstTime);
  return params;
}
export function replaceM5SearchUrl(search: M5SearchState): void {
  const params = buildM5SearchParams(search);
  params.set("tab", "m5");
  if (search.databaseKey) params.set("databaseKey", search.databaseKey);
  params.set("followLatest", search.followLatest ? "1" : "0");
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}
