"""M5 repository regressions using disposable SQLite fixtures only."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from sqlalchemy import event, text
from sqlalchemy.exc import SQLAlchemyError

from m5_observations import (
    METRIC_COLUMNS, METRICS_TABLE, OBSERVATION_TABLE, RUN_TABLE, TIMEFRAME_TABLE,
    M5ObservationDatabase, M5RequestError,
)


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_TIME = int(datetime(2026, 9, 8, 6, tzinfo=timezone.utc).timestamp())
FRAME_IDS = (49153, 32769, 16408, 16388, 16385, 15, 5)
FRAME_NAMES = ("MN1", "W1", "D1", "H4", "H1", "M15", "M5")


def create_fixture(path: Path, metrics: str = "full") -> sqlite3.Connection:
    """Use the actual writer DDL, not an independently guessed schema."""

    connection = sqlite3.connect(path)
    connection.execute("PRAGMA foreign_keys=ON")
    files = [
        "ZigZagElliotAlertRunDao.mqh", "ZigZagElliotObservationDao.mqh",
        "ZigZagElliotObservationTimeFrameDao.mqh",
    ]
    if metrics == "full":
        files.append("ZigZagElliotObservationCaptureMetricsDao.mqh")
    try:
        for filename in files:
            source = (PROJECT_ROOT / "Include/Mstng/Database/Dao" / filename).read_text(encoding="utf-8-sig")
            beginning = source.index('string sql = "CREATE TABLE')
            ending = source.index('sql += ")";', beginning) + len('sql += ")";')
            fragments = re.findall(r'(?:string sql =|sql \+=) "(.*)";', source[beginning:ending])
            connection.execute("".join(fragments))
        if metrics == "partial":
            connection.execute(f"CREATE TABLE {METRICS_TABLE} (observation_id INTEGER PRIMARY KEY, analysis_elapsed_ms INTEGER)")
    except BaseException:
        connection.close()
        raise
    return connection


def insert_row(connection: sqlite3.Connection, table: str, values: dict[str, object]) -> int:
    """Fill required fixture columns while preserving the writer constraints."""

    row = {}
    for column in connection.execute(f"PRAGMA table_info({table})"):
        name, kind, required, default = column[1:5]
        if name in values:
            row[name] = values[name]
        elif required and default is None:
            row[name] = "" if kind == "TEXT" else 0
    row.update(values)
    names = ", ".join(row)
    placeholders = ", ".join("?" for _ in row)
    cursor = connection.execute(f"INSERT INTO {table} ({names}) VALUES ({placeholders})", list(row.values()))
    return int(cursor.lastrowid)


def add_run(connection: sqlite3.Connection, run_id: int = 1, mode: str = "TESTER", profile: str = "profile1") -> int:
    canonical = "M5_OBSERVATION_PROFILE_V1|" + profile
    return insert_row(connection, RUN_TABLE, {
        "id": run_id, "run_uid": f"fixture-{run_id}", "schema_version": 1,
        "source_mode": mode, "source": "fixture", "source_server": "Fixture-Server",
        "source_login": 123456789, "source_chart_id": 987654321,
        "input_text": "PRIVATE_INPUT_SENTINEL", "input_hash": "PRIVATE_HASH_SENTINEL",
        "program_name": "ZigZagElliotM5ObservationAll", "program_version": "1.02",
        "strategy": "M5_OBSERVATION_ALL", "strategy_version": "M5_OBSERVATION_ALL_V1",
        "analysis_version": "ELLIOT_MN1_V6", "analysis_input_text": canonical,
        "analysis_input_hash": hashlib.sha256(canonical.encode()).hexdigest(),
    })


def add_observation(connection: sqlite3.Connection, jst: int = BASE_TIME, run_id: int = 1,
                    symbol: str = "GBPUSD", metrics: bool = True) -> int:
    run = dict(zip([item[0] for item in connection.execute(f"SELECT * FROM {RUN_TABLE} LIMIT 0").description],
                   connection.execute(f"SELECT * FROM {RUN_TABLE} WHERE id=?", (run_id,)).fetchone()))
    server = jst - 6 * 3600
    stamp = lambda value: datetime.fromtimestamp(value, timezone.utc).strftime("%Y.%m.%d %H:%M:%S")
    identifier = insert_row(connection, OBSERVATION_TABLE, {
        "run_id": run_id, "source_mode": run["source_mode"], "source_server": run["source_server"],
        "symbol_name": symbol, "anchor_time_frame": 5, "anchor_time_frame_text": "M5",
        "anchor_bar_time": server, "anchor_bar_time_text": stamp(server),
        "anchor_jst_time": jst, "anchor_jst_time_text": stamp(jst),
        "capture_phase": "BAR_OPEN_FIRST_SUCCESS", "spread_pips": 0, "pip_size": 0.0001,
        "analysis_version": run["analysis_version"], "analysis_input_hash": run["analysis_input_hash"],
        "snapshot_hash": f"snapshot-{run_id}-{symbol}-{jst}", "time_frame_count": 7,
        "created_at": server, "created_at_text": stamp(server),
    })
    for index, (frame, name) in enumerate(zip(FRAME_IDS, FRAME_NAMES)):
        insert_row(connection, TIMEFRAME_TABLE, {
            "observation_id": identifier, "time_frame": frame, "time_frame_text": name,
            "time_frame_order": index, "is_anchor_time_frame": int(frame == 5),
            "is_buy": int(frame == 5), "point_count": 1,
            "latest_point_time": server, "latest_point_time_text": stamp(server),
            "latest_point_jst_time": jst, "latest_point_jst_time_text": stamp(jst),
            "latest_point_rate": 1.25, "latest_point_is_added": None,
            "current_close": 1.25, "previous_close": 1.24,
        })
    tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_schema WHERE type='table'")}
    if metrics and METRICS_TABLE in tables:
        available = {row[1] for row in connection.execute(f"PRAGMA table_info({METRICS_TABLE})")}
        values = {"observation_id": identifier, "quote_tick_time_msc": server * 1000,
                  "capture_market_time": server, "analysis_elapsed_ms": 0,
                  "capture_elapsed_ms": 0, "analysis_attempt_count": 1}
        insert_row(connection, METRICS_TABLE, {key: value for key, value in values.items() if key in available})
    return identifier


def query(**values: object) -> dict[str, list[str]]:
    result = {"sourceMode": ["TESTER"], "runId": ["1"],
              "from": ["2026-09-08T06:00"], "to": ["2026-09-09T06:00"]}
    result.update({key: [str(value)] for key, value in values.items()})
    return result


class M5ObservationDatabaseTest(unittest.TestCase):
    """Check purpose protection, exact streams and nullable display contracts."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="m5-viewer-test-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "observations.sqlite"
        self.writer = create_fixture(self.path)
        self.addCleanup(self.writer.close)
        add_run(self.writer)
        self.identifier = add_observation(self.writer)
        self.writer.commit()
        self.database = M5ObservationDatabase(self.path)
        self.addCleanup(self.database.close)

    def assert_error(self, status: int, function, *args) -> None:
        with self.assertRaises(M5RequestError) as captured:
            function(*args)
        self.assertEqual(status, captured.exception.status)

    def test_m15_filters_before_count_and_pagination_without_filling_gaps(self) -> None:
        for minute in (5, 10, 15, 20, 30, 60):
            add_observation(self.writer, BASE_TIME + minute * 60)
        add_observation(self.writer, BASE_TIME + 15 * 60, symbol="EURUSD")
        self.writer.commit()
        before = self.path.read_bytes()
        result = self.database.observations(query(displayInterval=15, symbol="GBPUSD", pageSize=2, page=2, order="asc"))
        self.assertEqual((4, 2, 2), (result["total"], result["total_pages"], result["page"]))
        self.assertEqual([BASE_TIME + 1800, BASE_TIME + 3600], [row["anchor_jst_time"] for row in result["items"]])
        self.assertEqual(5, self.database.observations(query(displayInterval=15))["total"])
        self.assertEqual(8, self.database.observations(query())["total"])
        self.assertEqual(2, self.database.observations(query(displayInterval=15, jstTime="06:15"))["total"])
        self.assertEqual(1, self.database.observations(query(displayInterval=15, to="2026-09-08T06:15"))["total"])
        self.assertEqual(before, self.path.read_bytes())

    def test_m15_navigation_keeps_stream_and_skips_non_boundary_observations(self) -> None:
        nearby = add_observation(self.writer, BASE_TIME + 600)
        middle = add_observation(self.writer, BASE_TIME + 900)
        add_observation(self.writer, BASE_TIME + 1200)
        later = add_observation(self.writer, BASE_TIME + 2700)
        add_observation(self.writer, BASE_TIME + 1800, symbol="EURUSD")
        add_run(self.writer, 2)
        add_observation(self.writer, BASE_TIME + 1800, run_id=2)
        self.writer.commit()
        navigation = self.database.detail(middle, {"displayInterval": ["15"]})["navigation"]
        self.assertEqual(self.identifier, navigation["older"]["id"])
        self.assertEqual(later, navigation["newer"]["id"])
        self.assertEqual(1800, navigation["newer"]["gap_seconds"])
        self.assertEqual(nearby, self.database.detail(middle)["navigation"]["older"]["id"])
        self.assertIsNone(self.database.detail(later, {"displayInterval": ["15"]})["navigation"]["newer"])

    def test_display_interval_validation(self) -> None:
        for value in ("", "0", "10", "15.0", "M15", "15 OR 1=1"):
            self.assert_error(400, self.database.observations, query(displayInterval=value))
            self.assert_error(400, self.database.detail, self.identifier, {"displayInterval": [value]})
        self.assert_error(400, self.database.observations, query(displayInterval=15, jstTime="06:05"))
        self.assert_error(400, self.database.detail, self.identifier, {"displayInterval": ["5", "15"]})

    def test_metadata_chooses_latest_nonempty_not_newer_empty_run(self) -> None:
        add_run(self.writer, 2)
        add_run(self.writer, 3, "LIVE")
        add_observation(self.writer, run_id=3)
        self.writer.commit()
        metadata = self.database.metadata({})
        self.assertTrue(metadata["available"])
        self.assertEqual("READY", metadata["status"])
        self.assertEqual(1, metadata["effectiveRunId"])
        self.assertEqual([3, 2, 1], [row["id"] for row in metadata["runs"]])
        self.assertEqual(["GBPUSD"], metadata["symbols"])
        self.assertEqual({"first": BASE_TIME, "last": BASE_TIME}, metadata["range"])
        self.assertEqual(3, self.database.metadata({"sourceMode": ["LIVE"]})["effectiveRunId"])
        empty = self.database.metadata({"runId": ["2"]})
        self.assertEqual(2, empty["effectiveRunId"])
        self.assertEqual("EMPTY", empty["status"])
        self.assertEqual({"first": None, "last": None}, empty["range"])

    def test_previous_motive_sub_legacy_and_migrated_values_are_read_only(self) -> None:
        before = self.path.read_bytes()
        self.assertTrue(all(row["previous_motive_sub_elliot_index"] is None
                            for row in self.database.detail(self.identifier)["timeframes"]))
        self.assertEqual(before, self.path.read_bytes())
        migration = (PROJECT_ROOT / "Include/Mstng/Database/Dao/ZigZagElliotObservationPreviousMotiveSubMigration.mqh").read_text(encoding="utf-8-sig")
        body = migration.split('string sql = "ALTER TABLE', 1)[1].split("ResetLastError();", 1)[0]
        statement = "ALTER TABLE" + "".join(re.findall(r'(?:^|sql \+= )"?([^"\r\n]*)";', body))
        self.writer.execute(statement)
        self.writer.commit()
        self.assertTrue(all(row["previous_motive_sub_elliot_index"] is None
                            for row in self.database.detail(self.identifier)["timeframes"]))
        expected = [0, 1, 3, None, 0, 1, 3]
        for order, value in enumerate(expected):
            self.writer.execute(f"UPDATE {TIMEFRAME_TABLE} SET previous_motive_sub_elliot_index=? WHERE time_frame_order=?", (value, order))
        self.writer.commit()
        before = self.path.read_bytes()
        detail_rows = self.database.detail(self.identifier)["timeframes"]
        list_rows = self.database.observations(query())["items"][0]["timeframes"]
        for rows in (detail_rows, list_rows):
            self.assertEqual([row["previous_motive_sub_elliot_index"] for row in rows], expected)
        self.assertEqual(before, self.path.read_bytes())

    def test_metadata_has_no_run_and_no_implicit_live_fallback(self) -> None:
        live = self.database.metadata({"sourceMode": ["LIVE"]})
        self.assertIsNone(live["effectiveRunId"])
        self.assertEqual("EMPTY", live["status"])
        self.writer.execute(f"DELETE FROM {RUN_TABLE}")
        self.writer.commit()
        empty = self.database.metadata({})
        self.assertTrue(empty["available"])
        self.assertEqual([], empty["runs"])

    def test_all_empty_runs_choose_latest_matching_mode(self) -> None:
        self.writer.execute(f"DELETE FROM {OBSERVATION_TABLE}")
        add_run(self.writer, 2)
        self.writer.commit()
        self.assertEqual(2, self.database.metadata({})["effectiveRunId"])

    def test_metadata_explicit_run_errors_do_not_fallback(self) -> None:
        self.assert_error(404, self.database.metadata, {"runId": ["999"]})
        self.assert_error(400, self.database.metadata, {"sourceMode": ["LIVE"], "runId": ["1"]})

    def test_run_sensitive_fields_are_never_returned(self) -> None:
        for result in (self.database.metadata({}), self.database.detail(self.identifier)):
            rendered = json.dumps(result)
            for private in ("source_login", "source_chart_id", "PRIVATE_INPUT_SENTINEL", "PRIVATE_HASH_SENTINEL"):
                self.assertNotIn(private, rendered)

    def test_missing_and_unconfigured_database_are_not_created(self) -> None:
        missing = Path(self.directory.name) / "not-created.sqlite"
        database = M5ObservationDatabase(missing)
        self.addCleanup(database.close)
        self.assertEqual("NOT_FOUND", database.metadata({})["status"])
        self.assertFalse(missing.exists())
        self.assertEqual("NOT_CONFIGURED", M5ObservationDatabase(None).metadata({})["status"])
        self.assert_error(503, database.observations, query())

    def test_new_file_and_schema_are_revalidated_without_restart(self) -> None:
        path = Path(self.directory.name) / "later.sqlite"
        database = M5ObservationDatabase(path)
        self.addCleanup(database.close)
        self.assertEqual("NOT_FOUND", database.metadata({})["status"])
        with closing(create_fixture(path)) as writer:
            add_run(writer)
            writer.commit()
        self.assertEqual("EMPTY", database.metadata({})["status"])
        with closing(sqlite3.connect(path)) as writer:
            writer.execute(f"ALTER TABLE {TIMEFRAME_TABLE} RENAME COLUMN is_buy TO missing_buy")
            writer.commit()
        self.assertEqual("UNSUPPORTED", database.metadata({})["status"])

    def test_non_sqlite_and_unrelated_schema_are_unsupported_and_unchanged(self) -> None:
        path = Path(self.directory.name) / "unrelated.sqlite"
        with closing(sqlite3.connect(path)) as writer:
            writer.execute("CREATE TABLE unrelated(value TEXT)")
            writer.commit()
        database = M5ObservationDatabase(path)
        self.addCleanup(database.close)
        original = path.read_bytes()
        self.assertEqual("UNSUPPORTED", database.metadata({})["status"])
        self.assertEqual(original, path.read_bytes())
        database.close()
        path.write_bytes(b"Not a SQLite database. " * 200)
        original = path.read_bytes()
        self.assertEqual("UNSUPPORTED", database.metadata({})["status"])
        self.assertEqual(original, path.read_bytes())

    def test_h1_run_without_observations_is_rejected_without_mutation(self) -> None:
        self.writer.execute(f"DELETE FROM {OBSERVATION_TABLE}")
        self.writer.execute(f"UPDATE {RUN_TABLE} SET strategy='H1_OBSERVATION_ALL'")
        self.writer.commit()
        before = self.path.read_bytes()
        self.assertEqual("UNSUPPORTED", self.database.metadata({})["status"])
        self.assertEqual(before, self.path.read_bytes())
        self.assertFalse(Path(str(self.path) + "-wal").exists())
        self.assertFalse(Path(str(self.path) + "-shm").exists())

    def test_mixed_anchor_and_unknown_profile_are_rejected(self) -> None:
        self.writer.execute(f"UPDATE {OBSERVATION_TABLE} SET anchor_time_frame=16385")
        self.writer.commit()
        self.assertEqual("UNSUPPORTED", self.database.metadata({})["status"])
        self.writer.execute(f"UPDATE {OBSERVATION_TABLE} SET anchor_time_frame=5")
        self.writer.execute(f"UPDATE {RUN_TABLE} SET analysis_input_text='H1_PROFILE'")
        self.writer.commit()
        self.assertEqual("UNSUPPORTED", self.database.metadata({})["status"])

    def test_parent_run_profile_mismatch_is_rejected(self) -> None:
        self.writer.execute(f"UPDATE {OBSERVATION_TABLE} SET analysis_input_hash='another'")
        self.writer.commit()
        self.assertEqual("UNSUPPORTED", self.database.metadata({})["status"])
        self.assert_error(503, self.database.detail, self.identifier)

    def test_query_only_connection_blocks_write(self) -> None:
        with self.database.engine.connect() as connection:
            self.assertEqual(1, connection.exec_driver_sql("PRAGMA query_only").scalar_one())
            self.assertEqual(5000, connection.exec_driver_sql("PRAGMA busy_timeout").scalar_one())
            with self.assertRaises(SQLAlchemyError):
                connection.execute(text(f"DELETE FROM {OBSERVATION_TABLE}"))

    def test_page_is_half_open_and_uses_stored_jst(self) -> None:
        second = add_observation(self.writer, BASE_TIME + 300)
        add_observation(self.writer, BASE_TIME + 600)
        self.writer.commit()
        result = self.database.observations(query(to="2026-09-08T06:10"))
        self.assertEqual(2, result["total"])
        self.assertEqual([second, self.identifier], [row["id"] for row in result["items"]])
        self.assertEqual(7, len(result["items"][0]["timeframes"]))
        self.assertEqual(list(FRAME_IDS), [row["time_frame"] for row in result["items"][0]["timeframes"]])

    def test_exact_five_minute_clock_across_days(self) -> None:
        add_observation(self.writer, BASE_TIME + 3300)
        add_observation(self.writer, BASE_TIME + 86400 + 3300)
        self.writer.commit()
        result = self.database.observations(query(jstTime="06:55", to="2026-09-10T06:00"))
        self.assertEqual(2, result["total"])

    def test_bad_dates_modes_and_h1_filters_are_rejected(self) -> None:
        for key, value in (
            ("from", "2026-09-08"), ("from", "2026-09-08T06:01"),
            ("from", "2026-09-08T06:00Z"), ("from", "2026-02-30T06:00"),
            ("to", "2026-09-08T06:00"), ("jstTime", "06:01"), ("jstTime", "24:00"),
            ("sourceMode", "all"), ("groupMode", "SIGNAL"), ("fullAlignment", "BUY"),
            ("syncTimeFrame", "H1"), ("sort", "id; DROP TABLE x"), ("order", "other"),
            ("runId", "0"), ("page", "-1"), ("pageSize", "0"),
        ):
            with self.subTest(key=key, value=value):
                self.assert_error(400, self.database.observations, query(**{key: value}))
        missing = query()
        del missing["from"]
        self.assert_error(400, self.database.observations, missing)
        duplicate = query()
        duplicate["runId"] = ["1", "2"]
        self.assert_error(400, self.database.observations, duplicate)

    def test_sql_injection_symbol_is_only_a_literal_filter(self) -> None:
        result = self.database.observations(query(symbol="GBPUSD' OR 1=1 --"))
        self.assertEqual(0, result["total"])
        self.assertEqual(1, self.database.observations(query())["total"])

    def test_global_sorts_and_out_of_range_page(self) -> None:
        second = add_observation(self.writer, BASE_TIME + 300)
        third = add_observation(self.writer, BASE_TIME + 300, symbol="AUDUSD")
        self.writer.commit()
        result = self.database.observations(query(sort="symbol_name", order="asc", pageSize=1))
        self.assertEqual(third, result["items"][0]["id"])
        result = self.database.observations(query(order="asc", pageSize=1, page=2))
        self.assertEqual(second, result["items"][0]["id"])
        result = self.database.observations(query(order="asc", pageSize=1, page=999999999999))
        self.assertEqual(3, result["page"])
        self.assertEqual(third, result["items"][0]["id"])
        self.assertEqual(200, self.database.observations(query(pageSize=1000))["page_size"])

    def test_empty_search_returns_page_one(self) -> None:
        result = self.database.observations(query(symbol="NONE", page=10))
        self.assertEqual((0, 1, 0, []), (result["total"], result["page"], result["total_pages"], result["items"]))

    def test_capture_null_zero_missing_row_and_raw_numeric_values(self) -> None:
        self.writer.execute(f"UPDATE {METRICS_TABLE} SET quote_tick_time_msc=NULL")
        self.writer.commit()
        detail = self.database.detail(self.identifier)
        self.assertIsNone(detail["captureMetrics"]["quote_tick_time_msc"])
        self.assertEqual(0, detail["captureMetrics"]["analysis_elapsed_ms"])
        self.assertEqual(0, detail["observation"]["spread_pips"])
        self.assertEqual(0, detail["timeframes"][4]["is_buy"])
        self.assertEqual(1, detail["timeframes"][6]["is_buy"])
        self.writer.execute(f"DELETE FROM {METRICS_TABLE}")
        self.writer.commit()
        item = self.database.observations(query())["items"][0]
        self.assertIsNone(item["captureMetrics"])
        self.assertEqual({"tableAvailable": True, "rowAvailable": False, "missingColumns": []}, item["captureMetricsState"])

    def test_absent_and_partial_metrics_are_compatible(self) -> None:
        for mode in ("absent", "partial"):
            with self.subTest(mode=mode):
                path = Path(self.directory.name) / (mode + ".sqlite")
                with closing(create_fixture(path, mode)) as writer:
                    add_run(writer)
                    identifier = add_observation(writer)
                    writer.commit()
                database = M5ObservationDatabase(path)
                self.addCleanup(database.close)
                result = database.detail(identifier)
                self.assertEqual(mode == "partial", result["captureMetricsState"]["tableAvailable"])
                if mode == "partial":
                    self.assertEqual(0, result["captureMetrics"]["analysis_elapsed_ms"])
                    self.assertIsNone(result["captureMetrics"]["capture_elapsed_ms"])
                    self.assertEqual(4, len(result["captureMetricsState"]["missingColumns"]))
                else:
                    self.assertIsNone(result["captureMetrics"])
                    self.assertEqual(list(METRIC_COLUMNS), result["captureMetricsState"]["missingColumns"])

    def test_invalid_quality_clock_is_not_clamped_or_replaced(self) -> None:
        self.writer.execute(f"UPDATE {METRICS_TABLE} SET capture_market_time=capture_market_time-1")
        self.writer.commit()
        detail = self.database.detail(self.identifier)
        self.assertEqual(-1, detail["captureMetrics"]["capture_market_time"] - detail["observation"]["anchor_bar_time"])

    def test_missing_timeframes_are_returned_without_hiding_parent(self) -> None:
        self.writer.execute(f"DELETE FROM {TIMEFRAME_TABLE} WHERE time_frame=15")
        self.writer.commit()
        self.assertEqual(6, len(self.database.detail(self.identifier)["timeframes"]))
        self.assertEqual(1, self.database.observations(query())["total"])

    def test_navigation_stays_in_same_run_and_profile(self) -> None:
        add_run(self.writer, 2, profile="other")
        add_observation(self.writer, BASE_TIME + 300, run_id=2)
        other_symbol = add_observation(self.writer, BASE_TIME + 300, symbol="AUDUSD")
        next_id = add_observation(self.writer, BASE_TIME + 900)
        self.writer.commit()
        detail = self.database.detail(self.identifier)
        self.assertIsNone(detail["navigation"]["older"])
        self.assertEqual(next_id, detail["navigation"]["newer"]["id"])
        self.assertEqual(900, detail["navigation"]["newer"]["gap_seconds"])
        self.assertIsNone(self.database.detail(other_symbol)["navigation"]["older"])
        self.assertEqual(self.identifier, self.database.detail(next_id)["navigation"]["older"]["id"])

    def test_detail_id_errors_and_cross_database_identity(self) -> None:
        self.assert_error(404, self.database.detail, 999)
        for identifier in (0, -1, 1 << 64, True):
            self.assert_error(400, self.database.detail, identifier)
        key = self.database.metadata({})["database"]["key"]
        self.assertEqual(key, self.database.detail(self.identifier, {"databaseKey": [key]})["databaseKey"])
        self.assert_error(409, self.database.detail, self.identifier, {"databaseKey": ["other"]})
        other = M5ObservationDatabase(self.path)
        self.addCleanup(other.close)
        self.assert_error(409, other.detail, self.identifier, {"databaseKey": [key]})

    def test_list_has_batched_children_and_one_read_transaction(self) -> None:
        add_observation(self.writer, BASE_TIME + 300)
        self.writer.commit()
        statements = []
        def capture(connection, cursor, statement, parameters, context, many):
            statements.append(statement.strip())
        event.listen(self.database.engine, "before_cursor_execute", capture)
        result = self.database.observations(query())
        self.assertEqual(2, result["total"])
        self.assertEqual(1, sum(statement == "BEGIN" for statement in statements))
        self.assertEqual(1, sum(f"SELECT * FROM {TIMEFRAME_TABLE}" in statement for statement in statements))
        self.assertEqual(1, sum(f"FROM {METRICS_TABLE}\n" in statement for statement in statements))
        self.assertFalse(any(re.search(r"\b(INSERT|UPDATE|DELETE|CREATE|ALTER|VACUUM|checkpoint)\b", statement, re.I) for statement in statements))

    def test_live_wal_reads_recent_commit_without_checkpoint(self) -> None:
        self.writer.execute("PRAGMA journal_mode=WAL")
        next_id = add_observation(self.writer, BASE_TIME + 300)
        self.writer.commit()
        wal = Path(str(self.path) + "-wal")
        before_main = self.path.read_bytes()
        before_wal = wal.read_bytes()
        self.assertEqual(next_id, self.database.observations(query())["items"][0]["id"])
        self.assertEqual(before_main, self.path.read_bytes())
        self.assertEqual(before_wal, wal.read_bytes())
        self.assertEqual("wal", self.writer.execute("PRAGMA journal_mode").fetchone()[0])

    def test_sql_error_and_timeout_are_not_reported_as_zero(self) -> None:
        with patch.object(self.database, "_validate", side_effect=SQLAlchemyError("locked")):
            self.assert_error(503, self.database.metadata, {})
            self.assert_error(503, self.database.observations, query())
        for index in range(1, 40):
            add_observation(self.writer, BASE_TIME + index * 300)
        self.writer.commit()
        with patch("m5_observations.QUERY_TIMEOUT_SECONDS", -1):
            self.assert_error(503, self.database.observations, query())


if __name__ == "__main__":
    unittest.main()
