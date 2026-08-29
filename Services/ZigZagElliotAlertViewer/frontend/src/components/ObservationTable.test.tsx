import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { ObservationListItem, ObservationTimeFrame } from "../api/types";
import { ObservationTable, observationFullAlignmentSide } from "./ObservationTable";

function timeFrame(
  label: string,
  order: number,
  isEma200Buy: boolean,
  isEma200Sell: boolean,
  isBuy = true,
): ObservationTimeFrame {
  return {
    id: 100 + order,
    observation_id: 1,
    time_frame: order + 1,
    time_frame_text: label,
    time_frame_order: order,
    is_anchor_time_frame: label === "H1",
    is_buy: isBuy,
    buy_sell_label: isBuy ? "BUY" : "SELL",
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
    latest_point_is_added: false,
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

function fullAlignmentTimeFrames(side: "BUY" | "SELL"): ObservationTimeFrame[] {
  const isBuy = side === "BUY";
  return ["W1", "D1", "H4", "H1"].map((label, order) => (
    timeFrame(label, order, isBuy, !isBuy, isBuy)
  ));
}

function observation(
  id: number,
  symbol: string,
  isGmoTarget: boolean,
  timeFrames: ObservationTimeFrame[] = [],
  spreadPips: number | null = 1.2,
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
    spread_pips: spreadPips,
    pip_size: 0.0001,
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
  it("shows recorded, legacy, and zero spread values", async () => {
    render(
      <ObservationTable
        available
        grouped={false}
        items={[
          observation(1, "USDJPY", true, [], 1.2),
          observation(2, "USDCAD", false, [], null),
          observation(3, "EURUSD", false, [], 0),
        ]}
        loading={false}
        onOpenDetail={vi.fn()}
        onSort={vi.fn()}
        order="desc"
        sort="anchor_jst_time"
      />,
    );

    expect(await screen.findByText("1.2 pips")).toBeInTheDocument();
    expect(screen.getByText("未記録")).toBeInTheDocument();
    expect(screen.getByText("0.0 pips")).toBeInTheDocument();
  });

  it("shows GMO target state next to each symbol", async () => {
    render(
      <ObservationTable
        available
        grouped={false}
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
        grouped={false}
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

  it("shows FULL BUY and FULL SELL only for strict W1-to-H1 and EMA200 alignment", async () => {
    const fullBuy = observation(11, "AUDUSD", true, fullAlignmentTimeFrames("BUY"));
    const fullSell = observation(12, "EURUSD", true, fullAlignmentTimeFrames("SELL"));
    const mixedDirection = observation(13, "GBPUSD", true, fullAlignmentTimeFrames("BUY"));
    mixedDirection.time_frames[1] = {
      ...mixedDirection.time_frames[1],
      is_buy: false,
      buy_sell_label: "SELL",
    };
    const emaNone = observation(14, "NZDUSD", true, fullAlignmentTimeFrames("BUY"));
    emaNone.time_frames[2] = {
      ...emaNone.time_frames[2],
      is_ema200_buy: false,
      is_ema200_sell: false,
    };
    const emaBoth = observation(15, "USDCAD", true, fullAlignmentTimeFrames("SELL"));
    emaBoth.time_frames[3] = {
      ...emaBoth.time_frames[3],
      is_ema200_buy: true,
      is_ema200_sell: true,
    };
    const missingH1 = observation(
      16,
      "USDCHF",
      true,
      fullAlignmentTimeFrames("BUY").filter((item) => item.time_frame_text !== "H1"),
    );

    expect(observationFullAlignmentSide(fullBuy)).toBe("BUY");
    expect(observationFullAlignmentSide(fullSell)).toBe("SELL");
    expect(observationFullAlignmentSide(mixedDirection)).toBeNull();
    expect(observationFullAlignmentSide(emaNone)).toBeNull();
    expect(observationFullAlignmentSide(emaBoth)).toBeNull();
    expect(observationFullAlignmentSide(missingH1)).toBeNull();

    render(
      <ObservationTable
        available
        grouped={false}
        items={[fullBuy, fullSell, mixedDirection, emaNone, emaBoth, missingH1]}
        loading={false}
        onOpenDetail={vi.fn()}
        onSort={vi.fn()}
        order="desc"
        sort="anchor_jst_time"
      />,
    );

    expect(await screen.findByLabelText("W1～H1＋EMA200 完全一致 BUY"))
      .toHaveTextContent("FULL BUY");
    expect(screen.getByLabelText("W1～H1＋EMA200 完全一致 SELL"))
      .toHaveTextContent("FULL SELL");
    expect(screen.getAllByText(/^FULL (BUY|SELL)$/)).toHaveLength(2);
  });

  it("shows one row for a consecutive FULL signal with its span and boundaries", async () => {
    const onOpenDetail = vi.fn();
    const signal = {
      ...observation(21, "AUDUSD", true, []),
      signal_rule_version: "FULL_ALIGNMENT_EPISODE_V1" as const,
      signal_side: "BUY" as const,
      signal_start_observation_id: 21,
      signal_end_observation_id: 25,
      signal_end_anchor_bar_time: 1_786_392_000,
      signal_end_anchor_bar_time_text: "2026.08.10 07:00:00",
      signal_end_anchor_jst_time: 1_786_413_600,
      signal_end_anchor_jst_time_text: "2026.08.10 13:00:00",
      signal_h1_count: 3,
      signal_is_left_censored: true,
      signal_is_right_censored: false,
      signal_has_data_gap_before: false,
      signal_has_data_gap_after: true,
    };

    render(
      <ObservationTable
        available
        grouped
        items={[signal]}
        loading={false}
        onOpenDetail={onOpenDetail}
        onSort={vi.fn()}
        order="desc"
        sort="anchor_jst_time"
      />,
    );

    expect(await screen.findByRole("region", { name: "連続H1シグナル検索結果" }))
      .toBeInTheDocument();
    expect(await screen.findByText("3 H1")).toBeInTheDocument();
    expect(screen.getByText("開始JST")).toBeInTheDocument();
    expect(screen.getByText("開始Spread")).toBeInTheDocument();
    expect(screen.getByText("継続")).toBeInTheDocument();
    expect(screen.getByText("→ 2026.08.10 13:00:00 / 3 H1")).toBeInTheDocument();
    expect(screen.getByText("左打切り")).toBeInTheDocument();
    expect(screen.getByText("欠損後")).toBeInTheDocument();
    expect(screen.getByLabelText("W1～H1＋EMA200 完全一致 BUY"))
      .toHaveTextContent("FULL BUY");

    fireEvent.click(screen.getByRole("button", {
      name: "AUDUSD JST 2026.08.10 11:00:00 のH1推移詳細を表示",
    }));
    expect(onOpenDetail).toHaveBeenCalledWith(21, expect.any(HTMLButtonElement));
  });
});
