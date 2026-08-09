import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Pagination } from "./Pagination";

describe("Pagination", () => {
  it("disables the previous button on the first page", () => {
    render(<Pagination page={1} pageCount={3} onPage={vi.fn()} />);
    expect(screen.getByRole("button", { name: "前へ" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "次へ" })).toBeEnabled();
  });

  it("requests the next page", () => {
    const onPage = vi.fn();
    render(<Pagination page={1} pageCount={3} onPage={onPage} />);
    fireEvent.click(screen.getByRole("button", { name: "次へ" }));
    expect(onPage).toHaveBeenCalledWith(2);
  });
});
