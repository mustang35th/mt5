import type { EaMetadata, EaSamplesResponse, EaSessionsResponse, EaSummary, EaTradeDetail, EaTradeSearch, EaTradesResponse } from "./eaTypes";

export class EaApiError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

async function getJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(path, { headers: { Accept: "application/json" }, signal });
  let payload: unknown;
  try { payload = await response.json(); } catch { throw new EaApiError(`HTTP ${response.status}`, response.status); }
  if (!response.ok) {
    const error = payload as { error?: string; detail?: string };
    throw new EaApiError(error.error || error.detail || `HTTP ${response.status}`, response.status);
  }
  return payload as T;
}

function parameters(databaseKey: string, search?: EaTradeSearch): URLSearchParams {
  const params = new URLSearchParams({ database_key: databaseKey });
  if (search) Object.entries(search).forEach(([key, value]) => params.set(key, String(value)));
  return params;
}

export const eaApi = {
  metadata(signal?: AbortSignal): Promise<EaMetadata> { return getJson("/api/ea/metadata", signal); },
  sessions(databaseKey: string, page = 1, signal?: AbortSignal): Promise<EaSessionsResponse> {
    const params = parameters(databaseKey);
    params.set("page", String(page)); params.set("page_size", "50");
    return getJson(`/api/ea/sessions?${params}`, signal);
  },
  summary(session: string, databaseKey: string, signal?: AbortSignal): Promise<EaSummary> {
    return getJson(`/api/ea/sessions/${encodeURIComponent(session)}/summary?${parameters(databaseKey)}`, signal);
  },
  samples(session: string, databaseKey: string, signal?: AbortSignal): Promise<EaSamplesResponse> {
    const params = parameters(databaseKey); params.set("max_points", "1500");
    return getJson(`/api/ea/sessions/${encodeURIComponent(session)}/samples?${params}`, signal);
  },
  trades(session: string, databaseKey: string, search: EaTradeSearch, signal?: AbortSignal): Promise<EaTradesResponse> {
    return getJson(`/api/ea/sessions/${encodeURIComponent(session)}/trades?${parameters(databaseKey, search)}`, signal);
  },
  detail(id: number, session: string, databaseKey: string, search: EaTradeSearch, signal?: AbortSignal): Promise<EaTradeDetail> {
    const params = parameters(databaseKey, search); params.set("session", session);
    return getJson(`/api/ea/trades/${id}?${params}`, signal);
  },
};
