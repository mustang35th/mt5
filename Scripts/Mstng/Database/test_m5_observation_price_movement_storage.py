"""Check M5-only movement storage with production SQL in isolated SQLite memory.

The restricted adapters extract MQL DDL, ALTER definitions, INSERT/binding order
and pure validity predicates. Transactions and injected failures run in Python;
this is not native MQL execution and never opens a trading or observation DB.
"""

import hashlib
import json
import re
import sqlite3
import sys
import unittest
from contextlib import closing
from types import SimpleNamespace

import test_m5_observation_guard_contract as guard
from test_alert_price_movement_storage import FIELDS, SAMPLE, method, mql_expression
from test_m5_observation_profile_contract import canonical


TABLE = "zigzag_elliot_observation_timeframes"
DAO = guard.source(guard.DAO / "ZigZagElliotObservationTimeFrameDao.mqh")
MIGRATION = guard.source(guard.DAO / "ZigZagElliotObservationPriceMovementMigration.mqh")
PREVIOUS = guard.source(guard.DAO / "ZigZagElliotObservationPreviousMotiveSubMigration.mqh")
BUILDER = guard.source(guard.ROOT / "Include/Mstng/ExpertAdvisor/ZigZagElliotObservationSnapshotBuilder.mqh")


def columns(db):
    return {row[1]: row[2] for row in db.execute(f"PRAGMA table_info({TABLE})")}


def movement_definitions():
    body = method(MIGRATION, "execute")

    def array(name):
        values = re.search(r"string " + name + r"\[\]\s*=\s*\{([^}]+)\}", body)[1]
        return [json.loads(value) for value in re.findall(r'"[^"\n]*"', values)]

    return list(zip(array("columnNames"), array("columnDefinitions"), strict=True))


def migrate(db, fail_after=None):
    """Use the caller transaction, like M5 DatabaseContext.initializePersistence."""
    if "previous_motive_sub_elliot_index" not in columns(db):
        db.execute(next(guard.sql_assignments(method(PREVIOUS, "execute"))))
    alter = method(MIGRATION, "ensureColumn")
    alter = alter[alter.index("string sql ="):alter.index("ResetLastError();")]
    added = 0
    for name, definition in movement_definitions():
        if name in columns(db):
            continue
        sql = next(guard.sql_assignments(alter, dict(
            fromTableName=TABLE, fromColumnName=name, fromColumnDefinition=definition)))
        db.execute(sql)
        added += 1
        if added == fail_after:
            raise sqlite3.OperationalError("injected failure during migration")


def insert_contract(m5):
    body = method(DAO, "buildInsertSql").split('sql += ") VALUES (";', 1)[0]
    bindings = method(DAO, "bindEntity")
    if not m5:
        body = re.sub(r"if \(this\.(?:savePreviousMotiveSubElliot|savePriceMovement)\) \{.*?\}",
                      "", body, flags=re.S)
        bindings = re.sub(r"if \(isBound && this\.(?:savePreviousMotiveSubElliot|savePriceMovement)\) \{.*?\}",
                          "", bindings, flags=re.S)
    prefix = next(guard.sql_assignments(body))
    names = [name.strip() for name in prefix.split("(", 1)[1].split(",")]
    fields = re.findall(r"DatabaseBind\(\s*fromRequestHandle,\s*index\+\+,\s*fromEntity\.(\w+)\s*\)", bindings)
    return prefix + ") VALUES (" + ",".join("?" for _ in fields) + ")", names, fields


class M5ObservationPriceMovementStorageTest(unittest.TestCase):
    def setUp(self):
        self.fixture = guard.M5ObservationGuardContractTest()
        self.fixture.setUp()
        self.db = self.fixture.db

    def tearDown(self):
        self.db.close()

    def seed_old(self):
        observation = self.fixture.add_observation()
        self.fixture.insert(TABLE, observation_id=observation, time_frame=5, time_frame_order=0)
        self.db.commit()
        return observation

    def fingerprint(self):
        return hashlib.sha256(guard.schema_text(self.db).encode()).hexdigest()

    def test_base_previous_and_fresh_migrations_have_same_accepted_schema(self):
        self.assertTrue(guard.is_allowed(self.db))
        self.db.execute("BEGIN")
        migrate(self.db)
        self.db.commit()
        expected = guard.expected_schema_hash("getPriceMovementSchemaHash")
        self.assertEqual(self.fingerprint(), expected)
        self.assertTrue(guard.is_allowed(self.db))
        fresh = guard.schema_text(self.db)
        with closing(sqlite3.connect(":memory:")) as old:
            for sql in guard.schema_statements():
                old.execute(sql)
            old.execute(next(guard.sql_assignments(method(PREVIOUS, "execute"))))
            self.assertTrue(guard.is_allowed(old))
            migrate(old)
            self.assertEqual(guard.schema_text(old), fresh)
            self.assertTrue(guard.is_allowed(old))

    def test_old_records_and_run_metadata_stay_unchanged_and_defaults_are_unknown(self):
        self.seed_old()
        old_columns = ",".join(columns(self.db))
        old_rows = self.db.execute(f"SELECT {old_columns} FROM {TABLE}").fetchall()
        old_runs = self.db.execute(f"SELECT * FROM {guard.RUNS}").fetchall()
        self.db.execute("BEGIN")
        migrate(self.db)
        self.db.commit()
        self.assertEqual(old_rows, self.db.execute(f"SELECT {old_columns} FROM {TABLE}").fetchall())
        self.assertEqual(old_runs, self.db.execute(f"SELECT * FROM {guard.RUNS}").fetchall())
        self.assertEqual((0,) * 8, self.db.execute(f"SELECT {','.join(FIELDS)} FROM {TABLE}").fetchone())
        before = list(self.db.iterdump())
        self.db.execute("BEGIN")
        migrate(self.db)
        self.db.commit()
        self.assertEqual(before, list(self.db.iterdump()))
        self.assertTrue(guard.is_allowed(self.db))

    def test_failed_migration_rolls_back_all_columns_and_preserves_history(self):
        self.seed_old()
        before = list(self.db.iterdump())
        with self.assertRaises(sqlite3.OperationalError):
            with self.db:
                self.db.execute("BEGIN")
                migrate(self.db, fail_after=3)
        self.assertEqual(before, list(self.db.iterdump()))
        self.assertTrue(guard.is_allowed(self.db))
        self.assertEqual([], self.db.execute("PRAGMA foreign_key_check").fetchall())
        self.assertNotIn("DatabaseTransaction", MIGRATION)

    def test_partial_migration_completes_without_replacing_saved_values(self):
        self.seed_old()
        self.db.execute(next(guard.sql_assignments(method(PREVIOUS, "execute"))))
        name, definition = movement_definitions()[0]
        self.db.execute(f"ALTER TABLE {TABLE} ADD COLUMN {name} {definition}")
        self.db.execute(f"UPDATE {TABLE} SET {name}=1")
        self.assertFalse(guard.is_allowed(self.db))
        migrate(self.db)
        self.assertEqual((1,) + (0,) * 7,
                         self.db.execute(f"SELECT {','.join(FIELDS)} FROM {TABLE}").fetchone())
        self.assertTrue(guard.is_allowed(self.db))

    def test_m5_roundtrip_keeps_all_eight_values_without_rounding(self):
        migrate(self.db)
        observation = self.fixture.add_observation()
        sql, names, fields = insert_contract(True)
        self.assertEqual(len(fields), 96)
        types = columns(self.db)
        values = {field: ("text" if types[name] == "TEXT" else 1)
                  for name, field in zip(names, fields, strict=True)}
        values.update(observationId=observation, timeFrame=5, timeFrameOrder=0,
                      previousMotiveSubElliotIndex=3)
        values.update({FIELDS[name]: value for name, value in SAMPLE.items()})
        self.db.execute(sql, [values[field] for field in fields])
        self.assertEqual(tuple(SAMPLE.values()),
                         self.db.execute(f"SELECT {','.join(FIELDS)} FROM {TABLE}").fetchone())
        for name, value in (("is_price_movement_valid", 2), ("price_movement_level", 4),
                            ("is_price_movement_spread_valid", -1)):
            with self.subTest(name=name), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f"UPDATE {TABLE} SET {name}=?", (value,))

    def test_h1_retains_original_insert_and_physical_schema(self):
        sql, names, fields = insert_contract(False)
        self.assertEqual(len(fields), 87)
        self.assertFalse(set(FIELDS).intersection(columns(self.db)))
        self.assertEqual(self.fingerprint(), guard.expected_schema_hash())
        observation = self.fixture.add_observation()
        types = columns(self.db)
        entity = {field: ("text" if types[name] == "TEXT" else 1)
                  for name, field in zip(names, fields, strict=True)}
        entity.update(observationId=observation, timeFrame=16385, timeFrameOrder=0)
        self.db.execute(sql, [entity[field] for field in fields])
        self.assertEqual(16385, self.db.execute(f"SELECT time_frame FROM {TABLE}").fetchone()[0])
        create = method(DAO, "createTable")
        self.assertRegex(create, r"if \(fromCurrentSchemaOnly\s*&& !ZigZagElliotObservationPriceMovementMigration::execute")

    def test_optional_invalid_core_and_spread_do_not_reject_snapshot(self):
        predicate = re.search(r"return (.*?);", method(BUILDER, "isPriceMovementSnapshotValid"), re.S)[1]
        valid = dict(isValid=True, level=1, averageRangePips=0.0, referenceAtrPips=2.0,
                     activityRatio=0.0, referenceBarTime=1795503600)
        self.assertTrue(mql_expression(predicate, fromInfo=SimpleNamespace(**valid)))
        for changes in ({"isValid": False}, {"referenceAtrPips": 0.0},
                        {"referenceAtrPips": float("nan")}, {"activityRatio": sys.float_info.max},
                        {"averageRangePips": -1.0}, {"referenceBarTime": 0}, {"level": 4}):
            self.assertFalse(mql_expression(predicate, fromInfo=SimpleNamespace(**(valid | changes))))
        body = method(BUILDER, "buildTimeFrame")
        optional = body.split("if (fromProfile.isM5()) {", 2)[2].split("fromEntity.ema200Close1", 1)[0]
        self.assertNotIn("return", optional)
        spread = re.search(r"if \((priceMovement.isSpreadValid.*?)\) \{", optional, re.S)[1]
        for available, ratio, expected in ((True, 0.0, True), (False, 3.0, False),
                                            (True, -1.0, False), (True, float("inf"), False),
                                            (True, sys.float_info.max, False)):
            info = SimpleNamespace(isSpreadValid=available, rangeSpreadRatio=ratio)
            self.assertEqual(expected, mql_expression(spread, priceMovement=info))

    def test_movement_is_hashed_only_in_m5_and_all_fields_participate(self):
        body = method(BUILDER, "createSnapshotHash")
        self.assertRegex(body, r"if \(fromProfile.isM5\(\)\) \{[^}]+appendPriceMovementHashValues")
        common = method(BUILDER, "appendTimeFrameHashValues")
        self.assertNotIn("priceMovement", common)
        self.assertNotIn("PriceMovement", common)
        added = method(BUILDER, "appendPriceMovementHashValues")
        self.assertEqual(list(FIELDS.values()), re.findall(r"fromEntity\.(\w+)", added))
        self.assertEqual(4, len(re.findall(r"DoubleToString\(fromEntity\.\w+, 16\)", added)))

    def test_new_calculation_profile_keeps_old_rows_as_separate_analysis(self):
        self.seed_old()
        migrate(self.db)
        new_text = canonical(True)
        old_text = new_text.split("|priceMovementVersion=", 1)[0]
        self.assertNotEqual(new_text, old_text)
        self.assertNotIn("priceMovementVersion=", canonical(False))
        self.assertEqual(new_text.count("priceMovementVersion=PRICE_MOVEMENT_V1"), 1)
        new_hash = hashlib.sha256(new_text.encode()).hexdigest()
        self.assertNotEqual(new_hash, hashlib.sha256(old_text.encode()).hexdigest())
        old = self.db.execute(f"SELECT * FROM {guard.OBS}")
        values = dict(zip((column[0] for column in old.description), old.fetchone()))
        values.pop("id")
        new_run = self.fixture.add_run(run_uid="new-run", input_text="priceMovementVersion=PRICE_MOVEMENT_V1",
                                       analysis_input_text=new_text, analysis_input_hash=new_hash)
        values.update(run_id=new_run, analysis_input_hash=new_hash)
        self.fixture.insert(guard.OBS, **values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.fixture.insert(guard.OBS, **values)
        rows = self.db.execute(f"SELECT run_id, analysis_input_hash FROM {guard.OBS} ORDER BY id").fetchall()
        self.assertEqual(rows, [(1, "a" * 64), (new_run, new_hash)])
        self.assertTrue(guard.is_allowed(self.db))


if __name__ == "__main__":
    unittest.main()
