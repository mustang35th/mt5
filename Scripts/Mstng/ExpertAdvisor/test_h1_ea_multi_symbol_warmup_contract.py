"""Multi-symbol tick warmup source contracts and extracted-predicate boundaries.

No MT5 terminal, terminal database, orders, or Python controller simulation is
used. Elapsed-time cases evaluate the actual production guard expression.
"""

from pathlib import Path
import re
import unittest
from test_h1_ea_tester_warmup_contract import code_only, method
from test_h1_ea_preparation_history_contract import branch, condition, evaluate

ROOT = Path(__file__).resolve().parents[3]


class MultiSymbolWarmupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parent = (ROOT / "Include/MstngH1Ea/H1EaMultiSymbolController.mqh").read_text(encoding="utf-8-sig")
        cls.child = (ROOT / "Include/MstngH1Ea/H1EaController.mqh").read_text(encoding="utf-8-sig")
        cls.timer = (ROOT / "Include/MstngH1Ea/Runtime/H1EaEventTimer.mqh").read_text(encoding="utf-8-sig")

    def test_all_idle_gate_is_tester_only_and_exits_at_trade_boundary(self):
        before = code_only(method(self.parent, "isBeforeTesterTradeStart"))
        for guard in ("MQLInfoInteger(MQL_TESTER)", "this.testerTradeStartTime > 0", "TimeCurrent() < this.testerTradeStartTime"):
            self.assertIn(guard, before)
        body = code_only(method(self.parent, "canUseFastTesterWarmup"))
        for guard in ("!this.started", "!this.timerStarted", "!this.isBeforeTesterTradeStart()",
                      "PositionsTotal() != 0", "OrdersTotal() != 0"):
            self.assertLess(body.index(guard), body.index(".canUseScheduledFastTesterWarmup()"))
        self.assertIn("i < ArraySize(this.controllers)", body)
        self.assertIn("if (!this.controllers[i].canUseScheduledFastTesterWarmup())", body)
        self.assertNotIn("TimeCurrent() + 30", body)

    def test_exact_start_boundary_and_late_first_tick_exit_warmup(self):
        expression = method(self.parent, "isBeforeTesterTradeStart").split("return", 1)[1].split(";", 1)[0]
        for tester, start, now, expected in ((True, 10000, 9999, True),
                (True, 10000, 10000, False), (True, 10000, 10001, False),
                (True, 10000, 10000 + 3 * 86400, False),
                (True, 0, 1, False), (False, 10000, 9999, False)):
            with self.subTest(tester=tester, start=start, now=now):
                self.assertEqual(evaluate(expression, {"MQLInfoInteger(MQL_TESTER)": tester,
                    "this.testerTradeStartTime": start, "TimeCurrent()": now}), expected)

    def test_each_symbol_requires_restored_idle_and_owned_lease(self):
        body = code_only(method(self.child, "canUseScheduledFastTesterWarmup"))
        for guard in ("!this.started", "!this.persistencePreparation", "!this.protectionEnabled", "!this.entryEnabled",
                      "!this.config.isBeforeTesterTradeStart(TimeCurrent())", "!this.databaseReady", "!this.countsRestored",
                      "!this.executorInitialized", "this.auditStateLost", "this.leaseLost", "!this.instanceLock.isHeld()",
                      "this.run.id <= 0", "this.run.leaseExpiresAt <= TimeLocal()", "ArraySize(this.decisionQueue) > 0"):
            self.assertLess(body.index(guard), body.index("this.executor.isIdleForTesterWarmup("))
        for forbidden in ("persistence.", "strategy.", "OrderSend", "PositionSelect", "readPosition"):
            self.assertNotIn(forbidden, body)

    def test_reserved_lease_restore_precedes_normal_maintenance(self):
        body = code_only(method(self.child, "processPersistencePreparation"))
        self.assertIn("this.scheduledTickWarmup", body)
        self.assertLess(body.index("this.endScheduledTickWarmup()"), body.index("this.maintainPersistence()"))
        self.assertRegex(body, r"if \(this.scheduledTickWarmup && !this.endScheduledTickWarmup\(\)\) \{\s*return;")
        self.assertIn("this.maintainPersistence()", body)
        # The existing single-symbol heartbeat cadence is intentionally separate.
        gate = method(self.child, "maintainFastTesterWarmup")
        self.assertIn("TimeLocal() >= this.run.heartbeatAt + 30", gate)
        self.assertIn("this.maintainPersistence(true)", gate)
        maintenance = method(self.child, "maintainPersistence")
        for expected in ("heartbeatSeconds = 10", "heartbeatSeconds = 30", "this.run.leaseExpiresAt <= now"):
            self.assertIn(expected, maintenance)

    def test_fast_path_reserves_all_symbols_and_rechecks_safety(self):
        body = code_only(method(self.parent, "processFastTesterWarmup"))
        self.assertGreaterEqual(body.count("this.canUseFastTesterWarmup()"), 2)
        self.assertIn(".beginScheduledTickWarmup()", body)
        self.assertIn("this.processWarmupPreparation()", body)
        self.assertLess(body.index(".beginScheduledTickWarmup()"), body.index("EventKillTimer()"))
        self.assertLess(body.index("EventKillTimer()"), body.index("this.eventTimer.reset()"))
        self.assertNotIn("this.timerStarted = false", body)
        self.assertNotIn("this.updateEventTimer(true)", body)
        self.assertNotIn(".processPersistencePreparation(true)", body)

    def test_normal_timer_is_restored_before_each_lease_is_restored(self):
        body = code_only(method(self.parent, "endFastTesterWarmup"))
        self.assertIn("this.updateEventTimer(false)", body)
        self.assertLess(body.index("this.updateEventTimer(false)"), body.index(".endScheduledTickWarmup()"))
        self.assertIn(".isScheduledTickWarmup()", body)
        for name in ("onTick", "onTimer"):
            dispatch = code_only(method(self.parent, name))
            self.assertLess(dispatch.index("this.processFastTesterWarmup()"), dispatch.index(".processProtection("))

    def test_hourly_tick_batch_prepares_all_twenty_eight_symbols_without_decisions(self):
        body = code_only(method(self.parent, "processWarmupPreparation"))
        self.assertEqual(body.count(".processPreparation()"), 1)
        self.assertIn("i < ArraySize(this.controllers)", body)
        self.assertIn("this.controllers[i].processPreparation()", body)
        self.assertIn("this.lastWarmupPreparationTime = now", body)
        self.assertLess(body.index("this.lastWarmupPreparationTime = now"), body.index(".processPreparation()"))
        self.assertNotIn("nextSymbolIndex", body)
        self.assertNotIn("while (", body)
        for forbidden in ("restorePreparedDecision", "processScheduledEntry", "processScheduledTrail", "strategy.", "OrderSend"):
            self.assertNotIn(forbidden, body)
        timer = code_only(method(self.parent, "onTimer"))
        self.assertNotIn("this.processWarmupPreparation()", timer)
        self.assertRegex(timer, r"if \(!this.isBeforeTesterTradeStart\(\)\) \{\s*this.controllers\[symbolIndex\].restorePreparedDecision\(\);")

    def test_first_hourly_and_sparse_tick_boundaries_use_simulated_elapsed_time(self):
        body = code_only(method(self.parent, "processWarmupPreparation"))
        guard = "if (this.lastWarmupPreparationTime"
        skip = condition(body, guard)
        for previous, now, expected in ((0, 10000, False), (10000, 10000, True),
                (10000, 10001, True), (10000, 13599, True), (10000, 13600, False),
                (10000, 13601, False), (10000, 10000 + 12 * 3600, False),
                (10000, 10000 + 3 * 86400, False)):
            with self.subTest(previous=previous, now=now):
                self.assertEqual(evaluate(skip, {"this.lastWarmupPreparationTime": previous,
                    "now": now}), expected)
        self.assertEqual(branch(body, guard), "return true;")
        self.assertIn("datetime now = TimeCurrent()", body)
        for forbidden in ("TimeLocal", "GetTickCount", "H1EaClock", "Sleep", "EventSetTimer"):
            self.assertNotIn(forbidden, body)
        for name in ("resetMonitorMetrics", "endFastTesterWarmup", "processFastTesterWarmup"):
            self.assertIn("this.lastWarmupPreparationTime = 0", method(self.parent, name))

    def test_tick_rechecks_warmup_before_chart_filter_without_analysis_or_entry(self):
        body = code_only(method(self.parent, "onTick"))
        self.assertLess(body.index("this.processFastTesterWarmup()"), body.index("this.chartSymbolIndex < 0"))
        self.assertIn("this.processWarmupPreparation()", method(self.parent, "processFastTesterWarmup"))
        self.assertEqual(code_only(self.parent).count("this.processWarmupPreparation()"), 1)
        for forbidden in (".processPreparation()", "processScheduledEntry", "processTrail", "strategy."):
            self.assertNotIn(forbidden, body)
        self.assertIn("wasFastWarmup || !this.eventTimer.isNormalReady()", body)
        self.assertIn("this.controllers[i].processProtection", body)

    def test_timer_cannot_run_another_batch_while_tick_warmup_is_active(self):
        body = code_only(method(self.parent, "onTimer"))
        guard = "if (!this.started || !this.timerStarted || this.fastWarmupActive)"
        self.assertEqual(branch(body, guard), "return;")
        self.assertLess(body.index(guard), body.index("this.processFastTesterWarmup()"))
        skip = condition(body, guard)
        self.assertTrue(evaluate(skip, {"this.started": True, "this.timerStarted": True,
                                       "this.fastWarmupActive": True}))
        self.assertFalse(evaluate(skip, {"this.started": True, "this.timerStarted": True,
                                        "this.fastWarmupActive": False}))

    def test_timer_failure_never_counts_as_normal_entry_ready(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertIn("processScheduledEntry(entryBarTime, this.eventTimer.isNormalReady())", body)
        self.assertNotIn("processScheduledEntry(entryBarTime, this.timerStarted)", body)
        update = method(self.timer, "update")
        self.assertIn("this.timerSeconds = 0", update)
        self.assertIn("H1EaClock::milliseconds() + 5000", update)
        reset = code_only(method(self.parent, "updateEventTimer"))
        self.assertIn("resetMaintenance || (!fromFastWarmup && this.fastWarmupActive)", reset)
        self.assertIn("this.controllers[i].resetScheduledMaintenance()", reset)
        self.assertNotIn("if (updated)", reset)
        self.assertIn("this.nextMaintenanceTick = 0", method(self.child, "resetScheduledMaintenance"))

    def test_parent_start_and_shutdown_own_the_single_timer(self):
        body = code_only(method(self.parent, "startTimer"))
        self.assertLess(body.index(".canEnableProtection()"), body.index("this.updateEventTimer(false)"))
        self.assertLess(body.index("this.updateEventTimer(false)"), body.index(".enableEntry()"))
        shutdown = code_only(method(self.parent, "shutdown"))
        self.assertLess(shutdown.index("EventKillTimer()"), shutdown.index("this.eventTimer.reset()"))
        reset = code_only(method(self.timer, "reset"))
        self.assertIn("this.timerSeconds = 0", reset)
        self.assertIn("this.nextTimerRetryTick = 0", reset)
        self.assertNotIn("Event", reset)

    def test_single_symbol_gate_stays_separate_from_scheduled_gate(self):
        single = code_only(method(self.child, "canUseFastTesterWarmup"))
        self.assertIn("this.persistencePreparation", single)
        self.assertIn("PositionsTotal() == 0 && OrdersTotal() == 0", single)
        for name in ("startTimer", "onTick", "onTimer", "processMaintenance", "processWarmup"):
            self.assertIn("this.persistencePreparation", method(self.child, name))
        self.assertNotIn("canUseScheduledFastTesterWarmup", single)
        for name in ("onTick", "onTimer", "canUseFastTesterWarmup", "startTimer"):
            self.assertNotIn("beginScheduledTickWarmup", method(self.child, name))

    def test_operating_config_identifies_fast_warmup_and_versions_match(self):
        config = (ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh").read_text(encoding="utf-8-sig")
        self.assertIn("TESTER_FAST_WARMUP=ALL_IDLE_TICK_HOUR_V2", method(config, "createCanonicalText"))
        self.assertIn('this.run.programVersion = "1.10"', method(self.child, "initializePersistencePreparation"))
        expert = (ROOT / "Experts/MstngH1EaAll.mq5").read_text(encoding="utf-8-sig")
        self.assertIn('#property version "1.10"', expert)
        self.assertEqual(re.findall(r"(?m)^input\s+(?:double|datetime|bool|int|string)\s+(\w+)\s*=", expert),
                         ["InpLotSize", "InpMaxInitialStopLossPips", "InpTesterTradeStartTime", "InpExportBaselineReport", "InpShowStatusPanel"])


if __name__ == "__main__":
    unittest.main()
