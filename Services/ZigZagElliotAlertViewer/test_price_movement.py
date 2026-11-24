"""Saved movement is optional, source-consistent and safe for read-only JSON APIs."""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from sqlalchemy import event

from app import AlertDatabase
from price_movement import PRICE_MOVEMENT_COLUMNS, price_movement_snapshot
from test_alert_corrections import (
    ORIGINAL_TIME_FRAME_TABLE, TIME_FRAME_TABLE, create_correction_database,
)


def valid_movement(**changes) -> dict:
    values = {
        "is_price_movement_valid": 1,
        "price_movement_level": 3,
        "price_movement_average_range_pips": 4.5,
        "price_movement_reference_atr_pips": 3.0,
        "price_movement_activity_ratio": 1.5,
        "is_price_movement_spread_valid": 1,
        "price_movement_range_spread_ratio": 4.5,
        "price_movement_reference_bar_time": 1795507200,
    }
    values.update(changes)
    return values


class PriceMovementNormalizationTest(unittest.TestCase):
    def test_zero_is_valid_and_saved_level_is_not_reclassified(self) -> None:
        result = price_movement_snapshot(valid_movement(
            price_movement_level=1, price_movement_average_range_pips=0.0,
            price_movement_activity_ratio=0.0, price_movement_range_spread_ratio=0.0,
        ))
        self.assertEqual("VALID", result["price_movement_status"])
        self.assertIs(True, result["is_price_movement_valid"])
        self.assertIs(True, result["is_price_movement_spread_valid"])
        self.assertEqual(0.0, result["price_movement_activity_ratio"])
        self.assertEqual(0.0, result["price_movement_range_spread_ratio"])
        # Classification belongs to the saved calculation version, not the Viewer.
        result = price_movement_snapshot(valid_movement(price_movement_activity_ratio=0.5))
        self.assertEqual(3, result["price_movement_level"])

    def test_missing_or_partial_columns_are_unrecorded(self) -> None:
        for missing in PRICE_MOVEMENT_COLUMNS:
            with self.subTest(column=missing):
                row = valid_movement()
                row.pop(missing)
                result = price_movement_snapshot(row, {"schema_version": 10})
                self.assertEqual("UNRECORDED", result["price_movement_status"])
                self.assertIs(False, result["is_price_movement_valid"])
                self.assertIsNone(result["price_movement_activity_ratio"])

    def test_run_provenance_distinguishes_missing_calculation_from_legacy(self) -> None:
        row = valid_movement(is_price_movement_valid=0)
        cases = (
            ({"schema_version": 10}, "UNAVAILABLE"),
            ({"schema_version": 11}, "UNAVAILABLE"),
            ({"schema_version": 9}, "UNRECORDED"),
            ({"input_text": "x=1|priceMovementVersion=PRICE_MOVEMENT_V1|y=2"}, "UNAVAILABLE"),
            ({"input_text": "notpriceMovementVersion=PRICE_MOVEMENT_V1"}, "UNKNOWN"),
            ({"input_text": "priceMovementVersion="}, "UNKNOWN"),
            ({"input_text": "priceMovementVersion=V1|priceMovementVersion=V1"}, "UNKNOWN"),
            ({"schema_version": "10"}, "UNKNOWN"),
            ({"schema_version": 0}, "UNKNOWN"),
            (None, "UNKNOWN"),
        )
        for run, status in cases:
            with self.subTest(run=run):
                result = price_movement_snapshot(row, run)
                self.assertEqual(status, result["price_movement_status"])
                self.assertIsNone(result["price_movement_level"])
                self.assertIsNone(result["price_movement_reference_bar_time"])

    def test_invalid_core_never_leaks_nonfinite_or_fabricated_zero(self) -> None:
        cases = (
            ("is_price_movement_valid", 2), ("is_price_movement_valid", "1"),
            ("is_price_movement_valid", 1.0), ("price_movement_level", 0),
            ("price_movement_level", 4), ("price_movement_level", True),
            ("price_movement_average_range_pips", -0.1),
            ("price_movement_average_range_pips", float("nan")),
            ("price_movement_reference_atr_pips", 0),
            ("price_movement_reference_atr_pips", float("inf")),
            ("price_movement_activity_ratio", sys.float_info.max),
            ("price_movement_activity_ratio", None),
            ("price_movement_reference_bar_time", 0),
            ("price_movement_reference_bar_time", 1795507200.0),
        )
        for name, value in cases:
            with self.subTest(field=name, value=value):
                result = price_movement_snapshot(valid_movement(**{name: value}), {"schema_version": 10})
                self.assertEqual("UNAVAILABLE", result["price_movement_status"])
                self.assertIs(False, result["is_price_movement_valid"])
                self.assertIsNone(result["price_movement_activity_ratio"])
                json.dumps(result, allow_nan=False)

    def test_spread_failure_does_not_invalidate_activity(self) -> None:
        for flag, ratio in ((0, 4.5), (2, 4.5), ("1", 4.5), (1, -1),
                            (1, None), (1, float("inf")), (1, sys.float_info.max)):
            with self.subTest(flag=flag, ratio=ratio):
                result = price_movement_snapshot(valid_movement(
                    is_price_movement_spread_valid=flag, price_movement_range_spread_ratio=ratio,
                ))
                self.assertEqual("VALID", result["price_movement_status"])
                self.assertEqual(1.5, result["price_movement_activity_ratio"])
                self.assertIs(False, result["is_price_movement_spread_valid"])
                self.assertIsNone(result["price_movement_range_spread_ratio"])


class PriceMovementApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "movement.sqlite"
        create_correction_database(self.path)
        self.database = AlertDatabase(self.path)
        self.database.validate()

    def tearDown(self) -> None:
        self.database.close()
        self.temporary.cleanup()

    def update(self, sql: str, values: tuple = ()) -> None:
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute(sql, values)

    def save_movement(self, table: str, values: dict, alert_id: int = 1) -> None:
        fields = ",".join(f"{name}=?" for name in values)
        self.update(f"UPDATE {table} SET {fields} WHERE alert_id=?", (*values.values(), alert_id))

    def list_frame(self, alert_id: int = 1) -> dict:
        rows = self.database.alerts({"pageSize": ["50"]})["items"]
        return next(row for row in rows if row["id"] == alert_id)["analysis_snapshot"]["timeframes"][-1]

    def test_selected_list_and_both_detail_sources_keep_their_saved_values(self) -> None:
        self.save_movement(ORIGINAL_TIME_FRAME_TABLE, valid_movement(price_movement_activity_ratio=0.5))
        self.save_movement(TIME_FRAME_TABLE, valid_movement())
        original = self.database.timeframes(1)["items"][-1]
        detail = self.database.alert_detail(1)
        corrected = detail["correction"]["timeframes"][-1]
        self.assertEqual("APPLIED", detail["correction"]["status"])
        self.assertEqual(0.5, original["price_movement_activity_ratio"])
        self.assertEqual(1.5, corrected["price_movement_activity_ratio"])
        self.assertEqual(1.5, self.list_frame()["price_movement_activity_ratio"])
        for frame in (original, corrected, self.list_frame()):
            self.assertEqual("VALID", frame["price_movement_status"])
            self.assertIs(True, frame["is_price_movement_valid"])
            self.assertIs(True, frame["is_price_movement_spread_valid"])
            self.assertEqual(3, frame["price_movement_level"])

    def test_invalid_optional_movement_preserves_corrected_wave_and_valid_core(self) -> None:
        self.update("UPDATE zigzag_elliot_alert_runs SET schema_version=10")
        self.save_movement(TIME_FRAME_TABLE, valid_movement(
            is_price_movement_spread_valid=2, price_movement_range_spread_ratio=float("inf"),
        ))
        correction = self.database.alert_detail(1)["correction"]
        self.assertEqual("APPLIED", correction["status"])
        self.assertEqual("VALID", correction["timeframes"][-1]["price_movement_status"])
        self.assertIsNone(correction["timeframes"][-1]["price_movement_range_spread_ratio"])
        self.save_movement(TIME_FRAME_TABLE, {"price_movement_activity_ratio": float("inf")})
        correction = self.database.alert_detail(1)["correction"]
        self.assertEqual("APPLIED", correction["status"])
        self.assertEqual("UNAVAILABLE", correction["timeframes"][-1]["price_movement_status"])
        self.assertEqual("1", correction["timeframes"][-1]["latest_elliot_label"])
        self.assertEqual("UNAVAILABLE", self.list_frame()["price_movement_status"])
        json.dumps(correction, allow_nan=False)

    def test_migrated_legacy_rows_and_new_unknown_rows_use_run_metadata(self) -> None:
        for schema, input_text, status in (
            (9, "", "UNRECORDED"), (10, "", "UNAVAILABLE"),
            (9, "priceMovementVersion=PRICE_MOVEMENT_V1", "UNAVAILABLE"),
            (None, "", "UNKNOWN"),
        ):
            with self.subTest(schema=schema, input_text=input_text):
                self.update("UPDATE zigzag_elliot_alert_runs SET schema_version=?,input_text=?",
                            (schema, input_text))
                frames = [self.database.timeframes(1)["items"][-1], self.list_frame(),
                          self.database.alert_detail(1)["correction"]["timeframes"][-1]]
                for frame in frames:
                    self.assertEqual(status, frame["price_movement_status"])
                    self.assertIsNone(frame["price_movement_activity_ratio"])

    def test_missing_column_never_infers_valid_data_from_other_columns(self) -> None:
        self.save_movement(ORIGINAL_TIME_FRAME_TABLE, valid_movement())
        self.save_movement(TIME_FRAME_TABLE, valid_movement())
        self.update(f"ALTER TABLE {ORIGINAL_TIME_FRAME_TABLE} DROP COLUMN price_movement_reference_bar_time")
        self.update(f"ALTER TABLE {TIME_FRAME_TABLE} DROP COLUMN price_movement_reference_bar_time")
        self.database.close()
        self.database = AlertDatabase(self.path)
        self.database.validate()
        for frame in (self.database.timeframes(1)["items"][-1], self.list_frame(),
                      self.database.alert_detail(1)["correction"]["timeframes"][-1]):
            self.assertEqual("UNRECORDED", frame["price_movement_status"])
            self.assertIsNone(frame["price_movement_level"])

    def test_movement_reads_do_not_modify_database_or_issue_per_row_run_queries(self) -> None:
        statements = []
        def record(connection, cursor, statement, parameters, context, many):
            del connection, cursor, context, many
            statements.append((statement, parameters))
        with closing(sqlite3.connect(self.path)) as connection:
            before = "\n".join(connection.iterdump())
        event.listen(self.database.engine, "before_cursor_execute", record)
        try:
            page = self.database.alerts({"pageSize": ["2"]})
            self.database.timeframes(1)
            self.database.alert_detail(1)
        finally:
            event.remove(self.database.engine, "before_cursor_execute", record)
        run_queries = [(sql, parameters) for sql, parameters in statements
                       if "LEFT JOIN zigzag_elliot_alert_runs AS r" in sql]
        self.assertEqual(1, len(run_queries))
        self.assertEqual({row["id"] for row in page["items"]}, set(run_queries[0][1]))
        with closing(sqlite3.connect(self.path)) as connection:
            self.assertEqual(before, "\n".join(connection.iterdump()))


if __name__ == "__main__":
    unittest.main()
