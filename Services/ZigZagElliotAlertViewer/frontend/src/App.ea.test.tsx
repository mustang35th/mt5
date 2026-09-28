import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import { readViewerTab } from "./lib/searchState";
import { DEFAULT_OBSERVATION_SEARCH_STATE, readObservationSearchState } from "./lib/observationSearchState";

vi.mock("./components/H1EaResultsView", () => ({ H1EaResultsView: ({ active }: { active: boolean }) => active ? <div>EA結果独立画面</div> : null }));
vi.mock("./components/H1ObservationView", () => ({ H1ObservationView: () => null }));
vi.mock("./components/M5ObservationView", () => ({ M5ObservationView: () => null }));
vi.mock("./components/AlertTable", () => ({ AlertTable: () => null }));

describe("EA independent App entry", () => {
  afterEach(() => vi.unstubAllGlobals());
  it("opens EA without any alert API and keeps session out of H1 filters", () => {
    window.history.replaceState(null, "", "/?tab=ea&session=example&runId=99&sourceMode=TESTER");
    const fetch = vi.fn(); vi.stubGlobal("fetch", fetch);
    render(<App />);
    expect(screen.getByText("EA結果独立画面")).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
    expect(screen.getByRole("tab", { name: "H1 EA結果" })).toHaveAttribute("aria-selected", "true");
    expect(readViewerTab("?tab=ea")).toBe("ea");
    expect(readObservationSearchState("?tab=ea&runId=99")).toEqual(DEFAULT_OBSERVATION_SEARCH_STATE);
  });
  it("boots alerts lazily when leaving the EA tab", async () => {
    window.history.replaceState(null, "", "/?tab=ea&session=example&runId=99&sourceMode=TESTER");
    const calls: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input); calls.push(url);
      const payload = url === "/api/health" ? { status: "ok", database: "alerts.sqlite" } : url === "/api/runs" ? { items: [], count: 0 } : url === "/api/options" ? { symbols: [], time_frames: [], strategies: [], ranks: [], entry_results: [] } : url.startsWith("/api/alerts") ? { items: [], total: 0, page: 1, page_size: 50, page_count: 0 } : { total_count: 0, buy_count: 0, sell_count: 0, run_count: 0, symbol_count: 0, entry_result_counts: [] };
      return { ok: true, json: async () => payload } as Response;
    }));
    render(<App />);
    fireEvent.click(screen.getByRole("tab", { name: "アラート一覧" }));
    await waitFor(() => expect(calls.some(url => url.startsWith("/api/alerts?"))).toBe(true));
    const params = new URLSearchParams(calls.find(url => url.startsWith("/api/alerts?"))!.split("?")[1]);
    expect(params.has("session")).toBe(false); expect(params.has("runId")).toBe(false); expect(params.get("sourceMode")).toBe("LIVE");
  });
  it("selects EA on a default entry when only the EA database is available", async () => {
    window.history.replaceState(null, "", "/");
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith("/api/m5/metadata")) return { ok: true, json: async () => ({ available: false }) } as Response;
      if (url === "/api/ea/metadata") return { ok: true, json: async () => ({ available: true }) } as Response;
      return { ok: false, status: 503, json: async () => ({ error: "primary unavailable" }) } as Response;
    }));
    render(<App />);
    expect(await screen.findByText("EA結果独立画面")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(new URLSearchParams(window.location.search).get("tab")).toBe("ea");
  });
});
