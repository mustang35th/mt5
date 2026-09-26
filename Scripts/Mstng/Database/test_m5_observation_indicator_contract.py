"""M5 indicator input and status-display contracts (not a visual/runtime test)."""
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def body(source, signature):
    start = source.index("{", source.index(signature)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    return source[start:position - 1]


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
        for value in ("detailRowHeight = 18", '"H1ObsAll_"', '"M5ObsAll_"'):
            self.assertIn(value, self.draw)
        constructor = body(self.draw, "DrawH1ElliotObservationAllStatus(")
        row_height = int(re.search(r"this.summaryRowHeight = (\d+)", constructor).group(1))
        for name, previous in (("summaryPanelHeight", 139), ("detailPanelHeight", 275),
                               ("separatorYDistance", 128), ("detailFirstYDistance", 139)):
            value = int(re.search(rf"this\.{name} = (\d+)", constructor).group(1))
            self.assertEqual(value, previous + row_height)
        m5_height = re.findall(r"this.detailPanelHeight = (\d+)", constructor)[1]
        self.assertEqual(int(m5_height), 415 + row_height)
        self.assertRegex(self.draw, r"if \(this.captureQualityVisible\)\s*\{\s*this.detailRowHeight = 36;")

    def test_history_summary_is_separate_from_analysis_and_fits_its_own_row(self):
        summary = body(self.draw, "string buildSummaryText(")
        history = body(summary, "if (fromRowIndex == 4)")
        self.assertIn('historyText = "履歴準備"', history)
        self.assertIn('historyText = "履歴準備完了"', history)
        self.assertIn("fromStatus.targetCount > 0", history)
        self.assertIn("fromStatus.historyReadyCount == fromStatus.targetCount", history)
        self.assertIn("fromStatus.historyReadyCount, fromStatus.targetCount", history)
        self.assertNotIn("fromStatus.readyCount", history)
        self.assertIn("観測準備 %d/%d", body(summary, "if (fromRowIndex == 0)"))
        for signature in ("bool draw(", "bool create()", "void resetCache()"):
            self.assertIn("for (int i = 0; i < 6; i++)", body(self.draw, signature))
        self.assertIn("lastSummaryTexts[6]", self.draw)
        self.assertIn("lastSummaryColors[6]", self.draw)

    def test_history_tooltip_reads_cached_state_and_keeps_existing_message(self):
        tooltip = body(self.draw, "string buildDetailTooltip(")
        self.assertIn("fromStatus.symbolHistoryReady[fromIndex]", tooltip)
        self.assertIn('historyText = "WAIT"', tooltip)
        self.assertIn('historyText = "OK"', tooltip)
        self.assertIn("fromStatus.symbolMessages[fromIndex]", tooltip)
        for forbidden in ("prepare(", "Bars(", "CopyRates(", "SeriesInfoInteger("):
            self.assertNotIn(forbidden, tooltip)
        self.assertIn('this.lastDetailTooltips[i] = ""', body(self.draw, "void resetCache()"))

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
