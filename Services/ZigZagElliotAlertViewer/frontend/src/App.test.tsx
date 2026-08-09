import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

describe("App", () => {
  beforeEach(() => {
    window.history.replaceState(null, "", "/react/");
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/health") {
        return jsonResponse({ status: "ok", database: "test.sqlite", journal_mode: "wal", alert_count: 1 });
      }
      if (path === "/api/runs") {
        return jsonResponse({
          count: 2,
          items: [
            {
              id: 3,
              run_uid: "run-3",
              source_mode: "TESTER",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: "1",
              started_at_text: "2022.01.01 00:00:00",
              alert_count: 1,
              first_alert_time_text: "2026.07.30 19:00:00",
              last_alert_time_text: "2026.07.30 19:00:00",
              symbols: "AUDUSD",
            },
            {
              id: 2,
              run_uid: "run-2",
              source_mode: "TESTER",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: "1",
              started_at_text: "2022.01.01 00:00:00",
              alert_count: 0,
              first_alert_time_text: null,
              last_alert_time_text: null,
              symbols: null,
            },
          ],
        });
      }
      if (path === "/api/options") {
        return jsonResponse({ symbols: ["AUDUSD"], time_frames: ["H1"], strategies: ["MTF_3in3"], ranks: ["S"], entry_results: ["ENTRY"] });
      }
      if (path.startsWith("/api/alerts?")) {
        return jsonResponse({
          total: 1,
          page: 1,
          page_size: 50,
          page_count: 1,
          items: [{
            id: 74,
            run_id: 3,
            jst_time_text: "2026.07.31 01:00:00",
            server_time_text: "2026.07.30 19:00:00",
            symbol_name: "AUDUSD",
            time_frame_text: "H1",
            strategy: "MTF_3in3",
            side: "BUY",
            signal_count: 1,
            entry_count: 1,
            is_entry: true,
            entry_result: "ENTRY",
            current_elliot_label: "3-3-1",
            risk_pips: 50,
            spread_pips: 1.2,
            h1_structure_rank: "S",
            is_h1_structure_late: false,
            alert_title: "AUDUSD alert",
            mn1_side: "BUY",
            w1_side: "BUY",
            d1_side: "BUY",
            h4_side: "BUY",
            h1_side: "BUY",
            is_w1_aligned: true,
          }],
        });
      }
      if (path.startsWith("/api/summary?")) {
        return jsonResponse({ total_count: 1, buy_count: 1, sell_count: 0, w1_aligned_count: 1, w1_mismatched_count: 0, w1_unknown_count: 0, run_count: 1, symbol_count: 1 });
      }
      return jsonResponse({ error: `unexpected path: ${path}` });
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("selects the latest run with alerts and renders the first result", async () => {
    render(<App />);
    expect(await screen.findByText("接続済み・1件")).toBeInTheDocument();
    expect((await screen.findAllByText("AUDUSD")).length).toBeGreaterThan(0);
    expect(await screen.findByText("一致")).toBeInTheDocument();
    await waitFor(() => {
      const fetchMock = vi.mocked(fetch);
      expect(fetchMock.mock.calls.some(([path]) => String(path).includes("/api/alerts?runId=3"))).toBe(true);
    });
    expect(new URLSearchParams(window.location.search).get("runId")).toBe("3");
  });
});
