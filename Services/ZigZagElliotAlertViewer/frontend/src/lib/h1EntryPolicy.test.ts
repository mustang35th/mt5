import { describe, expect, it } from "vitest";
import { isH1H4WaveRestrictionDisabled, isH4WaveRestrictionDisabled, isM15H4FeLimitDisabled, isM5Mn1AndW1Ema200Required } from "./h1EntryPolicy";

describe("saved H1 H4 wave restriction", () => {
  it("requires one exact false setting on an H1 alert", () => {
    const input = "before=1|h1H4WaveRestrictionEnabled=false|after=0";
    expect(isH1H4WaveRestrictionDisabled("H1", input)).toBe(true);
    for (const frame of ["M15", "M5", undefined]) {
      expect(isH1H4WaveRestrictionDisabled(frame, input)).toBe(false);
    }
  });

  it.each([
    undefined,
    "h1H4WaveRestrictionEnabled=true",
    "h1H4WaveRestrictionEnabled=0",
    "h1H4WaveRestrictionEnabled=false ",
    "other=h1H4WaveRestrictionEnabled=false",
    "h1H4WaveRestrictionEnabledExtra=false",
    "h1H4WaveRestrictionEnabled=false|h1H4WaveRestrictionEnabled=false",
    "h1H4WaveRestrictionEnabled=false| h1H4WaveRestrictionEnabled=true",
  ])("does not infer an exemption from missing or ambiguous settings: %s", (input) => {
    expect(isH1H4WaveRestrictionDisabled("H1", input)).toBe(false);
  });
});

describe("saved M15 H4 exemptions", () => {
  const waveSetting = "h1H4WaveRestrictionEnabled=false";
  const feSetting = "m15H4MaxFibonacciExpansionPercent=0.0";

  it("shows both exemptions only for the explicitly saved M15 settings", () => {
    const input = `${waveSetting}|${feSetting}|m15H1MaxFibonacciExpansionPercent=161.8`;
    expect(isH4WaveRestrictionDisabled("M15", input)).toBe(true);
    expect(isM15H4FeLimitDisabled("M15", input)).toBe(true);
    expect(isH1H4WaveRestrictionDisabled("M15", input)).toBe(false);
    expect(isH4WaveRestrictionDisabled("H1", input)).toBe(true);
    expect(isM15H4FeLimitDisabled("H1", input)).toBe(false);
    for (const frame of ["M5", undefined]) {
      expect(isH4WaveRestrictionDisabled(frame, input)).toBe(false);
      expect(isM15H4FeLimitDisabled(frame, input)).toBe(false);
    }
  });

  it("does not infer FE exemption from a legacy zero or an incomplete new setting", () => {
    expect(isM15H4FeLimitDisabled("M15", feSetting)).toBe(false);
    expect(isM15H4FeLimitDisabled("M15", waveSetting)).toBe(false);
    expect(isH4WaveRestrictionDisabled("M15", feSetting)).toBe(false);
  });

  it.each([
    "161.8", "0", "0.0 ",
    "0.0|m15H4MaxFibonacciExpansionPercent=0.0",
    "0.0| m15H4MaxFibonacciExpansionPercent=161.8",
  ])("rejects noncanonical or ambiguous saved H4 FE limits: %s", (value) => {
    const input = `${waveSetting}|m15H4MaxFibonacciExpansionPercent=${value}`;
    expect(isH4WaveRestrictionDisabled("M15", input)).toBe(true);
    expect(isM15H4FeLimitDisabled("M15", input)).toBe(false);
  });
});

describe("saved M5 MN1 and W1 EMA200 confirmation", () => {
  it("requires one exact true setting on an explicit M5 alert", () => {
    const input = "before=1|m5Mn1AndW1Ema200Required=true|after=0";
    expect(isM5Mn1AndW1Ema200Required("M5", input)).toBe(true);
    for (const frame of ["H1", "M15", undefined]) {
      expect(isM5Mn1AndW1Ema200Required(frame, input)).toBe(false);
    }
  });

  it.each([
    undefined,
    "m5Mn1AndW1Ema200Required=false",
    "m5Mn1AndW1Ema200Required=1",
    "m5Mn1AndW1Ema200Required=true ",
    "other=m5Mn1AndW1Ema200Required=true",
    "m5Mn1AndW1Ema200RequiredExtra=true",
    "m5Mn1AndW1Ema200Required=true|m5Mn1AndW1Ema200Required=true",
    "m5Mn1AndW1Ema200Required=true| m5Mn1AndW1Ema200Required=false",
  ])("does not infer AND from missing or ambiguous saved settings: %s", (input) => {
    expect(isM5Mn1AndW1Ema200Required("M5", input)).toBe(false);
  });
});
