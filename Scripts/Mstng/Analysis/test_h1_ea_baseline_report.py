"""Deterministic portfolio replay/CSV tests; no terminal, account, or database access."""

import csv
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from h1_ea_baseline_report import aggregateSamples, buildReport, readRows, replayDeals


SCOPE = {("EURUSD", 12), ("GBPUSD", 13)}


def deal(ticket, time, position, entry, volume="1", symbol="EURUSD", magic=12, side=0):
    return dict(ticket=str(ticket), timeMsc=str(time), positionId=str(position), symbol=symbol,
                magic=str(magic), type=str(side), entry=str(entry), volume=volume,
                profit="0", commission="0", swap="0", fee="0")


def sample(time=0, **overrides):
    row = dict(serverTime=str(time), positions="0", pendingOrders="0", foreignPositions="0",
               foreignOrders="0", balance="10000", equity="10000", margin="0", freeMargin="10000",
               marginLevel="0", openProfit="0", slRiskKnown="0", slRiskUnknown="0", readErrors="0", currencySlots="")
    row.update(overrides)
    return row


def writeCsv(path, rows, headers=None):
    with path.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=headers or list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class ReplayTests(unittest.TestCase):
    def test_no_trades_is_zero_for_whole_period(self):
        result = replayDeals([], SCOPE, 0, 10000)
        self.assertEqual(result["histogram"], {0: 10000})
        self.assertEqual(result["mean"], 0)
        self.assertEqual(result["percentiles"], {50: 0, 90: 0, 95: 0, 99: 0})

    def test_overlap_and_duration_weighting(self):
        rows = [deal(1, 1000, 10, 0), deal(2, 2000, 20, 0, symbol="GBPUSD", magic=13),
                deal(3, 5000, 10, 1, side=1), deal(4, 8000, 20, 1, symbol="GBPUSD", magic=13, side=1)]
        result = replayDeals(reversed(rows), SCOPE, 0, 10000)
        self.assertEqual(result["histogram"], {0: 3000, 1: 4000, 2: 3000})
        self.assertEqual(result["mean"], 1)
        self.assertEqual(result["settledPeak"], 2)
        self.assertEqual(result["percentiles"], {50: 1, 90: 2, 95: 2, 99: 2})

    def test_partial_fills_and_partial_close_keep_one_position(self):
        rows = [deal(1, 1000, 10, 0, "0.1"), deal(2, 2000, 10, 0, "0.2"),
                deal(3, 3000, 10, 1, "0.1", side=1), deal(4, 5000, 10, 1, "0.2", side=1)]
        result = replayDeals(rows, SCOPE, 0, 6000)
        self.assertEqual(result["histogram"], {0: 2000, 1: 4000})
        self.assertEqual(result["openAtEnd"], 0)

    def test_exit_can_have_different_magic_and_close_by(self):
        rows = [deal(1, 1000, 10, 0), deal(2, 2000, 10, 3, magic=0, side=1)]
        result = replayDeals(rows, SCOPE, 0, 3000)
        self.assertEqual(result["foreignDeals"], 0)
        self.assertEqual(result["histogram"], {0: 2000, 1: 1000})

    def test_same_millisecond_peak_is_separate(self):
        rows = [deal(1, 1000, 10, 0), deal(2, 2000, 20, 0, symbol="GBPUSD", magic=13),
                deal(3, 2000, 10, 1, side=1)]
        result = replayDeals(rows, SCOPE, 0, 3000)
        self.assertEqual((result["settledPeak"], result["orderedPeak"]), (1, 2))
        self.assertEqual(result["histogram"], {0: 1000, 1: 2000})

    def test_short_lived_trade_and_last_millisecond_preserved(self):
        rows = [deal(1, 2050, 10, 0), deal(2, 2051, 10, 1, side=1)]
        result = replayDeals(rows, SCOPE, 0, 2000)
        self.assertEqual(result["histogram"][1], 1)
        self.assertEqual(result["durationMsc"], 2051)

    def test_foreign_symbol_or_magic_is_not_our_position(self):
        rows = [deal(1, 1000, 10, 0, magic=99), deal(2, 2000, 10, 1, magic=99, side=1)]
        result = replayDeals(rows, SCOPE, 0, 3000)
        self.assertEqual(result["foreignDeals"], 2)
        self.assertEqual(result["settledPeak"], 0)

    def test_deal_profit_includes_costs_and_open_at_end(self):
        opening = deal(1, 1000, 10, 0)
        opening.update(profit="2", commission="-0.3", swap="-0.1", fee="-0.1")
        result = replayDeals([opening], SCOPE, 0, 3000)
        self.assertEqual(result["netDealProfit"], Decimal("1.5"))
        self.assertEqual(result["openAtEnd"], 1)

    def test_rejects_incomplete_and_invalid_history(self):
        cases = [
            [deal(1, 1000, 10, 1, side=1)],
            [deal(1, 1000, 10, 0), deal(1, 2000, 10, 1, side=1)],
            [deal(1, 1000, 10, 0), deal(2, 2000, 10, 1, "2", side=1)],
            [deal(1, 1000, 10, 0), deal(2, 2000, 10, 1, side=0)],
            [deal(1, 1000, 10, 0), deal(2, 2000, 10, 2, side=1)],
            [deal(1, 1000, 10, 0, "NaN")],
            [deal(1, 1000, 10, 0, "0")],
            [deal(1, 1000, 10, 0), deal(2, 2000, 20, 0)],
            [deal(1, 4500, 10, 0)],
        ]
        for rows in cases:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                replayDeals(rows, SCOPE, 0, 3000)

    def test_rejects_managed_trade_during_warmup(self):
        with self.assertRaisesRegex(ValueError, "before trade start"):
            replayDeals([deal(1, 500, 10, 0)], SCOPE, 1000, 3000)


class SampleTests(unittest.TestCase):
    def test_unknown_risk_and_account_scope_are_retained(self):
        rows = [sample(1, positions="1", pendingOrders="2", margin="100", slRiskKnown="10",
                       slRiskUnknown="1", currencySlots="EUR:1:0|USD:0:1"),
                sample(2, positions="2", margin="150", slRiskKnown="20", foreignPositions="1",
                       currencySlots="EUR:1:1|USD:1:1")]
        result = aggregateSamples(rows, 0, 3)
        self.assertEqual(result["margin"], Decimal(150))
        self.assertEqual(result["slRiskKnown"], Decimal(20))
        self.assertEqual(result["unknownRiskRows"], 1)
        self.assertEqual(result["currencySlots"]["USD"], {"long": 1, "short": 1, "gross": 2})
        self.assertEqual(result["pendingOrders"], 2)
        self.assertEqual(result["foreignPositions"], 1)

    def test_invalid_samples_not_silently_zeroed(self):
        for rows in ([], [sample(0, equity="NaN")], [sample(2), sample(1)], [sample(5)], [sample(0, positions="-1")]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                aggregateSamples(rows, 0, 3)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.summary = dict(schema="H1_EA_BASELINE_V1", finalization="ONTESTER", ioFailed="0",
                            globalPositionLimit="0", testStart="0", tradeStart="1", testEnd="10",
                            sampleRows="2", dealRows="0", readErrors="0", accountCurrency="JPY",
                            leverage="100", initialDeposit="1000000", netProfit="0", equityDrawdown="0",
                            equityDrawdownPercent="0", trades="0")
        self.writeSummary()
        writeCsv(self.folder / "status.csv", [{"key": "exportState", "value": "EXPORTED"}])
        writeCsv(self.folder / "runs.csv", [dict(symbol=f"PAIR{i}", magic=str(i+1), sessionUid="a"*64,
                                                programVersion="1.06", configText="V1|GLOBAL_POSITION_LIMIT=0|X=1")
                                            for i in range(28)])
        writeCsv(self.folder / "samples.csv", [sample(1), sample(10)])
        writeCsv(self.folder / "deals.csv", [], list(deal(1, 0, 1, 0)))

    def tearDown(self):
        self.temp.cleanup()

    def writeSummary(self):
        writeCsv(self.folder / "summary.csv", [dict(key=key, value=value) for key, value in self.summary.items()])

    def test_complete_empty_test_builds_readable_report(self):
        report = buildReport(self.folder)
        self.assertIn("全体上限なし", report)
        self.assertIn("100.000%", report)
        self.assertIn("1,000,000.00", report)
        self.assertNotIn("要確認", report)

    def test_truncated_files_and_failed_export_rejected(self):
        for key, value in (("sampleRows", "3"), ("dealRows", "1"), ("ioFailed", "1"),
                           ("globalPositionLimit", "3"), ("tradeStart", "11")):
            original = self.summary[key]
            self.summary[key] = value
            self.writeSummary()
            with self.subTest(key=key), self.assertRaises(ValueError):
                buildReport(self.folder)
            self.summary[key] = original
        self.writeSummary()

    def test_missing_completion_marker_rejected(self):
        (self.folder / "status.csv").unlink()
        with self.assertRaises(OSError):
            buildReport(self.folder)

    def test_position_samples_cannot_be_combined_with_missing_deals(self):
        writeCsv(self.folder / "samples.csv", [sample(1, positions="1"), sample(10)])
        with self.assertRaisesRegex(ValueError, "missing opening history"):
            buildReport(self.folder)

    def test_quote_comma_newline_roundtrip_and_bad_column_count(self):
        path = self.folder / "quoted.csv"
        text = '日本語,"quoted"\nnext'
        writeCsv(path, [{"key": "a", "value": text}])
        self.assertEqual(list(readRows(path))[0]["value"], text)
        path.write_text("key,value\na,b,c\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "field count"):
            list(readRows(path))


if __name__ == "__main__":
    unittest.main()
