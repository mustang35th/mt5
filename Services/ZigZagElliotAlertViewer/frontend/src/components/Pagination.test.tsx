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

  it("keeps the existing UI without opting into direct input", () => {
    render(<Pagination page={2} pageCount={3} onPage={vi.fn()} />);
    expect(screen.queryByRole("textbox", { name: "ページ番号" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "移動" })).not.toBeInTheDocument();
    expect(screen.getByText("2 / 3")).toBeInTheDocument();
  });

  it("shows an accessible numeric-keyboard text input with the current page", () => {
    render(<Pagination page={2} pageCount={100} onPage={vi.fn()} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    expect(input).toHaveValue("2");
    expect(input).toHaveAttribute("inputmode", "numeric");
    expect(screen.getByRole("button", { name: "移動" })).toHaveAttribute("type", "submit");
  });

  it("does not request pages while editing and jumps only on button submission", () => {
    const onPage = vi.fn();
    render(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.change(input, { target: { value: "2" } });
    fireEvent.change(input, { target: { value: "25" } });
    expect(onPage).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "移動" }));
    expect(onPage).toHaveBeenCalledExactlyOnceWith(25);
  });

  it("uses the form submission path shared by Enter and the jump button", () => {
    const onPage = vi.fn();
    render(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "42" } });
    const form = input.closest("form");
    expect(form).not.toBeNull();
    // jsdom does not synthesize the browser's implicit Enter submission from keyDown.
    fireEvent.submit(form!);
    expect(onPage).toHaveBeenCalledExactlyOnceWith(42);
  });

  it.each(["", " ", "0", "-1", "1.5", "1e2", "2foo", "101", "9007199254740992", "Infinity", "+2", "２"])(
    "does not submit the invalid page value %j",
    (value) => {
      const onPage = vi.fn();
      render(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
      const input = screen.getByRole("textbox", { name: "ページ番号" });
      fireEvent.change(input, { target: { value } });
      fireEvent.click(screen.getByRole("button", { name: "移動" }));
      // Direct submission must also be guarded, not just the button's disabled state.
      fireEvent.submit(input.closest("form")!);
      expect(onPage).not.toHaveBeenCalled();
    },
  );

  it.each([1, 100])("accepts the inclusive page boundary %i", (page) => {
    const onPage = vi.fn();
    render(<Pagination page={50} pageCount={100} onPage={onPage} showPageInput />);
    fireEvent.change(screen.getByRole("textbox", { name: "ページ番号" }), {
      target: { value: String(page) },
    });
    fireEvent.click(screen.getByRole("button", { name: "移動" }));
    expect(onPage).toHaveBeenCalledExactlyOnceWith(page);
  });

  it("does not request the page that is already displayed", () => {
    const onPage = vi.fn();
    render(<Pagination page={2} pageCount={3} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.click(screen.getByRole("button", { name: "移動" }));
    fireEvent.submit(input.closest("form")!);
    expect(onPage).not.toHaveBeenCalled();
  });

  it("synchronizes the draft when the actual page prop changes", () => {
    const onPage = vi.fn();
    const { rerender } = render(<Pagination page={2} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "42" } });
    rerender(<Pagination page={3} pageCount={100} onPage={onPage} showPageInput />);
    expect(input).toHaveValue("3");
    fireEvent.change(input, { target: { value: "55" } });
    rerender(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
    expect(input).toHaveValue("1");
    expect(onPage).not.toHaveBeenCalled();
  });

  it("keeps the edited draft when only the total changes and uses the latest limit", () => {
    const onPage = vi.fn();
    const { rerender } = render(<Pagination page={2} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "80" } });
    rerender(<Pagination page={2} pageCount={50} onPage={onPage} showPageInput />);
    expect(input).toHaveValue("80");
    fireEvent.submit(input.closest("form")!);
    expect(onPage).not.toHaveBeenCalled();
    rerender(<Pagination page={2} pageCount={90} onPage={onPage} showPageInput />);
    expect(input).toHaveValue("80");
    fireEvent.click(screen.getByRole("button", { name: "移動" }));
    expect(onPage).toHaveBeenCalledExactlyOnceWith(80);
  });

  it("keeps the edited draft across an unrelated rerender", () => {
    const onPage = vi.fn();
    const { rerender } = render(<Pagination page={2} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "80" } });
    rerender(<Pagination page={2} pageCount={100} onPage={onPage} showPageInput />);
    expect(input).toHaveValue("80");
    expect(onPage).not.toHaveBeenCalled();
  });

  it.each([
    { pageCount: 3, disabled: true },
    { pageCount: 0, disabled: false },
    { pageCount: -1, disabled: false },
  ])("disables every control for %j", ({ pageCount, disabled }) => {
    const onPage = vi.fn();
    render(<Pagination page={1} pageCount={pageCount} onPage={onPage} showPageInput disabled={disabled} />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    expect(input).toBeDisabled();
    for (const button of screen.getAllByRole("button")) {
      expect(button).toBeDisabled();
      fireEvent.click(button);
    }
    fireEvent.change(input, { target: { value: "2" } });
    fireEvent.submit(input.closest("form")!);
    expect(onPage).not.toHaveBeenCalled();
  });

  it("blocks a pending draft while loading and enables it again afterward", () => {
    const onPage = vi.fn();
    const { rerender } = render(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
    const input = screen.getByRole("textbox", { name: "ページ番号" });
    fireEvent.change(input, { target: { value: "25" } });
    rerender(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput disabled />);
    expect(input).toHaveValue("25");
    fireEvent.submit(input.closest("form")!);
    expect(onPage).not.toHaveBeenCalled();
    rerender(<Pagination page={1} pageCount={100} onPage={onPage} showPageInput />);
    fireEvent.click(screen.getByRole("button", { name: "移動" }));
    expect(onPage).toHaveBeenCalledExactlyOnceWith(25);
  });

  it.each([
    { page: 0, expected: "1" },
    { page: 9, expected: "3" },
  ])("normalizes the initial input for out-of-range page $page", ({ page, expected }) => {
    render(<Pagination page={page} pageCount={3} onPage={vi.fn()} showPageInput />);
    expect(screen.getByRole("textbox", { name: "ページ番号" })).toHaveValue(expected);
  });
});
