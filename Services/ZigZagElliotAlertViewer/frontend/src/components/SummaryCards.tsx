import type { SummaryResponse } from "../api/types";
import { formatInteger } from "../lib/format";

interface SummaryCardsProps {
  summary: SummaryResponse | null;
}

export function SummaryCards({ summary }: SummaryCardsProps) {
  const value = (field: keyof SummaryResponse) => summary ? formatInteger(summary[field]) : "—";
  return (
    <section className="summary-grid" aria-label="検索結果集計">
      <article className="summary-card"><span>総件数</span><strong>{value("total_count")}</strong></article>
      <article className="summary-card buy"><span>BUY</span><strong>{value("buy_count")}</strong></article>
      <article className="summary-card sell"><span>SELL</span><strong>{value("sell_count")}</strong></article>
      <article className="summary-card align"><span>W1一致</span><strong>{value("w1_aligned_count")}</strong></article>
      <article className="summary-card mismatch"><span>W1不一致</span><strong>{value("w1_mismatched_count")}</strong></article>
    </section>
  );
}
