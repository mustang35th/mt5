import { describe, expect, it } from "vitest";
import {
  DEFAULT_REFRESH_INTERVAL_SECONDS,
  readRefreshInterval,
  REFRESH_INTERVAL_STORAGE_KEY,
  writeRefreshInterval,
} from "./refreshSettings";

describe("refreshSettings", () => {
  it("uses 15 seconds when no valid setting exists", () => {
    localStorage.removeItem(REFRESH_INTERVAL_STORAGE_KEY);
    expect(readRefreshInterval(localStorage)).toBe(DEFAULT_REFRESH_INTERVAL_SECONDS);

    localStorage.setItem(REFRESH_INTERVAL_STORAGE_KEY, "1");
    expect(readRefreshInterval(localStorage)).toBe(DEFAULT_REFRESH_INTERVAL_SECONDS);
  });

  it("persists OFF and supported intervals", () => {
    writeRefreshInterval(localStorage, 0);
    expect(readRefreshInterval(localStorage)).toBe(0);

    writeRefreshInterval(localStorage, 30);
    expect(readRefreshInterval(localStorage)).toBe(30);
  });
});
