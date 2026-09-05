"""Static source contracts for EMA readiness and H1 analysis retries.

These tests inspect the actual MQL source and its block boundaries. They do
not execute MQL, indicator calculations, clocks, orders, or Strategy Tester.
Operator checks describe the source's intended boundary behavior; they are
not a Python simulation or evidence of MT5 runtime behavior/performance.

Run with: python -B -m unittest discover -s Scripts/Mstng/ExpertAdvisor
          -p test_h1_ea_analysis_retry_contract.py -v
"""

import re
import unittest

from test_h1_ea_tester_warmup_contract import ROOT, block_end, code_only, method


CONTROLLER = ROOT / "Include/MstngH1Ea/H1EaController.mqh"
EMA = ROOT / "Include/Mstng/Oscillator/Ema200.mqh"
LOGGER = ROOT / "Include/Mstng/Log/Logger.mqh"
STRATEGY = ROOT / "Include/MstngH1Ea/Strategy/H1EaStrategy.mqh"


def compact(source: str) -> str:
    """Compare executable tokens, not matching words in comments or literals."""
    return re.sub(r"\s+", "", code_only(source))


def branch(source: str, condition: str) -> tuple[int, int, str]:
    """Return one exact if-condition's body using balanced MQL braces."""
    masked = code_only(source)
    matches = list(re.finditer(r"\bif\s*\(\s*" + condition + r"\s*\)\s*\{", masked))
    if len(matches) != 1:
        raise AssertionError(f"Expected one if-condition, found {len(matches)}: {condition}")
    match = matches[0]
    ending = block_end(masked, match.end() - 1)
    return match.start(), ending + 1, source[match.end():ending]


class AnalysisRetrySourceTests(unittest.TestCase):
    """Verify real-source wiring only; runtime acceptance remains separate."""

    @classmethod
    def setUpClass(cls):
        cls.controller = CONTROLLER.read_text(encoding="utf-8-sig")
        cls.ema = EMA.read_text(encoding="utf-8-sig")
        cls.logger = LOGGER.read_text(encoding="utf-8-sig")
        cls.strategy = STRATEGY.read_text(encoding="utf-8-sig")

    def entry(self):
        return method(self.controller, "evaluateEntry")

    def retry_branch(self, source):
        # Strict '<' means equality is eligible; the same-bar equality must
        # also be present so a new H1 bar cannot inherit the previous wait.
        return branch(source,
                      r"this\.config\.isTester\s*&&\s*this\.analysisRetryBar\s*==\s*barTime"
                      r"\s*&&\s*TimeCurrent\(\)\s*<\s*this\.nextAnalysisRetryTime")

    def failure_branch(self, source):
        return branch(source, r"!this\.strategy\.analyze\(snapshot\)")

    def test_retry_state_has_datetime_fields_and_explicit_zero_initializers(self):
        declarations = code_only(self.controller)
        constructor = compact(method(self.controller, "H1EaController"))
        for name in ("analysisRetryBar", "nextAnalysisRetryTime"):
            with self.subTest(field=name):
                self.assertRegex(declarations, rf"\bdatetime\s+{name}\s*;")
                self.assertIn(f"this.{name}=0;", constructor)

    def test_retry_guard_requires_tester_same_bar_and_strictly_earlier_time(self):
        _, _, retry = self.retry_branch(self.entry())
        self.assertEqual(compact(retry), "return;")

    def test_bar_observation_expired_save_and_finalized_check_precede_retry(self):
        source = self.entry()
        body = code_only(source)
        retry_start, _, _ = self.retry_branch(source)
        expired_start, expired_end, expired = branch(source, r"expiredBar\s*>\s*0")
        finalized_start, finalized_end, finalized = branch(
            source, r"this\.entryState\.isFinalized\(barTime\)")
        self.assertLess(body.index("this.entryState.observe(barTime)"), expired_start)
        self.assertLess(expired_end, finalized_start)
        self.assertLess(finalized_end, retry_start)
        self.assertEqual(compact(finalized), "return;")
        expired_code = compact(expired)
        for operation in ("this.initializeDecision(unavailable,expiredBar);",
                          "this.enqueueDecision(unavailable);", "this.flushDecisions();"):
            self.assertIn(operation, expired_code)
        self.assertIn('unavailable.reasonCode = "ANALYSIS_UNAVAILABLE";', expired)
        self.assertNotIn("nextAnalysisRetryTime", expired_code)

    def test_retry_state_clears_before_each_allowed_analysis_attempt(self):
        source = self.entry()
        _, retry_end, _ = self.retry_branch(source)
        failure_start, _, _ = self.failure_branch(source)
        between = compact(source[retry_end:failure_start])
        self.assertEqual(between,
                         "this.analysisRetryBar=0;this.nextAnalysisRetryTime=0;"
                         "H1EaStrategySnapshotsnapshot;")

    def test_only_failed_tester_analysis_arms_one_second_server_time_retry(self):
        source = self.entry()
        _, _, failure = self.failure_branch(source)
        _, arm_end, armed = branch(failure, r"this\.config\.isTester")
        self.assertEqual(compact(armed),
                         "this.analysisRetryBar=barTime;"
                         "this.nextAnalysisRetryTime=TimeCurrent()+1;")
        self.assertEqual(compact(failure[arm_end:]), "this.logAnalysisWait(barTime);return;")
        assignments = re.findall(
            r"this\.(analysisRetryBar|nextAnalysisRetryTime)\s*=(?!=)\s*([^;]+);",
            code_only(source),
        )
        assignments = [(name, re.sub(r"\s+", "", value)) for name, value in assignments]
        self.assertEqual(assignments, [
            ("analysisRetryBar", "0"), ("nextAnalysisRetryTime", "0"),
            ("analysisRetryBar", "barTime"), ("nextAnalysisRetryTime", "TimeCurrent()+1"),
        ])

    def test_analysis_failure_returns_without_judge_consumption_or_orders(self):
        source = self.entry()
        _, failure_end, failure = self.failure_branch(source)
        body = code_only(source)
        for operation in ("this.strategy.evaluate(", "this.buildDecision(",
                          "this.entryState.recordCount(", "this.entryState.finalize(",
                          "this.persistence.saveEntry(", "this.executor.sendEntry("):
            with self.subTest(operation=operation):
                self.assertNotIn(operation, code_only(failure))
                self.assertGreater(body.index(operation), failure_end)
        for forbidden in ("enqueueDecision", "flushDecisions", "observe(", "OrderSend("):
            self.assertNotIn(forbidden, code_only(failure))
        self.assertTrue(compact(failure).endswith("this.logAnalysisWait(barTime);return;"))

    def test_success_and_bar_identity_checks_precede_normal_judge_consumption(self):
        source = self.entry()
        body = code_only(source)
        _, failure_end, _ = self.failure_branch(source)
        changed_start, changed_end, changed = branch(source, r"snapshot\.h1BarTime\s*!=\s*barTime")
        self.assertLess(failure_end, body.index("this.clearAnalysisWait();"))
        self.assertLess(body.index("this.clearAnalysisWait();"), changed_start)
        self.assertIn("return;", code_only(changed))
        self.assertLess(changed_end, body.index("this.entryState.getCount("))
        self.assertLess(body.index("this.strategy.evaluate("), body.index("this.buildDecision("))
        self.assertLess(body.index("this.entryState.recordCount("), body.index("this.entryState.finalize("))
        self.assertNotIn("analysisRetryBar", body[failure_end:])
        self.assertNotIn("nextAnalysisRetryTime", body[failure_end:])

    def test_tick_protection_runs_before_entry_retry_and_has_no_retry_guard(self):
        source = method(self.controller, "onTick")
        body = code_only(source)
        tester_start, _, tester = branch(source, r"this\.config\.isTester")
        self.assertEqual(compact(tester), "this.evaluateEntry();")
        for operation in ("this.maintainPersistence();", "this.updateManagementAuthority();",
                          "this.executor.reconcile();", "this.executor.processPending(barTime);",
                          "this.executor.evaluateTrail("):
            self.assertLess(body.index(operation), tester_start, operation)
        self.assertNotIn("analysisRetryBar", body)
        self.assertNotIn("nextAnalysisRetryTime", body)

    def test_live_timer_retains_independent_thirty_second_schedule(self):
        source = method(self.controller, "onTimer")
        start, _, live = branch(
            source, r"!this\.config\.isTester\s*&&\s*GetTickCount64\(\)\s*>=\s*this\.nextEntryTick")
        self.assertEqual(compact(live),
                         "this.nextEntryTick=GetTickCount64()+30000;this.evaluateEntry();")
        body = code_only(source)
        self.assertLess(body.index("this.executor.reconcile();"), start)
        self.assertNotIn("analysisRetryBar", body)
        self.assertNotIn("nextAnalysisRetryTime", body)

    def test_retry_is_nonblocking_and_does_not_enter_warmup_bookkeeping(self):
        for name in ("evaluateEntry", "onTick", "onTimer", "processTesterWarmup"):
            with self.subTest(method=name):
                body = code_only(method(self.controller, name))
                self.assertNotRegex(body, r"\bSleep\s*\(")
                if name == "processTesterWarmup":
                    self.assertNotIn("analysisRetryBar", body)
                    self.assertNotIn("nextAnalysisRetryTime", body)

    def test_ema_copy_requests_calculation_without_barscalculated_gate(self):
        body = code_only(method(self.ema, "copyEmaValues"))
        self.assertNotRegex(body, r"\bBarsCalculated\s*\(")
        self.assertIn("int copyCount = maxShift + 1;", body)
        copy = re.search(r"int\s+copied\s*=\s*CopyBuffer\(this\.ema200Handle,\s*0,\s*0,"
                         r"\s*copyCount,\s*emaBuffer\)\s*;", body)
        self.assertIsNotNone(copy)
        self.assertEqual(len(re.findall(r"\bCopyBuffer\s*\(", body)), 1)
        self.assertLess(body.index("ArraySetAsSeries(emaBuffer, true);"), copy.start())
        self.assertLess(body.index("ResetLastError();"), copy.start())

    def test_ema_partial_or_failed_copy_returns_false_before_value_use(self):
        source = method(self.ema, "copyEmaValues")
        body = code_only(source)
        start, end, short = branch(source, r"copied\s*!=\s*copyCount")
        self.assertLess(body.index("CopyBuffer("), start)
        self.assertEqual(compact(short).count("returnfalse;"), 1)
        self.assertNotIn("returntrue;", compact(short))
        self.assertLess(end, body.index("for (int i = 0; i < copyCount; i++)"))

    def test_ema_checks_all_copied_values_before_reporting_success(self):
        source = method(self.ema, "copyEmaValues")
        body = code_only(source)
        loop = re.search(r"for\s*\(int\s+i\s*=\s*0;\s*i\s*<\s*copyCount;\s*i\+\+\)\s*\{", body)
        self.assertIsNotNone(loop)
        loop_end = block_end(body, loop.end() - 1)
        loop_body = source[loop.end():loop_end]
        _, _, invalid = branch(loop_body,
                               r"!MathIsValidNumber\(emaBuffer\[i\]\)\s*\|\|"
                               r"\s*emaBuffer\[i\]\s*==\s*EMPTY_VALUE")
        self.assertIn("returnfalse;", compact(invalid))
        self.assertNotIn("returntrue;", compact(source[:loop_end]))
        self.assertEqual(compact(source[loop_end + 1:]), "returntrue;")

    def test_ema_invalid_shift_and_missing_price_bars_still_fail_closed(self):
        source = method(self.ema, "copyEmaValues")
        copy_start = code_only(source).index("CopyBuffer(")
        for condition in (r"maxShift\s*<\s*0", r"bars\s*<=\s*maxShift"):
            with self.subTest(condition=condition):
                _, end, invalid = branch(source, condition)
                self.assertLess(end, copy_start)
                self.assertIn("returnfalse;", compact(invalid))

    def test_log_repeat_scope_defaults_off_and_requires_valid_tester_context(self):
        self.assertIn("bool Logger::repeatScopeActive = false;", code_only(self.logger))
        source = method(self.logger, "beginTesterRepeatScope")
        body = code_only(source)
        # String literals are masked; confirm the empty-symbol literal in the
        # same real guard separately rather than matching it in a comment.
        start, end, rejected = branch(
            source, r"!MQLInfoInteger\(MQL_TESTER\)\s*\|\|\s*fromSymbol\s*=="
                    r"\s*\|\|\s*fromH1BarTime\s*<=\s*0")
        self.assertIn('fromSymbol == ""', source[start:end])
        self.assertEqual(compact(rejected), "return;")
        self.assertLess(body.index("fromScope.started = false;"), start)
        self.assertLess(body.index("fromScope.wasActive = false;"), start)
        self.assertIn('fromScope.previousKey = "";', source[:start])
        self.assertGreater(body.index("Logger::repeatScopeActive = true;"), end)
        self.assertEqual(code_only(self.logger).count("Logger::repeatScopeActive = true;"), 1)

    def test_strategy_scope_wraps_only_full_elliot_analysis_and_always_ends(self):
        source = method(self.strategy, "analyze")
        body = compact(source)
        wrapping = (
            "Logger::beginTesterRepeatScope(this.marketContext.symbolName,barTime,logScope);"
            "this.elliotAll.analyze();"
            "Logger::endTesterRepeatScope(logScope,this.elliotAll.isAnalysisSucceeded);"
        )
        self.assertIn(wrapping, body)
        self.assertLess(body.index("this.prepareHistory()"), body.index(wrapping))
        self.assertLess(body.index(wrapping), body.index("decision.prepare("))
        self.assertEqual(code_only(self.strategy).count("Logger::beginTesterRepeatScope("), 1)
        self.assertEqual(code_only(self.strategy).count("Logger::endTesterRepeatScope("), 1)
        for name in ("evaluate", "prepareHistory"):
            self.assertNotIn("RepeatScope", code_only(method(self.strategy, name)))

    def test_log_repeat_filter_allows_normal_logs_and_non_info_error_levels(self):
        source = method(self.logger, "isRepeatedOutput")
        start, end, inactive = branch(
            source, r"!Logger::repeatScopeActive\s*\|\|\s*\(fromLevel\s*!=\s*LOG_INFO"
                    r"\s*&&\s*fromLevel\s*!=\s*LOG_ERROR\)")
        self.assertEqual(compact(source[:start]), "")
        self.assertEqual(compact(inactive), "returnfalse;")
        self.assertLess(end, code_only(source).index("for (int i = 0;"))

    def test_log_repeat_cache_changes_with_symbol_bar_key_and_clears_on_success(self):
        begin = method(self.logger, "beginTesterRepeatScope")
        self.assertIn('Logger::repeatScopeKey = fromSymbol + "|" + IntegerToString((long)fromH1BarTime);', begin)
        for name in ("beginTesterRepeatScope", "isRepeatedOutput"):
            with self.subTest(method=name):
                source = method(self.logger, name)
                _, _, changed = branch(source, r"Logger::repeatCacheKey\s*!=\s*Logger::repeatScopeKey")
                self.assertEqual(compact(changed),
                                 "Logger::clearRepeatCache();Logger::repeatCacheKey=Logger::repeatScopeKey;")
                self.assertEqual(compact(source).count("Logger::clearRepeatCache();"), 1)
        ending = method(self.logger, "endTesterRepeatScope")
        _, _, success = branch(ending, r"fromSucceeded")
        self.assertEqual(compact(success), "Logger::clearRepeatCache();")
        self.assertEqual(compact(ending).count("Logger::clearRepeatCache();"), 1)
        clear = method(self.logger, "clearRepeatCache")
        self.assertIn('Logger::repeatCacheKey = "";', clear)
        self.assertIn('Logger::repeatedOutputs[i] = "";', clear)
        self.assertIn("Logger::repeatedOutputCount=0;", compact(clear))
        self.assertIn("Logger::nextRepeatedOutputIndex=0;", compact(clear))

    def test_log_repeat_scope_restores_previous_state_and_invalid_token_is_noop(self):
        begin = compact(method(self.logger, "beginTesterRepeatScope"))
        self.assertLess(begin.index("fromScope.wasActive=Logger::repeatScopeActive;"),
                        begin.index("Logger::repeatScopeActive=true;"))
        self.assertLess(begin.index("fromScope.previousKey=Logger::repeatScopeKey;"),
                        begin.index("Logger::repeatScopeActive=true;"))
        source = method(self.logger, "endTesterRepeatScope")
        _, rejected_end, rejected = branch(source, r"!fromScope\.started")
        self.assertEqual(compact(rejected), "return;")
        _, success_end, _ = branch(source, r"fromSucceeded")
        self.assertLess(rejected_end, success_end)
        self.assertEqual(compact(source[success_end:]),
                         "Logger::repeatScopeActive=fromScope.wasActive;"
                         "Logger::repeatScopeKey=fromScope.previousKey;fromScope.started=false;")

    def test_log_filter_compares_full_formatted_output_before_print(self):
        source = method(self.logger, "log")
        body = code_only(source)
        start, end, repeated = branch(source, r"Logger::isRepeatedOutput\(level,\s*output\)")
        self.assertEqual(compact(repeated), "return;")
        self.assertLess(body.index("string output = StringFormat("), start)
        self.assertLess(end, body.index("Print(output);"))
        for value in ("this.levelToString(level)", "this.marketContext.symbolName",
                      "this.marketContext.timeFrameLabel", "funcName", "message"):
            self.assertIn(value, body[:start])
        source = method(self.logger, "isRepeatedOutput")
        _, _, duplicate = branch(source, r"Logger::repeatedOutputs\[i\]\s*==\s*fromOutput")
        self.assertEqual(compact(duplicate), "returntrue;")
        self.assertEqual(compact(source).count("returntrue;"), 1)

    def test_log_ring_is_bounded_and_new_output_is_not_suppressed_when_full(self):
        declarations = code_only(self.logger)
        self.assertRegex(declarations, r"static\s+string\s+repeatedOutputs\[64\];")
        source = method(self.logger, "isRepeatedOutput")
        body = code_only(source)
        write = body.index("Logger::repeatedOutputs[Logger::nextRepeatedOutputIndex] = fromOutput;")
        _, wrap_end, wrapped = branch(
            source, r"Logger::nextRepeatedOutputIndex\s*>=\s*ArraySize\(Logger::repeatedOutputs\)")
        self.assertEqual(compact(wrapped), "Logger::nextRepeatedOutputIndex=0;")
        self.assertLess(write, wrap_end)
        _, count_end, counted = branch(
            source, r"Logger::repeatedOutputCount\s*<\s*ArraySize\(Logger::repeatedOutputs\)")
        self.assertEqual(compact(counted), "Logger::repeatedOutputCount++;")
        self.assertEqual(compact(source[count_end:]), "returnfalse;")
        self.assertNotIn("returntrue;", compact(source[write:]))
        self.assertNotRegex(body, r"\bArrayResize\s*\(")


if __name__ == "__main__":
    unittest.main(verbosity=2)
