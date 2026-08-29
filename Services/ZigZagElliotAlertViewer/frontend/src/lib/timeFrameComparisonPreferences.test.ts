import { beforeEach, describe, expect, it } from "vitest";
import {
  clearTimeFrameComparisonColumnGroupState,
  defaultTimeFrameComparisonColumnGroupState,
  readTimeFrameComparisonColumnGroupState,
  TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY,
  writeTimeFrameComparisonColumnGroupState,
} from "./timeFrameComparisonPreferences";

describe("timeFrameComparisonPreferences", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("uses the collapsed overview when no valid state is stored", () => {
    expect(readTimeFrameComparisonColumnGroupState(localStorage)).toEqual(
      defaultTimeFrameComparisonColumnGroupState(),
    );

    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, "not-json");
    expect(readTimeFrameComparisonColumnGroupState(localStorage)).toEqual(
      defaultTimeFrameComparisonColumnGroupState(),
    );

    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, JSON.stringify({
      version: 2,
      groups: {
        wave: true,
        zigzag_point: false,
        price: false,
        fibo_expansion: false,
        oscillator_stochastic: "open",
        trend_ema: false,
      },
    }));
    expect(readTimeFrameComparisonColumnGroupState(localStorage)).toEqual(
      defaultTimeFrameComparisonColumnGroupState(),
    );
  });

  it("round-trips allowed group state and ignores unknown groups", () => {
    localStorage.setItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY, JSON.stringify({
      version: 2,
      groups: {
        wave: true,
        zigzag_point: false,
        price: false,
        fibo_expansion: true,
        oscillator_stochastic: false,
        trend_ema: true,
        removed_group: true,
      },
    }));

    expect(readTimeFrameComparisonColumnGroupState(localStorage)).toEqual({
      wave: true,
      zigzag_point: false,
      price: false,
      fibo_expansion: true,
      oscillator_stochastic: false,
      trend_ema: true,
    });

    writeTimeFrameComparisonColumnGroupState({
      wave: false,
      zigzag_point: true,
      price: true,
      fibo_expansion: false,
      oscillator_stochastic: true,
      trend_ema: false,
    }, localStorage);
    expect(JSON.parse(
      localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY) ?? "",
    )).toEqual({
      version: 2,
      groups: {
        wave: false,
        zigzag_point: true,
        price: true,
        fibo_expansion: false,
        oscillator_stochastic: true,
        trend_ema: false,
      },
    });
  });

  it("clears the saved state", () => {
    writeTimeFrameComparisonColumnGroupState({
      wave: true,
      zigzag_point: true,
      price: true,
      fibo_expansion: true,
      oscillator_stochastic: true,
      trend_ema: true,
    }, localStorage);

    clearTimeFrameComparisonColumnGroupState(localStorage);

    expect(localStorage.getItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY)).toBeNull();
  });
});
