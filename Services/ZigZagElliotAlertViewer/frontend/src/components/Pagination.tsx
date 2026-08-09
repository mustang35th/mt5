interface PaginationProps {
  page: number;
  pageCount: number;
  onPage: (page: number) => void;
}

export function Pagination({ page, pageCount, onPage }: PaginationProps) {
  const normalizedPageCount = Math.max(pageCount, 1);
  return (
    <nav className="pagination" aria-label="ページ移動">
      <button className="ghost-button" type="button" disabled={page <= 1} onClick={() => onPage(page - 1)}>
        前へ
      </button>
      <span>{page} / {normalizedPageCount}</span>
      <button
        className="ghost-button"
        type="button"
        disabled={page >= normalizedPageCount}
        onClick={() => onPage(page + 1)}
      >
        次へ
      </button>
    </nav>
  );
}
