export const M5_LAYOUT_KEY = "m5Observation.gridLayout.v1";
export const M5_DENSITY_KEY = "m5Observation.density.v1";
export const M5_REFRESH_KEY = "m5Observation.refreshIntervalSeconds.v1";
export interface M5ColumnLayout { colId: string; width: number; hide: boolean }
export function readM5Preference<T>(key: string, fallback: T, valid: (value: unknown) => value is T): T {
  try {
    const raw = localStorage.getItem(key);
    if (raw === null) return fallback;
    const value: unknown = JSON.parse(raw);
    return valid(value) ? value : fallback;
  } catch { return fallback; }
}
export function writeM5Preference(key: string, value: unknown): void {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* In-memory settings still work. */ }
}
export function validM5Layout(value: unknown): value is M5ColumnLayout[] {
  return Array.isArray(value) && value.length <= 30 && value.every((item: unknown) => {
    if (typeof item !== "object" || item === null) return false;
    const column = item as M5ColumnLayout;
    return typeof column.colId === "string" && Number.isFinite(column.width)
      && column.width >= 60 && column.width <= 2000 && typeof column.hide === "boolean";
  }) && new Set(value.map((item: M5ColumnLayout) => item.colId)).size === value.length;
}
