"""Check production MQL DDL/guard SELECTs using isolated in-memory SQLite.

Schema/SQL tests execute actual extracted SQL. MQL API wiring and the normalization
algorithm are source contracts, not native MQL runtime execution.
"""
import hashlib
import json
import re
import sqlite3
import unittest
from contextlib import closing
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DAO = ROOT / "Include/Mstng/Database/Dao"
GUARD = ROOT / "Include/Mstng/Database/Service/ZigZagElliotObservationDatabaseGuard.mqh"
ENTITY = ROOT / "Include/Mstng/Database/Entity/ZigZagElliotObservationCaptureMetricsEntity.mqh"
RUNS = "zigzag_elliot_alert_runs"
OBS = "zigzag_elliot_observations"
METRICS = "zigzag_elliot_observation_capture_metrics"


def source(path):
    return path.read_text(encoding="utf-8-sig")


def sql_assignments(body, variables=None):
    """Evaluate only string-literal/known-identifier SQL concatenations."""
    variables = variables or {}
    current = None
    for operator, expression in re.findall(r"\bsql\s*(=|\+=)\s*(.*?);", body, re.S):
        tokens = re.findall(r'"(?:[^"\\]|\\.)*"|\b[A-Za-z]\w*\b', expression)
        value = "".join(json.loads(token) if token.startswith('"') else variables[token]
                        for token in tokens)
        if operator == "=":
            if current is not None:
                yield current
            current = value
        else:
            if current is None:
                raise AssertionError("SQL += without initializer")
            current += value
    if current is not None:
        yield current


def schema_statements():
    for name in ("ZigZagElliotAlertRun", "ZigZagElliotObservation",
                 "ZigZagElliotObservationTimeFrame", "ZigZagElliotObservationCaptureMetrics"):
        body = source(DAO / f"{name}Dao.mqh").split("bool createTable(", 1)[1]
        body = body.split("\n    /**", 1)[0]
        yield from sql_assignments(body)
    body = source(DAO / "ZigZagElliotObservationJstMigration.mqh")
    body = body.split("static bool ensureMissingIndex(", 1)[1].split("\n    /**", 1)[0]
    for table, column in ((OBS, "anchor_jst_time"),
                          ("zigzag_elliot_observation_timeframes", "latest_point_jst_time")):
        yield from sql_assignments(body, dict(fromTableName=table,
                                             fromJstTimeColumnName=column,
                                             fromJstTimeTextColumnName=column + "_text"))


def normalize_sql(sql):
    literal = False
    pending_space = False
    result = ""
    for char in sql:
        if char == "'":
            if pending_space and result:
                result += " "
            pending_space = False
            literal = not literal
            result += char
        elif literal:
            result += char
        elif char in " \t\r\n":
            pending_space = True
        else:
            if pending_space and result:
                result += " "
            pending_space = False
            result += char.upper()
    return result


def schema_text(db):
    rows = db.execute("SELECT type, name, COALESCE(sql, '') FROM sqlite_master "
                      "WHERE name NOT GLOB 'sqlite_*' ORDER BY type, name")
    return "".join(f"{kind}:{name}:{normalize_sql(sql)}\n" for kind, name, sql in rows)


def expected_schema_hash():
    body = source(GUARD).split("static string getSupportedSchemaHash() {", 1)[1]
    return re.search(r'return "([^"]+)"', body).group(1)


def guard_queries():
    body = source(GUARD).split("static bool inspectM5(", 1)[1].split("\n    /**", 1)[0]
    return list(sql_assignments(body))


def is_allowed(db):
    text = schema_text(db)
    if not text:
        return True
    if hashlib.sha256(text.encode()).hexdigest() != expected_schema_hash():
        return False
    return not any(db.execute(sql).fetchone()[0] for sql in guard_queries())


class M5ObservationGuardContractTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys=ON")
        for sql in schema_statements():
            self.db.execute(sql)

    def tearDown(self):
        self.db.close()

    def insert(self, table, **changes):
        values = {name: (1 if kind == "INTEGER" else 1.0 if kind == "REAL" else "text")
                  for _, name, kind, required, default, primary in self.db.execute(f"PRAGMA table_info({table})")
                  if required and default is None and not primary}
        values.update(changes)
        columns = ",".join(values)
        placeholders = ",".join("?" for _ in values)
        return self.db.execute(f"INSERT INTO {table} ({columns}) VALUES ({placeholders})",
                               list(values.values())).lastrowid

    def add_run(self, **changes):
        values = dict(run_uid="run1", schema_version=1, source_mode="LIVE", source_server="test",
                      strategy="M5_OBSERVATION_ALL", strategy_version="M5_OBSERVATION_ALL_V1",
                      analysis_version="test", analysis_input_hash="a" * 64,
                      analysis_input_text="M5_OBSERVATION_PROFILE_V1|STO_SHORT_K=5")
        return self.insert(RUNS, **(values | changes))

    def add_observation(self, **changes):
        values = dict(run_id=self.add_run(), source_mode="LIVE", source_server="test",
                      anchor_time_frame=5, anchor_time_frame_text="M5", time_frame_count=7,
                      capture_phase="BAR_OPEN_FIRST_SUCCESS", analysis_version="test",
                      analysis_input_hash="a" * 64, pip_size=0.0001, spread_pips=0.0)
        return self.insert(OBS, **(values | changes))

    def test_production_schema_fingerprint(self):
        self.assertEqual(len(list(schema_statements())), 18)
        self.assertEqual(hashlib.sha256(schema_text(self.db).encode()).hexdigest(),
                         expected_schema_hash())
        self.assertEqual(len(self.db.execute(f"PRAGMA table_info({METRICS})").fetchall()), 6)

    def test_empty_and_complete_empty_m5_are_allowed(self):
        with closing(sqlite3.connect(":memory:")) as empty:
            self.assertTrue(is_allowed(empty))
        self.assertTrue(is_allowed(self.db))

    def test_compatible_m5_run_only_is_allowed(self):
        self.add_run()
        self.assertTrue(is_allowed(self.db))

    def test_h1_and_alert_run_only_are_rejected(self):
        for strategy in ("H1_OBSERVATION_ALL", "MTF_3in3", "M5_UNKNOWN"):
            with self.subTest(strategy=strategy):
                self.db.execute(f"DELETE FROM {RUNS}")
                self.add_run(strategy=strategy)
                self.assertFalse(is_allowed(self.db))

    def test_unsupported_version_or_profile_are_rejected(self):
        for changes in (dict(schema_version=2), dict(strategy_version="future"),
                        dict(analysis_input_text="H1_OBSERVATION_PROFILE_V1|"),
                        dict(analysis_input_hash="")):
            with self.subTest(changes=changes):
                self.db.execute(f"DELETE FROM {RUNS}")
                self.add_run(**changes)
                self.assertFalse(is_allowed(self.db))

    def test_mixed_run_rejected(self):
        self.add_run()
        self.add_run(run_uid="run2", strategy="H1_OBSERVATION_ALL")
        self.assertFalse(is_allowed(self.db))

    def test_m5_observation_with_missing_metrics_is_not_backfilled_or_rejected(self):
        self.add_observation()
        self.assertTrue(is_allowed(self.db))
        self.assertEqual(self.db.execute(f"SELECT COUNT(*) FROM {METRICS}").fetchone()[0], 0)

    def test_foreign_observation_or_inconsistent_run_rejected(self):
        for changes in (dict(anchor_time_frame=16385), dict(anchor_time_frame_text="H1"),
                        dict(time_frame_count=5), dict(source_server="different"),
                        dict(analysis_input_hash="b" * 64), dict(pip_size=None),
                        dict(spread_pips=None)):
            with self.subTest(changes=changes):
                self.db.execute(f"DELETE FROM {RUNS}")
                self.add_observation(**changes)
                self.assertFalse(is_allowed(self.db))

    def test_extra_table_index_or_trigger_rejected(self):
        for sql, drop in (("CREATE TABLE unknown(id INTEGER)", "DROP TABLE unknown"),
                          (f"CREATE INDEX extra ON {RUNS}(source_mode)", "DROP INDEX extra"),
                          (f"CREATE TRIGGER extra AFTER INSERT ON {RUNS} BEGIN SELECT 1; END",
                           "DROP TRIGGER extra")):
            with self.subTest(sql=sql):
                self.db.execute(sql)
                self.assertFalse(is_allowed(self.db))
                self.db.execute(drop)
        self.assertTrue(is_allowed(self.db))

    def test_partial_or_altered_schema_rejected(self):
        self.db.execute(f"DROP TABLE {METRICS}")
        self.assertFalse(is_allowed(self.db))
        self.db.execute(f"CREATE TABLE {METRICS}(observation_id INTEGER PRIMARY KEY)")
        self.assertFalse(is_allowed(self.db))

    def test_literals_preserved_during_normalization(self):
        self.assertEqual(normalize_sql(" CHECK ( mode IN ('LIVE', 'TESTER') ) "),
                         "CHECK ( MODE IN ('LIVE', 'TESTER') )")
        self.assertNotEqual(normalize_sql("CHECK(mode='LIVE')"), normalize_sql("CHECK(mode='live')"))
        self.assertEqual(normalize_sql(" DEFAULT 'a '' B' "), "DEFAULT 'a '' B'")
        self.assertNotEqual(normalize_sql("rate TEXT NOT NULL"), normalize_sql("rate TEXTNOTNULL"))
        body = source(GUARD).split("static string normalizeSql(", 1)[1].split("\n    /**", 1)[0]
        self.assertIn("if (!isLiteral)", body)
        self.assertIn("StringToUpper(part)", body)
        self.assertIn("hasPendingSpace", body)

    def test_inspection_is_read_only(self):
        self.add_run()
        self.db.commit()
        self.db.execute("PRAGMA query_only=ON")
        before = schema_text(self.db), self.db.total_changes
        self.assertTrue(is_allowed(self.db))
        self.assertEqual((schema_text(self.db), self.db.total_changes), before)
        text = source(GUARD)
        for forbidden in ("DatabaseExecute(", "DatabaseTransactionBegin(", "DatabaseOpen(",
                          "PRAGMA journal_mode", "PRAGMA wal_checkpoint"):
            self.assertNotIn(forbidden, text)

    def test_query_failure_is_not_treated_as_empty(self):
        self.db.close()
        with self.assertRaises(sqlite3.ProgrammingError):
            is_allowed(self.db)
        body = source(GUARD).split("if (!readSchema(", 1)[1].split("if (objectCount == 0)", 1)[0]
        self.assertIn("return false;", body)

    def test_quality_null_zero_positive_and_cascade(self):
        observation = self.add_observation()
        self.db.execute(f"INSERT INTO {METRICS}(observation_id,analysis_elapsed_ms,capture_elapsed_ms)"
                        " VALUES (?,0,0)", (observation,))
        row = self.db.execute(f"SELECT * FROM {METRICS}").fetchone()
        self.assertEqual(row, (observation, None, None, 0, 0, None))
        self.db.execute(f"UPDATE {METRICS} SET quote_tick_time_msc=1,capture_market_time=1,"
                        "analysis_attempt_count=1")
        self.db.execute(f"DELETE FROM {OBS}")
        self.assertEqual(self.db.execute(f"SELECT COUNT(*) FROM {METRICS}").fetchone()[0], 0)

    def test_quality_constraints_and_one_to_one(self):
        observation = self.add_observation()
        for column, value in (("quote_tick_time_msc", 0), ("capture_market_time", 0),
                              ("analysis_elapsed_ms", -1), ("capture_elapsed_ms", -1),
                              ("analysis_attempt_count", 0)):
            with self.subTest(column=column), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f"INSERT INTO {METRICS}(observation_id,{column}) VALUES (?,?)",
                                (observation, value))
        self.db.execute(f"INSERT INTO {METRICS}(observation_id) VALUES (?)", (observation,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(f"INSERT INTO {METRICS}(observation_id) VALUES (?)", (observation,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(f"INSERT INTO {METRICS}(observation_id) VALUES (?)", (observation + 100,))

    def test_entity_availability_and_dao_null_contract(self):
        entity = source(ENTITY)
        dao = source(DAO / "ZigZagElliotObservationCaptureMetricsDao.mqh")
        for name, invalid in (("QuoteTickTimeMsc", "<= 0"), ("CaptureMarketTime", "<= 0"),
                              ("AnalysisElapsedMs", "< 0"), ("CaptureElapsedMs", "< 0"),
                              ("AnalysisAttemptCount", "< 1")):
            member = name[0].lower() + name[1:]
            self.assertIn(f"bool has{name};", entity)
            self.assertIn(f"has{name} && {member} {invalid}", entity)
            self.assertIn(f"fromEntity.has{name}, fromEntity.{member}", dao)
        self.assertIn('return "NULL";', dao)
        self.assertIn("return IntegerToString(fromNumber);", dao)
        self.assertNotIn("ON CONFLICT", dao)
        self.assertNotIn("OR REPLACE", dao)

    def test_mql_headers_bom_and_identifier_length(self):
        for path in (ENTITY, GUARD, DAO / "ZigZagElliotObservationCaptureMetricsDao.mqh"):
            with self.subTest(path=path.name):
                self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"))
                guard = re.search(r"#ifndef (\w+)", source(path)).group(1)
                self.assertLessEqual(len(guard), 63)
                self.assertIn(f"#define {guard}", source(path))


if __name__ == "__main__":
    unittest.main()
