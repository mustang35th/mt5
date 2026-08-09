import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "./api/client";
import type {
  AlertsResponse,
  AlertSort,
  HealthResponse,
  OptionsResponse,
  RunItem,
  RunsResponse,
  SearchState,
  SourceMode,
  SummaryResponse,
} from "./api/types";
import { AlertDetailDrawer } from "./components/AlertDetailDrawer";
import { AlertTable } from "./components/AlertTable";
import { FilterPanel } from "./components/FilterPanel";
import { Pagination } from "./components/Pagination";
import { RefreshControls } from "./components/RefreshControls";
import { SummaryCards } from "./components/SummaryCards";
import { formatInteger } from "./lib/format";
import {
  DEFAULT_REFRESH_INTERVAL_SECONDS,
  readRefreshInterval,
  type RefreshIntervalSeconds,
  writeRefreshInterval,
} from "./lib/refreshSettings";
import { buildSearchParams, DEFAULT_SEARCH_STATE, readSearchState, replaceSearchUrl } from "./lib/searchState";

const EMPTY_OPTIONS: OptionsResponse = {
  symbols: [],
  time_frames: [],
  strategies: [],
  ranks: [],
  entry_results: [],
};

interface AppProps {
  styleNonce?: string;
}

type ResultRequestMode = "foreground" | "background" | "manual";

interface ResultRequest {
  generation: number;
  mode: ResultRequestMode;
}

function initialRefreshInterval(): RefreshIntervalSeconds {
  try {
    return readRefreshInterval(window.localStorage);
  } catch {
    return DEFAULT_REFRESH_INTERVAL_SECONDS;
  }
}

function formatCheckedTime(fromDate: Date | null): string {
  if (fromDate === null) return "一覧最終確認 —";
  return `一覧最終確認 ${fromDate.toLocaleTimeString("ja-JP", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  })}`;
}

function runSourceMode(run: RunItem | undefined): Exclude<SourceMode, "all"> | null {
  const sourceMode = run?.source_mode.toUpperCase();
  if (sourceMode === "LIVE" || sourceMode === "TESTER") return sourceMode;
  return null;
}

export default function App({ styleNonce }: AppProps) {
  const initialSearch = useMemo(() => readSearchState(window.location.search), []);
  const hasInitialRunParameter = useMemo(
    () => new URLSearchParams(window.location.search).has("runId"),
    [],
  );
  const hasInitialSourceModeParameter = useMemo(
    () => new URLSearchParams(window.location.search).has("sourceMode"),
    [],
  );
  const [draft, setDraft] = useState<SearchState>(initialSearch);
  const [applied, setApplied] = useState<SearchState>(initialSearch);
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [runs, setRuns] = useState<RunsResponse>({ items: [], count: 0 });
  const [options, setOptions] = useState<OptionsResponse>(EMPTY_OPTIONS);
  const [alerts, setAlerts] = useState<AlertsResponse | null>(null);
  const [summary, setSummary] = useState<SummaryResponse | null>(null);
  const [ready, setReady] = useState(false);
  const [loading, setLoading] = useState(false);
  const [fatalError, setFatalError] = useState("");
  const [loadError, setLoadError] = useState("");
  const [refreshIntervalSeconds, setRefreshIntervalSeconds] = useState(initialRefreshInterval);
  const [resultRequest, setResultRequest] = useState<ResultRequest>({
    generation: 0,
    mode: "foreground",
  });
  const [refreshing, setRefreshing] = useState(false);
  const [lastCheckedAt, setLastCheckedAt] = useState<Date | null>(null);
  const [pendingNewAlertCount, setPendingNewAlertCount] = useState(0);
  const [highlightedAlertIds, setHighlightedAlertIds] = useState<ReadonlySet<number>>(
    () => new Set<number>(),
  );
  const [pageVisible, setPageVisible] = useState(
    () => document.visibilityState !== "hidden",
  );
  const [selectedAlertId, setSelectedAlertId] = useState<number | null>(null);
  const detailTriggerRef = useRef<HTMLButtonElement | null>(null);
  const activeResultControllerRef = useRef<AbortController | null>(null);
  const refreshQueuedRef = useRef(false);
  const visibilityRefreshPendingRef = useRef(false);
  const alertsRef = useRef<AlertsResponse | null>(null);
  const highlightTimerRef = useRef<number | null>(null);

  useEffect(() => {
    let disposed = false;
    const controller = new AbortController();
    Promise.all([api.health(controller.signal), api.runs(controller.signal), api.options(controller.signal)])
      .then(([healthValue, runsValue, optionsValue]) => {
        if (disposed || controller.signal.aborted) return;
        const requestedRun = initialSearch.runId === null
          ? undefined
          : runsValue.items.find((run) => run.id === initialSearch.runId);
        let sourceMode = initialSearch.sourceMode;
        if (hasInitialRunParameter && !hasInitialSourceModeParameter) {
          sourceMode = runSourceMode(requestedRun) || sourceMode;
        }
        const requestedRunSourceMode = runSourceMode(requestedRun);
        const requestedRunMatchesMode = requestedRun !== undefined
          && requestedRunSourceMode !== null
          && (sourceMode === "all" || requestedRunSourceMode === sourceMode);
        const resolvedSearch = {
          ...initialSearch,
          sourceMode,
          runId: hasInitialRunParameter && requestedRunMatchesMode ? requestedRun.id : null,
        };
        setHealth(healthValue);
        setRuns(runsValue);
        setOptions(optionsValue);
        setDraft(resolvedSearch);
        setApplied(resolvedSearch);
        replaceSearchUrl(resolvedSearch);
        setReady(true);
      })
      .catch((error: unknown) => {
        if (disposed || controller.signal.aborted) return;
        if (error instanceof DOMException && error.name === "AbortError") return;
        setFatalError(error instanceof Error ? error.message : "起動できませんでした");
      });
    return () => {
      disposed = true;
      controller.abort();
    };
  }, [hasInitialRunParameter, hasInitialSourceModeParameter, initialSearch]);

  useEffect(() => {
    if (!ready) return;
    refreshQueuedRef.current = false;
    activeResultControllerRef.current?.abort();
    const controller = new AbortController();
    const requestMode = resultRequest.mode;
    activeResultControllerRef.current = controller;
    if (requestMode === "foreground") {
      setLoading(true);
      setRefreshing(false);
    } else {
      setLoading(false);
      setRefreshing(true);
    }
    setLoadError("");
    Promise.all([api.alerts(applied, controller.signal), api.summary(applied, controller.signal)])
      .then(([alertValue, summaryValue]) => {
        if (activeResultControllerRef.current !== controller || controller.signal.aborted) return;
        const previousAlerts = alertsRef.current;
        const isLatestView = applied.page === 1
          && applied.sort === "jst_time"
          && applied.order === "desc";
        if (requestMode === "background" && previousAlerts !== null && !isLatestView) {
          setPendingNewAlertCount(Math.max(0, alertValue.total - previousAlerts.total));
          setLastCheckedAt(new Date());
          return;
        }

        let highlightedIds = new Set<number>();
        if (requestMode !== "foreground" && previousAlerts !== null && isLatestView) {
          const previousIds = new Set(previousAlerts.items.map((item) => item.id));
          highlightedIds = new Set(
            alertValue.items.filter((item) => !previousIds.has(item.id)).map((item) => item.id),
          );
        }
        if (highlightTimerRef.current !== null) {
          window.clearTimeout(highlightTimerRef.current);
          highlightTimerRef.current = null;
        }
        setHighlightedAlertIds(highlightedIds);
        if (highlightedIds.size > 0) {
          highlightTimerRef.current = window.setTimeout(() => {
            setHighlightedAlertIds(new Set<number>());
            highlightTimerRef.current = null;
          }, 8000);
        }

        alertsRef.current = alertValue;
        setAlerts(alertValue);
        setSummary(summaryValue);
        setPendingNewAlertCount(0);
        setLastCheckedAt(new Date());
        if (alertValue.page !== applied.page) {
          const corrected = { ...applied, page: alertValue.page };
          setResultRequest((current) => ({
            generation: current.generation + 1,
            mode: "foreground",
          }));
          setApplied(corrected);
          setDraft((current) => ({ ...current, page: alertValue.page }));
          replaceSearchUrl(corrected);
        }
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        if (activeResultControllerRef.current !== controller || controller.signal.aborted) return;
        controller.abort();
        setLoadError(error instanceof Error ? error.message : "読み込みに失敗しました");
      })
      .finally(() => {
        if (activeResultControllerRef.current !== controller) return;
        activeResultControllerRef.current = null;
        setLoading(false);
        setRefreshing(false);
        const refreshAfterVisibility = visibilityRefreshPendingRef.current
          && document.visibilityState !== "hidden";
        visibilityRefreshPendingRef.current = false;
        if (refreshAfterVisibility) {
          refreshQueuedRef.current = true;
          setResultRequest((current) => ({
            generation: current.generation + 1,
            mode: "background",
          }));
        }
      });
    return () => {
      controller.abort();
      if (activeResultControllerRef.current === controller) {
        activeResultControllerRef.current = null;
      }
    };
  }, [applied, ready, resultRequest]);

  const requestRefresh = useCallback((mode: Exclude<ResultRequestMode, "foreground">) => {
    if (!ready || activeResultControllerRef.current !== null || refreshQueuedRef.current) {
      return false;
    }
    refreshQueuedRef.current = true;
    setResultRequest((current) => ({
      generation: current.generation + 1,
      mode,
    }));
    return true;
  }, [ready]);

  useEffect(() => {
    let timerId: number | null = null;
    let disposed = false;
    const autoRefreshEnabled = ready
      && applied.sourceMode === "LIVE"
      && refreshIntervalSeconds > 0;

    function clearTimer() {
      if (timerId === null) return;
      window.clearTimeout(timerId);
      timerId = null;
    }

    function scheduleTimer() {
      clearTimer();
      if (disposed || !autoRefreshEnabled || document.visibilityState === "hidden") return;
      timerId = window.setTimeout(() => {
        timerId = null;
        if (disposed || !autoRefreshEnabled || document.visibilityState === "hidden") return;
        requestRefresh("background");
        scheduleTimer();
      }, refreshIntervalSeconds * 1000);
    }

    function handleVisibilityChange() {
      const visible = document.visibilityState !== "hidden";
      setPageVisible(visible);
      clearTimer();
      if (!visible || !autoRefreshEnabled) {
        visibilityRefreshPendingRef.current = false;
        return;
      }
      const refreshStarted = requestRefresh("background");
      if (!refreshStarted && activeResultControllerRef.current !== null) {
        visibilityRefreshPendingRef.current = true;
      }
      scheduleTimer();
    }

    setPageVisible(document.visibilityState !== "hidden");
    document.addEventListener("visibilitychange", handleVisibilityChange);
    scheduleTimer();
    return () => {
      disposed = true;
      visibilityRefreshPendingRef.current = false;
      clearTimer();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [applied, ready, refreshIntervalSeconds, requestRefresh]);

  useEffect(() => () => {
    activeResultControllerRef.current?.abort();
    if (highlightTimerRef.current !== null) window.clearTimeout(highlightTimerRef.current);
  }, []);

  const commitSearch = useCallback((value: SearchState) => {
    refreshQueuedRef.current = false;
    visibilityRefreshPendingRef.current = false;
    alertsRef.current = null;
    setResultRequest((current) => ({
      generation: current.generation + 1,
      mode: "foreground",
    }));
    setPendingNewAlertCount(0);
    setHighlightedAlertIds(new Set<number>());
    setDraft(value);
    setApplied(value);
    replaceSearchUrl(value);
  }, []);

  function submitSearch() {
    commitSearch({ ...draft, page: 1 });
  }

  function resetSearch() {
    commitSearch(DEFAULT_SEARCH_STATE);
  }

  const changeSort = useCallback((sort: AlertSort) => {
    const order = draft.sort === sort && draft.order === "desc" ? "asc" : "desc";
    commitSearch({ ...draft, sort, order, page: 1 });
  }, [commitSearch, draft]);

  function changePage(page: number) {
    commitSearch({ ...draft, page });
  }

  function exportCsv() {
    const params = buildSearchParams(draft, false, true);
    window.location.assign(`/api/export.csv?${params}`);
  }

  const changeRefreshInterval = useCallback((intervalSeconds: RefreshIntervalSeconds) => {
    setRefreshIntervalSeconds(intervalSeconds);
    try {
      writeRefreshInterval(window.localStorage, intervalSeconds);
    } catch {
      // Continue with the in-memory setting when storage access is unavailable.
    }
  }, []);

  const showLatestAlerts = useCallback(() => {
    commitSearch({ ...applied, page: 1, sort: "jst_time", order: "desc" });
  }, [applied, commitSearch]);

  const openDetail = useCallback((alertId: number, fromTrigger: HTMLButtonElement) => {
    detailTriggerRef.current = fromTrigger;
    setSelectedAlertId(alertId);
  }, []);

  const closeDetail = useCallback(() => {
    const trigger = detailTriggerRef.current;
    setSelectedAlertId(null);
    window.requestAnimationFrame(() => {
      if (trigger?.isConnected && !trigger.disabled) trigger.focus();
    });
  }, []);

  const total = alerts?.total || 0;
  const page = alerts?.page || applied.page;
  const pageSize = alerts?.page_size || applied.pageSize;
  const first = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);
  let resultStatus = `${formatInteger(total)}件中 ${formatInteger(first)}–${formatInteger(last)}件`;
  if (loading) resultStatus = "読み込み中…";
  if (loadError) resultStatus = "読み込み失敗・以前の結果を表示中";
  if (fatalError) resultStatus = "起動できませんでした";

  let refreshStatus = `${refreshIntervalSeconds}秒ごとに自動更新`;
  if (refreshIntervalSeconds === 0) refreshStatus = "自動更新 OFF";
  else if (applied.sourceMode !== "LIVE") refreshStatus = "LIVE表示中のみ自動更新";
  else if (!pageVisible) refreshStatus = "タブ非表示中は停止";
  else if (refreshing) refreshStatus = "一覧を更新中…";

  const sourceModeLabel = applied.sourceMode === "all" ? "全モード" : applied.sourceMode;
  let connectionText = "DB確認中";
  if (fatalError) connectionText = "DB接続エラー";
  else if (health && summary) {
    connectionText = `接続済み・${sourceModeLabel} ${formatInteger(summary.total_count)}件`;
  } else if (health) connectionText = `接続済み・${sourceModeLabel}確認中`;

  return (
    <>
      <header className="app-header">
        <div className="app-brand">
          <p className="eyebrow">ELLIOTT SIGNAL ARCHIVE</p>
          <h1>ZigZagElliot Alert Viewer</h1>
          <p className="subtitle">アラート時点の波動構造を、Run単位で検索・比較します。</p>
        </div>
        <div className="header-actions">
          <a className="secondary-button app-link" href="/legacy/">従来画面</a>
          <div className={`connection${fatalError ? " error" : health ? " ready" : ""}`} role="status" aria-live="polite">
            <span className="status-dot" />
            <span>{connectionText}</span>
          </div>
        </div>
      </header>

      <main>
        <FilterPanel
          value={draft}
          appliedValue={applied}
          runs={runs.items}
          options={options}
          busy={loading}
          onChange={setDraft}
          onSubmit={submitSearch}
          onReset={resetSearch}
          onExport={exportCsv}
        />
        <SummaryCards summary={summary} />
        <section className="results-panel" aria-labelledby="reactResultsTitle">
          <div className="section-heading results-heading">
            <div className="results-title-line">
              <p className="eyebrow">SNAPSHOTS</p>
              <h2 id="reactResultsTitle">アラート一覧</h2>
              <p className="result-status" role="status" aria-live="polite">{resultStatus}</p>
            </div>
            <div className="results-tools">
              <RefreshControls
                intervalSeconds={refreshIntervalSeconds}
                statusText={refreshStatus}
                lastCheckedText={formatCheckedTime(lastCheckedAt)}
                busy={loading || refreshing}
                onIntervalChange={changeRefreshInterval}
                onRefresh={() => requestRefresh("manual")}
              />
            </div>
          </div>
          {alerts ? (
            <>
              {pendingNewAlertCount > 0 && (
                <div className="new-alert-banner" role="status" aria-live="polite">
                  <span>新しいアラートが{formatInteger(pendingNewAlertCount)}件あります。</span>
                  <button className="secondary-button" type="button" onClick={showLatestAlerts}>
                    最新を表示
                  </button>
                </div>
              )}
              <AlertTable
                items={alerts.items}
                loading={loading || refreshing}
                highlightedIds={highlightedAlertIds}
                sort={applied.sort}
                order={applied.order}
                styleNonce={styleNonce}
                onSort={changeSort}
                onOpenDetail={openDetail}
              />
              <Pagination page={page} pageCount={alerts.page_count} onPage={changePage} />
            </>
          ) : (
            <p className="loading-message">{fatalError || loadError || "一覧を読み込んでいます…"}</p>
          )}
        </section>
      </main>

      {(fatalError || loadError) && (
        <div className="toast" role="alert" aria-live="assertive">
          {fatalError || loadError}
        </div>
      )}
      <AlertDetailDrawer alertId={selectedAlertId} onClose={closeDetail} />
    </>
  );
}
