import { type MouseEvent, useCallback, useEffect, useRef, useState } from "react";
import { api } from "../api/client";
import type {
  ObservationDetailNavigation,
  ObservationDetailParent,
  ObservationDetailResponse,
  ObservationDetailTimeFrame,
  ObservationNavigationItem,
} from "../api/types";
import {
  displayValue,
  elliottDirectionSymbol,
  formatElliottDirection,
  formatNumber,
  formatSignedNumber,
  sideClass,
} from "../lib/format";
import { Ema200SignalBadge } from "./Ema200SignalBadge";
import { GmoTargetBadge } from "./GmoTargetBadge";
import { H1EntryCheckPanel } from "./H1EntryCheckPanel";
import { ObservationTimeFrameSnapshotGrid } from "./ObservationTimeFrameSnapshotGrid";

interface ObservationDetailDrawerProps {
  initialView?: ObservationDetailView;
  observationId: number | null;
  onClose: () => void;
  onNavigate: (observationId: number) => void;
  styleNonce?: string;
}

type ObservationDetailView = "cards" | "grid";

const EMPTY_OBSERVATION_NAVIGATION: ObservationDetailNavigation = {
  older: null,
  newer: null,
};

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function Badge({ text, variant = "neutral" }: { text: string; variant?: string }) {
  return <span className={`badge ${variant}`}>{displayValue(text)}</span>;
}

function DetailField({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="detail-field">
      <span>{label}</span>
      <strong>{displayValue(value)}</strong>
    </div>
  );
}

function spreadLabel(spreadPips: number | null | undefined): string {
  if (spreadPips === null || spreadPips === undefined) return "未記録";
  return `${formatNumber(spreadPips)} pips`;
}

function pipSizeLabel(pipSize: number | null | undefined): string {
  if (pipSize === null || pipSize === undefined) return "未記録";
  return String(pipSize);
}

function TimeFrameValue({ label, value }: { label: string; value: unknown }) {
  return (
    <div>
      <span>{label}</span>
      <b>{displayValue(value)}</b>
    </div>
  );
}

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

function isEma200Skipped(timeFrame: ObservationDetailTimeFrame): boolean {
  return timeFrame.time_frame_text.toUpperCase() === "MN1";
}

function ema200PositionLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (isEma200Skipped(timeFrame)) return "対象外（MN1は計算省略）";

  let position = `不明（code ${formatNumber(timeFrame.ema200_close_position, 0)}）`;
  if (timeFrame.ema200_close_position === 1) {
    position = "終値が上";
  } else if (timeFrame.ema200_close_position === -1) {
    position = "終値が下";
  } else if (timeFrame.ema200_close_position === 2) {
    position = "終値とEMA200が同値";
  } else if (timeFrame.ema200_close_position === 0) {
    position = "未判定";
  }

  return `${position}（距離 ${formatSignedNumber(timeFrame.ema200_close_diff_pips)} pips）`;
}

function ema200SlopeLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (isEma200Skipped(timeFrame)) return "対象外（MN1は計算省略）";

  let direction = `不明（code ${formatNumber(timeFrame.ema200_slope_direction, 0)}）`;
  if (timeFrame.ema200_slope_direction === 1) {
    direction = "上向き";
  } else if (timeFrame.ema200_slope_direction === -1) {
    direction = "下向き";
  } else if (timeFrame.ema200_slope_direction === 0) {
    direction = "横ばい";
  }

  return `${direction}（${formatSignedNumber(timeFrame.ema200_slope_pips)} pips）`;
}

function ema200TrendLabel(timeFrame: ObservationDetailTimeFrame): string {
  if (isEma200Skipped(timeFrame)) return "対象外（MN1は計算省略）";

  let direction = "拮抗";
  if (timeFrame.ema200_trend_count > 0) {
    direction = "上昇優勢";
  } else if (timeFrame.ema200_trend_count < 0) {
    direction = "下降優勢";
  }

  return `${direction} ${formatSignedNumber(timeFrame.ema200_trend_count, 0)}（上昇 ${formatNumber(timeFrame.ema200_up_count, 0)}回 / 下降 ${formatNumber(timeFrame.ema200_down_count, 0)}回）`;
}

function fePrice(timeFrame: ObservationDetailTimeFrame, value: number): string {
  if (!timeFrame.is_fibo_expansion_available) return "—";
  return formatNumber(value, 5);
}

function TimeFrameCard({ timeFrame }: { timeFrame: ObservationDetailTimeFrame }) {
  const waveDirection = formatElliottDirection(timeFrame.is_wave_uptrend);
  const feDistance = timeFrame.is_fibo_expansion_available
    ? `${formatNumber(timeFrame.distance_to_fe2000_pips)} pips`
    : "—";

  return (
    <article
      aria-label={`${timeFrame.time_frame_text} 時間足詳細`}
      className="timeframe-card"
    >
      <div className="timeframe-header">
        <strong>{timeFrame.time_frame_text}</strong>
        <div className="badge-row">
          <Badge text={timeFrame.buy_sell_label} variant={sideClass(timeFrame.buy_sell_label)} />
          <Ema200SignalBadge timeFrame={timeFrame} />
          <Badge
            text={timeFrame.is_wave_confirmed ? "確定" : "形成中"}
            variant={timeFrame.is_wave_confirmed ? "good" : "warn"}
          />
          {timeFrame.is_anchor_time_frame && <Badge text="基準足" />}
        </div>
      </div>
      <div className="timeframe-values">
        <TimeFrameValue label="分析方向" value={timeFrame.buy_sell_label} />
        <TimeFrameValue label="Wave方向" value={waveDirection} />
        <TimeFrameValue label="Wave状態" value={timeFrame.is_wave_confirmed ? "確定" : "形成中"} />
        <TimeFrameValue label="Wave種別" value={timeFrame.is_wave_motive ? "推進波" : "修正波"} />
        <TimeFrameValue
          label="Wave数 / 最新index"
          value={`${formatNumber(timeFrame.wave_count, 0)} / ${formatNumber(timeFrame.latest_wave_index, 0)}`}
        />
        <TimeFrameValue label="Elliott / Sub" value={waveLabel(timeFrame)} />
        <TimeFrameValue label="前回Wave最終" value={timeFrame.previous_last_elliot_label} />
        <TimeFrameValue label="保存ポイント数" value={formatNumber(timeFrame.point_count, 0)} />
        <TimeFrameValue label="最新点 JST" value={timeFrame.latest_point_jst_time_text} />
        <TimeFrameValue label="最新点 Server" value={timeFrame.latest_point_time_text} />
        <TimeFrameValue label="最新点価格" value={formatNumber(timeFrame.latest_point_rate, 5)} />
        <TimeFrameValue
          label="前足 OHLC"
          value={ohlcLabel(
            timeFrame.previous_open,
            timeFrame.previous_high,
            timeFrame.previous_low,
            timeFrame.previous_close,
          )}
        />
        <TimeFrameValue
          label="現在足 OHLC"
          value={ohlcLabel(
            timeFrame.current_open,
            timeFrame.current_high,
            timeFrame.current_low,
            timeFrame.current_close,
          )}
        />
        <TimeFrameValue
          label="Fibo / FE"
          value={timeFrame.is_fibo_expansion_available ? "取得済" : "未取得"}
        />
        <TimeFrameValue
          label="FE 61.8 / 100.0"
          value={`${fePrice(timeFrame, timeFrame.fe618_price)} / ${fePrice(timeFrame, timeFrame.fe1000_price)}`}
        />
        <TimeFrameValue
          label="FE 127.2 / 161.8"
          value={`${fePrice(timeFrame, timeFrame.fe1272_price)} / ${fePrice(timeFrame, timeFrame.fe1618_price)}`}
        />
        <TimeFrameValue label="FE 200.0" value={fePrice(timeFrame, timeFrame.fe2000_price)} />
        <TimeFrameValue label="FE200距離" value={feDistance} />
        <TimeFrameValue
          label="Oscillator"
          value={`${timeFrame.is_oscillator_buy ? "BUY" : "SELL"} / count ${formatSignedNumber(timeFrame.oscillator_count, 0)}`}
        />
        <TimeFrameValue
          label="Stochastic"
          value={`${displayValue(timeFrame.stochastic_main_order_text)} / ${displayValue(timeFrame.stochastic_main_direction_text)} [${formatNumber(timeFrame.stochastic_main_order, 0)}]`}
        />
        <TimeFrameValue
          label="Stoch 短期"
          value={stochasticLabel(
            timeFrame.stochastic_short_count,
            timeFrame.stochastic_short_main,
            timeFrame.stochastic_short_signal,
          )}
        />
        <TimeFrameValue
          label="Stoch 中期"
          value={stochasticLabel(
            timeFrame.stochastic_middle_count,
            timeFrame.stochastic_middle_main,
            timeFrame.stochastic_middle_signal,
          )}
        />
        <TimeFrameValue
          label="Stoch 長期"
          value={stochasticLabel(
            timeFrame.stochastic_long_count,
            timeFrame.stochastic_long_main,
            timeFrame.stochastic_long_signal,
          )}
        />
        <TimeFrameValue
          label="GMMA trend / cross"
          value={`${formatSignedNumber(timeFrame.gmma_trend_count, 0)} / ${formatSignedNumber(timeFrame.gmma_cross_count, 0)}`}
        />
        <TimeFrameValue
          label="EMA30 / EMA60"
          value={`${formatNumber(timeFrame.ema30, 5)} / ${formatNumber(timeFrame.ema60, 5)}`}
        />
        <TimeFrameValue
          label="EMA30-60距離"
          value={`${formatSignedNumber(timeFrame.ema30_ema60_diff_pips)} pips`}
        />
        <TimeFrameValue label="ATR14" value={`${formatNumber(timeFrame.atr14_pips)} pips`} />
        <TimeFrameValue label="EMA200 終値位置" value={ema200PositionLabel(timeFrame)} />
        <TimeFrameValue label="EMA200 傾き" value={ema200SlopeLabel(timeFrame)} />
        <TimeFrameValue label="EMA200 継続" value={ema200TrendLabel(timeFrame)} />
        <TimeFrameValue
          label="EMA200 Close1 / Shift1"
          value={`${formatNumber(timeFrame.ema200_close1, 5)} / ${formatNumber(timeFrame.ema200_shift1, 5)}`}
        />
        <TimeFrameValue label="EMA200比較値" value={formatNumber(timeFrame.ema200_compare, 5)} />
      </div>
    </article>
  );
}

function orderedTimeFrames(
  timeFrames: ObservationDetailTimeFrame[],
): ObservationDetailTimeFrame[] {
  return [...timeFrames].sort((left, right) => {
    const storedOrderDifference = left.time_frame_order - right.time_frame_order;
    if (storedOrderDifference !== 0) return storedOrderDifference;
    return left.id - right.id;
  });
}

function navigationAriaLabel(
  label: string,
  target: ObservationNavigationItem | null,
  available: boolean,
): string {
  if (!available) return `${label}の情報はありません`;
  if (!target) return `${label}はありません`;
  return `${label}。JST ${target.anchor_jst_time_text}、Server ${target.anchor_bar_time_text}、Run ${target.run_id}`;
}

function ObservationNavigationButton({
  arrow,
  available,
  busy,
  emptyLabel,
  label,
  target,
  onNavigate,
}: {
  arrow: "left" | "right";
  available: boolean;
  busy: boolean;
  emptyLabel: string;
  label: string;
  target: ObservationNavigationItem | null;
  onNavigate: (target: ObservationNavigationItem) => void;
}) {
  return (
    <button
      aria-label={navigationAriaLabel(label, target, available)}
      className="secondary-button observation-snapshot-grid-navigation-button"
      disabled={busy || target === null}
      title={navigationAriaLabel(label, target, available)}
      type="button"
      onClick={() => {
        if (target) onNavigate(target);
      }}
    >
      <span className="observation-snapshot-grid-navigation-label">
        <span aria-hidden="true">{arrow === "left" ? "←" : ""}</span>
        {label}
        <span aria-hidden="true">{arrow === "right" ? "→" : ""}</span>
      </span>
      <span className="observation-snapshot-grid-navigation-time">
        {target ? `JST ${target.anchor_jst_time_text}` : emptyLabel}
      </span>
    </button>
  );
}

function ObservationNavigation({
  available,
  busy,
  error,
  navigation,
  symbol,
  onNavigate,
}: {
  available: boolean;
  busy: boolean;
  error: string;
  navigation: ObservationDetailNavigation;
  symbol: string;
  onNavigate: (target: ObservationNavigationItem) => void;
}) {
  return (
    <div className="observation-snapshot-grid-navigation-area">
      <nav
        aria-label={`${symbol}の観測時刻を移動`}
        className="observation-snapshot-grid-navigation"
      >
        <ObservationNavigationButton
          arrow="left"
          available={available}
          busy={busy}
          emptyLabel={available ? "最古" : "情報なし"}
          label="前の観測"
          target={navigation.older}
          onNavigate={onNavigate}
        />
        <ObservationNavigationButton
          arrow="right"
          available={available}
          busy={busy}
          emptyLabel={available ? "最新" : "情報なし"}
          label="次の観測"
          target={navigation.newer}
          onNavigate={onNavigate}
        />
      </nav>
      {busy && (
        <p aria-hidden="true" className="observation-snapshot-grid-navigation-status">
          観測を読み込んでいます…
        </p>
      )}
      {error && (
        <p className="observation-snapshot-grid-navigation-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

function AuditDetails({
  observation,
  timeFrames,
}: {
  observation: ObservationDetailParent;
  timeFrames: ObservationDetailTimeFrame[];
}) {
  return (
    <section className="detail-section">
      <details>
        <summary>監査情報を表示</summary>
        <div className="detail-grid">
          <DetailField label="Observation ID" value={observation.id} />
          <DetailField label="Run UID" value={observation.run_uid} />
          <DetailField label="Analysis input hash" value={observation.analysis_input_hash} />
          <DetailField label="Snapshot hash" value={observation.snapshot_hash} />
          <DetailField label="Anchor epoch (JST / Server)" value={`${observation.anchor_jst_time} / ${observation.anchor_bar_time}`} />
          <DetailField
            label="Tester from / to"
            value={`${displayValue(observation.tester_from)} / ${displayValue(observation.tester_to)}`}
          />
          {orderedTimeFrames(timeFrames).map((timeFrame) => (
            <DetailField
              key={timeFrame.id}
              label={`${timeFrame.time_frame_text} row`}
              value={`ID ${timeFrame.id} / ${displayValue(timeFrame.created_at_text)}`}
            />
          ))}
        </div>
        <details className="analysis-profile-details">
          <summary>分析Profile設定を表示</summary>
          <code className="analysis-profile-text">
            {observation.analysis_input_text || "Legacy（設定詳細なし）"}
          </code>
        </details>
      </details>
    </section>
  );
}

function DetailContent({
  busy,
  navigationError,
  onNavigate,
  response,
  styleNonce,
  view,
}: {
  busy: boolean;
  navigationError: string;
  onNavigate: (target: ObservationNavigationItem) => void;
  response: ObservationDetailResponse;
  styleNonce?: string;
  view: ObservationDetailView;
}) {
  const observation = response.observation;
  if (!observation) return null;
  const timeFrames = orderedTimeFrames(response.time_frames);

  if (view === "grid") {
    return (
      <section className="observation-snapshot-grid-content">
        <div className="observation-snapshot-grid-context">
          <div>
            <p className="eyebrow">TIMEFRAME COMPARISON</p>
            <div className="observation-snapshot-grid-symbol">
              <strong>{observation.symbol_name}</strong>
              <GmoTargetBadge isTarget={observation.is_gmo_target} />
            </div>
          </div>
          <ObservationNavigation
            available={response.navigation !== undefined}
            busy={busy}
            error={navigationError}
            navigation={response.navigation ?? EMPTY_OBSERVATION_NAVIGATION}
            symbol={observation.symbol_name}
            onNavigate={onNavigate}
          />
          <div className="observation-snapshot-grid-context-values">
            <span>JST {displayValue(observation.anchor_jst_time_text)}</span>
            <span>Server {displayValue(observation.anchor_bar_time_text)}</span>
            <span>Run {observation.run_id}</span>
            <span>Spread {spreadLabel(observation.spread_pips)}</span>
            <span>Pip size {pipSizeLabel(observation.pip_size)}</span>
          </div>
        </div>
        <H1EntryCheckPanel
          spreadPips={observation.spread_pips}
          timeFrames={timeFrames}
        />
        <ObservationTimeFrameSnapshotGrid
          styleNonce={styleNonce}
          timeFrames={timeFrames}
        />
      </section>
    );
  }

  return (
    <>
      <section className="detail-hero">
        <div>
          <div className="badge-row">
            <Badge text={observation.source_mode} />
            <Badge text={observation.anchor_time_frame_text} />
            <Badge text={observation.capture_phase} />
          </div>
          <div className="detail-title-line">
            <h3 className="detail-title">{observation.symbol_name}</h3>
            <GmoTargetBadge isTarget={observation.is_gmo_target} />
          </div>
          <p className="subtitle">
            JST {displayValue(observation.anchor_jst_time_text)} / Server {displayValue(observation.anchor_bar_time_text)}
          </p>
        </div>
        <div className="detail-price">
          <strong>Run {observation.run_id}</strong>
          <span>{displayValue(observation.source)} / {displayValue(observation.source_server)}</span>
        </div>
      </section>

      <section className="detail-section">
        <h3>観測情報</h3>
        <div className="detail-grid">
          <DetailField label="Program" value={`${displayValue(observation.program_name)} ${displayValue(observation.program_version)}`} />
          <DetailField label="Strategy" value={`${displayValue(observation.strategy)} ${displayValue(observation.strategy_version)}`} />
          <DetailField label="Analysis version" value={observation.analysis_version} />
          <DetailField
            label="Analysis Profile"
            value={`${observation.analysis_profile_is_legacy ? "Legacy" : "Profile"} / ${displayValue(observation.analysis_input_hash)}`}
          />
          <DetailField label="Anchor time frame" value={observation.anchor_time_frame_text} />
          <DetailField label="Capture phase" value={observation.capture_phase} />
          <DetailField label="Spread" value={spreadLabel(observation.spread_pips)} />
          <DetailField label="Pip size" value={pipSizeLabel(observation.pip_size)} />
          <DetailField label="Source mode / server" value={`${observation.source_mode} / ${displayValue(observation.source_server)}`} />
          <DetailField label="Run started" value={observation.started_at_text} />
          <DetailField label="Tester model" value={observation.tester_model} />
          <DetailField label="保存時間足数" value={formatNumber(observation.time_frame_count, 0)} />
          <DetailField label="観測作成時刻" value={observation.created_at_text} />
        </div>
      </section>

      <section className="detail-section">
        <h3>時間足別 H1新規足スナップショット</h3>
        <div className="timeframe-grid">
          {timeFrames.map((timeFrame) => (
            <TimeFrameCard key={timeFrame.id} timeFrame={timeFrame} />
          ))}
        </div>
      </section>

      <AuditDetails observation={observation} timeFrames={timeFrames} />
    </>
  );
}

export function ObservationDetailDrawer({
  initialView = "cards",
  observationId,
  onClose,
  onNavigate,
  styleNonce,
}: ObservationDetailDrawerProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const responseRef = useRef<ObservationDetailResponse | null>(null);
  const onNavigateRef = useRef(onNavigate);
  const [response, setResponse] = useState<ObservationDetailResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [navigationAnnouncement, setNavigationAnnouncement] = useState("");
  const [view, setView] = useState<ObservationDetailView>(initialView);
  const isOpen = observationId !== null;

  useEffect(() => {
    onNavigateRef.current = onNavigate;
  }, [onNavigate]);

  useEffect(() => {
    if (!isOpen) {
      setView(initialView);
    }
  }, [initialView, isOpen]);

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
    if (observationId === null) {
      responseRef.current = null;
      setResponse(null);
      setLoading(false);
      setError("");
      setNavigationAnnouncement("");
      return;
    }
    const displayedResponse = responseRef.current;
    if (displayedResponse?.observation?.id === observationId) {
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    let active = true;
    setLoading(true);
    setError("");

    api.observationDetail(observationId, controller.signal)
      .then((value) => {
        if (!active || controller.signal.aborted) return;
        if (value.available && !value.observation) {
          throw new Error("H1観測詳細の応答が不正です");
        }
        responseRef.current = value;
        setResponse(value);
        if (displayedResponse?.observation && value.observation) {
          setNavigationAnnouncement(
            `${value.observation.symbol_name} JST ${value.observation.anchor_jst_time_text}を表示しました`,
          );
        } else {
          setNavigationAnnouncement("");
        }
      })
      .catch((reason: unknown) => {
        if (active && !controller.signal.aborted && !isAbortError(reason)) {
          const message = reason instanceof Error
            ? reason.message
            : "H1観測詳細の読み込みに失敗しました";
          if (displayedResponse?.observation) {
            setError(`${message}。現在の観測を表示しています`);
            setNavigationAnnouncement("");
            onNavigateRef.current(displayedResponse.observation.id);
          } else {
            setError(message);
          }
        }
      })
      .finally(() => {
        if (active && !controller.signal.aborted) setLoading(false);
      });

    return () => {
      active = false;
      controller.abort();
    };
  }, [observationId]);

  const navigateTo = useCallback((target: ObservationNavigationItem) => {
    if (loading) return;
    setError("");
    setNavigationAnnouncement(`JST ${target.anchor_jst_time_text}の観測を読み込んでいます`);
    onNavigate(target.id);
  }, [loading, onNavigate]);

  function handleBackdropClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target !== event.currentTarget || event.detail === 0) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const isOutside = event.clientX < bounds.left
      || event.clientX > bounds.right
      || event.clientY < bounds.top
      || event.clientY > bounds.bottom;
    if (isOutside) onClose();
  }

  const title = response?.observation
    ? `${response.observation.symbol_name} / ${response.observation.anchor_jst_time_text}`
    : "H1観測詳細";
  const hasDisplayedObservation = Boolean(response?.available && response.observation);

  return (
    <dialog
      aria-labelledby="observationDetailTitle"
      className={`react-detail-dialog observation-detail-dialog${view === "grid" ? " observation-grid-mode" : ""}`}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onClick={handleBackdropClick}
      ref={dialogRef}
    >
      <div className="drawer-header">
        <div>
          <p className="eyebrow">H1 OBSERVATION SNAPSHOT</p>
          <h2 id="observationDetailTitle">{title}</h2>
        </div>
        <div className="observation-detail-header-actions">
          {response?.available && response.observation && (
            <div
              aria-label="時間足スナップショット表示"
              className="observation-detail-view-toggle"
              role="group"
            >
              <button
                aria-pressed={view === "cards"}
                className="secondary-button"
                onClick={() => setView("cards")}
                type="button"
              >
                カード表示
              </button>
              <button
                aria-pressed={view === "grid"}
                className="secondary-button"
                onClick={() => setView("grid")}
                type="button"
              >
                全画面グリッド
              </button>
            </div>
          )}
          <button
            aria-label="H1観測詳細を閉じる"
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
        <span aria-live="polite" className="visually-hidden" role="status">
          {navigationAnnouncement}
        </span>
        {loading && !hasDisplayedObservation && (
          <p aria-live="polite" className="loading-message" role="status">
            H1観測詳細を読み込んでいます…
          </p>
        )}
        {error && (!hasDisplayedObservation || view === "cards") && (
          <p className="loading-message" role="alert">{error}</p>
        )}
        {!loading && !error && response?.available === false && (
          <p className="loading-message" role="status">
            H1観測DBはまだ利用されていません
          </p>
        )}
        {response?.available && response.observation && (
          <DetailContent
            busy={loading}
            navigationError={view === "grid" ? error : ""}
            response={response}
            styleNonce={styleNonce}
            view={view}
            onNavigate={navigateTo}
          />
        )}
      </div>
    </dialog>
  );
}
