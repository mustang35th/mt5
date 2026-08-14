import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { AlertTimeFrame } from "../api/types";
import { AlertDetailDrawer } from "./AlertDetailDrawer";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

function errorResponse(message: string): Response {
  return {
    ok: false,
    status: 500,
    json: async () => ({ error: message }),
  } as Response;
}

function detailPayload(alertId = 74) {
  return {
    alert: {
      id: alertId,
      run_id: 3,
      symbol_name: alertId === 74 ? "AUDUSD" : "USDJPY",
      is_gmo_target: alertId === 74,
      side: "BUY",
      current_bar_time_text: "2026.07.30 19:00:00",
      alert_title: "test <img onerror=alert(1)>",
      jst_time_text: "2026.07.31 01:00:00",
      server_time_text: "2026.07.30 19:00:00",
      reference_price: 0,
      is_stop_loss_available: false,
      stop_loss: 0,
      risk_pips: 50,
      h1_structure_rank: "S",
      is_h1_structure_late: false,
      strategy: "MTF_3in3",
      signal_count: 1,
      entry_count: 1,
      is_judge: true,
      is_entry_count_match: true,
      is_entry_evaluated: true,
      is_entry_wave: true,
      is_ema200_distance_within: true,
      is_alert: true,
      is_entry: true,
      entry_result: "ENTRY",
      current_elliot_label: "3-3-1",
      close_ema200_diff_pips: 10,
      max_close_ema200_diff_pips: 25,
      spread_pips: 1.2,
      currency_strength_status: 0,
      is_currency_strength_available: false,
      long_medium_rank_difference: 5,
      medium_short_rank_difference: -3,
      market_signal_key: `market-${alertId}`,
      alert_text: "<script>alert('x')</script>",
      is_w1_aligned: null,
      w1_confirmation_mode: "OBSERVE_ONLY",
      w1_confirmation_state: "UNAVAILABLE",
      is_w1_confirmation_available: false,
      is_w1_confirmation_valid: false,
      is_w1_direction_matched: false,
      w1_ema200_direction: "BUY",
      is_w1_ema200_matched: false,
      is_w1_confirmation_passed: false,
      is_w1_confirmation_legacy: false,
    },
    run: {
      id: 3,
      source_mode: "TESTER",
      program_version: "1.21",
      tester_model: "Open Prices only",
    },
    w1: null,
  };
}

function timeFrame(
  id: number,
  label: string,
  order: number,
  overrides: Partial<AlertTimeFrame> = {},
): AlertTimeFrame {
  return {
    id,
    time_frame_text: label,
    time_frame_order: order,
    is_current_time_frame: label === "H1",
    buy_sell_label: "BUY",
    is_wave_confirmed: label === "MN1",
    is_wave_motive: true,
    is_wave_uptrend: false,
    wave_trend_label: "▼",
    latest_wave_index: 3,
    point_count: 2,
    latest_elliot_label: "3",
    latest_sub_elliot_label: "iii",
    stochastic_main_order_text: "BUY",
    stochastic_main_direction_text: "BUY",
    gmma_trend_count: 3,
    gmma_cross_count: -2,
    is_ema200_available: true,
    is_ema200_buy: false,
    is_ema200_sell: false,
    atr14_pips: 10,
    is_fibo_expansion_available: false,
    distance_to_fe2000_pips: 0,
    current_close: 1.23456,
    ...overrides,
  };
}

function point(id: number, timeFrame: string, order: number, pointOrder: number) {
  return {
    id,
    time_frame_text: timeFrame,
    time_frame_order: order,
    point_order: pointOrder,
    bar_time_text: `2026.01.0${id} 00:00:00`,
    rate: 1.2 + id / 100,
    is_peak: true,
    elliot_label: "3-3-1",
    sub_elliot_label: "iii",
    pips_diff: 0,
    is_fibonacci_available: false,
    fibonacci_percent: 0,
    is_fibonacci_expansion_available: false,
    fibonacci_expansion_percent: 0,
    is_latest: id === 1,
    is_signal_reference: id === 1,
    is_added_point: false,
    is_correct: false,
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.classList.remove("drawer-open");
});

describe("AlertDetailDrawer", () => {
  it("loads the three detail APIs and renders analysis and wave data without treating zero as missing", async () => {
    const timeFrames = [
      timeFrame(1, "MN1", 0),
      timeFrame(2, "W1", 1, { is_ema200_sell: true }),
      timeFrame(3, "D1", 2, { is_ema200_buy: true, is_ema200_sell: true }),
      timeFrame(4, "H4", 3),
      timeFrame(5, "H1", 4, { is_ema200_available: false }),
    ];
    const points = [point(1, "MN1", 0, 0), point(2, "H1", 4, 0)];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/74") return jsonResponse(detailPayload());
      if (path.endsWith("/timeframes")) return jsonResponse({ items: timeFrames, count: timeFrames.length });
      if (path.endsWith("/points")) return jsonResponse({ items: points, count: points.length });
      throw new Error(`unexpected path: ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    const onClose = vi.fn();
    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);

    expect(await screen.findByRole("heading", { name: "AUDUSD BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(screen.getByText("UNAVAILABLE / 取得不可")).toBeInTheDocument();
    expect(screen.getByText("mode: 記録のみ")).toBeInTheDocument();
    expect(screen.getByText("不通過（記録のみ・エントリー制限なし）")).toBeInTheDocument();
    expect(screen.getByLabelText("GMO取引 対象")).toBeInTheDocument();
    expect(screen.getAllByText("▼ DOWN / 下降")).toHaveLength(5);
    expect(screen.getAllByText("▼3.iii")).toHaveLength(5);
    expect(screen.getByText("0.00000")).toBeInTheDocument();
    expect(screen.getByText(/SL — \/ Risk 50.0 pips/)).toBeInTheDocument();
    expect(screen.getAllByText("trend +3 / cross -2")).toHaveLength(5);
    expect(screen.getByText("+5 / -3")).toBeInTheDocument();
    expect(screen.getAllByText("未取得").length).toBeGreaterThan(0);
    const wavePointContainer = screen.getByRole("group", { name: "時間足別最新Waveポイント" });
    const pointGroups = Array.from(wavePointContainer.querySelectorAll(".wave-point-timeframe-group"));
    expect(pointGroups.map((group) => group.querySelector("h4 > span")?.textContent)).toEqual(["MN1", "W1", "D1", "H4", "H1"]);
    expect(pointGroups.map((group) => group.querySelector(".wave-point-timeframe-count")?.textContent)).toEqual([
      "1件",
      "0件",
      "0件",
      "0件",
      "1件",
    ]);
    expect(within(wavePointContainer).getAllByRole("group").map((group) => group.getAttribute("aria-label"))).toEqual([
      "MN1 最新Waveポイント（1件）",
      "W1 最新Waveポイント（0件）",
      "D1 最新Waveポイント（0件）",
      "H4 最新Waveポイント（0件）",
      "H1 最新Waveポイント（1件）",
    ]);
    expect(pointGroups.slice(0, 4).every((group) => !group.hasAttribute("open"))).toBe(true);
    expect(pointGroups[4]).toHaveAttribute("open");
    expect(within(wavePointContainer).queryByRole("region", { name: "MN1 最新Waveポイントグリッド" })).not.toBeInTheDocument();
    const h1PointGrid = await within(wavePointContainer).findByRole("region", { name: "H1 最新Waveポイントグリッド" });
    const disclosureCases = [
      { label: "判定情報", content: screen.getByText("Strategy") },
      { label: "時間足別 Elliott スナップショット", content: screen.getAllByRole("article")[0] },
      { label: "最新Waveポイント（2件）", content: wavePointContainer },
    ];
    const alertText = screen.getByText("<script>alert('x')</script>");
    const alertTextSummary = screen.getByText("アラート本文").closest("summary");
    const alertTextDisclosure = alertTextSummary?.closest("details");
    expect(alertTextDisclosure).not.toHaveAttribute("open");
    expect(alertText).not.toBeVisible();
    const openAllButton = screen.getByRole("button", { name: "すべて開く" });
    expect(openAllButton).toHaveAttribute(
      "aria-controls",
      "alertDetail74Judgement alertDetail74TimeFrames alertDetail74WavePoints alertDetail74Text alertDetail74WavePoints0MN1 alertDetail74WavePoints1W1 alertDetail74WavePoints2D1 alertDetail74WavePoints3H4 alertDetail74WavePoints4H1",
    );
    expect(openAllButton).not.toHaveAttribute("aria-expanded");
    fireEvent.click(openAllButton);
    await waitFor(() => {
      expect(alertTextDisclosure).toHaveAttribute("open");
      expect(alertText).toBeVisible();
      expect(pointGroups.every((group) => group.hasAttribute("open"))).toBe(true);
    });
    expect(screen.getByRole("button", { name: "すべて閉じる" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "詳細を閉じる" })).toHaveFocus();
    disclosureCases.forEach(({ label, content }) => {
      const summary = screen.getByText(label).closest("summary");
      const disclosure = summary?.closest("details");
      expect(disclosure).toHaveAttribute("open");
      expect(content).toBeVisible();
      summary?.focus();
      fireEvent.click(summary as HTMLElement);
      expect(disclosure).not.toHaveAttribute("open");
      expect(content).not.toBeVisible();
      expect(summary).toHaveFocus();
      fireEvent.click(summary as HTMLElement);
      expect(disclosure).toHaveAttribute("open");
      expect(content).toBeVisible();
    });
    const cards = screen.getAllByRole("article");
    expect(cards).toHaveLength(5);
    expect(cards.map((card) => card.querySelector(".timeframe-header strong")?.textContent)).toEqual([
      "MN1",
      "W1",
      "D1",
      "H4",
      "H1",
    ]);
    const mn1Card = screen.getByRole("article", { name: "MN1 時間足スナップショット" });
    const w1Card = screen.getByRole("article", { name: "W1 時間足スナップショット" });
    const d1Card = screen.getByRole("article", { name: "D1 時間足スナップショット" });
    const h4Card = screen.getByRole("article", { name: "H4 時間足スナップショット" });
    const h1Card = screen.getByRole("article", {
      name: "H1 時間足スナップショット（現在足）",
    });
    expect(within(mn1Card).getByLabelText(/EMA200判定 対象外/))
      .toHaveTextContent("EMA200 SKIP");
    const w1RawEmaBadge = within(w1Card).getByLabelText("EMA200判定 SELL");
    expect(w1RawEmaBadge).toHaveTextContent("EMA200 ↓ SELL");
    expect(w1RawEmaBadge.closest(".timeframe-header")).toBeInTheDocument();
    expect(within(d1Card).getByLabelText(/BUYとSELLが同時/))
      .toHaveTextContent("EMA200 異常");
    expect(within(h4Card).getByLabelText("EMA200判定 NONE"))
      .toHaveTextContent("EMA200 NONE");
    expect(within(h1Card).getByLabelText("EMA200判定 記録なし"))
      .toHaveTextContent("EMA200 記録なし");
    expect(h1Card).toHaveAttribute("aria-current", "true");
    expect(within(h1Card).getByText("現在足")).toBeInTheDocument();
    expect(cards.slice(0, 4).every((card) => !card.hasAttribute("aria-current"))).toBe(true);
    const heroEmaGroup = screen.getByRole("group", { name: "H1 現在足 EMA200" });
    expect(heroEmaGroup).toHaveAttribute("aria-current", "true");
    expect(heroEmaGroup.closest(".detail-hero")).toBeInTheDocument();
    expect(within(heroEmaGroup).getByText("H1 現在足")).toBeInTheDocument();
    expect(within(heroEmaGroup).getByLabelText("EMA200判定 記録なし"))
      .toHaveAttribute("title", "EMA200判定 記録なし");
    const w1ConfirmationDirection = screen.getByText("W1確認 EMA200方向")
      .closest(".detail-field");
    const w1ConfirmationMatched = screen.getByText("W1確認 EMA200一致")
      .closest(".detail-field");
    expect(w1ConfirmationDirection).toHaveTextContent("BUY");
    expect(w1ConfirmationMatched).toHaveTextContent("いいえ");
    expect(screen.queryByText("W1 EMA200方向")).not.toBeInTheDocument();
    expect(screen.queryByText("W1 EMA200一致")).not.toBeInTheDocument();
    expect(screen.queryByText("EMA200方向")).not.toBeInTheDocument();
    expect(h1PointGrid.querySelector("table")).toBeNull();
    expect(h1PointGrid.querySelector(".ag-layout-auto-height")).toBeInTheDocument();
    expect(h1PointGrid.querySelector('[aria-label="H1 最新Waveポイント"]')).toBeInTheDocument();
    expect(within(h1PointGrid).getAllByRole("columnheader")).toHaveLength(10);
    expect(within(h1PointGrid).queryByRole("columnheader", { name: "TF" })).not.toBeInTheDocument();
    expect(within(h1PointGrid).getByRole("columnheader", { name: "Server時刻" })).toBeInTheDocument();
    expect(within(h1PointGrid).getByText("2026.01.02 00:00:00")).toBeInTheDocument();
    expect(within(h1PointGrid).queryByText("2026.01.01 00:00:00")).not.toBeInTheDocument();

    const mn1Summary = pointGroups[0].querySelector("summary");
    const mn1PointGrid = await within(wavePointContainer).findByRole("region", { name: "MN1 最新Waveポイントグリッド" });
    expect(await within(mn1PointGrid).findByText("2026.01.01 00:00:00")).toBeInTheDocument();
    expect(within(mn1PointGrid).queryByText("2026.01.02 00:00:00")).not.toBeInTheDocument();
    expect(within(mn1PointGrid).getByText("最新・基準").closest(".ag-row")).toHaveClass(
      "point-latest",
      "point-reference",
    );
    expect(within(h1PointGrid).getByText("2026.01.02 00:00:00").closest(".ag-row")).not.toHaveClass(
      "point-latest",
      "point-reference",
    );

    expect(within(pointGroups[1] as HTMLElement).getByText("保存されたポイントはありません。")).toBeVisible();
    expect(within(pointGroups[1] as HTMLElement).queryByRole("region")).not.toBeInTheDocument();
    mn1Summary?.focus();
    fireEvent.click(mn1Summary as HTMLElement);
    await waitFor(() => {
      expect(pointGroups[0]).not.toHaveAttribute("open");
      expect(mn1PointGrid).not.toBeVisible();
    });
    expect(screen.getByRole("button", { name: "すべて開く" })).toBeInTheDocument();
    expect(mn1Summary).toHaveFocus();
    fireEvent.click(mn1Summary as HTMLElement);
    await waitFor(() => {
      expect(pointGroups[0]).toHaveAttribute("open");
      expect(mn1PointGrid).toBeVisible();
    });
    expect(screen.getByRole("button", { name: "すべて閉じる" })).toBeInTheDocument();
    const pointGrid = h1PointGrid;
    const closeAllButton = await screen.findByRole("button", { name: "すべて閉じる" });
    closeAllButton.focus();
    fireEvent.click(closeAllButton);
    await waitFor(() => {
      disclosureCases.forEach(({ label, content }) => {
        expect(screen.getByText(label).closest("details")).not.toHaveAttribute("open");
        expect(content).not.toBeVisible();
      });
      expect(alertTextDisclosure).not.toHaveAttribute("open");
      expect(alertText).not.toBeVisible();
      expect(pointGroups.every((group) => !group.hasAttribute("open"))).toBe(true);
    });
    const reopenAllButton = screen.getByRole("button", { name: "すべて開く" });
    expect(reopenAllButton).toHaveFocus();
    expect(pointGrid).toBeInTheDocument();
    fireEvent.click(reopenAllButton);
    await waitFor(() => {
      disclosureCases.forEach(({ label, content }) => {
        expect(screen.getByText(label).closest("details")).toHaveAttribute("open");
        expect(content).toBeVisible();
      });
      expect(alertTextDisclosure).toHaveAttribute("open");
      expect(alertText).toBeVisible();
      expect(pointGroups.every((group) => group.hasAttribute("open"))).toBe(true);
    });
    expect(screen.getByRole("button", { name: "すべて閉じる" })).toHaveFocus();
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(onClose).not.toHaveBeenCalled();
    expect(document.querySelector("img")).toBeNull();
    expect(document.querySelector("script:not([type='module'])")).toBeNull();
  });

  it("keeps point-only timeframes and sorts their points by point order", async () => {
    const timeFrames = [timeFrame(5, "H1", 4)];
    const points = [point(3, "M5", 5, 1), point(4, "M5", 5, 0)];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/77") return jsonResponse(detailPayload(77));
      if (path.endsWith("/timeframes")) return jsonResponse({ items: timeFrames, count: timeFrames.length });
      if (path.endsWith("/points")) return jsonResponse({ items: points, count: points.length });
      throw new Error(`unexpected path: ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<AlertDetailDrawer alertId={77} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "USDJPY BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    const wavePointContainer = screen.getByRole("group", { name: "時間足別最新Waveポイント" });
    const pointGroups = within(wavePointContainer).getAllByRole("group");
    expect(pointGroups.map((group) => group.getAttribute("aria-label"))).toEqual([
      "H1 最新Waveポイント（0件）",
      "M5 最新Waveポイント（2件）",
    ]);
    expect(pointGroups[0]).toHaveAttribute("open");
    expect(pointGroups[1]).not.toHaveAttribute("open");

    fireEvent.click(pointGroups[1].querySelector("summary") as HTMLElement);
    const m5PointGrid = await within(wavePointContainer).findByRole("region", { name: "M5 最新Waveポイントグリッド" });
    const earlierOrderPoint = await within(m5PointGrid).findByText("2026.01.04 00:00:00");
    const laterOrderPoint = within(m5PointGrid).getByText("2026.01.03 00:00:00");
    expect(Number(earlierOrderPoint.compareDocumentPosition(laterOrderPoint))
      & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("uses the M5 current snapshot for the hero without marking H1 as current", async () => {
    const timeFrames = [
      timeFrame(5, "H1", 4, {
        is_current_time_frame: false,
        is_ema200_sell: true,
      }),
      timeFrame(6, "M5", 5, {
        is_current_time_frame: true,
        is_ema200_buy: true,
      }),
    ];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/78") return jsonResponse(detailPayload(78));
      if (path.endsWith("/timeframes")) {
        return jsonResponse({ items: timeFrames, count: timeFrames.length });
      }
      if (path.endsWith("/points")) return jsonResponse({ items: [], count: 0 });
      throw new Error(`unexpected path: ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    const view = render(<AlertDetailDrawer alertId={78} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", {
      name: "USDJPY BUY / 2026.07.30 19:00:00",
    })).toBeInTheDocument();
    const heroEmaGroup = screen.getByRole("group", { name: "M5 現在足 EMA200" });
    expect(heroEmaGroup).toHaveAttribute("aria-current", "true");
    expect(heroEmaGroup.closest(".detail-hero")).toBeInTheDocument();
    expect(within(heroEmaGroup).getByText("M5 現在足")).toBeInTheDocument();
    expect(within(heroEmaGroup).getByLabelText("EMA200判定 BUY"))
      .toHaveTextContent("EMA200 ↑ BUY");
    const h1Card = screen.getByRole("article", { name: "H1 時間足スナップショット" });
    const m5Card = screen.getByRole("article", {
      name: "M5 時間足スナップショット（現在足）",
    });
    expect(within(h1Card).getByLabelText("EMA200判定 SELL"))
      .toHaveTextContent("EMA200 ↓ SELL");
    expect(h1Card).not.toHaveAttribute("aria-current");
    expect(within(h1Card).queryByText("現在足")).not.toBeInTheDocument();
    expect(within(m5Card).getByLabelText("EMA200判定 BUY"))
      .toHaveTextContent("EMA200 ↑ BUY");
    expect(m5Card).toHaveAttribute("aria-current", "true");
    expect(within(m5Card).getByText("現在足")).toBeInTheDocument();
    expect(view.container.querySelectorAll(".timeframe-card[aria-current='true']"))
      .toHaveLength(1);
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("toggles only the available sections when the alert text is empty", async () => {
    const payload = detailPayload(76);
    payload.alert.alert_text = "";
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/76") return jsonResponse(payload);
      if (path.endsWith("/timeframes")) return jsonResponse({ items: [], count: 0 });
      if (path.endsWith("/points")) return jsonResponse({ items: [], count: 0 });
      throw new Error(`unexpected path: ${path}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<AlertDetailDrawer alertId={76} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "USDJPY BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    const closeAllButton = screen.getByRole("button", { name: "すべて閉じる" });
    expect(closeAllButton).toHaveAttribute(
      "aria-controls",
      "alertDetail76Judgement alertDetail76TimeFrames alertDetail76WavePoints",
    );
    expect(screen.queryByText("アラート本文")).not.toBeInTheDocument();
    fireEvent.click(closeAllButton);
    await waitFor(() => {
      expect(screen.getByText("判定情報").closest("details")).not.toHaveAttribute("open");
      expect(screen.getByText("時間足別 Elliott スナップショット").closest("details")).not.toHaveAttribute("open");
      expect(screen.getByText("最新Waveポイント（0件）").closest("details")).not.toHaveAttribute("open");
    });
    expect(screen.getByRole("button", { name: "すべて開く" })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("aborts stale requests and keeps the newest alert detail", async () => {
    let resolveOld!: (response: Response) => void;
    const oldPromise = new Promise<Response>((resolve) => {
      resolveOld = resolve;
    });
    const oldSignals: AbortSignal[] = [];
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input);
      if (path.includes("/74")) {
        if (init?.signal) oldSignals.push(init.signal);
        return oldPromise;
      }
      if (path === "/api/alerts/75") return Promise.resolve(jsonResponse(detailPayload(75)));
      if (path.endsWith("/timeframes")) return Promise.resolve(jsonResponse({ items: [], count: 0 }));
      if (path.endsWith("/points")) return Promise.resolve(jsonResponse({ items: [], count: 0 }));
      return Promise.reject(new Error(`unexpected path: ${path}`));
    });
    vi.stubGlobal("fetch", fetchMock);

    const view = render(<AlertDetailDrawer alertId={74} onClose={vi.fn()} />);
    view.rerender(<AlertDetailDrawer alertId={75} onClose={vi.fn()} />);

    expect(await screen.findByRole("heading", { name: "USDJPY BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    expect(await screen.findByText("保存されたポイントはありません。")).toBeInTheDocument();
    expect(oldSignals).toHaveLength(3);
    oldSignals.forEach((signal) => expect(signal.aborted).toBe(true));
    resolveOld(jsonResponse(detailPayload(74)));
    await waitFor(() => expect(screen.queryByText("AUDUSD BUY / 2026.07.30 19:00:00")).not.toBeInTheDocument());
  });

  it("closes on cancel and an outside pointer action", () => {
    const onClose = vi.fn();
    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);
    const dialog = screen.getByRole("dialog") as HTMLDialogElement;
    fireEvent(dialog, new Event("cancel", { bubbles: false, cancelable: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
    vi.spyOn(dialog, "getBoundingClientRect").mockReturnValue({
      left: 100,
      right: 900,
      top: 0,
      bottom: 800,
      width: 800,
      height: 800,
      x: 100,
      y: 0,
      toJSON: () => ({}),
    });
    fireEvent.click(dialog, { clientX: 10, clientY: 100, detail: 0 });
    expect(onClose).toHaveBeenCalledTimes(1);
    fireEvent.click(dialog, { clientX: 10, clientY: 100, detail: 1 });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it("shows a detail error without disabling the close action", async () => {
    const onClose = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/alerts/74") return errorResponse("detail failed");
      return jsonResponse({ items: [], count: 0 });
    }));

    render(<AlertDetailDrawer alertId={74} onClose={onClose} />);
    expect(await screen.findByRole("alert")).toHaveTextContent("detail failed");
    fireEvent.click(screen.getByRole("button", { name: "詳細を閉じる" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
