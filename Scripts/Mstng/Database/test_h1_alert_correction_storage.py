"""Exercise production correction DDL/SQL and extracted MQL direction checks.

SQLite fixtures are in memory only. This verifies the migration SQL and failure
boundaries under a Python transaction harness; the MQL history smoke script
additionally exercises the actual DAO/service/reader inside MT5.
"""

import ast
import re
import sqlite3
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/ExpertAdvisor"))
from test_h1_ea_tester_warmup_contract import code_only, method


def source(relative):
    return (ROOT / "Include/Mstng" / relative).read_text(encoding="utf-8-sig")


DAO = source("Database/Dao/ZigZagElliotAlertCorrectionDao.mqh")
MIGRATION = source("Database/Dao/ZigZagElliotAlertCorrectionTimeFrameMigration.mqh")
SERVICE = source("Database/Service/ZigZagElliotAlertPersistenceService.mqh")
READER = source("Database/Query/ZigZagElliotAlertHistoryReader.mqh")
BUILDER = source("ExpertAdvisor/Mtf3In3AlertSnapshotBuilder.mqh")
TABLE = "zigzag_elliot_alert_corrections"
CONSTANTS = dict(PERIOD_MN1=49153, PERIOD_W1=32769, PERIOD_D1=16408,
                 PERIOD_H4=16388, PERIOD_H1=16385, PERIOD_M15=15, PERIOD_M5=5)
FRAMES = list(CONSTANTS.values())


def correction_ddl():
    statements = re.findall(r'\bsql\s*(?:\+=|=)\s*("(?:[^"\\]|\\.)*")\s*;', method(DAO, "createTable"))
    return "".join(ast.literal_eval(item) for item in statements)


def replacement_pairs():
    return [(ast.literal_eval(old), ast.literal_eval(new)) for old, new in re.findall(
        r'StringReplace\(tableSql,\s*("[^"]*"),\s*("[^"]*")\)', method(MIGRATION, "execute"))]


def legacy_ddl():
    ddl = correction_ddl()
    for old, new in replacement_pairs():
        ddl = ddl.replace(new, old)
    return ddl


def migrate(connection, fail_after_drop=False):
    """Run the SQL extracted from production, retaining its transaction order."""
    ddl = connection.execute(f"SELECT sql FROM sqlite_master WHERE name='{TABLE}'").fetchone()[0]
    updated = ddl
    for old, new in replacement_pairs():
        updated = updated.replace(old, new)
    if updated == ddl:
        return
    foreign_keys = connection.execute("PRAGMA foreign_keys").fetchone()[0]
    connection.execute("PRAGMA foreign_keys=OFF")
    try:
        connection.execute("BEGIN")
        connection.execute(f"UPDATE {TABLE} SET alert_id=alert_id WHERE 0")
        objects = connection.execute("SELECT sql FROM sqlite_master WHERE tbl_name=? "
                                     "AND type IN ('index','trigger') AND sql IS NOT NULL ORDER BY type,name", (TABLE,)).fetchall()
        connection.execute(updated.replace(TABLE, TABLE + "_v8", 1))
        statements = re.findall(r'executeSql\(fromDatabaseHandle,\s*("[^"]*"), fromLogger\)', method(MIGRATION, "rebuildTable"))
        if len(statements) != 3:
            raise AssertionError("Migration SQL sequence changed; update harness")
        for literal in statements:
            sql = ast.literal_eval(literal)
            connection.execute(sql)
            if fail_after_drop and sql.startswith("DROP TABLE"):
                raise sqlite3.OperationalError("injected failure after old table drop")
        for (sql,) in objects:
            connection.execute(sql)
        if connection.execute("PRAGMA foreign_key_check").fetchall():
            raise sqlite3.IntegrityError("foreign key check failed")
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.execute(f"PRAGMA foreign_keys={foreign_keys}")


def insert_correction(connection, alert_id, frame=0):
    values = {}
    for _, name, field_type, *_ in connection.execute(f"PRAGMA table_info({TABLE})"):
        values[name] = "" if field_type == "TEXT" else 0
    values.update(alert_id=alert_id, correction_status="NONE", selected_analysis="ORIGINAL")
    if frame:
        values.update(correction_status="APPLIED", correction_time_frame=frame,
                      original_direction="SELL", corrected_direction="BUY",
                      selected_analysis="CORRECTED", corrected_reference_point_time=100)
    connection.execute("INSERT INTO zigzag_elliot_alerts VALUES(?)", (alert_id,))
    placeholders = ",".join("?" for _ in values)
    connection.execute(f"INSERT INTO {TABLE}({','.join(values)}) VALUES({placeholders})", tuple(values.values()))


def translate_check(body, arguments):
    """Translate the small pure MQL direction validator, rejecting unknown code."""
    body = code_only(body)
    body = re.sub(r'ENUM_TIMEFRAMES\s+(\w+)\[\]\s*=\s*\{([^}]+)\};', r'\1 = [\2];', body)
    body = re.sub(r'for\s*\(int (\w+) = 0; \1 < ([^;]+); \1\+\+\)', r'for \1 in range(\2)', body)
    body = re.sub(r'\b(?:int|bool|ENUM_TIMEFRAMES)\s+(?=\w+\s*=)', '', body)
    body = body.replace("&&", " and ").replace("||", " or ").replace("ArraySize", "len")
    body = re.sub(r'!(?!=)', ' not ', body)
    body = re.sub(r'\btrue\b', 'True', body)
    body = re.sub(r'\bfalse\b', 'False', body)
    lines = [f"def extracted({arguments}):"]
    depth = 1
    statement = ""
    for token in re.split(r'([{};])', body):
        if token == "{":
            statement = " ".join(statement.split())
            if statement.startswith("else if "):
                statement = "elif " + statement[8:]
            if not (statement.startswith(("if ", "elif ", "for ")) or statement == "else"):
                raise AssertionError("Unknown block: " + statement)
            lines.append("    " * depth + statement + ":")
            depth += 1
            statement = ""
        elif token == "}":
            if statement.strip():
                raise AssertionError(statement)
            depth -= 1
        elif token == ";":
            lines.append("    " * depth + " ".join(statement.split()))
            statement = ""
        else:
            statement += token
    namespace = dict(CONSTANTS)
    exec("\n".join(lines), namespace)
    return namespace["extracted"]


class CorrectionMigrationTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:", isolation_level=None)
        self.connection.execute("PRAGMA foreign_keys=ON")
        self.connection.execute("CREATE TABLE zigzag_elliot_alerts(id INTEGER PRIMARY KEY)")

    def tearDown(self):
        self.connection.close()

    def create_legacy(self):
        self.connection.execute(legacy_ddl())
        self.connection.execute(f"ALTER TABLE {TABLE} ADD COLUMN preserved_note TEXT DEFAULT 'kept'")
        insert_correction(self.connection, 1)
        insert_correction(self.connection, 2, CONSTANTS["PERIOD_H4"])
        self.connection.execute(f"CREATE TABLE child(id INTEGER PRIMARY KEY, alert_id INTEGER REFERENCES {TABLE}(alert_id) ON DELETE CASCADE)")
        self.connection.execute("INSERT INTO child VALUES(91,2)")
        self.connection.execute(f"CREATE INDEX retained_index ON {TABLE}(selected_analysis)")
        self.connection.execute("CREATE TABLE audit(alert_id INTEGER)")
        self.connection.execute(f"CREATE TRIGGER retained_trigger AFTER UPDATE ON {TABLE} BEGIN INSERT INTO audit VALUES(NEW.alert_id); END")

    def test_fresh_schema_accepts_d1_and_preserves_old_choices(self):
        self.connection.execute(correction_ddl())
        for alert_id, frame in enumerate((0, CONSTANTS["PERIOD_H1"], CONSTANTS["PERIOD_H4"], CONSTANTS["PERIOD_D1"]), 1):
            insert_correction(self.connection, alert_id, frame)
        with self.assertRaises(sqlite3.IntegrityError):
            insert_correction(self.connection, 9, CONSTANTS["PERIOD_M15"])

    def test_migration_preserves_rows_children_objects_and_is_idempotent(self):
        self.create_legacy()
        before = self.connection.execute(f"SELECT * FROM {TABLE} ORDER BY alert_id").fetchall()
        migrate(self.connection)
        self.assertEqual(before, self.connection.execute(f"SELECT * FROM {TABLE} ORDER BY alert_id").fetchall())
        self.assertEqual([(91, 2)], self.connection.execute("SELECT * FROM child").fetchall())
        self.assertEqual([], self.connection.execute("PRAGMA foreign_key_check").fetchall())
        ddl = self.connection.execute(f"SELECT sql FROM sqlite_master WHERE name='{TABLE}'").fetchone()
        migrate(self.connection)
        self.assertEqual(ddl, self.connection.execute(f"SELECT sql FROM sqlite_master WHERE name='{TABLE}'").fetchone())
        self.assertEqual(1, self.connection.execute("PRAGMA foreign_keys").fetchone()[0])
        self.assertEqual(2, self.connection.execute("SELECT COUNT(*) FROM sqlite_master WHERE name IN ('retained_index','retained_trigger')").fetchone()[0])
        self.connection.execute(f"UPDATE {TABLE} SET selected_alert_text='kept' WHERE alert_id=2")
        self.assertEqual([(2,)], self.connection.execute("SELECT * FROM audit").fetchall())
        insert_correction(self.connection, 3, CONSTANTS["PERIOD_D1"])

    def test_failure_after_drop_rolls_back_everything_and_restores_fk(self):
        self.create_legacy()
        before = self.connection.execute(f"SELECT * FROM {TABLE} ORDER BY alert_id").fetchall()
        with self.assertRaises(sqlite3.OperationalError):
            migrate(self.connection, fail_after_drop=True)
        self.assertEqual(before, self.connection.execute(f"SELECT * FROM {TABLE} ORDER BY alert_id").fetchall())
        self.assertEqual([(91, 2)], self.connection.execute("SELECT * FROM child").fetchall())
        self.assertEqual(1, self.connection.execute("PRAGMA foreign_keys").fetchone()[0])
        self.assertEqual(0, self.connection.execute(f"SELECT COUNT(*) FROM sqlite_master WHERE name='{TABLE}_v8'").fetchone()[0])
        with self.assertRaises(sqlite3.IntegrityError):
            insert_correction(self.connection, 3, CONSTANTS["PERIOD_D1"])

    def test_disabled_fk_setting_is_preserved(self):
        self.create_legacy()
        self.connection.execute("PRAGMA foreign_keys=OFF")
        migrate(self.connection)
        self.assertEqual(0, self.connection.execute("PRAGMA foreign_keys").fetchone()[0])


class DirectionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.direction = staticmethod(translate_check(method(SERVICE, "isAppliedDirectionValid"),
            "fromOriginal, fromCorrected, fromCorrection, fromCurrentTimeFrame"))
        cls.profile = staticmethod(translate_check(method(READER, "isCorrectionTimeFrameValid"),
            "fromCurrentTimeFrame, fromCorrectionTimeFrame"))

    def fixture(self, current, correction, buy):
        count = 5 if current == CONSTANTS["PERIOD_H1"] else 7
        def frame(index, side):
            return SimpleNamespace(timeFrame=FRAMES[index], timeFrameOrder=index, isBuy=int(side),
                                   buySellLabel="BUY" if side else "SELL", latestElliotLabel="3")
        original = [frame(index, buy if timeframe != correction else not buy) for index, timeframe in enumerate(FRAMES[:count])]
        corrected = [frame(index, buy) for index in range(count)]
        metadata = SimpleNamespace(correctionTimeFrame=correction, originalDirection="SELL" if buy else "BUY",
                                   correctedDirection="BUY" if buy else "SELL", selectedCurrentElliotLabel="3")
        return original, corrected, metadata

    def test_m5_and_h1_both_sides_and_allowed_single_corrections(self):
        for current, corrections in ((CONSTANTS["PERIOD_M5"], ("PERIOD_H4", "PERIOD_H1")),
                                     (CONSTANTS["PERIOD_H1"], ("PERIOD_D1", "PERIOD_H4"))):
            for correction in corrections:
                for buy in (False, True):
                    with self.subTest(current=current, correction=correction, buy=buy):
                        self.assertTrue(self.profile(current, CONSTANTS[correction]))
                        self.assertTrue(self.direction(*self.fixture(current, CONSTANTS[correction], buy), current))

    def test_reject_two_opposing_legs_and_incorrect_shape(self):
        for current, correction, other in ((5, CONSTANTS["PERIOD_H4"], 4),
                                            (CONSTANTS["PERIOD_H1"], CONSTANTS["PERIOD_D1"], 3)):
            original, corrected, metadata = self.fixture(current, correction, True)
            original[other].isBuy = 0
            original[other].buySellLabel = "SELL"
            self.assertFalse(self.direction(original, corrected, metadata, current))
            original, corrected, metadata = self.fixture(current, correction, True)
            self.assertFalse(self.direction(original[:-1], corrected, metadata, current))
            corrected[0].isBuy = 0
            self.assertFalse(self.direction(original, corrected, metadata, current))

    def test_cross_profile_corrections_are_rejected(self):
        self.assertFalse(self.profile(CONSTANTS["PERIOD_H1"], CONSTANTS["PERIOD_H1"]))
        self.assertFalse(self.profile(CONSTANTS["PERIOD_M5"], CONSTANTS["PERIOD_D1"]))
        self.assertFalse(self.profile(CONSTANTS["PERIOD_M15"], CONSTANTS["PERIOD_H4"]))

    def test_source_wiring_uses_current_frame_and_selected_history(self):
        valid = method(SERVICE, "isCorrectionSnapshotValid")
        self.assertIn("fromCorrectedPoints, fromAlert.timeFrame", valid)
        self.assertIn("fromCorrection, fromAlert.timeFrame", valid)
        build = method(BUILDER, "isJudgmentSnapshotValid")
        self.assertIn("currentTimeFrame == PERIOD_H1", build)
        self.assertIn("fromOriginal.getElliot(currentTimeFrame)", build)
        markers = method(READER, "selectMarkers")
        self.assertIn("CASE WHEN c.correction_status='APPLIED' AND c.selected_analysis='CORRECTED'", markers)
        self.assertNotIn("if (fromTimeFrame == PERIOD_H1)", markers)
        for name in ("validateAnalysis", "validateComparison", "loadSnapshotRows"):
            self.assertNotIn("[6]", method(READER, name))


if __name__ == "__main__":
    unittest.main()
