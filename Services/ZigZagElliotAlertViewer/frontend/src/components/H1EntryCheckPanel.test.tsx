import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type {
  AlertDetail,
  ObservationDetailTimeFrame,
} from "../api/types";
import {
  buildH1EntryCheckSnapshot,
  H1EntryCheckPanel,
  type H1EntryCheckItem,
} from "./H1EntryCheckPanel";

function timeFrame(
  fromTimeFrameText: string,
  fromOverrides: Partial<ObservationDetailTimeFrame> = {},
): ObservationDetailTimeFrame {
  const orderByTimeFrame: Record<string, number> = {
    MN1: 1,
    W1: 2,
    D1: 3,
    H4: 4,
    H1: 5,
  };
  return {
    id: orderByTimeFrame[fromTimeFrameText],
    time_frame_order: orderByTimeFrame[fromTimeFrameText],
    time_frame_text: fromTimeFrameText,
    is_buy: true,
    is_wave_uptrend: true,
    latest_elliot_label: "3",
    gmma_trend_count: 5,
    gmma_cross_count: 36,
    is_ema200_buy: true,
    is_ema200_sell: false,
    ema200_close_diff_pips: 46.9,
    ...fromOverrides,
  } as ObservationDetailTimeFrame;
}

function passingBuyTimeFrames(): ObservationDetailTimeFrame[] {
  return [
    timeFrame("MN1"),
    timeFrame("W1"),
    timeFrame("D1"),
    timeFrame("H4"),
    timeFrame("H1"),
  ];
}

function item(
  fromItems: readonly H1EntryCheckItem[],
  fromId: string,
): H1EntryCheckItem {
  const result = fromItems.find((candidate) => candidate.id === fromId);
  if (!result) throw new Error(`Missing check item: ${fromId}`);
  return result;
}

describe("buildH1EntryCheckSnapshot", () => {
  it("marks determinable BUY conditions as OK but keeps the overall unknown", () => {
    const snapshot = buildH1EntryCheckSnapshot(passingBuyTimeFrames(), 1.2);

    expect(snapshot.direction).toBe("BUY");
    expect(snapshot.overallStatus).toBe("判定不能");
    expect(snapshot.overallReason).toBe("必須データ不足: 通貨強弱");
    expect(snapshot.items.map((check) => check.id)).toEqual([
      "currency_strength",
      "spread",
      "h1_wave_direction",
      "d1_h4_h1_direction",
      "mn1_w1_direction",
      "h1_elliott_wave",
      "h1_gmma_trend",
      "h1_gmma_cross",
      "h1_ema200",
      "h4_ema200",
      "w1_confirmation",
      "signal_entry_count",
      "h1_display_wave_scope",
      "h1_ema200_distance",
    ]);
    expect(snapshot.items.filter((check) => (
      check.required && check.status !== "不明"
    )).every((check) => check.status === "OK")).toBe(true);
    expect(item(snapshot.items, "h4_ema200")).toMatchObject({
      status: "不明",
      actual: "BUY（一致）",
      required: true,
    });
    for (const checkId of [
      "currency_strength",
      "mn1_w1_direction",
      "w1_confirmation",
      "signal_entry_count",
    ]) {
      expect(item(snapshot.items, checkId).status).toBe("不明");
    }
  });

  it("uses the first NG in actual processing order as the Snapshot result", () => {
    const timeFrames = passingBuyTimeFrames();
    const h1 = timeFrames.find((candidate) => candidate.time_frame_text === "H1");
    if (!h1) throw new Error("H1 fixture missing");
    h1.is_wave_uptrend = false;
    h1.latest_elliot_label = "2";

    const snapshot = buildH1EntryCheckSnapshot(timeFrames, 3.1);

    expect(item(snapshot.items, "spread").status).toBe("NG");
    expect(item(snapshot.items, "h1_wave_direction").status).toBe("NG");
    expect(item(snapshot.items, "h1_elliott_wave").status).toBe("NG");
    expect(snapshot.overallStatus).toBe("NG");
    expect(snapshot.overallReason).toBe("最初のNG: Spread");
  });

  it("returns 判定不能 when a required Snapshot value is missing and no known NG exists", () => {
    const snapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames().filter((candidate) => candidate.time_frame_text !== "H1"),
      1.2,
    );

    expect(snapshot.direction).toBeNull();
    expect(snapshot.overallStatus).toBe("判定不能");
    expect(snapshot.overallReason).toBe("必須データ不足: 通貨強弱");
    expect(item(snapshot.items, "h1_wave_direction").status).toBe("不明");
    expect(item(snapshot.items, "h1_ema200_distance").status).toBe("不明");
  });

  it("applies strict EMA200 flags and keeps H1 EMA200 distance as reference", () => {
    const sellTimeFrames = [
      timeFrame("D1", { is_buy: false }),
      timeFrame("H4", {
        is_buy: false,
        is_ema200_buy: false,
        is_ema200_sell: true,
      }),
      timeFrame("H1", {
        is_buy: false,
        is_wave_uptrend: false,
        latest_elliot_label: "5",
        gmma_trend_count: -2,
        gmma_cross_count: -1,
        is_ema200_buy: true,
        is_ema200_sell: true,
        ema200_close_diff_pips: -50,
      }),
    ];

    const snapshot = buildH1EntryCheckSnapshot(sellTimeFrames, 3);

    expect(snapshot.direction).toBe("SELL");
    expect(item(snapshot.items, "spread").status).toBe("OK");
    expect(item(snapshot.items, "h1_gmma_trend").status).toBe("OK");
    expect(item(snapshot.items, "h1_gmma_cross").status).toBe("NG");
    expect(item(snapshot.items, "h1_ema200")).toMatchObject({
      actual: "INVALID",
      status: "NG",
    });
    expect(item(snapshot.items, "h1_ema200_distance")).toMatchObject({
      actual: "50.0 pips",
      expected: "現行H1ではエントリー条件に使用しない",
      status: "参考",
      required: false,
    });
    expect(snapshot.overallReason).toBe("最初のNG: H1 GMMA cross");
  });

  it("prioritizes saved Alert decisions for overall, modes, count, and distance", () => {
    const savedDecision = {
      is_entry: false,
      entry_result: "EMA200_DISTANCE_REJECTED",
      side: "BUY",
      spread_pips: 1.4,
      is_currency_strength_enabled: true,
      currency_strength_status: 3,
      is_currency_strength_available: true,
      currency_strength_target_m5_bar_time: 1_785_438_000,
      currency_strength_m5_bar_time: 1_785_438_000,
      long_medium_rank_difference: 5,
      medium_short_rank_difference: 3,
      h1_direction_alignment_mode: "MN1_TO_H1_REQUIRED",
      h1_direction_alignment_state: "MN1_MISMATCH",
      is_h1_direction_alignment_passed: false,
      is_h1_direction_alignment_legacy: false,
      w1_confirmation_mode: "DIRECTION_AND_EMA200",
      w1_confirmation_state: "REJECT",
      w1_ema200_direction: "SELL",
      is_w1_confirmation_passed: false,
      is_w1_confirmation_legacy: false,
      signal_count: 2,
      entry_count: 2,
      is_entry_count_match: true,
      is_entry_evaluated: true,
      close_ema200_diff_pips: 51,
      max_close_ema200_diff_pips: 50,
      is_ema200_distance_within: false,
    } as AlertDetail;

    const snapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames(),
      8,
      savedDecision,
    );

    expect(snapshot.source).toBe("SAVED");
    expect(snapshot.overallStatus).toBe("NG");
    expect(snapshot.overallReason)
      .toBe("Entry NG: H1 EMA200距離（EMA200_DISTANCE_REJECTED）");
    expect(item(snapshot.items, "spread")).toMatchObject({
      actual: "1.4 pips",
      status: "OK",
    });
    expect(item(snapshot.items, "currency_strength")).toMatchObject({
      actual: "順位差 +5 / +3 / M5 EXACT",
      status: "OK",
    });
    expect(item(snapshot.items, "mn1_w1_direction")).toMatchObject({
      status: "NG",
      required: true,
    });
    expect(item(snapshot.items, "w1_confirmation")).toMatchObject({
      status: "NG",
      required: true,
    });
    expect(item(snapshot.items, "signal_entry_count")).toMatchObject({
      actual: "2 / 2（評価済み）",
      status: "OK",
    });
    expect(item(snapshot.items, "h1_display_wave_scope")).toMatchObject({
      actual: "制限OFFまたは通過",
      status: "OK",
    });
    expect(item(snapshot.items, "h1_ema200_distance")).toMatchObject({
      actual: "51.0 pips",
      expected: "50.0 pips以下（保存時判定）",
      status: "NG",
    });
  });

  it("rejects stale currency strength and keeps missing Legacy M5 times unknown", () => {
    const savedDecision = {
      is_entry: false,
      entry_result: "CURRENCY_STRENGTH_REJECTED",
      side: "BUY",
      spread_pips: 1,
      is_currency_strength_enabled: true,
      currency_strength_status: 3,
      is_currency_strength_available: true,
      currency_strength_target_m5_bar_time: 1_785_438_000,
      currency_strength_m5_bar_time: 1_785_437_700,
      long_medium_rank_difference: 5,
      medium_short_rank_difference: 3,
    } as AlertDetail;

    const staleSnapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames(),
      1,
      savedDecision,
    );
    expect(item(staleSnapshot.items, "currency_strength")).toMatchObject({
      actual: "順位差 +5 / +3 / M5 STALE",
      status: "NG",
      required: true,
    });

    const legacySnapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames(),
      1,
      {
        ...savedDecision,
        currency_strength_target_m5_bar_time: undefined,
        currency_strength_m5_bar_time: undefined,
      },
    );
    expect(item(legacySnapshot.items, "currency_strength")).toMatchObject({
      actual: "順位差 +5 / +3 / M5時刻 未記録",
      status: "不明",
      required: true,
    });

    const zeroSentinelSnapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames(),
      1,
      {
        ...savedDecision,
        currency_strength_target_m5_bar_time: 0,
        currency_strength_m5_bar_time: 0,
      },
    );
    expect(item(zeroSentinelSnapshot.items, "currency_strength"))
      .toMatchObject({
        actual: "順位差 +5 / +3 / M5時刻 未記録",
        status: "不明",
        required: true,
      });
  });

  it("distinguishes disabled and observe-only saved modes from failures", () => {
    const savedDecision = {
      is_entry: true,
      entry_result: "ENTRY",
      spread_pips: 1,
      is_currency_strength_enabled: false,
      h1_direction_alignment_mode: "D1_TO_H1",
      h1_direction_alignment_state: "D1_TO_H1",
      is_h1_direction_alignment_passed: true,
      is_h1_direction_alignment_legacy: false,
      w1_confirmation_mode: "OBSERVE_ONLY",
      w1_confirmation_state: "REJECT",
      w1_ema200_direction: "SELL",
      is_w1_confirmation_passed: false,
      is_w1_confirmation_legacy: false,
      signal_count: 1,
      entry_count: 1,
      is_entry_count_match: true,
      is_entry_evaluated: true,
      close_ema200_diff_pips: 51,
      max_close_ema200_diff_pips: 50,
      is_ema200_distance_within: false,
    } as AlertDetail;

    const snapshot = buildH1EntryCheckSnapshot(
      passingBuyTimeFrames(),
      1,
      savedDecision,
    );

    expect(snapshot.overallStatus).toBe("OK");
    expect(item(snapshot.items, "currency_strength").status).toBe("対象外");
    expect(item(snapshot.items, "h1_display_wave_scope").status).toBe("OK");
    expect(item(snapshot.items, "mn1_w1_direction").status).toBe("対象外");
    expect(item(snapshot.items, "w1_confirmation")).toMatchObject({
      status: "参考",
      required: false,
    });
    expect(item(snapshot.items, "h1_ema200_distance")).toMatchObject({
      actual: "51.0 pips",
      expected: "現行H1ではエントリー条件に使用しない",
      status: "参考",
      required: false,
    });
  });
});

describe("H1EntryCheckPanel", () => {
  it("renders the overall result and accessible status for every condition", () => {
    render(
      <H1EntryCheckPanel
        spreadPips={1.2}
        timeFrames={passingBuyTimeFrames()}
      />,
    );

    expect(screen.getByRole("heading", {
      name: "ZigZagElliot H1エントリー条件",
    })).toBeInTheDocument();
    expect(screen.getByLabelText("総合判定 判定不能"))
      .toHaveTextContent("総合 判定不能");
    expect(screen.getByText("Snapshot推定")).toBeInTheDocument();
    const disclosure = screen.getByText("条件を表示").closest("details");
    expect(disclosure).not.toHaveAttribute("open");
    fireEvent.click(disclosure?.querySelector("summary") as HTMLElement);
    expect(disclosure).toHaveAttribute("open");
    const table = screen.getByRole("table", {
      name: "H1エントリー条件チェック",
    });
    expect(within(table).getByLabelText("H1 GMMA trend OK"))
      .toHaveClass("badge", "good");
    expect(within(table).getByLabelText("H4 EMA200 不明"))
      .toHaveClass("h1-entry-check-status-unknown");
    expect(within(table).getByLabelText("通貨強弱 不明"))
      .toHaveClass("h1-entry-check-status-unknown");
    expect(within(table).getAllByRole("row")).toHaveLength(18);
  });
});
