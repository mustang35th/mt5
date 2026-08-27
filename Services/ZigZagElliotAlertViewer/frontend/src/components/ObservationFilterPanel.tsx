import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Checkbox from "@mui/material/Checkbox";
import FormControl from "@mui/material/FormControl";
import InputLabel from "@mui/material/InputLabel";
import ListItemText from "@mui/material/ListItemText";
import MenuItem from "@mui/material/MenuItem";
import Paper from "@mui/material/Paper";
import Select, { type SelectChangeEvent } from "@mui/material/Select";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import useMediaQuery from "@mui/material/useMediaQuery";
import { useMemo, type FormEvent } from "react";
import type {
  GmoTargetFilter,
  ObservationAnalysisProfile,
  ObservationOptionsResponse,
  ObservationSearchState,
  ObservationSyncTimeFrame,
  RunItem,
  SourceMode,
} from "../api/types";
import {
  OBSERVATION_JST_TIMES,
  OBSERVATION_SYNC_TIME_FRAMES,
} from "../lib/observationSearchState";

interface ObservationFilterPanelProps {
  value: ObservationSearchState;
  runs: RunItem[];
  options: ObservationOptionsResponse;
  busy: boolean;
  sidebar?: boolean;
  onChange: (value: ObservationSearchState) => void;
  onSubmit: () => void;
  onReset: () => void;
}

function isRunVisible(run: RunItem, sourceMode: SourceMode): boolean {
  return sourceMode === "all" || run.source_mode.toUpperCase() === sourceMode;
}

function runLabel(run: RunItem): string {
  const symbols = run.observation_symbols || "観測なし";
  let range = "記録なし";
  if (run.last_observation_jst_time_text) {
    range = `JST ${run.first_observation_jst_time_text || "?"} – ${run.last_observation_jst_time_text}`;
  } else if (run.last_observation_time_text) {
    range = `Server ${run.first_observation_time_text || "?"} – ${run.last_observation_time_text}`;
  }
  return `${run.source_mode}｜Run ${run.id}｜${symbols}｜${run.observation_count || 0}件｜${range}`;
}

export function observationProfilesForMode(
  options: ObservationOptionsResponse,
  sourceMode: SourceMode,
): ObservationAnalysisProfile[] {
  return (options.analysis_profiles || []).filter((profile) => sourceMode === "all"
    || profile.source_modes.some((mode) => mode.toUpperCase() === sourceMode));
}

export function defaultObservationAnalysisInputHash(
  options: ObservationOptionsResponse,
  sourceMode: SourceMode,
): string {
  const defaults = options.default_analysis_input_hashes;
  if (defaults) {
    return defaults[sourceMode] || "";
  }
  return options.default_analysis_input_hash || "";
}

export function defaultObservationAnalysisProfile(
  options: ObservationOptionsResponse,
  sourceMode: SourceMode,
): ObservationAnalysisProfile | null {
  const completeDefaults = options.default_analysis_profiles;
  if (completeDefaults) return completeDefaults[sourceMode];
  const defaultHash = defaultObservationAnalysisInputHash(options, sourceMode);
  if (!defaultHash) return null;
  return observationProfilesForMode(options, sourceMode).find(
    (profile) => profile.analysis_input_hash === defaultHash,
  ) || null;
}

export function observationProfileMatchesSearch(
  profile: ObservationAnalysisProfile,
  value: ObservationSearchState,
): boolean {
  return profile.analysis_version === value.analysisVersion
    && profile.analysis_input_hash === value.analysisInputHash
    && profile.analysis_profile_kind === value.analysisProfileKind;
}

export function observationProfileSearchFields(profile: ObservationAnalysisProfile | null) {
  return {
    analysisVersion: profile?.analysis_version || "",
    analysisInputHash: profile?.analysis_input_hash || "",
    analysisProfileKind: profile?.analysis_profile_kind || "" as const,
  };
}

function profileLabel(profile: ObservationAnalysisProfile): string {
  const kind = profile.is_legacy ? "Legacy" : "Profile";
  const shortHash = profile.analysis_input_hash.slice(0, 12) || "hashなし";
  const last = profile.last_anchor_jst_time_text
    ? `最終JST ${profile.last_anchor_jst_time_text}`
    : "記録なし";
  return `${profile.analysis_version}｜${kind}｜${shortHash}｜${profile.observation_count}件｜${last}`;
}

function syncTimeFrameSummary(
  timeFrames: readonly ObservationSyncTimeFrame[],
  emptyLabel: string,
): string {
  if (timeFrames.length === 0) return emptyLabel;
  if (timeFrames.length <= 2) return timeFrames.join("・");
  return `${timeFrames.slice(0, 2).join("・")}＋${timeFrames.length - 2}`;
}

function sameSyncTimeFrames(
  first: readonly ObservationSyncTimeFrame[],
  second: readonly ObservationSyncTimeFrame[],
): boolean {
  const firstValues = new Set(first);
  const secondValues = new Set(second);
  return firstValues.size === secondValues.size
    && [...firstValues].every((timeFrame) => secondValues.has(timeFrame));
}

function gmoTargetSummary(gmoTarget: GmoTargetFilter): string {
  if (gmoTarget === "target") return "対象";
  if (gmoTarget === "excluded") return "対象外";
  return "すべて";
}

function fullAlignmentSummary(value: ObservationSearchState["fullAlignment"]): string {
  if (value === "FULL") return "方向問わず完全一致";
  if (value === "BUY") return "完全BUY";
  if (value === "SELL") return "完全SELL";
  return "指定なし";
}

function groupModeSummary(value: ObservationSearchState["groupMode"]): string {
  return value === "signal" ? "連続FULLを1シグナル" : "H1ごと";
}

export function observationFilterSummary(value: ObservationSearchState): string {
  const mode = value.sourceMode === "all" ? "LIVE＋TESTER" : value.sourceMode;
  const run = value.runId === null ? "全Run" : `Run ${value.runId}`;
  const symbol = value.symbol || "全通貨";
  const profile = value.analysisInputHash
    ? `${value.analysisProfileKind === "legacy" ? "Legacy" : "Profile"} `
      + `${value.analysisVersion}/${value.analysisInputHash.slice(0, 12)}`
    : "全Profile";
  const period = value.from || value.to
    ? `JST期間 ${value.from || "先頭"} – ${value.to || "末尾"}`
    : "JST全期間";
  const jstTime = value.jstTime ? `JST時刻 ${value.jstTime}` : "JST全時刻";
  const synchronization = value.syncTimeFrames.length > 0
    ? `上位足同期 ${value.syncTimeFrames.join("・")}`
    : "上位足同期なし";
  return `${mode} / ${run} / ${profile} / ${symbol} / ${period} / ${jstTime} / ${synchronization}`
    + ` / W1～H1＋EMA200 ${fullAlignmentSummary(value.fullAlignment)}`
    + ` / 表示 ${groupModeSummary(value.groupMode)}`
    + ` / GMO取引 ${gmoTargetSummary(value.gmoTarget)}`;
}

export function hasObservationUnappliedChanges(
  value: ObservationSearchState,
  appliedValue: ObservationSearchState,
): boolean {
  return value.sourceMode !== appliedValue.sourceMode
    || value.runId !== appliedValue.runId
    || value.analysisVersion !== appliedValue.analysisVersion
    || value.analysisInputHash !== appliedValue.analysisInputHash
    || value.analysisProfileKind !== appliedValue.analysisProfileKind
    || value.symbol !== appliedValue.symbol
    || value.gmoTarget !== appliedValue.gmoTarget
    || value.from !== appliedValue.from
    || value.to !== appliedValue.to
    || value.jstTime !== appliedValue.jstTime
    || !sameSyncTimeFrames(value.syncTimeFrames, appliedValue.syncTimeFrames)
    || value.fullAlignment !== appliedValue.fullAlignment
    || value.groupMode !== appliedValue.groupMode
    || value.pageSize !== appliedValue.pageSize;
}

const NO_SYNC_TIME_FRAMES_VALUE = "__no_sync_time_frames__";

export function ObservationFilterPanel({
  value,
  runs,
  options,
  busy,
  sidebar = false,
  onChange,
  onSubmit,
  onReset,
}: ObservationFilterPanelProps) {
  const desktopSidebar = useMediaQuery("(min-width: 1280px)");
  const sidebarLayout = sidebar && desktopSidebar;
  const visibleRuns = useMemo(
    () => runs.filter((run) => isRunVisible(run, value.sourceMode)),
    [runs, value.sourceMode],
  );
  const visibleProfiles = useMemo(
    () => observationProfilesForMode(options, value.sourceMode),
    [options, value.sourceMode],
  );
  const selectedProfile = useMemo(
    () => visibleProfiles.find((profile) => observationProfileMatchesSearch(profile, value)),
    [value, visibleProfiles],
  );
  const selectedSyncTimeFrames: string[] = value.syncTimeFrames.length === 0
    ? [NO_SYNC_TIME_FRAMES_VALUE]
    : value.syncTimeFrames;
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit();
  }

  function changeSyncTimeFrames(event: SelectChangeEvent<string[]>) {
    const rawValue = event.target.value;
    const requestedValues = typeof rawValue === "string" ? rawValue.split(",") : rawValue;
    if (value.syncTimeFrames.length > 0
        && requestedValues.includes(NO_SYNC_TIME_FRAMES_VALUE)) {
      onChange({ ...value, syncTimeFrames: [] });
      return;
    }
    const requestedTimeFrames = new Set(requestedValues);
    const syncTimeFrames = OBSERVATION_SYNC_TIME_FRAMES.filter(
      (timeFrame) => requestedTimeFrames.has(timeFrame),
    );
    onChange({ ...value, syncTimeFrames });
  }

  return (
    <Paper
      className={`observation-filter-panel${sidebarLayout ? " sidebar-layout" : ""}`}
      component="section"
      aria-labelledby="observationFilterTitle"
      aria-busy={busy}
      elevation={0}
      sx={{
        mb: sidebarLayout ? 0 : 1.25,
        p: 2,
        border: 1,
        borderColor: "divider",
        borderRadius: 2,
        bgcolor: "rgba(15, 26, 34, 0.92)",
      }}
    >
      <Stack
        className="observation-filter-heading"
        direction={sidebarLayout ? "column" : { xs: "column", sm: "row" }}
        sx={{ justifyContent: "space-between", gap: 1.5 }}
      >
        <Box className="observation-filter-heading-content" sx={{ minWidth: 0 }}>
          <Typography className="observation-filter-eyebrow" sx={{ color: "primary.main", fontSize: "0.68rem", fontWeight: 800, letterSpacing: "0.2em" }}>
            H1 OBSERVATION SEARCH
          </Typography>
          <Typography id="observationFilterTitle" variant="h6" sx={{ fontSize: "1.15rem", fontWeight: 700 }}>
            H1推移検索
          </Typography>
        </Box>
        <Stack className="observation-filter-heading-actions" direction="row" sx={{ flexWrap: "wrap", gap: 1, alignItems: "center" }}>
          <Button className="observation-filter-reset" color="inherit" size="small" variant="outlined" onClick={onReset}>
            条件をリセット
          </Button>
        </Stack>
      </Stack>

      <div id="observationFilterFields">
        <form onSubmit={submit}>
          <Box sx={{
            mt: 2,
            display: "grid",
            gridTemplateColumns: sidebarLayout
              ? "repeat(2, minmax(0, 1fr))"
              : {
                xs: "repeat(2, minmax(0, 1fr))",
                md: "repeat(4, minmax(130px, 1fr))",
                xl: "1fr 2fr repeat(5, minmax(130px, 1fr)) auto",
              },
            gap: 1.5,
            alignItems: "end",
          }} className="observation-filter-grid">
          <FormControl size="small">
            <InputLabel id="observationSourceModeLabel">実行モード</InputLabel>
            <Select
              labelId="observationSourceModeLabel"
              label="実行モード"
              value={value.sourceMode}
              onChange={(event) => {
                const sourceMode = event.target.value;
                if (sourceMode === "LIVE" || sourceMode === "TESTER" || sourceMode === "all") {
                  onChange({
                    ...value,
                    sourceMode,
                    runId: null,
                    ...observationProfileSearchFields(
                      defaultObservationAnalysisProfile(options, sourceMode),
                    ),
                  });
                }
              }}
            >
              <MenuItem value="LIVE">LIVE</MenuItem>
              <MenuItem value="TESTER">TESTER</MenuItem>
              <MenuItem value="all">LIVE＋TESTER</MenuItem>
            </Select>
          </FormControl>
          <FormControl
            className="observation-filter-run-field"
            size="small"
            sx={{
              gridColumn: sidebarLayout
                ? "1 / -1"
                : { xs: "span 2", md: "span 2", xl: "auto" },
            }}
          >
            <InputLabel id="observationRunLabel">Run</InputLabel>
            <Select
              labelId="observationRunLabel"
              label="Run"
              value={value.runId === null ? "" : String(value.runId)}
              onChange={(event) => {
                const runId = event.target.value ? Number(event.target.value) : null;
                const run = runId === null ? undefined : runs.find((item) => item.id === runId);
                onChange({
                  ...value,
                  runId,
                  ...(runId === null ? {} : {
                    analysisVersion: run?.analysis_version || "",
                    analysisInputHash: run?.analysis_input_hash || "",
                    analysisProfileKind: run?.analysis_profile_is_legacy
                      ? "legacy" as const
                      : "profile" as const,
                  }),
                });
              }}
            >
              <MenuItem value="">すべての観測Run</MenuItem>
              {visibleRuns.map((run) => (
                <MenuItem key={run.id} value={String(run.id)}>{runLabel(run)}</MenuItem>
              ))}
            </Select>
          </FormControl>
          <FormControl
            className="observation-filter-profile-field"
            size="small"
            sx={{
              gridColumn: sidebarLayout
                ? "1 / -1"
                : { xs: "span 2", md: "span 2", xl: "auto" },
            }}
          >
            <InputLabel id="observationAnalysisProfileLabel" shrink>分析Profile</InputLabel>
            <Select
              displayEmpty
              labelId="observationAnalysisProfileLabel"
              label="分析Profile"
              value={selectedProfile?.profile_key || ""}
              renderValue={(selected) => {
                if (!selected) return "すべてのProfile";
                const profile = visibleProfiles.find(
                  (item) => item.profile_key === selected,
                );
                return profile ? profileLabel(profile) : "未確認のProfile";
              }}
              onChange={(event) => {
                const profile = visibleProfiles.find(
                  (item) => item.profile_key === event.target.value,
                ) || null;
                onChange({
                  ...value,
                  runId: null,
                  ...observationProfileSearchFields(profile),
                });
              }}
            >
              <MenuItem value="">すべてのProfile</MenuItem>
              {visibleProfiles.map((profile) => (
                <MenuItem
                  key={profile.profile_key}
                  title={profile.analysis_input_text || "Legacy（設定詳細なし）"}
                  value={profile.profile_key}
                >
                  {profileLabel(profile)}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel id="observationSymbolLabel">通貨</InputLabel>
            <Select
              labelId="observationSymbolLabel"
              label="通貨"
              value={value.symbol}
              onChange={(event) => onChange({ ...value, symbol: event.target.value })}
            >
              <MenuItem value="">すべて</MenuItem>
              {options.symbols.map((symbol) => <MenuItem key={symbol} value={symbol}>{symbol}</MenuItem>)}
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel id="observationGmoTargetLabel">GMO取引</InputLabel>
            <Select
              labelId="observationGmoTargetLabel"
              label="GMO取引"
              value={value.gmoTarget}
              onChange={(event) => {
                const gmoTarget = event.target.value;
                if (gmoTarget === "all" || gmoTarget === "target" || gmoTarget === "excluded") {
                  onChange({ ...value, gmoTarget });
                }
              }}
            >
              <MenuItem value="all">すべて</MenuItem>
              <MenuItem value="target">対象</MenuItem>
              <MenuItem value="excluded">対象外</MenuItem>
            </Select>
          </FormControl>
          <TextField
            label="開始日（JST）"
            size="small"
            type="date"
            value={value.from}
            slotProps={{ inputLabel: { shrink: true } }}
            onChange={(event) => onChange({ ...value, from: event.target.value })}
          />
          <TextField
            label="終了日（JST）"
            size="small"
            type="date"
            value={value.to}
            slotProps={{ inputLabel: { shrink: true } }}
            onChange={(event) => onChange({ ...value, to: event.target.value })}
          />
          <FormControl size="small">
            <InputLabel id="observationJstTimeLabel" shrink>時刻（JST）</InputLabel>
            <Select
              displayEmpty
              labelId="observationJstTimeLabel"
              label="時刻（JST）"
              value={value.jstTime}
              renderValue={(selected) => selected || "すべて"}
              onChange={(event) => onChange({ ...value, jstTime: event.target.value })}
            >
              <MenuItem value="">すべて</MenuItem>
              {OBSERVATION_JST_TIMES.map((jstTime) => (
                <MenuItem key={jstTime} value={jstTime}>{jstTime}</MenuItem>
              ))}
            </Select>
          </FormControl>
          <FormControl
            className="observation-filter-sync-field"
            size="small"
            sx={{
              gridColumn: sidebarLayout
                ? "1 / -1"
                : { xs: "span 2", md: "span 2", xl: "auto" },
            }}
          >
            <InputLabel id="observationSyncTimeFramesLabel" shrink>
              上位足同期（H1方向）
            </InputLabel>
            <Select<string[]>
              displayEmpty
              labelId="observationSyncTimeFramesLabel"
              label="上位足同期（H1方向）"
              multiple
              value={selectedSyncTimeFrames}
              renderValue={(selected) => syncTimeFrameSummary(
                selected.filter(
                  (timeFrame) => timeFrame !== NO_SYNC_TIME_FRAMES_VALUE,
                ) as ObservationSyncTimeFrame[],
                "指定なし",
              )}
              onChange={changeSyncTimeFrames}
              MenuProps={{ slotProps: { paper: { sx: { maxHeight: 320 } } } }}
            >
              <MenuItem value={NO_SYNC_TIME_FRAMES_VALUE}>
                <Checkbox
                  aria-hidden="true"
                  checked={value.syncTimeFrames.length === 0}
                  disableRipple
                  indeterminate={value.syncTimeFrames.length > 0}
                  size="small"
                  tabIndex={-1}
                />
                <ListItemText primary="指定なし" />
              </MenuItem>
              {OBSERVATION_SYNC_TIME_FRAMES.map((timeFrame) => (
                <MenuItem key={timeFrame} value={timeFrame}>
                  <Checkbox
                    aria-hidden="true"
                    checked={value.syncTimeFrames.includes(timeFrame)}
                    disableRipple
                    size="small"
                    tabIndex={-1}
                  />
                  <ListItemText primary={timeFrame} />
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel id="observationFullAlignmentLabel" shrink>W1～H1＋EMA200一致</InputLabel>
            <Select
              displayEmpty
              labelId="observationFullAlignmentLabel"
              label="W1～H1＋EMA200一致"
              value={value.fullAlignment}
              renderValue={(selected) => fullAlignmentSummary(selected)}
              onChange={(event) => {
                const fullAlignment = event.target.value as string;
                if (fullAlignment === "" || fullAlignment === "FULL"
                    || fullAlignment === "BUY" || fullAlignment === "SELL") {
                  onChange({ ...value, fullAlignment });
                }
              }}
            >
              <MenuItem value="">指定なし</MenuItem>
              <MenuItem value="FULL">方向問わず完全一致</MenuItem>
              <MenuItem value="BUY">完全BUY</MenuItem>
              <MenuItem value="SELL">完全SELL</MenuItem>
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel id="observationGroupModeLabel" shrink>表示単位</InputLabel>
            <Select
              labelId="observationGroupModeLabel"
              label="表示単位"
              value={value.groupMode}
              onChange={(event) => {
                const groupMode = event.target.value === "signal" ? "signal" : "h1";
                const fullAlignment = groupMode === "signal" && value.fullAlignment === ""
                  ? "FULL"
                  : value.fullAlignment;
                onChange({ ...value, groupMode, fullAlignment });
              }}
            >
              <MenuItem value="h1">H1ごと</MenuItem>
              <MenuItem value="signal">連続FULLを1シグナル</MenuItem>
            </Select>
          </FormControl>
          <FormControl size="small">
            <InputLabel id="observationPageSizeLabel">表示件数</InputLabel>
            <Select
              labelId="observationPageSizeLabel"
              label="表示件数"
              value={String(value.pageSize)}
              onChange={(event) => onChange({ ...value, pageSize: Number(event.target.value) })}
            >
              <MenuItem value="25">25件</MenuItem>
              <MenuItem value="50">50件</MenuItem>
              <MenuItem value="100">100件</MenuItem>
            </Select>
          </FormControl>
          <Button
            disabled={busy}
            type="submit"
            variant="contained"
            sx={{
              minHeight: 40,
              ...(sidebarLayout ? {
                position: "sticky",
                bottom: 0,
                zIndex: 1,
                gridColumn: "1 / -1",
              } : {}),
            }}
          >
            検索
          </Button>
          </Box>
        </form>
      </div>
    </Paper>
  );
}
