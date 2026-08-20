import Checkbox from "@mui/material/Checkbox";
import FormControl from "@mui/material/FormControl";
import ListItemText from "@mui/material/ListItemText";
import MenuItem from "@mui/material/MenuItem";
import Select, { type SelectChangeEvent } from "@mui/material/Select";
import { useState, type FormEvent } from "react";
import type {
  GmoTargetFilter,
  H1DirectionAlignmentMode,
  H1DirectionAlignmentState,
  OptionsResponse,
  RunItem,
  SearchState,
  SourceMode,
  W1ConfirmationMode,
  W1ConfirmationState,
} from "../api/types";
import {
  h1DirectionAlignmentModeLabel,
  h1DirectionAlignmentStateDescription,
} from "./H1DirectionAlignmentBadge";
import {
  w1ConfirmationModeLabel,
  w1ConfirmationStateDescription,
} from "./W1ConfirmationBadge";

interface FilterPanelProps {
  value: SearchState;
  runs: RunItem[];
  options: OptionsResponse;
  busy: boolean;
  onChange: (value: SearchState) => void;
  onSubmit: () => void;
  onReset: () => void;
  onExport: () => void;
}

function isRunVisible(run: RunItem, sourceMode: SourceMode): boolean {
  return sourceMode === "all" || run.source_mode.toUpperCase() === sourceMode;
}

const SEARCH_VALUE_KEYS: ReadonlyArray<keyof SearchState> = [
  "sourceMode",
  "runId",
  "q",
  "symbol",
  "gmoTarget",
  "side",
  "rank",
  "w1Aligned",
  "w1ConfirmationMode",
  "w1ConfirmationState",
  "h1DirectionAlignmentMode",
  "h1DirectionAlignmentState",
  "from",
  "to",
  "pageSize",
];

export function hasAlertUnappliedChanges(value: SearchState, appliedValue: SearchState): boolean {
  const valueTimeFrames = new Set(value.timeFrames);
  const appliedTimeFrames = new Set(appliedValue.timeFrames);
  return SEARCH_VALUE_KEYS.some((key) => value[key] !== appliedValue[key])
    || valueTimeFrames.size !== appliedTimeFrames.size
    || [...valueTimeFrames].some((timeFrame) => !appliedTimeFrames.has(timeFrame));
}

function timeFrameSummary(timeFrames: string[], emptyLabel: string): string {
  if (timeFrames.length === 0) return emptyLabel;
  if (timeFrames.length <= 2) return timeFrames.join("・");
  return `${timeFrames.slice(0, 2).join("・")}＋${timeFrames.length - 2}`;
}

function gmoTargetSummary(gmoTarget: GmoTargetFilter): string {
  if (gmoTarget === "target") return "対象";
  if (gmoTarget === "excluded") return "対象外";
  return "すべて";
}

export function alertFilterSummary(value: SearchState): string {
  const sourceMode = value.sourceMode === "all" ? "LIVE＋TESTER" : value.sourceMode;
  const run = value.runId === null ? "全Run" : `Run ${value.runId}`;
  const symbol = value.symbol || "全通貨";
  const timeFrames = timeFrameSummary(value.timeFrames, "全時間足");
  const side = value.side || "BUY＋SELL";
  const additionalFilterCount = [
    value.q.trim() !== "",
    value.rank !== "",
    value.w1Aligned !== "all",
    value.w1ConfirmationMode !== "all",
    value.w1ConfirmationState !== "all",
    value.h1DirectionAlignmentMode !== "all",
    value.h1DirectionAlignmentState !== "all",
    value.from !== "" || value.to !== "",
  ].filter(Boolean).length;
  const additionalFilters = additionalFilterCount > 0
    ? ` / 絞り込み ${additionalFilterCount}項目`
    : "";
  return `${sourceMode} / ${run} / ${symbol} / ${timeFrames} / ${side}${additionalFilters}`
    + ` / GMO取引 ${gmoTargetSummary(value.gmoTarget)}`;
}

const ALL_TIME_FRAMES_VALUE = "__all_time_frames__";
const W1_CONFIRMATION_MODE_ORDER: W1ConfirmationMode[] = [
  "OFF",
  "OBSERVE_ONLY",
  "DIRECTION_OR_EMA200",
  "DIRECTION_AND_EMA200",
];
const W1_CONFIRMATION_STATE_ORDER: W1ConfirmationState[] = [
  "STRONG",
  "DIRECTION_ONLY",
  "EMA_CONFLICT",
  "EMA_ONLY",
  "REJECT_NONE",
  "REJECT",
  "OFF",
  "NOT_APPLICABLE",
  "UNAVAILABLE",
  "INVALID",
  "NOT_EVALUATED",
];
const H1_DIRECTION_ALIGNMENT_MODE_ORDER: H1DirectionAlignmentMode[] = [
  "D1_TO_H1",
  "MN1_TO_H1_OBSERVE",
  "MN1_TO_H1_REQUIRED",
  "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
  "INVALID",
];
const H1_DIRECTION_ALIGNMENT_STATE_ORDER: H1DirectionAlignmentState[] = [
  "FULL_BUY",
  "FULL_SELL",
  "EMA200_FALLBACK_BUY",
  "EMA200_FALLBACK_SELL",
  "MN1_EMA200_MISMATCH",
  "MN1_MISMATCH",
  "W1_MISMATCH",
  "MN1_W1_MISMATCH",
  "D1_TO_H1",
  "NOT_APPLICABLE",
  "UNAVAILABLE",
  "INVALID",
  "NOT_EVALUATED",
];

export function FilterPanel({
  value,
  runs,
  options,
  busy,
  onChange,
  onSubmit,
  onReset,
  onExport,
}: FilterPanelProps) {
  const [timeFrameMenuOpen, setTimeFrameMenuOpen] = useState(false);
  const visibleRuns = runs.filter((run) => isRunVisible(run, value.sourceMode));
  const allRunsLabel = value.sourceMode === "all"
    ? "すべてのRun（重複を含む）"
    : `すべての${value.sourceMode} Run（重複を含む）`;
  const menuTimeFrames = [...new Set([...options.time_frames, ...value.timeFrames])];
  const selectedTimeFrames = value.timeFrames.length === 0
    ? [ALL_TIME_FRAMES_VALUE]
    : value.timeFrames;

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit();
  }

  function changeTimeFrames(event: SelectChangeEvent<string[]>) {
    const rawValue = event.target.value;
    const requestedValues = typeof rawValue === "string" ? rawValue.split(",") : rawValue;
    setTimeFrameMenuOpen(false);
    if (value.timeFrames.length > 0 && requestedValues.includes(ALL_TIME_FRAMES_VALUE)) {
      onChange({ ...value, timeFrames: [] });
      return;
    }
    const timeFrames = [...new Set(
      requestedValues
        .filter((timeFrame) => timeFrame !== ALL_TIME_FRAMES_VALUE)
        .map((timeFrame) => timeFrame.trim())
        .filter(Boolean),
    )];
    onChange({
      ...value,
      timeFrames,
    });
  }

  return (
    <section className="filter-panel react-filter-panel" aria-busy={busy} aria-labelledby="reactFilterTitle">
      <div className="section-heading filter-panel-heading">
        <div className="filter-heading-content">
          <p className="eyebrow">SEARCH</p>
          <h2 id="reactFilterTitle">アラート検索</h2>
        </div>
        <div className="filter-heading-actions">
          <button className="ghost-button" type="button" onClick={onReset}>
            条件をリセット
          </button>
        </div>
      </div>

      <div id="reactFilterFields">
        <form className="filter-grid" aria-busy={busy} onSubmit={submit}>
        <label className="field">
          <span>実行モード</span>
          <select
            aria-label="実行モード"
            value={value.sourceMode}
            onChange={(event) => {
              const sourceMode = event.target.value;
              if (sourceMode === "LIVE" || sourceMode === "TESTER" || sourceMode === "all") {
                onChange({ ...value, sourceMode, runId: null });
              }
            }}
          >
            <option value="LIVE">LIVE</option>
            <option value="TESTER">TESTER</option>
            <option value="all">LIVE＋TESTER</option>
          </select>
        </label>
        <label className="field field-wide">
          <span>Run</span>
          <select
            aria-label="実行Run"
            value={value.runId === null ? "" : value.runId}
            onChange={(event) => onChange({ ...value, runId: event.target.value ? Number(event.target.value) : null })}
          >
            <option value="">{allRunsLabel}</option>
            {visibleRuns.map((run) => {
              const symbolText = run.symbols || "アラートなし";
              const range = run.last_alert_time_text
                ? `${run.first_alert_time_text || "?"} – ${run.last_alert_time_text}`
                : "記録なし";
              return (
                <option key={run.id} value={run.id}>
                  {`${run.source_mode}｜Run ${run.id}｜${symbolText}｜${run.alert_count}件｜${range}`}
                </option>
              );
            })}
          </select>
        </label>
        <label className="field field-search">
          <span>キーワード</span>
          <input
            type="search"
            maxLength={200}
            placeholder="波動ラベル、タイトル、シグナルキー"
            value={value.q}
            onChange={(event) => onChange({ ...value, q: event.target.value })}
          />
        </label>
        <label className="field">
          <span>通貨</span>
          <select value={value.symbol} onChange={(event) => onChange({ ...value, symbol: event.target.value })}>
            <option value="">すべて</option>
            {options.symbols.map((symbol) => <option key={symbol}>{symbol}</option>)}
          </select>
        </label>
        <label className="field">
          <span>GMO取引</span>
          <select
            aria-label="GMO取引"
            value={value.gmoTarget}
            onChange={(event) => {
              const gmoTarget = event.target.value;
              if (gmoTarget === "all" || gmoTarget === "target" || gmoTarget === "excluded") {
                onChange({ ...value, gmoTarget });
              }
            }}
          >
            <option value="all">すべて</option>
            <option value="target">対象</option>
            <option value="excluded">対象外</option>
          </select>
        </label>
        <div className="field">
          <span id="alertTimeFramesLabel">時間足</span>
          <FormControl fullWidth size="small">
            <Select<string[]>
              displayEmpty
              labelId="alertTimeFramesLabel"
              multiple
              open={timeFrameMenuOpen}
              value={selectedTimeFrames}
              renderValue={(selected) => timeFrameSummary(
                selected.filter((timeFrame) => timeFrame !== ALL_TIME_FRAMES_VALUE),
                "すべて",
              )}
              onChange={changeTimeFrames}
              onClose={() => setTimeFrameMenuOpen(false)}
              onOpen={() => setTimeFrameMenuOpen(true)}
              MenuProps={{ slotProps: { paper: { sx: { maxHeight: 320 } } } }}
              sx={{
                height: 40,
                bgcolor: "#0a141b",
                fontSize: "0.78rem",
                "& .MuiSelect-select": { px: 1.4, py: 1 },
                "& .MuiOutlinedInput-notchedOutline": { borderColor: "divider" },
              }}
            >
              <MenuItem value={ALL_TIME_FRAMES_VALUE}>
                <Checkbox
                  aria-hidden="true"
                  checked={value.timeFrames.length === 0}
                  disableRipple
                  indeterminate={value.timeFrames.length > 0}
                  size="small"
                  tabIndex={-1}
                />
                <ListItemText primary="すべて" />
              </MenuItem>
              {menuTimeFrames.map((timeFrame) => (
                <MenuItem key={timeFrame} value={timeFrame}>
                  <Checkbox
                    aria-hidden="true"
                    checked={value.timeFrames.includes(timeFrame)}
                    disableRipple
                    size="small"
                    tabIndex={-1}
                  />
                  <ListItemText primary={timeFrame} />
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        </div>
        <label className="field">
          <span>方向</span>
          <select
            value={value.side}
            onChange={(event) => {
              const side = event.target.value === "BUY" || event.target.value === "SELL" ? event.target.value : "";
              onChange({ ...value, side });
            }}
          >
            <option value="">BUY＋SELL</option>
            <option value="BUY">BUY</option>
            <option value="SELL">SELL</option>
          </select>
        </label>
        <label className="field">
          <span>H1構造</span>
          <select value={value.rank} onChange={(event) => onChange({ ...value, rank: event.target.value })}>
            <option value="">すべて</option>
            {options.ranks.map((rank) => <option key={rank}>{rank}</option>)}
          </select>
        </label>
        <label className="field">
          <span>W1方向</span>
          <select
            value={value.w1Aligned}
            onChange={(event) => {
              const nextValue = event.target.value;
              if (nextValue === "all" || nextValue === "aligned" || nextValue === "mismatched" || nextValue === "unknown") {
                onChange({ ...value, w1Aligned: nextValue });
              }
            }}
          >
            <option value="all">すべて</option>
            <option value="aligned">アラートと一致</option>
            <option value="mismatched">アラートと不一致</option>
            <option value="unknown">不明</option>
          </select>
        </label>
        <label className="field">
          <span>W1確認</span>
          <select
            aria-label="W1確認"
            value={value.w1ConfirmationState}
            onChange={(event) => {
              const nextValue = event.target.value as SearchState["w1ConfirmationState"];
              if (nextValue === "all" || W1_CONFIRMATION_STATE_ORDER.includes(nextValue)) {
                onChange({ ...value, w1ConfirmationState: nextValue });
              }
            }}
          >
            <option value="all">すべて</option>
            {W1_CONFIRMATION_STATE_ORDER.map((state) => (
              <option key={state} value={state}>
                {state === "NOT_EVALUATED"
                  ? "NOT_EVALUATED（Legacy）"
                  : `${state}（${w1ConfirmationStateDescription(state)}）`}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>W1確認モード</span>
          <select
            aria-label="W1確認モード"
            value={value.w1ConfirmationMode}
            onChange={(event) => {
              const nextValue = event.target.value as SearchState["w1ConfirmationMode"];
              if (nextValue === "all" || W1_CONFIRMATION_MODE_ORDER.includes(nextValue)) {
                onChange({ ...value, w1ConfirmationMode: nextValue });
              }
            }}
          >
            <option value="all">すべて</option>
            {W1_CONFIRMATION_MODE_ORDER.map((mode) => (
              <option key={mode} value={mode}>
                {mode === "OFF" ? "OFF" : `${w1ConfirmationModeLabel(mode)}（${mode}）`}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>H1方向ルール状態</span>
          <select
            aria-label="H1方向ルール状態"
            value={value.h1DirectionAlignmentState}
            onChange={(event) => {
              const nextValue = event.target.value as SearchState["h1DirectionAlignmentState"];
              if (nextValue === "all" || H1_DIRECTION_ALIGNMENT_STATE_ORDER.includes(nextValue)) {
                onChange({ ...value, h1DirectionAlignmentState: nextValue });
              }
            }}
          >
            <option value="all">すべて</option>
            {H1_DIRECTION_ALIGNMENT_STATE_ORDER.map((state) => (
              <option key={state} value={state}>
                {state === "NOT_EVALUATED"
                  ? "NOT_EVALUATED（Legacy）"
                  : `${state}（${h1DirectionAlignmentStateDescription(state)}）`}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>H1方向ルールモード</span>
          <select
            aria-label="H1方向ルールモード"
            value={value.h1DirectionAlignmentMode}
            onChange={(event) => {
              const nextValue = event.target.value as SearchState["h1DirectionAlignmentMode"];
              if (nextValue === "all" || H1_DIRECTION_ALIGNMENT_MODE_ORDER.includes(nextValue)) {
                onChange({ ...value, h1DirectionAlignmentMode: nextValue });
              }
            }}
          >
            <option value="all">すべて</option>
            {H1_DIRECTION_ALIGNMENT_MODE_ORDER.map((mode) => (
              <option key={mode} value={mode}>
                {`${h1DirectionAlignmentModeLabel(mode)}（${mode}）`}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>開始日（JST）</span>
          <input type="date" value={value.from} onChange={(event) => onChange({ ...value, from: event.target.value })} />
        </label>
        <label className="field">
          <span>終了日（JST）</span>
          <input type="date" value={value.to} onChange={(event) => onChange({ ...value, to: event.target.value })} />
        </label>
        <label className="field field-small">
          <span>表示件数</span>
          <select value={value.pageSize} onChange={(event) => onChange({ ...value, pageSize: Number(event.target.value) })}>
            <option value={25}>25件</option>
            <option value={50}>50件</option>
            <option value={100}>100件</option>
          </select>
        </label>
        <div className="filter-actions">
          <button className="primary-button" type="submit">検索</button>
          <button className="secondary-button" type="button" onClick={onExport}>CSV出力</button>
        </div>
        </form>
      </div>
    </section>
  );
}
