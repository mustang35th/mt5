"""Execute production result DDL in SQLite; wiring checks do not execute MQL.

H1EaDatabaseSmokeTest covers the native Context migration and timeout handling.
"""
import json
import re
import sqlite3
import unittest

import test_h1_ea_database_contract as database_contract
from test_h1_ea_database_contract import (
    CONTEXT, DAO, schema_statements,
)


def result_statements():
    source = (DAO / "H1EaResultDao.mqh").read_text(encoding="utf-8-sig")
    for method in ("createSessionSql", "createSampleSql", "createDealSql"):
        body = source.split(f"static string {method}() {{", 1)[1].split("return sql;", 1)[0]
        yield "".join(json.loads(value) for value in re.findall(
            r'sql\s*(?:=|\+=)\s*("(?:[^"\\]|\\.)*")', body))
    for value in re.findall(
            r'H1EaSql::execute\(fromHandle, ("CREATE (?:UNIQUE )?INDEX[^"]+")\)', source):
        yield json.loads(value)


def normalize(sql):
    return sql.replace("IF NOT EXISTS ", "").replace(";", "")


def validate_result_schema(database):
    for statement in result_statements():
        kind, name = re.match(r"CREATE (?:UNIQUE )?(TABLE|INDEX) IF NOT EXISTS (\w+)", statement).groups()
        row = database.execute("SELECT sql FROM sqlite_schema WHERE type=? AND name=?",
                               (kind.lower(), name)).fetchone()
        if row is None or normalize(row[0]) != normalize(statement):
            raise ValueError(name)


class ResultSchemaTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys=ON")
        for statement in result_statements():
            self.db.execute(statement)
        self.insert("sessions", self.session_values())

    def tearDown(self):
        self.db.close()

    def insert(self, table, values, prefix="INSERT"):
        self.db.execute(f"{prefix} INTO h1_ea_{table} ({','.join(values)})"
                        f" VALUES ({','.join('?' for _ in values)})", tuple(values.values()))

    def session_values(self, **changes):
        return dict(session_uid="a" * 64, source_mode="TESTER", account_currency="JPY",
                    account_server="Demo", leverage=100, program_version="1.10",
                    started_server_time=100, trade_start_time=200, initial_balance=100000,
                    sample_interval_seconds=60, recording_state="RECORDING",
                    statistics_available=0, deals_complete=0, recorded_at=1000) | changes

    def sample_values(self, **changes):
        return dict(session_uid="a" * 64, sequence=1, server_time=100, reason="START",
                    balance=100000, equity=99900, margin=50, free_margin=99850,
                    margin_level=199800, open_profit=-100, positions=1, pending_orders=0,
                    foreign_positions=0, foreign_orders=0) | changes

    def deal_values(self, **changes):
        return dict(session_uid="a" * 64, ticket="18446744073709551615", time_msc=100001,
                    position_identifier="18446744073709551614", symbol="EURUSD",
                    magic_number="18446744073709551613", deal_type=1, entry_type=1,
                    volume=0.01, price=1.1, profit=-10, commission=-2, swap=-1, fee=-0.5,
                    reason=3) | changes

    def test_columns_and_composite_primary_keys(self):
        for table, count, primary in (("sessions", 22, ["session_uid"]),
                                      ("account_samples", 14, ["session_uid", "sequence"]),
                                      ("deals", 15, ["session_uid", "ticket"])):
            info = self.db.execute(f"PRAGMA table_info(h1_ea_{table})").fetchall()
            self.assertEqual(len(info), count)
            self.assertEqual([row[1] for row in sorted(info, key=lambda row: row[5]) if row[5]], primary)
        validate_result_schema(self.db)
        self.assertEqual(len(list(result_statements())), 6)

    def test_unsigned_ids_stay_exact_text(self):
        self.insert("deals", self.deal_values())
        self.assertEqual(self.db.execute(
            "SELECT ticket,position_identifier,magic_number,typeof(ticket),typeof(position_identifier),"
            "typeof(magic_number) FROM h1_ea_deals").fetchone(),
            ("18446744073709551615", "18446744073709551614", "18446744073709551613", "text", "text", "text"))

    def test_same_ticket_and_sequence_are_scoped_to_session(self):
        self.insert("sessions", self.session_values(session_uid="b" * 64))
        for uid in ("a" * 64, "b" * 64):
            self.insert("deals", self.deal_values(session_uid=uid))
            self.insert("account_samples", self.sample_values(session_uid=uid))
        for table, values in (("deals", self.deal_values()), ("account_samples", self.sample_values())):
            with self.assertRaises(sqlite3.IntegrityError):
                self.insert(table, values)
            self.assertEqual(self.db.execute(f"SELECT COUNT(*) FROM h1_ea_{table}").fetchone()[0], 2)

    def test_foreign_keys_reject_orphans_and_session_deletion(self):
        for table, values in (("deals", self.deal_values(session_uid="b" * 64)),
                              ("account_samples", self.sample_values(session_uid="b" * 64))):
            with self.assertRaises(sqlite3.IntegrityError):
                self.insert(table, values)
        self.insert("account_samples", self.sample_values())
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM h1_ea_sessions")
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_unavailable_statistics_are_null_not_zero(self):
        self.assertEqual(self.db.execute("SELECT statistics_available,deals_complete,initial_deposit,"
                         "net_profit,equity_drawdown,equity_drawdown_percent,mt5_trades,ended_server_time,"
                         "finished_at,error_text FROM h1_ea_sessions").fetchone(),
                         (0, 0, None, None, None, None, None, None, None, None))

    def test_recorded_requires_stats_deals_and_finish_times(self):
        complete = dict(recording_state="RECORDED", statistics_available=1, deals_complete=1,
                        ended_server_time=300, finished_at=1100)
        for changes in (dict(statistics_available=0), dict(deals_complete=0),
                        dict(ended_server_time=None), dict(finished_at=None)):
            with self.subTest(changes=changes), self.assertRaises(sqlite3.IntegrityError):
                self.insert("sessions", self.session_values(session_uid="b" * 64, **(complete | changes)))
        self.insert("sessions", self.session_values(session_uid="b" * 64, **complete))

    def test_failed_before_finish_and_interrupted_allow_partial_results(self):
        for state, uid in (("FAILED", "b" * 64), ("INTERRUPTED", "c" * 64)):
            self.insert("sessions", self.session_values(session_uid=uid, recording_state=state,
                                                       error_text="locked", deals_complete=0))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_sessions WHERE finished_at IS NULL").fetchone()[0], 3)

    def test_invalid_session_metadata_and_states_rejected(self):
        for changes in (dict(session_uid=None), dict(session_uid="z" * 64), dict(source_mode="OTHER"),
                        dict(recording_state="SUCCESS"), dict(sample_interval_seconds=0),
                        dict(statistics_available=2), dict(deals_complete=-1), dict(leverage=-1),
                        dict(started_server_time=0), dict(trade_start_time=-1), dict(ended_server_time=99),
                        dict(equity_drawdown=-1), dict(equity_drawdown_percent=-0.1), dict(mt5_trades=-1),
                        dict(finished_at=999), dict(account_currency="")):
            values = self.session_values(session_uid="b" * 64) | changes
            with self.subTest(changes=changes), self.assertRaises(sqlite3.IntegrityError):
                self.insert("sessions", values)

    def test_samples_preserve_losses_and_reject_bad_counts(self):
        self.insert("account_samples", self.sample_values(balance=-100, equity=-110,
                                                          free_margin=-120, open_profit=-10))
        for changes in (dict(sequence=0), dict(server_time=0), dict(reason=""), dict(positions=-1),
                        dict(pending_orders=-1), dict(foreign_positions=-1), dict(foreign_orders=-1)):
            with self.subTest(changes=changes), self.assertRaises(sqlite3.IntegrityError):
                self.insert("account_samples", self.sample_values(sequence=2) | changes)

    def test_fee_only_deal_and_zero_ids_are_supported(self):
        self.insert("deals", self.deal_values(volume=0, price=0, position_identifier="0",
                                              magic_number="0", symbol="", profit=-10))
        self.assertEqual(self.db.execute("SELECT volume,price,symbol FROM h1_ea_deals").fetchone(), (0, 0, ""))

    def test_invalid_deal_ids_and_values_rejected(self):
        for changes in (dict(ticket=""), dict(ticket="1e20"), dict(position_identifier="-1"),
                        dict(magic_number="1.2"), dict(time_msc=0), dict(volume=-1),
                        dict(price=-1), dict(deal_type=-1), dict(entry_type=-1), dict(reason=-1)):
            with self.subTest(changes=changes), self.assertRaises(sqlite3.IntegrityError):
                self.insert("deals", self.deal_values(**changes))

    def test_missing_constraint_or_index_fails_exact_schema_validation(self):
        self.db.execute("DELETE FROM h1_ea_sessions")
        self.db.execute("DROP TABLE h1_ea_deals")
        actual = next(sql for sql in result_statements() if "CREATE TABLE IF NOT EXISTS h1_ea_deals " in sql)
        self.db.execute(actual.replace("CHECK(volume>=0 AND price>=0)", "CHECK(volume>=0)"))
        for sql in result_statements():
            if sql.startswith("CREATE INDEX"):
                self.db.execute(sql)
        with self.assertRaisesRegex(ValueError, "h1_ea_deals"):
            validate_result_schema(self.db)
        self.db.execute("DROP TABLE h1_ea_deals")
        self.db.execute(actual)
        with self.assertRaisesRegex(ValueError, "idx_h1_ea_deals_time"):
            validate_result_schema(self.db)

    def test_v3_to_v4_preserves_old_tables_rows_and_allows_active_run(self):
        legacy = sqlite3.connect(":memory:", isolation_level=None)
        try:
            legacy.execute("PRAGMA foreign_keys=ON")
            for sql in schema_statements():
                legacy.execute(sql)
            values = database_contract.DatabaseContractTest.run_values(self)
            legacy.execute(f"INSERT INTO h1_ea_runs ({','.join(values)}) VALUES ({','.join('?' for _ in values)})",
                           tuple(values.values()))
            legacy.execute("PRAGMA user_version=3")
            before = legacy.execute("SELECT * FROM h1_ea_runs").fetchall()
            schema = legacy.execute("SELECT name,sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name").fetchall()
            legacy.execute("BEGIN IMMEDIATE")
            for sql in result_statements():
                legacy.execute(sql)
            validate_result_schema(legacy)
            legacy.execute("PRAGMA user_version=4")
            legacy.execute("COMMIT")
            self.assertEqual(legacy.execute("PRAGMA user_version").fetchone()[0], 4)
            self.assertEqual(legacy.execute("SELECT * FROM h1_ea_runs").fetchall(), before)
            self.assertEqual(legacy.execute("SELECT status,session_uid FROM h1_ea_runs").fetchone(), ("RUNNING", None))
            for name, sql in schema:
                self.assertEqual(legacy.execute("SELECT sql FROM sqlite_schema WHERE name=?", (name,)).fetchone()[0], sql)
            cookie = legacy.execute("PRAGMA schema_version").fetchone()[0]
            validate_result_schema(legacy)
            self.assertEqual(legacy.execute("PRAGMA schema_version").fetchone()[0], cookie)
        finally:
            legacy.close()

    def test_migration_failure_rolls_back_new_tables_and_version(self):
        self.db.execute("DROP TABLE h1_ea_deals")
        self.db.execute("DROP TABLE h1_ea_account_samples")
        self.db.execute("DROP TABLE h1_ea_sessions")
        session_sql = next(result_statements()).replace("CHECK(source_mode IN ('LIVE', 'TESTER')),", "")
        self.db.execute(session_sql)
        self.db.execute("PRAGMA user_version=3")
        before = self.db.execute("SELECT name,sql FROM sqlite_schema ORDER BY name").fetchall()
        self.db.execute("BEGIN IMMEDIATE")
        for sql in result_statements():
            self.db.execute(sql)
        with self.assertRaises(ValueError):
            validate_result_schema(self.db)
        self.db.execute("ROLLBACK")
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 3)
        self.assertEqual(self.db.execute("SELECT name,sql FROM sqlite_schema ORDER BY name").fetchall(), before)

    def test_context_migration_and_timeout_contract(self):
        source = CONTEXT.read_text(encoding="utf-8-sig")
        self.assertIn("const int fromBusyTimeoutMilliseconds = 5000", source)
        self.assertIn('"PRAGMA busy_timeout=" + IntegerToString(fromBusyTimeoutMilliseconds)', source)
        self.assertIn("timeout != fromBusyTimeoutMilliseconds", source)
        self.assertIn("fromBusyTimeoutMilliseconds < 0", source)
        migration = source.split("bool migrateResultTables() {", 1)[1].split("bool prepareSchema", 1)[0]
        self.assertLess(migration.index("this.validateSchema(false, false, true)"), migration.index("H1EaResultDao::createTables"))
        self.assertLess(migration.index("this.validateSchema()"), migration.index("PRAGMA user_version=4"))
        self.assertNotIn("UPDATE ", migration)
        self.assertNotIn("activeRuns", migration)
        self.assertRegex(source, r'version == 3 && fromInitializeSchema\)\s*\{\s*success = this\.migrateResultTables\(\);')
        self.assertRegex(source, r'version == 4\)\s*\{\s*success = this\.validateSchema\(\);')
        for statement in result_statements():
            if statement.startswith("CREATE INDEX"):
                self.assertIn(statement, source)


if __name__ == "__main__":
    unittest.main()
