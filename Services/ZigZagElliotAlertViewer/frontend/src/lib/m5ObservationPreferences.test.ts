import { beforeEach, describe, expect, it } from "vitest";
import { M5_DENSITY_KEY, M5_LAYOUT_KEY, M5_REFRESH_KEY, readM5Preference, validM5Layout, writeM5Preference } from "./m5ObservationPreferences";

describe("M5 independent preferences", () => {
  beforeEach(() => localStorage.clear());
  it("uses separate M5 keys and round-trips sanitized column state", () => {
    expect([M5_LAYOUT_KEY, M5_DENSITY_KEY, M5_REFRESH_KEY].every((key) => key.startsWith("m5Observation."))).toBe(true);
    const layout = [{ colId: "tf_M5", width: 150, hide: false }];
    writeM5Preference(M5_LAYOUT_KEY, layout);
    expect(readM5Preference(M5_LAYOUT_KEY, [], validM5Layout)).toEqual(layout);
  });
  it("rejects damaged, repeated, negative or oversized layout entries", () => {
    const column = { colId: "tf_M5", width: 150, hide: false };
    expect(validM5Layout([column, column])).toBe(false);
    expect(validM5Layout([{ ...column, width: -1 }])).toBe(false);
    expect(validM5Layout([{ ...column, width: 5000 }])).toBe(false);
    localStorage.setItem(M5_LAYOUT_KEY, "bad JSON");
    expect(readM5Preference(M5_LAYOUT_KEY, [], validM5Layout)).toEqual([]);
  });
});
