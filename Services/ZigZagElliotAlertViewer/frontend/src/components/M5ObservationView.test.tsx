import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
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
    expect(screen.queryByText("FULL")).not.toBeInTheDocument();
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
    expect(screen.getByRole("option", { name: /Run 3.*v1.02.*8064|Run 3.*v1.02.*8,064/ })).toHaveTextContent("2026-09-08 06:00");
    fireEvent.click(screen.getByText("接続情報"));
    expect(screen.getByText("C:/db-a.sqlite")).toBeVisible();
    expect(screen.getByText(/input hash: profile-m5/)).toBeVisible();
    fireEvent.change(screen.getByLabelText("M5通貨"), { target: { value: "AUDUSD" } });
    expect(screen.getByText(/未適用の変更/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    expect(screen.getByLabelText("M5通貨")).not.toBeVisible();
    expect(screen.getByText(/表示中：TESTER.*通貨 すべて.*JST時刻 すべて/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "検索条件を開く" }));
    expect(screen.getByLabelText("M5通貨")).toHaveValue("AUDUSD");
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
