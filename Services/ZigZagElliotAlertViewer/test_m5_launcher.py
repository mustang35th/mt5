"""M5 shortcut launcher checks without starting a browser or reading operational DBs."""

from __future__ import annotations

import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import app


class InitialTabTest(unittest.TestCase):
    def test_default_keeps_automatic_tab_selection(self):
        with patch("sys.argv", ["app.py"]):
            arguments = app.parse_arguments()
        self.assertIsNone(arguments.open_tab)
        self.assertIsNone(arguments.open_source_mode)

    def test_currency_strength_options_and_defaults(self):
        with patch("sys.argv", ["app.py"]):
            arguments = app.parse_arguments()
        self.assertIsNone(arguments.currency_strength_database)
        self.assertEqual("WEIGHTED", arguments.currency_strength_calculation)
        with patch("sys.argv", ["app.py", "--currency-strength-database", "strength.sqlite",
                                "--currency-strength-calculation", "WEIGHTED"]):
            arguments = app.parse_arguments()
        self.assertEqual("strength.sqlite", arguments.currency_strength_database)
        self.assertEqual("WEIGHTED", arguments.currency_strength_calculation)

    def test_unknown_tab_is_rejected(self):
        with patch("sys.argv", ["app.py", "--open-tab", "unknown"]), \
                patch("sys.stderr", new_callable=io.StringIO):
            with self.assertRaises(SystemExit) as result:
                app.parse_arguments()
        self.assertEqual(2, result.exception.code)

    def test_unknown_source_mode_is_rejected(self):
        with patch("sys.argv", ["app.py", "--open-source-mode", "unknown"]), \
                patch("sys.stderr", new_callable=io.StringIO):
            with self.assertRaises(SystemExit) as result:
                app.parse_arguments()
        self.assertEqual(2, result.exception.code)

    def run_startup(self, options):
        with tempfile.TemporaryDirectory(prefix="m5-launcher-url-") as directory:
            primary_path = Path(directory) / "primary.fixture"
            primary_path.touch()
            primary = Mock()
            primary.validate.return_value = {
                "database": str(primary_path), "alert_count": 0, "journal_mode": "wal",
            }
            m5 = Mock()
            m5.metadata.return_value = {"available": True}
            with patch("sys.argv", ["app.py", "--database", str(primary_path), *options]), \
                    patch.object(app, "AlertDatabase", return_value=primary), \
                    patch.object(app, "M5ObservationDatabase", return_value=m5), \
                    patch.object(app, "ViewerServer", return_value=Mock()), \
                    patch.object(app.threading, "Timer") as timer, \
                    patch.object(app.webbrowser, "open") as browser, \
                    patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(0, app.main())
                if timer.called:
                    timer.return_value.start.assert_called_once()
                    timer.call_args.args[1]()
                return timer, browser

    def test_default_browser_url_is_unchanged(self):
        _, browser = self.run_startup(["--open-browser"])
        browser.assert_called_once_with("http://127.0.0.1:5187")

    def test_explicit_tab_uses_the_requested_port(self):
        for tab in ("m5", "h1", "alerts"):
            with self.subTest(tab=tab):
                _, browser = self.run_startup([
                    "--open-browser", "--open-tab", tab, "--port", "5188",
                ])
                browser.assert_called_once_with(f"http://127.0.0.1:5188/?tab={tab}")

    def test_tab_alone_does_not_open_a_browser(self):
        timer, browser = self.run_startup(["--open-tab", "m5", "--open-source-mode", "LIVE"])
        timer.assert_not_called()
        browser.assert_not_called()

    def test_m5_browser_url_selects_the_requested_source_mode(self):
        for mode in ("LIVE", "TESTER"):
            with self.subTest(mode=mode):
                _, browser = self.run_startup([
                    "--open-browser", "--open-tab", "m5", "--open-source-mode", mode,
                    "--port", "5188",
                ])
                browser.assert_called_once_with(f"http://127.0.0.1:5188/?tab=m5&sourceMode={mode}")

    def test_source_mode_without_tab_uses_a_valid_query_string(self):
        _, browser = self.run_startup(["--open-browser", "--open-source-mode", "LIVE"])
        browser.assert_called_once_with("http://127.0.0.1:5187/?sourceMode=LIVE")


@unittest.skipUnless(os.name == "nt", "Windows batch launcher")
class M5BatchLauncherTest(unittest.TestCase):
    def test_wrapper_passes_the_live_database_mode_tab_and_extra_arguments(self):
        source = Path(__file__).parent / "start-m5-viewer.cmd"
        with tempfile.TemporaryDirectory(prefix="m5-launcher-batch-") as directory:
            root = Path(directory)
            launcher_folder = root / "viewer with spaces"
            launcher_folder.mkdir()
            launcher = launcher_folder / source.name
            launcher.write_bytes(source.read_bytes())
            # Replace only the delegated launcher with a harmless fixture.
            (launcher_folder / "start-viewer.cmd").write_bytes(
                b"@echo off\r\necho %*\r\nexit /b 37\r\n"
            )
            environment = {**os.environ, "APPDATA": str(root / "app data")}
            result = subprocess.run(
                [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", "call",
                 str(launcher), "--port", "5188"],
                cwd=root, env=environment, capture_output=True, text=True, timeout=10,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
            self.assertEqual(37, result.returncode, result.stdout + result.stderr)
            expected = str(Path(environment["APPDATA"]) / "MetaQuotes" / "Terminal"
                           / "Common" / "Files" / "mstng-zigzag-elliot-m5-observation.sqlite")
            self.assertIn(f'--m5-database "{expected}" --open-tab m5 --open-source-mode LIVE --port 5188', result.stdout)
            self.assertNotIn("--database ", result.stdout)


if __name__ == "__main__":
    unittest.main()
