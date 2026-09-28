import { useEffect, useMemo, useRef, useState } from "react";
import type { EaSample, EaSamplesResponse } from "../api/eaTypes";
import { eaMoney, eaNumber, eaTime } from "../lib/eaFormat";

type ChartMode = "equity" | "floating" | "positions";
type SampleKey = "balance" | "equity" | "open_profit" | "positions";
const SERIES: Record<ChartMode, { key: SampleKey; label: string; className: string }[]> = {
  equity: [{ key: "balance", label: "残高", className: "ea-series-balance" }, { key: "equity", label: "有効証拠金", className: "ea-series-equity" }],
  floating: [{ key: "open_profit", label: "評価損益（Swap込み）", className: "ea-series-balance" }],
  positions: [{ key: "positions", label: "保有数", className: "ea-series-balance" }],
};

/** Split paths at reported gaps, segment boundaries and unavailable values. */
export function eaChartPath(items: EaSample[], key: SampleKey, x: (value: number) => number, y: (value: number) => number): string {
  let previous: EaSample | null = null;
  let path = "";
  for (const item of items) {
    const value = item[key];
    if (value === null || !Number.isFinite(value)) { previous = null; continue; }
    const px = x(item.server_time).toFixed(2), py = y(value).toFixed(2);
    if (!previous || item.gap_before || item.segment_id !== previous.segment_id) path += `M${px},${py}`;
    else if (key === "positions" || key === "balance") path += `H${px}V${py}`;
    else path += `L${px},${py}`;
    previous = item;
  }
  return path;
}

export function eaIsolatedPoints(items: EaSample[], key: SampleKey): EaSample[] {
  const valid = (item: EaSample | undefined) => item !== undefined && item[key] !== null && Number.isFinite(item[key]);
  return items.filter((item, index) => {
    if (!valid(item)) return false;
    const before = items[index - 1], after = items[index + 1];
    const connectsBefore = valid(before) && !item.gap_before && before.segment_id === item.segment_id;
    const connectsAfter = valid(after) && !after.gap_before && after.segment_id === item.segment_id;
    return !connectsBefore && !connectsAfter;
  });
}

export function H1EaChart({ samples, currency }: { samples: EaSamplesResponse; currency: string | null }) {
  const [mode, setMode] = useState<ChartMode>("equity");
  const [width, setWidth] = useState(800);
  const [selected, setSelected] = useState<number | null>(null);
  const container = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const node = container.current;
    if (!node) return;
    const resize = () => setWidth(Math.max(240, node.getBoundingClientRect().width || 800));
    resize();
    const observer = new ResizeObserver(resize); observer.observe(node);
    return () => observer.disconnect();
  }, []);
  useEffect(() => setSelected(null), [mode, samples]);
  const items = samples.items;
  const series = SERIES[mode];
  const domain = useMemo(() => {
    const values = items.flatMap(item => series.map(itemSeries => item[itemSeries.key]))
      .filter((value): value is number => value !== null && Number.isFinite(value));
    let minimum = 0, maximum = 1;
    if (values.length) { minimum = Math.min(...values); maximum = Math.max(...values); }
    if (mode !== "equity") { minimum = Math.min(minimum, 0); maximum = Math.max(maximum, 0); }
    const padding = Math.max((maximum - minimum) * 0.08, mode === "positions" ? 1 : 0.01);
    return { low: mode === "positions" ? 0 : minimum - padding, high: maximum + padding };
  }, [items, mode, series]);
  const height = 240, left = width < 480 ? 74 : 88, right = 22, top = 20, bottom = 44;
  const first = items[0]?.server_time || 0, last = items.at(-1)?.server_time || first;
  const x = (value: number) => left + (value - first) / Math.max(last - first, 1) * (width - left - right);
  const y = (value: number) => height - bottom - (value - domain.low) / (domain.high - domain.low) * (height - top - bottom);
  const point = selected === null ? null : items[selected] || null;
  const unit = mode === "positions" ? "件" : currency || "口座通貨不明";
  const tickCount = first === last ? 1 : width < 500 ? 3 : 5;
  const tickValues = mode === "positions"
    ? [...new Set([0, Math.ceil(domain.high / 2), Math.ceil(domain.high - 1)])].sort((a, b) => a - b)
    : Array.from({ length: 4 }, (_, index) => domain.low + (domain.high - domain.low) * index / 3);
  function hover(clientX: number, bounds: DOMRect) {
    if (!items.length || !bounds.width) return;
    const time = first + ((clientX - bounds.left) / bounds.width * width - left) / (width - left - right) * (last - first);
    let low = 0, high = items.length - 1;
    while (low < high) { const middle = Math.floor((low + high) / 2); if (items[middle].server_time < time) low = middle + 1; else high = middle; }
    if (low > 0 && Math.abs(items[low - 1].server_time - time) < Math.abs(items[low].server_time - time)) low--;
    setSelected(low);
  }
  return <section className="ea-panel" aria-label="資産・保有状況">
    <div className="ea-panel-heading"><h3>資産・保有状況</h3><div className="ea-switch" aria-label="グラフ切替">
      {([['equity', '残高・有効証拠金'], ['floating', '評価損益'], ['positions', '保有数']] as const).map(([key, label]) =>
        <button key={key} type="button" aria-pressed={mode === key} onClick={() => setMode(key)}>{label}</button>)}
    </div></div>
    <div ref={container} className="ea-chart-container">
      {!items.length ? <p className="ea-empty">{samples.recorded ? "資産推移の記録はまだありません。" : "資産推移は未記録です。このテストは取引一覧・詳細を参照できます。"}</p> : <>
        <div className="ea-chart-legend"><span>{mode === "equity" ? "口座全体" : "対象EA"} · {unit}</span>
          {series.map(item => <span key={item.key}><i className={item.className} />{item.label}</span>)}
        </div>
        <svg className="ea-chart-svg" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${series.map(item => item.label).join("・")}の観測推移。${eaTime(first)}から${eaTime(last)} Server。`}
          onPointerMove={event => hover(event.clientX, event.currentTarget.getBoundingClientRect())}
          onPointerDown={event => hover(event.clientX, event.currentTarget.getBoundingClientRect())}
          onPointerLeave={() => setSelected(null)}>
          <rect className="ea-chart-frame" x={left} y={top} width={width - left - right} height={height - top - bottom} />
          {tickValues.map(value => <g key={value}><line className="ea-chart-grid" x1={left} x2={width - right} y1={y(value)} y2={y(value)} /><text x={left - 9} y={y(value) + 4} textAnchor="end">{eaNumber(value, mode === "positions" ? 0 : 2)}</text></g>)}
          {Array.from({ length: tickCount }, (_, index) => { const date = first + (last - first) * index / Math.max(tickCount - 1, 1); return <text key={index} x={x(date)} y={height - 23} textAnchor={index === 0 ? "start" : index === tickCount - 1 ? "end" : "middle"}>{last - first < 86400 ? eaTime(date).slice(11, 16) : eaTime(date).slice(5, 10)}</text>; })}
          <text x={left} y={12}>{unit}</text><text x={width - right} y={height - 5} textAnchor="end">日時 / Server</text>
          {series.map(item => <path key={item.key} className={`ea-chart-line ${item.className}`} d={eaChartPath(items, item.key, x, y)} />)}
          {series.flatMap(item => eaIsolatedPoints(items, item.key).map(point => <circle key={`${item.key}-${point.sequence}`} className={item.className} cx={x(point.server_time)} cy={y(point[item.key]!)} r={3} />))}
          {point && <line className="ea-chart-guide" x1={x(point.server_time)} x2={x(point.server_time)} y1={top} y2={height - bottom} />}
        </svg>
        {point && <div className="ea-chart-tooltip" role="tooltip"><div>{eaTime(point.server_time)} Server</div>{series.map(item => <div key={item.key}>{item.label}：{mode === "positions" ? eaNumber(point[item.key], 0) : eaMoney(point[item.key], currency)} {unit}</div>)}</div>}
        <p className="ea-note">{samples.sample_interval_seconds ? `${samples.sample_interval_seconds}秒間隔` : "記録間隔不明"}＋保有変化時の観測値。{samples.downsampled ? `${eaNumber(samples.total, 0)}点を${eaNumber(samples.returned, 0)}点に間引いて表示。` : ""}記録の空白は線を接続しません。</p>
      </>}
    </div>
  </section>;
}
