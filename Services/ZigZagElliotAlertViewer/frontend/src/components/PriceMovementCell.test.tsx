import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { PriceMovementSnapshot } from "../api/types";
import { priceMovementLabel, priceMovementTooltip } from "../lib/priceMovement";
import { PriceMovementCell } from "./PriceMovementCell";

const saved: PriceMovementSnapshot = {
  price_movement_status: "VALID",
  is_price_movement_valid: true,
  price_movement_level: 3,
  price_movement_average_range_pips: 4.2,
  price_movement_reference_atr_pips: 3,
  price_movement_activity_ratio: 1.4,
  is_price_movement_spread_valid: true,
  price_movement_range_spread_ratio: 7,
  price_movement_reference_bar_time: Date.UTC(2026, 10, 24, 10, 25) / 1000,
};

describe("PriceMovementCell", () => {
  it("shows the saved category and details with an unshifted server time", () => {
    render(<PriceMovementCell snapshot={saved} detailed timeFrame="M5" />);
    const cell = screen.getByLabelText(/M5 値動き：活発 1.40倍/);
    expect(cell).toHaveClass("price-movement-active");
    expect(cell).toHaveTextContent("平均値幅：4.2 pips");
    expect(cell).toHaveTextContent("基準ATR14：3.0 pips");
    expect(cell).toHaveTextContent("スプレッド倍率：7.00倍");
    expect(cell).toHaveTextContent("2026/11/24 10:25:00 Server");
  });

  it("retains a valid zero range and does not reclassify the stored level", () => {
    expect(priceMovementLabel({ ...saved, price_movement_level: 1,
      price_movement_average_range_pips: 0, price_movement_activity_ratio: 0 })).toBe("静か 0.00倍");
    expect(priceMovementLabel({ ...saved, price_movement_level: 2 })).toBe("通常 1.40倍");
  });

  it.each([
    ["UNRECORDED", "未記録"], ["UNAVAILABLE", "判定不能"], ["UNKNOWN", "未記録／判定不能"],
  ] as const)("respects %s even when stray numeric values exist", (status, expected) => {
    expect(priceMovementLabel({ ...saved, price_movement_status: status })).toBe(expected);
    expect(priceMovementTooltip({ ...saved, price_movement_status: status })).not.toContain("pips");
  });

  it("treats absent fields as unrecorded, and an unclassified false flag as unknown", () => {
    expect(priceMovementLabel(undefined)).toBe("未記録");
    expect(priceMovementLabel({})).toBe("未記録");
    expect(priceMovementLabel({ is_price_movement_valid: false })).toBe("未記録／判定不能");
  });

  it.each([
    { price_movement_reference_atr_pips: 0 }, { price_movement_reference_atr_pips: Number.NaN },
    { price_movement_activity_ratio: Number.POSITIVE_INFINITY }, { price_movement_average_range_pips: -1 },
    { price_movement_level: 0 }, { price_movement_level: 4 }, { price_movement_reference_bar_time: 0 },
    { price_movement_activity_ratio: Number.MAX_VALUE }, { is_price_movement_valid: false },
  ])("does not display invalid core values: %j", (invalid) => {
    expect(priceMovementLabel({ ...saved, ...invalid })).toBe("判定不能");
  });

  it("keeps core values when spread comparison is unavailable", () => {
    const snapshot = { ...saved, is_price_movement_spread_valid: false, price_movement_range_spread_ratio: null };
    expect(priceMovementLabel(snapshot)).toBe("活発 1.40倍");
    expect(priceMovementTooltip(snapshot)).toContain("スプレッド倍率：取得不能");
    expect(priceMovementTooltip(snapshot)).toContain("平均値幅：4.2 pips");
  });
});
