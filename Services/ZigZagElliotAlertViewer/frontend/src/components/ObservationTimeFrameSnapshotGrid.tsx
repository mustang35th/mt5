import {
  ClientSideRowModelModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  type ColumnGroupOpenedEvent,
  type GridApi,
  type GridReadyEvent,
  RenderApiModule,
  RowStyleModule,
  ScrollApiModule,
  themeQuartz,
  type ColDef,
  type ColGroupDef,
  type ICellRendererParams,
  type RowClassParams,
  type RowStyle,
} from "ag-grid-community";
import { AgGridReact } from "ag-grid-react";
import useMediaQuery from "@mui/material/useMediaQuery";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ObservationDetailTimeFrame } from "../api/types";
import {
  displayValue,
  elliottDirectionSymbol,
  formatElliottDirection,
  formatNumber,
  formatSignedNumber,
  sideClass,
} from "../lib/format";
import {
  clearTimeFrameComparisonColumnGroupState,
  defaultTimeFrameComparisonColumnGroupState,
  readTimeFrameComparisonColumnGroupState,
  TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS,
  type TimeFrameComparisonColumnGroupId,
  type TimeFrameComparisonColumnGroupState,
  writeTimeFrameComparisonColumnGroupState,
} from "../lib/timeFrameComparisonPreferences";
import { Ema200SignalBadge } from "./Ema200SignalBadge";

export interface ObservationTimeFrameSnapshotGridProps {
  ariaLabel?: string;
  showLatestPointDetails?: boolean;
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
  ScrollApiModule,
];

const TIME_FRAME_COLUMN_ID = "time_frame_text";
const EMA200_DIRECTION_COLUMN_ID = "ema200_direction";
const WAVE_DIRECTION_COLUMN_ID = "wave_direction";
const LATEST_POINT_SUMMARY_COLUMN_ID = "latest_point_summary";
const LATEST_POINT_SHAPE_COLUMN_ID = "latest_point_shape";
const LATEST_POINT_RATE_COLUMN_ID = "latest_point_rate";
const FIBO_EXPANSION_STATUS_COLUMN_ID = "fibo_expansion_status";
const OSCILLATOR_COLUMN_ID = "oscillator";
const GMMA_TREND_CROSS_COLUMN_ID = "gmma_trend_cross";
const EMA200_CLOSE_SHIFT_COLUMN_ID = "ema200_close1_shift1";
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

type Ema200AvailabilityTimeFrame = ObservationDetailTimeFrame & {
  is_ema200_available?: boolean;
};

type ColumnGroupPresetId =
  | "essentials"
  | "wave"
  | "zigzag_point"
  | "price_fibo"
  | "oscillator"
  | "ema200"
  | "all";

interface ColumnGroupPreset {
  id: ColumnGroupPresetId;
  label: string;
  groups: TimeFrameComparisonColumnGroupState;
  focusColumnId: string;
}

const COLUMN_GROUP_PRESETS: readonly ColumnGroupPreset[] = [
  {
    id: "essentials",
    label: "要点のみ",
    groups: columnGroupState(),
    focusColumnId: WAVE_DIRECTION_COLUMN_ID,
  },
  {
    id: "wave",
    label: "波動",
    groups: columnGroupState("wave"),
    focusColumnId: WAVE_DIRECTION_COLUMN_ID,
  },
  {
    id: "zigzag_point",
    label: "ZigZag Point",
    groups: columnGroupState("zigzag_point"),
    focusColumnId: LATEST_POINT_SHAPE_COLUMN_ID,
  },
  {
    id: "price_fibo",
    label: "価格・Fibo",
    groups: columnGroupState("price", "fibo_expansion"),
    focusColumnId: LATEST_POINT_RATE_COLUMN_ID,
  },
  {
    id: "oscillator",
    label: "オシレーター",
    groups: columnGroupState("oscillator_stochastic"),
    focusColumnId: OSCILLATOR_COLUMN_ID,
  },
  {
    id: "ema200",
    label: "EMA200検証",
    groups: columnGroupState("trend_ema"),
    focusColumnId: EMA200_CLOSE_SHIFT_COLUMN_ID,
  },
  {
    id: "all",
    label: "すべて展開",
    groups: columnGroupState(...TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS),
    focusColumnId: WAVE_DIRECTION_COLUMN_ID,
  },
];

/**
 * 指定したグループだけを開いた状態を生成します。
 *
 * @param fromOpenGroupIds 開くグループID
 * @return 列グループ開閉状態
 */
function columnGroupState(
  ...fromOpenGroupIds: TimeFrameComparisonColumnGroupId[]
): TimeFrameComparisonColumnGroupState {
  const state = defaultTimeFrameComparisonColumnGroupState();
  for (const groupId of fromOpenGroupIds) {
    state[groupId] = true;
  }
  return state;
}

/**
 * 開閉状態に一致するプリセットを返します。
 *
 * @param fromState 現在の開閉状態
 * @return 一致するプリセットID
 */
function matchingColumnGroupPreset(
  fromState: TimeFrameComparisonColumnGroupState,
  fromGroupIds: readonly TimeFrameComparisonColumnGroupId[],
): ColumnGroupPresetId | null {
  for (const preset of COLUMN_GROUP_PRESETS) {
    const matches = fromGroupIds.every(
      (groupId) => preset.groups[groupId] === fromState[groupId],
    );
    if (matches) return preset.id;
  }
  return null;
}

/**
 * Grid APIの列グループ状態から許可グループだけを取得します。
 *
 * @param fromApi Grid API
 * @param fromState 現在の列グループ開閉状態
 * @param fromGroupIds この画面で有効な列グループID
 * @return 列グループ開閉状態
 */
function columnGroupStateFromApi(
  fromApi: GridApi<ObservationDetailTimeFrame>,
  fromState: TimeFrameComparisonColumnGroupState,
  fromGroupIds: readonly TimeFrameComparisonColumnGroupId[],
): TimeFrameComparisonColumnGroupState {
  const state = { ...fromState };
  const gridState = new Map(
    fromApi.getColumnGroupState().map((item) => [item.groupId, item.open]),
  );
  for (const groupId of fromGroupIds) {
    state[groupId] = gridState.get(groupId) === true;
  }
  return state;
}

/**
 * 列グループ開閉状態を保存します。
 *
 * @param fromState 保存する開閉状態
 */
function persistColumnGroupState(
  fromState: TimeFrameComparisonColumnGroupState,
): void {
  const hasOpenGroup = TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS.some(
    (groupId) => fromState[groupId],
  );
  if (hasOpenGroup) {
    writeTimeFrameComparisonColumnGroupState(fromState);
  } else {
    clearTimeFrameComparisonColumnGroupState();
  }
}

function waveLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (typeof timeFrame.is_wave_uptrend !== "boolean") {
    return "—";
  }

  const main = displayValue(timeFrame.latest_elliot_label);
  const sub = displayValue(timeFrame.latest_sub_elliot_label);
  return `${elliottDirectionSymbol(timeFrame.is_wave_uptrend)}${main} [${timeFrame.latest_elliot_index}] / ${sub} [${timeFrame.latest_sub_elliot_index}]`;
}

function booleanLabel(
  value: boolean | null | undefined,
  trueLabel: string,
  falseLabel: string,
): string {
  if (typeof value !== "boolean") {
    return "—";
  }
  if (value) {
    return trueLabel;
  }
  return falseLabel;
}

/**
 * 最新ZigZagポイントの保存状態を表示します。
 *
 * @param timeFrame 時間足スナップショット
 * @return 通常、追加ポイントまたは未記録
 */
function zigZagStateLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (typeof timeFrame.latest_point_is_added !== "boolean") {
    return "未記録";
  }
  if (timeFrame.latest_point_is_added) {
    return "追加ポイント";
  }
  return "通常";
}

function isRecordedNumber(value: number | null | undefined): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isRecordedPositiveNumber(value: number | null | undefined): value is number {
  return isRecordedNumber(value) && value > 0;
}

function numberWithUnit(
  value: number | null | undefined,
  digits: number,
  unit: string,
): string {
  if (!isRecordedNumber(value)) return "—";
  return `${formatNumber(value, digits)}${unit}`;
}

function signedNumberWithUnit(
  value: number | null | undefined,
  digits: number,
  unit: string,
): string {
  if (!isRecordedNumber(value)) return "—";
  return `${formatSignedNumber(value, digits)}${unit}`;
}

function latestPointShapeLabel(timeFrame: ObservationDetailTimeFrame): string {
  return booleanLabel(timeFrame.latest_point_is_peak, "Peak", "Bottom");
}

function latestPointSummaryLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (typeof timeFrame.latest_point_is_peak !== "boolean") return "未記録";
  return `${latestPointShapeLabel(timeFrame)} / ${numberWithUnit(
    timeFrame.latest_point_wave_bars_from_start,
    0,
    "本",
  )} / ${signedNumberWithUnit(timeFrame.latest_point_pips_diff, 1, " pips")}`;
}

function latestPointFibonacciLabel(timeFrame: ObservationDetailTimeFrame): string {
  const originalIndex = timeFrame.latest_point_org_elliot_index;
  if (!isRecordedNumber(originalIndex)) return "未記録";
  if (originalIndex <= 1) return "対象外";
  if (originalIndex % 2 === 0) {
    if (!isRecordedPositiveNumber(timeFrame.latest_point_fibonacci_percent)) {
      return "未記録";
    }
    const fibonacci = numberWithUnit(
      timeFrame.latest_point_fibonacci_percent,
      1,
      "%",
    );
    return fibonacci === "—" ? "未記録" : `F ${fibonacci}`;
  }
  if (!isRecordedPositiveNumber(
    timeFrame.latest_point_fibonacci_expansion_percent,
  )) {
    return "未記録";
  }
  const expansion = numberWithUnit(
    timeFrame.latest_point_fibonacci_expansion_percent,
    1,
    "%",
  );
  return expansion === "—" ? "未記録" : `FE ${expansion}`;
}

function latestPointFiboDepthLabel(timeFrame: ObservationDetailTimeFrame): string {
  const originalIndex = timeFrame.latest_point_org_elliot_index;
  if (!isRecordedNumber(originalIndex)) return "未記録";
  if (originalIndex <= 1 || originalIndex % 2 !== 0) return "対象外";
  if (!isRecordedPositiveNumber(timeFrame.latest_point_fibonacci_percent)) {
    return "未記録";
  }
  const label = typeof timeFrame.latest_point_fibo_depth_zone_label === "string"
    ? timeFrame.latest_point_fibo_depth_zone_label.trim()
    : "";
  const hasZone = isRecordedNumber(timeFrame.latest_point_fibo_depth_zone);
  if (!label && !hasZone) return "未記録";
  if (!hasZone) return label;
  if (!label) return `[${formatNumber(timeFrame.latest_point_fibo_depth_zone, 0)}]`;
  return `${label} [${formatNumber(timeFrame.latest_point_fibo_depth_zone, 0)}]`;
}

function latestPointElliottKindLabel(timeFrame: ObservationDetailTimeFrame): string {
  return booleanLabel(
    timeFrame.latest_point_is_elliot_alphabet,
    "Alphabet波",
    "数字波",
  );
}

function elliottPointLabel(
  label: string | null | undefined,
  index: number | null | undefined,
): string {
  const normalizedLabel = typeof label === "string" ? label.trim() : "";
  if (!normalizedLabel) return "—";
  if (!isRecordedNumber(index)) return normalizedLabel;
  return `${normalizedLabel} [${formatNumber(index, 0)}]`;
}

function latestPointReanalysisLabel(timeFrame: ObservationDetailTimeFrame): string {
  const original = elliottPointLabel(
    timeFrame.latest_point_org_elliot_label,
    timeFrame.latest_point_org_elliot_index,
  );
  if (original === "—") return "—";
  const current = elliottPointLabel(
    timeFrame.latest_elliot_label,
    timeFrame.latest_elliot_index,
  );
  if (current === "—") return original;
  return `${original} → ${current}`;
}

function latestPointCorrectionLabel(timeFrame: ObservationDetailTimeFrame): string {
  return booleanLabel(timeFrame.latest_point_is_correct, "補正済", "未補正");
}

function formatStoredEpoch(value: number | null | undefined): string {
  if (!isRecordedNumber(value) || value <= 0) return "—";
  const date = new Date(value * 1_000);
  if (Number.isNaN(date.getTime())) return "—";
  const pad = (part: number) => String(part).padStart(2, "0");
  return `${date.getUTCFullYear()}.${pad(date.getUTCMonth() + 1)}.${pad(
    date.getUTCDate(),
  )} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`;
}

function latestPointBarPositionLabel(timeFrame: ObservationDetailTimeFrame): string {
  const parts: string[] = [];
  if (isRecordedNumber(timeFrame.latest_point_bar_index)) {
    parts.push(`#${formatNumber(timeFrame.latest_point_bar_index, 0)}`);
  }
  const timeNext = formatStoredEpoch(timeFrame.latest_point_time_next);
  if (timeNext !== "—") parts.push(timeNext);
  return parts.length > 0 ? parts.join(" / ") : "—";
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

type SnapshotSignedValueTone = "positive" | "negative" | "neutral";

interface SnapshotSignedValuePart {
  kind: "signed";
  value: number | null | undefined;
  digits: number;
  tone: SnapshotSignedValueTone | undefined;
}

type SnapshotCellPart = string | SnapshotSignedValuePart;

type SnapshotCellParts = (
  timeFrame: ObservationDetailTimeFrame,
) => SnapshotCellPart[];

function signedValueTone(
  value: number | null | undefined,
): SnapshotSignedValueTone {
  const number = Number(value);
  if (!Number.isFinite(number) || number === 0) return "neutral";
  return number > 0 ? "positive" : "negative";
}

function ema200CodeTone(value: number): SnapshotSignedValueTone {
  if (value === 1) return "positive";
  if (value === -1) return "negative";
  return "neutral";
}

function signedValue(
  value: number | null | undefined,
  digits = 1,
  tone?: SnapshotSignedValueTone,
): SnapshotSignedValuePart {
  return { kind: "signed", value, digits, tone };
}

function signedSnapshotCellRenderer(fromParts: SnapshotCellParts) {
  return function SignedSnapshotCellRenderer(
    params: ICellRendererParams<ObservationDetailTimeFrame, string>,
  ) {
    const timeFrame = params.data;
    if (!timeFrame) return null;
    return (
      <span className="snapshot-signed-cell">
        {fromParts(timeFrame).map((part, index) => {
          if (typeof part === "string") return part;
          return (
            <span
              className={`snapshot-signed-value ${part.tone ?? signedValueTone(part.value)}`}
              key={`signed-${index}`}
            >
              {formatSignedNumber(part.value, part.digits)}
            </span>
          );
        })}
      </span>
    );
  };
}

function ema200Direction(timeFrame: ObservationDetailTimeFrame): string {
  const availableTimeFrame = timeFrame as Ema200AvailabilityTimeFrame;
  if (availableTimeFrame.is_ema200_available === false) {
    return "記録なし";
  }
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

/**
 * グループ展開時だけ表示する詳細列を生成します。
 *
 * @param colId 列ID
 * @param headerName 見出し
 * @param initialWidth 初期幅
 * @param formatter 表示値生成処理
 * @return 詳細列定義
 */
function detailSnapshotColumn(
  colId: string,
  headerName: string,
  initialWidth: number,
  formatter: SnapshotFormatter,
): ColDef<ObservationDetailTimeFrame, string> {
  return {
    ...snapshotColumn(colId, headerName, initialWidth, formatter),
    columnGroupShow: "open",
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
  const timeFrame = params.data as Ema200AvailabilityTimeFrame;
  return (
    <Ema200SignalBadge
      available={timeFrame.is_ema200_available !== false}
      timeFrame={timeFrame}
    />
  );
}

function ElliottWaveDirectionCell(
  params: ICellRendererParams<ObservationDetailTimeFrame, string>,
) {
  const timeFrame = params.data;
  if (!timeFrame) return null;
  let directionClass = "";
  if (typeof timeFrame.is_wave_uptrend === "boolean") {
    if (timeFrame.is_wave_uptrend) {
      directionClass = " uptrend";
    } else {
      directionClass = " downtrend";
    }
  }
  return (
    <span className={`snapshot-elliott-wave-value${directionClass}`}>
      {displayValue(params.value)}
    </span>
  );
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

const latestZigZagPointColumnGroup: ColGroupDef<ObservationDetailTimeFrame> = {
  groupId: "zigzag_point",
  headerName: "最新ZigZag Point",
  marryChildren: true,
  openByDefault: false,
  children: [
    {
      ...snapshotColumn(
        LATEST_POINT_SUMMARY_COLUMN_ID,
        "Point要約",
        210,
        latestPointSummaryLabel,
      ),
      columnGroupShow: "closed",
    },
    detailSnapshotColumn(
      LATEST_POINT_SHAPE_COLUMN_ID,
      "Point形状",
      112,
      latestPointShapeLabel,
    ),
    detailSnapshotColumn(
      "latest_point_wave_bars_from_start",
      "Wave経過",
      112,
      (timeFrame) => numberWithUnit(
        timeFrame.latest_point_wave_bars_from_start,
        0,
        "本",
      ),
    ),
    {
      ...detailSnapshotColumn(
        "latest_point_pips_diff",
        "価格差",
        132,
        (timeFrame) => signedNumberWithUnit(
          timeFrame.latest_point_pips_diff,
          1,
          " pips",
        ),
      ),
      cellRenderer: signedSnapshotCellRenderer((timeFrame) => {
        if (!isRecordedNumber(timeFrame.latest_point_pips_diff)) return ["—"];
        return [signedValue(timeFrame.latest_point_pips_diff), " pips"];
      }),
    },
    detailSnapshotColumn(
      "latest_point_fibonacci",
      "F / FE",
      132,
      latestPointFibonacciLabel,
    ),
    detailSnapshotColumn(
      "latest_point_fibo_depth_zone",
      "Depth Zone",
      132,
      latestPointFiboDepthLabel,
    ),
    detailSnapshotColumn(
      "latest_point_elliott_kind",
      "ラベル種別",
      122,
      latestPointElliottKindLabel,
    ),
    detailSnapshotColumn(
      "latest_point_reanalysis",
      "再分析",
      178,
      latestPointReanalysisLabel,
    ),
    detailSnapshotColumn(
      "latest_point_correction",
      "補正状態",
      112,
      latestPointCorrectionLabel,
    ),
    detailSnapshotColumn(
      "latest_point_bar_position",
      "Bar / 次足開始",
      226,
      latestPointBarPositionLabel,
    ),
  ],
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
      {
        ...pinnedSnapshotColumn("elliott_sub", "Elliott / Sub", 210, waveLabel),
        cellRenderer: ElliottWaveDirectionCell,
      },
    ],
  },
  {
    groupId: "wave",
    headerName: "波動",
    marryChildren: true,
    openByDefault: false,
    children: [
      {
        ...snapshotColumn(
          WAVE_DIRECTION_COLUMN_ID,
          "Wave方向",
          96,
          (timeFrame) => booleanLabel(
            timeFrame.is_wave_uptrend,
            formatElliottDirection(true),
            formatElliottDirection(false),
          ),
        ),
        cellRenderer: ElliottWaveDirectionCell,
      },
      detailSnapshotColumn(
        "wave_state",
        "Wave状態",
        96,
        (timeFrame) => booleanLabel(timeFrame.is_wave_confirmed, "確定", "形成中"),
      ),
      detailSnapshotColumn(
        "zigzag_state",
        "ZigZag状態",
        116,
        zigZagStateLabel,
      ),
      detailSnapshotColumn(
        "wave_type",
        "Wave種別",
        96,
        (timeFrame) => booleanLabel(timeFrame.is_wave_motive, "推進波", "修正波"),
      ),
      detailSnapshotColumn(
        "wave_count_latest_index",
        "Wave数 / 最新index",
        152,
        (timeFrame) => `${formatNumber(timeFrame.wave_count, 0)} / ${formatNumber(timeFrame.latest_wave_index, 0)}`,
      ),
      detailSnapshotColumn(
        "previous_last_elliot_label",
        "前回Wave最終",
        132,
        (timeFrame) => displayValue(timeFrame.previous_last_elliot_label),
      ),
      detailSnapshotColumn(
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
    marryChildren: true,
    openByDefault: false,
    children: [
      detailSnapshotColumn(
        "latest_point_jst_time_text",
        "最新点 JST",
        172,
        (timeFrame) => displayValue(timeFrame.latest_point_jst_time_text),
      ),
      detailSnapshotColumn(
        "latest_point_time_text",
        "最新点 Server",
        172,
        (timeFrame) => displayValue(timeFrame.latest_point_time_text),
      ),
      snapshotColumn(
        LATEST_POINT_RATE_COLUMN_ID,
        "最新点価格",
        118,
        (timeFrame) => formatNumber(timeFrame.latest_point_rate, 5),
      ),
      detailSnapshotColumn(
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
      detailSnapshotColumn(
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
    marryChildren: true,
    openByDefault: false,
    children: [
      snapshotColumn(
        FIBO_EXPANSION_STATUS_COLUMN_ID,
        "Fibo / FE",
        104,
        (timeFrame) => booleanLabel(
          timeFrame.is_fibo_expansion_available,
          "取得済",
          "未取得",
        ),
      ),
      detailSnapshotColumn(
        "fe618_fe1000",
        "FE 61.8 / 100.0",
        228,
        (timeFrame) => `${fePrice(timeFrame, timeFrame.fe618_price)} / ${fePrice(timeFrame, timeFrame.fe1000_price)}`,
      ),
      detailSnapshotColumn(
        "fe1272_fe1618",
        "FE 127.2 / 161.8",
        228,
        (timeFrame) => `${fePrice(timeFrame, timeFrame.fe1272_price)} / ${fePrice(timeFrame, timeFrame.fe1618_price)}`,
      ),
      detailSnapshotColumn(
        "fe2000_price",
        "FE 200.0",
        122,
        (timeFrame) => fePrice(timeFrame, timeFrame.fe2000_price),
      ),
      detailSnapshotColumn(
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
    marryChildren: true,
    openByDefault: false,
    children: [
      {
        ...snapshotColumn(
          OSCILLATOR_COLUMN_ID,
          "Oscillator",
          164,
          (timeFrame) => {
            if (typeof timeFrame.is_oscillator_buy !== "boolean") {
              return "—";
            }
            let direction = "SELL";
            if (timeFrame.is_oscillator_buy) {
              direction = "BUY";
            }
            return `${direction} / count ${formatSignedNumber(timeFrame.oscillator_count, 0)}`;
          },
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => {
          if (typeof timeFrame.is_oscillator_buy !== "boolean") {
            return ["—"];
          }
          let direction = "SELL";
          if (timeFrame.is_oscillator_buy) {
            direction = "BUY";
          }
          return [
            `${direction} / count `,
            signedValue(timeFrame.oscillator_count, 0),
          ];
        }),
      },
      detailSnapshotColumn(
        "stochastic",
        "Stochastic",
        232,
        (timeFrame) => `${displayValue(timeFrame.stochastic_main_order_text)} / ${displayValue(timeFrame.stochastic_main_direction_text)} [${formatNumber(timeFrame.stochastic_main_order, 0)}]`,
      ),
      {
        ...detailSnapshotColumn(
          "stochastic_short",
          "Stoch 短期",
          252,
          (timeFrame) => stochasticLabel(
            timeFrame.stochastic_short_count,
            timeFrame.stochastic_short_main,
            timeFrame.stochastic_short_signal,
          ),
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          "count ",
          signedValue(timeFrame.stochastic_short_count, 0),
          ` / Main ${formatNumber(timeFrame.stochastic_short_main, 2)} / Signal ${formatNumber(timeFrame.stochastic_short_signal, 2)}`,
        ]),
      },
      {
        ...detailSnapshotColumn(
          "stochastic_middle",
          "Stoch 中期",
          252,
          (timeFrame) => stochasticLabel(
            timeFrame.stochastic_middle_count,
            timeFrame.stochastic_middle_main,
            timeFrame.stochastic_middle_signal,
          ),
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          "count ",
          signedValue(timeFrame.stochastic_middle_count, 0),
          ` / Main ${formatNumber(timeFrame.stochastic_middle_main, 2)} / Signal ${formatNumber(timeFrame.stochastic_middle_signal, 2)}`,
        ]),
      },
      {
        ...detailSnapshotColumn(
          "stochastic_long",
          "Stoch 長期",
          252,
          (timeFrame) => stochasticLabel(
            timeFrame.stochastic_long_count,
            timeFrame.stochastic_long_main,
            timeFrame.stochastic_long_signal,
          ),
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          "count ",
          signedValue(timeFrame.stochastic_long_count, 0),
          ` / Main ${formatNumber(timeFrame.stochastic_long_main, 2)} / Signal ${formatNumber(timeFrame.stochastic_long_signal, 2)}`,
        ]),
      },
    ],
  },
  {
    groupId: "trend_ema",
    headerName: "Trend / EMA",
    marryChildren: true,
    openByDefault: false,
    children: [
      {
        ...snapshotColumn(
          GMMA_TREND_CROSS_COLUMN_ID,
          "GMMA trend / cross",
          164,
          (timeFrame) => `${formatSignedNumber(timeFrame.gmma_trend_count, 0)} / ${formatSignedNumber(timeFrame.gmma_cross_count, 0)}`,
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          signedValue(timeFrame.gmma_trend_count, 0),
          " / ",
          signedValue(timeFrame.gmma_cross_count, 0),
        ]),
      },
      detailSnapshotColumn(
        "ema30_ema60",
        "EMA30 / EMA60",
        212,
        (timeFrame) => `${formatNumber(timeFrame.ema30, 5)} / ${formatNumber(timeFrame.ema60, 5)}`,
      ),
      {
        ...detailSnapshotColumn(
          "ema30_ema60_diff_pips",
          "EMA30-60距離",
          142,
          (timeFrame) => `${formatSignedNumber(timeFrame.ema30_ema60_diff_pips)} pips`,
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          signedValue(timeFrame.ema30_ema60_diff_pips),
          " pips",
        ]),
      },
      detailSnapshotColumn(
        "atr14_pips",
        "ATR14",
        112,
        (timeFrame) => `${formatNumber(timeFrame.atr14_pips)} pips`,
      ),
      detailSnapshotColumn(
        "ema200_close1_shift1",
        "EMA200 Close1 / Shift1",
        226,
        (timeFrame) => `${formatNumber(timeFrame.ema200_close1, 5)} / ${formatNumber(timeFrame.ema200_shift1, 5)}`,
      ),
      detailSnapshotColumn(
        "ema200_compare",
        "EMA200比較値",
        142,
        (timeFrame) => formatNumber(timeFrame.ema200_compare, 5),
      ),
      {
        ...detailSnapshotColumn(
          "ema200_slope_distance",
          "EMA200傾き / 距離",
          178,
          (timeFrame) => `${formatSignedNumber(timeFrame.ema200_slope_pips)} / ${formatSignedNumber(timeFrame.ema200_close_diff_pips)} pips`,
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          signedValue(timeFrame.ema200_slope_pips),
          " / ",
          signedValue(timeFrame.ema200_close_diff_pips),
          " pips",
        ]),
      },
      {
        ...detailSnapshotColumn(
          "ema200_position_slope_code",
          "EMA200位置 / 傾きcode",
          192,
          (timeFrame) => `${formatSignedNumber(timeFrame.ema200_close_position, 0)} / ${formatSignedNumber(timeFrame.ema200_slope_direction, 0)}`,
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          signedValue(
            timeFrame.ema200_close_position,
            0,
            ema200CodeTone(timeFrame.ema200_close_position),
          ),
          " / ",
          signedValue(
            timeFrame.ema200_slope_direction,
            0,
            ema200CodeTone(timeFrame.ema200_slope_direction),
          ),
        ]),
      },
      {
        ...detailSnapshotColumn(
          "ema200_counts",
          "EMA200 上昇 / 下降 / trend",
          218,
          (timeFrame) => `${formatNumber(timeFrame.ema200_up_count, 0)} / ${formatNumber(timeFrame.ema200_down_count, 0)} / ${formatSignedNumber(timeFrame.ema200_trend_count, 0)}`,
        ),
        cellRenderer: signedSnapshotCellRenderer((timeFrame) => [
          `${formatNumber(timeFrame.ema200_up_count, 0)} / ${formatNumber(timeFrame.ema200_down_count, 0)} / `,
          signedValue(timeFrame.ema200_trend_count, 0),
        ]),
      },
    ],
  },
];

function columnDefs(
  showLatestPointDetails: boolean,
): Array<ColDef<ObservationDetailTimeFrame> | ColGroupDef<ObservationDetailTimeFrame>> {
  if (!showLatestPointDetails) return COLUMN_DEFS;
  return [
    COLUMN_DEFS[0],
    COLUMN_DEFS[1],
    latestZigZagPointColumnGroup,
    ...COLUMN_DEFS.slice(2),
  ];
}

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
  ariaLabel = "時間足別 H1新規足スナップショットグリッド",
  showLatestPointDetails = false,
  timeFrames,
  styleNonce,
}: ObservationTimeFrameSnapshotGridProps) {
  const gridApiRef = useRef<GridApi<ObservationDetailTimeFrame> | null>(null);
  const wideLayout = useMediaQuery("(min-width: 761px)");
  const [gridReady, setGridReady] = useState(false);
  const [columnGroupStateValue, setColumnGroupStateValue] = useState(
    readTimeFrameComparisonColumnGroupState,
  );
  const effectiveGroupIds = useMemo(
    () => TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS.filter(
      (groupId) => showLatestPointDetails || groupId !== "zigzag_point",
    ),
    [showLatestPointDetails],
  );
  const availablePresets = useMemo(
    () => COLUMN_GROUP_PRESETS.filter(
      (preset) => showLatestPointDetails || preset.id !== "zigzag_point",
    ),
    [showLatestPointDetails],
  );
  const gridColumnDefs = useMemo(
    () => columnDefs(showLatestPointDetails),
    [showLatestPointDetails],
  );
  const rowData = useMemo(() => orderedTimeFrames(timeFrames), [timeFrames]);
  const activePresetId = useMemo(
    () => matchingColumnGroupPreset(columnGroupStateValue, effectiveGroupIds),
    [columnGroupStateValue, effectiveGroupIds],
  );

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
    event.api.setColumnGroupState(
      effectiveGroupIds.map((groupId) => ({
        groupId,
        open: columnGroupStateValue[groupId],
      })),
    );
    event.api.setGridAriaProperty(
      "label",
      ariaLabel,
    );
    setGridReady(true);
  }, [applyPinning, ariaLabel, columnGroupStateValue, effectiveGroupIds]);

  const handleColumnGroupOpened = useCallback((
    event: ColumnGroupOpenedEvent<ObservationDetailTimeFrame>,
  ) => {
    const nextState = columnGroupStateFromApi(
      event.api,
      columnGroupStateValue,
      effectiveGroupIds,
    );
    setColumnGroupStateValue(nextState);
    persistColumnGroupState(nextState);
  }, [columnGroupStateValue, effectiveGroupIds]);

  const applyColumnGroupPreset = useCallback((fromPresetId: ColumnGroupPresetId) => {
    const api = gridApiRef.current;
    const preset = COLUMN_GROUP_PRESETS.find((item) => item.id === fromPresetId);
    if (!api || !preset) return;

    const nextState = { ...columnGroupStateValue };
    for (const groupId of effectiveGroupIds) {
      nextState[groupId] = preset.groups[groupId];
    }
    api.setColumnGroupState(
      effectiveGroupIds.map((groupId) => ({
        groupId,
        open: nextState[groupId],
      })),
    );
    setColumnGroupStateValue(nextState);
    persistColumnGroupState(nextState);
    api.ensureColumnVisible(preset.focusColumnId, "start");
  }, [columnGroupStateValue, effectiveGroupIds]);

  const resetColumnGroupState = useCallback(() => {
    const api = gridApiRef.current;
    if (!api) return;

    const nextState = defaultTimeFrameComparisonColumnGroupState();
    api.resetColumnGroupState();
    setColumnGroupStateValue(nextState);
    clearTimeFrameComparisonColumnGroupState();
    api.ensureColumnVisible(WAVE_DIRECTION_COLUMN_ID, "start");
  }, []);

  useEffect(() => {
    if (gridApiRef.current) applyPinning(gridApiRef.current);
  }, [applyPinning]);

  return (
    <div
      aria-label={ariaLabel}
      className="observation-timeframe-snapshot-grid"
      role="region"
      style={{ height: "100%", minHeight: 0, minWidth: 0, width: "100%" }}
    >
      <div
        aria-label="時間足比較の列表示"
        className="observation-timeframe-column-toolbar"
        role="group"
      >
        <span className="observation-timeframe-column-toolbar-label">列表示</span>
        {wideLayout ? (
          <div className="observation-timeframe-column-presets">
            {availablePresets.map((preset) => (
              <button
                aria-label={`列プリセット: ${preset.label}`}
                aria-pressed={activePresetId === preset.id}
                className="secondary-button"
                disabled={!gridReady}
                key={preset.id}
                type="button"
                onClick={() => applyColumnGroupPreset(preset.id)}
              >
                {preset.label}
              </button>
            ))}
          </div>
        ) : (
          <select
            aria-label="列プリセット"
            disabled={!gridReady}
            value={activePresetId ?? "custom"}
            onChange={(event) => applyColumnGroupPreset(
              event.target.value as ColumnGroupPresetId,
            )}
          >
            {activePresetId === null && (
              <option disabled value="custom">カスタム</option>
            )}
            {availablePresets.map((preset) => (
              <option key={preset.id} value={preset.id}>{preset.label}</option>
            ))}
          </select>
        )}
        <button
          aria-label="列表示をリセット"
          className="ghost-button observation-timeframe-column-reset"
          disabled={!gridReady}
          type="button"
          onClick={resetColumnGroupState}
        >
          列表示をリセット
        </button>
      </div>
      <div
        className="observation-timeframe-snapshot-grid-body"
        style={{ flex: "1 1 0", height: "100%", minHeight: 0 }}
      >
        <AgGridReact<ObservationDetailTimeFrame>
          animateRows={false}
          columnDefs={gridColumnDefs}
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
          onColumnGroupOpened={handleColumnGroupOpened}
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
