"""M5 indicator input and status-display contracts (not a visual/runtime test)."""
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class ObservationIndicatorContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.indicator = (ROOT / "Indicators/ZigZagElliotM5ObservationAll.mq5").read_text(encoding="utf-8-sig")
        cls.draw = (ROOT / "Include/Mstng/Draw/DrawH1ElliotObservationAllStatus.mqh").read_text(encoding="utf-8-sig")

    def test_dedicated_database_and_collection_defaults(self):
        expected = {
            "observationDatabaseFileName": '"mstng-zigzag-elliot-m5-observation.sqlite"',
            "observationDatabaseUseCommonFolder": "true",
            "observationTimerSeconds": "2",
            "observationDatabaseRetrySeconds": "15",
            "observationQueueCapacity": "672",
            "observationTesterSaveStartTime": "0",
        }
        for name, value in expected.items():
            with self.subTest(name=name):
                self.assertRegex(self.indicator, rf"input\s+\w+\s+{name}\s*=\s*{re.escape(value)};")
        self.assertEqual(self.indicator.count("input group"), 4)

    def test_rejects_optimization_and_upper_tester_before_controller(self):
        creation = self.indicator.index("gObservationController = new")
        self.assertLess(self.indicator.index("MQLInfoInteger(MQL_OPTIMIZATION)"), creation)
        self.assertLess(self.indicator.index("PeriodSeconds(_Period) > PeriodSeconds(PERIOD_M5)"), creation)
        self.assertLess(self.indicator.index("return INIT_PARAMETERS_INCORRECT"), creation)

    def test_entry_forwards_both_events_and_releases_owned_objects(self):
        self.assertIn("gObservationController.onCalculate(fromRatesTotal)", self.indicator)
        self.assertIn("gObservationController.onTimer()", self.indicator)
        self.assertRegex(self.indicator, r"statusPanelDetailVisible,\s*true\s*\)")
        cleanup = self.indicator.split("void OnDeinit(", 1)[1].split("int OnCalculate(", 1)[0]
        self.assertIn("delete gObservationStatusView", cleanup)
        self.assertIn("delete gObservationController", cleanup)

    def test_h1_default_layout_and_object_prefix_remain_separate(self):
        self.assertIn("bool fromCaptureQualityVisible = false", self.draw)
        for value in ("detailPanelHeight = 275", "detailRowHeight = 18", '"H1ObsAll_"', '"M5ObsAll_"'):
            self.assertIn(value, self.draw)
        self.assertRegex(self.draw, r"if \(this.captureQualityVisible\)\s*\{\s*this.detailRowHeight = 36;\s*this.detailPanelHeight = 415;")

    def test_quality_has_its_own_line_and_no_measurement_fallback(self):
        self.assertIn("this.detailRowHeight = 36", self.draw)
        self.assertIn("this.detailFirstYDistance + (rowIndex * this.detailRowHeight) + 17", self.draw)
        self.assertIn("metrics.hasAnalysisElapsedMs, metrics.analysisElapsedMs", self.draw)
        self.assertIn("metrics.hasCaptureElapsedMs, metrics.captureElapsedMs", self.draw)
        self.assertIn("metrics.hasAnalysisAttemptCount, metrics.analysisAttemptCount", self.draw)
        optional = self.draw.split("string formatOptionalLong(", 1)[1].split("string formatElapsed(", 1)[0]
        self.assertIn('if (!fromAvailable)', optional)
        self.assertIn('return "-";', optional)
        self.assertIn("return IntegerToString(fromValue)", optional)
        self.assertNotIn("fromValue == 0", optional)

    def test_quality_labels_identify_capture_bar_and_not_database_save(self):
        self.assertIn("symbolCaptureMetricsBarTimes[fromIndex]", self.draw)
        self.assertIn("Latest captured M5 (server):", self.draw)
        self.assertIn("Adopted quote time ms (server):", self.draw)
        self.assertIn("Captured values; DB Save status is shown separately.", self.draw)
        self.assertIn("OBJPROP_TOOLTIP, tooltip", self.draw)

    def test_indicator_does_not_trade_or_send_alerts(self):
        for forbidden in ("OrderSend(", "SendMail(", "SendNotification(", "Alert(", "ExpertAdvisorFactory"):
            self.assertNotIn(forbidden, self.indicator)


if __name__ == "__main__":
    unittest.main()
