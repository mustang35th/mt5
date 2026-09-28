import { useEffect, useRef, useState } from "react";
import { eaApi, EaApiError } from "../api/eaClient";
import type { EaMetadata, EaSamplesResponse, EaSession, EaSummary, EaTradeDetail, EaTradeSearch, EaTradesResponse } from "../api/eaTypes";
import { eaMoney, eaNumber, eaState, eaTime, eaTone } from "../lib/eaFormat";
import { H1EaChart } from "./H1EaChart";
import { EaDirection, H1EaTradeDetail } from "./H1EaTradeDetail";
import { Pagination } from "./Pagination";
import "./H1EaResults.css";

const DEFAULT_SEARCH: EaTradeSearch = { symbol: "", profit: "all", status: "all", page: 1, page_size: 25, sort: "opened_at_msc", direction: "desc" };
function errorText(error: unknown): string {
  if (error instanceof EaApiError && error.status === 409) return "接続DBが変更されました。「更新」でテストを選び直してください。";
  return error instanceof Error ? error.message : "H1 EA結果の読み込みに失敗しました。";
}
function initialSession(): string {
  const params = new URLSearchParams(window.location.search);
  return params.get("tab") === "ea" ? params.get("session") || "" : "";
}
function sessionLabel(session: EaSession): string {
  const start = eaTime(session.started_server_time).slice(0, 10);
  const end = session.ended_server_time ? eaTime(session.ended_server_time).slice(0, 10) : "記録終了日時なし";
  return `${start} – ${end} ｜ ${session.symbols.length}通貨 ｜ ${session.source_mode} ｜ ${session.key.slice(-10)}`;
}

/** The EA view has its own DB identity and never depends on the alert DB. */
export function H1EaResultsView({ active }: { active: boolean }) {
  const [metadata, setMetadata] = useState<EaMetadata | null>(null);
  const [sessions, setSessions] = useState<EaSession[]>([]);
  const [sessionTotal, setSessionTotal] = useState(0);
  const [sessionPage, setSessionPage] = useState(1);
  const [sessionKey, setSessionKey] = useState(initialSession);
  const [summary, setSummary] = useState<EaSummary | null>(null);
  const [samples, setSamples] = useState<EaSamplesResponse | null>(null);
  const [trades, setTrades] = useState<EaTradesResponse | null>(null);
  const [detail, setDetail] = useState<EaTradeDetail | null>(null);
  const [search, setSearch] = useState<EaTradeSearch>(DEFAULT_SEARCH);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [revision, setRevision] = useState(0);
  const [connectionLoading, setConnectionLoading] = useState(false);
  const [summaryLoading, setSummaryLoading] = useState(false);
  const [samplesLoading, setSamplesLoading] = useState(false);
  const [tradesLoading, setTradesLoading] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [moreLoading, setMoreLoading] = useState(false);
  const [connectionError, setConnectionError] = useState("");
  const [summaryError, setSummaryError] = useState("");
  const [samplesError, setSamplesError] = useState("");
  const [tradesError, setTradesError] = useState("");
  const [detailError, setDetailError] = useState("");
  const databaseIdentity = useRef("");
  const selectedSession = useRef(sessionKey);
  const moreRequest = useRef<AbortController | null>(null);
  const databaseKey = metadata?.database_key || metadata?.database?.key || "";
  const available = Boolean(metadata?.available && databaseKey);
  selectedSession.current = sessionKey;

  useEffect(() => {
    if (!active) return;
    const controller = new AbortController();
    setSummaryLoading(false); setSamplesLoading(false); setTradesLoading(false); setDetailLoading(false); setMoreLoading(false);
    setSummaryError(""); setSamplesError(""); setTradesError(""); setDetailError("");
    setConnectionLoading(true); setConnectionError(""); setMetadata(null); setSummary(null); setSamples(null); setTrades(null); setDetail(null); setSelectedId(null);
    void (async () => {
      try {
        const info = await eaApi.metadata(controller.signal);
        if (controller.signal.aborted) return;
        const key = info.database_key || info.database?.key || "";
        const replaced = databaseIdentity.current !== "" && databaseIdentity.current !== key;
        databaseIdentity.current = key;
        if (!info.available) { setMetadata(info); setSessions([]); setSessionTotal(0); return; }
        const response = await eaApi.sessions(key, 1, controller.signal);
        if (controller.signal.aborted) return;
        setSessions(response.items); setSessionTotal(response.total); setSessionPage(1);
        if (replaced) { setSearch(DEFAULT_SEARCH); setSessionKey(response.items[0]?.key || ""); }
        else if (!selectedSession.current) setSessionKey(response.items[0]?.key || "");
        setMetadata(info);
      } catch (error) { if (!controller.signal.aborted) setConnectionError(errorText(error)); }
      finally { if (!controller.signal.aborted) setConnectionLoading(false); }
    })();
    return () => { controller.abort(); moreRequest.current?.abort(); };
  }, [active, revision]);

  useEffect(() => {
    if (!active || !available || !sessionKey) { setSummaryLoading(false); setSamplesLoading(false); return; }
    const params = new URLSearchParams({ tab: "ea", session: sessionKey });
    window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
    const controller = new AbortController();
    setSummaryLoading(true); setSamplesLoading(true); setSummaryError(""); setSamplesError(""); setSummary(null); setSamples(null);
    eaApi.summary(sessionKey, databaseKey, controller.signal)
      .then(nextSummary => { if (!controller.signal.aborted) setSummary(nextSummary); })
      .catch(error => { if (!controller.signal.aborted) setSummaryError(errorText(error)); })
      .finally(() => { if (!controller.signal.aborted) setSummaryLoading(false); });
    eaApi.samples(sessionKey, databaseKey, controller.signal)
      .then(nextSamples => { if (!controller.signal.aborted) setSamples(nextSamples); })
      .catch(error => { if (!controller.signal.aborted) setSamplesError(errorText(error)); })
      .finally(() => { if (!controller.signal.aborted) setSamplesLoading(false); });
    return () => controller.abort();
  }, [active, available, databaseKey, sessionKey, revision]);

  useEffect(() => {
    if (!active || !available || !sessionKey) { setTradesLoading(false); return; }
    const controller = new AbortController();
    setTradesLoading(true); setTradesError(""); setTrades(null); setSelectedId(null); setDetail(null);
    eaApi.trades(sessionKey, databaseKey, search, controller.signal)
      .then(response => {
        if (controller.signal.aborted) return;
        if (response.page !== search.page) { setSearch(previous => ({ ...previous, page: response.page })); return; }
        setTrades(response); setSelectedId(response.items[0]?.id || null);
      })
      .catch(error => { if (!controller.signal.aborted) setTradesError(errorText(error)); })
      .finally(() => { if (!controller.signal.aborted) setTradesLoading(false); });
    return () => controller.abort();
  }, [active, available, databaseKey, sessionKey, search, revision]);

  useEffect(() => {
    setDetail(null); setDetailError("");
    if (!active || !available || !sessionKey || selectedId === null) { setDetailLoading(false); return; }
    const controller = new AbortController();
    setDetailLoading(true);
    eaApi.detail(selectedId, sessionKey, databaseKey, search, controller.signal)
      .then(response => { if (!controller.signal.aborted) setDetail(response); })
      .catch(error => { if (!controller.signal.aborted) setDetailError(errorText(error)); })
      .finally(() => { if (!controller.signal.aborted) setDetailLoading(false); });
    return () => controller.abort();
  }, [active, available, databaseKey, sessionKey, search, selectedId, revision]);

  async function loadMoreSessions() {
    moreRequest.current?.abort();
    const controller = new AbortController(); moreRequest.current = controller;
    setMoreLoading(true);
    try {
      const response = await eaApi.sessions(databaseKey, sessionPage + 1, controller.signal);
      if (controller.signal.aborted) return;
      setSessions(previous => [...previous, ...response.items.filter(item => !previous.some(known => known.key === item.key))]);
      setSessionPage(response.page); setSessionTotal(response.total);
    } catch (error) { if (!controller.signal.aborted) setConnectionError(errorText(error)); }
    finally { if (!controller.signal.aborted) setMoreLoading(false); }
  }
  function changeSession(key: string) {
    setSessionKey(key); setSelectedId(null); setDetail(null); setSummary(null); setSamples(null); setSearch(previous => ({ ...DEFAULT_SEARCH, page_size: previous.page_size }));
  }
  function filter(patch: Partial<EaTradeSearch>) { setSearch(previous => ({ ...previous, ...patch, page: 1 })); }
  if (!active) return null;
  const currentSummary = summary?.session.key === sessionKey ? summary : null;
  const session = currentSummary?.session || sessions.find(item => item.key === sessionKey);
  const currency = session?.account_currency || null;
  const unit = currency || "口座通貨不明";
  const choices = session && !sessions.some(item => item.key === session.key) ? [session, ...sessions] : sessions;
  const metrics = currentSummary?.metrics;
  const standard = currentSummary?.account_statistics;
  const maximum = currentSummary?.max_positions;
  const currentDetail = detail?.session.key === sessionKey && detail.trade.id === selectedId ? detail : null;
  const missingStatistic = standard?.available ? "—" : "未記録";
  const maximumText = maximum?.value != null ? `${maximum.value}件` : maximum?.reference_value != null ? `${maximum.reference_value}件（参考）` : "未集計";
  const busy = connectionLoading || summaryLoading || tradesLoading;
  return <section id="viewer-tabpanel-ea" className="viewer-tab-panel ea-view" role="tabpanel" aria-labelledby="viewer-tab-ea">
    <header className="ea-panel ea-header"><div><p className="eyebrow">H1 EA RESULTS</p><h2>MstngH1EaAll</h2></div><span className="ea-database" title={metadata?.database?.path}>{metadata?.database?.name || "H1 EA結果DB"} · 読取専用</span><button type="button" disabled={busy} onClick={() => setRevision(value => value + 1)}>更新</button></header>
    {connectionError && <p className="ea-error" role="alert">{connectionError}</p>}
    {connectionLoading && <p className="ea-note" role="status">結果DBを確認しています…</p>}
    {metadata && !metadata.available && <div className="ea-panel"><h3>結果DBを参照できません</h3><p>{metadata.reason || "DBのパスと保存状態を確認してください。"}</p><p className="ea-note">start-ea-viewer.cmd から起動するか、--ea-database で結果DBを指定できます。</p></div>}
    {available && <>
      <section className="ea-panel ea-session" aria-label="テスト選択"><div className="ea-session-row"><label>テスト<select aria-label="テスト" value={sessionKey} disabled={connectionLoading} onChange={event => changeSession(event.target.value)}>
        {!choices.length && <option value="">テスト記録なし</option>}
        {sessionKey && !choices.some(item => item.key === sessionKey) && <option value={sessionKey}>指定テスト {sessionKey.slice(-12)}</option>}
        {choices.map(item => <option key={item.key} value={item.key}>{sessionLabel(item)}</option>)}
      </select></label>{session && <span className={`ea-record-state ${session.recording_state === "FAILED" ? "ea-sell" : ""}`}>{eaState(session.recording_state)}</span>}
        {sessions.length < sessionTotal && <button type="button" disabled={moreLoading} onClick={() => void loadMoreSessions()}>{moreLoading ? "読込中…" : "以前のテストを追加"}</button>}
      </div>{session && <div className="ea-session-info"><span>テスト内期間 {eaTime(session.started_server_time)} – {eaTime(session.ended_server_time)} Server</span><span>売買開始 {session.trade_start_time === 0 ? "制限なし" : eaTime(session.trade_start_time)}</span><span>通貨 {unit}</span><span>v{session.program_version || "不明"} · {session.run_count} Run</span>{standard?.initial_deposit != null && <span>初期資金 {eaMoney(standard.initial_deposit, currency)} {unit}</span>}</div>}</section>
      {session?.error_text && <p className="ea-error" role="alert">記録エラー：{session.error_text}</p>}
      {session?.config_texts?.length ? <details className="ea-panel ea-skips"><summary>テスト設定・接続先</summary><p className="ea-note">{session.account_server} ／ レバレッジ {session.leverage ?? "未記録"}</p>{session.config_texts.map((config, index) => <pre className="ea-config" key={index}>{config}</pre>)}</details> : null}
      {summaryError && <p className="ea-error" role="alert">{summaryError}</p>}
      {summaryLoading && <p className="ea-note" role="status">成績・資産推移を読み込んでいます…</p>}
      {currentSummary && <>
        <section className="ea-metrics" aria-label="テスト成績">
          <Metric label="確定純損益" value={eaMoney(metrics?.net_profit, currency, true)} note={`${unit} · 対象EA`} tone={eaTone(metrics?.net_profit)} />
          <Metric label="勝率" value={`${eaNumber(metrics?.win_rate, 1)}${metrics?.win_rate == null ? "" : "%"}`} note={`${metrics?.wins}勝 / 損益取得済み${metrics?.known_pnl_trades}件`} />
          <Metric label="PF" value={eaNumber(metrics?.profit_factor, 2)} note={metrics?.losses === 0 && Boolean(metrics?.wins) ? "対象EA · 損失取引なし" : "対象EA · 費用込み"} />
          <Metric label="最大DD額" value={standard?.equity_drawdown == null ? missingStatistic : eaMoney(standard.equity_drawdown, currency)} note={`${unit} · MT5 / 口座全体`} />
          <Metric label="最大DD率" value={standard?.equity_drawdown_percent == null ? missingStatistic : `${eaNumber(standard.equity_drawdown_percent, 2)}%`} note="MT5 / 口座全体" />
          <Metric label="最大同時保有数" value={maximumText} note={maximum?.source === "SESSION_DEALS" ? "対象EA · 約定から集計" : maximum?.source === "TRADE_EVENTS" ? "対象EA · 履歴から参考集計" : "対象EA · 記録不足"} />
        </section>
        <div className="ea-summary-note"><span>保有・処理中 {metrics?.open_trades}件 ／ 決済済み {metrics?.closed_trades}件</span>{Boolean(metrics?.unknown_pnl_trades) && <span>損益未確定・欠損 {metrics?.unknown_pnl_trades}件（成績集計対象外）</span>}<span>最大DD額と率は最大となる時点が異なる場合があります。</span></div>
        {maximum?.reason && <p className="ea-note">同時保有数：{maximum.reason}</p>}
        {currentSummary.warnings.length > 0 && <div className="ea-warning" role="status">{currentSummary.warnings.map((warning, index) => <p key={index}>{warning}</p>)}</div>}
      </>}
      {samples && <H1EaChart samples={samples} currency={currency} />}
      {samplesLoading && <p className="ea-note" role="status">資産推移を読み込んでいます…</p>}
      {samplesError && <p className="ea-error" role="alert">資産推移：{samplesError}</p>}
      {sessionKey && <>
        <section className="ea-panel" aria-label="取引一覧" aria-busy={tradesLoading}>
          <div className="ea-panel-heading"><h3>取引一覧</h3><div className="ea-filters">
            <label>通貨<select value={search.symbol} onChange={event => filter({ symbol: event.target.value })}><option value="">すべて</option>{session?.symbols.map(symbol => <option key={symbol}>{symbol}</option>)}</select></label>
            <label>損益<select value={search.profit} onChange={event => filter({ profit: event.target.value as EaTradeSearch["profit"] })}><option value="all">すべて</option><option value="win">利益のみ</option><option value="loss">損失のみ</option></select></label>
            <label>状態<select value={search.status} onChange={event => filter({ status: event.target.value as EaTradeSearch["status"] })}><option value="all">すべて</option><option value="closed">決済済み</option><option value="open">保有・処理中</option></select></label>
            <label>並び順<select value={search.sort} onChange={event => filter({ sort: event.target.value as EaTradeSearch["sort"] })}><option value="opened_at_msc">エントリー日時</option><option value="closed_at_msc">決済日時</option><option value="net_profit">純損益</option><option value="symbol_name">通貨</option><option value="id">取引ID</option></select></label>
            <button type="button" aria-label="並び順の向き" onClick={() => filter({ direction: search.direction === "asc" ? "desc" : "asc" })}>{search.direction === "asc" ? "昇順 ↑" : "降順 ↓"}</button>
          </div></div>
          {tradesError && <p className="ea-error" role="alert">{tradesError}</p>}
          <div className="ea-table-wrap"><table><thead><tr><th>通貨</th><th>方向</th><th>エントリー / Server</th><th>決済 / Server</th><th className="ea-number">約定Lot</th><th className="ea-number">純損益 / {unit}</th><th>状態・決済理由</th></tr></thead><tbody>
            {trades?.items.map(trade => <tr key={trade.id} className={selectedId === trade.id ? "ea-selected" : ""}><td><button type="button" className="ea-trade-link" aria-label={`${trade.symbol_name} 取引${trade.id}の詳細`} onClick={() => setSelectedId(trade.id)}>{trade.symbol_name}</button></td><td><EaDirection value={trade.side} /></td><td>{eaTime(trade.opened_at_msc, true)}</td><td>{eaTime(trade.closed_at_msc, true)}</td><td className="ea-number">{eaNumber(trade.opened_volume, 4)}</td><td className={`ea-number ${eaTone(trade.net_profit)}`}>{eaMoney(trade.net_profit, currency, true)}</td><td>{trade.status === "CLOSED" ? trade.close_reason || "決済済み" : trade.status}</td></tr>)}
            {!trades?.items.length && <tr><td colSpan={7} className="ea-empty">{tradesLoading ? "取引を読み込んでいます…" : tradesError ? "取得できませんでした。" : "条件に一致する取引はありません。"}</td></tr>}
          </tbody></table></div>
          <div className="ea-pagination"><span>{eaNumber(trades?.total || 0, 0)}件</span><label>ページ件数<select value={search.page_size} onChange={event => filter({ page_size: Number(event.target.value) })}>{[25, 50, 100].map(size => <option key={size} value={size}>{size}</option>)}</select></label><Pagination page={trades?.page || search.page} pageCount={trades?.total_pages || 0} disabled={tradesLoading} onPage={page => setSearch(previous => ({ ...previous, page }))} /></div>
        </section>
        <H1EaTradeDetail detail={currentDetail} loading={detailLoading} error={detailError} onNavigate={setSelectedId} />
        {Boolean(currentSummary?.skip_reasons.length) && <details className="ea-panel ea-skips"><summary>見送り理由（選択テスト全体）</summary><div className="ea-table-wrap"><table><thead><tr><th>理由</th><th className="ea-number">件数</th></tr></thead><tbody>{currentSummary?.skip_reasons.map(item => <tr key={item.reason_code}><td>{item.reason_code}</td><td className="ea-number">{eaNumber(item.count, 0)}</td></tr>)}</tbody></table></div></details>}
        <p className="ea-note">時刻：Server ／ 成績は選択テスト全体。通貨・損益・状態の絞り込みは取引一覧と詳細の前後移動に適用します。</p>
      </>}
      {!sessionKey && !connectionLoading && <p className="ea-empty">保存されたテストはありません。</p>}
    </>}
  </section>;
}

function Metric({ label, value, note, tone = "" }: { label: string; value: string; note: string; tone?: string }) {
  return <div className="ea-metric"><span>{label}</span><strong className={tone}>{value}</strong><small>{note}</small></div>;
}
