import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { M5ListResponse, M5Metadata, M5SearchState } from "../api/m5Types";
import { m5Api } from "../api/m5Client";
import { M5ObservationView } from "./M5ObservationView";

vi.mock("../api/m5Client", () => ({ m5Api: { metadata: vi.fn(), observations: vi.fn() } }));
vi.mock("./M5ObservationTable", () => ({ M5ObservationTable: (props: { items: { id: number }[]; onOpenDetail: (id: number, target: HTMLElement) => void; onSort: (key: string) => void }) =>
  <div data-testid="m5-table">Rows:{props.items.map((row) => row.id).join(",")}<button onClick={(event) => props.onOpenDetail(10, event.currentTarget)}>Open row</button><button onClick={() => props.onSort("symbol_name")}>Sort symbol</button></div> }));
vi.mock("./M5ObservationDetailDrawer", () => ({ M5ObservationDetailDrawer: (props: { observationId: number | null; databaseKey: string }) =>
  <div data-testid="m5-detail">{props.databaseKey}:{props.observationId ?? "closed"}</div> }));

const first = Date.parse("2026-09-08T06:00:00Z") / 1000;
const last = first + 86400 - 300;
function metadata(mode = "TESTER", key = "db-a", runId = 3, count = 8064): M5Metadata {
  return { available: true, status: count ? "READY" : "EMPTY", reason: null,
    database: { name: `${key}.sqlite`, path: `C:/${key}.sqlite`, key }, sourceMode: mode as "TESTER" | "LIVE", effectiveRunId: runId,
    runs: [{ id: runId, source_mode: mode, observation_count: count, first_observation_jst_time: count ? first : null, last_observation_jst_time: count ? last : null }],
    symbols: ["GBPUSD", "AUDUSD"], range: { first: count ? first : null, last: count ? last : null },
    capabilities: { captureMetricsTable: true, captureMetricsColumns: [] } };
}
function rows(search: M5SearchState, id = 10): M5ListResponse {
  return { databaseKey: search.databaseKey, items: [{ id, run_id: search.runId!, symbol_name: "GBPUSD", anchor_bar_time: first - 21600, anchor_jst_time: first,
    timeframes: [], captureMetrics: null, captureMetricsState: { tableAvailable: false, rowAvailable: false, missingColumns: [] } }],
    total: 200, page: search.page, page_size: search.pageSize, total_pages: 4 };
}
describe("M5 observation independent view", () => {
  beforeEach(() => {
    vi.clearAllMocks(); localStorage.clear(); window.history.replaceState(null, "", "/react/?tab=m5");
    vi.mocked(m5Api.metadata).mockImplementation(async (mode = "TESTER") => metadata(mode));
    vi.mocked(m5Api.observations).mockImplementation(async (search) => rows(search));
  });
  afterEach(() => { vi.useRealTimers(); });
  it("initializes TESTER/latest observed Run and latest24h, shows DB and no H1 filters", async () => {
    render(<M5ObservationView active />);
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(1));
    expect(m5Api.metadata).toHaveBeenCalledWith("TESTER", null, expect.any(AbortSignal));
    expect(vi.mocked(m5Api.observations).mock.calls[0][0]).toMatchObject({ runId: 3, from: "2026-09-08T06:00", to: "2026-09-09T06:00", page: 1, pageSize: 50 });
    expect(screen.getByText("接続DB：db-a.sqlite")).toBeInTheDocument();
    expect(screen.getByLabelText("DB接続状態")).toHaveTextContent("接続済み");
    expect(screen.getByRole("button", { name: "接続詳細" })).toHaveAttribute("aria-expanded", "false");
    expect(screen.getByText("C:/db-a.sqlite")).not.toBeVisible();
    expect(screen.getByText("接続DB：db-a.sqlite")).toHaveAttribute("title", "C:/db-a.sqlite");
    expect(screen.queryByText("FULL")).not.toBeInTheDocument();
  });
  it("groups all search controls in the sidebar and keeps result controls beside it", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    const sidebar = screen.getByRole("complementary", { name: "M5検索条件" });
    expect(sidebar.tagName).toBe("ASIDE");
    expect(sidebar).toHaveAttribute("id", "m5-filter-panel");
    expect(sidebar).toBeVisible();
    for (const label of ["M5実行モード", "M5 Run", "M5通貨", "M5開始JST", "M5終了JST", "M5 JST時刻"]) {
      expect(within(sidebar).getByLabelText(label)).toBeVisible();
    }
    expect(within(sidebar).getByRole("button", { name: /^検索$/ })).toBeVisible();
    expect(within(sidebar).getByRole("button", { name: "最新24時間" })).toBeVisible();
    const resultPanel = screen.getByTestId("m5-table").closest(".m5-panel") as HTMLElement;
    expect(sidebar).not.toContainElement(resultPanel);
    expect(within(resultPanel).getByText(/表示中：TESTER/)).toBeVisible();
    expect(within(resultPanel).getByRole("button", { name: "今すぐ更新" })).toBeVisible();
    expect(within(resultPanel).getByLabelText("M5ページ件数")).toBeVisible();
    expect(within(resultPanel).getByRole("navigation", { name: "ページ移動" })).toBeVisible();
  });
  it("does not request an unbounded list when a selected Run has no observations", async () => {
    vi.mocked(m5Api.metadata).mockResolvedValue(metadata("TESTER", "db-a", 9, 0));
    render(<M5ObservationView active />);
    await screen.findByText(/選択モード／Runは未収集/);
    expect(m5Api.observations).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "最新24時間" })).toBeDisabled();
    expect(screen.getByLabelText("M5開始JST")).toHaveValue("");
  });
  it("keeps editing separate from search and submits a five-minute half-open range", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    fireEvent.change(screen.getByLabelText("M5開始JST"), { target: { value: "2026-09-08T07:05" } });
    expect(m5Api.observations).toHaveBeenCalledTimes(1);
    fireEvent.change(screen.getByLabelText("M5通貨"), { target: { value: "GBPUSD" } });
    fireEvent.click(screen.getByRole("button", { name: /^検索$/ }));
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(2));
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ from: "2026-09-08T07:05", to: "2026-09-09T06:00", symbol: "GBPUSD", page: 1, followLatest: false });
  });
  it("resets filters/page/detail and latest range when source mode changes", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    fireEvent.click(screen.getByText("Open row"));
    fireEvent.change(screen.getByLabelText("M5通貨"), { target: { value: "GBPUSD" } });
    fireEvent.change(screen.getByLabelText("M5実行モード"), { target: { value: "LIVE" } });
    await waitFor(() => expect(vi.mocked(m5Api.observations).mock.lastCall?.[0].sourceMode).toBe("LIVE"));
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ symbol: "", page: 1, followLatest: true });
    expect(screen.getByTestId("m5-detail")).toHaveTextContent("closed");
  });
  it("resets filters/page/detail and latest range when the sidebar Run changes", async () => {
    window.history.replaceState(null, "", "/react/?tab=m5&symbol=GBPUSD&from=2026-09-08T07:00&to=2026-09-08T08:00&page=2");
    vi.mocked(m5Api.metadata).mockImplementation(async (mode = "TESTER", runId) => {
      const info = metadata(mode, "db-a", runId ?? 3);
      info.runs = [metadata(mode, "db-a", 3).runs[0], metadata(mode, "db-a", 2).runs[0]];
      return info;
    });
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    fireEvent.click(screen.getByText("Open row"));
    const sidebar = screen.getByRole("complementary", { name: "M5検索条件" });
    fireEvent.change(within(sidebar).getByLabelText("M5通貨"), { target: { value: "AUDUSD" } });
    fireEvent.change(within(sidebar).getByLabelText("M5 Run"), { target: { value: "2" } });
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(2));
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({
      runId: 2, symbol: "", page: 1, from: "2026-09-08T06:00", to: "2026-09-09T06:00", followLatest: false,
    });
    expect(within(sidebar).getByLabelText("M5通貨")).toHaveValue("");
    expect(screen.getByTestId("m5-detail")).toHaveTextContent("closed");
  });
  it("invalidates old DB/Run/detail before requesting replacement data", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    fireEvent.click(screen.getByText("Open row"));
    vi.mocked(m5Api.metadata).mockResolvedValue(metadata("TESTER", "db-b", 1));
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await waitFor(() => expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ databaseKey: "db-b", runId: 1 }));
    expect(screen.getByTestId("m5-detail")).toHaveTextContent("db-b:closed");
    expect(screen.getByText(/旧DBのRun・検索・詳細を解除/)).toBeInTheDocument();
  });
  it("retains the last successful data on request errors and marks it stale", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    vi.mocked(m5Api.observations).mockRejectedValue(new Error("network down"));
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await screen.findByRole("alert");
    expect(screen.getByTestId("m5-table")).toHaveTextContent("Rows:10");
    expect(screen.getByRole("alert")).toHaveTextContent("前回成功時のデータを表示中");
    expect(screen.getByLabelText("DB接続状態")).toHaveTextContent("読込エラー");
  });
  it("ignores an old list response after another mode has become active", async () => {
    let finishOld!: (value: M5ListResponse) => void;
    let oldSearch!: M5SearchState;
    vi.mocked(m5Api.observations).mockImplementationOnce((search) => {
      oldSearch = search; return new Promise((resolve) => { finishOld = resolve; });
    }).mockImplementation(async (search) => rows(search, 20));
    render(<M5ObservationView active />);
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(1));
    fireEvent.change(screen.getByLabelText("M5実行モード"), { target: { value: "LIVE" } });
    await screen.findByText("Rows:20");
    await act(async () => { finishOld(rows(oldSearch, 99)); });
    expect(screen.getByTestId("m5-table")).toHaveTextContent("Rows:20");
    expect(screen.getByTestId("m5-table")).not.toHaveTextContent("99");
  });
  it("LIVE polls only when active and refreshes on return, preserving the selected Run", async () => {
    vi.useFakeTimers(); window.history.replaceState(null, "", "/react/?tab=m5&sourceMode=LIVE");
    const view = render(<M5ObservationView active />);
    await act(async () => { await vi.advanceTimersByTimeAsync(0); });
    expect(m5Api.observations).toHaveBeenCalledTimes(1);
    await act(async () => { await vi.advanceTimersByTimeAsync(15000); });
    expect(m5Api.observations).toHaveBeenCalledTimes(2);
    view.rerender(<M5ObservationView active={false} />);
    await act(async () => { await vi.advanceTimersByTimeAsync(30000); });
    expect(m5Api.observations).toHaveBeenCalledTimes(2);
    view.rerender(<M5ObservationView active />);
    await act(async () => { await vi.advanceTimersByTimeAsync(0); });
    expect(m5Api.observations).toHaveBeenCalledTimes(3);
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0].runId).toBe(3);
  });
  it("exposes connection details and collapsible search with unapplied changes", async () => {
    const info = metadata(); info.runs[0].program_version = "1.02"; info.runs[0].analysis_input_hash = "profile-m5";
    vi.mocked(m5Api.metadata).mockResolvedValue(info);
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    expect(screen.getByRole("option", { name: "Run 3 · v1.02" })).toBeInTheDocument();
    expect(screen.getByLabelText("選択Runの保存範囲")).toHaveTextContent(/8,?064件/);
    expect(screen.getByLabelText("選択Runの保存範囲")).toHaveTextContent("2026-09-08 06:00");
    const connectionToggle = screen.getByRole("button", { name: "接続詳細" });
    const metadataCallsBeforeToggle = vi.mocked(m5Api.metadata).mock.calls.length;
    const listCallsBeforeToggle = vi.mocked(m5Api.observations).mock.calls.length;
    fireEvent.click(connectionToggle);
    expect(connectionToggle).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByText("C:/db-a.sqlite")).toBeVisible();
    expect(screen.getByText(/input hash: profile-m5/)).toBeVisible();
    expect(screen.getByText(/M5基準・7時間足の保存済み観測/)).toBeVisible();
    fireEvent.click(connectionToggle);
    expect(connectionToggle).toHaveAttribute("aria-expanded", "false");
    expect(screen.getByText("C:/db-a.sqlite")).not.toBeVisible();
    expect(m5Api.metadata).toHaveBeenCalledTimes(metadataCallsBeforeToggle);
    expect(m5Api.observations).toHaveBeenCalledTimes(listCallsBeforeToggle);
    fireEvent.change(screen.getByLabelText("M5通貨"), { target: { value: "AUDUSD" } });
    expect(screen.getByText(/未適用の変更/)).toBeVisible();
    const sidebar = screen.getByRole("complementary", { name: "M5検索条件" });
    const urlBeforeToggle = window.location.search;
    const appliedBeforeToggle = vi.mocked(m5Api.observations).mock.lastCall?.[0];
    const closeSearch = screen.getByRole("button", { name: "検索条件を閉じる" });
    expect(closeSearch).toHaveAttribute("aria-controls", sidebar.id);
    expect(closeSearch).toHaveAttribute("aria-expanded", "true");
    expect(sidebar).not.toContainElement(closeSearch);
    fireEvent.click(closeSearch);
    expect(sidebar).not.toBeVisible();
    expect(sidebar.parentElement).toHaveClass("filter-sidebar-collapsed");
    expect(screen.getByLabelText("M5実行モード")).not.toBeVisible();
    expect(screen.getByLabelText("M5 Run")).not.toBeVisible();
    expect(screen.getByText(/表示中：TESTER.*通貨 すべて.*JST時刻 すべて/)).toBeVisible();
    expect(screen.getByTestId("m5-table")).toBeVisible();
    expect(screen.getByRole("button", { name: "今すぐ更新" })).toBeVisible();
    expect(screen.getByLabelText("M5ページ件数")).toBeVisible();
    expect(screen.getByRole("navigation", { name: "ページ移動" })).toBeVisible();
    const openSearch = screen.getByRole("button", { name: "検索条件を開く" });
    expect(openSearch).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(openSearch);
    expect(sidebar).toBeVisible();
    expect(sidebar.parentElement).not.toHaveClass("filter-sidebar-collapsed");
    expect(screen.getByLabelText("M5通貨")).toHaveValue("AUDUSD");
    expect(screen.getByText(/未適用の変更/)).toBeVisible();
    expect(window.location.search).toBe(urlBeforeToggle);
    expect(m5Api.metadata).toHaveBeenCalledTimes(1);
    expect(m5Api.observations).toHaveBeenCalledTimes(1);
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toEqual(appliedBeforeToggle);
  });
  it("refreshes applied results while the sidebar is hidden and preserves its unsaved draft", async () => {
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    const appliedBeforeRefresh = vi.mocked(m5Api.observations).mock.lastCall?.[0];
    const urlBeforeRefresh = window.location.search;
    fireEvent.change(screen.getByLabelText("M5通貨"), { target: { value: "AUDUSD" } });
    fireEvent.change(screen.getByLabelText("M5開始JST"), { target: { value: "2026-09-08T07:05" } });
    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    vi.mocked(m5Api.observations).mockImplementation(async (search) => rows(search, 20));
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await screen.findByText("Rows:20");
    expect(m5Api.observations).toHaveBeenCalledTimes(2);
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toEqual(appliedBeforeRefresh);
    expect(window.location.search).toBe(urlBeforeRefresh);
    expect(screen.getByLabelText("M5通貨")).not.toBeVisible();
    expect(screen.getByText(/表示中：TESTER.*通貨 すべて/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "検索条件を開く" }));
    expect(screen.getByLabelText("M5通貨")).toHaveValue("AUDUSD");
    expect(screen.getByLabelText("M5開始JST")).toHaveValue("2026-09-08T07:05");
    expect(screen.getByText(/未適用の変更/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: /^検索$/ }));
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(3));
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ symbol: "AUDUSD", from: "2026-09-08T07:05", page: 1 });
  });
  it("keeps a fixed LIVE range and announces observations beyond it", async () => {
    window.history.replaceState(null, "", "/react/?tab=m5&sourceMode=LIVE&from=2026-09-08T06:00&to=2026-09-08T08:00&followLatest=0&page=2");
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ page: 2, to: "2026-09-08T08:00", followLatest: false });
    expect(screen.getByText(/選択範囲より新しいM5観測/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "最新24時間" }));
    await waitFor(() => expect(vi.mocked(m5Api.observations).mock.lastCall?.[0]).toMatchObject({ page: 1, to: "2026-09-09T06:00", followLatest: true }));
  });
  it("does not auto-switch to a new LIVE Run on refresh", async () => {
    window.history.replaceState(null, "", "/react/?tab=m5&sourceMode=LIVE");
    render(<M5ObservationView active />);
    await screen.findByText("Rows:10");
    vi.mocked(m5Api.metadata).mockImplementation(async (mode = "LIVE", runId) => {
      const info = metadata(mode, "db-a", runId ?? 4);
      info.runs = [metadata(mode, "db-a", 4).runs[0], metadata(mode, "db-a", 3).runs[0]];
      return info;
    });
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await waitFor(() => expect(m5Api.observations).toHaveBeenCalledTimes(2));
    expect(vi.mocked(m5Api.observations).mock.lastCall?.[0].runId).toBe(3);
    expect(screen.getByText(/観測のある最新Runは 4/)).toBeInTheDocument();
  });
  it("does not poll while the document is hidden and refreshes on visibility return", async () => {
    vi.useFakeTimers(); window.history.replaceState(null, "", "/react/?tab=m5&sourceMode=LIVE");
    const hidden = vi.spyOn(document, "hidden", "get").mockReturnValue(false);
    try {
      render(<M5ObservationView active />);
      await act(async () => { await vi.advanceTimersByTimeAsync(0); });
      hidden.mockReturnValue(true);
      await act(async () => { await vi.advanceTimersByTimeAsync(45000); });
      expect(m5Api.observations).toHaveBeenCalledTimes(1);
      hidden.mockReturnValue(false);
      await act(async () => { document.dispatchEvent(new Event("visibilitychange")); await vi.advanceTimersByTimeAsync(0); });
      expect(m5Api.observations).toHaveBeenCalledTimes(2);
    } finally { hidden.mockRestore(); }
  });
});
