export type GridDensity = "standard" | "compact";

export interface GridColumnLayoutItem {
  colId: string;
  width: number;
  hide: boolean;
}

interface StoredGridColumnLayout {
  version: 1;
  columns: GridColumnLayoutItem[];
}

export const DEFAULT_GRID_DENSITY: GridDensity = "standard";
export const GRID_DENSITY_STORAGE_KEY = "zigzagElliotAlertViewer.gridDensity";
export const GRID_LAYOUT_STORAGE_KEY = "zigzagElliotAlertViewer.gridColumnLayout.v1";

const MIN_COLUMN_WIDTH = 60;
const MAX_COLUMN_WIDTH = 2000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Restore the grid density from browser storage.
 */
export function readGridDensity(storage: Storage): GridDensity {
  try {
    const stored = storage.getItem(GRID_DENSITY_STORAGE_KEY);
    if (stored === "standard" || stored === "compact") return stored;
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
  return DEFAULT_GRID_DENSITY;
}

/**
 * Persist the grid density for the next viewer session.
 */
export function writeGridDensity(storage: Storage, density: GridDensity): void {
  try {
    storage.setItem(GRID_DENSITY_STORAGE_KEY, density);
  } catch {
    // Continue with the in-memory setting when storage is unavailable.
  }
}

/**
 * Restore and validate the saved column order, width and visibility.
 */
export function readGridColumnLayout(
  storage: Storage,
  allowedColumnIds: ReadonlySet<string>,
): GridColumnLayoutItem[] | null {
  try {
    const storedText = storage.getItem(GRID_LAYOUT_STORAGE_KEY);
    if (storedText === null) return null;
    const stored: unknown = JSON.parse(storedText);
    if (!isRecord(stored) || stored.version !== 1 || !Array.isArray(stored.columns)) {
      return null;
    }

    const seen = new Set<string>();
    const columns: GridColumnLayoutItem[] = [];
    for (const value of stored.columns) {
      if (!isRecord(value)) return null;
      const colId = value.colId;
      const width = value.width;
      const hide = value.hide;
      if (typeof colId !== "string" || typeof width !== "number" || typeof hide !== "boolean") {
        return null;
      }
      if (!Number.isFinite(width) || width < MIN_COLUMN_WIDTH || width > MAX_COLUMN_WIDTH) {
        return null;
      }
      if (!allowedColumnIds.has(colId)) continue;
      if (seen.has(colId)) return null;
      seen.add(colId);
      columns.push({ colId, width: Math.round(width), hide });
    }
    return columns.length > 0 ? columns : null;
  } catch {
    return null;
  }
}

/**
 * Persist the column order, width and visibility.
 */
export function writeGridColumnLayout(
  storage: Storage,
  columns: GridColumnLayoutItem[],
): void {
  const stored: StoredGridColumnLayout = { version: 1, columns };
  try {
    storage.setItem(GRID_LAYOUT_STORAGE_KEY, JSON.stringify(stored));
  } catch {
    // Continue with the in-memory layout when storage is unavailable.
  }
}

/**
 * Remove the saved column layout.
 */
export function clearGridColumnLayout(storage: Storage): void {
  try {
    storage.removeItem(GRID_LAYOUT_STORAGE_KEY);
  } catch {
    // The current grid can still reset even when storage is unavailable.
  }
}
