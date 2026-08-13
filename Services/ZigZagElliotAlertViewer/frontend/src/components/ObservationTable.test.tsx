import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { ObservationListItem, ObservationTimeFrame } from "../api/types";
import { ObservationTable } from "./ObservationTable";

function timeFrame(
  label: string,
  order: number,
  isEma200Buy: boolean,
  isEma200Sell: boolean,
): ObservationTimeFrame {
  return {
    id: 100 + order,
    observation_id: 1,
    time_frame: order + 1,
    time_frame_text: label,
    time_frame_order: order,
    is_anchor_time_frame: label === "H1",
    is_buy: true,
    buy_sell_label: "BUY",
    wave_count: 2,
    latest_wave_index: 1,
    is_wave_confirmed: true,
    is_wave_motive: true,
    is_wave_uptrend: true,
    wave_trend_label: "▲",
    previous_last_elliot_label: "2",
    point_count: 4,
    latest_elliot_index: 3,
    latest_elliot_label: "3",
    latest_sub_elliot_index: 1,
    latest_sub_elliot_label: "3-1",
    latest_point_time: 1_786_384_800,
    latest_point_time_text: "2026.08.10 05:00:00",
    latest_point_jst_time: 1_786_406_400,
    latest_point_jst_time_text: "2026.08.10 11:00:00",
    latest_point_rate: 1.23456,
    current_close: 1.235,
    stochastic_main_order_text: "SHORT>MIDDLE>LONG",
    stochastic_main_direction_text: "BUY",
    gmma_trend_count: 3,
    gmma_cross_count: 2,
    atr14_pips: 12.3,
    is_ema200_buy: isEma200Buy,
    is_ema200_sell: isEma200Sell,
  };
}

function observation(
  id: number,
  symbol: string,
  isGmoTarget: boolean,
  timeFrames: ObservationTimeFrame[] = [],
): ObservationListItem {
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
    time_frame_count: timeFrames.length,
    created_at: 1_786_406_401,
    created_at_text: "2026.08.10 11:00:01",
    time_frames: timeFrames,
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

  it("shows an independent EMA200 badge for every timeframe state", async () => {
    render(
      <ObservationTable
        available
        items={[
          observation(1, "USDJPY", true, [
            timeFrame("MN1", 0, false, false),
            timeFrame("W1", 1, true, false),
            timeFrame("D1", 2, false, true),
            timeFrame("H4", 3, false, false),
            timeFrame("H1", 4, true, true),
          ]),
        ]}
        loading={false}
        onOpenDetail={vi.fn()}
        onSort={vi.fn()}
        order="desc"
        sort="anchor_jst_time"
      />,
    );

    expect(await screen.findByLabelText("EMA200判定 対象外。MN1は計算を省略"))
      .toHaveTextContent("EMA200 SKIP");
    expect(screen.getByLabelText("EMA200判定 BUY")).toHaveTextContent("EMA200 ↑ BUY");
    expect(screen.getByLabelText("EMA200判定 SELL")).toHaveTextContent("EMA200 ↓ SELL");
    expect(screen.getByLabelText("EMA200判定 NONE")).toHaveTextContent("EMA200 NONE");
    expect(screen.getByLabelText("EMA200判定 異常。BUYとSELLが同時に記録されています"))
      .toHaveTextContent("EMA200 異常");
  });
});
