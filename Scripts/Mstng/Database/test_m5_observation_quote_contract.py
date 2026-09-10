"""Source contracts for explicit adopted-quote analysis, not MQL execution.

Legacy method fingerprints were captured before the adopted-tick overload was
added. The shared daily-range helper is expanded for the TodayRate comparison.
"""
import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INCLUDE = ROOT / "Include" / "Mstng"


def read(relative):
    return (INCLUDE / relative).read_text(encoding="utf-8-sig")


def method_body(source, signature):
    """Extract these brace-balanced production methods without evaluating MQL."""
    position = source.index("{", source.index(signature)) + 1
    start = position
    depth = 1
    while depth:
        if source[position] == "{":
            depth += 1
        elif source[position] == "}":
            depth -= 1
        position += 1
    return source[start:position - 1]


def fingerprint(body):
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


class AdoptedQuoteContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.elliot = read("Elliot/ElliotAll.mqh")
        cls.rate = read("Util/TodayRate.mqh")
        cls.adopted_analysis = method_body(
            cls.elliot, "bool analyze(const MqlTick &fromQuoteTick)"
        )
        cls.adopted_rate = method_body(cls.rate, "bool update(")
        cls.range_helper = method_body(
            cls.rate, "void updateDailyRangeAndLabels(const int fromDigits)"
        )

    def test_legacy_analyze_method_is_byte_unchanged(self):
        self.assertEqual(fingerprint(method_body(self.elliot, "void analyze()")),
                         "6439dd4b770aa3d8cb42c0a3498f3825981e4c3a1aa09bcb76f134c0d260b726")

    def test_legacy_today_rate_update_still_uses_original_path(self):
        body = method_body(self.rate, "void update(MarketContext &fromMarketContext)")
        self.assertEqual(body.strip(),
                         "this.initializeMarketContext(fromMarketContext);\n"
                         "        this.updateValues();")

    def test_legacy_rate_body_unchanged_after_helper_expansion(self):
        body = method_body(self.rate, "void updateValues()")
        expanded = body.replace("this.updateDailyRangeAndLabels(digits);",
                                self.range_helper.replace("fromDigits", "digits").strip())
        self.assertEqual(fingerprint(expanded),
                         "3d393153600ef66ea78fcafbc9c10b3781139edcaf65bab1f2c91d77854ee822")

    def test_explicit_quote_never_falls_back_to_market_quote(self):
        for forbidden in ("SymbolInfoDouble", "SymbolInfoTick", "updateValues()",
                          "TimeCurrent()", "TimeLocal()", "time_msc"):
            self.assertNotIn(forbidden, self.adopted_rate)
        self.assertIn("this.bid = fromQuoteTick.bid;", self.adopted_rate)
        self.assertIn("this.ask = fromQuoteTick.ask;", self.adopted_rate)
        self.assertIn("this.spread = spreadPips;", self.adopted_rate)

    def test_bad_quotes_and_invalid_pip_size_are_rejected(self):
        body = self.adopted_rate
        for required in ("!MathIsValidNumber(fromQuoteTick.bid)",
                         "!MathIsValidNumber(fromQuoteTick.ask)",
                         "fromQuoteTick.bid == EMPTY_VALUE",
                         "fromQuoteTick.ask == EMPTY_VALUE",
                         "fromQuoteTick.bid <= 0.0", "fromQuoteTick.ask <= 0.0",
                         "fromQuoteTick.ask < fromQuoteTick.bid",
                         "!MathIsValidNumber(pipSize)", "pipSize <= 0.0",
                         "!MathIsValidNumber(spreadPips)", "spreadPips < 0.0"):
            self.assertIn(required, body)
        self.assertLess(body.index("this.initializeValues();"), body.index("if ("))
        self.assertNotIn("MathAbs", body)
        self.assertNotRegex(body, r"spreadPips\s*>\s*\d")
        self.assertIn("(fromQuoteTick.ask - fromQuoteTick.bid) / pipSize", body)

    def test_daily_range_helper_does_not_replace_adopted_prices(self):
        self.assertNotRegex(self.range_helper, r"this\.(?:bid|ask|spread)\s*=")
        self.assertNotIn("SymbolInfoTick", self.range_helper)
        self.assertIn("this.canReadDailyRange()", self.range_helper)
        self.assertIn("this.clearDailyRange()", self.range_helper)

    def test_explicit_analysis_preserves_call_order_and_actual_result(self):
        body = self.adopted_analysis
        sequence = ("this.isAnalysisSucceeded = false;",
                    "this.todayRate.update(this.marketContext, fromQuoteTick)",
                    "this.setTimeFrame(this.marketContext.timeFrame);",
                    "this.setElliotAll();", "this.setTrendAlignDecision();",
                    "this.setHigherStochasticMainOrderDecision();",
                    "this.lossCut.setData(this.elliotCurrent, this.todayRate);")
        offsets = [body.index(step) for step in sequence]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("return this.isAnalysisSucceeded;", body)
        self.assertIn("LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);", body)
        self.assertNotIn("this.todayRate.update(this.marketContext);", body)
        self.assertNotIn("SymbolInfoTick", body)
        self.assertLess(body.index("return false;"), body.index("this.setElliotAll();"))

    def test_modified_headers_remain_utf8_with_bom(self):
        for relative in ("Elliot/ElliotAll.mqh", "Util/TodayRate.mqh"):
            raw = (INCLUDE / relative).read_bytes()
            self.assertTrue(raw.startswith(b"\xef\xbb\xbf"), relative)
            self.assertNotIn("\ufffd", raw.decode("utf-8-sig"), relative)


if __name__ == "__main__":
    unittest.main()
