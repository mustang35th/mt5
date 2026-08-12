import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { GmoTargetBadge } from "./GmoTargetBadge";

describe("GmoTargetBadge", () => {
  it.each([
    [true, "GMO取引 対象", "GMO"],
    [undefined, "GMO取引 不明", "GMO不明"],
  ])("renders the GMO target state", (isTarget, accessibleName, compactLabel) => {
    render(<GmoTargetBadge compact isTarget={isTarget} />);

    const badge = screen.getByLabelText(accessibleName);
    expect(badge).toHaveTextContent(compactLabel);
    expect(badge).toHaveAttribute("title", accessibleName);
  });

  it("does not render a badge for an excluded symbol", () => {
    const { container } = render(<GmoTargetBadge compact isTarget={false} />);

    expect(container).toBeEmptyDOMElement();
  });
});
