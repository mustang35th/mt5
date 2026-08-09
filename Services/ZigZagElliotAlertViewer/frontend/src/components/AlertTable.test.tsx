import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { AlertListItem } from "../api/types";
import { AlertTable } from "./AlertTable";

function alertWithAlignment(id: number, aligned: boolean | null): AlertListItem {
  return {
    id,
    run_id: 3,
    jst_time_text: "2026.07.31 01:00:00",
    server_time_text: "2026.07.30 19:00:00",
    symbol_name: "AUDUSD",
    time_frame_text: "H1",
    strategy: "MTF_3in3",
    side: "BUY",
    signal_count: 1,
    entry_count: 1,
    is_entry: true,
    entry_result: "ENTRY",
    current_elliot_label: "3-3-1",
    risk_pips: 50,
    spread_pips: 1.2,
    h1_structure_rank: "S",
    is_h1_structure_late: false,
    alert_title: "test <img onerror=alert(1)>",
    mn1_side: "BUY",
    w1_side: "BUY",
    d1_side: "BUY",
    h4_side: "BUY",
    h1_side: "BUY",
    is_w1_aligned: aligned,
  };
}

describe("AlertTable", () => {
  it("renders W1 alignment as a three-state value and escapes DB text", () => {
    const onOpenDetail = vi.fn();
    render(
      <AlertTable
        items={[alertWithAlignment(1, true), alertWithAlignment(2, false), alertWithAlignment(3, null)]}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );
    expect(screen.getByText("一致")).toBeInTheDocument();
    expect(screen.getByText("不一致")).toBeInTheDocument();
    expect(screen.getByText("不明")).toBeInTheDocument();
    expect(screen.getAllByText("test <img onerror=alert(1)>")).toHaveLength(3);
    expect(document.querySelector("img")).toBeNull();
    const detailButton = screen.getAllByRole("button", { name: "AUDUSD BUY 2026.07.31 01:00:00 の詳細を表示" })[0];
    fireEvent.click(detailButton);
    expect(onOpenDetail).toHaveBeenCalledWith(1, detailButton);
  });
});
