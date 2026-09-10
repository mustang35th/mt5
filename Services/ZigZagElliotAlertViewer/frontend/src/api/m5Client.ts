import type { M5DetailResponse, M5ListResponse, M5Metadata, M5SearchState, M5SourceMode } from "./m5Types";
import { buildM5SearchParams } from "../lib/m5ObservationSearchState";

export class M5ApiError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}
async function getJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(path, { headers: { Accept: "application/json" }, signal });
  let payload: unknown;
  try { payload = await response.json(); } catch { throw new M5ApiError(`HTTP ${response.status}`, response.status); }
  if (!response.ok) {
    const error = payload as { error?: string; detail?: string };
    throw new M5ApiError(error.error || error.detail || `HTTP ${response.status}`, response.status);
  }
  return payload as T;
}
export const m5Api = {
  metadata(sourceMode: M5SourceMode = "TESTER", runId: number | null = null, signal?: AbortSignal): Promise<M5Metadata> {
    const params = new URLSearchParams({ sourceMode });
    if (runId !== null) params.set("runId", String(runId));
    return getJson(`/api/m5/metadata?${params}`, signal);
  },
  observations(search: M5SearchState, signal?: AbortSignal): Promise<M5ListResponse> {
    return getJson(`/api/m5/observations?${buildM5SearchParams(search)}`, signal);
  },
  detail(id: number, databaseKey: string, signal?: AbortSignal): Promise<M5DetailResponse> {
    return getJson(`/api/m5/observations/${id}?${new URLSearchParams({ databaseKey })}`, signal);
  },
};
