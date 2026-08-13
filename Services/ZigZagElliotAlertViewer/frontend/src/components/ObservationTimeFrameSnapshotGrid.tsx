import {
  ClientSideRowModelModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  type GridApi,
  type GridReadyEvent,
  RenderApiModule,
  RowStyleModule,
  themeQuartz,
  type ColDef,
  type ColGroupDef,
  type ICellRendererParams,
  type RowClassParams,
  type RowStyle,
} from "ag-grid-community";
import { AgGridReact } from "ag-grid-react";
import useMediaQuery from "@mui/material/useMediaQuery";
import { useCallback, useEffect, useMemo, useRef } from "react";
import type { ObservationDetailTimeFrame } from "../api/types";
import {
  displayValue,
  elliottDirectionSymbol,
  formatElliottDirection,
  formatNumber,
  formatSignedNumber,
  sideClass,
} from "../lib/format";
import { Ema200SignalBadge } from "./Ema200SignalBadge";

export interface ObservationTimeFrameSnapshotGridProps {
  timeFrames: readonly ObservationDetailTimeFrame[];
  styleNonce?: string;
}

export const OBSERVATION_TIME_FRAME_SNAPSHOT_ANCHOR_ROW_CLASS =
  "observation-anchor-row";

const GRID_MODULES = [
  ClientSideRowModelModule,
  ColumnApiModule,
  RenderApiModule,
  RowStyleModule,
];

const TIME_FRAME_COLUMN_ID = "time_frame_text";
const EMA200_DIRECTION_COLUMN_ID = "ema200_direction";
const DESKTOP_PINNED_COLUMN_IDS = [
  TIME_FRAME_COLUMN_ID,
  "buy_sell_label",
  EMA200_DIRECTION_COLUMN_ID,
  "elliott_sub",
] as const;

const snapshotGridTheme = themeQuartz
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
    rowHoverColor: "rgba(89, 216, 194, 0.075)",
    spacing: 6,
  });

type SnapshotFormatter = (timeFrame: ObservationDetailTimeFrame) => string;

function waveLabel(timeFrame: ObservationDetailTimeFrame): string {
  const main = displayValue(timeFrame.latest_elliot_label);
  const sub = displayValue(timeFrame.latest_sub_elliot_label);
  return `${elliottDirectionSymbol(timeFrame.is_wave_uptrend)}${main} [${timeFrame.latest_elliot_index}] / ${sub} [${timeFrame.latest_sub_elliot_index}]`;
}

function ohlcLabel(
  open: number,
  high: number,
  low: number,
  close: number,
): string {
  return `O ${formatNumber(open, 5)} / H ${formatNumber(high, 5)} / L ${formatNumber(low, 5)} / C ${formatNumber(close, 5)}`;
}

function stochasticLabel(count: number, main: number, signal: number): string {
  return `count ${formatSignedNumber(count, 0)} / Main ${formatNumber(main, 2)} / Signal ${formatNumber(signal, 2)}`;
}

function ema200Direction(timeFrame: ObservationDetailTimeFrame): string {
  if (timeFrame.is_ema200_buy && timeFrame.is_ema200_sell) return "BUY / SELL";
  if (timeFrame.is_ema200_buy) return "BUY";
  if (timeFrame.is_ema200_sell) return "SELL";
  return "NONE";
}

function fePrice(timeFrame: ObservationDetailTimeFrame, value: number): string {
  if (!timeFrame.is_fibo_expansion_available) return "—";
  return formatNumber(value, 5);
}

function snapshotColumn(
  colId: string,
  headerName: string,
  initialWidth: number,
  formatter: SnapshotFormatter,
): ColDef<ObservationDetailTimeFrame, string> {
  return {
    colId,
    headerName,
    initialWidth,
    minWidth: Math.min(initialWidth, 100),
    valueGetter: ({ data }) => data ? formatter(data) : "—",
  };
}

function pinnedSnapshotColumn(
  colId: string,
  headerName: string,
  initialWidth: number,
  formatter: SnapshotFormatter,
): ColDef<ObservationDetailTimeFrame, string> {
  return {
    ...snapshotColumn(colId, headerName, initialWidth, formatter),
    initialPinned: "left",
    lockPinned: true,
    suppressMovable: true,
  };
}

function TimeFrameCell(
  params: ICellRendererParams<ObservationDetailTimeFrame, string>,
) {
  const timeFrame = params.data;
  if (!timeFrame) return null;
  return (
    <span className="snapshot-time-frame-cell">
      <strong>{displayValue(params.value)}</strong>
      {timeFrame.is_anchor_time_frame && (
        <span className="badge neutral snapshot-anchor-badge">基準足</span>
      )}
    </span>
  );
}

function DirectionCell(
  params: ICellRendererParams<ObservationDetailTimeFrame, string>,
) {
  return (
    <span className={`badge ${sideClass(params.value)}`}>
      {displayValue(params.value)}
    </span>
  );
}

function Ema200DirectionCell(
  params: ICellRendererParams<ObservationDetailTimeFrame, string>,
) {
  if (!params.data) return null;
  return <Ema200SignalBadge timeFrame={params.data} />;
}

const timeFrameColumn: ColDef<ObservationDetailTimeFrame, string> = {
  ...pinnedSnapshotColumn(
    TIME_FRAME_COLUMN_ID,
    "時間足",
    132,
    (timeFrame) => displayValue(timeFrame.time_frame_text),
  ),
  cellAriaRole: "rowheader",
  cellRenderer: TimeFrameCell,
};

const directionColumn: ColDef<ObservationDetailTimeFrame, string> = {
  ...pinnedSnapshotColumn(
    "buy_sell_label",
    "分析方向",
    104,
    (timeFrame) => displayValue(timeFrame.buy_sell_label),
  ),
  cellRenderer: DirectionCell,
};

const ema200DirectionColumn: ColDef<ObservationDetailTimeFrame, string> = {
  ...pinnedSnapshotColumn(
    EMA200_DIRECTION_COLUMN_ID,
    "EMA200判定",
    132,
    ema200Direction,
  ),
  cellRenderer: Ema200DirectionCell,
};

const COLUMN_DEFS: Array<
  ColDef<ObservationDetailTimeFrame> | ColGroupDef<ObservationDetailTimeFrame>
> = [
  {
    groupId: "comparison_key",
    headerName: "比較キー",
    marryChildren: true,
    children: [
      timeFrameColumn,
      directionColumn,
      ema200DirectionColumn,
      pinnedSnapshotColumn("elliott_sub", "Elliott / Sub", 210, waveLabel),
    ],
  },
  {
    groupId: "wave",
    headerName: "波動",
    children: [
      snapshotColumn(
        "wave_direction",
        "Wave方向",
        96,
        (timeFrame) => formatElliottDirection(timeFrame.is_wave_uptrend),
      ),
      snapshotColumn(
        "wave_state",
        "Wave状態",
        96,
        (timeFrame) => timeFrame.is_wave_confirmed ? "確定" : "形成中",
      ),
      snapshotColumn(
        "wave_type",
        "Wave種別",
        96,
        (timeFrame) => timeFrame.is_wave_motive ? "推進波" : "修正波",
      ),
      snapshotColumn(
        "wave_count_latest_index",
        "Wave数 / 最新index",
        152,
        (timeFrame) => `${formatNumber(timeFrame.wave_count, 0)} / ${formatNumber(timeFrame.latest_wave_index, 0)}`,
      ),
      snapshotColumn(
        "previous_last_elliot_label",
        "前回Wave最終",
        132,
        (timeFrame) => displayValue(timeFrame.previous_last_elliot_label),
      ),
      snapshotColumn(
        "point_count",
        "保存ポイント数",
        122,
        (timeFrame) => formatNumber(timeFrame.point_count, 0),
      ),
    ],
  },
  {
    groupId: "price",
    headerName: "最新ポイント・価格",
    children: [
      snapshotColumn(
        "latest_point_jst_time_text",
        "最新点 JST",
        172,
        (timeFrame) => displayValue(timeFrame.latest_point_jst_time_text),
      ),
      snapshotColumn(
        "latest_point_time_text",
        "最新点 Server",
        172,
        (timeFrame) => displayValue(timeFrame.latest_point_time_text),
      ),
      snapshotColumn(
        "latest_point_rate",
        "最新点価格",
        118,
        (timeFrame) => formatNumber(timeFrame.latest_point_rate, 5),
      ),
      snapshotColumn(
        "previous_ohlc",
        "前足 OHLC",
        390,
        (timeFrame) => ohlcLabel(
          timeFrame.previous_open,
          timeFrame.previous_high,
          timeFrame.previous_low,
          timeFrame.previous_close,
        ),
      ),
      snapshotColumn(
        "current_ohlc",
        "現在足 OHLC",
        390,
        (timeFrame) => ohlcLabel(
          timeFrame.current_open,
          timeFrame.current_high,
          timeFrame.current_low,
          timeFrame.current_close,
        ),
      ),
    ],
  },
  {
    groupId: "fibo_expansion",
    headerName: "Fibo / FE",
    children: [
      snapshotColumn(
        "fibo_expansion_status",
        "Fibo / FE",
        104,
        (timeFrame) => timeFrame.is_fibo_expansion_available ? "取得済" : "未取得",
      ),
      snapshotColumn(
        "fe618_fe1000",
        "FE 61.8 / 100.0",
        228,
        (timeFrame) => `${fePrice(timeFrame, timeFrame.fe618_price)} / ${fePrice(timeFrame, timeFrame.fe1000_price)}`,
      ),
      snapshotColumn(
        "fe1272_fe1618",
        "FE 127.2 / 161.8",
        228,
        (timeFrame) => `${fePrice(timeFrame, timeFrame.fe1272_price)} / ${fePrice(timeFrame, timeFrame.fe1618_price)}`,
      ),
      snapshotColumn(
        "fe2000_price",
        "FE 200.0",
        122,
        (timeFrame) => fePrice(timeFrame, timeFrame.fe2000_price),
      ),
      snapshotColumn(
        "distance_to_fe2000_pips",
        "FE200距離",
        126,
        (timeFrame) => timeFrame.is_fibo_expansion_available
          ? `${formatNumber(timeFrame.distance_to_fe2000_pips)} pips`
          : "—",
      ),
    ],
  },
  {
    groupId: "oscillator_stochastic",
    headerName: "Oscillator / Stochastic",
    children: [
      snapshotColumn(
        "oscillator",
        "Oscillator",
        164,
        (timeFrame) => `${timeFrame.is_oscillator_buy ? "BUY" : "SELL"} / count ${formatSignedNumber(timeFrame.oscillator_count, 0)}`,
      ),
      snapshotColumn(
        "stochastic",
        "Stochastic",
        232,
        (timeFrame) => `${displayValue(timeFrame.stochastic_main_order_text)} / ${displayValue(timeFrame.stochastic_main_direction_text)} [${formatNumber(timeFrame.stochastic_main_order, 0)}]`,
      ),
      snapshotColumn(
        "stochastic_short",
        "Stoch 短期",
        252,
        (timeFrame) => stochasticLabel(
          timeFrame.stochastic_short_count,
          timeFrame.stochastic_short_main,
          timeFrame.stochastic_short_signal,
        ),
      ),
      snapshotColumn(
        "stochastic_middle",
        "Stoch 中期",
        252,
        (timeFrame) => stochasticLabel(
          timeFrame.stochastic_middle_count,
          timeFrame.stochastic_middle_main,
          timeFrame.stochastic_middle_signal,
        ),
      ),
      snapshotColumn(
        "stochastic_long",
        "Stoch 長期",
        252,
        (timeFrame) => stochasticLabel(
          timeFrame.stochastic_long_count,
          timeFrame.stochastic_long_main,
          timeFrame.stochastic_long_signal,
        ),
      ),
    ],
  },
  {
    groupId: "trend_ema",
    headerName: "Trend / EMA",
    children: [
      snapshotColumn(
        "gmma_trend_cross",
        "GMMA trend / cross",
        164,
        (timeFrame) => `${formatSignedNumber(timeFrame.gmma_trend_count, 0)} / ${formatSignedNumber(timeFrame.gmma_cross_count, 0)}`,
      ),
      snapshotColumn(
        "ema30_ema60",
        "EMA30 / EMA60",
        212,
        (timeFrame) => `${formatNumber(timeFrame.ema30, 5)} / ${formatNumber(timeFrame.ema60, 5)}`,
      ),
      snapshotColumn(
        "ema30_ema60_diff_pips",
        "EMA30-60距離",
        142,
        (timeFrame) => `${formatSignedNumber(timeFrame.ema30_ema60_diff_pips)} pips`,
      ),
      snapshotColumn(
        "atr14_pips",
        "ATR14",
        112,
        (timeFrame) => `${formatNumber(timeFrame.atr14_pips)} pips`,
      ),
      snapshotColumn(
        "ema200_close1_shift1",
        "EMA200 Close1 / Shift1",
        226,
        (timeFrame) => `${formatNumber(timeFrame.ema200_close1, 5)} / ${formatNumber(timeFrame.ema200_shift1, 5)}`,
      ),
      snapshotColumn(
        "ema200_compare",
        "EMA200比較値",
        142,
        (timeFrame) => formatNumber(timeFrame.ema200_compare, 5),
      ),
      snapshotColumn(
        "ema200_slope_distance",
        "EMA200傾き / 距離",
        178,
        (timeFrame) => `${formatSignedNumber(timeFrame.ema200_slope_pips)} / ${formatSignedNumber(timeFrame.ema200_close_diff_pips)} pips`,
      ),
      snapshotColumn(
        "ema200_position_slope_code",
        "EMA200位置 / 傾きcode",
        192,
        (timeFrame) => `${formatSignedNumber(timeFrame.ema200_close_position, 0)} / ${formatSignedNumber(timeFrame.ema200_slope_direction, 0)}`,
      ),
      snapshotColumn(
        "ema200_counts",
        "EMA200 上昇 / 下降 / trend",
        218,
        (timeFrame) => `${formatNumber(timeFrame.ema200_up_count, 0)} / ${formatNumber(timeFrame.ema200_down_count, 0)} / ${formatSignedNumber(timeFrame.ema200_trend_count, 0)}`,
      ),
    ],
  },
];

function orderedTimeFrames(
  timeFrames: readonly ObservationDetailTimeFrame[],
): ObservationDetailTimeFrame[] {
  return [...timeFrames].sort((left, right) => {
    const orderDifference = left.time_frame_order - right.time_frame_order;
    if (orderDifference !== 0) return orderDifference;
    return left.id - right.id;
  });
}

function snapshotRowClass(
  params: RowClassParams<ObservationDetailTimeFrame>,
): string | undefined {
  if (params.data?.is_anchor_time_frame) {
    return OBSERVATION_TIME_FRAME_SNAPSHOT_ANCHOR_ROW_CLASS;
  }
  return undefined;
}

function snapshotRowStyle(
  params: RowClassParams<ObservationDetailTimeFrame>,
): RowStyle | undefined {
  if (!params.data?.is_anchor_time_frame) return undefined;
  return {
    backgroundColor: "rgba(89, 216, 194, 0.10)",
  };
}

function EmptySnapshotOverlay() {
  return (
    <div className="empty-state grid-empty-state">
      <strong>時間足スナップショットがありません</strong>
    </div>
  );
}

export function ObservationTimeFrameSnapshotGrid({
  timeFrames,
  styleNonce,
}: ObservationTimeFrameSnapshotGridProps) {
  const gridApiRef = useRef<GridApi<ObservationDetailTimeFrame> | null>(null);
  const wideLayout = useMediaQuery("(min-width: 761px)");
  const rowData = useMemo(() => orderedTimeFrames(timeFrames), [timeFrames]);

  const applyPinning = useCallback((api: GridApi<ObservationDetailTimeFrame>) => {
    api.setColumnsPinned([...DESKTOP_PINNED_COLUMN_IDS], null);
    api.setColumnsPinned(
      wideLayout ? [...DESKTOP_PINNED_COLUMN_IDS] : [TIME_FRAME_COLUMN_ID],
      "left",
    );
  }, [wideLayout]);

  const handleGridReady = useCallback((event: GridReadyEvent<ObservationDetailTimeFrame>) => {
    gridApiRef.current = event.api;
    applyPinning(event.api);
    event.api.setGridAriaProperty(
      "label",
      "時間足別 H1新規足スナップショットグリッド",
    );
  }, [applyPinning]);

  useEffect(() => {
    if (gridApiRef.current) applyPinning(gridApiRef.current);
  }, [applyPinning]);

  return (
    <div
      aria-label="時間足別 H1新規足スナップショットグリッド"
      className="observation-timeframe-snapshot-grid"
      role="region"
      style={{ height: "100%", minHeight: 0, minWidth: 0, width: "100%" }}
    >
      <div
        className="observation-timeframe-snapshot-grid-body"
        style={{ flex: "1 1 0", height: "100%", minHeight: 0 }}
      >
        <AgGridReact<ObservationDetailTimeFrame>
          animateRows={false}
          columnDefs={COLUMN_DEFS}
          defaultColDef={{
            filter: false,
            resizable: true,
            sortable: false,
            suppressHeaderMenuButton: true,
          }}
          domLayout="normal"
          ensureDomOrder
          getRowClass={snapshotRowClass}
          getRowId={({ data }) => String(data.id)}
          getRowStyle={snapshotRowStyle}
          groupHeaderHeight={32}
          headerHeight={36}
          maintainColumnOrder
          modules={GRID_MODULES}
          noRowsOverlayComponent={EmptySnapshotOverlay}
          onGridReady={handleGridReady}
          pagination={false}
          rowData={rowData}
          rowHeight={44}
          styleNonce={styleNonce}
          suppressColumnVirtualisation
          theme={snapshotGridTheme}
        />
      </div>
    </div>
  );
}
