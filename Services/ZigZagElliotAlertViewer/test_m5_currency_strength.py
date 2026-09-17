"""Exact-time currency references using temporary writer-schema databases."""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

from m5_currency_strength import M5CurrencyStrengthReader, CURRENCIES
from m5_observations import M5ObservationDatabase
from test_m5_observations import PROJECT_ROOT, BASE_TIME, create_fixture, add_run, add_observation, insert_row


class CurrencyStrengthTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.path = self.directory / "mstng-currency-strength-2026.sqlite"
        self.connection = sqlite3.connect(self.path)
        self.addCleanup(self.connection.close)
        for name in ("CurrencyStrengthRunDao.mqh", "CurrencyStrengthResultDao.mqh"):
            source = (PROJECT_ROOT / "Include/Mstng/Database/Dao" / name).read_text(encoding="utf-8-sig")
            start = source.index('string sql = "CREATE TABLE')
            end = source.index('sql += ")";', start) + len('sql += ")";')
            fragments = re.findall(r'(?:string sql =|sql \+=) "(.*)";', source[start:end])
            self.connection.execute("".join(fragments))
        self.target = BASE_TIME - 6 * 3600
        self.observation = {"anchor_bar_time": self.target, "source_mode": "TESTER",
                            "source_server": "Fixture-Server", "symbol_name": "GBPUSD"}
        insert_row(self.connection, "currency_strength_runs", {
            "id": 42, "m5_bar_time": self.target, "source_mode": "TESTER",
            "source_server": "Fixture-Server", "source_login": 123456789,
            "calculation_version": "pair-direction-closed-v1", "is_complete": 1,
            "valid_pair_count": 28, "expected_pair_count": 28, "vote_count": 196,
        })
        for index, currency in enumerate(CURRENCIES):
            insert_row(self.connection, "currency_strength_results", {
                "run_id": 42, "currency_name": currency,
                "long_medium_term_average_rank": index + 1,
                "medium_short_term_average_rank": 8 - index,
            })
        self.connection.commit()
        self.reader = M5CurrencyStrengthReader(self.directory, calculation_mode="UNIFORM")

    def read(self):
        return self.reader.read(self.observation, 123456789)

    def test_exact_periods_and_read_only(self):
        before = hashlib.sha256(self.path.read_bytes()).hexdigest()
        result = self.read()
        self.assertEqual("FOUND", result["status"])
        self.assertEqual(42, result["runId"])
        self.assertEqual(["SELL", "BUY"], [row["direction"] for row in result["periods"]])
        self.assertEqual([-3, 3], [row["rankDifference"] for row in result["periods"]])
        self.assertEqual(before, hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertNotIn("123456789", json.dumps(result))

    def test_each_identity_field_must_match_and_never_uses_previous_bar(self):
        changes = {"m5_bar_time": self.target - 300, "source_mode": "LIVE",
                   "source_server": "Other", "source_login": 2,
                   "calculation_version": "pair-direction-weighted-closed-v1", "is_complete": 0}
        for field, value in changes.items():
            with self.subTest(field=field):
                original = self.connection.execute(f"SELECT {field} FROM currency_strength_runs").fetchone()[0]
                self.connection.execute(f"UPDATE currency_strength_runs SET {field}=?", (value,))
                self.connection.commit()
                self.assertEqual("RECORD_NOT_FOUND", self.read()["status"])
                self.connection.execute(f"UPDATE currency_strength_runs SET {field}=?", (original,))
                self.connection.commit()
        self.observation["anchor_bar_time"] = BASE_TIME
        self.assertEqual("RECORD_NOT_FOUND", self.read()["status"])

    def test_weighted_is_explicit(self):
        weighted = M5CurrencyStrengthReader(self.directory, calculation_mode="WEIGHTED")
        self.assertEqual("RECORD_NOT_FOUND", weighted.read(self.observation, 123456789)["status"])
        self.connection.execute("UPDATE currency_strength_runs SET calculation_version='pair-direction-weighted-closed-v1'")
        self.connection.commit()
        self.assertEqual("FOUND", weighted.read(self.observation, 123456789)["status"])

    def test_prefix_suffix_and_ambiguous_symbol(self):
        self.observation["symbol_name"] = "m.GBPUSD.pro"
        self.assertEqual("FOUND", self.read()["status"])
        for symbol in ("XAUUSD", "GBPUSDJPY", ""):
            self.observation["symbol_name"] = symbol
            self.assertEqual("UNSUPPORTED_SYMBOL", self.read()["status"])

    def test_missing_db_not_created_and_year_follows_server_anchor(self):
        self.observation["anchor_bar_time"] = 1798761600  # 2027-01-01 server clock
        result = self.read()
        self.assertEqual("mstng-currency-strength-2027.sqlite", result["databaseName"])
        self.assertEqual("DATABASE_NOT_FOUND", result["status"])
        self.assertFalse((self.directory / result["databaseName"]).exists())

    def test_explicit_file_overrides_year_path(self):
        explicit = self.directory / "chosen.sqlite"
        explicit.write_bytes(self.path.read_bytes())
        result = M5CurrencyStrengthReader(None, explicit, "UNIFORM").read(self.observation, 123456789)
        self.assertEqual("FOUND", result["status"])
        self.assertEqual("chosen.sqlite", result["databaseName"])

    def test_no_account_no_fallback(self):
        self.assertEqual("IDENTITY_UNAVAILABLE", self.reader.read(self.observation, None)["status"])

    def test_partial_ranks_and_inconsistent_complete_run(self):
        self.connection.execute("UPDATE currency_strength_results SET long_medium_term_average_rank=0 WHERE currency_name='USD'")
        self.connection.commit()
        self.assertEqual("INVALID_DATA", self.read()["status"])
        self.connection.execute("UPDATE currency_strength_results SET long_medium_term_average_rank=1 WHERE currency_name='USD'")
        self.connection.execute("UPDATE currency_strength_runs SET vote_count=195")
        self.connection.commit()
        self.assertEqual("INVALID_DATA", self.read()["status"])
        self.connection.execute("UPDATE currency_strength_runs SET vote_count=196")
        self.connection.execute("DELETE FROM currency_strength_results WHERE currency_name='CAD'")
        self.connection.commit()
        self.assertEqual("INVALID_DATA", self.read()["status"])

    def test_ties_are_neutral(self):
        self.connection.execute("UPDATE currency_strength_results SET long_medium_term_average_rank=1, medium_short_term_average_rank=1")
        self.connection.commit()
        self.assertEqual(["TIE", "TIE"], [row["direction"] for row in self.read()["periods"]])

    def test_duplicate_matching_runs_are_not_selected_arbitrarily(self):
        insert_row(self.connection, "currency_strength_runs", {
            "id": 43, "m5_bar_time": self.target, "source_mode": "TESTER", "source_server": "Fixture-Server",
            "source_login": 123456789, "calculation_version": "pair-direction-closed-v1", "is_complete": 1,
        })
        self.connection.commit()
        self.assertEqual("AMBIGUOUS", self.read()["status"])

    def test_broken_secondary_database_does_not_hide_observation(self):
        observation_path = self.directory / "m5.sqlite"
        connection = create_fixture(observation_path)
        try:
            add_run(connection)
            identifier = add_observation(connection)
            connection.commit()
        finally:
            connection.close()
        repository = M5ObservationDatabase(observation_path, currency_strength_calculation="UNIFORM")
        self.addCleanup(repository.close)
        result = repository.detail(identifier)
        self.assertEqual("FOUND", result["currencyStrength"]["status"])
        self.assertNotIn("123456789", json.dumps(result))
        before = observation_path.read_bytes()
        self.connection.execute("DROP TABLE currency_strength_results")
        self.connection.commit()
        result = repository.detail(identifier)
        self.assertEqual(identifier, result["observation"]["id"])
        self.assertEqual("ERROR", result["currencyStrength"]["status"])
        self.assertEqual(before, observation_path.read_bytes())


if __name__ == "__main__":
    unittest.main()
