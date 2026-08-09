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
}

interface DetailBundle {
  detail: AlertDetailResponse;
  timeFrames: TimeFramesResponse;
  points: PointsResponse;
}

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

function WavePointTable({ points }: { points: AlertPoint[] }) {
  return (
    <div className="points-wrap">
      <table>
        <thead>
          <tr>
            {['TF', '順', '時刻', '価格', '山/谷', 'Elliott', 'Sub', 'pips', 'Fibo', 'FE', '状態'].map((label) => (
              <th scope="col" key={label}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {points.map((point) => {
            const classNames = [
              point.is_latest ? "point-latest" : "",
              point.is_signal_reference ? "point-reference" : "",
            ].filter(Boolean).join(" ");
            return (
              <tr className={classNames} key={point.id}>
                <td>{point.time_frame_text}</td>
                <td>{point.point_order}</td>
                <td>{displayValue(point.bar_time_text)}</td>
                <td>{formatNumber(point.rate, 5)}</td>
                <td>{point.is_peak ? "山" : "谷"}</td>
                <td>{displayValue(point.elliot_label)}</td>
                <td>{displayValue(point.sub_elliot_label)}</td>
                <td>{formatNumber(point.pips_diff)}</td>
                <td>{point.is_fibonacci_available ? `${formatNumber(point.fibonacci_percent)}%` : "—"}</td>
                <td>{point.is_fibonacci_expansion_available ? `${formatNumber(point.fibonacci_expansion_percent)}%` : "—"}</td>
                <td>{pointStatus(point)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function DetailContent({ bundle }: { bundle: DetailBundle }) {
  const alert = bundle.detail.alert;
  const run = bundle.detail.run;
  const w1 = bundle.detail.w1;
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

      <section className="detail-section">
        <h3>判定情報</h3>
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
      </section>

      <section className="detail-section">
        <h3>時間足別 Elliott スナップショット</h3>
        <div className="timeframe-grid">
          {bundle.timeFrames.items.map((timeFrame) => <TimeFrameCard timeFrame={timeFrame} key={timeFrame.id} />)}
        </div>
      </section>

      <section className="detail-section">
        <h3>最新Waveポイント（{bundle.points.count}件）</h3>
        <WavePointTable points={bundle.points.items} />
      </section>

      {alert.alert_text && (
        <section className="detail-section">
          <details>
            <summary>アラート本文を表示</summary>
            <pre className="detail-field">{alert.alert_text}</pre>
          </details>
        </section>
      )}
    </>
  );
}

export function AlertDetailDrawer({ alertId, onClose }: AlertDetailDrawerProps) {
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
        {!loading && !error && bundle && <DetailContent bundle={bundle} />}
      </div>
    </dialog>
  );
}
