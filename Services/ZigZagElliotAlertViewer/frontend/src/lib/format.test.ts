import { describe, expect, it } from "vitest";
import {
  elliottDirectionSymbol,
  formatElliottDirection,
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
