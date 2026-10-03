import { describe, expect, it } from "vitest";
import {
  elliottDirectionSymbol,
  formatElliottDirection,
  formatElliottLabel,
  formatNumber,
  formatSignedNumber,
} from "./format";

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
