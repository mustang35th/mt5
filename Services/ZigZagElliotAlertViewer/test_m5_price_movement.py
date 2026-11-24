"""M5 movement display reads optional saved data without changing the source."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from sqlalchemy import event

from m5_observations import M5ObservationDatabase, RUN_TABLE, TIMEFRAME_TABLE
from test_m5_observations import BASE_TIME, add_observation, add_run, create_fixture, query


MOVEMENT_TYPES = {
    "is_price_movement_valid": "INTEGER",
    "price_movement_level": "INTEGER",
    "price_movement_average_range_pips": "REAL",
    "price_movement_reference_atr_pips": "REAL",
    "price_movement_activity_ratio": "REAL",
    "is_price_movement_spread_valid": "INTEGER",
    "price_movement_range_spread_ratio": "REAL",
    "price_movement_reference_bar_time": "INTEGER",
}
MOVEMENT_PROFILE = "private=secret|priceMovementVersion=PRICE_MOVEMENT_V1|priceMovementRecentBars=3"


class M5PriceMovementTest(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory(prefix="m5-movement-test-")
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "observations.sqlite"
        self.writer = create_fixture(self.path)
        self.addCleanup(self.writer.close)
        add_run(self.writer)
        self.identifier = add_observation(self.writer)
        self.writer.commit()
        self.database = M5ObservationDatabase(self.path)
        self.addCleanup(self.database.close)

    def add_columns(self, names=None) -> None:
        existing = {row[1] for row in self.writer.execute(f"PRAGMA table_info({TIMEFRAME_TABLE})")}
        for name in names or MOVEMENT_TYPES:
            if name not in existing:
                self.writer.execute(
                    f"ALTER TABLE {TIMEFRAME_TABLE} ADD COLUMN {name} {MOVEMENT_TYPES[name]} DEFAULT 0"
                )
        self.writer.commit()

    def enable_movement(self, run_id: int = 1) -> None:
        self.writer.execute(f"UPDATE {RUN_TABLE} SET input_text=? WHERE id=?", (MOVEMENT_PROFILE, run_id))
        self.writer.commit()

    def save_movement(self, frame: int = 5, **changes) -> None:
        values = {
            "is_price_movement_valid": 1, "price_movement_level": 3,
            "price_movement_average_range_pips": 4.5, "price_movement_reference_atr_pips": 3.0,
            "price_movement_activity_ratio": 1.5, "is_price_movement_spread_valid": 1,
            "price_movement_range_spread_ratio": 4.5, "price_movement_reference_bar_time": BASE_TIME,
        }
        values.update(changes)
        assignments = ", ".join(f"{name}=?" for name in values)
        self.writer.execute(
            f"UPDATE {TIMEFRAME_TABLE} SET {assignments} WHERE observation_id=? AND time_frame=?",
            (*values.values(), self.identifier, frame),
        )
        self.writer.commit()

    def frames(self, identifier: int | None = None, run_id: int = 1):
        identifier = identifier or self.identifier
        listing = self.database.observations(query(runId=run_id))
        listed = next(item for item in listing["items"] if item["id"] == identifier)
        detail = self.database.detail(identifier)
        self.assertEqual(listed["timeframes"], detail["timeframes"])
        json.dumps(detail, allow_nan=False)
        self.assertNotIn("input_text", detail["run"])
        self.assertNotIn("private=secret", json.dumps(detail))
        return detail["timeframes"]

    def test_missing_and_partial_columns_remain_unrecorded(self) -> None:
        self.enable_movement()
        for names in ((), ("is_price_movement_valid", "price_movement_activity_ratio")):
            if names:
                self.add_columns(names)
            before = self.path.read_bytes()
            for frame in self.frames():
                self.assertEqual("UNRECORDED", frame["price_movement_status"])
                self.assertIs(False, frame["is_price_movement_valid"])
                self.assertIsNone(frame["price_movement_activity_ratio"])
            self.assertEqual(before, self.path.read_bytes())

    def test_migrated_legacy_and_new_failed_runs_stay_distinct(self) -> None:
        self.add_columns()
        add_run(self.writer, 2)
        newer = add_observation(self.writer, BASE_TIME + 300, run_id=2)
        self.enable_movement(2)
        before = self.path.read_bytes()
        self.assertEqual({"UNRECORDED"}, {frame["price_movement_status"] for frame in self.frames()})
        self.assertEqual({"UNAVAILABLE"}, {
            frame["price_movement_status"] for frame in self.frames(newer, 2)
        })
        self.assertEqual("READY", self.database.metadata({})["status"])
        self.assertNotIn("private=secret", json.dumps(self.database.metadata({})))
        self.assertEqual(before, self.path.read_bytes())

    def test_valid_zero_saved_level_and_optional_spread_are_preserved(self) -> None:
        self.add_columns()
        self.enable_movement()
        self.save_movement(price_movement_average_range_pips=0.0,
                           price_movement_activity_ratio=0.0, price_movement_range_spread_ratio=0.0)
        self.save_movement(15, is_price_movement_spread_valid=1, price_movement_range_spread_ratio=None)
        frames = {frame["time_frame"]: frame for frame in self.frames()}
        for frame_id in (5, 15):
            self.assertEqual("VALID", frames[frame_id]["price_movement_status"])
            self.assertIs(True, frames[frame_id]["is_price_movement_valid"])
        self.assertEqual(3, frames[5]["price_movement_level"])
        self.assertEqual(0.0, frames[5]["price_movement_activity_ratio"])
        self.assertEqual(0.0, frames[5]["price_movement_range_spread_ratio"])
        self.assertIs(True, frames[5]["is_price_movement_spread_valid"])
        self.assertIs(False, frames[15]["is_price_movement_spread_valid"])
        self.assertIsNone(frames[15]["price_movement_range_spread_ratio"])
        self.assertEqual("UNAVAILABLE", frames[16385]["price_movement_status"])

    def test_invalid_movement_does_not_hide_other_timeframe_analysis(self) -> None:
        self.add_columns()
        self.enable_movement()
        for changes in (
            {"is_price_movement_valid": 2}, {"price_movement_activity_ratio": float("inf")},
            {"price_movement_average_range_pips": None}, {"price_movement_reference_atr_pips": 0.0},
            {"price_movement_level": 4}, {"price_movement_reference_bar_time": 0},
        ):
            with self.subTest(changes=changes):
                self.save_movement(**changes)
                frame = self.frames()[-1]
                self.assertEqual("UNAVAILABLE", frame["price_movement_status"])
                self.assertIs(False, frame["is_price_movement_valid"])
                self.assertIsNone(frame["price_movement_activity_ratio"])
                self.assertEqual(1.25, frame["latest_point_rate"])
                self.assertEqual(1, frame["point_count"])

    def test_missing_optional_run_input_text_is_legacy(self) -> None:
        self.add_columns()
        self.writer.execute(f"ALTER TABLE {RUN_TABLE} DROP COLUMN input_text")
        self.writer.commit()
        self.assertEqual({"UNRECORDED"}, {frame["price_movement_status"] for frame in self.frames()})

    def test_added_data_does_not_add_queries_or_modify_the_database(self) -> None:
        add_observation(self.writer, BASE_TIME + 300)
        self.writer.commit()
        statements = []

        def capture(connection, cursor, statement, parameters, context, many):
            statements.append(statement.strip())

        event.listen(self.database.engine, "before_cursor_execute", capture)
        self.frames()
        legacy_count = len(statements)
        self.add_columns()
        self.enable_movement()
        self.save_movement()
        statements.clear()
        before = self.path.read_bytes()
        self.frames()
        self.assertEqual(legacy_count, len(statements))
        self.assertEqual(before, self.path.read_bytes())


if __name__ == "__main__":
    unittest.main()
