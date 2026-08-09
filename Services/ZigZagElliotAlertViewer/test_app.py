"""HTTP routing tests for the local alert viewer."""

from __future__ import annotations

import base64
import http.client
import json
import re
import threading
import unittest
from pathlib import Path

from app import AlertDatabase, DEFAULT_HOST, RequestError, ViewerServer


class StubDatabase:
    """Provide the read-only health contract needed by route tests."""

    def validate(self) -> dict[str, object]:
        """Return deterministic health metadata."""

        return {
            "database": "stub.sqlite",
            "journal_mode": "wal",
            "alert_count": 0,
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


class AlertFilterTest(unittest.TestCase):
    """Verify filters shared by alert lists, summaries and CSV export."""

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


if __name__ == "__main__":
    unittest.main()
