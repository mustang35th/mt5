import { useLayoutEffect, useMemo, useRef, useState, type RefObject } from "react";
import type { M5TimeFrame } from "../api/m5Types";
import { m5StoredServerTime } from "../lib/m5CaptureQuality";
import { m5Boolean, m5DepthLabel, m5Direction, m5EmaLabel, m5FibonacciLabel, m5FlagLabel, m5Number, m5PreviousMotiveSubLabel, m5Text, m5TimeFrameSlots, m5WaveLabel } from "../lib/m5TimeFrame";
import "./M5TimeFrameSnapshotGrid.css";

interface Column { label: string; tooltip?: string; summary?: boolean; minWidth?: number; numeric?: boolean; signed?: boolean; colorValue?: (row: M5TimeFrame) => string; value: (row: M5TimeFrame) => string }
interface Group { id: string; label: string; columns: Column[] }
export interface M5GridScroll { left: number; top: number }

function columnHeader(label: string) {
  const prefix = ["直前推進波の", "最新点の", "F / FE", "Oscillator ", "Stochastic ", "GMMA "].find((value) => label.startsWith(value));
  if (!prefix) return label;
  return <>{[label.slice(0, prefix.length), label.slice(prefix.length)].map((line, index) =>
    <span className="m5-snapshot-header-line" key={index}>{line}</span>)}</>;
}

const signedFields = new Set<keyof M5TimeFrame>([
  "oscillator_count", "stochastic_short_count", "stochastic_middle_count", "stochastic_long_count",
  "gmma_trend_count", "gmma_cross_count", "ema200_trend_count",
  "ema200_slope_pips", "ema200_close_diff_pips", "ema30_ema60_diff_pips",
]);

function numberColumn(label: string, field: keyof M5TimeFrame, digits = 0, unit = ""): Column {
  const signed = signedFields.has(field);
  return { label, numeric: true, signed, value: (row) => m5Number(row[field], digits, unit, signed) };
}

function cellColor(column: Column, value: string, row: M5TimeFrame | null): string | undefined {
  if (column.colorValue) value = row ? column.colorValue(row) : "";
  if (value === "BUY" || value.startsWith("▲") || (column.signed && value.startsWith("+"))) return "m5-buy";
  if (value === "SELL" || value.startsWith("▼") || (column.signed && value.startsWith("-"))) return "m5-sell";
  return undefined;
}
function textColumn(label: string, field: keyof M5TimeFrame): Column {
  return { label, value: (row) => m5Text(row[field]) };
}
function flagColumn(label: string, field: keyof M5TimeFrame, yes: string, no: string): Column {
  return { label, value: (row) => m5FlagLabel(row[field], yes, no) };
}
function feValue(row: M5TimeFrame, field: keyof M5TimeFrame, digits: number, unit = ""): string {
  if (m5Boolean(row.is_fibo_expansion_available) !== true) {
    return m5FlagLabel(row.is_fibo_expansion_available, "取得済", "利用不可");
  }
  return m5Number(row[field], digits, unit);
}

const groups: Group[] = [
  { id: "keys", label: "比較キー", columns: [
    textColumn("時間足", "time_frame_text"),
    { label: "分析方向", value: (row) => m5Direction(row.is_buy) },
    { label: "EMA200方向", value: m5EmaLabel },
    { label: "Elliott / Sub", value: m5WaveLabel, colorValue: (row) => m5Direction(row.is_buy) },
  ] },
  { id: "wave", label: "波動", columns: [
    { ...flagColumn("Wave状態", "is_wave_confirmed", "確定", "形成中"), summary: true, minWidth: 90,
      tooltip: "確定：最新Waveが確定と判定されています。\n形成中：最新Waveは未確定です。\n未記録：判別できる保存情報がありません。\n\n各時間足の観測時点の状態です。\n直前推進波の副次波自体の\n確定・未確定を示すものではありません。" },
    { label: "直前推進波の副次波", summary: true, minWidth: 150, value: (row) => m5PreviousMotiveSubLabel(row.previous_motive_sub_elliot_index),
      tooltip: "現在2・3波：1波の副次波を確認\n現在4・5波：3波の副次波を確認\n\n該当なし：対象の副次波なし、または対象外\n未記録：保存情報なし\n\n観測時点の分析結果です。\n前のWaveの情報ではありません。" },
    { ...flagColumn("最新点の取得種別", "latest_point_is_added", "補完", "通常"), summary: true,
      tooltip: "通常：ZigZagから取得した最新ポイント。\n補完：ZigZagから取得できず、\n　　　ロジックで補完した最新ポイント。\n未記録：判別できる保存情報がありません。\n\nWaveの確定／形成中とは別の情報です。" },
    flagColumn("Wave方向", "is_wave_uptrend", "▲ 上昇", "▼ 下降"),
    flagColumn("Wave種別", "is_wave_motive", "推進波", "修正波"),
    numberColumn("Wave数", "wave_count"), numberColumn("最新Wave index", "latest_wave_index"),
    textColumn("前回Wave最終", "previous_last_elliot_label"), numberColumn("保存Point数", "point_count"),
  ] },
  { id: "point", label: "最新ZigZag Point", columns: [
    { label: "F / FE（元番号に対応）", summary: true, minWidth: 140, value: m5FibonacciLabel },
    { ...numberColumn("pips差", "latest_point_pips_diff", 1, " pips"), summary: true },
    { ...numberColumn("最新点価格", "latest_point_rate", 5), summary: true },
    textColumn("最新点 JST", "latest_point_jst_time_text"), textColumn("最新点 Server", "latest_point_time_text"),
    flagColumn("Peak / Bottom", "latest_point_is_peak", "Peak", "Bottom"),
    numberColumn("波の開始からの本数", "latest_point_wave_bars_from_start", 0, "本"),
    { label: "Depth Zone", value: m5DepthLabel },
    { label: "元番号 → 表示番号", value: (row) => `${m5Text(row.latest_point_org_elliot_label)} [${m5Number(row.latest_point_org_elliot_index, 0)}] → ${m5Text(row.latest_elliot_label)} [${m5Number(row.latest_elliot_index, 0)}]` },
    flagColumn("補正", "latest_point_is_correct", "補正済", "未補正"),
    flagColumn("波の表記", "latest_point_is_elliot_alphabet", "Alphabet波", "数字波"), numberColumn("Bar index", "latest_point_bar_index"),
    { label: "次の点 Server", value: (row) => m5StoredServerTime(row.latest_point_time_next === 0 ? null : row.latest_point_time_next) },
  ] },
  { id: "ohlc", label: "OHLC", columns: (["previous", "current"] as const).flatMap((period) =>
    (["open", "high", "low", "close"] as const).map((field) => numberColumn(`${period === "previous" ? "直前確定足" : "取得時点の形成中足"} ${field[0].toUpperCase()}${field.slice(1)}`, `${period}_${field}`, 5))) },
  { id: "ema", label: "EMA200", columns: [
    numberColumn("Close1", "ema200_close1", 5), numberColumn("Shift1", "ema200_shift1", 5), numberColumn("比較値", "ema200_compare", 5),
    numberColumn("終値位置 code", "ema200_close_position"), numberColumn("傾き方向 code", "ema200_slope_direction"),
    numberColumn("傾き pips", "ema200_slope_pips", 1), numberColumn("終値距離 pips", "ema200_close_diff_pips", 1),
    numberColumn("上昇本数", "ema200_up_count"), numberColumn("下降本数", "ema200_down_count"), numberColumn("Trend Count", "ema200_trend_count"),
  ].map((column) => ({ ...column, value: (row: M5TimeFrame) => row.time_frame === 49153 ? "対象外（MN1）" : column.value(row) })) },
  { id: "indicators", label: "その他指標", columns: [
    { ...numberColumn("Oscillator Count", "oscillator_count"), summary: true },
    ...(["short", "middle", "long"] as const).map((period, index) => ({
      ...numberColumn(`Stochastic ${["短期", "中期", "長期"][index]} Count`, `stochastic_${period}_count`), summary: true,
    })),
    { ...numberColumn("GMMA Trend", "gmma_trend_count"), summary: true },
    { ...numberColumn("GMMA Cross", "gmma_cross_count"), summary: true },
    numberColumn("EMA30", "ema30", 5), numberColumn("EMA60", "ema60", 5), numberColumn("EMA30–60距離 pips", "ema30_ema60_diff_pips", 1),
    { label: "Oscillator方向", value: (row) => m5Direction(row.is_oscillator_buy) },
    ...(["short", "middle", "long"] as const).flatMap((period, index) => [
      numberColumn(`Stochastic ${["短期", "中期", "長期"][index]} Main`, `stochastic_${period}_main`, 2),
      numberColumn(`Stochastic ${["短期", "中期", "長期"][index]} Signal`, `stochastic_${period}_signal`, 2),
    ]),
    textColumn("Stochastic順序", "stochastic_main_order_text"), textColumn("Stochastic方向", "stochastic_main_direction_text"),
    numberColumn("ATR14 pips", "atr14_pips", 1),
  ] },
  { id: "fe", label: "FE", columns: [
    flagColumn("FE利用可否", "is_fibo_expansion_available", "利用可", "利用不可"),
    ...(["618", "1000", "1272", "1618", "2000"] as const).map((level) => ({
      label: `FE ${Number(level) / 10}%価格`, numeric: true, value: (row: M5TimeFrame) => feValue(row, `fe${level}_price`, 5),
    })),
    { label: "FE200距離 pips", numeric: true, value: (row) => feValue(row, "distance_to_fe2000_pips", 1) },
  ] },
];

const summaryGroups = groups.map((group) => ({
  ...group, columns: group.columns.filter((column) => group.id === "keys" || column.summary),
})).filter((group) => group.columns.length > 0);

export function M5TimeFrameSnapshotGrid({ timeFrames, expanded, onExpandedChange, scrollPosition }: {
  timeFrames: readonly M5TimeFrame[];
  expanded: boolean;
  onExpandedChange: (expanded: boolean) => void;
  scrollPosition: RefObject<M5GridScroll>;
}) {
  const { slots, warnings } = useMemo(() => m5TimeFrameSlots(timeFrames), [timeFrames]);
  const scroller = useRef<HTMLDivElement>(null);
  const [jump, setJump] = useState<string | null>(null);
  const shownGroups = expanded ? groups : summaryGroups;
  useLayoutEffect(() => {
    if (scroller.current) {
      scroller.current.scrollLeft = scrollPosition.current.left;
      scroller.current.scrollTop = scrollPosition.current.top;
    }
  }, [scrollPosition]);
  useLayoutEffect(() => {
    if (!jump || !scroller.current) return;
    const target = scroller.current.querySelector<HTMLElement>(`[data-group="${jump}"]`);
    const pinned = scroller.current.querySelector<HTMLElement>(".m5-snapshot-key-group");
    const first = scroller.current.querySelector<HTMLElement>(".m5-snapshot-key-0");
    if (target && pinned && first) {
      const width = window.matchMedia("(max-width: 760px)").matches ? first.offsetWidth : pinned.offsetWidth;
      scroller.current.scrollLeft += target.getBoundingClientRect().left - scroller.current.getBoundingClientRect().left - width;
      scrollPosition.current.left = scroller.current.scrollLeft;
    }
    setJump(null);
  }, [jump, expanded, scrollPosition]);
  return <section className="detail-section m5-snapshot-section" aria-label="M5全画面時間足比較">
    <div className="m5-snapshot-toolbar">
      <nav aria-label="M5詳細項目へ移動">{groups.slice(1).map((group) => <button className="secondary-button" type="button" key={group.id}
        onClick={() => { if (!summaryGroups.some((shownGroup) => shownGroup.id === group.id)) onExpandedChange(true); setJump(group.id); }}>{group.label}</button>)}</nav>
      <button className="secondary-button" type="button" aria-expanded={expanded} onClick={() => onExpandedChange(!expanded)}>{expanded ? "要点のみ" : "すべて表示"}</button>
    </div>
    {warnings.length > 0 && <div className="m5-warning" role="alert"><strong>足構成を要確認</strong><ul>{warnings.map((warning, index) => <li key={index}>{warning}</li>)}</ul></div>}
    <div className="m5-snapshot-scroll" ref={scroller} role="region" aria-label="M5全画面グリッド" tabIndex={0}
      onScroll={(event) => { scrollPosition.current = { left: event.currentTarget.scrollLeft, top: event.currentTarget.scrollTop }; }}>
      <table className="m5-snapshot-table" aria-label="M5詳細7時間足比較">
        <thead><tr>{shownGroups.map((group, index) => <th key={group.id} scope="colgroup" colSpan={group.columns.length}
          data-group={group.id} className={index === 0 ? "m5-snapshot-key-group" : undefined}>{group.label}</th>)}</tr>
          <tr>{shownGroups.flatMap((group, groupIndex) => group.columns.map((column, index) => <th key={`${group.id}-${index}`} scope="col"
            style={{ minWidth: column.minWidth ?? (column.summary ? 110 : undefined) }}
            className={groupIndex === 0 ? `m5-snapshot-key-${index}` : undefined} aria-label={column.label} title={column.tooltip} aria-description={column.tooltip}>{columnHeader(column.label)}</th>))}</tr></thead>
        <tbody>{slots.map((slot) => <tr key={slot.id} data-timeframe={slot.label} className={slot.id === 5 ? "m5-snapshot-anchor" : undefined}>
          {shownGroups.flatMap((group, groupIndex) => group.columns.map((column, index) => {
            const value = groupIndex === 0 && index === 0 ? slot.label : slot.timeFrame ? column.value(slot.timeFrame) : "未記録・足構成を要確認";
            return <td key={`${group.id}-${index}`} className={groupIndex === 0 ? `m5-snapshot-key-${index}` : column.numeric ? "m5-snapshot-number" : undefined}
              style={{ minWidth: column.minWidth ?? (column.summary ? 110 : undefined) }}>
              <span className={cellColor(column, value, slot.timeFrame)}>{value}</span>
              {groupIndex === 0 && index === 0 && <>{slot.id === 5 && <small>基準足</small>}{slot.warning && <small className="m5-warning">要確認</small>}</>}
            </td>;
          }))}
        </tr>)}</tbody>
      </table>
    </div>
    <p className="m5-note">7時間足・M5基準。分析方向とWave方向は別項目です。形成中足のOHLCは取得時点の保存値です。</p>
  </section>;
}
