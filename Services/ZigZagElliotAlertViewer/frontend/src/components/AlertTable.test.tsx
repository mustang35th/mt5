import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AlertListItem } from "../api/types";
import {
  GRID_DENSITY_STORAGE_KEY,
  GRID_LAYOUT_STORAGE_KEY,
  writeGridColumnLayout,
} from "../lib/gridPreferences";
import {
  AlertTable,
  GRID_PINNED_LEFT_COLUMN_IDS,
  GRID_PINNED_RIGHT_COLUMN_IDS,
} from "./AlertTable";

function alertWithAlignment(id: number, aligned: boolean | null): AlertListItem {
  return {
    id,
    run_id: 3,
    source_mode: "LIVE",
    jst_time_text: "2026.07.31 01:00:00",
    server_time_text: "2026.07.30 19:00:00",
    symbol_name: "AUDUSD",
    is_gmo_target: id !== 2,
    time_frame_text: "H1",
    strategy: "MTF_3in3",
    side: "BUY",
    ...(id === 1 ? {
      is_ema200_available: true,
      is_ema200_buy: true,
      is_ema200_sell: false,
      mn1_is_ema200_available: true,
      mn1_is_ema200_buy: false,
      mn1_is_ema200_sell: false,
      w1_is_ema200_available: true,
      w1_is_ema200_buy: false,
      w1_is_ema200_sell: true,
      d1_is_ema200_available: true,
      d1_is_ema200_buy: false,
      d1_is_ema200_sell: true,
      h4_is_ema200_available: true,
      h4_is_ema200_buy: false,
      h4_is_ema200_sell: false,
      h1_is_ema200_available: true,
      h1_is_ema200_buy: true,
      h1_is_ema200_sell: false,
    } : id === 2 ? {
      is_ema200_available: true,
      is_ema200_buy: false,
      is_ema200_sell: true,
    } : {}),
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
    w1_confirmation_mode: id === 3 ? "OFF" : "DIRECTION_OR_EMA200",
    w1_confirmation_state: id === 1 ? "STRONG" : id === 2 ? "EMA_CONFLICT" : "NOT_EVALUATED",
    is_w1_confirmation_available: id !== 3,
    is_w1_confirmation_valid: id !== 3,
    is_w1_direction_matched: id === 1 || id === 2,
    w1_ema200_direction: id === 1 ? "BUY" : id === 2 ? "SELL" : "NONE",
    is_w1_ema200_matched: id === 1,
    is_w1_confirmation_passed: id === 1 || id === 2,
    is_w1_confirmation_legacy: id === 3,
    h1_direction_alignment_mode: id === 1
      ? "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
      : id === 2
        ? "MN1_TO_H1_OBSERVE"
        : "D1_TO_H1",
    h1_direction_alignment_state: id === 1
      ? "EMA200_FALLBACK_BUY"
      : id === 2
        ? "MN1_MISMATCH"
        : "NOT_EVALUATED",
    is_h1_direction_alignment_available: id !== 3,
    is_h1_direction_alignment_valid: id !== 3,
    h1_direction_alignment_direction: id === 3 ? "NONE" : "BUY",
    is_h1_mn1_direction_matched: false,
    is_h1_w1_direction_matched: id === 1 || id === 2,
    is_h1_direction_alignment_passed: id === 1,
    is_h1_direction_alignment_legacy: id === 3,
  };
}

describe("AlertTable", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("renders compact W1 confirmation states and escapes DB text", async () => {
    const onOpenComparison = vi.fn();
    const onOpenDetail = vi.fn();
    const onSort = vi.fn();
    const view = render(
      <AlertTable
        items={[alertWithAlignment(1, true), alertWithAlignment(2, false), alertWithAlignment(3, null)]}
        loading={false}
        highlightedIds={new Set([2])}
        sort="jst_time"
        order="desc"
        onSort={onSort}
        onOpenComparison={onOpenComparison}
        onOpenDetail={onOpenDetail}
      />,
    );
    expect(await screen.findByText("両方一致")).toBeInTheDocument();
    expect(screen.getByText("方向一致・EMA逆")).toBeInTheDocument();
    expect(screen.getAllByText("Legacy / 未記録")).toHaveLength(2);
    expect(screen.getAllByText("OR")).toHaveLength(2);
    expect(screen.getByText("EMA200補完BUY")).toHaveClass("good");
    expect(screen.getByText("W1～H1一致＋MN1またはW1 EMA200・必須"))
      .toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "H1方向ルール" })).toBeInTheDocument();
    expect(screen.getByText("STRONG / EMA BUY")).toBeInTheDocument();
    expect(screen.getByText("EMA_CONFLICT / EMA SELL")).toBeInTheDocument();
    expect(screen.getByText("方向 不明 / EMA NONE")).toBeInTheDocument();
    expect(view.container.querySelectorAll(".w1-confirmation-badges-compact")).toHaveLength(3);
    const confirmationHeader = screen.getByRole("columnheader", { name: "W1確認" });
    fireEvent.click(within(confirmationHeader).getByRole("button", { name: "W1確認" }));
    expect(onSort).toHaveBeenCalledWith("w1_confirmation_state");
    const sideHeader = screen.getByRole("columnheader", { name: "方向" });
    fireEvent.click(within(sideHeader).getByRole("button", { name: "方向" }));
    expect(onSort).toHaveBeenLastCalledWith("side");
    expect(screen.getAllByText("LIVE")).toHaveLength(3);
    expect(screen.getAllByLabelText("アラート方向 BUY")).toHaveLength(3);
    const firstRow = view.container.querySelector<HTMLElement>('.ag-row[row-id="1"]');
    const secondRow = view.container.querySelector<HTMLElement>('.ag-row[row-id="2"]');
    const thirdRow = view.container.querySelector<HTMLElement>('.ag-row[row-id="3"]');
    expect(firstRow).not.toBeNull();
    expect(secondRow).not.toBeNull();
    expect(thirdRow).not.toBeNull();
    expect(within(firstRow?.querySelector('.ag-cell[col-id="side"]') as HTMLElement)
      .getByLabelText("EMA200判定 BUY")).toHaveTextContent("EMA200 ↑ BUY");
    expect(within(secondRow?.querySelector('.ag-cell[col-id="side"]') as HTMLElement)
      .getByLabelText("EMA200判定 SELL")).toHaveTextContent("EMA200 ↓ SELL");
    expect(within(thirdRow?.querySelector('.ag-cell[col-id="side"]') as HTMLElement)
      .getByLabelText("EMA200判定 記録なし")).toHaveTextContent("EMA200 記録なし");
    expect(screen.getAllByLabelText("GMO取引 対象")).toHaveLength(2);
    expect(screen.queryByLabelText("GMO取引 対象外")).not.toBeInTheDocument();
    expect(screen.getAllByText("test <img onerror=alert(1)>")).toHaveLength(3);
    expect(document.querySelector("img")).toBeNull();
    expect(screen.getByRole("columnheader", { name: "時間足" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "操作" })).toBeInTheDocument();
    await waitFor(() => {
      const timeFrameCells = view.container.querySelectorAll('.ag-cell[col-id="time_frame"]');
      expect(timeFrameCells).toHaveLength(3);
      for (const cell of timeFrameCells) expect(cell).toHaveTextContent("H1");
      const symbolCells = view.container.querySelectorAll('.ag-cell[col-id="symbol_name"]');
      for (const cell of symbolCells) {
        expect(cell).toHaveTextContent("Run 3");
        expect(cell).not.toHaveTextContent("H1");
      }
    });
    const mn1Cell = firstRow?.querySelector<HTMLElement>('.ag-cell[col-id="tf_mn1"]');
    const w1Cell = firstRow?.querySelector<HTMLElement>('.ag-cell[col-id="tf_w1"]');
    const d1Cell = firstRow?.querySelector<HTMLElement>('.ag-cell[col-id="tf_d1"]');
    const h4Cell = firstRow?.querySelector<HTMLElement>('.ag-cell[col-id="tf_h4"]');
    const h1Cell = firstRow?.querySelector<HTMLElement>('.ag-cell[col-id="tf_h1"]');
    expect(within(mn1Cell as HTMLElement).getByLabelText("MN1 分析方向 BUY"))
      .toBeInTheDocument();
    expect(within(mn1Cell as HTMLElement).getByLabelText(/EMA200判定 対象外/))
      .toHaveTextContent("EMA200 SKIP");
    expect(within(w1Cell as HTMLElement).getByLabelText("EMA200判定 SELL"))
      .toHaveTextContent("EMA200 ↓ SELL");
    expect(within(d1Cell as HTMLElement).getByLabelText("EMA200判定 SELL"))
      .toHaveTextContent("EMA200 ↓ SELL");
    expect(within(h4Cell as HTMLElement).getByLabelText("EMA200判定 NONE"))
      .toHaveTextContent("EMA200 NONE");
    const currentTimeFrameGroup = within(h1Cell as HTMLElement).getByRole("group", {
      name: "H1 分析方向とEMA200判定（現在のアラート時間足）",
    });
    expect(currentTimeFrameGroup).toHaveClass("current-time-frame-analysis-cell");
    expect(currentTimeFrameGroup).toHaveAttribute("aria-current", "true");
    expect(within(currentTimeFrameGroup).getByText("現在足")).toBeInTheDocument();
    expect(within(currentTimeFrameGroup).getByLabelText("H1 分析方向 BUY"))
      .toBeInTheDocument();
    expect(within(currentTimeFrameGroup).getByLabelText("EMA200判定 BUY"))
      .toBeInTheDocument();
    await waitFor(() => expect(document.querySelector('.ag-row[row-id="2"]')).toHaveClass("alert-row-new"));
    const detailButton = screen.getAllByRole("button", { name: "AUDUSD BUY 2026.07.31 01:00:00 の詳細を表示" })[0];
    fireEvent.click(detailButton);
    expect(onOpenDetail).toHaveBeenCalledWith(1, detailButton);
    const comparisonButton = screen.getAllByRole("button", {
      name: "AUDUSD BUY 2026.07.31 01:00:00 のTIMEFRAME COMPARISONを表示",
    })[0];
    fireEvent.click(comparisonButton);
    expect(onOpenComparison).toHaveBeenCalledWith(1, comparisonButton);
  });

  it("requests server sorting without changing the current page row order", async () => {
    const onSort = vi.fn();
    const first = { ...alertWithAlignment(11, true), symbol_name: "USDJPY" };
    const second = { ...alertWithAlignment(12, false), symbol_name: "AUDUSD" };
    const view = render(
      <AlertTable
        items={[first, second]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={onSort}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    const dateHeader = await screen.findByRole("columnheader", { name: /JST日時/ });
    expect(view.container.querySelector(".ag-layout-normal")).toBeInTheDocument();
    expect(view.container.querySelector(".ag-layout-auto-height")).toBeNull();
    expect(view.container.querySelector(".ag-header")).toHaveStyle({ height: "33px" });
    expect(dateHeader).toHaveAttribute("aria-sort", "descending");
    const timeFrameHeader = screen.getByRole("columnheader", { name: "時間足" });
    fireEvent.click(within(timeFrameHeader).getByRole("button", { name: "時間足" }));
    expect(onSort).toHaveBeenCalledWith("time_frame");
    const symbolHeader = screen.getByRole("columnheader", { name: "通貨" });
    fireEvent.click(within(symbolHeader).getByRole("button", { name: "通貨" }));
    expect(onSort).toHaveBeenCalledWith("symbol_name");

    fireEvent.focus(symbolHeader);
    fireEvent.keyDown(symbolHeader, { key: "Enter" });
    expect(onSort).toHaveBeenCalledTimes(3);
    await waitFor(() => {
      const rows = Array.from(view.container.querySelectorAll<HTMLElement>(".ag-row[row-id]"));
      expect(rows).toHaveLength(2);
      expect(rows[0]).toHaveTextContent("USDJPY");
      expect(rows[1]).toHaveTextContent("AUDUSD");
    });
  });

  it("persists density and column visibility while keeping fixed columns pinned", async () => {
    const firstView = render(
      <AlertTable
        items={[alertWithAlignment(21, true)]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(firstView.container.querySelector('.ag-header-cell[col-id="jst_time"]'))
        .toBeInTheDocument();
    });
    expect(GRID_PINNED_LEFT_COLUMN_IDS).toEqual(["jst_time", "symbol_name", "time_frame", "side"]);
    expect(GRID_PINNED_RIGHT_COLUMN_IDS).toEqual(["detail"]);

    fireEvent.click(screen.getByRole("button", { name: "コンパクト表示" }));
    expect(firstView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
    expect(firstView.container.querySelector(".ag-header")).toHaveStyle({ height: "29px" });
    expect(localStorage.getItem(GRID_DENSITY_STORAGE_KEY)).toBe("compact");

    fireEvent.click(screen.getByRole("button", { name: "表示列" }));
    for (const timeFrame of ["MN1", "W1", "D1", "H4", "H1"]) {
      expect(await screen.findByRole("menuitemcheckbox", {
        name: new RegExp(`${timeFrame} 方向 / EMA200`),
      })).toHaveAttribute("aria-checked", "true");
    }
    const w1TimeFrameColumnItem = await screen.findByRole("menuitemcheckbox", {
      name: /W1 方向 \/ EMA200/,
    });
    expect(w1TimeFrameColumnItem).toHaveAttribute("aria-checked", "true");
    fireEvent.click(w1TimeFrameColumnItem);
    await waitFor(() => {
      expect(screen.queryByRole("columnheader", { name: "W1" })).not.toBeInTheDocument();
      const storedText = localStorage.getItem(GRID_LAYOUT_STORAGE_KEY);
      expect(storedText).not.toBeNull();
      const stored = JSON.parse(storedText || "{}") as {
        columns?: Array<{ colId: string; hide: boolean }>;
      };
      expect(stored.columns?.find((column) => column.colId === "tf_w1")?.hide).toBe(true);
    });

    firstView.unmount();
    const restoredView = render(
      <AlertTable
        items={[alertWithAlignment(22, true)]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );
    await waitFor(() => {
      expect(restoredView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
      expect(screen.queryByRole("columnheader", { name: "W1" })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: "列を初期化" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "列を初期化" }));
    await waitFor(() => {
      expect(localStorage.getItem(GRID_LAYOUT_STORAGE_KEY)).toBeNull();
    });
    fireEvent.click(screen.getByRole("button", { name: "表示列" }));
    expect(await screen.findByRole("menuitemcheckbox", { name: /W1 方向 \/ EMA200/ }))
      .toHaveAttribute("aria-checked", "true");
    expect(restoredView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
  });

  it("restores column width and order without letting server sort reset them", async () => {
    writeGridColumnLayout(localStorage, [
      { colId: "jst_time", width: 190, hide: true },
      { colId: "symbol_name", width: 140, hide: false },
      { colId: "side", width: 90, hide: false },
      { colId: "entry_result", width: 165, hide: false },
      { colId: "tf_h1", width: 180, hide: false },
      { colId: "source_mode", width: 110, hide: false },
      { colId: "judgement", width: 300, hide: false },
      { colId: "h1_structure_rank", width: 145, hide: false },
      { colId: "time_frame_sides", width: 270, hide: false },
      { colId: "is_w1_aligned", width: 115, hide: false },
      { colId: "risk_pips", width: 135, hide: false },
      { colId: "detail", width: 90, hide: false },
    ]);
    const alert = alertWithAlignment(31, true);
    const view = render(
      <AlertTable
        items={[alert]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "列を初期化" })).toBeEnabled();
      expect(screen.getByRole("columnheader", { name: /JST日時/ })).toBeInTheDocument();
      expect(screen.getByRole("columnheader", { name: "時間足" })).toBeInTheDocument();
      expect(view.container.querySelector<HTMLElement>('[col-id="entry_result"]'))
        .toHaveStyle({ width: "165px" });
      expect(view.container.querySelector<HTMLElement>('[role="columnheader"][col-id="is_w1_aligned"]'))
        .toHaveStyle({ width: "210px" });
      const sideHeader = view.container.querySelector<HTMLElement>(
        '[role="columnheader"][col-id="side"]',
      );
      expect(Number.parseInt(sideHeader?.style.width || "0", 10)).toBeGreaterThanOrEqual(120);
      for (const colId of ["tf_mn1", "tf_w1", "tf_d1", "tf_h4", "tf_h1"]) {
        expect(view.container.querySelector<HTMLElement>(
          `[role="columnheader"][col-id="${colId}"]`,
        )).toHaveStyle({ width: "125px" });
      }
      expect(view.container.querySelector('[col-id="time_frame_sides"]')).not.toBeInTheDocument();
    });
    const initialColumnIds = Array.from(
      view.container.querySelectorAll<HTMLElement>('[role="columnheader"][col-id]'),
      (element) => element.getAttribute("col-id"),
    );
    expect(initialColumnIds.indexOf("entry_result"))
      .toBeLessThan(initialColumnIds.indexOf("source_mode"));
    expect(initialColumnIds.indexOf("symbol_name"))
      .toBeLessThan(initialColumnIds.indexOf("time_frame"));
    expect(initialColumnIds.indexOf("time_frame"))
      .toBeLessThan(initialColumnIds.indexOf("side"));
    const migratedTimeFrameColumnIds = ["tf_mn1", "tf_w1", "tf_d1", "tf_h4", "tf_h1"];
    expect(initialColumnIds.filter((colId) => migratedTimeFrameColumnIds.includes(colId || "")))
      .toEqual(migratedTimeFrameColumnIds);
    expect(initialColumnIds.indexOf("h1_structure_rank"))
      .toBeLessThan(initialColumnIds.indexOf("tf_mn1"));
    expect(initialColumnIds.indexOf("tf_h1"))
      .toBeLessThan(initialColumnIds.indexOf("is_w1_aligned"));
    const migratedStoredLayout = JSON.parse(
      localStorage.getItem(GRID_LAYOUT_STORAGE_KEY) || "{}",
    ) as { columns?: Array<{ colId: string; width: number; hide: boolean }> };
    expect(migratedStoredLayout.columns?.some(
      (column) => column.colId === "time_frame_sides",
    )).toBe(false);
    expect(migratedStoredLayout.columns?.filter(
      (column) => migratedTimeFrameColumnIds.includes(column.colId),
    )).toEqual(migratedTimeFrameColumnIds.map((colId) => ({
      colId,
      width: 125,
      hide: false,
    })));

    view.rerender(
      <AlertTable
        items={[alert]}
        loading={false}
        sort="symbol_name"
        order="desc"
        onSort={vi.fn()}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );
    await waitFor(() => {
      expect(view.container.querySelector<HTMLElement>('[col-id="entry_result"]'))
        .toHaveStyle({ width: "165px" });
      const updatedColumnIds = Array.from(
        view.container.querySelectorAll<HTMLElement>('[role="columnheader"][col-id]'),
        (element) => element.getAttribute("col-id"),
      );
      expect(updatedColumnIds.indexOf("entry_result"))
        .toBeLessThan(updatedColumnIds.indexOf("source_mode"));
    });
  });

  it("shows fixed higher-time-frame context without marking a current column for M5 alerts", async () => {
    const alert = { ...alertWithAlignment(41, true), time_frame_text: "M5" };
    const view = render(
      <AlertTable
        items={[alert]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenComparison={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByRole("columnheader", { name: "MN1" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "H1" })).toBeInTheDocument();
    expect(view.container.querySelectorAll(".time-frame-analysis-cell")).toHaveLength(5);
    expect(view.container.querySelector(".current-time-frame-analysis-cell")).toBeNull();
    expect(view.container.querySelector('[aria-current="true"]')).toBeNull();
    expect(screen.queryByText("現在足")).not.toBeInTheDocument();
  });
});
