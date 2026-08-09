import { beforeEach, describe, expect, it } from "vitest";
import {
  clearGridColumnLayout,
  DEFAULT_GRID_DENSITY,
  GRID_DENSITY_STORAGE_KEY,
  GRID_LAYOUT_STORAGE_KEY,
  readGridColumnLayout,
  readGridDensity,
  writeGridColumnLayout,
  writeGridDensity,
} from "./gridPreferences";

const ALLOWED_COLUMNS = new Set(["jst_time", "symbol_name", "risk_pips"]);

describe("gridPreferences", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("uses standard density unless a supported value is stored", () => {
    expect(readGridDensity(localStorage)).toBe(DEFAULT_GRID_DENSITY);

    localStorage.setItem(GRID_DENSITY_STORAGE_KEY, "dense");
    expect(readGridDensity(localStorage)).toBe(DEFAULT_GRID_DENSITY);

    writeGridDensity(localStorage, "compact");
    expect(readGridDensity(localStorage)).toBe("compact");
  });

  it("round-trips valid column state and ignores removed columns", () => {
    writeGridColumnLayout(localStorage, [
      { colId: "risk_pips", width: 151, hide: true },
      { colId: "removed_column", width: 120, hide: false },
      { colId: "jst_time", width: 190, hide: false },
    ]);

    expect(readGridColumnLayout(localStorage, ALLOWED_COLUMNS)).toEqual([
      { colId: "risk_pips", width: 151, hide: true },
      { colId: "jst_time", width: 190, hide: false },
    ]);

    clearGridColumnLayout(localStorage);
    expect(localStorage.getItem(GRID_LAYOUT_STORAGE_KEY)).toBeNull();
  });

  it("rejects malformed layouts instead of partially applying them", () => {
    localStorage.setItem(GRID_LAYOUT_STORAGE_KEY, JSON.stringify({
      version: 1,
      columns: [{ colId: "jst_time", width: 10, hide: false }],
    }));
    expect(readGridColumnLayout(localStorage, ALLOWED_COLUMNS)).toBeNull();

    localStorage.setItem(GRID_LAYOUT_STORAGE_KEY, "not-json");
    expect(readGridColumnLayout(localStorage, ALLOWED_COLUMNS)).toBeNull();
  });
});
