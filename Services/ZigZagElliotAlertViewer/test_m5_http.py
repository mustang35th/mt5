"""M5 routing and independent startup regression tests (fixture-only)."""

from __future__ import annotations

import argparse
import http.client
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import app
from m5_observations import M5ObservationDatabase, M5RequestError


class M5Stub:
    def metadata(self, params):
        return {"available": True, "params": params}

    def observations(self, params):
        if "fail" in params:
            raise M5RequestError("fixture database unavailable", 503)
        return {"items": [], "params": params}

    def detail(self, observation_id, params=None):
        return {"observation": {"id": observation_id}, "params": params}


class M5RouteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = app.ViewerServer(
            (app.DEFAULT_HOST, 0), None, Path(__file__).parent / "static",
            m5_database=M5Stub(), primary_database_error="fixture primary unavailable",
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def get(self, path, host=None):
        connection = http.client.HTTPConnection(app.DEFAULT_HOST, self.server.server_port, timeout=5)
        try:
            headers = {} if host is None else {"Host": host}
            connection.request("GET", path, headers=headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_m5_routes_work_without_primary_database(self):
        status, body = self.get("/api/m5/metadata?sourceMode=TESTER")
        self.assertEqual(status, 200)
        self.assertTrue(body["available"])
        self.assertEqual(body["params"], {"sourceMode": ["TESTER"]})
        status, body = self.get("/api/health")
        self.assertEqual(status, 503)
        self.assertIn("primary unavailable", body["error"])

    def test_m5_query_keeps_empty_unsupported_parameters_for_validation(self):
        status, body = self.get("/api/m5/observations?fullAlignment=&runId=1")
        self.assertEqual(status, 200)
        self.assertEqual(body["params"]["fullAlignment"], [""])

    def test_m5_detail_receives_database_identity(self):
        status, body = self.get("/api/m5/observations/12?databaseKey=fixture-key")
        self.assertEqual(status, 200)
        self.assertEqual(body["observation"]["id"], 12)
        self.assertEqual(body["params"]["databaseKey"], ["fixture-key"])

    def test_invalid_identifiers_and_unknown_paths(self):
        for value in ("zero", "0", "-1"):
            with self.subTest(value=value):
                self.assertEqual(self.get(f"/api/m5/observations/{value}")[0], 400)
        self.assertEqual(self.get("/api/m5/unknown")[0], 404)
        self.assertEqual(self.get("/api/m5/observations/1/extra")[0], 404)

    def test_m5_read_failure_is_not_an_empty_success(self):
        status, body = self.get("/api/m5/observations?fail=1")
        self.assertEqual(status, 503)
        self.assertIn("unavailable", body["error"])

    def test_host_validation_also_protects_m5(self):
        status, body = self.get("/api/m5/metadata", "untrusted.example")
        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "invalid Host header")


class M5StartupTest(unittest.TestCase):
    def test_command_line_preserves_primary_and_adds_optional_m5(self):
        with patch("sys.argv", ["app.py", "--database", "primary.sqlite", "--m5-database", "m5.sqlite"]):
            arguments = app.parse_arguments()
        self.assertEqual(arguments.database, "primary.sqlite")
        self.assertEqual(arguments.m5_database, "m5.sqlite")
        with patch("sys.argv", ["app.py"]):
            self.assertIsNone(app.parse_arguments().m5_database)

    def run_main(self, primary_path, m5_path, m5_available, *, metadata_error=None,
                 bind_error=None, primary_error=None):
        arguments = argparse.Namespace(
            database=str(primary_path), m5_database=m5_path,
            host=app.DEFAULT_HOST, port=5187, allowed_host=[], open_browser=False,
            open_tab=None, open_source_mode=None,
        )
        primary = Mock()
        primary.validate.return_value = {"database": str(primary_path), "alert_count": 0, "journal_mode": "wal"}
        primary.validate.side_effect = primary_error
        m5 = Mock()
        m5.metadata.return_value = {"available": m5_available, "reason": "fixture unavailable"}
        m5.metadata.side_effect = metadata_error
        server = Mock()
        with patch.object(app, "parse_arguments", return_value=arguments), \
                patch.object(app, "AlertDatabase", return_value=primary), \
                patch.object(app, "M5ObservationDatabase", return_value=m5), \
                patch.object(app, "ViewerServer", return_value=server, side_effect=bind_error) as server_factory, \
                patch("sys.stdout", new_callable=io.StringIO), \
                patch("sys.stderr", new_callable=io.StringIO):
            result = app.main()
        return result, server_factory, primary, m5

    def test_m5_only_startup_does_not_require_alert_tables(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            result, factory, _, m5 = self.run_main(Path(directory) / "absent.sqlite", "m5.sqlite", True)
        self.assertEqual(result, 0)
        self.assertIsNone(factory.call_args.args[1])
        m5.close.assert_called_once()

    def test_invalid_optional_m5_does_not_stop_primary(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            primary_path = Path(directory) / "primary.fixture"
            primary_path.touch()
            result, factory, primary, m5 = self.run_main(primary_path, "missing-m5.sqlite", False)
        self.assertEqual(result, 0)
        factory.assert_called_once()
        primary.close.assert_called_once()
        m5.close.assert_called_once()

    def test_missing_primary_without_m5_preserves_startup_failure(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            result, factory, _, _ = self.run_main(Path(directory) / "absent.sqlite", None, False)
        self.assertEqual(result, 2)
        factory.assert_not_called()

    def test_both_unavailable_do_not_listen(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            result, factory, _, m5 = self.run_main(Path(directory) / "absent.sqlite", "missing-m5.sqlite", False)
        self.assertEqual(result, 2)
        factory.assert_not_called()
        m5.close.assert_called_once()

    def test_temporary_m5_metadata_failure_keeps_primary_and_retryable_source(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            primary_path = Path(directory) / "primary.fixture"
            primary_path.touch()
            result, factory, primary, m5 = self.run_main(
                primary_path, "m5.sqlite", False,
                metadata_error=M5RequestError("fixture busy", 503),
            )
        self.assertEqual(0, result)
        self.assertIs(primary, factory.call_args.args[1])
        self.assertIs(m5, factory.call_args.kwargs["m5_database"])
        primary.close.assert_called_once()
        m5.close.assert_called_once()

    def test_failed_bind_closes_both_sources(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            primary_path = Path(directory) / "primary.fixture"
            primary_path.touch()
            result, factory, primary, m5 = self.run_main(
                primary_path, "m5.sqlite", True, bind_error=OSError("fixture address in use"),
            )
        self.assertEqual(2, result)
        factory.assert_called_once()
        primary.close.assert_called_once()
        m5.close.assert_called_once()

    def test_primary_path_and_open_errors_do_not_prevent_m5_only(self):
        for error in (OSError("fixture path inaccessible"), ValueError("fixture invalid path")):
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
                primary_path = Path(directory) / "primary.fixture"
                primary_path.touch()
                result, factory, primary, m5 = self.run_main(primary_path, "m5.sqlite", True, primary_error=error)
                self.assertEqual(0, result)
                self.assertIsNone(factory.call_args.args[1])
                primary.close.assert_called_once()
                m5.close.assert_called_once()
        with patch.object(app, "Path", side_effect=ValueError("fixture invalid primary path")):
            # Test path construction at the primary boundary without mocking M5's Path.
            arguments = argparse.Namespace(database="bad", m5_database=None, host=app.DEFAULT_HOST,
                                           port=5187, allowed_host=[], open_browser=False,
                                           open_tab=None, open_source_mode=None)
            with patch.object(app, "parse_arguments", return_value=arguments), patch("sys.stderr", new_callable=io.StringIO):
                self.assertEqual(2, app.main())

    def test_default_primary_path_error_does_not_prevent_m5_only(self):
        arguments = argparse.Namespace(database=None, m5_database="m5.sqlite", host=app.DEFAULT_HOST,
                                       port=5187, allowed_host=[], open_browser=False,
                                       open_tab=None, open_source_mode=None)
        m5 = Mock()
        m5.metadata.return_value = {"available": True, "database": None}
        with patch.object(app, "parse_arguments", return_value=arguments), \
                patch.object(app, "default_database_path", side_effect=RuntimeError("APPDATA unavailable")), \
                patch.object(app, "M5ObservationDatabase", return_value=m5), \
                patch.object(app, "ViewerServer", return_value=Mock()) as factory, \
                patch("sys.stdout", new_callable=io.StringIO), patch("sys.stderr", new_callable=io.StringIO):
            self.assertEqual(0, app.main())
        self.assertIsNone(factory.call_args.args[1])
        m5.close.assert_called_once()

    def test_invalid_m5_path_is_visible_in_metadata_without_stopping_primary(self):
        with tempfile.TemporaryDirectory(prefix="m5-viewer-startup-") as directory:
            primary_path = Path(directory) / "primary.fixture"
            primary_path.touch()
            arguments = argparse.Namespace(database=str(primary_path), m5_database="bad\x00.sqlite",
                                           host=app.DEFAULT_HOST, port=5187, allowed_host=[], open_browser=False,
                                           open_tab=None, open_source_mode=None)
            primary = Mock()
            primary.validate.return_value = {"database": str(primary_path), "alert_count": 0, "journal_mode": "wal"}
            with patch.object(app, "parse_arguments", return_value=arguments), \
                    patch.object(app, "AlertDatabase", return_value=primary), \
                    patch.object(app, "ViewerServer", return_value=Mock()) as factory, \
                    patch("sys.stdout", new_callable=io.StringIO), patch("sys.stderr", new_callable=io.StringIO):
                self.assertEqual(0, app.main())
            source = factory.call_args.kwargs["m5_database"]
            self.assertIsInstance(source, M5ObservationDatabase)
            metadata = source.metadata({})
            self.assertFalse(metadata["available"])
            self.assertEqual("UNSUPPORTED", metadata["status"])
            self.assertIn("could not be initialized", metadata["reason"])
            self.assertIs(primary, factory.call_args.args[1])
            primary.close.assert_called_once()


@unittest.skipUnless(os.name == "nt" and shutil.which("powershell.exe"), "Windows launcher probe")
class M5LauncherProbeTest(unittest.TestCase):
    """Run only the launcher health expression, with HTTP calls replaced by fixtures."""

    def run_probe(self, primary, m5):
        source = (Path(__file__).parent / "start-viewer.cmd").read_text(encoding="utf-8")
        match = re.search(r'^powershell.exe .*?-Command "(.*)" >nul 2>&1$', source, re.MULTILINE)
        self.assertIsNotNone(match)
        command = match.group(1)
        stub = (
            "function Invoke-RestMethod { param($Uri, $TimeoutSec); "
            "if ($Uri -eq '%VIEWER_HEALTH_URL%') { " + primary + " }; "
            "if ($Uri -eq '%VIEWER_M5_METADATA_URL%') { " + m5 + " }; "
            "throw 'unexpected fixture URI' }; "
        )
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", stub + command],
            capture_output=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW,
        )
        return result.returncode

    def test_primary_success_does_not_require_m5(self):
        self.assertEqual(0, self.run_probe(
            "return [PSCustomObject]@{ status='ok'; database='fixture.sqlite' }", "exit 91",
        ))

    def test_m5_only_success_reuses_existing_viewer(self):
        self.assertEqual(0, self.run_probe(
            "throw 'fixture primary unavailable'",
            "return [PSCustomObject]@{ available=$true; database=@{ path='m5.sqlite'; key='m5_fixture' } }",
        ))

    def test_unavailable_or_unidentified_m5_does_not_count_as_running(self):
        for m5 in (
            "throw 'fixture not running'",
            "return [PSCustomObject]@{ available=$false; database=@{ path='m5.sqlite'; key='m5_fixture' } }",
            "return [PSCustomObject]@{ available=$true; database=@{ path='m5.sqlite'; key='' } }",
        ):
            with self.subTest(m5=m5):
                self.assertEqual(1, self.run_probe("throw 'fixture primary unavailable'", m5))


if __name__ == "__main__":
    unittest.main()
