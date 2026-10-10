import { describe, expect, it, vi } from "vitest";
import {
  elliottDirectionSymbol,
  formatAlertBarTimes,
  formatElliottDirection,
  formatElliottLabel,
  formatNumber,
  formatSignedNumber,
} from "./format";

describe("formatAlertBarTimes", () => {
  it("keeps the server bar start and derives JST without judgment seconds", () => {
    expect(formatAlertBarTimes(
      "2026.10.08 20:30:00", "2026.10.08 20:30:02", "2026.10.09 02:30:02",
    )).toEqual({ jst: "2026.10.09 02:30:00", server: "2026.10.08 20:30:00" });
  });

  it("uses the saved winter offset", () => {
    expect(formatAlertBarTimes(
      "2026.12.08 20:30:00", "2026.12.08 20:30:07", "2026.12.09 03:30:07",
    )).toEqual({ jst: "2026.12.09 03:30:00", server: "2026.12.08 20:30:00" });
  });

  it.each([
    ["2026.10.31 20:30:00", "2026.10.31 20:30:02", "2026.11.01 02:30:02",
      "2026.11.01 02:30:00"],
    ["2026.12.31 20:30:00", "2026.12.31 20:30:02", "2027.01.01 03:30:02",
      "2027.01.01 03:30:00"],
    ["2027.01.01 00:30:00", "2027.01.01 00:30:02", "2027.01.01 07:30:02",
      "2027.01.01 07:30:00"],
    ["2028.02.29 20:30:00", "2028.02.29 20:30:02", "2028.03.01 03:30:02",
      "2028.03.01 03:30:00"],
  ])("handles calendar boundaries for %s", (bar, server, savedJst, jst) => {
    expect(formatAlertBarTimes(bar, server, savedJst)).toEqual({ jst, server: bar });
  });

  it.each([
    "", " ", "invalid", "2026-10-08 20:30:00", "2026.10.08 20:30",
    "2026.10.08 20:30:00Z", "2026.10.08 20:30:00 ", "2026.2.08 20:30:00",
    "2026.02.29 20:30:00", "2026.04.31 20:30:00", "2026.13.08 20:30:00",
    "2026.00.08 20:30:00", "2026.10.00 20:30:00", "2026.10.08 24:00:00",
    "2026.10.08 20:60:00", "2026.10.08 20:30:60", "0000.10.08 20:30:00",
  ])("returns missing values for invalid saved timestamps: %s", (invalid) => {
    expect(formatAlertBarTimes(invalid, "2026.10.08 20:30:02", "2026.10.09 02:30:02"))
      .toEqual({ jst: "未記録", server: "未記録" });
    expect(formatAlertBarTimes("2026.10.08 20:30:00", invalid, "2026.10.09 02:30:02"))
      .toEqual({ jst: "未記録", server: "2026.10.08 20:30:00" });
    expect(formatAlertBarTimes("2026.10.08 20:30:00", "2026.10.08 20:30:02", invalid))
      .toEqual({ jst: "未記録", server: "2026.10.08 20:30:00" });
  });

  it("preserves valid server dates when JST offset or output is invalid", () => {
    expect(formatAlertBarTimes(
      "2026.10.08 20:30:00", "2026.10.08 20:30:02", "2026.10.10 02:30:02",
    )).toEqual({ jst: "未記録", server: "2026.10.08 20:30:00" });
    expect(formatAlertBarTimes(
      "9999.12.31 23:30:00", "2026.10.08 20:30:02", "2026.10.09 02:30:02",
    )).toEqual({ jst: "未記録", server: "9999.12.31 23:30:00" });
    expect(formatAlertBarTimes(
      "0001.01.01 00:30:00", "2026.10.08 20:30:02", "2026.10.08 14:30:02",
    )).toEqual({ jst: "未記録", server: "0001.01.01 00:30:00" });
    expect(formatAlertBarTimes("2026.10.08 20:30:00", "", ""))
      .toEqual({ jst: "未記録", server: "2026.10.08 20:30:00" });
  });

  it.each(["UTC", "Asia/Tokyo", "America/New_York"])(
    "keeps saved wall-clock conversion independent of local TZ %s", (timeZone) => {
      vi.stubEnv("TZ", timeZone);
      try {
        expect(formatAlertBarTimes(
          "2026.10.08 20:30:00", "2026.10.08 20:30:02", "2026.10.09 02:30:02",
        )).toEqual({ jst: "2026.10.09 02:30:00", server: "2026.10.08 20:30:00" });
      } finally {
        vi.unstubAllEnvs();
      }
    },
  );
});

describe("formatSignedNumber", () => {
  it("adds a plus sign only to positive directional values", () => {
    expect(formatSignedNumber(2.5)).toBe("+2.5");
    expect(formatSignedNumber(-2.5)).toBe("-2.5");
    expect(formatSignedNumber(0)).toBe("0.0");
    expect(formatSignedNumber(-0)).toBe("0.0");
    expect(formatSignedNumber(3, 0)).toBe("+3");
    expect(formatSignedNumber(null)).toBe("—");
    expect(formatSignedNumber(Number.NaN)).toBe("—");
  });

  it("keeps ordinary number formatting unsigned", () => {
    expect(formatNumber(1.2, 5)).toBe("1.20000");
  });
});

describe("formatElliottDirection", () => {
  it("pairs a visible triangle with the direction label", () => {
    expect(elliottDirectionSymbol(true)).toBe("▲");
    expect(elliottDirectionSymbol(false)).toBe("▼");
    expect(formatElliottDirection(true)).toBe("▲ 上昇");
    expect(formatElliottDirection(false)).toBe("▼ 下降");
  });
});

describe("formatElliottLabel", () => {
  it("appends the saved pre-recount label only to a changed main label", () => {
    expect(formatElliottLabel("1", "iii", "3")).toBe("1.iii[3]");
    expect(formatElliottLabel("A", "iii", "C")).toBe("A.iii[C]");
    expect(formatElliottLabel("3", "iii", "3")).toBe("3.iii");
    expect(formatElliottLabel("1", "", "3")).toBe("1[3]");
    expect(formatElliottLabel(" 3 ", " i ", "3")).toBe("3.i");
  });

  it("never infers original labels or appends them to missing main labels", () => {
    for (const original of [null, undefined, "", "   "]) {
      expect(formatElliottLabel("1", "iii", original)).toBe("1.iii");
    }
    expect(formatElliottLabel(null, "iii", "3")).toBe("—.iii");
    expect(formatElliottLabel("", "iii", "3", "未記録")).toBe("未記録.iii");
  });
});
