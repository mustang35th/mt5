import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { AlertListItem } from "../api/types";
import { Ema200DistanceCell } from "./Ema200DistanceCell";

function savedAlert(overrides: Partial<AlertListItem> = {}): AlertListItem {
  return {
    id: 3574,
    time_frame_text: "M15",
    is_entry_evaluated: true,
    close_ema200_diff_pips: 33.99868384499127,
    max_close_ema200_diff_pips: 25,
    is_ema200_distance_within: false,
    ...overrides,
  } as AlertListItem;
}

describe("Ema200DistanceCell", () => {
  it("shows the saved M15 distance and separates reference comparison from entry eligibility", () => {
    render(<Ema200DistanceCell alert={savedAlert()} />);

    const cell = screen.getByLabelText(/M15 EMA200距離: 34\.0 pips/);
    expect(cell).toHaveTextContent("34.0 pips");
    expect(cell).toHaveTextContent("超過");
    expect(cell).toHaveClass("over-limit");
    expect(cell.getAttribute("title")).toContain("M15の確定足終値[1]とEMA200[1]の絶対差");
    expect(cell.getAttribute("title")).toContain("保存参考上限: 25.0 pips");
    expect(cell.getAttribute("title")).toContain("超過量: 9.0 pips");
    expect(cell.getAttribute("title")).toContain("参考比較であり、ENTRY可否とは別");
    expect(cell.getAttribute("title")).toContain("現行M15では距離制限の適用なし");
    expect(cell.getAttribute("title")).toContain("保存当時の適用有無を示す表示ではありません");
  });

  it.each([0, -0, 24.9999, 25])("keeps the genuine value %s within its saved upper limit", (distance) => {
    render(<Ema200DistanceCell alert={savedAlert({ close_ema200_diff_pips: distance })} />);

    const cell = screen.getByLabelText(/M15 EMA200距離:/);
    expect(cell).not.toHaveClass("over-limit");
    expect(screen.queryByText("超過")).not.toBeInTheDocument();
    expect(cell.getAttribute("title")).toContain("保存参考上限以内");
    if (distance === 0) {
      expect(cell).toHaveTextContent("0.0 pips");
      expect(cell).not.toHaveTextContent("-0.0");
      expect(screen.queryByText("未記録")).not.toBeInTheDocument();
    }
  });

  it("compares before rounding even when both values display as 25.0", () => {
    render(<Ema200DistanceCell alert={savedAlert({
      close_ema200_diff_pips: 25.0001,
      is_ema200_distance_within: true,
    })} />);

    const cell = screen.getByLabelText(/M15 EMA200距離: 25\.0 pips/);
    expect(cell).toHaveClass("over-limit");
    expect(cell).toHaveTextContent("超過");
    expect(cell.getAttribute("title")).toContain("超過量: 0.1 pips未満");
    expect(cell.getAttribute("title")).not.toContain("超過量: 0.0");
  });

  it("uses each alert's timeframe and saved upper limit", () => {
    render(<Ema200DistanceCell alert={savedAlert({
      time_frame_text: "H1",
      max_close_ema200_diff_pips: 50,
    })} />);

    const cell = screen.getByLabelText(/H1 EMA200距離: 34\.0 pips/);
    expect(cell).not.toHaveClass("over-limit");
    expect(cell.getAttribute("title")).toContain("H1の確定足終値[1]");
    expect(cell.getAttribute("title")).toContain("保存参考上限: 50.0 pips");
    expect(cell.getAttribute("title")).not.toContain("M15");
  });

  it("does not interpret an unevaluated initial zero as zero distance", () => {
    render(<Ema200DistanceCell alert={savedAlert({
      is_entry_evaluated: false,
      close_ema200_diff_pips: 0,
      max_close_ema200_diff_pips: 0,
    })} />);

    const cell = screen.getByLabelText("M15 EMA200距離: 未評価");
    expect(cell).toHaveTextContent("—");
    expect(cell).toHaveTextContent("未評価");
    expect(cell).not.toHaveTextContent("pips");
  });

  it.each<Partial<AlertListItem>>([
    { is_entry_evaluated: undefined },
    { close_ema200_diff_pips: undefined },
    { close_ema200_diff_pips: null },
    { close_ema200_diff_pips: Number.NaN },
    { close_ema200_diff_pips: Number.POSITIVE_INFINITY },
    { close_ema200_diff_pips: Number.MAX_VALUE },
    { close_ema200_diff_pips: -1 },
    { max_close_ema200_diff_pips: undefined },
    { max_close_ema200_diff_pips: null },
    { max_close_ema200_diff_pips: Number.NaN },
    { max_close_ema200_diff_pips: Number.POSITIVE_INFINITY },
    { max_close_ema200_diff_pips: Number.MAX_VALUE },
    { max_close_ema200_diff_pips: 0 },
    { max_close_ema200_diff_pips: -1 },
    { close_ema200_diff_pips: 0, max_close_ema200_diff_pips: 0 },
  ])("marks unavailable saved data as unrecorded: %o", (overrides) => {
    render(<Ema200DistanceCell alert={savedAlert(overrides)} />);

    const cell = screen.getByLabelText("M15 EMA200距離: 未記録");
    expect(cell).toHaveTextContent("—");
    expect(cell).toHaveTextContent("未記録");
    expect(cell).not.toHaveClass("over-limit");
    expect(cell).not.toHaveTextContent("pips");
  });

  it.each(["APPLIED", "INCOMPLETE"] as const)(
    "keeps the saved entry distance independent of the %s analysis snapshot",
    (status) => {
      render(<Ema200DistanceCell alert={savedAlert({
        analysis_snapshot: { status, correction_time_frame_text: "H1", timeframes: [] },
      })} />);

      expect(screen.getByLabelText(/M15 EMA200距離: 34\.0 pips/)).toHaveTextContent("超過");
    },
  );
});
