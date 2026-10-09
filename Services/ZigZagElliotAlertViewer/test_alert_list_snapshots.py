"""Read-only list snapshots must select one analysis and preserve missing data."""

from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from sqlalchemy import event

from app import AlertDatabase
from test_alert_corrections import (
    CORRECTION_TABLE,
    ORIGINAL_POINT_TABLE,
    ORIGINAL_TIME_FRAME_TABLE,
    POINT_TABLE,
    TIME_FRAME_TABLE,
    create_correction_database,
)


class AlertListSnapshotsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "snapshots.sqlite"
        create_correction_database(self.path)
        self.database = AlertDatabase(self.path)
        self.database.validate()
        for table, percent in ((ORIGINAL_POINT_TABLE, 111.1), (POINT_TABLE, 138.2)):
            self.update(f"""
                UPDATE {table}
                SET is_original_elliot_available=1, org_elliot_index=3,
                    org_elliot_label='3', is_fibonacci_available=0,
                    fibonacci_percent=62.8, is_fibonacci_expansion_available=1,
                    fibonacci_expansion_percent=?
                WHERE is_latest=1
            """, (percent,))

    def tearDown(self) -> None:
        self.database.close()
        self.temporary.cleanup()

    def update(self, sql: str, parameters: tuple = ()) -> None:
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute(sql, parameters)

    def rows(self, query: dict | None = None) -> dict[int, dict]:
        return {row["id"]: row for row in self.database.alerts(query or {})["items"]}

    def snapshot(self, alert_id: int) -> dict:
        return self.rows()[alert_id]["analysis_snapshot"]

    def test_selected_analysis_is_consistent_and_flat_fields_unchanged(self) -> None:
        rows = self.rows()
        for alert_id, changed_frame, side in (
            (1, "H1", "BUY"), (2, "H4", "SELL"),
            (7, "D1", "BUY"), (8, "D1", "SELL"),
            (11, "D1", "BUY"), (12, "D1", "SELL"),
            (13, "H4", "BUY"), (14, "H4", "SELL"),
            (16, "H1", "BUY"), (17, "H1", "SELL"),
        ):
            with self.subTest(alert=alert_id):
                row = rows[alert_id]
                snapshot = row["analysis_snapshot"]
                self.assertEqual("APPLIED", snapshot["status"])
                self.assertEqual(changed_frame, snapshot["correction_time_frame_text"])
                self.assertNotEqual(side, row[f"{changed_frame.lower()}_side"])
                self.assertTrue(all(frame["side"] == side for frame in snapshot["timeframes"]))
                self.assertTrue(all(frame["latest_elliot_label"] == "1" for frame in snapshot["timeframes"]))
                self.assertTrue(all(frame["fibonacci_expansion_percent"] == 138.2 for frame in snapshot["timeframes"]))
                self.assertEqual(row["time_frame_text"], snapshot["timeframes"][-1]["time_frame_text"])
                self.assertEqual("3", self.database.timeframes(alert_id)["items"][-1]["latest_elliot_label"])

    def test_none_unrecorded_and_incomplete_have_distinct_sources(self) -> None:
        for alert_id, status in ((3, "NONE"), (4, "UNRECORDED"), (5, "INCOMPLETE")):
            with self.subTest(status=status):
                snapshot = self.snapshot(alert_id)
                self.assertEqual(status, snapshot["status"])
                self.assertIsNone(snapshot["correction_time_frame_text"])
                if status == "INCOMPLETE":
                    self.assertEqual([], snapshot["timeframes"])
                else:
                    self.assertEqual("3", snapshot["timeframes"][-1]["latest_elliot_label"])
                    self.assertEqual(111.1, snapshot["timeframes"][-1]["fibonacci_expansion_percent"])

    def test_original_m1_alerts_preserve_current_frame_and_ema(self) -> None:
        self.update("UPDATE zigzag_elliot_alerts SET time_frame=1, time_frame_text='M1' WHERE id IN (3,4)")
        self.update(f"UPDATE {ORIGINAL_TIME_FRAME_TABLE} SET time_frame=1, time_frame_text='M1' "
                    "WHERE alert_id IN (3,4) AND time_frame=5")
        for alert_id, status in ((3, "NONE"), (4, "UNRECORDED")):
            with self.subTest(status=status):
                snapshot = self.snapshot(alert_id)
                self.assertEqual(status, snapshot["status"])
                frame = snapshot["timeframes"][-1]
                self.assertEqual("M1", frame["time_frame_text"])
                self.assertEqual("BUY", frame["side"])
                self.assertIs(True, frame["is_ema200_available"])
                self.assertIs(True, frame["is_ema200_buy"])
                self.assertIs(False, frame["is_ema200_sell"])
                self.assertEqual(111.1, frame["fibonacci_expansion_percent"])

    def test_correction_validation_matches_detail_and_never_falls_back(self) -> None:
        mutations = (
            f"UPDATE {CORRECTION_TABLE} SET selected_stop_loss=9 WHERE alert_id=1",
            f"UPDATE {TIME_FRAME_TABLE} SET is_buy=1,buy_sell_label='BUY' WHERE alert_id=2 AND time_frame=32769",
            f"DELETE FROM {POINT_TABLE} WHERE alert_timeframe_id=705",
            f"UPDATE {POINT_TABLE} SET is_latest=1 WHERE alert_timeframe_id=1206",
        )
        for sql in mutations:
            self.update(sql)
        rows = self.rows()
        for alert_id in (1, 2, 7, 12):
            with self.subTest(alert=alert_id):
                self.assertEqual("INCOMPLETE", self.database.alert_detail(alert_id)["correction"]["status"])
                self.assertEqual({"status": "INCOMPLETE", "correction_time_frame_text": None,
                                  "timeframes": []}, rows[alert_id]["analysis_snapshot"])

    def test_nullable_corrected_values_are_not_filled_from_original(self) -> None:
        self.update(f"UPDATE {TIME_FRAME_TABLE} SET is_ema200_buy=NULL, is_wave_uptrend=NULL, "
                    "is_wave_confirmed=NULL WHERE alert_id=11 AND time_frame=15")
        self.update(f"UPDATE {POINT_TABLE} SET is_original_elliot_available=NULL, "
                    "is_fibonacci_expansion_available=NULL WHERE alert_timeframe_id=1106 AND is_latest=1")
        snapshot = self.snapshot(11)
        self.assertEqual("APPLIED", snapshot["status"])
        frame = snapshot["timeframes"][-1]
        for key in ("is_ema200_buy", "is_wave_uptrend", "is_wave_confirmed", "org_elliot_index",
                    "org_elliot_label", "is_fibonacci_expansion_available", "fibonacci_expansion_percent"):
            self.assertIsNone(frame[key], key)
        self.assertIs(True, frame["is_ema200_available"])

    def test_missing_or_ambiguous_latest_point_does_not_guess_percent(self) -> None:
        self.update(f"UPDATE {ORIGINAL_POINT_TABLE} SET is_latest=1 WHERE alert_timeframe_id=307")
        self.update(f"UPDATE {ORIGINAL_POINT_TABLE} SET is_latest=0 WHERE alert_timeframe_id=407")
        self.update(f"UPDATE {ORIGINAL_POINT_TABLE} SET point_order=99 WHERE alert_timeframe_id=1506 AND is_latest=1")
        for alert_id in (3, 4, 15):
            with self.subTest(alert=alert_id):
                frame = self.snapshot(alert_id)["timeframes"][-1]
                self.assertIsNone(frame["org_elliot_index"])
                self.assertIsNone(frame["is_fibonacci_expansion_available"])
                self.assertIsNone(frame["fibonacci_expansion_percent"])
                self.assertEqual("3", frame["latest_elliot_label"])

    def test_availability_and_finite_numbers_are_independent(self) -> None:
        self.update(f"UPDATE {ORIGINAL_POINT_TABLE} SET org_elliot_index=4, org_elliot_label='4', "
                    "is_fibonacci_available=1, fibonacci_percent=0, "
                    "is_fibonacci_expansion_available=0 WHERE alert_timeframe_id=307 AND is_latest=1")
        frame = self.snapshot(3)["timeframes"][-1]
        self.assertEqual(4, frame["org_elliot_index"])
        self.assertIs(True, frame["is_fibonacci_available"])
        self.assertEqual(0, frame["fibonacci_percent"])
        self.assertIs(False, frame["is_fibonacci_expansion_available"])
        self.assertIsNone(frame["fibonacci_expansion_percent"])
        self.update(f"UPDATE {ORIGINAL_POINT_TABLE} SET fibonacci_percent=? "
                    "WHERE alert_timeframe_id=307 AND is_latest=1", (float("inf"),))
        snapshot = self.snapshot(3)
        self.assertIsNone(snapshot["timeframes"][-1]["fibonacci_percent"])
        json.dumps(snapshot, allow_nan=False)

    def test_legacy_database_without_correction_or_point_tables(self) -> None:
        for table in (CORRECTION_TABLE, TIME_FRAME_TABLE, POINT_TABLE, ORIGINAL_POINT_TABLE):
            self.update(f"DROP TABLE {table}")
        for column in ("is_ema200_buy", "is_ema200_sell"):
            self.update(f"ALTER TABLE {ORIGINAL_TIME_FRAME_TABLE} DROP COLUMN {column}")
        snapshot = self.snapshot(1)
        self.assertEqual("UNRECORDED", snapshot["status"])
        frame = snapshot["timeframes"][-1]
        self.assertEqual("3", frame["latest_elliot_label"])
        self.assertIs(False, frame["is_ema200_available"])
        self.assertIsNone(frame["is_ema200_buy"])
        self.assertIsNone(frame["fibonacci_expansion_percent"])

    def test_page_queries_are_batched_and_only_request_page_ids(self) -> None:
        statements: list[tuple[str, tuple]] = []
        def record(connection, cursor, statement, parameters, context, many):
            del connection, cursor, context, many
            statements.append((statement, parameters))
        event.listen(self.database.engine, "before_cursor_execute", record)
        try:
            page = self.database.alerts({"pageSize": ["2"]})
        finally:
            event.remove(self.database.engine, "before_cursor_execute", record)
        ids = {row["id"] for row in page["items"]}
        self.assertEqual(2, len(ids))
        snapshot_queries = [(sql, parameters) for sql, parameters in statements if " IN (?, ?)" in sql]
        self.assertEqual(5, len(snapshot_queries))
        for sql, parameters in snapshot_queries:
            self.assertEqual(ids, set(parameters), sql)
        for table in (CORRECTION_TABLE, TIME_FRAME_TABLE, POINT_TABLE,
                      ORIGINAL_TIME_FRAME_TABLE, ORIGINAL_POINT_TABLE):
            self.assertEqual(1, sum(f'PRAGMA table_info("{table}")' in sql for sql, _ in statements), table)

    def test_snapshot_uses_same_transaction_as_list_page(self) -> None:
        changed = False
        def change_after_page(connection, cursor, statement, parameters, context, many):
            nonlocal changed
            del connection, cursor, parameters, context, many
            if not changed and "SELECT * FROM alert_rows" in statement:
                changed = True
                self.update(f"UPDATE {POINT_TABLE} SET fibonacci_expansion_percent=155.5 WHERE is_latest=1")
        event.listen(self.database.engine, "after_cursor_execute", change_after_page)
        try:
            snapshot = self.snapshot(11)
            self.assertTrue(changed)
            self.assertEqual(138.2, snapshot["timeframes"][-1]["fibonacci_expansion_percent"])
        finally:
            event.remove(self.database.engine, "after_cursor_execute", change_after_page)
        self.assertEqual(155.5, self.snapshot(11)["timeframes"][-1]["fibonacci_expansion_percent"])


if __name__ == "__main__":
    unittest.main()
