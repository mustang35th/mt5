import { type MouseEvent, useEffect, useRef, useState } from "react";
import { m5Api } from "../api/m5Client";
import type { M5DetailResponse, M5NavigationItem } from "../api/m5Types";
import { m5Direction, m5Number, m5Text, m5TimeFrameSlots } from "../lib/m5TimeFrame";
import { M5CaptureQuality } from "./M5CaptureQuality";
import { M5TimeFrameComparison } from "./M5TimeFrameComparison";
import "./M5ObservationDetailDrawer.css";

interface Props {
  observationId: number | null;
  databaseKey: string;
  databaseName?: string;
  active?: boolean;
  onClose: () => void;
  onNavigate: (id: number) => void;
  styleNonce?: string;
}

function HashField({ label, value }: { label: string; value: unknown }) {
  const [message, setMessage] = useState("");
  const text = typeof value === "string" ? value : "";
  return <details className="m5-hash"><summary>{label}: {text ? `${text.slice(0, 16)}${text.length > 16 ? "…" : ""}` : "未記録"}</summary>
    <code>{m5Text(text)}</code>{text && <button className="secondary-button" type="button" onClick={async () => {
      try { await navigator.clipboard.writeText(text); setMessage("コピーしました"); }
      catch { setMessage("コピーできません。展開した値を選択してください。"); }
    }}>{label}をコピー</button>}<span role="status">{message}</span>
  </details>;
}

function RecordInfo({ response, databaseName }: { response: M5DetailResponse; databaseName?: string }) {
  const { observation, run } = response;
  const fields: Array<[string, unknown]> = [
    ["接続DB名", databaseName], ["Observation ID", observation.id], ["Run ID", observation.run_id],
    ["Run UID", run.run_uid], ["Source mode", observation.source_mode], ["取引サーバー", observation.source_server],
    ["Program", run.program_name], ["Program version", run.program_version],
    ["Strategy", run.strategy], ["Strategy version", run.strategy_version],
    ["Analysis version", observation.analysis_version], ["Capture phase", observation.capture_phase],
    ["Pip size（保存値）", observation.pip_size], ["記録作成日時（Server）", observation.created_at_text],
  ];
  return <section className="detail-section" aria-label="M5保存情報"><details>
    <summary className="eyebrow">RECORD INFO</summary>
    <div className="m5-record-fields">{fields.map(([label, value]) => <div className="detail-field" key={label}><span>{label}</span><strong>{m5Text(value)}</strong></div>)}</div>
    <HashField label="Analysis input hash" value={observation.analysis_input_hash} />
    <HashField label="Snapshot hash" value={observation.snapshot_hash} />
    <details className="m5-hash"><summary>接続DB識別情報・分析Profileを展開</summary><code>{response.databaseKey}</code><code>{m5Text(run.analysis_input_text)}</code></details>
    <p className="m5-note">created_atはFIFO追加前に固定した記録作成日時です。DB commit完了時刻・収集終了日時ではありません。品質値の代用にはしません。</p>
  </details></section>;
}

function NavigationButton({ target, label, busy, onNavigate }: { target: M5NavigationItem | null; label: string; busy: boolean; onNavigate: (id: number) => void }) {
  const gap = target?.gap_seconds;
  return <button className="secondary-button" type="button" disabled={busy || !target}
    aria-label={target ? `${label} JST ${target.anchor_jst_time_text}` : `${label}なし`}
    onClick={() => { if (target && !busy) onNavigate(target.id); }}>
    <strong>{label}</strong><span>{target ? `JST ${target.anchor_jst_time_text}` : "観測なし"}</span>
    {typeof gap === "number" && Number.isFinite(gap) && gap > 300 && <small>時刻差 {m5Number(gap, 0, "秒")}（休場・欠損は断定不可）</small>}
  </button>;
}

export function M5ObservationDetailDrawer({ observationId, databaseKey, databaseName, active = true, onClose, onNavigate, styleNonce }: Props) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const [response, setResponse] = useState<M5DetailResponse | null>(null);
  const [lastReadAt, setLastReadAt] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const [visible, setVisible] = useState(() => document.visibilityState !== "hidden");
  const isOpen = active && observationId !== null;
  const requestKey = isOpen ? `${databaseKey}:${observationId}` : "";
  const latestRequest = useRef(requestKey);
  latestRequest.current = requestKey;

  useEffect(() => {
    const changed = () => setVisible(document.visibilityState !== "hidden");
    document.addEventListener("visibilitychange", changed);
    return () => document.removeEventListener("visibilitychange", changed);
  }, []);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog || !isOpen) return;
    const previousFocus = document.activeElement;
    const hadLock = document.body.classList.contains("drawer-open");
    if (!dialog.open) dialog.showModal();
    document.body.classList.add("drawer-open");
    closeRef.current?.focus();
    return () => {
      if (dialog.open) dialog.close();
      if (!hadLock) document.body.classList.remove("drawer-open");
      if (previousFocus instanceof HTMLElement && previousFocus.isConnected) previousFocus.focus({ preventScroll: true });
    };
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || observationId === null || !visible || !databaseKey) {
      setLoading(false);
      setError("");
      if (!isOpen) setResponse(null);
      return;
    }
    const controller = new AbortController();
    let current = true;
    setLoading(true);
    setError("");
    m5Api.detail(observationId, databaseKey, controller.signal).then((result) => {
      if (!current || controller.signal.aborted || latestRequest.current !== requestKey) return;
      if (result.databaseKey !== databaseKey || result.observation?.id !== observationId
          || result.run?.id !== result.observation.run_id || !Array.isArray(result.timeframes)) {
        throw new Error("接続DBまたは観測IDが変わりました。一覧を更新して選択し直してください。");
      }
      setResponse(result);
      setLastReadAt(new Date().toLocaleString("ja-JP"));
      if (bodyRef.current) bodyRef.current.scrollTop = 0;
    }).catch((reason: unknown) => {
      if (!current || controller.signal.aborted || latestRequest.current !== requestKey) return;
      setError(reason instanceof Error ? reason.message : "M5観測詳細の更新に失敗しました");
    }).finally(() => {
      if (current && !controller.signal.aborted && latestRequest.current === requestKey) setLoading(false);
    });
    return () => { current = false; controller.abort(); };
  }, [databaseKey, isOpen, observationId, requestKey, retry, visible]);

  const shown = response?.databaseKey === databaseKey && response.observation.id === observationId ? response : null;
  const observation = shown?.observation;
  const anchor = shown ? m5TimeFrameSlots(shown.timeframes).slots.find((slot) => slot.id === 5)?.timeFrame : null;
  function backdropClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target !== event.currentTarget || event.detail === 0) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) onClose();
  }
  return <dialog className="react-detail-dialog m5-detail-dialog" aria-labelledby="m5DetailTitle" ref={dialogRef}
    onCancel={(event) => { event.preventDefault(); onClose(); }} onClick={backdropClick}>
    <div className="drawer-header"><div><p className="eyebrow">M5 OBSERVATION SNAPSHOT</p>
      <h2 id="m5DetailTitle">{observation ? `${observation.symbol_name} / ${m5Text(observation.anchor_jst_time_text)} JST` : "M5観測詳細"}</h2></div>
      <button className="close-button" aria-label="M5観測詳細を閉じる" onClick={onClose} ref={closeRef} type="button">×</button>
    </div>
    <div className="drawer-body" aria-busy={loading} ref={bodyRef}>
      <p className="m5-database-name">M5 DB: {databaseName || "接続名未記録"}</p>
      {loading && <p role="status">M5観測詳細を読み込んでいます…</p>}
      {error && <div role="alert" className="m5-warning">更新失敗：{error}{shown && `。前回取得した保存値を表示しています。最終読取成功（ブラウザー時刻）：${lastReadAt}`}<button className="secondary-button" type="button" onClick={() => setRetry((value) => value + 1)}>再試行</button></div>}
      {shown && observation && <>
        <div className="m5-detail-context"><span>M5開始 JST {m5Text(observation.anchor_jst_time_text)}</span><span>Server {m5Text(observation.anchor_bar_time_text)}</span>
          <span>M5分析方向 <b className={`badge ${m5Direction(anchor?.is_buy).toLowerCase()}`}>{m5Direction(anchor?.is_buy)}</b></span>
          <span>Spread {m5Number(observation.spread_pips, 1, " pips")}</span><span>Run {observation.run_id}</span>
        </div>
        <nav className="m5-detail-navigation" aria-label="同一Run・通貨の前後観測">
          <NavigationButton label="前の観測" target={shown.navigation.older} busy={loading} onNavigate={onNavigate} />
          <NavigationButton label="次の観測" target={shown.navigation.newer} busy={loading} onNavigate={onNavigate} />
        </nav>
        <p className="m5-note">同一Run・通貨の前後観測。一覧の検索範囲外へ移動する場合あり。時刻差から休場・欠損を断定せず、観測の補間はしません。</p>
        <M5TimeFrameComparison timeFrames={shown.timeframes} styleNonce={styleNonce} />
        <M5CaptureQuality observation={observation} metrics={shown.captureMetrics} state={shown.captureMetricsState} />
        <RecordInfo response={shown} databaseName={databaseName} />
      </>}
    </div>
  </dialog>;
}
