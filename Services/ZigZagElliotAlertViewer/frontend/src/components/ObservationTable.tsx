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
import {
  displayValue,
  elliottDirectionSymbol,
  formatElliottDirection,
  formatInteger,
  formatNumber,
  formatSignedNumber,
  sideClass,
} from "../lib/format";
import { Ema200SignalBadge } from "./Ema200SignalBadge";
import { GmoTargetBadge } from "./GmoTargetBadge";

interface ObservationTableProps {
  items: ObservationListItem[];
  available: boolean;
  grouped: boolean;
  loading: boolean;
  sort: ObservationSort;
  order: SortOrder;
  styleNonce?: string;
  onSort: (sort: ObservationSort) => void;
  onOpenDetail: (observationId: number, trigger: HTMLButtonElement) => void;
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
const DETAIL_COLUMN_ID = "detail";

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

type FullAlignmentSide = "BUY" | "SELL";

function strictEma200Matches(
  timeFrame: ObservationTimeFrame,
  side: FullAlignmentSide,
): boolean {
  if (side === "BUY") {
    return timeFrame.is_ema200_buy === true && timeFrame.is_ema200_sell === false;
  }
  return timeFrame.is_ema200_buy === false && timeFrame.is_ema200_sell === true;
}

export function observationFullAlignmentSide(
  observation: ObservationListItem,
): FullAlignmentSide | null {
  const w1 = timeFrameFrom(observation, "W1");
  const d1 = timeFrameFrom(observation, "D1");
  const h4 = timeFrameFrom(observation, "H4");
  const h1 = timeFrameFrom(observation, "H1");
  if (!w1 || !d1 || !h4 || !h1) return null;

  const requiredTimeFrames = [w1, d1, h4, h1];
  if (requiredTimeFrames.every((timeFrame) => timeFrame.is_buy === true)
      && strictEma200Matches(h4, "BUY") && strictEma200Matches(h1, "BUY")) {
    return "BUY";
  }
  if (requiredTimeFrames.every((timeFrame) => timeFrame.is_buy === false)
      && strictEma200Matches(h4, "SELL") && strictEma200Matches(h1, "SELL")) {
    return "SELL";
  }
  return null;
}

function ObservationTimeCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  const isSignal = observation.signal_h1_count !== undefined;
  const serverTitle = isSignal
    ? `Server ${displayValue(observation.anchor_bar_time_text)} → ${displayValue(observation.signal_end_anchor_bar_time_text)}`
    : `Server ${displayValue(observation.anchor_bar_time_text)} / H1新規足`;
  const subText = isSignal
    ? `→ ${displayValue(observation.signal_end_anchor_jst_time_text)} / ${formatInteger(observation.signal_h1_count)} H1`
    : `Server ${displayValue(observation.anchor_bar_time_text)} / H1新規足`;
  return (
    <div className="grid-cell-stack">
      <span className="date-main">{displayValue(observation.anchor_jst_time_text)}</span>
      <Typography
        className="date-sub"
        component="span"
        noWrap
        title={serverTitle}
        sx={{ maxWidth: "100%" }}
      >
        {subText}
      </Typography>
    </div>
  );
}

function SymbolCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  const profileKind = observation.analysis_profile_is_legacy ? "Legacy" : "Profile";
  const profileHash = observation.analysis_input_hash.slice(0, 8) || "—";
  const shortVersion = observation.analysis_version.replace(/^ELLIOT_MN1_/, "");
  const fullAlignmentSide = observation.signal_side || observationFullAlignmentSide(observation);
  return (
    <div className="grid-cell-stack">
      <Stack
        direction="row"
        spacing={0.5}
        sx={{ alignItems: "center", flexWrap: "nowrap", minWidth: 0, overflow: "hidden" }}
      >
        <Typography
          className="symbol"
          component="span"
          noWrap
          title={observation.symbol_name}
          sx={{ minWidth: 0 }}
        >
          {observation.symbol_name}
        </Typography>
        {fullAlignmentSide && (
          <Box
            aria-label={`W1～H1＋EMA200 完全一致 ${fullAlignmentSide}`}
            className={`badge ${sideClass(fullAlignmentSide)}`}
            component="span"
            title={`W1・D1・H4・H1の方向とH4・H1のEMA200が${fullAlignmentSide}で完全一致`}
            sx={{ flex: "0 0 auto", fontSize: "0.56rem", px: 0.5 }}
          >
            FULL {fullAlignmentSide}
          </Box>
        )}
        <GmoTargetBadge compact isTarget={observation.is_gmo_target} />
        <Box component="span" className="badge neutral" sx={{ flex: "0 0 auto" }}>
          {displayValue(observation.source_mode)}
        </Box>
      </Stack>
      <Typography
        className="subtext"
        component="span"
        noWrap
        title={`Run ${observation.run_id} / ${observation.analysis_version} / ${profileKind} ${profileHash} / ${displayValue(observation.source_server)}`}
      >
        Run {observation.run_id} / {shortVersion} {profileKind} {profileHash}
      </Typography>
    </div>
  );
}

function SignalSpanCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation || observation.signal_h1_count === undefined) return null;
  const boundaryLabels = [
    observation.signal_is_left_censored ? "左打切り" : "",
    observation.signal_is_right_censored ? "右打切り" : "",
    observation.signal_has_data_gap_before ? "欠損前" : "",
    observation.signal_has_data_gap_after ? "欠損後" : "",
  ].filter(Boolean);
  return (
    <div className="grid-cell-stack">
      <Typography component="span" sx={{ fontSize: "0.76rem", fontWeight: 800 }}>
        {formatInteger(observation.signal_h1_count)} H1
      </Typography>
      <Stack
        direction="row"
        spacing={0.4}
        sx={{ alignItems: "center", flexWrap: "wrap", minWidth: 0, rowGap: 0.25 }}
      >
        {boundaryLabels.length === 0 ? (
          <Typography className="subtext" component="span" noWrap>
            完結
          </Typography>
        ) : boundaryLabels.map((label) => (
          <Box className="badge neutral" component="span" key={label} sx={{ fontSize: "0.56rem", px: 0.5 }}>
            {label}
          </Box>
        ))}
      </Stack>
    </div>
  );
}

function SpreadCell(params: ICellRendererParams<ObservationListItem>) {
  const observation = dataFrom(params);
  if (!observation) return null;
  const spread = observation.spread_pips;
  return (
    <span>
      {spread === null || spread === undefined
        ? "未記録"
        : `${formatNumber(spread)} pips`}
    </span>
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

function waveLabel(timeFrame: ObservationTimeFrame): string {
  const elliot = displayValue(timeFrame.latest_elliot_label);
  const sub = displayValue(timeFrame.latest_sub_elliot_label, "");
  const direction = elliottDirectionSymbol(timeFrame.is_wave_uptrend);
  return sub ? `${direction}${elliot} / ${sub}` : `${direction}${elliot}`;
}

function TimeFrameSnapshot({ timeFrame }: { timeFrame: ObservationTimeFrame | undefined }) {
  if (!timeFrame) {
    return (
      <Box sx={{ minWidth: 0, overflow: "hidden", py: 0.25 }}>
        <Typography noWrap sx={{ color: "text.secondary", fontSize: "0.72rem" }}>
          記録なし
        </Typography>
        <Typography noWrap sx={{ color: "text.secondary", fontSize: "0.66rem" }}>
          —
        </Typography>
      </Box>
    );
  }
  const side = displayValue(timeFrame.buy_sell_label).toUpperCase();
  const waveState = `${timeFrame.is_wave_confirmed ? "確" : "未"}・${timeFrame.is_wave_motive ? "推" : "修"}`;
  const waveDirection = elliottDirectionSymbol(timeFrame.is_wave_uptrend);
  const waveSummary = `${formatElliottDirection(timeFrame.is_wave_uptrend)}、${timeFrame.is_wave_confirmed ? "確定" : "未確定"}、${timeFrame.is_wave_motive ? "推進波" : "修正波"}、GMMA trend ${formatSignedNumber(timeFrame.gmma_trend_count, 0)}、cross ${formatSignedNumber(timeFrame.gmma_cross_count, 0)}`;
  return (
    <Box sx={{ minWidth: 0, overflow: "hidden", py: 0.25 }}>
      <Stack
        direction="row"
        spacing={0.5}
        sx={{ alignItems: "center", flexWrap: "nowrap", minWidth: 0, overflow: "hidden" }}
      >
        <span className={`badge ${sideClass(side)}`}>{side}</span>
        <Typography
          noWrap
          title={`Elliott ${waveLabel(timeFrame)}`}
          sx={{ fontSize: "0.72rem", fontWeight: 800, minWidth: 0 }}
        >
          Elliott {waveLabel(timeFrame)}
        </Typography>
      </Stack>
      <Stack
        direction="row"
        spacing={0.5}
        sx={{ alignItems: "center", minWidth: 0, mt: 0.25, overflow: "hidden" }}
      >
        <Ema200SignalBadge timeFrame={timeFrame} />
        <Typography
          noWrap
          aria-label={waveSummary}
          title={waveSummary}
          sx={{ color: "text.secondary", fontSize: "0.64rem", minWidth: 0 }}
        >
          {waveDirection}・{waveState}・GMMA T
          {formatSignedNumber(timeFrame.gmma_trend_count, 0)}/C
          {formatSignedNumber(timeFrame.gmma_cross_count, 0)}
        </Typography>
      </Stack>
    </Box>
  );
}

function timeFrameCell(timeFrame: string) {
  return function TimeFrameCell(params: ICellRendererParams<ObservationListItem>) {
    const observation = dataFrom(params);
    if (!observation) return null;
    return <TimeFrameSnapshot timeFrame={timeFrameFrom(observation, timeFrame)} />;
  };
}

function detailCell(onOpenDetail: ObservationTableProps["onOpenDetail"]) {
  return function DetailCell(params: ICellRendererParams<ObservationListItem>) {
    const observation = dataFrom(params);
    if (!observation) return null;
    return (
      <button
        aria-label={`${observation.symbol_name} JST ${displayValue(observation.anchor_jst_time_text)} のH1推移詳細を表示`}
        className="secondary-button detail-open-button"
        type="button"
        onClick={(event) => onOpenDetail(observation.id, event.currentTarget)}
      >
        詳細
      </button>
    );
  };
}

export function ObservationTable({
  items,
  available,
  grouped,
  loading,
  sort,
  order,
  styleNonce,
  onSort,
  onOpenDetail,
}: ObservationTableProps) {
  const gridApiRef = useRef<GridApi<ObservationListItem> | null>(null);
  const wideLayout = useMediaQuery("(min-width: 761px)");

  const applyPinning = useCallback((api: GridApi<ObservationListItem>) => {
    api.setColumnsPinned([...PINNED_COLUMN_IDS], wideLayout ? "left" : null);
    api.setColumnsPinned([DETAIL_COLUMN_ID], wideLayout ? "right" : null);
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
      <strong>
        {available
          ? grouped ? "該当する連続FULLシグナルはありません" : "該当するH1観測はありません"
          : "H1観測はまだ利用されていません"}
      </strong>
      <span>
        {available
          ? "JST期間や通貨などの検索条件を変更してください。"
          : "観測DB機能を有効にすると、次のH1新規足から記録されます。"}
      </span>
    </div>
  ), [available, grouped]);

  const columnDefs = useMemo<ColDef<ObservationListItem>[]>(() => [
    {
      colId: "anchor_jst_time",
      field: "anchor_jst_time_text",
      headerName: grouped ? "開始JST" : "JST日時",
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
      initialWidth: 250,
      minWidth: 230,
      lockPinned: true,
      suppressMovable: true,
      headerComponent: SortHeader,
      headerComponentParams: sortHeaderParameters("symbol_name", sort, order, onSort),
      cellRenderer: SymbolCell,
    },
    ...(grouped ? [{
      colId: "signal_h1_count",
      field: "signal_h1_count" as const,
      headerName: "継続",
      initialWidth: 130,
      minWidth: 120,
      cellRenderer: SignalSpanCell,
    }] : []),
    {
      colId: "spread_pips",
      field: "spread_pips",
      headerName: grouped ? "開始Spread" : "Spread",
      initialWidth: 105,
      minWidth: 100,
      cellRenderer: SpreadCell,
    },
    ...TIME_FRAMES.map((timeFrame): ColDef<ObservationListItem> => ({
      colId: `time_frame_${timeFrame.toLowerCase()}`,
      headerName: timeFrame,
      initialWidth: 180,
      minWidth: 170,
      cellRenderer: timeFrameCell(timeFrame),
    })),
    {
      colId: DETAIL_COLUMN_ID,
      headerName: "詳細",
      initialPinned: "right",
      initialWidth: 80,
      minWidth: 80,
      maxWidth: 80,
      lockPinned: true,
      resizable: false,
      suppressMovable: true,
      cellRenderer: detailCell(onOpenDetail),
    },
  ], [grouped, onOpenDetail, onSort, order, sort]);

  return (
    <div
      className="grid-view"
      role="region"
      aria-label={grouped ? "連続H1シグナル検索結果" : "H1 Elliott推移検索結果"}
      aria-busy={loading}
    >
      <Box sx={{ px: 1.5, pb: 0.75, color: "text.secondary", fontSize: "0.68rem" }}>
        {grouped && "連続FULL：同一通貨・同一方向で連続する市場H1を1シグナルに集約 / "}
        各時間足：BUY/SELL / Elliott（主波・下位波） / 波方向（▲上昇・▼下降）・状態 / EMA200 / GMMA（Trend・Cross）
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
          rowHeight={64}
          styleNonce={styleNonce}
          theme={observationGridTheme}
        />
      </div>
    </div>
  );
}
