"""Exercise production price-movement SQL against in-memory SQLite only.

DDL, INSERT, bind order and migration column definitions come from the MQL
sources. Migration transactions use a Python harness with injected failures.
The small pure reader is translated, with Python adapters for DatabaseColumn
type checks. This does not execute MQL, MT5, live databases or broker operations;
native smoke tests are still needed to validate the MQL runtime integration.
"""

import ast
import math
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


DAO = source("Database/Dao/ZigZagElliotAlertTimeFrameDao.mqh")
MIGRATION = source("Database/Dao/ZigZagElliotAlertPriceMovementMigration.mqh")
READER = source("Database/Query/ZigZagElliotAlertHistoryReader.mqh")
BUILDER = source("ExpertAdvisor/Mtf3In3AlertSnapshotBuilder.mqh")
TABLES = ("zigzag_elliot_alert_timeframes", "zigzag_elliot_alert_corrected_timeframes")
FIELDS = {
    "is_price_movement_valid": "isPriceMovementValid",
    "price_movement_level": "priceMovementLevel",
    "price_movement_average_range_pips": "priceMovementAverageRangePips",
    "price_movement_reference_atr_pips": "priceMovementReferenceAtrPips",
    "price_movement_activity_ratio": "priceMovementActivityRatio",
    "is_price_movement_spread_valid": "isPriceMovementSpreadValid",
    "price_movement_range_spread_ratio": "priceMovementRangeSpreadRatio",
    "price_movement_reference_bar_time": "priceMovementReferenceBarTime",
}
SAMPLE = dict(zip(FIELDS, (1, 3, 3.123456789012345, 2.345678901234567,
                          1.33179157062345, 1, 7.987654321012345, 1795503600)))


def expression(text, **names):
    text = text.replace("this.", "").replace("getPriceMovementColumns()", "movementColumns")
    tree = ast.parse("(" + text.strip() + ")", mode="eval")
    if any(not isinstance(node, (ast.Expression, ast.BinOp, ast.Add, ast.Constant,
                                  ast.Name, ast.Load)) for node in ast.walk(tree)):
        raise AssertionError("Unsupported SQL expression: " + text)
    return eval(compile(tree, "<extracted SQL>", "eval"), {"__builtins__": {}}, names)


def sql_assignments(body, **names):
    return "".join(expression(value, **names) for value in
                   re.findall(r"\bsql\s*(?:\+=|=)\s*([^;]+);", body))


def ddl(table):
    body = method(DAO, "createTable")
    body = body[body.index('string sql ='):body.index('if (!this.executeSql(sql,')]
    body = re.sub(r"if \(this\.isCorrectedTable\(\)\) \{([^}]+)\} else \{([^}]+)\}",
                  lambda match: match[1] if table == TABLES[1] else match[2], body)
    return sql_assignments(body, tableName=table,
                           parentTableName="zigzag_elliot_alert_corrections" if table == TABLES[1]
                           else "zigzag_elliot_alerts")


def migration_columns():
    body = method(MIGRATION, "execute")
    def array(name):
        text = re.search(r"string " + name + r"\[\]\s*=\s*\{([^}]+)\}", body)[1]
        return [ast.literal_eval(value) for value in re.findall(r'"[^"\n]*"', text)]
    return list(zip(array("columnNames"), array("columnDefinitions"), strict=True))


def columns(connection, table):
    return {row[1]: row[2] for row in connection.execute(f"PRAGMA table_info({table})")}


def migrate(connection, table, fail_after=None):
    """Execute production ALTER definitions inside the production transaction shape."""
    additions = migration_columns()
    if all(name in columns(connection, table) for name, _ in additions):
        return
    lock = re.search(r'"UPDATE " \+ fromTableName \+ "[^"\n]+"', method(MIGRATION, "execute"))[0]
    alter = method(MIGRATION, "ensureColumn")
    alter = alter[alter.index('string sql ='):alter.index('ResetLastError();', alter.index('string sql ='))]
    connection.execute("BEGIN")
    try:
        connection.execute(expression(lock, fromTableName=table))
        added = 0
        for name, definition in additions:
            if name in columns(connection, table):
                continue
            connection.execute(sql_assignments(alter, fromTableName=table,
                                                fromColumnName=name, fromColumnDefinition=definition))
            added += 1
            if fail_after == added:
                raise sqlite3.OperationalError("injected failure during ALTER sequence")
        connection.commit()
    except Exception:
        connection.rollback()
        raise


def legacy_ddl(table):
    body = ddl(table)
    for name, _ in migration_columns():
        body = re.sub(r"\b" + name + r" (?:INTEGER|REAL) NOT NULL DEFAULT 0(?: CHECK\([^)]*\)\))?,", "", body)
    return body


def insert_legacy(connection, table):
    data = {name: "" if kind == "TEXT" else 0 for name, kind in columns(connection, table).items()}
    data.update(id=1, alert_id=1, time_frame=5, time_frame_text="M5", raw_csv_text="既存の分析")
    connection.execute(f"INSERT INTO {table}({','.join(data)}) VALUES({','.join('?' for _ in data)})", tuple(data.values()))


def insert_current(connection, table, sample):
    sql = sql_assignments(method(DAO, "buildInsertSql"), tableName=table)
    column_names = re.search(r"\(([^)]+)\) VALUES", sql)[1].replace(" ", "").split(",")
    bind_fields = re.findall(r"DatabaseBind\(\s*fromRequestHandle,\s*index\+\+,\s*fromEntity\.(\w+)\s*\)",
                             method(DAO, "bindEntity"))
    types = columns(connection, table)
    entity = {field: "" if types[column] == "TEXT" else 0
              for field, column in zip(bind_fields, column_names, strict=True)}
    entity.update(alertId=1, timeFrame=5, timeFrameText="M5", rawCsvText="今回の分析")
    entity.update({FIELDS[column]: value for column, value in sample.items()})
    connection.execute(sql, tuple(entity[field] for field in bind_fields))


def movement_columns():
    return expression(re.search(r"return (.*?);", method(READER, "getPriceMovementColumns"), re.S)[1])


def frame_columns():
    return expression(re.search(r"return (.*?);", method(READER, "getTimeFrameColumns"), re.S)[1],
                      movementColumns=movement_columns()).split(",")


def mql_expression(text, **names):
    text = " ".join(text.split()).replace("&&", " and ").replace("||", " or ")
    text = re.sub(r"!(?!=)", " not ", text)
    return eval("(" + text + ")", {"__builtins__": {}, "StringFind": lambda text, term: text.find(term),
                                    "MathIsValidNumber": math.isfinite, "EMPTY_VALUE": sys.float_info.max,
                                    "PRICE_MOVEMENT_CALM": 1, "PRICE_MOVEMENT_ACTIVE": 3}, names)


def reader_projection(connection, table):
    """Execute the extracted legacy-column predicates and SQL expressions."""
    body = method(READER, "projection")
    missing = re.search(r'if \((StringFind\(columns, [^\n]+)\) \{', body)[1]
    fallback = re.search(r'if \((fromAllowLegacyTimeFrame && !hasPriceMovementColumns.*?)\) \{', body, re.S)[1]
    assignments = re.findall(r'fromProjection \+= ([^;]+);', body)
    default = next(value for value in assignments if value.startswith('"0 AS "'))
    existing = next(value for value in assignments if value.startswith("fromAlias +"))
    movement = movement_columns().split(",")
    present = "," + ",".join(columns(connection, table)) + ","
    has_all = not any(mql_expression(missing, columns=present, movementColumns=movement, i=index)
                      for index in range(len(movement)))
    required = frame_columns()
    projected = []
    for index in range(len(required)):
        use_default = mql_expression(fallback, fromAllowLegacyTimeFrame=True, hasPriceMovementColumns=has_all,
                                     priceMovementColumns="," + movement_columns() + ",", required=required, i=index)
        projected.append(mql_expression(default if use_default else existing, fromAlias="", required=required, i=index))
    return ",".join(projected)


def read_value(row, index, name, values, kind, flag=False):
    value = row[index]
    if kind == "double":
        valid = type(value) in (int, float) and math.isfinite(value)
    else:
        valid = type(value) is int
        if kind == "int":
            valid = valid and -2147483648 <= value <= 2147483647 and (not flag or value in (0, 1))
    if valid:
        values[name] = value
    return valid


def extracted_reader():
    """Translate only the production pure reader statements, rejecting unknown blocks."""
    body = code_only(method(READER, "readPriceMovement"))
    names = re.findall(r"\b(?:int|long|double)\s+(\w+)\s*=", body)
    for name in names:
        body = re.sub(r"\b" + name + r"\b", 'values["' + name + '"]', body)
    body = re.sub(r"\b(?:int|long|double)\s+(?=values\[)", "", body)
    body = re.sub(r'this\.read(Int|Long|Double)Value\(fromRequest,\s*(\d+),\s*values\["(\w+)"\](,\s*true)?\)',
                  lambda match: f'read_value(row, {match[2]}, "{match[3]}", values, "{match[1].lower()}"'
                  + (", True)" if match[4] else ")"), body)
    body = body.replace("fromEntity.", "entity.").replace("&&", " and ").replace("||", " or ")
    body = re.sub(r"!(?!=)", " not ", body)
    lines, depth, statement = ["def extracted(row, entity):", "    values = {}"], 1, ""
    for token in re.split(r"([{};])", body):
        if token == "{":
            statement = " ".join(statement.split())
            if not statement.startswith("if "):
                raise AssertionError("Unsupported reader block: " + statement)
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
    namespace = dict(read_value=read_value, PRICE_MOVEMENT_CALM=1, PRICE_MOVEMENT_ACTIVE=3,
                     EMPTY_VALUE=sys.float_info.max)
    exec("\n".join(lines), namespace)
    return namespace["extracted"]


class PriceMovementStorageTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:", isolation_level=None)
        self.connection.execute("PRAGMA foreign_keys=ON")
        self.connection.execute("CREATE TABLE zigzag_elliot_alerts(id INTEGER PRIMARY KEY)")
        self.connection.execute("CREATE TABLE zigzag_elliot_alert_corrections(alert_id INTEGER PRIMARY KEY REFERENCES zigzag_elliot_alerts(id))")
        self.connection.execute("INSERT INTO zigzag_elliot_alerts VALUES(1)")
        self.connection.execute("INSERT INTO zigzag_elliot_alert_corrections VALUES(1)")

    def tearDown(self):
        self.connection.close()

    def test_fresh_dao_roundtrip_both_tables_preserves_full_precision(self):
        for table in TABLES:
            self.connection.execute(ddl(table))
            insert_current(self.connection, table, SAMPLE)
            self.assertEqual(tuple(SAMPLE.values()), self.connection.execute(
                f"SELECT {','.join(SAMPLE)} FROM {table}").fetchone())

    def test_legacy_migration_preserves_data_and_is_idempotent(self):
        for table in TABLES:
            self.connection.execute(legacy_ddl(table))
            insert_legacy(self.connection, table)
            old_columns = list(columns(self.connection, table))
            before = self.connection.execute(f"SELECT {','.join(old_columns)} FROM {table}").fetchall()
            migrate(self.connection, table)
            self.assertEqual(before, self.connection.execute(f"SELECT {','.join(old_columns)} FROM {table}").fetchall())
            self.assertEqual((0,) * 8, self.connection.execute(f"SELECT {','.join(FIELDS)} FROM {table}").fetchone())
            after = list(self.connection.iterdump())
            migrate(self.connection, table)
            self.assertEqual(after, list(self.connection.iterdump()))

    def test_partial_migration_retains_existing_values_and_adds_missing_columns(self):
        table = TABLES[0]
        self.connection.execute(legacy_ddl(table))
        insert_legacy(self.connection, table)
        name, definition = migration_columns()[2]
        self.connection.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")
        self.connection.execute(f"UPDATE {table} SET {name}=3.125")
        migrate(self.connection, table)
        self.assertEqual((0, 3.125), self.connection.execute(f"SELECT is_price_movement_valid,{name} FROM {table}").fetchone())

    def test_failure_rolls_back_all_added_columns_and_preserves_rows(self):
        for table in TABLES:
            self.connection.execute(legacy_ddl(table))
            insert_legacy(self.connection, table)
            before = list(self.connection.iterdump())
            with self.assertRaises(sqlite3.OperationalError):
                migrate(self.connection, table, fail_after=3)
            self.assertEqual(before, list(self.connection.iterdump()))
            self.assertEqual([], self.connection.execute("PRAGMA foreign_key_check").fetchall())

    def test_fresh_and_migrated_constraints_reject_invalid_flags_and_levels(self):
        for legacy in (False, True):
            table = TABLES[int(legacy)]
            self.connection.execute(legacy_ddl(table) if legacy else ddl(table))
            if legacy:
                migrate(self.connection, table)
            insert_current(self.connection, table, SAMPLE)
            for column, value in (("is_price_movement_valid", 2), ("is_price_movement_spread_valid", -1),
                                  ("price_movement_level", 4)):
                with self.assertRaises(sqlite3.IntegrityError):
                    self.connection.execute(f"UPDATE {table} SET {column}=?", (value,))

    def test_production_reader_reads_full_rows_and_valid_zero_range(self):
        reader = extracted_reader()
        for sample in (SAMPLE, {**SAMPLE, "price_movement_level": 1, "price_movement_average_range_pips": 0.0,
                                 "price_movement_activity_ratio": 0.0, "price_movement_range_spread_ratio": 0.0}):
            row = [sample.get(column, 0) for column in frame_columns()]
            entity = SimpleNamespace(**dict.fromkeys(FIELDS.values(), 0))
            reader(row, entity)
            self.assertEqual({FIELDS[key]: value for key, value in sample.items()}, vars(entity))

    def test_reader_old_and_partial_schema_projects_unknown_without_losing_history(self):
        reader = extracted_reader()
        for table in TABLES:
            self.connection.execute(legacy_ddl(table))
            insert_legacy(self.connection, table)
            for partial in (False, True):
                if partial:
                    name, definition = migration_columns()[0]
                    self.connection.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")
                    self.connection.execute(f"UPDATE {table} SET {name}=1")
                row = self.connection.execute(f"SELECT {reader_projection(self.connection, table)} FROM {table}").fetchone()
                self.assertEqual((1, 1, 5, "M5"), row[:4])
                entity = SimpleNamespace(**dict.fromkeys(FIELDS.values(), 0))
                reader(row, entity)
                self.assertEqual(dict.fromkeys(FIELDS.values(), 0), vars(entity))

    def test_builder_accepts_flat_range_but_rejects_missing_and_invalid_data(self):
        predicate = re.search(r"return (.*?);", method(BUILDER, "isPriceMovementSnapshotValid"), re.S)[1]
        valid = dict(isValid=True, level=1, averageRangePips=0.0, referenceAtrPips=2.0,
                     activityRatio=0.0, referenceBarTime=1795503600)
        self.assertTrue(mql_expression(predicate, fromInfo=SimpleNamespace(**valid)))
        for changes in ({"isValid": False}, {"referenceAtrPips": 0.0}, {"referenceAtrPips": float("nan")},
                        {"averageRangePips": -1.0}, {"activityRatio": sys.float_info.max},
                        {"referenceBarTime": 0}, {"level": 0}, {"level": 4}):
            self.assertFalse(mql_expression(predicate, fromInfo=SimpleNamespace(**(valid | changes))))

    def test_reader_invalid_core_is_unknown_and_spread_failure_keeps_core(self):
        reader = extracted_reader()
        for invalid in (0.0, -1.0, None, "2.3", float("inf"), sys.float_info.max):
            sample = {**SAMPLE, "price_movement_reference_atr_pips": invalid}
            entity = SimpleNamespace(**dict.fromkeys(FIELDS.values(), 0))
            reader([sample.get(column, 0) for column in frame_columns()], entity)
            self.assertEqual(dict.fromkeys(FIELDS.values(), 0), vars(entity))
        for invalid in (None, "4.5", -1.0, sys.float_info.max):
            sample = {**SAMPLE, "price_movement_range_spread_ratio": invalid}
            entity = SimpleNamespace(**dict.fromkeys(FIELDS.values(), 0))
            reader([sample.get(column, 0) for column in frame_columns()], entity)
            self.assertEqual(1, entity.isPriceMovementValid)
            self.assertEqual(SAMPLE["price_movement_activity_ratio"], entity.priceMovementActivityRatio)
            self.assertEqual(0, entity.isPriceMovementSpreadValid)


if __name__ == "__main__":
    unittest.main()
