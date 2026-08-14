import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Ema200SignalBadge } from "./Ema200SignalBadge";

describe("Ema200SignalBadge", () => {
  it.each([
    ["H1", true, false, "EMA200 ↑ BUY", "EMA200判定 BUY", "buy"],
    ["H1", false, true, "EMA200 ↓ SELL", "EMA200判定 SELL", "sell"],
    ["H1", false, false, "EMA200 NONE", "EMA200判定 NONE", "neutral"],
    ["H1", true, true, "EMA200 異常", "EMA200判定 異常。BUYとSELLが同時に記録されています", "warn"],
    ["MN1", false, false, "EMA200 SKIP", "EMA200判定 対象外。MN1は計算を省略", "neutral"],
  ])(
    "renders the %s signal state",
    (timeFrameText, isBuy, isSell, label, description, variant) => {
      render(
        <Ema200SignalBadge
          timeFrame={{
            time_frame_text: timeFrameText,
            is_ema200_buy: isBuy,
            is_ema200_sell: isSell,
          }}
        />,
      );

      const badge = screen.getByLabelText(description);
      expect(badge).toHaveTextContent(label);
      expect(badge).toHaveClass("badge", variant, "observation-ema200-badge");
      expect(badge).toHaveAttribute("title", description);
    },
  );

  it("shows an unavailable record before interpreting signal flags", () => {
    render(
      <Ema200SignalBadge
        available={false}
        timeFrame={{
          time_frame_text: "H1",
          is_ema200_buy: true,
          is_ema200_sell: false,
        }}
      />,
    );

    const badge = screen.getByLabelText("EMA200判定 記録なし");
    expect(badge).toHaveTextContent("EMA200 記録なし");
    expect(badge).toHaveClass("badge", "neutral", "observation-ema200-badge");
    expect(screen.queryByLabelText("EMA200判定 BUY")).not.toBeInTheDocument();
  });
});
