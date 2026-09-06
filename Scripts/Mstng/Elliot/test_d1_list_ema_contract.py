"""Static source-wiring regression for the D1-fixed List EMA200 filter.

This does not execute MQL, indicator analysis, MT5, or broker operations.
Direction/value behavior is exercised separately by the MQL SmokeTest.
Run: python -B -m unittest discover -s Scripts/Mstng/Elliot -p test_d1_list_ema_contract.py -v
"""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/ExpertAdvisor"))
from test_h1_ea_tester_warmup_contract import block_end, code_only, method


def compact(source):
    return re.sub(r"\s+", "", code_only(source))


def typed_body(source, name):
    """Read a custom-return-type MQL method declaration, not a call site."""
    masked = code_only(source)
    match = re.search(r"(?m)^\s*(?:static\s+)?\w+\s+" + re.escape(name)
                      + r"\s*\([^;{}]*\)\s*\{", masked)
    if match is None:
        raise AssertionError(f"Missing method: {name}")
    return source[match.end():block_end(masked, match.end() - 1)]


def branch(source, condition):
    masked = code_only(source)
    match = re.search(r"if\s*\(" + condition + r"\)\s*\{", masked)
    if match is None:
        raise AssertionError(f"Missing branch: {condition}")
    end = block_end(masked, match.end() - 1)
    return match.start(), source[match.end():end]


class D1ListEmaWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths = {
            "indicator": "Indicators/ZigZagElliotList.mq5",
            "controller": "Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotListController.mqh",
            "decision": "Include/Mstng/Elliot/ElliotDirectionAlignmentDecision.mqh",
            "drawer": "Include/Mstng/Draw/DrawAlignedElliotAllList.mqh",
        }
        for name, path in paths.items():
            setattr(cls, name, (ROOT / path).read_text(encoding="utf-8-sig"))

    def test_only_d1_fixed_mode_enables_flag_and_keeps_three_existing_modes(self):
        initialize = method(self.indicator, "OnInit")
        position, fixed = branch(initialize, r"listMode\s*==\s*ZIGZAG_ELLIOT_LIST_MODE_D1")
        self.assertIn("boold1Ema200Required=false;", compact(initialize[:position]))
        self.assertEqual(compact(initialize).count("d1Ema200Required=true;"), 1)
        self.assertIn("d1Ema200Required=true;", compact(fixed))
        self.assertIn("listTimeFrame=PERIOD_D1;", compact(fixed))
        self.assertIn("alignmentStartTimeFrame=PERIOD_W1;", compact(fixed))
        for mode in ("MN1_AND_W1", "W1_WITH_MN1_OR_EMA200"):
            self.assertIn("ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_" + mode, compact(fixed))
        self.assertRegex(code_only(initialize),
                         r"gZigZagElliotListController\.initialize\([^;]*,\s*d1Ema200Required\s*,"
                         r"\s*h1D1AlignmentStartTimeFrame\s*,\s*h1D1AlignmentRule\s*\)")

    def test_controller_forwards_flag_only_to_primary_list_decision(self):
        initialize = compact(method(self.controller, "initialize"))
        self.assertIn("this.alignmentDecision=newElliotDirectionAlignmentDecision("
                      "fromAlignmentStartTimeFrame,fromAlignmentRule,fromD1Ema200Required);", initialize)
        self.assertIn("this.h1AlignmentDecision=newElliotDirectionAlignmentDecision("
                      "fromH1AlignmentStartTimeFrame,fromH1AlignmentRule);", initialize)
        alert_call = re.search(r"this\.alertAllController\.initialize\([^;]+\)", initialize)
        self.assertIsNotNone(alert_call)
        self.assertNotIn("fromD1Ema200Required", alert_call.group())
        self.assertRegex(code_only(self.controller), r"const bool fromD1Ema200Required\s*=\s*false")
        self.assertRegex(code_only(self.decision), r"bool fromD1Ema200Required\s*=\s*false")
        self.assertIn("this.d1Ema200Required=fromD1Ema200Required;",
                      compact(method(self.decision, "ElliotDirectionAlignmentDecision")))

    def test_instance_gate_requires_d1_and_enabled_flag_without_affecting_readiness(self):
        align = typed_body(self.decision, "getAlignType")
        condition = (r"fromCurrentTimeFrame\s*==\s*PERIOD_D1\s*&&\s*this\.d1Ema200Required"
                     r"\s*&&\s*!this\.isD1Ema200DirectionMatched\(fromElliotAll\)")
        position, rejected = branch(align, condition)
        self.assertEqual(compact(rejected), "returntrendAlignNone;")
        self.assertLess(compact(align).index("this.isReadyWithTimeFrames("),
                        compact(align).index("this.isD1Ema200DirectionMatched("))
        self.assertLess(position, align.index("evaluateD1W1WithMn1OrEma200("))
        for name in ("isReady", "isReadyWithTimeFrames"):
            self.assertNotIn("d1Ema200Required", method(self.decision, name))
            self.assertNotIn("isD1Ema200DirectionMatched", method(self.decision, name))

    def test_none_conflicts_and_timeframe_mismatches_cannot_pass_strict_helper(self):
        strict = method(self.decision, "isD1Ema200DirectionMatched")
        body = compact(strict)
        for owner in ("elliotD1", "elliotD1.oscillator", "elliotD1.oscillator.ema200"):
            self.assertIn(owner + ".marketContext.timeFrame!=PERIOD_D1", body)
        self.assertIn("elliotD1==NULL", body)
        self.assertRegex(strict, r'return isEma200Buy\s*&&\s*!isEma200Sell\s*&&\s*direction == "BUY";')
        self.assertRegex(strict, r'return !isEma200Buy\s*&&\s*isEma200Sell\s*&&\s*direction == "SELL";')

    def test_count_and_sorted_rows_use_same_filter_with_existing_d1_rank(self):
        for name in ("countRows", "buildDisplayOrder"):
            body = compact(method(self.drawer, name))
            self.assertIn("fromDecision.isReady(elliotAll,fromCurrentTimeFrame)", body)
            self.assertIn("fromDecision.getAlignType(elliotAll,fromCurrentTimeFrame)", body)
            self.assertNotIn("d1Ema200Required", body)
        order = compact(method(self.drawer, "buildDisplayOrder"))
        self.assertLess(order.index("if(alignType!=fromAlignType){continue;}"),
                        order.index("d1SortDecision.evaluate(elliotAll,d1SortResult);"))
        self.assertIn("ELLIOT_LIST_SORT_D1_ELLIOT_EMA&&fromCurrentTimeFrame==PERIOD_D1", order)
        self.assertIn("fromD1SortResults[displayCount]=d1SortResult;", order)
        for name in ("evaluateD1W1WithMn1OrEma200", "evaluateH4W1WithMn1OrEma200",
                     "evaluateH1W1WithMn1OrEma200"):
            body = typed_body(self.decision, name)
            self.assertNotIn("d1Ema200Required", body)
            self.assertNotIn("isD1Ema200DirectionMatched", body)

    def test_title_suffix_is_limited_to_enabled_d1_mode(self):
        _, title = branch(self.drawer, r"currentTimeFrame\s*==\s*PERIOD_D1\s*&&\s*fromDecision\.isD1Ema200Required\(\)")
        self.assertRegex(title, r'alignmentStartTimeFrameText\s*\+=\s*"&D1EMA";')
        self.assertEqual(self.drawer.count('"&D1EMA"'), 1)
        _, fixed = branch(method(self.indicator, "OnInit"), r"listMode\s*==\s*ZIGZAG_ELLIOT_LIST_MODE_D1")
        self.assertRegex(fixed, r'alignmentText\s*\+=\s*"&D1EMA";')
        self.assertEqual(self.indicator.count('"&D1EMA"'), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
