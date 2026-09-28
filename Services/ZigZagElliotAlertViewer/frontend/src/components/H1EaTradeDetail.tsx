import { useState } from "react";
import type { EaRecord, EaTradeDetail, EaValue } from "../api/eaTypes";
import { eaMoney, eaNumber, eaTime, eaTone, eaValue } from "../lib/eaFormat";

export function EaDirection({ value }: { value: EaValue | undefined }) {
  return <span className={value === "BUY" ? "ea-buy" : value === "SELL" ? "ea-sell" : ""}>{eaValue(value)}</span>;
}

function Fields({ record, fields }: { record: EaRecord; fields: [string, string][] }) {
  return <dl className="ea-fields">{fields.map(([key, label]) => <div key={key}><dt>{label}</dt><dd>{eaValue(record[key])}</dd></div>)}</dl>;
}

function eventTime(event: EaRecord): string {
  if (typeof event.broker_time_msc === "number" && event.broker_time_msc > 0) return eaTime(event.broker_time_msc, true);
  return eaTime(typeof event.server_time === "number" ? event.server_time : null);
}

export function H1EaTradeDetail({ detail, loading, error, onNavigate }: {
  detail: EaTradeDetail | null; loading: boolean; error: string; onNavigate: (id: number) => void;
}) {
  const [tab, setTab] = useState("conditions");
  const trade = detail?.trade;
  const currency = detail?.session.account_currency || null;
  const decision = detail?.decision;
  return <section className="ea-panel" aria-label="取引詳細" aria-busy={loading}>
    <div className="ea-panel-heading">
      <h3>取引詳細 {trade && <><span>{trade.symbol_name}</span> <EaDirection value={trade.side} /> <span className="ea-muted">#{trade.id}</span></>}</h3>
      <div className="ea-nav"><button type="button" disabled={loading || detail?.previous_id == null} onClick={() => detail?.previous_id != null && onNavigate(detail.previous_id)}>← 前の取引</button><button type="button" disabled={loading || detail?.next_id == null} onClick={() => detail?.next_id != null && onNavigate(detail.next_id)}>次の取引 →</button></div>
    </div>
    {error && <p className="ea-error" role="alert">{error}</p>}
    {loading ? <p className="ea-empty" role="status">取引詳細を読み込んでいます…</p> : !detail || !trade ? <p className="ea-empty">一覧の通貨名から取引を選択してください。</p> : <>
      <div className="ea-detail-summary"><span>{eaTime(trade.opened_at_msc, true)} Server</span><span>状態 {trade.status}</span><span className={eaTone(trade.net_profit)}>純損益 {eaMoney(trade.net_profit, currency, true)} {currency || "口座通貨不明"}</span><span>保有時間 {trade.holding_seconds == null ? "—" : `${eaNumber(trade.holding_seconds / 3600, 1)}時間`}</span></div>
      <div className="ea-switch ea-detail-tabs" aria-label="取引詳細の表示">
        {[["conditions", "エントリー条件"], ["deals", "約定・費用"], ["events", "SL・取引履歴"]].map(([key, label]) => <button type="button" key={key} aria-pressed={tab === key} onClick={() => setTab(key)}>{label}</button>)}
      </div>
      {tab === "conditions" && <div className="ea-detail-content">
        {!decision ? <p className="ea-note">エントリー時の判定情報は未記録です（復元された取引など）。</p> : <>
          <div className="ea-detail-columns"><div><h4>保存された判定</h4><Fields record={decision} fields={[["decision", "判定"], ["reason_code", "理由"], ["spread_pips", "Spread / pips"], ["h1_gmma_trend_count", "H1 GMMA Trend Count"], ["h1_gmma_cross_count", "H1 GMMA Cross Count"]]} /></div>
            <div><h4>発注時の条件</h4><Fields record={decision} fields={[["requested_volume", "発注数量 / Lot"], ["initial_stop_loss", "初期SL価格"], ["initial_risk_pips", "初期SL幅 / pips"], ["max_initial_risk_pips", "初期SL幅の上限 / pips"], ["h1_direction_alignment_mode", "上位足方向の判定方式"]]} /></div></div>
          <div className="ea-table-wrap"><table><caption>判定時の分析方向・EMA200・波動</caption><thead><tr><th>時間足</th><th>分析方向</th><th>EMA200</th><th>波動</th></tr></thead><tbody>
            {["MN1", "W1", "D1", "H4", "H1"].map(frame => { const key = frame.toLowerCase(); return <tr key={frame}><th>{frame}</th><td><EaDirection value={decision[`${key}_direction`]} /></td><td><EaDirection value={decision[`${key}_ema200_direction`]} /></td><td>{eaValue(decision[`${key}_elliot_label`])}</td></tr>; })}
          </tbody></table></div>
          {decision.analysis_snapshot_text && <details className="ea-raw"><summary>保存された分析情報</summary><pre>{String(decision.analysis_snapshot_text)}</pre></details>}
        </>}
      </div>}
      {tab === "deals" && <div className="ea-detail-content">
        <div className="ea-detail-columns"><div><h4>約定情報</h4><Fields record={trade} fields={[["open_price", "新規価格"], ["opened_volume", "約定数量 / Lot"], ["close_price", "決済価格"], ["remaining_position_volume", "残数量 / Lot"], ["close_reason", "決済理由"], ["position_identifier", "Position ID"]]} /></div>
          <div><h4>費用内訳 / {currency || "口座通貨不明"}</h4><dl className="ea-fields">{([['profit', '売買損益'], ['commission', '手数料'], ['swap', 'スワップ'], ['fee', 'Fee'], ['net_profit', '純損益']] as const).map(([key, label]) => <div key={key}><dt>{label}</dt><dd className={eaTone(trade[key])}>{eaMoney(trade[key], currency, true)}</dd></div>)}</dl></div></div>
        {!detail.deals_recorded ? <p className="ea-note">約定明細は未記録です。上の金額は取引単位で保存された集計値です。</p> : <div className="ea-table-wrap"><table><caption>約定明細（Server時刻）</caption><thead><tr><th>日時</th><th>Ticket</th><th>区分</th><th>方向</th><th className="ea-number">Lot</th><th className="ea-number">価格</th><th className="ea-number">損益</th><th className="ea-number">手数料</th><th className="ea-number">Swap</th><th className="ea-number">Fee</th></tr></thead><tbody>
          {detail.deals.map((deal, index) => <tr key={String(deal.ticket ?? index)}><td>{eaTime(typeof deal.time_msc === "number" ? deal.time_msc : null, true)}</td><td>{eaValue(deal.ticket)}</td><td>{({ 0: "新規", 1: "決済", 2: "反転", 3: "対当決済" } as Record<string, string>)[String(deal.entry_type)] || eaValue(deal.entry_type)}</td><td><EaDirection value={deal.deal_type === 0 ? "BUY" : deal.deal_type === 1 ? "SELL" : deal.deal_type} /></td>{["volume", "price"].map(key => <td className="ea-number" key={key}>{eaValue(deal[key])}</td>)}{["profit", "commission", "swap", "fee"].map(key => <td className="ea-number" key={key}>{eaMoney(typeof deal[key] === "number" ? deal[key] as number : null, currency, true)}</td>)}</tr>)}
          {!detail.deals.length && <tr><td colSpan={10}>この取引の約定明細はありません。</td></tr>}
        </tbody></table></div>}
        {detail.deals_truncated && <p className="ea-note">明細件数が多いため、一部のみ表示しています。</p>}
      </div>}
      {tab === "events" && <div className="ea-detail-content"><div className="ea-table-wrap"><table><caption>SL変更・取引イベント（Server時刻）</caption><thead><tr><th>日時</th><th>イベント</th><th className="ea-number">変更前SL</th><th className="ea-number">候補SL</th><th className="ea-number">確定SL</th><th>内容</th></tr></thead><tbody>
        {detail.events.map((event, index) => <tr key={String(event.id ?? index)}><td>{eventTime(event)}</td><td>{eaValue(event.event_type)}</td><td className="ea-number">{eaValue(event.previous_stop_loss)}</td><td className="ea-number">{eaValue(event.stop_loss)}</td><td className="ea-number">{eaValue(event.confirmed_stop_loss)}</td><td className="ea-event-message">{eaValue(event.message)}</td></tr>)}
        {!detail.events.length && <tr><td colSpan={6}>履歴は未記録です。</td></tr>}
      </tbody></table></div>{detail.events_truncated && <p className="ea-note">履歴件数が多いため、一部のみ表示しています。</p>}</div>}
    </>}
  </section>;
}
