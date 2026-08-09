import MuiPagination from "@mui/material/Pagination";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";

interface PaginationProps {
  page: number;
  pageCount: number;
  onPage: (page: number) => void;
}

export function Pagination({ page, pageCount, onPage }: PaginationProps) {
  const normalizedPageCount = Math.max(pageCount, 1);
  return (
    <Stack className="pagination" component="nav" direction="row" aria-label="ページ移動">
      <MuiPagination
        count={normalizedPageCount}
        page={Math.min(Math.max(page, 1), normalizedPageCount)}
        variant="outlined"
        shape="rounded"
        showFirstButton
        showLastButton
        getItemAriaLabel={(type, pageNumber) => {
          if (type === "previous") return "前へ";
          if (type === "next") return "次へ";
          if (type === "first") return "最初のページ";
          if (type === "last") return "最後のページ";
          return `${pageNumber}ページへ`;
        }}
        onChange={(_, nextPage) => onPage(nextPage)}
      />
      <Typography color="text.secondary" variant="body2">
        {page} / {normalizedPageCount}
      </Typography>
    </Stack>
  );
}
