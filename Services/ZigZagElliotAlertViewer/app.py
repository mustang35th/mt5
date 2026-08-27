#!/usr/bin/env python3
"""ZigZagElliot alert database read-only local web viewer."""

from __future__ import annotations

import argparse
import base64
import ctypes
import csv
import io
import json
import os
import secrets
import sys
import threading
import webbrowser
from collections.abc import Collection, Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote, unquote, urlparse

try:
    from sqlalchemy import MetaData, create_engine, event, select, text
    from sqlalchemy.engine import Connection, Row, RowMapping
    from sqlalchemy.exc import SQLAlchemyError
    from sqlalchemy.ext.automap import automap_base
    from sqlalchemy.orm import Session
    from sqlalchemy.pool import NullPool
except ModuleNotFoundError as error:
    print(
        "SQLAlchemy is required. Run: python -m pip install -r requirements.txt",
        file=sys.stderr,
    )
    raise SystemExit(2) from error


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5187
DEFAULT_DATABASE_NAME = "mstng-zigzag-elliot-alert.sqlite"
MAX_PAGE_SIZE = 200
MAX_SEARCH_LENGTH = 200
MAX_TIME_FRAME_FILTERS = 32
SQLITE_MAX_INTEGER = (1 << 63) - 1
OBSERVATION_SYNC_TIME_FRAMES = {"MN1", "W1", "D1", "H4"}
W1_TIME_FRAME = 32769
REACT_CSP_NONCE_PLACEHOLDER = "__CSP_NONCE__"

W1_CONFIRMATION_ALERT_COLUMNS = {
    "w1_confirmation_mode",
    "w1_confirmation_state",
    "is_w1_confirmation_available",
    "is_w1_confirmation_valid",
    "is_w1_direction_matched",
    "w1_ema200_direction",
    "is_w1_ema200_matched",
    "is_w1_confirmation_passed",
}
H1_DIRECTION_ALIGNMENT_ALERT_COLUMNS = {
    "h1_direction_alignment_mode",
    "h1_direction_alignment_state",
    "is_h1_direction_alignment_available",
    "is_h1_direction_alignment_valid",
    "h1_direction_alignment_direction",
    "is_h1_mn1_direction_matched",
    "is_h1_w1_direction_matched",
    "is_h1_direction_alignment_passed",
}
EMA200_TIME_FRAME_COLUMNS = {
    "is_ema200_buy",
    "is_ema200_sell",
}
W1_CONFIRMATION_MODES = {
    "OFF",
    "OBSERVE_ONLY",
    "DIRECTION_OR_EMA200",
    "DIRECTION_AND_EMA200",
}
W1_CONFIRMATION_STATES = {
    "NOT_EVALUATED",
    "NOT_APPLICABLE",
    "OFF",
    "UNAVAILABLE",
    "INVALID",
    "STRONG",
    "DIRECTION_ONLY",
    "EMA_CONFLICT",
    "EMA_ONLY",
    "REJECT_NONE",
    "REJECT",
}
H1_DIRECTION_ALIGNMENT_MODES = {
    "D1_TO_H1",
    "MN1_TO_H1_OBSERVE",
    "MN1_TO_H1_REQUIRED",
    "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED",
    "INVALID",
}
H1_DIRECTION_ALIGNMENT_STATES = {
    "NOT_EVALUATED",
    "NOT_APPLICABLE",
    "D1_TO_H1",
    "FULL_BUY",
    "FULL_SELL",
    "MN1_MISMATCH",
    "W1_MISMATCH",
    "MN1_W1_MISMATCH",
    "EMA200_FALLBACK_BUY",
    "EMA200_FALLBACK_SELL",
    "MN1_EMA200_MISMATCH",
    "UNAVAILABLE",
    "INVALID",
}

# Keep this classification aligned with SymbolNameInfoAll.setGmo().
GMO_SYMBOL_TARGETS = {
    "USDJPY": True,
    "EURJPY": True,
    "GBPJPY": True,
    "AUDJPY": True,
    "NZDJPY": True,
    "CADJPY": True,
    "CHFJPY": True,
    "EURUSD": True,
    "GBPUSD": True,
    "AUDUSD": True,
    "NZDUSD": True,
    "USDCAD": False,
    "USDCHF": True,
    "EURGBP": True,
    "GBPAUD": True,
    "GBPNZD": False,
    "GBPCAD": False,
    "GBPCHF": True,
    "EURAUD": True,
    "EURNZD": False,
    "EURCAD": False,
    "EURCHF": True,
    "AUDNZD": True,
    "AUDCAD": False,
    "AUDCHF": False,
    "NZDCAD": False,
    "NZDCHF": False,
    "CADCHF": False,
}

STATIC_CONTENT_TYPES = {
    "/legacy": ("index.html", "text/html; charset=utf-8"),
    "/legacy/": ("index.html", "text/html; charset=utf-8"),
    "/legacy/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/styles.css": ("styles.css", "text/css; charset=utf-8"),
}

REACT_INDEX_PATHS = {
    "/",
    "/index.html",
    "/react",
    "/react/",
    "/react/index.html",
}

REACT_ASSET_CONTENT_TYPES = {
    ".css": "text/css; charset=utf-8",
    ".ico": "image/x-icon",
    ".js": "text/javascript; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
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
    "w1_confirmation_state": "w1_confirmation_state COLLATE NOCASE",
    "w1_confirmation_mode": "w1_confirmation_mode COLLATE NOCASE",
    "created_at": "created_at",
}

OBSERVATION_SORT_COLUMNS = {
    "id": "id",
    "run_id": "run_id",
    "source_mode": "source_mode COLLATE NOCASE",
    "source_server": "source_server COLLATE NOCASE",
    "symbol_name": "symbol_name COLLATE NOCASE",
    "anchor_jst_time": "anchor_jst_time",
    "anchor_bar_time": "anchor_bar_time",
    "server_time": "anchor_bar_time",
    "anchor_time_frame": "anchor_time_frame",
    "capture_phase": "capture_phase COLLATE NOCASE",
    "analysis_version": "analysis_version COLLATE NOCASE",
    "created_at": "created_at",
}

OBSERVATION_REQUIRED_COLUMNS = {
    "zigzag_elliot_observations": {
        "id",
        "run_id",
        "source_mode",
        "source_server",
        "symbol_name",
        "anchor_time_frame",
        "anchor_time_frame_text",
        "anchor_bar_time",
        "anchor_bar_time_text",
        "anchor_jst_time",
        "anchor_jst_time_text",
        "capture_phase",
        "analysis_version",
        "analysis_input_hash",
        "snapshot_hash",
        "time_frame_count",
        "created_at",
        "created_at_text",
    },
    "zigzag_elliot_observation_timeframes": {
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
    },
}

ANALYSIS_PROFILE_RUN_COLUMNS = {
    "analysis_input_text",
    "analysis_input_hash",
}

BOOLEAN_COLUMNS = {
    "is_judge",
    "is_entry_count_match",
    "is_entry_evaluated",
    "is_alert",
    "is_entry",
    "is_send_mail",
    "is_entry_wave",
    "is_ema200_available",
    "is_ema200_distance_within",
    "mn1_is_ema200_available",
    "mn1_is_ema200_buy",
    "mn1_is_ema200_sell",
    "w1_is_ema200_available",
    "w1_is_ema200_buy",
    "w1_is_ema200_sell",
    "d1_is_ema200_available",
    "d1_is_ema200_buy",
    "d1_is_ema200_sell",
    "h4_is_ema200_available",
    "h4_is_ema200_buy",
    "h4_is_ema200_sell",
    "h1_is_ema200_available",
    "h1_is_ema200_buy",
    "h1_is_ema200_sell",
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
    "is_anchor_time_frame",
    "is_fibonacci_available",
    "is_fibonacci_expansion_available",
    "is_elliot_alphabet",
    "is_sub_elliot_available",
    "is_original_elliot_available",
    "is_correct",
    "is_w1_aligned",
    "is_w1_confirmation_available",
    "is_w1_confirmation_valid",
    "is_w1_direction_matched",
    "is_w1_ema200_matched",
    "is_w1_confirmation_passed",
    "is_w1_confirmation_legacy",
    "is_h1_direction_alignment_available",
    "is_h1_direction_alignment_valid",
    "is_h1_mn1_direction_matched",
    "is_h1_w1_direction_matched",
    "is_h1_direction_alignment_passed",
    "is_h1_direction_alignment_legacy",
    "w1_is_buy",
    "w1_is_wave_confirmed",
    "w1_is_wave_motive",
    "w1_is_wave_uptrend",
    "analysis_profile_is_legacy",
    "is_legacy",
    "is_gmo_target",
    "signal_is_left_censored",
    "signal_is_right_censored",
    "signal_has_data_gap_before",
    "signal_has_data_gap_after",
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


@dataclass(frozen=True)
class ObservationFilters:
    """Validated filters for H1 observation list and summary endpoints."""

    where_sql: str
    signal_candidate_where_sql: str
    signal_result_where_sql: str
    parameters: dict[str, Any]
    analysis_profile_kind: str | None
    group_continuous: bool
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
    """Build a SQLAlchemy SQLite read-only URI with Windows drive syntax."""

    resolved = database_path.resolve()
    path_text = resolved.as_posix()
    return f"sqlite+pysqlite:///file:{quote(path_text, safe='/:')}?mode=ro&uri=true"


def values_to_dict(values: Mapping[str, Any]) -> dict[str, Any]:
    """Convert mapped database values to JSON-ready values."""

    result: dict[str, Any] = {}
    for key, value in values.items():
        if key in BOOLEAN_COLUMNS and value is not None:
            result[key] = bool(value)
        else:
            result[key] = value
    return result


def row_to_dict(
    row: Row[Any] | RowMapping | Mapping[str, Any] | None,
) -> dict[str, Any] | None:
    """Convert a SQLAlchemy row to JSON-ready values."""

    if row is None:
        return None
    if isinstance(row, Row):
        return values_to_dict(row._mapping)
    return values_to_dict(row)


def model_to_dict(entity: Any | None) -> dict[str, Any] | None:
    """Convert one reflected ORM entity to JSON-ready values."""

    if entity is None:
        return None
    values = {
        column.key: getattr(entity, column.key) for column in entity.__table__.columns
    }
    return values_to_dict(values)


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


def parse_jst_time(value: str) -> str:
    """Validate one exact H1 JST clock value in HH:00 format."""

    try:
        parsed = datetime.strptime(value, "%H:%M")
    except ValueError as error:
        raise RequestError("jstTime must use HH:00") from error
    if parsed.strftime("%H:%M") != value or parsed.minute != 0:
        raise RequestError("jstTime must use HH:00")
    return value


def escape_like(value: str) -> str:
    """Escape LIKE wildcard characters for literal free-text matching."""

    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def canonical_symbol_name(symbol_name: str | None) -> str | None:
    """Resolve a canonical FX pair from a broker prefix/suffix symbol."""

    if not isinstance(symbol_name, str):
        return None
    normalized = symbol_name.strip().upper()
    if not normalized:
        return None
    matches = [symbol for symbol in GMO_SYMBOL_TARGETS if symbol in normalized]
    if len(matches) != 1:
        return None
    return matches[0]


def is_gmo_target(symbol_name: str | None) -> bool:
    """Return whether a canonical or decorated symbol is a GMO target."""

    canonical = canonical_symbol_name(symbol_name)
    if canonical is None:
        return False
    return GMO_SYMBOL_TARGETS[canonical]


def sqlite_is_gmo_target(symbol_name: Any) -> int:
    """Expose the GMO classification to SQLite filtering and projections."""

    return int(is_gmo_target(symbol_name))


def sqlite_is_consecutive_market_h1(
    previous_time: Any,
    current_time: Any,
) -> int:
    """Return whether two stored times are adjacent tradable FX H1 bars."""

    try:
        previous_epoch = int(previous_time)
        current_epoch = int(current_time)
    except (TypeError, ValueError, OverflowError):
        return 0
    elapsed = current_epoch - previous_epoch
    if elapsed == 3600:
        return 1
    if elapsed <= 0:
        return 0

    try:
        previous = datetime.fromtimestamp(previous_epoch, timezone.utc)
        current = datetime.fromtimestamp(current_epoch, timezone.utc)
    except (OSError, OverflowError, ValueError):
        return 0
    is_weekend = (
        elapsed == 49 * 3600
        and previous.weekday() == 4
        and previous.hour == 23
        and previous.minute == 0
        and current.weekday() == 0
        and current.hour == 0
        and current.minute == 0
    )
    is_christmas = (
        elapsed == 25 * 3600
        and previous.year == current.year
        and previous.month == 12
        and previous.day == 24
        and previous.hour == 23
        and previous.minute == 0
        and current.month == 12
        and current.day == 26
        and current.hour == 0
        and current.minute == 0
    )
    is_new_year = (
        elapsed == 25 * 3600
        and current.year == previous.year + 1
        and previous.month == 12
        and previous.day == 31
        and previous.hour == 23
        and previous.minute == 0
        and current.month == 1
        and current.day == 2
        and current.hour == 0
        and current.minute == 0
    )
    return int(is_weekend or is_christmas or is_new_year)


def add_gmo_target_filter(
    value: str | None,
    symbol_column: str,
    clauses: list[str],
    parameters: dict[str, Any],
) -> None:
    """Add one validated GMO target predicate using a bound boolean value."""

    mode = (value or "all").lower()
    if mode not in {"all", "target", "excluded"}:
        raise RequestError("gmoTarget must be target, excluded or all")
    if mode == "all":
        return
    clauses.append(f"is_gmo_target({symbol_column}) = :is_gmo_target")
    parameters["is_gmo_target"] = int(mode == "target")


def analysis_profile_key(
    analysis_version: str,
    analysis_input_hash: str,
    analysis_profile_kind: str,
) -> str:
    """Return a stable opaque key for one exact analysis-profile cohort."""

    payload = json.dumps(
        [analysis_version, analysis_input_hash, analysis_profile_kind],
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    encoded = base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")
    return "ap1_" + encoded


class AlertDatabase:
    """Read-only access layer for the ZigZagElliot alert database."""

    def __init__(self, database_path: Path):
        self.database_path = database_path.resolve()
        self.engine = create_engine(
            database_uri(self.database_path),
            poolclass=NullPool,
            connect_args={"timeout": 5.0},
        )
        event.listen(self.engine, "connect", self.configure_connection)
        self.metadata = MetaData()
        self.orm_base: Any | None = None
        self.models: dict[str, Any] = {}
        self.schema_lock = threading.Lock()

    @staticmethod
    def configure_connection(dbapi_connection: Any, connection_record: Any) -> None:
        """Apply defensive read-only pragmas to every DBAPI connection."""

        del connection_record
        dbapi_connection.create_function(
            "is_gmo_target",
            1,
            sqlite_is_gmo_target,
            deterministic=True,
        )
        dbapi_connection.create_function(
            "is_consecutive_market_h1",
            2,
            sqlite_is_consecutive_market_h1,
            deterministic=True,
        )
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA query_only=ON")
            cursor.execute("PRAGMA busy_timeout=5000")
        finally:
            cursor.close()

    def connect(self) -> Connection:
        """Open a short-lived SQLAlchemy connection."""

        return self.engine.connect()

    def close(self) -> None:
        """Dispose the SQLAlchemy engine and its connection resources."""

        self.engine.dispose()

    def model(self, table_name: str) -> Any:
        """Return a reflected ORM class after schema validation."""

        model = self.models.get(table_name)
        if model is None:
            raise RuntimeError("database schema has not been prepared")
        return model

    def prepare_models(
        self, connection: Connection, table_names: list[str]
    ) -> None:
        """Reflect the existing schema and prepare read-only ORM classes once."""

        if self.models:
            return
        with self.schema_lock:
            if self.models:
                return
            self.metadata.reflect(bind=connection, only=table_names)
            self.orm_base = automap_base(metadata=self.metadata)
            self.orm_base.prepare()
            self.models = {
                table_name: self.orm_base.classes[table_name]
                for table_name in table_names
            }

    @staticmethod
    def table_columns(connection: Connection, table_name: str) -> set[str]:
        """Return reflected SQLite column names without changing the schema."""

        return {
            str(row["name"])
            for row in connection.exec_driver_sql(
                f"PRAGMA table_info({table_name})"
            ).mappings()
        }

    @staticmethod
    def analysis_profile_schema_status(
        connection: Connection,
    ) -> dict[str, Any]:
        """Return availability of the optional run-level analysis profile."""

        actual_columns = AlertDatabase.table_columns(
            connection,
            "zigzag_elliot_alert_runs",
        )
        missing_columns = sorted(ANALYSIS_PROFILE_RUN_COLUMNS - actual_columns)
        if missing_columns:
            return {
                "available": False,
                "reason": "analysis profile columns are not available",
                "missing_columns": missing_columns,
            }
        return {
            "available": True,
            "reason": None,
            "missing_columns": [],
        }

    @staticmethod
    def w1_confirmation_schema_status(
        connection: Connection,
    ) -> dict[str, Any]:
        """Return availability of the optional alert-level W1 diagnosis."""

        actual_columns = AlertDatabase.table_columns(
            connection,
            "zigzag_elliot_alerts",
        )
        missing_columns = sorted(W1_CONFIRMATION_ALERT_COLUMNS - actual_columns)
        return {
            "available": not missing_columns,
            "reason": None if not missing_columns else "W1 confirmation columns are not available",
            "missing_columns": missing_columns,
        }

    @staticmethod
    def w1_confirmation_projection(connection: Connection) -> str:
        """Return real W1 columns or legacy-safe projected defaults."""

        if AlertDatabase.w1_confirmation_schema_status(connection)["available"]:
            return """
                a.w1_confirmation_mode,
                a.w1_confirmation_state,
                a.is_w1_confirmation_available,
                a.is_w1_confirmation_valid,
                a.is_w1_direction_matched,
                a.w1_ema200_direction,
                a.is_w1_ema200_matched,
                a.is_w1_confirmation_passed,
                CASE WHEN a.w1_confirmation_state = 'NOT_EVALUATED'
                     THEN 1 ELSE 0 END AS is_w1_confirmation_legacy,
            """
        return """
            'OFF' AS w1_confirmation_mode,
            'NOT_EVALUATED' AS w1_confirmation_state,
            0 AS is_w1_confirmation_available,
            0 AS is_w1_confirmation_valid,
            0 AS is_w1_direction_matched,
            'NONE' AS w1_ema200_direction,
            0 AS is_w1_ema200_matched,
            1 AS is_w1_confirmation_passed,
            1 AS is_w1_confirmation_legacy,
        """

    @staticmethod
    def h1_direction_alignment_schema_status(
        connection: Connection,
    ) -> dict[str, Any]:
        """Return availability of the optional H1 direction diagnosis."""

        actual_columns = AlertDatabase.table_columns(
            connection,
            "zigzag_elliot_alerts",
        )
        missing_columns = sorted(
            H1_DIRECTION_ALIGNMENT_ALERT_COLUMNS - actual_columns
        )
        return {
            "available": not missing_columns,
            "reason": None
            if not missing_columns
            else "H1 direction alignment columns are not available",
            "missing_columns": missing_columns,
        }

    @staticmethod
    def h1_direction_alignment_projection(connection: Connection) -> str:
        """Return real H1 direction columns or legacy-safe defaults."""

        if AlertDatabase.h1_direction_alignment_schema_status(connection)[
            "available"
        ]:
            return """
                a.h1_direction_alignment_mode,
                a.h1_direction_alignment_state,
                a.is_h1_direction_alignment_available,
                a.is_h1_direction_alignment_valid,
                a.h1_direction_alignment_direction,
                a.is_h1_mn1_direction_matched,
                a.is_h1_w1_direction_matched,
                a.is_h1_direction_alignment_passed,
                CASE WHEN a.h1_direction_alignment_state = 'NOT_EVALUATED'
                     THEN 1 ELSE 0 END AS is_h1_direction_alignment_legacy,
            """
        return """
            'D1_TO_H1' AS h1_direction_alignment_mode,
            'NOT_EVALUATED' AS h1_direction_alignment_state,
            0 AS is_h1_direction_alignment_available,
            0 AS is_h1_direction_alignment_valid,
            'NONE' AS h1_direction_alignment_direction,
            0 AS is_h1_mn1_direction_matched,
            0 AS is_h1_w1_direction_matched,
            0 AS is_h1_direction_alignment_passed,
            1 AS is_h1_direction_alignment_legacy,
        """

    @staticmethod
    def ema200_projection(connection: Connection) -> str:
        """Return list EMA200 flags with legacy-safe defaults."""

        actual_columns = AlertDatabase.table_columns(
            connection,
            "zigzag_elliot_alert_timeframes",
        )
        if EMA200_TIME_FRAME_COLUMNS.issubset(actual_columns):
            return """
                CASE WHEN current_tf.id IS NULL THEN 0 ELSE 1 END
                    AS is_ema200_available,
                COALESCE(current_tf.is_ema200_buy, 0) AS is_ema200_buy,
                COALESCE(current_tf.is_ema200_sell, 0) AS is_ema200_sell,
                CASE WHEN mn1.id IS NULL THEN 0 ELSE 1 END
                    AS mn1_is_ema200_available,
                COALESCE(mn1.is_ema200_buy, 0) AS mn1_is_ema200_buy,
                COALESCE(mn1.is_ema200_sell, 0) AS mn1_is_ema200_sell,
                CASE WHEN w1.id IS NULL THEN 0 ELSE 1 END
                    AS w1_is_ema200_available,
                COALESCE(w1.is_ema200_buy, 0) AS w1_is_ema200_buy,
                COALESCE(w1.is_ema200_sell, 0) AS w1_is_ema200_sell,
                CASE WHEN d1.id IS NULL THEN 0 ELSE 1 END
                    AS d1_is_ema200_available,
                COALESCE(d1.is_ema200_buy, 0) AS d1_is_ema200_buy,
                COALESCE(d1.is_ema200_sell, 0) AS d1_is_ema200_sell,
                CASE WHEN h4.id IS NULL THEN 0 ELSE 1 END
                    AS h4_is_ema200_available,
                COALESCE(h4.is_ema200_buy, 0) AS h4_is_ema200_buy,
                COALESCE(h4.is_ema200_sell, 0) AS h4_is_ema200_sell,
                CASE WHEN h1.id IS NULL THEN 0 ELSE 1 END
                    AS h1_is_ema200_available,
                COALESCE(h1.is_ema200_buy, 0) AS h1_is_ema200_buy,
                COALESCE(h1.is_ema200_sell, 0) AS h1_is_ema200_sell,
            """
        return """
            0 AS is_ema200_available,
            0 AS is_ema200_buy,
            0 AS is_ema200_sell,
            0 AS mn1_is_ema200_available,
            0 AS mn1_is_ema200_buy,
            0 AS mn1_is_ema200_sell,
            0 AS w1_is_ema200_available,
            0 AS w1_is_ema200_buy,
            0 AS w1_is_ema200_sell,
            0 AS d1_is_ema200_available,
            0 AS d1_is_ema200_buy,
            0 AS d1_is_ema200_sell,
            0 AS h4_is_ema200_available,
            0 AS h4_is_ema200_buy,
            0 AS h4_is_ema200_sell,
            0 AS h1_is_ema200_available,
            0 AS h1_is_ema200_buy,
            0 AS h1_is_ema200_sell,
        """

    @staticmethod
    def apply_w1_confirmation_defaults(
        alert: dict[str, Any],
    ) -> None:
        """Normalize a reflected legacy alert to the current response contract."""

        defaults: dict[str, Any] = {
            "w1_confirmation_mode": "OFF",
            "w1_confirmation_state": "NOT_EVALUATED",
            "is_w1_confirmation_available": False,
            "is_w1_confirmation_valid": False,
            "is_w1_direction_matched": False,
            "w1_ema200_direction": "NONE",
            "is_w1_ema200_matched": False,
            "is_w1_confirmation_passed": True,
        }
        if not W1_CONFIRMATION_ALERT_COLUMNS.issubset(alert):
            alert.update(defaults)
        else:
            for key, value in defaults.items():
                if alert[key] is None:
                    alert[key] = value
        alert["is_w1_confirmation_legacy"] = (
            alert["w1_confirmation_state"] == "NOT_EVALUATED"
        )

    @staticmethod
    def apply_h1_direction_alignment_defaults(
        alert: dict[str, Any],
    ) -> None:
        """Normalize a reflected legacy alert to the H1 diagnosis contract."""

        defaults: dict[str, Any] = {
            "h1_direction_alignment_mode": "D1_TO_H1",
            "h1_direction_alignment_state": "NOT_EVALUATED",
            "is_h1_direction_alignment_available": False,
            "is_h1_direction_alignment_valid": False,
            "h1_direction_alignment_direction": "NONE",
            "is_h1_mn1_direction_matched": False,
            "is_h1_w1_direction_matched": False,
            "is_h1_direction_alignment_passed": False,
        }
        if not H1_DIRECTION_ALIGNMENT_ALERT_COLUMNS.issubset(alert):
            alert.update(defaults)
        else:
            for key, value in defaults.items():
                if alert[key] is None:
                    alert[key] = value
        alert["is_h1_direction_alignment_legacy"] = (
            alert["h1_direction_alignment_state"] == "NOT_EVALUATED"
        )

    @staticmethod
    def observation_schema_status(connection: Connection) -> dict[str, Any]:
        """Return optional observation-table availability without changing schema."""

        rows = connection.execute(
            text("SELECT name FROM sqlite_schema WHERE type='table'")
        ).mappings()
        actual_tables = {str(row["name"]) for row in rows}
        missing_tables = sorted(set(OBSERVATION_REQUIRED_COLUMNS) - actual_tables)
        if missing_tables:
            return {
                "available": False,
                "reason": "observation tables are not available",
            }
        for table_name, expected_columns in OBSERVATION_REQUIRED_COLUMNS.items():
            actual_columns = AlertDatabase.table_columns(connection, table_name)
            if expected_columns - actual_columns:
                return {
                    "available": False,
                    "reason": "observation table schema is not supported",
                }
        jst_columns = {
            "zigzag_elliot_observations": (
                "anchor_jst_time",
                "anchor_jst_time_text",
            ),
            "zigzag_elliot_observation_timeframes": (
                "latest_point_jst_time",
                "latest_point_jst_time_text",
            ),
        }
        for table_name, (time_column, text_column) in jst_columns.items():
            sql = (
                f"SELECT 1 FROM {table_name} "
                f"WHERE {time_column} <= 0 OR {text_column} = '' LIMIT 1"
            )
            if connection.exec_driver_sql(sql).first() is not None:
                return {
                    "available": False,
                    "reason": "observation JST migration is incomplete",
                }
        return {"available": True, "reason": None}

    @staticmethod
    def observation_spread_available(connection: Connection) -> bool:
        """Return whether observation parents contain captured spread values."""

        return "spread_pips" in AlertDatabase.table_columns(
            connection,
            "zigzag_elliot_observations",
        )

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
        with self.connect() as connection:
            rows = connection.execute(
                text("SELECT name FROM sqlite_schema WHERE type='table'")
            ).mappings()
            actual_tables = {str(row["name"]) for row in rows}
            missing = sorted(set(required_columns) - actual_tables)
            if missing:
                raise RuntimeError("required tables are missing: " + ", ".join(missing))
            for table_name, expected_columns in required_columns.items():
                actual_columns = self.table_columns(connection, table_name)
                missing_columns = sorted(expected_columns - actual_columns)
                if missing_columns:
                    raise RuntimeError(
                        f"required columns are missing from {table_name}: "
                        + ", ".join(missing_columns)
                    )
            self.prepare_models(connection, list(required_columns))
            journal_mode = connection.exec_driver_sql("PRAGMA journal_mode").scalar_one()
            alert_count = connection.execute(
                text("SELECT COUNT(*) FROM zigzag_elliot_alerts")
            ).scalar_one()
            observation_status = self.observation_schema_status(connection)
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            w1_confirmation_status = self.w1_confirmation_schema_status(connection)
            h1_direction_alignment_status = (
                self.h1_direction_alignment_schema_status(connection)
            )
            observation_count = 0
            if observation_status["available"]:
                observation_count = connection.execute(
                    text("SELECT COUNT(*) FROM zigzag_elliot_observations")
                ).scalar_one()
        return {
            "database": str(self.database_path),
            "journal_mode": journal_mode,
            "alert_count": alert_count,
            "observation_available": observation_status["available"],
            "observation_count": observation_count,
            "analysis_profile_available": analysis_profile_status["available"],
            "analysis_profile_reason": analysis_profile_status["reason"],
            "w1_confirmation_available": w1_confirmation_status["available"],
            "w1_confirmation_reason": w1_confirmation_status["reason"],
            "h1_direction_alignment_available": (
                h1_direction_alignment_status["available"]
            ),
            "h1_direction_alignment_reason": (
                h1_direction_alignment_status["reason"]
            ),
        }

    def runs(self) -> dict[str, Any]:
        """Return all runs with alert range summaries."""

        base_select = """
            SELECT r.id, r.run_uid, r.schema_version, r.source_mode, r.source,
                   r.program_name, r.program_version, r.strategy,
                   r.strategy_version, r.analysis_version, r.source_server,
                   r.source_login, r.source_chart_id, r.terminal_build,
                   r.tester_from, r.tester_to, r.tester_model, r.input_hash,
                   r.started_at, r.started_at_text, r.market_started_at,
                   r.market_started_at_text, r.created_at, r.created_at_text,
                   {analysis_profile_columns},
                   COUNT(a.id) AS alert_count,
                   MIN(a.current_bar_time) AS first_alert_time,
                   MIN(a.current_bar_time_text) AS first_alert_time_text,
                   MAX(a.current_bar_time) AS last_alert_time,
                   MAX(a.current_bar_time_text) AS last_alert_time_text,
                   GROUP_CONCAT(DISTINCT a.symbol_name) AS symbols,
                   {observation_columns}
            FROM zigzag_elliot_alert_runs AS r
            LEFT JOIN zigzag_elliot_alerts AS a ON a.run_id = r.id
            {observation_join}
            GROUP BY r.id
            ORDER BY r.id DESC
        """
        with self.connect() as connection:
            observation_status = self.observation_schema_status(connection)
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            legacy_hash_expression = "NULL"
            if observation_status["available"]:
                legacy_hash_expression = """
                    (
                        SELECT legacy_profile.analysis_input_hash
                        FROM zigzag_elliot_observations AS legacy_profile
                        WHERE legacy_profile.run_id = r.id
                        ORDER BY legacy_profile.anchor_jst_time DESC,
                                 legacy_profile.id DESC
                        LIMIT 1
                    )
                """
            if analysis_profile_status["available"]:
                analysis_profile_columns = f"""
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                        THEN r.analysis_input_text
                        ELSE NULL
                    END AS analysis_input_text,
                    COALESCE(
                        NULLIF(r.analysis_input_hash, ''),
                        {legacy_hash_expression}
                    ) AS analysis_input_hash,
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                        THEN 0
                        ELSE 1
                    END AS analysis_profile_is_legacy,
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                        THEN 'profile'
                        ELSE 'legacy'
                    END AS analysis_profile_kind
                """
            else:
                analysis_profile_columns = f"""
                    NULL AS analysis_input_text,
                    {legacy_hash_expression} AS analysis_input_hash,
                    1 AS analysis_profile_is_legacy,
                    'legacy' AS analysis_profile_kind
                """
            if observation_status["available"]:
                observation_columns = """
                    COALESCE(MAX(observation_stats.observation_count), 0)
                        AS observation_count,
                    MAX(observation_stats.first_observation_time)
                        AS first_observation_time,
                    MAX(observation_stats.first_observation_time_text)
                        AS first_observation_time_text,
                    MAX(observation_stats.last_observation_time)
                        AS last_observation_time,
                    MAX(observation_stats.last_observation_time_text)
                        AS last_observation_time_text,
                    MAX(observation_stats.first_observation_jst_time)
                        AS first_observation_jst_time,
                    MAX(observation_stats.first_observation_jst_time_text)
                        AS first_observation_jst_time_text,
                    MAX(observation_stats.last_observation_jst_time)
                        AS last_observation_jst_time,
                    MAX(observation_stats.last_observation_jst_time_text)
                        AS last_observation_jst_time_text,
                    MAX(observation_stats.observation_symbols)
                        AS observation_symbols
                """
                observation_join = """
                    LEFT JOIN (
                        SELECT run_id, COUNT(*) AS observation_count,
                               MIN(anchor_bar_time) AS first_observation_time,
                               MIN(anchor_bar_time_text)
                                   AS first_observation_time_text,
                               MAX(anchor_bar_time) AS last_observation_time,
                               MAX(anchor_bar_time_text)
                                   AS last_observation_time_text,
                               MIN(anchor_jst_time)
                                   AS first_observation_jst_time,
                               MIN(anchor_jst_time_text)
                                   AS first_observation_jst_time_text,
                               MAX(anchor_jst_time)
                                   AS last_observation_jst_time,
                               MAX(anchor_jst_time_text)
                                   AS last_observation_jst_time_text,
                               GROUP_CONCAT(DISTINCT symbol_name)
                                   AS observation_symbols
                        FROM zigzag_elliot_observations
                        GROUP BY run_id
                    ) AS observation_stats ON observation_stats.run_id = r.id
                """
            else:
                observation_columns = """
                    0 AS observation_count,
                    NULL AS first_observation_time,
                    NULL AS first_observation_time_text,
                    NULL AS last_observation_time,
                    NULL AS last_observation_time_text,
                    NULL AS first_observation_jst_time,
                    NULL AS first_observation_jst_time_text,
                    NULL AS last_observation_jst_time,
                    NULL AS last_observation_jst_time_text,
                    NULL AS observation_symbols
                """
                observation_join = ""
            sql = base_select.format(
                analysis_profile_columns=analysis_profile_columns,
                observation_columns=observation_columns,
                observation_join=observation_join,
            )
            rows = connection.execute(text(sql)).mappings()
            items = [row_to_dict(row) for row in rows]
        return {
            "items": items,
            "count": len(items),
            "analysis_profile_available": analysis_profile_status["available"],
            "analysis_profile_reason": analysis_profile_status["reason"],
        }

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
        with self.connect() as connection:
            for output_name, column_name in fields.items():
                sql = (
                    f"SELECT DISTINCT {column_name} AS value "
                    "FROM zigzag_elliot_alerts "
                    f"WHERE {column_name} <> '' ORDER BY {column_name} COLLATE NOCASE"
                )
                rows = connection.execute(text(sql)).mappings()
                result[output_name] = [row["value"] for row in rows]
            result["w1_confirmation_states"] = sorted(W1_CONFIRMATION_STATES)
            result["w1_confirmation_modes"] = sorted(W1_CONFIRMATION_MODES)
            result["w1_confirmation_available"] = (
                self.w1_confirmation_schema_status(connection)["available"]
            )
            result["h1_direction_alignment_modes"] = sorted(
                H1_DIRECTION_ALIGNMENT_MODES
            )
            result["h1_direction_alignment_states"] = sorted(
                H1_DIRECTION_ALIGNMENT_STATES
            )
            result["h1_direction_alignment_available"] = (
                self.h1_direction_alignment_schema_status(connection)[
                    "available"
                ]
            )
        return result

    def observation_options(self) -> dict[str, Any]:
        """Return filter values from the optional H1 observation tables."""

        with self.connect() as connection:
            status = self.observation_schema_status(connection)
            if not status["available"]:
                return {
                    "available": False,
                    "symbols": [],
                    "source_modes": [],
                    "analysis_versions": [],
                    "analysis_profile_available": False,
                    "analysis_profile_reason": status["reason"],
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
                }
            fields = {
                "symbols": "symbol_name",
                "source_modes": "source_mode",
                "analysis_versions": "analysis_version",
            }
            result: dict[str, Any] = {"available": True}
            for output_name, column_name in fields.items():
                sql = (
                    f"SELECT DISTINCT {column_name} AS value "
                    "FROM zigzag_elliot_observations "
                    f"WHERE {column_name} <> '' "
                    f"ORDER BY {column_name} COLLATE NOCASE"
                )
                rows = connection.execute(text(sql)).mappings()
                result[output_name] = [row["value"] for row in rows]
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            profile_classification_sql = """
                NULL AS analysis_input_text,
                'legacy' AS analysis_profile_kind
            """
            if analysis_profile_status["available"]:
                profile_classification_sql = """
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                         AND r.analysis_version = o.analysis_version
                         AND r.analysis_input_hash = o.analysis_input_hash
                        THEN r.analysis_input_text
                        ELSE NULL
                    END AS analysis_input_text,
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                         AND r.analysis_version = o.analysis_version
                         AND r.analysis_input_hash = o.analysis_input_hash
                        THEN 'profile'
                        ELSE 'legacy'
                    END AS analysis_profile_kind
                """
            profile_sql = f"""
                WITH profile_observation_rows AS (
                    SELECT o.id, o.analysis_version, o.analysis_input_hash,
                           o.source_mode, o.anchor_jst_time,
                           o.anchor_jst_time_text,
                           {profile_classification_sql}
                    FROM zigzag_elliot_observations AS o
                    INNER JOIN zigzag_elliot_alert_runs AS r
                            ON r.id = o.run_id
                    WHERE o.analysis_input_hash <> ''
                )
                SELECT analysis_input_hash,
                       MAX(analysis_input_text) AS analysis_input_text,
                       analysis_version,
                       analysis_profile_kind,
                       COUNT(*) AS observation_count,
                       MAX(anchor_jst_time) AS last_anchor_jst_time,
                       MAX(anchor_jst_time_text) AS last_anchor_jst_time_text,
                       GROUP_CONCAT(DISTINCT source_mode) AS source_modes_text,
                       MAX(id) AS last_observation_id,
                       MAX(CASE WHEN source_mode = 'LIVE'
                                THEN id END) AS last_live_id,
                       MAX(CASE WHEN source_mode = 'TESTER'
                                THEN id END) AS last_tester_id
                FROM profile_observation_rows
                GROUP BY analysis_version, analysis_input_hash,
                         analysis_profile_kind
                ORDER BY last_observation_id DESC
            """
            profile_rows = connection.execute(text(profile_sql)).mappings()
            profile_items: list[dict[str, Any]] = []
            selection_items: list[dict[str, Any]] = []
            profile_items_by_key: dict[str, dict[str, Any]] = {}
            for row in profile_rows:
                selection_item = dict(row)
                source_modes_text = str(selection_item.pop("source_modes_text") or "")
                source_modes = sorted(
                    mode for mode in source_modes_text.split(",") if mode
                )
                analysis_input_text = selection_item["analysis_input_text"]
                analysis_version = str(selection_item["analysis_version"])
                analysis_input_hash = str(selection_item["analysis_input_hash"])
                analysis_profile_kind = str(
                    selection_item["analysis_profile_kind"]
                )
                profile_key = analysis_profile_key(
                    analysis_version,
                    analysis_input_hash,
                    analysis_profile_kind,
                )
                selection_item["source_modes"] = source_modes
                selection_item["profile_key"] = profile_key
                selection_item["is_legacy"] = analysis_profile_kind == "legacy"
                selection_items.append(selection_item)
                profile_item = {
                    "profile_key": profile_key,
                    "analysis_profile_kind": analysis_profile_kind,
                    "analysis_input_hash": analysis_input_hash,
                    "analysis_input_text": analysis_input_text,
                    "analysis_version": analysis_version,
                    "observation_count": selection_item["observation_count"],
                    "last_anchor_jst_time": selection_item[
                        "last_anchor_jst_time"
                    ],
                    "last_anchor_jst_time_text": selection_item[
                        "last_anchor_jst_time_text"
                    ],
                    "source_modes": source_modes,
                    "is_legacy": analysis_profile_kind == "legacy",
                }
                profile_items.append(profile_item)
                profile_items_by_key[profile_key] = profile_item

            def default_profile(
                source_mode: str | None,
            ) -> dict[str, Any] | None:
                candidates = selection_items
                id_key = "last_observation_id"
                if source_mode == "LIVE":
                    candidates = [
                        item for item in selection_items
                        if "LIVE" in item["source_modes"]
                    ]
                    id_key = "last_live_id"
                elif source_mode == "TESTER":
                    candidates = [
                        item for item in selection_items
                        if "TESTER" in item["source_modes"]
                    ]
                    id_key = "last_tester_id"
                profiled = [
                    item for item in candidates
                    if item["analysis_profile_kind"] == "profile"
                ]
                if profiled:
                    candidates = profiled
                if not candidates:
                    return None
                latest = max(
                    candidates,
                    key=lambda item: int(item[id_key] or 0),
                )
                return profile_items_by_key[str(latest["profile_key"])]

            default_profiles = {
                "all": default_profile(None),
                "LIVE": default_profile("LIVE"),
                "TESTER": default_profile("TESTER"),
            }
            default_profile_keys = {
                mode: item["profile_key"] if item is not None else None
                for mode, item in default_profiles.items()
            }
            default_hashes = {
                mode: item["analysis_input_hash"] if item is not None else None
                for mode, item in default_profiles.items()
            }
            result["analysis_profile_available"] = analysis_profile_status[
                "available"
            ]
            result["analysis_profile_reason"] = analysis_profile_status["reason"]
            result["analysis_profiles"] = profile_items
            result["default_analysis_input_hash"] = default_hashes["all"]
            result["default_analysis_input_hashes"] = default_hashes
            result["default_analysis_profile_keys"] = default_profile_keys
            result["default_analysis_profiles"] = default_profiles
        return result

    @staticmethod
    def parse_observation_filters(
        query: dict[str, list[str]],
    ) -> ObservationFilters:
        """Validate H1 observation filters and fixed sort identifiers."""

        def first(name: str) -> str | None:
            values = query.get(name)
            if not values:
                return None
            return values[0].strip()

        clauses: list[str] = []
        signal_candidate_clauses: list[str] = []
        signal_result_clauses: list[str] = []
        parameters: dict[str, Any] = {}

        group_mode = (first("groupMode") or "H1").upper()
        if group_mode not in {"H1", "SIGNAL"}:
            raise RequestError("groupMode must be H1 or SIGNAL")
        group_continuous = group_mode == "SIGNAL"

        source_mode = (first("sourceMode") or "all").upper()
        if source_mode not in {"ALL", "LIVE", "TESTER"}:
            raise RequestError("sourceMode must be LIVE, TESTER or all")
        if source_mode != "ALL":
            clauses.append("o.source_mode = :source_mode")
            signal_candidate_clauses.append("o.source_mode = :source_mode")
            parameters["source_mode"] = source_mode

        run_id_text = first("runId")
        if run_id_text:
            run_id = positive_int(run_id_text, "runId", 1)
            clauses.append("o.run_id = :run_id")
            signal_candidate_clauses.append("o.run_id = :run_id")
            parameters["run_id"] = run_id

        symbol = first("symbol")
        if symbol:
            clauses.append("o.symbol_name = :symbol_name")
            signal_candidate_clauses.append("o.symbol_name = :symbol_name")
            parameters["symbol_name"] = symbol

        add_gmo_target_filter(
            first("gmoTarget"),
            "o.symbol_name",
            clauses,
            parameters,
        )
        add_gmo_target_filter(
            first("gmoTarget"),
            "o.symbol_name",
            signal_candidate_clauses,
            parameters,
        )

        analysis_version = first("analysisVersion")
        if analysis_version:
            clauses.append("o.analysis_version = :analysis_version")
            signal_candidate_clauses.append(
                "o.analysis_version = :analysis_version"
            )
            parameters["analysis_version"] = analysis_version

        analysis_input_hash = first("analysisInputHash")
        if analysis_input_hash:
            if len(analysis_input_hash) > MAX_SEARCH_LENGTH:
                raise RequestError(
                    f"analysisInputHash must be at most {MAX_SEARCH_LENGTH} characters"
                )
            clauses.append(
                "o.analysis_input_hash <> '' "
                "AND o.analysis_input_hash = :analysis_input_hash"
            )
            signal_candidate_clauses.append(
                "o.analysis_input_hash <> '' "
                "AND o.analysis_input_hash = :analysis_input_hash"
            )
            parameters["analysis_input_hash"] = analysis_input_hash

        analysis_profile_kind = first("analysisProfileKind")
        if analysis_profile_kind:
            analysis_profile_kind = analysis_profile_kind.lower()
            if analysis_profile_kind not in {"profile", "legacy"}:
                raise RequestError(
                    "analysisProfileKind must be profile or legacy"
                )
            parameters["analysis_profile_kind"] = analysis_profile_kind

        side = first("side")
        if side:
            side = side.upper()
            if side not in {"BUY", "SELL"}:
                raise RequestError("side must be BUY or SELL")
            side_clause = """
                EXISTS (
                    SELECT 1
                    FROM zigzag_elliot_observation_timeframes AS side_tf
                    WHERE side_tf.observation_id = o.id
                      AND side_tf.time_frame_order = 4
                      AND side_tf.buy_sell_label = :h1_side
                )
                """
            clauses.append(side_clause)
            signal_result_clauses.append(
                "e.full_alignment_side = :h1_side"
            )
            parameters["h1_side"] = side

        from_date = first("from")
        if from_date:
            clauses.append("o.anchor_jst_time >= :from_time")
            signal_result_clauses.append(
                "e.anchor_jst_time >= :from_time"
            )
            parameters["from_time"] = parse_date_boundary(from_date, False)

        to_date = first("to")
        if to_date:
            clauses.append("o.anchor_jst_time < :to_time")
            signal_result_clauses.append("e.anchor_jst_time < :to_time")
            parameters["to_time"] = parse_date_boundary(to_date, True)

        jst_time = first("jstTime")
        if jst_time:
            clauses.append(
                "strftime('%H:%M', o.anchor_jst_time, 'unixepoch') = :jst_time"
            )
            signal_result_clauses.append(
                "strftime('%H:%M', e.anchor_jst_time, 'unixepoch') = :jst_time"
            )
            parameters["jst_time"] = parse_jst_time(jst_time)

        sync_time_frames: list[str] = []
        seen_sync_time_frames: set[str] = set()
        for raw_time_frame in query.get("syncTimeFrame", []):
            time_frame = raw_time_frame.strip().upper()
            if not time_frame or time_frame in seen_sync_time_frames:
                continue
            if time_frame not in OBSERVATION_SYNC_TIME_FRAMES:
                raise RequestError(
                    "syncTimeFrame must be MN1, W1, D1 or H4"
                )
            seen_sync_time_frames.add(time_frame)
            sync_time_frames.append(time_frame)
        if sync_time_frames:
            placeholders: list[str] = []
            for index, time_frame in enumerate(sync_time_frames):
                parameter_name = f"sync_time_frame_{index}"
                placeholders.append(f":{parameter_name}")
                parameters[parameter_name] = time_frame
            parameters["sync_time_frame_count"] = len(sync_time_frames)
            sync_clause = (
                """
                EXISTS (
                    SELECT 1
                    FROM zigzag_elliot_observation_timeframes AS sync_tf
                    INNER JOIN zigzag_elliot_observation_timeframes AS h1_tf
                            ON h1_tf.observation_id = sync_tf.observation_id
                           AND h1_tf.time_frame_order = 4
                    WHERE sync_tf.observation_id = o.id
                      AND sync_tf.time_frame_text IN (
                """
                + ", ".join(placeholders)
                + """
                      )
                      AND sync_tf.is_buy = h1_tf.is_buy
                    GROUP BY sync_tf.observation_id
                    HAVING COUNT(DISTINCT sync_tf.time_frame_text)
                           = :sync_time_frame_count
                )
                """
            )
            clauses.append(sync_clause)
            signal_result_clauses.append(
                sync_clause.replace("o.id", "e.id")
            )

        full_alignment = first("fullAlignment")
        if full_alignment is not None:
            full_alignment = full_alignment.upper()
            if full_alignment not in {"FULL", "BUY", "SELL"}:
                raise RequestError(
                    "fullAlignment must be FULL, BUY or SELL"
                )
            direction_clause = ""
            if full_alignment != "FULL":
                direction_clause = (
                    "AND full_h1.is_buy = :full_alignment_is_buy"
                )
                parameters["full_alignment_is_buy"] = int(
                    full_alignment == "BUY"
                )
                signal_result_clauses.append(
                    "e.full_alignment_side = :signal_full_alignment_side"
                )
                parameters["signal_full_alignment_side"] = full_alignment
            clauses.append(
                """
                EXISTS (
                    SELECT 1
                    FROM zigzag_elliot_observation_timeframes AS full_w1
                    INNER JOIN zigzag_elliot_observation_timeframes AS full_d1
                            ON full_d1.observation_id = full_w1.observation_id
                           AND full_d1.time_frame_order = 2
                    INNER JOIN zigzag_elliot_observation_timeframes AS full_h4
                            ON full_h4.observation_id = full_w1.observation_id
                           AND full_h4.time_frame_order = 3
                    INNER JOIN zigzag_elliot_observation_timeframes AS full_h1
                            ON full_h1.observation_id = full_w1.observation_id
                           AND full_h1.time_frame_order = 4
                    WHERE full_w1.observation_id = o.id
                      AND full_w1.time_frame_order = 1
                      AND full_w1.is_buy IN (0, 1)
                      AND full_d1.is_buy = full_w1.is_buy
                      AND full_h4.is_buy = full_w1.is_buy
                      AND full_h1.is_buy = full_w1.is_buy
                      AND (
                          (
                              full_h1.is_buy = 1
                              AND full_h4.is_ema200_buy = 1
                              AND full_h4.is_ema200_sell = 0
                              AND full_h1.is_ema200_buy = 1
                              AND full_h1.is_ema200_sell = 0
                          )
                          OR (
                              full_h1.is_buy = 0
                              AND full_h4.is_ema200_buy = 0
                              AND full_h4.is_ema200_sell = 1
                              AND full_h1.is_ema200_buy = 0
                              AND full_h1.is_ema200_sell = 1
                          )
                      )
                      """
                + direction_clause
                + """
                )
                """
            )

        search_text = first("q")
        if search_text:
            if len(search_text) > MAX_SEARCH_LENGTH:
                raise RequestError(f"q must be at most {MAX_SEARCH_LENGTH} characters")
            parameters["search_text"] = f"%{escape_like(search_text)}%"
            search_clause = """
                (
                    COALESCE(o.symbol_name, '') LIKE :search_text ESCAPE '\\'
                    OR COALESCE(o.source_server, '')
                        LIKE :search_text ESCAPE '\\'
                    OR EXISTS (
                        SELECT 1
                        FROM zigzag_elliot_observation_timeframes AS search_tf
                        WHERE search_tf.observation_id = o.id
                          AND (
                              COALESCE(search_tf.latest_elliot_label, '')
                                  LIKE :search_text ESCAPE '\\'
                              OR COALESCE(search_tf.latest_sub_elliot_label, '')
                                  LIKE :search_text ESCAPE '\\'
                              OR COALESCE(search_tf.previous_last_elliot_label, '')
                                  LIKE :search_text ESCAPE '\\'
                          )
                    )
                )
                """
            clauses.append(search_clause)
            signal_result_clauses.append(
                search_clause.replace("o.", "e.")
            )

        sort_key = first("sort") or "anchor_jst_time"
        if sort_key not in OBSERVATION_SORT_COLUMNS:
            raise RequestError("unsupported observation sort column")
        order = (first("order") or "desc").lower()
        if order not in {"asc", "desc"}:
            raise RequestError("order must be asc or desc")

        page = positive_int(first("page"), "page", 1)
        page_size = min(
            positive_int(first("pageSize"), "pageSize", 50),
            MAX_PAGE_SIZE,
        )
        where_sql = ""
        if clauses:
            where_sql = " AND " + " AND ".join(clauses)
        signal_candidate_where_sql = ""
        if signal_candidate_clauses:
            signal_candidate_where_sql = (
                " AND " + " AND ".join(signal_candidate_clauses)
            )
        signal_result_where_sql = ""
        if signal_result_clauses:
            signal_result_where_sql = (
                " AND " + " AND ".join(signal_result_clauses)
            )
        return ObservationFilters(
            where_sql=where_sql,
            signal_candidate_where_sql=signal_candidate_where_sql,
            signal_result_where_sql=signal_result_where_sql,
            parameters=parameters,
            analysis_profile_kind=analysis_profile_kind,
            group_continuous=group_continuous,
            sort_sql=OBSERVATION_SORT_COLUMNS[sort_key],
            order_sql=order.upper(),
            page=page,
            page_size=page_size,
        )

    @staticmethod
    def observation_rows_cte(
        filters: ObservationFilters,
        analysis_profile_available: bool = False,
        spread_available: bool = False,
    ) -> str:
        """Return filtered parents; child rows are loaded only after paging."""

        profile_kind_expression = "'legacy'"
        analysis_profile_columns = """
            NULL AS analysis_input_text,
            1 AS analysis_profile_is_legacy,
            'legacy' AS analysis_profile_kind,
        """
        if analysis_profile_available:
            profile_match = """
                NULLIF(r.analysis_input_text, '') IS NOT NULL
                AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                AND r.analysis_version = o.analysis_version
                AND r.analysis_input_hash = o.analysis_input_hash
            """
            profile_kind_expression = f"""
                CASE WHEN {profile_match}
                     THEN 'profile' ELSE 'legacy' END
            """
            analysis_profile_columns = """
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN r.analysis_input_text
                    ELSE NULL
                END AS analysis_input_text,
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN 0
                    ELSE 1
                END AS analysis_profile_is_legacy,
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN 'profile'
                    ELSE 'legacy'
                END AS analysis_profile_kind,
            """
        analysis_profile_filter_sql = ""
        if filters.analysis_profile_kind is not None:
            analysis_profile_filter_sql = (
                f" AND ({profile_kind_expression}) = :analysis_profile_kind"
            )
        spread_expression = "NULL AS spread_pips"
        if spread_available:
            spread_expression = "o.spread_pips"
        return f"""
            WITH observation_rows AS (
                SELECT
                    o.id, o.run_id, r.run_uid, o.source_mode, o.source_server,
                    r.program_name, r.program_version, r.strategy,
                    r.strategy_version,
                    o.symbol_name,
                    is_gmo_target(o.symbol_name) AS is_gmo_target,
                    o.anchor_time_frame,
                    o.anchor_time_frame_text, o.anchor_bar_time,
                    o.anchor_bar_time_text, o.anchor_jst_time,
                    o.anchor_jst_time_text, o.capture_phase,
                    {spread_expression},
                    o.analysis_version, o.analysis_input_hash,
                    {analysis_profile_columns}
                    o.snapshot_hash, o.time_frame_count,
                    o.created_at, o.created_at_text
                FROM zigzag_elliot_observations AS o
                INNER JOIN zigzag_elliot_alert_runs AS r ON r.id = o.run_id
                WHERE 1 = 1 {filters.where_sql}
                      {analysis_profile_filter_sql}
            )
        """

    @staticmethod
    def observation_signal_rows_cte(
        filters: ObservationFilters,
        analysis_profile_available: bool = False,
        spread_available: bool = False,
    ) -> str:
        """Return consecutive FULL rows collapsed before paging."""

        analysis_profile_columns = """
            NULL AS analysis_input_text,
            1 AS analysis_profile_is_legacy,
            'legacy' AS analysis_profile_kind,
        """
        if analysis_profile_available:
            analysis_profile_columns = """
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN r.analysis_input_text
                    ELSE NULL
                END AS analysis_input_text,
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN 0
                    ELSE 1
                END AS analysis_profile_is_legacy,
                CASE
                    WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                     AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                     AND r.analysis_version = o.analysis_version
                     AND r.analysis_input_hash = o.analysis_input_hash
                    THEN 'profile'
                    ELSE 'legacy'
                END AS analysis_profile_kind,
            """
        analysis_profile_filter_sql = ""
        if filters.analysis_profile_kind is not None:
            analysis_profile_filter_sql = (
                " AND o.analysis_profile_kind = :analysis_profile_kind"
            )
        spread_expression = "NULL AS spread_pips"
        if spread_available:
            spread_expression = "o.spread_pips"
        symbol_stream_partition = """
            source_mode, source_server, run_id, symbol_name,
            anchor_time_frame, capture_phase, analysis_version,
            analysis_input_hash
        """
        episode_partition = symbol_stream_partition + ", signal_number"
        return f"""
            WITH signal_state_rows AS (
                SELECT
                    o.id, o.run_id, r.run_uid, o.source_mode, o.source_server,
                    r.program_name, r.program_version, r.strategy,
                    r.strategy_version,
                    o.symbol_name,
                    is_gmo_target(o.symbol_name) AS is_gmo_target,
                    o.anchor_time_frame,
                    o.anchor_time_frame_text, o.anchor_bar_time,
                    o.anchor_bar_time_text, o.anchor_jst_time,
                    o.anchor_jst_time_text, o.capture_phase,
                    {spread_expression},
                    o.analysis_version, o.analysis_input_hash,
                    {analysis_profile_columns}
                    o.snapshot_hash, o.time_frame_count,
                    o.created_at, o.created_at_text,
                    CASE
                        WHEN full_w1.is_buy = 1
                         AND full_d1.is_buy = 1
                         AND full_h4.is_buy = 1
                         AND full_h1.is_buy = 1
                         AND full_h4.is_ema200_buy = 1
                         AND full_h4.is_ema200_sell = 0
                         AND full_h1.is_ema200_buy = 1
                         AND full_h1.is_ema200_sell = 0
                        THEN 'BUY'
                        WHEN full_w1.is_buy = 0
                         AND full_d1.is_buy = 0
                         AND full_h4.is_buy = 0
                         AND full_h1.is_buy = 0
                         AND full_h4.is_ema200_buy = 0
                         AND full_h4.is_ema200_sell = 1
                         AND full_h1.is_ema200_buy = 0
                         AND full_h1.is_ema200_sell = 1
                        THEN 'SELL'
                        ELSE NULL
                    END AS full_alignment_side
                FROM zigzag_elliot_observations AS o
                INNER JOIN zigzag_elliot_alert_runs AS r ON r.id = o.run_id
                LEFT JOIN zigzag_elliot_observation_timeframes AS full_w1
                        ON full_w1.observation_id = o.id
                       AND full_w1.time_frame_order = 1
                LEFT JOIN zigzag_elliot_observation_timeframes AS full_d1
                        ON full_d1.observation_id = o.id
                       AND full_d1.time_frame_order = 2
                LEFT JOIN zigzag_elliot_observation_timeframes AS full_h4
                        ON full_h4.observation_id = o.id
                       AND full_h4.time_frame_order = 3
                LEFT JOIN zigzag_elliot_observation_timeframes AS full_h1
                        ON full_h1.observation_id = o.id
                       AND full_h1.time_frame_order = 4
            ),
            signal_partition_rows AS (
                SELECT o.*
                FROM signal_state_rows AS o
                WHERE o.full_alignment_side IS NOT NULL
                      {filters.signal_candidate_where_sql}
                      {analysis_profile_filter_sql}
            ),
            signal_stream_rows AS (
                SELECT id, run_id, source_mode, source_server, symbol_name,
                       anchor_time_frame, capture_phase, analysis_version,
                       analysis_input_hash, anchor_bar_time, anchor_jst_time,
                       full_alignment_side,
                       LAG(anchor_bar_time) OVER (
                           PARTITION BY {symbol_stream_partition}
                           ORDER BY anchor_bar_time, id
                       ) AS previous_stream_anchor_bar_time,
                       LAG(full_alignment_side) OVER (
                           PARTITION BY {symbol_stream_partition}
                           ORDER BY anchor_bar_time, id
                       ) AS previous_stream_side
                FROM signal_partition_rows
            ),
            signal_marked_rows AS (
                SELECT signal_stream_rows.*,
                       CASE
                           WHEN previous_stream_side = full_alignment_side
                            AND is_consecutive_market_h1(
                                previous_stream_anchor_bar_time,
                                anchor_bar_time
                            ) = 1
                            AND NOT EXISTS (
                                SELECT 1
                                FROM zigzag_elliot_observations
                                     AS between_observation
                                WHERE between_observation.source_mode
                                          = signal_stream_rows.source_mode
                                  AND between_observation.source_server
                                          = signal_stream_rows.source_server
                                  AND between_observation.run_id
                                          = signal_stream_rows.run_id
                                  AND between_observation.symbol_name
                                          = signal_stream_rows.symbol_name
                                  AND between_observation.anchor_time_frame
                                          = signal_stream_rows.anchor_time_frame
                                  AND between_observation.capture_phase
                                          = signal_stream_rows.capture_phase
                                  AND between_observation.analysis_version
                                          = signal_stream_rows.analysis_version
                                  AND between_observation.analysis_input_hash
                                          = signal_stream_rows.analysis_input_hash
                                  AND between_observation.anchor_bar_time
                                          > previous_stream_anchor_bar_time
                                  AND between_observation.anchor_bar_time
                                          < signal_stream_rows.anchor_bar_time
                            )
                           THEN 0 ELSE 1
                       END AS is_signal_start
                FROM signal_stream_rows
            ),
            signal_numbered_rows AS (
                SELECT signal_marked_rows.*,
                       SUM(is_signal_start) OVER (
                           PARTITION BY {symbol_stream_partition}
                           ORDER BY anchor_bar_time, id
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                       ) AS signal_number
                FROM signal_marked_rows
            ),
            signal_episode_bounds AS (
                SELECT source_mode, source_server, run_id, symbol_name,
                       anchor_time_frame, capture_phase, analysis_version,
                       analysis_input_hash, signal_number,
                       MIN(anchor_bar_time) AS signal_start_anchor_bar_time,
                       MAX(anchor_bar_time) AS signal_end_anchor_bar_time,
                       COUNT(*) AS signal_h1_count
                FROM signal_numbered_rows
                GROUP BY {episode_partition}
            ),
            observation_rows AS (
                SELECT
                    start_observation.id, start_observation.run_id,
                    start_observation.run_uid, start_observation.source_mode,
                    start_observation.source_server,
                    start_observation.program_name,
                    start_observation.program_version,
                    start_observation.strategy,
                    start_observation.strategy_version,
                    start_observation.symbol_name,
                    start_observation.is_gmo_target,
                    start_observation.anchor_time_frame,
                    start_observation.anchor_time_frame_text,
                    start_observation.anchor_bar_time,
                    start_observation.anchor_bar_time_text,
                    start_observation.anchor_jst_time,
                    start_observation.anchor_jst_time_text,
                    start_observation.capture_phase,
                    start_observation.spread_pips,
                    start_observation.analysis_version,
                    start_observation.analysis_input_hash,
                    start_observation.analysis_input_text,
                    start_observation.analysis_profile_is_legacy,
                    start_observation.analysis_profile_kind,
                    start_observation.snapshot_hash,
                    start_observation.time_frame_count,
                    start_observation.created_at,
                    start_observation.created_at_text,
                    'FULL_ALIGNMENT_EPISODE_V1' AS signal_rule_version,
                    e.full_alignment_side AS signal_side,
                    e.id AS signal_start_observation_id,
                    signal_end.id AS signal_end_observation_id,
                    end_observation.anchor_bar_time
                        AS signal_end_anchor_bar_time,
                    end_observation.anchor_bar_time_text
                        AS signal_end_anchor_bar_time_text,
                    end_observation.anchor_jst_time
                        AS signal_end_anchor_jst_time,
                    end_observation.anchor_jst_time_text
                        AS signal_end_anchor_jst_time_text,
                    bounds.signal_h1_count,
                    CASE WHEN previous_observation.id IS NULL
                         THEN 1 ELSE 0 END AS signal_is_left_censored,
                    CASE WHEN next_observation.id IS NULL
                         THEN 1 ELSE 0 END AS signal_is_right_censored,
                    CASE
                        WHEN previous_observation.id IS NOT NULL
                         AND (
                             is_consecutive_market_h1(
                                 previous_observation.anchor_bar_time,
                                 e.anchor_bar_time
                             ) = 0
                             OR (
                                 SELECT COUNT(DISTINCT previous_tf.time_frame_order)
                                 FROM zigzag_elliot_observation_timeframes
                                      AS previous_tf
                                 WHERE previous_tf.observation_id
                                           = previous_observation.id
                                   AND previous_tf.time_frame_order
                                           IN (1, 2, 3, 4)
                             ) <> 4
                         )
                        THEN 1 ELSE 0
                    END AS signal_has_data_gap_before,
                    CASE
                        WHEN next_observation.id IS NOT NULL
                         AND (
                             is_consecutive_market_h1(
                                 signal_end.anchor_bar_time,
                                 next_observation.anchor_bar_time
                             ) = 0
                             OR (
                                 SELECT COUNT(DISTINCT next_tf.time_frame_order)
                                 FROM zigzag_elliot_observation_timeframes
                                      AS next_tf
                                 WHERE next_tf.observation_id
                                           = next_observation.id
                                   AND next_tf.time_frame_order
                                           IN (1, 2, 3, 4)
                             ) <> 4
                         )
                        THEN 1 ELSE 0
                    END AS signal_has_data_gap_after
                FROM signal_episode_bounds AS bounds
                INNER JOIN signal_numbered_rows AS e
                        ON e.source_mode = bounds.source_mode
                       AND e.source_server = bounds.source_server
                       AND e.run_id = bounds.run_id
                       AND e.symbol_name = bounds.symbol_name
                       AND e.anchor_time_frame = bounds.anchor_time_frame
                       AND e.capture_phase = bounds.capture_phase
                       AND e.analysis_version = bounds.analysis_version
                       AND e.analysis_input_hash = bounds.analysis_input_hash
                       AND e.signal_number = bounds.signal_number
                       AND e.anchor_bar_time
                           = bounds.signal_start_anchor_bar_time
                INNER JOIN signal_numbered_rows AS signal_end
                        ON signal_end.source_mode = bounds.source_mode
                       AND signal_end.source_server = bounds.source_server
                       AND signal_end.run_id = bounds.run_id
                       AND signal_end.symbol_name = bounds.symbol_name
                       AND signal_end.anchor_time_frame
                           = bounds.anchor_time_frame
                       AND signal_end.capture_phase = bounds.capture_phase
                       AND signal_end.analysis_version = bounds.analysis_version
                       AND signal_end.analysis_input_hash
                           = bounds.analysis_input_hash
                       AND signal_end.signal_number = bounds.signal_number
                       AND signal_end.anchor_bar_time
                           = bounds.signal_end_anchor_bar_time
                INNER JOIN signal_partition_rows AS start_observation
                        ON start_observation.id = e.id
                INNER JOIN signal_partition_rows AS end_observation
                        ON end_observation.id = signal_end.id
                LEFT JOIN zigzag_elliot_observations AS previous_observation
                       ON previous_observation.id = (
                           SELECT previous_parent.id
                           FROM zigzag_elliot_observations AS previous_parent
                           WHERE previous_parent.source_mode = e.source_mode
                             AND previous_parent.source_server = e.source_server
                             AND previous_parent.run_id = e.run_id
                             AND previous_parent.symbol_name = e.symbol_name
                             AND previous_parent.anchor_time_frame
                                   = e.anchor_time_frame
                             AND previous_parent.capture_phase = e.capture_phase
                             AND previous_parent.analysis_version
                                   = e.analysis_version
                             AND previous_parent.analysis_input_hash
                                   = e.analysis_input_hash
                             AND previous_parent.anchor_bar_time
                                   < e.anchor_bar_time
                           ORDER BY previous_parent.anchor_bar_time DESC,
                                    previous_parent.id DESC
                           LIMIT 1
                       )
                LEFT JOIN zigzag_elliot_observations AS next_observation
                       ON next_observation.id = (
                           SELECT next_parent.id
                           FROM zigzag_elliot_observations AS next_parent
                           WHERE next_parent.source_mode
                                   = signal_end.source_mode
                             AND next_parent.source_server
                                   = signal_end.source_server
                             AND next_parent.run_id = signal_end.run_id
                             AND next_parent.symbol_name
                                   = signal_end.symbol_name
                             AND next_parent.anchor_time_frame
                                   = signal_end.anchor_time_frame
                             AND next_parent.capture_phase
                                   = signal_end.capture_phase
                             AND next_parent.analysis_version
                                   = signal_end.analysis_version
                             AND next_parent.analysis_input_hash
                                   = signal_end.analysis_input_hash
                             AND next_parent.anchor_bar_time
                                   > signal_end.anchor_bar_time
                           ORDER BY next_parent.anchor_bar_time,
                                    next_parent.id
                           LIMIT 1
                       )
                WHERE 1 = 1
                      {filters.signal_result_where_sql}
            )
        """

    @staticmethod
    def unavailable_observation_list(filters: ObservationFilters) -> dict[str, Any]:
        """Return a predictable empty page while optional tables are absent."""

        return {
            "available": False,
            "items": [],
            "total": 0,
            "page": 1,
            "page_size": filters.page_size,
            "page_count": 0,
            "grouped": filters.group_continuous,
        }

    @staticmethod
    def observation_timeframes(
        connection: Connection,
        observation_ids: list[int],
    ) -> dict[int, list[dict[str, Any]]]:
        """Load compact timeframe snapshots for one page using bound IDs."""

        result = {observation_id: [] for observation_id in observation_ids}
        if not observation_ids:
            return result
        parameters: dict[str, Any] = {}
        placeholders: list[str] = []
        for index, observation_id in enumerate(observation_ids):
            name = f"observation_id_{index}"
            placeholders.append(f":{name}")
            parameters[name] = observation_id
        sql = f"""
            SELECT id, observation_id, time_frame, time_frame_text,
                   time_frame_order, is_anchor_time_frame,
                   is_buy, buy_sell_label, wave_count, latest_wave_index,
                   is_wave_confirmed, is_wave_motive, is_wave_uptrend,
                   wave_trend_label, previous_last_elliot_label,
                   point_count, latest_elliot_index, latest_elliot_label,
                   latest_sub_elliot_index, latest_sub_elliot_label,
                   latest_point_time, latest_point_time_text,
                   latest_point_jst_time, latest_point_jst_time_text,
                   latest_point_rate, current_close,
                   stochastic_main_order_text,
                   stochastic_main_direction_text,
                   gmma_trend_count, gmma_cross_count,
                   ema30_ema60_diff_pips, atr14_pips,
                   ema200_slope_pips, ema200_close_diff_pips,
                   ema200_trend_count,
                   is_ema200_buy, is_ema200_sell,
                   created_at, created_at_text
            FROM zigzag_elliot_observation_timeframes
            WHERE observation_id IN ({", ".join(placeholders)})
            ORDER BY observation_id, time_frame_order, id
        """
        rows = connection.execute(text(sql), parameters).mappings()
        for row in rows:
            item = row_to_dict(row)
            if item is not None:
                result[int(item["observation_id"])].append(item)
        return result

    def observations(self, query: dict[str, list[str]]) -> dict[str, Any]:
        """Return a filtered H1 observation page with nested timeframe rows."""

        filters = self.parse_observation_filters(query)
        with self.connect() as connection:
            if not self.observation_schema_status(connection)["available"]:
                return self.unavailable_observation_list(filters)
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            spread_available = self.observation_spread_available(connection)
            rows_cte = self.observation_rows_cte
            if filters.group_continuous:
                rows_cte = self.observation_signal_rows_cte
            cte = rows_cte(
                filters,
                analysis_profile_status["available"],
                spread_available,
            )
            list_sql = (
                cte
                + " SELECT observation_rows.*, COUNT(*) OVER () AS result_total"
                + " FROM observation_rows"
                + f" ORDER BY {filters.sort_sql} {filters.order_sql}, id DESC"
                + " LIMIT :limit OFFSET :offset"
            )
            raw_list_sql = (
                cte
                + " SELECT * FROM observation_rows"
                + f" ORDER BY {filters.sort_sql} {filters.order_sql}, id DESC"
                + " LIMIT :limit OFFSET :offset"
            )
            parameters = dict(filters.parameters)
            parameters["limit"] = filters.page_size
            requested_offset = (filters.page - 1) * filters.page_size
            connection.exec_driver_sql("BEGIN")
            try:
                if not filters.group_continuous:
                    count_sql = cte + " SELECT COUNT(*) FROM observation_rows"
                    total = int(connection.execute(
                        text(count_sql), filters.parameters
                    ).scalar_one())
                    page_count = (
                        total + filters.page_size - 1
                    ) // filters.page_size
                    effective_page = (
                        1 if page_count == 0 else min(filters.page, page_count)
                    )
                    parameters["offset"] = (
                        effective_page - 1
                    ) * filters.page_size
                    rows = connection.execute(
                        text(raw_list_sql), parameters
                    ).mappings()
                    items = [row_to_dict(row) for row in rows]
                else:
                    rows = []
                    if requested_offset <= SQLITE_MAX_INTEGER:
                        parameters["offset"] = requested_offset
                        rows = list(
                            connection.execute(
                                text(list_sql),
                                parameters,
                            ).mappings()
                        )
                    total = 0
                    effective_page = filters.page
                    items = []
                    if rows:
                        total = int(rows[0]["result_total"])
                        for row in rows:
                            values = dict(row)
                            values.pop("result_total", None)
                            items.append(values_to_dict(values))
                    elif filters.page > 1:
                        count_sql = cte + " SELECT COUNT(*) FROM observation_rows"
                        total = int(connection.execute(
                            text(count_sql), filters.parameters
                        ).scalar_one())
                        page_count = (
                            total + filters.page_size - 1
                        ) // filters.page_size
                        effective_page = 1 if page_count == 0 else page_count
                        if total > 0:
                            parameters["offset"] = (
                                effective_page - 1
                            ) * filters.page_size
                            rows = list(connection.execute(
                                text(list_sql), parameters
                            ).mappings())
                            for row in rows:
                                values = dict(row)
                                values.pop("result_total", None)
                                items.append(values_to_dict(values))
                page_count = (
                    total + filters.page_size - 1
                ) // filters.page_size
                if page_count == 0:
                    effective_page = 1
                observation_ids = [
                    int(item["id"]) for item in items if item is not None
                ]
                time_frames = self.observation_timeframes(
                    connection,
                    observation_ids,
                )
                for item in items:
                    if item is not None:
                        item["time_frames"] = time_frames[int(item["id"])]
            finally:
                connection.rollback()
        return {
            "available": True,
            "items": items,
            "total": total,
            "page": effective_page,
            "page_size": filters.page_size,
            "page_count": page_count,
            "grouped": filters.group_continuous,
        }

    def observation_summary(self, query: dict[str, list[str]]) -> dict[str, Any]:
        """Return compact counts for the current H1 observation filters."""

        filters = self.parse_observation_filters(query)
        unavailable = {
            "available": False,
            "total_count": 0,
            "live_count": 0,
            "tester_count": 0,
            "run_count": 0,
            "symbol_count": 0,
            "first_anchor_bar_time": None,
            "first_anchor_bar_time_text": None,
            "last_anchor_bar_time": None,
            "last_anchor_bar_time_text": None,
            "first_anchor_jst_time": None,
            "first_anchor_jst_time_text": None,
            "last_anchor_jst_time": None,
            "last_anchor_jst_time_text": None,
            "analysis_profile_count": 0,
            "legacy_profile_observation_count": 0,
            "matched_observation_count": 0,
            "signal_buy_count": 0,
            "signal_sell_count": 0,
            "grouped": filters.group_continuous,
        }
        with self.connect() as connection:
            if not self.observation_schema_status(connection)["available"]:
                return unavailable
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            spread_available = self.observation_spread_available(connection)
            rows_cte = self.observation_rows_cte
            if filters.group_continuous:
                rows_cte = self.observation_signal_rows_cte
            signal_summary_columns = """
                       COUNT(*) AS matched_observation_count,
                       0 AS signal_buy_count,
                       0 AS signal_sell_count,
            """
            legacy_profile_count_expression = (
                "COALESCE(SUM(analysis_profile_is_legacy), 0)"
            )
            if filters.group_continuous:
                signal_summary_columns = """
                       COALESCE(SUM(signal_h1_count), 0)
                           AS matched_observation_count,
                       COALESCE(SUM(CASE WHEN signal_side = 'BUY'
                                         THEN 1 ELSE 0 END), 0)
                           AS signal_buy_count,
                       COALESCE(SUM(CASE WHEN signal_side = 'SELL'
                                         THEN 1 ELSE 0 END), 0)
                           AS signal_sell_count,
                """
                legacy_profile_count_expression = """
                    COALESCE(SUM(
                        analysis_profile_is_legacy * signal_h1_count
                    ), 0)
                """
            sql = rows_cte(
                filters,
                analysis_profile_status["available"],
                spread_available,
            ) + f"""
                SELECT COUNT(*) AS total_count,
                       COALESCE(SUM(CASE WHEN source_mode = 'LIVE'
                                         THEN 1 ELSE 0 END), 0) AS live_count,
                       COALESCE(SUM(CASE WHEN source_mode = 'TESTER'
                                         THEN 1 ELSE 0 END), 0) AS tester_count,
                       COUNT(DISTINCT run_id) AS run_count,
                       COUNT(DISTINCT symbol_name) AS symbol_count,
                       (
                           SELECT COUNT(*)
                           FROM (
                               SELECT DISTINCT analysis_version,
                                               analysis_input_hash,
                                               analysis_profile_kind
                               FROM observation_rows
                           ) AS exact_profiles
                       ) AS analysis_profile_count,
                       {legacy_profile_count_expression}
                           AS legacy_profile_observation_count,
                       {signal_summary_columns}
                       MIN(anchor_bar_time) AS first_anchor_bar_time,
                       MIN(anchor_bar_time_text) AS first_anchor_bar_time_text,
                       MAX(anchor_bar_time) AS last_anchor_bar_time,
                       MAX(anchor_bar_time_text) AS last_anchor_bar_time_text,
                       MIN(anchor_jst_time) AS first_anchor_jst_time,
                       MIN(anchor_jst_time_text) AS first_anchor_jst_time_text,
                       MAX(anchor_jst_time) AS last_anchor_jst_time,
                       MAX(anchor_jst_time_text) AS last_anchor_jst_time_text
                FROM observation_rows
            """
            row = connection.execute(text(sql), filters.parameters).mappings().one()
        result = row_to_dict(row) or {}
        result["available"] = True
        result["grouped"] = filters.group_continuous
        return result

    @staticmethod
    def observation_navigation(
        connection: Connection,
        observation: RowMapping,
    ) -> dict[str, dict[str, Any] | None]:
        """Return the adjacent older and newer rows in one observation stream."""

        select_sql = """
            SELECT o.id, o.run_id, o.anchor_jst_time, o.anchor_jst_time_text,
                   o.anchor_bar_time, o.anchor_bar_time_text
            FROM zigzag_elliot_observations AS o
            WHERE o.source_mode = :source_mode
              AND o.source_server = :source_server
              AND o.symbol_name = :symbol_name
              AND o.anchor_time_frame = :anchor_time_frame
              AND o.capture_phase = :capture_phase
              AND o.analysis_version = :analysis_version
              AND o.analysis_input_hash = :analysis_input_hash
        """
        older_sql = select_sql + """
              AND (
                  o.anchor_jst_time < :anchor_jst_time
                  OR (
                      o.anchor_jst_time = :anchor_jst_time
                      AND o.id < :observation_id
                  )
              )
            ORDER BY o.anchor_jst_time DESC, o.id DESC
            LIMIT 1
        """
        newer_sql = select_sql + """
              AND (
                  o.anchor_jst_time > :anchor_jst_time
                  OR (
                      o.anchor_jst_time = :anchor_jst_time
                      AND o.id > :observation_id
                  )
              )
            ORDER BY o.anchor_jst_time ASC, o.id ASC
            LIMIT 1
        """
        parameters = {
            "observation_id": int(observation["id"]),
            "source_mode": observation["source_mode"],
            "source_server": observation["source_server"],
            "symbol_name": observation["symbol_name"],
            "anchor_time_frame": observation["anchor_time_frame"],
            "capture_phase": observation["capture_phase"],
            "analysis_version": observation["analysis_version"],
            "analysis_input_hash": observation["analysis_input_hash"],
            "anchor_jst_time": observation["anchor_jst_time"],
        }
        older = connection.execute(text(older_sql), parameters).mappings().one_or_none()
        newer = connection.execute(text(newer_sql), parameters).mappings().one_or_none()
        return {
            "older": row_to_dict(older),
            "newer": row_to_dict(newer),
        }

    def observation_detail(self, observation_id: int) -> dict[str, Any]:
        """Return one full parent, timeframe snapshots and stream navigation."""

        parent_sql_template = """
            SELECT o.*,
                   {spread_pips_column}
                   is_gmo_target(o.symbol_name) AS is_gmo_target,
                   r.run_uid, r.source, r.program_name, r.program_version,
                   r.strategy, r.strategy_version, r.tester_from, r.tester_to,
                   r.tester_model, r.started_at, r.started_at_text,
                   {analysis_profile_columns}
            FROM zigzag_elliot_observations AS o
            INNER JOIN zigzag_elliot_alert_runs AS r ON r.id = o.run_id
            WHERE o.id = :observation_id
        """
        time_frame_sql = """
            SELECT * FROM zigzag_elliot_observation_timeframes
            WHERE observation_id = :observation_id
            ORDER BY time_frame_order, id
        """
        parameters = {"observation_id": observation_id}
        with self.connect() as connection:
            if not self.observation_schema_status(connection)["available"]:
                return {
                    "available": False,
                    "observation": None,
                    "time_frames": [],
                    "navigation": {"older": None, "newer": None},
                }
            analysis_profile_status = self.analysis_profile_schema_status(connection)
            spread_pips_column = "NULL AS spread_pips,"
            if self.observation_spread_available(connection):
                spread_pips_column = ""
            analysis_profile_columns = """
                NULL AS analysis_input_text,
                1 AS analysis_profile_is_legacy,
                'legacy' AS analysis_profile_kind
            """
            if analysis_profile_status["available"]:
                analysis_profile_columns = """
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                         AND r.analysis_version = o.analysis_version
                         AND r.analysis_input_hash = o.analysis_input_hash
                        THEN r.analysis_input_text
                        ELSE NULL
                    END AS analysis_input_text,
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                         AND r.analysis_version = o.analysis_version
                         AND r.analysis_input_hash = o.analysis_input_hash
                        THEN 0
                        ELSE 1
                    END AS analysis_profile_is_legacy,
                    CASE
                        WHEN NULLIF(r.analysis_input_text, '') IS NOT NULL
                         AND NULLIF(r.analysis_input_hash, '') IS NOT NULL
                         AND r.analysis_version = o.analysis_version
                         AND r.analysis_input_hash = o.analysis_input_hash
                        THEN 'profile'
                        ELSE 'legacy'
                    END AS analysis_profile_kind
                """
            parent_sql = parent_sql_template.format(
                analysis_profile_columns=analysis_profile_columns,
                spread_pips_column=spread_pips_column,
            )
            connection.exec_driver_sql("BEGIN")
            try:
                parent = (
                    connection.execute(text(parent_sql), parameters)
                    .mappings()
                    .one_or_none()
                )
                if parent is None:
                    raise RequestError(
                        "observation was not found",
                        HTTPStatus.NOT_FOUND,
                    )
                rows = connection.execute(text(time_frame_sql), parameters).mappings()
                time_frames = [row_to_dict(row) for row in rows]
                navigation = self.observation_navigation(connection, parent)
            finally:
                connection.rollback()
        return {
            "available": True,
            "observation": row_to_dict(parent),
            "time_frames": time_frames,
            "navigation": navigation,
        }

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

        source_mode = (first("sourceMode") or "all").upper()
        if source_mode not in {"ALL", "LIVE", "TESTER"}:
            raise RequestError("sourceMode must be LIVE, TESTER or all")
        if source_mode != "ALL":
            clauses.append("r.source_mode = :source_mode")
            parameters["source_mode"] = source_mode

        run_id_text = first("runId")
        if run_id_text:
            run_id = positive_int(run_id_text, "runId", 1)
            clauses.append("a.run_id = :run_id")
            parameters["run_id"] = run_id

        simple_filters = {
            "symbol": ("a.symbol_name", "symbol_name"),
            "strategy": ("a.strategy", "strategy"),
            "rank": ("a.h1_structure_rank", "h1_structure_rank"),
            "entryResult": ("a.entry_result", "entry_result"),
        }
        for query_name, (column_name, parameter_name) in simple_filters.items():
            value = first(query_name)
            if value:
                clauses.append(f"{column_name} = :{parameter_name}")
                parameters[parameter_name] = value

        add_gmo_target_filter(
            first("gmoTarget"),
            "a.symbol_name",
            clauses,
            parameters,
        )

        time_frames: list[str] = []
        seen_time_frames: set[str] = set()
        for raw_time_frame in query.get("timeFrame", []):
            time_frame = raw_time_frame.strip()
            if not time_frame or time_frame in seen_time_frames:
                continue
            seen_time_frames.add(time_frame)
            time_frames.append(time_frame)
        if len(time_frames) > MAX_TIME_FRAME_FILTERS:
            raise RequestError(
                f"timeFrame must have at most {MAX_TIME_FRAME_FILTERS} values"
            )
        if len(time_frames) == 1:
            clauses.append("a.time_frame_text = :time_frame_text")
            parameters["time_frame_text"] = time_frames[0]
        elif time_frames:
            placeholders: list[str] = []
            for index, time_frame in enumerate(time_frames):
                parameter_name = f"time_frame_text_{index}"
                placeholders.append(f":{parameter_name}")
                parameters[parameter_name] = time_frame
            clauses.append(
                "a.time_frame_text IN (" + ", ".join(placeholders) + ")"
            )

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

        derived_clauses: list[str] = []
        if alignment_map[alignment]:
            derived_clauses.append(alignment_map[alignment])

        confirmation_state = (first("w1ConfirmationState") or "all").upper()
        if confirmation_state != "ALL":
            if confirmation_state not in W1_CONFIRMATION_STATES:
                raise RequestError(
                    "w1ConfirmationState must be an exact persisted W1 state or all"
                )
            derived_clauses.append(
                "w1_confirmation_state = :w1_confirmation_state"
            )
            parameters["w1_confirmation_state"] = confirmation_state

        confirmation_mode = (first("w1ConfirmationMode") or "all").upper()
        confirmation_mode_aliases = {
            "OR": "DIRECTION_OR_EMA200",
            "AND": "DIRECTION_AND_EMA200",
        }
        confirmation_mode = confirmation_mode_aliases.get(
            confirmation_mode,
            confirmation_mode,
        )
        if confirmation_mode != "ALL":
            if confirmation_mode not in W1_CONFIRMATION_MODES:
                raise RequestError(
                    "w1ConfirmationMode must be OFF, OBSERVE_ONLY, OR, AND or all"
                )
            derived_clauses.append("w1_confirmation_mode = :w1_confirmation_mode")
            parameters["w1_confirmation_mode"] = confirmation_mode

        h1_alignment_state = (
            first("h1DirectionAlignmentState") or "all"
        ).upper()
        if h1_alignment_state != "ALL":
            if h1_alignment_state not in H1_DIRECTION_ALIGNMENT_STATES:
                raise RequestError(
                    "h1DirectionAlignmentState must be an exact persisted H1 state or all"
                )
            derived_clauses.append(
                "h1_direction_alignment_state = :h1_direction_alignment_state"
            )
            parameters["h1_direction_alignment_state"] = h1_alignment_state

        h1_alignment_mode = (
            first("h1DirectionAlignmentMode") or "all"
        ).upper()
        if h1_alignment_mode != "ALL":
            if h1_alignment_mode not in H1_DIRECTION_ALIGNMENT_MODES:
                raise RequestError(
                    "h1DirectionAlignmentMode must be an exact persisted H1 mode or all"
                )
            derived_clauses.append(
                "h1_direction_alignment_mode = :h1_direction_alignment_mode"
            )
            parameters["h1_direction_alignment_mode"] = h1_alignment_mode

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
        derived_where_sql = " AND ".join(derived_clauses)
        return AlertFilters(
            where_sql=where_sql,
            parameters=parameters,
            derived_where_sql=derived_where_sql,
            sort_sql=SORT_COLUMNS[sort_key],
            order_sql=order.upper(),
            page=page,
            page_size=page_size,
        )

    def alert_rows_cte(self, filters: AlertFilters) -> str:
        """Return the shared list CTE using only fixed SQL identifiers."""

        with self.connect() as connection:
            w1_confirmation_columns = self.w1_confirmation_projection(connection)
            h1_direction_alignment_columns = (
                self.h1_direction_alignment_projection(connection)
            )
            ema200_columns = self.ema200_projection(connection)

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
                    a.symbol_name,
                    is_gmo_target(a.symbol_name) AS is_gmo_target,
                    a.time_frame, a.time_frame_text,
                    a.magic_number, a.strategy, a.side,
                    a.is_judge, a.signal_count, a.entry_count,
                    a.is_entry_count_match, a.is_entry_evaluated,
                    a.is_alert, a.is_entry, a.entry_result, a.is_send_mail,
                    a.current_elliot_label, a.is_entry_wave,
                    a.close_ema200_diff_pips, a.max_close_ema200_diff_pips,
                    a.is_ema200_distance_within, a.spread_pips,
                    {ema200_columns}
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
                    {w1_confirmation_columns}
                    {h1_direction_alignment_columns}
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
                LEFT JOIN zigzag_elliot_alert_timeframes AS current_tf
                       ON current_tf.alert_id = a.id
                      AND current_tf.time_frame = a.time_frame
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
        with self.connect() as connection:
            connection.exec_driver_sql("BEGIN")
            try:
                total = connection.execute(
                    text(count_sql), filters.parameters
                ).scalar_one()
                page_count = (total + filters.page_size - 1) // filters.page_size
                if page_count == 0:
                    effective_page = 1
                else:
                    effective_page = min(filters.page, page_count)
                parameters["offset"] = (effective_page - 1) * filters.page_size
                rows = connection.execute(text(list_sql), parameters).mappings()
                items = [row_to_dict(row) for row in rows]
            finally:
                connection.rollback()
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
                (SELECT COUNT(*) FROM zigzag_elliot_alerts)
                    AS database_total_count,
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
        with self.connect() as connection:
            row = connection.execute(text(sql), filters.parameters).mappings().one()
        return row_to_dict(row) or {}

    def alert_detail(self, alert_id: int) -> dict[str, Any]:
        """Return an alert, its run and W1 summary."""

        alert_model = self.model("zigzag_elliot_alerts")
        run_model = self.model("zigzag_elliot_alert_runs")
        time_frame_model = self.model("zigzag_elliot_alert_timeframes")
        with Session(self.engine) as session:
            alert_entity = session.get(alert_model, alert_id)
            if alert_entity is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            run_entity = session.get(run_model, alert_entity.run_id)
            w1_entity = session.scalars(
                select(time_frame_model).where(
                    time_frame_model.alert_id == alert_id,
                    time_frame_model.time_frame == W1_TIME_FRAME,
                )
            ).one_or_none()
            alert = model_to_dict(alert_entity) or {}
            alert["is_gmo_target"] = is_gmo_target(alert.get("symbol_name"))
            self.apply_w1_confirmation_defaults(alert)
            self.apply_h1_direction_alignment_defaults(alert)
            run = model_to_dict(run_entity)
            w1: dict[str, Any] | None = None
            if w1_entity is not None:
                w1 = values_to_dict(
                    {
                        "w1_timeframe_id": w1_entity.id,
                        "w1_is_buy": w1_entity.is_buy,
                        "w1_side": w1_entity.buy_sell_label,
                        "w1_elliot_label": w1_entity.latest_elliot_label,
                        "w1_sub_elliot_label": w1_entity.latest_sub_elliot_label,
                        "w1_is_wave_confirmed": w1_entity.is_wave_confirmed,
                        "w1_is_wave_motive": w1_entity.is_wave_motive,
                        "w1_is_wave_uptrend": w1_entity.is_wave_uptrend,
                        "w1_wave_trend": w1_entity.wave_trend_label,
                    }
                )
        is_w1_aligned: bool | None = None
        if w1 is not None:
            is_w1_aligned = (alert["side"] == "BUY" and w1["w1_is_buy"]) or (
                alert["side"] == "SELL" and not w1["w1_is_buy"]
            )
        alert["is_w1_aligned"] = is_w1_aligned
        return {"alert": alert, "run": run, "w1": w1}

    def timeframes(self, alert_id: int) -> dict[str, Any]:
        """Return all timeframe snapshots for an alert."""

        alert_model = self.model("zigzag_elliot_alerts")
        time_frame_model = self.model("zigzag_elliot_alert_timeframes")
        time_frame_columns = {
            column.key for column in time_frame_model.__table__.columns
        }
        is_ema200_available = EMA200_TIME_FRAME_COLUMNS.issubset(
            time_frame_columns
        )
        with Session(self.engine) as session:
            if session.get(alert_model, alert_id) is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            entities = session.scalars(
                select(time_frame_model)
                .where(time_frame_model.alert_id == alert_id)
                .order_by(time_frame_model.time_frame_order, time_frame_model.id)
            )
            items: list[dict[str, Any]] = []
            for entity in entities:
                item = model_to_dict(entity) or {}
                item["is_ema200_available"] = is_ema200_available
                item["is_ema200_buy"] = bool(item.get("is_ema200_buy", False))
                item["is_ema200_sell"] = bool(item.get("is_ema200_sell", False))
                items.append(item)
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
        with self.connect() as connection:
            exists = connection.execute(
                text("SELECT 1 FROM zigzag_elliot_alerts WHERE id = :alert_id"),
                {"alert_id": alert_id},
            ).first()
            if exists is None:
                raise RequestError("alert was not found", HTTPStatus.NOT_FOUND)
            rows = connection.execute(text(sql), parameters).mappings()
            items = [row_to_dict(row) for row in rows]
        return {"items": items, "count": len(items)}

    def export_csv(self, query: dict[str, list[str]]) -> bytes:
        """Export all alerts matching current filters as UTF-8 BOM CSV."""

        filters = self.parse_filters(query)
        sql = self.alert_rows_cte(filters) + f"""
            SELECT id AS alert_id, run_id, source_mode, current_bar_time_text,
                   server_time_text, jst_time_text, symbol_name,
                   time_frame_text, strategy, side, signal_count, entry_count,
                   entry_result, current_elliot_label, h1_structure_rank,
                   mn1_side, w1_side, d1_side, h4_side, h1_side,
                   is_w1_aligned, w1_elliot_label, w1_sub_elliot_label,
                   w1_confirmation_mode, w1_confirmation_state,
                   is_w1_confirmation_available, is_w1_confirmation_valid,
                   is_w1_direction_matched, w1_ema200_direction,
                   is_w1_ema200_matched, is_w1_confirmation_passed,
                   is_w1_confirmation_legacy,
                   h1_direction_alignment_mode,
                   h1_direction_alignment_state,
                   is_h1_direction_alignment_available,
                   is_h1_direction_alignment_valid,
                   h1_direction_alignment_direction,
                   is_h1_mn1_direction_matched,
                   is_h1_w1_direction_matched,
                   is_h1_direction_alignment_passed,
                   is_h1_direction_alignment_legacy,
                   reference_price, is_stop_loss_available, stop_loss,
                   risk_pips, spread_pips, long_medium_rank_difference,
                   medium_short_rank_difference, alert_title,
                   wave_summary_text, market_signal_key
            FROM alert_rows {self.outer_where(filters)}
            ORDER BY {filters.sort_sql} {filters.order_sql}, id DESC
        """
        with self.connect() as connection:
            rows = connection.execute(text(sql), filters.parameters).mappings().all()
        output = io.StringIO(newline="")
        writer = csv.writer(output, lineterminator="\r\n")
        headers = list(rows[0].keys()) if rows else [
            "alert_id",
            "run_id",
            "source_mode",
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
            "w1_confirmation_mode",
            "w1_confirmation_state",
            "is_w1_confirmation_available",
            "is_w1_confirmation_valid",
            "is_w1_direction_matched",
            "w1_ema200_direction",
            "is_w1_ema200_matched",
            "is_w1_confirmation_passed",
            "is_w1_confirmation_legacy",
            "h1_direction_alignment_mode",
            "h1_direction_alignment_state",
            "is_h1_direction_alignment_available",
            "is_h1_direction_alignment_valid",
            "h1_direction_alignment_direction",
            "is_h1_mn1_direction_matched",
            "is_h1_w1_direction_matched",
            "is_h1_direction_alignment_passed",
            "is_h1_direction_alignment_legacy",
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
            if parsed.path in REACT_INDEX_PATHS:
                self.send_react_static("index.html")
                return
            if parsed.path in STATIC_CONTENT_TYPES:
                self.send_static(parsed.path)
                return
            if parsed.path.startswith("/react/assets/"):
                relative_path = unquote(parsed.path[len("/react/") :])
                self.send_react_static(relative_path)
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
            if parsed.path == "/api/observation-options":
                self.send_json(self.viewer_server.database.observation_options())
                return
            if parsed.path == "/api/alerts":
                self.send_json(self.viewer_server.database.alerts(query))
                return
            if parsed.path == "/api/observations":
                self.send_json(self.viewer_server.database.observations(query))
                return
            if parsed.path == "/api/summary":
                self.send_json(self.viewer_server.database.summary(query))
                return
            if parsed.path == "/api/observation-summary":
                self.send_json(self.viewer_server.database.observation_summary(query))
                return
            if parsed.path == "/api/export.csv":
                self.send_csv(self.viewer_server.database.export_csv(query))
                return

            path_parts = [part for part in parsed.path.split("/") if part]
            if len(path_parts) == 3 and path_parts[:2] == ["api", "observations"]:
                try:
                    observation_id = int(path_parts[2])
                except ValueError as error:
                    raise RequestError("observation id must be an integer") from error
                if observation_id <= 0:
                    raise RequestError("observation id must be greater than zero")
                self.send_json(
                    self.viewer_server.database.observation_detail(observation_id)
                )
                return
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
        except SQLAlchemyError as error:
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
        """Reject DNS rebinding and Host headers not explicitly permitted."""

        host_headers = self.headers.get_all("Host", [])
        if len(host_headers) != 1:
            return False
        host_header = host_headers[0].strip().lower()
        return host_header in self.viewer_server.allowed_hosts

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

    def send_react_static(self, relative_path: str) -> None:
        """Send a generated React asset from the isolated build directory."""

        if "\x00" in relative_path or "\\" in relative_path:
            raise RequestError("static file was not found", HTTPStatus.NOT_FOUND)
        react_root = (self.viewer_server.static_path / "react").resolve()
        file_path = (react_root / relative_path).resolve()
        try:
            file_path.relative_to(react_root)
        except ValueError as error:
            raise RequestError("static file was not found", HTTPStatus.NOT_FOUND) from error
        if not file_path.is_file():
            raise RequestError("static file was not found", HTTPStatus.NOT_FOUND)
        style_nonce: str | None = None
        if relative_path == "index.html":
            content_type = "text/html; charset=utf-8"
        else:
            if not relative_path.startswith("assets/"):
                raise RequestError("static file was not found", HTTPStatus.NOT_FOUND)
            content_type = REACT_ASSET_CONTENT_TYPES.get(file_path.suffix.lower())
            if content_type is None:
                raise RequestError("static file was not found", HTTPStatus.NOT_FOUND)
        payload = file_path.read_bytes()
        if relative_path == "index.html":
            html = payload.decode("utf-8")
            if REACT_CSP_NONCE_PLACEHOLDER not in html:
                raise RequestError(
                    "generated React index does not contain the CSP nonce placeholder",
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                )
            style_nonce = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
            payload = html.replace(REACT_CSP_NONCE_PLACEHOLDER, style_nonce).encode(
                "utf-8"
            )
        self.send_response(HTTPStatus.OK)
        self.send_common_headers(content_type, len(payload), style_nonce)
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

    def send_common_headers(
        self,
        content_type: str,
        length: int,
        style_nonce: str | None = None,
    ) -> None:
        """Send local-viewer security and cache headers."""

        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        content_security_policy = (
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'"
        )
        if style_nonce is not None:
            content_security_policy = (
                "default-src 'self'; script-src 'self'; style-src 'self'; "
                f"style-src-elem 'self' 'nonce-{style_nonce}'; "
                "style-src-attr 'unsafe-inline'; img-src 'self' data:; "
                "connect-src 'self'; frame-ancestors 'none'"
            )
        self.send_header("Content-Security-Policy", content_security_policy)

    def log_message(self, message_format: str, *args: Any) -> None:
        """Write compact local access logs."""

        sys.stdout.write("[HTTP] " + (message_format % args) + "\n")


class ViewerServer(ThreadingHTTPServer):
    """Threaded localhost server holding immutable app dependencies."""

    allow_reuse_address = os.name != "nt"
    allow_reuse_port = False
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        database: AlertDatabase,
        static_path: Path,
        *,
        allowed_hosts: Collection[str] | None = None,
    ):
        configured_allowed_hosts = {
            normalize_allowed_host(host) for host in (allowed_hosts or ())
        }
        self.instance_mutex_handle: int | None = None
        if address[1] != 0:
            self.acquire_instance_mutex(address)
        try:
            super().__init__(address, ViewerRequestHandler)
            if address[1] == 0:
                bound_address = (str(self.server_address[0]), int(self.server_address[1]))
                self.acquire_instance_mutex(bound_address)
        except BaseException:
            self.release_instance_mutex()
            raise
        bound_port = int(self.server_address[1])
        self.allowed_hosts = frozenset(
            {
                DEFAULT_HOST,
                f"{DEFAULT_HOST}:{bound_port}",
                *configured_allowed_hosts,
            }
        )
        self.database = database
        self.static_path = static_path

    def server_close(self) -> None:
        """Close the listener and release the Windows single-instance guard."""

        try:
            super().server_close()
        finally:
            self.release_instance_mutex()

    def acquire_instance_mutex(self, address: tuple[str, int]) -> None:
        """Prevent two Windows Viewer processes from sharing one port."""

        if os.name != "nt":
            return
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        create_mutex = kernel32.CreateMutexW
        create_mutex.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
        create_mutex.restype = ctypes.c_void_p
        close_handle = kernel32.CloseHandle
        close_handle.argtypes = [ctypes.c_void_p]
        close_handle.restype = ctypes.c_bool
        host = address[0].replace(":", "_").replace("\\", "_")
        mutex_name = f"Local\\MstngZigZagElliotViewer-{host}-{address[1]}"
        ctypes.set_last_error(0)
        handle = create_mutex(None, False, mutex_name)
        error_code = ctypes.get_last_error()
        if not handle:
            raise ctypes.WinError(error_code)
        if error_code == 183:
            close_handle(handle)
            raise OSError(10048, f"Viewer is already using {address[0]}:{address[1]}")
        self.instance_mutex_handle = int(handle)

    def release_instance_mutex(self) -> None:
        """Release the Windows single-instance guard when held."""

        if self.instance_mutex_handle is None or os.name != "nt":
            return
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        close_handle = kernel32.CloseHandle
        close_handle.argtypes = [ctypes.c_void_p]
        close_handle.restype = ctypes.c_bool
        close_handle(self.instance_mutex_handle)
        self.instance_mutex_handle = None


def normalize_allowed_host(host: str) -> str:
    """Normalize and validate one exact HTTP Host authority."""

    normalized_host = host.strip().lower()
    has_invalid_character = any(
        character.isspace()
        or ord(character) < 32
        or ord(character) == 127
        or character in "*/\\@?#,;%"
        for character in normalized_host
    )
    if not normalized_host or has_invalid_character or normalized_host.endswith(":"):
        raise ValueError("allowed host must be one exact hostname or IP with optional port")

    parsed_host = urlparse(f"//{normalized_host}")
    try:
        port = parsed_host.port
    except ValueError as error:
        raise ValueError("allowed host has an invalid port") from error
    if (
        not parsed_host.hostname
        or parsed_host.username is not None
        or parsed_host.password is not None
        or parsed_host.path
        or parsed_host.query
        or parsed_host.fragment
        or port == 0
    ):
        raise ValueError("allowed host must be one exact hostname or IP with optional port")
    return normalized_host


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
    parser.add_argument(
        "--allowed-host",
        action="append",
        default=[],
        type=normalize_allowed_host,
        metavar="HOST",
        help="additional exact Host header authority (repeatable)",
    )
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

    database: AlertDatabase | None = None
    try:
        database = AlertDatabase(database_path)
        health = database.validate()
    except (RuntimeError, SQLAlchemyError) as error:
        print(f"Database could not be opened: {error}", file=sys.stderr)
        if database is not None:
            database.close()
        return 2
    assert database is not None

    static_path = Path(__file__).resolve().parent / "static"
    try:
        server = ViewerServer(
            (arguments.host, arguments.port),
            database,
            static_path,
            allowed_hosts=arguments.allowed_host,
        )
    except OSError as error:
        print(
            f"Viewer could not listen on {arguments.host}:{arguments.port}: {error}",
            file=sys.stderr,
        )
        database.close()
        return 2
    url = f"http://{DEFAULT_HOST}:{arguments.port}"
    print("ZigZagElliot Alert Viewer")
    print(f"Database: {health['database']}")
    print(f"Alerts: {health['alert_count']} / journal: {health['journal_mode']}")
    if arguments.allowed_host:
        print(f"Allowed proxy Host: {', '.join(arguments.allowed_host)}")
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
        database.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
