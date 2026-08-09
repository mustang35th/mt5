export const REFRESH_INTERVAL_OPTIONS = [0, 5, 15, 30, 60] as const;
export type RefreshIntervalSeconds = (typeof REFRESH_INTERVAL_OPTIONS)[number];

export const DEFAULT_REFRESH_INTERVAL_SECONDS: RefreshIntervalSeconds = 15;
export const REFRESH_INTERVAL_STORAGE_KEY = "zigzagElliotAlertViewer.refreshIntervalSeconds";

/**
 * Check whether a value is an allowed refresh interval.
 */
export function isRefreshIntervalSeconds(value: number): value is RefreshIntervalSeconds {
  return REFRESH_INTERVAL_OPTIONS.some((option) => option === value);
}

/**
 * Restore the refresh interval from browser storage.
 */
export function readRefreshInterval(storage: Storage): RefreshIntervalSeconds {
  try {
    const storedText = storage.getItem(REFRESH_INTERVAL_STORAGE_KEY);
    if (storedText === null) return DEFAULT_REFRESH_INTERVAL_SECONDS;
    const stored = Number(storedText);
    if (isRefreshIntervalSeconds(stored)) return stored;
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
  return DEFAULT_REFRESH_INTERVAL_SECONDS;
}

/**
 * Persist the refresh interval for the next viewer session.
 */
export function writeRefreshInterval(
  storage: Storage,
  intervalSeconds: RefreshIntervalSeconds,
): void {
  try {
    storage.setItem(REFRESH_INTERVAL_STORAGE_KEY, String(intervalSeconds));
  } catch {
    // Continue with the in-memory value when storage is unavailable.
  }
}
