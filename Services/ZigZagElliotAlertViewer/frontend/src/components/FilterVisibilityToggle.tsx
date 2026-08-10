interface FilterVisibilityToggleProps {
  controls: string;
  expanded: boolean;
  onExpandedChange: (expanded: boolean) => void;
}

export function FilterVisibilityToggle({
  controls,
  expanded,
  onExpandedChange,
}: FilterVisibilityToggleProps) {
  return (
    <button
      className="secondary-button viewer-filter-summary-toggle"
      type="button"
      aria-controls={controls}
      aria-expanded={expanded}
      aria-label={expanded ? "検索条件を閉じる" : "検索条件を開く"}
      onClick={() => onExpandedChange(!expanded)}
    >
      {expanded ? "閉じる" : "開く"}
    </button>
  );
}
