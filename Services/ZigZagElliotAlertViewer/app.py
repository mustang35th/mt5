#!/usr/bin/env python3
"""ZigZagElliot alert database read-only local web viewer."""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sqlite3
import sys
import threading
import webbrowser
from contextlib import closing
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote, urlparse


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5187
DEFAULT_DATABASE_NAME = "mstng-zigzag-elliot-alert.sqlite"
MAX_PAGE_SIZE = 200
MAX_SEARCH_LENGTH = 200
W1_TIME_FRAME = 32769

STATIC_CONTENT_TYPES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/styles.css": ("styles.css", "text/css; charset=utf-8"),
}

SORT_COLUMNS = {
    "id": "id",
    "run_id": "run_id",
    "current_bar_time": "current_bar_time",
    "server_time": "server_time",
    "jst_time": "jst_time",
    "symbol_name": "symbol_name COLLATE NOCASE",
    "time_frame": "time_frame",
    "strategy": "strategy COLLATE NOCASE",
    "side": "side",
    "signal_count": "signal_count",
    "entry_count": "entry_count",
    "entry_result": "entry_result COLLATE NOCASE",
    "current_elliot_label": "current_elliot_label COLLATE NOCASE",
    "h1_structure_rank": "h1_structure_rank COLLATE NOCASE",
    "reference_price": "reference_price",
    "risk_pips": "risk_pips",
    "spread_pips": "spread_pips",
    "w1_side": "w1_side",
    "is_w1_aligned": "is_w1_aligned",
    "created_at": "created_at",
}

BOOLEAN_COLUMNS = {
    "is_judge",
    "is_entry_count_match",
    "is_entry_evaluated",
    "is_alert",
    "is_entry",
    "is_send_mail",
    "is_entry_wave",
    "is_ema200_distance_within",
    "is_currency_strength_enabled",
    "is_currency_strength_available",
    "is_stop_loss_available",
    "is_h1_structure_valid",
    "is_h1_structure_late",
    "is_h1_direction_exception",
    "is_current_time_frame",
    "is_buy",
    "is_wave_confirmed",
    "is_wave_motive",
    "is_wave_uptrend",
    "is_fibo_expansion_available",
    "is_oscillator_buy",
    "is_ema200_buy",
    "is_ema200_sell",
    "is_latest",
    "is_signal_reference",
    "is_bar_time_next_available",
    "is_peak",
    "is_added_point",
    "is_fibonacci_available",
    "is_fibonacci_expansion_available",
    "is_elliot_alphabet",
    "is_sub_elliot_available",
    "is_original_elliot_available",
    "is_correct",
    "is_w1_aligned",
    "w1_is_buy",
    "w1_is_wave_confirmed",
    "w1_is_wave_motive",
    "w1_is_wave_uptrend",
}


class RequestError(Exception):
    """Represents an HTTP request validation error."""

    def __init__(self, message: str, status: HTTPStatus = HTTPStatus.BAD_REQUEST):
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class AlertFilters:
    """Validated filters shared by list, summary and CSV endpoints."""

    where_sql: str
    parameters: dict[str, Any]
    derived_where_sql: str
    sort_sql: str
    order_sql: str
    page: int
    page_size: int


def default_database_path() -> Path:
    """Return the default MetaTrader Common Files database path."""

    app_data = os.environ.get("APPDATA")
    if not app_data:
        raise RuntimeError("APPDATA is not available")
    return (
        Path(app_data)
        / "MetaQuotes"
        / "Terminal"
        / "Common"
        / "Files"
        / DEFAULT_DATABASE_NAME
    )


def database_uri(database_path: Path) -> str:
    """Build a SQLite read-only URI while preserving Windows drive syntax."""

    resolved = database_path.resolve()
    path_text = resolved.as_posix()
    return f"file:{quote(path_text, safe='/:')}?mode=ro"


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    """Convert a SQLite row to JSON-ready values."""

    if row is None:
        return None
    result: dict[str, Any] = {}
    for key in row.keys():
        value = row[key]
        if key in BOOLEAN_COLUMNS and value is not None:
            result[key] = bool(value)
        else:
            result[key] = value
    return result


def positive_int(value: str | None, name: str, default: int) -> int:
    """Parse a positive integer query parameter."""

    if value is None or value == "":
        return default
    try:
        parsed = int(value)
    except ValueError as error:
        raise RequestError(f"{name} must be an integer") from error
    if parsed <= 0:
        raise RequestError(f"{name} must be greater than zero")
    return parsed


def parse_date_boundary(value: str, is_end: bool) -> int:
    """Parse an HTML date or datetime-local value as a UTC-like MQL epoch."""

    formats = ("%Y-%m-%dT%H:%M", "%Y-%m-%d")
    parsed: datetime | None = None
    used_date_only = False
    for date_format in formats:
        try:
            parsed = datetime.strptime(value, date_format).replace(tzinfo=timezone.utc)
            used_date_only = date_format == "%Y-%m-%d"
            break
        except ValueError:
            continue
    if parsed is None:
        raise RequestError("date must use YYYY-MM-DD or YYYY-MM-DDTHH:MM")
    if is_end and used_date_only:
        parsed += timedelta(days=1)
    return int(parsed.timestamp())


def escape_like(value: str) -> str:
    """Escape LIKE wildcard characters for literal free-text matching."""

    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class AlertDatabase:
    """Read-only access layer for the ZigZagElliot alert database."""

    def __init__(self, database_path: Path):
        self.database_path = database_path.resolve()

    def connect(self) -> sqlite3.Connection:
        """Open a short-lived read-only connection."""

        connection = sqlite3.connect(
            database_uri(self.database_path), uri=True, timeout=5.0
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only=ON")
        connection.execute("PRAGMA busy_timeout=5000")
        return connection

    def validate(self) -> dict[str, Any]:
        """Validate the required schema without modifying the database."""

        required_columns = {
            "zigzag_elliot_alert_runs": {"id", "run_uid", "schema_version"},
            "zigzag_elliot_alerts": {
                "id",
                "run_id",
                "side",
                "jst_time",
                "current_bar_time",
                "symbol_name",
                "h1_structure_rank",
            },
            "zigzag_elliot_alert_timeframes": {
                "id",
                "alert_id",
                "time_frame",
                "time_frame_text",
                "is_buy",
                "buy_sell_label",
            },
            "zigzag_elliot_alert_points": {
                "id",
                "alert_timeframe_id",
                "point_order",
            },
        }
        with closing(self.connect()) as connection:
            rows = connection.execute(
                "SELECT name FROM sqlite_schema WHERE type='table'"
            ).fetchall()
            actual_tables = {str(row["name"]) for row in rows}
            missing = sorted(set(required_columns) - actual_tables)
            if missing:
                raise RuntimeError("required tables are missing: " + ", ".join(missing))
            for table_name, expected_columns in required_columns.items():
                actual_columns = {
                    str(row["name"])
                    for row in connection.execute(f"PRAGMA table_info({table_name})")
                }
                missing_columns = sorted(expected_columns - actual_columns)
                if missing_columns:
                    raise RuntimeError(
                        f"required columns are missing from {table_name}: "
                        + ", ".join(missing_columns)
                    )
            journal_mode = connection.execute("PRAGMA journal_mode").fetchone()[0]
            alert_count = connection.execute(
                "SELECT COUNT(*) FROM zigzag_elliot_alerts"
            ).fetchone()[0]
        return {
            "database": str(self.database_path),
            "journal_mode": journal_mode,
            "alert_count": alert_count,
        }

    def runs(self) -> dict[str, Any]:
        """Return all runs with alert range summaries."""

        sql = """
            SELECT r.id, r.run_uid, r.schema_version, r.source_mode, r.source,
                   r.program_name, r.program_version, r.strategy,
                   r.strategy_version, r.analysis_version, r.source_server,
                   r.source_login, r.source_chart_id, r.terminal_build,
                   r.tester_from, r.tester_to, r.tester_model, r.input_hash,
                   r.started_at, r.started_at_text, r.market_started_at,
                   r.market_started_at_text, r.created_at, r.created_at_text,
                   COUNT(a.id) AS alert_count,
                   MIN(a.current_bar_time) AS first_alert_time,
                   MIN(a.current_bar_time_text) AS first_alert_time_text,
                   MAX(a.current_bar_time) AS last_alert_time,
                   MAX(a.current_bar_time_text) AS last_alert_time_text,
                   GROUP_CONCAT(DISTINCT a.symbol_name) AS symbols
            FROM zigzag_elliot_alert_runs AS r
            LEFT JOIN zigzag_elliot_alerts AS a ON a.run_id = r.id
            GROUP BY r.id
            ORDER BY r.id DESC
        """
        with closing(self.connect()) as connection:
            items = [row_to_dict(row) for row in connection.execute(sql)]
        return {"items": items, "count": len(items)}

    def options(self) -> dict[str, Any]:
        """Return distinct values used by filter controls."""

        fields = {
            "symbols": "symbol_name",
            "time_frames": "time_frame_text",
            "strategies": "strategy",
            "ranks": "h1_structure_rank",
            "entry_results": "entry_result",
        }
        result: dict[str, Any] = {}
        with closing(self.connect()) as connection:
            for output_name, column_name in fields.items():
                sql = (
                    f"SELECT DISTINCT {column_name} AS value "
                    "FROM zigzag_elliot_alerts "
                    f"WHERE {column_name} <> '' ORDER BY {column_name} COLLATE NOCASE"
                )
                result[output_name] = [row["value"] for row in connection.execute(sql)]
        return result

    @staticmethod
    def parse_filters(query: dict[str, list[str]]) -> AlertFilters:
        """Validate request query parameters and build parameterized clauses."""

        def first(name: str) -> str | None:
            values = query.get(name)
            if not values:
                return None
            return values[0].strip()

        clauses: list[str] = []
        parameters: dict[str, Any] = {}

        run_id_text = first("runId")
        if run_id_text:
            run_id = positive_int(run_id_text, "runId", 1)
            clauses.append("a.run_id = :run_id")
            parameters["run_id"] = run_id

        simple_filters = {
            "symbol": ("a.symbol_name", "symbol_name"),
            "timeFrame": ("a.time_frame_text", "time_frame_text"),
            "strategy": ("a.strategy", "strategy"),
            "rank": ("a.h1_structure_rank", "h1_structure_rank"),
            "entryResult": ("a.entry_result", "entry_result"),
        }
        for query_name, (column_name, parameter_name) in simple_filters.items():
            value = first(query_name)
            if value:
                clauses.append(f"{column_name} = :{parameter_name}")
                parameters[parameter_name] = value

        side = first("side")
        if side:
            side = side.upper()
            if side not in {"BUY", "SELL"}:
                raise RequestError("side must be BUY or SELL")
            clauses.append("a.side = :side")
            parameters["side"] = side

        from_date = first("from")
        if from_date:
            clauses.append("a.jst_time >= :from_time")
            parameters["from_time"] = parse_date_boundary(from_date, False)

        to_date = first("to")
        if to_date:
            clauses.append("a.jst_time < :to_time")
            parameters["to_time"] = parse_date_boundary(to_date, True)

        search_text = first("q")
        if search_text:
            if len(search_text) > MAX_SEARCH_LENGTH:
                raise RequestError(f"q must be at most {MAX_SEARCH_LENGTH} characters")
            parameters["search_text"] = f"%{escape_like(search_text)}%"
            searchable_columns = (
                "a.symbol_name",
                "a.strategy",
                "a.entry_result",
                "a.current_elliot_label",
                "a.h1_structure_rank",
                "a.alert_title",
                "a.alert_text",
                "a.wave_summary_text",
                "a.market_signal_key",
                "w1.latest_elliot_label",
                "w1.latest_sub_elliot_label",
            )
            search_parts = [
                f"COALESCE({column}, '') LIKE :search_text ESCAPE '\\'"
                for column in searchable_columns
            ]
            search_parts.append(
                """
                EXISTS (
                    SELECT 1
                    FROM zigzag_elliot_alert_timeframes AS search_tf
                    WHERE search_tf.alert_id = a.id
                      AND (
                          COALESCE(search_tf.latest_elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                          OR COALESCE(search_tf.latest_sub_elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                          OR COALESCE(search_tf.previous_last_elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                      )
                )
                """
            )
            search_parts.append(
                """
                EXISTS (
                    SELECT 1
                    FROM zigzag_elliot_alert_timeframes AS search_tf
                    INNER JOIN zigzag_elliot_alert_points AS search_point
                            ON search_point.alert_timeframe_id = search_tf.id
                    WHERE search_tf.alert_id = a.id
                      AND (
                          COALESCE(search_point.elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                          OR COALESCE(search_point.sub_elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                          OR COALESCE(search_point.org_elliot_label, '')
                              LIKE :search_text ESCAPE '\\'
                      )
                )
                """
            )
            clauses.append("(" + " OR ".join(search_parts) + ")")

        alignment = (first("w1Aligned") or "all").lower()
        alignment_map = {
            "all": "",
            "aligned": "is_w1_aligned = 1",
            "mismatched": "is_w1_aligned = 0",
            "unknown": "is_w1_aligned IS NULL",
        }
        if alignment not in alignment_map:
            raise RequestError("w1Aligned must be all, aligned, mismatched or unknown")

        sort_key = first("sort") or "jst_time"
        if sort_key not in SORT_COLUMNS:
            raise RequestError("unsupported sort column")
        order = (first("order") or "desc").lower()
        if order not in {"asc", "desc"}:
            raise RequestError("order must be asc or desc")

        page = positive_int(first("page"), "page", 1)
        page_size = positive_int(first("pageSize"), "pageSize", 50)
        page_size = min(page_size, MAX_PAGE_SIZE)

        where_sql = ""
        if clauses:
            where_sql = " AND " + " AND ".join(clauses)
        derived_where_sql = alignment_map[alignment]
        return AlertFilters(
            where_sql=where_sql,
            parameters=parameters,
            derived_where_sql=derived_where_sql,
            sort_sql=SORT_COLUMNS[sort_key],
            order_sql=order.upper(),
            page=page,
            page_size=page_size,
        )

    @staticmethod
    def alert_rows_cte(filters: AlertFilters) -> str:
        """Return the shared list CTE using only fixed SQL identifiers."""

        return f"""
            WITH alert_rows AS (
                SELECT
                    a.id, a.run_id, r.run_uid, r.source_mode, r.program_name,
                    r.program_version, r.strategy_version, r.analysis_version,
                    r.tester_model,
                    a.event_uid, a.market_signal_key,
                    a.server_time, a.server_time_text,
                    a.jst_time, a.jst_time_text,
                    a.current_bar_time, a.current_bar_time_text,
                    a.signal_reference_point_time,
                    a.signal_reference_point_time_text,
                    a.symbol_name, a.time_frame, a.time_frame_text,
                    a.magic_number, a.strategy, a.side,
                    a.is_judge, a.signal_count, a.entry_count,
                    a.is_entry_count_match, a.is_entry_evaluated,
                    a.is_alert, a.is_entry, a.entry_result, a.is_send_mail,
                    a.current_elliot_label, a.is_entry_wave,
                    a.close_ema200_diff_pips, a.max_close_ema200_diff_pips,
                    a.is_ema200_distance_within, a.spread_pips,
                    a.is_currency_strength_enabled,
                    a.currency_strength_status,
                    a.is_currency_strength_available,
                    a.base_currency, a.base_long_medium_rank,
                    a.base_medium_short_rank, a.quote_currency,
                    a.quote_long_medium_rank, a.quote_medium_short_rank,
                    a.long_medium_rank_difference,
                    a.medium_short_rank_difference,
                    a.reference_price, a.is_stop_loss_available,
                    a.stop_loss, a.risk_pips,
                    a.h1_structure_rank, a.is_h1_structure_valid,
                    a.is_h1_structure_late, a.is_h1_direction_exception,
                    a.alert_title, a.wave_summary_text,
                    a.created_at, a.created_at_text,
                    mn1.buy_sell_label AS mn1_side,
                    w1.buy_sell_label AS w1_side,
                    d1.buy_sell_label AS d1_side,
                    h4.buy_sell_label AS h4_side,
                    h1.buy_sell_label AS h1_side,
                    w1.id AS w1_timeframe_id,
                    w1.is_buy AS w1_is_buy,
                    w1.latest_elliot_label AS w1_elliot_label,
                    w1.latest_sub_elliot_label AS w1_sub_elliot_label,
                    w1.is_wave_confirmed AS w1_is_wave_confirmed,
                    w1.is_wave_motive AS w1_is_wave_motive,
                    w1.is_wave_uptrend AS w1_is_wave_uptrend,
                    w1.wave_trend_label AS w1_wave_trend,
                    CASE
                        WHEN w1.id IS NULL THEN NULL
                        WHEN (a.side = 'BUY' AND w1.is_buy = 1)
                          OR (a.side = 'SELL' AND w1.is_buy = 0) THEN 1
                        ELSE 0
                    END AS is_w1_aligned
                FROM zigzag_elliot_alerts AS a
                INNER JOIN zigzag_elliot_alert_runs AS r ON r.id = a.run_id
                LEFT JOIN zigzag_elliot_alert_timeframes AS mn1
                       ON mn1.alert_id = a.id AND mn1.time_frame_text = 'MN1'
                LEFT JOIN zigzag_elliot_alert_timeframes AS w1
                       ON w1.alert_id = a.id AND w1.time_frame = {W1_TIME_FRAME}
                LEFT JOIN zigzag_elliot_alert_timeframes AS d1
                       ON d1.alert_id = a.id AND d1.time_frame_text = 'D1'
                LEFT JOIN zigzag_elliot_alert_timeframes AS h4
                       ON h4.alert_id = a.id AND h4.time_frame_text = 'H4'
                LEFT JOIN zigzag_elliot_alert_timeframes AS h1
                       ON h1.alert_id = a.id AND h1.time_frame_text = 'H1'
                WHERE 1 = 1 {filters.where_sql}
            )
        """

    @staticmethod
    def outer_where(filters: AlertFilters) -> str:
        """Return the optional derived W1-alignment predicate."""

        if not filters.derived_where_sql:
            return ""
        return " WHERE " + filters.derived_where_sql

    def alerts(self, query: dict[str, list[str]]) -> dict[str, Any]:
        """Return a filtered and paginated alert list."""

        filters = self.parse_filters(query)
        cte = self.alert_rows_cte(filters)
        outer_where = self.outer_where(filters)
        count_sql = cte + " SELECT COUNT(*) AS total FROM alert_rows" + outer_where
        list_sql = (
            cte
            + " SELECT * FROM alert_rows"
            + outer_where
            + f" ORDER BY {filters.sort_sql} {filters.order_sql}, id DESC"
            + " LIMIT :limit OFFSET :offset"
        )
        parameters = dict(filters.parameters)
        parameters["limit"] = filters.page_size
        with closing(self.connect()) as connection:
            connection.execute("BEGIN")
            total = connection.execute(count_sql, filters.parameters).fetchone()["total"]
            page_count = (total + filters.page_size - 1) // filters.page_size
            if page_count == 0:
                effective_page = 1
            else:
                effective_page = min(filters.page, page_count)
            parameters["offset"] = (effective_page - 1) * filters.page_size
            items = [
                row_to_dict(row) for row in connection.execute(list_sql, parameters)
            ]
        return {
            "items": items,
            "total": total,
            "page": effective_page,
            "page_size": filters.page_size,
            "page_count": page_count,
        }

    def summary(self, query: dict[str, list[str]]) -> dict[str, Any]:
        """Return counts for the same filters used by the alert list."""

        filters = self.parse_filters(query)
        sql = self.alert_rows_cte(filters) + f"""
            SELECT
                COUNT(*) AS total_count,
                COALESCE(SUM(CASE WHEN side = 'BUY' THEN 1 ELSE 0 END), 0)
                    AS buy_count,
                COALESCE(SUM(CASE WHEN side = 'SELL' THEN 1 ELSE 0 END), 0)
                    AS sell_count,
                COALESCE(SUM(CASE WHEN is_w1_aligned = 1 THEN 1 ELSE 0 END), 0)
                    AS w1_aligned_count,
                COALESCE(SUM(CASE WHEN is_w1_aligned = 0 THEN 1 ELSE 0 END), 0)
                    AS w1_mismatched_count,
                COALESCE(SUM(CASE WHEN is_w1_aligned IS NULL THEN 1 ELSE 0 END), 0)
                    AS w1_unknown_count,
                COUNT(DISTINCT run_id) AS run_count,
                COUNT(DISTINCT symbol_name) AS symbol_count
            FROM alert_rows {self.outer_where(filters)}
        """
        with closing(self.connect()) as connection:
            row = connection.execute(sql, filters.parameters).fetchone()
        return row_to_dict(row) or {}

    def alert_detail(self, alert_id: int) -> dict[str, Any]:
        """Return an alert, its run and W1 summary."""

        with closing(self.connect()) as connection:
            alert_row = connection.execute(
                "SELECT * FROM zigzag_elliot_alerts WHERE id = ?", (alert_id,)
            ).fetchone()
            if alert_row is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            run_row = connection.execute(
                "SELECT * FROM zigzag_elliot_alert_runs WHERE id = ?",
                (alert_row["run_id"],),
            ).fetchone()
            w1_row = connection.execute(
                """
                SELECT id AS w1_timeframe_id, is_buy AS w1_is_buy,
                       buy_sell_label AS w1_side,
                       latest_elliot_label AS w1_elliot_label,
                       latest_sub_elliot_label AS w1_sub_elliot_label,
                       is_wave_confirmed AS w1_is_wave_confirmed,
                       is_wave_motive AS w1_is_wave_motive,
                       is_wave_uptrend AS w1_is_wave_uptrend,
                       wave_trend_label AS w1_wave_trend
                FROM zigzag_elliot_alert_timeframes
                WHERE alert_id = ? AND time_frame = ?
                """,
                (alert_id, W1_TIME_FRAME),
            ).fetchone()
        alert = row_to_dict(alert_row) or {}
        w1 = row_to_dict(w1_row)
        is_w1_aligned: bool | None = None
        if w1 is not None:
            is_w1_aligned = (alert["side"] == "BUY" and w1["w1_is_buy"]) or (
                alert["side"] == "SELL" and not w1["w1_is_buy"]
            )
        alert["is_w1_aligned"] = is_w1_aligned
        return {"alert": alert, "run": row_to_dict(run_row), "w1": w1}

    def timeframes(self, alert_id: int) -> dict[str, Any]:
        """Return all timeframe snapshots for an alert."""

        sql = """
            SELECT * FROM zigzag_elliot_alert_timeframes
            WHERE alert_id = ?
            ORDER BY time_frame_order, id
        """
        with closing(self.connect()) as connection:
            exists = connection.execute(
                "SELECT 1 FROM zigzag_elliot_alerts WHERE id = ?", (alert_id,)
            ).fetchone()
            if exists is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            items = [row_to_dict(row) for row in connection.execute(sql, (alert_id,))]
        return {"items": items, "count": len(items)}

    def points(self, alert_id: int, time_frame: str | None) -> dict[str, Any]:
        """Return latest-wave points grouped by timeframe for an alert."""

        where = "tf.alert_id = :alert_id"
        parameters: dict[str, Any] = {"alert_id": alert_id}
        if time_frame:
            where += " AND tf.time_frame_text = :time_frame"
            parameters["time_frame"] = time_frame
        sql = f"""
            SELECT tf.alert_id, tf.time_frame, tf.time_frame_text,
                   tf.time_frame_order, p.*
            FROM zigzag_elliot_alert_timeframes AS tf
            INNER JOIN zigzag_elliot_alert_points AS p
                    ON p.alert_timeframe_id = tf.id
            WHERE {where}
            ORDER BY tf.time_frame_order, p.point_order, p.id
        """
        with closing(self.connect()) as connection:
            exists = connection.execute(
                "SELECT 1 FROM zigzag_elliot_alerts WHERE id = ?", (alert_id,)
            ).fetchone()
            if exists is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            items = [row_to_dict(row) for row in connection.execute(sql, parameters)]
        return {"items": items, "count": len(items)}

    def export_csv(self, query: dict[str, list[str]]) -> bytes:
        """Export all alerts matching current filters as UTF-8 BOM CSV."""

        filters = self.parse_filters(query)
        sql = self.alert_rows_cte(filters) + f"""
            SELECT id AS alert_id, run_id, current_bar_time_text,
                   server_time_text, jst_time_text, symbol_name,
                   time_frame_text, strategy, side, signal_count, entry_count,
                   entry_result, current_elliot_label, h1_structure_rank,
                   mn1_side, w1_side, d1_side, h4_side, h1_side,
                   is_w1_aligned, w1_elliot_label, w1_sub_elliot_label,
                   reference_price, is_stop_loss_available, stop_loss,
                   risk_pips, spread_pips, long_medium_rank_difference,
                   medium_short_rank_difference, alert_title,
                   wave_summary_text, market_signal_key
            FROM alert_rows {self.outer_where(filters)}
            ORDER BY {filters.sort_sql} {filters.order_sql}, id DESC
        """
        with closing(self.connect()) as connection:
            rows = connection.execute(sql, filters.parameters).fetchall()
        output = io.StringIO(newline="")
        writer = csv.writer(output, lineterminator="\r\n")
        headers = list(rows[0].keys()) if rows else [
            "alert_id",
            "run_id",
            "current_bar_time_text",
            "server_time_text",
            "jst_time_text",
            "symbol_name",
            "time_frame_text",
            "strategy",
            "side",
            "signal_count",
            "entry_count",
            "entry_result",
            "current_elliot_label",
            "h1_structure_rank",
            "mn1_side",
            "w1_side",
            "d1_side",
            "h4_side",
            "h1_side",
            "is_w1_aligned",
            "w1_elliot_label",
            "w1_sub_elliot_label",
            "reference_price",
            "is_stop_loss_available",
            "stop_loss",
            "risk_pips",
            "spread_pips",
            "long_medium_rank_difference",
            "medium_short_rank_difference",
            "alert_title",
            "wave_summary_text",
            "market_signal_key",
        ]
        writer.writerow(headers)
        wave_columns = {
            "current_elliot_label",
            "w1_elliot_label",
            "w1_sub_elliot_label",
        }
        for row in rows:
            values: list[Any] = []
            for header in headers:
                value = row[header]
                if header in wave_columns and value not in (None, ""):
                    value = "wave:" + str(value)
                if isinstance(value, str) and value.lstrip().startswith(("=", "+", "-", "@")):
                    value = "'" + value
                values.append(value)
            writer.writerow(values)
        return b"\xef\xbb\xbf" + output.getvalue().encode("utf-8")


class ViewerRequestHandler(BaseHTTPRequestHandler):
    """HTTP handler for API and fixed local static assets."""

    server_version = "ZigZagElliotAlertViewer/1.0"

    @property
    def viewer_server(self) -> "ViewerServer":
        return self.server  # type: ignore[return-value]

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        """Route a read-only GET request."""

        try:
            if not self.is_allowed_host():
                raise RequestError("invalid Host header", HTTPStatus.BAD_REQUEST)
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query, keep_blank_values=False)
            if parsed.path in STATIC_CONTENT_TYPES:
                self.send_static(parsed.path)
                return
            if parsed.path == "/favicon.ico":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
                return
            if parsed.path == "/api/health":
                self.send_json({"status": "ok", **self.viewer_server.database.validate()})
                return
            if parsed.path == "/api/runs":
                self.send_json(self.viewer_server.database.runs())
                return
            if parsed.path == "/api/options":
                self.send_json(self.viewer_server.database.options())
                return
            if parsed.path == "/api/alerts":
                self.send_json(self.viewer_server.database.alerts(query))
                return
            if parsed.path == "/api/summary":
                self.send_json(self.viewer_server.database.summary(query))
                return
            if parsed.path == "/api/export.csv":
                self.send_csv(self.viewer_server.database.export_csv(query))
                return

            path_parts = [part for part in parsed.path.split("/") if part]
            if len(path_parts) >= 3 and path_parts[:2] == ["api", "alerts"]:
                try:
                    alert_id = int(path_parts[2])
                except ValueError as error:
                    raise RequestError("alert id must be an integer") from error
                if alert_id <= 0:
                    raise RequestError("alert id must be greater than zero")
                if len(path_parts) == 3:
                    self.send_json(self.viewer_server.database.alert_detail(alert_id))
                    return
                if len(path_parts) == 4 and path_parts[3] == "timeframes":
                    self.send_json(self.viewer_server.database.timeframes(alert_id))
                    return
                if len(path_parts) == 4 and path_parts[3] == "points":
                    time_frame_values = query.get("timeFrame")
                    time_frame = time_frame_values[0] if time_frame_values else None
                    self.send_json(self.viewer_server.database.points(alert_id, time_frame))
                    return
            raise RequestError("resource was not found", HTTPStatus.NOT_FOUND)
        except RequestError as error:
            self.send_json({"error": str(error)}, error.status)
        except sqlite3.Error as error:
            print(f"Database error: {error}", file=sys.stderr)
            self.send_json(
                {"error": "database is temporarily unavailable"},
                HTTPStatus.SERVICE_UNAVAILABLE,
            )
        except Exception as error:  # keep the local server available after one bad request
            print(f"Unexpected request error: {error}", file=sys.stderr)
            self.send_json(
                {"error": "unexpected server error"},
                HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def is_allowed_host(self) -> bool:
        """Reject DNS rebinding and non-local Host headers."""

        host_header = (self.headers.get("Host") or "").strip().lower()
        port = self.viewer_server.server_address[1]
        return host_header in {DEFAULT_HOST, f"{DEFAULT_HOST}:{port}"}

    def send_static(self, request_path: str) -> None:
        """Send one of the fixed, non-traversable static files."""

        file_name, content_type = STATIC_CONTENT_TYPES[request_path]
        file_path = self.viewer_server.static_path / file_name
        if not file_path.is_file():
            raise RequestError("static file was not found", HTTPStatus.NOT_FOUND)
        payload = file_path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_common_headers(content_type, len(payload))
        self.end_headers()
        self.wfile.write(payload)

    def send_json(
        self, value: Any, status: HTTPStatus = HTTPStatus.OK
    ) -> None:
        """Serialize and send a JSON response."""

        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode(
            "utf-8"
        )
        self.send_response(status)
        self.send_common_headers("application/json; charset=utf-8", len(payload))
        self.end_headers()
        self.wfile.write(payload)

    def send_csv(self, payload: bytes) -> None:
        """Send a downloadable CSV response."""

        self.send_response(HTTPStatus.OK)
        self.send_common_headers("text/csv; charset=utf-8", len(payload))
        self.send_header(
            "Content-Disposition",
            'attachment; filename="zigzag-elliot-alerts.csv"',
        )
        self.end_headers()
        self.wfile.write(payload)

    def send_common_headers(self, content_type: str, length: int) -> None:
        """Send local-viewer security and cache headers."""

        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'",
        )

    def log_message(self, message_format: str, *args: Any) -> None:
        """Write compact local access logs."""

        sys.stdout.write("[HTTP] " + (message_format % args) + "\n")


class ViewerServer(ThreadingHTTPServer):
    """Threaded localhost server holding immutable app dependencies."""

    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        database: AlertDatabase,
        static_path: Path,
    ):
        super().__init__(address, ViewerRequestHandler)
        self.database = database
        self.static_path = static_path


def parse_arguments() -> argparse.Namespace:
    """Parse command-line options."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--database",
        default=os.environ.get("ZIGZAG_ELLIOT_ALERT_DB"),
        help="SQLite database path (default: MetaTrader Common Files)",
    )
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--open-browser", action="store_true")
    return parser.parse_args()


def main() -> int:
    """Start the read-only localhost viewer."""

    arguments = parse_arguments()
    if arguments.host != DEFAULT_HOST:
        print(f"Only {DEFAULT_HOST} is allowed", file=sys.stderr)
        return 2
    if arguments.port < 1 or arguments.port > 65535:
        print("Port must be between 1 and 65535", file=sys.stderr)
        return 2

    database_path = Path(arguments.database) if arguments.database else default_database_path()
    if not database_path.is_file():
        print(f"Database was not found: {database_path}", file=sys.stderr)
        return 2

    database = AlertDatabase(database_path)
    try:
        health = database.validate()
    except (RuntimeError, sqlite3.Error) as error:
        print(f"Database could not be opened: {error}", file=sys.stderr)
        return 2

    static_path = Path(__file__).resolve().parent / "static"
    try:
        server = ViewerServer((arguments.host, arguments.port), database, static_path)
    except OSError as error:
        print(
            f"Viewer could not listen on {arguments.host}:{arguments.port}: {error}",
            file=sys.stderr,
        )
        return 2
    url = f"http://{DEFAULT_HOST}:{arguments.port}"
    print("ZigZagElliot Alert Viewer")
    print(f"Database: {health['database']}")
    print(f"Alerts: {health['alert_count']} / journal: {health['journal_mode']}")
    print(f"Open: {url}")
    print("Close this window or press Ctrl+C to stop.")
    if arguments.open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        print("\nStopping viewer...")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
