"""Independent, read-only M5 observation queries (no H1 entry evaluation)."""

from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import quote

from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Connection
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.pool import NullPool


RUN_TABLE = "zigzag_elliot_alert_runs"
OBSERVATION_TABLE = "zigzag_elliot_observations"
TIMEFRAME_TABLE = "zigzag_elliot_observation_timeframes"
METRICS_TABLE = "zigzag_elliot_observation_capture_metrics"
METRIC_COLUMNS = (
    "quote_tick_time_msc", "capture_market_time", "analysis_elapsed_ms",
    "capture_elapsed_ms", "analysis_attempt_count",
)
RUN_COLUMNS = tuple("""
    id run_uid schema_version source_mode source program_name program_version
    strategy strategy_version analysis_version analysis_input_text analysis_input_hash
    source_server terminal_build tester_from tester_to tester_model started_at
    started_at_text market_started_at market_started_at_text created_at created_at_text
""".split())
REQUIRED_COLUMNS = {
    RUN_TABLE: set("""
        id run_uid schema_version source_mode source_server program_name program_version
        strategy strategy_version analysis_version analysis_input_text analysis_input_hash
    """.split()),
    OBSERVATION_TABLE: set("""
        id run_id source_mode source_server symbol_name anchor_time_frame
        anchor_time_frame_text anchor_bar_time anchor_bar_time_text anchor_jst_time
        anchor_jst_time_text capture_phase spread_pips pip_size analysis_version
        analysis_input_hash snapshot_hash time_frame_count created_at created_at_text
    """.split()),
    TIMEFRAME_TABLE: set("""
        id observation_id time_frame time_frame_text time_frame_order is_anchor_time_frame
        is_buy buy_sell_label wave_count latest_wave_index is_wave_confirmed is_wave_motive
        is_wave_uptrend wave_trend_label previous_last_elliot_label point_count
        latest_elliot_index latest_elliot_label latest_sub_elliot_index latest_sub_elliot_label
        latest_point_time latest_point_time_text latest_point_jst_time
        latest_point_jst_time_text latest_point_rate previous_open previous_high previous_low
        previous_close current_open current_high current_low current_close
        is_fibo_expansion_available fe618_price fe1000_price fe1272_price fe1618_price
        fe2000_price distance_to_fe2000_pips oscillator_count is_oscillator_buy
        stochastic_main_order stochastic_main_order_text stochastic_main_direction_text
        stochastic_short_count stochastic_short_main stochastic_short_signal
        stochastic_middle_count stochastic_middle_main stochastic_middle_signal
        stochastic_long_count stochastic_long_main stochastic_long_signal
        gmma_trend_count gmma_cross_count ema30 ema60 ema30_ema60_diff_pips atr14_pips
        ema200_close1 ema200_shift1 ema200_compare ema200_slope_pips
        ema200_close_diff_pips ema200_close_position ema200_slope_direction
        ema200_up_count ema200_down_count ema200_trend_count is_ema200_buy is_ema200_sell
        created_at created_at_text
    """.split()),
}
MAX_SQLITE_INTEGER = (1 << 63) - 1
QUERY_TIMEOUT_SECONDS = 10.0
M5_RUN_PREDICATE = """
    r.strategy = 'M5_OBSERVATION_ALL'
    AND r.strategy_version = 'M5_OBSERVATION_ALL_V1'
    AND r.schema_version = 1
"""


class M5RequestError(Exception):
    """An isolated M5 request error with an HTTP-compatible status."""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


class _Unavailable(Exception):
    """A persistent connection/schema state returned by metadata."""

    def __init__(self, status: str, reason: str):
        super().__init__(reason)
        self.status = status


def _parameters(params: dict[str, list[str]], allowed: set[str]) -> dict[str, str]:
    """Reject unknown, duplicated or oversized parameters before constructing SQL."""

    result = {}
    for name, values in params.items():
        if name not in allowed:
            raise M5RequestError(f"unsupported M5 parameter: {name}")
        if len(values) != 1 or not isinstance(values[0], str):
            raise M5RequestError(f"{name} must be specified once")
        value = values[0].strip()
        if len(value) > 512:
            raise M5RequestError(f"{name} is too long")
        result[name] = value
    return result


def _positive(value: str | None, name: str, default: int | None = None) -> int:
    """Parse a bounded positive integer without passing huge offsets to SQLite."""

    if value is None or value == "":
        if default is not None:
            return default
        raise M5RequestError(f"{name} is required")
    if re.fullmatch(r"[0-9]+", value) is None:
        raise M5RequestError(f"{name} must be a positive integer")
    number = int(value)
    if number < 1 or number > MAX_SQLITE_INTEGER:
        raise M5RequestError(f"{name} is outside the supported range")
    return number


def _source_mode(params: dict[str, str]) -> str:
    mode = params.get("sourceMode", "TESTER")
    if mode not in {"TESTER", "LIVE"}:
        raise M5RequestError("sourceMode must be TESTER or LIVE")
    return mode


def _date_boundary(value: str | None, name: str) -> int:
    """Parse the stored JST clock, not an actual UTC conversion, at five minutes."""

    if not value or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}", value) is None:
        raise M5RequestError(f"{name} must use YYYY-MM-DDTHH:mm (JST)")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M").replace(tzinfo=timezone.utc)
    except ValueError as error:
        raise M5RequestError(f"{name} is not a valid date") from error
    if parsed.minute % 5 != 0:
        raise M5RequestError(f"{name} must be on a five-minute boundary")
    return int(parsed.timestamp())


class M5ObservationDatabase:
    """One separately configured M5 source; all access uses read-only snapshots."""

    def __init__(self, database_path: Path | None, *, initialization_error: str | None = None):
        self.database_path = database_path.resolve() if database_path is not None else None
        self.initialization_error = initialization_error
        self.instance_key = uuid.uuid4().hex
        self.engine = None
        if self.database_path is not None:
            path = quote(self.database_path.as_posix(), safe="/:")
            self.engine = create_engine(
                f"sqlite+pysqlite:///file:{path}?mode=ro&uri=true",
                poolclass=NullPool,
                connect_args={"timeout": 5.0},
            )
            event.listen(self.engine, "connect", self._configure_connection)

    @staticmethod
    def _configure_connection(connection: Any, record: Any) -> None:
        del record
        cursor = connection.cursor()
        try:
            cursor.execute("PRAGMA query_only=ON")
            cursor.execute("PRAGMA busy_timeout=5000")
        finally:
            cursor.close()
        deadline = time.monotonic() + QUERY_TIMEOUT_SECONDS
        connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)

    def close(self) -> None:
        """Dispose only this source's connection resources."""

        if self.engine is not None:
            self.engine.dispose()

    def _database_info(self) -> dict[str, Any] | None:
        if self.database_path is None:
            return None
        identity = "missing"
        try:
            stat = self.database_path.stat()
            identity = f"{stat.st_dev}:{stat.st_ino}"
        except FileNotFoundError:
            pass
        path = str(self.database_path)
        key = hashlib.sha256(
            f"{self.instance_key}|{os.path.normcase(path)}|{identity}".encode("utf-8")
        ).hexdigest()
        return {"name": self.database_path.name, "path": path, "key": "m5_" + key}

    @contextmanager
    def _snapshot(self) -> Iterator[tuple[Connection, dict[str, Any], dict[str, set[str]]]]:
        """Revalidate purpose and optional columns within every read transaction."""

        if self.initialization_error is not None:
            raise _Unavailable("UNSUPPORTED", self.initialization_error)
        if self.database_path is None or self.engine is None:
            raise _Unavailable("NOT_CONFIGURED", "M5 database is not configured")
        try:
            if not self.database_path.is_file():
                raise _Unavailable("NOT_FOUND", "M5 database was not found")
            info = self._database_info()
            assert info is not None
            with self.engine.connect() as connection:
                connection.exec_driver_sql("BEGIN")
                try:
                    columns = self._validate(connection)
                    if info != self._database_info():
                        raise M5RequestError("M5 database changed; reload metadata", 409)
                    yield connection, info, columns
                finally:
                    connection.rollback()
        except (OSError, SQLAlchemyError) as error:
            code = getattr(getattr(error, "orig", None), "sqlite_errorcode", None)
            if code is not None and (code & 255) in {sqlite3.SQLITE_NOTADB, sqlite3.SQLITE_CORRUPT}:
                raise _Unavailable("UNSUPPORTED", "M5 database is not a readable SQLite database") from error
            message = "M5 database is temporarily unavailable"
            if "interrupted" in str(error).lower():
                message = "M5 query timed out; narrow the date range and retry"
            raise M5RequestError(message, 503) from error

    @staticmethod
    def _validate(connection: Connection) -> dict[str, set[str]]:
        tables = set(connection.execute(text(
            "SELECT name FROM sqlite_schema WHERE type = 'table'"
        )).scalars())
        missing = set(REQUIRED_COLUMNS) - tables
        if missing:
            raise _Unavailable("UNSUPPORTED", "M5 required tables are missing: " + ", ".join(sorted(missing)))
        columns = {}
        for name in (*REQUIRED_COLUMNS, METRICS_TABLE):
            columns[name] = set()
            if name in tables:
                columns[name] = {
                    row["name"] for row in connection.exec_driver_sql(
                        f"PRAGMA table_info({name})"
                    ).mappings()
                }
            required = REQUIRED_COLUMNS.get(name, set())
            if required - columns[name]:
                raise _Unavailable("UNSUPPORTED", f"M5 required columns are missing from {name}")
        if METRICS_TABLE in tables and "observation_id" not in columns[METRICS_TABLE]:
            raise _Unavailable("UNSUPPORTED", "M5 capture metrics have no observation key")
        invalid_run = connection.execute(text(f"""
            SELECT 1 FROM {RUN_TABLE} AS r
            WHERE NOT ({M5_RUN_PREDICATE})
               OR r.strategy IS NULL OR r.strategy_version IS NULL OR r.schema_version IS NULL
               OR r.source_mode IS NULL OR r.source_mode NOT IN ('TESTER', 'LIVE')
               OR r.source_server IS NULL OR r.source_server = ''
               OR r.analysis_version IS NULL OR r.analysis_version = ''
               OR r.analysis_input_hash IS NULL OR r.analysis_input_hash = ''
               OR r.analysis_input_text IS NULL
               OR substr(r.analysis_input_text, 1, 26) <> 'M5_OBSERVATION_PROFILE_V1|'
            LIMIT 1
        """)).first()
        if invalid_run is not None:
            raise _Unavailable("UNSUPPORTED", "M5 database contains an unsupported or non-M5 Run")
        invalid_parent = connection.execute(text(f"""
            SELECT 1 FROM {OBSERVATION_TABLE} AS o
            LEFT JOIN {RUN_TABLE} AS r ON r.id = o.run_id
            WHERE r.id IS NULL OR o.anchor_time_frame IS NULL OR o.anchor_time_frame <> 5
               OR o.anchor_time_frame_text IS NULL OR o.anchor_time_frame_text <> 'M5'
               OR o.source_mode IS NOT r.source_mode OR o.source_server IS NOT r.source_server
               OR o.analysis_version IS NOT r.analysis_version
               OR o.analysis_input_hash IS NOT r.analysis_input_hash
               OR o.capture_phase IS NULL OR o.capture_phase <> 'BAR_OPEN_FIRST_SUCCESS'
               OR o.anchor_jst_time IS NULL OR o.anchor_jst_time <= 0
               OR o.anchor_jst_time_text IS NULL OR o.anchor_jst_time_text = ''
            LIMIT 1
        """)).first()
        if invalid_parent is not None:
            raise _Unavailable("UNSUPPORTED", "M5 database contains incompatible observations or Run attributes")
        return columns

    @staticmethod
    def _run_projection(columns: set[str], prefix: str = "r.") -> str:
        return ", ".join(prefix + name for name in RUN_COLUMNS if name in columns)

    @staticmethod
    def _selected_run(connection: Connection, run_id: int, mode: str | None, columns: set[str]) -> dict[str, Any]:
        row = connection.execute(text(f"""
            SELECT {M5ObservationDatabase._run_projection(columns)}
            FROM {RUN_TABLE} AS r WHERE r.id = :run_id AND {M5_RUN_PREDICATE}
        """), {"run_id": run_id}).mappings().one_or_none()
        if row is None:
            raise M5RequestError("M5 Run was not found", 404)
        if mode is not None and row["source_mode"] != mode:
            raise M5RequestError("runId does not belong to sourceMode")
        return dict(row)

    @staticmethod
    def _check_database_key(params: dict[str, str], info: dict[str, Any]) -> None:
        if "databaseKey" in params and params["databaseKey"] != info["key"]:
            raise M5RequestError("M5 database changed; reload metadata", 409)

    def metadata(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Return isolated source status and an explicit, nonempty-first Run selection."""

        values = _parameters(params, {"sourceMode", "runId", "databaseKey"})
        mode = _source_mode(values)
        run_id = None
        if "runId" in values:
            run_id = _positive(values["runId"], "runId")
        result: dict[str, Any] = {
            "available": False, "status": "NOT_CONFIGURED", "reason": None,
            "database": None, "sourceMode": mode, "effectiveRunId": None,
            "runs": [], "symbols": [], "range": {"first": None, "last": None},
            "capabilities": {"captureMetricsTable": False, "captureMetricsColumns": []},
        }
        try:
            result["database"] = self._database_info()
            with self._snapshot() as (connection, info, columns):
                self._check_database_key(values, info)
                rows = connection.execute(text(f"""
                    SELECT {self._run_projection(columns[RUN_TABLE])},
                           COALESCE(c.observation_count, 0) AS observation_count,
                           c.first_observation_jst_time, c.last_observation_jst_time
                    FROM {RUN_TABLE} AS r
                    LEFT JOIN (
                        SELECT run_id, COUNT(*) AS observation_count,
                               MIN(anchor_jst_time) AS first_observation_jst_time,
                               MAX(anchor_jst_time) AS last_observation_jst_time
                        FROM {OBSERVATION_TABLE} WHERE anchor_time_frame = 5 GROUP BY run_id
                    ) AS c ON c.run_id = r.id
                    WHERE {M5_RUN_PREDICATE} ORDER BY r.id DESC
                """)).mappings()
                runs = [dict(row) for row in rows]
                if run_id is not None:
                    self._selected_run(connection, run_id, mode, columns[RUN_TABLE])
                else:
                    candidates = [row for row in runs if row["source_mode"] == mode]
                    nonempty = [row for row in candidates if row["observation_count"] > 0]
                    if nonempty:
                        run_id = nonempty[0]["id"]
                    elif candidates:
                        run_id = candidates[0]["id"]
                selected = next((row for row in runs if row["id"] == run_id), None)
                result.update({
                    "available": True, "status": "EMPTY", "database": info,
                    "runs": runs, "effectiveRunId": run_id,
                    "capabilities": {
                        "captureMetricsTable": bool(columns[METRICS_TABLE]),
                        "captureMetricsColumns": sorted(columns[METRICS_TABLE]),
                    },
                })
                if selected is not None:
                    result["range"] = {
                        "first": selected["first_observation_jst_time"],
                        "last": selected["last_observation_jst_time"],
                    }
                    if selected["observation_count"] > 0:
                        result["status"] = "READY"
                    result["symbols"] = list(connection.execute(text(f"""
                        SELECT DISTINCT symbol_name FROM {OBSERVATION_TABLE}
                        WHERE run_id = :run_id AND anchor_time_frame = 5
                        ORDER BY symbol_name COLLATE NOCASE
                    """), {"run_id": run_id}).scalars())
        except _Unavailable as error:
            result.update({"status": error.status, "reason": str(error)})
        except OSError as error:
            raise M5RequestError("M5 database is temporarily unavailable", 503) from error
        return result

    @staticmethod
    def _children(connection: Connection, ids: list[int], columns: dict[str, set[str]]) -> tuple[dict[int, list[dict[str, Any]]], dict[int, dict[str, Any]]]:
        timeframes: dict[int, list[dict[str, Any]]] = {identifier: [] for identifier in ids}
        metrics: dict[int, dict[str, Any]] = {}
        if not ids:
            return timeframes, metrics
        parameters = {f"id{index}": identifier for index, identifier in enumerate(ids)}
        placeholders = ", ".join(":" + name for name in parameters)
        rows = connection.execute(text(f"""
            SELECT * FROM {TIMEFRAME_TABLE} WHERE observation_id IN ({placeholders})
            ORDER BY observation_id, time_frame_order, id
        """), parameters).mappings()
        for row in rows:
            timeframes[row["observation_id"]].append(dict(row))
        if columns[METRICS_TABLE]:
            projection = ["observation_id"]
            for name in METRIC_COLUMNS:
                if name in columns[METRICS_TABLE]:
                    projection.append(name)
                else:
                    projection.append(f"NULL AS {name}")
            rows = connection.execute(text(f"""
                SELECT {', '.join(projection)} FROM {METRICS_TABLE}
                WHERE observation_id IN ({placeholders})
            """), parameters).mappings()
            for row in rows:
                if row["observation_id"] in metrics:
                    raise M5RequestError("M5 capture metrics contain duplicate observation keys", 422)
                metrics[row["observation_id"]] = dict(row)
        return timeframes, metrics

    @staticmethod
    def _metrics_state(columns: dict[str, set[str]], metrics: dict[str, Any] | None) -> dict[str, Any]:
        return {
            "tableAvailable": bool(columns[METRICS_TABLE]),
            "rowAvailable": metrics is not None,
            "missingColumns": [name for name in METRIC_COLUMNS if name not in columns[METRICS_TABLE]],
        }

    def observations(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Read one bounded M5 page without H1-specific conditions or derived signals."""

        values = _parameters(params, {
            "sourceMode", "runId", "symbol", "from", "to", "jstTime",
            "page", "pageSize", "sort", "order", "databaseKey",
        })
        mode = _source_mode(values)
        run_id = _positive(values.get("runId"), "runId")
        first = _date_boundary(values.get("from"), "from")
        last = _date_boundary(values.get("to"), "to")
        if last <= first:
            raise M5RequestError("to must be later than from (exclusive end)")
        page = _positive(values.get("page"), "page", 1)
        page_size = min(_positive(values.get("pageSize"), "pageSize", 50), 200)
        sort = values.get("sort", "anchor_jst_time")
        order = values.get("order", "desc")
        if sort not in {"anchor_jst_time", "symbol_name"} or order not in {"asc", "desc"}:
            raise M5RequestError("unsupported M5 sort or order")
        direction = order.upper()
        order_sql = f"o.anchor_jst_time {direction}, o.id {direction}"
        if sort == "symbol_name":
            order_sql = f"o.symbol_name COLLATE NOCASE {direction}, o.anchor_jst_time DESC, o.id DESC"
        where = f"""o.run_id = :run_id AND o.source_mode = :source_mode
            AND o.anchor_time_frame = 5 AND {M5_RUN_PREDICATE}
            AND o.anchor_jst_time >= :first AND o.anchor_jst_time < :last"""
        parameters: dict[str, Any] = {"run_id": run_id, "source_mode": mode, "first": first, "last": last}
        if values.get("symbol"):
            where += " AND o.symbol_name = :symbol"
            parameters["symbol"] = values["symbol"]
        if values.get("jstTime"):
            clock = values["jstTime"]
            if re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5][05]", clock) is None:
                raise M5RequestError("jstTime must use HH:mm at five-minute intervals")
            where += " AND strftime('%H:%M', o.anchor_jst_time, 'unixepoch') = :clock"
            parameters["clock"] = clock
        source = f"FROM {OBSERVATION_TABLE} AS o INNER JOIN {RUN_TABLE} AS r ON r.id = o.run_id WHERE {where}"
        try:
            with self._snapshot() as (connection, info, columns):
                self._check_database_key(values, info)
                self._selected_run(connection, run_id, mode, columns[RUN_TABLE])
                total = int(connection.execute(text("SELECT COUNT(*) " + source), parameters).scalar_one())
                total_pages = (total + page_size - 1) // page_size
                page = min(page, max(1, total_pages))
                parameters.update({"limit": page_size, "offset": (page - 1) * page_size})
                rows = connection.execute(text(
                    "SELECT o.* " + source + f" ORDER BY {order_sql} LIMIT :limit OFFSET :offset"
                ), parameters).mappings()
                items = [dict(row) for row in rows]
                timeframes, metrics = self._children(connection, [item["id"] for item in items], columns)
                for item in items:
                    item["timeframes"] = timeframes[item["id"]]
                    item["captureMetrics"] = metrics.get(item["id"])
                    item["captureMetricsState"] = self._metrics_state(columns, item["captureMetrics"])
                return {"databaseKey": info["key"], "items": items, "total": total,
                        "page": page, "page_size": page_size, "total_pages": total_pages}
        except _Unavailable as error:
            raise M5RequestError(str(error), 503) from error

    def detail(self, observation_id: int, params: dict[str, list[str]] | None = None) -> dict[str, Any]:
        """Read one record and its neighbours in the exact same M5 Run/Profile stream."""

        if not isinstance(observation_id, int) or isinstance(observation_id, bool) or not 0 < observation_id <= MAX_SQLITE_INTEGER:
            raise M5RequestError("observation id must be a positive integer")
        values = _parameters(params or {}, {"databaseKey"})
        try:
            with self._snapshot() as (connection, info, columns):
                self._check_database_key(values, info)
                row = connection.execute(text(f"""
                    SELECT o.* FROM {OBSERVATION_TABLE} AS o
                    INNER JOIN {RUN_TABLE} AS r ON r.id = o.run_id
                    WHERE o.id = :id AND o.anchor_time_frame = 5 AND {M5_RUN_PREDICATE}
                """), {"id": observation_id}).mappings().one_or_none()
                if row is None:
                    raise M5RequestError("M5 observation was not found", 404)
                observation = dict(row)
                run = self._selected_run(connection, row["run_id"], row["source_mode"], columns[RUN_TABLE])
                timeframes, metrics = self._children(connection, [observation_id], columns)
                navigation = self._navigation(connection, observation)
                return {
                    "databaseKey": info["key"], "observation": observation, "run": run,
                    "timeframes": timeframes[observation_id], "captureMetrics": metrics.get(observation_id),
                    "captureMetricsState": self._metrics_state(columns, metrics.get(observation_id)),
                    "navigation": navigation,
                }
        except _Unavailable as error:
            raise M5RequestError(str(error), 503) from error

    @staticmethod
    def _navigation(connection: Connection, observation: dict[str, Any]) -> dict[str, Any]:
        stream_columns = ("run_id", "source_mode", "source_server", "symbol_name",
                          "capture_phase", "analysis_version", "analysis_input_hash")
        stream = " AND ".join(f"o.{name} = :{name}" for name in stream_columns)
        result = {}
        for name, operator, direction in (("older", "<", "DESC"), ("newer", ">", "ASC")):
            row = connection.execute(text(f"""
                SELECT o.id, o.anchor_bar_time, o.anchor_bar_time_text,
                       o.anchor_jst_time, o.anchor_jst_time_text
                FROM {OBSERVATION_TABLE} AS o INNER JOIN {RUN_TABLE} AS r ON r.id = o.run_id
                WHERE {stream} AND o.anchor_time_frame = 5 AND {M5_RUN_PREDICATE}
                  AND (o.anchor_jst_time {operator} :anchor_jst_time
                       OR (o.anchor_jst_time = :anchor_jst_time AND o.id {operator} :id))
                ORDER BY o.anchor_jst_time {direction}, o.id {direction} LIMIT 1
            """), observation).mappings().one_or_none()
            neighbour = None
            if row is not None:
                neighbour = dict(row)
                neighbour["gap_seconds"] = abs(row["anchor_jst_time"] - observation["anchor_jst_time"])
            result[name] = neighbour
        return result
