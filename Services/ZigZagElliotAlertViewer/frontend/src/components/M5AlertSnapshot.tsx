import { useMemo, useState } from "react";
import type { AlertCorrectionMetadata, AlertCorrectionResponse, AlertDetailResponse, AlertPoint, AlertTimeFrame } from "../api/types";
import { CurrencyStrengthSnapshotPanel } from "./CurrencyStrengthSnapshotPanel";
import "./M5AlertSnapshot.css";

type Analysis = "ORIGINAL" | "CORRECTED";
type View = "selected" | "original" | "comparison";
interface SnapshotRow { label: string; frame: number; analysis: Analysis; timeFrame: AlertTimeFrame | null; point: AlertPoint | null }
interface Column {
  id: string;
  label: string;
  summary?: boolean;
  numeric?: boolean;
  signed?: boolean;
  digits?: number;
  get: (row: SnapshotRow) => unknown;
  display?: (row: SnapshotRow) => string;
  direction?: (row: SnapshotRow) => string;
}
export interface M5AlertSnapshotProps { detail: AlertDetailResponse; timeFrames: AlertTimeFrame[]; points: AlertPoint[] }

const frames = [
  { id: 49153, label: "MN1" }, { id: 32769, label: "W1" }, { id: 16408, label: "D1" },
  { id: 16388, label: "H4" }, { id: 16385, label: "H1" }, { id: 15, label: "M15" }, { id: 5, label: "M5" },
];
const missing = "未記録";

function text(value: unknown): string {
  if (value === null || value === undefined || value === "") return missing;
  return String(value);
}
function number(value: unknown, digits = 0, signed = false): string {
  if (typeof value !== "number" || !Number.isFinite(value)) return missing;
  let prefix = "";
  if (signed && value > 0) prefix = "+";
  return prefix + value.toLocaleString("ja-JP", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}
function flag(value: unknown, yes: string, no: string): string {
  if (value === true) return yes;
  if (value === false) return no;
  return missing;
}
function direction(row: SnapshotRow): string { return flag(row.timeFrame?.is_buy, "BUY", "SELL"); }
function sideClass(value: string): string {
  if (value === "BUY" || value.startsWith("+")) return "m5-alert-buy";
  if (value === "SELL" || value.startsWith("-")) return "m5-alert-sell";
  return "";
}
function wave(row: SnapshotRow): string {
  if (!row.timeFrame) return missing;
  let symbol = "";
  if (row.timeFrame.is_wave_uptrend === true) symbol = "▲";
  if (row.timeFrame.is_wave_uptrend === false) symbol = "▼";
  let suffix = "";
  if (row.timeFrame.latest_sub_elliot_label) suffix = "." + row.timeFrame.latest_sub_elliot_label;
  return symbol + text(row.timeFrame.latest_elliot_label) + suffix;
}
function emaDirection(row: SnapshotRow): string {
  if (row.frame === 49153) return "対象外（MN1）";
  if (!row.timeFrame?.is_ema200_available) return missing;
  const buy = row.timeFrame.is_ema200_buy;
  const sell = row.timeFrame.is_ema200_sell;
  if (typeof buy !== "boolean" || typeof sell !== "boolean") return missing;
  if (buy === true && sell === false) return "BUY";
  if (sell === true && buy === false) return "SELL";
  if (buy === false && sell === false) return "NONE";
  return "不整合";
}
function fibonacci(row: SnapshotRow): string {
  const point = row.point;
  if (!point || typeof point.org_elliot_index !== "number") return missing;
  if (point.org_elliot_index <= 1) return "対象外";
  let label = "FE";
  let available = point.is_fibonacci_expansion_available;
  let value = point.fibonacci_expansion_percent;
  if (point.org_elliot_index % 2 === 0) {
    label = "F";
    available = point.is_fibonacci_available;
    value = point.fibonacci_percent;
  }
  if (available !== true || !Number.isFinite(value) || value <= 0) return missing;
  return label + " " + number(value, 1) + "%";
}
function field(id: keyof AlertTimeFrame, label: string, digits = 0, signed = false, summary = false): Column {
  return { id, label, digits, signed, summary, numeric: true, get: (row) => row.timeFrame?.[id] };
}
function pointField(id: keyof AlertPoint, label: string, digits = 0, summary = false): Column {
  return { id: "point-" + id, label, digits, summary, numeric: true, get: (row) => row.point?.[id] };
}
function emaField(id: keyof AlertTimeFrame, label: string, digits = 0, signed = false): Column {
  return { ...field(id, label, digits, signed), get: (row) => [row.timeFrame?.is_ema200_available, row.timeFrame?.[id]], display: (row) => {
    if (row.frame === 49153) return "対象外（MN1）";
    if (!row.timeFrame?.is_ema200_available) return missing;
    return number(row.timeFrame[id], digits, signed);
  } };
}
const columns: Column[] = [
  { id: "state", label: "Wave状態", summary: true, get: (row) => row.timeFrame?.is_wave_confirmed, display: (row) => flag(row.timeFrame?.is_wave_confirmed, "確定", "形成中") },
  { id: "added", label: "最新点の取得種別", summary: true, get: (row) => row.point?.is_added_point, display: (row) => flag(row.point?.is_added_point, "補完", "通常") },
  { id: "fibonacci", label: "F / FE（元番号に対応）", summary: true, get: (row) => [row.point?.org_elliot_index, row.point?.is_fibonacci_available, row.point?.fibonacci_percent, row.point?.is_fibonacci_expansion_available, row.point?.fibonacci_expansion_percent], display: fibonacci },
  pointField("pips_diff", "pips差", 1, true), pointField("rate", "最新点価格", 5, true),
  field("oscillator_count", "Oscillator Count", 0, true, true),
  field("stochastic_short_count", "Stochastic 短期 Count", 0, true, true),
  field("stochastic_middle_count", "Stochastic 中期 Count", 0, true, true),
  field("stochastic_long_count", "Stochastic 長期 Count", 0, true, true),
  field("gmma_trend_count", "GMMA Trend", 0, true, true), field("gmma_cross_count", "GMMA Cross", 0, true, true),
  { id: "wave-direction", label: "Wave方向", get: (row) => row.timeFrame?.is_wave_uptrend, display: (row) => flag(row.timeFrame?.is_wave_uptrend, "▲ 上昇", "▼ 下降") },
  { id: "motive", label: "Wave種別", get: (row) => row.timeFrame?.is_wave_motive, display: (row) => flag(row.timeFrame?.is_wave_motive, "推進波", "修正波") },
  field("wave_count", "Wave数"), field("latest_wave_index", "最新Wave index"), field("point_count", "保存Point数"),
  { id: "previous-wave", label: "前回Wave最終", get: (row) => row.timeFrame?.previous_last_elliot_label },
  { id: "point-time", label: "最新点 Server", get: (row) => row.point?.bar_time, display: (row) => text(row.point?.bar_time_text) },
  { id: "point-next", label: "次足 Server", get: (row) => [row.point?.is_bar_time_next_available, row.point?.bar_time_next], display: (row) => {
    if (!row.point?.is_bar_time_next_available) return missing;
    return text(row.point.bar_time_next_text);
  } },
  { id: "peak", label: "Peak / Bottom", get: (row) => row.point?.is_peak, display: (row) => flag(row.point?.is_peak, "Peak", "Bottom") },
  pointField("wave_bars_from_start", "波の開始からの本数"), pointField("bar_index", "Bar index"),
  { id: "org-wave", label: "元番号 → 表示番号", get: (row) => [row.point?.org_elliot_label, row.point?.elliot_label], display: (row) => text(row.point?.org_elliot_label) + " → " + text(row.point?.elliot_label) },
  { id: "depth", label: "Depth Zone", get: (row) => [row.point?.fibo_depth_zone, row.point?.fibo_depth_zone_label], display: (row) => text(row.point?.fibo_depth_zone_label) },
  ...(["previous", "current"] as const).flatMap((period) => {
    let label = "取得時点の形成中足";
    if (period === "previous") label = "直前確定足";
    return (["open", "high", "low", "close"] as const).map((item) => field(`${period}_${item}`, label + " " + item, 5));
  }),
  emaField("ema200_close1", "EMA200 Close1", 5), emaField("ema200_shift1", "EMA200 Shift1", 5), emaField("ema200_compare", "EMA200 比較値", 5),
  emaField("ema200_slope_pips", "EMA200 傾き pips", 1, true), emaField("ema200_close_diff_pips", "EMA200 終値距離 pips", 1, true),
  emaField("ema200_up_count", "EMA200 上昇本数"), emaField("ema200_down_count", "EMA200 下降本数"), emaField("ema200_trend_count", "EMA200 Trend Count", 0, true),
  field("ema30", "EMA30", 5), field("ema60", "EMA60", 5), field("ema30_ema60_diff_pips", "EMA30–60距離 pips", 1, true), field("atr14_pips", "ATR14 pips", 1),
  { id: "osc-direction", label: "Oscillator方向", get: (row) => row.timeFrame?.is_oscillator_buy, display: (row) => flag(row.timeFrame?.is_oscillator_buy, "BUY", "SELL") },
  ...(["short", "middle", "long"] as const).flatMap((period, index) => [
    field(`stochastic_${period}_main`, `Stochastic ${["短期", "中期", "長期"][index]} Main`, 2),
    field(`stochastic_${period}_signal`, `Stochastic ${["短期", "中期", "長期"][index]} Signal`, 2),
  ]),
  { id: "stoch-order", label: "Stochastic 順序", get: (row) => row.timeFrame?.stochastic_main_order_text },
  { id: "stoch-direction", label: "Stochastic 方向", get: (row) => row.timeFrame?.stochastic_main_direction_text },
  ...(["618", "1000", "1272", "1618", "2000"] as const).map((level): Column => ({
    ...field(`fe${level}_price`, `FE ${Number(level) / 10}%価格`, 5), get: (row) => [row.timeFrame?.is_fibo_expansion_available, row.timeFrame?.[`fe${level}_price`]], display: (row) => {
      if (!row.timeFrame?.is_fibo_expansion_available) return "利用不可";
      return number(row.timeFrame[`fe${level}_price`], 5);
    },
  })),
  { ...field("distance_to_fe2000_pips", "FE200距離 pips", 1), get: (row) => [row.timeFrame?.is_fibo_expansion_available, row.timeFrame?.distance_to_fe2000_pips], display: (row) => {
    if (row.timeFrame?.is_fibo_expansion_available !== true) return "利用不可";
    return number(row.timeFrame.distance_to_fe2000_pips, 1);
  } },
];
const keyColumns: Column[] = [
  { id: "direction", label: "分析方向", get: (row) => row.timeFrame?.is_buy, display: direction },
  { id: "ema-direction", label: "EMA200方向", get: (row) => [row.timeFrame?.is_ema200_available, row.timeFrame?.is_ema200_buy, row.timeFrame?.is_ema200_sell], display: emaDirection },
  { id: "wave", label: "Elliott / Sub", get: (row) => [row.timeFrame?.is_wave_uptrend, row.timeFrame?.latest_elliot_label, row.timeFrame?.latest_sub_elliot_label], display: wave, direction },
];
function rowsFor(timeFrames: AlertTimeFrame[], points: AlertPoint[], analysis: Analysis): SnapshotRow[] {
  return frames.map((frame) => {
    const matches = timeFrames.filter((row) => row.time_frame === frame.id);
    let timeFrame: AlertTimeFrame | null = null;
    let point: AlertPoint | null = null;
    if (matches.length === 1) {
      timeFrame = matches[0];
      const latest = points.filter((item) => item.alert_timeframe_id === timeFrame?.id && item.time_frame === frame.id && item.is_latest);
      if (latest.length === 1) point = latest[0];
    }
    return { label: frame.label, frame: frame.id, analysis, timeFrame, point };
  });
}
function hasDifference(column: Column, first: SnapshotRow, second: SnapshotRow): boolean {
  return JSON.stringify(column.get(first)) !== JSON.stringify(column.get(second));
}
function cellText(column: Column, row: SnapshotRow): string {
  if (!row.timeFrame) return missing;
  if (column.display) return column.display(row);
  if (column.numeric) return number(column.get(row), column.digits, column.signed);
  return text(column.get(row));
}
function correctionStatus(correction: AlertCorrectionResponse | undefined): AlertCorrectionResponse["status"] {
  if (!correction) return "UNRECORDED";
  if ((correction.status === "APPLIED" || correction.status === "NONE") && !correction.metadata) return "INCOMPLETE";
  return correction.status;
}
function statusMessage(status: AlertCorrectionResponse["status"]): string {
  if (status === "APPLIED") return "補正後の分析を判定・損切りに採用";
  if (status === "NONE") return "補正なし・元分析を採用";
  if (status === "INCOMPLETE") return "補正データ不完全・採用分析を表示できません。元の保存分析を比較用として表示します。";
  return "補正情報は未記録です。元の保存分析を表示し、採用分析は推定しません。";
}
function analysisLabel(analysis: Analysis, status: AlertCorrectionResponse["status"]): string {
  if (analysis === "CORRECTED") return "補正後（採用）";
  if (status === "APPLIED") return "補正前（比較用）";
  if (status === "NONE") return "元分析（採用）";
  if (status === "INCOMPLETE") return "元の保存分析（比較用）";
  return "元の保存分析";
}

function StopLoss({ detail, status }: { detail: AlertDetailResponse; status: AlertCorrectionResponse["status"] }) {
  const metadata = detail.correction?.metadata;
  const known = status === "APPLIED" || status === "NONE";
  let selected = "未記録";
  let risk = "未記録";
  if (status === "INCOMPLETE") selected = "表示不可（補正データ不完全）";
  if (known && metadata?.is_selected_stop_loss_available) {
    selected = number(metadata.selected_stop_loss, 5);
    risk = number(metadata.selected_risk_pips, 1) + " pips";
  }
  let original = missing;
  if (detail.alert.is_stop_loss_available) original = number(detail.alert.stop_loss, 5);
  return <section className="m5-alert-sl" aria-label="判定時の損切り候補">
    <div><span>採用SL候補</span><strong>{selected}</strong><small>リスク {risk}</small></div>
    <div><span>元SL候補（参考）</span><strong>{original}</strong><small>リスク {number(detail.alert.risk_pips, 1)} pips</small></div>
    <p>判定時の分析値です。注文・ポジションの実SLとは異なる場合があります。</p>
    {known && metadata && <details><summary>LC0 / 5 / 10 / 15 の保存値</summary><table aria-label="補正前後の損切り候補詳細"><thead><tr><th>分析</th>{[0, 5, 10, 15].map((offset) => <th key={offset}>LC{offset}</th>)}</tr></thead><tbody>
      {status === "APPLIED" && <tr><th>補正後（採用）</th>{[metadata.corrected_lc0, metadata.corrected_lc5, metadata.corrected_lc10, metadata.corrected_lc15].map((value, index) => <td key={index}>{number(value, 5)}</td>)}</tr>}
      <tr><th>元分析</th>{[metadata.original_lc0, metadata.original_lc5, metadata.original_lc10, metadata.original_lc15].map((value, index) => <td key={index}>{number(value, 5)}</td>)}</tr>
    </tbody></table></details>}
  </section>;
}

function WavePoints({ rows, points, label }: { rows: SnapshotRow[]; points: AlertPoint[]; label: string }) {
  return <div className="m5-alert-point-analysis"><h4>{label}</h4>{rows.map((row) => {
    const values = points.filter((point) => point.alert_timeframe_id === row.timeFrame?.id && point.time_frame === row.frame).sort((first, second) => first.point_order - second.point_order);
    return <details key={row.frame}><summary>{row.label}・{values.length}点</summary><div className="m5-alert-point-scroll">
      <table aria-label={`${label} ${row.label} 最新Wave全ポイント`}><thead><tr>{["順序", "Server", "価格", "Elliott / Sub", "元番号", "pips差", "F %", "FE %", "取得種別", "最新", "基準点"].map((column) => <th key={column}>{column}</th>)}</tr></thead>
        <tbody>{values.map((point) => <tr key={`${row.analysis}-${point.id}`}><td>{point.point_order}</td><td>{text(point.bar_time_text)}</td><td>{number(point.rate, 5)}</td><td>{text(point.elliot_label)}{point.sub_elliot_label && "." + point.sub_elliot_label}</td><td>{text(point.org_elliot_label)}</td><td>{number(point.pips_diff, 1)}</td><td>{flag(point.is_fibonacci_available, number(point.fibonacci_percent, 1), "対象外")}</td><td>{flag(point.is_fibonacci_expansion_available, number(point.fibonacci_expansion_percent, 1), "対象外")}</td><td>{flag(point.is_added_point, "補完", "通常")}</td><td>{flag(point.is_latest, "最新", "—")}</td><td>{flag(point.is_signal_reference, "基準点", "—")}</td></tr>)}</tbody>
      </table>{values.length === 0 && <p>ポイントは未記録です。</p>}
    </div></details>;
  })}</div>;
}

export function M5AlertSnapshot({ detail, timeFrames, points }: M5AlertSnapshotProps) {
  return <SnapshotContent key={`${detail.alert.id}-${correctionStatus(detail.correction)}`} detail={detail} timeFrames={timeFrames} points={points} />;
}

function SnapshotContent({ detail, timeFrames, points }: M5AlertSnapshotProps) {
  const status = correctionStatus(detail.correction);
  const applied = status === "APPLIED";
  const metadata: AlertCorrectionMetadata | null = detail.correction?.metadata ?? null;
  const [view, setView] = useState<View>("selected");
  const [expanded, setExpanded] = useState(false);
  const [changedOnly, setChangedOnly] = useState(false);
  const originalRows = useMemo(() => rowsFor(timeFrames, points, "ORIGINAL"), [timeFrames, points]);
  const correctedRows = useMemo(() => rowsFor(detail.correction?.timeframes ?? [], detail.correction?.points ?? [], "CORRECTED"), [detail.correction]);
  let selectedRows = originalRows;
  if (applied && view !== "original") selectedRows = correctedRows;
  let visibleRows = selectedRows;
  const comparison = applied && view === "comparison";
  if (comparison) visibleRows = frames.flatMap((_frame, index) => [correctedRows[index], originalRows[index]]);
  let shownColumns = columns.filter((column) => expanded || column.summary);
  if (comparison && changedOnly) shownColumns = shownColumns.filter((column) => originalRows.some((row, index) => hasDifference(column, row, correctedRows[index])));
  let primaryLabel = "元の保存分析";
  if (applied) primaryLabel = "補正後（採用）";
  if (status === "NONE") primaryLabel = "元分析（採用）";
  let savedAlertText = detail.alert.alert_text;
  if ((applied || status === "NONE") && metadata) savedAlertText = metadata.selected_alert_text;
  const analyses: Analysis[] = [];
  if (comparison || (applied && view === "selected")) analyses.push("CORRECTED");
  if (comparison || !applied || view === "original") analyses.push("ORIGINAL");
  return <section className="m5-alert-snapshot" aria-label="M5アラート補正スナップショット">
    <div className="m5-alert-context"><strong>M5 ALERT SNAPSHOT</strong><span>JST {text(detail.alert.jst_time_text)}</span><span>Server {text(detail.alert.server_time_text)}</span><span>Spread {number(detail.alert.spread_pips, 1)} pips</span><span>Alert {detail.alert.id} / Run {detail.run?.id}</span></div>
    <div className="m5-alert-status" data-status={status} role="status"><strong>{statusMessage(status)}</strong>
      {applied && metadata && <span className="m5-alert-correction-badge">{frames.find((frame) => frame.id === metadata.correction_time_frame)?.label}方向補正：<span className={sideClass(metadata.original_direction)}>{metadata.original_direction}</span> → <span className={sideClass(metadata.corrected_direction)}>{metadata.corrected_direction}</span></span>}
      {detail.correction?.reason && <small>{detail.correction.reason}</small>}
    </div>
    <section className="m5-alert-decision" aria-label="保存済みエントリー判定"><strong>保存判定：{text(detail.alert.entry_result)}</strong><span>採用結果を固定表示・再判定なし</span><span className={sideClass(detail.alert.side)}>{detail.alert.side}</span><span>Signal / Entry {detail.alert.signal_count} / {detail.alert.entry_count}</span><span>{text(savedAlertText)}</span></section>
    <StopLoss detail={detail} status={status} />
    <details className="m5-alert-extra"><summary>通貨強弱（Alert保存時点）</summary><CurrencyStrengthSnapshotPanel alert={detail.alert} /></details>
    <div className="m5-alert-toolbar"><div role="group" aria-label="分析の表示対象">
      <button type="button" className="secondary-button" aria-pressed={view === "selected"} onClick={() => setView("selected")}>{primaryLabel}</button>
      <button type="button" className="secondary-button" aria-pressed={view === "original"} disabled={!applied} onClick={() => setView("original")}>補正前</button>
      <button type="button" className="secondary-button" aria-pressed={view === "comparison"} disabled={!applied} onClick={() => setView("comparison")}>前後比較</button>
    </div><div>
      <label><input type="checkbox" checked={changedOnly} disabled={!comparison} onChange={(event) => setChangedOnly(event.target.checked)} />差がある列のみ</label>
      <button type="button" className="secondary-button" aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{expanded && "要点のみ"}{!expanded && "すべて表示"}</button>
    </div></div>
    {comparison && changedOnly && shownColumns.length === 0 && <p className="m5-alert-note">表示中の項目に差はありません。比較キーは常に表示します。</p>}
    <div className="m5-alert-grid-scroll" role="region" aria-label="M5アラート全画面グリッド" tabIndex={0}>
      <table className="m5-alert-grid" aria-label="M5アラート7時間足比較"><thead><tr><th className="m5-alert-key-0" scope="col">時間足</th><th className="m5-alert-key-1" scope="col">分析</th>{[...keyColumns, ...shownColumns].map((column, index) => {
        let className = "";
        if (index < keyColumns.length) className = `m5-alert-key-${index + 2}`;
        return <th scope="col" key={column.id} className={className} title={column.label}>{column.label}</th>;
      })}</tr></thead><tbody>{visibleRows.map((row) => {
        const frameIndex = frames.findIndex((frame) => frame.id === row.frame);
        const other = originalRows[frameIndex];
        let pair = correctedRows[frameIndex];
        if (row.analysis === "CORRECTED") pair = other;
        let rowClass = "";
        if (row.frame === 5) rowClass = "m5-alert-current";
        return <tr key={`${row.analysis}-${row.frame}`} data-timeframe={row.label} data-analysis={row.analysis} className={rowClass}>
          <th scope="row" className="m5-alert-key-0">{row.label}{row.frame === 5 && <small>現在足</small>}{row.analysis === "CORRECTED" && metadata?.correction_time_frame === row.frame && <small className="m5-alert-force">方向補正</small>}</th>
          <td className="m5-alert-key-1">{analysisLabel(row.analysis, status)}</td>
          {[...keyColumns, ...shownColumns].map((column, index) => {
            const value = cellText(column, row);
            const classes = [];
            if (index < keyColumns.length) classes.push(`m5-alert-key-${index + 2}`);
            if (column.numeric) classes.push("m5-alert-number");
            if (comparison && hasDifference(column, row, pair)) classes.push("m5-alert-changed");
            let color = sideClass(value);
            if (column.direction) color = sideClass(column.direction(row));
            if (column.numeric && !column.signed) color = "";
            return <td key={column.id} data-column={column.id} className={classes.join(" ")}><span className={color}>{value}</span></td>;
          })}
        </tr>;
      })}</tbody></table>
    </div>
    <p className="m5-alert-note">金色は前後で異なる保存値です。BUYは青、SELLは赤。分析方向とWave方向は別項目です。直前推進波の副次波は保存本文で確認できます。</p>
    <details className="m5-alert-extra"><summary>最新Waveの全ポイント</summary><div className="m5-alert-analysis-panels">{analyses.map((analysis) => {
      let rows = originalRows;
      let values = points;
      if (analysis === "CORRECTED") { rows = correctedRows; values = detail.correction?.points ?? []; }
      return <WavePoints key={analysis} rows={rows} points={values} label={analysisLabel(analysis, status)} />;
    })}</div></details>
    <details className="m5-alert-extra"><summary>保存本文</summary><div className="m5-alert-analysis-panels">{analyses.map((analysis) => {
      let content = metadata?.original_analysis_text;
      if (analysis === "CORRECTED") content = metadata?.corrected_analysis_text;
      return <section key={analysis}><h4>{analysisLabel(analysis, status)}</h4><pre>{text(content)}</pre></section>;
    })}</div></details>
  </section>;
}
