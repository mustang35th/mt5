import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "./api/client";
import type {
  AlertsResponse,
  AlertSort,
  HealthResponse,
  OptionsResponse,
  RunsResponse,
  SearchState,
  SummaryResponse,
} from "./api/types";
import { AlertDetailDrawer } from "./components/AlertDetailDrawer";
import { AlertTable } from "./components/AlertTable";
import { FilterPanel } from "./components/FilterPanel";
import { Pagination } from "./components/Pagination";
import { SummaryCards } from "./components/SummaryCards";
import { formatInteger } from "./lib/format";
import { buildSearchParams, DEFAULT_SEARCH_STATE, readSearchState, replaceSearchUrl } from "./lib/searchState";

const EMPTY_OPTIONS: OptionsResponse = {
  symbols: [],
  time_frames: [],
  strategies: [],
  ranks: [],
  entry_results: [],
};

export default function App() {
  const initialSearch = useMemo(() => readSearchState(window.location.search), []);
  const hasInitialRunParameter = useMemo(
    () => new URLSearchParams(window.location.search).has("runId"),
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
  const [selectedAlertId, setSelectedAlertId] = useState<number | null>(null);
  const detailTriggerRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    Promise.all([api.health(controller.signal), api.runs(controller.signal), api.options(controller.signal)])
      .then(([healthValue, runsValue, optionsValue]) => {
        const latestWithAlerts = runsValue.items.find((run) => Number(run.alert_count) > 0);
        const requestedRunExists = initialSearch.runId !== null
          && runsValue.items.some((run) => run.id === initialSearch.runId);
        const resolvedSearch = {
          ...initialSearch,
          runId: hasInitialRunParameter
            ? requestedRunExists ? initialSearch.runId : null
            : latestWithAlerts?.id ?? null,
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
        if (error instanceof DOMException && error.name === "AbortError") return;
        setFatalError(error instanceof Error ? error.message : "起動できませんでした");
      });
    return () => controller.abort();
  }, [hasInitialRunParameter, initialSearch]);

  useEffect(() => {
    if (!ready) return;
    const controller = new AbortController();
    setLoading(true);
    setLoadError("");
    Promise.all([api.alerts(applied, controller.signal), api.summary(applied, controller.signal)])
      .then(([alertValue, summaryValue]) => {
        setAlerts(alertValue);
        setSummary(summaryValue);
        if (alertValue.page !== applied.page) {
          const corrected = { ...applied, page: alertValue.page };
          setApplied(corrected);
          setDraft((current) => ({ ...current, page: alertValue.page }));
          replaceSearchUrl(corrected);
        }
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setLoadError(error instanceof Error ? error.message : "読み込みに失敗しました");
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [applied, ready]);

  const commitSearch = useCallback((value: SearchState) => {
    setDraft(value);
    setApplied(value);
    replaceSearchUrl(value);
  }, []);

  function submitSearch() {
    commitSearch({ ...draft, page: 1 });
  }

  function resetSearch() {
    const latestWithAlerts = runs.items.find((run) => Number(run.alert_count) > 0);
    commitSearch({ ...DEFAULT_SEARCH_STATE, runId: latestWithAlerts?.id ?? null });
  }

  function changeSort(sort: AlertSort) {
    const order = draft.sort === sort && draft.order === "desc" ? "asc" : "desc";
    commitSearch({ ...draft, sort, order, page: 1 });
  }

  function changePage(page: number) {
    commitSearch({ ...draft, page });
  }

  function exportCsv() {
    const params = buildSearchParams(draft, false, true);
    window.location.assign(`/api/export.csv?${params}`);
  }

  function openDetail(alertId: number, fromTrigger: HTMLButtonElement) {
    detailTriggerRef.current = fromTrigger;
    setSelectedAlertId(alertId);
  }

  function closeDetail() {
    const trigger = detailTriggerRef.current;
    setSelectedAlertId(null);
    window.requestAnimationFrame(() => {
      if (trigger?.isConnected && !trigger.disabled) trigger.focus();
    });
  }

  const total = alerts?.total || 0;
  const page = alerts?.page || applied.page;
  const pageSize = alerts?.page_size || applied.pageSize;
  const first = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);
  let resultStatus = `${formatInteger(total)}件中 ${formatInteger(first)}–${formatInteger(last)}件`;
  if (loading) resultStatus = "読み込み中…";
  if (loadError) resultStatus = "読み込み失敗・以前の結果を表示中";
  if (fatalError) resultStatus = "起動できませんでした";

  return (
    <>
      <header className="app-header">
        <div>
          <p className="eyebrow">ELLIOTT SIGNAL ARCHIVE</p>
          <h1>ZigZagElliot Alert Viewer</h1>
          <p className="subtitle">アラート時点の波動構造を、Run単位で検索・比較します。</p>
        </div>
        <div className="header-actions">
          <a className="secondary-button app-link" href="/legacy/">従来画面</a>
          <div className={`connection${fatalError ? " error" : health ? " ready" : ""}`} role="status" aria-live="polite">
            <span className="status-dot" />
            <span>{fatalError ? "DB接続エラー" : health ? `接続済み・${formatInteger(health.alert_count)}件` : "DB確認中"}</span>
          </div>
        </div>
      </header>

      <main>
        <FilterPanel
          value={draft}
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
            <div>
              <p className="eyebrow">SNAPSHOTS</p>
              <h2 id="reactResultsTitle">アラート一覧</h2>
            </div>
            <p className="result-status" role="status" aria-live="polite">{resultStatus}</p>
          </div>
          {alerts ? (
            <>
              <AlertTable
                items={alerts.items}
                sort={applied.sort}
                order={applied.order}
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
