import type { M5CurrencyStrength } from "../api/m5Types";
import { m5Number } from "../lib/m5TimeFrame";
import { m5StoredServerTime } from "../lib/m5CaptureQuality";
import "./M5CurrencyStrengthPanel.css";

const HELP = "観測と同じM5開始時刻・実行モード・サーバー・口座の完全集計を参照。\n長中期：MN1・W1・D1・H4・H1\n中短期：D1・H4・H1・M15・M5\n順位は小さいほど強い。順位差＝右通貨順位−左通貨順位。\n＋はBUY、−はSELL、0は同順位。\nエントリー判定ではなく、別DBを参照した参考情報です。";
const STATUS: Record<M5CurrencyStrength["status"], string> = {
  FOUND: "時刻一致", NOT_CONFIGURED: "参照DB未設定", DATABASE_NOT_FOUND: "参照DBなし",
  IDENTITY_UNAVAILABLE: "照合情報なし", UNSUPPORTED_SYMBOL: "対象外の通貨ペア",
  RECORD_NOT_FOUND: "該当なし", AMBIGUOUS: "集計を一意に特定できません",
  INVALID_DATA: "順位データ不正", ERROR: "通貨強弱の取得失敗",
};

/** 観測時刻に一致する別DBの通貨強弱を、Entry判定と分けて表示する。 */
export function M5CurrencyStrengthPanel({ snapshot, direction }: {
  snapshot?: M5CurrencyStrength;
  direction: "BUY" | "SELL" | "不明";
}) {
  const available = snapshot?.status === "FOUND" && snapshot.periods.length === 2;
  const periods = available ? snapshot.periods : [];
  const aligned = periods.length === 2 && periods.every((period) => period.direction === direction);
  const opposed = periods.length === 2 && direction !== "不明"
    && periods.every((period) => period.direction === (direction === "BUY" ? "SELL" : "BUY"));
  let comparison = "混在";
  if (direction === "不明") comparison = "M5方向不明";
  else if (aligned) comparison = "M5方向と一致";
  else if (opposed) comparison = "M5方向と逆";
  else if (periods.every((period) => period.direction === "TIE")) comparison = "同順位";
  const comparisonColor = aligned ? direction.toLowerCase() : opposed ? (direction === "BUY" ? "sell" : "buy") : "neutral";
  return <section className="m5-currency-strength" aria-label="通貨強弱（観測時刻・別DB参照）">
    <div className="m5-currency-heading">
      <h3 title={HELP}>通貨強弱 <small>観測時刻・別DB参照</small></h3>
      {available ? <span className={`m5-currency-direction ${comparisonColor}`}>{comparison}</span>
        : <span className="m5-currency-unavailable">{snapshot ? STATUS[snapshot.status] : "未取得"}</span>}
      <span className="m5-currency-reference">参考</span>
    </div>
    {available && <div className="m5-currency-table-scroll"><table>
      <thead><tr><th scope="col">期間</th><th scope="col">{snapshot.baseCurrency}</th>
        <th scope="col">{snapshot.quoteCurrency}</th><th scope="col">順位差</th><th scope="col">強弱方向</th></tr></thead>
      <tbody>{periods.map((period) => <tr key={period.label}>
        <th scope="row">{period.label}</th><td>{period.baseRank}位</td><td>{period.quoteRank}位</td>
        <td className={period.direction.toLowerCase()}>{m5Number(period.rankDifference, 0, "", true)}</td>
        <td className={`m5-currency-direction ${period.direction.toLowerCase()}`}>{period.direction === "TIE" ? "同順位" : period.direction}</td>
      </tr>)}</tbody>
    </table></div>}
    {snapshot && <details className="m5-currency-source"><summary>参照元：{snapshot.databaseName ?? "未設定"} · {snapshot.calculationMode}</summary>
      <span>対象M5 Server {m5StoredServerTime(snapshot.targetM5BarTime)}</span>
      {available && <><span>取得M5 Server {m5StoredServerTime(snapshot.actualM5BarTime)}</span><span>Run {snapshot.runId}</span></>}
      <span>{snapshot.sourceMode} · {snapshot.calculationVersion}</span>
      <span>閲覧時の別DB参照値です。M5観測DBに保存された値ではありません。</span>
    </details>}
  </section>;
}
