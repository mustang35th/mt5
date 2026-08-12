import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { ObservationListItem } from "../api/types";
import { ObservationTable } from "./ObservationTable";

function observation(id: number, symbol: string, isGmoTarget: boolean): ObservationListItem {
  return {
    id,
    run_id: 7,
    run_uid: "run-7",
    source_mode: "LIVE",
    source_server: "MetaQuotes-Demo",
    symbol_name: symbol,
    is_gmo_target: isGmoTarget,
    anchor_bar_time: 1_786_384_800,
    anchor_bar_time_text: "2026.08.10 05:00:00",
    anchor_jst_time: 1_786_406_400,
    anchor_jst_time_text: "2026.08.10 11:00:00",
    anchor_time_frame: 16_385,
    anchor_time_frame_text: "H1",
    capture_phase: "BAR_OPEN_FIRST_SUCCESS",
    analysis_version: "2.0",
    analysis_input_hash: "analysis-hash",
    snapshot_hash: `snapshot-${id}`,
    time_frame_count: 0,
    created_at: 1_786_406_401,
    created_at_text: "2026.08.10 11:00:01",
    time_frames: [],
  };
}

describe("ObservationTable", () => {
  it("shows GMO target state next to each symbol", async () => {
    render(
      <ObservationTable
        available
        items={[
          observation(1, "USDJPY", true),
          observation(2, "USDCAD", false),
        ]}
        loading={false}
        onOpenDetail={vi.fn()}
        onSort={vi.fn()}
        order="desc"
        sort="anchor_jst_time"
      />,
    );

    expect(await screen.findByLabelText("GMO取引 対象")).toHaveTextContent("GMO");
    expect(screen.queryByLabelText("GMO取引 対象外")).not.toBeInTheDocument();
  });
});
