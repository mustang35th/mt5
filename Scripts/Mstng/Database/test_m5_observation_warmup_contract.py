"""M5 warmup/history diagnostics source contracts, not MT5 runtime tests.

These assertions inspect production MQL control flow and the shared history
preparation contract. A restricted Python AST evaluator checks extracted boolean
predicates at boundary values; it is not an MQL interpreter. These tests do not
execute a tester, download history, or prove actual collection speed/completeness.
Native compilation and collection are separate.
"""
import ast
import hashlib
import operator
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CONTROLLER = ROOT / "Include/Mstng/Indicator/ZigZagElliot/H1ElliotObservationAllController.mqh"
HISTORY = ROOT / "Include/Mstng/Util/ElliotHistoryPreparation.mqh"


def body(source, signature):
    start = source.index("{", source.index(signature)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    return source[start:position - 1]


def condition(source, prefix):
    start = source.index("(", source.index(prefix)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "(") - (source[position] == ")")
        position += 1
    return source[start:position - 1]


def evaluate_predicate(expression, **values):
    """Evaluate only known identifiers, constants, booleans, and comparisons."""
    replacements = {
        "this.observationProfile.isM5()": "is_m5",
        "this.isTesterSaveWindowEnabled()": "save_window",
        "this.observationTesterSaveStartTime": "save_start",
        "this.lastHistoryLogTexts[fromIndex]": "last_history",
        "this.lastM5TesterProgressText": "last_progress",
        "this.databaseRun.sourceServer": "source_server",
        "this.lastDatabaseMessage": "message",
        "this.databaseRejected": "rejected",
        "this.competingWriterDetected": "competing_writer",
        "this.databaseReady": "db_ready",
        "this.initialized": "initialized",
        "this.lastTesterWarmupTime": "last_warmup",
        "this.testerSaveGateOpen": "gate_open",
        "this.testerMode": "tester",
        "MQLInfoInteger(MQL_TESTER)": "tester",
        "TimeCurrent()": "current",
        "this.checked": "checked",
        "this.beforeStart": "was_before_start",
        "this.lastCheckTick": "last_check",
        "fromWarmupEndTime": "warmup_end",
        "isBeforeStart": "before_start",
        "phaseChanged": "phase_changed",
        "clockReversed": "clock_reversed",
        "fromHistoryText": "history",
        "fromCurrentTime": "current",
        "progressText": "progress",
        "elapsedSeconds": "elapsed",
        "currentTime": "current",
    }
    for original, replacement in replacements.items():
        expression = expression.replace(original, replacement)
    expression = re.sub(r"!(?!=)", " not ", expression)
    expression = " ".join(expression.replace("&&", " and ").replace("||", " or ").split())
    comparison = {ast.Eq: operator.eq, ast.NotEq: operator.ne, ast.Lt: operator.lt,
                  ast.LtE: operator.le, ast.Gt: operator.gt, ast.GtE: operator.ge}

    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (str, int, bool)):
            return node.value
        if isinstance(node, ast.Name):
            return values[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not visit(node.operand)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Sub):
            return visit(node.left) - visit(node.right)
        if isinstance(node, ast.BoolOp) and isinstance(node.op, (ast.And, ast.Or)):
            results = [bool(visit(value)) for value in node.values]
            return all(results) if isinstance(node.op, ast.And) else any(results)
        if isinstance(node, ast.Compare):
            left = visit(node.left)
            for operation, right_node in zip(node.ops, node.comparators):
                right = visit(right_node)
                if not comparison[type(operation)](left, right):
                    return False
                left = right
            return True
        raise AssertionError("Unsupported predicate syntax: " + ast.dump(node))

    return bool(visit(ast.parse(expression, mode="eval")))


class ObservationWarmupContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CONTROLLER.read_text(encoding="utf-8-sig")
        cls.history = HISTORY.read_text(encoding="utf-8-sig")

    def test_h1_event_paths_unchanged(self):
        golden = {
            "int onCalculate(": "94fe4140139321890ce8413d8805eb589da61d55cc3fb982b34c74d0951bb39a",
            "void onTimer()": "c536619302b854c13bbd05b249f3164a6c0a2638718ff3f0bb0958de43d311c8",
            "bool isTesterSaveWindowEnabled()": "f9ededd55b8529b99ba452a8453c1653317342d6e1b2c8859a5e703ec8445854",
        }
        for signature, expected in golden.items():
            with self.subTest(signature=signature):
                self.assertEqual(hashlib.sha256(body(self.source, signature).encode()).hexdigest(), expected)

    def test_h1_and_m5_delegate_history_without_promoting_analysis(self):
        readiness = body(self.source, "bool isAnalysisSeriesReady(")
        self.assertIn("return this.isM5AnalysisSeriesReady(fromIndex)", readiness)
        m5 = body(self.source, "bool isM5AnalysisSeriesReady(")
        for method in (readiness, m5):
            self.assertIn("this.historyPreparations[fromIndex].prepare(", method)
            self.assertIn("this.observationTesterSaveStartTime", method)
            for forbidden in ("Bars(", "CopyRates(", "analysisReadyFlags", "testerSaveGateOpen"):
                self.assertNotIn(forbidden, method)
        self.assertIn("this.historyPreparations[fromIndex].getMissingStatusText()", m5)
        self.assertIn("this.logM5HistoryStatus(", m5)

    def test_preflight_rechecks_history_before_reusing_analysis_success(self):
        preflight = body(self.source, "void processTesterPreflight(")
        missing = body(preflight, "if (!this.isAnalysisSeriesReady(fromIndex))")
        for reset in ("this.analysisReadyFlags[fromIndex] = false",
                      "this.testerPreflightH1BarTimes[fromIndex] = 0",
                      "this.pendingAnalysisH1BarTimes[fromIndex] = 0"):
            self.assertIn(reset, missing)
        self.assertTrue(missing.rstrip().endswith("return;"))
        self.assertLess(preflight.index("this.isAnalysisSeriesReady(fromIndex)"),
                        preflight.index("if (!saveStartReached"))
        self.assertNotIn("this.analysisReadyFlags[fromIndex] = true", preflight)
        self.assertNotIn("this.testerSaveGateOpen = true", preflight)
        capture = body(self.source, "void capturePendingObservation(")
        successful_discard = body(capture, "if (fromDiscard) {\n            delete elliotAll;")
        self.assertIn("this.analysisReadyFlags[fromIndex] = true", successful_discard)
        self.assertLess(capture.index("if (!elliotAll.isAnalysisSucceeded"),
                        capture.index("this.analysisReadyFlags[fromIndex] = true"))

    def test_common_timeframes_counts_and_initial_reference_order(self):
        feet = re.findall(r"PERIOD_[A-Z0-9]+", body(self.history, "ENUM_TIMEFRAMES getTimeFrame("))
        self.assertEqual(feet, ["PERIOD_MN1", "PERIOD_W1", "PERIOD_D1", "PERIOD_H4",
                               "PERIOD_H1", "PERIOD_M15", "PERIOD_M5"])
        count = body(self.history, "int getTimeFrameCount()")
        self.assertEqual(body(count, "if (this.anchorTimeFrame == PERIOD_M5)").strip(), "return 7;")
        self.assertTrue(count.rstrip().endswith("return 5;"))
        required = body(self.history, "int getRequiredBars(")
        self.assertEqual(body(required, "if (fromTimeFrame == PERIOD_MN1)").strip(), "return 61;")
        self.assertTrue(required.rstrip().endswith("return 206;"))
        initialize = body(self.history, "bool initialize(")
        self.assertIn("timeFrames[i] = this.getTimeFrame(total - 1 - i)", initialize)
        self.assertIn("WarmUpSeriesUtil::warmUp(this.symbolName, timeFrames, 500)", initialize)
        self.assertNotIn("this.ready = true", initialize)

    def test_common_warmup_hour_cache_and_start_transition(self):
        prepare = body(self.history, "bool prepare(")
        start_expression = prepare.split("bool isBeforeStart =", 1)[1].split(";", 1)[0]
        for tester, start, current, expected in ((True, 10000, 9999, True),
                                               (True, 10000, 10000, False),
                                               (True, 0, 9999, False),
                                               (False, 10000, 9999, False)):
            with self.subTest(tester=tester, start=start, current=current):
                self.assertEqual(evaluate_predicate(start_expression, tester=tester,
                                                    warmup_end=start, current=current), expected)
        throttle = condition(prepare, "if (this.checked && isBeforeStart")
        defaults = dict(checked=True, before_start=True, was_before_start=True,
                        phase_changed=False, clock_reversed=False, now=200, last_check=100)
        cases = [("cached", {}, True), ("first", {"checked": False}, False),
                 ("3599999 ms", {"now": 3600099}, True),
                 ("3600000 ms", {"now": 3600100}, False),
                 ("start reached", {"before_start": False}, False),
                 ("start setting changed", {"phase_changed": True}, False),
                 ("clock reversed", {"clock_reversed": True, "now": 99}, False),
                 ("LIVE or start disabled", {"before_start": False, "was_before_start": False}, False)]
        for name, changes, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(evaluate_predicate(throttle, **dict(defaults, **changes)), expected)
        reset_guard = "if (clockReversed || (this.checked && isBeforeStart != this.beforeStart))"
        self.assertEqual(body(prepare, reset_guard).strip(),
                         "this.nextRequestTick = 0;")
        request_reset = condition(prepare, reset_guard)
        for current_phase, previous_phase, reversed_clock, expected in (
                (False, False, False, False), (False, True, False, True),
                (True, False, False, True), (False, False, True, True)):
            with self.subTest(current_phase=current_phase, previous_phase=previous_phase,
                              reversed_clock=reversed_clock):
                self.assertEqual(evaluate_predicate(request_reset, checked=True,
                    before_start=current_phase, was_before_start=previous_phase,
                    clock_reversed=reversed_clock), expected)
        self.assertLess(prepare.index(reset_guard),
                        prepare.index("if (this.checked && isBeforeStart"))
        self.assertIn("this.nextRequestTick = now + 60000", prepare)
        clock = body(self.history, "ulong getClock()")
        self.assertIn("return (ulong)TimeCurrent() * 1000", clock)
        self.assertIn("return GetTickCount64()", clock)

    def test_history_status_refresh_is_read_only_and_independent_from_gate(self):
        refresh = body(self.source, "void refreshStatus()")
        self.assertIn("this.status.historyReadyCount = 0", refresh)
        self.assertIn("this.status.symbolHistoryReady[i] = this.historyPreparations[i].isReady()", refresh)
        self.assertIn("&& this.currentH1BarTimes[i] > 0", refresh)
        self.assertIn("this.status.historyReadyCount++", body(refresh, "if (this.status.symbolHistoryReady[i])"))
        for forbidden in (".prepare(", "Bars(", "CopyRates(", "this.analysisReadyFlags[i] =",
                          "this.testerSaveGateOpen ="):
            self.assertNotIn(forbidden, refresh)
        self.assertIn("this.status.readyCount = this.getReadyCount()", refresh)
        gate = body(self.source, "bool tryOpenTesterSaveGate()")
        self.assertNotIn("historyReadyCount", gate)
        self.assertIn("this.getReadyCount()", gate)
        self.assertIn("this.testerPreflightH1BarTimes[i]", gate)

    def test_history_instances_and_display_state_reset_between_runs(self):
        self.assertIn("ElliotHistoryPreparation historyPreparations[28]", self.source)
        clear = body(self.source, "void clearStateArrays()")
        self.assertIn("this.historyPreparations[i].reset()", clear)
        for signature in ("H1ElliotObservationAllController(", "void destroy()"):
            self.assertIn("this.clearStateArrays()", body(self.source, signature))
        reset = body(self.history, "void reset()")
        for initial in ("this.checked = false", "this.ready = false", "this.lastCheckTick = 0",
                        "this.nextRequestTick = 0", 'this.missingStatusText = ""'):
            self.assertIn(initial, reset)
        self.assertEqual(body(self.history, "bool isReady() const").strip(),
                         "return this.checked && this.ready;")
        status = (ROOT / "Include/Mstng/Indicator/ZigZagElliot/H1ElliotObservationAllStatus.mqh").read_text(encoding="utf-8-sig")
        self.assertIn("this.historyReadyCount = 0", body(status, "void reset()"))
        self.assertIn("this.clearSymbol(i)", body(status, "void reset()"))
        self.assertIn("this.symbolHistoryReady[fromIndex] = false", body(status, "void clearSymbol("))

    def test_warmup_skip_checked_after_source_identity_before_symbol_loop(self):
        execute = body(self.source, "void execute()")
        self.assertEqual(execute.count("this.shouldSkipM5TesterWarmup()"), 1)
        self.assertLess(execute.index("this.ensureExecutionSource()"),
                        execute.index("this.shouldSkipM5TesterWarmup()"))
        self.assertLess(execute.index("this.shouldSkipM5TesterWarmup()"),
                        execute.index("this.executing = true"))
        self.assertLess(execute.index("this.shouldSkipM5TesterWarmup()"),
                        execute.index("this.processSymbol(i)"))
        skip_branch = body(execute, "if (this.shouldSkipM5TesterWarmup())")
        self.assertIn("return;", skip_branch)
        self.assertNotIn("this.processSymbol", skip_branch)
        self.assertNotIn("this.drainSnapshotQueue", skip_branch)

    def test_warmup_clock_and_activity_reset_at_construction_and_destruction(self):
        for signature in ("H1ElliotObservationAllController(", "void destroy()"):
            method = body(self.source, signature)
            with self.subTest(signature=signature):
                self.assertIn("this.lastTesterWarmupTime = 0", method)
                self.assertIn("this.testerWarmupActive = false", method)

    def test_skip_eligibility_excludes_h1_live_zero_save_start_and_open_gate(self):
        helper = body(self.source, "bool shouldSkipM5TesterWarmup()")
        eligibility = condition(helper, "if (!this.observationProfile.isM5()")
        window = body(self.source, "bool isTesterSaveWindowEnabled()")
        window = window.split("return ", 1)[1].split(";", 1)[0]
        cases = [
            ("M5 before gate", True, True, 10000, False, False),
            ("H1", False, True, 10000, False, True),
            ("LIVE", True, False, 10000, False, True),
            ("zero save start", True, True, 0, False, True),
            ("gate open", True, True, 10000, True, True),
        ]
        for name, m5, tester, save_start, gate, expected in cases:
            with self.subTest(name=name):
                save_window = evaluate_predicate(window, tester=tester, save_start=save_start)
                self.assertEqual(evaluate_predicate(eligibility, is_m5=m5, save_window=save_window,
                                                    gate_open=gate), expected)
        self.assertEqual(body(helper, "if (!this.observationProfile.isM5()").strip(), "return false;")

    def test_zero_market_clock_never_enters_warmup_throttle(self):
        helper = body(self.source, "bool shouldSkipM5TesterWarmup()")
        invalid_clock = condition(helper, "if (currentTime <= 0)")
        for current, expected in ((0, True), (-1, True), (1, False)):
            with self.subTest(current=current):
                self.assertEqual(evaluate_predicate(invalid_clock, current=current), expected)
        self.assertEqual(body(helper, "if (currentTime <= 0)").strip(), "return false;")
        self.assertLess(helper.index("if (currentTime <= 0)"), helper.index("this.testerWarmupActive = true"))

    def test_save_start_boundary_bypasses_previous_hour_wait_and_resets_state(self):
        helper = body(self.source, "bool shouldSkipM5TesterWarmup()")
        reached = condition(helper, "if (currentTime >= this.observationTesterSaveStartTime)")
        for current, expected in ((9999, False), (10000, True), (10001, True)):
            with self.subTest(current=current):
                self.assertEqual(evaluate_predicate(reached, current=current, save_start=10000), expected)
        branch = body(helper, "if (currentTime >= this.observationTesterSaveStartTime)")
        self.assertIn("this.testerWarmupActive = false", branch)
        self.assertIn("this.lastTesterWarmupTime = 0", branch)
        self.assertIn("return false;", branch)
        self.assertLess(helper.index("if (currentTime >= this.observationTesterSaveStartTime)"),
                        helper.index("long elapsedSeconds"))
        self.assertIn("TESTER_WARMUP_END", branch)

    def test_throttle_first_attempt_hour_boundary_and_clock_rollback(self):
        helper = body(self.source, "bool shouldSkipM5TesterWarmup()")
        throttle = condition(helper, "if (this.lastTesterWarmupTime > 0")
        cases = [("first", 0, 10, False), ("same second", 100, 0, True),
                 ("3599 seconds", 100, 3599, True), ("3600 seconds", 100, 3600, False),
                 ("3601 seconds", 100, 3601, False), ("rollback", 100, -1, False)]
        for name, last, elapsed, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(evaluate_predicate(throttle, last_warmup=last, elapsed=elapsed), expected)
        self.assertIn("currentTime - this.lastTesterWarmupTime", helper)
        branch = body(helper, "if (this.lastTesterWarmupTime > 0")
        self.assertEqual(branch.strip(), "return true;")
        self.assertLess(helper.index("return true;"), helper.index("this.lastTesterWarmupTime = currentTime"))
        self.assertTrue(helper.rstrip().endswith("return false;"))

    def test_history_log_arrays_created_and_cleared_per_symbol(self):
        initialize = body(self.source, "void initializeStateArrays()")
        clear = body(self.source, "void clearStateArrays()")
        for name, initial in (("lastHistoryLogTexts", '""'), ("lastHistoryLogTimes", "0")):
            with self.subTest(name=name):
                self.assertIn("ArrayResize(this." + name + ", total)", initialize)
                self.assertIn("this." + name + "[i] = " + initial, initialize)
                self.assertIn("ArrayResize(this." + name + ", 0)", clear)

    def test_common_checks_all_feet_without_first_failure_return(self):
        readiness = body(self.history, "bool prepare(")
        self.assertIn("this.getTimeFrameCount()", readiness)
        self.assertIn("this.getTimeFrame(i)", readiness)
        self.assertIn("this.getRequiredBars(timeFrame)", readiness)
        self.assertIn("WarmUpSeriesUtil::isSeriesSynchronized(", readiness)
        self.assertIn("Bars(", readiness)
        loop = body(readiness, "for (int i = 0;")
        self.assertNotIn("return false", loop)
        self.assertNotIn("return true", loop)
        self.assertIn("this.ready = false", body(loop, "if (!timeFrameReady)"))
        request = body(loop, "if ((!synchronized || availableBars < requiredBars) && mayRequest)")
        self.assertLess(request.index("CopyRates("), request.index("availableBars = Bars("))
        self.assertLess(request.index("CopyRates("), request.index("synchronized = WarmUpSeriesUtil"))
        self.assertNotIn("this.ready = true", request)

    def test_sufficient_feet_are_excluded_from_history_change_text(self):
        readiness = body(self.history, "bool prepare(")
        sufficient = readiness.split("bool timeFrameReady =", 1)[1].split(";", 1)[0]
        for synced, bars, required, expected in ((True, 61, 61, True), (True, 60, 61, False),
                                                (True, 206, 206, True), (True, 205, 206, False),
                                                (False, 500, 206, False)):
            with self.subTest(synced=synced, bars=bars, required=required):
                self.assertEqual(evaluate_predicate(sufficient, synchronized=synced,
                                                    availableBars=bars, requiredBars=required), expected)
        missing = body(readiness, "if (!timeFrameReady)")
        self.assertIn("this.missingStatusText += detail", missing)
        self.assertEqual(readiness.count("this.missingStatusText += detail"), 1)
        self.assertIn("this.statusText += detail", readiness)
        self.assertIn("SERIES_FIRSTDATE", body(self.history, "string createStatusText("))
        for field in ("bars=%d", "required=%d", "first=%s", "sync=%d"):
            self.assertIn(field, body(self.history, "string createStatusText("))
        self.assertIn('firstDateText = "UNAVAILABLE"', self.history)
        self.assertTrue(readiness.rstrip().endswith("return this.ready;"))

    def test_history_log_first_change_day_boundary_and_clock_rollback(self):
        log = body(self.source, "void logM5HistoryStatus(")
        throttle = condition(log, 'if (this.lastHistoryLogTexts[fromIndex] != "" &&')
        cases = [("first immediate", "", "A", 0, False),
                 ("changed at 3599", "A", "B", 3599, True),
                 ("changed at 3600", "A", "B", 3600, False),
                 ("unchanged at 3600", "A", "A", 3600, True),
                 ("unchanged at 86399", "A", "A", 86399, True),
                 ("unchanged at 86400", "A", "A", 86400, False),
                 ("rollback unchanged", "A", "A", -1, False),
                 ("rollback changed", "A", "B", -1, False)]
        for name, previous, current, elapsed, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(evaluate_predicate(throttle, last_history=previous,
                                                    history=current, elapsed=elapsed), expected)
        self.assertEqual(body(log, 'if (this.lastHistoryLogTexts[fromIndex] != "" &&').strip(), "return;")
        self.assertLess(log.index("ANALYSIS_HISTORY_UNAVAILABLE"),
                        log.index("this.lastHistoryLogTexts[fromIndex] = fromHistoryText"))
        self.assertIn("currentTime - this.lastHistoryLogTimes[fromIndex]", log)
        self.assertIn("this.lastHistoryLogTimes[fromIndex] = currentTime", log)

    def test_history_ready_is_immediate_once_and_clears_previous_log_state(self):
        log = body(self.source, "void logM5HistoryStatus(")
        ready = body(log, 'if (fromHistoryText == "")')
        emit = condition(ready, 'if (this.lastHistoryLogTexts[fromIndex] != "")')
        self.assertTrue(evaluate_predicate(emit, last_history="A"))
        self.assertFalse(evaluate_predicate(emit, last_history=""))
        self.assertIn("HISTORY_READY", body(ready, 'if (this.lastHistoryLogTexts[fromIndex] != "")'))
        self.assertIn('this.lastHistoryLogTexts[fromIndex] = ""', ready)
        self.assertIn("this.lastHistoryLogTimes[fromIndex] = 0", ready)
        self.assertTrue(ready.rstrip().endswith("return;"))
        self.assertLess(log.index('if (fromHistoryText == "")'), log.index("datetime currentTime"))

    def test_missing_current_m5_still_reports_specific_history_shortage(self):
        process = body(self.source, "void processSymbol(")
        missing = body(process, "if (currentH1BarTime <= 0)")
        self.assertEqual(missing.count("this.warmUpSymbol(fromIndex)"), 1)
        self.assertLess(missing.index("this.warmUpSymbol(fromIndex)"), missing.index("return;"))
        warmup = body(self.source, "void warmUpSymbol(")
        self.assertIn("this.isAnalysisSeriesReady(fromIndex)", warmup)
        self.assertNotIn("CopyRates(", warmup)
        readiness = body(self.source, "bool isAnalysisSeriesReady(")
        self.assertIn("return this.isM5AnalysisSeriesReady(fromIndex)", readiness)
        self.assertIn("getMissingStatusText()", body(self.source, "bool isM5AnalysisSeriesReady("))

    def test_missing_anchor_discards_stale_preflight_before_opening_save_gate(self):
        process = body(self.source, "void processSymbol(")
        missing = body(process, "if (currentH1BarTime <= 0)")
        self.assertIn("this.currentH1BarTimes[fromIndex] = 0", missing)
        closed_gate = body(missing, "if (this.isTesterSaveWindowEnabled() && !this.testerSaveGateOpen)")
        self.assertIn("this.analysisReadyFlags[fromIndex] = false", closed_gate)
        self.assertIn("this.testerPreflightH1BarTimes[fromIndex] = 0", closed_gate)
        self.assertLess(missing.index("this.analysisReadyFlags[fromIndex] = false"), missing.index("return;"))
        self.assertNotIn("this.testerSaveGateOpen = true", missing)
        gate = body(self.source, "bool tryOpenTesterSaveGate()")
        self.assertRegex(gate, r"this.currentH1BarTimes\[i\]\s*< this.observationTesterSaveStartTime")
        self.assertRegex(gate, r"this.testerPreflightH1BarTimes\[i\]\s*!= this.currentH1BarTimes\[i\]")

    def test_progress_does_not_depend_on_shutdown_or_claim_completion(self):
        destroy = body(self.source, "void destroy()")
        self.assertNotIn("logM5TesterProgress", destroy)
        for obsolete in ("logM5TesterCompletion", "M5_TESTER_SUMMARY",
                         "TESTER_SAVE_START_NOT_REACHED", "TESTER_SAVE_NOT_STARTED"):
            self.assertNotIn(obsolete, self.source)
        progress = body(self.source, "void logM5TesterProgress()")
        self.assertIn("M5_TESTER_PROGRESS", progress)
        self.assertNotIn("SUMMARY", progress)
        self.assertNotIn("COMPLETE", progress)

    def test_progress_called_after_drain_and_for_each_stop_or_source_wait_return(self):
        execute = body(self.source, "void execute()")
        self.assertEqual(execute.count("this.logM5TesterProgress()"), 4)
        stopped = body(execute, "if (this.competingWriterDetected || this.databaseRejected)")
        self.assertIn("this.logM5TesterProgress()", stopped)
        self.assertLess(stopped.index("this.logM5TesterProgress()"), stopped.index("return;"))
        failures = list(re.finditer(r"if \(!this\.ensureExecutionSource\(\)\)", execute))
        self.assertEqual(len(failures), 2)
        for index, match in enumerate(failures):
            with self.subTest(source_check=index):
                branch = body(execute[match.start():], "if (!this.ensureExecutionSource())")
                self.assertIn("this.logM5TesterProgress()", branch)
                self.assertLess(branch.index("this.logM5TesterProgress()"), branch.index("return;"))
        self.assertLess(execute.index("this.drainSnapshotQueue()"),
                        execute.rindex("this.logM5TesterProgress()"))
        self.assertLess(execute.rindex("this.executing = false"),
                        execute.rindex("this.logM5TesterProgress()"))

    def test_progress_clock_and_text_reset_at_construction_and_destruction(self):
        for signature in ("H1ElliotObservationAllController(", "void destroy()"):
            method = body(self.source, signature)
            with self.subTest(signature=signature):
                self.assertIn('this.lastM5TesterProgressText = ""', method)
                self.assertIn("this.lastM5TesterProgressTime = 0", method)

    def test_progress_excludes_uninitialized_h1_and_live_before_reading_status(self):
        progress = body(self.source, "void logM5TesterProgress()")
        guard = condition(progress, "if (!this.initialized")
        cases = [(True, True, True, False), (False, True, True, True),
                 (True, False, True, True), (True, True, False, True)]
        for initialized, m5, tester, expected in cases:
            with self.subTest(initialized=initialized, m5=m5, tester=tester):
                self.assertEqual(evaluate_predicate(guard, initialized=initialized, is_m5=m5,
                                                    tester=tester), expected)
        self.assertEqual(body(progress, "if (!this.initialized").strip(), "return;")
        self.assertLess(progress.index("if (!this.initialized"), progress.index("TimeCurrent()"))
        self.assertLess(progress.index("if (!this.initialized"), progress.index("this.logger.info"))

    def test_progress_first_change_hour_boundary_and_clock_rollback(self):
        progress = body(self.source, "void logM5TesterProgress()")
        throttle = condition(progress, 'if (this.lastM5TesterProgressText != ""')
        cases = [("first", "", "COLLECTING saved=0", 0, False),
                 ("same second", "WAIT_GATE", "WAIT_GATE", 0, True),
                 ("same 3599", "WAIT_GATE", "WAIT_GATE", 3599, True),
                 ("same 3600", "WAIT_GATE", "WAIT_GATE", 3600, False),
                 ("same 3601", "WAIT_GATE", "WAIT_GATE", 3601, False),
                 ("phase change", "WAIT_GATE", "COLLECTING", 0, False),
                 ("saved change", "COLLECTING saved=0", "COLLECTING saved=1", 1, False),
                 ("queue change", "DB_WAIT queued=1", "DB_WAIT queued=2", 1, False),
                 ("rollback", "WAIT_GATE", "WAIT_GATE", -1, False)]
        for name, previous, current, elapsed, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(evaluate_predicate(throttle, last_progress=previous,
                                                    progress=current, elapsed=elapsed), expected)
        self.assertEqual(body(progress, 'if (this.lastM5TesterProgressText != ""').strip(), "return;")
        self.assertIn("currentTime - this.lastM5TesterProgressTime", progress)
        self.assertLess(progress.index("M5_TESTER_PROGRESS"),
                        progress.index("this.lastM5TesterProgressText = progressText"))
        self.assertLess(progress.index("M5_TESTER_PROGRESS"),
                        progress.index("this.lastM5TesterProgressTime = currentTime"))

    def test_progress_comparison_key_has_state_counters_but_no_timestamp_values(self):
        progress = body(self.source, "void logM5TesterProgress()")
        comparison_key = progress.split("string progressText =", 1)[1].split(");", 1)[0]
        for field in ("phase=%s", "gateOpened=%d", "ready=%d/%d", "dbReady=%d",
                      "saved=%d", "queued=%d", "gaps=%d", "message=%s"):
            self.assertIn(field, comparison_key)
        for field in ("this.getM5TesterProgressPhase(currentTime)", "this.testerSaveGateOpen",
                      "this.getReadyCount()", "this.databaseReady", "this.totalSavedCount",
                      "this.snapshotQueue.Total()", "this.totalGapCount", "this.lastDatabaseMessage"):
            self.assertIn(field, comparison_key)
        for forbidden in ("formatDateTime", "this.currentBatchH1BarTime", "saveStart=", "serverTime=", "lastM5="):
            self.assertNotIn(forbidden, comparison_key)
        emitted = progress[progress.index("this.logger.info"):]
        for field in ("M5_TESTER_PROGRESS", "saveStart=%s", "serverTime=%s", "lastM5=%s",
                      "this.formatDateTime(this.observationTesterSaveStartTime)",
                      "this.formatDateTime(currentTime)", "this.formatDateTime(this.currentBatchH1BarTime)",
                      "progressText"):
            self.assertIn(field, emitted)

    def test_progress_phase_priority_and_save_window_boundary(self):
        phase = body(self.source, "string getM5TesterProgressPhase(")
        self.assertEqual(re.findall(r'return "([A-Z_]+)";', phase),
                         ["STOPPED", "SOURCE_WAIT", "WARMUP", "WAIT_GATE", "DB_WAIT", "COLLECTING"])
        stop = condition(phase, "if (this.competingWriterDetected || this.databaseRejected)")
        source_wait = condition(phase, 'if (this.databaseRun.sourceServer == ""')
        window = condition(phase, "if (this.isTesterSaveWindowEnabled())")
        window_body = body(phase, "if (this.isTesterSaveWindowEnabled())")
        warmup = condition(window_body, "if (fromCurrentTime < this.observationTesterSaveStartTime)")
        wait_gate = condition(window_body, "if (!this.testerSaveGateOpen)")
        database_wait = condition(phase, "if (!this.databaseReady)")
        self.assertEqual(body(window_body, "if (fromCurrentTime < this.observationTesterSaveStartTime)").strip(),
                         'return "WARMUP";')
        self.assertEqual(body(window_body, "if (!this.testerSaveGateOpen)").strip(), 'return "WAIT_GATE";')
        self.assertEqual(body(phase, "if (!this.databaseReady)").strip(), 'return "DB_WAIT";')
        self.assertTrue(phase.rstrip().endswith('return "COLLECTING";'))
        defaults = dict(competing_writer=False, rejected=False, source_server="server", message="",
                        save_window=True, save_start=10000, current=10000, gate_open=True, db_ready=True)
        cases = [
            ("collecting", {}, "COLLECTING"),
            ("competing writer beats source wait", {"competing_writer": True, "source_server": ""}, "STOPPED"),
            ("rejected beats warmup", {"rejected": True, "current": 9999}, "STOPPED"),
            ("empty source beats warmup", {"source_server": "", "current": 9999}, "SOURCE_WAIT"),
            ("explicit source wait", {"message": "取引サーバー情報を取得待ち"}, "SOURCE_WAIT"),
            ("before start beats gate and DB wait", {"current": 9999, "gate_open": False, "db_ready": False}, "WARMUP"),
            ("at start gate wait beats DB wait", {"gate_open": False, "db_ready": False}, "WAIT_GATE"),
            ("after start gate wait", {"current": 10001, "gate_open": False}, "WAIT_GATE"),
            ("DB wait after gate", {"db_ready": False}, "DB_WAIT"),
            ("saveStart0 bypasses warmup and gate", {"save_window": False, "gate_open": False, "current": 9999}, "COLLECTING"),
            ("saveStart0 DB wait", {"save_window": False, "gate_open": False, "db_ready": False}, "DB_WAIT"),
        ]
        # Compose only the source predicates whose nesting/order is checked above.
        # This is not execution of the Controller or an MQL runtime simulation.
        for name, changed, expected in cases:
            values = dict(defaults, **changed)
            if evaluate_predicate(stop, **values):
                actual = "STOPPED"
            elif evaluate_predicate(source_wait, **values):
                actual = "SOURCE_WAIT"
            elif evaluate_predicate(window, **values) and evaluate_predicate(warmup, **values):
                actual = "WARMUP"
            elif evaluate_predicate(window, **values) and evaluate_predicate(wait_gate, **values):
                actual = "WAIT_GATE"
            elif evaluate_predicate(database_wait, **values):
                actual = "DB_WAIT"
            else:
                actual = "COLLECTING"
            with self.subTest(name=name):
                self.assertEqual(actual, expected)

    def test_m5_indicator_and_run_share_program_version(self):
        indicator = (ROOT / "Indicators/ZigZagElliotM5ObservationAll.mq5").read_text(encoding="utf-8-sig")
        version = re.search(r'#property version\s+"([^"]+)"', indicator).group(1)
        run = body(self.source, "void setDatabaseRun()")
        self.assertIn('this.databaseRun.programVersion = "1.04"', run)
        self.assertIn(f'this.databaseRun.programVersion = "{version}"', body(run, "if (this.observationProfile.isM5())"))

    def test_new_diagnostics_do_not_trade_persist_or_rewrite_gate(self):
        for signature in ("bool shouldSkipM5TesterWarmup()", "bool isM5AnalysisSeriesReady(",
                          "void logM5HistoryStatus(", "void logM5TesterProgress()",
                          "string getM5TesterProgressPhase("):
            method = body(self.source, signature)
            with self.subTest(signature=signature):
                for forbidden in ("OrderSend(", "SendMail(", "Alert(", "SendNotification(",
                                  "DatabaseOpen(", "DatabaseExecute(", "saveSnapshot(",
                                  "this.testerSaveGateOpen = true", "this.snapshotQueue.Add(",
                                  "this.capturePendingObservation("):
                    self.assertNotIn(forbidden, method)


if __name__ == "__main__":
    unittest.main()
