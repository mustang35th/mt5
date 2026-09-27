"""Filtered alert navigation and HTTP contract regression tests."""

from __future__ import annotations

import http.client
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.parse import urlencode

from app import AlertDatabase, DEFAULT_HOST, SORT_COLUMNS, ViewerServer, W1_TIME_FRAME
from test_app import (
    add_h1_direction_alignment_fixture_columns,
    add_w1_confirmation_fixture_columns,
    create_alert_summary_database,
)


class AlertNavigationTest(unittest.TestCase):
    """Keep previous/next consistent with the entire current alert result set."""

    def setUp(self) -> None:
        """Create mixed runs, ties, NULLs and searchable snapshot-only labels."""

        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.database_path = Path(directory.name) / "alerts.sqlite"
        create_alert_summary_database(self.database_path)
        add_w1_confirmation_fixture_columns(self.database_path)
        add_h1_direction_alignment_fixture_columns(self.database_path)
        with sqlite3.connect(self.database_path) as connection:
            connection.execute(
                "ALTER TABLE zigzag_elliot_alerts ADD COLUMN alert_text TEXT"
            )
            connection.execute(
                "ALTER TABLE zigzag_elliot_alert_timeframes "
                "ADD COLUMN previous_last_elliot_label TEXT"
            )
            connection.execute("""
                CREATE TABLE zigzag_elliot_alert_points (
                    id INTEGER PRIMARY KEY, alert_timeframe_id INTEGER,
                    elliot_label TEXT, sub_elliot_label TEXT, org_elliot_label TEXT
                )
            """)
            connection.executemany("""
                INSERT INTO zigzag_elliot_alerts (
                    id, run_id, symbol_name, side, time_frame_text,
                    strategy, h1_structure_rank
                ) VALUES (?, ?, ?, ?, ?, 'MTF_3in3', 'A')
            """, [
                (4, 1, "EURUSD", "BUY", "M15"),
                (5, 1, "EURUSD", "BUY", "H4"),
                (6, 1, "USDCAD", "SELL", "H1"),
                (7, 2, "USDJPY", "SELL", "H1"),
                (8, 1, "eurusd", "BUY", "H1"),
            ])
            connection.executemany("""
                UPDATE zigzag_elliot_alerts
                SET jst_time = strftime('%s', ?), jst_time_text = ?,
                    server_time_text = ?, risk_pips = ?, entry_result = 'SENT'
                WHERE id = ?
            """, [
                (f"2026-09-27 {hour}:00:00", f"2026.09.27 {hour}:00",
                 f"2026.09.27 {hour}:00", risk, alert_id)
                for alert_id, hour, risk in [
                    (1, "09", None), (2, "09", 10), (3, "10", 20),
                    (4, "11", 10), (5, "12", 15), (6, "13", 5), (7, "14", 10),
                ]
            ])
            connection.executemany("""
                INSERT INTO zigzag_elliot_alert_timeframes (
                    id, alert_id, time_frame, time_frame_text, is_buy, buy_sell_label
                ) VALUES (?, ?, ?, 'W1', ?, ?)
            """, [
                (4, 4, W1_TIME_FRAME, 1, "BUY"),
                (5, 5, W1_TIME_FRAME, 0, "SELL"),
                (7, 7, W1_TIME_FRAME, 0, "SELL"),
            ])
            connection.execute("""
                UPDATE zigzag_elliot_alerts
                SET w1_confirmation_mode = 'DIRECTION_OR_EMA200',
                    w1_confirmation_state = 'STRONG',
                    h1_direction_alignment_mode = 'W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED',
                    h1_direction_alignment_state = 'EMA200_FALLBACK_BUY'
                WHERE id IN (4, 5)
            """)
            connection.execute("""
                INSERT INTO zigzag_elliot_alert_points (
                    id, alert_timeframe_id, org_elliot_label
                ) VALUES (1, 1, 'original wave_% label')
            """)
            connection.execute("""
                UPDATE zigzag_elliot_alert_timeframes
                SET previous_last_elliot_label = 'snapshot wave_% label'
                WHERE alert_id = 4
            """)
            connection.execute("""
                UPDATE zigzag_elliot_alerts
                SET alert_text = 'alert wave_% label' WHERE id = 5
            """)
            connection.execute("""
                UPDATE zigzag_elliot_alerts
                SET alert_text = 'alert waveABC label' WHERE id = 8
            """)
        connection.close()
        self.database = AlertDatabase(self.database_path)
        self.addCleanup(self.database.close)

    def assert_navigation(
        self, query: dict[str, list[str]], expected_ids: list[int]
    ) -> None:
        """Check boundaries, metadata and every neighbor against expected order."""

        page = self.database.alerts({**query, "page": ["1"], "pageSize": ["200"]})
        self.assertEqual(expected_ids, [item["id"] for item in page["items"]])
        fields = (
            "id", "run_id", "symbol_name", "side", "jst_time_text",
            "server_time_text", "time_frame_text",
        )
        expected_items = [
            {field: item[field] for field in fields} for item in page["items"]
        ]
        for index, alert_id in enumerate(expected_ids):
            with self.subTest(alert_id=alert_id, query=query):
                result = self.database.alert_navigation(alert_id, query)
                previous = None
                following = None
                if index > 0:
                    previous = expected_items[index - 1]
                if index + 1 < len(expected_items):
                    following = expected_items[index + 1]
                self.assertEqual({
                    "alert_id": alert_id, "matched": True,
                    "previous": previous, "next": following,
                }, result)

    def test_time_order_ties_boundaries_and_page_crossing(self) -> None:
        """Respect time direction and id DESC ties across any requested page."""

        self.assert_navigation(
            {"page": ["2"], "pageSize": ["2"]}, [7, 6, 5, 4, 3, 2, 1, 8]
        )
        self.assert_navigation(
            {"sort": ["jst_time"], "order": ["asc"],
             "page": ["999"], "pageSize": ["1"]},
            [8, 2, 1, 3, 4, 5, 6, 7],
        )

    def test_text_collation_null_sort_and_all_supported_sorts(self) -> None:
        """Use the list's NOCASE collation and SQLite NULL ordering for every sort."""

        self.assert_navigation(
            {"sort": ["symbol_name"], "order": ["asc"]},
            [8, 5, 4, 1, 2, 6, 7, 3],
        )
        self.assert_navigation(
            {"sort": ["risk_pips"], "order": ["asc"]},
            [8, 1, 7, 4, 2, 5, 3, 6],
        )
        for sort in SORT_COLUMNS:
            for order in ("asc", "desc"):
                query = {"sort": [sort], "order": [order]}
                with self.subTest(sort=sort, order=order):
                    page = self.database.alerts(query)
                    self.assert_navigation(query, [item["id"] for item in page["items"]])

    def test_shared_filters_search_runs_and_derived_conditions(self) -> None:
        """Apply ordinary and derived conditions before finding adjacent rows."""

        cases = [
            ({"sourceMode": ["TESTER"]}, [7, 3]),
            ({"sourceMode": ["all"], "runId": ["1"]}, [6, 5, 4, 2, 1, 8]),
            ({"q": ["wave_%"]}, [5, 4, 1]),
            ({"gmoTarget": ["excluded"]}, [6]),
            ({"w1Aligned": ["unknown"]}, [6, 3, 8]),
            ({"w1Aligned": ["mismatched"]}, [5, 2]),
            ({"w1Aligned": ["aligned"]}, [7, 4, 1]),
            ({"from": ["2026-09-27T10:00"], "to": ["2026-09-27T13:00"]}, [5, 4, 3]),
            ({
                "sourceMode": ["LIVE"], "runId": ["1"], "q": ["wave_%"],
                "symbol": ["EURUSD"], "gmoTarget": ["target"],
                "timeFrame": ["H1", "M15"], "side": ["BUY"], "rank": ["A"],
                "strategy": ["MTF_3in3"], "entryResult": ["SENT"],
                "w1Aligned": ["aligned"], "w1ConfirmationMode": ["OR"],
                "w1ConfirmationState": ["STRONG"],
                "h1DirectionAlignmentMode": ["W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"],
                "h1DirectionAlignmentState": ["EMA200_FALLBACK_BUY"],
                "from": ["2026-09-27"], "to": ["2026-09-27"],
            }, [4, 1]),
        ]
        for query, expected_ids in cases:
            with self.subTest(query=query):
                self.assert_navigation(query, expected_ids)

    def test_unmatched_and_missing_ids_have_no_neighbors(self) -> None:
        """Do not jump to another result when the selected alert is absent."""

        for alert_id, query in [
            (1, {"sourceMode": ["TESTER"]}),
            (1, {"symbol": ["no matches"]}),
            (999, {}),
        ]:
            with self.subTest(alert_id=alert_id, query=query):
                self.assertEqual({
                    "alert_id": alert_id, "matched": False,
                    "previous": None, "next": None,
                }, self.database.alert_navigation(alert_id, query))

    def test_legacy_optional_columns_and_read_only_database(self) -> None:
        """Read an unchanged legacy database without creating optional columns."""

        legacy_path = self.database_path.with_name("legacy.sqlite")
        create_alert_summary_database(legacy_path)
        original_bytes = legacy_path.read_bytes()
        database = AlertDatabase(legacy_path)
        try:
            result = database.alert_navigation(2, {})
        finally:
            database.close()
        self.assertTrue(result["matched"])
        self.assertEqual(3, result["previous"]["id"])
        self.assertEqual(1, result["next"]["id"])
        self.assertEqual(original_bytes, legacy_path.read_bytes())

    def test_http_route_passes_query_and_validates_requests(self) -> None:
        """Expose exact neighbor metadata and retain the existing 400 contract."""

        server = ViewerServer(
            (DEFAULT_HOST, 0), self.database,
            Path(__file__).resolve().parent / "static",
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            query = {"sourceMode": ["LIVE"], "timeFrame": ["H1", "M15"],
                     "sort": ["jst_time"], "order": ["asc"], "pageSize": ["1"]}
            paths = [
                ("/api/alerts/4/navigation?" + urlencode(query, doseq=True), 200),
                ("/api/alerts/999/navigation", 200),
                ("/api/alerts/0/navigation", 400),
                ("/api/alerts/invalid/navigation", 400),
                ("/api/alerts/4/navigation?sort=invalid", 400),
                ("/api/alerts/4/navigation?sourceMode=invalid", 400),
            ]
            for path, expected_status in paths:
                with self.subTest(path=path):
                    connection = http.client.HTTPConnection(
                        DEFAULT_HOST, int(server.server_address[1]), timeout=5
                    )
                    try:
                        connection.request("GET", path)
                        response = connection.getresponse()
                        payload = json.loads(response.read())
                        self.assertEqual(expected_status, response.status)
                        self.assertEqual("no-store", response.getheader("Cache-Control"))
                        if path.startswith("/api/alerts/4/navigation?") and expected_status == 200:
                            self.assertEqual(self.database.alert_navigation(4, query), payload)
                            self.assertEqual(1, payload["previous"]["id"])
                            self.assertEqual(6, payload["next"]["id"])
                    finally:
                        connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
