"""Verify alert-list currency strength uses only the saved alert snapshot."""

from __future__ import annotations

import csv
import io
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from app import AlertDatabase
from test_app import create_alert_summary_database


METADATA_COLUMNS = {
    "currency_strength_source_mode": "TEXT",
    "currency_strength_target_m5_bar_time": "INTEGER",
    "currency_strength_m5_bar_time": "INTEGER",
    "currency_strength_calculation_version": "TEXT",
    "currency_strength_run_id": "INTEGER",
}

RANK_COLUMNS = (
    "base_long_medium_rank", "quote_long_medium_rank",
    "base_medium_short_rank", "quote_medium_short_rank",
    "long_medium_rank_difference", "medium_short_rank_difference",
)


class AlertListCurrencyStrengthTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "alerts.sqlite"
        create_alert_summary_database(self.path)
        with closing(sqlite3.connect(self.path)) as connection, connection:
            for name in RANK_COLUMNS:
                connection.execute(f"ALTER TABLE zigzag_elliot_alerts DROP COLUMN {name}")
                connection.execute(f"ALTER TABLE zigzag_elliot_alerts ADD COLUMN {name} INTEGER")
        self.write("""
            UPDATE zigzag_elliot_alerts
            SET is_currency_strength_enabled=1, currency_strength_status=3,
                is_currency_strength_available=1,
                base_currency='EUR', quote_currency='USD',
                base_long_medium_rank=1, quote_long_medium_rank=3,
                base_medium_short_rank=6, quote_medium_short_rank=8,
                long_medium_rank_difference=2, medium_short_rank_difference=2
            WHERE id=1
        """)
        self.database = AlertDatabase(self.path)

    def tearDown(self) -> None:
        self.database.close()
        self.temporary.cleanup()

    def write(self, sql: str, parameters: tuple = ()) -> None:
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute(sql, parameters)

    def add_metadata(self, column_names: tuple[str, ...] | None = None) -> None:
        if column_names is None:
            column_names = tuple(METADATA_COLUMNS)
        with closing(sqlite3.connect(self.path)) as connection, connection:
            for name in column_names:
                connection.execute(
                    f"ALTER TABLE zigzag_elliot_alerts ADD COLUMN {name} {METADATA_COLUMNS[name]}"
                )

    def rows(self) -> dict[int, dict]:
        return {row["id"]: row for row in self.database.alerts({})["items"]}

    def test_saved_ranks_and_metadata_are_preserved_per_alert(self) -> None:
        self.add_metadata()
        self.write("""
            UPDATE zigzag_elliot_alerts
            SET currency_strength_source_mode='TESTER',
                currency_strength_target_m5_bar_time=1788192000,
                currency_strength_m5_bar_time=1788191700,
                currency_strength_calculation_version='saved-weighted-v1',
                currency_strength_run_id=42
            WHERE id=1
        """)
        self.write("""
            UPDATE zigzag_elliot_alerts
            SET currency_strength_source_mode='LIVE',
                currency_strength_target_m5_bar_time=1788192300,
                currency_strength_m5_bar_time=1788192300,
                currency_strength_calculation_version='saved-uniform-v1',
                currency_strength_run_id=43
            WHERE id=2
        """)
        before = self.path.read_bytes()
        rows = self.rows()
        first = rows[1]
        self.assertEqual("LIVE", first["source_mode"])
        self.assertEqual("TESTER", first["currency_strength_source_mode"])
        self.assertEqual(1788192000, first["currency_strength_target_m5_bar_time"])
        self.assertEqual(1788191700, first["currency_strength_m5_bar_time"])
        self.assertEqual("saved-weighted-v1", first["currency_strength_calculation_version"])
        self.assertEqual(42, first["currency_strength_run_id"])
        self.assertIs(first["is_currency_strength_enabled"], True)
        self.assertIs(first["is_currency_strength_available"], True)
        self.assertEqual("3", first["currency_strength_status"])
        self.assertEqual("EUR", first["base_currency"])
        self.assertEqual("USD", first["quote_currency"])
        with closing(sqlite3.connect(self.path)) as connection:
            stored_types = connection.execute(
                "SELECT " + ",".join(f"typeof({name})" for name in RANK_COLUMNS)
                + " FROM zigzag_elliot_alerts WHERE id=1"
            ).fetchone()
        self.assertEqual(("integer",) * len(RANK_COLUMNS), stored_types)
        for name in RANK_COLUMNS:
            self.assertIs(type(first[name]), int, name)
        self.assertEqual(
            [1, 3, 6, 8, 2, 2],
            [first[name] for name in RANK_COLUMNS],
        )
        self.assertEqual("LIVE", rows[2]["currency_strength_source_mode"])
        self.assertEqual(43, rows[2]["currency_strength_run_id"])
        self.assertEqual(1788192300, rows[2]["currency_strength_m5_bar_time"])
        for name in METADATA_COLUMNS:
            self.assertIsNone(rows[3][name], name)
        self.assertEqual(before, self.path.read_bytes())

    def test_absent_legacy_metadata_is_null_without_hiding_saved_ranks(self) -> None:
        before = self.path.read_bytes()
        rows = self.rows()
        self.assertEqual(3, len(rows))
        for row in rows.values():
            for name in METADATA_COLUMNS:
                self.assertIn(name, row)
                self.assertIsNone(row[name], name)
        self.assertEqual(1, rows[1]["base_long_medium_rank"])
        self.assertEqual(2, rows[1]["medium_short_rank_difference"])
        self.assertEqual(before, self.path.read_bytes())

    def test_partial_schema_preserves_existing_metadata_and_zero_sentinels(self) -> None:
        self.add_metadata((
            "currency_strength_source_mode", "currency_strength_target_m5_bar_time",
        ))
        self.write("""
            UPDATE zigzag_elliot_alerts
            SET currency_strength_source_mode='', currency_strength_target_m5_bar_time=0
            WHERE id=1
        """)
        first = self.rows()[1]
        self.assertEqual("", first["currency_strength_source_mode"])
        self.assertEqual(0, first["currency_strength_target_m5_bar_time"])
        for name in (
            "currency_strength_m5_bar_time", "currency_strength_calculation_version",
            "currency_strength_run_id",
        ):
            self.assertIsNone(first[name], name)

    def test_run_filter_pagination_summary_and_csv_are_unchanged(self) -> None:
        query = {"sourceMode": ["LIVE"], "pageSize": ["1"], "page": ["99"]}
        before_page = self.database.alerts(query)
        before_summary = self.database.summary(query)
        before_csv = self.database.export_csv(query)
        before_empty_csv = self.database.export_csv({"symbol": ["NOTFOUND"]})
        self.add_metadata()
        self.write("""
            UPDATE zigzag_elliot_alerts SET currency_strength_source_mode='TESTER',
                currency_strength_run_id=99
        """)
        page = self.database.alerts(query)
        self.assertEqual(2, page["total"])
        self.assertEqual(2, page["page"])
        self.assertEqual(2, page["page_count"])
        self.assertEqual([1], [row["id"] for row in page["items"]])
        self.assertEqual(
            [row["id"] for row in before_page["items"]],
            [row["id"] for row in page["items"]],
        )
        self.assertEqual(before_summary, self.database.summary(query))
        self.assertEqual(before_csv, self.database.export_csv(query))
        self.assertEqual(
            before_empty_csv, self.database.export_csv({"symbol": ["NOTFOUND"]}),
        )
        csv_rows = list(csv.reader(io.StringIO(before_csv.decode("utf-8-sig"))))
        self.assertEqual(3, len(csv_rows))
        self.assertEqual(51, len(csv_rows[0]))
        self.assertTrue(all(len(row) == 51 for row in csv_rows))
        self.assertEqual(
            csv_rows[0],
            next(csv.reader(io.StringIO(before_empty_csv.decode("utf-8-sig")))),
        )
        self.assertFalse(set(METADATA_COLUMNS) & set(csv_rows[0]))


if __name__ == "__main__":
    unittest.main()
