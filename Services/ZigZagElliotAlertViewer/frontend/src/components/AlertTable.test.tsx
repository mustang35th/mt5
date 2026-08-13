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
  };
}

describe("AlertTable", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("renders compact W1 confirmation states and escapes DB text", async () => {
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
        onOpenDetail={onOpenDetail}
      />,
    );
    expect(await screen.findByText("両方一致")).toBeInTheDocument();
    expect(screen.getByText("方向一致・EMA逆")).toBeInTheDocument();
    expect(screen.getByText("Legacy / 未記録")).toBeInTheDocument();
    expect(screen.getAllByText("OR")).toHaveLength(2);
    expect(screen.getByText("STRONG / EMA BUY")).toBeInTheDocument();
    expect(screen.getByText("EMA_CONFLICT / EMA SELL")).toBeInTheDocument();
    expect(screen.getByText("方向 不明 / EMA NONE")).toBeInTheDocument();
    expect(view.container.querySelectorAll(".w1-confirmation-badges-compact")).toHaveLength(3);
    const confirmationHeader = screen.getByRole("columnheader", { name: "W1確認" });
    fireEvent.click(within(confirmationHeader).getByRole("button", { name: "W1確認" }));
    expect(onSort).toHaveBeenCalledWith("w1_confirmation_state");
    expect(screen.getAllByText("LIVE")).toHaveLength(3);
    expect(screen.getAllByLabelText("GMO取引 対象")).toHaveLength(2);
    expect(screen.queryByLabelText("GMO取引 対象外")).not.toBeInTheDocument();
    expect(screen.getAllByText("test <img onerror=alert(1)>")).toHaveLength(3);
    expect(document.querySelector("img")).toBeNull();
    expect(screen.getByRole("columnheader", { name: "時間足" })).toBeInTheDocument();
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
    await waitFor(() => expect(document.querySelector('.ag-row[row-id="2"]')).toHaveClass("alert-row-new"));
    const detailButton = screen.getAllByRole("button", { name: "AUDUSD BUY 2026.07.31 01:00:00 の詳細を表示" })[0];
    fireEvent.click(detailButton);
    expect(onOpenDetail).toHaveBeenCalledWith(1, detailButton);
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
    const w1ColumnItem = await screen.findByRole("menuitemcheckbox", { name: /W1確認/ });
    expect(w1ColumnItem).toHaveAttribute("aria-checked", "true");
    fireEvent.click(w1ColumnItem);
    await waitFor(() => {
      expect(screen.queryByRole("columnheader", { name: "W1確認" })).not.toBeInTheDocument();
      const storedText = localStorage.getItem(GRID_LAYOUT_STORAGE_KEY);
      expect(storedText).not.toBeNull();
      const stored = JSON.parse(storedText || "{}") as {
        columns?: Array<{ colId: string; hide: boolean }>;
      };
      expect(stored.columns?.find((column) => column.colId === "is_w1_aligned")?.hide).toBe(true);
    });

    firstView.unmount();
    const restoredView = render(
      <AlertTable
        items={[alertWithAlignment(22, true)]}
        loading={false}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );
    await waitFor(() => {
      expect(restoredView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
      expect(screen.queryByRole("columnheader", { name: "W1確認" })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: "列を初期化" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "列を初期化" }));
    await waitFor(() => {
      expect(localStorage.getItem(GRID_LAYOUT_STORAGE_KEY)).toBeNull();
    });
    fireEvent.click(screen.getByRole("button", { name: "表示列" }));
    expect(await screen.findByRole("menuitemcheckbox", { name: /W1確認/ }))
      .toHaveAttribute("aria-checked", "true");
    expect(restoredView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
  });

  it("restores column width and order without letting server sort reset them", async () => {
    writeGridColumnLayout(localStorage, [
      { colId: "jst_time", width: 190, hide: true },
      { colId: "symbol_name", width: 140, hide: false },
      { colId: "side", width: 90, hide: false },
      { colId: "entry_result", width: 165, hide: false },
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

    view.rerender(
      <AlertTable
        items={[alert]}
        loading={false}
        sort="symbol_name"
        order="desc"
        onSort={vi.fn()}
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
});
