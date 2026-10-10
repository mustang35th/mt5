import {
  ClientSideRowModelModule,
  CellStyleModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  RenderApiModule,
  RowStyleModule,
  themeQuartz,
  type ColDef,
  type GridState,
  type ICellRendererParams,
  type RowClassParams,
} from "ag-grid-community";
import { AgGridReact } from "ag-grid-react";
import { type MouseEvent, type ReactNode, type RefObject, useEffect, useMemo, useRef, useState } from "react";
import { api } from "../api/client";
import type {
  AlertDetailResponse,
  AlertNavigationItem,
  AlertNavigationResponse,
  AlertPoint,
  AlertTimeFrame,
  ObservationDetailTimeFrame,
  PointsResponse,
  SearchState,
  TimeFramesResponse,
} from "../api/types";
import {
  displayValue,
  elliottDirectionSymbol,
  formatAlertBarTimes,
  formatElliottLabel,
  formatNumber,
  formatSignedNumber,
  sideClass,
} from "../lib/format";
import { CurrencyStrengthSnapshotPanel } from "./CurrencyStrengthSnapshotPanel";
import { ElliottLabelText } from "./ElliottLabelText";
import { Ema200SignalBadge } from "./Ema200SignalBadge";
import { GmoTargetBadge } from "./GmoTargetBadge";
import {
  H1DirectionAlignmentBadge,
  h1DirectionAlignmentModeLabel,
  h1DirectionAlignmentStateDescription,
} from "./H1DirectionAlignmentBadge";
import { H1EntryCheckPanel } from "./H1EntryCheckPanel";
import { AlertCorrectionSnapshot, M5AlertSnapshot } from "./M5AlertSnapshot";
import { ObservationTimeFrameSnapshotGrid } from "./ObservationTimeFrameSnapshotGrid";
import {
  W1ConfirmationBadge,
  w1ConfirmationModeLabel,
  w1ConfirmationStateDescription,
} from "./W1ConfirmationBadge";
import "./AlertDetailDrawer.css";

export type AlertDetailView = "detail" | "comparison";

interface AlertDetailDrawerProps {
  alertId: number | null;
  initialView?: AlertDetailView;
  navigationSearch?: SearchState;
  onNavigate?: (alertId: number) => void;
  onClose: () => void;
  styleNonce?: string;
}

interface DetailBundle {
  detail: AlertDetailResponse;
  timeFrames: TimeFramesResponse;
  points: PointsResponse;
}

interface DetailSectionState {
  judgement: boolean;
  timeFrames: boolean;
  wavePoints: boolean;
  alertText: boolean;
}

interface WavePointGroup {
  key: string;
  timeFrameText: string;
  timeFrameOrder: number;
  points: AlertPoint[];
}

const WAVE_POINT_GRID_MODULES = [
  ClientSideRowModelModule,
  CellStyleModule,
  ColumnApiModule,
  RenderApiModule,
  RowStyleModule,
];

const wavePointGridTheme = themeQuartz
  .withPart(colorSchemeDarkBlue)
  .withParams({
    accentColor: "#59d8c2",
    backgroundColor: "#0b151c",
    borderColor: "#263946",
    dataBackgroundColor: "#0f1a22",
    fontFamily: "Segoe UI, Yu Gothic UI, Meiryo, sans-serif",
    fontSize: 11,
    foregroundColor: "#edf5f5",
    headerBackgroundColor: "#0b151c",
    headerTextColor: "#8ba0aa",
    rowHoverColor: "rgba(89, 216, 194, 0.055)",
    spacing: 5,
  });

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function yesNo(value: boolean): string {
  return value ? "はい" : "いいえ";
}

function structureLabel(rank: string, isLate: boolean): string {
  return `${displayValue(rank)}${isLate ? "-LATE" : ""}`;
}

function w1EvaluationLabel(alert: AlertDetailResponse["alert"]): string {
  const result = alert.is_w1_confirmation_passed ? "通過" : "不通過";
  if (alert.w1_confirmation_mode === "OBSERVE_ONLY") {
    return `${result}（記録のみ・エントリー制限なし）`;
  }
  if (alert.is_w1_confirmation_legacy) return "未記録（Legacy）";
  return result;
}

function h1DirectionAlignmentEvaluationLabel(
  alert: AlertDetailResponse["alert"],
): string {
  if (alert.is_h1_direction_alignment_legacy) return "未記録（Legacy）";
  if (alert.h1_direction_alignment_state === "NOT_APPLICABLE") return "対象外";
  const result = alert.is_h1_direction_alignment_passed ? "通過" : "不通過";
  if (alert.h1_direction_alignment_mode === "MN1_TO_H1_OBSERVE") {
    return `${result}（記録のみ・エントリー制限なし）`;
  }
  return result;
}

function h1DirectionAlignmentDataLabel(
  alert: AlertDetailResponse["alert"],
): string {
  if (alert.is_h1_direction_alignment_legacy) return "未記録（Legacy）";
  if (
    alert.h1_direction_alignment_state === "D1_TO_H1"
    || alert.h1_direction_alignment_state === "NOT_APPLICABLE"
  ) {
    return "対象外";
  }
  return `${yesNo(alert.is_h1_direction_alignment_available)} / ${yesNo(alert.is_h1_direction_alignment_valid)}`;
}

function h1DirectionAlignmentMatchLabel(
  alert: AlertDetailResponse["alert"],
): string {
  if (alert.is_h1_direction_alignment_legacy) return "未記録（Legacy）";
  if (
    alert.h1_direction_alignment_state === "D1_TO_H1"
    || alert.h1_direction_alignment_state === "NOT_APPLICABLE"
  ) {
    return "対象外";
  }
  return `${yesNo(alert.is_h1_mn1_direction_matched)} / ${yesNo(alert.is_h1_w1_direction_matched)}`;
}

function Badge({ text, variant = "neutral" }: { text: string; variant?: string }) {
  return <span className={`badge ${variant}`}>{text}</span>;
}

function DetailField({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="detail-field">
      <span>{label}</span>
      <strong>{displayValue(value)}</strong>
    </div>
  );
}

function TimeFrameCard({ timeFrame, points }: { timeFrame: AlertTimeFrame; points: AlertPoint[] }) {
  const waveDirection = `${elliottDirectionSymbol(timeFrame.is_wave_uptrend)} ${timeFrame.is_wave_uptrend ? "UP / 上昇" : "DOWN / 下降"}`;
  const latestPoints = points.filter((point) => point.alert_timeframe_id === timeFrame.id
    && point.time_frame === timeFrame.time_frame && point.is_latest);
  const latestPoint = latestPoints.length === 1 ? latestPoints[0] : undefined;
  const originalLabel = latestPoint?.elliot_label === timeFrame.latest_elliot_label
    && latestPoint?.sub_elliot_label === timeFrame.latest_sub_elliot_label
    ? latestPoint?.org_elliot_label : undefined;
  const wave = `${elliottDirectionSymbol(timeFrame.is_wave_uptrend)}${formatElliottLabel(
    timeFrame.latest_elliot_label, timeFrame.latest_sub_elliot_label, originalLabel,
  )}`;

  return (
    <article
      aria-current={timeFrame.is_current_time_frame ? "true" : undefined}
      aria-label={`${timeFrame.time_frame_text} 時間足スナップショット${
        timeFrame.is_current_time_frame ? "（現在足）" : ""
      }`}
      className="timeframe-card"
    >
      <div className="timeframe-header">
        <div className="badge-row">
          <strong>{timeFrame.time_frame_text}</strong>
          {timeFrame.is_current_time_frame && (
            <span aria-hidden="true" className="current-time-frame-chip">現在足</span>
          )}
        </div>
        <div className="badge-row">
          <Badge text={timeFrame.buy_sell_label} variant={sideClass(timeFrame.buy_sell_label)} />
          <Ema200SignalBadge
            available={timeFrame.is_ema200_available}
            timeFrame={timeFrame}
          />
          <Badge
            text={timeFrame.is_wave_confirmed ? "確定" : "形成中"}
            variant={timeFrame.is_wave_confirmed ? "good" : "warn"}
          />
        </div>
      </div>
      <div className="timeframe-values">
        <div><span>分析方向</span><b>{timeFrame.buy_sell_label}</b></div>
        <div><span>最新Wave方向</span><b>{waveDirection}</b></div>
        <div><span>波動</span><b><ElliottLabelText label={wave}
          mainLabel={timeFrame.latest_elliot_label} originalLabel={originalLabel} /></b></div>
        <div><span>状態</span><b>{timeFrame.is_wave_confirmed ? "確定" : "形成中"}</b></div>
        <div><span>Wave種別</span><b>{timeFrame.is_wave_motive ? "推進波" : "修正波"}</b></div>
        <div><span>ポイント</span><b>{timeFrame.point_count} / wave {timeFrame.latest_wave_index}</b></div>
        <div><span>Stochastic</span><b>{displayValue(timeFrame.stochastic_main_order_text)} / {displayValue(timeFrame.stochastic_main_direction_text)}</b></div>
        <div><span>GMMA</span><b>trend {formatSignedNumber(timeFrame.gmma_trend_count, 0)} / cross {formatSignedNumber(timeFrame.gmma_cross_count, 0)}</b></div>
        <div><span>ATR14</span><b>{formatNumber(timeFrame.atr14_pips)} pips</b></div>
        <div>
          <span>FE200距離</span>
          <b>{timeFrame.is_fibo_expansion_available ? `${formatNumber(timeFrame.distance_to_fe2000_pips)} pips` : "未取得"}</b>
        </div>
        <div><span>現在Close</span><b>{formatNumber(timeFrame.current_close, 5)}</b></div>
      </div>
    </article>
  );
}

function pointStatus(point: AlertPoint): string {
  const values: string[] = [];
  if (point.is_latest) values.push("最新");
  if (point.is_signal_reference) values.push("基準");
  if (point.is_added_point) values.push("追加");
  if (point.is_correct) values.push("補正");
  return values.join("・") || "—";
}

const wavePointColumns: ColDef<AlertPoint>[] = [
  {
    field: "point_order",
    headerName: "順",
    lockPinned: true,
    pinned: "left",
    width: 48,
  },
  { field: "bar_time_text", headerName: "Server時刻", width: 150 },
  {
    cellClass: "numeric-cell",
    field: "rate",
    headerName: "価格",
    valueFormatter: ({ value }) => formatNumber(value, 5),
    width: 90,
  },
  {
    headerName: "山/谷",
    valueGetter: ({ data }) => data ? (data.is_peak ? "山" : "谷") : "—",
    width: 64,
  },
  {
    field: "elliot_label",
    headerName: "Elliott",
    valueGetter: ({ data }) => formatElliottLabel(data?.elliot_label, undefined, data?.org_elliot_label),
    cellRenderer: ({ data, value }: ICellRendererParams<AlertPoint, string>) => (
      <ElliottLabelText label={displayValue(value)} mainLabel={data?.elliot_label}
        originalLabel={data?.org_elliot_label} />
    ),
    width: 80,
  },
  {
    field: "sub_elliot_label",
    headerName: "Sub",
    valueFormatter: ({ value }) => displayValue(value),
    width: 62,
  },
  {
    cellClass: "numeric-cell",
    field: "pips_diff",
    headerName: "pips",
    valueFormatter: ({ value }) => formatNumber(value),
    width: 70,
  },
  {
    headerName: "Fibo",
    valueGetter: ({ data }) => data?.is_fibonacci_available
      ? `${formatNumber(data.fibonacci_percent)}%`
      : "—",
    width: 70,
  },
  {
    headerName: "FE",
    valueGetter: ({ data }) => data?.is_fibonacci_expansion_available
      ? `${formatNumber(data.fibonacci_expansion_percent)}%`
      : "—",
    width: 70,
  },
  {
    flex: 1,
    headerName: "状態",
    minWidth: 94,
    valueGetter: ({ data }) => data ? pointStatus(data) : "—",
  },
];

function wavePointRowClass(params: RowClassParams<AlertPoint>): string {
  const classNames = [
    params.data?.is_latest ? "point-latest" : "",
    params.data?.is_signal_reference ? "point-reference" : "",
  ];
  return classNames.filter(Boolean).join(" ");
}

function wavePointGroupKey(timeFrameOrder: number, timeFrameText: string): string {
  return `${timeFrameOrder}\u0000${timeFrameText}`;
}

function wavePointGroupId(alertId: number, group: WavePointGroup): string {
  const timeFrameId = group.timeFrameText.replace(/[^A-Za-z0-9_-]/g, "-");
  return `alertDetail${alertId}WavePoints${group.timeFrameOrder}${timeFrameId}`;
}

function buildWavePointGroups(timeFrames: AlertTimeFrame[], points: AlertPoint[]): WavePointGroup[] {
  const groupsByKey = new Map<string, WavePointGroup>();
  timeFrames.forEach((timeFrame) => {
    const key = wavePointGroupKey(timeFrame.time_frame_order, timeFrame.time_frame_text);
    if (groupsByKey.has(key)) return;
    groupsByKey.set(key, {
      key,
      timeFrameText: timeFrame.time_frame_text,
      timeFrameOrder: timeFrame.time_frame_order,
      points: [],
    });
  });
  points.forEach((point) => {
    const key = wavePointGroupKey(point.time_frame_order, point.time_frame_text);
    let group = groupsByKey.get(key);
    if (!group) {
      group = {
        key,
        timeFrameText: point.time_frame_text,
        timeFrameOrder: point.time_frame_order,
        points: [],
      };
      groupsByKey.set(key, group);
    }
    group.points.push(point);
  });
  const groups = Array.from(groupsByKey.values());
  groups.forEach((group) => {
    group.points.sort((firstPoint, secondPoint) => {
      if (firstPoint.point_order !== secondPoint.point_order) {
        return firstPoint.point_order - secondPoint.point_order;
      }
      return firstPoint.id - secondPoint.id;
    });
  });
  return groups.sort((firstGroup, secondGroup) => {
    if (firstGroup.timeFrameOrder !== secondGroup.timeFrameOrder) {
      return firstGroup.timeFrameOrder - secondGroup.timeFrameOrder;
    }
    return firstGroup.timeFrameText.localeCompare(secondGroup.timeFrameText);
  });
}

function WavePointGrid({ points, styleNonce, timeFrameText }: {
  points: AlertPoint[];
  styleNonce?: string;
  timeFrameText: string;
}) {
  return (
    <div className="wave-point-grid" role="region" aria-label={`${timeFrameText} 最新Waveポイントグリッド`}>
      <AgGridReact<AlertPoint>
        animateRows={false}
        columnDefs={wavePointColumns}
        defaultColDef={{
          filter: false,
          resizable: true,
          sortable: false,
          suppressHeaderMenuButton: true,
        }}
        domLayout="autoHeight"
        ensureDomOrder
        getRowClass={wavePointRowClass}
        getRowId={({ data }) => String(data.id)}
        headerHeight={32}
        modules={WAVE_POINT_GRID_MODULES}
        onGridReady={({ api: gridApi }) => gridApi.setGridAriaProperty("label", `${timeFrameText} 最新Waveポイント`)}
        rowData={points}
        rowHeight={36}
        styleNonce={styleNonce}
        suppressColumnVirtualisation
        theme={wavePointGridTheme}
      />
    </div>
  );
}

function WavePointTimeFrameGroup({ alertId, group, isOpen, onOpenChange, styleNonce }: {
  alertId: number;
  group: WavePointGroup;
  isOpen: boolean;
  onOpenChange: (isOpen: boolean) => void;
  styleNonce?: string;
}) {
  const [hasOpened, setHasOpened] = useState(isOpen);
  const groupId = wavePointGroupId(alertId, group);

  function handleToggle(fromOpen: boolean) {
    if (fromOpen) setHasOpened(true);
    onOpenChange(fromOpen);
  }

  return (
    <details
      aria-label={`${group.timeFrameText} 最新Waveポイント（${group.points.length}件）`}
      className="wave-point-timeframe-group"
      id={groupId}
      onToggle={(event) => handleToggle(event.currentTarget.open)}
      open={isOpen}
    >
      <summary>
        <h4>
          <span>{group.timeFrameText}</span>
          <span className="wave-point-timeframe-count">{group.points.length}件</span>
        </h4>
      </summary>
      {group.points.length === 0 && <p className="grid-empty-state">保存されたポイントはありません。</p>}
      {group.points.length > 0 && (hasOpened || isOpen) && (
        <WavePointGrid points={group.points} styleNonce={styleNonce} timeFrameText={group.timeFrameText} />
      )}
    </details>
  );
}

function DetailContent({ bundle, styleNonce }: { bundle: DetailBundle; styleNonce?: string }) {
  const alert = bundle.detail.alert;
  const run = bundle.detail.run;
  const w1 = bundle.detail.w1;
  const currentTimeFrame = bundle.timeFrames.items.find(
    (timeFrame) => timeFrame.is_current_time_frame,
  );
  const wavePointGroups = buildWavePointGroups(bundle.timeFrames.items, bundle.points.items);
  const [sectionState, setSectionState] = useState<DetailSectionState>({
    judgement: true,
    timeFrames: true,
    wavePoints: true,
    alertText: false,
  });
  const [wavePointGroupState, setWavePointGroupState] = useState<Record<string, boolean>>(() => {
    const initialState: Record<string, boolean> = {};
    wavePointGroups.forEach((group) => {
      initialState[group.key] = group.timeFrameText === "H1";
    });
    return initialState;
  });
  const allSectionsOpen = sectionState.judgement
    && sectionState.timeFrames
    && sectionState.wavePoints
    && (!alert.alert_text || sectionState.alertText)
    && wavePointGroups.every((group) => wavePointGroupState[group.key] === true);
  const sectionIds = {
    judgement: `alertDetail${alert.id}Judgement`,
    timeFrames: `alertDetail${alert.id}TimeFrames`,
    wavePoints: `alertDetail${alert.id}WavePoints`,
    alertText: `alertDetail${alert.id}Text`,
  };
  const controlledSectionIds = [
    sectionIds.judgement,
    sectionIds.timeFrames,
    sectionIds.wavePoints,
  ];
  if (alert.alert_text) controlledSectionIds.push(sectionIds.alertText);
  wavePointGroups.forEach((group) => controlledSectionIds.push(wavePointGroupId(alert.id, group)));

  function updateSectionState(fromSection: keyof DetailSectionState, fromOpen: boolean) {
    setSectionState((currentState) => {
      if (currentState[fromSection] === fromOpen) return currentState;
      return { ...currentState, [fromSection]: fromOpen };
    });
  }

  function toggleAllSections() {
    const nextOpen = !allSectionsOpen;
    setSectionState({
      judgement: nextOpen,
      timeFrames: nextOpen,
      wavePoints: nextOpen,
      alertText: nextOpen,
    });
    const nextWavePointGroupState: Record<string, boolean> = {};
    wavePointGroups.forEach((group) => {
      nextWavePointGroupState[group.key] = nextOpen;
    });
    setWavePointGroupState(nextWavePointGroupState);
  }

  function updateWavePointGroupState(fromGroupKey: string, fromOpen: boolean) {
    setWavePointGroupState((currentState) => {
      if (currentState[fromGroupKey] === fromOpen) return currentState;
      return { ...currentState, [fromGroupKey]: fromOpen };
    });
  }

  return (
    <>
      <section className="detail-hero">
        <div>
          <div className="badge-row">
            <Badge text={alert.side} variant={sideClass(alert.side)} />
            {currentTimeFrame && (
              <span
                aria-current="true"
                aria-label={`${currentTimeFrame.time_frame_text} 現在足 EMA200`}
                className="badge-row"
                role="group"
              >
                <span aria-hidden="true" className="current-time-frame-chip">
                  {currentTimeFrame.time_frame_text} 現在足
                </span>
                <Ema200SignalBadge
                  available={currentTimeFrame.is_ema200_available}
                  timeFrame={currentTimeFrame}
                />
              </span>
            )}
            <Badge text={`H1 ${structureLabel(alert.h1_structure_rank, alert.is_h1_structure_late)}`} />
            <H1DirectionAlignmentBadge alignment={alert} />
            <W1ConfirmationBadge confirmation={alert} />
            <Badge text={run?.source_mode || "UNKNOWN"} />
            {String(run?.tester_model || "").toLowerCase().includes("open") && <Badge text="Open Prices" variant="warn" />}
          </div>
          <div className="detail-title-line">
            <h3 className="detail-title">{displayValue(alert.alert_title)}</h3>
            <GmoTargetBadge isTarget={alert.is_gmo_target} />
          </div>
          <p className="subtitle">JST {displayValue(alert.jst_time_text)} / Server {displayValue(alert.server_time_text)}</p>
        </div>
        <div className="detail-price">
          <strong>{formatNumber(alert.reference_price, 5)}</strong>
          <span>
            SL {alert.is_stop_loss_available ? formatNumber(alert.stop_loss, 5) : "—"}
            {` / Risk ${formatNumber(alert.risk_pips)} pips`}
          </span>
        </div>
      </section>

      <div className="detail-disclosure-toolbar">
        <button
          aria-controls={controlledSectionIds.join(" ")}
          className="secondary-button"
          onClick={toggleAllSections}
          type="button"
        >
          {allSectionsOpen ? "すべて閉じる" : "すべて開く"}
        </button>
      </div>

      <section className="detail-section">
        <details
          className="detail-disclosure"
          id={sectionIds.judgement}
          onToggle={(event) => updateSectionState("judgement", event.currentTarget.open)}
          open={sectionState.judgement}
        >
          <summary><h3>判定情報</h3></summary>
          <div className="detail-grid">
            <DetailField label="Strategy" value={alert.strategy} />
            <DetailField label="Signal / Entry count" value={`${alert.signal_count} / ${alert.entry_count}`} />
            <DetailField label="Judge" value={yesNo(alert.is_judge)} />
            <DetailField label="Count一致" value={yesNo(alert.is_entry_count_match)} />
            <DetailField label="Entry評価済み" value={yesNo(alert.is_entry_evaluated)} />
            <DetailField label="Entry波動" value={yesNo(alert.is_entry_wave)} />
            <DetailField label="EMA200距離条件" value={yesNo(alert.is_ema200_distance_within)} />
            <DetailField label="Alert / Entry" value={`${yesNo(alert.is_alert)} / ${yesNo(alert.is_entry)}`} />
            <DetailField label="Entry result" value={alert.entry_result} />
            <DetailField label="現在Elliott" value={`wave ${displayValue(alert.current_elliot_label)}`} />
            <DetailField label="EMA200距離" value={`${formatNumber(alert.close_ema200_diff_pips)} / max ${formatNumber(alert.max_close_ema200_diff_pips)} pips`} />
            <DetailField label="Spread" value={`${formatNumber(alert.spread_pips)} pips`} />
            <DetailField label="通貨強弱" value={`${displayValue(alert.currency_strength_status)} / ${alert.is_currency_strength_available ? "取得済" : "未取得"}`} />
            <DetailField label="順位差 長中期 / 中短期" value={`${formatSignedNumber(alert.long_medium_rank_difference, 0)} / ${formatSignedNumber(alert.medium_short_rank_difference, 0)}`} />
            <DetailField label="W1分析方向" value={w1?.w1_side || "不明"} />
            <DetailField
              label="W1確認モード"
              value={alert.is_w1_confirmation_legacy
                ? "未記録（Legacy）"
                : `${w1ConfirmationModeLabel(alert.w1_confirmation_mode)} / ${alert.w1_confirmation_mode}`}
            />
            <DetailField
              label="W1確認状態"
              value={`${alert.w1_confirmation_state} / ${w1ConfirmationStateDescription(alert.w1_confirmation_state)}`}
            />
            <DetailField label="W1データ取得" value={yesNo(alert.is_w1_confirmation_available)} />
            <DetailField label="W1データ有効" value={yesNo(alert.is_w1_confirmation_valid)} />
            <DetailField label="W1方向一致" value={yesNo(alert.is_w1_direction_matched)} />
            <DetailField label="W1確認 EMA200方向" value={alert.w1_ema200_direction} />
            <DetailField label="W1確認 EMA200一致" value={yesNo(alert.is_w1_ema200_matched)} />
            <DetailField label="W1ルール評価" value={w1EvaluationLabel(alert)} />
            <DetailField
              label="H1方向一致モード"
              value={alert.is_h1_direction_alignment_legacy
                ? "未記録（Legacy）"
                : `${h1DirectionAlignmentModeLabel(alert.h1_direction_alignment_mode)} / ${alert.h1_direction_alignment_mode}`}
            />
            <DetailField
              label="H1方向一致状態"
              value={`${alert.h1_direction_alignment_state} / ${h1DirectionAlignmentStateDescription(alert.h1_direction_alignment_state)}`}
            />
            <DetailField
              label="H1方向一致 基準方向"
              value={alert.h1_direction_alignment_direction}
            />
            <DetailField
              label="H1方向一致 データ取得 / 有効"
              value={h1DirectionAlignmentDataLabel(alert)}
            />
            <DetailField
              label="H1方向一致 MN1 / W1"
              value={h1DirectionAlignmentMatchLabel(alert)}
            />
            <DetailField
              label="H1方向一致 ルール評価"
              value={h1DirectionAlignmentEvaluationLabel(alert)}
            />
            <DetailField label="Run" value={run ? `${run.id} / ${displayValue(run.program_version)}` : "不明"} />
            <DetailField label="Signal key" value={alert.market_signal_key} />
            <DetailField label="Snapshot" value="アラート記録時点" />
          </div>
        </details>
      </section>

      <section className="detail-section">
        <details
          className="detail-disclosure"
          id={sectionIds.timeFrames}
          onToggle={(event) => updateSectionState("timeFrames", event.currentTarget.open)}
          open={sectionState.timeFrames}
        >
          <summary><h3>時間足別 Elliott スナップショット</h3></summary>
          <div className="timeframe-grid">
            {bundle.timeFrames.items.map((timeFrame) => <TimeFrameCard timeFrame={timeFrame}
              points={bundle.points.items} key={timeFrame.id} />)}
          </div>
        </details>
      </section>

      <section className="detail-section">
        <details
          className="detail-disclosure"
          id={sectionIds.wavePoints}
          onToggle={(event) => updateSectionState("wavePoints", event.currentTarget.open)}
          open={sectionState.wavePoints}
        >
          <summary><h3>最新Waveポイント（{bundle.points.count}件）</h3></summary>
          {wavePointGroups.length === 0 && <p className="grid-empty-state">保存されたポイントはありません。</p>}
          {wavePointGroups.length > 0 && (
            <div className="wave-point-timeframe-list" role="group" aria-label="時間足別最新Waveポイント">
              {wavePointGroups.map((group) => (
                <WavePointTimeFrameGroup
                  alertId={alert.id}
                  group={group}
                  key={group.key}
                  isOpen={wavePointGroupState[group.key] === true}
                  onOpenChange={(isOpen) => updateWavePointGroupState(group.key, isOpen)}
                  styleNonce={styleNonce}
                />
              ))}
            </div>
          )}
        </details>
      </section>

      {alert.alert_text && (
        <section className="detail-section">
          <details
            className="detail-disclosure"
            id={sectionIds.alertText}
            onToggle={(event) => updateSectionState("alertText", event.currentTarget.open)}
            open={sectionState.alertText}
          >
            <summary><h3>アラート本文</h3></summary>
            <pre className="detail-field">{alert.alert_text}</pre>
          </details>
        </section>
      )}
    </>
  );
}

/**
 * アラート保存時点の時間足を共通比較グリッド形式へ変換します。
 *
 * @param bundle アラート詳細、時間足およびWaveポイント
 * @return TIMEFRAME COMPARISONへ渡す時間足一覧
 */
function comparisonTimeFrames(bundle: DetailBundle): ObservationDetailTimeFrame[] {
  const latestPoints = new Map<number, AlertPoint>();
  for (const point of bundle.points.items) {
    if (point.is_latest) latestPoints.set(point.alert_timeframe_id, point);
  }

  return bundle.timeFrames.items.map((timeFrame) => {
    const latestPoint = latestPoints.get(timeFrame.id);
    return {
      ...timeFrame,
      observation_id: timeFrame.alert_id,
      is_anchor_time_frame: timeFrame.is_current_time_frame,
      latest_point_time: latestPoint?.bar_time ?? 0,
      latest_point_time_text: latestPoint?.bar_time_text ?? "",
      latest_point_jst_time: 0,
      latest_point_jst_time_text: "",
      latest_point_rate: latestPoint?.rate ?? Number.NaN,
      latest_point_org_elliot_label: latestPoint?.org_elliot_label ?? null,
      latest_point_is_added:
        timeFrame.latest_point_is_added ?? latestPoint?.is_added_point ?? null,
    };
  });
}

/**
 * 一覧の検索結果順で前後へ移動する操作を表示します。
 */
function AlertNavigation({ navigation, busy, error, onNavigate }: {
  navigation: AlertNavigationResponse | null;
  busy: boolean;
  error: string;
  onNavigate: (target: AlertNavigationItem) => void;
}) {
  function targetTitle(label: string, target: AlertNavigationItem | null | undefined) {
    if (target) {
      return `${label}（検索結果順）\n${displayValue(target.symbol_name)} ${displayValue(target.side)} ${displayValue(target.time_frame_text)}\nJST ${displayValue(target.jst_time_text)}`;
    }
    return `${label}はありません`;
  }

  return (
    <div className="observation-snapshot-grid-navigation-area">
      <nav aria-label="アラートを検索結果順で移動" className="alert-snapshot-navigation">
        <button
          aria-label="前のアラート（検索結果順）"
          className="secondary-button"
          disabled={busy || !navigation?.previous}
          title={targetTitle("前のアラート", navigation?.previous)}
          type="button"
          onClick={() => {
            if (navigation?.previous) onNavigate(navigation.previous);
          }}
        >
          ← 前
        </button>
        <button
          aria-label="次のアラート（検索結果順）"
          className="secondary-button"
          disabled={busy || !navigation?.next}
          title={targetTitle("次のアラート", navigation?.next)}
          type="button"
          onClick={() => {
            if (navigation?.next) onNavigate(navigation.next);
          }}
        >
          次 →
        </button>
        <span className="observation-snapshot-grid-navigation-status">{busy ? "読み込み中…" : "検索結果順"}</span>
      </nav>
      {error && <p className="observation-snapshot-grid-navigation-error" role="alert">{error}</p>}
      {!error && navigation && !navigation.matched && (
        <p className="observation-snapshot-grid-navigation-status">現在のアラートは検索結果に含まれていません</p>
      )}
    </div>
  );
}

function ComparisonContent({ bundle, gridStateRef, navigation, styleNonce, showCorrection = false, correctionTimeFrame = "H1" }: {
  bundle: DetailBundle;
  gridStateRef: RefObject<GridState | undefined>;
  navigation?: ReactNode;
  styleNonce?: string;
  showCorrection?: boolean;
  correctionTimeFrame?: "H1" | "M15";
}) {
  const alert = bundle.detail.alert;
  const run = bundle.detail.run;
  const timeFrames = useMemo(() => {
    if (showCorrection && bundle.detail.correction?.status === "APPLIED") {
      return comparisonTimeFrames({ ...bundle, timeFrames: {
        ...bundle.timeFrames, items: bundle.detail.correction.timeframes,
      }, points: {
        ...bundle.points, items: bundle.detail.correction.points,
      } });
    }
    return comparisonTimeFrames(bundle);
  }, [bundle, showCorrection]);
  const savedH1Decision = timeFrames.some((timeFrame) => (
    timeFrame.is_anchor_time_frame
    && timeFrame.time_frame_text.trim().toUpperCase() === "H1"
  )) ? alert : null;
  const comparisonGrid = <ObservationTimeFrameSnapshotGrid
    ariaLabel="アラート時間足比較スナップショットグリッド"
    showOriginalElliottLabel
    stateRef={gridStateRef}
    styleNonce={styleNonce}
    timeFrames={timeFrames}
  />;

  return (
    <section className="observation-snapshot-grid-content">
      <div className="observation-snapshot-grid-context">
        <div>
          <p className="eyebrow">TIMEFRAME COMPARISON</p>
          <div className="observation-snapshot-grid-symbol">
            <strong>{alert.symbol_name}</strong>
            <GmoTargetBadge isTarget={alert.is_gmo_target} />
          </div>
        </div>
        {navigation}
        <div className="observation-snapshot-grid-context-values">
          <span>{alert.side}</span>
          <span>JST {displayValue(alert.jst_time_text)}</span>
          <span>Server {displayValue(alert.server_time_text)}</span>
          <span>Alert {alert.id}</span>
          <span>Run {run?.id ?? "—"}</span>
        </div>
      </div>
      {showCorrection && <AlertCorrectionSnapshot
        detail={bundle.detail}
        timeFrames={bundle.timeFrames.items}
        points={bundle.points.items}
        currentTimeFrame={correctionTimeFrame}
      />}
      {!showCorrection && <CurrencyStrengthSnapshotPanel alert={alert} />}
      {!showCorrection && <H1EntryCheckPanel
        savedDecision={savedH1Decision}
        savedRunInputText={run?.input_text}
        spreadPips={alert.spread_pips}
        timeFrames={timeFrames}
      />}
      {showCorrection ? <details className="m5-alert-extra">
        <summary>{bundle.detail.correction?.status === "APPLIED" ? "採用分析のTF比較" : "元の保存分析のTF比較（比較用）"}</summary>
        <p className="m5-alert-note">この表は{bundle.detail.correction?.status === "APPLIED" ? "補正後の採用分析" : "元の保存分析（比較用）"}を固定表示します。上の補正前後切替とは独立し、保存済みエントリー判定は再計算しません。</p>
        {comparisonGrid}
      </details> : comparisonGrid}
    </section>
  );
}

export function AlertDetailDrawer({
  alertId,
  initialView = "detail",
  navigationSearch,
  onClose,
  onNavigate,
  styleNonce,
}: AlertDetailDrawerProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const bundleRef = useRef<DetailBundle | null>(null);
  const comparisonGridStateRef = useRef<GridState | undefined>(undefined);
  const onNavigateRef = useRef(onNavigate);
  const [navigation, setNavigation] = useState<AlertNavigationResponse | null>(null);
  const [navigationError, setNavigationError] = useState("");
  const [announcement, setAnnouncement] = useState("");
  const [bundle, setBundle] = useState<DetailBundle | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [view, setView] = useState<AlertDetailView>(initialView);
  const isOpen = alertId !== null;

  useEffect(() => {
    setView(initialView);
  }, [isOpen, initialView]);

  useEffect(() => {
    onNavigateRef.current = onNavigate;
  }, [onNavigate]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (isOpen) {
      if (!dialog.open) dialog.showModal();
      document.body.classList.add("drawer-open");
      closeButtonRef.current?.focus();
      return () => {
        document.body.classList.remove("drawer-open");
        if (dialog.open) dialog.close();
      };
    }
    if (dialog.open) dialog.close();
  }, [isOpen]);

  useEffect(() => {
    if (alertId === null) {
      bundleRef.current = null;
      setBundle(null);
      setNavigation(null);
      setNavigationError("");
      setAnnouncement("");
      setLoading(false);
      setError("");
      return;
    }
    let displayedBundle: DetailBundle | null = null;
    if (navigationSearch && onNavigateRef.current) {
      displayedBundle = bundleRef.current;
    }
    if (displayedBundle?.detail.alert.id === alertId) {
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    let active = true;
    setLoading(true);
    setError("");
    if (!displayedBundle) {
      setBundle(null);
      setAnnouncement("");
    }
    const navigationRequest = navigationSearch
      ? api.alertNavigation(alertId, navigationSearch, controller.signal)
        .then((value) => {
          if (value.alert_id !== alertId) throw new Error("前後アラートの応答が不正です");
          return { navigation: value, error: "" };
        })
        .catch((reason: unknown) => {
          if (isAbortError(reason)) throw reason;
          const message = reason instanceof Error ? reason.message : "前後アラートの取得に失敗しました";
          return { navigation: null, error: message };
        })
      : Promise.resolve({ navigation: null, error: "" });
    Promise.all([
      api.alertDetail(alertId, controller.signal),
      api.alertTimeFrames(alertId, controller.signal),
      api.alertPoints(alertId, controller.signal),
      navigationRequest,
    ])
      .then(([detail, timeFrames, points, navigationResult]) => {
        if (!active || controller.signal.aborted) return;
        if (detail.alert.id !== alertId) throw new Error("アラート詳細の応答が不正です");
        const value = { detail, timeFrames, points };
        bundleRef.current = value;
        setBundle(value);
        setNavigation(navigationResult.navigation);
        setNavigationError(navigationResult.error);
        setAnnouncement(`${detail.alert.symbol_name} ${detail.alert.side} JST ${detail.alert.jst_time_text}を表示しました`);
      })
      .catch((reason: unknown) => {
        if (!active || controller.signal.aborted || isAbortError(reason)) return;
        const message = reason instanceof Error ? reason.message : "詳細の読み込みに失敗しました";
        if (displayedBundle && onNavigateRef.current) {
          setError(`${message}。現在のアラートを表示しています`);
          onNavigateRef.current(displayedBundle.detail.alert.id);
        } else {
          setError(message);
        }
        setAnnouncement("");
      })
      .finally(() => {
        if (active && !controller.signal.aborted) setLoading(false);
      });
    return () => {
      active = false;
      controller.abort();
    };
  }, [alertId, navigationSearch]);

  function navigateTo(target: AlertNavigationItem) {
    if (loading || !onNavigate || navigation?.alert_id !== bundle?.detail.alert.id) return;
    setLoading(true);
    setError("");
    setAnnouncement(`${target.symbol_name} ${target.side} JST ${target.jst_time_text}を読み込んでいます`);
    onNavigate(target.id);
  }

  function handleBackdropClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target !== event.currentTarget || event.detail === 0) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const isOutside = event.clientX < bounds.left
      || event.clientX > bounds.right
      || event.clientY < bounds.top
      || event.clientY > bounds.bottom;
    if (isOutside) onClose();
  }

  const hasDisplayedBundle = isOpen && bundle !== null
    && (bundle.detail.alert.id === alertId || Boolean(navigationSearch && onNavigate));
  let isM5Alert = false;
  let hasUpperCorrection = false;
  let correctionTimeFrame: "H1" | "M15" = "H1";
  let title: ReactNode = "アラート詳細";
  let titleDescription: string | undefined;
  if (hasDisplayedBundle && bundle) {
    const alert = bundle.detail.alert;
    isM5Alert = alert.time_frame === 5 || alert.time_frame_text === "M5"
      || bundle.timeFrames.items.some((timeFrame) => (
        timeFrame.is_current_time_frame && timeFrame.time_frame_text === "M5"
      ));
    const isH1Alert = !isM5Alert && (alert.time_frame === 16385 || alert.time_frame_text === "H1"
      || bundle.timeFrames.items.some((timeFrame) => (
        timeFrame.is_current_time_frame && timeFrame.time_frame_text === "H1"
      )));
    const isM15Alert = !isM5Alert && (alert.time_frame === 15 || alert.time_frame_text === "M15"
      || bundle.timeFrames.items.some((timeFrame) => (
        timeFrame.is_current_time_frame && timeFrame.time_frame_text === "M15"
      )));
    if (isM15Alert) correctionTimeFrame = "M15";
    hasUpperCorrection = (isH1Alert || isM15Alert) && (bundle.detail.correction?.status === "APPLIED"
      || bundle.detail.correction?.status === "INCOMPLETE");
    const timeFrameText = alert.time_frame_text?.trim()
      || bundle.timeFrames.items.find((timeFrame) => timeFrame.is_current_time_frame)?.time_frame_text
      || "未記録";
    const barTimes = formatAlertBarTimes(
      alert.current_bar_time_text, alert.server_time_text, alert.jst_time_text,
    );
    titleDescription = "足開始時刻（JST / Server）";
    title = <>
      <span>{alert.symbol_name} {alert.side}</span>{" ｜ "}<span>{timeFrameText}</span>{" ｜ "}
      <span className="alert-snapshot-jst">JST {barTimes.jst}</span>{" ｜ "}
      <span className="alert-snapshot-server">Server {barTimes.server}</span>
    </>;
  }
  let dialogClassName = "react-detail-dialog";
  if (isM5Alert || hasUpperCorrection || view === "comparison") {
    dialogClassName += " observation-grid-mode";
  }
  const navigationControls = navigationSearch && onNavigate && hasDisplayedBundle && (
    <AlertNavigation
      busy={loading}
      error={error || navigationError}
      navigation={navigation}
      onNavigate={navigateTo}
    />
  );

  let closeLabel = "詳細を閉じる";
  if (isM5Alert || hasUpperCorrection) {
    dialogClassName += " m5-alert-dialog";
  }
  if (isM5Alert) {
    closeLabel = "M5アラート詳細を閉じる";
  } else if (view === "comparison") {
    closeLabel = "TIMEFRAME COMPARISONを閉じる";
  }

  return (
    <dialog
      aria-labelledby="reactDetailTitle"
      className={dialogClassName}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onClick={handleBackdropClick}
      ref={dialogRef}
    >
      <div className="drawer-header alert-snapshot-header">
        <div className="alert-snapshot-heading">
          <p className="eyebrow">ALERT SNAPSHOT</p>
          <h2 id="reactDetailTitle" tabIndex={0} title={titleDescription}>{title}</h2>
        </div>
        <div className="observation-detail-header-actions">
          {hasDisplayedBundle && bundle && !isM5Alert && (
            <div
              aria-label="アラートスナップショット表示"
              className="observation-detail-view-toggle"
              role="group"
            >
              <button
                aria-pressed={view === "detail"}
                className="secondary-button"
                onClick={() => setView("detail")}
                type="button"
              >
                詳細
              </button>
              <button
                aria-pressed={view === "comparison"}
                className="secondary-button"
                onClick={() => setView("comparison")}
                type="button"
              >
                TF比較
              </button>
            </div>
          )}
          <button
            aria-label={closeLabel}
            className="close-button"
            onClick={onClose}
            ref={closeButtonRef}
            type="button"
          >
            ×
          </button>
        </div>
      </div>
      <div aria-busy={loading} className="drawer-body">
        {announcement && <span className="visually-hidden" role="status" aria-live="polite">{announcement}</span>}
        {loading && !hasDisplayedBundle && <p className="loading-message" role="status" aria-live="polite">詳細を読み込んでいます…</p>}
        {error && !navigationControls && <p className="loading-message" role="alert">{error}</p>}
        {(isM5Alert || view === "detail") && navigationControls}
        {hasDisplayedBundle && bundle && isM5Alert && (
          <M5AlertSnapshot
            key={bundle.detail.alert.id}
            detail={bundle.detail}
            timeFrames={bundle.timeFrames.items}
            points={bundle.points.items}
          />
        )}
        {hasDisplayedBundle && bundle && !isM5Alert && view === "detail" && (
          hasUpperCorrection ? <AlertCorrectionSnapshot
            detail={bundle.detail}
            timeFrames={bundle.timeFrames.items}
            points={bundle.points.items}
            currentTimeFrame={correctionTimeFrame}
          /> : <DetailContent bundle={bundle} styleNonce={styleNonce} />
        )}
        {hasDisplayedBundle && bundle && !isM5Alert && view === "comparison" && (
          <ComparisonContent bundle={bundle} gridStateRef={comparisonGridStateRef} navigation={navigationControls} styleNonce={styleNonce} showCorrection={hasUpperCorrection} correctionTimeFrame={correctionTimeFrame} />
        )}
      </div>
    </dialog>
  );
}
