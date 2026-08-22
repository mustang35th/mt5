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
import { Ema200SignalBadge } from "./Ema200SignalBadge";
import { GmoTargetBadge } from "./GmoTargetBadge";
import { GridControls, type GridColumnOption } from "./GridControls";
import { H1DirectionAlignmentBadge } from "./H1DirectionAlignmentBadge";
import { W1ConfirmationBadge } from "./W1ConfirmationBadge";

interface AlertTableProps {
  items: AlertListItem[];
  loading: boolean;
  highlightedIds?: ReadonlySet<number>;
  sort: AlertSort;
  order: SortOrder;
  styleNonce?: string;
  gridControlsTarget?: HTMLElement | null;
  onSort: (sort: AlertSort) => void;
  onOpenComparison: (alertId: number, fromTrigger: HTMLButtonElement) => void;
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

const TIME_FRAME_ANALYSIS_COLUMN_IDS = [
  "tf_mn1",
  "tf_w1",
  "tf_d1",
  "tf_h4",
  "tf_h1",
] as const;
const LEGACY_TIME_FRAME_SIDES_COLUMN_ID = "time_frame_sides";
const TIME_FRAME_ANALYSIS_COLUMN_WIDTH = 125;

const GRID_COLUMN_IDS = [
  "jst_time",
  "symbol_name",
  "time_frame",
  "side",
  "source_mode",
  "judgement",
  "h1_structure_rank",
  ...TIME_FRAME_ANALYSIS_COLUMN_IDS,
  "h1_direction_alignment",
  "is_w1_aligned",
  "risk_pips",
  "entry_result",
  "detail",
] as const;

const GRID_LAYOUT_COLUMN_ID_SET: ReadonlySet<string> = new Set([
  ...GRID_COLUMN_IDS,
  LEGACY_TIME_FRAME_SIDES_COLUMN_ID,
]);
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
  { colId: "tf_mn1", label: "MN1 方向 / EMA200" },
  { colId: "tf_w1", label: "W1 方向 / EMA200" },
  { colId: "tf_d1", label: "D1 方向 / EMA200" },
  { colId: "tf_h4", label: "H4 方向 / EMA200" },
  { colId: "tf_h1", label: "H1 方向 / EMA200" },
  { colId: "h1_direction_alignment", label: "H1方向ルール" },
  { colId: "is_w1_aligned", label: "W1確認" },
  { colId: "risk_pips", label: "Risk / Spread" },
  { colId: "entry_result", label: "ENTRY" },
];

const TIME_FRAME_ANALYSIS_COLUMNS = [
  {
    colId: "tf_mn1",
    timeFrame: "MN1",
    sideField: "mn1_side",
    availableField: "mn1_is_ema200_available",
    buyField: "mn1_is_ema200_buy",
    sellField: "mn1_is_ema200_sell",
  },
  {
    colId: "tf_w1",
    timeFrame: "W1",
    sideField: "w1_side",
    availableField: "w1_is_ema200_available",
    buyField: "w1_is_ema200_buy",
    sellField: "w1_is_ema200_sell",
  },
  {
    colId: "tf_d1",
    timeFrame: "D1",
    sideField: "d1_side",
    availableField: "d1_is_ema200_available",
    buyField: "d1_is_ema200_buy",
    sellField: "d1_is_ema200_sell",
  },
  {
    colId: "tf_h4",
    timeFrame: "H4",
    sideField: "h4_side",
    availableField: "h4_is_ema200_available",
    buyField: "h4_is_ema200_buy",
    sellField: "h4_is_ema200_sell",
  },
  {
    colId: "tf_h1",
    timeFrame: "H1",
    sideField: "h1_side",
    availableField: "h1_is_ema200_available",
    buyField: "h1_is_ema200_buy",
    sellField: "h1_is_ema200_sell",
  },
] as const;

type TimeFrameAnalysisColumn = (typeof TIME_FRAME_ANALYSIS_COLUMNS)[number];

function migrateLegacyTimeFrameColumns(
  fromLayout: GridColumnLayoutItem[],
): GridColumnLayoutItem[] {
  if (!fromLayout.some((column) => column.colId === LEGACY_TIME_FRAME_SIDES_COLUMN_ID)) {
    return fromLayout;
  }
  const newColumnIds: ReadonlySet<string> = new Set(TIME_FRAME_ANALYSIS_COLUMN_IDS);
  return fromLayout.flatMap((column) => {
    if (newColumnIds.has(column.colId)) return [];
    if (column.colId !== LEGACY_TIME_FRAME_SIDES_COLUMN_ID) return [column];
    return TIME_FRAME_ANALYSIS_COLUMN_IDS.map((colId) => ({
      colId,
      width: TIME_FRAME_ANALYSIS_COLUMN_WIDTH,
      hide: column.hide,
    }));
  });
}

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

function Badge({
  text,
  variant = "neutral",
  ariaLabel,
}: {
  text: string;
  variant?: string;
  ariaLabel?: string;
}) {
  return <span aria-label={ariaLabel} className={`badge ${variant}`}>{text}</span>;
}

function timeFrameAnalysisCell(column: TimeFrameAnalysisColumn) {
  return function TimeFrameAnalysisCell(params: ICellRendererParams<AlertListItem>) {
    const alert = dataFrom(params);
    if (!alert) return null;
    const normalizedSide = String(alert[column.sideField] || "NONE").toUpperCase();
    const isCurrentTimeFrame = alert.time_frame_text.toUpperCase() === column.timeFrame;
    const groupLabel = `${column.timeFrame} 分析方向とEMA200判定${
      isCurrentTimeFrame ? "（現在のアラート時間足）" : ""
    }`;

    return (
      <div
        aria-current={isCurrentTimeFrame ? "true" : undefined}
        aria-label={groupLabel}
        className={`grid-cell-stack time-frame-analysis-cell${
          isCurrentTimeFrame ? " current-time-frame-analysis-cell" : ""
        }`}
        role="group"
      >
        <span className="time-frame-analysis-direction-line">
          <Badge
            ariaLabel={`${column.timeFrame} 分析方向 ${normalizedSide}`}
            text={normalizedSide === "NONE" ? "—" : normalizedSide}
            variant={sideClass(normalizedSide)}
          />
          {isCurrentTimeFrame && (
            <span aria-hidden="true" className="current-time-frame-chip">現在足</span>
          )}
        </span>
        <Ema200SignalBadge
          available={alert[column.availableField] === true}
          timeFrame={{
            time_frame_text: column.timeFrame,
            is_ema200_buy: alert[column.buyField] === true,
            is_ema200_sell: alert[column.sellField] === true,
          }}
        />
      </div>
    );
  };
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
      <span className="symbol-gmo-line">
        <span className="symbol">{alert.symbol_name}</span>
        <GmoTargetBadge compact isTarget={alert.is_gmo_target} />
      </span>
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
  return (
    <div className="grid-cell-stack alert-direction-cell">
      <Badge
        ariaLabel={`アラート方向 ${alert.side}`}
        text={alert.side}
        variant={sideClass(alert.side)}
      />
      <Ema200SignalBadge
        available={alert.is_ema200_available === true}
        timeFrame={{
          time_frame_text: alert.time_frame_text,
          is_ema200_buy: alert.is_ema200_buy === true,
          is_ema200_sell: alert.is_ema200_sell === true,
        }}
      />
    </div>
  );
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

function W1ConfirmationCell(params: ICellRendererParams<AlertListItem>) {
  const alert = dataFrom(params);
  if (!alert) return null;
  const isLegacy = alert.is_w1_confirmation_legacy
    || alert.w1_confirmation_state === "NOT_EVALUATED";
  return (
    <div className="grid-cell-stack w1-confirmation-cell">
      <W1ConfirmationBadge compact confirmation={alert} />
      <span className="subtext">
        {isLegacy
          ? `方向 ${alert.is_w1_aligned === null ? "不明" : alert.is_w1_aligned ? "一致" : "不一致"}`
          : alert.w1_confirmation_state}
        {` / EMA ${displayValue(alert.w1_ema200_direction)}`}
      </span>
    </div>
  );
}

function H1DirectionAlignmentCell(
  params: ICellRendererParams<AlertListItem>,
) {
  const alert = dataFrom(params);
  if (!alert) return null;
  const isLegacy = alert.is_h1_direction_alignment_legacy
    || alert.h1_direction_alignment_state === "NOT_EVALUATED";
  return (
    <div className="grid-cell-stack h1-direction-alignment-cell">
      <H1DirectionAlignmentBadge alignment={alert} compact />
      <span className="subtext">
        {isLegacy
          ? "方向一致診断なし"
          : `基準 ${alert.h1_direction_alignment_direction}`}
        {!isLegacy && alert.h1_direction_alignment_mode !== "D1_TO_H1" && (
          ` / MN1 ${alert.is_h1_mn1_direction_matched ? "一致" : "不一致"}`
            + ` / W1 ${alert.is_h1_w1_direction_matched ? "一致" : "不一致"}`
        )}
      </span>
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
  onOpenComparison,
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
    const storedLayout = readGridColumnLayout(window.localStorage, GRID_LAYOUT_COLUMN_ID_SET);
    if (storedLayout !== null) {
      const hasLegacyTimeFrameColumn = storedLayout.some(
        (column) => column.colId === LEGACY_TIME_FRAME_SIDES_COLUMN_ID,
      );
      const restoredLayout = includeTimeFrameColumn(
        migrateLegacyTimeFrameColumns(storedLayout),
      );
      event.api.applyColumnState({
        state: restoredLayout.map((column) => ({
          ...column,
          hide: FIXED_COLUMN_IDS.has(column.colId) ? false : column.hide,
        })),
        applyOrder: true,
      });
      if (hasLegacyTimeFrameColumn) {
        writeGridColumnLayout(
          window.localStorage,
          restoredLayout.map((column) => ({
            ...column,
            hide: FIXED_COLUMN_IDS.has(column.colId) ? false : column.hide,
          })),
        );
      }
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

  const ActionCell = useCallback((params: ICellRendererParams<AlertListItem>) => {
    const alert = dataFrom(params);
    if (!alert) return null;
    return (
      <div
        aria-label={`${alert.symbol_name} ${alert.side} ${alert.jst_time_text} の操作`}
        role="group"
        style={{ alignItems: "center", display: "flex", gap: "6px" }}
      >
        <button
          aria-label={`${alert.symbol_name} ${alert.side} ${alert.jst_time_text} のTIMEFRAME COMPARISONを表示`}
          className="secondary-button detail-open-button"
          type="button"
          onClick={(event) => onOpenComparison(alert.id, event.currentTarget)}
        >
          TF比較
        </button>
        <button
          aria-label={`${alert.symbol_name} ${alert.side} ${alert.jst_time_text} の詳細を表示`}
          className="secondary-button detail-open-button"
          type="button"
          onClick={(event) => onOpenDetail(alert.id, event.currentTarget)}
        >
          詳細
        </button>
      </div>
    );
  }, [onOpenComparison, onOpenDetail]);

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
      initialWidth: 130,
      minWidth: 120,
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
    ...TIME_FRAME_ANALYSIS_COLUMNS.map((column): ColDef<AlertListItem> => ({
      colId: column.colId,
      headerName: column.timeFrame,
      initialWidth: TIME_FRAME_ANALYSIS_COLUMN_WIDTH,
      minWidth: 120,
      cellRenderer: timeFrameAnalysisCell(column),
    })),
    {
      colId: "h1_direction_alignment",
      field: "h1_direction_alignment_state",
      headerName: "H1方向ルール",
      initialWidth: 230,
      minWidth: 210,
      cellRenderer: H1DirectionAlignmentCell,
    },
    {
      colId: "is_w1_aligned",
      field: "w1_confirmation_state",
      headerName: "W1確認",
      initialWidth: 210,
      minWidth: 190,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("w1_confirmation_state", sort, order, onSort),
      cellRenderer: W1ConfirmationCell,
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
      headerName: "操作",
      initialPinned: "right",
      initialWidth: 190,
      minWidth: 180,
      lockPinned: true,
      lockPosition: "right",
      suppressMovable: true,
      cellRenderer: ActionCell,
    },
  ], [ActionCell, onSort, order, sort]);

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
