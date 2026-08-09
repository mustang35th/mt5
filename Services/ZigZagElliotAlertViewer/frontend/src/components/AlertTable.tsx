import type { AlertListItem, AlertSort, SortOrder } from "../api/types";
import { displayValue, formatNumber, sideClass } from "../lib/format";

interface AlertTableProps {
  items: AlertListItem[];
  sort: AlertSort;
  order: SortOrder;
  onSort: (sort: AlertSort) => void;
}

interface SortHeaderProps {
  label: string;
  value: AlertSort;
  activeSort: AlertSort;
  order: SortOrder;
  onSort: (sort: AlertSort) => void;
}

function SortHeader({ label, value, activeSort, order, onSort }: SortHeaderProps) {
  const active = activeSort === value;
  return (
    <th scope="col" aria-sort={active ? (order === "asc" ? "ascending" : "descending") : "none"}>
      <button className={`sort-button${active ? ` active ${order}` : ""}`} type="button" onClick={() => onSort(value)}>
        {label}
      </button>
    </th>
  );
}

function Badge({ text, variant = "neutral" }: { text: string; variant?: string }) {
  return <span className={`badge ${variant}`}>{text}</span>;
}

function TimeFrameSequence({ alert }: { alert: AlertListItem }) {
  const values: Array<[string, string | null]> = [
    ["MN1", alert.mn1_side],
    ["W1", alert.w1_side],
    ["D1", alert.d1_side],
    ["H4", alert.h4_side],
    ["H1", alert.h1_side],
  ];
  return (
    <div className="tf-sequence">
      {values.map(([timeFrame, side]) => {
        const normalized = String(side || "NONE").toUpperCase();
        return (
          <span className={`tf-chip ${sideClass(normalized)}`} key={timeFrame}>
            <small>{timeFrame}</small>
            <strong>{normalized === "NONE" ? "—" : normalized}</strong>
          </span>
        );
      })}
    </div>
  );
}

function AlignmentBadge({ alert }: { alert: AlertListItem }) {
  if (alert.is_w1_aligned === true) return <Badge text="一致" variant="good" />;
  if (alert.is_w1_aligned === false) return <Badge text="不一致" variant="warn" />;
  return <Badge text="不明" />;
}

export function AlertTable({ items, sort, order, onSort }: AlertTableProps) {
  return (
    <div className="table-wrap">
      <table>
        <caption className="visually-hidden">ZigZagElliotアラート検索結果</caption>
        <thead>
          <tr>
            <SortHeader label="JST日時" value="jst_time" activeSort={sort} order={order} onSort={onSort} />
            <SortHeader label="通貨" value="symbol_name" activeSort={sort} order={order} onSort={onSort} />
            <SortHeader label="方向" value="side" activeSort={sort} order={order} onSort={onSort} />
            <th scope="col">判定</th>
            <SortHeader label="構造・波動" value="h1_structure_rank" activeSort={sort} order={order} onSort={onSort} />
            <th scope="col">MN1 → H1 分析方向</th>
            <SortHeader label="W1一致" value="is_w1_aligned" activeSort={sort} order={order} onSort={onSort} />
            <SortHeader label="Risk / Spread" value="risk_pips" activeSort={sort} order={order} onSort={onSort} />
            <SortHeader label="ENTRY" value="entry_result" activeSort={sort} order={order} onSort={onSort} />
          </tr>
        </thead>
        <tbody>
          {items.map((alert) => (
            <tr key={alert.id}>
              <td>
                <span className="date-main">{displayValue(alert.jst_time_text)}</span>
                <span className="date-sub">Server {displayValue(alert.server_time_text)}</span>
              </td>
              <td>
                <span className="symbol">{alert.symbol_name}</span>
                <span className="subtext">Run {alert.run_id} / {alert.time_frame_text}</span>
              </td>
              <td><Badge text={alert.side} variant={sideClass(alert.side)} /></td>
              <td>
                <strong>{alert.strategy} {alert.signal_count}/{alert.entry_count}</strong>
                <span className="subtext">{displayValue(alert.alert_title)}</span>
              </td>
              <td>
                <Badge text={`${displayValue(alert.h1_structure_rank)}${alert.is_h1_structure_late ? "-LATE" : ""}`} />
                <span className="subtext">wave {displayValue(alert.current_elliot_label)}</span>
              </td>
              <td><TimeFrameSequence alert={alert} /></td>
              <td>
                <AlignmentBadge alert={alert} />
                <span className="subtext">W1 {displayValue(alert.w1_side)}</span>
              </td>
              <td className="metric-stack">
                <span>{formatNumber(alert.risk_pips)} pips</span>
                <span className="subtext">spread {formatNumber(alert.spread_pips)} pips</span>
              </td>
              <td><Badge text={displayValue(alert.entry_result)} variant={alert.is_entry ? "good" : "neutral"} /></td>
            </tr>
          ))}
        </tbody>
      </table>
      {items.length === 0 && (
        <div className="empty-state">
          <strong>該当するアラートはありません</strong>
          <span>検索条件を変更してください。</span>
        </div>
      )}
    </div>
  );
}
