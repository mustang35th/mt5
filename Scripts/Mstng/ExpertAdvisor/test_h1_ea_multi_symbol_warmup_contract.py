"""Multi-symbol tester warmup wiring; no terminal, live DB or orders are used."""

from pathlib import Path
import re
import unittest
from test_h1_ea_tester_warmup_contract import code_only, method

ROOT = Path(__file__).resolve().parents[3]


class MultiSymbolWarmupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parent = (ROOT / "Include/MstngH1Ea/H1EaMultiSymbolController.mqh").read_text(encoding="utf-8-sig")
        cls.child = (ROOT / "Include/MstngH1Ea/H1EaController.mqh").read_text(encoding="utf-8-sig")
        cls.timer = (ROOT / "Include/MstngH1Ea/Runtime/H1EaEventTimer.mqh").read_text(encoding="utf-8-sig")

    def test_all_idle_gate_is_tester_only_and_exits_before_trade_boundary(self):
        before = code_only(method(self.parent, "isBeforeTesterTradeStart"))
        for guard in ("MQLInfoInteger(MQL_TESTER)", "this.testerTradeStartTime > 0", "TimeCurrent() < this.testerTradeStartTime"):
            self.assertIn(guard, before)
        body = code_only(method(self.parent, "canUseFastTesterWarmup"))
        for guard in ("!this.started", "!this.timerStarted", "!this.isBeforeTesterTradeStart()",
                      "TimeCurrent() + 30 >= this.testerTradeStartTime", "PositionsTotal() != 0", "OrdersTotal() != 0"):
            self.assertLess(body.index(guard), body.index(".canUseScheduledFastTesterWarmup()"))
        self.assertIn("i < ArraySize(this.controllers)", body)
        self.assertIn("if (!this.controllers[i].canUseScheduledFastTesterWarmup())", body)

    def test_each_symbol_requires_restored_idle_and_owned_lease(self):
        body = code_only(method(self.child, "canUseScheduledFastTesterWarmup"))
        for guard in ("!this.started", "!this.persistencePreparation", "!this.protectionEnabled", "!this.entryEnabled",
                      "!this.config.isBeforeTesterTradeStart(TimeCurrent())", "!this.databaseReady", "!this.countsRestored",
                      "!this.executorInitialized", "this.auditStateLost", "this.leaseLost", "!this.instanceLock.isHeld()",
                      "this.run.id <= 0", "this.run.leaseExpiresAt <= TimeLocal()", "ArraySize(this.decisionQueue) > 0"):
            self.assertLess(body.index(guard), body.index("this.executor.isIdleForTesterWarmup()"))
        for forbidden in ("persistence.", "strategy.", "OrderSend", "PositionSelect", "readPosition"):
            self.assertNotIn(forbidden, body)

    def test_fast_maintenance_is_rechecked_and_uses_existing_thirty_second_gate(self):
        body = code_only(method(self.child, "processPersistencePreparation"))
        self.assertIn("fromFastWarmup && this.canUseScheduledFastTesterWarmup()", body)
        self.assertIn("this.maintainFastTesterWarmup()", body)
        self.assertIn("this.maintainPersistence()", body)
        gate = method(self.child, "maintainFastTesterWarmup")
        self.assertIn("TimeLocal() >= this.run.heartbeatAt + 30", gate)
        self.assertIn("this.maintainPersistence(true)", gate)
        maintenance = method(self.child, "maintainPersistence")
        for expected in ("heartbeatSeconds = 10", "heartbeatSeconds = 30", "this.run.leaseExpiresAt <= now"):
            self.assertIn(expected, maintenance)

    def test_fast_path_rechecks_after_every_symbol_maintenance(self):
        body = code_only(method(self.parent, "processFastTesterWarmup"))
        self.assertEqual(body.count("this.canUseFastTesterWarmup()"), 2)
        self.assertLess(body.index("!this.updateEventTimer(fastWarmup)"), body.index(".processPersistencePreparation(true)"))
        self.assertLess(body.index(".processPersistencePreparation(true)"), body.rindex("this.canUseFastTesterWarmup()"))
        self.assertIn("this.updateEventTimer(false)", body)

    def test_fast_timer_prepares_one_symbol_without_entry_or_decision_lookup(self):
        body = code_only(method(self.parent, "processWarmupPreparation"))
        self.assertEqual(body.count(".processPreparation()"), 1)
        self.assertIn("(this.nextSymbolIndex + 1) % ArraySize(this.controllers)", body)
        for forbidden in ("restorePreparedDecision", "processScheduledEntry", "processScheduledTrail", "strategy.", "OrderSend"):
            self.assertNotIn(forbidden, body)
        timer = code_only(method(self.parent, "onTimer"))
        self.assertRegex(timer, r"if \(this.fastWarmupActive\) \{\s*this.lastProtectionClock = 0;\s*this.lastProtectionGapMs = 0;\s*this.processWarmupPreparation\(\);\s*this.recordTimerDuration\(timerStartedMicros\);\s*return;")
        self.assertLess(timer.index("this.processWarmupPreparation()"), timer.index(".processProtection(barTime)"))
        self.assertRegex(timer, r"if \(!this.isBeforeTesterTradeStart\(\)\) \{\s*this.controllers\[symbolIndex\].restorePreparedDecision\(\);")

    def test_fast_tick_has_no_history_analysis_or_entry(self):
        body = code_only(method(self.parent, "onTick"))
        self.assertLess(body.index("this.processFastTesterWarmup()"), body.index("this.chartSymbolIndex < 0"))
        for forbidden in ("processPreparation", "processWarmupPreparation", "processScheduledEntry", "processTrail", "strategy."):
            self.assertNotIn(forbidden, body)
        self.assertIn("wasFastWarmup || !this.eventTimer.isNormalReady()", body)
        self.assertIn("this.controllers[i].processProtection", body)

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

    def test_operating_config_identifies_fast_warmup_and_versions_match(self):
        config = (ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh").read_text(encoding="utf-8-sig")
        self.assertIn("TESTER_FAST_WARMUP=ALL_IDLE_TIMER30_V1", method(config, "createCanonicalText"))
        self.assertIn('this.run.programVersion = "1.06"', method(self.child, "initializePersistencePreparation"))
        expert = (ROOT / "Experts/MstngH1EaAll.mq5").read_text(encoding="utf-8-sig")
        self.assertIn('#property version "1.06"', expert)
        self.assertEqual(re.findall(r"(?m)^input\s+(?:double|datetime|bool|int|string)\s+(\w+)\s*=", expert),
                         ["InpLotSize", "InpMaxInitialStopLossPips", "InpTesterTradeStartTime", "InpExportBaselineReport", "InpShowStatusPanel"])


if __name__ == "__main__":
    unittest.main()
