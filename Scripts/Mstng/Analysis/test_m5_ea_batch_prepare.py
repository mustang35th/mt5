"""Exercise missing/mismatched source data without accessing production databases."""

import configparser
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

import m5_ea_batch_prepare as prepare


class BatchPrepareTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "strength.sqlite"
        self.symbols = prepare.readSymbols()
        with closing(sqlite3.connect(self.path)) as database, database:
            database.executescript("""
                CREATE TABLE currency_strength_runs (
                    id INTEGER, m5_bar_time INTEGER, calculation_version TEXT, source_mode TEXT,
                    source_server TEXT, source_login INTEGER, is_complete INTEGER,
                    valid_pair_count INTEGER, expected_pair_count INTEGER, vote_count INTEGER);
                CREATE TABLE currency_strength_results (
                    run_id INTEGER, currency_name TEXT, long_medium_term_average_rank INTEGER,
                    medium_short_term_average_rank INTEGER);
                CREATE TABLE currency_strength_pair_votes (
                    run_id INTEGER, canonical_symbol_name TEXT, resolved_symbol_name TEXT, time_frame INTEGER);
            """)
            for runId, barTime in enumerate((prepare.START, prepare.START + 300), 1):
                database.execute("INSERT INTO currency_strength_runs VALUES (?,?,?,?,?,?,?,?,?,?)",
                                 (runId, barTime, prepare.VERSION, "LIVE", "fixture", 42, 1, 28, 28, 196))
                database.executemany("INSERT INTO currency_strength_results VALUES (?,?,?,?)",
                                     [(runId, currency, rank, rank) for rank, currency
                                      in enumerate(sorted(prepare.CURRENCIES), 1)])
                database.executemany("INSERT INTO currency_strength_pair_votes VALUES (?,?,?,?)",
                                     [(runId, symbol, symbol, frame) for symbol in self.symbols
                                      for frame in prepare.TIMEFRAMES])

    def inspect(self, fromIdentity=("fixture", 42)):
        with patch.object(prepare, "END", prepare.START + 600):
            return prepare.inspectStrength(self.path, fromIdentity, self.symbols)

    def mutate(self, fromSql):
        with closing(sqlite3.connect(self.path)) as database, database:
            database.execute(fromSql)

    def testCompleteWeekWithoutPreviousWeekendSlot(self):
        result = self.inspect()
        self.assertTrue(result["passed"])
        self.assertEqual(result["completeSlots"], 2)
        self.assertFalse(result["previousSlotAvailable"])
        self.assertEqual(result["voteRows"], 392)

    def testWrongAccountCannotUseAnotherAccountsRanks(self):
        result = self.inspect(("fixture", 43))
        self.assertFalse(result["passed"])
        self.assertEqual(len(result["missingOrInvalidSlots"]), 2)

    def testInvalidRankFailsEvenWithCompleteRunFlag(self):
        self.mutate("UPDATE currency_strength_results SET long_medium_term_average_rank=0 WHERE run_id=1 AND currency_name='USD'")
        result = self.inspect()
        self.assertFalse(result["passed"])
        self.assertEqual(result["missingOrInvalidSlots"], [prepare.START])

    def testMissingVoteFailsEvenWithReportedCount196(self):
        self.mutate("DELETE FROM currency_strength_pair_votes WHERE run_id=1 AND canonical_symbol_name='USDJPY' AND time_frame=5")
        self.assertFalse(self.inspect()["passed"])

    def testMissingSlotIsNotReplacedByPreviousSlot(self):
        self.mutate("DELETE FROM currency_strength_runs WHERE id=2")
        self.assertEqual(self.inspect()["missingOrInvalidSlots"], [prepare.START + 300])

    def testImmutableRejectsSidecars(self):
        Path(str(self.path) + "-wal").touch()
        with self.assertRaisesRegex(ValueError, "WAL/SHM"):
            prepare.openReadOnly(self.path, True)

    def testPresetsKeepEveryInputAndTesterSettingExceptSymbolReport(self):
        template = (prepare.ROOT / "Scripts/Mstng/ExpertAdvisor/BacktestPresets/MstngM5Ea.USDJPY.20260907_20260911.WarmupDeferred.ini").read_text(encoding="utf-8-sig")
        baseline = configparser.ConfigParser(interpolation=None)
        baseline.optionxform = str
        baseline.read_string(template)
        reports = set()
        for symbol in self.symbols:
            actual = configparser.ConfigParser(interpolation=None)
            actual.optionxform = str
            actual.read_string(prepare.createPreset(template, symbol, "Fixture28"))
            self.assertEqual(dict(actual["TesterInputs"]), dict(baseline["TesterInputs"]))
            self.assertEqual(actual["Tester"]["Symbol"], symbol)
            reports.add(actual["Tester"]["Report"])
            for key, value in baseline["Tester"].items():
                if key not in ("Symbol", "Report"):
                    self.assertEqual(actual["Tester"][key], value)
        self.assertEqual(len(reports), 28)


if __name__ == "__main__":
    unittest.main()
