import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import {
  defaultObservationAnalysisInputHash,
  observationProfileMatchesSearch,
} from "./components/ObservationFilterPanel";
import { DEFAULT_OBSERVATION_SEARCH_STATE } from "./lib/observationSearchState";
import { REFRESH_INTERVAL_STORAGE_KEY } from "./lib/refreshSettings";

function jsonResponse(payload: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response;
}

let observationAvailable = true;
let observationOptionsFailures = 0;
const LIVE_ANALYSIS_PROFILE_HASH = "live-profile-hash";
const TESTER_ANALYSIS_PROFILE_HASH = "input-hash";
const ANALYSIS_PROFILE_TEXT = "ZIGZAG_ELLIOT_ANALYSIS_PROFILE_V1|STOCH_SHORT=5,3,3";
const ANALYSIS_VERSION = "ELLIOT_MN1_V2";

function analysisProfile(
  hash: string,
  mode: "LIVE" | "TESTER",
  observationCount: number,
  lastTime: number,
) {
  return {
    profile_key: `profile-${mode.toLowerCase()}`,
    analysis_profile_kind: "profile" as const,
    analysis_input_hash: hash,
    analysis_input_text: ANALYSIS_PROFILE_TEXT,
    analysis_version: ANALYSIS_VERSION,
    observation_count: observationCount,
    last_anchor_jst_time: lastTime,
    last_anchor_jst_time_text: mode === "LIVE"
      ? "2026.08.10 07:00:01"
      : "2026.08.10 07:00:00",
    source_modes: [mode],
    is_legacy: false,
  };
}

function observationTimeFrame(timeFrame: string, index: number) {
  return {
    id: 100 + index,
    observation_id: 9,
    time_frame: index + 1,
    time_frame_text: timeFrame,
    time_frame_order: index,
    is_anchor_time_frame: timeFrame === "H1",
    is_buy: index % 2 === 0,
    buy_sell_label: index % 2 === 0 ? "BUY" : "SELL",
    wave_count: 2,
    latest_wave_index: 1,
    is_wave_confirmed: true,
    is_wave_motive: true,
    is_wave_uptrend: index % 2 === 0,
    wave_trend_label: "Бе",
    previous_last_elliot_label: "2",
    point_count: 4,
    latest_elliot_index: 3,
    latest_elliot_label: "3",
    latest_sub_elliot_index: 1,
    latest_sub_elliot_label: "3-1",
    latest_point_time: 1786309200,
    latest_point_time_text: "2026.08.10 01:00:00",
    latest_point_jst_time: 1786330800,
    latest_point_jst_time_text: "2026.08.10 07:00:00",
    latest_point_rate: 1.23456,
    current_close: 1.235,
    stochastic_main_order_text: "SHORT>MIDDLE>LONG",
    stochastic_main_direction_text: "BUY",
    gmma_trend_count: 3,
    gmma_cross_count: 0,
    atr14_pips: 12.3,
    is_ema200_buy: true,
    is_ema200_sell: false,
  };
}

function observationsResponse() {
  return {
    available: observationAvailable,
    total: observationAvailable ? 1 : 0,
    page: 1,
    page_size: 50,
    page_count: observationAvailable ? 1 : 0,
    items: observationAvailable ? [{
      id: 9,
      run_id: 3,
      run_uid: "run-3",
      source_mode: "TESTER",
      source_server: "Test-Server",
      symbol_name: "AUDUSD",
      anchor_bar_time: 1786309200,
      anchor_bar_time_text: "2026.08.10 01:00:00",
      anchor_jst_time: 1786330800,
      anchor_jst_time_text: "2026.08.10 07:00:00",
      anchor_time_frame: 16385,
      anchor_time_frame_text: "H1",
      capture_phase: "BAR_OPEN_FIRST_SUCCESS",
      spread_pips: 1.2,
      analysis_version: ANALYSIS_VERSION,
      analysis_input_hash: TESTER_ANALYSIS_PROFILE_HASH,
      analysis_input_text: ANALYSIS_PROFILE_TEXT,
      analysis_profile_is_legacy: false,
      snapshot_hash: "snapshot-hash",
      time_frame_count: 5,
      created_at: 1786309201,
      created_at_text: "2026.08.10 01:00:01",
      time_frames: ["MN1", "W1", "D1", "H4", "H1"].map(observationTimeFrame),
    }] : [],
  };
}

describe("App", () => {
  beforeEach(() => {
    observationAvailable = true;
    observationOptionsFailures = 0;
    window.history.replaceState(null, "", "/");
    window.localStorage.clear();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/api/health") {
        return jsonResponse({ status: "ok", database: "test.sqlite", journal_mode: "wal", alert_count: 1 });
      }
      if (path === "/api/runs") {
        return jsonResponse({
          count: 3,
          items: [
            {
              id: 4,
              run_uid: "run-4",
              source_mode: "LIVE",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: ANALYSIS_VERSION,
              started_at_text: "2026.08.01 00:00:00",
              alert_count: 0,
              first_alert_time_text: null,
              last_alert_time_text: null,
              symbols: null,
            },
            {
              id: 3,
              run_uid: "run-3",
              source_mode: "TESTER",
              program_name: "ZigZagElliot",
              program_version: "1.21",
              strategy: "MTF_3in3",
              strategy_version: "1",
              analysis_version: ANALYSIS_VERSION,
              started_at_text: "2022.01.01 00:00:00",
              alert_count: 1,
              first_alert_time_text: "2026.07.30 19:00:00",
              last_alert_time_text: "2026.07.30 19:00:00",
              symbols: "AUDUSD",
              observation_count: 1,
              first_observation_time_text: "2026.08.10 01:00:00",
              last_observation_time_text: "2026.08.10 01:00:00",
              first_observation_jst_time: 1786330800,
              first_observation_jst_time_text: "2026.08.10 07:00:00",
              last_observation_jst_time: 1786330800,
              last_observation_jst_time_text: "2026.08.10 07:00:00",
              observation_symbols: "AUDUSD",
              analysis_input_text: ANALYSIS_PROFILE_TEXT,
              analysis_input_hash: TESTER_ANALYSIS_PROFILE_HASH,
              analysis_profile_is_legacy: false,
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
        return jsonResponse({ symbols: ["AUDUSD"], time_frames: ["H1", "M5", "D1"], strategies: ["MTF_3in3"], ranks: ["S"], entry_results: ["ENTRY"] });
      }
      if (path === "/api/observation-options") {
        if (observationOptionsFailures > 0) {
          observationOptionsFailures -= 1;
          throw new Error("Profile条件を読み込めませんでした");
        }
        return jsonResponse({
          available: observationAvailable,
          symbols: observationAvailable ? ["AUDUSD"] : [],
          source_modes: observationAvailable ? ["TESTER"] : [],
          analysis_versions: observationAvailable ? ["1"] : [],
          analysis_profile_available: observationAvailable,
          analysis_profile_reason: observationAvailable ? "" : "observation table schema is not supported",
          analysis_profiles: observationAvailable ? [
            analysisProfile(LIVE_ANALYSIS_PROFILE_HASH, "LIVE", 2, 1786330801),
            analysisProfile(TESTER_ANALYSIS_PROFILE_HASH, "TESTER", 1, 1786330800),
          ] : [],
          default_analysis_input_hash: observationAvailable ? LIVE_ANALYSIS_PROFILE_HASH : null,
          default_analysis_input_hashes: {
            all: observationAvailable ? LIVE_ANALYSIS_PROFILE_HASH : null,
            LIVE: observationAvailable ? LIVE_ANALYSIS_PROFILE_HASH : null,
            TESTER: observationAvailable ? TESTER_ANALYSIS_PROFILE_HASH : null,
          },
          default_analysis_profile_keys: {
            all: observationAvailable ? "profile-live" : null,
            LIVE: observationAvailable ? "profile-live" : null,
            TESTER: observationAvailable ? "profile-tester" : null,
          },
          default_analysis_profiles: {
            all: observationAvailable
              ? analysisProfile(LIVE_ANALYSIS_PROFILE_HASH, "LIVE", 2, 1786330801)
              : null,
            LIVE: observationAvailable
              ? analysisProfile(LIVE_ANALYSIS_PROFILE_HASH, "LIVE", 2, 1786330801)
              : null,
            TESTER: observationAvailable
              ? analysisProfile(TESTER_ANALYSIS_PROFILE_HASH, "TESTER", 1, 1786330800)
              : null,
          },
        });
      }
      if (path.startsWith("/api/observations?")) {
        return jsonResponse(observationsResponse());
      }
      if (path === "/api/observations/9") {
        const observation = observationsResponse().items[0];
        return jsonResponse({
          available: observationAvailable,
          observation: observationAvailable ? observation : null,
          time_frames: observationAvailable ? observation.time_frames : [],
          navigation: {
            older: null,
            newer: null,
          },
        });
      }
      if (path.startsWith("/api/observation-summary?")) {
        return jsonResponse({
          available: observationAvailable,
          total_count: observationAvailable ? 1 : 0,
          live_count: 0,
          tester_count: observationAvailable ? 1 : 0,
          run_count: observationAvailable ? 1 : 0,
          symbol_count: observationAvailable ? 1 : 0,
          first_anchor_bar_time: observationAvailable ? 1786309200 : null,
          first_anchor_bar_time_text: observationAvailable ? "2026.08.10 01:00:00" : null,
          last_anchor_bar_time: observationAvailable ? 1786309200 : null,
          last_anchor_bar_time_text: observationAvailable ? "2026.08.10 01:00:00" : null,
          first_anchor_jst_time: observationAvailable ? 1786330800 : null,
          first_anchor_jst_time_text: observationAvailable ? "2026.08.10 07:00:00" : null,
          last_anchor_jst_time: observationAvailable ? 1786330800 : null,
          last_anchor_jst_time_text: observationAvailable ? "2026.08.10 07:00:00" : null,
        });
      }
      if (path === "/api/alerts/74") {
        return jsonResponse({
          alert: {
            id: 74, run_id: 4, symbol_name: "AUDUSD", side: "BUY",
            current_bar_time_text: "2026.07.30 19:00:00", alert_title: "AUDUSD alert",
            jst_time_text: "2026.07.31 01:00:00", server_time_text: "2026.07.30 19:00:00",
            reference_price: 1.2, is_stop_loss_available: true, stop_loss: 1.1, risk_pips: 50,
            h1_structure_rank: "S", is_h1_structure_late: false, strategy: "MTF_3in3",
            signal_count: 1, entry_count: 1, is_judge: true, is_entry_count_match: true,
            is_entry_evaluated: true, is_entry_wave: true, is_ema200_distance_within: true,
            is_alert: true, is_entry: true, entry_result: "ENTRY", current_elliot_label: "3-3-1",
            close_ema200_diff_pips: 10, max_close_ema200_diff_pips: 25, spread_pips: 1.2,
            currency_strength_status: 0, is_currency_strength_available: false,
            long_medium_rank_difference: 0, medium_short_rank_difference: 0,
            market_signal_key: "market-74", alert_text: "", is_w1_aligned: true,
            w1_confirmation_mode: "DIRECTION_OR_EMA200",
            w1_confirmation_state: "STRONG",
            is_w1_confirmation_available: true,
            is_w1_confirmation_valid: true,
            is_w1_direction_matched: true,
            w1_ema200_direction: "BUY",
            is_w1_ema200_matched: true,
            is_w1_confirmation_passed: true,
            is_w1_confirmation_legacy: false,
          },
          run: { id: 4, source_mode: "LIVE", program_version: "1.21", tester_model: "" },
          w1: null,
        });
      }
      if (path === "/api/alerts/74/timeframes" || path === "/api/alerts/74/points") {
        return jsonResponse({ items: [], count: 0 });
      }
      if (path.startsWith("/api/alerts?")) {
        return jsonResponse({
          total: 1,
          page: 1,
          page_size: 50,
          page_count: 1,
          items: [{
            id: 74,
            run_id: 4,
            source_mode: "LIVE",
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
            w1_confirmation_mode: "DIRECTION_OR_EMA200",
            w1_confirmation_state: "STRONG",
            is_w1_confirmation_available: true,
            is_w1_confirmation_valid: true,
            is_w1_direction_matched: true,
            w1_ema200_direction: "BUY",
            is_w1_ema200_matched: true,
            is_w1_confirmation_passed: true,
            is_w1_confirmation_legacy: false,
          }],
        });
      }
      if (path.startsWith("/api/summary?")) {
        return jsonResponse({ total_count: 1, database_total_count: 451, buy_count: 1, sell_count: 0, w1_aligned_count: 1, w1_mismatched_count: 0, w1_unknown_count: 0, run_count: 1, symbol_count: 1 });
      }
      return jsonResponse({ error: `unexpected path: ${path}` });
    }));
  });

  it("does not borrow another mode's analysis profile default", () => {
    expect(defaultObservationAnalysisInputHash({
      available: true,
      symbols: [],
      source_modes: ["TESTER"],
      analysis_versions: ["ELLIOT_MN1_V2"],
      default_analysis_input_hash: TESTER_ANALYSIS_PROFILE_HASH,
      default_analysis_input_hashes: {
        all: TESTER_ANALYSIS_PROFILE_HASH,
        LIVE: null,
        TESTER: TESTER_ANALYSIS_PROFILE_HASH,
      },
    }, "LIVE")).toBe("");
  });

  it("keeps analysis versions and Legacy cohorts separate when hashes match", () => {
    const profile = analysisProfile(TESTER_ANALYSIS_PROFILE_HASH, "TESTER", 1, 1);
    expect(observationProfileMatchesSearch(profile, {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      sourceMode: "TESTER",
      analysisVersion: ANALYSIS_VERSION,
      analysisInputHash: TESTER_ANALYSIS_PROFILE_HASH,
      analysisProfileKind: "profile",
    })).toBe(true);
    expect(observationProfileMatchesSearch(profile, {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      sourceMode: "TESTER",
      analysisVersion: "ELLIOT_MN1_V3",
      analysisInputHash: TESTER_ANALYSIS_PROFILE_HASH,
      analysisProfileKind: "profile",
    })).toBe(false);
    expect(observationProfileMatchesSearch(profile, {
      ...DEFAULT_OBSERVATION_SEARCH_STATE,
      sourceMode: "TESTER",
      analysisVersion: ANALYSIS_VERSION,
      analysisInputHash: TESTER_ANALYSIS_PROFILE_HASH,
      analysisProfileKind: "legacy",
    })).toBe(false);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("defaults to all LIVE runs without falling back to a TESTER run", async () => {
    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    expect(screen.getByRole("tabpanel")).toHaveClass("viewer-tab-panel");
    expect(screen.queryByRole("link", { name: "従来画面" })).not.toBeInTheDocument();
    const header = screen.getByRole("banner");
    const viewerNavigation = within(header).getByRole("navigation", { name: "Viewer表示切替" });
    expect(viewerNavigation).toContainElement(screen.getByRole("tab", { name: "アラート一覧" }));
    expect(viewerNavigation.compareDocumentPosition(screen.getByRole("heading", { level: 1 })) & Node.DOCUMENT_POSITION_FOLLOWING)
      .toBeTruthy();
    const searchSidebar = screen.getByRole("complementary", { name: "アラート検索条件" });
    const searchHeading = screen.getByRole("heading", { name: "アラート検索" });
    const searchToggle = screen.getByRole("button", { name: "検索条件を閉じる" });
    expect(searchSidebar).toContainElement(searchHeading);
    expect(searchSidebar.parentElement).toHaveClass("viewer-workspace");
    expect((await screen.findAllByText("AUDUSD")).length).toBeGreaterThan(0);
    expect(await screen.findByText("両方一致")).toBeInTheDocument();
    expect(screen.getByText("STRONG / EMA BUY")).toBeInTheDocument();
    const snapshotsLabel = screen.getByText("SNAPSHOTS");
    const resultsTitleLine = snapshotsLabel.closest(".results-title-line");
    expect(resultsTitleLine).toContainElement(screen.getByRole("heading", { name: "アラート一覧" }));
    expect(resultsTitleLine).toContainElement(screen.getByText("1件中 1–1件"));
    const refreshState = resultsTitleLine?.parentElement?.querySelector(".refresh-state");
    expect(refreshState?.children).toHaveLength(2);
    expect(refreshState?.firstElementChild?.tagName).toBe("SPAN");
    expect(refreshState?.lastElementChild?.tagName).toBe("SMALL");
    const gridToolbar = screen.getByRole("toolbar", { name: "グリッド表示設定" });
    const refreshControls = screen.getByLabelText("自動更新間隔").closest(".refresh-controls");
    expect(resultsTitleLine?.parentElement).toContainElement(gridToolbar);
    expect(refreshControls).not.toBeNull();
    expect((refreshControls as HTMLElement).compareDocumentPosition(gridToolbar) & Node.DOCUMENT_POSITION_FOLLOWING)
      .toBeTruthy();
    expect(screen.getByRole("region", { name: "ZigZagElliotアラート検索結果" }))
      .not.toContainElement(gridToolbar);
    const resultSummary = screen.getByRole("region", { name: "検索結果集計" });
    const conditionSummary = screen.getByRole("region", { name: "適用中の検索条件" });
    expect(resultSummary.parentElement).toHaveClass("viewer-summary-bar");
    expect(searchToggle).toHaveAttribute("aria-controls", "alertFilterSidebar");
    expect(searchToggle.compareDocumentPosition(conditionSummary) & Node.DOCUMENT_POSITION_FOLLOWING)
      .toBeTruthy();
    expect(within(resultSummary).getByText("検索該当 / DB全体").nextElementSibling)
      .toHaveTextContent("1/451");
    await waitFor(() => {
      const fetchMock = vi.mocked(fetch);
      expect(fetchMock.mock.calls.some(([path]) => {
        const requestedPath = String(path);
        return requestedPath.startsWith("/api/alerts?sourceMode=LIVE")
          && !requestedPath.includes("runId=");
      })).toBe(true);
    });
    const parameters = new URLSearchParams(window.location.search);
    expect(parameters.get("sourceMode")).toBe("LIVE");
    expect(parameters.has("runId")).toBe(false);
  });

  it("opens the H1 view directly with JST time and five timeframe comparisons", async () => {
    window.history.replaceState(
      null,
      "",
      "/?tab=h1&sourceMode=TESTER&runId=3&symbol=AUDUSD&from=2026-08-01&to=2026-08-10&jstTime=07%3A00&syncTimeFrame=D1&syncTimeFrame=MN1&sort=anchor_bar_time",
    );
    render(<App />);

    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    const tabPanel = screen.getByRole("tabpanel");
    expect(tabPanel).toHaveClass("viewer-tab-panel");
    const workspace = tabPanel.querySelector(".viewer-workspace");
    const sidebar = within(tabPanel).getByRole("complementary", { name: "H1推移検索条件" });
    const resultsColumn = tabPanel.querySelector(".viewer-results-column");
    expect(workspace).toContainElement(sidebar);
    expect(sidebar.querySelector(".observation-filter-panel.sidebar-layout")).toBeInTheDocument();
    const observationToggle = within(tabPanel).getByRole("button", { name: "検索条件を閉じる" });
    const observationConditionSummary = within(tabPanel).getByRole("region", { name: "適用中の検索条件" });
    expect(observationToggle).toHaveAttribute("aria-controls", "observationFilterSidebar");
    expect(observationToggle.compareDocumentPosition(observationConditionSummary) & Node.DOCUMENT_POSITION_FOLLOWING)
      .toBeTruthy();
    expect(observationConditionSummary).toHaveTextContent("JST期間 2026-08-01 – 2026-08-10");
    expect(observationConditionSummary).toHaveTextContent("JST時刻 07:00");
    expect(observationConditionSummary).toHaveTextContent("上位足同期 MN1・D1");
    await waitFor(() => {
      expect(observationConditionSummary).toHaveTextContent(
        `Profile ${ANALYSIS_VERSION}/${TESTER_ANALYSIS_PROFILE_HASH}`,
      );
    });
    expect(screen.getByLabelText("Run")).toHaveTextContent(
      "JST 2026.08.10 07:00:00 – 2026.08.10 07:00:00",
    );
    expect(screen.getByLabelText("分析Profile")).toHaveTextContent(
      `${ANALYSIS_VERSION}｜Profile｜${TESTER_ANALYSIS_PROFILE_HASH}`,
    );
    expect(screen.getByRole("combobox", { name: "時刻（JST）" })).toHaveTextContent("07:00");
    expect(screen.getByRole("combobox", { name: "上位足同期（H1方向）" }))
      .toHaveTextContent("MN1・D1");
    expect(tabPanel.querySelector(".viewer-summary-bar"))
      .toContainElement(tabPanel.querySelector(".observation-summary-strip"));
    expect(resultsColumn).toContainElement(tabPanel.querySelector(".results-panel"));
    expect(await screen.findByRole("columnheader", { name: /JST日時/ })).toBeInTheDocument();
    expect(screen.getByText("2026.08.10 07:00:00")).toBeInTheDocument();
    expect(screen.getByText("Server 2026.08.10 01:00:00 / H1新規足")).toBeInTheDocument();
    for (const timeFrame of ["MN1", "W1", "D1", "H4", "H1"]) {
      expect(screen.getByRole("columnheader", { name: timeFrame })).toBeInTheDocument();
    }
    expect(screen.getAllByLabelText(/^(▲ 上昇|▼ 下降)、/)).toHaveLength(5);
    expect(screen.getAllByText(/^[▲▼]・/)).toHaveLength(5);
    expect(screen.getAllByText(/Elliott ▲3 \/ 3-1/)).toHaveLength(3);
    expect(screen.getAllByText(/Elliott ▼3 \/ 3-1/)).toHaveLength(2);
    expect(screen.getAllByText(/GMMA T\+3\/C0/)).toHaveLength(5);
    expect(screen.getByLabelText("EMA200判定 対象外。MN1は計算を省略"))
      .toHaveTextContent("EMA200 SKIP");
    expect(screen.getAllByLabelText("EMA200判定 BUY")).toHaveLength(4);
    expect(screen.queryByText("Бе")).not.toBeInTheDocument();
    expect(screen.queryByText(/最新点 JST 2026\.08\.10 07:00:00/)).not.toBeInTheDocument();
    const detailButton = screen.getByRole("button", {
      name: "AUDUSD JST 2026.08.10 07:00:00 のH1推移詳細を表示",
    });
    fireEvent.click(detailButton);
    const detailDialog = await screen.findByRole("dialog");
    expect(within(detailDialog).getByRole("heading", {
      name: "AUDUSD / 2026.08.10 07:00:00",
    })).toBeInTheDocument();
    expect(detailDialog).toHaveClass("observation-grid-mode");
    expect(within(detailDialog).getByText("TIMEFRAME COMPARISON")).toBeInTheDocument();
    expect(within(detailDialog).getByRole("button", { name: "全画面グリッド" }))
      .toHaveAttribute("aria-pressed", "true");
    expect(await within(detailDialog).findByRole("grid", {
      name: "時間足別 H1新規足スナップショットグリッド",
    })).toBeInTheDocument();
    fireEvent.click(within(detailDialog).getByRole("button", { name: "カード表示" }));
    expect(detailDialog).not.toHaveClass("observation-grid-mode");
    expect(within(detailDialog).getAllByText("最新点 JST")).toHaveLength(5);
    expect(within(detailDialog).getByText(`Profile / ${TESTER_ANALYSIS_PROFILE_HASH}`)).toBeInTheDocument();
    expect(within(detailDialog).getByText(ANALYSIS_PROFILE_TEXT)).toBeInTheDocument();
    expect(vi.mocked(fetch).mock.calls.some(([path]) => String(path) === "/api/observations/9")).toBe(true);
    fireEvent.click(within(detailDialog).getByRole("button", { name: "H1観測詳細を閉じる" }));
    await waitFor(() => expect(detailButton).toHaveFocus());
    fireEvent.click(detailButton);
    const reopenedDetailDialog = await screen.findByRole("dialog");
    expect(reopenedDetailDialog).toHaveClass("observation-grid-mode");
    expect(within(reopenedDetailDialog).getByRole("button", { name: "全画面グリッド" }))
      .toHaveAttribute("aria-pressed", "true");
    fireEvent.click(within(reopenedDetailDialog).getByRole("button", {
      name: "H1観測詳細を閉じる",
    }));
    await waitFor(() => expect(detailButton).toHaveFocus());
    expect(screen.getByLabelText("開始日（JST）")).toHaveValue("2026-08-01");
    expect(screen.getByLabelText("終了日（JST）")).toHaveValue("2026-08-10");
    expect(new URLSearchParams(window.location.search).get("tab")).toBe("h1");

    const calls = vi.mocked(fetch).mock.calls.map(([path]) => String(path));
    expect(calls.some((path) => path.startsWith("/api/observations?sourceMode=TESTER")
      && path.includes(`analysisVersion=${ANALYSIS_VERSION}`)
      && path.includes(`analysisInputHash=${TESTER_ANALYSIS_PROFILE_HASH}`)
      && path.includes("analysisProfileKind=profile")
      && path.includes("jstTime=07%3A00")
      && path.includes("syncTimeFrame=MN1&syncTimeFrame=D1")
      && path.includes("sort=anchor_jst_time"))).toBe(true);
    expect(calls.some((path) => path.startsWith("/api/observation-summary?sourceMode=TESTER")
      && path.includes(`analysisVersion=${ANALYSIS_VERSION}`)
      && path.includes(`analysisInputHash=${TESTER_ANALYSIS_PROFILE_HASH}`)
      && path.includes("analysisProfileKind=profile")
      && path.includes("jstTime=07%3A00")
      && path.includes("syncTimeFrame=MN1&syncTimeFrame=D1")
      && path.includes("sort=anchor_jst_time"))).toBe(true);
    expect(calls.some((path) => path.startsWith("/api/alerts?"))).toBe(false);
    expect(new URLSearchParams(window.location.search).get("sort")).toBe("anchor_jst_time");
    expect(new URLSearchParams(window.location.search).get("analysisInputHash"))
      .toBe(TESTER_ANALYSIS_PROFILE_HASH);
    expect(new URLSearchParams(window.location.search).get("analysisVersion"))
      .toBe(ANALYSIS_VERSION);
    expect(new URLSearchParams(window.location.search).get("analysisProfileKind"))
      .toBe("profile");
    expect(new URLSearchParams(window.location.search).get("jstTime")).toBe("07:00");
    expect(new URLSearchParams(window.location.search).getAll("syncTimeFrame"))
      .toEqual(["MN1", "D1"]);

    fireEvent.click(within(screen.getByRole("columnheader", { name: /JST日時/ }))
      .getByRole("button", { name: /JST日時/ }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("tab")).toBe("h1");
      expect(parameters.get("sort")).toBe("anchor_jst_time");
      expect(parameters.get("order")).toBe("asc");
    });
  });

  it("selects the latest analysis profile for an H1 mode before loading observations", async () => {
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE");
    render(<App />);

    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    await waitFor(() => {
      expect(new URLSearchParams(window.location.search).get("analysisInputHash"))
        .toBe(LIVE_ANALYSIS_PROFILE_HASH);
    });
    const observationCalls = vi.mocked(fetch).mock.calls
      .map(([path]) => String(path))
      .filter((path) => path.startsWith("/api/observations?"));
    expect(observationCalls.length).toBeGreaterThan(0);
    expect(observationCalls.every((path) => path.includes(
      `analysisInputHash=${LIVE_ANALYSIS_PROFILE_HASH}`,
    ))).toBe(true);
    expect(observationCalls.every((path) => path.includes(
      `analysisVersion=${ANALYSIS_VERSION}`,
    ))).toBe(true);
    expect(observationCalls.every((path) => path.includes(
      "analysisProfileKind=profile",
    ))).toBe(true);
    expect(screen.getByLabelText("分析Profile")).toHaveTextContent(
      `${ANALYSIS_VERSION}｜Profile｜${LIVE_ANALYSIS_PROFILE_HASH.slice(0, 12)}`,
    );
  });

  it("preserves an explicit all-profile H1 search", async () => {
    window.history.replaceState(
      null,
      "",
      "/?tab=h1&sourceMode=TESTER&analysisInputHash=all",
    );
    render(<App />);

    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    await waitFor(() => {
      const observationCalls = vi.mocked(fetch).mock.calls
        .map(([path]) => String(path))
        .filter((path) => path.startsWith("/api/observations?"));
      expect(observationCalls.length).toBeGreaterThan(0);
      expect(observationCalls.every((path) => !path.includes("analysisInputHash="))).toBe(true);
      expect(observationCalls.every((path) => !path.includes("analysisVersion="))).toBe(true);
      expect(observationCalls.every((path) => !path.includes("analysisProfileKind="))).toBe(true);
    });
    expect(new URLSearchParams(window.location.search).get("analysisInputHash")).toBe("all");
    expect(new URLSearchParams(window.location.search).has("analysisVersion")).toBe(false);
    expect(new URLSearchParams(window.location.search).has("analysisProfileKind")).toBe(false);
    expect(screen.getByLabelText("分析Profile")).toHaveTextContent("すべてのProfile");
  });

  it("waits for analysis profiles and retries before the first H1 data request", async () => {
    observationOptionsFailures = 1;
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE");
    render(<App />);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Profile条件を読み込めませんでした",
    );
    expect(vi.mocked(fetch).mock.calls.some(([path]) => (
      String(path).startsWith("/api/observations?")
    ))).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await waitFor(() => {
      const observationCalls = vi.mocked(fetch).mock.calls
        .map(([path]) => String(path))
        .filter((path) => path.startsWith("/api/observations?"));
      expect(observationCalls.length).toBeGreaterThan(0);
      expect(observationCalls.every((path) => path.includes(
        `analysisInputHash=${LIVE_ANALYSIS_PROFILE_HASH}`,
      ))).toBe(true);
    });
  });

  it("applies and resets the H1 JST hour and multiple higher-timeframe synchronizations", async () => {
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE");
    render(<App />);

    const jstTimeSelect = await screen.findByRole("combobox", { name: "時刻（JST）" });
    await waitFor(() => {
      expect(new URLSearchParams(window.location.search).get("analysisInputHash"))
        .toBe(LIVE_ANALYSIS_PROFILE_HASH);
    });
    fireEvent.mouseDown(jstTimeSelect);
    fireEvent.click(screen.getByRole("option", { name: "07:00" }));

    const synchronizationSelect = screen.getByRole("combobox", {
      name: "上位足同期（H1方向）",
    });
    fireEvent.mouseDown(synchronizationSelect);
    fireEvent.click(screen.getByRole("option", { name: "MN1" }));
    fireEvent.click(screen.getByRole("option", { name: "D1" }));
    fireEvent.keyDown(screen.getByRole("listbox"), { key: "Escape" });
    await waitFor(() => expect(screen.queryByRole("listbox")).not.toBeInTheDocument());

    expect(jstTimeSelect).toHaveTextContent("07:00");
    expect(synchronizationSelect).toHaveTextContent("MN1・D1");
    expect(new URLSearchParams(window.location.search).has("jstTime")).toBe(false);
    expect(screen.getByRole("region", { name: "適用中の検索条件" }))
      .toHaveTextContent("未検索の変更あり");

    fireEvent.click(screen.getByRole("button", { name: "検索" }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("jstTime")).toBe("07:00");
      expect(parameters.getAll("syncTimeFrame")).toEqual(["MN1", "D1"]);
      const requestedPaths = vi.mocked(fetch).mock.calls.map(([path]) => String(path));
      for (const prefix of ["/api/observations?", "/api/observation-summary?"]) {
        expect(requestedPaths.some((path) => {
          if (!path.startsWith(prefix)) return false;
          const searchParams = new URL(path, "http://localhost").searchParams;
          return searchParams.get("jstTime") === "07:00"
            && searchParams.getAll("syncTimeFrame").join(",") === "MN1,D1";
        })).toBe(true);
      }
    });

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.has("jstTime")).toBe(false);
      expect(parameters.has("syncTimeFrame")).toBe(false);
      expect(jstTimeSelect).toHaveTextContent("すべて");
      expect(synchronizationSelect).toHaveTextContent("指定なし");
    });
  });

  it("keeps each filter panel collapsed independently when switching tabs", async () => {
    render(<App />);

    expect(await screen.findByRole("complementary", { name: "アラート検索条件" })).toBeInTheDocument();
    expect(screen.queryByRole("complementary", { name: "H1推移検索条件" })).not.toBeInTheDocument();
    const alertCloseButton = await screen.findByRole("button", { name: "検索条件を閉じる" });
    const alertWorkspace = document.querySelector("#viewer-tabpanel-alerts .viewer-workspace");
    const alertSidebar = document.getElementById("alertFilterSidebar");
    expect(alertWorkspace).not.toHaveClass("filter-sidebar-collapsed");
    expect(alertSidebar).not.toHaveAttribute("hidden");
    alertCloseButton.focus();
    fireEvent.click(alertCloseButton);
    const alertOpenButton = screen.getByRole("button", { name: "検索条件を開く" });
    expect(alertOpenButton).toHaveFocus();
    expect(alertOpenButton).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("button", { name: "条件をリセット" })).not.toBeInTheDocument();
    expect(alertWorkspace).toHaveClass("filter-sidebar-collapsed");
    expect(alertSidebar).toHaveAttribute("hidden");
    expect(alertSidebar).not.toBeVisible();
    const alertConditionSummary = screen.getByRole("region", { name: "適用中の検索条件" });
    const alertCountSummary = screen.getByRole("region", { name: "検索結果集計" });
    expect(alertConditionSummary).toHaveTextContent("LIVE / 全Run / 全通貨 / 全時間足 / BUY＋SELL");
    expect(alertConditionSummary.parentElement).toBe(alertCountSummary.parentElement);
    expect(alertConditionSummary.parentElement).toHaveClass("viewer-summary-bar");
    expect(alertCountSummary).toHaveClass("compact");

    fireEvent.click(screen.getByRole("tab", { name: "H1推移" }));
    expect(await screen.findByRole("complementary", { name: "H1推移検索条件" })).toBeInTheDocument();
    expect(screen.queryByRole("complementary", { name: "アラート検索条件" })).not.toBeInTheDocument();
    const observationCloseButton = await screen.findByRole("button", { name: "検索条件を閉じる" });
    const observationWorkspace = document.querySelector("#viewer-tabpanel-h1 .viewer-workspace");
    const observationSidebar = document.getElementById("observationFilterSidebar");
    expect(observationWorkspace).not.toHaveClass("filter-sidebar-collapsed");
    expect(observationSidebar).not.toHaveAttribute("hidden");
    expect(observationCloseButton).toHaveAttribute("aria-expanded", "true");
    observationCloseButton.focus();
    fireEvent.click(observationCloseButton);
    const observationOpenButton = screen.getByRole("button", { name: "検索条件を開く" });
    expect(observationOpenButton).toHaveFocus();
    expect(observationOpenButton).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("button", { name: "条件をリセット" })).not.toBeInTheDocument();
    expect(observationWorkspace).toHaveClass("filter-sidebar-collapsed");
    expect(observationSidebar).toHaveAttribute("hidden");
    expect(observationSidebar).not.toBeVisible();
    const observationConditionSummary = screen.getByRole("region", { name: "適用中の検索条件" });
    expect(observationConditionSummary.parentElement).toHaveClass("viewer-summary-bar");
    expect(observationConditionSummary.parentElement?.querySelector(".observation-summary-strip"))
      .toHaveClass("compact");

    fireEvent.click(screen.getByRole("tab", { name: "アラート一覧" }));
    const restoredAlertOpenButton = await screen.findByRole("button", { name: "検索条件を開く" });
    expect(restoredAlertOpenButton).toHaveAttribute("aria-expanded", "false");
    expect(document.querySelector("#viewer-tabpanel-alerts .viewer-workspace"))
      .toHaveClass("filter-sidebar-collapsed");

    fireEvent.click(screen.getByRole("tab", { name: "H1推移" }));
    const restoredObservationOpenButton = await screen.findByRole("button", { name: "検索条件を開く" });
    expect(restoredObservationOpenButton).toHaveAttribute("aria-expanded", "false");
    expect(document.querySelector("#viewer-tabpanel-h1 .viewer-workspace"))
      .toHaveClass("filter-sidebar-collapsed");
  });

  it("shows an unused state when the observation tables do not exist", async () => {
    observationAvailable = false;
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE");
    render(<App />);
    expect(await screen.findByText("H1観測はまだ利用されていません")).toBeInTheDocument();
    expect(screen.getByText("H1観測DB 未利用")).toBeInTheDocument();
  });

  it("drops an observation Run that does not match the explicit source mode", async () => {
    window.history.replaceState(null, "", "/?tab=h1&sourceMode=LIVE&runId=3");
    render(<App />);
    expect(await screen.findByRole("tab", { name: "H1推移", selected: true })).toBeInTheDocument();
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sourceMode")).toBe("LIVE");
      expect(parameters.has("runId")).toBe(false);
    });
    const observationCalls = vi.mocked(fetch).mock.calls
      .map(([path]) => String(path))
      .filter((path) => path.startsWith("/api/observations?"));
    expect(observationCalls.length).toBeGreaterThan(0);
    expect(observationCalls.every((path) => !path.includes("runId="))).toBe(true);
  });

  it("infers TESTER for a legacy URL containing only runId", async () => {
    window.history.replaceState(null, "", "/?runId=3");
    render(<App />);

    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sourceMode")).toBe("TESTER");
      expect(parameters.get("runId")).toBe("3");
    });
    await waitFor(() => {
      const fetchMock = vi.mocked(fetch);
      expect(fetchMock.mock.calls.some(([path]) => {
        const requestedPath = String(path);
        return requestedPath.startsWith("/api/alerts?sourceMode=TESTER&runId=3");
      })).toBe(true);
    });
  });

  it("filters Run choices by mode and clears runId when the mode changes", async () => {
    window.history.replaceState(null, "", "/?sourceMode=TESTER&runId=3");
    render(<App />);

    const modeSelect = await screen.findByLabelText("実行モード");
    const runSelect = screen.getByLabelText("実行Run") as HTMLSelectElement;
    await waitFor(() => expect(runSelect.value).toBe("3"));
    expect(within(runSelect).getByRole("option", { name: /TESTER｜Run 3/ })).toBeInTheDocument();
    expect(within(runSelect).queryByRole("option", { name: /LIVE｜Run 4/ })).not.toBeInTheDocument();

    fireEvent.change(modeSelect, { target: { value: "LIVE" } });
    expect(runSelect.value).toBe("");
    expect(within(runSelect).getByRole("option", { name: /LIVE｜Run 4/ })).toBeInTheDocument();
    expect(within(runSelect).queryByRole("option", { name: /TESTER｜Run 3/ })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    const parameters = new URLSearchParams(window.location.search);
    expect(parameters.get("sourceMode")).toBe("LIVE");
    expect(parameters.has("runId")).toBe(false);
  });

  it("applies and resets multiple alert time frame filters", async () => {
    render(<App />);

    const timeFrameSelect = await screen.findByRole("combobox", { name: "時間足" });
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "H1" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    fireEvent.mouseDown(timeFrameSelect);
    fireEvent.click(screen.getByRole("option", { name: "M5" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(timeFrameSelect).toHaveTextContent("H1・M5");
    expect(new URLSearchParams(window.location.search).has("timeFrame")).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    const pendingConditionSummary = screen.getByRole("region", { name: "適用中の検索条件" });
    expect(pendingConditionSummary).toHaveTextContent("全時間足");
    expect(within(pendingConditionSummary).getByText("未検索の変更あり")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "検索条件を開く" }));

    fireEvent.click(screen.getByRole("button", { name: "検索" }));
    await waitFor(() => {
      expect(new URLSearchParams(window.location.search).getAll("timeFrame")).toEqual(["H1", "M5"]);
      const requestedPaths = vi.mocked(fetch).mock.calls.map(([path]) => String(path));
      for (const prefix of ["/api/alerts?", "/api/summary?"]) {
        expect(requestedPaths.some((path) => (
          path.startsWith(prefix)
          && new URL(path, "http://localhost").searchParams.getAll("timeFrame").join(",") === "H1,M5"
        ))).toBe(true);
      }
    });

    fireEvent.click(screen.getByRole("button", { name: "検索条件を閉じる" }));
    const appliedConditionSummary = screen.getByRole("region", { name: "適用中の検索条件" });
    expect(appliedConditionSummary).toHaveTextContent("H1・M5");
    expect(within(appliedConditionSummary).queryByText("未検索の変更あり")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "検索条件を開く" }));

    fireEvent.click(screen.getByRole("button", { name: "条件をリセット" }));
    await waitFor(() => {
      expect(timeFrameSelect).toHaveTextContent("すべて");
      expect(new URLSearchParams(window.location.search).has("timeFrame")).toBe(false);
    });
  });

  it("opens an alert detail and restores focus to its trigger after closing", async () => {
    render(<App />);
    const detailButton = await screen.findByRole("button", { name: "AUDUSD BUY 2026.07.31 01:00:00 の詳細を表示" });
    detailButton.focus();
    fireEvent.click(detailButton);
    expect(await screen.findByRole("heading", { name: "AUDUSD BUY / 2026.07.30 19:00:00" })).toBeInTheDocument();
    const dialog = screen.getByRole("dialog");
    fireEvent(dialog, new Event("cancel", { bubbles: false, cancelable: true }));
    await waitFor(() => expect(detailButton).toHaveFocus());
  });

  it("opens TIMEFRAME COMPARISON directly and restores focus to its trigger", async () => {
    render(<App />);
    const comparisonButton = await screen.findByRole("button", {
      name: "AUDUSD BUY 2026.07.31 01:00:00 のTIMEFRAME COMPARISONを表示",
    });
    comparisonButton.focus();
    fireEvent.click(comparisonButton);

    expect(await screen.findByText("TIMEFRAME COMPARISON")).toBeInTheDocument();
    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveClass("observation-grid-mode");
    expect(screen.getByRole("button", { name: "TF比較" }))
      .toHaveAttribute("aria-pressed", "true");

    fireEvent(dialog, new Event("cancel", { bubbles: false, cancelable: true }));
    await waitFor(() => expect(comparisonButton).toHaveFocus());
  });

  it("uses a grid header to request whole-result server sorting", async () => {
    render(<App />);
    const firstHeader = await screen.findByRole("columnheader", { name: "通貨" });
    fireEvent.click(within(firstHeader).getByRole("button", { name: "通貨" }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sort")).toBe("symbol_name");
      expect(parameters.get("order")).toBe("desc");
      expect(parameters.get("page")).toBe("1");
    });

    const secondHeader = screen.getByRole("columnheader", { name: /通貨/ });
    fireEvent.click(within(secondHeader).getByRole("button", { name: /通貨/ }));
    await waitFor(() => {
      const parameters = new URLSearchParams(window.location.search);
      expect(parameters.get("sort")).toBe("symbol_name");
      expect(parameters.get("order")).toBe("asc");
    });
  });

  it("persists the selected interval and supports a manual refresh", async () => {
    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();

    const intervalSelect = screen.getByLabelText("自動更新間隔");
    fireEvent.change(intervalSelect, { target: { value: "30" } });
    expect(window.localStorage.getItem(REFRESH_INTERVAL_STORAGE_KEY)).toBe("30");
    expect(screen.getByText("30秒ごとに自動更新")).toBeInTheDocument();

    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;
    const summaryCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/summary?"),
    ).length;
    fireEvent.click(screen.getByRole("button", { name: "今すぐ更新" }));
    await waitFor(() => {
      expect(vi.mocked(fetch).mock.calls.filter(
        ([path]) => String(path).startsWith("/api/alerts?"),
      )).toHaveLength(alertCallsBefore + 1);
      expect(vi.mocked(fetch).mock.calls.filter(
        ([path]) => String(path).startsWith("/api/summary?"),
      )).toHaveLength(summaryCallsBefore + 1);
    });
    expect(screen.queryByText("一覧最終確認 —")).not.toBeInTheDocument();
  });

  it("refreshes LIVE results on the stored interval without polling TESTER results", async () => {
    window.localStorage.setItem(REFRESH_INTERVAL_STORAGE_KEY, "5");
    const scheduledRefreshes: Array<() => void> = [];
    const nativeSetTimeout = window.setTimeout.bind(window);
    const timerSpy = vi.spyOn(window, "setTimeout");
    timerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        scheduledRefreshes.push(handler as () => void);
        return 9001;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof timerSpy.mockImplementation>[0]);

    const liveView = render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    await waitFor(() => expect(scheduledRefreshes.length).toBeGreaterThan(0));
    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;
    await act(async () => {
      scheduledRefreshes[0]();
      await Promise.resolve();
    });
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    )).toHaveLength(alertCallsBefore + 1));

    liveView.unmount();
    timerSpy.mockRestore();
    window.history.replaceState(null, "", "/?sourceMode=TESTER&runId=3");
    const testerTimers: Array<() => void> = [];
    const testerTimerSpy = vi.spyOn(window, "setTimeout");
    testerTimerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        testerTimers.push(handler as () => void);
        return 9002;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof testerTimerSpy.mockImplementation>[0]);
    render(<App />);
    expect(await screen.findByText("接続済み・TESTER 1件")).toBeInTheDocument();
    expect(screen.getByText("LIVE表示中のみ自動更新")).toBeInTheDocument();
    expect(testerTimers).toHaveLength(0);
  });

  it("pauses while hidden and refreshes immediately when the tab becomes visible", async () => {
    window.localStorage.setItem(REFRESH_INTERVAL_STORAGE_KEY, "5");
    let visibilityState: DocumentVisibilityState = "hidden";
    vi.spyOn(document, "visibilityState", "get").mockImplementation(() => visibilityState);
    const scheduledRefreshes: Array<() => void> = [];
    const nativeSetTimeout = window.setTimeout.bind(window);
    const timerSpy = vi.spyOn(window, "setTimeout");
    timerSpy.mockImplementation(((handler: (...args: any[]) => void, timeout?: number) => {
      if (timeout === 5000 && typeof handler === "function") {
        scheduledRefreshes.push(handler as () => void);
        return 9003;
      }
      return nativeSetTimeout(handler, timeout);
    }) as unknown as Parameters<typeof timerSpy.mockImplementation>[0]);

    render(<App />);
    expect(await screen.findByText("接続済み・LIVE 1件")).toBeInTheDocument();
    expect(screen.getByText("タブ非表示中は停止")).toBeInTheDocument();
    expect(scheduledRefreshes).toHaveLength(0);
    const alertCallsBefore = vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    ).length;

    visibilityState = "visible";
    fireEvent(document, new Event("visibilitychange"));
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.filter(
      ([path]) => String(path).startsWith("/api/alerts?"),
    )).toHaveLength(alertCallsBefore + 1));
    expect(scheduledRefreshes.length).toBeGreaterThan(0);
  });
});
