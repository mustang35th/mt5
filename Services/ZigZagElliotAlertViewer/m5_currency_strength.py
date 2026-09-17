"""Read observation-time currency ranks from a separate, read-only yearly database."""

from __future__ import annotations

import sqlite3
import time
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CALCULATION_VERSIONS = {
    "UNIFORM": "pair-direction-closed-v1",
    "WEIGHTED": "pair-direction-weighted-closed-v1",
}
CURRENCIES = ("USD", "EUR", "JPY", "GBP", "AUD", "NZD", "CAD", "CHF")


class M5CurrencyStrengthReader:
    """Match exact server time, environment, account and calculation method only."""

    def __init__(self, directory: Path | None, database_path: Path | None = None,
                 calculation_mode: str = "WEIGHTED"):
        if calculation_mode not in CALCULATION_VERSIONS:
            raise ValueError("Unknown currency strength calculation mode")
        self.directory = directory
        self.database_path = database_path
        self.calculation_mode = calculation_mode

    def read(self, observation: dict[str, Any], source_login: int | None) -> dict[str, Any]:
        """Return a reference, never substitute a different time or write either database."""

        target = observation["anchor_bar_time"]
        result: dict[str, Any] = {
            "status": "NOT_CONFIGURED", "databaseName": None,
            "calculationMode": self.calculation_mode,
            "calculationVersion": CALCULATION_VERSIONS[self.calculation_mode],
            "targetM5BarTime": target, "actualM5BarTime": None, "runId": None,
            "sourceMode": observation.get("source_mode"),
            "baseCurrency": None, "quoteCurrency": None, "periods": [],
        }
        try:
            database_path = self.database_path
            if database_path is None and self.directory is not None:
                year = datetime.fromtimestamp(target, timezone.utc).year
                database_path = self.directory / f"mstng-currency-strength-{year}.sqlite"
            if database_path is None:
                return result
            result["databaseName"] = database_path.name
            if not database_path.is_file():
                result["status"] = "DATABASE_NOT_FOUND"
                return result
            if (not isinstance(source_login, int) or source_login <= 0
                    or observation.get("source_mode") not in {"LIVE", "TESTER"}
                    or not observation.get("source_server")):
                result["status"] = "IDENTITY_UNAVAILABLE"
                return result
            symbol = str(observation.get("symbol_name", "")).upper()
            pairs = [(base, quote) for base in CURRENCIES for quote in CURRENCIES
                     if base != quote and base + quote in symbol]
            if len(pairs) != 1:
                result["status"] = "UNSUPPORTED_SYMBOL"
                return result
            base, quote = pairs[0]
            result.update(baseCurrency=base, quoteCurrency=quote)
            with closing(sqlite3.connect(database_path.resolve().as_uri() + "?mode=ro",
                                         uri=True, timeout=1.0)) as connection:
                connection.row_factory = sqlite3.Row
                connection.execute("PRAGMA query_only=ON")
                deadline = time.monotonic() + 2.0
                connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)
                connection.execute("BEGIN")
                runs = connection.execute("""
                    SELECT id, m5_bar_time, valid_pair_count, expected_pair_count, vote_count
                    FROM currency_strength_runs
                    WHERE m5_bar_time = ? AND source_mode = ? AND source_server = ?
                      AND source_login = ? AND calculation_version = ? AND is_complete = 1
                    LIMIT 2
                """, (target, observation["source_mode"], observation["source_server"],
                      source_login, result["calculationVersion"])).fetchall()
                if not runs:
                    result["status"] = "RECORD_NOT_FOUND"
                    return result
                if len(runs) != 1:
                    result["status"] = "AMBIGUOUS"
                    return result
                run = runs[0]
                if (run["valid_pair_count"] != 28 or run["expected_pair_count"] != 28
                        or run["vote_count"] != 196):
                    result["status"] = "INVALID_DATA"
                    return result
                rows = connection.execute("""
                    SELECT currency_name, long_medium_term_average_rank,
                           medium_short_term_average_rank
                    FROM currency_strength_results WHERE run_id = ? LIMIT 9
                """, (run["id"],)).fetchall()
                ranks = {row["currency_name"]: row for row in rows}
                fields = ("long_medium_term_average_rank", "medium_short_term_average_rank")
                if (len(rows) != 8 or set(ranks) != set(CURRENCIES)
                        or any(not isinstance(row[field], int) or not 1 <= row[field] <= 8
                               for row in rows for field in fields)):
                    result["status"] = "INVALID_DATA"
                    return result
                periods = []
                for label, field in zip(("長中期", "中短期"), fields):
                    difference = ranks[quote][field] - ranks[base][field]
                    direction = "TIE"
                    if difference > 0:
                        direction = "BUY"
                    elif difference < 0:
                        direction = "SELL"
                    periods.append({"label": label, "baseRank": ranks[base][field],
                                    "quoteRank": ranks[quote][field],
                                    "rankDifference": difference, "direction": direction})
                result.update(status="FOUND", runId=run["id"],
                              actualM5BarTime=run["m5_bar_time"], periods=periods)
        except (OSError, sqlite3.Error, ValueError, OverflowError):
            # Failure of this optional source must not hide the original observation.
            result["status"] = "ERROR"
        return result
