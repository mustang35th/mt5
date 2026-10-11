import { describe, expect, it } from "vitest";
import { isH1H4WaveRestrictionDisabled } from "./h1EntryPolicy";

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
