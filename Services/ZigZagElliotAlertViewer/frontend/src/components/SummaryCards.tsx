import type { SummaryResponse } from "../api/types";
import { formatInteger } from "../lib/format";

interface SummaryCardsProps {
  summary: SummaryResponse | null;
  staleReason?: "loading" | "error" | null;
  compact?: boolean;
}

const PERCENT_FORMATTER = new Intl.NumberFormat("ja-JP", {
  style: "percent",
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

function percentage(count: number | undefined, total: number): string {
  if (count === undefined || total <= 0) return "—";
  return PERCENT_FORMATTER.format(count / total);
}

function Metric({
  count,
  rate,
}: {
  count: number | undefined;
  rate: string;
}) {
  return (
    <dd>
      <strong>{count === undefined ? "—" : formatInteger(count)}</strong>
      <span className="react-summary-rate">（{rate}）</span>
    </dd>
  );
}

export function SummaryCards({ summary, staleReason = null, compact = false }: SummaryCardsProps) {
  const knownW1Count = summary
    ? summary.w1_aligned_count + summary.w1_mismatched_count
    : 0;
  return (
    <section
      className={`react-summary-strip${compact ? " compact" : ""}`}
      aria-busy={staleReason === "loading" || undefined}
      aria-label="検索結果集計"
    >
      <div className="react-summary-content">
        <dl className="react-summary-total-list">
          <div className="react-summary-item total">
            <dt>
              検索該当 / DB全体
              <span className="react-summary-scope">DB全体: LIVE＋TESTER</span>
            </dt>
            <dd>
              <strong>{summary ? formatInteger(summary.total_count) : "—"}</strong>
              <span className="react-summary-total-separator">/</span>
              <span>
                {summary && typeof summary.database_total_count === "number"
                  ? formatInteger(summary.database_total_count)
                  : "—"}
              </span>
            </dd>
          </div>
        </dl>
        <div className="react-summary-metrics">
          <dl className="react-summary-metrics-list">
            <div className="react-summary-item buy">
              <dt>BUY件数</dt>
              <Metric
                count={summary?.buy_count}
                rate={percentage(summary?.buy_count, summary?.total_count ?? 0)}
              />
            </div>
            <div className="react-summary-item sell">
              <dt>SELL件数</dt>
              <Metric
                count={summary?.sell_count}
                rate={percentage(summary?.sell_count, summary?.total_count ?? 0)}
              />
            </div>
            <div className="react-summary-item align">
              <dt>W1一致件数</dt>
              <Metric
                count={summary?.w1_aligned_count}
                rate={percentage(summary?.w1_aligned_count, knownW1Count)}
              />
            </div>
            <div className="react-summary-item mismatch">
              <dt>W1不一致件数</dt>
              <Metric
                count={summary?.w1_mismatched_count}
                rate={percentage(summary?.w1_mismatched_count, knownW1Count)}
              />
            </div>
          </dl>
        </div>
      </div>
      {summary && staleReason && (
        <p className="react-summary-note">
          {staleReason === "loading" ? "更新中・前回集計を表示" : "更新失敗・前回集計を表示"}
        </p>
      )}
      {summary && summary.w1_unknown_count > 0 && (
        <p className="react-summary-note">
          W1判定不明 {formatInteger(summary.w1_unknown_count)}件は一致率の分母外
        </p>
      )}
    </section>
  );
}
