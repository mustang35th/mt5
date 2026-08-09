import "@testing-library/jest-dom/vitest";

Object.defineProperty(Element.prototype, "innerText", {
  configurable: true,
  get() {
    return this.textContent || "";
  },
  set(value: string) {
    this.textContent = value;
  },
});

if (!HTMLDialogElement.prototype.showModal) {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute("open", "");
  };
}

if (!HTMLDialogElement.prototype.close) {
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute("open");
  };
}
