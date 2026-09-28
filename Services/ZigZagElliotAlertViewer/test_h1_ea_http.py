"""EA routes and independent startup use temporary databases, never Common Files."""

from __future__ import annotations

import http.client
import io
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.parse import quote

import app
from h1_ea_results import H1EaResultsDatabase, default_ea_database_path
from test_h1_ea_results import Fixture, KEY


class EaHttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="ea-http-")
        cls.fixture = Fixture(Path(cls.directory.name) / "ea.sqlite")
        cls.fixture.session()
        cls.trade_id = cls.fixture.trade(cls.fixture.run())
        cls.source = H1EaResultsDatabase(cls.fixture.path)
        cls.server = app.ViewerServer((app.DEFAULT_HOST, 0), None, Path(__file__).parent/"static",
                        ea_database=cls.source, primary_database_error="fixture primary unavailable")
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)
        cls.fixture.close()
        cls.directory.cleanup()

    def get(self, path, host=None):
        connection = http.client.HTTPConnection(app.DEFAULT_HOST, self.server.server_port, timeout=5)
        try:
            connection.request("GET", path, headers={} if host is None else {"Host": host})
            response = connection.getresponse()
            return response.status, json.loads(response.read()), dict(response.getheaders())
        finally:
            connection.close()

    def test_all_routes_work_without_alert_database(self):
        metadata = self.get("/api/ea/metadata")[1]
        self.assertTrue(metadata["available"])
        database_key = metadata["database_key"]
        for path in ("/api/ea/sessions", *(f"/api/ea/sessions/{quote(KEY, safe='')}/{part}" for part in ("summary", "samples", "trades")),
                     f"/api/ea/trades/{self.trade_id}?session={quote(KEY, safe='')}"):
            with self.subTest(path=path):
                status, body, headers = self.get(path)
                self.assertEqual(status, 200)
                self.assertEqual(body["database_key"], database_key)
                self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(self.get("/api/health")[0], 503)

    def test_database_identity_applies_to_every_endpoint(self):
        for path in ("metadata", "sessions", *(f"sessions/{quote(KEY, safe='')}/{part}" for part in ("summary", "samples", "trades")),
                     f"trades/{self.trade_id}?session={quote(KEY, safe='')}"):
            separator = "&" if "?" in path else "?"
            with self.subTest(path=path):
                self.assertEqual(self.get(f"/api/ea/{path}{separator}database_key=old")[0], 409)

    def test_bad_ids_queries_missing_sessions_and_unknown_paths(self):
        for path in ("trades/0", "trades/invalid", "trades/9223372036854775808", "sessions/run%3A0/summary",
                     "sessions?page=", "sessions?page=1&page=2", f"sessions/{KEY}/trades?profit=garbage"):
            with self.subTest(path=path):
                self.assertEqual(self.get("/api/ea/"+path)[0], 400)
        for path in ("unknown", "sessions/run%3A999/summary", "trades/1/extra", f"sessions/{KEY}/extra"):
            self.assertEqual(self.get("/api/ea/"+path)[0], 404)

    def test_host_validation_applies_to_ea(self):
        status, body, _ = self.get("/api/ea/metadata", "untrusted.example")
        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "invalid Host header")

    def test_optional_missing_ea_metadata_is_not_fake_empty_data(self):
        missing = H1EaResultsDatabase(Path(self.directory.name)/"absent.sqlite")
        with patch.object(self.server, "ea_database", missing):
            status, body, _ = self.get("/api/ea/metadata")
            self.assertEqual(status, 200)
            self.assertFalse(body["available"])
            self.assertEqual(body["status"], "NOT_FOUND")
            self.assertEqual(self.get("/api/ea/sessions")[0], 503)


class EaStartupTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ea-startup-")
        self.addCleanup(self.directory.cleanup)
        environment = patch.dict("os.environ", {"APPDATA": self.directory.name})
        environment.start()
        self.addCleanup(environment.stop)
        self.path = Path(self.directory.name)/"ea.sqlite"
        self.fixture = Fixture(self.path)
        self.addCleanup(self.fixture.close)
        self.fixture.session()
        self.fixture.run()

    def run_main(self, *, ea_path=None, primary_available=False, bind_error=None, serve_error=None, open_browser=False):
        arguments = ["app.py", "--database", str(Path(self.directory.name)/"primary.sqlite"), "--open-tab", "ea"]
        if ea_path is not None:
            arguments += ["--ea-database", str(ea_path)]
        if open_browser:
            arguments += ["--open-browser"]
        with patch("sys.argv", arguments):
            options = app.parse_arguments()
        primary = Mock()
        primary.validate.return_value = {"database": "fixture", "alert_count": 0, "journal_mode": "delete"}
        if primary_available:
            Path(options.database).touch()
        source = H1EaResultsDatabase(ea_path)
        server = Mock()
        server.serve_forever.side_effect = serve_error
        with patch.object(app, "parse_arguments", return_value=options), \
                patch.object(app, "AlertDatabase", return_value=primary), \
                patch.object(app, "H1EaResultsDatabase", return_value=source), \
                patch.object(source, "close", wraps=source.close) as close, \
                patch.object(app, "ViewerServer", return_value=server, side_effect=bind_error) as factory, \
                patch.object(app.threading, "Timer") as timer, \
                patch("sys.stdout", new_callable=io.StringIO), patch("sys.stderr", new_callable=io.StringIO):
            result = app.main()
        return result, factory, source, close, server, timer

    def test_ea_only_startup_and_lifecycle(self):
        result, factory, source, close, server, _ = self.run_main(ea_path=self.path)
        self.assertEqual(result, 0)
        self.assertIsNone(factory.call_args.args[1])
        self.assertIs(factory.call_args.kwargs["ea_database"], source)
        close.assert_called_once()
        server.server_close.assert_called_once()

    def test_existing_default_ea_allows_startup_without_explicit_argument(self):
        path = default_ea_database_path()
        path.parent.mkdir(parents=True)
        fixture = Fixture(path)
        fixture.close()
        result, factory, *_ = self.run_main()
        self.assertEqual(result, 0)
        self.assertIsNone(factory.call_args.args[1])

    def test_missing_optional_ea_keeps_primary_available(self):
        for path in (None, Path(self.directory.name)/"missing.sqlite", "bad\x00.sqlite"):
            with self.subTest(path=path):
                result, factory, source, close, _, _ = self.run_main(ea_path=path, primary_available=True)
                self.assertEqual(result, 0)
                self.assertFalse(source.metadata()["available"])
                factory.assert_called_once()
                close.assert_called_once()

    def test_all_missing_do_not_listen(self):
        result, factory, _, close, *_ = self.run_main()
        self.assertEqual(result, 2)
        factory.assert_not_called()
        close.assert_called_once()

    def test_failed_bind_closes_ea_source(self):
        result, _, _, close, *_ = self.run_main(ea_path=self.path, bind_error=OSError("fixture address in use"))
        self.assertEqual(result, 2)
        close.assert_called_once()

    def test_interruption_closes_ea_source_and_browser_accepts_ea_tab(self):
        result, _, _, close, server, timer = self.run_main(ea_path=self.path, serve_error=KeyboardInterrupt(), open_browser=True)
        self.assertEqual(result, 0)
        close.assert_called_once()
        server.server_close.assert_called_once()
        callback = timer.call_args.args[1]
        with patch.object(app.webbrowser, "open") as open_url:
            callback()
        open_url.assert_called_once_with("http://127.0.0.1:5187/?tab=ea")


if __name__ == "__main__":
    unittest.main()
