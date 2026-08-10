import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Collapse from "@mui/material/Collapse";
import FormControl from "@mui/material/FormControl";
import InputLabel from "@mui/material/InputLabel";
import MenuItem from "@mui/material/MenuItem";
import Paper from "@mui/material/Paper";
import Select from "@mui/material/Select";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import useMediaQuery from "@mui/material/useMediaQuery";
import { useMemo, type FormEvent } from "react";
import type {
  ObservationOptionsResponse,
  ObservationSearchState,
  RunItem,
  SourceMode,
} from "../api/types";

interface ObservationFilterPanelProps {
  value: ObservationSearchState;
  appliedValue: ObservationSearchState;
  runs: RunItem[];
  options: ObservationOptionsResponse;
  busy: boolean;
  expanded: boolean;
  sidebar?: boolean;
  showCollapsedSummary?: boolean;
  onChange: (value: ObservationSearchState) => void;
  onExpandedChange: (expanded: boolean) => void;
  onSubmit: () => void;
  onReset: () => void;
}

function isRunVisible(run: RunItem, sourceMode: SourceMode): boolean {
  return sourceMode === "all" || run.source_mode.toUpperCase() === sourceMode;
}

function runLabel(run: RunItem): string {
  const symbols = run.observation_symbols || "観測なし";
  const range = run.last_observation_time_text
    ? `${run.first_observation_time_text || "?"} – ${run.last_observation_time_text}`
    : "記録なし";
  return `${run.source_mode}｜Run ${run.id}｜${symbols}｜${run.observation_count || 0}件｜${range}`;
}

export function observationFilterSummary(value: ObservationSearchState): string {
  const mode = value.sourceMode === "all" ? "LIVE＋TESTER" : value.sourceMode;
  const run = value.runId === null ? "全Run" : `Run ${value.runId}`;
  const symbol = value.symbol || "全通貨";
  const period = value.from || value.to
    ? `Server期間 ${value.from || "先頭"} – ${value.to || "末尾"}`
    : "Server全期間";
  return `${mode} / ${run} / ${symbol} / ${period}`;
}

export function hasObservationUnappliedChanges(
  value: ObservationSearchState,
  appliedValue: ObservationSearchState,
): boolean {
  return value.sourceMode !== appliedValue.sourceMode
    || value.runId !== appliedValue.runId
    || value.symbol !== appliedValue.symbol
    || value.from !== appliedValue.from
    || value.to !== appliedValue.to
    || value.pageSize !== appliedValue.pageSize;
}

export function ObservationFilterPanel({
  value,
  appliedValue,
  runs,
  options,
  busy,
  expanded,
  sidebar = false,
  showCollapsedSummary = true,
  onChange,
  onExpandedChange,
  onSubmit,
  onReset,
}: ObservationFilterPanelProps) {
  const desktopSidebar = useMediaQuery("(min-width: 1280px)");
  const sidebarLayout = sidebar && desktopSidebar;
  const visibleRuns = useMemo(
    () => runs.filter((run) => isRunVisible(run, value.sourceMode)),
    [runs, value.sourceMode],
  );
  const changed = hasObservationUnappliedChanges(value, appliedValue);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit();
  }

  return (
    <Paper
      className={`observation-filter-panel${sidebarLayout ? " sidebar-layout" : ""}${expanded ? "" : " collapsed"}`}
      component="section"
      aria-labelledby="observationFilterTitle"
      aria-busy={busy}
      elevation={0}
      sx={{
        mb: sidebarLayout ? 0 : 1.25,
        p: expanded ? 2 : 1.5,
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
          {!expanded && showCollapsedSummary && (
            <Stack className="filter-collapsed-summary observation-filter-collapsed-summary" direction="row" sx={{ flexWrap: "wrap", gap: 1, mt: 0.5, alignItems: "center" }}>
              <Typography sx={{ color: "text.secondary", fontSize: "0.72rem" }}>{observationFilterSummary(appliedValue)}</Typography>
              {changed && <Typography sx={{ color: "warning.main", fontSize: "0.68rem" }}>未検索の変更あり</Typography>}
            </Stack>
          )}
        </Box>
        <Stack className="observation-filter-heading-actions" direction="row" sx={{ flexWrap: "wrap", gap: 1, alignItems: "center" }}>
          <Button className="observation-filter-reset" color="inherit" size="small" variant="outlined" hidden={!expanded} onClick={onReset}>
            条件をリセット
          </Button>
          <Button
            className="observation-filter-toggle"
            aria-controls="observationFilterFields"
            aria-expanded={expanded}
            aria-label={expanded ? "検索条件を閉じる" : "検索条件を開く"}
            color="inherit"
            endIcon={<span aria-hidden style={{ fontSize: "0.7rem" }}>{expanded ? "▴" : "▾"}</span>}
            size="small"
            variant="outlined"
            onClick={() => onExpandedChange(!expanded)}
          >
            {expanded ? "閉じる" : "開く"}
          </Button>
        </Stack>
      </Stack>

      <Collapse id="observationFilterFields" in={expanded}>
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
                  onChange({ ...value, sourceMode, runId: null });
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
              onChange={(event) => onChange({
                ...value,
                runId: event.target.value ? Number(event.target.value) : null,
              })}
            >
              <MenuItem value="">すべての観測Run</MenuItem>
              {visibleRuns.map((run) => (
                <MenuItem key={run.id} value={String(run.id)}>{runLabel(run)}</MenuItem>
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
          <TextField
            label="開始日（Server）"
            size="small"
            type="date"
            value={value.from}
            slotProps={{ inputLabel: { shrink: true } }}
            onChange={(event) => onChange({ ...value, from: event.target.value })}
          />
          <TextField
            label="終了日（Server）"
            size="small"
            type="date"
            value={value.to}
            slotProps={{ inputLabel: { shrink: true } }}
            onChange={(event) => onChange({ ...value, to: event.target.value })}
          />
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
      </Collapse>
    </Paper>
  );
}
