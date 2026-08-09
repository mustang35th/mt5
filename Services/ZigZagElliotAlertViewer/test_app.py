"""HTTP routing tests for the local alert viewer."""

from __future__ import annotations

import http.client
import json
import re
import threading
import unittest
from pathlib import Path

from app import DEFAULT_HOST, ViewerServer


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


if __name__ == "__main__":
    unittest.main()
