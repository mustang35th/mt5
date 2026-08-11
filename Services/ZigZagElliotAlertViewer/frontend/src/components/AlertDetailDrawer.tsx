import {
  ClientSideRowModelModule,
  CellStyleModule,
  colorSchemeDarkBlue,
  ColumnApiModule,
  RenderApiModule,
  RowStyleModule,
  themeQuartz,
  type ColDef,
  type RowClassParams,
} from "ag-grid-community";
import { AgGridReact } from "ag-grid-react";
import { type MouseEvent, useEffect, useRef, useState } from "react";
import { api } from "../api/client";
import type {
  AlertDetailResponse,
  AlertPoint,
  AlertTimeFrame,
  PointsResponse,
  TimeFramesResponse,
} from "../api/types";
import { displayValue, formatNumber, sideClass } from "../lib/format";

interface AlertDetailDrawerProps {
  alertId: number | null;
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

function waveLabel(mainLabel: string, subLabel: string): string {
  if (!mainLabel) return "—";
  if (!subLabel) return mainLabel;
  return `${mainLabel}.${subLabel}`;
}

function structureLabel(rank: string, isLate: boolean): string {
  return `${displayValue(rank)}${isLate ? "-LATE" : ""}`;
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

function TimeFrameCard({ timeFrame }: { timeFrame: AlertTimeFrame }) {
  const waveDirection = timeFrame.is_wave_uptrend ? "UP / 上昇" : "DOWN / 下降";
  let ema200Direction = "NONE";
  if (timeFrame.is_ema200_buy) ema200Direction = "BUY";
  if (timeFrame.is_ema200_sell) ema200Direction = "SELL";

  return (
    <article className="timeframe-card">
      <div className="timeframe-header">
        <strong>{timeFrame.time_frame_text}</strong>
        <div className="badge-row">
          <Badge text={timeFrame.buy_sell_label} variant={sideClass(timeFrame.buy_sell_label)} />
          <Badge
            text={timeFrame.is_wave_confirmed ? "確定" : "形成中"}
            variant={timeFrame.is_wave_confirmed ? "good" : "warn"}
          />
        </div>
      </div>
      <div className="timeframe-values">
        <div><span>分析方向</span><b>{timeFrame.buy_sell_label}</b></div>
        <div><span>最新Wave方向</span><b>{waveDirection} ({displayValue(timeFrame.wave_trend_label)})</b></div>
        <div><span>波動</span><b>{waveLabel(timeFrame.latest_elliot_label, timeFrame.latest_sub_elliot_label)}</b></div>
        <div><span>状態</span><b>{timeFrame.is_wave_confirmed ? "確定" : "形成中"}</b></div>
        <div><span>Wave種別</span><b>{timeFrame.is_wave_motive ? "推進波" : "修正波"}</b></div>
        <div><span>ポイント</span><b>{timeFrame.point_count} / wave {timeFrame.latest_wave_index}</b></div>
        <div><span>Stochastic</span><b>{displayValue(timeFrame.stochastic_main_order_text)} / {displayValue(timeFrame.stochastic_main_direction_text)}</b></div>
        <div><span>GMMA</span><b>trend {formatNumber(timeFrame.gmma_trend_count, 0)} / cross {formatNumber(timeFrame.gmma_cross_count, 0)}</b></div>
        <div><span>EMA200方向</span><b>{ema200Direction}</b></div>
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
    valueFormatter: ({ value }) => displayValue(value),
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

  let alignmentText = "W1不明";
  let alignmentVariant = "neutral";
  if (alert.is_w1_aligned === true) {
    alignmentText = "W1一致";
    alignmentVariant = "good";
  } else if (alert.is_w1_aligned === false) {
    alignmentText = "W1不一致";
    alignmentVariant = "warn";
  }

  return (
    <>
      <section className="detail-hero">
        <div>
          <div className="badge-row">
            <Badge text={alert.side} variant={sideClass(alert.side)} />
            <Badge text={`H1 ${structureLabel(alert.h1_structure_rank, alert.is_h1_structure_late)}`} />
            <Badge text={alignmentText} variant={alignmentVariant} />
            <Badge text={run?.source_mode || "UNKNOWN"} />
            {String(run?.tester_model || "").toLowerCase().includes("open") && <Badge text="Open Prices" variant="warn" />}
          </div>
          <h3 className="detail-title">{displayValue(alert.alert_title)}</h3>
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
            <DetailField label="順位差 長中期 / 中短期" value={`${formatNumber(alert.long_medium_rank_difference, 0)} / ${formatNumber(alert.medium_short_rank_difference, 0)}`} />
            <DetailField label="W1分析方向" value={w1?.w1_side || "不明"} />
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
            {bundle.timeFrames.items.map((timeFrame) => <TimeFrameCard timeFrame={timeFrame} key={timeFrame.id} />)}
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

export function AlertDetailDrawer({ alertId, onClose, styleNonce }: AlertDetailDrawerProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const [bundle, setBundle] = useState<DetailBundle | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const isOpen = alertId !== null;

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
      setBundle(null);
      setLoading(false);
      setError("");
      return;
    }
    const controller = new AbortController();
    let active = true;
    setBundle(null);
    setLoading(true);
    setError("");
    Promise.all([
      api.alertDetail(alertId, controller.signal),
      api.alertTimeFrames(alertId, controller.signal),
      api.alertPoints(alertId, controller.signal),
    ])
      .then(([detail, timeFrames, points]) => {
        if (active && !controller.signal.aborted) setBundle({ detail, timeFrames, points });
      })
      .catch((reason: unknown) => {
        if (active && !controller.signal.aborted && !isAbortError(reason)) {
          setError(reason instanceof Error ? reason.message : "詳細の読み込みに失敗しました");
        }
      })
      .finally(() => {
        if (active && !controller.signal.aborted) setLoading(false);
      });
    return () => {
      active = false;
      controller.abort();
    };
  }, [alertId]);

  function handleBackdropClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target !== event.currentTarget || event.detail === 0) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const isOutside = event.clientX < bounds.left
      || event.clientX > bounds.right
      || event.clientY < bounds.top
      || event.clientY > bounds.bottom;
    if (isOutside) onClose();
  }

  const title = bundle
    ? `${bundle.detail.alert.symbol_name} ${bundle.detail.alert.side} / ${bundle.detail.alert.current_bar_time_text}`
    : "アラート詳細";

  return (
    <dialog
      aria-labelledby="reactDetailTitle"
      className="react-detail-dialog"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onClick={handleBackdropClick}
      ref={dialogRef}
    >
      <div className="drawer-header">
        <div>
          <p className="eyebrow">ALERT SNAPSHOT</p>
          <h2 id="reactDetailTitle">{title}</h2>
        </div>
        <button aria-label="詳細を閉じる" className="close-button" onClick={onClose} ref={closeButtonRef} type="button">×</button>
      </div>
      <div aria-busy={loading} className="drawer-body">
        {loading && <p className="loading-message" role="status" aria-live="polite">詳細を読み込んでいます…</p>}
        {error && <p className="loading-message" role="alert">{error}</p>}
        {!loading && !error && bundle && <DetailContent bundle={bundle} styleNonce={styleNonce} />}
      </div>
    </dialog>
  );
}
