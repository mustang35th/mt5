import type { AlertListItem } from "../api/types";
import "./CurrencyStrengthCell.css";

interface SavedPeriod {
  label: string;
  baseRank: number | null;
  quoteRank: number | null;
  difference: number | null;
  direction: "BUY" | "SELL" | "同順位" | "不明";
  issue: string;
}

function savedInteger(fromValue: unknown, fromMinimum: number, fromMaximum: number): number | null {
  if (typeof fromValue !== "number" || !Number.isInteger(fromValue)
      || fromValue < fromMinimum || fromValue > fromMaximum) {
    return null;
  }

  return fromValue;
}

function savedText(fromValue: unknown): string {
  if (typeof fromValue === "string" && fromValue.trim() !== "") {
    return fromValue.trim();
  }

  return "—";
}

function signedDifference(fromValue: number | null): string {
  if (fromValue === null) return "—";
  if (fromValue > 0) return `+${fromValue}`;

  return String(fromValue);
}

function savedPeriod(fromLabel: string, fromBase: unknown, fromQuote: unknown,
  fromDifference: unknown): SavedPeriod {
  const baseRank = savedInteger(fromBase, 1, 8);
  const quoteRank = savedInteger(fromQuote, 1, 8);
  const difference = savedInteger(fromDifference, -7, 7);
  let issue = "";
  let direction: SavedPeriod["direction"] = "不明";
  if (baseRank === null || quoteRank === null || difference === null) {
    issue = "保存値不足・不正";
  } else if (quoteRank - baseRank !== difference) {
    issue = "順位と保存差が不整合";
  } else if (difference > 0) {
    direction = "BUY";
  } else if (difference < 0) {
    direction = "SELL";
  } else {
    direction = "同順位";
  }

  return { label: fromLabel, baseRank, quoteRank, difference, direction, issue };
}

/** MT5の保存カレンダー値を、ローカル時差を加えずSRVとして表示する。 */
function savedServerTime(fromValue: unknown): string {
  const seconds = savedInteger(fromValue, 1, Number.MAX_SAFE_INTEGER);
  if (seconds === null) return "—";

  const date = new Date(seconds * 1000);
  if (!Number.isFinite(date.getTime()) || date.getUTCFullYear() > 9999) return "—";

  const year = String(date.getUTCFullYear()).padStart(4, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hour = String(date.getUTCHours()).padStart(2, "0");
  const minute = String(date.getUTCMinutes()).padStart(2, "0");
  const second = String(date.getUTCSeconds()).padStart(2, "0");

  return `${year}/${month}/${day} ${hour}:${minute}:${second} SRV`;
}

function Rank({ rank }: { rank: number | null }) {
  if (rank === 1 || rank === 8) return <strong>{rank}</strong>;

  return <span>{rank ?? "—"}</span>;
}

/** 保存時の2期間の方向と順位を示す。エントリー条件の再評価は行わない。 */
export function CurrencyStrengthCell({ alert }: { alert: AlertListItem }) {
  const periods = [
    savedPeriod("長中期", alert.base_long_medium_rank, alert.quote_long_medium_rank,
      alert.long_medium_rank_difference),
    savedPeriod("中短期", alert.base_medium_short_rank, alert.quote_medium_short_rank,
      alert.medium_short_rank_difference),
  ];
  const available = alert.is_currency_strength_available === true;
  let status = "未記録";
  let variant = "unavailable";
  if (alert.is_currency_strength_available === false) {
    status = "未取得";
  } else if (available) {
    if (periods.some((period) => period.issue !== "")) {
      status = "不明";
    } else if (periods.every((period) => period.direction === "BUY")) {
      status = "BUY一致";
      variant = "buy";
    } else if (periods.every((period) => period.direction === "SELL")) {
      status = "SELL一致";
      variant = "sell";
    } else {
      status = "方向混在";
      variant = "mixed";
    }
  }

  const targetTime = savedInteger(alert.currency_strength_target_m5_bar_time, 1, Number.MAX_SAFE_INTEGER);
  const actualTime = savedInteger(alert.currency_strength_m5_bar_time, 1, Number.MAX_SAFE_INTEGER);
  const targetText = savedServerTime(targetTime);
  const actualText = savedServerTime(actualTime);
  const isStale = targetText !== "—" && actualText !== "—" && targetTime !== actualTime;
  let freshnessText = "対象M5と実M5は一致（保存時点）";
  if (targetText === "—" || actualText === "—") {
    freshnessText = "時刻未記録";
  } else if (isStale) {
    freshnessText = "古い（対象M5と実M5が不一致）";
  }

  const baseCurrency = savedText(alert.base_currency);
  const quoteCurrency = savedText(alert.quote_currency);
  const description = [
    `通貨強弱（保存時）：${status}`,
    `基軸：${baseCurrency} ／ 決済：${quoteCurrency}`,
    ...periods.map((period) => {
      let direction = "利用不可";
      if (available) direction = period.direction;
      let text = `${period.label}：${baseCurrency} ${period.baseRank ?? "—"}位 / `
        + `${quoteCurrency} ${period.quoteRank ?? "—"}位 差${signedDifference(period.difference)} ${direction}`;
      if (period.issue !== "") text += `（${period.issue}）`;

      return text;
    }),
    "方向は両期間の比較です。アラートの売買方向との一致やENTRY成立を保証しません。",
    "差は決済通貨順位−基軸通貨順位。正はBUY、負はSELL、0は同順位。",
    `取得元：${savedText(alert.currency_strength_source_mode)}`,
    `対象M5：${targetText}`,
    `実M5：${actualText}`,
    `時刻照合：${freshnessText}`,
    `計算方式：${savedText(alert.currency_strength_calculation_version)}`,
  ].join("\n");

  return (
    <span className={`currency-strength-cell ${variant}`} title={description} aria-label={description}>
      <span className="currency-strength-cell-status">
        <span>{status}</span>
        {isStale && <span className="currency-strength-cell-stale">古い</span>}
      </span>
      {periods.map((period) => (
        <span key={period.label} className="currency-strength-cell-period">
          <span className="currency-strength-cell-period-label">{period.label}</span>
          <span className="currency-strength-cell-ranks">
            <Rank rank={period.baseRank} /><span> / </span><Rank rank={period.quoteRank} />
          </span>
          <span className="currency-strength-cell-difference">差{signedDifference(period.difference)}</span>
        </span>
      ))}
    </span>
  );
}
