"""Static source-wiring regression for the H1 List's additional D1 condition.

This does not execute MQL, indicator analysis, MT5, or broker operations.
Direction/value behavior is covered separately by the MQL SmokeTest.
Run: python -B -m unittest discover -s Scripts/Mstng/Elliot -p test_h1_list_d1_contract.py -v
"""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/Elliot"))
from test_d1_list_ema_contract import branch, code_only, compact, method, typed_body


class H1ListD1WiringTests(unittest.TestCase):
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

    def test_new_instance_and_optional_controller_arguments_default_to_disabled(self):
        constructor = compact(method(self.decision, "ElliotDirectionAlignmentDecision"))
        self.assertIn("this.h1D1AlignmentStartTimeFrame=PERIOD_CURRENT;", constructor)
        self.assertEqual(compact(method(self.decision, "isH1D1ConditionRequired")),
                         "returnthis.h1D1AlignmentStartTimeFrame!=PERIOD_CURRENT;")
        setter = compact(method(self.decision, "setH1D1Condition"))
        for field in ("AlignmentStartTimeFrame", "AlignmentRule"):
            self.assertIn("this.h1D1" + field + "=from" + field + ";", setter)
        self.assertRegex(code_only(self.controller),
                         r"fromH1D1AlignmentStartTimeFrame\s*=\s*PERIOD_CURRENT")

    def test_selected_d1_condition_is_common_to_all_four_h1_modes(self):
        initialize = method(self.indicator, "OnInit")
        body = compact(initialize)
        self.assertIn("boolh1AlignmentSettingsEnabled=h1M5IndependentModeEnabled||"
                      "(listMode==ZIGZAG_ELLIOT_LIST_MODE_CHART&&_Period==PERIOD_H1);", body)
        position, common = branch(initialize, r"h1AlignmentSettingsEnabled")
        self.assertIn("h1D1AlignmentStartTimeFrame=PERIOD_CURRENT;", compact(initialize[:position]))
        self.assertIn("h1D1AlignmentStartTimeFrame=PERIOD_W1;", compact(common))
        _, mn1 = branch(common, r"d1AlignmentMode\s*==\s*ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_MN1_AND_W1")
        _, either = branch(common, r"d1AlignmentMode\s*==\s*ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_WITH_MN1_OR_EMA200")
        for selected in (mn1, either):
            self.assertIn("h1D1AlignmentStartTimeFrame=PERIOD_MN1;", compact(selected))
        self.assertIn("h1D1AlignmentRule=ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200;",
                      compact(either))
        self.assertNotIn("h1AlignmentMode", code_only(common))
        self.assertRegex(common, r'h1AlignmentText\s*\+=\s*"&D1\["\s*\+\s*d1ConditionText\s*\+\s*"\+EMA\]";')
        self.assertRegex(code_only(initialize), r"gZigZagElliotListController\.initialize\([^;]*,"
                         r"\s*h1D1AlignmentStartTimeFrame\s*,\s*h1D1AlignmentRule\s*\)")

    def test_invalid_d1_input_is_rejected_for_every_h1_mode(self):
        initialize = method(self.indicator, "OnInit")
        _, invalid = branch(initialize,
            r"\(listMode\s*==\s*ZIGZAG_ELLIOT_LIST_MODE_D1\s*\|\|\s*"
            r"listMode\s*==\s*ZIGZAG_ELLIOT_LIST_MODE_H4\s*\|\|\s*h1AlignmentSettingsEnabled\)"
            r"\s*&&\s*d1AlignmentMode\s*!=\s*ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_ONLY"
            r"\s*&&\s*d1AlignmentMode\s*!=\s*ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_MN1_AND_W1"
            r"\s*&&\s*d1AlignmentMode\s*!=\s*ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_WITH_MN1_OR_EMA200")
        self.assertIn("returnINIT_PARAMETERS_INCORRECT;", compact(invalid))

    def test_controller_configures_chart_h1_and_upper_h1_but_not_primary_m5_or_alert(self):
        initialize = method(self.controller, "initialize")
        _, primary = branch(initialize, r"this\.marketContext\.timeFrame\s*==\s*PERIOD_H1")
        call = ".setH1D1Condition(fromH1D1AlignmentStartTimeFrame,fromH1D1AlignmentRule);"
        self.assertIn("this.alignmentDecision" + call, compact(primary))
        _, independent = branch(initialize, r"this\.h1M5IndependentModeEnabled")
        self.assertIn("this.h1AlignmentDecision" + call, compact(independent))
        self.assertNotIn("this.alignmentDecision.setH1D1Condition", compact(independent))
        self.assertEqual(compact(initialize).count(".setH1D1Condition("), 2)
        alert = re.search(r"this\.alertAllController\.initialize\([^;]+\)", compact(initialize))
        self.assertIsNotNone(alert)
        self.assertNotIn("H1D1", alert.group())

    def test_h1_gate_reuses_selected_d1_rule_with_mandatory_ema_before_existing_modes(self):
        align = typed_body(self.decision, "getAlignType")
        position, rejected = branch(align,
            r"fromCurrentTimeFrame\s*==\s*PERIOD_H1\s*&&\s*this\.isH1D1ConditionRequired\(\)"
            r"\s*&&\s*this\.getH1D1AlignType\(fromElliotAll\)\s*==\s*trendAlignNone")
        self.assertEqual(compact(rejected), "returntrendAlignNone;")
        self.assertLess(position, align.index("evaluateD1W1WithMn1OrEma200("))
        helper = compact(typed_body(self.decision, "getH1D1AlignType"))
        self.assertIn("ElliotDirectionAlignmentDecisiond1Decision("
                      "this.h1D1AlignmentStartTimeFrame,this.h1D1AlignmentRule,true);", helper)
        self.assertIn("returnd1Decision.getAlignType(fromElliotAll,PERIOD_D1);", helper)

    def test_readiness_only_requires_d1_data_and_d1_rejection_cannot_be_runner_up(self):
        ready = method(self.decision, "isReady")
        _, extra = branch(ready,
            r"fromCurrentTimeFrame\s*==\s*PERIOD_H1\s*&&\s*this\.isH1D1ConditionRequired\(\)")
        self.assertIn("returnd1Decision.isReady(fromElliotAll,PERIOD_D1);", compact(extra))
        for forbidden in ("getAlignType", "getH1D1AlignType", "isD1Ema200DirectionMatched"):
            self.assertNotIn(forbidden, code_only(ready))
        runner = method(self.decision, "getH1RunnerUpResult")
        position, gated = branch(runner, r"this\.isH1D1ConditionRequired\(\)")
        self.assertIn("fromCurrentTimeFrame!=PERIOD_H1", compact(runner[:position]))
        self.assertIn("fromResult.reset();", compact(runner[:position]))
        self.assertIn("if(!this.isReady(fromElliotAll,fromCurrentTimeFrame)){returnfalse;}", compact(gated))
        self.assertIn("if(this.getH1D1AlignType(fromElliotAll)==trendAlignNone){returntrue;}", compact(gated))
        self.assertLess(position, runner.index("evaluateH1W1WithMn1OrEma200RunnerUp("))

    def test_shared_static_decisions_and_existing_h1_ranking_do_not_gain_list_state(self):
        static_names = re.findall(r"static\s+\w+\s+(evaluate\w+)\s*\(", code_only(self.decision))
        self.assertGreaterEqual(len(static_names), 7)
        for name in static_names:
            for forbidden in ("h1D1Alignment", "H1D1Condition", "getH1D1AlignType"):
                self.assertNotIn(forbidden, typed_body(self.decision, name))
        for name in ("countRows", "buildDisplayOrder"):
            body = compact(method(self.drawer, name))
            self.assertIn("fromDecision.isReady(elliotAll,fromCurrentTimeFrame)", body)
            self.assertIn("fromDecision.getAlignType(elliotAll,fromCurrentTimeFrame)", body)
            self.assertNotIn("h1D1Alignment", body)
        order = compact(method(self.drawer, "buildDisplayOrder"))
        self.assertLess(order.index("if(alignType!=fromAlignType){continue;}"),
                        order.index("h1D1SortDecision.evaluate("))
        self.assertIn("h1D1SortDecision.evaluate(d1SortResult,priorityTimeFrame,priorityResult,h1D1SortResult);", order)

    def test_title_describes_selected_d1_condition_only_for_enabled_h1(self):
        _, title = branch(self.drawer,
            r"currentTimeFrame\s*==\s*PERIOD_H1\s*&&\s*fromDecision\.isH1D1ConditionRequired\(\)")
        self.assertIn("fromDecision.getH1D1AlignmentRule()", title)
        self.assertIn("fromDecision.getH1D1AlignmentStartTimeFrame()", title)
        self.assertRegex(title, r'alignmentStartTimeFrameText\s*\+=\s*"&D1\["\s*\+\s*d1ConditionText\s*\+\s*"\+EMA\]";')
        self.assertEqual(self.drawer.count('"&D1["'), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
