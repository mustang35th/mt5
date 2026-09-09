"""Static regression for highest-timeframe F/FE display metadata.

These tests inspect real MQL sources. They do not execute MQL calculations,
MT5 rendering, database writes, or broker operations.
Run: python -B -m unittest discover -s Scripts/Mstng/Elliot -p test_elliot_highest_fibonacci_contract.py -v
"""

from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/ExpertAdvisor"))
from test_h1_ea_tester_warmup_contract import code_only, method


def compact(source):
    return re.sub(r"\s+", "", code_only(source))


class HighestFibonacciContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths = {
            "highest": "Include/Mstng/Elliot/Analysis/ElliotHighest.mqh",
            "base": "Include/Mstng/Elliot/Analysis/ElliotBase.mqh",
            "wave": "Include/Mstng/Elliot/Wave.mqh",
            "point": "Include/Mstng/Elliot/ZigZagPoint.mqh",
            "point_util": "Include/Mstng/Elliot/ZigZagPointUtil.mqh",
            "observation": "Include/Mstng/ExpertAdvisor/ZigZagElliotObservationSnapshotBuilder.mqh",
        }
        for name, path in paths.items():
            setattr(cls, name, (ROOT / path).read_text(encoding="utf-8-sig"))

    def test_highest_sets_original_fields_after_analysis_before_copy(self):
        body = compact(method(self.highest, "analyze"))
        sequence = (
            "this.analyzeWave();"
            "Wave*wave=this.waveList.At(0);"
            "ZigZagPointUtil::setOrgField(wave.zigZagPointList);"
            "ZigZagPointUtil::copyZigZagPointList(wave.zigZagPointList,wave.orgZigZagPointList);"
        )
        self.assertIn(sequence, body)
        self.assertEqual(body.count("ZigZagPointUtil::setOrgField("), 1)

    def test_original_number_and_label_copy_current_values_without_recalculation(self):
        body = compact(method(self.point_util, "setOrgField"))
        self.assertIn("for(inti=0;i<total;i++){", body)
        self.assertIn("zigZagPoint.orgElliotIndex=zigZagPoint.elliotIndex;", body)
        self.assertIn("zigZagPoint.orgElliotLabel=zigZagPoint.elliotLabel;", body)
        self.assertNotIn("fibonacciPercent", body)
        self.assertNotIn("fibonacciExpansionPercent", body)

    def test_highest_wave_calculates_f_and_fe_without_timeframe_exclusion(self):
        self.assertIn("wave.analyze();", compact(method(self.base, "analyzeWave")))
        self.assertEqual(
            compact(method(self.wave, "analyze")),
            "this.setElliotLabel();this.setPipsAndWaveBarsFromStart();"
            "this.setFibonacci();this.setFibonacciExpansion();",
        )
        for name in ("setFibonacci", "setFibonacciExpansion"):
            with self.subTest(method=name):
                body = code_only(method(self.wave, name))
                self.assertNotRegex(body, r"\bPERIOD_\w+|\bmarketContext\b|\btimeFrame\b")
        self.assertIn("zigZagPointNext.fibonacciPercent=NormalizeDouble(",
                      compact(method(self.wave, "setFibonacci")))
        self.assertIn("zigZagPoint.fibonacciExpansionPercent=percent*100;",
                      compact(method(self.wave, "setFibonacciExpansion")))

    def test_point_text_selects_f_or_fe_by_original_index_for_every_timeframe(self):
        body = method(self.point, "getTextFibonacci")
        self.assertIn("intindex=this.orgElliotIndex;", compact(body))
        self.assertRegex(
            body,
            r'if\s*\(index > 1\)\s*\{\s*if\s*\(Util::isEven\(index\)\)\s*\{'
            r'\s*text \+= "\[F" \+ DoubleToString\(this.fibonacciPercent, 1\) \+ "%\]";'
            r'\s*\} else \{\s*text \+= "\[FE" \+ '
            r'DoubleToString\(this.fibonacciExpansionPercent, 1\) \+ "%\]";',
        )
        self.assertNotRegex(code_only(body), r"\bPERIOD_\w+|\bmarketContext\b|\btimeFrame\b")
        self.assertIn("text+=this.getTextFibonacci();",
                      compact(method(self.point, "getTextIndexInfo")))

    def test_observation_preserves_values_and_original_display_metadata(self):
        body = compact(method(self.observation, "buildTimeFrame"))
        for saved, source in (
            ("latestPointFibonacciPercent", "fibonacciPercent"),
            ("latestPointFibonacciExpansionPercent", "fibonacciExpansionPercent"),
            ("latestPointOrgElliotIndex", "orgElliotIndex"),
        ):
            with self.subTest(field=saved):
                self.assertIn(f"fromEntity.{saved}=fromLatestPoint.{source};", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
