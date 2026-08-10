"""HTTP routing tests for the local alert viewer."""

from __future__ import annotations

import base64
import http.client
import json
import re
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from app import (
    AlertDatabase,
    DEFAULT_HOST,
    MAX_TIME_FRAME_FILTERS,
    RequestError,
    ViewerServer,
    W1_TIME_FRAME,
)


class StubDatabase:
    """Provide the read-only health contract needed by route tests."""

    def validate(self) -> dict[str, object]:
        """Return deterministic health metadata."""

        return {
            "database": "stub.sqlite",
            "journal_mode": "wal",
            "alert_count": 0,
        }

    def summary(self, query: dict[str, list[str]]) -> dict[str, object]:
        """Return the alert-summary response contract used by the route."""

        del query
        return {
            "total_count": 2,
            "database_total_count": 3,
            "buy_count": 1,
            "sell_count": 1,
            "w1_aligned_count": 1,
            "w1_mismatched_count": 1,
            "w1_unknown_count": 0,
            "run_count": 1,
            "symbol_count": 2,
        }

    def observation_options(self) -> dict[str, object]:
        """Return the missing-table contract used by the route tests."""

        return {"available": False, "symbols": []}

    def observations(self, query: dict[str, list[str]]) -> dict[str, object]:
        """Return a deterministic empty observation page."""

        del query
        return {
            "available": False,
            "items": [],
            "total": 0,
            "page": 1,
            "page_size": 50,
            "page_count": 0,
        }

    def observation_summary(
        self,
        query: dict[str, list[str]],
    ) -> dict[str, object]:
        """Return a deterministic empty observation summary."""

        del query
        return {
            "available": False,
            "total_count": 0,
            "run_count": 0,
            "symbol_count": 0,
        }

    def observation_detail(self, observation_id: int) -> dict[str, object]:
        """Return the missing-table detail contract."""

        del observation_id
        return {
            "available": False,
            "observation": None,
            "time_frames": [],
        }


class ViewerRouteTest(unittest.TestCase):
    """Verify the standard, compatibility and fallback viewer routes."""

    server: ViewerServer
    server_thread: threading.Thread
    port: int

    @classmethod
    def setUpClass(cls) -> None:
        """Start an isolated HTTP server on an operating-system assigned port."""

        static_path = Path(__file__).resolve().parent / "static"
        cls.server = ViewerServer((DEFAULT_HOST, 0), StubDatabase(), static_path)  # type: ignore[arg-type]
        cls.port = int(cls.server.server_address[1])
        cls.server_thread = threading.Thread(
            target=cls.server.serve_forever,
            name="viewer-route-test",
            daemon=True,
        )
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        """Stop the isolated server and release its socket."""

        cls.server.shutdown()
        cls.server.server_close()
        cls.server_thread.join(timeout=5)

    def get(
        self,
        path: str,
        host: str | None = None,
    ) -> tuple[int, dict[str, str], bytes]:
        """Perform a local GET with an explicitly controlled Host header."""

        connection = http.client.HTTPConnection(DEFAULT_HOST, self.port, timeout=5)
        request_host = host or f"{DEFAULT_HOST}:{self.port}"
        connection.request("GET", path, headers={"Host": request_host})
        response = connection.getresponse()
        payload = response.read()
        headers = {key.lower(): value for key, value in response.getheaders()}
        status = response.status
        connection.close()
        return status, headers, payload

    def assert_security_headers(self, headers: dict[str, str]) -> None:
        """Check headers shared by every viewer page and generated asset."""

        self.assertEqual("no-store", headers.get("cache-control"))
        self.assertEqual("nosniff", headers.get("x-content-type-options"))
        self.assertIn("default-src 'self'", headers.get("content-security-policy", ""))

    def assert_react_nonce(
        self,
        headers: dict[str, str],
        payload: bytes,
    ) -> str:
        """Verify one request-scoped nonce across HTML and its CSP header."""

        html = payload.decode("utf-8")
        self.assertNotIn("__CSP_NONCE__", html)
        nonce_match = re.search(
            r'<meta property="csp-nonce" nonce="([A-Za-z0-9+/=]+)">',
            html,
        )
        self.assertIsNotNone(nonce_match)
        assert nonce_match is not None
        nonce = nonce_match.group(1)
        self.assertEqual(16, len(base64.b64decode(nonce, validate=True)))
        nonce_values = re.findall(r' nonce="([A-Za-z0-9+/=]+)"', html)
        self.assertGreaterEqual(len(nonce_values), 3)
        self.assertTrue(all(value == nonce for value in nonce_values))
        content_security_policy = headers.get("content-security-policy", "")
        self.assertIn(f"style-src-elem 'self' 'nonce-{nonce}'", content_security_policy)
        self.assertIn("style-src-attr 'unsafe-inline'", content_security_policy)
        self.assertNotIn("script-src 'unsafe-inline'", content_security_policy)
        self.assertNotIn("script-src 'unsafe-eval'", content_security_policy)
        return nonce

    def test_react_is_standard_and_compatibility_view(self) -> None:
        """Serve the same React build from root and the existing React aliases."""

        paths = [
            "/",
            "/index.html",
            "/react",
            "/react/",
            "/react/index.html",
            "/?runId=7&side=BUY",
        ]
        for path in paths:
            with self.subTest(path=path):
                status, headers, payload = self.get(path)
                html = payload.decode("utf-8")
                self.assertEqual(200, status)
                self.assertIn('<html lang="ja" class="react-viewer-page">', html)
                self.assertIn('<body class="react-viewer">', html)
                self.assertIn('<div id="root"></div>', html)
                self.assertNotIn('id="filterForm"', html)
                self.assert_security_headers(headers)
                self.assert_react_nonce(headers, payload)

        first_status, first_headers, first_payload = self.get("/")
        second_status, second_headers, second_payload = self.get("/")
        self.assertEqual(200, first_status)
        self.assertEqual(200, second_status)
        self.assertNotEqual(
            self.assert_react_nonce(first_headers, first_payload),
            self.assert_react_nonce(second_headers, second_payload),
        )

    def test_legacy_view_remains_available(self) -> None:
        """Keep the previous interface as an immediate operational fallback."""

        paths = [
            "/legacy",
            "/legacy/",
            "/legacy/index.html",
            "/legacy/?q=wave",
        ]
        for path in paths:
            with self.subTest(path=path):
                status, headers, payload = self.get(path)
                html = payload.decode("utf-8")
                self.assertEqual(200, status)
                self.assertIn('id="filterForm"', html)
                self.assertIn('<script src="/app.js" defer></script>', html)
                self.assertIn('href="/">React版へ戻る</a>', html)
                self.assert_security_headers(headers)
                self.assertNotIn('property="csp-nonce"', html)
                self.assertNotIn(
                    "style-src-attr 'unsafe-inline'",
                    headers.get("content-security-policy", ""),
                )

    def test_generated_asset_and_shared_legacy_assets_are_served(self) -> None:
        """Resolve the hashed React asset while preserving shared legacy files."""

        root_status, _, root_payload = self.get("/")
        self.assertEqual(200, root_status)
        asset_match = re.search(
            rb'src="(/react/assets/index-[A-Za-z0-9_-]+\.js)"',
            root_payload,
        )
        self.assertIsNotNone(asset_match)
        assert asset_match is not None
        asset_path = asset_match.group(1).decode("ascii")
        asset_status, asset_headers, asset_payload = self.get(asset_path)
        self.assertEqual(200, asset_status)
        self.assertGreater(len(asset_payload), 0)
        self.assertTrue(
            asset_headers.get("content-type", "").startswith("text/javascript")
        )
        self.assert_security_headers(asset_headers)

        for path, content_type in [
            ("/app.js", "text/javascript"),
            ("/styles.css", "text/css"),
        ]:
            with self.subTest(path=path):
                status, headers, payload = self.get(path)
                self.assertEqual(200, status)
                self.assertGreater(len(payload), 0)
                self.assertTrue(headers.get("content-type", "").startswith(content_type))

    def test_security_boundaries_and_health_remain_active(self) -> None:
        """Reject non-local hosts and attempts to escape the React asset root."""

        invalid_host_status, _, _ = self.get("/", host="example.com")
        self.assertEqual(400, invalid_host_status)

        for path in [
            "/react/assets/%2e%2e/%2e%2e/app.py",
            "/react/assets/%5capp.js",
        ]:
            with self.subTest(path=path):
                status, _, _ = self.get(path)
                self.assertEqual(404, status)

        health_status, health_headers, health_payload = self.get("/api/health")
        self.assertEqual(200, health_status)
        self.assertTrue(
            health_headers.get("content-type", "").startswith("application/json")
        )
        self.assertEqual("ok", json.loads(health_payload)["status"])

    def test_observation_routes_expose_the_optional_table_contract(self) -> None:
        """Route all H1 APIs even before the optional tables have been created."""

        paths = [
            "/api/observations",
            "/api/observation-summary",
            "/api/observation-options",
            "/api/observations/1",
        ]
        for path in paths:
            with self.subTest(path=path):
                status, headers, payload = self.get(path)
                result = json.loads(payload)
                self.assertEqual(200, status)
                self.assertFalse(result["available"])
                self.assertTrue(
                    headers.get("content-type", "").startswith("application/json")
                )

    def test_alert_summary_exposes_filtered_and_database_totals(self) -> None:
        """Expose the filtered count together with the unfiltered DB count."""

        status, headers, payload = self.get("/api/summary?sourceMode=LIVE")
        result = json.loads(payload)

        self.assertEqual(200, status)
        self.assertTrue(
            headers.get("content-type", "").startswith("application/json")
        )
        self.assertEqual(2, result["total_count"])
        self.assertEqual(3, result["database_total_count"])


class AlertFilterTest(unittest.TestCase):
    """Verify filters shared by alert lists, summaries and CSV export."""

    def test_single_time_frame_keeps_the_existing_bound_filter(self) -> None:
        """Keep one timeFrame query compatible with the original contract."""

        filters = AlertDatabase.parse_filters({"timeFrame": [" H1 "]})

        self.assertIn(
            "a.time_frame_text = :time_frame_text",
            filters.where_sql,
        )
        self.assertEqual({"time_frame_text": "H1"}, filters.parameters)

    def test_multiple_time_frames_are_deduplicated_and_bound(self) -> None:
        """Build an IN predicate using only internal parameter identifiers."""

        unsafe_value = "M5') OR 1=1 --"
        filters = AlertDatabase.parse_filters(
            {
                "timeFrame": [
                    " H1 ",
                    "",
                    "H1",
                    unsafe_value,
                    " M5 ",
                    "   ",
                ]
            }
        )

        self.assertIn(
            "a.time_frame_text IN ("
            ":time_frame_text_0, :time_frame_text_1, :time_frame_text_2)",
            filters.where_sql,
        )
        self.assertNotIn(unsafe_value, filters.where_sql)
        self.assertEqual(
            {
                "time_frame_text_0": "H1",
                "time_frame_text_1": unsafe_value,
                "time_frame_text_2": "M5",
            },
            filters.parameters,
        )

    def test_empty_time_frames_do_not_add_a_filter(self) -> None:
        """Treat repeated empty values as no time-frame selection."""

        filters = AlertDatabase.parse_filters(
            {"timeFrame": ["", " ", "\t"]}
        )

        self.assertNotIn("time_frame_text", filters.where_sql)
        self.assertEqual({}, filters.parameters)

    def test_excessive_unique_time_frames_are_rejected(self) -> None:
        """Bound the number of generated SQL parameters."""

        time_frames = [
            f"TF{index}" for index in range(MAX_TIME_FRAME_FILTERS + 1)
        ]

        with self.assertRaisesRegex(
            RequestError,
            f"timeFrame must have at most {MAX_TIME_FRAME_FILTERS} values",
        ):
            AlertDatabase.parse_filters({"timeFrame": time_frames})

    def test_source_mode_is_bound_as_a_run_filter(self) -> None:
        """Filter LIVE and TESTER data through the parent run source mode."""

        live_filters = AlertDatabase.parse_filters({"sourceMode": ["LIVE"]})
        self.assertIn("r.source_mode = :source_mode", live_filters.where_sql)
        self.assertEqual("LIVE", live_filters.parameters["source_mode"])

        tester_filters = AlertDatabase.parse_filters({"sourceMode": ["tester"]})
        self.assertIn("r.source_mode = :source_mode", tester_filters.where_sql)
        self.assertEqual("TESTER", tester_filters.parameters["source_mode"])

        run_filters = AlertDatabase.parse_filters(
            {"sourceMode": ["LIVE"], "runId": ["7"]}
        )
        self.assertIn("r.source_mode = :source_mode", run_filters.where_sql)
        self.assertIn("a.run_id = :run_id", run_filters.where_sql)
        self.assertEqual({"source_mode": "LIVE", "run_id": 7}, run_filters.parameters)

    def test_all_source_modes_do_not_add_a_clause(self) -> None:
        """Keep the existing all-run query when the mode is omitted or all."""

        for query in ({}, {"sourceMode": ["all"]}):
            with self.subTest(query=query):
                filters = AlertDatabase.parse_filters(query)
                self.assertNotIn("r.source_mode", filters.where_sql)
                self.assertNotIn("source_mode", filters.parameters)

    def test_unsupported_source_mode_is_rejected(self) -> None:
        """Reject unrecognized modes instead of silently widening results."""

        with self.assertRaisesRegex(
            RequestError,
            "sourceMode must be LIVE, TESTER or all",
        ):
            AlertDatabase.parse_filters(
                {"sourceMode": ["LIVE' OR 1=1 --"]}
            )


def create_alert_summary_database(database_path: Path) -> None:
    """Create the columns read by the production alert-summary CTE."""

    run_columns = [
        "id INTEGER PRIMARY KEY",
        "run_uid TEXT",
        "source_mode TEXT",
        "program_name TEXT",
        "program_version TEXT",
        "strategy_version TEXT",
        "analysis_version TEXT",
        "tester_model TEXT",
    ]
    alert_column_names = [
        "event_uid",
        "market_signal_key",
        "server_time",
        "server_time_text",
        "jst_time",
        "jst_time_text",
        "current_bar_time",
        "current_bar_time_text",
        "signal_reference_point_time",
        "signal_reference_point_time_text",
        "symbol_name",
        "time_frame",
        "time_frame_text",
        "magic_number",
        "strategy",
        "side",
        "is_judge",
        "signal_count",
        "entry_count",
        "is_entry_count_match",
        "is_entry_evaluated",
        "is_alert",
        "is_entry",
        "entry_result",
        "is_send_mail",
        "current_elliot_label",
        "is_entry_wave",
        "close_ema200_diff_pips",
        "max_close_ema200_diff_pips",
        "is_ema200_distance_within",
        "spread_pips",
        "is_currency_strength_enabled",
        "currency_strength_status",
        "is_currency_strength_available",
        "base_currency",
        "base_long_medium_rank",
        "base_medium_short_rank",
        "quote_currency",
        "quote_long_medium_rank",
        "quote_medium_short_rank",
        "long_medium_rank_difference",
        "medium_short_rank_difference",
        "reference_price",
        "is_stop_loss_available",
        "stop_loss",
        "risk_pips",
        "h1_structure_rank",
        "is_h1_structure_valid",
        "is_h1_structure_late",
        "is_h1_direction_exception",
        "alert_title",
        "wave_summary_text",
        "created_at",
        "created_at_text",
    ]
    alert_columns = [
        "id INTEGER PRIMARY KEY",
        "run_id INTEGER",
        *(f"{column_name} TEXT" for column_name in alert_column_names),
    ]
    time_frame_columns = [
        "id INTEGER PRIMARY KEY",
        "alert_id INTEGER",
        "time_frame INTEGER",
        "time_frame_text TEXT",
        "is_buy INTEGER",
        "buy_sell_label TEXT",
        "latest_elliot_label TEXT",
        "latest_sub_elliot_label TEXT",
        "is_wave_confirmed INTEGER",
        "is_wave_motive INTEGER",
        "is_wave_uptrend INTEGER",
        "wave_trend_label TEXT",
    ]

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "CREATE TABLE zigzag_elliot_alert_runs ("
            + ",".join(run_columns)
            + ")"
        )
        connection.execute(
            "CREATE TABLE zigzag_elliot_alerts ("
            + ",".join(alert_columns)
            + ")"
        )
        connection.execute(
            "CREATE TABLE zigzag_elliot_alert_timeframes ("
            + ",".join(time_frame_columns)
            + ")"
        )
        connection.executemany(
            """
            INSERT INTO zigzag_elliot_alert_runs (
                id, run_uid, source_mode, program_name, program_version,
                strategy_version, analysis_version, tester_model
            ) VALUES (?, ?, ?, 'ZigZagElliot', '1.23', '1', '1', '')
            """,
            [(1, "run-live", "LIVE"), (2, "run-tester", "TESTER")],
        )
        connection.executemany(
            """
            INSERT INTO zigzag_elliot_alerts (
                id, run_id, symbol_name, side, time_frame_text,
                strategy, h1_structure_rank
            ) VALUES (?, ?, ?, ?, 'H1', 'MTF_3in3', 'A')
            """,
            [
                (1, 1, "EURUSD", "BUY"),
                (2, 1, "GBPUSD", "SELL"),
                (3, 2, "USDJPY", "SELL"),
            ],
        )
        connection.executemany(
            """
            INSERT INTO zigzag_elliot_alert_timeframes (
                id, alert_id, time_frame, time_frame_text, is_buy,
                buy_sell_label
            ) VALUES (?, ?, ?, 'W1', ?, ?)
            """,
            [
                (1, 1, W1_TIME_FRAME, 1, "BUY"),
                (2, 2, W1_TIME_FRAME, 1, "BUY"),
            ],
        )
    connection.close()


class AlertSummaryTest(unittest.TestCase):
    """Verify filtered metrics and the unfiltered database total contract."""

    def test_database_total_is_unfiltered_even_for_zero_matches(self) -> None:
        """Keep the global total independent from every search predicate."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_alert_summary_database(database_path)
            database = AlertDatabase(database_path)
            try:
                all_summary = database.summary({})
                filtered_summary = database.summary(
                    {
                        "sourceMode": ["LIVE"],
                        "symbol": ["EURUSD"],
                        "side": ["BUY"],
                    }
                )
                zero_summary = database.summary(
                    {"sourceMode": ["TESTER"], "symbol": ["EURUSD"]}
                )
                unknown_summary = database.summary(
                    {"sourceMode": ["TESTER"]}
                )
            finally:
                database.close()

        self.assertEqual(3, all_summary["total_count"])
        self.assertEqual(3, all_summary["database_total_count"])
        self.assertEqual(1, filtered_summary["total_count"])
        self.assertEqual(3, filtered_summary["database_total_count"])
        self.assertEqual(1, filtered_summary["w1_aligned_count"])
        self.assertEqual(0, zero_summary["total_count"])
        self.assertEqual(3, zero_summary["database_total_count"])
        self.assertEqual(1, unknown_summary["total_count"])
        self.assertEqual(1, unknown_summary["w1_unknown_count"])
        self.assertEqual(3, unknown_summary["database_total_count"])


def create_observation_database(database_path: Path) -> None:
    """Create a compact SQLite fixture matching the H1 read contract."""

    run_columns = [
        "id INTEGER PRIMARY KEY",
        "run_uid TEXT",
        "schema_version INTEGER",
        "source_mode TEXT",
        "source TEXT",
        "program_name TEXT",
        "program_version TEXT",
        "strategy TEXT",
        "strategy_version TEXT",
        "analysis_version TEXT",
        "source_server TEXT",
        "source_login INTEGER",
        "source_chart_id INTEGER",
        "terminal_build INTEGER",
        "tester_from INTEGER",
        "tester_to INTEGER",
        "tester_model TEXT",
        "input_hash TEXT",
        "started_at INTEGER",
        "started_at_text TEXT",
        "market_started_at INTEGER",
        "market_started_at_text TEXT",
        "created_at INTEGER",
        "created_at_text TEXT",
    ]
    observation_columns = [
        "id INTEGER PRIMARY KEY",
        "run_id INTEGER",
        "source_mode TEXT",
        "source_server TEXT",
        "symbol_name TEXT",
        "anchor_time_frame INTEGER",
        "anchor_time_frame_text TEXT",
        "anchor_bar_time INTEGER",
        "anchor_bar_time_text TEXT",
        "capture_phase TEXT",
        "analysis_version TEXT",
        "analysis_input_hash TEXT",
        "snapshot_hash TEXT",
        "time_frame_count INTEGER",
        "created_at INTEGER",
        "created_at_text TEXT",
    ]
    time_frame_column_names = [
        "id",
        "observation_id",
        "time_frame",
        "time_frame_text",
        "time_frame_order",
        "is_anchor_time_frame",
        "is_buy",
        "buy_sell_label",
        "wave_count",
        "latest_wave_index",
        "is_wave_confirmed",
        "is_wave_motive",
        "is_wave_uptrend",
        "wave_trend_label",
        "previous_last_elliot_label",
        "point_count",
        "latest_elliot_index",
        "latest_elliot_label",
        "latest_sub_elliot_index",
        "latest_sub_elliot_label",
        "latest_point_time",
        "latest_point_time_text",
        "latest_point_rate",
        "current_close",
        "stochastic_main_order_text",
        "stochastic_main_direction_text",
        "gmma_trend_count",
        "gmma_cross_count",
        "ema30_ema60_diff_pips",
        "atr14_pips",
        "ema200_slope_pips",
        "ema200_close_diff_pips",
        "ema200_trend_count",
        "is_ema200_buy",
        "is_ema200_sell",
        "created_at",
        "created_at_text",
    ]
    text_columns = {
        "time_frame_text",
        "buy_sell_label",
        "wave_trend_label",
        "previous_last_elliot_label",
        "latest_elliot_label",
        "latest_sub_elliot_label",
        "latest_point_time_text",
        "stochastic_main_order_text",
        "stochastic_main_direction_text",
        "created_at_text",
    }
    real_columns = {
        "latest_point_rate",
        "current_close",
        "ema30_ema60_diff_pips",
        "atr14_pips",
        "ema200_slope_pips",
        "ema200_close_diff_pips",
    }
    time_frame_columns = []
    for column_name in time_frame_column_names:
        column_type = "INTEGER"
        if column_name in text_columns:
            column_type = "TEXT"
        elif column_name in real_columns:
            column_type = "REAL"
        primary_key = " PRIMARY KEY" if column_name == "id" else ""
        time_frame_columns.append(f"{column_name} {column_type}{primary_key}")

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "CREATE TABLE zigzag_elliot_alert_runs ("
            + ",".join(run_columns)
            + ")"
        )
        connection.execute(
            """
            CREATE TABLE zigzag_elliot_alerts (
                id INTEGER PRIMARY KEY,
                run_id INTEGER,
                side TEXT,
                jst_time INTEGER,
                current_bar_time INTEGER,
                current_bar_time_text TEXT,
                symbol_name TEXT,
                h1_structure_rank TEXT
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE zigzag_elliot_alert_timeframes (
                id INTEGER PRIMARY KEY,
                alert_id INTEGER,
                time_frame INTEGER,
                time_frame_text TEXT,
                is_buy INTEGER,
                buy_sell_label TEXT
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE zigzag_elliot_alert_points (
                id INTEGER PRIMARY KEY,
                alert_timeframe_id INTEGER,
                point_order INTEGER
            )
            """
        )
        connection.execute(
            "CREATE TABLE zigzag_elliot_observations ("
            + ",".join(observation_columns)
            + ")"
        )
        connection.execute(
            "CREATE TABLE zigzag_elliot_observation_timeframes ("
            + ",".join(time_frame_columns)
            + ")"
        )
        for run_id, source_mode in [(1, "LIVE"), (2, "TESTER")]:
            connection.execute(
                """
                INSERT INTO zigzag_elliot_alert_runs (
                    id, run_uid, schema_version, source_mode, source,
                    program_name, program_version, strategy,
                    strategy_version, analysis_version, source_server,
                    started_at, started_at_text, created_at, created_at_text
                ) VALUES (
                    :id, :run_uid, 1, :source_mode, 'ZigZagElliot',
                    'ZigZagElliot', '1.23', 'MTF 3in3',
                    '1', '1', 'OANDA-Demo',
                    1704067200, '2024.01.01 00:00:00',
                    1704067200, '2024.01.01 00:00:00'
                )
                """,
                {
                    "id": run_id,
                    "run_uid": f"run-{run_id}",
                    "source_mode": source_mode,
                },
            )
        connection.executemany(
            """
            INSERT INTO zigzag_elliot_alerts (
                id, run_id, side, jst_time, current_bar_time,
                current_bar_time_text, symbol_name, h1_structure_rank
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (1, 1, "BUY", 1704067200, 1704067200,
                 "2024.01.01 00:00:00", "EURUSD", "A"),
                (2, 1, "BUY", 1704153600, 1704153600,
                 "2024.01.02 00:00:00", "GBPUSD", "A"),
                (3, 2, "SELL", 1704240000, 1704240000,
                 "2024.01.03 00:00:00", "USDJPY", "A"),
            ],
        )
        parent_rows = [
            (1, 1, "LIVE", "EURUSD", 1704067200, "2024.01.01 00:00:00"),
            (2, 1, "LIVE", "GBPUSD", 1704153600, "2024.01.02 00:00:00"),
            (3, 2, "TESTER", "USDJPY", 1704240000, "2024.01.03 00:00:00"),
        ]
        for observation_id, run_id, source_mode, symbol, bar_time, bar_text in parent_rows:
            connection.execute(
                """
                INSERT INTO zigzag_elliot_observations (
                    id, run_id, source_mode, source_server, symbol_name,
                    anchor_time_frame, anchor_time_frame_text,
                    anchor_bar_time, anchor_bar_time_text, capture_phase,
                    analysis_version, analysis_input_hash, snapshot_hash,
                    time_frame_count, created_at, created_at_text
                ) VALUES (
                    :id, :run_id, :source_mode, 'OANDA-Demo', :symbol_name,
                    16385, 'H1', :bar_time, :bar_text,
                    'BAR_OPEN_FIRST_SUCCESS', '1', 'input-hash',
                    :snapshot_hash, 5, :bar_time, :bar_text
                )
                """,
                {
                    "id": observation_id,
                    "run_id": run_id,
                    "source_mode": source_mode,
                    "symbol_name": symbol,
                    "bar_time": bar_time,
                    "bar_text": bar_text,
                    "snapshot_hash": f"snapshot-{observation_id}",
                },
            )
        insert_columns = ",".join(time_frame_column_names)
        insert_parameters = ",".join(
            f":{column_name}" for column_name in time_frame_column_names
        )
        time_frames = ["MN1", "W1", "D1", "H4", "H1"]
        row_id = 0
        for observation_id, _, _, _, bar_time, bar_text in parent_rows:
            for time_frame_order, time_frame_text in enumerate(time_frames):
                row_id += 1
                values: dict[str, object] = {
                    column_name: 0 for column_name in time_frame_column_names
                }
                for column_name in text_columns:
                    values[column_name] = ""
                for column_name in real_columns:
                    values[column_name] = 0.0
                is_buy = observation_id != 3
                values.update(
                    {
                        "id": row_id,
                        "observation_id": observation_id,
                        "time_frame": time_frame_order + 1,
                        "time_frame_text": time_frame_text,
                        "time_frame_order": time_frame_order,
                        "is_anchor_time_frame": int(time_frame_text == "H1"),
                        "is_buy": int(is_buy),
                        "buy_sell_label": "BUY" if is_buy else "SELL",
                        "wave_count": 4,
                        "latest_wave_index": 3,
                        "is_wave_confirmed": 1,
                        "is_wave_motive": 1,
                        "is_wave_uptrend": int(is_buy),
                        "wave_trend_label": "UP" if is_buy else "DOWN",
                        "point_count": 5,
                        "latest_elliot_index": 3,
                        "latest_elliot_label": "3",
                        "latest_sub_elliot_index": 1,
                        "latest_sub_elliot_label": "i",
                        "latest_point_time": bar_time,
                        "latest_point_time_text": bar_text,
                        "latest_point_rate": 1.25,
                        "current_close": 1.24,
                        "stochastic_main_order_text": "S>M>L",
                        "stochastic_main_direction_text": "BUY",
                        "gmma_trend_count": 3,
                        "gmma_cross_count": 2,
                        "ema30_ema60_diff_pips": 12.5,
                        "atr14_pips": 18.2,
                        "ema200_slope_pips": 2.3,
                        "ema200_close_diff_pips": 20.1,
                        "ema200_trend_count": 4,
                        "is_ema200_buy": int(is_buy),
                        "is_ema200_sell": int(not is_buy),
                        "created_at": bar_time,
                        "created_at_text": bar_text,
                    }
                )
                connection.execute(
                    "INSERT INTO zigzag_elliot_observation_timeframes ("
                    + insert_columns
                    + ") VALUES ("
                    + insert_parameters
                    + ")",
                    values,
                )
    connection.close()


class ObservationDatabaseTest(unittest.TestCase):
    """Verify optional-schema behavior and H1 list aggregation."""

    def test_missing_tables_return_available_false_without_sql_errors(self) -> None:
        """Keep Viewer usable before the observation feature creates its tables."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "DROP TABLE zigzag_elliot_observation_timeframes"
                )
                connection.execute("DROP TABLE zigzag_elliot_observations")
                journal_mode = connection.execute(
                    "PRAGMA journal_mode=WAL"
                ).fetchone()[0]
            connection.close()
            database_mtime = database_path.stat().st_mtime_ns
            database = AlertDatabase(database_path)
            try:
                health = database.validate()
                page = database.observations({"pageSize": ["500"]})
                summary = database.observation_summary({})
                options = database.observation_options()
                detail = database.observation_detail(1)
                runs = database.runs()
            finally:
                database.close()
            database_mtime_after_read = database_path.stat().st_mtime_ns
        self.assertEqual("wal", journal_mode)
        self.assertEqual(3, health["alert_count"])
        self.assertFalse(health["observation_available"])
        self.assertEqual(2, runs["count"])
        self.assertEqual(database_mtime, database_mtime_after_read)
        self.assertFalse(page["available"])
        self.assertEqual([], page["items"])
        self.assertEqual(200, page["page_size"])
        self.assertFalse(summary["available"])
        self.assertEqual(0, summary["total_count"])
        self.assertEqual({"available": False, "symbols": [], "source_modes": [],
                          "analysis_versions": []}, options)
        self.assertFalse(detail["available"])

    def test_list_summary_options_detail_and_run_counts(self) -> None:
        """Return one parent per observation and exactly five ordered TF rows."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            database = AlertDatabase(database_path)
            try:
                page = database.observations(
                    {
                        "sourceMode": ["LIVE"],
                        "page": ["1"],
                        "pageSize": ["1"],
                        "sort": ["anchor_bar_time"],
                        "order": ["asc"],
                    }
                )
                clamped_page = database.observations(
                    {
                        "sourceMode": ["LIVE"],
                        "page": ["999"],
                        "pageSize": ["1"],
                        "sort": ["anchor_bar_time"],
                        "order": ["asc"],
                    }
                )
                date_page = database.observations(
                    {"from": ["2024-01-02"], "to": ["2024-01-02"]}
                )
                summary = database.observation_summary({})
                options = database.observation_options()
                detail = database.observation_detail(1)
                with self.assertRaisesRegex(
                    RequestError,
                    "observation was not found",
                ):
                    database.observation_detail(999)
                runs = database.runs()
            finally:
                database.close()
        self.assertTrue(page["available"])
        self.assertEqual(2, page["total"])
        self.assertEqual(2, page["page_count"])
        self.assertEqual("EURUSD", page["items"][0]["symbol_name"])
        self.assertEqual(2, clamped_page["page"])
        self.assertEqual("GBPUSD", clamped_page["items"][0]["symbol_name"])
        self.assertEqual(5, len(page["items"][0]["time_frames"]))
        self.assertEqual(
            ["MN1", "W1", "D1", "H4", "H1"],
            [item["time_frame_text"] for item in page["items"][0]["time_frames"]],
        )
        self.assertTrue(page["items"][0]["time_frames"][4]["is_anchor_time_frame"])
        self.assertEqual(1, date_page["total"])
        self.assertEqual("GBPUSD", date_page["items"][0]["symbol_name"])
        self.assertEqual(3, summary["total_count"])
        self.assertEqual(2, summary["live_count"])
        self.assertEqual(1, summary["tester_count"])
        self.assertEqual(2, summary["run_count"])
        self.assertEqual(["EURUSD", "GBPUSD", "USDJPY"], options["symbols"])
        self.assertTrue(detail["available"])
        self.assertEqual(5, len(detail["time_frames"]))
        run_one = next(item for item in runs["items"] if item["id"] == 1)
        self.assertEqual(2, run_one["alert_count"])
        self.assertEqual(2, run_one["observation_count"])

    def test_filters_are_bound_and_sort_identifiers_are_whitelisted(self) -> None:
        """Use Server-time dates and reject arbitrary SQL sort expressions."""

        filters = AlertDatabase.parse_observation_filters(
            {
                "sourceMode": ["tester"],
                "runId": ["2"],
                "symbol": ["USDJPY"],
                "from": ["2024-01-01"],
                "to": ["2024-01-04"],
            }
        )
        self.assertIn("o.source_mode = :source_mode", filters.where_sql)
        self.assertIn("o.run_id = :run_id", filters.where_sql)
        self.assertIn("o.symbol_name = :symbol_name", filters.where_sql)
        self.assertIn("o.anchor_bar_time >= :from_time", filters.where_sql)
        self.assertIn("o.anchor_bar_time < :to_time", filters.where_sql)
        self.assertEqual("TESTER", filters.parameters["source_mode"])
        with self.assertRaisesRegex(
            RequestError,
            "unsupported observation sort column",
        ):
            AlertDatabase.parse_observation_filters(
                {"sort": ["anchor_bar_time; DROP TABLE x"]}
            )
        with self.assertRaisesRegex(
            RequestError,
            "sourceMode must be LIVE, TESTER or all",
        ):
            AlertDatabase.parse_observation_filters(
                {"sourceMode": ["LIVE' OR 1=1 --"]}
            )


if __name__ == "__main__":
    unittest.main()
