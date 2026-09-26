"""History-log source contracts and boundary checks of extracted MQL predicates.

The restricted evaluator checks production expressions, not a Python rewrite of
the logger. These tests do not execute MT5, measure speed, or verify log I/O.
"""

import ast
import operator
from pathlib import Path
import re
import unittest

from test_h1_ea_tester_warmup_contract import block_end, code_only, method


ROOT = Path(__file__).resolve().parents[3]


def condition(source, prefix):
    start = source.index("(", source.index(prefix)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "(") - (source[position] == ")")
        position += 1
    return source[start:position - 1]


def branch(source, prefix):
    opening = source.index("{", source.index(prefix))
    return source[opening + 1:block_end(code_only(source), opening)].strip()


def evaluate(expression, values):
    """Accept only known values, constants, boolean/comparison and integer ops."""
    resolved = {}
    for index, key in enumerate(sorted(values, key=len, reverse=True)):
        name = f"value{index}"
        expression = expression.replace(key, name)
        resolved[name] = values[key]
    expression = re.sub(r"\((?:u?long)\)", "", expression)
    expression = expression.replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", " not ", expression).strip()
    comparisons = {ast.Eq: operator.eq, ast.NotEq: operator.ne, ast.Lt: operator.lt,
                   ast.LtE: operator.le, ast.Gt: operator.gt, ast.GtE: operator.ge}
    operations = {ast.BitAnd: operator.and_, ast.LShift: operator.lshift,
                  ast.Div: operator.floordiv}

    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Name):
            return resolved[node.id]
        if isinstance(node, ast.Constant) and isinstance(node.value, (str, int, bool)):
            return node.value
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not visit(node.operand)
        if isinstance(node, ast.BoolOp) and isinstance(node.op, (ast.And, ast.Or)):
            results = [bool(visit(value)) for value in node.values]
            return all(results) if isinstance(node.op, ast.And) else any(results)
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            return comparisons[type(node.ops[0])](visit(node.left), visit(node.comparators[0]))
        if isinstance(node, ast.BinOp) and type(node.op) in operations:
            return operations[type(node.op)](visit(node.left), visit(node.right))
        raise AssertionError("Unsupported extracted syntax: " + ast.dump(node))

    return visit(ast.parse("(" + expression + ")", mode="eval"))


class PreparationHistoryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        def read(name):
            return (ROOT / name).read_text(encoding="utf-8-sig")
        cls.child = read("Include/MstngH1Ea/H1EaController.mqh")
        cls.parent = read("Include/MstngH1Ea/H1EaMultiSymbolController.mqh")
        cls.strategy = read("Include/MstngH1Ea/Strategy/H1EaStrategy.mqh")
        cls.state = read("Include/MstngH1Ea/Runtime/H1EaPreparationState.mqh")

    def test_unchanged_wait_ready_and_error_have_no_hourly_or_daily_repeat(self):
        log = method(self.child, "logPreparationHistory")
        guard = "if (now >= this.lastPreparationLogTime"
        unchanged = condition(log, guard)
        values = {"now": 100, "this.lastPreparationLogTime": 100,
                  "status": "WAIT_HISTORY", "this.lastPreparationLogStatus": "WAIT_HISTORY",
                  "reason": "ANALYSIS_HISTORY_UNAVAILABLE",
                  "this.lastPreparationLogReason": "ANALYSIS_HISTORY_UNAVAILABLE",
                  "missingMask": 1, "this.lastPreparationLogMissingMask": 1,
                  "unsynchronizedMask": 0, "this.lastPreparationLogUnsynchronizedMask": 0}
        for status in ("WAIT_HISTORY", "READY", "ERROR"):
            for elapsed in (0, 1, 3599, 3600, 86399, 86400, 864000):
                with self.subTest(status=status, elapsed=elapsed):
                    current = dict(values, status=status, now=100 + elapsed)
                    current["this.lastPreparationLogStatus"] = status
                    self.assertTrue(evaluate(unchanged, current))
        self.assertEqual(branch(log, guard), "return;")
        self.assertLess(log.index(guard), log.index("this.strategy.getHistoryMissingStatusText()"))
        for forbidden in ("historyText", "bars", "firstDate", "h1BarTime", "86400", "3600"):
            self.assertNotIn(forbidden, unchanged)

    def test_first_reason_mask_sync_status_error_and_rollback_emit_immediately(self):
        log = method(self.child, "logPreparationHistory")
        unchanged = condition(log, "if (now >= this.lastPreparationLogTime")
        values = {"now": 100, "this.lastPreparationLogTime": 100,
                  "status": "WAIT_HISTORY", "this.lastPreparationLogStatus": "WAIT_HISTORY",
                  "reason": "ANALYSIS_HISTORY_UNAVAILABLE",
                  "this.lastPreparationLogReason": "ANALYSIS_HISTORY_UNAVAILABLE",
                  "missingMask": 1, "this.lastPreparationLogMissingMask": 1,
                  "unsynchronizedMask": 0, "this.lastPreparationLogUnsynchronizedMask": 0}
        changes = [("first wait", {"this.lastPreparationLogStatus": ""}),
                   ("first ready", {"status": "READY", "this.lastPreparationLogStatus": ""}),
                   ("reason", {"reason": "H1_BAR_UNAVAILABLE_OR_CHANGED"}),
                   ("missing foot", {"missingMask": 3}),
                   ("same missing foot loses synchronization", {"unsynchronizedMask": 1}),
                   ("ready", {"status": "READY"}), ("error", {"status": "ERROR"}),
                   ("error reason", {"status": "ERROR", "this.lastPreparationLogStatus": "ERROR",
                                     "reason": "INITIALIZATION_FAILED"}),
                   ("rollback", {"now": 99})]
        for name, changed in changes:
            with self.subTest(name=name):
                self.assertFalse(evaluate(unchanged, dict(values, **changed)))
        error = condition(log, 'if (status == "ERROR")')
        self.assertTrue(evaluate(error, {"status": "ERROR"}))
        self.assertFalse(evaluate(error, {"status": "WAIT_HISTORY"}))
        self.assertIn("this.logger.error(", branch(log, 'if (status == "ERROR")'))
        self.assertIn("this.logger.info(", log)
        self.assertNotIn("getHistoryStatusText", log)
        self.assertIn('historyText = "history=READY"', log)
        for field in ("Status", "Reason", "MissingMask", "UnsynchronizedMask", "Time"):
            self.assertIn("this.lastPreparationLog" + field + " =", log)

    def test_daily_summary_requires_tester_and_first_28_timer_events(self):
        log = method(self.parent, "logHistoryWaitSummary")
        guard = "if (!MQLInfoInteger(MQL_TESTER)"
        skip = condition(log, guard)
        for tester, count, expected in ((False, 28, True), (True, 0, True),
                                         (True, 27, True), (True, 28, False), (True, 29, False)):
            with self.subTest(tester=tester, count=count):
                self.assertEqual(evaluate(skip, {"MQLInfoInteger(MQL_TESTER)": tester,
                    "this.timerCount": count, "ArraySize(this.controllers)": 28}), expected)
        self.assertEqual(branch(log, guard), "return;")
        record = method(self.parent, "recordTimerDuration")
        self.assertLess(record.index("this.timerCount++"), record.index("this.logHistoryWaitSummary()"))
        self.assertIn("this.lastHistorySummaryDay = -1", method(self.parent, "resetMonitorMetrics"))

    def test_daily_summary_uses_calendar_day_and_suppresses_all_ready(self):
        log = method(self.parent, "logHistoryWaitSummary")
        day_expression = log.split("long currentDay =", 1)[1].split(";", 1)[0].strip()
        same_day = condition(log, "if (currentDay == this.lastHistorySummaryDay)")
        for current, previous_day, expected in ((10 * 86400, -1, False),
                (10 * 86400 + 86399, 10, True), (11 * 86400, 10, False),
                (9 * 86400 + 86399, 10, False)):
            with self.subTest(current=current, previous_day=previous_day):
                day = evaluate(day_expression, {"TimeCurrent()": current})
                self.assertEqual(evaluate(same_day, {"currentDay": day,
                    "this.lastHistorySummaryDay": previous_day}), expected)
        self.assertEqual(branch(log, "if (currentDay == this.lastHistorySummaryDay)"), "return;")
        all_ready = "if (readyCount == ArraySize(this.controllers))"
        for count in (0, 27, 28):
            self.assertEqual(evaluate(condition(log, all_ready),
                {"readyCount": count, "ArraySize(this.controllers)": 28}), count == 28)
        self.assertEqual(branch(log, all_ready), "return;")
        self.assertLess(log.index("this.lastHistorySummaryDay = currentDay"), log.index(all_ready))
        self.assertLess(log.index(all_ready), log.index('"HISTORY_WAIT ready="'))
        self.assertEqual(log.count("this.timerLogger.info("), 1)

    def test_aggregation_distinguishes_unknown_ready_missing_and_error(self):
        log = method(self.parent, "logHistoryWaitSummary")
        ready = condition(log, "if (state.historyChecked && state.historyReady)")
        pending = condition(log, "if (!state.historyChecked)")
        missing = condition(log, "if (state.historyChecked && (state.historyMissingMask")
        for checked, is_ready, mask, expected in ((False, False, 0, (False, True, False)),
                (False, True, 31, (False, True, False)), (True, True, 0, (True, False, False)),
                (True, False, 1, (False, False, True)), (True, False, 2, (False, False, False))):
            values = {"state.historyChecked": checked, "state.historyReady": is_ready,
                      "state.historyMissingMask": mask, "j": 0}
            self.assertEqual(tuple(evaluate(expression, values) for expression in (ready, pending, missing)), expected)
        self.assertEqual(branch(log, 'if (state.status == "ERROR")'), "errorCount++;")
        self.assertIn('string timeFrames[5] = {"MN1", "W1", "D1", "H4", "H1"}', log)
        for guard in ("if (pendingCount > 0)", "if (errorCount > 0)", "if (missingCounts[i] > 0)"):
            self.assertIn(guard, log)

    def test_snapshot_reads_latest_cached_values_and_never_updates_trade_gate(self):
        snapshot = method(self.child, "getPreparationState")
        self.assertIn("fromState = this.preparationState;", snapshot)
        for field, getter, shared in (("historyChecked", "isHistoryChecked", "isChecked"),
                ("historyReady", "isHistoryPrepared", "isReady"),
                ("historyMissingMask", "getHistoryMissingMask", "getMissingMask"),
                ("historyUnsynchronizedMask", "getHistoryUnsynchronizedMask", "getUnsynchronizedMask")):
            self.assertIn(f"fromState.{field} = this.strategy.{getter}();", snapshot)
            self.assertEqual(method(self.strategy, getter).strip(),
                             f"return this.historyPreparation.{shared}();")
        self.assertNotIn("this.preparationState.historyReady =", snapshot)
        reset = method(self.state, "reset")
        for field, initial in (("historyChecked", "false"), ("historyMissingMask", "0"),
                               ("historyUnsynchronizedMask", "0")):
            self.assertIn(f"this.{field} = {initial};", reset)

    def test_log_paths_have_no_market_database_analysis_or_trading_side_effects(self):
        for source, name in ((self.child, "logPreparationHistory"),
                             (self.child, "getPreparationState"),
                             (self.parent, "logHistoryWaitSummary")):
            body = code_only(method(source, name))
            for forbidden in ("CopyRates", "CopyBuffer", "Bars(", "iTime(", "SeriesInfo",
                    "SymbolInfo", ".prepare(", ".prepareHistory(", ".processPreparation(",
                    "persistence.", "Database", "executor.", "strategy.analyze", "strategy.evaluate",
                    "OrderSend", "entryState.", "decisionQueue", "EventSet", "Sleep("):
                self.assertNotIn(forbidden, body, name)
        for name in ("onTimer", "processWarmupPreparation"):
            body = method(self.parent, name)
            self.assertIn("if (!MQLInfoInteger(MQL_TESTER) && (previousState.status != currentState.status", body)


if __name__ == "__main__":
    unittest.main()
