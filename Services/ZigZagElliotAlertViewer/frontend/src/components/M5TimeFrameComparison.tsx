import { useMemo, useState } from "react";
import type { M5TimeFrame } from "../api/m5Types";
import { m5StoredServerTime } from "../lib/m5CaptureQuality";
import { m5Boolean, m5DepthLabel, m5Direction, m5EmaLabel, m5FibonacciLabel, m5FlagLabel, m5Number, m5Text, m5TimeFrameSlots, m5WaveLabel } from "../lib/m5TimeFrame";

const STORAGE_KEY = "m5Observation.comparisonSections.v1";
type Section = "point" | "ohlc" | "indicators";
type Sections = Record<Section, boolean>;
const SECTION_LABELS: Record<Section, string> = { point: "最新ZigZag Point", ohlc: "OHLC", indicators: "指標詳細" };

function readSections(): Sections {
  const initial: Sections = { point: false, ohlc: false, indicators: false };
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    if (saved && typeof saved === "object") {
      for (const key of Object.keys(initial) as Section[]) initial[key] = (saved as Record<string, unknown>)[key] === true;
    }
  } catch { /* Storage is optional. */ }
  return initial;
}

function Field({ label, value }: { label: string; value: unknown }) {
  return <div className="detail-field"><span>{label}</span><strong>{m5Text(value)}</strong></div>;
}

function PointFields({ row }: { row: M5TimeFrame }) {
  return <div className="m5-extra-fields">
    <Field label="最新点 JST" value={row.latest_point_jst_time_text} />
    <Field label="最新点 Server" value={row.latest_point_time_text} />
    <Field label="最新点価格" value={m5Number(row.latest_point_rate, 5)} />
    <Field label="Peak / Bottom" value={m5FlagLabel(row.latest_point_is_peak, "Peak", "Bottom")} />
    <Field label="波の開始からの本数" value={m5Number(row.latest_point_wave_bars_from_start, 0, "本")} />
    <Field label="pips差" value={m5Number(row.latest_point_pips_diff, 1, " pips")} />
    <Field label="F / FE（元番号に対応）" value={m5FibonacciLabel(row)} />
    <Field label="Depth Zone" value={m5DepthLabel(row)} />
    <Field label="元番号 → 表示番号" value={`${m5Text(row.latest_point_org_elliot_label)} [${m5Number(row.latest_point_org_elliot_index, 0)}] → ${m5Text(row.latest_elliot_label)} [${m5Number(row.latest_elliot_index, 0)}]`} />
    <Field label="補正" value={m5FlagLabel(row.latest_point_is_correct, "補正済", "未補正")} />
    <Field label="波の表記" value={m5FlagLabel(row.latest_point_is_elliot_alphabet, "Alphabet波", "数字波")} />
    <Field label="Bar index" value={m5Number(row.latest_point_bar_index, 0)} />
    <Field label="次の点 Server" value={m5StoredServerTime(row.latest_point_time_next === 0 ? null : row.latest_point_time_next)} />
    <Field label="保存ポイント数" value={m5Number(row.point_count, 0)} />
    <Field label="Wave数 / 最新index" value={`${m5Number(row.wave_count, 0)} / ${m5Number(row.latest_wave_index, 0)}`} />
    <Field label="前回Wave最終（保存値）" value={row.previous_last_elliot_label} />
  </div>;
}

function OhlcFields({ row }: { row: M5TimeFrame }) {
  return <table className="m5-ohlc"><thead><tr><th>OHLC</th>{["Open", "High", "Low", "Close"].map((label) => <th key={label}>{label}</th>)}</tr></thead>
    <tbody>{(["previous", "current"] as const).map((prefix) => <tr key={prefix}><th>{prefix === "previous" ? "直前確定足" : "取得時点の形成中足"}</th>
      {(["open", "high", "low", "close"] as const).map((field) => <td key={field}>{m5Number(row[`${prefix}_${field}`], 5)}</td>)}
    </tr>)}</tbody></table>;
}

function IndicatorFields({ row }: { row: M5TimeFrame }) {
  const emaFields: Array<[string, keyof M5TimeFrame, number, string]> = [
    ["EMA200 Close1", "ema200_close1", 5, ""], ["EMA200 Shift1", "ema200_shift1", 5, ""],
    ["EMA200比較値", "ema200_compare", 5, ""], ["EMA200終値位置 code", "ema200_close_position", 0, ""],
    ["EMA200傾き code", "ema200_slope_direction", 0, ""], ["EMA200傾き", "ema200_slope_pips", 1, " pips"],
    ["EMA200終値距離", "ema200_close_diff_pips", 1, " pips"], ["EMA200上昇本数", "ema200_up_count", 0, ""],
    ["EMA200下降本数", "ema200_down_count", 0, ""], ["EMA200 Trend Count", "ema200_trend_count", 0, ""],
  ];
  return <div className="m5-extra-fields">
    {emaFields.map(([label, field, digits, unit]) => <Field key={field} label={label} value={row.time_frame === 49153 ? "対象外（MN1は計算省略）" : m5Number(row[field], digits, unit)} />)}
    <Field label="EMA30 / EMA60" value={`${m5Number(row.ema30, 5)} / ${m5Number(row.ema60, 5)}`} />
    <Field label="EMA30-60距離" value={m5Number(row.ema30_ema60_diff_pips, 1, " pips")} />
    <Field label="GMMA Trend / Cross" value={`${m5Number(row.gmma_trend_count, 0)} / ${m5Number(row.gmma_cross_count, 0)}`} />
    <Field label="Oscillator方向 / Count" value={`${m5Direction(row.is_oscillator_buy)} / ${m5Number(row.oscillator_count, 0)}`} />
    {(["short", "middle", "long"] as const).map((period) => <Field key={period} label={`Stochastic ${period} Count / Main / Signal`}
      value={`${m5Number(row[`stochastic_${period}_count`], 0)} / ${m5Number(row[`stochastic_${period}_main`], 2)} / ${m5Number(row[`stochastic_${period}_signal`], 2)}`} />)}
    {(["618", "1000", "1272", "1618", "2000"] as const).map((level) => <Field key={level} label={`FE ${Number(level) / 10}%価格`}
      value={m5Boolean(row.is_fibo_expansion_available) === true ? m5Number(row[`fe${level}_price`], 5) : m5FlagLabel(row.is_fibo_expansion_available, "取得済", "利用不可")} />)}
    <Field label="FE200距離" value={m5Boolean(row.is_fibo_expansion_available) === true ? m5Number(row.distance_to_fe2000_pips, 1, " pips") : "利用不可・未記録"} />
  </div>;
}

export function M5TimeFrameComparison({ timeFrames }: { timeFrames: readonly M5TimeFrame[]; styleNonce?: string }) {
  const { slots, warnings } = useMemo(() => m5TimeFrameSlots(timeFrames), [timeFrames]);
  const [sections, setSections] = useState(readSections);
  function toggle(section: Section) {
    const next = { ...sections, [section]: !sections[section] };
    setSections(next);
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(next)); } catch { /* Preserve the in-memory choice. */ }
  }
  return <section className="detail-section" aria-label="M5時間足比較">
    <h3 className="eyebrow">TIMEFRAME COMPARISON</h3>
    {warnings.length > 0 && <div className="m5-warning" role="alert"><strong>足構成を要確認（正常 {slots.filter((slot) => !slot.warning).length}/7足）</strong><ul>{warnings.map((warning, index) => <li key={`${index}:${warning}`}>{warning}</li>)}</ul></div>}
    <div className="m5-comparison-scroll" role="region" aria-label="7時間足比較表" tabIndex={0}>
      <table className="m5-comparison"><thead><tr>{["時間足", "分析方向", "Elliott / 副次波", "Wave方向", "Wave状態・種別", "ZigZag Point", "EMA200", "GMMA Trend/Cross", "Stochastic", "ATR14"].map((label) => <th scope="col" key={label}>{label}</th>)}</tr></thead>
        <tbody>{slots.map(({ id, label, timeFrame: row, warning }) => <tr key={id} data-timeframe={label} className={id === 5 ? "m5-anchor-row" : ""}>
          <th scope="row">{label}{id === 5 && <small>基準足</small>}{warning && <small className="m5-warning" title={warning}>要確認</small>}</th>
          {!row ? <td colSpan={9}>{warning.includes("重複") ? "複数記録・要確認" : "未記録"}</td> : <>
            <td><span className={`badge ${m5Direction(row.is_buy).toLowerCase()}`}>{m5Direction(row.is_buy)}</span></td>
            <td>{m5WaveLabel(row)}</td><td>{m5FlagLabel(row.is_wave_uptrend, "▲ 上昇", "▼ 下降")}</td>
            <td>{m5FlagLabel(row.is_wave_confirmed, "確定", "形成中")} / {m5FlagLabel(row.is_wave_motive, "推進波", "修正波")}</td>
            <td>{m5FlagLabel(row.latest_point_is_added, "追加ポイント", "通常")}</td><td>{m5EmaLabel(row)}</td>
            <td>{m5Number(row.gmma_trend_count, 0)} / {m5Number(row.gmma_cross_count, 0)}</td>
            <td>{m5Text(row.stochastic_main_order_text)} / {m5Text(row.stochastic_main_direction_text)}</td><td>{m5Number(row.atr14_pips, 1, " pips")}</td>
          </>}
        </tr>)}</tbody></table>
    </div>
    <p className="m5-note">分析方向（is_buy）とWave方向は別項目です。Waveの確定は保存時点の状態で、将来の再分析による変化を保証しません。</p>
    <div className="m5-comparison-options" role="group" aria-label="M5比較の詳細項目">
      {(Object.keys(SECTION_LABELS) as Section[]).map((section) => <button key={section} type="button" className="secondary-button" aria-pressed={sections[section]} onClick={() => toggle(section)}>{SECTION_LABELS[section]}</button>)}
    </div>
    {sections.ohlc && <p className="m5-note">現在足OHLCは取得時点の途中経過です。後に確定したM5・上位足のOHLCと同一とは限りません。</p>}
    {Object.values(sections).some(Boolean) && <div className="m5-extra-timeframes">{slots.map(({ id, label, timeFrame: row }) => <article className="m5-extra-timeframe" key={id} aria-label={`${label} 保存値の詳細`}>
      <h4>{label}</h4>{!row ? <p>未記録・足構成を要確認</p> : <>
        {sections.point && <><h5>最新ZigZag Point</h5><PointFields row={row} /></>}
        {sections.ohlc && <OhlcFields row={row} />}
        {sections.indicators && <><h5>指標詳細</h5><IndicatorFields row={row} /></>}
      </>}
    </article>)}</div>}
  </section>;
}
