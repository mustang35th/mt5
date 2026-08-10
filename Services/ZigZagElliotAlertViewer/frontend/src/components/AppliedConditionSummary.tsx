interface AppliedConditionSummaryProps {
  summary: string;
  hasUnappliedChanges: boolean;
}

export function AppliedConditionSummary({
  summary,
  hasUnappliedChanges,
}: AppliedConditionSummaryProps) {
  return (
    <section className="viewer-applied-filter-summary" aria-label="適用中の検索条件">
      <span className="viewer-applied-filter-label">検索条件</span>
      <span className="viewer-applied-filter-value" title={summary}>{summary}</span>
      {hasUnappliedChanges && <strong>未検索の変更あり</strong>}
    </section>
  );
}
