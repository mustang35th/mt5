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
    expect(screen.getByLabelText(/記録のみのためエントリー制限なし/)).toBeInTheDocument();
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
    expect(screen.queryByLabelText(/全足不一致・記録のみ/)).not.toBeInTheDocument();
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
