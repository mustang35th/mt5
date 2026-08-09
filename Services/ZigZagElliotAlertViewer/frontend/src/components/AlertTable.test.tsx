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
  beforeEach(() => {
    localStorage.clear();
  });

  it("renders W1 alignment as a three-state value and escapes DB text", async () => {
    const onOpenDetail = vi.fn();
    render(
      <AlertTable
        items={[alertWithAlignment(1, true), alertWithAlignment(2, false), alertWithAlignment(3, null)]}
        loading={false}
        highlightedIds={new Set([2])}
        sort="jst_time"
        order="desc"
        onSort={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );
    expect(await screen.findByText("一致")).toBeInTheDocument();
    expect(screen.getByText("不一致")).toBeInTheDocument();
    expect(screen.getByText("不明")).toBeInTheDocument();
    expect(screen.getAllByText("LIVE")).toHaveLength(3);
    expect(screen.getAllByText("test <img onerror=alert(1)>")).toHaveLength(3);
    expect(document.querySelector("img")).toBeNull();
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
    const symbolHeader = screen.getByRole("columnheader", { name: "通貨" });
    fireEvent.click(within(symbolHeader).getByRole("button", { name: "通貨" }));
    expect(onSort).toHaveBeenCalledWith("symbol_name");

    fireEvent.focus(symbolHeader);
    fireEvent.keyDown(symbolHeader, { key: "Enter" });
    expect(onSort).toHaveBeenCalledTimes(2);
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
    expect(GRID_PINNED_LEFT_COLUMN_IDS).toEqual(["jst_time", "symbol_name", "side"]);
    expect(GRID_PINNED_RIGHT_COLUMN_IDS).toEqual(["detail"]);

    fireEvent.click(screen.getByRole("button", { name: "コンパクト表示" }));
    expect(firstView.container.querySelector(".alert-grid")).toHaveClass("density-compact");
    expect(firstView.container.querySelector(".ag-header")).toHaveStyle({ height: "29px" });
    expect(localStorage.getItem(GRID_DENSITY_STORAGE_KEY)).toBe("compact");

    fireEvent.click(screen.getByRole("button", { name: "表示列" }));
    const w1ColumnItem = await screen.findByRole("menuitemcheckbox", { name: /W1一致/ });
    expect(w1ColumnItem).toHaveAttribute("aria-checked", "true");
    fireEvent.click(w1ColumnItem);
    await waitFor(() => {
      expect(screen.queryByRole("columnheader", { name: "W1一致" })).not.toBeInTheDocument();
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
      expect(screen.queryByRole("columnheader", { name: "W1一致" })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: "列を初期化" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "列を初期化" }));
    await waitFor(() => {
      expect(localStorage.getItem(GRID_LAYOUT_STORAGE_KEY)).toBeNull();
    });
    fireEvent.click(screen.getByRole("button", { name: "表示列" }));
    expect(await screen.findByRole("menuitemcheckbox", { name: /W1一致/ }))
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
      expect(view.container.querySelector<HTMLElement>('[col-id="entry_result"]'))
        .toHaveStyle({ width: "165px" });
    });
    const initialColumnIds = Array.from(
      view.container.querySelectorAll<HTMLElement>('[role="columnheader"][col-id]'),
      (element) => element.getAttribute("col-id"),
    );
    expect(initialColumnIds.indexOf("entry_result"))
      .toBeLessThan(initialColumnIds.indexOf("source_mode"));

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
