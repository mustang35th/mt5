"""Static wiring checks for the H1 EA tester warmup gate.

These tests inspect the real MQL sources. They do not execute MQL, MT5,
analysis, strategy decisions, database writes, or broker operations.
Boundary/state behavior is covered separately by the MQL SmokeTest sources;
compiling those sources is not a substitute for running them in MT5.

Run with: python -B -m unittest discover -s Scripts/Mstng/ExpertAdvisor
          -p test_h1_ea_tester_warmup_contract.py -v
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh"
CONTROLLER = ROOT / "Include/MstngH1Ea/H1EaController.mqh"
EXPERT = ROOT / "Experts/MstngH1Ea.mq5"
STRATEGY = ROOT / "Include/MstngH1Ea/Strategy/H1EaStrategy.mqh"
EXECUTOR = ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh"
PERSISTENCE = ROOT / "Include/Mstng/Database/Service/H1EaPersistenceService.mqh"


def code_only(source: str) -> str:
    """Mask comments/literals without changing character offsets."""
    tokens = re.compile(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        re.DOTALL,
    )
    return tokens.sub(lambda match: re.sub(r"[^\n]", " ", match.group()), source)


def block_end(masked: str, opening: int) -> int:
    depth = 0
    for offset in range(opening, len(masked)):
        if masked[offset] == "{":
            depth += 1
        elif masked[offset] == "}":
            depth -= 1
            if depth == 0:
                return offset
    raise AssertionError("Unterminated MQL block")


def method(source: str, name: str) -> str:
    masked = code_only(source)
    signature = re.search(
        r"(?m)^[ \t]*(?:(?:static|virtual)\s+)*"
        r"(?:(?:bool|void|int|long|ulong|datetime|string)\s+)?"
        + re.escape(name) + r"\s*\([^;{}]*?\)\s*(?:const\s*)?\{",
        masked,
    )
    if signature is None:
        raise AssertionError(f"Missing MQL method: {name}")
    opening = signature.end() - 1
    return source[opening + 1:block_end(masked, opening)]


class TesterWarmupWiringTests(unittest.TestCase):
    """Source contracts only: no simulated claim of running the Controller."""

    @classmethod
    def setUpClass(cls):
        cls.config = CONFIG.read_text(encoding="utf-8-sig")
        cls.controller = CONTROLLER.read_text(encoding="utf-8-sig")
        cls.expert = EXPERT.read_text(encoding="utf-8-sig")
        cls.strategy = STRATEGY.read_text(encoding="utf-8-sig")
        cls.executor = EXECUTOR.read_text(encoding="utf-8-sig")
        cls.persistence = PERSISTENCE.read_text(encoding="utf-8-sig")

    def test_program_version_changes_without_new_inputs(self):
        self.assertRegex(self.expert, r'#property\s+version\s+"1\.02"')
        self.assertIn('return "1.02";', method(self.config, "getProgramVersion"))
        self.assertEqual(
            re.findall(r"(?m)^input\s+(?:double|datetime|int|bool|string)\s+(\w+)\s*=", self.expert),
            ["InpLotSize", "InpMaxInitialStopLossPips", "InpTesterTradeStartTime"],
        )

    def test_input_is_forwarded_through_controller_to_config(self):
        self.assertRegex(
            self.expert,
            r"input\s+datetime\s+InpTesterTradeStartTime\s*=\s*D'2026\.01\.01 00:00'\s*;",
        )
        self.assertRegex(
            code_only(method(self.expert, "OnInit")),
            r"controller\.initialize\([^;]*\bInpTesterTradeStartTime\b",
        )
        self.assertRegex(
            code_only(method(self.controller, "initialize")),
            r"this\.config\.initialize\([^;]*\bfromTesterTradeStartTime\b",
        )

    def test_live_initialization_keeps_effective_start_zero(self):
        body = code_only(method(self.config, "initialize"))
        zero_assignment = body.index("this.testerTradeStartTime = 0;")
        tester_branch = re.search(r"if\s*\(this\.isTester\)\s*\{", body)
        self.assertIsNotNone(tester_branch)
        self.assertLess(zero_assignment, tester_branch.start())
        branch_end = block_end(body, tester_branch.end() - 1)
        branch = body[tester_branch.end():branch_end]
        self.assertIn("this.testerTradeStartTime = fromTesterTradeStartTime;", branch)
        self.assertEqual(body.count("this.testerTradeStartTime = fromTesterTradeStartTime;"), 1)

    def test_gate_uses_current_time_strict_before_with_zero_disabled(self):
        body = re.sub(r"\s+", "", code_only(method(self.config, "isBeforeTesterTradeStart")))
        self.assertEqual(
            body,
            "returnthis.isTester&&this.testerTradeStartTime>0&&fromTime<this.testerTradeStartTime;",
        )

    def test_entry_gate_returns_before_any_entry_state_or_decision_work(self):
        body = code_only(method(self.controller, "evaluateEntry"))
        gate = re.search(
            r"\A\s*if\s*\(this\.config\.isBeforeTesterTradeStart\(TimeCurrent\(\)\)\)\s*\{",
            body,
        )
        self.assertIsNotNone(gate)
        end = block_end(body, gate.end() - 1)
        warmup_branch = body[gate.end():end]
        self.assertRegex(warmup_branch, r"this\.processTesterWarmup\(\);\s*return;")
        self.assertNotIn("entryState", warmup_branch)
        for operation in (
            "this.entryState.observe(", "this.entryState.recordCount(",
            "this.entryState.finalize(", "this.strategy.evaluate(",
            "this.buildDecision(", "this.enqueueDecision(", "this.persistence.saveEntry(",
        ):
            self.assertGreater(body.index(operation), end, operation)

    def test_warmup_prepares_history_once_per_h1_without_analysis_or_judge(self):
        body = code_only(method(self.controller, "processTesterWarmup"))
        self.assertIn("PERIOD_H1", body)
        self.assertRegex(body, r"barTime\s*==\s*this\.lastWarmupBar")
        assignment = body.index("this.lastWarmupBar = barTime;")
        self.assertLess(assignment, body.index("this.strategy.prepareHistory()"))
        self.assertEqual(body.count("this.strategy.prepareHistory("), 1)
        for forbidden in (
            "entryState", "strategy.evaluate", "persistence.", "executor.",
            "buildDecision", "initializeDecision", "enqueueDecision", "flushDecisions", "strategy.analyze",
        ):
            self.assertNotIn(forbidden, body)

    def test_history_preparation_never_authorizes_stale_strategy_evaluation(self):
        prepare = code_only(method(self.strategy, "prepareHistory"))
        self.assertIn("this.isPrepared = false;", prepare)
        self.assertIn("this.handlePool == NULL || !this.isHistoryReady()", prepare)
        for forbidden in ("isPrepared = true", "new ElliotAll", "elliotAll.analyze", ".evaluate("):
            self.assertNotIn(forbidden, prepare)
        analyze = code_only(method(self.strategy, "analyze"))
        guard = re.search(r"if\s*\(!this\.prepareHistory\(\)\)\s*\{\s*return false;", analyze)
        self.assertIsNotNone(guard)
        self.assertLess(guard.end(), analyze.index("new ElliotAll"))
        self.assertLess(analyze.index("new ElliotAll"), analyze.index("this.elliotAll.analyze();"))
        self.assertLess(analyze.index("this.elliotAll.analyze();"), analyze.index("this.isPrepared = decision.prepare("))

    def test_fast_gate_rejects_unrestored_unsafe_or_expired_state(self):
        body = code_only(method(self.controller, "canUseFastTesterWarmup"))
        compact = re.sub(r"\s+", "", body)
        for guard in (
            "!this.config.isBeforeTesterTradeStart(TimeCurrent())",
            "!this.databaseReady", "!this.countsRestored", "!this.executorInitialized",
            "this.auditStateLost", "this.leaseLost", "!this.instanceLock.isHeld()",
            "this.run.id<=0", "this.run.leaseExpiresAt<=TimeLocal()",
            "ArraySize(this.decisionQueue)>0",
        ):
            self.assertIn(guard, compact)
            self.assertLess(compact.index(guard), compact.index("returnfalse;"))
        self.assertIn("returnthis.executor.isIdleForTesterWarmup()&&PositionsTotal()==0&&OrdersTotal()==0;", compact)

    def test_executor_fast_gate_requires_confirmed_idle_with_no_pending_work(self):
        body = code_only(method(self.executor, "isIdleForTesterWarmup"))
        compact = re.sub(r"\s+", "", body)
        for guard in (
            "!this.initialized", "!this.loaded", "!this.idleReconciled", "this.persistence==NULL",
            "this.runId<=0", "!this.lockHeld", "this.knownLeaseExpires<=0", "this.active",
            "this.ownershipLost", "this.queueOverflow", "ArraySize(this.saveQueue)>0",
            "this.recoveryCommitPending", "this.orderReadFailed", "this.pendingStored",
            "this.trade.id!=0", "this.pendingModifyRequestId!=0",
        ):
            self.assertIn(guard, compact)
        for forbidden in ("OrderSend(", "Database", "this.reconcile(", "this.readPosition("):
            self.assertNotIn(forbidden, body)

    def test_fast_tick_and_timer_recheck_safety_before_skipping_normal_work(self):
        for name in ("onTick", "onTimer"):
            with self.subTest(name=name):
                body = code_only(method(self.controller, name))
                branch = re.search(r"if\s*\(fastWarmup\)\s*\{", body)
                self.assertIsNotNone(branch)
                end = block_end(body, branch.end() - 1)
                fast = body[branch.end():end]
                self.assertLess(fast.index("this.maintainFastTesterWarmup();"),
                                fast.index("if (this.canUseFastTesterWarmup())"))
                self.assertIn("return;", fast)
                self.assertIn("this.updateEventTimer(false);", fast)
                self.assertLess(end, body.index("this.maintainPersistence();"))
                self.assertLess(end, body.index("this.executor.reconcile();"))
                self.assertRegex(body[:branch.start()],
                    r"if\s*\(!this\.updateEventTimer\(fastWarmup\)\)\s*\{\s*fastWarmup\s*=\s*false;")
                if name == "onTick":
                    self.assertRegex(fast, r"this\.processTesterWarmup\(\);\s*return;")
                    self.assertLess(end, body.index("this.executor.processPending(barTime);"))
                else:
                    self.assertNotIn("processTesterWarmup", fast)

    def test_timer_switches_30_to_1_and_failed_restore_blocks_entry_only(self):
        timer = code_only(method(self.controller, "updateEventTimer"))
        compact = re.sub(r"\s+", "", timer)
        self.assertIn("intrequiredSeconds=1;", compact)
        self.assertIn("if(fromFastWarmup){requiredSeconds=30;}", compact)
        self.assertIn("if(this.timerSeconds==requiredSeconds){returntrue;}", compact)
        self.assertIn("if(!EventSetTimer(requiredSeconds))", compact)
        self.assertIn("this.timerSeconds=0;", compact)
        entry = code_only(method(self.controller, "evaluateEntry"))
        guard = re.search(r"if\s*\(this\.timerSeconds\s*!=\s*1\)\s*\{\s*return;", entry)
        self.assertIsNotNone(guard)
        self.assertLess(guard.end(), entry.index("this.entryState.observe("))
        self.assertIn("this.executor.processPending(barTime);", method(self.controller, "onTick"))
        self.assertIn("controller.startTimer()", method(self.expert, "OnInit"))
        self.assertNotIn("EventSetTimer(", code_only(method(self.expert, "OnInit")))

    def test_normal_restore_drops_fast_maintenance_wait_before_timer_api(self):
        timer = code_only(method(self.controller, "updateEventTimer"))
        reset = re.search(
            r"if\s*\(requiredSeconds\s*==\s*1\)\s*\{\s*this\.nextMaintenanceTick\s*=\s*0;\s*\}",
            timer,
        )
        self.assertIsNotNone(reset)
        self.assertLess(reset.end(), timer.index("EventSetTimer(requiredSeconds)"))
        self.assertIn("this.updateEventTimer(this.canUseFastTesterWarmup())",
                      code_only(method(self.controller, "startTimer")))

    def test_history_ready_message_does_not_claim_full_analysis_completed(self):
        body = method(self.controller, "clearAnalysisWait")
        self.assertRegex(body, r'if\s*\(fromHistoryOnly\)\s*\{\s*readyCode\s*=\s*"HISTORY_READY";')
        self.assertIn('string readyCode = "ANALYSIS_READY";', body)
        self.assertIn("this.clearAnalysisWait(true);", method(self.controller, "processTesterWarmup"))
        self.assertIn("this.clearAnalysisWait();", method(self.controller, "evaluateEntry"))

    def test_fast_heartbeat_30_seconds_does_not_extend_60_second_lease(self):
        fast = re.sub(r"\s+", "", code_only(method(self.controller, "maintainFastTesterWarmup")))
        self.assertEqual(fast, "if(TimeLocal()>=this.run.heartbeatAt+30){this.maintainPersistence(true);}")
        normal = re.sub(r"\s+", "", code_only(method(self.controller, "maintainPersistence")))
        self.assertIn("intheartbeatSeconds=10;", normal)
        self.assertIn("ulongmaintenanceMilliseconds=5000;", normal)
        self.assertIn("if(fromFastWarmup){heartbeatSeconds=30;maintenanceMilliseconds=30000;}", normal)
        self.assertIn("this.run.leaseExpiresAt<=now", normal)
        self.assertIn("this.leaseLost=true;", normal)
        self.assertIn("this.persistence.heartbeat(this.run,now)", normal)
        heartbeat = re.sub(r"\s+", "", code_only(method(self.persistence, "heartbeat")))
        self.assertIn("fromRun.leaseExpiresAt=(long)fromNow+60;", heartbeat)

    def test_warmup_bookkeeping_is_not_entry_bar_bookkeeping(self):
        constructor = code_only(method(self.controller, "H1EaController"))
        self.assertIn("this.lastWarmupBar = 0;", constructor)
        self.assertNotIn("lastWarmupBar", code_only(method(self.controller, "evaluateEntry")))
        self.assertNotIn("entryState", code_only(method(self.controller, "processTesterWarmup")))

    def test_canonical_suffix_flows_into_run_hash(self):
        body = method(self.config, "createCanonicalText")
        self.assertRegex(
            body,
            r'"\|TESTER_TRADE_START_TIME="\s*\+\s*IntegerToString\(this\.testerTradeStartTime\)\s*;',
        )
        self.assertLess(body.index("TESTER_EVALUATION_TRIGGER=TICK"), body.index("TESTER_TRADE_START_TIME="))
        run = code_only(method(self.controller, "initializeRun"))
        self.assertIn("this.run.configText = this.config.createCanonicalText();", run)
        self.assertIn("this.run.configHash = H1EaTextUtil::hash(this.run.configText);", run)

    def test_history_wait_uses_info_and_hourly_daily_suppression(self):
        source = method(self.controller, "logAnalysisWait")
        masked = code_only(source)
        branch = re.search(r'if\s*\(reason\s*==\s*"ANALYSIS_HISTORY_UNAVAILABLE"\)\s*\{', source)
        self.assertIsNotNone(branch)
        end = block_end(masked, branch.end() - 1)
        body = masked[branch.end():end]
        compact = re.sub(r"\s+", "", body)
        self.assertIn("this.strategy.getHistoryStatusText()", body)
        self.assertIn("elapsedSeconds<86400", compact)
        self.assertIn("message==this.lastAnalysisLogText||elapsedSeconds<3600", compact)
        self.assertIn("this.logger.info(", body)
        self.assertNotIn("this.logger.error(", body)
        self.assertLess(body.index("return;"), body.index("this.logger.info("))
        self.assertGreater(masked.index("this.lastAnalysisLogTime = now;"), end)

    def test_other_analysis_errors_are_deduplicated_and_success_resets_wait(self):
        body = code_only(method(self.controller, "logAnalysisWait"))
        self.assertRegex(
            body,
            r"if\s*\(message\s*==\s*this\.lastAnalysisLogText\s*&&\s*fromBar\s*==\s*this\.lastAnalysisErrorBar\)\s*\{\s*return;",
        )
        clear = method(self.controller, "clearAnalysisWait")
        self.assertIn('this.lastAnalysisLogText = "";', clear)
        self.assertIn("this.lastAnalysisLogTime = 0;", clear)
        self.assertIn("this.lastAnalysisErrorBar = 0;", clear)
        self.assertIn("this.clearAnalysisWait(true);", method(self.controller, "processTesterWarmup"))
        self.assertIn("this.clearAnalysisWait();", method(self.controller, "evaluateEntry"))

    def test_history_requirements_and_minute_request_throttle_remain_wired(self):
        body = code_only(method(self.strategy, "isHistoryReady"))
        compact = re.sub(r"\s+", "", body)
        self.assertIn("PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1", compact)
        self.assertIn("intrequestBars=206;", compact)
        self.assertIn("if(timeFrames[i]==PERIOD_MN1){requestBars=61;}", compact)
        self.assertIn("if(isTester){requiredBars=requestBars;}", compact)
        self.assertIn("mayRequest=H1EaClock::milliseconds()>=this.nextHistoryRequestTick", compact)
        self.assertIn("(!isSynchronized||availableBars<requiredBars)&&mayRequest", compact)
        self.assertIn("CopyRates(this.marketContext.symbolName,timeFrames[i],0,requestBars,requestedRates)", compact)
        self.assertIn("if(wasRequested){this.nextHistoryRequestTick=H1EaClock::milliseconds()+60000;}", compact)
        self.assertIn("SERIES_FIRSTDATE", body)
        self.assertNotIn("TimeCurrent(", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
