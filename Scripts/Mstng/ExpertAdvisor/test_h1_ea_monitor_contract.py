"""Read-only monitoring and timing contracts, separate from entry decisions."""
from pathlib import Path
import unittest
from test_h1_ea_tester_warmup_contract import method, code_only

ROOT = Path(__file__).resolve().parents[3]

class MonitorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        def read(name):
            return (ROOT / name).read_text(encoding="utf-8-sig")
        cls.child = read("Include/MstngH1Ea/H1EaController.mqh")
        cls.parent = read("Include/MstngH1Ea/H1EaMultiSymbolController.mqh")
        cls.panel = read("Include/MstngH1Ea/Presentation/H1EaStatusPanel.mqh")
        cls.expert = read("Experts/MstngH1EaAll.mq5")
        cls.config = read("Include/MstngH1Ea/Config/H1EaConfig.mqh")

    def test_snapshot_reads_memory_without_broker_or_database_queries(self):
        for source in (self.child, self.parent):
            body = code_only(method(source, "getMonitorState"))
            for forbidden in ("iTime(", "SymbolInfo", "loadDecision", "saveDecision", "reconcile(", "OrderSend",
                              "strategy.analyze", "canEnter", "recordCount", "entryState.finalize"):
                self.assertNotIn(forbidden, body)
        self.assertIn("this.entryState.getFinalizedBar()", method(self.child, "getMonitorState"))
        self.assertNotIn("fromState.finalizedBar = this.restoredDecisionBar", method(self.child, "getMonitorState"))

    def test_history_readiness_is_separate_from_analysis_and_trading_categories(self):
        child = code_only(method(self.child, "getMonitorState"))
        self.assertIn("fromState.historyReady = this.strategy.isHistoryPrepared()", child)
        parent = code_only(method(self.parent, "getMonitorState"))
        self.assertIn("if (fromState.symbols[i].historyReady)", parent)
        self.assertIn("fromState.historyReadyCount++", parent)
        monitor = (ROOT / "Include/MstngH1Ea/Runtime/H1EaMonitorState.mqh").read_text(encoding="utf-8-sig")
        self.assertIn("this.historyReady = false", monitor)
        self.assertIn("this.historyReadyCount = 0", monitor)
        panel = method(self.panel, "draw")
        self.assertIn("fromState.symbolCount > 0 && fromState.historyReadyCount == fromState.symbolCount", panel)
        self.assertIn("履歴準備完了", panel)
        for name in ("evaluateEntry", "applyEntrySafety", "processScheduledEntry"):
            self.assertNotIn("historyReadyCount", method(self.child, name))

    def test_monitor_is_never_used_to_authorize_entries(self):
        for name in ("evaluateEntry", "applyEntrySafety", "processScheduledEntry", "getPendingEntryBar"):
            body = method(self.child, name)
            self.assertNotIn("getMonitorState", body)
            self.assertNotIn("category", body)
            self.assertNotIn("lastAnalysisMicros", body)
        self.assertNotIn("InpShowStatusPanel", method(self.config, "createCanonicalText"))

    def test_stop_reason_precedes_warmup_and_readiness(self):
        body = method(self.child, "getMonitorState")
        for guard in ("this.leaseLost", "!this.instanceLock.isHeld()", "this.auditStateLost", "!this.databaseReady",
                      "ArraySize(this.decisionQueue) > 0", "this.executor.hasUnsavedEvents()"):
            self.assertLess(body.index(guard), body.index("if (fromBeforeTradeStart)"))
        self.assertIn("this.preparationState.h1BarTime != fromCurrentBar", body)
        self.assertIn("this.restoredDecisionBar != fromCurrentBar", body)

    def test_aggregation_categories_are_exclusive_and_active_is_not_position_count(self):
        body = method(self.parent, "getMonitorState")
        for field in ("stoppedCount++", "preparingCount++", "watchingCount++", "activeTradeCount++"):
            self.assertIn(field, body)
        self.assertIn('else if (fromState.symbols[i].category == "PREPARING")', body)
        self.assertNotIn("PositionsTotal", body)
        self.assertIn("fromState.symbols[i].activeTrade", body)

    def test_analysis_timing_covers_success_and_failure_without_clocking_retry(self):
        for name, call in (("evaluateEntry", "this.strategy.analyze(snapshot)"), ("processTrail", "this.strategy.analyze(trailSnapshot)")):
            body = code_only(method(self.child, name))
            self.assertLess(body.index("GetMicrosecondCount()"), body.index(call))
            self.assertEqual(body.count("this.recordAnalysisDuration(analysisStarted)"), 2)
        body = code_only(method(self.child, "recordAnalysisDuration"))
        self.assertIn("if (!this.persistencePreparation)", body)
        self.assertIn("GetMicrosecondCount()", body)
        for forbidden in ("nextEntry", "Retry", "entryState", "EventSetTimer", "H1EaClock"):
            self.assertNotIn(forbidden, body)

    def test_timer_metrics_do_not_include_render_and_warmup_resets_gap_baseline(self):
        body = code_only(method(self.parent, "recordTimerDuration"))
        self.assertLess(body.index("this.lastTimerMicros = GetMicrosecondCount() - fromStarted"), body.index("this.logRuntimeMetrics(false)"))
        for name in ("onTimer", "onTick"):
            body = code_only(method(self.parent, name))
            self.assertIn("this.lastProtectionClock = 0", body)
            self.assertIn("this.lastProtectionGapMs = 0", body)
        body = code_only(method(self.parent, "recordProtectionPass"))
        self.assertIn("H1EaClock::milliseconds()", body)
        self.assertNotIn("GetMicrosecondCount", body)

    def test_metrics_log_frequency_and_shutdown_record(self):
        body = method(self.parent, "logRuntimeMetrics")
        self.assertIn("!fromForce && now < this.nextMetricsLogTick", body)
        self.assertIn("now + 60000", body)
        self.assertIn("now + 3600000", body)
        self.assertIn("this.logRuntimeMetrics(true)", method(self.parent, "shutdown"))

    def test_view_owns_no_strategy_controller_or_database(self):
        for forbidden in ("H1EaController", "H1EaMultiSymbolController", "OrderSend", "Database", "strategy.", "persistence."):
            self.assertNotIn(forbidden, code_only(self.panel))
        self.assertIn("MQL_VISUAL_MODE", method(self.panel, "canDraw"))
        self.assertIn("MQL_VISUAL_MODE", method(self.panel, "clear"))
        self.assertIn("ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1)", method(self.panel, "clear"))

    def test_panel_is_throttled_and_updated_after_trading_work(self):
        self.assertIn("this.nextRefreshTick = now + 60000", method(self.panel, "draw"))
        body = method(self.expert, "updateStatusPanel")
        self.assertLess(body.index("!statusPanel.isRefreshDue()"), body.index("controller.getMonitorState(state)"))
        for name, dispatch in (("OnTick", "controller.onTick()"), ("OnTimer", "controller.onTimer()")):
            body = method(self.expert, name)
            self.assertLess(body.index(dispatch), body.index("updateStatusPanel()"))

    def test_view_uses_direction_colors_and_own_page_names(self):
        body = method(self.panel, "draw")
        self.assertIn('state.activeTrade && state.tradeSide == "BUY"', body)
        self.assertIn("tradeColor = clrDeepSkyBlue", body)
        self.assertIn("tradeColor = clrLightCoral", body)
        self.assertIn("this.page * slots + i", body)
        self.assertIn("symbolIndex >= fromState.symbolCount", body)
        events = method(self.panel, "onChartEvent")
        self.assertIn('fromObjectName == this.objectPrefix + "Previous"', events)
        self.assertIn('fromObjectName == this.objectPrefix + "Next"', events)

if __name__ == "__main__":
    unittest.main()
