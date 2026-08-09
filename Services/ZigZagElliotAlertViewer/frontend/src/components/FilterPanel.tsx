import type { FormEvent } from "react";
import type { OptionsResponse, RunItem, SearchState, SourceMode } from "../api/types";

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
  const visibleRuns = runs.filter((run) => isRunVisible(run, value.sourceMode));
  const allRunsLabel = value.sourceMode === "all"
    ? "すべてのRun（重複を含む）"
    : `すべての${value.sourceMode} Run（重複を含む）`;

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit();
  }

  return (
    <section className="filter-panel" aria-labelledby="reactFilterTitle">
      <div className="section-heading">
        <div>
          <p className="eyebrow">SEARCH</p>
          <h2 id="reactFilterTitle">アラート検索</h2>
        </div>
        <button className="ghost-button" type="button" onClick={onReset}>
          条件をリセット
        </button>
      </div>

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
          <button className="primary-button" type="submit">検索する</button>
          <button className="secondary-button" type="button" onClick={onExport}>CSV出力</button>
        </div>
      </form>
    </section>
  );
}
