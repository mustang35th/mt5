import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { H1DirectionAlignmentDiagnostics } from "../api/types";
import { H1DirectionAlignmentBadge } from "./H1DirectionAlignmentBadge";

const OBSERVE_MISMATCH: H1DirectionAlignmentDiagnostics = {
  h1_direction_alignment_mode: "MN1_TO_H1_OBSERVE",
  h1_direction_alignment_state: "MN1_MISMATCH",
  is_h1_direction_alignment_available: true,
  is_h1_direction_alignment_valid: true,
  h1_direction_alignment_direction: "BUY",
  is_h1_mn1_direction_matched: false,
  is_h1_w1_direction_matched: true,
  is_h1_direction_alignment_passed: false,
  is_h1_direction_alignment_legacy: false,
};

describe("H1DirectionAlignmentBadge", () => {
  it("shows an observe mismatch without implying entry rejection", () => {
    render(<H1DirectionAlignmentBadge alignment={OBSERVE_MISMATCH} />);

    expect(screen.getByText("MN1_MISMATCH / MN1不一致")).toBeInTheDocument();
    expect(screen.getByText("mode: MN1～H1・記録のみ")).toBeInTheDocument();
    expect(screen.getByLabelText(/ルール不通過・記録のみのためエントリー制限なし/))
      .toBeInTheDocument();
    expect(screen.queryByLabelText(/全足/)).not.toBeInTheDocument();
  });

  it.each([
    ["UNAVAILABLE", "取得不可"],
    ["INVALID", "不正"],
  ] as const)("labels an observe %s result as unavailable", (state, label) => {
    render(
      <H1DirectionAlignmentBadge
        alignment={{
          ...OBSERVE_MISMATCH,
          h1_direction_alignment_state: state,
          is_h1_direction_alignment_available: state !== "UNAVAILABLE",
          is_h1_direction_alignment_valid: false,
        }}
      />,
    );

    expect(
      screen.getByLabelText(new RegExp(`${label}・記録のみのためエントリー制限なし`)),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText(/ルール不通過・記録のみ/)).not.toBeInTheDocument();
  });

  it.each([
    ["EMA200_FALLBACK_BUY", "BUY", "EMA200補完BUY"],
    ["EMA200_FALLBACK_SELL", "SELL", "EMA200補完SELL"],
  ] as const)("shows %s as a successful EMA200 fallback", (state, direction, label) => {
    render(
      <H1DirectionAlignmentBadge
        alignment={{
          ...OBSERVE_MISMATCH,
          h1_direction_alignment_mode: "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
          h1_direction_alignment_state: state,
          h1_direction_alignment_direction: direction,
          is_h1_direction_alignment_passed: true,
        }}
      />,
    );

    expect(screen.getByText(`${state} / ${label}`)).toHaveClass("good");
    expect(screen.getByText("mode: W1～H1一致＋MN1またはW1 EMA200・必須"))
      .toBeInTheDocument();
    expect(screen.getByLabelText(/ルール評価通過/)).toBeInTheDocument();
  });

  it("shows an MN1 and EMA200 mismatch as a warning", () => {
    render(
      <H1DirectionAlignmentBadge
        alignment={{
          ...OBSERVE_MISMATCH,
          h1_direction_alignment_mode: "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
          h1_direction_alignment_state: "MN1_EMA200_MISMATCH",
        }}
      />,
    );

    expect(screen.getByText("MN1_EMA200_MISMATCH / MN1・EMA200不一致"))
      .toHaveClass("warn");
    expect(screen.getByLabelText(/MN1とW1 EMA200が基準方向と不一致/))
      .toHaveAccessibleName(/ルール評価不通過/);
  });

  it("labels legacy rows as unrecorded", () => {
    render(
      <H1DirectionAlignmentBadge
        compact
        alignment={{
          ...OBSERVE_MISMATCH,
          h1_direction_alignment_mode: "D1_TO_H1",
          h1_direction_alignment_state: "NOT_EVALUATED",
          is_h1_direction_alignment_legacy: true,
        }}
      />,
    );

    expect(screen.getByText("Legacy / 未記録")).toBeInTheDocument();
    expect(screen.queryByText("D1～H1")).not.toBeInTheDocument();
    expect(screen.getByLabelText(/mode未記録。ルール評価未記録/)).toBeInTheDocument();
  });
});
