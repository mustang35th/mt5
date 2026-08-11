import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import {
  ClientSideRowModelModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  ColumnAutoSizeModule,
  RowStyleModule,
  themeQuartz,
  type ColDef,
  type ColumnMovedEvent,
  type ColumnResizedEvent,
  type ColumnVisibleEvent,
  type GridApi,
  type GridReadyEvent,
  type ICellRendererParams,
  type RowClassParams,
} from "ag-grid-community";
import { AgGridReact, type CustomHeaderProps } from "ag-grid-react";
import { useMediaQuery } from "@mui/material";
import type { AlertListItem, AlertSort, SortOrder } from "../api/types";
import { displayValue, formatNumber, sideClass } from "../lib/format";
import {
  clearGridColumnLayout,
  type GridColumnLayoutItem,
  type GridDensity,
  readGridColumnLayout,
  readGridDensity,
  writeGridColumnLayout,
  writeGridDensity,
} from "../lib/gridPreferences";
import { GridControls, type GridColumnOption } from "./GridControls";

interface AlertTableProps {
  items: AlertListItem[];
  loading: boolean;
  highlightedIds?: ReadonlySet<number>;
  sort: AlertSort;
  order: SortOrder;
  styleNonce?: string;
  gridControlsTarget?: HTMLElement | null;
  onSort: (sort: AlertSort) => void;
  onOpenDetail: (alertId: number, fromTrigger: HTMLButtonElement) => void;
}

interface ServerSortHeaderParameters {
  sortKey: AlertSort;
  activeSort: AlertSort;
  order: SortOrder;
  onSort: (sort: AlertSort) => void;
}

type ServerSortHeaderProps = CustomHeaderProps<AlertListItem> & ServerSortHeaderParameters;

const GRID_MODULES = [
  ClientSideRowModelModule,
  ColumnApiModule,
  ColumnAutoSizeModule,
  RowStyleModule,
];

const GRID_COLUMN_IDS = [
  "jst_time",
  "symbol_name",
  "time_frame",
  "side",
  "source_mode",
  "judgement",
  "h1_structure_rank",
  "time_frame_sides",
  "is_w1_aligned",
  "risk_pips",
  "entry_result",
  "detail",
] as const;

const GRID_COLUMN_ID_SET: ReadonlySet<string> = new Set(GRID_COLUMN_IDS);
export const GRID_PINNED_LEFT_COLUMN_IDS = [
  "jst_time",
  "symbol_name",
  "time_frame",
  "side",
] as const;
export const GRID_PINNED_RIGHT_COLUMN_IDS = ["detail"] as const;
const FIXED_COLUMN_IDS: ReadonlySet<string> = new Set([
  ...GRID_PINNED_LEFT_COLUMN_IDS,
  ...GRID_PINNED_RIGHT_COLUMN_IDS,
]);
const TIME_FRAME_COLUMN_WIDTH = 80;

const CONFIGURABLE_COLUMNS: ReadonlyArray<Omit<GridColumnOption, "visible">> = [
  { colId: "source_mode", label: "実行モード" },
  { colId: "judgement", label: "判定" },
  { colId: "h1_structure_rank", label: "構造・波動" },
  { colId: "time_frame_sides", label: "MN1 → H1 分析方向" },
  { colId: "is_w1_aligned", label: "W1一致" },
  { colId: "risk_pips", label: "Risk / Spread" },
  { colId: "entry_result", label: "ENTRY" },
];

function includeTimeFrameColumn(
  fromLayout: GridColumnLayoutItem[],
): GridColumnLayoutItem[] {
  if (fromLayout.some((column) => column.colId === "time_frame")) return fromLayout;
  const symbolIndex = fromLayout.findIndex((column) => column.colId === "symbol_name");
  const insertIndex = symbolIndex < 0 ? fromLayout.length : symbolIndex + 1;
  const timeFrameColumn = {
    colId: "time_frame",
    width: TIME_FRAME_COLUMN_WIDTH,
    hide: false,
  };
  return [
    ...fromLayout.slice(0, insertIndex),
    timeFrameColumn,
    ...fromLayout.slice(insertIndex),
  ];
}

const alertGridTheme = themeQuartz
  .withPart(colorSchemeDarkBlue)
  .withParams({
    accentColor: "#59d8c2",
    backgroundColor: "#0b151c",
    borderColor: "#263946",
    dataBackgroundColor: "#0f1a22",
    fontFamily: "Segoe UI, Yu Gothic UI, Meiryo, sans-serif",
    fontSize: 12,
    foregroundColor: "#edf5f5",
    headerBackgroundColor: "#0b151c",
    headerTextColor: "#8ba0aa",
    rowHoverColor: "rgba(89, 216, 194, 0.055)",
    spacing: 6,
  });

function ServerSortHeader({
  displayName,
  eGridHeader,
  sortKey,
  activeSort,
  order,
  onSort,
}: ServerSortHeaderProps) {
  const active = activeSort === sortKey;
  const requestSort = useCallback(() => {
    onSort(sortKey);
  }, [onSort, sortKey]);

  useEffect(() => {
    eGridHeader.setAttribute(
      "aria-sort",
      active ? (order === "asc" ? "ascending" : "descending") : "none",
    );

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      event.stopPropagation();
      requestSort();
    }

    eGridHeader.addEventListener("keydown", handleKeyDown);
    return () => {
      eGridHeader.removeEventListener("keydown", handleKeyDown);
      eGridHeader.removeAttribute("aria-sort");
    };
  }, [active, eGridHeader, order, requestSort]);

  return (
    <button
      className={`server-sort-header${active ? ` active ${order}` : ""}`}
      tabIndex={-1}
      type="button"
      onClick={requestSort}
    >
      <span>{displayName}</span>
      {active && <span aria-hidden="true">{order === "asc" ? "↑" : "↓"}</span>}
    </button>
  );
}

function Badge({ text, variant = "neutral" }: { text: string; variant?: string }) {
  return <span className={`badge ${variant}`}>{text}</span>;
}

function TimeFrameSequence({ alert }: { alert: AlertListItem }) {
  const values: Array<[string, string | null]> = [
    ["MN1", alert.mn1_side],
    ["W1", alert.w1_side],
    ["D1", alert.d1_side],
    ["H4", alert.h4_side],
    ["H1", alert.h1_side],
  ];
  return (
    <div className="tf-sequence">
      {values.map(([timeFrame, side]) => {
        const normalized = String(side || "NONE").toUpperCase();
        return (
          <span className={`tf-chip ${sideClass(normalized)}`} key={timeFrame}>
            <small>{timeFrame}</small>
            <strong>{normalized === "NONE" ? "—" : normalized}</strong>
          </span>
        );
      })}
    </div>
  );
}

function AlignmentBadge({ alert }: { alert: AlertListItem }) {
  if (alert.is_w1_aligned === true) return <Badge text="一致" variant="good" />;
  if (alert.is_w1_aligned === false) return <Badge text="不一致" variant="warn" />;
  return <Badge text="不明" />;
}

function dataFrom(params: ICellRendererParams<AlertListItem>) {
  return params.data;
}

function DateCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="grid-cell-stack">
      <span className="date-main">{displayValue(alert.jst_time_text)}</span>
      <span className="date-sub">Server {displayValue(alert.server_time_text)}</span>
    </div>
  );
}

function SymbolCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="grid-cell-stack">
      <span className="symbol">{alert.symbol_name}</span>
      <span className="subtext">Run {alert.run_id}</span>
    </div>
  );
}

function TimeFrameCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return <Badge text={displayValue(alert.time_frame_text)} />;
}

function SourceModeCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return <Badge text={displayValue(alert.source_mode)} />;
}

function SideCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return <Badge text={alert.side} variant={sideClass(alert.side)} />;
}

function JudgementCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="grid-cell-stack grid-cell-wrap">
      <strong>{alert.strategy} {alert.signal_count}/{alert.entry_count}</strong>
      <span className="subtext">{displayValue(alert.alert_title)}</span>
    </div>
  );
}

function StructureCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="grid-cell-stack">
      <Badge text={`${displayValue(alert.h1_structure_rank)}${alert.is_h1_structure_late ? "-LATE" : ""}`} />
      <span className="subtext">wave {displayValue(alert.current_elliot_label)}</span>
    </div>
  );
}

function TimeFramesCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return <TimeFrameSequence alert={alert} />;
}

function AlignmentCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="grid-cell-stack">
      <AlignmentBadge alert={alert} />
      <span className="subtext">W1 {displayValue(alert.w1_side)}</span>
    </div>
  );
}

function RiskCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return (
    <div className="metric-stack">
      <span>{formatNumber(alert.risk_pips)} pips</span>
      <span className="subtext">spread {formatNumber(alert.spread_pips)} pips</span>
    </div>
  );
}

function EntryCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  return <Badge text={displayValue(alert.entry_result)} variant={alert.is_entry ? "good" : "neutral"} />;
}

function NoAlertsOverlay() {
  return (
    <div className="empty-state grid-empty-state">
      <strong>該当するアラートはありません</strong>
      <span>検索条件を変更してください。</span>
    </div>
  );
}

function sortHeaderParameters(
  sortKey: AlertSort,
  activeSort: AlertSort,
  order: SortOrder,
  onSort: (sort: AlertSort) => void,
): ServerSortHeaderParameters {
  return { sortKey, activeSort, order, onSort };
}

export function AlertTable({
  items,
  loading,
  highlightedIds,
  sort,
  order,
  styleNonce,
  gridControlsTarget,
  onSort,
  onOpenDetail,
}: AlertTableProps) {
  const gridApiRef = useRef<GridApi<AlertListItem> | null>(null);
  const columnLayoutReadyRef = useRef(false);
  const columnLayoutSaveTimerRef = useRef<number | null>(null);
  const wideGridLayout = useMediaQuery("(min-width: 761px)");
  const [density, setDensity] = useState<GridDensity>(() => readGridDensity(window.localStorage));
  const [gridReady, setGridReady] = useState(false);
  const [visibleColumns, setVisibleColumns] = useState<Record<string, boolean>>(() => (
    Object.fromEntries(GRID_COLUMN_IDS.map((colId) => [colId, true]))
  ));

  const syncColumnVisibility = useCallback((api: GridApi<AlertListItem>) => {
    const nextVisibility: Record<string, boolean> = {};
    for (const column of api.getColumnState()) {
      nextVisibility[column.colId] = column.hide !== true;
    }
    setVisibleColumns(nextVisibility);
  }, []);

  const applyFixedColumnPinning = useCallback((api: GridApi<AlertListItem>) => {
    api.setColumnsPinned(
      [...GRID_PINNED_LEFT_COLUMN_IDS],
      wideGridLayout ? "left" : null,
    );
    api.setColumnsPinned(
      [...GRID_PINNED_RIGHT_COLUMN_IDS],
      wideGridLayout ? "right" : null,
    );
  }, [wideGridLayout]);

  const scheduleColumnLayoutSave = useCallback((api: GridApi<AlertListItem>) => {
    if (!columnLayoutReadyRef.current) return;
    if (columnLayoutSaveTimerRef.current !== null) {
      window.clearTimeout(columnLayoutSaveTimerRef.current);
    }
    columnLayoutSaveTimerRef.current = window.setTimeout(() => {
      columnLayoutSaveTimerRef.current = null;
      if (!columnLayoutReadyRef.current || gridApiRef.current !== api) return;
      writeGridColumnLayout(
        window.localStorage,
        api.getColumnState().flatMap((column) => {
          if (typeof column.width !== "number" || !Number.isFinite(column.width)) return [];
          return [{
            colId: column.colId,
            width: column.width,
            hide: FIXED_COLUMN_IDS.has(column.colId) ? false : column.hide === true,
          }];
        }),
      );
      syncColumnVisibility(api);
    }, 0);
  }, [syncColumnVisibility]);

  const handleGridReady = useCallback((event: GridReadyEvent<AlertListItem>) => {
    gridApiRef.current = event.api;
    columnLayoutReadyRef.current = false;
    const storedLayout = readGridColumnLayout(window.localStorage, GRID_COLUMN_ID_SET);
    if (storedLayout !== null) {
      const restoredLayout = includeTimeFrameColumn(storedLayout);
      event.api.applyColumnState({
        state: restoredLayout.map((column) => ({
          ...column,
          hide: FIXED_COLUMN_IDS.has(column.colId) ? false : column.hide,
        })),
        applyOrder: true,
      });
    }
    event.api.setColumnsVisible([...FIXED_COLUMN_IDS], true);
    applyFixedColumnPinning(event.api);
    columnLayoutReadyRef.current = true;
    syncColumnVisibility(event.api);
    setGridReady(true);
  }, [applyFixedColumnPinning, syncColumnVisibility]);

  const handleColumnMoved = useCallback((event: ColumnMovedEvent<AlertListItem>) => {
    if (event.finished && event.source === "uiColumnMoved") scheduleColumnLayoutSave(event.api);
  }, [scheduleColumnLayoutSave]);

  const handleColumnResized = useCallback((event: ColumnResizedEvent<AlertListItem>) => {
    if (
      event.finished
      && (event.source === "uiColumnResized" || event.source === "autosizeColumns")
    ) {
      scheduleColumnLayoutSave(event.api);
    }
  }, [scheduleColumnLayoutSave]);

  const handleColumnVisible = useCallback((event: ColumnVisibleEvent<AlertListItem>) => {
    scheduleColumnLayoutSave(event.api);
  }, [scheduleColumnLayoutSave]);

  const changeDensity = useCallback((fromDensity: GridDensity) => {
    setDensity(fromDensity);
    writeGridDensity(window.localStorage, fromDensity);
  }, []);

  const toggleColumn = useCallback((fromColId: string, fromVisible: boolean) => {
    if (FIXED_COLUMN_IDS.has(fromColId)) return;
    gridApiRef.current?.setColumnsVisible([fromColId], fromVisible);
  }, []);

  const resetColumnLayout = useCallback(() => {
    const api = gridApiRef.current;
    if (api === null) return;
    if (columnLayoutSaveTimerRef.current !== null) {
      window.clearTimeout(columnLayoutSaveTimerRef.current);
      columnLayoutSaveTimerRef.current = null;
    }
    columnLayoutReadyRef.current = false;
    clearGridColumnLayout(window.localStorage);
    api.resetColumnState();
    api.setColumnsVisible([...GRID_COLUMN_IDS], true);
    applyFixedColumnPinning(api);
    columnLayoutReadyRef.current = true;
    syncColumnVisibility(api);
  }, [applyFixedColumnPinning, syncColumnVisibility]);

  useEffect(() => () => {
    if (columnLayoutSaveTimerRef.current !== null) {
      window.clearTimeout(columnLayoutSaveTimerRef.current);
    }
  }, []);

  useEffect(() => {
    const api = gridApiRef.current;
    if (api !== null) applyFixedColumnPinning(api);
  }, [applyFixedColumnPinning]);

  const columnOptions = useMemo<GridColumnOption[]>(() => (
    CONFIGURABLE_COLUMNS.map((column) => ({
      ...column,
      visible: visibleColumns[column.colId] !== false,
    }))
  ), [visibleColumns]);

  let gridHeaderHeight = density === "compact" ? 28 : 32;
  if (!wideGridLayout) gridHeaderHeight += 8;

  const getRowClass = useCallback((params: RowClassParams<AlertListItem>) => {
    if (params.data && highlightedIds?.has(params.data.id)) return "alert-row-new";
    return undefined;
  }, [highlightedIds]);

  const DetailCell = useCallback((params: ICellRendererParams<AlertListItem>) => {
    const alert = dataFrom(params);
    if (!alert) return null;
    return (
      <button
        aria-label={`${alert.symbol_name} ${alert.side} ${alert.jst_time_text} の詳細を表示`}
        className="secondary-button detail-open-button"
        type="button"
        onClick={(event) => onOpenDetail(alert.id, event.currentTarget)}
      >
        詳細
      </button>
    );
  }, [onOpenDetail]);

  const columnDefs = useMemo<ColDef<AlertListItem>[]>(() => [
    {
      colId: "jst_time",
      field: "jst_time_text",
      headerName: "JST日時",
      initialPinned: "left",
      initialWidth: 180,
      lockPinned: true,
      lockPosition: "left",
      suppressMovable: true,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("jst_time", sort, order, onSort),
      cellRenderer: DateCell,
    },
    {
      colId: "symbol_name",
      field: "symbol_name",
      headerName: "通貨",
      initialPinned: "left",
      initialWidth: 135,
      lockPinned: true,
      lockPosition: "left",
      suppressMovable: true,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("symbol_name", sort, order, onSort),
      cellRenderer: SymbolCell,
    },
    {
      colId: "time_frame",
      field: "time_frame_text",
      headerName: "時間足",
      initialPinned: "left",
      initialWidth: TIME_FRAME_COLUMN_WIDTH,
      minWidth: 72,
      lockPinned: true,
      lockPosition: "left",
      suppressMovable: true,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("time_frame", sort, order, onSort),
      cellRenderer: TimeFrameCell,
    },
    {
      colId: "side",
      field: "side",
      headerName: "方向",
      initialPinned: "left",
      initialWidth: 90,
      lockPinned: true,
      lockPosition: "left",
      suppressMovable: true,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("side", sort, order, onSort),
      cellRenderer: SideCell,
    },
    {
      colId: "source_mode",
      field: "source_mode",
      headerName: "実行モード",
      initialWidth: 110,
      cellRenderer: SourceModeCell,
    },
    {
      colId: "judgement",
      headerName: "判定",
      initialWidth: 300,
      minWidth: 220,
      cellRenderer: JudgementCell,
    },
    {
      colId: "h1_structure_rank",
      field: "h1_structure_rank",
      headerName: "構造・波動",
      initialWidth: 145,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("h1_structure_rank", sort, order, onSort),
      cellRenderer: StructureCell,
    },
    {
      colId: "time_frame_sides",
      headerName: "MN1 → H1 分析方向",
      initialWidth: 270,
      cellRenderer: TimeFramesCell,
    },
    {
      colId: "is_w1_aligned",
      field: "is_w1_aligned",
      headerName: "W1一致",
      initialWidth: 115,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("is_w1_aligned", sort, order, onSort),
      cellRenderer: AlignmentCell,
    },
    {
      colId: "risk_pips",
      field: "risk_pips",
      headerName: "Risk / Spread",
      initialWidth: 135,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("risk_pips", sort, order, onSort),
      cellRenderer: RiskCell,
    },
    {
      colId: "entry_result",
      field: "entry_result",
      headerName: "ENTRY",
      initialWidth: 105,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("entry_result", sort, order, onSort),
      cellRenderer: EntryCell,
    },
    {
      colId: "detail",
      headerName: "詳細",
      initialPinned: "right",
      initialWidth: 90,
      lockPinned: true,
      lockPosition: "right",
      suppressMovable: true,
      cellRenderer: DetailCell,
    },
  ], [DetailCell, onSort, order, sort]);

  const gridControls = (
    <GridControls
      columns={columnOptions}
      density={density}
      layoutReady={gridReady}
      onDensityChange={changeDensity}
      onResetLayout={resetColumnLayout}
      onToggleColumn={toggleColumn}
    />
  );
  let renderedGridControls: ReactNode = gridControls;
  if (gridControlsTarget === null) renderedGridControls = null;
  else if (gridControlsTarget !== undefined) {
    renderedGridControls = createPortal(gridControls, gridControlsTarget);
  }

  return (
    <div
      className="grid-view"
      role="region"
      aria-label="ZigZagElliotアラート検索結果"
      aria-busy={loading}
    >
      {renderedGridControls}
      <div className={`alert-grid density-${density}`}>
        <AgGridReact<AlertListItem>
          animateRows={false}
          columnDefs={columnDefs}
          defaultColDef={{
            filter: false,
            resizable: true,
            sortable: false,
            suppressHeaderMenuButton: true,
          }}
          domLayout="normal"
          ensureDomOrder
          getRowId={({ data }) => String(data.id)}
          getRowClass={getRowClass}
          headerHeight={gridHeaderHeight}
          maintainColumnOrder
          modules={GRID_MODULES}
          noRowsOverlayComponent={NoAlertsOverlay}
          onColumnMoved={handleColumnMoved}
          onColumnResized={handleColumnResized}
          onColumnVisible={handleColumnVisible}
          onGridPreDestroyed={() => {
            if (columnLayoutSaveTimerRef.current !== null) {
              window.clearTimeout(columnLayoutSaveTimerRef.current);
              columnLayoutSaveTimerRef.current = null;
            }
            columnLayoutReadyRef.current = false;
            gridApiRef.current = null;
            setGridReady(false);
          }}
          onGridReady={handleGridReady}
          pagination={false}
          rowData={items}
          rowHeight={density === "compact" ? 56 : 72}
          styleNonce={styleNonce}
          suppressColumnVirtualisation
          theme={alertGridTheme}
        />
      </div>
    </div>
  );
}
