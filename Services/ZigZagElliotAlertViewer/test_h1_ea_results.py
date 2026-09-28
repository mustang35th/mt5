"""H1 EA API tests using temporary SQLite files and the production MQL DDL."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

from h1_ea_results import EaRequestError, H1EaResultsDatabase, default_ea_database_path

UID = "a" * 64
KEY = "session:" + UID
DAO = Path(__file__).resolve().parents[2] / "Include/Mstng/Database/Dao"


def ddl(name, method="createSql"):
    source = (DAO / f"H1Ea{name}Dao.mqh").read_text(encoding="utf-8-sig")
    body = source.split(f"static string {method}() {{", 1)[1].split("return sql;", 1)[0]
    return "".join(json.loads(value) for value in re.findall(r'sql\s*(?:=|\+=)\s*("(?:[^"\\]|\\.)*")', body))


class Fixture:
    def __init__(self, path, version=4):
        self.path = Path(path)
        self.connection = sqlite3.connect(path, isolation_level=None)
        self.connection.execute("PRAGMA foreign_keys=ON")
        for name in ("Run", "Decision", "Trade", "TradeEvent"):
            statement = ddl(name)
            if name == "Run" and version < 3:
                statement = statement.replace(" session_uid TEXT CHECK(session_uid IS NULL OR (length(session_uid)=64 AND session_uid NOT GLOB '*[^0-9a-f]*')),", "")
            if name == "Decision" and version < 2:
                statement = statement.replace(" d1_ema200_direction TEXT CHECK(d1_ema200_direction IS NULL OR d1_ema200_direction IN ('BUY', 'SELL', 'NONE')),", "")
            self.connection.execute(statement)
        if version >= 4:
            for method in ("createSessionSql", "createSampleSql", "createDealSql"):
                self.connection.execute(ddl("Result", method))
        self.connection.execute(f"PRAGMA user_version={version}")
        self.version = version
        self.serial = 0

    def close(self):
        self.connection.close()

    def insert(self, table, values):
        return self.connection.execute(f"INSERT INTO h1_ea_{table} ({','.join(values)}) VALUES ({','.join('?' for _ in values)})", tuple(values.values())).lastrowid

    def run(self, **changes):
        self.serial += 1
        values = dict(run_uid=f"run{self.serial}", schema_version=1, source_mode="TESTER",
                      context_key=f"ctx{self.serial}", account_server="fixture", account_login=1,
                      symbol_name="EURUSD", time_frame=16385, magic_number="18446744073709551613",
                      program_version="1", strategy_version="1", analysis_version="1", analysis_input_text="",
                      analysis_input_hash="hash", config_text="MAX_INITIAL_RISK_PIPS=200", config_hash="hash",
                      started_at=1700000000, ended_at=1700000100, heartbeat_at=1700000100,
                      lease_expires_at=1700000160, status="STOPPED", error_text="")
        if self.version >= 3:
            values["session_uid"] = UID
        return self.insert("runs", values | changes)

    def decision(self, run_id, **changes):
        self.serial += 1
        return self.insert("decisions", dict(run_id=run_id, context_key=f"dctx{self.serial}", snapshot_hash="hash",
                    h1_bar_time=1000000000+self.serial*3600, evaluated_server_time=1000000001+self.serial*3600,
                    created_at=1700000000, decision="SKIP", reason_code="JUDGE_NOT_MATCHED",
                    is_judge_matched=0, signal_count=0, entry_count=1, is_entry_evaluated=0,
                    is_strategy_entry=0, is_signal_consumed=0, max_initial_risk_pips=200,
                    is_h1_wave_accepted=0, is_h4_wave_accepted=0, h1_direction_alignment_mode="STRICT",
                    is_h1_direction_alignment_passed=0, analysis_snapshot_text="fixture snapshot") | changes)

    def trade(self, run_id, **changes):
        self.serial += 1
        values = dict(created_run_id=run_id, decision_id=None, context_key=f"tctx{self.serial}", origin="RECOVERED",
                      status="CLOSED", side="BUY", position_identifier=str(100+self.serial),
                      opened_at_msc=1000000000000+self.serial*10000, closed_at_msc=1000000005000+self.serial*10000,
                      opened_volume=1, remaining_position_volume=0, stop_loss_source="NONE",
                      close_reason="EXTERNAL_CLOSE", broker_close_reason="DEAL_REASON_CLIENT",
                      profit=100, commission=-2, swap=-1, fee=-1, last_error="", created_at=1700000000, updated_at=1700000001)
        return self.insert("trades", values | changes)

    def event(self, run_id, trade_id, **changes):
        self.serial += 1
        return self.insert("trade_events", dict(run_id=run_id, trade_id=trade_id, event_uid=f"event{self.serial}",
                    sequence=self.serial, event_type="RECOVERY", event_source="RECONCILIATION",
                    recorded_at=1700000000, message="fixture event") | changes)

    def session(self, **changes):
        return self.insert("sessions", dict(session_uid=UID, source_mode="TESTER", account_currency="USD",
                    account_server="fixture", leverage=100, program_version="1", started_server_time=1000000000,
                    trade_start_time=1000001000, ended_server_time=1000002000, initial_balance=10000,
                    sample_interval_seconds=60, recording_state="RECORDED", statistics_available=1,
                    deals_complete=1, initial_deposit=10000, net_profit=777, equity_drawdown=250,
                    equity_drawdown_percent=2.4, mt5_trades=20, recorded_at=1700000000, finished_at=1700000100) | changes)

    def sample(self, sequence, **changes):
        return self.insert("account_samples", dict(session_uid=UID, sequence=sequence, server_time=1000000000+sequence*60,
                    reason="INTERVAL", balance=10000, equity=10000, margin=0, free_margin=10000,
                    margin_level=0, open_profit=0, positions=0, pending_orders=0, foreign_positions=0, foreign_orders=0) | changes)

    def deal(self, ticket, stamp, position, entry, volume=1, **changes):
        return self.insert("deals", dict(session_uid=UID, ticket=str(ticket), time_msc=stamp, position_identifier=str(position),
                    symbol="EURUSD", magic_number="18446744073709551613", deal_type=0, entry_type=entry,
                    volume=volume, price=1.1, profit=0, commission=0, swap=0, fee=0, reason=0) | changes)


class ResultsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="h1-ea-viewer-")
        self.addCleanup(self.directory.cleanup)
        self.fixture = Fixture(Path(self.directory.name) / "ea.sqlite")
        self.addCleanup(self.fixture.close)
        self.source = H1EaResultsDatabase(self.fixture.path)

    def legacy(self, version=3):
        fixture = Fixture(Path(self.directory.name) / f"legacy{version}.sqlite", version)
        self.addCleanup(fixture.close)
        return fixture, H1EaResultsDatabase(fixture.path)

    def test_legacy_groups_28_runs_and_keeps_null_sessions_separate(self):
        fixture, source = self.legacy()
        for index in range(28):
            fixture.run(symbol_name=f"symbol{index}")
        null_runs = [fixture.run(session_uid=None), fixture.run(session_uid=None)]
        result = source.sessions()
        self.assertEqual(result["total"], 3)
        session = next(row for row in result["items"] if row["key"] == KEY)
        self.assertEqual(session["run_count"], 28)
        self.assertEqual({row["key"] for row in result["items"]}, {KEY, *(f"run:{value}" for value in null_runs)})
        self.assertEqual(session["recording_state"], "UNRECORDED")
        self.assertIsNone(session["account_currency"])
        self.assertIsNone(session["started_server_time"])
        self.assertEqual(source.samples(KEY)["items"], [])
        self.assertFalse(source.summary(KEY)["account_statistics"]["available"])

    def test_physical_v1_v2_without_session_column_remain_readable(self):
        for version in (1, 2):
            fixture, source = self.legacy(version)
            run = fixture.run()
            trade = fixture.trade(run)
            key = f"run:{run}"
            self.assertEqual(source.sessions()["items"][0]["key"], key)
            self.assertEqual(source.trades(key)["items"][0]["id"], trade)
            self.assertFalse(source.detail(trade, {"session": [key]})["deals_recorded"])

    def test_metrics_use_only_closed_trades_with_all_costs_and_keep_account_scope(self):
        self.fixture.session()
        run = self.fixture.run()
        self.fixture.trade(run, profit=104)
        self.fixture.trade(run, profit=-46)
        self.fixture.trade(run, profit=4)
        self.fixture.trade(run, fee=None)
        self.fixture.trade(run, status="OPEN", closed_at_msc=None, profit=9999)
        self.fixture.trade(self.fixture.run(session_uid="b"*64), profit=99999)
        result = self.source.summary(KEY)
        self.assertEqual(result["metrics"], dict(closed_trades=4, open_trades=1, known_pnl_trades=3,
                    unknown_pnl_trades=1, net_profit=50, wins=1, losses=1, breakeven=1,
                    win_rate=100/3, profit_factor=2, average_net_profit=50/3))
        self.assertEqual(result["account_statistics"]["net_profit"], 777)
        self.assertEqual(result["account_statistics"]["equity_drawdown"], 250)
        self.assertEqual(result["account_statistics"]["equity_drawdown_percent"], 2.4)
        self.assertEqual(result["session"]["account_currency"], "USD")
        with self.assertRaises(EaRequestError):
            self.source.summary(KEY, {"profit": ["loss"]})

    def test_unknown_or_nonfinite_costs_are_not_coerced_to_zero(self):
        self.fixture.session()
        run = self.fixture.run()
        for value in (None, "unknown", float("inf"), 1.7976931348623157e308):
            self.fixture.trade(run, fee=value)
        result = self.source.summary(KEY)
        self.assertEqual(result["metrics"]["unknown_pnl_trades"], 4)
        self.assertIsNone(result["metrics"]["net_profit"])
        self.assertIsNone(result["metrics"]["win_rate"])
        self.assertIsNone(result["metrics"]["profit_factor"])
        json.dumps(self.source.trades(KEY), allow_nan=False)

    def test_filter_pagination_and_detail_navigation_share_sort_and_session(self):
        self.fixture.session()
        run = self.fixture.run()
        ids = [self.fixture.trade(run, profit=-value, opened_at_msc=1000000000000) for value in (10, 20, 30)]
        self.fixture.trade(run, profit=50)
        self.fixture.trade(self.fixture.run(symbol_name="USDJPY"), profit=-50)
        other = self.fixture.trade(self.fixture.run(session_uid="b"*64), profit=-50)
        query = {"symbol": ["EURUSD"], "profit": ["loss"], "sort": ["opened_at_msc"], "direction": ["asc"], "page": ["2"], "page_size": ["1"]}
        result = self.source.trades(KEY, query)
        self.assertEqual((result["total"], result["total_pages"]), (3, 3))
        self.assertEqual(result["items"][0]["id"], ids[1])
        detail = self.source.detail(ids[1], query | {"session": [KEY]})
        self.assertEqual((detail["previous_id"], detail["next_id"]), (ids[0], ids[2]))
        with self.assertRaises(EaRequestError) as caught:
            self.source.detail(other, {"session": [KEY]})
        self.assertEqual(caught.exception.status, 404)

    def test_detail_preserves_raw_decision_stop_loss_events_and_large_ticket_strings(self):
        self.fixture.session()
        run = self.fixture.run()
        decision = self.fixture.decision(run, d1_ema200_direction="BUY")
        trade = self.fixture.trade(run, decision_id=decision, position_identifier="18446744073709551614")
        self.fixture.event(run, trade, stop_loss=1.2, previous_stop_loss=1.1, stop_loss_source="H1_ZIGZAG_TRAIL")
        self.fixture.deal("18446744073709551615", 1000000000001, "18446744073709551614", 0)
        result = self.source.detail(trade, {"session": [KEY]})
        self.assertEqual(result["decision"]["d1_ema200_direction"], "BUY")
        self.assertEqual(result["events"][0]["stop_loss"], 1.2)
        self.assertEqual(result["deals"][0]["ticket"], "18446744073709551615")
        self.assertTrue(result["deals_recorded"])
        self.assertEqual(result["trade"]["holding_seconds"], 5)

    def test_skip_reasons_are_scoped_to_all_runs_in_the_session(self):
        self.fixture.session()
        for _ in range(2):
            self.fixture.decision(self.fixture.run())
        self.fixture.decision(self.fixture.run(session_uid="b"*64))
        self.assertEqual(self.source.summary(KEY)["skip_reasons"], [{"reason_code": "JUDGE_NOT_MATCHED", "count": 2}])

    def test_complete_deals_replay_partial_quantities_and_ignore_foreign_positions(self):
        self.fixture.session()
        self.fixture.run()
        self.fixture.deal(1, 1000, 11, 0, 0.3)
        self.fixture.deal(2, 2000, 11, 1, 0.1)
        self.fixture.deal(3, 3000, 12, 0, 0.1)
        self.fixture.deal(4, 4000, 11, 1, 0.2, magic_number="0")
        self.fixture.deal(5, 5000, 12, 1, 0.1)
        for position in range(100, 104):
            self.fixture.deal(position, 1500, position, 0, magic_number="777")
        result = self.source.summary(KEY)["max_positions"]
        self.assertEqual((result["value"], result["quality"]), (2, "EXACT"))
        self.assertEqual(result["source"], "SESSION_DEALS")

    def test_same_millisecond_and_remaining_positions_are_reference_only(self):
        self.fixture.session()
        self.fixture.run()
        self.fixture.deal(1, 1000, 11, 0)
        self.fixture.deal(2, 1000, 12, 0)
        result = self.source.summary(KEY)["max_positions"]
        self.assertIsNone(result["value"])
        self.assertEqual((result["reference_value"], result["quality"]), (2, "REFERENCE"))

    def test_missing_entry_or_unsupported_reversal_never_reports_exact(self):
        self.fixture.session()
        self.fixture.run()
        self.fixture.deal(1, 1000, 11, 1)
        result = self.source.summary(KEY)["max_positions"]
        self.assertIsNone(result["value"])
        self.assertEqual(result["quality"], "UNAVAILABLE")
        self.fixture.connection.execute("UPDATE h1_ea_deals SET entry_type=2")
        self.assertEqual(self.source.summary(KEY)["max_positions"]["quality"], "UNAVAILABLE")

    def test_closed_trade_missing_all_deals_prevents_exact_zero(self):
        self.fixture.session()
        self.fixture.trade(self.fixture.run())
        self.assertIsNone(self.source.summary(KEY)["max_positions"]["value"])

    def test_legacy_event_replay_is_explicitly_reference(self):
        fixture, source = self.legacy()
        run = fixture.run()
        trade = fixture.trade(run)
        for ticket, stamp, entry in (("1", 1000, "IN"), ("2", 2000, "OUT")):
            fixture.event(run, trade, event_type="DEAL_ADD", deal_ticket=ticket, deal_scope_key=ticket,
                          broker_time_msc=stamp, position_identifier="11", side="BUY", broker_reason="CLIENT",
                          volume=1, message="DEAL_ENTRY_"+entry)
        result = source.summary(KEY)["max_positions"]
        self.assertIsNone(result["value"])
        self.assertEqual((result["reference_value"], result["quality"]), (1, "REFERENCE"))

    def test_samples_are_bounded_keep_endpoints_extrema_and_gap_segments(self):
        self.fixture.session()
        self.fixture.run()
        self.fixture.connection.execute("BEGIN")
        for index in range(1, 4002):
            gap = 3600 if index >= 2000 else 0
            self.fixture.sample(index, server_time=1000000000+index*60+gap,
                                balance=12000 if index == 234 else 10000,
                                equity=5000 if index == 345 else 10000,
                                open_profit=-3000 if index == 567 else 0,
                                positions=12 if index == 789 else 0 if index == 901 else 1)
        self.fixture.connection.execute("COMMIT")
        result = self.source.samples(KEY, {"max_points": ["80"]})
        self.assertEqual(result["total"], 4001)
        self.assertLessEqual(result["returned"], 80)
        self.assertTrue(result["downsampled"])
        sequences = {row["sequence"] for row in result["items"]}
        self.assertTrue({1, 234, 345, 567, 789, 901, 4001} <= sequences)
        self.assertEqual(min(row["positions"] for row in result["items"]), 0)
        self.assertEqual(max(row["positions"] for row in result["items"]), 12)
        self.assertTrue(any(row["gap_before"] for row in result["items"]))
        self.assertEqual({row["segment_id"] for row in result["items"]}, {1, 2})
        for maximum in (16, 19, 20, 1500):
            with self.subTest(max_points=maximum):
                bounded = self.source.samples(KEY, {"max_points": [str(maximum)]})
                self.assertLessEqual(bounded["returned"], maximum)
                self.assertTrue({789, 901} <= {row["sequence"] for row in bounded["items"]})
        with self.assertRaises(EaRequestError):
            self.source.samples(KEY, {"max_points": ["5001"]})

    def test_recording_without_runs_is_visible_and_failed_statistics_stay_null(self):
        self.fixture.session(recording_state="FAILED", statistics_available=0, deals_complete=0,
                             initial_deposit=None, net_profit=None, equity_drawdown=None,
                             equity_drawdown_percent=None, mt5_trades=None, error_text="fixture locked")
        self.assertEqual(self.source.sessions()["items"][0]["run_count"], 0)
        result = self.source.summary(KEY)
        self.assertFalse(result["account_statistics"]["available"])
        self.assertIsNone(result["account_statistics"]["equity_drawdown"])
        self.assertEqual(result["session"]["error_text"], "fixture locked")

    def test_readonly_requests_leave_fixture_bytes_unchanged_and_reject_writes(self):
        self.fixture.session()
        self.fixture.trade(self.fixture.run())
        digest = hashlib.sha256(self.fixture.path.read_bytes()).hexdigest()
        for call in (self.source.metadata, self.source.sessions, lambda: self.source.summary(KEY), lambda: self.source.trades(KEY)):
            call()
        with self.source._snapshot({}) as (connection, *_):
            self.assertEqual(connection.execute("PRAGMA query_only").fetchone()[0], 1)
            with self.assertRaises(sqlite3.OperationalError):
                connection.execute("DELETE FROM h1_ea_trades")
        self.assertEqual(hashlib.sha256(self.fixture.path.read_bytes()).hexdigest(), digest)

    def test_live_wal_append_keeps_identity_and_is_visible_on_next_request(self):
        self.fixture.connection.execute("PRAGMA journal_mode=WAL")
        self.fixture.session()
        run = self.fixture.run()
        key = self.source.metadata()["database_key"]
        self.fixture.trade(run)
        self.assertEqual(self.source.trades(KEY, {"database_key": [key]})["total"], 1)
        self.assertEqual(self.source.metadata()["database_key"], key)

    def test_replacing_database_rejects_stale_identity(self):
        self.fixture.session()
        key = self.source.metadata()["database_key"]
        replacement = Fixture(Path(self.directory.name) / "replacement.sqlite")
        replacement.close()
        self.fixture.close()
        self.fixture.close = lambda: None
        os.replace(replacement.path, self.fixture.path)
        with self.assertRaises(EaRequestError) as caught:
            self.source.sessions({"database_key": [key]})
        self.assertEqual(caught.exception.status, 409)

    def test_missing_corrupt_unsupported_and_bad_path_are_distinct_unavailable_metadata(self):
        missing = H1EaResultsDatabase(Path(self.directory.name)/"missing.sqlite")
        self.assertEqual(missing.metadata()["status"], "NOT_FOUND")
        self.assertFalse(missing.database_path.exists())
        with self.assertRaises(EaRequestError) as caught:
            missing.sessions()
        self.assertEqual(caught.exception.status, 503)
        corrupt = Path(self.directory.name)/"corrupt.sqlite"
        corrupt.write_bytes(b"not a sqlite database")
        self.assertEqual(H1EaResultsDatabase(corrupt).metadata()["status"], "UNSUPPORTED")
        self.assertEqual(H1EaResultsDatabase("bad\x00.sqlite").metadata()["status"], "UNAVAILABLE")
        self.fixture.connection.execute("PRAGMA user_version=99")
        self.assertEqual(self.source.metadata()["status"], "UNSUPPORTED")

    def test_parameter_validation_rejects_sql_injection_duplicates_and_bad_limits(self):
        self.fixture.session()
        self.fixture.run()
        for params in ({"sort": ["id; DROP TABLE h1_ea_runs"]}, {"profit": ["loss", "win"]},
                       {"page_size": ["201"]}, {"page": ["0"]}, {"extra": [""]}, {"direction": ["sideways"]}):
            with self.subTest(params=params), self.assertRaises(EaRequestError):
                self.source.trades(KEY, params)
        for key in ("session:' OR 1=1 --", "run:0", "run:9223372036854775808"):
            with self.assertRaises(EaRequestError):
                self.source.summary(key)
        self.assertTrue(self.source.metadata()["available"])


if __name__ == "__main__":
    unittest.main()
