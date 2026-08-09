import type {
  AlertsResponse,
  ApiErrorResponse,
  HealthResponse,
  OptionsResponse,
  RunsResponse,
  SearchState,
  SummaryResponse,
} from "./types";
import { buildSearchParams } from "../lib/searchState";

export class ApiError extends Error {}

async function fetchJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(path, {
    headers: { Accept: "application/json" },
    signal,
  });
  let payload: T | ApiErrorResponse;
  try {
    payload = (await response.json()) as T | ApiErrorResponse;
  } catch {
    throw new ApiError(`HTTP ${response.status}`);
  }
  if (!response.ok) {
    const errorPayload = payload as ApiErrorResponse;
    throw new ApiError(errorPayload.error || errorPayload.detail || `HTTP ${response.status}`);
  }
  return payload as T;
}

export const api = {
  health(signal?: AbortSignal): Promise<HealthResponse> {
    return fetchJson<HealthResponse>("/api/health", signal);
  },
  runs(signal?: AbortSignal): Promise<RunsResponse> {
    return fetchJson<RunsResponse>("/api/runs", signal);
  },
  options(signal?: AbortSignal): Promise<OptionsResponse> {
    return fetchJson<OptionsResponse>("/api/options", signal);
  },
  alerts(search: SearchState, signal?: AbortSignal): Promise<AlertsResponse> {
    return fetchJson<AlertsResponse>(`/api/alerts?${buildSearchParams(search)}`, signal);
  },
  summary(search: SearchState, signal?: AbortSignal): Promise<SummaryResponse> {
    return fetchJson<SummaryResponse>(`/api/summary?${buildSearchParams(search)}`, signal);
  },
};
