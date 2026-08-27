import Box from "@mui/material/Box";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "../api/client";
import type {
  ObservationOptionsResponse,
  ObservationsResponse,
  ObservationSearchState,
  ObservationSort,
  ObservationSummaryResponse,
  RunItem,
} from "../api/types";
import { formatInteger } from "../lib/format";
import {
  DEFAULT_OBSERVATION_SEARCH_STATE,
  readObservationSearchState,
  replaceObservationSearchUrl,
} from "../lib/observationSearchState";
import type { RefreshIntervalSeconds } from "../lib/refreshSettings";
import { AppliedConditionSummary } from "./AppliedConditionSummary";
import { FilterVisibilityToggle } from "./FilterVisibilityToggle";
import {
  defaultObservationAnalysisProfile,
  hasObservationUnappliedChanges,
  ObservationFilterPanel,
  observationProfileSearchFields,
  observationProfilesForMode,
  observationFilterSummary,
} from "./ObservationFilterPanel";
import { ObservationDetailDrawer } from "./ObservationDetailDrawer";
import { ObservationTable } from "./ObservationTable";
import { Pagination } from "./Pagination";
import { RefreshControls } from "./RefreshControls";

const EMPTY_OPTIONS: ObservationOptionsResponse = {
  available: false,
  symbols: [],
  source_modes: [],
  analysis_versions: [],
};

interface H1ObservationViewProps {
  active: boolean;
  ready: boolean;
  runs: RunItem[];
  refreshIntervalSeconds: RefreshIntervalSeconds;
  styleNonce?: string;
  onRefreshIntervalChange: (intervalSeconds: RefreshIntervalSeconds) => void;
}

function checkedTime(fromDate: Date | null): string {
  if (fromDate === null) return "H1推移 最終確認 —";
  return `H1推移 最終確認 ${fromDate.toLocaleTimeString("ja-JP", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  })}`;
}

function SummaryStrip({
  summary,
  grouped,
  compact = false,
}: {
  summary: ObservationSummaryResponse | null;
  grouped: boolean;
  compact?: boolean;
}) {
  const values = grouped
    ? [
      ["シグナル数", summary?.total_count],
      ["対象H1", summary?.matched_observation_count],
      ["BUY", summary?.signal_buy_count],
      ["SELL", summary?.signal_sell_count],
    ] as const
    : [
      ["観測数", summary?.total_count],
      ["Run数", summary?.run_count],
      ["通貨数", summary?.symbol_count],
    ] as const;
  return (
    <Box className={`observation-summary-strip${compact ? " compact" : ""}`} sx={{
      display: "grid",
      gridTemplateColumns: `repeat(${values.length}, minmax(0, 1fr))`,
      gap: 1,
      m: "10px 0",
      "@media (min-width: 1280px)": {
        mt: 0,
      },
    }}>
      {values.map(([label, value]) => (
        <Paper
          className="observation-summary-metric"
          component="div"
          elevation={0}
          key={label}
          sx={{
            display: "flex",
            minWidth: 0,
            px: 1.5,
            py: 0.75,
            alignItems: "baseline",
            justifyContent: "space-between",
            gap: 1,
            border: 1,
            borderLeft: 3,
            borderColor: "divider",
            borderLeftColor: "primary.main",
            bgcolor: "background.paper",
          }}
        >
          <Typography className="observation-summary-label" sx={{ color: "text.secondary", fontSize: "0.7rem", fontWeight: 700 }}>
            {label}
          </Typography>
          <Typography className="observation-summary-value" sx={{ m: 0, fontSize: "1rem", fontWeight: 800 }}>
            {formatInteger(value)}
          </Typography>
        </Paper>
      ))}
    </Box>
  );
}

export function H1ObservationView({
  active,
  ready,
  runs,
  refreshIntervalSeconds,
  styleNonce,
  onRefreshIntervalChange,
}: H1ObservationViewProps) {
  const initialSearch = useMemo(
    () => readObservationSearchState(window.location.search),
    [],
  );
  const initialHasSourceMode = useMemo(() => {
    const params = new URLSearchParams(window.location.search);
    return params.has("sourceMode");
  }, []);
  const initialHasAnalysisInputHash = useMemo(() => {
    const params = new URLSearchParams(window.location.search);
    return params.has("analysisInputHash");
  }, []);
  const [draft, setDraft] = useState<ObservationSearchState>(initialSearch);
  const [applied, setApplied] = useState<ObservationSearchState>(initialSearch);
  const [filterExpanded, setFilterExpanded] = useState(true);
  const [options, setOptions] = useState<ObservationOptionsResponse>(EMPTY_OPTIONS);
  const [observations, setObservations] = useState<ObservationsResponse | null>(null);
  const [summary, setSummary] = useState<ObservationSummaryResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [lastCheckedAt, setLastCheckedAt] = useState<Date | null>(null);
  const [requestGeneration, setRequestGeneration] = useState(0);
  const [pageVisible, setPageVisible] = useState(
    () => document.visibilityState !== "hidden",
  );
  const [selectedObservationId, setSelectedObservationId] = useState<number | null>(null);
  const [initialRunValidated, setInitialRunValidated] = useState(
    initialSearch.runId === null,
  );
  const [optionsResolved, setOptionsResolved] = useState(false);
  const [initialProfileValidated, setInitialProfileValidated] = useState(false);
  const activeControllerRef = useRef<AbortController | null>(null);
  const detailTriggerRef = useRef<HTMLButtonElement | null>(null);
  const requestModeRef = useRef<"foreground" | "background" | "manual">("foreground");
  const optionsLoadedRef = useRef(false);

  useEffect(() => {
    if (!active || !initialRunValidated || !initialProfileValidated) return;
    replaceObservationSearchUrl(applied);
  }, [active, applied, initialProfileValidated, initialRunValidated]);

  useEffect(() => {
    if (!active || !ready || initialRunValidated) return;
    const requestedRun = runs.find((run) => run.id === initialSearch.runId);
    const requestedMode = requestedRun?.source_mode.toUpperCase();
    const isRequestedModeValid = requestedMode === "TESTER" || requestedMode === "LIVE";
    const correctedMode = !initialHasSourceMode && isRequestedModeValid
      ? requestedMode
      : initialSearch.sourceMode;
    const requestedRunMatchesMode = requestedRun !== undefined
      && isRequestedModeValid
      && (correctedMode === "all" || requestedMode === correctedMode);
    const correctedRunId = requestedRunMatchesMode ? initialSearch.runId : null;
    setDraft((current) => ({ ...current, sourceMode: correctedMode, runId: correctedRunId }));
    setApplied((current) => ({ ...current, sourceMode: correctedMode, runId: correctedRunId }));
    setInitialRunValidated(true);
  }, [active, initialHasSourceMode, initialRunValidated, initialSearch, ready, runs]);

  useEffect(() => {
    if (!active || !ready || optionsLoadedRef.current) return;
    const controller = new AbortController();
    api.observationOptions(controller.signal)
      .then((value) => {
        if (controller.signal.aborted) return;
        optionsLoadedRef.current = true;
        setOptions(value);
        setOptionsResolved(true);
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        if (!controller.signal.aborted) {
          setLoadError(error instanceof Error ? error.message : "H1観測条件を読み込めませんでした");
        }
      });
    return () => controller.abort();
  }, [active, ready, requestGeneration]);

  useEffect(() => {
    if (!active || !ready || !initialRunValidated || !optionsResolved || initialProfileValidated) {
      return;
    }
    const selectedRun = applied.runId === null
      ? undefined
      : runs.find((run) => run.id === applied.runId);
    const profiles = observationProfilesForMode(options, applied.sourceMode);
    let selectedProfile = null;
    if (selectedRun?.analysis_input_hash) {
      selectedProfile = profiles.find((profile) => (
        profile.analysis_version === selectedRun.analysis_version
          && profile.analysis_input_hash === selectedRun.analysis_input_hash
          && profile.analysis_profile_kind === (
            selectedRun.analysis_profile_is_legacy ? "legacy" : "profile"
          )
      )) || null;
    } else if (initialHasAnalysisInputHash) {
      const requestedHash = initialSearch.analysisInputHash;
      const requestedProfiles = profiles.filter((profile) => (
        profile.analysis_input_hash === requestedHash
          && (!initialSearch.analysisVersion
            || profile.analysis_version === initialSearch.analysisVersion)
          && (!initialSearch.analysisProfileKind
            || profile.analysis_profile_kind === initialSearch.analysisProfileKind)
      ));
      if (!requestedHash) {
        selectedProfile = null;
      } else if (requestedProfiles.length === 1) {
        selectedProfile = requestedProfiles[0];
      } else {
        selectedProfile = defaultObservationAnalysisProfile(options, applied.sourceMode);
      }
    } else {
      selectedProfile = defaultObservationAnalysisProfile(options, applied.sourceMode);
    }
    const profileFields = selectedRun?.analysis_input_hash && selectedProfile === null
      ? {
        analysisVersion: selectedRun.analysis_version,
        analysisInputHash: selectedRun.analysis_input_hash,
        analysisProfileKind: selectedRun.analysis_profile_is_legacy
          ? "legacy" as const
          : "profile" as const,
      }
      : observationProfileSearchFields(selectedProfile);
    setDraft((current) => ({ ...current, ...profileFields }));
    setApplied((current) => ({ ...current, ...profileFields }));
    setInitialProfileValidated(true);
  }, [
    active,
    applied.runId,
    applied.sourceMode,
    initialHasAnalysisInputHash,
    initialProfileValidated,
    initialRunValidated,
    initialSearch.analysisInputHash,
    initialSearch.analysisProfileKind,
    initialSearch.analysisVersion,
    options,
    optionsResolved,
    ready,
    runs,
  ]);

  useEffect(() => {
    if (!active || !ready || !initialRunValidated || !initialProfileValidated) return;
    activeControllerRef.current?.abort();
    const controller = new AbortController();
    const requestMode = requestModeRef.current;
    activeControllerRef.current = controller;
    if (requestMode === "foreground") setLoading(true);
    else setRefreshing(true);
    setLoadError("");

    Promise.all([
      api.observations(applied, controller.signal),
      api.observationSummary(applied, controller.signal),
    ])
      .then(([observationsValue, summaryValue]) => {
        if (controller.signal.aborted || activeControllerRef.current !== controller) return;
        setObservations(observationsValue);
        setSummary(summaryValue);
        setLastCheckedAt(new Date());
        if (observationsValue.page !== applied.page) {
          const corrected = { ...applied, page: observationsValue.page };
          requestModeRef.current = "foreground";
          setDraft((current) => ({ ...current, page: corrected.page }));
          setApplied(corrected);
        }
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        if (controller.signal.aborted || activeControllerRef.current !== controller) return;
        controller.abort();
        setLoadError(error instanceof Error ? error.message : "H1推移を読み込めませんでした");
      })
      .finally(() => {
        if (activeControllerRef.current !== controller) return;
        activeControllerRef.current = null;
        setLoading(false);
        setRefreshing(false);
      });
    return () => {
      controller.abort();
      if (activeControllerRef.current === controller) activeControllerRef.current = null;
    };
  }, [active, applied, initialProfileValidated, initialRunValidated, ready, requestGeneration]);

  const requestRefresh = useCallback((mode: "background" | "manual") => {
    if (!active || !ready || activeControllerRef.current !== null) return false;
    requestModeRef.current = mode;
    setRequestGeneration((current) => current + 1);
    return true;
  }, [active, ready]);

  useEffect(() => {
    if (!active) return;
    let timerId: number | null = null;
    let disposed = false;
    const enabled = ready && applied.sourceMode === "LIVE" && refreshIntervalSeconds > 0;

    function clearTimer() {
      if (timerId !== null) window.clearTimeout(timerId);
      timerId = null;
    }

    function schedule() {
      clearTimer();
      if (disposed || !enabled || document.visibilityState === "hidden") return;
      timerId = window.setTimeout(() => {
        timerId = null;
        if (disposed) return;
        if (document.visibilityState !== "hidden") requestRefresh("background");
        schedule();
      }, refreshIntervalSeconds * 1000);
    }

    function visibilityChanged() {
      const visible = document.visibilityState !== "hidden";
      setPageVisible(visible);
      clearTimer();
      if (visible && enabled) {
        requestRefresh("background");
        schedule();
      }
    }

    setPageVisible(document.visibilityState !== "hidden");
    document.addEventListener("visibilitychange", visibilityChanged);
    schedule();
    return () => {
      disposed = true;
      clearTimer();
      document.removeEventListener("visibilitychange", visibilityChanged);
    };
  }, [active, applied, ready, refreshIntervalSeconds, requestRefresh]);

  useEffect(() => () => activeControllerRef.current?.abort(), []);

  const commitSearch = useCallback((value: ObservationSearchState) => {
    if (value.groupMode !== applied.groupMode) {
      detailTriggerRef.current = null;
      setSelectedObservationId(null);
      setObservations(null);
      setSummary(null);
    }
    requestModeRef.current = "foreground";
    setDraft(value);
    setApplied(value);
    setRequestGeneration((current) => current + 1);
  }, [applied.groupMode]);

  const changeSort = useCallback((sort: ObservationSort) => {
    const order = applied.sort === sort && applied.order === "desc" ? "asc" : "desc";
    commitSearch({ ...applied, sort, order, page: 1 });
  }, [applied, commitSearch]);

  const openDetail = useCallback((observationId: number, fromTrigger: HTMLButtonElement) => {
    detailTriggerRef.current = fromTrigger;
    setSelectedObservationId(observationId);
  }, []);

  const navigateDetail = useCallback((observationId: number) => {
    setSelectedObservationId(observationId);
  }, []);

  const closeDetail = useCallback(() => {
    const trigger = detailTriggerRef.current;
    setSelectedObservationId(null);
    window.requestAnimationFrame(() => {
      if (trigger?.isConnected && !trigger.disabled) trigger.focus();
    });
  }, []);

  useEffect(() => {
    if (active) return;
    detailTriggerRef.current = null;
    setSelectedObservationId(null);
  }, [active]);

  if (!active) return null;

  const total = observations?.total || 0;
  const page = observations?.page || applied.page;
  const pageSize = observations?.page_size || applied.pageSize;
  const grouped = applied.groupMode === "signal";
  const first = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);
  let resultStatus = `${formatInteger(total)}件中 ${formatInteger(first)}–${formatInteger(last)}件`;
  if (loading) resultStatus = "読み込み中…";
  if (loadError) resultStatus = "読み込み失敗・以前の結果を表示中";
  if (observations?.available === false) resultStatus = "H1観測DB 未利用";

  let refreshStatus = `${refreshIntervalSeconds}秒ごとに自動更新`;
  if (refreshIntervalSeconds === 0) refreshStatus = "自動更新 OFF";
  else if (applied.sourceMode !== "LIVE") refreshStatus = "LIVE表示中のみ自動更新";
  else if (!pageVisible) refreshStatus = "タブ非表示中は停止";
  else if (refreshing) refreshStatus = "H1推移を更新中…";

  return (
    <Box
      component="div"
      className="viewer-tab-panel"
      role="tabpanel"
      id="viewer-tabpanel-h1"
      aria-labelledby="viewer-tab-h1"
    >
      <div className="viewer-summary-bar">
        <FilterVisibilityToggle
          controls="observationFilterSidebar"
          expanded={filterExpanded}
          onExpandedChange={setFilterExpanded}
        />
        <AppliedConditionSummary
          summary={observationFilterSummary(applied)}
          hasUnappliedChanges={hasObservationUnappliedChanges(draft, applied)}
        />
        <SummaryStrip summary={summary} grouped={grouped} compact />
      </div>
      <div className={`viewer-workspace${filterExpanded ? "" : " filter-sidebar-collapsed"}`}>
        <aside
          id="observationFilterSidebar"
          className="viewer-filter-sidebar"
          aria-label="H1推移検索条件"
          hidden={!filterExpanded}
        >
          <ObservationFilterPanel
            value={draft}
            runs={runs}
            options={options}
            busy={loading}
            sidebar
            onChange={setDraft}
            onSubmit={() => commitSearch({ ...draft, page: 1 })}
            onReset={() => commitSearch({
              ...DEFAULT_OBSERVATION_SEARCH_STATE,
              ...observationProfileSearchFields(
                defaultObservationAnalysisProfile(options, "LIVE"),
              ),
            })}
          />
        </aside>
        <div className="viewer-results-column">
          <section className="results-panel" aria-labelledby="observationResultsTitle">
            <div className="section-heading results-heading">
              <div className="results-title-line">
                <p className="eyebrow">{grouped ? "H1 SIGNALS" : "H1 OBSERVATIONS"}</p>
                <h2 id="observationResultsTitle">
                  {grouped ? "連続H1シグナル" : "H1推移"}
                </h2>
                <p className="result-status" role="status" aria-live="polite">{resultStatus}</p>
              </div>
              <div className="results-tools">
                <RefreshControls
                  intervalSeconds={refreshIntervalSeconds}
                  statusText={refreshStatus}
                  lastCheckedText={checkedTime(lastCheckedAt)}
                  busy={loading || refreshing}
                  onIntervalChange={onRefreshIntervalChange}
                  onRefresh={() => requestRefresh("manual")}
                />
              </div>
            </div>
            {observations ? (
              <>
                <ObservationTable
                  items={observations.items}
                  available={observations.available}
                  grouped={grouped}
                  loading={loading || refreshing}
                  sort={applied.sort}
                  order={applied.order}
                  styleNonce={styleNonce}
                  onSort={changeSort}
                  onOpenDetail={openDetail}
                />
                <Pagination
                  page={page}
                  pageCount={observations.page_count}
                  onPage={(nextPage) => commitSearch({ ...applied, page: nextPage })}
                />
              </>
            ) : (
              <Typography className="loading-message">
                {loadError || "H1推移を読み込んでいます…"}
              </Typography>
            )}
          </section>
        </div>
      </div>
      {loadError && (
        <div className="toast" role="alert" aria-live="assertive">{loadError}</div>
      )}
      <ObservationDetailDrawer
        initialView="grid"
        observationId={selectedObservationId}
        onClose={closeDetail}
        onNavigate={navigateDetail}
        styleNonce={styleNonce}
      />
    </Box>
  );
}
