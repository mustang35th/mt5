"""Read-only H1 EA sessions, trade results, and recorded account history."""

from __future__ import annotations

import hashlib
import math
import os
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path
from typing import Any

MAX_INTEGER = (1 << 63) - 1
ACTIVE = ("OPEN_PENDING", "OPEN_PARTIAL", "OPEN", "CLOSE_PENDING", "CLOSE_PARTIAL", "RECOVERY_REQUIRED")
SORTS = {"opened_at_msc", "closed_at_msc", "net_profit", "symbol_name", "id"}
FILTERS = {"symbol", "profit", "status", "sort", "direction", "page", "page_size", "database_key"}
REQUIRED = {
    "h1_ea_runs": set("id run_uid source_mode account_server symbol_name magic_number program_version started_at ended_at status config_text".split()),
    "h1_ea_trades": set("id created_run_id decision_id position_identifier status side opened_at_msc closed_at_msc profit commission swap fee".split()),
    "h1_ea_decisions": set("id run_id h1_bar_time decision reason_code".split()),
    "h1_ea_trade_events": set("id trade_id event_type broker_time_msc deal_ticket position_identifier volume side message".split()),
}
RECORDING = {
    "h1_ea_sessions": set("session_uid source_mode account_currency account_server leverage program_version started_server_time trade_start_time ended_server_time initial_balance sample_interval_seconds recording_state statistics_available deals_complete initial_deposit net_profit equity_drawdown equity_drawdown_percent mt5_trades error_text recorded_at finished_at".split()),
    "h1_ea_account_samples": set("session_uid sequence server_time reason balance equity margin free_margin margin_level open_profit positions pending_orders foreign_positions foreign_orders".split()),
    "h1_ea_deals": set("session_uid ticket time_msc position_identifier symbol magic_number deal_type entry_type volume price profit commission swap fee reason".split()),
}


class EaRequestError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


class _Unavailable(EaRequestError):
    def __init__(self, state: str, message: str):
        super().__init__(message, 503)
        self.state = state


def default_ea_database_path() -> Path:
    roaming = os.environ.get("APPDATA")
    if roaming:
        return Path(roaming) / "MetaQuotes/Terminal/Common/Files/mstng-h1-ea-tester.sqlite"
    return Path.home() / "AppData/Roaming/MetaQuotes/Terminal/Common/Files/mstng-h1-ea-tester.sqlite"


def _params(params: dict[str, list[str]] | None, allowed: set[str]) -> dict[str, str]:
    result = {}
    for name, values in (params or {}).items():
        if name not in allowed or len(values) != 1:
            raise EaRequestError(f"unsupported or duplicated EA parameter: {name}")
        value = values[0].strip()
        if len(value) > 512:
            raise EaRequestError(f"{name} is too long")
        result[name] = value
    return result


def _integer(value: str | None, name: str, default: int, maximum: int = MAX_INTEGER) -> int:
    if value is None:
        return default
    if not re.fullmatch(r"[0-9]+", value) or not 0 < int(value) <= maximum:
        raise EaRequestError(f"{name} must be between 1 and {maximum}")
    return int(value)


def _number(value: Any) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return float(value)
    return None


def _clean(row: Any) -> Any:
    if isinstance(row, (dict, sqlite3.Row)):
        return {key: _clean(row[key]) for key in row.keys()}
    if isinstance(row, (list, tuple)):
        return [_clean(item) for item in row]
    if isinstance(row, float) and not math.isfinite(row):
        return None
    return row


def _net_sql() -> str:
    valid = " AND ".join(f"typeof(t.{name}) IN ('integer','real') AND abs(t.{name}) < 1.0e308" for name in ("profit", "commission", "swap", "fee"))
    return f"CASE WHEN {valid} AND abs(t.profit+t.commission+t.swap+t.fee)<1.0e308 THEN t.profit+t.commission+t.swap+t.fee ELSE NULL END"


class H1EaResultsDatabase:
    """Each request owns a bounded read transaction; no schema repair or writes."""

    def __init__(self, database_path: Path | str | None = None):
        self.instance_key = uuid.uuid4().hex
        self.configuration_error = None
        self.database_path = None
        try:
            if database_path is not None and "\x00" in str(database_path):
                raise ValueError("embedded null character")
            self.database_path = Path(database_path or default_ea_database_path()).resolve()
        except (OSError, ValueError, RuntimeError) as error:
            self.configuration_error = f"H1 EA database path is invalid: {error}"

    def close(self) -> None:
        # Connections are request-scoped, including after exceptions.
        pass

    def _info(self) -> dict[str, str]:
        identity = "missing"
        try:
            if self.database_path is not None:
                stat = self.database_path.stat()
                identity = f"{stat.st_dev}:{stat.st_ino}"
        except (OSError, ValueError):
            pass
        path = str(self.database_path) if self.database_path is not None else ""
        key = hashlib.sha256(f"{self.instance_key}|{os.path.normcase(path)}|{identity}".encode()).hexdigest()
        return {"path": path, "name": self.database_path.name if self.database_path else "", "key": "ea_" + key}

    @contextmanager
    def _snapshot(self, values: dict[str, str]):
        connection = None
        try:
            if self.configuration_error is not None:
                raise _Unavailable("UNAVAILABLE", self.configuration_error)
            if not self.database_path.is_file():
                raise _Unavailable("NOT_FOUND", "H1 EA database was not found")
            info = self._info()
            if "database_key" in values and values["database_key"] != info["key"]:
                raise EaRequestError("H1 EA database changed; reload sessions", 409)
            connection = sqlite3.connect(self.database_path.as_uri() + "?mode=ro", uri=True, timeout=1)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA query_only=ON")
            deadline = time.monotonic() + 10
            connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 2000)
            connection.execute("BEGIN")
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version not in (1, 2, 3, 4):
                raise _Unavailable("UNSUPPORTED", f"Unsupported H1 EA schema version: {version}")
            tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_schema WHERE type='table'")}
            columns = {}
            for name, required in {**REQUIRED, **RECORDING}.items():
                columns[name] = {row[1] for row in connection.execute(f"PRAGMA table_info({name})")} if name in tables else set()
                if name in REQUIRED and not required <= columns[name]:
                    raise _Unavailable("UNSUPPORTED", f"Required H1 EA columns are missing: {name}")
            if tables & RECORDING.keys():
                if "session_uid" not in columns["h1_ea_runs"]:
                    raise _Unavailable("UNSUPPORTED", "Recording schema requires Run session_uid")
                for name, required in RECORDING.items():
                    if not required <= columns[name]:
                        raise _Unavailable("UNSUPPORTED", f"Recording schema is incomplete: {name}")
            elif version == 4:
                raise _Unavailable("UNSUPPORTED", "H1 EA recording tables are missing")
            if self._info() != info:
                raise EaRequestError("H1 EA database changed; reload sessions", 409)
            yield connection, columns, info, version
            if self._info() != info:
                raise EaRequestError("H1 EA database changed; reload sessions", 409)
        except sqlite3.Error as error:
            code = getattr(error, "sqlite_errorcode", 0) & 255
            state = "UNAVAILABLE"
            if code in (sqlite3.SQLITE_NOTADB, sqlite3.SQLITE_CORRUPT):
                state = "UNSUPPORTED"
            raise _Unavailable(state, "H1 EA database is unavailable or the query timed out") from error
        except OSError as error:
            raise _Unavailable("UNAVAILABLE", "H1 EA database cannot be read") from error
        finally:
            if connection is not None:
                connection.rollback()
                connection.close()

    def metadata(self, params=None) -> dict[str, Any]:
        values = _params(params, {"database_key"})
        try:
            with self._snapshot(values) as (_, columns, info, version):
                return {"available": True, "status": "READY", "reason": None, "database": info,
                        "database_key": info["key"], "schema_version": version,
                        "recording_supported": bool(columns["h1_ea_sessions"])}
        except _Unavailable as error:
            info = self._info()
            return {"available": False, "status": error.state, "reason": str(error), "database": info,
                    "database_key": info["key"], "schema_version": None, "recording_supported": False}

    @staticmethod
    def _run_key(columns, alias="r") -> str:
        if "session_uid" not in columns["h1_ea_runs"]:
            return f"'run:' || {alias}.id"
        return f"CASE WHEN {alias}.session_uid IS NOT NULL AND {alias}.session_uid<>'' THEN 'session:' || {alias}.session_uid ELSE 'run:' || {alias}.id END"

    def _session(self, connection, columns, key: str) -> dict[str, Any]:
        if not re.fullmatch(r"(?:session:[0-9a-f]{64}|run:[1-9][0-9]*)", key):
            raise EaRequestError("invalid EA session key")
        if key.startswith("run:") and int(key[4:]) > MAX_INTEGER:
            raise EaRequestError("invalid EA run id")
        runs = connection.execute(f"SELECT r.* FROM h1_ea_runs r WHERE {self._run_key(columns)}=? ORDER BY id", (key,)).fetchall()
        session_uid = key[8:] if key.startswith("session:") else None
        recorded = None
        if columns["h1_ea_sessions"] and session_uid:
            recorded = connection.execute("SELECT * FROM h1_ea_sessions WHERE session_uid=?", (session_uid,)).fetchone()
        if not runs and recorded is None:
            raise EaRequestError("H1 EA session was not found", 404)
        row = dict(recorded) if recorded is not None else {}
        first = dict(runs[0]) if runs else {}
        result = {"key": key, "session_uid": session_uid, "legacy": recorded is None,
                  "source_mode": row.get("source_mode", first.get("source_mode", "")),
                  "account_currency": row.get("account_currency") or None,
                  "account_server": row.get("account_server", first.get("account_server", "")),
                  "program_version": row.get("program_version", first.get("program_version", "")),
                  "run_count": len(runs), "symbols": sorted({run["symbol_name"] for run in runs}),
                  "started_server_time": row.get("started_server_time"), "trade_start_time": row.get("trade_start_time"),
                  "ended_server_time": row.get("ended_server_time"), "recording_state": row.get("recording_state", "UNRECORDED"),
                  "statistics_available": row.get("statistics_available") == 1, "deals_complete": row.get("deals_complete") == 1,
                  "run_ids": [run["id"] for run in runs], "run_statuses": sorted({run["status"] for run in runs}),
                  "sample_interval_seconds": row.get("sample_interval_seconds"), "error_text": row.get("error_text"),
                  "leverage": row.get("leverage"), "initial_balance": row.get("initial_balance"),
                  "started_at": min((run["started_at"] for run in runs), default=row.get("recorded_at")),
                  "config_texts": list(dict.fromkeys(run["config_text"] for run in runs))}
        return _clean(result)

    def sessions(self, params=None):
        values = _params(params, {"page", "page_size", "database_key"})
        page = _integer(values.get("page"), "page", 1, 1000000)
        size = _integer(values.get("page_size"), "page_size", 50, 200)
        with self._snapshot(values) as (connection, columns, info, _):
            keys = f"SELECT {self._run_key(columns)} AS key, MAX(r.started_at) AS started FROM h1_ea_runs r GROUP BY key"
            if columns["h1_ea_sessions"]:
                keys += " UNION ALL SELECT 'session:' || s.session_uid, s.recorded_at FROM h1_ea_sessions s WHERE NOT EXISTS(SELECT 1 FROM h1_ea_runs r WHERE r.session_uid=s.session_uid)"
            total = connection.execute(f"SELECT COUNT(*) FROM ({keys})").fetchone()[0]
            rows = connection.execute(f"SELECT * FROM ({keys}) ORDER BY started DESC,key DESC LIMIT ? OFFSET ?", (size, (page-1)*size)).fetchall()
            return {"items": [self._session(connection, columns, row["key"]) for row in rows], "total": total,
                    "page": page, "page_size": size, "database_key": info["key"]}

    def _trade_source(self, columns) -> str:
        return f"SELECT t.*,r.symbol_name,r.run_uid,{self._run_key(columns)} AS session_key,{_net_sql()} AS net_profit FROM h1_ea_trades t JOIN h1_ea_runs r ON r.id=t.created_run_id"

    @staticmethod
    def _trade(row) -> dict[str, Any]:
        result = _clean(row)
        opened = _number(result.get("opened_at_msc"))
        closed = _number(result.get("closed_at_msc"))
        result["holding_seconds"] = (closed-opened)/1000 if opened and closed and closed >= opened else None
        return result

    @staticmethod
    def _trade_filter(values):
        profit = values.get("profit", "all")
        status = values.get("status", "all")
        sort = values.get("sort", "opened_at_msc")
        direction = values.get("direction", "desc")
        if profit not in ("all", "win", "loss") or status not in ("all", "closed", "open") or sort not in SORTS or direction not in ("asc", "desc"):
            raise EaRequestError("invalid EA trade filter or sort")
        where = "session_key=:session"
        bindings = {}
        if values.get("symbol"):
            where += " AND symbol_name=:symbol"
            bindings["symbol"] = values["symbol"]
        if profit != "all":
            where += " AND status='CLOSED' AND net_profit " + (">0" if profit == "win" else "<0")
        if status == "closed":
            where += " AND status='CLOSED'"
        elif status == "open":
            where += " AND status IN (" + ",".join(f"'{state}'" for state in ACTIVE) + ")"
        order = f"({sort} IS NULL) ASC, {sort} {direction.upper()}, id {direction.upper()}"
        return where, bindings, order

    def trades(self, key: str, params=None):
        values = _params(params, FILTERS)
        page = _integer(values.get("page"), "page", 1, 1000000)
        size = _integer(values.get("page_size"), "page_size", 50, 200)
        where, bindings, order = self._trade_filter(values)
        bindings["session"] = key
        with self._snapshot(values) as (connection, columns, info, _):
            self._session(connection, columns, key)
            source = self._trade_source(columns)
            total = connection.execute(f"SELECT COUNT(*) FROM ({source}) WHERE {where}", bindings).fetchone()[0]
            rows = connection.execute(f"SELECT * FROM ({source}) WHERE {where} ORDER BY {order} LIMIT :limit OFFSET :offset", {**bindings, "limit": size, "offset": (page-1)*size}).fetchall()
            return {"items": [self._trade(row) for row in rows], "total": total, "page": page,
                    "page_size": size, "total_pages": (total+size-1)//size, "database_key": info["key"]}

    def summary(self, key: str, params=None):
        values = _params(params, {"database_key"})
        with self._snapshot(values) as (connection, columns, info, _):
            session = self._session(connection, columns, key)
            active_sql = ",".join(f"'{state}'" for state in ACTIVE)
            aggregate = connection.execute(f"""SELECT
                COUNT(CASE WHEN status='CLOSED' THEN 1 END) AS closed_trades,
                COUNT(CASE WHEN status IN ({active_sql}) THEN 1 END) AS open_trades,
                COUNT(CASE WHEN status='CLOSED' THEN net_profit END) AS known_pnl_trades,
                COUNT(CASE WHEN status='CLOSED' AND net_profit>0 THEN 1 END) AS wins,
                COUNT(CASE WHEN status='CLOSED' AND net_profit<0 THEN 1 END) AS losses,
                SUM(CASE WHEN status='CLOSED' THEN net_profit END) AS net_profit,
                SUM(CASE WHEN status='CLOSED' AND net_profit>0 THEN net_profit END) AS gross_wins,
                SUM(CASE WHEN status='CLOSED' AND net_profit<0 THEN net_profit END) AS gross_losses
                FROM ({self._trade_source(columns)}) WHERE session_key=?""", (key,)).fetchone()
            metrics = {name: aggregate[name] for name in ("closed_trades", "open_trades", "known_pnl_trades", "wins", "losses", "net_profit")}
            known = metrics["known_pnl_trades"]
            metrics.update(unknown_pnl_trades=metrics["closed_trades"]-known,
                           win_rate=100*metrics["wins"]/known if known else None,
                           profit_factor=(aggregate["gross_wins"] or 0)/-aggregate["gross_losses"] if metrics["losses"] else None,
                           breakeven=known-metrics["wins"]-metrics["losses"],
                           average_net_profit=metrics["net_profit"]/known if known else None)
            account = {"available": False, **{name: None for name in ("initial_deposit", "net_profit", "equity_drawdown", "equity_drawdown_percent", "mt5_trades")}}
            if session["statistics_available"]:
                recorded = connection.execute("SELECT * FROM h1_ea_sessions WHERE session_uid=?", (session["session_uid"],)).fetchone()
                account.update({name: _number(recorded[name]) for name in account if name != "available"})
                account["available"] = True
            reasons = connection.execute(f"SELECT d.reason_code,COUNT(*) AS count FROM h1_ea_decisions d JOIN h1_ea_runs r ON r.id=d.run_id WHERE {self._run_key(columns)}=? AND d.decision='SKIP' GROUP BY d.reason_code ORDER BY count DESC,d.reason_code", (key,)).fetchall()
            warnings = []
            if session["legacy"]:
                warnings.append("資産推移・MT5標準統計は未記録です。")
            if metrics["unknown_pnl_trades"]:
                warnings.append("費用未取得の決済済み取引を成績計算から除外しています。")
            if session["recording_state"] in ("FAILED", "INTERRUPTED"):
                warnings.append("記録が未完了です。予定期間の完走を示すものではありません。")
            return _clean({"session": session, "metrics": metrics, "account_statistics": account,
                           "max_positions": self._max_positions(connection, columns, session),
                           "skip_reasons": reasons, "warnings": warnings, "database_key": info["key"]})

    def _max_positions(self, connection, columns, session):
        source = "NONE"
        complete = False
        if columns["h1_ea_deals"] and not session["legacy"]:
            source = "SESSION_DEALS"
            # Reconfirm ownership against this session's runs before using a position in this metric.
            # Include all exits by position ID, even when an external close has a different magic.
            rows = connection.execute("""WITH owned AS (
                SELECT d.position_identifier FROM h1_ea_deals d
                WHERE d.session_uid=:session AND d.deal_type IN (0,1) AND EXISTS(
                    SELECT 1 FROM h1_ea_runs r WHERE r.session_uid=:session
                    AND r.symbol_name=d.symbol AND r.magic_number=d.magic_number)
                UNION SELECT t.position_identifier FROM h1_ea_trades t JOIN h1_ea_runs r ON r.id=t.created_run_id
                    WHERE r.session_uid=:session AND t.position_identifier IS NOT NULL
            ) SELECT ticket,time_msc,position_identifier,entry_type,volume FROM h1_ea_deals
                WHERE session_uid=:session AND deal_type IN (0,1) AND position_identifier IN(SELECT position_identifier FROM owned)
                ORDER BY time_msc,length(ticket),ticket LIMIT 200001""", {"session": session["session_uid"]}).fetchall()
            complete = session["deals_complete"] and session["recording_state"] == "RECORDED"
            missing = connection.execute("""SELECT COUNT(*) FROM h1_ea_trades t JOIN h1_ea_runs r ON r.id=t.created_run_id
                WHERE r.session_uid=? AND t.opened_at_msc IS NOT NULL AND NOT EXISTS(
                    SELECT 1 FROM h1_ea_deals d WHERE d.session_uid=r.session_uid
                    AND d.position_identifier=t.position_identifier AND d.deal_type IN (0,1))""", (session["session_uid"],)).fetchone()[0]
            complete = complete and not missing
        else:
            source = "TRADE_EVENTS"
            rows = connection.execute(f"SELECT e.deal_ticket AS ticket,e.broker_time_msc AS time_msc,CAST(e.trade_id AS TEXT) AS position_identifier,e.message AS entry_type,e.volume FROM h1_ea_trade_events e JOIN h1_ea_trades t ON t.id=e.trade_id JOIN h1_ea_runs r ON r.id=t.created_run_id WHERE {self._run_key(columns)}=? AND e.event_type='DEAL_ADD' ORDER BY e.broker_time_msc,e.id LIMIT 200001", (session["key"],)).fetchall()
        result = {"value": None, "reference_value": None, "quality": "UNAVAILABLE", "reason": "約定履歴がありません。", "source": source}
        if len(rows) > 200000:
            result["reason"] = "約定件数が集計上限を超えています。"
            return result
        if not rows and not complete:
            return result
        positions = {}
        peak = 0
        previous_time = None
        tickets = set()
        uncertain = not complete
        invalid = False
        entry_names = {"DEAL_ENTRY_IN": 0, "DEAL_ENTRY_OUT": 1, "DEAL_ENTRY_INOUT": 2, "DEAL_ENTRY_OUT_BY": 3}
        for row in rows:
            volume = _number(row["volume"])
            stamp = row["time_msc"]
            ticket = row["ticket"]
            position = row["position_identifier"]
            entry = entry_names.get(row["entry_type"], row["entry_type"])
            if not isinstance(stamp, int) or stamp <= 0 or not ticket or ticket in tickets or not position or volume is None or volume <= 0 or entry not in (0, 1, 3):
                invalid = True
                break
            tickets.add(ticket)
            if stamp == previous_time:
                uncertain = True
            previous_time = stamp
            current = positions.get(position, Decimal(0))
            amount = Decimal(str(volume))
            if entry == 0:
                positions[position] = current + amount
            elif current < amount:
                invalid = True
                break
            elif current == amount:
                positions.pop(position)
            else:
                positions[position] = current - amount
            peak = max(peak, len(positions))
        if invalid:
            result["reason"] = "約定の欠落・数量不整合・未対応反転があり復元できません。"
            return result
        if positions:
            uncertain = True
        result.update(reference_value=peak, quality="REFERENCE", reason="未完了または同一ミリ秒内の順序を保証できない約定復元の参考値です。")
        if not uncertain:
            result.update(value=peak, quality="EXACT", reason="記録完了した約定の数量を復元した最大同時保有数です。")
        return result

    def samples(self, key: str, params=None):
        values = _params(params, {"max_points", "database_key"})
        maximum = _integer(values.get("max_points"), "max_points", 1500, 5000)
        if maximum < 16:
            raise EaRequestError("max_points must be at least 16")
        with self._snapshot(values) as (connection, columns, info, _):
            session = self._session(connection, columns, key)
            interval = session.get("sample_interval_seconds") or 60
            gap = max(120, interval*2)
            result = {"items": [], "total": 0, "returned": 0, "downsampled": False,
                      "recorded": not session["legacy"], "sample_interval_seconds": interval,
                      "gap_threshold_seconds": gap, "database_key": info["key"]}
            if session["legacy"]:
                return result
            total = connection.execute("SELECT COUNT(*) FROM h1_ea_account_samples WHERE session_uid=?", (session["session_uid"],)).fetchone()[0]
            # Preserve first/last and extrema of every plotted series in each bin.
            bins = max(1, maximum//10)
            sql = """WITH ordered AS (
                SELECT *,ROW_NUMBER() OVER(ORDER BY server_time,sequence) AS rn,
                LAG(server_time) OVER(ORDER BY server_time,sequence) AS previous_time
                FROM h1_ea_account_samples WHERE session_uid=:session
            ), segmented AS (
                SELECT *,SUM(CASE WHEN previous_time IS NULL OR server_time-previous_time>:gap THEN 1 ELSE 0 END)
                OVER(ORDER BY rn) AS segment_id,CAST((rn-1)*:bins/:total AS INTEGER) AS bucket FROM ordered
            ), ranked AS (
                SELECT *,ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY rn) AS first_rank,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY rn DESC) AS last_rank,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY equity,rn) AS eq_min,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY equity DESC,rn) AS eq_max,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY balance,rn) AS bal_min,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY balance DESC,rn) AS bal_max,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY open_profit,rn) AS pnl_min,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY open_profit DESC,rn) AS pnl_max,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY positions,rn) AS positions_min,
                ROW_NUMBER() OVER(PARTITION BY bucket ORDER BY positions DESC,rn) AS positions_max FROM segmented
            ) SELECT * FROM ranked WHERE :total<=:maximum OR first_rank=1 OR last_rank=1 OR eq_min=1 OR eq_max=1
                OR bal_min=1 OR bal_max=1 OR pnl_min=1 OR pnl_max=1
                OR positions_min=1 OR positions_max=1 ORDER BY rn"""
            rows = connection.execute(sql, {"session": session["session_uid"], "gap": gap, "bins": bins, "total": max(total, 1), "maximum": maximum}).fetchall()
            items = []
            previous_segment = None
            for row in rows:
                item = {name: row[name] for name in RECORDING["h1_ea_account_samples"]}
                item["segment_id"] = row["segment_id"]
                item["gap_before"] = previous_segment is not None and previous_segment != row["segment_id"]
                previous_segment = row["segment_id"]
                items.append(item)
            result.update(items=_clean(items), total=total, returned=len(items), downsampled=len(items)<total)
            return result

    def detail(self, trade_id: int, params=None):
        values = _params(params, FILTERS | {"session"})
        if not isinstance(trade_id, int) or not 0 < trade_id <= MAX_INTEGER:
            raise EaRequestError("invalid EA trade id")
        key = values.get("session", "")
        where, bindings, order = self._trade_filter(values)
        bindings.update(session=key, id=trade_id)
        with self._snapshot(values) as (connection, columns, info, _):
            session = self._session(connection, columns, key)
            row = connection.execute(f"SELECT * FROM ({self._trade_source(columns)}) WHERE session_key=:session AND id=:id", bindings).fetchone()
            if row is None:
                raise EaRequestError("H1 EA trade was not found in this session", 404)
            navigation = connection.execute(f"WITH filtered AS (SELECT id,LAG(id) OVER(ORDER BY {order}) AS previous_id,LEAD(id) OVER(ORDER BY {order}) AS next_id FROM ({self._trade_source(columns)}) WHERE {where}) SELECT * FROM filtered WHERE id=:id", bindings).fetchone()
            decision = None
            if row["decision_id"] is not None:
                decision = connection.execute(f"SELECT d.* FROM h1_ea_decisions d JOIN h1_ea_runs r ON r.id=d.run_id WHERE d.id=? AND {self._run_key(columns)}=?", (row["decision_id"], key)).fetchone()
            events = connection.execute("SELECT * FROM h1_ea_trade_events WHERE trade_id=? ORDER BY id LIMIT 5001", (trade_id,)).fetchall()
            deals = []
            recorded = bool(columns["h1_ea_deals"]) and not session["legacy"]
            if recorded and row.keys() and "position_identifier" in row.keys() and row["position_identifier"]:
                deals = connection.execute("SELECT * FROM h1_ea_deals WHERE session_uid=? AND position_identifier=? ORDER BY time_msc,length(ticket),ticket LIMIT 5001", (session["session_uid"], row["position_identifier"])).fetchall()
            return _clean({"session": session, "trade": self._trade(row), "decision": decision,
                           "events": events[:5000], "events_truncated": len(events)>5000,
                           "deals": deals[:5000], "deals_recorded": recorded, "deals_truncated": len(deals)>5000,
                           "previous_id": navigation["previous_id"] if navigation else None,
                           "next_id": navigation["next_id"] if navigation else None, "database_key": info["key"]})
