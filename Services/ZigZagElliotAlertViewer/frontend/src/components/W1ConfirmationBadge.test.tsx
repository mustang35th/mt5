import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { W1ConfirmationDiagnostics } from "../api/types";
import { W1ConfirmationBadge } from "./W1ConfirmationBadge";

const OBSERVE_CONFLICT: W1ConfirmationDiagnostics = {
  w1_confirmation_mode: "OBSERVE_ONLY",
  w1_confirmation_state: "EMA_CONFLICT",
  is_w1_confirmation_available: true,
  is_w1_confirmation_valid: true,
  is_w1_direction_matched: true,
  w1_ema200_direction: "SELL",
  is_w1_ema200_matched: false,
  is_w1_confirmation_passed: false,
  is_w1_confirmation_legacy: false,
};

describe("W1ConfirmationBadge", () => {
  it("shows code, Japanese meaning and observe-only mode without implying entry rejection", () => {
    render(<W1ConfirmationBadge confirmation={OBSERVE_CONFLICT} />);

    expect(screen.getByText("EMA_CONFLICT / 方向一致・EMA逆")).toBeInTheDocument();
    expect(screen.getByText("mode: 記録のみ")).toBeInTheDocument();
    expect(screen.getByLabelText(/記録のみのためエントリー制限なし/)).toBeInTheDocument();
  });

  it("labels old rows as Legacy instead of presenting default OFF as recorded", () => {
    render(
      <W1ConfirmationBadge
        compact
        confirmation={{
          ...OBSERVE_CONFLICT,
          w1_confirmation_mode: "OFF",
          w1_confirmation_state: "NOT_EVALUATED",
          is_w1_confirmation_passed: true,
          is_w1_confirmation_legacy: true,
        }}
      />,
    );

    expect(screen.getByText("Legacy / 未記録")).toBeInTheDocument();
    expect(screen.queryByText("OFF")).not.toBeInTheDocument();
    expect(screen.getByLabelText(/mode未記録。ルール評価未記録/)).toBeInTheDocument();
  });
});
