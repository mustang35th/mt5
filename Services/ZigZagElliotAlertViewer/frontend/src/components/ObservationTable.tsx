import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import useMediaQuery from "@mui/material/useMediaQuery";
import {
  ClientSideRowModelModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  themeQuartz,
  type ColDef,
  type GridApi,
  type GridReadyEvent,
  type ICellRendererParams,
} from "ag-grid-community";
import { AgGridReact, type CustomHeaderProps } from "ag-grid-react";
import { useCallback, useEffect, useMemo, useRef } from "react";
import type {
  ObservationListItem,
  ObservationSort,
  ObservationTimeFrame,
  SortOrder,
} from "../api/types";
import { displayValue, formatNumber, sideClass } from "../lib/format";

interface ObservationTableProps {
  items: ObservationListItem[];
  available: boolean;
  loading: boolean;
  sort: ObservationSort;
  order: SortOrder;
  styleNonce?: string;
  onSort: (sort: ObservationSort) => void;
}

interface SortHeaderParameters {
  sortKey: ObservationSort;
  activeSort: ObservationSort;
  order: SortOrder;
  onSort: (sort: ObservationSort) => void;
}

type SortHeaderProps = CustomHeaderProps<ObservationListItem> & SortHeaderParameters;

const GRID_MODULES = [ClientSideRowModelModule, ColumnApiModule];
const TIME_FRAMES = ["MN1", "W1", "D1", "H4", "H1"] as const;
const PINNED_COLUMN_IDS = ["anchor_jst_time", "symbol_name"] as const;

const observationGridTheme = themeQuartz
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

function SortHeader({
  displayName,
  eGridHeader,
  sortKey,
  activeSort,
  order,
  onSort,
}: SortHeaderProps) {
  const active = sortKey === activeSort;
  const requestSort = useCallback(() => onSort(sortKey), [onSort, sortKey]);

  useEffect(() => {
    eGridHeader.setAttribute(
      "aria-sort",
      active ? (order === "asc" ? "ascending" : "descending") : "none",
    );
    function keyDown(event: KeyboardEvent) {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      requestSort();
    }
    eGridHeader.addEventListener("keydown", keyDown);
    return () => {
      eGridHeader.removeEventListener("keydown", keyDown);
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
      {active && <span aria-hidden>{order === "asc" ? "↑" : "↓"}</span>}
    </button>
  );
}

function sortHeaderParameters(
  sortKey: ObservationSort,
  activeSort: ObservationSort,
  order: SortOrder,
  onSort: (sort: ObservationSort) => void,
): SortHeaderParameters {
  return { sortKey, activeSort, order, onSort };
}

function dataFrom(params: ICellRendererParams<ObservationListItem>) {
  return params.data;
}

function ObservationTimeCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  return (
    <div className="grid-cell-stack">
      <span className="date-main">{displayValue(observation.anchor_jst_time_text)}</span>
      <span className="date-sub">
        Server {displayValue(observation.anchor_bar_time_text)} / H1新規足
      </span>
    </div>
  );
}

function SymbolCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  return (
    <div className="grid-cell-stack">
      <span className="symbol">{observation.symbol_name}</span>
      <span className="subtext">Run {observation.run_id} / {observation.anchor_time_frame_text}</span>
    </div>
  );
}

function SourceCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  return (
    <div className="grid-cell-stack">
      <span className="badge neutral">{displayValue(observation.source_mode)}</span>
      <span className="subtext">{displayValue(observation.source_server)}</span>
    </div>
  );
}

function VersionCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  return (
    <div className="grid-cell-stack">
      <span>分析 {displayValue(observation.analysis_version)}</span>
      <span className="subtext">{displayValue(observation.capture_phase)}</span>
    </div>
  );
}

function timeFrameFrom(
  observation: ObservationListItem,
  timeFrame: string,
): ObservationTimeFrame | undefined {
  return observation.time_frames.find(
    (item) => item.time_frame_text.toUpperCase() === timeFrame,
  );
}

function emaDirection(timeFrame: ObservationTimeFrame): string {
  if (timeFrame.is_ema200_buy) return "BUY";
  if (timeFrame.is_ema200_sell) return "SELL";
  return "—";
}

function waveLabel(timeFrame: ObservationTimeFrame): string {
  const elliot = displayValue(timeFrame.latest_elliot_label);
  const sub = displayValue(timeFrame.latest_sub_elliot_label, "");
  return sub ? `${elliot} / ${sub}` : elliot;
}

function TimeFrameSnapshot({
  timeFrame,
  showLatestPoint,
}: {
  timeFrame: ObservationTimeFrame | undefined;
  showLatestPoint: boolean;
}) {
  if (!timeFrame) {
    return <Typography sx={{ color: "text.secondary", fontSize: "0.72rem" }}>記録なし</Typography>;
  }
  const side = displayValue(timeFrame.buy_sell_label).toUpperCase();
  const waveState = `${timeFrame.is_wave_confirmed ? "確定" : "未確定"}・${timeFrame.is_wave_motive ? "推進" : "修正"}`;
  const waveDirection = timeFrame.is_wave_uptrend ? "上昇" : "下降";
  const latestPointJst = displayValue(timeFrame.latest_point_jst_time_text);
  const latestPointServer = displayValue(timeFrame.latest_point_time_text);
  const latestPointRate = formatNumber(timeFrame.latest_point_rate, 5);
  return (
    <Box sx={{ minWidth: 0, py: 0.25 }}>
      <Stack direction="row" spacing={0.75} sx={{ alignItems: "center", minWidth: 0 }}>
        <span className={`badge ${sideClass(side)}`}>{side}</span>
        <Typography noWrap title={waveLabel(timeFrame)} sx={{ fontSize: "0.74rem", fontWeight: 800 }}>
          Elliott {waveLabel(timeFrame)}
        </Typography>
      </Stack>
      <Typography noWrap sx={{ color: "text.secondary", fontSize: "0.66rem", mt: 0.35 }}>
        {waveState}・{waveDirection}
      </Typography>
      <Typography noWrap sx={{ color: "text.secondary", fontSize: "0.66rem" }}>
        EMA200 {emaDirection(timeFrame)}・GMMA T{timeFrame.gmma_trend_count} / C{timeFrame.gmma_cross_count}
      </Typography>
      <Typography noWrap sx={{ color: "text.secondary", fontSize: "0.66rem" }}>
        Stoch {displayValue(timeFrame.stochastic_main_direction_text)}・ATR {formatNumber(timeFrame.atr14_pips)}p
      </Typography>
      {showLatestPoint && (
        <Typography
          noWrap
          aria-label={`最新点 JST ${latestPointJst}、Server ${latestPointServer}、レート ${latestPointRate}`}
          title={`Server ${latestPointServer}`}
          sx={{ color: "text.secondary", fontSize: "0.64rem" }}
        >
          最新点 JST {latestPointJst} @ {latestPointRate}
        </Typography>
      )}
    </Box>
  );
}

function timeFrameCell(timeFrame: string) {
  return function TimeFrameCell(params: ICellRendererParams<ObservationListItem>) {
    const observation = dataFrom(params);
    if (!observation) return null;
    return (
      <TimeFrameSnapshot
        timeFrame={timeFrameFrom(observation, timeFrame)}
        showLatestPoint={timeFrame === "H1"}
      />
    );
  };
}

export function ObservationTable({
  items,
  available,
  loading,
  sort,
  order,
  styleNonce,
  onSort,
}: ObservationTableProps) {
  const gridApiRef = useRef<GridApi<ObservationListItem> | null>(null);
  const wideLayout = useMediaQuery("(min-width: 761px)");

  const applyPinning = useCallback((api: GridApi<ObservationListItem>) => {
    api.setColumnsPinned([...PINNED_COLUMN_IDS], wideLayout ? "left" : null);
  }, [wideLayout]);

  const gridReady = useCallback((event: GridReadyEvent<ObservationListItem>) => {
    gridApiRef.current = event.api;
    applyPinning(event.api);
  }, [applyPinning]);

  useEffect(() => {
    if (gridApiRef.current) applyPinning(gridApiRef.current);
  }, [applyPinning]);

  const EmptyOverlay = useCallback(() => (
    <div className="empty-state grid-empty-state">
      <strong>{available ? "該当するH1観測はありません" : "H1観測はまだ利用されていません"}</strong>
      <span>
        {available
          ? "JST期間や通貨などの検索条件を変更してください。"
          : "観測DB機能を有効にすると、次のH1新規足から記録されます。"}
      </span>
    </div>
  ), [available]);

  const columnDefs = useMemo<ColDef<ObservationListItem>[]>(() => [
    {
      colId: "anchor_jst_time",
      field: "anchor_jst_time_text",
      headerName: "JST日時",
      initialPinned: "left",
      initialWidth: 180,
      lockPinned: true,
      suppressMovable: true,
      headerComponent: SortHeader,
      headerComponentParams: sortHeaderParameters("anchor_jst_time", sort, order, onSort),
      cellRenderer: ObservationTimeCell,
    },
    {
      colId: "symbol_name",
      field: "symbol_name",
      headerName: "通貨",
      initialPinned: "left",
      initialWidth: 135,
      lockPinned: true,
      suppressMovable: true,
      headerComponent: SortHeader,
      headerComponentParams: sortHeaderParameters("symbol_name", sort, order, onSort),
      cellRenderer: SymbolCell,
    },
    {
      colId: "source_mode",
      field: "source_mode",
      headerName: "実行元",
      initialWidth: 125,
      cellRenderer: SourceCell,
    },
    ...TIME_FRAMES.map((timeFrame): ColDef<ObservationListItem> => ({
      colId: `time_frame_${timeFrame.toLowerCase()}`,
      headerName: timeFrame,
      initialWidth: 215,
      minWidth: 190,
      cellRenderer: timeFrameCell(timeFrame),
    })),
    {
      colId: "analysis_version",
      field: "analysis_version",
      headerName: "観測情報",
      initialWidth: 190,
      cellRenderer: VersionCell,
    },
  ], [onSort, order, sort]);

  return (
    <div className="grid-view" role="region" aria-label="H1 Elliott推移検索結果" aria-busy={loading}>
      <Box sx={{ px: 1.5, pb: 0.75, color: "text.secondary", fontSize: "0.68rem" }}>
        各時間足：方向 / Elliott（主波・下位波） / 波動状態 / EMA200 / GMMA（Trend・Cross） / Stochastic / ATR
      </Box>
      <div className="alert-grid density-compact">
        <AgGridReact<ObservationListItem>
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
          headerHeight={32}
          maintainColumnOrder
          modules={GRID_MODULES}
          noRowsOverlayComponent={EmptyOverlay}
          onGridPreDestroyed={() => {
            gridApiRef.current = null;
          }}
          onGridReady={gridReady}
          pagination={false}
          rowData={items}
          rowHeight={108}
          styleNonce={styleNonce}
          theme={observationGridTheme}
        />
      </div>
    </div>
  );
}
