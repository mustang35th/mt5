import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import MuiPagination from "@mui/material/Pagination";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useEffect, useId, useState, type FormEvent } from "react";

interface PaginationProps {
  page: number;
  pageCount: number;
  showPageInput?: boolean;
  disabled?: boolean;
  onPage: (page: number) => void;
}

export function Pagination({
  page,
  pageCount,
  showPageInput = false,
  disabled = false,
  onPage,
}: PaginationProps) {
  const normalizedPageCount = Math.max(pageCount, 1);
  const currentPage = Math.min(Math.max(page, 1), normalizedPageCount);
  const navigationDisabled = disabled || (showPageInput && pageCount <= 0);
  const [pageInput, setPageInput] = useState(String(currentPage));
  const [inputInvalid, setInputInvalid] = useState(false);
  const inputId = useId();
  const errorId = `${inputId}-error`;

  useEffect(() => {
    setPageInput(String(currentPage));
    setInputInvalid(false);
  }, [page, currentPage]);

  function submitPage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (navigationDisabled) return;
    const input = pageInput.trim();
    const nextPage = Number(input);
    if (!/^\d+$/.test(input) || !Number.isSafeInteger(nextPage)
        || nextPage < 1 || nextPage > pageCount) {
      setInputInvalid(true);
      return;
    }
    setInputInvalid(false);
    setPageInput(String(nextPage));
    if (nextPage !== currentPage) onPage(nextPage);
  }

  return (
    <Stack
      className={`pagination${showPageInput ? " pagination-with-input" : ""}`}
      component="nav"
      direction="row"
      aria-label="ページ移動"
    >
      <MuiPagination
        count={normalizedPageCount}
        page={currentPage}
        disabled={navigationDisabled}
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
      {showPageInput ? (
        <Box component="form" className="pagination-jump" aria-label="ページ番号で移動"
          noValidate onSubmit={submitPage}>
          <TextField
            id={inputId}
            className="pagination-page-input"
            label="ページ番号"
            size="small"
            value={pageInput}
            disabled={navigationDisabled}
            error={inputInvalid}
            slotProps={{ htmlInput: {
              inputMode: "numeric",
              "aria-describedby": inputInvalid ? errorId : undefined,
            } }}
            onChange={(event) => {
              setPageInput(event.target.value);
              setInputInvalid(false);
            }}
          />
          <Typography component="span" color="text.secondary" variant="body2">
            / {normalizedPageCount}
          </Typography>
          <Button type="submit" variant="outlined" disabled={navigationDisabled}>移動</Button>
          {inputInvalid && (
            <Typography id={errorId} className="pagination-page-error" role="alert"
              color="error" variant="caption">
              1～{pageCount}の整数を入力してください。
            </Typography>
          )}
        </Box>
      ) : (
        <Typography color="text.secondary" variant="body2">
          {page} / {normalizedPageCount}
        </Typography>
      )}
    </Stack>
  );
}
