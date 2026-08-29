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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from app import (
    AlertDatabase,
    DEFAULT_HOST,
    GMO_SYMBOL_TARGETS,
    MAX_TIME_FRAME_FILTERS,
    OBSERVATION_REQUIRED_COLUMNS,
    RequestError,
    ViewerServer,
    W1_TIME_FRAME,
    canonical_symbol_name,
    is_gmo_target,
    normalize_allowed_host,
    sqlite_is_consecutive_market_h1,
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
            "navigation": {"older": None, "newer": None},
        }


class AllowedHostTest(unittest.TestCase):
    """Verify exact reverse-proxy Host configuration."""

    def test_allowed_host_is_normalized(self) -> None:
        """Normalize case while retaining an explicit HTTPS port."""

        self.assertEqual(
            "steelers.tail9d1d2a.ts.net:443",
            normalize_allowed_host("STEELERS.TAIL9D1D2A.TS.NET:443"),
        )

    def test_url_wildcard_and_invalid_port_are_rejected(self) -> None:
        """Require one exact HTTP Host authority rather than a URL or pattern."""

        for host in [
            "",
            "https://steelers.tail9d1d2a.ts.net",
            "*.tail9d1d2a.ts.net",
            "user@steelers.tail9d1d2a.ts.net",
            "steelers.tail9d1d2a.ts.net;parameter",
            "steelers.tail9d1d2a.ts.net%2fpath",
            "steelers.tail9d1d2a.ts.net:0",
            "steelers.tail9d1d2a.ts.net:65536",
        ]:
            with self.subTest(host=host), self.assertRaises(ValueError):
                normalize_allowed_host(host)


class ViewerRouteTest(unittest.TestCase):
    """Verify the standard, compatibility and fallback viewer routes."""

    server: ViewerServer
    server_thread: threading.Thread
    port: int

    @classmethod
    def setUpClass(cls) -> None:
        """Start an isolated HTTP server on an operating-system assigned port."""

        static_path = Path(__file__).resolve().parent / "static"
        cls.server = ViewerServer(
            (DEFAULT_HOST, 0),
            StubDatabase(),  # type: ignore[arg-type]
            static_path,
            allowed_hosts=(
                "steelers.tail9d1d2a.ts.net",
                "steelers.tail9d1d2a.ts.net:443",
            ),
        )
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

    def test_explicit_tailscale_serve_hosts_are_allowed(self) -> None:
        """Allow only the configured Tailscale Serve authorities."""

        for host in [
            "steelers.tail9d1d2a.ts.net",
            "STEELERS.TAIL9D1D2A.TS.NET",
            "steelers.tail9d1d2a.ts.net:443",
        ]:
            with self.subTest(host=host):
                status, _, payload = self.get("/api/health", host=host)
                self.assertEqual(200, status)
                self.assertEqual("ok", json.loads(payload)["status"])

        for host in [
            "steelers.tail9d1d2a.ts.net.evil.example",
            "steelers.tail9d1d2a.ts.net:444",
        ]:
            with self.subTest(host=host):
                status, _, _ = self.get("/api/health", host=host)
                self.assertEqual(400, status)

    def test_unconfigured_viewer_keeps_local_only_host_allowlist(self) -> None:
        """Keep Tailscale authorities opt-in for the default server."""

        static_path = Path(__file__).resolve().parent / "static"
        server = ViewerServer(
            (DEFAULT_HOST, 0),
            StubDatabase(),  # type: ignore[arg-type]
            static_path,
        )
        try:
            self.assertNotIn("steelers.tail9d1d2a.ts.net", server.allowed_hosts)
            self.assertIn(DEFAULT_HOST, server.allowed_hosts)
        finally:
            server.server_close()

    def test_second_viewer_cannot_share_the_listening_port(self) -> None:
        """Reject a stale Viewer process attempting to share the same port."""

        static_path = Path(__file__).resolve().parent / "static"
        with self.assertRaises(OSError):
            duplicate_server = ViewerServer(
                (DEFAULT_HOST, self.port),
                StubDatabase(),  # type: ignore[arg-type]
                static_path,
            )
            duplicate_server.server_close()

    def test_viewer_cannot_share_a_legacy_server_port(self) -> None:
        """Reject an older server that does not hold the instance mutex."""

        static_path = Path(__file__).resolve().parent / "static"
        legacy_server = ThreadingHTTPServer(
            (DEFAULT_HOST, 0),
            BaseHTTPRequestHandler,
        )
        legacy_port = int(legacy_server.server_address[1])
        try:
            with self.assertRaises(OSError):
                duplicate_server = ViewerServer(
                    (DEFAULT_HOST, legacy_port),
                    StubDatabase(),  # type: ignore[arg-type]
                    static_path,
                )
                duplicate_server.server_close()
        finally:
            legacy_server.server_close()

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
                if path == "/api/observations/1":
                    self.assertEqual(
                        {"older": None, "newer": None},
                        result["navigation"],
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

    def test_w1_confirmation_filters_use_exact_persisted_values(self) -> None:
        """Bind exact state values and normalize the two mode aliases."""

        filters = AlertDatabase.parse_filters(
            {
                "w1ConfirmationState": [" EMA_CONFLICT "],
                "w1ConfirmationMode": ["OR"],
            }
        )

        self.assertIn(
            "w1_confirmation_state = :w1_confirmation_state",
            filters.derived_where_sql,
        )
        self.assertIn(
            "w1_confirmation_mode = :w1_confirmation_mode",
            filters.derived_where_sql,
        )
        self.assertEqual("EMA_CONFLICT", filters.parameters["w1_confirmation_state"])
        self.assertEqual(
            "DIRECTION_OR_EMA200",
            filters.parameters["w1_confirmation_mode"],
        )

    def test_unknown_w1_confirmation_state_is_rejected(self) -> None:
        """Do not collapse persisted states into ambiguous UI-only groups."""

        with self.assertRaisesRegex(RequestError, "exact persisted W1 state"):
            AlertDatabase.parse_filters(
                {"w1ConfirmationState": ["CONFLICT"]}
            )

    def test_h1_direction_alignment_filters_use_exact_persisted_values(
        self,
    ) -> None:
        """Bind the new H1 mode and each persisted diagnostic state."""

        mode = "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
        states = (
            "EMA200_FALLBACK_BUY",
            "EMA200_FALLBACK_SELL",
            "MN1_EMA200_MISMATCH",
        )
        for state in states:
            with self.subTest(state=state):
                filters = AlertDatabase.parse_filters(
                    {
                        "h1DirectionAlignmentMode": [f" {mode} "],
                        "h1DirectionAlignmentState": [f" {state} "],
                    }
                )
                self.assertIn(
                    "h1_direction_alignment_mode = :h1_direction_alignment_mode",
                    filters.derived_where_sql,
                )
                self.assertIn(
                    "h1_direction_alignment_state = :h1_direction_alignment_state",
                    filters.derived_where_sql,
                )
                self.assertEqual(
                    mode,
                    filters.parameters["h1_direction_alignment_mode"],
                )
                self.assertEqual(
                    state,
                    filters.parameters["h1_direction_alignment_state"],
                )

    def test_unknown_h1_direction_alignment_values_are_rejected(self) -> None:
        """Reject UI-only or misspelled H1 mode and state names."""

        cases = (
            ({"h1DirectionAlignmentMode": ["MN1_OR_EMA200"]}, "H1 mode"),
            ({"h1DirectionAlignmentState": ["EMA200_FALLBACK"]}, "H1 state"),
        )
        for query, message in cases:
            with self.subTest(query=query):
                with self.assertRaisesRegex(RequestError, message):
                    AlertDatabase.parse_filters(query)


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


def add_alert_ema200_fixture_columns(database_path: Path) -> None:
    """Add EMA200 flags and representative alert timeframe snapshots."""

    current_time_frame = 5
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "ALTER TABLE zigzag_elliot_alert_timeframes "
            "ADD COLUMN is_ema200_buy INTEGER"
        )
        connection.execute(
            "ALTER TABLE zigzag_elliot_alert_timeframes "
            "ADD COLUMN is_ema200_sell INTEGER"
        )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET time_frame = ?, time_frame_text = 'M5'
            """,
            (current_time_frame,),
        )
        connection.execute(
            """
            UPDATE zigzag_elliot_alert_timeframes
            SET is_ema200_buy = CASE WHEN alert_id = 1 THEN 1 ELSE 0 END,
                is_ema200_sell = CASE WHEN alert_id = 2 THEN 1 ELSE 0 END
            WHERE time_frame = ?
            """,
            (W1_TIME_FRAME,),
        )
        connection.executemany(
            """
            INSERT INTO zigzag_elliot_alert_timeframes (
                id, alert_id, time_frame, time_frame_text, is_buy,
                buy_sell_label, is_ema200_buy, is_ema200_sell
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (10, 1, current_time_frame, "M5", 1, "BUY", 1, 0),
                (11, 2, current_time_frame, "M5", 0, "SELL", 0, 1),
                (20, 1, 49153, "MN1", 0, "SELL", 0, 1),
                (21, 1, 16408, "D1", 1, "BUY", 1, 0),
                (22, 1, 16388, "H4", 1, "BUY", 0, 0),
                (23, 2, 16408, "D1", 1, "BUY", 1, 1),
                (24, 2, 16388, "H4", 0, "SELL", 0, 1),
                (25, 1, 16385, "H1", 0, "SELL", 0, 1),
                (26, 2, 16385, "H1", 1, "BUY", 1, 0),
            ],
        )
    connection.close()


def add_w1_confirmation_fixture_columns(database_path: Path) -> None:
    """Add the current optional W1 confirmation contract to an alert fixture."""

    definitions = [
        "w1_confirmation_mode TEXT NOT NULL DEFAULT 'OFF'",
        "w1_confirmation_state TEXT NOT NULL DEFAULT 'NOT_EVALUATED'",
        "is_w1_confirmation_available INTEGER NOT NULL DEFAULT 0",
        "is_w1_confirmation_valid INTEGER NOT NULL DEFAULT 0",
        "is_w1_direction_matched INTEGER NOT NULL DEFAULT 0",
        "w1_ema200_direction TEXT NOT NULL DEFAULT 'NONE'",
        "is_w1_ema200_matched INTEGER NOT NULL DEFAULT 0",
        "is_w1_confirmation_passed INTEGER NOT NULL DEFAULT 1",
    ]
    with sqlite3.connect(database_path) as connection:
        for definition in definitions:
            connection.execute(
                f"ALTER TABLE zigzag_elliot_alerts ADD COLUMN {definition}"
            )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET w1_confirmation_mode = 'DIRECTION_OR_EMA200',
                w1_confirmation_state = 'STRONG',
                is_w1_confirmation_available = 1,
                is_w1_confirmation_valid = 1,
                is_w1_direction_matched = 1,
                w1_ema200_direction = 'BUY',
                is_w1_ema200_matched = 1,
                is_w1_confirmation_passed = 1
            WHERE id = 1
            """
        )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET w1_confirmation_mode = 'OBSERVE_ONLY',
                w1_confirmation_state = 'EMA_ONLY',
                is_w1_confirmation_available = 1,
                is_w1_confirmation_valid = 1,
                is_w1_direction_matched = 0,
                w1_ema200_direction = 'SELL',
                is_w1_ema200_matched = 1,
                is_w1_confirmation_passed = 1
            WHERE id = 2
            """
        )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET w1_confirmation_mode = 'DIRECTION_AND_EMA200',
                w1_confirmation_state = 'UNAVAILABLE',
                is_w1_confirmation_passed = 0
            WHERE id = 3
            """
        )
    connection.close()


def add_h1_direction_alignment_fixture_columns(database_path: Path) -> None:
    """Add the current H1 direction-alignment contract to an alert fixture."""

    definitions = [
        "h1_direction_alignment_mode TEXT NOT NULL DEFAULT 'D1_TO_H1'",
        "h1_direction_alignment_state TEXT NOT NULL DEFAULT 'NOT_EVALUATED'",
        "is_h1_direction_alignment_available INTEGER NOT NULL DEFAULT 0",
        "is_h1_direction_alignment_valid INTEGER NOT NULL DEFAULT 0",
        "h1_direction_alignment_direction TEXT NOT NULL DEFAULT 'NONE'",
        "is_h1_mn1_direction_matched INTEGER NOT NULL DEFAULT 0",
        "is_h1_w1_direction_matched INTEGER NOT NULL DEFAULT 0",
        "is_h1_direction_alignment_passed INTEGER NOT NULL DEFAULT 0",
    ]
    with sqlite3.connect(database_path) as connection:
        for definition in definitions:
            connection.execute(
                f"ALTER TABLE zigzag_elliot_alerts ADD COLUMN {definition}"
            )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET h1_direction_alignment_mode =
                    'W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED',
                h1_direction_alignment_state = 'EMA200_FALLBACK_BUY',
                is_h1_direction_alignment_available = 1,
                is_h1_direction_alignment_valid = 1,
                h1_direction_alignment_direction = 'BUY',
                is_h1_mn1_direction_matched = 0,
                is_h1_w1_direction_matched = 1,
                is_h1_direction_alignment_passed = 1
            WHERE id = 1
            """
        )
        connection.execute(
            """
            UPDATE zigzag_elliot_alerts
            SET h1_direction_alignment_mode = 'MN1_TO_H1_OBSERVE',
                h1_direction_alignment_state = 'MN1_MISMATCH',
                is_h1_direction_alignment_available = 1,
                is_h1_direction_alignment_valid = 1,
                h1_direction_alignment_direction = 'SELL',
                is_h1_mn1_direction_matched = 0,
                is_h1_w1_direction_matched = 1,
                is_h1_direction_alignment_passed = 0
            WHERE id = 2
            """
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


class AlertListEma200Test(unittest.TestCase):
    """Verify current-timeframe EMA200 flags and legacy compatibility."""

    def test_current_schema_projects_current_and_fixed_time_frame_flags(
        self,
    ) -> None:
        """Return independent current and fixed-timeframe EMA200 states."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "current-ema200.sqlite"
            create_alert_summary_database(database_path)
            add_alert_ema200_fixture_columns(database_path)
            database = AlertDatabase(database_path)
            try:
                page = database.alerts({})
                summary = database.summary({})
            finally:
                database.close()

        items = {item["id"]: item for item in page["items"]}
        self.assertEqual(3, page["total"])
        self.assertEqual(3, summary["total_count"])
        self.assertIs(items[1]["is_ema200_available"], True)
        self.assertIs(items[1]["is_ema200_buy"], True)
        self.assertIs(items[1]["is_ema200_sell"], False)
        self.assertIs(items[2]["is_ema200_available"], True)
        self.assertIs(items[2]["is_ema200_buy"], False)
        self.assertIs(items[2]["is_ema200_sell"], True)
        self.assertIs(items[3]["is_ema200_available"], False)
        self.assertIs(items[3]["is_ema200_buy"], False)
        self.assertIs(items[3]["is_ema200_sell"], False)

        expected_alert_one = {
            "mn1": (True, False, True),
            "w1": (True, True, False),
            "d1": (True, True, False),
            "h4": (True, False, False),
            "h1": (True, False, True),
        }
        for time_frame, expected in expected_alert_one.items():
            available, is_buy, is_sell = expected
            self.assertIs(
                items[1][f"{time_frame}_is_ema200_available"],
                available,
            )
            self.assertIs(items[1][f"{time_frame}_is_ema200_buy"], is_buy)
            self.assertIs(items[1][f"{time_frame}_is_ema200_sell"], is_sell)
        self.assertEqual("SELL", items[1]["mn1_side"])
        self.assertEqual("BUY", items[1]["w1_side"])
        self.assertEqual("BUY", items[1]["d1_side"])
        self.assertEqual("BUY", items[1]["h4_side"])
        self.assertEqual("SELL", items[1]["h1_side"])
        self.assertEqual("NONE", items[1]["w1_ema200_direction"])

        self.assertIs(items[2]["mn1_is_ema200_available"], False)
        self.assertIs(items[2]["mn1_is_ema200_buy"], False)
        self.assertIs(items[2]["mn1_is_ema200_sell"], False)
        self.assertIs(items[2]["d1_is_ema200_available"], True)
        self.assertIs(items[2]["d1_is_ema200_buy"], True)
        self.assertIs(items[2]["d1_is_ema200_sell"], True)
        for time_frame in ("mn1", "w1", "d1", "h4", "h1"):
            self.assertIs(
                items[3][f"{time_frame}_is_ema200_available"],
                False,
            )
            self.assertIs(items[3][f"{time_frame}_is_ema200_buy"], False)
            self.assertIs(items[3][f"{time_frame}_is_ema200_sell"], False)

    def test_legacy_schema_projects_unavailable_boolean_flags(self) -> None:
        """Keep list and summary operational when EMA200 columns are absent."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "legacy-ema200.sqlite"
            create_alert_summary_database(database_path)
            database = AlertDatabase(database_path)
            try:
                page = database.alerts({})
                summary = database.summary({})
            finally:
                database.close()

        self.assertEqual(3, page["total"])
        self.assertEqual(3, summary["total_count"])
        for item in page["items"]:
            self.assertIs(item["is_ema200_available"], False)
            self.assertIs(item["is_ema200_buy"], False)
            self.assertIs(item["is_ema200_sell"], False)
            for time_frame in ("mn1", "w1", "d1", "h4", "h1"):
                self.assertIs(
                    item[f"{time_frame}_is_ema200_available"],
                    False,
                )
                self.assertIs(item[f"{time_frame}_is_ema200_buy"], False)
                self.assertIs(item[f"{time_frame}_is_ema200_sell"], False)


class W1ConfirmationApiTest(unittest.TestCase):
    """Verify current W1 diagnostics and legacy read compatibility."""

    def test_legacy_schema_projects_not_evaluated_without_breaking_queries(
        self,
    ) -> None:
        """Expose old databases as Legacy and keep exact filtering available."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "legacy.sqlite"
            create_alert_summary_database(database_path)
            database = AlertDatabase(database_path)
            try:
                page = database.alerts({})
                legacy_page = database.alerts(
                    {"w1ConfirmationState": ["NOT_EVALUATED"]}
                )
                strong_page = database.alerts(
                    {"w1ConfirmationState": ["STRONG"]}
                )
                options = database.options()
                csv_text = database.export_csv({}).decode("utf-8-sig")
            finally:
                database.close()

        self.assertEqual(3, page["total"])
        self.assertEqual(3, legacy_page["total"])
        self.assertEqual(0, strong_page["total"])
        self.assertTrue(page["items"][0]["is_w1_confirmation_legacy"])
        self.assertEqual(
            "NOT_EVALUATED",
            page["items"][0]["w1_confirmation_state"],
        )
        self.assertEqual("OFF", page["items"][0]["w1_confirmation_mode"])
        self.assertFalse(options["w1_confirmation_available"])
        self.assertIn("NOT_EVALUATED", options["w1_confirmation_states"])
        self.assertIn("w1_confirmation_state", csv_text.splitlines()[0])

    def test_current_schema_filters_list_summary_and_csv_by_state_and_mode(
        self,
    ) -> None:
        """Keep list, summary and export on the same exact W1 cohort."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "current.sqlite"
            create_alert_summary_database(database_path)
            add_w1_confirmation_fixture_columns(database_path)
            database = AlertDatabase(database_path)
            query = {
                "w1ConfirmationState": ["EMA_ONLY"],
                "w1ConfirmationMode": ["OBSERVE_ONLY"],
            }
            try:
                page = database.alerts(query)
                summary = database.summary(query)
                csv_text = database.export_csv(query).decode("utf-8-sig")
                or_page = database.alerts(
                    {"w1ConfirmationMode": ["OR"]}
                )
            finally:
                database.close()

        self.assertEqual(1, page["total"])
        self.assertEqual(page["total"], summary["total_count"])
        self.assertEqual(2, page["items"][0]["id"])
        self.assertEqual("EMA_ONLY", page["items"][0]["w1_confirmation_state"])
        self.assertEqual("OBSERVE_ONLY", page["items"][0]["w1_confirmation_mode"])
        self.assertTrue(page["items"][0]["is_w1_confirmation_passed"])
        self.assertIn("EMA_ONLY", csv_text)
        self.assertEqual(1, or_page["total"])
        self.assertEqual("STRONG", or_page["items"][0]["w1_confirmation_state"])

    def test_detail_normalizes_legacy_and_exposes_current_diagnostics(self) -> None:
        """Return one stable detail shape before and after the optional migration."""

        with tempfile.TemporaryDirectory() as directory:
            legacy_path = Path(directory) / "legacy-detail.sqlite"
            create_observation_database(legacy_path)
            legacy_database = AlertDatabase(legacy_path)
            try:
                legacy_database.validate()
                legacy_detail = legacy_database.alert_detail(1)["alert"]
            finally:
                legacy_database.close()

            current_path = Path(directory) / "current-detail.sqlite"
            create_observation_database(current_path)
            add_w1_confirmation_fixture_columns(current_path)
            current_database = AlertDatabase(current_path)
            try:
                current_database.validate()
                current_detail = current_database.alert_detail(1)["alert"]
            finally:
                current_database.close()

        self.assertTrue(legacy_detail["is_w1_confirmation_legacy"])
        self.assertEqual("NOT_EVALUATED", legacy_detail["w1_confirmation_state"])
        self.assertFalse(current_detail["is_w1_confirmation_legacy"])
        self.assertEqual("STRONG", current_detail["w1_confirmation_state"])
        self.assertEqual("BUY", current_detail["w1_ema200_direction"])
        self.assertTrue(current_detail["is_w1_direction_matched"])

    def test_invalid_state_reports_bad_request(self) -> None:
        """Reject non-contract state names with HTTP 400 semantics."""

        with self.assertRaises(RequestError) as context:
            AlertDatabase.parse_filters(
                {"w1ConfirmationState": ["DIRECTION_CONFLICT"]}
            )
        self.assertEqual(400, context.exception.status)


class H1DirectionAlignmentApiTest(unittest.TestCase):
    """Verify current H1 direction diagnostics and legacy read compatibility."""

    def test_legacy_schema_projects_not_evaluated(self) -> None:
        """Expose databases created before V4 without inventing diagnostics."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "legacy-h1-alignment.sqlite"
            create_alert_summary_database(database_path)
            database = AlertDatabase(database_path)
            try:
                page = database.alerts({})
                options = database.options()
                csv_text = database.export_csv({}).decode("utf-8-sig")
            finally:
                database.close()

        self.assertEqual(3, page["total"])
        self.assertTrue(page["items"][0]["is_h1_direction_alignment_legacy"])
        self.assertEqual(
            "NOT_EVALUATED",
            page["items"][0]["h1_direction_alignment_state"],
        )
        self.assertEqual(
            "D1_TO_H1",
            page["items"][0]["h1_direction_alignment_mode"],
        )
        self.assertFalse(options["h1_direction_alignment_available"])
        self.assertIn(
            "NOT_EVALUATED",
            options["h1_direction_alignment_states"],
        )
        self.assertIn(
            "h1_direction_alignment_state",
            csv_text.splitlines()[0],
        )

    def test_current_schema_exposes_list_detail_and_csv_diagnostics(self) -> None:
        """Return the persisted DB V5 diagnosis consistently from every endpoint."""

        with tempfile.TemporaryDirectory() as directory:
            list_path = Path(directory) / "current-h1-alignment-list.sqlite"
            create_alert_summary_database(list_path)
            add_h1_direction_alignment_fixture_columns(list_path)
            database = AlertDatabase(list_path)
            query = {
                "h1DirectionAlignmentMode": [
                    "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
                ],
                "h1DirectionAlignmentState": ["EMA200_FALLBACK_BUY"],
            }
            try:
                page = database.alerts(query)
                summary = database.summary(query)
                options = database.options()
                csv_text = database.export_csv(query).decode("utf-8-sig")
            finally:
                database.close()

            detail_path = Path(directory) / "current-h1-alignment-detail.sqlite"
            create_observation_database(detail_path)
            add_h1_direction_alignment_fixture_columns(detail_path)
            detail_database = AlertDatabase(detail_path)
            try:
                detail_database.validate()
                detail = detail_database.alert_detail(1)["alert"]
            finally:
                detail_database.close()

        self.assertEqual(1, page["total"])
        self.assertEqual(page["total"], summary["total_count"])
        first = page["items"][0]
        self.assertFalse(first["is_h1_direction_alignment_legacy"])
        self.assertEqual(
            "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
            first["h1_direction_alignment_mode"],
        )
        self.assertEqual(
            "EMA200_FALLBACK_BUY",
            first["h1_direction_alignment_state"],
        )
        self.assertEqual("BUY", first["h1_direction_alignment_direction"])
        self.assertFalse(first["is_h1_mn1_direction_matched"])
        self.assertTrue(first["is_h1_w1_direction_matched"])
        self.assertTrue(first["is_h1_direction_alignment_passed"])
        self.assertEqual(
            "EMA200_FALLBACK_BUY",
            detail["h1_direction_alignment_state"],
        )
        self.assertTrue(options["h1_direction_alignment_available"])
        self.assertIn(
            "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
            options["h1_direction_alignment_modes"],
        )
        for state in (
            "EMA200_FALLBACK_BUY",
            "EMA200_FALLBACK_SELL",
            "MN1_EMA200_MISMATCH",
        ):
            self.assertIn(state, options["h1_direction_alignment_states"])
        self.assertIn("W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED", csv_text)
        self.assertIn("EMA200_FALLBACK_BUY", csv_text)


def create_observation_database(database_path: Path) -> None:
    """Create a SQLite fixture matching the H1 list and detail contracts."""

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
        "anchor_jst_time INTEGER",
        "anchor_jst_time_text TEXT",
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
        "latest_point_jst_time",
        "latest_point_jst_time_text",
        "latest_point_rate",
        "previous_open",
        "previous_high",
        "previous_low",
        "previous_close",
        "current_open",
        "current_high",
        "current_low",
        "current_close",
        "is_fibo_expansion_available",
        "fe618_price",
        "fe1000_price",
        "fe1272_price",
        "fe1618_price",
        "fe2000_price",
        "distance_to_fe2000_pips",
        "oscillator_count",
        "is_oscillator_buy",
        "stochastic_main_order",
        "stochastic_main_order_text",
        "stochastic_main_direction_text",
        "stochastic_short_count",
        "stochastic_short_main",
        "stochastic_short_signal",
        "stochastic_middle_count",
        "stochastic_middle_main",
        "stochastic_middle_signal",
        "stochastic_long_count",
        "stochastic_long_main",
        "stochastic_long_signal",
        "gmma_trend_count",
        "gmma_cross_count",
        "ema30",
        "ema60",
        "ema30_ema60_diff_pips",
        "atr14_pips",
        "ema200_close1",
        "ema200_shift1",
        "ema200_compare",
        "ema200_slope_pips",
        "ema200_close_diff_pips",
        "ema200_close_position",
        "ema200_slope_direction",
        "ema200_up_count",
        "ema200_down_count",
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
        "latest_point_jst_time_text",
        "stochastic_main_order_text",
        "stochastic_main_direction_text",
        "created_at_text",
    }
    real_columns = {
        "latest_point_rate",
        "previous_open",
        "previous_high",
        "previous_low",
        "previous_close",
        "current_open",
        "current_high",
        "current_low",
        "current_close",
        "fe618_price",
        "fe1000_price",
        "fe1272_price",
        "fe1618_price",
        "fe2000_price",
        "distance_to_fe2000_pips",
        "stochastic_short_main",
        "stochastic_short_signal",
        "stochastic_middle_main",
        "stochastic_middle_signal",
        "stochastic_long_main",
        "stochastic_long_signal",
        "ema30",
        "ema60",
        "ema30_ema60_diff_pips",
        "atr14_pips",
        "ema200_close1",
        "ema200_shift1",
        "ema200_compare",
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
        connection.execute(
            """
            CREATE INDEX idx_zigzag_elliot_observations_jst_missing
            ON zigzag_elliot_observations(id)
            WHERE anchor_jst_time <= 0 OR anchor_jst_time_text = ''
            """
        )
        connection.execute(
            """
            CREATE INDEX idx_zigzag_elliot_observation_timeframes_jst_missing
            ON zigzag_elliot_observation_timeframes(id)
            WHERE latest_point_jst_time <= 0
               OR latest_point_jst_time_text = ''
            """
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
            (
                1, 1, "LIVE", "EURUSD",
                1704067200, "2024.01.01 00:00:00",
                1704099600, "2024.01.01 09:00:00",
            ),
            (
                2, 1, "LIVE", "GBPUSD",
                1704153600, "2024.01.02 00:00:00",
                1704186000, "2024.01.02 09:00:00",
            ),
            (
                3, 2, "TESTER", "USDJPY",
                1704240000, "2024.01.03 00:00:00",
                1704272400, "2024.01.03 09:00:00",
            ),
        ]
        for (
            observation_id,
            run_id,
            source_mode,
            symbol,
            bar_time,
            bar_text,
            jst_time,
            jst_text,
        ) in parent_rows:
            connection.execute(
                """
                INSERT INTO zigzag_elliot_observations (
                    id, run_id, source_mode, source_server, symbol_name,
                    anchor_time_frame, anchor_time_frame_text,
                    anchor_bar_time, anchor_bar_time_text,
                    anchor_jst_time, anchor_jst_time_text, capture_phase,
                    analysis_version, analysis_input_hash, snapshot_hash,
                    time_frame_count, created_at, created_at_text
                ) VALUES (
                    :id, :run_id, :source_mode, 'OANDA-Demo', :symbol_name,
                    16385, 'H1', :bar_time, :bar_text, :jst_time, :jst_text,
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
                    "jst_time": jst_time,
                    "jst_text": jst_text,
                    "snapshot_hash": f"snapshot-{observation_id}",
                },
            )
        insert_columns = ",".join(time_frame_column_names)
        insert_parameters = ",".join(
            f":{column_name}" for column_name in time_frame_column_names
        )
        time_frames = ["MN1", "W1", "D1", "H4", "H1"]
        row_id = 0
        for (
            observation_id,
            _,
            _,
            _,
            bar_time,
            bar_text,
            jst_time,
            jst_text,
        ) in parent_rows:
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
                        "latest_point_jst_time": jst_time,
                        "latest_point_jst_time_text": jst_text,
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


def insert_observation_parent_rows(
    connection: sqlite3.Connection,
    rows: list[dict[str, object]],
) -> None:
    """Insert parent-only rows used by observation navigation tests."""

    connection.executemany(
        """
        INSERT INTO zigzag_elliot_observations (
            id, run_id, source_mode, source_server, symbol_name,
            anchor_time_frame, anchor_time_frame_text,
            anchor_bar_time, anchor_bar_time_text,
            anchor_jst_time, anchor_jst_time_text, capture_phase,
            analysis_version, analysis_input_hash, snapshot_hash,
            time_frame_count, created_at, created_at_text
        ) VALUES (
            :id, :run_id, :source_mode, :source_server, :symbol_name,
            :anchor_time_frame, 'H1', :anchor_bar_time,
            :anchor_bar_time_text, :anchor_jst_time,
            :anchor_jst_time_text, :capture_phase,
            :analysis_version, :analysis_input_hash, :snapshot_hash,
            5, :anchor_bar_time, :anchor_bar_time_text
        )
        """,
        rows,
    )


def clone_observation_fixture(
    connection: sqlite3.Connection,
    observation_id: int,
    symbol: str,
    bar_time: int,
    bar_time_text: str,
    jst_time: int,
    jst_time_text: str,
    state: str,
) -> None:
    """Clone fixture observation 1 at a new market H1 and classification state."""

    connection.execute(
        """
        INSERT INTO zigzag_elliot_observations (
            id, run_id, source_mode, source_server, symbol_name,
            anchor_time_frame, anchor_time_frame_text,
            anchor_bar_time, anchor_bar_time_text,
            anchor_jst_time, anchor_jst_time_text, capture_phase,
            analysis_version, analysis_input_hash, snapshot_hash,
            time_frame_count, created_at, created_at_text
        )
        SELECT :observation_id, 1, source_mode, source_server, :symbol_name,
               anchor_time_frame, anchor_time_frame_text,
               :bar_time, :bar_time_text, :jst_time, :jst_time_text,
               capture_phase, analysis_version, analysis_input_hash,
               :snapshot_hash, time_frame_count, :bar_time, :bar_time_text
        FROM zigzag_elliot_observations
        WHERE id = 1
        """,
        {
            "observation_id": observation_id,
            "symbol_name": symbol,
            "bar_time": bar_time,
            "bar_time_text": bar_time_text,
            "jst_time": jst_time,
            "jst_time_text": jst_time_text,
            "snapshot_hash": f"signal-snapshot-{observation_id}",
        },
    )
    columns = [
        row[1]
        for row in connection.execute(
            "PRAGMA table_info(zigzag_elliot_observation_timeframes)"
        )
    ]
    quoted_columns = ", ".join(f'"{column}"' for column in columns)
    select_expressions: list[str] = []
    for column in columns:
        expression = f'"{column}"'
        if column == "id":
            expression = ":time_frame_id_base + time_frame_order"
        elif column == "observation_id":
            expression = ":observation_id"
        elif column in {"latest_point_time", "created_at"}:
            expression = ":bar_time"
        elif column == "latest_point_jst_time":
            expression = ":jst_time"
        elif column in {"latest_point_time_text", "created_at_text"}:
            expression = ":bar_time_text"
        elif column == "latest_point_jst_time_text":
            expression = ":jst_time_text"
        select_expressions.append(expression)
    connection.execute(
        "INSERT INTO zigzag_elliot_observation_timeframes ("
        + quoted_columns
        + ") SELECT "
        + ", ".join(select_expressions)
        + " FROM zigzag_elliot_observation_timeframes "
        + "WHERE observation_id = 1",
        {
            "time_frame_id_base": observation_id * 10,
            "observation_id": observation_id,
            "bar_time": bar_time,
            "bar_time_text": bar_time_text,
            "jst_time": jst_time,
            "jst_time_text": jst_time_text,
        },
    )
    is_buy = state != "SELL"
    connection.execute(
        """
        UPDATE zigzag_elliot_observation_timeframes
        SET is_buy = :is_buy,
            buy_sell_label = :side,
            is_ema200_buy = :is_buy,
            is_ema200_sell = :is_sell
        WHERE observation_id = :observation_id
        """,
        {
            "is_buy": int(is_buy),
            "is_sell": int(not is_buy),
            "side": "BUY" if is_buy else "SELL",
            "observation_id": observation_id,
        },
    )
    if state == "NONE":
        connection.execute(
            """
            UPDATE zigzag_elliot_observation_timeframes
            SET is_ema200_buy = 0, is_ema200_sell = 0
            WHERE observation_id = :observation_id
              AND time_frame_order = 3
            """,
            {"observation_id": observation_id},
        )


def add_alert_detail_time_frame_fixture(
    database_path: Path,
    include_ema200_columns: bool,
) -> None:
    """Add ordered alert timeframe rows with an optional EMA200 schema."""

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "ALTER TABLE zigzag_elliot_alert_timeframes "
            "ADD COLUMN time_frame_order INTEGER"
        )
        if include_ema200_columns:
            connection.execute(
                "ALTER TABLE zigzag_elliot_alert_timeframes "
                "ADD COLUMN is_ema200_buy INTEGER"
            )
            connection.execute(
                "ALTER TABLE zigzag_elliot_alert_timeframes "
                "ADD COLUMN is_ema200_sell INTEGER"
            )
            connection.executemany(
                """
                INSERT INTO zigzag_elliot_alert_timeframes (
                    id, alert_id, time_frame, time_frame_text,
                    time_frame_order, is_buy, buy_sell_label,
                    is_ema200_buy, is_ema200_sell
                ) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (1, W1_TIME_FRAME, "W1", 0, 1, "BUY", 1, 0),
                    (2, 16385, "H1", 1, 0, "SELL", 1, 1),
                ],
            )
        else:
            connection.executemany(
                """
                INSERT INTO zigzag_elliot_alert_timeframes (
                    id, alert_id, time_frame, time_frame_text,
                    time_frame_order, is_buy, buy_sell_label
                ) VALUES (?, 1, ?, ?, ?, ?, ?)
                """,
                [
                    (1, W1_TIME_FRAME, "W1", 0, 1, "BUY"),
                    (2, 16385, "H1", 1, 0, "SELL"),
                ],
            )
    connection.close()


class AlertTimeFrameDetailEma200Test(unittest.TestCase):
    """Verify the stable EMA200 contract of alert timeframe details."""

    def load_time_frames(self, include_ema200_columns: bool) -> dict[str, object]:
        """Return one reflected timeframe response for the selected schema."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "detail-timeframes.sqlite"
            create_observation_database(database_path)
            add_alert_detail_time_frame_fixture(
                database_path,
                include_ema200_columns,
            )
            database = AlertDatabase(database_path)
            try:
                database.validate()
                response = database.timeframes(1)
            finally:
                database.close()
        return response

    def test_current_schema_marks_each_row_available_and_keeps_raw_flags(
        self,
    ) -> None:
        """Expose boolean BUY, SELL and simultaneous abnormal raw flags."""

        response = self.load_time_frames(True)
        items = response["items"]

        self.assertEqual(2, response["count"])
        self.assertEqual(["W1", "H1"], [item["time_frame_text"] for item in items])
        self.assertIs(items[0]["is_ema200_available"], True)
        self.assertIs(items[0]["is_ema200_buy"], True)
        self.assertIs(items[0]["is_ema200_sell"], False)
        self.assertIs(items[1]["is_ema200_available"], True)
        self.assertIs(items[1]["is_ema200_buy"], True)
        self.assertIs(items[1]["is_ema200_sell"], True)

    def test_legacy_schema_adds_unavailable_false_flags_to_each_row(self) -> None:
        """Normalize EMA200-less reflected rows without changing count or order."""

        response = self.load_time_frames(False)
        items = response["items"]

        self.assertEqual(2, response["count"])
        self.assertEqual(["W1", "H1"], [item["time_frame_text"] for item in items])
        for item in items:
            self.assertIs(item["is_ema200_available"], False)
            self.assertIs(item["is_ema200_buy"], False)
            self.assertIs(item["is_ema200_sell"], False)
            self.assertIsNone(item["latest_point_is_added"])

    def test_latest_point_added_state_is_mapped_to_each_timeframe(self) -> None:
        """Expose the isAddedPoint flag only from each stored latest point."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "detail-timeframes.sqlite"
            create_observation_database(database_path)
            add_alert_detail_time_frame_fixture(database_path, False)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_points "
                    "ADD COLUMN is_latest INTEGER"
                )
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_points "
                    "ADD COLUMN is_added_point INTEGER"
                )
                connection.executemany(
                    """
                    INSERT INTO zigzag_elliot_alert_points (
                        id, alert_timeframe_id, point_order,
                        is_latest, is_added_point
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    [
                        (1, 1, 0, 1, 0),
                        (2, 2, 0, 0, 0),
                        (3, 2, 1, 1, 1),
                    ],
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                database.validate()
                response = database.timeframes(1)
            finally:
                database.close()

        items = response["items"]
        self.assertIs(items[0]["latest_point_is_added"], False)
        self.assertIs(items[1]["latest_point_is_added"], True)


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
        self.assertEqual(
            {
                "available": False,
                "symbols": [],
                "source_modes": [],
                "analysis_versions": [],
                "analysis_profile_available": False,
                "analysis_profile_reason": "observation tables are not available",
                "analysis_profiles": [],
                "default_analysis_input_hash": None,
                "default_analysis_input_hashes": {
                    "all": None,
                    "LIVE": None,
                    "TESTER": None,
                },
                "default_analysis_profile_keys": {
                    "all": None,
                    "LIVE": None,
                    "TESTER": None,
                },
                "default_analysis_profiles": {
                    "all": None,
                    "LIVE": None,
                    "TESTER": None,
                },
            },
            options,
        )
        self.assertFalse(detail["available"])
        self.assertEqual(
            {"older": None, "newer": None},
            detail["navigation"],
        )

    def test_missing_detail_column_returns_available_false(self) -> None:
        """Do not advertise a partial row as the full observation detail contract."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observation_timeframes "
                    "DROP COLUMN previous_open"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                health = database.validate()
                page = database.observations({})
                detail = database.observation_detail(1)
            finally:
                database.close()

        self.assertFalse(health["observation_available"])
        self.assertFalse(page["available"])
        self.assertFalse(detail["available"])
        self.assertEqual(
            {"older": None, "newer": None},
            detail["navigation"],
        )

    def test_incomplete_jst_backfill_returns_available_false(self) -> None:
        """Do not expose default JST values inserted by a legacy writer."""

        updates = [
            (
                "zigzag_elliot_observations",
                "anchor_jst_time = 0, anchor_jst_time_text = ''",
                "anchor_jst_time <= 0 OR anchor_jst_time_text = ''",
            ),
            (
                "zigzag_elliot_observation_timeframes",
                "latest_point_jst_time = 0, latest_point_jst_time_text = ''",
                "latest_point_jst_time <= 0 OR latest_point_jst_time_text = ''",
            ),
        ]
        for table_name, assignments, missing_predicate in updates:
            with self.subTest(table_name=table_name):
                with tempfile.TemporaryDirectory() as directory:
                    database_path = Path(directory) / "alerts.sqlite"
                    create_observation_database(database_path)
                    with sqlite3.connect(database_path) as connection:
                        query_plan = connection.execute(
                            "EXPLAIN QUERY PLAN SELECT 1 FROM "
                            + table_name
                            + f" WHERE {missing_predicate} LIMIT 1"
                        ).fetchall()
                        connection.execute(
                            f"UPDATE {table_name} SET {assignments} WHERE id = 1"
                        )
                    connection.close()
                    database = AlertDatabase(database_path)
                    try:
                        health = database.validate()
                        page = database.observations({})
                        summary = database.observation_summary({})
                        options = database.observation_options()
                        detail = database.observation_detail(1)
                        runs = database.runs()
                    finally:
                        database.close()

                self.assertTrue(
                    any("jst_missing" in str(row) for row in query_plan),
                    query_plan,
                )
                self.assertFalse(health["observation_available"])
                self.assertFalse(page["available"])
                self.assertFalse(summary["available"])
                self.assertFalse(options["available"])
                self.assertFalse(detail["available"])
                self.assertTrue(
                    all(item["observation_count"] == 0 for item in runs["items"])
                )

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
                    {
                        "from": ["2024-01-01T08:00"],
                        "to": ["2024-01-01T10:00"],
                    }
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
        self.assertEqual(
            "2024.01.01 00:00:00",
            page["items"][0]["anchor_bar_time_text"],
        )
        self.assertEqual(
            "2024.01.01 09:00:00",
            page["items"][0]["anchor_jst_time_text"],
        )
        self.assertEqual(2, clamped_page["page"])
        self.assertEqual("GBPUSD", clamped_page["items"][0]["symbol_name"])
        self.assertEqual(5, len(page["items"][0]["time_frames"]))
        self.assertEqual(
            ["MN1", "W1", "D1", "H4", "H1"],
            [item["time_frame_text"] for item in page["items"][0]["time_frames"]],
        )
        self.assertTrue(page["items"][0]["time_frames"][4]["is_anchor_time_frame"])
        self.assertEqual(
            "2024.01.01 00:00:00",
            page["items"][0]["time_frames"][4]["latest_point_time_text"],
        )
        self.assertEqual(
            "2024.01.01 09:00:00",
            page["items"][0]["time_frames"][4]["latest_point_jst_time_text"],
        )
        self.assertIsNone(
            page["items"][0]["time_frames"][4]["latest_point_is_added"]
        )
        self.assertEqual(1, date_page["total"])
        self.assertEqual("EURUSD", date_page["items"][0]["symbol_name"])
        self.assertEqual(3, summary["total_count"])
        self.assertEqual(2, summary["live_count"])
        self.assertEqual(1, summary["tester_count"])
        self.assertEqual(2, summary["run_count"])
        self.assertEqual(1, summary["analysis_profile_count"])
        self.assertEqual(3, summary["legacy_profile_observation_count"])
        self.assertEqual(
            "2024.01.01 09:00:00",
            summary["first_anchor_jst_time_text"],
        )
        self.assertEqual(
            "2024.01.03 09:00:00",
            summary["last_anchor_jst_time_text"],
        )
        self.assertEqual(["EURUSD", "GBPUSD", "USDJPY"], options["symbols"])
        self.assertFalse(options["analysis_profile_available"])
        self.assertEqual("input-hash", options["default_analysis_input_hash"])
        self.assertEqual(
            {
                "all": "input-hash",
                "LIVE": "input-hash",
                "TESTER": "input-hash",
            },
            options["default_analysis_input_hashes"],
        )
        self.assertEqual(1, len(options["analysis_profiles"]))
        self.assertTrue(options["analysis_profiles"][0]["is_legacy"])
        self.assertEqual(
            ["LIVE", "TESTER"],
            options["analysis_profiles"][0]["source_modes"],
        )
        self.assertIsNone(page["items"][0]["analysis_input_text"])
        self.assertTrue(page["items"][0]["analysis_profile_is_legacy"])
        self.assertIsNone(page["items"][0]["spread_pips"])
        self.assertIsNone(page["items"][0]["pip_size"])
        self.assertTrue(detail["available"])
        self.assertEqual(
            {"older": None, "newer": None},
            detail["navigation"],
        )
        self.assertIsNone(detail["observation"]["analysis_input_text"])
        self.assertTrue(detail["observation"]["analysis_profile_is_legacy"])
        self.assertIsNone(detail["observation"]["spread_pips"])
        self.assertIsNone(detail["observation"]["pip_size"])
        self.assertEqual(
            "2024.01.01 09:00:00",
            detail["observation"]["anchor_jst_time_text"],
        )
        self.assertEqual(
            "2024.01.01 09:00:00",
            detail["time_frames"][4]["latest_point_jst_time_text"],
        )
        self.assertIsNone(detail["time_frames"][4]["latest_point_is_added"])
        self.assertEqual(5, len(detail["time_frames"]))
        expected_parent_columns = (
            OBSERVATION_REQUIRED_COLUMNS["zigzag_elliot_observations"]
            | {
                "run_uid",
                "source",
                "program_name",
                "program_version",
                "strategy",
                "strategy_version",
                "tester_from",
                "tester_to",
                "tester_model",
                "started_at",
                "started_at_text",
                "analysis_input_text",
                "analysis_profile_is_legacy",
                "analysis_profile_kind",
                "is_gmo_target",
                "spread_pips",
                "pip_size",
            }
        )
        self.assertEqual(expected_parent_columns, set(detail["observation"]))
        self.assertEqual(
            OBSERVATION_REQUIRED_COLUMNS[
                "zigzag_elliot_observation_timeframes"
            ] | {"latest_point_is_added"},
            set(detail["time_frames"][0]),
        )
        self.assertEqual(0.0, detail["time_frames"][0]["previous_open"])
        self.assertIs(
            detail["time_frames"][0]["is_fibo_expansion_available"],
            False,
        )
        self.assertIs(detail["time_frames"][0]["is_oscillator_buy"], False)
        run_one = next(item for item in runs["items"] if item["id"] == 1)
        self.assertFalse(runs["analysis_profile_available"])
        self.assertEqual("input-hash", run_one["analysis_input_hash"])
        self.assertIsNone(run_one["analysis_input_text"])
        self.assertTrue(run_one["analysis_profile_is_legacy"])
        self.assertEqual(2, run_one["alert_count"])
        self.assertEqual(2, run_one["observation_count"])
        self.assertEqual(
            "2024.01.01 00:00:00",
            run_one["first_observation_time_text"],
        )
        self.assertEqual(
            "2024.01.01 09:00:00",
            run_one["first_observation_jst_time_text"],
        )

    def test_optional_latest_point_added_is_returned_by_list_and_detail(
        self,
    ) -> None:
        """Expose recorded latest-point kinds while preserving nullable rows."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observation_timeframes "
                    "ADD COLUMN latest_point_is_added INTEGER"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET latest_point_is_added = 0 "
                    "WHERE observation_id = 1 AND time_frame_text = 'H4'"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET latest_point_is_added = 1 "
                    "WHERE observation_id = 1 AND time_frame_text = 'H1'"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                health = database.validate()
                page = database.observations(
                    {
                        "sourceMode": ["LIVE"],
                        "pageSize": ["1"],
                        "sort": ["anchor_bar_time"],
                        "order": ["asc"],
                    }
                )
                detail = database.observation_detail(1)
            finally:
                database.close()

        self.assertTrue(health["observation_available"])
        list_time_frames = {
            item["time_frame_text"]: item
            for item in page["items"][0]["time_frames"]
        }
        detail_time_frames = {
            item["time_frame_text"]: item for item in detail["time_frames"]
        }
        self.assertIs(list_time_frames["H4"]["latest_point_is_added"], False)
        self.assertIs(list_time_frames["H1"]["latest_point_is_added"], True)
        self.assertIsNone(list_time_frames["MN1"]["latest_point_is_added"])
        self.assertIs(detail_time_frames["H4"]["latest_point_is_added"], False)
        self.assertIs(detail_time_frames["H1"]["latest_point_is_added"], True)
        self.assertIsNone(detail_time_frames["MN1"]["latest_point_is_added"])

    def test_optional_point_detail_booleans_are_normalized_in_detail(
        self,
    ) -> None:
        """Normalize newly recorded point flags while preserving legacy NULL."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observation_timeframes "
                    "ADD COLUMN latest_point_is_peak INTEGER"
                )
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observation_timeframes "
                    "ADD COLUMN latest_point_is_elliot_alphabet INTEGER"
                )
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observation_timeframes "
                    "ADD COLUMN latest_point_is_correct INTEGER"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET latest_point_is_peak = 1, "
                    "latest_point_is_elliot_alphabet = 0, "
                    "latest_point_is_correct = 1 "
                    "WHERE observation_id = 1 AND time_frame_text = 'H1'"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                detail = database.observation_detail(1)
            finally:
                database.close()

        detail_time_frames = {
            item["time_frame_text"]: item for item in detail["time_frames"]
        }
        self.assertIs(detail_time_frames["H1"]["latest_point_is_peak"], True)
        self.assertIs(
            detail_time_frames["H1"]["latest_point_is_elliot_alphabet"],
            False,
        )
        self.assertIs(detail_time_frames["H1"]["latest_point_is_correct"], True)
        self.assertIsNone(detail_time_frames["MN1"]["latest_point_is_peak"])

    def test_optional_spread_is_returned_by_list_and_detail(self) -> None:
        """Expose captured spread while keeping zero as a recorded value."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observations "
                    "ADD COLUMN spread_pips REAL"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET spread_pips = 1.7 WHERE id = 1"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET spread_pips = 0.0 WHERE id = 2"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                page = database.observations(
                    {
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                summary = database.observation_summary({})
                first_detail = database.observation_detail(1)
                second_detail = database.observation_detail(2)
            finally:
                database.close()

        spread_by_id = {
            item["id"]: item["spread_pips"] for item in page["items"]
        }
        self.assertEqual(3, summary["total_count"])
        self.assertEqual(1.7, spread_by_id[1])
        self.assertEqual(0.0, spread_by_id[2])
        self.assertIsNone(spread_by_id[3])
        self.assertEqual(1.7, first_detail["observation"]["spread_pips"])
        self.assertEqual(0.0, second_detail["observation"]["spread_pips"])
        self.assertIsNone(first_detail["observation"]["pip_size"])

    def test_optional_pip_size_is_returned_by_list_signal_and_detail(self) -> None:
        """Expose captured pip sizes without requiring the new parent column."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_observations "
                    "ADD COLUMN pip_size REAL"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET pip_size = 0.0001 WHERE id = 1"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET pip_size = 0.01 WHERE id = 3"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                page = database.observations(
                    {
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                signal_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                summary = database.observation_summary({})
                eurusd_detail = database.observation_detail(1)
                usdjpy_detail = database.observation_detail(3)
            finally:
                database.close()

        pip_size_by_id = {
            item["id"]: item["pip_size"] for item in page["items"]
        }
        signal_pip_size_by_id = {
            item["id"]: item["pip_size"] for item in signal_page["items"]
        }
        self.assertEqual(3, summary["total_count"])
        self.assertEqual(0.0001, pip_size_by_id[1])
        self.assertIsNone(pip_size_by_id[2])
        self.assertEqual(0.01, pip_size_by_id[3])
        self.assertEqual(0.0001, signal_pip_size_by_id[1])
        self.assertEqual(0.01, signal_pip_size_by_id[3])
        self.assertEqual(0.0001, eurusd_detail["observation"]["pip_size"])
        self.assertEqual(0.01, usdjpy_detail["observation"]["pip_size"])
        self.assertIsNone(eurusd_detail["observation"]["spread_pips"])

    def test_detail_navigation_crosses_runs_and_excludes_other_streams(
        self,
    ) -> None:
        """Navigate one exact stream across Runs without accepting distractors."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            current_bar_time = 1704067200
            current_jst_time = 1704099600

            def parent_row(
                observation_id: int,
                time_delta: int,
                **overrides: object,
            ) -> dict[str, object]:
                row: dict[str, object] = {
                    "id": observation_id,
                    "run_id": 1,
                    "source_mode": "LIVE",
                    "source_server": "OANDA-Demo",
                    "symbol_name": "EURUSD",
                    "anchor_time_frame": 16385,
                    "anchor_bar_time": current_bar_time + time_delta,
                    "anchor_bar_time_text": f"server-{observation_id}",
                    "anchor_jst_time": current_jst_time + time_delta,
                    "anchor_jst_time_text": f"jst-{observation_id}",
                    "capture_phase": "BAR_OPEN_FIRST_SUCCESS",
                    "analysis_version": "1",
                    "analysis_input_hash": "input-hash",
                    "snapshot_hash": f"navigation-{observation_id}",
                }
                row.update(overrides)
                return row

            older_row = parent_row(
                10,
                -3600,
                run_id=3,
                anchor_bar_time_text="2023.12.31 23:00:00",
                anchor_jst_time_text="2024.01.01 08:00:00",
            )
            newer_row = parent_row(
                11,
                3600,
                run_id=3,
                anchor_bar_time_text="2024.01.01 01:00:00",
                anchor_jst_time_text="2024.01.01 10:00:00",
            )
            distractors = [
                parent_row(20, 60, symbol_name="GBPUSD"),
                parent_row(21, 120, run_id=2, source_mode="TESTER"),
                parent_row(22, 180, source_server="OTHER-Demo"),
                parent_row(23, 240, anchor_time_frame=16388),
                parent_row(24, 300, capture_phase="OTHER_PHASE"),
                parent_row(25, 360, analysis_version="2"),
                parent_row(26, 420, analysis_input_hash="other-hash"),
            ]
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "INSERT INTO zigzag_elliot_alert_runs (id, run_uid) "
                    "VALUES (3, 'run-3')"
                )
                insert_observation_parent_rows(
                    connection,
                    [older_row, newer_row, *distractors],
                )
            connection.close()

            database = AlertDatabase(database_path)
            try:
                current_detail = database.observation_detail(1)
                oldest_detail = database.observation_detail(10)
                newest_detail = database.observation_detail(11)
            finally:
                database.close()

        self.assertEqual(
            {
                "id": 10,
                "run_id": 3,
                "anchor_jst_time": current_jst_time - 3600,
                "anchor_jst_time_text": "2024.01.01 08:00:00",
                "anchor_bar_time": current_bar_time - 3600,
                "anchor_bar_time_text": "2023.12.31 23:00:00",
            },
            current_detail["navigation"]["older"],
        )
        self.assertEqual(
            {
                "id": 11,
                "run_id": 3,
                "anchor_jst_time": current_jst_time + 3600,
                "anchor_jst_time_text": "2024.01.01 10:00:00",
                "anchor_bar_time": current_bar_time + 3600,
                "anchor_bar_time_text": "2024.01.01 01:00:00",
            },
            current_detail["navigation"]["newer"],
        )
        self.assertIsNone(oldest_detail["navigation"]["older"])
        self.assertEqual(1, oldest_detail["navigation"]["newer"]["id"])
        self.assertEqual(1, newest_detail["navigation"]["older"]["id"])
        self.assertIsNone(newest_detail["navigation"]["newer"])

    def test_detail_navigation_uses_id_to_break_equal_time_ties(self) -> None:
        """Order equal JST anchors deterministically by observation ID."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            current_bar_time = 1704067200
            current_jst_time = 1704099600
            tie_rows: list[dict[str, object]] = []
            for observation_id, bar_delta in [(40, -120), (41, -60), (42, 60)]:
                tie_rows.append(
                    {
                        "id": observation_id,
                        "run_id": 1,
                        "source_mode": "LIVE",
                        "source_server": "OANDA-Demo",
                        "symbol_name": "EURUSD",
                        "anchor_time_frame": 16385,
                        "anchor_bar_time": current_bar_time + bar_delta,
                        "anchor_bar_time_text": f"server-{observation_id}",
                        "anchor_jst_time": current_jst_time,
                        "anchor_jst_time_text": "2024.01.01 09:00:00",
                        "capture_phase": "BAR_OPEN_FIRST_SUCCESS",
                        "analysis_version": "1",
                        "analysis_input_hash": "input-hash",
                        "snapshot_hash": f"tie-{observation_id}",
                    }
                )
            with sqlite3.connect(database_path) as connection:
                insert_observation_parent_rows(connection, tie_rows)
            connection.close()

            database = AlertDatabase(database_path)
            try:
                detail = database.observation_detail(41)
            finally:
                database.close()

        self.assertEqual(40, detail["navigation"]["older"]["id"])
        self.assertEqual(42, detail["navigation"]["newer"]["id"])

    def test_jst_time_and_higher_time_frame_sync_filters(self) -> None:
        """Filter one JST hour and require every selected upper TF to match H1."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET anchor_jst_time = anchor_jst_time + 3600, "
                    "anchor_jst_time_text = '2024.01.02 10:00:00' "
                    "WHERE id = 2"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET is_buy = 0, buy_sell_label = 'SELL' "
                    "WHERE observation_id = 2 AND time_frame_text = 'H4'"
                )
                connection.execute(
                    "DELETE FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = 3 AND time_frame_text = 'D1'"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                nine_page = database.observations({"jstTime": ["09:00"]})
                ten_page = database.observations({"jstTime": ["10:00"]})
                h4_page = database.observations(
                    {"syncTimeFrame": ["H4"]}
                )
                d1_page = database.observations(
                    {"syncTimeFrame": ["D1"]}
                )
                all_sync_page = database.observations(
                    {"syncTimeFrame": ["D1", "H4"]}
                )
                combined_page = database.observations(
                    {
                        "jstTime": ["09:00"],
                        "syncTimeFrame": ["D1", "H4"],
                    }
                )
                combined_summary = database.observation_summary(
                    {
                        "jstTime": ["09:00"],
                        "syncTimeFrame": ["D1", "H4"],
                    }
                )
            finally:
                database.close()

        self.assertEqual([1, 3], sorted(item["id"] for item in nine_page["items"]))
        self.assertEqual([2], [item["id"] for item in ten_page["items"]])
        self.assertEqual([1, 3], sorted(item["id"] for item in h4_page["items"]))
        self.assertEqual([1, 2], sorted(item["id"] for item in d1_page["items"]))
        self.assertEqual([1], [item["id"] for item in all_sync_page["items"]])
        self.assertEqual([1], [item["id"] for item in combined_page["items"]])
        self.assertEqual(1, combined_summary["total_count"])
        self.assertEqual(1, combined_summary["live_count"])
        self.assertEqual(0, combined_summary["tester_count"])

    def test_full_alignment_filters_list_and_summary_by_direction(self) -> None:
        """Require W1 through H1 and strict H4/H1 EMA200 alignment."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            database = AlertDatabase(database_path)
            try:
                full_page = database.observations(
                    {
                        "fullAlignment": [" full "],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                buy_page = database.observations(
                    {
                        "fullAlignment": ["buy"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                sell_page = database.observations(
                    {
                        "fullAlignment": ["SELL"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                full_summary = database.observation_summary(
                    {"fullAlignment": ["FULL"]}
                )
                buy_summary = database.observation_summary(
                    {"fullAlignment": ["BUY"]}
                )
                sell_summary = database.observation_summary(
                    {"fullAlignment": ["SELL"]}
                )
            finally:
                database.close()

        self.assertEqual([1, 2, 3], [item["id"] for item in full_page["items"]])
        self.assertEqual([1, 2], [item["id"] for item in buy_page["items"]])
        self.assertEqual([3], [item["id"] for item in sell_page["items"]])
        self.assertEqual(3, full_summary["total_count"])
        self.assertEqual(2, full_summary["live_count"])
        self.assertEqual(1, full_summary["tester_count"])
        self.assertEqual(2, buy_summary["total_count"])
        self.assertEqual(2, buy_summary["live_count"])
        self.assertEqual(0, buy_summary["tester_count"])
        self.assertEqual(1, sell_summary["total_count"])
        self.assertEqual(0, sell_summary["live_count"])
        self.assertEqual(1, sell_summary["tester_count"])

    def test_continuous_full_h1_rows_are_grouped_before_filtering_and_paging(
        self,
    ) -> None:
        """Collapse market-adjacent FULL rows and split direction, NONE and gaps."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "DELETE FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id IN (2, 3)"
                )
                connection.execute(
                    "DELETE FROM zigzag_elliot_observations WHERE id IN (2, 3)"
                )
                rows = [
                    (10, "EURUSD", 1704070800, "2024.01.01 01:00:00",
                     1704103200, "2024.01.01 10:00:00", "BUY"),
                    (11, "EURUSD", 1704074400, "2024.01.01 02:00:00",
                     1704106800, "2024.01.01 11:00:00", "NONE"),
                    (12, "EURUSD", 1704078000, "2024.01.01 03:00:00",
                     1704110400, "2024.01.01 12:00:00", "BUY"),
                    (13, "EURUSD", 1704081600, "2024.01.01 04:00:00",
                     1704114000, "2024.01.01 13:00:00", "SELL"),
                    (14, "EURUSD", 1704085200, "2024.01.01 05:00:00",
                     1704117600, "2024.01.01 14:00:00", "SELL"),
                    (17, "EURUSD", 1704092400, "2024.01.01 07:00:00",
                     1704124800, "2024.01.01 16:00:00", "SELL"),
                ]
                for row in rows:
                    clone_observation_fixture(connection, *row)
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET latest_sub_elliot_label = 'ONLY_MIDDLE' "
                    "WHERE observation_id = 10"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET latest_sub_elliot_label = 'START_MATCH' "
                    "WHERE observation_id = 1"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observation_timeframes "
                    "SET is_buy = 0, buy_sell_label = 'SELL' "
                    "WHERE observation_id = 10 AND time_frame_order = 0"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                summary = database.observation_summary(
                    {"groupMode": ["SIGNAL"]}
                )
                sell_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "fullAlignment": ["SELL"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                ranged_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "from": ["2024-01-01T12:00"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                middle_search_page = database.observations(
                    {"groupMode": ["signal"], "q": ["ONLY_MIDDLE"]}
                )
                start_search_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "q": ["START_MATCH"],
                    }
                )
                synchronized_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "syncTimeFrame": ["MN1"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
                second_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                        "pageSize": ["2"],
                        "page": ["2"],
                    }
                )
                clamped_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                        "pageSize": ["2"],
                        "page": ["999"],
                    }
                )
                huge_page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                        "pageSize": ["2"],
                        "page": ["999999999999999999999999999999"],
                    }
                )
            finally:
                database.close()

        self.assertTrue(page["grouped"])
        self.assertEqual([1, 12, 13, 17], [item["id"] for item in page["items"]])
        self.assertEqual([2, 1, 2, 1], [item["signal_h1_count"] for item in page["items"]])
        self.assertEqual(
            ["BUY", "BUY", "SELL", "SELL"],
            [item["signal_side"] for item in page["items"]],
        )
        self.assertEqual(10, page["items"][0]["signal_end_observation_id"])
        self.assertTrue(page["items"][0]["signal_is_left_censored"])
        self.assertFalse(page["items"][1]["signal_has_data_gap_before"])
        self.assertTrue(page["items"][2]["signal_has_data_gap_after"])
        self.assertTrue(page["items"][3]["signal_has_data_gap_before"])
        self.assertTrue(page["items"][3]["signal_is_right_censored"])
        self.assertEqual(4, summary["total_count"])
        self.assertEqual(6, summary["matched_observation_count"])
        self.assertEqual(6, summary["legacy_profile_observation_count"])
        self.assertEqual(2, summary["signal_buy_count"])
        self.assertEqual(2, summary["signal_sell_count"])
        self.assertEqual([13, 17], [item["id"] for item in sell_page["items"]])
        self.assertEqual(
            [12, 13, 17],
            [item["id"] for item in ranged_page["items"]],
        )
        self.assertEqual(0, middle_search_page["total"])
        self.assertEqual(1, start_search_page["total"])
        self.assertEqual(2, start_search_page["items"][0]["signal_h1_count"])
        self.assertEqual(
            [1, 12, 13, 17],
            [item["id"] for item in synchronized_page["items"]],
        )
        self.assertEqual(2, synchronized_page["items"][0]["signal_h1_count"])
        self.assertEqual([13, 17], [item["id"] for item in second_page["items"]])
        self.assertEqual(4, second_page["total"])
        self.assertEqual(2, second_page["page_count"])
        self.assertEqual(2, clamped_page["page"])
        self.assertEqual([13, 17], [item["id"] for item in clamped_page["items"]])
        self.assertEqual(2, huge_page["page"])
        self.assertEqual([13, 17], [item["id"] for item in huge_page["items"]])

    def test_missing_timeframe_parent_splits_and_marks_signal_gap(self) -> None:
        """Treat an incomplete H1 snapshot as an unknown boundary."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "DELETE FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id IN (2, 3)"
                )
                connection.execute(
                    "DELETE FROM zigzag_elliot_observations WHERE id IN (2, 3)"
                )
                clone_observation_fixture(
                    connection,
                    10,
                    "EURUSD",
                    1704070800,
                    "2024.01.01 01:00:00",
                    1704103200,
                    "2024.01.01 10:00:00",
                    "BUY",
                )
                clone_observation_fixture(
                    connection,
                    11,
                    "EURUSD",
                    1704074400,
                    "2024.01.01 02:00:00",
                    1704106800,
                    "2024.01.01 11:00:00",
                    "BUY",
                )
                connection.execute(
                    "DELETE FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = 10 AND time_frame_order = 3"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                page = database.observations(
                    {
                        "groupMode": ["signal"],
                        "sort": ["id"],
                        "order": ["asc"],
                    }
                )
            finally:
                database.close()

        self.assertEqual([1, 11], [item["id"] for item in page["items"]])
        self.assertEqual([1, 1], [item["signal_h1_count"] for item in page["items"]])
        self.assertTrue(page["items"][0]["signal_has_data_gap_after"])
        self.assertTrue(page["items"][1]["signal_has_data_gap_before"])
        self.assertTrue(page["items"][0]["signal_is_left_censored"])
        self.assertTrue(page["items"][1]["signal_is_right_censored"])

    def test_invalid_observation_group_mode_is_rejected(self) -> None:
        """Reject unknown grouping modes instead of widening the query."""

        with self.assertRaisesRegex(RequestError, "groupMode must be H1 or SIGNAL"):
            AlertDatabase.parse_observation_filters(
                {"groupMode": ["continuous; DROP TABLE x"]}
            )

    def test_full_alignment_rejects_partial_and_invalid_matches(self) -> None:
        """Exclude mixed directions, invalid EMA states, NULLs and missing rows."""

        invalid_cases = [
            (
                "mixed_is_buy",
                "UPDATE zigzag_elliot_observation_timeframes "
                "SET is_buy = 0 WHERE observation_id = 1 "
                "AND time_frame_order = 2",
            ),
            (
                "ema_none",
                "UPDATE zigzag_elliot_observation_timeframes "
                "SET is_ema200_buy = 0, is_ema200_sell = 0 "
                "WHERE observation_id = 1 AND time_frame_order = 3",
            ),
            (
                "ema_both",
                "UPDATE zigzag_elliot_observation_timeframes "
                "SET is_ema200_buy = 1, is_ema200_sell = 1 "
                "WHERE observation_id = 1 AND time_frame_order = 4",
            ),
            (
                "ema_opposite",
                "UPDATE zigzag_elliot_observation_timeframes "
                "SET is_ema200_buy = 0, is_ema200_sell = 1 "
                "WHERE observation_id = 1 AND time_frame_order = 3",
            ),
            (
                "ema_null",
                "UPDATE zigzag_elliot_observation_timeframes "
                "SET is_ema200_buy = NULL "
                "WHERE observation_id = 1 AND time_frame_order = 4",
            ),
            (
                "missing_time_frame",
                "DELETE FROM zigzag_elliot_observation_timeframes "
                "WHERE observation_id = 1 AND time_frame_order = 3",
            ),
        ]
        for case_name, mutation_sql in invalid_cases:
            with self.subTest(case_name=case_name):
                with tempfile.TemporaryDirectory() as directory:
                    database_path = Path(directory) / "alerts.sqlite"
                    create_observation_database(database_path)
                    with sqlite3.connect(database_path) as connection:
                        connection.execute(mutation_sql)
                    connection.close()
                    database = AlertDatabase(database_path)
                    try:
                        page = database.observations(
                            {
                                "fullAlignment": ["FULL"],
                                "sort": ["id"],
                                "order": ["asc"],
                            }
                        )
                        summary = database.observation_summary(
                            {"fullAlignment": ["FULL"]}
                        )
                    finally:
                        database.close()

                self.assertEqual(
                    [2, 3],
                    [item["id"] for item in page["items"]],
                )
                self.assertEqual(2, summary["total_count"])

    def test_analysis_profile_contract_and_legacy_fallback(self) -> None:
        """Prefer the latest stored profile while retaining legacy observations."""

        profile_hash = "a" * 64
        profile_text = (
            "OSCILLATOR_PROFILE_V1|STO_SHORT=5,3,3|GMMA=30,60|ATR=14"
        )
        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_runs "
                    "ADD COLUMN analysis_input_text TEXT NOT NULL DEFAULT ''"
                )
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_runs "
                    "ADD COLUMN analysis_input_hash TEXT NOT NULL DEFAULT ''"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_alert_runs "
                    "SET analysis_version = 'ELLIOT_MN1_V2', "
                    "analysis_input_text = ?, analysis_input_hash = ? "
                    "WHERE id = 1",
                    (profile_text, profile_hash),
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET analysis_version = 'ELLIOT_MN1_V2', "
                    "analysis_input_hash = ? WHERE run_id = 1",
                    (profile_hash,),
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                health = database.validate()
                options = database.observation_options()
                runs = database.runs()
                profile_page = database.observations(
                    {
                        "analysisVersion": ["ELLIOT_MN1_V2"],
                        "analysisInputHash": [profile_hash],
                        "analysisProfileKind": ["profile"],
                    }
                )
                legacy_page = database.observations(
                    {
                        "analysisVersion": ["1"],
                        "analysisInputHash": ["input-hash"],
                        "analysisProfileKind": ["legacy"],
                    }
                )
                profile_summary = database.observation_summary(
                    {
                        "analysisVersion": ["ELLIOT_MN1_V2"],
                        "analysisInputHash": [profile_hash],
                        "analysisProfileKind": ["profile"],
                    }
                )
                legacy_summary = database.observation_summary(
                    {
                        "analysisVersion": ["1"],
                        "analysisInputHash": ["input-hash"],
                        "analysisProfileKind": ["legacy"],
                    }
                )
                profile_detail = database.observation_detail(1)
                legacy_detail = database.observation_detail(3)
            finally:
                database.close()

        self.assertTrue(health["analysis_profile_available"])
        self.assertIsNone(health["analysis_profile_reason"])
        self.assertTrue(options["analysis_profile_available"])
        self.assertEqual(profile_hash, options["default_analysis_input_hash"])
        self.assertEqual(
            {
                "all": profile_hash,
                "LIVE": profile_hash,
                "TESTER": "input-hash",
            },
            options["default_analysis_input_hashes"],
        )
        self.assertEqual(2, len(options["analysis_profiles"]))
        profiles = {
            item["analysis_input_hash"]: item
            for item in options["analysis_profiles"]
        }
        self.assertEqual(profile_text, profiles[profile_hash]["analysis_input_text"])
        self.assertEqual(["LIVE"], profiles[profile_hash]["source_modes"])
        self.assertEqual(2, profiles[profile_hash]["observation_count"])
        self.assertFalse(profiles[profile_hash]["is_legacy"])
        self.assertEqual(
            "profile",
            profiles[profile_hash]["analysis_profile_kind"],
        )
        self.assertTrue(profiles[profile_hash]["profile_key"].startswith("ap1_"))
        self.assertIsNone(profiles["input-hash"]["analysis_input_text"])
        self.assertEqual(["TESTER"], profiles["input-hash"]["source_modes"])
        self.assertTrue(profiles["input-hash"]["is_legacy"])
        self.assertEqual(
            "legacy",
            profiles["input-hash"]["analysis_profile_kind"],
        )
        self.assertEqual(
            profiles[profile_hash]["profile_key"],
            options["default_analysis_profile_keys"]["all"],
        )
        self.assertEqual(
            profiles[profile_hash],
            options["default_analysis_profiles"]["LIVE"],
        )
        self.assertEqual(
            profiles["input-hash"],
            options["default_analysis_profiles"]["TESTER"],
        )

        run_items = {item["id"]: item for item in runs["items"]}
        self.assertTrue(runs["analysis_profile_available"])
        self.assertEqual(profile_hash, run_items[1]["analysis_input_hash"])
        self.assertEqual(profile_text, run_items[1]["analysis_input_text"])
        self.assertFalse(run_items[1]["analysis_profile_is_legacy"])
        self.assertEqual("profile", run_items[1]["analysis_profile_kind"])
        self.assertEqual("input-hash", run_items[2]["analysis_input_hash"])
        self.assertIsNone(run_items[2]["analysis_input_text"])
        self.assertTrue(run_items[2]["analysis_profile_is_legacy"])
        self.assertEqual("legacy", run_items[2]["analysis_profile_kind"])

        self.assertEqual(2, profile_page["total"])
        self.assertTrue(
            all(
                item["analysis_input_text"] == profile_text
                and not item["analysis_profile_is_legacy"]
                and item["analysis_profile_kind"] == "profile"
                for item in profile_page["items"]
            )
        )
        self.assertEqual(1, legacy_page["total"])
        self.assertTrue(legacy_page["items"][0]["analysis_profile_is_legacy"])
        self.assertEqual(
            "legacy",
            legacy_page["items"][0]["analysis_profile_kind"],
        )
        self.assertEqual(1, profile_summary["analysis_profile_count"])
        self.assertEqual(0, profile_summary["legacy_profile_observation_count"])
        self.assertEqual(1, legacy_summary["analysis_profile_count"])
        self.assertEqual(1, legacy_summary["legacy_profile_observation_count"])
        self.assertEqual(
            profile_text,
            profile_detail["observation"]["analysis_input_text"],
        )
        self.assertFalse(
            profile_detail["observation"]["analysis_profile_is_legacy"]
        )
        self.assertEqual(
            "profile",
            profile_detail["observation"]["analysis_profile_kind"],
        )
        self.assertIsNone(legacy_detail["observation"]["analysis_input_text"])
        self.assertTrue(
            legacy_detail["observation"]["analysis_profile_is_legacy"]
        )
        self.assertEqual(
            "legacy",
            legacy_detail["observation"]["analysis_profile_kind"],
        )

    def test_analysis_profile_cohorts_and_defaults_use_exact_identity(self) -> None:
        """Separate version/kind cohorts and choose defaults by observation id."""

        shared_hash = "shared-hash"
        newer_hash = "newer-hash"
        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_runs "
                    "ADD COLUMN analysis_input_text TEXT NOT NULL DEFAULT ''"
                )
                connection.execute(
                    "ALTER TABLE zigzag_elliot_alert_runs "
                    "ADD COLUMN analysis_input_hash TEXT NOT NULL DEFAULT ''"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_alert_runs "
                    "SET analysis_version = 'V1', analysis_input_text = 'v1', "
                    "analysis_input_hash = ? WHERE id = 1",
                    (shared_hash,),
                )
                connection.execute(
                    "UPDATE zigzag_elliot_alert_runs "
                    "SET analysis_version = 'V1' WHERE id = 2"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET analysis_version = 'V1', analysis_input_hash = ?",
                    (shared_hash,),
                )
                connection.executemany(
                    """
                    INSERT INTO zigzag_elliot_alert_runs (
                        id, run_uid, schema_version, source_mode, source,
                        program_name, program_version, strategy,
                        strategy_version, analysis_version, source_server,
                        started_at, started_at_text, created_at,
                        created_at_text, analysis_input_text,
                        analysis_input_hash
                    ) VALUES (
                        ?, ?, 1, 'TESTER', 'ZigZagElliot', 'ZigZagElliot',
                        '1.23', 'MTF 3in3', '1', 'V2', 'OANDA-Demo',
                        ?, ?, ?, ?, ?, ?
                    )
                    """,
                    [
                        (
                            3,
                            "run-3",
                            1893452400,
                            "2030.01.01 00:00:00",
                            1893452400,
                            "2030.01.01 00:00:00",
                            "v2-shared",
                            shared_hash,
                        ),
                        (
                            4,
                            "run-4",
                            1577804400,
                            "2020.01.01 00:00:00",
                            1577804400,
                            "2020.01.01 00:00:00",
                            "v2-newer",
                            newer_hash,
                        ),
                    ],
                )
                connection.executemany(
                    """
                    INSERT INTO zigzag_elliot_observations (
                        id, run_id, source_mode, source_server, symbol_name,
                        anchor_time_frame, anchor_time_frame_text,
                        anchor_bar_time, anchor_bar_time_text,
                        anchor_jst_time, anchor_jst_time_text, capture_phase,
                        analysis_version, analysis_input_hash, snapshot_hash,
                        time_frame_count, created_at, created_at_text
                    ) VALUES (
                        ?, ?, 'TESTER', 'OANDA-Demo', ?, 16385, 'H1',
                        ?, ?, ?, ?, 'BAR_OPEN_FIRST_SUCCESS', 'V2', ?, ?,
                        5, ?, ?
                    )
                    """,
                    [
                        (
                            4,
                            3,
                            "AUDUSD",
                            1893452400,
                            "2030.01.01 00:00:00",
                            1893484800,
                            "2030.01.01 09:00:00",
                            shared_hash,
                            "snapshot-4",
                            1893452400,
                            "2030.01.01 00:00:00",
                        ),
                        (
                            5,
                            4,
                            "NZDUSD",
                            1577804400,
                            "2020.01.01 00:00:00",
                            1577836800,
                            "2020.01.01 09:00:00",
                            newer_hash,
                            "snapshot-5",
                            1577804400,
                            "2020.01.01 00:00:00",
                        ),
                    ],
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                options = database.observation_options()
                summary = database.observation_summary({})

                def exact_summary(
                    version: str,
                    input_hash: str,
                    kind: str,
                ) -> dict[str, object]:
                    return database.observation_summary(
                        {
                            "analysisVersion": [version],
                            "analysisInputHash": [input_hash],
                            "analysisProfileKind": [kind],
                        }
                    )

                v1_profile = exact_summary("V1", shared_hash, "profile")
                v1_legacy = exact_summary("V1", shared_hash, "legacy")
                v2_shared = exact_summary("V2", shared_hash, "profile")
                v2_newer = exact_summary("V2", newer_hash, "profile")
                combined = database.observations(
                    {
                        "analysisVersion": ["V1"],
                        "analysisInputHash": [shared_hash],
                    }
                )
            finally:
                database.close()

        self.assertEqual(4, len(options["analysis_profiles"]))
        profiles = {
            (
                item["analysis_version"],
                item["analysis_input_hash"],
                item["analysis_profile_kind"],
            ): item
            for item in options["analysis_profiles"]
        }
        self.assertEqual(4, len(profiles))
        self.assertEqual(4, len({item["profile_key"] for item in profiles.values()}))
        self.assertEqual(2, profiles[("V1", shared_hash, "profile")]["observation_count"])
        self.assertEqual(1, profiles[("V1", shared_hash, "legacy")]["observation_count"])
        self.assertIsNone(profiles[("V1", shared_hash, "legacy")]["analysis_input_text"])
        self.assertEqual(4, summary["analysis_profile_count"])
        self.assertEqual(1, summary["legacy_profile_observation_count"])
        self.assertEqual(2, v1_profile["total_count"])
        self.assertEqual(1, v1_legacy["total_count"])
        self.assertEqual(1, v2_shared["total_count"])
        self.assertEqual(1, v2_newer["total_count"])
        self.assertEqual(3, combined["total"])

        tester_default = options["default_analysis_profiles"]["TESTER"]
        self.assertEqual("V2", tester_default["analysis_version"])
        self.assertEqual(newer_hash, tester_default["analysis_input_hash"])
        self.assertEqual("profile", tester_default["analysis_profile_kind"])
        self.assertEqual(
            tester_default["profile_key"],
            options["default_analysis_profile_keys"]["TESTER"],
        )
        self.assertEqual(
            newer_hash,
            options["default_analysis_input_hashes"]["TESTER"],
        )
        self.assertEqual(
            newer_hash,
            options["default_analysis_input_hash"],
        )

    def test_filters_are_bound_and_sort_identifiers_are_whitelisted(self) -> None:
        """Use JST dates and reject arbitrary SQL sort expressions."""

        filters = AlertDatabase.parse_observation_filters(
            {
                "sourceMode": ["tester"],
                "runId": ["2"],
                "symbol": ["USDJPY"],
                "analysisVersion": ["V2"],
                "analysisInputHash": ["profile-hash"],
                "analysisProfileKind": ["PROFILE"],
                "from": ["2024-01-01"],
                "to": ["2024-01-04"],
                "jstTime": ["09:00"],
                "syncTimeFrame": [" h4 ", "D1", "H4", "d1", " "],
                "fullAlignment": ["buy"],
            }
        )
        self.assertIn("o.source_mode = :source_mode", filters.where_sql)
        self.assertIn("o.run_id = :run_id", filters.where_sql)
        self.assertIn("o.symbol_name = :symbol_name", filters.where_sql)
        self.assertIn(
            "o.analysis_input_hash = :analysis_input_hash",
            filters.where_sql,
        )
        self.assertIn("o.analysis_version = :analysis_version", filters.where_sql)
        self.assertIn("o.anchor_jst_time >= :from_time", filters.where_sql)
        self.assertIn("o.anchor_jst_time < :to_time", filters.where_sql)
        self.assertIn("strftime('%H:%M'", filters.where_sql)
        self.assertIn("sync_tf.is_buy = h1_tf.is_buy", filters.where_sql)
        self.assertIn(
            "COUNT(DISTINCT sync_tf.time_frame_text)",
            filters.where_sql,
        )
        self.assertIn(
            "full_h1.is_buy = :full_alignment_is_buy",
            filters.where_sql,
        )
        self.assertIn("full_h4.is_ema200_buy = 1", filters.where_sql)
        self.assertIn("full_h1.is_ema200_sell = 0", filters.where_sql)
        self.assertEqual("TESTER", filters.parameters["source_mode"])
        self.assertEqual("profile-hash", filters.parameters["analysis_input_hash"])
        self.assertEqual("V2", filters.parameters["analysis_version"])
        self.assertEqual("profile", filters.parameters["analysis_profile_kind"])
        self.assertEqual("09:00", filters.parameters["jst_time"])
        self.assertEqual("H4", filters.parameters["sync_time_frame_0"])
        self.assertEqual("D1", filters.parameters["sync_time_frame_1"])
        self.assertEqual(2, filters.parameters["sync_time_frame_count"])
        self.assertEqual(1, filters.parameters["full_alignment_is_buy"])
        self.assertEqual("profile", filters.analysis_profile_kind)
        self.assertNotIn(
            "full_w1",
            AlertDatabase.parse_observation_filters({}).where_sql,
        )
        self.assertEqual(
            "anchor_jst_time",
            AlertDatabase.parse_observation_filters({}).sort_sql,
        )
        self.assertEqual(
            "anchor_jst_time",
            AlertDatabase.parse_observation_filters(
                {"sort": ["anchor_jst_time"]}
            ).sort_sql,
        )
        self.assertEqual(
            "anchor_bar_time",
            AlertDatabase.parse_observation_filters(
                {"sort": ["anchor_bar_time"]}
            ).sort_sql,
        )
        self.assertEqual(
            "anchor_bar_time",
            AlertDatabase.parse_observation_filters(
                {"sort": ["server_time"]}
            ).sort_sql,
        )
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
        with self.assertRaisesRegex(
            RequestError,
            "analysisProfileKind must be profile or legacy",
        ):
            AlertDatabase.parse_observation_filters(
                {"analysisProfileKind": ["mixed"]}
            )
        for invalid_alignment in ["", "ALL", "BUY' OR 1=1 --"]:
            with self.subTest(full_alignment=invalid_alignment):
                with self.assertRaisesRegex(
                    RequestError,
                    "fullAlignment must be FULL, BUY or SELL",
                ):
                    AlertDatabase.parse_observation_filters(
                        {"fullAlignment": [invalid_alignment]}
                    )
        for invalid_time in [
            "9:00",
            "09:30",
            "24:00",
            "00:000",
            "-1:00",
            "invalid",
        ]:
            with self.subTest(jst_time=invalid_time):
                with self.assertRaisesRegex(
                    RequestError,
                    "jstTime must use HH:00",
                ):
                    AlertDatabase.parse_observation_filters(
                        {"jstTime": [invalid_time]}
                    )
        for invalid_time_frame in ["H1", "M5", "H4' OR 1=1 --"]:
            with self.subTest(sync_time_frame=invalid_time_frame):
                with self.assertRaisesRegex(
                    RequestError,
                    "syncTimeFrame must be MN1, W1, D1 or H4",
                ):
                    AlertDatabase.parse_observation_filters(
                        {"syncTimeFrame": [invalid_time_frame]}
                    )

    def test_run_ranges_aggregate_shared_symbol_boundaries_once(self) -> None:
        """Keep one run row when 28 symbols share its first and last times."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    """
                    INSERT INTO zigzag_elliot_alert_runs (
                        id, run_uid, schema_version, source_mode, source,
                        program_name, program_version, strategy,
                        strategy_version, analysis_version, source_server,
                        started_at, started_at_text, created_at, created_at_text
                    ) VALUES (
                        3, 'run-3', 1, 'LIVE', 'ZigZagElliot',
                        'ZigZagElliot', '1.23', 'MTF 3in3',
                        '1', '1', 'OANDA-Demo',
                        1704067200, '2024.01.01 00:00:00',
                        1704067200, '2024.01.01 00:00:00'
                    )
                    """
                )
                boundaries = [
                    (
                        1704067200,
                        "2024.01.01 00:00:00",
                        1704099600,
                        "2024.01.01 09:00:00",
                    ),
                    (
                        1704153600,
                        "2024.01.02 00:00:00",
                        1704186000,
                        "2024.01.02 09:00:00",
                    ),
                ]
                observation_rows = []
                for boundary_index, boundary in enumerate(boundaries):
                    bar_time, bar_text, jst_time, jst_text = boundary
                    for symbol_index in range(28):
                        observation_id = 100 + boundary_index * 28 + symbol_index
                        observation_rows.append(
                            {
                                "id": observation_id,
                                "symbol_name": f"PAIR{symbol_index:02d}",
                                "bar_time": bar_time,
                                "bar_text": bar_text,
                                "jst_time": jst_time,
                                "jst_text": jst_text,
                                "snapshot_hash": f"boundary-{observation_id}",
                            }
                        )
                connection.executemany(
                    """
                    INSERT INTO zigzag_elliot_observations (
                        id, run_id, source_mode, source_server, symbol_name,
                        anchor_time_frame, anchor_time_frame_text,
                        anchor_bar_time, anchor_bar_time_text,
                        anchor_jst_time, anchor_jst_time_text, capture_phase,
                        analysis_version, analysis_input_hash, snapshot_hash,
                        time_frame_count, created_at, created_at_text
                    ) VALUES (
                        :id, 3, 'LIVE', 'OANDA-Demo', :symbol_name,
                        16385, 'H1', :bar_time, :bar_text,
                        :jst_time, :jst_text, 'BAR_OPEN_FIRST_SUCCESS',
                        '1', 'input-hash', :snapshot_hash,
                        5, :bar_time, :bar_text
                    )
                    """,
                    observation_rows,
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                runs = database.runs()
            finally:
                database.close()

        self.assertEqual(3, runs["count"])
        run_three_items = [item for item in runs["items"] if item["id"] == 3]
        self.assertEqual(1, len(run_three_items))
        run_three = run_three_items[0]
        self.assertEqual(0, run_three["alert_count"])
        self.assertEqual(56, run_three["observation_count"])
        self.assertEqual(1704067200, run_three["first_observation_time"])
        self.assertEqual(
            "2024.01.01 00:00:00",
            run_three["first_observation_time_text"],
        )
        self.assertEqual(1704153600, run_three["last_observation_time"])
        self.assertEqual(
            "2024.01.02 00:00:00",
            run_three["last_observation_time_text"],
        )
        self.assertEqual(1704099600, run_three["first_observation_jst_time"])
        self.assertEqual(
            "2024.01.01 09:00:00",
            run_three["first_observation_jst_time_text"],
        )
        self.assertEqual(1704186000, run_three["last_observation_jst_time"])
        self.assertEqual(
            "2024.01.02 09:00:00",
            run_three["last_observation_jst_time_text"],
        )


class MarketH1ContinuityTest(unittest.TestCase):
    """Verify the conservative server-time market adjacency rule."""

    def test_known_market_closures_are_continuous(self) -> None:
        """Keep regular, weekend and fixed holiday boundaries continuous."""

        friday_23 = 1704495600
        monday_00 = 1704672000
        christmas_eve_23 = 1735081200
        boxing_day_00 = 1735171200
        new_year_eve_23 = 1735686000
        january_second_00 = 1735776000
        self.assertEqual(
            1,
            sqlite_is_consecutive_market_h1(1704067200, 1704070800),
        )
        self.assertEqual(
            1,
            sqlite_is_consecutive_market_h1(friday_23, monday_00),
        )
        self.assertEqual(
            1,
            sqlite_is_consecutive_market_h1(
                christmas_eve_23,
                boxing_day_00,
            ),
        )
        self.assertEqual(
            1,
            sqlite_is_consecutive_market_h1(
                new_year_eve_23,
                january_second_00,
            ),
        )
        self.assertEqual(
            0,
            sqlite_is_consecutive_market_h1(1704067200, 1704074400),
        )
        self.assertEqual(
            0,
            sqlite_is_consecutive_market_h1(friday_23, monday_00 + 3600),
        )
        self.assertEqual(0, sqlite_is_consecutive_market_h1(None, monday_00))


class GmoTargetTest(unittest.TestCase):
    """Verify derived GMO classification across both API data sets."""

    def test_canonical_prefix_and_suffix_symbols_use_the_28_pair_profile(
        self,
    ) -> None:
        """Resolve broker decorations without changing the persisted symbol."""

        self.assertEqual(28, len(GMO_SYMBOL_TARGETS))
        self.assertEqual(18, sum(GMO_SYMBOL_TARGETS.values()))
        self.assertEqual("EURUSD", canonical_symbol_name("eurusd"))
        self.assertEqual("EURUSD", canonical_symbol_name("gmo.EURUSD.a"))
        self.assertEqual("USDCAD", canonical_symbol_name("USDCAD.pro"))
        self.assertTrue(is_gmo_target("gmo.EURUSD.a"))
        self.assertFalse(is_gmo_target("USDCAD.pro"))
        self.assertFalse(is_gmo_target("UNKNOWN"))

    def test_alert_list_summary_and_detail_expose_the_same_classification(
        self,
    ) -> None:
        """Keep alert filtering, totals and detail fields consistent."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "alerts.sqlite"
            create_alert_summary_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "UPDATE zigzag_elliot_alerts "
                    "SET symbol_name = 'gmo.EURUSD.a' WHERE id = 1"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_alerts "
                    "SET symbol_name = 'USDCAD.pro' WHERE id = 2"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                target_page = database.alerts({"gmoTarget": ["target"]})
                target_summary = database.summary({"gmoTarget": ["target"]})
                excluded_page = database.alerts({"gmoTarget": ["excluded"]})
                excluded_summary = database.summary(
                    {"gmoTarget": ["excluded"]}
                )
            finally:
                database.close()

        self.assertEqual(target_page["total"], target_summary["total_count"])
        self.assertEqual(2, target_page["total"])
        self.assertTrue(
            all(item["is_gmo_target"] for item in target_page["items"])
        )
        self.assertEqual(
            excluded_page["total"], excluded_summary["total_count"]
        )
        self.assertEqual(1, excluded_page["total"])
        self.assertFalse(excluded_page["items"][0]["is_gmo_target"])

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "detail.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "UPDATE zigzag_elliot_alerts "
                    "SET symbol_name = 'broker.EURUSD.a' WHERE id = 1"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                database.validate()
                detail = database.alert_detail(1)
            finally:
                database.close()

        self.assertTrue(detail["alert"]["is_gmo_target"])

    def test_observation_list_summary_and_detail_share_gmo_filter(self) -> None:
        """Classify observation parents in page, summary and detail APIs."""

        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "observations.sqlite"
            create_observation_database(database_path)
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET symbol_name = 'broker.EURUSD.a' WHERE id = 1"
                )
                connection.execute(
                    "UPDATE zigzag_elliot_observations "
                    "SET symbol_name = 'USDCAD.pro' WHERE id = 2"
                )
            connection.close()
            database = AlertDatabase(database_path)
            try:
                target_page = database.observations(
                    {"gmoTarget": ["target"]}
                )
                target_summary = database.observation_summary(
                    {"gmoTarget": ["target"]}
                )
                excluded_page = database.observations(
                    {"gmoTarget": ["excluded"]}
                )
                excluded_summary = database.observation_summary(
                    {"gmoTarget": ["excluded"]}
                )
                target_detail = database.observation_detail(1)
                excluded_detail = database.observation_detail(2)
            finally:
                database.close()

        self.assertEqual(target_page["total"], target_summary["total_count"])
        self.assertEqual(2, target_page["total"])
        self.assertTrue(
            all(item["is_gmo_target"] for item in target_page["items"])
        )
        self.assertEqual(
            excluded_page["total"], excluded_summary["total_count"]
        )
        self.assertEqual(1, excluded_page["total"])
        self.assertFalse(excluded_page["items"][0]["is_gmo_target"])
        self.assertTrue(target_detail["observation"]["is_gmo_target"])
        self.assertFalse(excluded_detail["observation"]["is_gmo_target"])

    def test_invalid_gmo_filter_is_rejected_for_both_data_sets(self) -> None:
        """Return the standard bad-request error for unsupported values."""

        for parser in (
            AlertDatabase.parse_filters,
            AlertDatabase.parse_observation_filters,
        ):
            with self.subTest(parser=parser.__name__):
                with self.assertRaisesRegex(
                    RequestError,
                    "gmoTarget must be target, excluded or all",
                ) as raised:
                    parser({"gmoTarget": ["maybe"]})
                self.assertEqual(400, raised.exception.status)
                self.assertNotIn(
                    "is_gmo_target",
                    parser({"gmoTarget": ["all"]}).where_sql,
                )


if __name__ == "__main__":
    unittest.main()
