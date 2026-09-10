import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import { readObservationSearchState, DEFAULT_OBSERVATION_SEARCH_STATE } from "./lib/observationSearchState";
import { readViewerTab } from "./lib/searchState";

vi.mock("./components/M5ObservationView", () => ({
  M5ObservationView: ({ active }: { active: boolean }) => active ? <div>M5独立画面</div> : null,
}));
vi.mock("./components/H1ObservationView", () => ({
  H1ObservationView: ({ active }: { active: boolean }) => active ? <div>H1既存画面</div> : null,
}));
vi.mock("./components/AlertTable", () => ({ AlertTable: () => <div>既存アラート表</div> }));

function response(payload: unknown, ok = true): Response {
  return { ok, status: ok ? 200 : 503, json: async () => payload } as Response;
}

describe("M5 independent App entry", () => {
  let primaryAvailable: boolean;
  let m5Available: boolean;
  let calls: string[];

  beforeEach(() => {
    primaryAvailable = true;
    m5Available = true;
    calls = [];
    window.history.replaceState(null, "", "/");
    window.localStorage.clear();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      calls.push(path);
      if (path.startsWith("/api/m5/metadata")) return response({ available: m5Available });
      if (!primaryAvailable) return response({ error: "primary unavailable" }, false);
      if (path === "/api/health") return response({ status: "ok", database: "primary.sqlite", journal_mode: "wal", alert_count: 0 });
      if (path === "/api/runs") return response({ items: [], count: 0 });
      if (path === "/api/options") return response({ symbols: [], time_frames: [], strategies: [], ranks: [], entry_results: [] });
      if (path.startsWith("/api/alerts?")) return response({ items: [], total: 0, page: 1, page_size: 50, page_count: 0 });
      if (path.startsWith("/api/summary?")) return response({ total_count: 0, buy_count: 0, sell_count: 0, run_count: 0, symbol_count: 0, entry_result_counts: [] });
      throw new Error(`Unexpected API call: ${path}`);
    }));
  });

  afterEach(() => vi.unstubAllGlobals());

  it("opens an explicit M5 tab without bootstrapping the primary APIs", async () => {
    window.history.replaceState(null, "", "/?tab=m5&runId=97&sourceMode=TESTER");
    render(<App />);
    expect(await screen.findByText("M5独立画面")).toBeInTheDocument();
    expect(calls).toEqual([]);
    expect(screen.getByRole("tab", { name: "M5推移" })).toHaveAttribute("aria-selected", "true");
  });

  it("falls back to M5 when the default primary entry is unavailable", async () => {
    primaryAvailable = false;
    render(<App />);
    expect(await screen.findByText("M5独立画面")).toBeInTheDocument();
    expect(new URLSearchParams(window.location.search).get("tab")).toBe("m5");
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("keeps an explicitly requested H1 tab on primary failure", async () => {
    primaryAvailable = false;
    window.history.replaceState(null, "", "/?tab=h1");
    render(<App />);
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("primary unavailable"));
    expect(screen.getByText("H1既存画面")).toBeInTheDocument();
    expect(calls.some((path) => path.startsWith("/api/m5/"))).toBe(false);
  });

  it("does not fall back when neither database is available", async () => {
    primaryAvailable = false;
    m5Available = false;
    render(<App />);
    await waitFor(() => expect(calls.some((path) => path.startsWith("/api/m5/"))).toBe(true));
    expect(screen.queryByText("M5独立画面")).not.toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("primary unavailable");
  });

  it("loads primary lazily without borrowing the M5 run or date filter", async () => {
    window.history.replaceState(null, "", "/?tab=m5&runId=97&sourceMode=TESTER&from=2026-09-08T06:05");
    render(<App />);
    fireEvent.click(screen.getByRole("tab", { name: "アラート一覧" }));
    expect(await screen.findByText("既存アラート表")).toBeInTheDocument();
    const alertUrl = calls.find((path) => path.startsWith("/api/alerts?"));
    expect(alertUrl).toBeDefined();
    const parameters = new URLSearchParams(alertUrl!.split("?")[1]);
    expect(parameters.get("sourceMode")).toBe("LIVE");
    expect(parameters.has("runId")).toBe(false);
    expect(parameters.has("from")).toBe(false);
  });

  it("recognizes the M5 tab but never restores M5 filters as H1 filters", () => {
    expect(readViewerTab("?tab=m5")).toBe("m5");
    expect(readObservationSearchState("?tab=m5&runId=97&sourceMode=TESTER&jstTime=06:05"))
      .toEqual(DEFAULT_OBSERVATION_SEARCH_STATE);
  });
});
