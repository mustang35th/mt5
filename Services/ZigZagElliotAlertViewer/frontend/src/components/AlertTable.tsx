import { useCallback, useEffect, useMemo } from "react";
import {
  ClientSideRowModelModule,
  colorSchemeDarkBlue,
  ColumnAutoSizeModule,
  RowStyleModule,
  themeQuartz,
  type ColDef,
  type ICellRendererParams,
  type RowClassParams,
} from "ag-grid-community";
import { AgGridReact, type CustomHeaderProps } from "ag-grid-react";
import type { AlertListItem, AlertSort, SortOrder } from "../api/types";
import { displayValue, formatNumber, sideClass } from "../lib/format";

interface AlertTableProps {
  items: AlertListItem[];
  loading: boolean;
  highlightedIds?: ReadonlySet<number>;
  sort: AlertSort;
  order: SortOrder;
  styleNonce?: string;
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
  ColumnAutoSizeModule,
  RowStyleModule,
];

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
      <span className="subtext">Run {alert.run_id} / {alert.time_frame_text}</span>
    </div>
  );
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
  onSort,
  onOpenDetail,
}: AlertTableProps) {
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
      width: 180,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("jst_time", sort, order, onSort),
      cellRenderer: DateCell,
    },
    {
      colId: "symbol_name",
      field: "symbol_name",
      headerName: "通貨",
      width: 135,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("symbol_name", sort, order, onSort),
      cellRenderer: SymbolCell,
    },
    {
      colId: "side",
      field: "side",
      headerName: "方向",
      width: 90,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("side", sort, order, onSort),
      cellRenderer: SideCell,
    },
    {
      colId: "source_mode",
      field: "source_mode",
      headerName: "実行モード",
      width: 110,
      cellRenderer: SourceModeCell,
    },
    {
      colId: "judgement",
      headerName: "判定",
      minWidth: 220,
      flex: 1,
      cellRenderer: JudgementCell,
    },
    {
      colId: "h1_structure_rank",
      field: "h1_structure_rank",
      headerName: "構造・波動",
      width: 145,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("h1_structure_rank", sort, order, onSort),
      cellRenderer: StructureCell,
    },
    {
      colId: "time_frame_sides",
      headerName: "MN1 → H1 分析方向",
      width: 270,
      cellRenderer: TimeFramesCell,
    },
    {
      colId: "is_w1_aligned",
      field: "is_w1_aligned",
      headerName: "W1一致",
      width: 115,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("is_w1_aligned", sort, order, onSort),
      cellRenderer: AlignmentCell,
    },
    {
      colId: "risk_pips",
      field: "risk_pips",
      headerName: "Risk / Spread",
      width: 135,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("risk_pips", sort, order, onSort),
      cellRenderer: RiskCell,
    },
    {
      colId: "entry_result",
      field: "entry_result",
      headerName: "ENTRY",
      width: 105,
      headerComponent: ServerSortHeader,
      headerComponentParams: sortHeaderParameters("entry_result", sort, order, onSort),
      cellRenderer: EntryCell,
    },
    {
      colId: "detail",
      headerName: "詳細",
      width: 90,
      cellRenderer: DetailCell,
    },
  ], [DetailCell, onSort, order, sort]);

  return (
    <div
      className="alert-grid"
      role="region"
      aria-label="ZigZagElliotアラート検索結果"
      aria-busy={loading}
    >
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
        modules={GRID_MODULES}
        noRowsOverlayComponent={NoAlertsOverlay}
        pagination={false}
        rowData={items}
        rowHeight={72}
        styleNonce={styleNonce}
        suppressColumnVirtualisation
        theme={alertGridTheme}
      />
    </div>
  );
}
