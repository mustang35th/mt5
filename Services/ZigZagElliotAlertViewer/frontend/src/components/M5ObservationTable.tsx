import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useMediaQuery } from "@mui/material";
import { ClientSideRowModelModule, ColumnApiModule, colorSchemeDarkBlue, themeQuartz,
  type ColDef, type GridApi, type ICellRendererParams } from "ag-grid-community";
import { AgGridReact } from "ag-grid-react";
import type { M5ObservationItem, M5Sort } from "../api/m5Types";
import { m5CaptureSummary } from "../lib/m5CaptureQuality";
import { M5_TIME_FRAMES, m5Direction, m5EmaLabel, m5Number, m5TimeFrameSlots, m5WaveLabel } from "../lib/m5TimeFrame";
import { M5_DENSITY_KEY, M5_LAYOUT_KEY, readM5Preference, validM5Layout, writeM5Preference,
  type M5ColumnLayout } from "../lib/m5ObservationPreferences";
import { m5DateTime } from "../lib/m5ObservationSearchState";
import "./M5Observation.css";

interface Props {
  items: M5ObservationItem[];
  databaseKey: string;
  loading: boolean;
  sort: M5Sort;
  order: "asc" | "desc";
  styleNonce?: string;
  toolbarStart?: ReactNode;
  onSort: (sort: M5Sort) => void;
  onOpenDetail: (id: number, trigger: HTMLElement) => void;
}
const modules = [ClientSideRowModelModule, ColumnApiModule];
const theme = themeQuartz.withPart(colorSchemeDarkBlue).withParams({
  fontFamily: '"IBM Plex Sans", "Noto Sans JP", sans-serif', fontSize: 12,
  backgroundColor: "#101c2a", foregroundColor: "#dce9f6", headerBackgroundColor: "#132234",
  borderColor: "#294055", rowHoverColor: "#1b3045", spacing: 4,
});
const mandatoryColumns = ["anchor_jst_time", "symbol_name", "detail"];
const columnLabels = [
  { id: "m5_direction", label: "M5分析方向" },
  ...M5_TIME_FRAMES.map((frame) => ({ id: `tf_${frame.label}`, label: frame.label })),
  { id: "spread_pips", label: "Spread" }, { id: "quality", label: "取得品質" },
];

export function M5ObservationTable({ items, databaseKey, loading, sort, order, styleNonce, toolbarStart, onSort, onOpenDetail }: Props) {
  const grid = useRef<GridApi<M5ObservationItem> | null>(null);
  const restoring = useRef(false);
  const wide = useMediaQuery("(min-width: 761px)");
  const [layout, setLayout] = useState(() => readM5Preference<M5ColumnLayout[]>(M5_LAYOUT_KEY, [], validM5Layout));
  const [density, setDensity] = useState(() => readM5Preference(M5_DENSITY_KEY, "compact", (value): value is string => value === "compact" || value === "comfortable"));
  const pinColumns = useCallback((api: GridApi<M5ObservationItem>) => {
    api.setColumnsPinned(["anchor_jst_time", "symbol_name", "m5_direction"], wide ? "left" : null);
    api.setColumnsPinned(["detail"], wide ? "right" : null);
  }, [wide]);
  useEffect(() => { if (grid.current) pinColumns(grid.current); }, [pinColumns]);
  const saveLayout = useCallback(() => {
    if (!grid.current || restoring.current) return;
    const next = grid.current.getColumnState().map((column) => ({ colId: column.colId, width: column.width ?? 120, hide: Boolean(column.hide) }));
    setLayout(next);
    writeM5Preference(M5_LAYOUT_KEY, next);
  }, []);
  const columns = useMemo<ColDef<M5ObservationItem>[]>(() => {
    const sortHeader = (key: M5Sort, label: string) => () => (
      <button className="m5-sort-header" type="button" onClick={() => onSort(key)}
        aria-label={`${label}で${sort === key && order === "asc" ? "降順" : "昇順"}に並べ替え`}>
        {label} {sort === key ? order === "asc" ? "▲" : "▼" : "↕"}
      </button>
    );
    return [
      { colId: "anchor_jst_time", headerName: "JST日時", initialWidth: 180, minWidth: 160,
        headerComponent: sortHeader("anchor_jst_time", "JST日時"),
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => data
          ? <span title={`Server: ${data.anchor_bar_time_text || m5DateTime(data.anchor_bar_time).replace("T", " ")} / ID: ${data.id}`}>{data.anchor_jst_time_text || m5DateTime(data.anchor_jst_time).replace("T", " ")}</span> : null },
      { colId: "symbol_name", field: "symbol_name", headerName: "通貨", initialWidth: 112, minWidth: 100,
        headerComponent: sortHeader("symbol_name", "通貨") },
      { colId: "m5_direction", headerName: "M5分析方向", initialWidth: 112, minWidth: 100,
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => {
          const frame = data && m5TimeFrameSlots(data.timeframes).slots.find((slot) => slot.id === 5)?.timeFrame;
          const direction = m5Direction(frame?.is_buy);
          return <span className={`m5-direction m5-${direction.toLowerCase()}`}>{direction}</span>;
        } },
      ...M5_TIME_FRAMES.map((frame): ColDef<M5ObservationItem> => ({
        colId: `tf_${frame.label}`, headerName: frame.label, initialWidth: 148, minWidth: 120,
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => {
          const slot = data && m5TimeFrameSlots(data.timeframes).slots.find((item) => item.id === frame.id);
          if (!slot?.timeFrame) return <span title={slot?.warning}>未記録</span>;
          const direction = m5Direction(slot.timeFrame.is_buy);
          return <div className="m5-timeframe-cell" title={slot.warning || undefined}>
            <span><span className={`m5-direction m5-${direction.toLowerCase()}`}>{direction}</span> {m5WaveLabel(slot.timeFrame)}{slot.warning ? " ⚠" : ""}</span>
            <small>EMA {m5EmaLabel(slot.timeFrame)}</small>
          </div>;
        },
      })),
      { colId: "spread_pips", headerName: "Spread", initialWidth: 100, minWidth: 90,
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => m5Number(data?.spread_pips, 1, "p") },
      { colId: "quality", headerName: "取得品質", initialWidth: 315, minWidth: 230,
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => data
          ? <span title={`${m5CaptureSummary(data, data.captureMetrics, data.captureMetricsState)}。遅れ＝取得市場時刻－M5開始Server時刻。解析＝採用した解析1回の実時間。取得＝当該M5の初検出からSnapshot確定までの実時間（再試行を含む）。DB保存待ちは含みません。`}>{m5CaptureSummary(data, data.captureMetrics, data.captureMetricsState)}</span> : null },
      { colId: "detail", headerName: "詳細", initialWidth: 78, minWidth: 78, maxWidth: 90,
        cellRenderer: ({ data }: ICellRendererParams<M5ObservationItem>) => data
          ? <button type="button" className="secondary-button" onClick={(event) => onOpenDetail(data.id, event.currentTarget)} aria-label={`${data.symbol_name} ${data.anchor_jst_time_text || m5DateTime(data.anchor_jst_time)} の詳細`}>詳細</button> : null },
    ];
  }, [sort, order, onSort, onOpenDetail]);
  return <div className="m5-table" aria-label="M5観測検索結果" aria-busy={loading}>
    <div className="m5-table-controls">
      {toolbarStart}
      <div className="m5-grid-settings">
      <label>行密度 <select aria-label="M5行密度" value={density} onChange={(event) => {
        setDensity(event.target.value); writeM5Preference(M5_DENSITY_KEY, event.target.value);
      }}><option value="compact">コンパクト</option><option value="comfortable">ゆったり</option></select></label>
      <details className="m5-column-settings"><summary>表示設定</summary><div>
        <p className="m5-muted">各足：分析方向 / 波動（▲上昇・▼下降） / EMA200。M5はH1から独立した保存値です。</p>
        {columnLabels.map((column) => <label key={column.id}><input type="checkbox" checked={!layout.find((item) => item.colId === column.id)?.hide}
          onChange={(event) => { grid.current?.setColumnsVisible([column.id], event.target.checked); saveLayout(); }} />{column.label}</label>)}
      </div></details>
      <button type="button" className="secondary-button" onClick={() => {
          restoring.current = true; grid.current?.resetColumnState(); if (grid.current) pinColumns(grid.current); restoring.current = false; saveLayout();
        }}>列設定を初期化</button>
      </div>
    </div>
    <div className="m5-grid">
      <AgGridReact<M5ObservationItem> modules={modules} theme={theme} styleNonce={styleNonce}
        rowData={items} columnDefs={columns} rowHeight={density === "compact" ? 50 : 66} headerHeight={34}
        defaultColDef={{ sortable: false, filter: false, resizable: true, suppressHeaderMenuButton: true }}
        getRowId={({ data }) => `${databaseKey}:${data.id}`} animateRows={false} maintainColumnOrder
        pagination={false} ensureDomOrder
        noRowsOverlayComponent={() => <span>該当するM5観測はありません。</span>}
        onGridReady={({ api }) => {
          grid.current = api; restoring.current = true;
          api.applyColumnState({ state: layout.map((column) => ({ ...column, hide: mandatoryColumns.includes(column.colId) ? false : column.hide })), applyOrder: true });
          pinColumns(api); restoring.current = false;
        }}
        onGridPreDestroyed={() => { grid.current = null; }}
        onColumnMoved={(event) => { if (event.finished) saveLayout(); }}
        onColumnResized={(event) => { if (event.finished) saveLayout(); }}
        onColumnVisible={saveLayout}
      />
    </div>
  </div>;
}
