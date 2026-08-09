import type { SummaryResponse } from "../api/types";
import { formatInteger } from "../lib/format";

interface SummaryCardsProps {
  summary: SummaryResponse | null;
}

export function SummaryCards({ summary }: SummaryCardsProps) {
  const value = (field: keyof SummaryResponse) => summary ? formatInteger(summary[field]) : "—";
  return (
    <section className="react-summary-strip" aria-label="検索結果集計">
      <dl>
        <div className="react-summary-item"><dt>総件数</dt><dd>{value("total_count")}</dd></div>
        <div className="react-summary-item buy"><dt>BUY</dt><dd>{value("buy_count")}</dd></div>
        <div className="react-summary-item sell"><dt>SELL</dt><dd>{value("sell_count")}</dd></div>
        <div className="react-summary-item align"><dt>W1一致</dt><dd>{value("w1_aligned_count")}</dd></div>
        <div className="react-summary-item mismatch"><dt>W1不一致</dt><dd>{value("w1_mismatched_count")}</dd></div>
      </dl>
    </section>
  );
}
