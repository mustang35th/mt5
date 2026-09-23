"""Check read-only baseline wiring and CSV schema boundaries, without running MT5."""

from pathlib import Path
import re
import unittest
from test_h1_ea_tester_warmup_contract import code_only, method

ROOT = Path(__file__).resolve().parents[3]


class BaselineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = (ROOT / "Include/MstngH1Ea/Analysis/H1EaBaselineReport.mqh").read_text(encoding="utf-8-sig")
        cls.expert = (ROOT / "Experts/MstngH1EaAll.mq5").read_text(encoding="utf-8-sig")

    def test_tester_only_before_reading_run_or_creating_files(self):
        init = code_only(method(self.expert, "initializeBaselineReport"))
        self.assertLess(init.index("!MQLInfoInteger(MQL_TESTER)"), init.index("getRestorationState"))
        self.assertIn("!InpExportBaselineReport", init)
        report = code_only(method(self.report, "initialize"))
        self.assertLess(report.index("!MQLInfoInteger(MQL_TESTER)"), report.index("FolderCreate"))
        self.assertIn('sourceMode != "TESTER"', method(self.report, "initialize"))
        self.assertIn("ArraySize(fromRuns) != 28", report)

    def test_after_trading_and_not_in_transaction_callback(self):
        for name, controllerCall in (("OnTimer", "controller.onTimer()"), ("OnTick", "controller.onTick()")):
            body = method(self.expert, name)
            self.assertLess(body.index(controllerCall), body.index("baselineReport.sample()"))
        self.assertNotIn("baselineReport", method(self.expert, "OnTradeTransaction"))
        self.assertRegex(self.expert, r"double OnTester\(\)\s*\{\s*baselineReport.finish\(\);\s*return 0.0;")
        self.assertIn("baselineReport.close()", method(self.expert, "OnDeinit"))

    def test_sampling_guard_precedes_portfolio_reads(self):
        body = method(self.report, "sample")
        self.assertLess(body.index("now < this.tradeStart"), body.index("PositionsTotal()"))
        self.assertIn("now <= this.lastSampleTime", body)
        self.assertIn("now >= this.lastWriteTime + 60", body)
        self.assertIn("now >= this.lastFlushTime + 60", body)
        self.assertIn("this.owns(symbol, (ulong)PositionGetInteger(POSITION_MAGIC))", body)
        self.assertIn("unknownRisk++", body)
        self.assertIn("risk += MathMax(0.0, -loss)", body)

    def test_history_is_exported_unfiltered_and_completion_follows_flush(self):
        body = method(self.report, "exportDeals")
        self.assertIn("HistorySelect(0, TimeCurrent())", body)
        self.assertNotIn("this.owns", body)
        for field in ("DEAL_TIME_MSC", "DEAL_POSITION_ID", "DEAL_ENTRY", "DEAL_VOLUME", "DEAL_FEE"):
            self.assertIn(field, body)
        finish = method(self.report, "finish")
        self.assertLess(finish.index("this.finishFile(summaryHandle)"), finish.index('this.openFile("status.csv")'))
        self.assertIn('"dealRows", IntegerToString(this.dealRows)', finish)

    def test_no_trading_database_or_canonical_changes(self):
        body = code_only(self.report)
        for forbidden in ("OrderSend(", "OrderSendAsync(", "PositionClose(", "DatabaseOpen(", "EventSetTimer(", "CopyBuffer("):
            self.assertNotIn(forbidden, body)
        config = (ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh").read_text(encoding="utf-8-sig")
        self.assertNotIn("Baseline", method(config, "createCanonicalText"))

    def test_schema_column_counts_and_utf8(self):
        counts = {"symbol,magic,": 10, "serverTime,positions,": 15, "ticket,timeMsc,": 12, "key,value": 2}
        for prefix, expected in counts.items():
            headers = re.findall(r'writeLine\([^,]+, "(' + re.escape(prefix) + r'[^"\n]*)"\)', self.report)
            self.assertTrue(headers)
            for header in headers:
                self.assertEqual(len(header.split(",")), expected)
        self.assertIn("CP_UTF8", self.report)


if __name__ == "__main__":
    unittest.main()
