import type { M5CaptureMetrics, M5CaptureMetricsState, M5ObservationParent } from "../api/m5Types";
import { m5CaptureLag, m5CaptureWarnings, m5MetricLabel, m5MetricMissingReason, type M5MetricField } from "../lib/m5CaptureQuality";
import { m5Number, m5Text } from "../lib/m5TimeFrame";

const FIELDS: Array<{ field: M5MetricField; label: string; description: string }> = [
  { field: "quote_tick_time_msc", label: "採用気配時刻（Server、ms）", description: "Spread計算に採用した気配の更新時刻。現在の気配ではありません。" },
  { field: "capture_market_time", label: "取得市場時刻（Server）", description: "Snapshot確定時の市場時刻。TESTERでは模擬時刻です。" },
  { field: "analysis_elapsed_ms", label: "解析時間（ms）", description: "最後に成功した解析1回の実経過時間。DB書き込み時間は含みません。" },
  { field: "capture_elapsed_ms", label: "取得時間（ms）", description: "対象M5の初検出からSnapshot確定までの実経過時間。FIFO追加後のDB保存待ちは含みません。" },
  { field: "analysis_attempt_count", label: "解析回数", description: "観測用の実解析回数。事前分析・履歴確認・DB再送を除きます。" },
];

export function M5CaptureQuality({ observation, metrics, state }: {
  observation: M5ObservationParent;
  metrics: M5CaptureMetrics | null;
  state: M5CaptureMetricsState;
}) {
  const lag = m5CaptureLag(observation, metrics, state);
  const warnings = m5CaptureWarnings(observation, metrics, state);
  return <section aria-label="M5取得品質" className="detail-section m5-capture-quality">
    <h3 className="eyebrow">CAPTURE QUALITY</h3>
    <p>M5開始 JST {m5Text(observation.anchor_jst_time_text)} ／ Server {m5Text(observation.anchor_bar_time_text)}</p>
    {!state.tableAvailable && <p className="m5-notice">未記録：品質テーブルがありません。</p>}
    {state.tableAvailable && !state.rowAvailable && <p className="m5-notice">未記録：この観測の品質行がありません。</p>}
    {state.tableAvailable && state.missingColumns.length > 0 && <p className="m5-notice">未記録の品質列：{state.missingColumns.join("、")}</p>}
    <div className="m5-quality-fields">
      <div className="detail-field" title="capture_market_time - anchor_bar_time。通信遅延や実処理時間ではありません。">
        <span>市場取得遅れ（秒）</span>
        <strong>{lag === null ? m5MetricMissingReason(metrics, state, "capture_market_time") || "不正値" : m5Number(lag, 0, "秒")}</strong>
        <small>M5開始から取得市場時刻までの差。実処理時間ではありません。</small>
      </div>
      {FIELDS.map(({ field, label, description }) => <div className="detail-field" key={field} title={description}>
        <span>{label}</span><strong>{m5MetricLabel(metrics, state, field)}</strong><small>{description}</small>
      </div>)}
    </div>
    {warnings.length > 0 && <ul className="m5-warning" aria-label="取得品質の要確認事項">{warnings.map((warning) => <li key={warning}>{warning}</li>)}</ul>}
    <p className="m5-note">市場時刻と実経過時間は別の時計です。品質時刻は保存されたServer時刻で、PC日時や独自のJSTへ変換しません。任意の遅れによる観測除外は行わず、28通貨の同時取得・収集全体の完全性を保証する表示ではありません。</p>
  </section>;
}
