"""Fixture-only SQLite integration tests for optional alert correction snapshots."""

from __future__ import annotations

import http.client
import json
import re
import sqlite3
import tempfile
import threading
import unittest
from contextlib import closing
from pathlib import Path

from sqlalchemy import event, text
from sqlalchemy.exc import SQLAlchemyError

from app import AlertDatabase, RequestError, ViewerServer
from alert_corrections import CORRECTION_TABLE, TIME_FRAME_TABLE, POINT_TABLE, TIME_FRAMES

ROOT = Path(__file__).resolve().parents[2]
DAO = ROOT / "Include" / "Mstng" / "Database" / "Dao"
ORIGINAL_TIME_FRAME_TABLE = "zigzag_elliot_alert_timeframes"
ORIGINAL_POINT_TABLE = "zigzag_elliot_alert_points"
TABLE_DAOS = {
    "zigzag_elliot_alert_runs": "ZigZagElliotAlertRunDao.mqh",
    "zigzag_elliot_alerts": "ZigZagElliotAlertDao.mqh",
    ORIGINAL_TIME_FRAME_TABLE: "ZigZagElliotAlertTimeFrameDao.mqh",
    ORIGINAL_POINT_TABLE: "ZigZagElliotAlertPointDao.mqh",
    CORRECTION_TABLE: "ZigZagElliotAlertCorrectionDao.mqh",
    TIME_FRAME_TABLE: "ZigZagElliotAlertTimeFrameDao.mqh",
    POINT_TABLE: "ZigZagElliotAlertPointDao.mqh",
}


def production_columns(filename: str) -> dict[str, str]:
    """Use real MQL DAO columns while allowing malformed values in corruption fixtures."""
    source = (DAO / filename).read_text(encoding="utf-8-sig")
    start = source.index("bool createTable(")
    end = source.index("return true;", start)
    return dict(re.findall(r'sql \+= "([a-z_0-9]+) (INTEGER|REAL|TEXT)', source[start:end]))


def empty_row(columns: dict[str, str]) -> dict[str, object]:
    row: dict[str, object] = {}
    for name, kind in columns.items():
        row[name] = ""
        if kind == "INTEGER":
            row[name] = 0
        elif kind == "REAL":
            row[name] = 0.0
    return row


def insert_row(connection: sqlite3.Connection, table: str, row: dict[str, object]) -> None:
    fields = ",".join(row)
    connection.execute(f"INSERT INTO {table} ({fields}) VALUES ({','.join('?' for _ in row)})", tuple(row.values()))


def create_correction_database(path: Path, include_corrections: bool = True) -> None:
    """Build six synthetic alert variants, suitable for the full viewer and browser QA."""
    columns = {table: production_columns(dao) for table, dao in TABLE_DAOS.items()}
    with closing(sqlite3.connect(path)) as connection, connection:
        connection.execute("PRAGMA journal_mode=WAL")
        for table, definitions in columns.items():
            if not include_corrections and table in {CORRECTION_TABLE, TIME_FRAME_TABLE, POINT_TABLE}:
                continue
            declarations = []
            for name, kind in definitions.items():
                declaration = f"{name} {kind}"
                if name == "id" or (table == CORRECTION_TABLE and name == "alert_id"):
                    declaration += " PRIMARY KEY"
                declarations.append(declaration)
            connection.execute(f"CREATE TABLE {table} ({','.join(declarations)})")
        run = empty_row(columns["zigzag_elliot_alert_runs"])
        run.update(id=1, run_uid="correction-viewer-fixture", schema_version=7, source_mode="LIVE",
                   source="ZIGZAG_ELLIOT", program_name="ZigZagElliot", program_version="1.44",
                   strategy="MTF_3in3", strategy_version="MTF3IN3_M5_CORRECTED_WAVES_V12",
                   analysis_version="fixture", analysis_input_hash="a" * 64,
                   started_at_text="2026.09.19 12:00:00")
        run = {key: value for key, value in run.items() if key in columns["zigzag_elliot_alert_runs"]}
        insert_row(connection, "zigzag_elliot_alert_runs", run)
        for alert_id, state, side, changed in (
            (1, "APPLIED", "BUY", 16385), (2, "APPLIED", "SELL", 16388),
            (3, "NONE", "BUY", 0), (4, "UNRECORDED", "BUY", 0),
            (5, "INCOMPLETE", "BUY", 16385), (6, "NONE", "SELL", 0),
        ):
            is_buy = int(side == "BUY")
            is_applied = state in {"APPLIED", "INCOMPLETE"}
            current_frame = 5
            frame_list = TIME_FRAMES
            if alert_id == 6:
                current_frame = 16385
                frame_list = TIME_FRAMES[:5]
            reference_time = 1789819200 + alert_id * 300
            original_lc0 = 1.08
            original_lc5 = 1.0795
            corrected_lc0 = 1.09
            corrected_lc5 = 1.0895
            if not is_buy:
                original_lc0 = 1.12
                original_lc5 = 1.1205
                corrected_lc0 = 1.11
                corrected_lc5 = 1.1105
            selected_label = "3"
            if is_applied:
                selected_label = "1"
            alert = empty_row(columns["zigzag_elliot_alerts"])
            alert.update(id=alert_id, run_id=1, event_uid=f"fixture-{alert_id}",
                         market_signal_key=f"fixture-{alert_id}", snapshot_hash=f"hash-{alert_id}",
                         server_time=reference_time, jst_time=reference_time + 21600,
                         current_bar_time=reference_time, signal_reference_point_time=reference_time - 600,
                         symbol_name="EURUSD", time_frame=current_frame, time_frame_text=frame_list[-1][1],
                         strategy="MTF_3in3", side=side, is_judge=1, is_alert=1, is_entry=1,
                         is_entry_wave=1, signal_count=1, entry_count=1, is_entry_count_match=1,
                         is_entry_evaluated=1, entry_result="ENTRY", current_elliot_label=selected_label,
                         reference_price=1.1, is_stop_loss_available=1, stop_loss=original_lc5,
                         risk_pips=abs(1.1-original_lc5)*10000, spread_pips=1.2,
                         alert_title=f"fixture {state}", alert_text="original waves", h1_structure_rank="A",
                         server_time_text="2026.09.19 12:00:00", jst_time_text="2026.09.19 18:00:00",
                         current_bar_time_text="2026.09.19 12:00:00", created_at=reference_time,
                         created_at_text="2026.09.19 12:00:00")
            insert_row(connection, "zigzag_elliot_alerts", alert)
            for corrected in (False, True):
                if corrected and (not is_applied or not include_corrections):
                    continue
                tf_table = ORIGINAL_TIME_FRAME_TABLE
                point_table = ORIGINAL_POINT_TABLE
                if corrected:
                    tf_table = TIME_FRAME_TABLE
                    point_table = POINT_TABLE
                for order, (time_frame, label) in enumerate(frame_list):
                    timeframe_id = alert_id * 100 + order + 1
                    direction = is_buy
                    if time_frame == changed and not corrected:
                        direction = 1 - is_buy
                    direction_label = "SELL"
                    if direction == 1:
                        direction_label = "BUY"
                    latest_label = "3"
                    if corrected:
                        latest_label = "1"
                    timeframe = empty_row(columns[tf_table])
                    timeframe.update(id=timeframe_id, alert_id=alert_id, time_frame=time_frame,
                                     time_frame_text=label, time_frame_order=order,
                                     is_current_time_frame=int(time_frame == current_frame), is_buy=direction,
                                     buy_sell_label=direction_label, wave_count=1, latest_wave_index=0,
                                     point_count=2, latest_elliot_index=int(latest_label), latest_elliot_label=latest_label,
                                     latest_sub_elliot_index=0, latest_sub_elliot_label="",
                                     is_ema200_buy=is_buy, is_ema200_sell=1-is_buy,
                                     raw_csv_text="synthetic", created_at=reference_time)
                    insert_row(connection, tf_table, timeframe)
                    for point_order in range(2):
                        rate = original_lc0
                        point_time = reference_time - 600 + point_order * 300
                        if corrected:
                            rate = corrected_lc0
                            point_time += 60
                        point_label = "2"
                        if point_order == 1:
                            point_label = latest_label
                        point = empty_row(columns[point_table])
                        point.update(id=timeframe_id * 10 + point_order, alert_timeframe_id=timeframe_id,
                                     point_order=point_order, is_latest=int(point_order == 1),
                                     is_signal_reference=int(time_frame == current_frame and point_order == 0),
                                     rate=rate, bar_time=point_time, bar_time_text="2026.09.19 11:50:00",
                                     elliot_index=int(point_label), elliot_label=point_label,
                                     sub_elliot_index=0, sub_elliot_label="", created_at=reference_time)
                        insert_row(connection, point_table, point)
            if include_corrections and state != "UNRECORDED":
                metadata = empty_row(columns[CORRECTION_TABLE])
                metadata.update(alert_id=alert_id, correction_status="NONE", selected_analysis="ORIGINAL",
                                selected_alert_text="original waves", selected_current_elliot_label=selected_label,
                                selected_wave_summary_text="MN1 ... current", reference_price=1.1,
                                is_selected_stop_loss_available=1, selected_stop_loss=original_lc5,
                                selected_risk_pips=alert["risk_pips"], original_lc0=original_lc0,
                                original_lc5=original_lc5, original_lc10=original_lc5, original_lc15=original_lc5,
                                original_loss_cut_diff_pips=200.0, original_loss_cut_diff_jpy=10.0,
                                original_analysis_text="original full analysis", comparison_hash=f"compare-{alert_id}",
                                created_at=reference_time, created_at_text="2026.09.19 12:00:00")
                if is_applied:
                    original_direction = "SELL"
                    if side == "SELL":
                        original_direction = "BUY"
                    metadata.update(correction_status="APPLIED", correction_time_frame=changed,
                                    original_direction=original_direction, corrected_direction=side,
                                    selected_analysis="CORRECTED", selected_alert_text=f"selected [{dict(TIME_FRAMES)[changed]}補正]",
                                    selected_stop_loss=corrected_lc5, selected_risk_pips=abs(1.1-corrected_lc5)*10000,
                                    corrected_lc0=corrected_lc0, corrected_lc5=corrected_lc5,
                                    corrected_lc10=corrected_lc5, corrected_lc15=corrected_lc5,
                                    corrected_loss_cut_diff_pips=100.0, corrected_loss_cut_diff_jpy=5.0,
                                    corrected_reference_point_time=reference_time-540,
                                    corrected_analysis_text="corrected full analysis", corrected_elliot_csv_text="corrected csv")
                insert_row(connection, CORRECTION_TABLE, metadata)
            if state == "INCOMPLETE" and include_corrections:
                connection.execute(f"DELETE FROM {TIME_FRAME_TABLE} WHERE alert_id = ? AND time_frame = 32769", (alert_id,))


class AlertCorrectionsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "fixture.sqlite"
        create_correction_database(self.path)
        self.database = AlertDatabase(self.path)
        self.database.validate()

    def tearDown(self) -> None:
        self.database.close()
        self.temporary.cleanup()

    def update(self, sql: str, parameters: tuple = ()) -> None:
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute(sql, parameters)

    def correction(self, alert_id: int = 1) -> dict:
        return self.database.alert_detail(alert_id)["correction"]

    def test_applied_both_directions_and_table_local_ids(self) -> None:
        for alert_id, side, frame in ((1, "BUY", 16385), (2, "SELL", 16388)):
            with self.subTest(side=side):
                result = self.correction(alert_id)
                self.assertEqual("APPLIED", result["status"])
                self.assertIsNone(result["reason"])
                self.assertEqual(32, len(result["metadata"]))
                self.assertEqual(frame, result["metadata"]["correction_time_frame"])
                self.assertIs(True, result["metadata"]["is_selected_stop_loss_available"])
                self.assertEqual(7, len(result["timeframes"]))
                self.assertEqual(14, len(result["points"]))
                self.assertTrue(all(row["alert_id"] == alert_id for row in result["points"]))
                self.assertEqual("1", result["timeframes"][-1]["latest_elliot_label"])
                self.assertEqual("3", self.database.timeframes(alert_id)["items"][-1]["latest_elliot_label"])
                self.assertIs(True, result["timeframes"][-1]["is_ema200_available"])

    def test_none_legacy_and_incomplete_are_distinct(self) -> None:
        for alert_id, expected in ((3, "NONE"), (4, "UNRECORDED"), (5, "INCOMPLETE"), (6, "NONE")):
            with self.subTest(status=expected, alert=alert_id):
                result = self.correction(alert_id)
                self.assertEqual(expected, result["status"])
                self.assertEqual([], result["timeframes"])
                self.assertEqual([], result["points"])
        self.assertIsNone(self.correction(4)["metadata"])
        self.assertIn("7時間足", self.correction(5)["reason"])

    def test_old_database_without_optional_tables_is_unchanged(self) -> None:
        path = Path(self.temporary.name) / "legacy.sqlite"
        create_correction_database(path, include_corrections=False)
        before = path.read_bytes()
        database = AlertDatabase(path)
        try:
            database.validate()
            self.assertEqual("UNRECORDED", database.alert_detail(1)["correction"]["status"])
            self.assertEqual(7, self.database.timeframes(1)["count"])
            with database.connect() as connection:
                with self.assertRaises(SQLAlchemyError):
                    connection.execute(text("UPDATE zigzag_elliot_alerts SET side='SELL'"))
        finally:
            database.close()
        self.assertEqual(before, path.read_bytes())

    def test_missing_schema_and_missing_children_are_incomplete(self) -> None:
        mutations = (
            f"DROP TABLE {POINT_TABLE}",
            f"ALTER TABLE {TIME_FRAME_TABLE} DROP COLUMN point_count",
            f"ALTER TABLE {CORRECTION_TABLE} DROP COLUMN selected_stop_loss",
        )
        for index, sql in enumerate(mutations):
            with self.subTest(sql=sql):
                copy = Path(self.temporary.name) / f"broken-{index}.sqlite"
                create_correction_database(copy)
                with closing(sqlite3.connect(copy)) as connection, connection:
                    connection.execute(sql)
                database = AlertDatabase(copy)
                try:
                    database.validate()
                    result = database.alert_detail(1)["correction"]
                    self.assertEqual("INCOMPLETE", result["status"])
                    self.assertEqual([], result["timeframes"])
                finally:
                    database.close()
                    copy.unlink(missing_ok=True)

    def test_mutated_snapshots_never_fallback_to_original(self) -> None:
        mutations = (
            (CORRECTION_TABLE, "selected_stop_loss=9", "alert_id=1"),
            (CORRECTION_TABLE, "reference_price=9", "alert_id=1"),
            (CORRECTION_TABLE, "selected_risk_pips=-1", "alert_id=1"),
            (CORRECTION_TABLE, "correction_time_frame=15", "alert_id=1"),
            (CORRECTION_TABLE, "correction_status='FAILED'", "alert_id=1"),
            (CORRECTION_TABLE, "selected_analysis='ORIGINAL'", "alert_id=1"),
            (CORRECTION_TABLE, "corrected_direction='SELL'", "alert_id=1"),
            (CORRECTION_TABLE, "corrected_reference_point_time=1", "alert_id=1"),
            (TIME_FRAME_TABLE, "is_buy=0,buy_sell_label='SELL'", "alert_id=1 AND time_frame=16408"),
            (TIME_FRAME_TABLE, "point_count=3", "alert_id=1 AND time_frame=5"),
            (POINT_TABLE, "is_latest=0", "alert_timeframe_id=107"),
            (POINT_TABLE, "is_latest=1", "alert_timeframe_id=107"),
            (POINT_TABLE, "is_signal_reference=0", "alert_timeframe_id=107"),
            (POINT_TABLE, "point_order=3", "id=1071"),
            (POINT_TABLE, "alert_timeframe_id=201", "id=1071"),
            (POINT_TABLE, "elliot_label='C'", "id=1071"),
        )
        for index, (table, assignment, condition) in enumerate(mutations):
            with self.subTest(table=table, assignment=assignment):
                path = Path(self.temporary.name) / f"mutated-{index}.sqlite"
                create_correction_database(path)
                with closing(sqlite3.connect(path)) as connection, connection:
                    connection.execute(f"UPDATE {table} SET {assignment} WHERE {condition}")
                database = AlertDatabase(path)
                try:
                    database.validate()
                    result = database.alert_detail(1)["correction"]
                    self.assertEqual("INCOMPLETE", result["status"])
                    self.assertTrue(result["reason"])
                    self.assertEqual([], result["timeframes"])
                    self.assertEqual([], result["points"])
                finally:
                    database.close()
                    path.unlink(missing_ok=True)

    def test_nullable_boolean_values_are_not_fabricated(self) -> None:
        self.update(f"UPDATE {TIME_FRAME_TABLE} SET is_ema200_buy=NULL WHERE alert_id=1")
        self.update(f"UPDATE {POINT_TABLE} SET is_added_point=NULL WHERE alert_timeframe_id=107 AND is_latest=1")
        result = self.correction()
        self.assertEqual("APPLIED", result["status"])
        self.assertIsNone(result["timeframes"][-1]["is_ema200_buy"])
        self.assertIsNone(result["timeframes"][-1]["latest_point_is_added"])
        self.assertIsNone(result["points"][-1]["is_added_point"])

    def test_invalid_numeric_metadata_is_not_returned(self) -> None:
        self.update(f"UPDATE {CORRECTION_TABLE} SET selected_risk_pips=? WHERE alert_id=1", (float("inf"),))
        result = self.correction()
        self.assertEqual("INCOMPLETE", result["status"])
        self.assertIsNone(result["metadata"])
        json.dumps(result, allow_nan=False)

    def test_snapshot_is_stable_during_concurrent_writer_commit(self) -> None:
        changed = False
        def commit_after_alert_read(connection, cursor, statement, parameters, context, many):
            nonlocal changed
            del connection, cursor, parameters, context, many
            if not changed and "FROM zigzag_elliot_alerts" in statement and statement.startswith("SELECT"):
                changed = True
                self.update(f"UPDATE {CORRECTION_TABLE} SET selected_alert_text='new snapshot' WHERE alert_id=1")
        event.listen(self.database.engine, "after_cursor_execute", commit_after_alert_read)
        try:
            result = self.correction()
            self.assertTrue(changed)
            self.assertEqual("selected [H1補正]", result["metadata"]["selected_alert_text"])
        finally:
            event.remove(self.database.engine, "after_cursor_execute", commit_after_alert_read)
        self.assertEqual("new snapshot", self.correction()["metadata"]["selected_alert_text"])

    def test_http_contract_and_missing_alert_404(self) -> None:
        server = ViewerServer(("127.0.0.1", 0), self.database, Path(__file__).parent / "static")
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for alert_id, expected in ((1, 200), (999, 404)):
                connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
                try:
                    connection.request("GET", f"/api/alerts/{alert_id}")
                    response = connection.getresponse()
                    body = json.loads(response.read())
                    self.assertEqual(expected, response.status)
                    if expected == 200:
                        self.assertEqual("APPLIED", body["correction"]["status"])
                finally:
                    connection.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)
        with self.assertRaises(RequestError) as error:
            self.database.alert_detail(999)
        self.assertEqual(404, error.exception.status)


if __name__ == "__main__":
    unittest.main()
