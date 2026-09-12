import { useCallback, useEffect, useRef, useState } from "react";
import { m5Api } from "../api/m5Client";
import type { M5ListResponse, M5Metadata, M5SearchState, M5Sort, M5SourceMode } from "../api/m5Types";
import { DEFAULT_M5_SEARCH, M5_JST_TIMES, latestM5Range, m5DateTime, readM5Search,
  replaceM5SearchUrl, validateM5Search } from "../lib/m5ObservationSearchState";
import { M5_REFRESH_KEY, readM5Preference, writeM5Preference } from "../lib/m5ObservationPreferences";
import { isRefreshIntervalSeconds, type RefreshIntervalSeconds } from "../lib/refreshSettings";
import { AppliedConditionSummary } from "./AppliedConditionSummary";
import { FilterVisibilityToggle } from "./FilterVisibilityToggle";
import { M5ObservationDetailDrawer } from "./M5ObservationDetailDrawer";
import { M5ObservationTable } from "./M5ObservationTable";
import { Pagination } from "./Pagination";
import { RefreshControls } from "./RefreshControls";
import "./M5Observation.css";

interface Props { active: boolean; styleNonce?: string }
type RequestKind = "initial" | "refresh" | "reset" | "search" | "latest";

/** M5 owns its database identity, selection and URL state independently of H1. */
export function M5ObservationView({ active, styleNonce }: Props) {
  const [applied, setApplied] = useState<M5SearchState>(() => readM5Search(window.location.search));
  const [draft, setDraft] = useState(applied);
  const [metadata, setMetadata] = useState<M5Metadata | null>(null);
  const [result, setResult] = useState<M5ListResponse | null>(null);
  const [displayedSearch, setDisplayedSearch] = useState<M5SearchState | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [validation, setValidation] = useState("");
  const [lastChecked, setLastChecked] = useState("");
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [searchExpanded, setSearchExpanded] = useState(true);
  const [connectionExpanded, setConnectionExpanded] = useState(false);
  const [intervalSeconds, setIntervalSeconds] = useState<RefreshIntervalSeconds>(() =>
    readM5Preference<RefreshIntervalSeconds>(M5_REFRESH_KEY, 15, (value): value is RefreshIntervalSeconds =>
      typeof value === "number" && isRefreshIntervalSeconds(value)));
  const appliedRef = useRef(applied);
  const activeRef = useRef(active);
  const dirtyDraft = useRef(false);
  const databaseKey = useRef(applied.databaseKey);
  const request = useRef<AbortController | null>(null);
  const busy = useRef(false);
  const initialized = useRef(false);
  const detailTrigger = useRef<HTMLElement | null>(null);

  const load = useCallback(async (requested: M5SearchState, kind: RequestKind) => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    const current = () => activeRef.current && request.current === controller && !controller.signal.aborted;
    busy.current = true; setLoading(true); setError(""); setValidation("");
    let candidate = { ...requested };
    try {
      // The first metadata call intentionally omits Run: detect DB replacement before reusing an old ID.
      for (let attempt = 0; attempt < 2; attempt++) {
        let info = await m5Api.metadata(candidate.sourceMode, null, controller.signal);
        if (!current()) return;
        const key = info.database?.key || "";
        const replaced = Boolean((databaseKey.current && databaseKey.current !== key)
          || (candidate.databaseKey && candidate.databaseKey !== key));
        if (replaced) {
          setResult(null); setDisplayedSearch(null); setSelectedId(null);
          setNotice("接続DBが変更されたため、旧DBのRun・検索・詳細を解除しました。");
          candidate = { ...DEFAULT_M5_SEARCH, sourceMode: candidate.sourceMode, pageSize: candidate.pageSize,
            followLatest: candidate.sourceMode === "LIVE" };
          kind = "reset";
          dirtyDraft.current = false;
        }
        databaseKey.current = key;
        setMetadata(info);
        if (info.available && candidate.runId !== null && candidate.runId !== info.effectiveRunId) {
          info = await m5Api.metadata(candidate.sourceMode, candidate.runId, controller.signal);
          if (!current()) return;
          if (info.database?.key !== key) { candidate = { ...candidate, databaseKey: key }; continue; }
          setMetadata(info);
        }
        let next: M5SearchState = { ...candidate, databaseKey: key, runId: info.effectiveRunId };
        const noDates = !next.from && !next.to;
        if (kind === "reset" || kind === "latest" || noDates || (kind === "refresh" && next.followLatest)) {
          next = { ...next, ...latestM5Range(info.range.last) };
          if (kind === "reset" || kind === "latest") {
            next.page = 1; next.sort = "anchor_jst_time"; next.order = "desc";
            next.followLatest = next.sourceMode === "LIVE";
          }
        }
        appliedRef.current = next; setApplied(next);
        if (kind !== "refresh" || !dirtyDraft.current) setDraft(next);
        replaceM5SearchUrl(next);
        if (!info.available || next.runId === null || (!next.from && !next.to)) {
          setResult(null); setDisplayedSearch(null); setSelectedId(null);
          setLastChecked(new Date().toLocaleString("ja-JP"));
          return;
        }
        const invalid = validateM5Search(next);
        if (invalid) { setValidation(invalid); return; }
        const rows = await m5Api.observations(next, controller.signal);
        if (!current()) return;
        if (rows.databaseKey !== key) {
          setResult(null); setDisplayedSearch(null); setSelectedId(null);
          setNotice("取得中に接続DBが変更されました。旧DBの選択を解除して再取得します。");
          candidate = { ...DEFAULT_M5_SEARCH, sourceMode: next.sourceMode, pageSize: next.pageSize, databaseKey: key };
          kind = "reset"; dirtyDraft.current = false;
          continue;
        }
        // Keep server-clamped pagination consistent with both URL and visible controls.
        next = { ...next, page: rows.page };
        appliedRef.current = next; setApplied(next); replaceM5SearchUrl(next);
        if (kind !== "refresh" || !dirtyDraft.current) setDraft(next);
        setResult(rows); setDisplayedSearch(next);
        setLastChecked(new Date().toLocaleString("ja-JP"));
        return;
      }
      throw new Error("接続DBが取得中に変更されました。今すぐ更新で再取得してください。");
    } catch (caught) {
      if (current()) setError(caught instanceof Error ? caught.message : "M5データの取得に失敗しました。");
    } finally {
      if (request.current === controller) { busy.current = false; setLoading(false); }
    }
  }, []);

  useEffect(() => {
    activeRef.current = active;
    if (active) {
      const kind = initialized.current ? "refresh" : "initial";
      initialized.current = true;
      void load(appliedRef.current, kind);
    } else {
      request.current?.abort(); busy.current = false; setLoading(false);
    }
    return () => { activeRef.current = false; request.current?.abort(); };
  }, [active, load]);
  useEffect(() => {
    if (!active || applied.sourceMode !== "LIVE") return;
    const refresh = () => {
      if (!document.hidden && !busy.current && activeRef.current) void load(appliedRef.current, "refresh");
    };
    const timer = intervalSeconds > 0 ? window.setInterval(refresh, intervalSeconds * 1000) : null;
    const onVisibility = () => { if (!document.hidden) refresh(); };
    document.addEventListener("visibilitychange", onVisibility);
    return () => { if (timer !== null) window.clearInterval(timer); document.removeEventListener("visibilitychange", onVisibility); };
  }, [active, applied.sourceMode, intervalSeconds, load]);

  function resetSelection(sourceMode: M5SourceMode, runId: number | null) {
    const next = { ...DEFAULT_M5_SEARCH, sourceMode, runId, databaseKey: databaseKey.current,
      pageSize: appliedRef.current.pageSize, followLatest: sourceMode === "LIVE" };
    dirtyDraft.current = false; setDraft(next); setApplied(next); appliedRef.current = next;
    setSelectedId(null); setResult(null); setDisplayedSearch(null); setNotice("");
    void load(next, "reset");
  }
  function editDraft(patch: Partial<M5SearchState>) {
    dirtyDraft.current = true;
    setDraft((previous) => ({ ...previous, ...patch, followLatest: false }));
    if (appliedRef.current.followLatest) {
      const fixed = { ...appliedRef.current, followLatest: false };
      appliedRef.current = fixed; setApplied(fixed); replaceM5SearchUrl(fixed);
    }
  }
  function search() {
    const next = { ...draft, page: 1, followLatest: false };
    const invalid = validateM5Search(next);
    setValidation(invalid);
    if (invalid) return;
    dirtyDraft.current = false; void load(next, "search");
  }
  const sortRows = useCallback((sort: M5Sort) => {
    const previous = appliedRef.current;
    const next = { ...previous, sort, order: (previous.sort === sort && previous.order === "asc" ? "desc" : "asc") as "asc" | "desc",
      page: 1, followLatest: false };
    dirtyDraft.current = false; void load(next, "search");
  }, [load]);
  const openDetail = useCallback((id: number, trigger: HTMLElement) => {
    detailTrigger.current = trigger; setSelectedId(id);
  }, []);
  if (!active) return null;
  const runs = metadata?.runs.filter((run) => run.source_mode === applied.sourceMode) || [];
  const selectedRun = runs.find((run) => run.id === applied.runId);
  const latestRun = runs.find((run) => run.observation_count > 0);
  const hasLive = metadata?.runs.some((run) => run.source_mode === "LIVE");
  const newerOutsideRange = applied.sourceMode === "LIVE" && !applied.followLatest && displayedSearch
    && metadata?.range.last && m5DateTime(metadata.range.last) >= displayedSearch.to;
  const available = Boolean(metadata?.available);
  const connectionText = error ? "読込エラー" : !metadata ? "確認中"
    : metadata.status === "NOT_CONFIGURED" ? "未設定" : available ? "接続済み" : "接続エラー";
  const connectionTone = error || (metadata && !available && metadata.status !== "NOT_CONFIGURED")
    ? "error" : available ? "ready" : "pending";
  const refreshStatus = applied.sourceMode === "TESTER" ? "TESTER：手動更新"
    : intervalSeconds === 0 ? "LIVE：自動更新OFF" : `LIVE：${intervalSeconds}秒更新（非表示中は停止）`;
  return <section id="viewer-tabpanel-m5" className="viewer-tab-panel m5-observation-view" role="tabpanel" aria-labelledby="viewer-tab-m5">
    <header className="m5-panel m5-header">
      <div className="m5-heading">
        <FilterVisibilityToggle controls="m5-filter-panel" expanded={searchExpanded} onExpandedChange={setSearchExpanded} />
        <h2 title="M5 OBSERVATIONS">M5 OBSERVATIONS</h2>
        <span className={`m5-connection-status m5-connection-${connectionTone}`} role="status" aria-label="DB接続状態"
          title={error || metadata?.reason || metadata?.status || undefined}>{connectionText}</span>
        <div className="m5-database" title={metadata?.database?.path || undefined}>接続DB：{metadata?.database?.name || "未設定／確認中"}</div>
        <span className="m5-header-run">{selectedRun ? `Run ${selectedRun.id}` : "Runなし"}</span>
        <button className="secondary-button m5-header-button" type="button" aria-controls="m5-connection-details"
          aria-expanded={connectionExpanded} onClick={() => setConnectionExpanded(!connectionExpanded)}>
          接続詳細 <span aria-hidden="true">{connectionExpanded ? "▴" : "▾"}</span>
        </button>
      </div>
      <div id="m5-connection-details" className="m5-connection-info" role="region" aria-label="接続詳細" hidden={!connectionExpanded}>
        <dl>
        <dt>解決済みパス</dt><dd>{metadata?.database?.path || "未設定"}</dd>
        <dt>接続状態</dt><dd>{metadata?.status || "確認中"}{metadata?.reason ? ` / ${metadata.reason}` : ""}{error ? ` / ${error}` : ""}</dd>
        <dt>選択Run</dt><dd>{selectedRun ? `Run ${selectedRun.id} / ${selectedRun.program_name || "未記録"} v${selectedRun.program_version || "未記録"}` : "なし"}</dd>
        <dt>分析Profile</dt><dd>analysis version: {selectedRun?.analysis_version || "未記録"}<br />input hash: {selectedRun?.analysis_input_hash || "未記録"}
          {selectedRun?.analysis_input_text && <pre>{selectedRun.analysis_input_text}</pre>}</dd>
        </dl>
        <p className="m5-muted">M5基準・7時間足の保存済み観測を表示します。売買判定や収集の終了判定は行いません。</p>
      </div>
    </header>
    <div className={`viewer-workspace m5-workspace${searchExpanded ? "" : " filter-sidebar-collapsed"}`}>
      <aside id="m5-filter-panel" className="viewer-filter-sidebar" aria-label="M5検索条件" hidden={!searchExpanded}>
        <div className="m5-panel m5-filter-panel">
          <h3>M5 OBSERVATION SEARCH</h3>
          <div className="m5-search-fields">
            <label>実行モード<select aria-label="M5実行モード" value={applied.sourceMode} onChange={(event) => resetSelection(event.target.value as M5SourceMode, null)}>
              <option value="TESTER">TESTER</option><option value="LIVE">LIVE</option>
            </select></label>
            <label>Run（1件必須）<select aria-label="M5 Run" value={applied.runId ?? ""} disabled={!available || !runs.length}
              onChange={(event) => resetSelection(applied.sourceMode, Number(event.target.value))}>
              {!runs.length && <option value="">Runなし</option>}
              {runs.map((run) => <option key={run.id} value={run.id}>Run {run.id} · v{run.program_version || "未記録"}{run.observation_count === 0 ? " · 未収集" : ""}</option>)}
            </select></label>
          </div>
          {selectedRun && <div className="m5-muted m5-run-summary" role="group" aria-label="選択Runの保存範囲">
            <span>Run {selectedRun.id}：{selectedRun.observation_count.toLocaleString()}件</span>
            <span>保存範囲JST</span>
            <span>{m5DateTime(metadata?.range.first).replace("T", " ") || "未収集"}</span>
            <span>～ {m5DateTime(metadata?.range.last).replace("T", " ") || "未収集"}</span>
          </div>}
          <form id="m5-search-form" onSubmit={(event) => { event.preventDefault(); search(); }}>
            <div className="m5-search-fields">
              <label>通貨<select aria-label="M5通貨" value={draft.symbol} onChange={(event) => editDraft({ symbol: event.target.value })}>
                <option value="">すべての通貨</option>{metadata?.symbols.map((symbol) => <option key={symbol} value={symbol}>{symbol}</option>)}
              </select></label>
              <label>開始JST（含む）<input type="datetime-local" aria-label="M5開始JST" step={300} value={draft.from} onChange={(event) => editDraft({ from: event.target.value })} /></label>
              <label>終了JST（含まない）<input type="datetime-local" aria-label="M5終了JST" step={300} value={draft.to} onChange={(event) => editDraft({ to: event.target.value })} /></label>
              <label>JST時刻<select aria-label="M5 JST時刻" value={draft.jstTime} onChange={(event) => editDraft({ jstTime: event.target.value })}>
                <option value="">すべての時刻</option>{M5_JST_TIMES.map((time) => <option key={time}>{time}</option>)}
              </select></label>
            </div>
            <div className="m5-actions m5-search-actions">
              <button className="primary-button" type="submit" disabled={!available || applied.runId === null || loading}>検索</button>
              <button className="secondary-button" type="button" disabled={!metadata?.range.last || loading} onClick={() => {
                dirtyDraft.current = false; void load({ ...appliedRef.current, page: 1 }, "latest");
              }}>最新24時間</button>
            </div>
            <p className="m5-muted m5-range-help">{applied.followLatest ? "最新24時間を追従中" : "固定期間"}<br />5分刻み・終了時刻は含まない</p>
          </form>
          {validation && <p role="alert" className="m5-error">{validation}</p>}
        </div>
      </aside>
      <div className="viewer-results-column">
        <div className="results-panel m5-panel m5-results-panel">
          <div className="m5-results-heading">
            <div className="m5-result-summary">
              <strong>{result?.total.toLocaleString() ?? "0"}件</strong>
              <AppliedConditionSummary hasUnappliedChanges={dirtyDraft.current}
              summary={displayedSearch ? `表示中：${displayedSearch.sourceMode} / Run ${displayedSearch.runId} / ${displayedSearch.from.replace("T", " ")} ≤ JST < ${displayedSearch.to.replace("T", " ")} / 通貨 ${displayedSearch.symbol || "すべて"} / JST時刻 ${displayedSearch.jstTime || "すべて"} / ${displayedSearch.sort === "anchor_jst_time" ? "日時" : "通貨"}${displayedSearch.order === "asc" ? "昇順" : "降順"}` : "検索結果なし"} />
              {metadata?.range.last && <span className="m5-latest-observation"
                title="選択Runの最新M5開始JSTです。稼働・収集完了を示すものではありません。">
                最新観測JST：{m5DateTime(metadata.range.last).replace("T", " ")}
              </span>}
            </div>
            {dirtyDraft.current && <p className="m5-notice" role="status">未適用の変更があります。「検索」で反映してください。</p>}
            {latestRun && latestRun.id !== applied.runId && <p className="m5-notice">観測のある最新Runは {latestRun.id} です。選択Runは自動で切り替えません。</p>}
            {applied.sourceMode === "TESTER" && !runs.length && hasLive && <p className="m5-notice">TESTERのRunはありません。LIVEのRunはあります（実行モードで切替）。</p>}
            {notice && <p role="status" className="m5-notice">{notice}</p>}
            {newerOutsideRange && <p className="m5-notice" role="status">選択範囲より新しいM5観測があります。「最新24時間」で表示できます。現在の期間・ページは維持しています。</p>}
            {error && <p role="alert" className="m5-error">更新失敗：{error}{result ? "（前回成功時のデータを表示中）" : ""}</p>}
            {metadata && !available && <p role="status">M5観測は利用できません：{metadata.reason || metadata.status}</p>}
            {available && (!applied.runId || !metadata?.range.last) && <p role="status">選択モード／Runは未収集です。保存済み観測が追加されると期間を選択できます。</p>}
          </div>
          <M5ObservationTable items={result?.items || []} databaseKey={databaseKey.current} loading={loading}
            sort={applied.sort} order={applied.order} styleNonce={styleNonce} onSort={sortRows} onOpenDetail={openDetail}
            toolbarStart={<div className="m5-refresh-toolbar" title={refreshStatus}>
            {applied.sourceMode === "LIVE" ? <RefreshControls intervalSeconds={intervalSeconds} statusText="LIVE"
              lastCheckedText={lastChecked ? `最終取得成功：${lastChecked}` : "未取得"} busy={loading}
              onIntervalChange={(value) => { setIntervalSeconds(value); writeM5Preference(M5_REFRESH_KEY, value); }}
              onRefresh={() => void load(appliedRef.current, "refresh")} />
              : <div className="m5-actions"><button className="secondary-button" type="button" disabled={loading} onClick={() => void load(appliedRef.current, "refresh")}>{loading ? "更新中…" : "今すぐ更新"}</button>
                <small className="m5-muted">{refreshStatus} / 最終取得成功：{lastChecked || "未取得"}</small></div>}
            </div>} />
          <div className="m5-pagination-footer">
            <label className="m5-page-size">ページ件数 <select aria-label="M5ページ件数" value={applied.pageSize} disabled={loading} onChange={(event) => {
              dirtyDraft.current = false; void load({ ...appliedRef.current, pageSize: Number(event.target.value) as 50 | 100 | 200, page: 1 }, "search");
            }}><option value={50}>50</option><option value={100}>100</option><option value={200}>200</option></select></label>
            <Pagination page={result?.page || applied.page} pageCount={result?.total_pages || 0} showPageInput disabled={loading || !result}
              onPage={(page) => { dirtyDraft.current = false; void load({ ...appliedRef.current, page, followLatest: false }, "search"); }} />
          </div>
        </div>
      </div>
    </div>
    <M5ObservationDetailDrawer observationId={selectedId} databaseKey={databaseKey.current} databaseName={metadata?.database?.name}
      active={active} styleNonce={styleNonce} onNavigate={setSelectedId} onClose={() => {
        setSelectedId(null); if (detailTrigger.current?.isConnected) detailTrigger.current.focus();
      }} />
  </section>;
}
