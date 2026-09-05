"""Exercise the exact MQL5 CREATE statements using isolated in-memory SQLite."""
import json
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DAO = ROOT / "Include" / "Mstng" / "Database" / "Dao"


def schema_statements():
    for name in ("Run", "Decision", "Trade", "TradeEvent"):
        source = (DAO / f"H1Ea{name}Dao.mqh").read_text(encoding="utf-8-sig")
        body = source.split("static string createSql() {", 1)[1].split("return sql;", 1)[0]
        literals = re.findall(r'sql\s*(?:=|\+=)\s*("(?:[^"\\]|\\.)*")', body)
        yield "".join(json.loads(value) for value in literals)
        for value in re.findall(r'H1EaSql::execute\(fromHandle, ("CREATE (?:UNIQUE )?INDEX[^"]+")\)', source):
            yield json.loads(value)


class DatabaseContractTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys=ON")
        for statement in schema_statements():
            self.db.execute(statement)
        self.run = self.insert("runs", self.run_values())
        self.serial = 0

    def tearDown(self):
        self.db.close()

    def insert(self, table, values):
        names = ",".join(values)
        params = ",".join("?" for _ in values)
        return self.db.execute(
            f"INSERT INTO h1_ea_{table} ({names}) VALUES ({params})", tuple(values.values())
        ).lastrowid

    def run_values(self, **changes):
        values = dict(
            run_uid="run1", schema_version=1, source_mode="LIVE", context_key="ctx",
            account_server="server", account_login=1, symbol_name="EURUSD", time_frame=16385,
            magic_number="1201020501", program_version="1", strategy_version="1",
            analysis_version="1", analysis_input_text="", analysis_input_hash="hash",
            config_text="ZIGZAG_SL_BUFFER_PIPS=10.0", config_hash="hash", started_at=1,
            heartbeat_at=1, lease_expires_at=61, status="RUNNING", error_text="",
        )
        return values | changes

    def decision_values(self, **changes):
        self.serial += 1
        values = dict(
            run_id=self.run, context_key="ctx", snapshot_hash="hash", h1_bar_time=self.serial * 3600,
            evaluated_server_time=self.serial * 3600 + 1, created_at=1, decision="SKIP",
            reason_code="JUDGE_NOT_MATCHED", is_judge_matched=0, signal_count=0, entry_count=1,
            is_entry_evaluated=0, is_strategy_entry=0, is_signal_consumed=0,
            max_initial_risk_pips=200, is_h1_wave_accepted=0, is_h4_wave_accepted=0,
            h1_direction_alignment_mode="mode", is_h1_direction_alignment_passed=0,
            analysis_snapshot_text="snapshot",
        )
        return values | changes

    def consumed_values(self, **changes):
        return self.decision_values(
            is_judge_matched=1, signal_count=1, is_entry_evaluated=1,
            is_signal_consumed=1, signal_reference_time=100, signal_side="BUY",
        ) | changes

    def entry_values(self, **changes):
        return self.consumed_values(
            decision="BUY", reason_code="ENTRY", is_strategy_entry=1, initial_stop_loss=1.1,
        ) | changes

    def trade_values(self, **changes):
        decision = self.insert("decisions", self.entry_values())
        values = dict(
            created_run_id=self.run, decision_id=decision, context_key="ctx", origin="NORMAL",
            status="OPEN_PENDING", side="BUY", requested_volume=0.01, requested_stop_loss=1.1,
            stop_loss_source="NONE", last_error="", created_at=1, updated_at=1,
        )
        return values | changes

    def event_values(self, trade, **changes):
        values = dict(
            trade_id=trade, run_id=self.run, event_uid="event1", sequence=1,
            event_type="RECOVERY", event_source="RECONCILIATION", recorded_at=1, message="",
        )
        return values | changes

    def test_exact_columns(self):
        for table, count in (("runs", 23), ("decisions", 41), ("trades", 51), ("trade_events", 38)):
            self.assertEqual(len(self.db.execute(f"PRAGMA table_info(h1_ea_{table})").fetchall()), count)

    def test_exact_sqlite_schema_text_matches_context_validation(self):
        count = 0
        for statement in schema_statements():
            kind, name = re.match(r"CREATE (?:UNIQUE )?(TABLE|INDEX) IF NOT EXISTS (\w+)", statement).groups()
            actual = self.db.execute("SELECT sql FROM sqlite_schema WHERE type=? AND name=?",
                                     (kind.lower(), name)).fetchone()[0]
            normalize = lambda text: text.replace("IF NOT EXISTS ", "").replace(";", "")
            self.assertEqual(normalize(actual), normalize(statement), name)
            count += 1
        self.assertEqual(count, 28)

    def test_successor_run_distinguishes_expiry_from_snapshot_ownership_loss(self):
        query = "SELECT COUNT(*) FROM h1_ea_runs WHERE context_key=? AND id>?"
        self.db.execute("UPDATE h1_ea_runs SET heartbeat_at=1,lease_expires_at=1")
        self.assertEqual(self.db.execute(query, ("ctx", self.run)).fetchone()[0], 0)
        self.db.execute("UPDATE h1_ea_runs SET status='INTERRUPTED'")
        second = self.insert("runs", self.run_values(run_uid="run2"))
        self.assertEqual(self.db.execute(query, ("ctx", self.run)).fetchone()[0], 1)
        self.assertEqual(self.db.execute(query, ("ctx", second)).fetchone()[0], 0)

    def test_run_context_unique_and_expired_handover(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("runs", self.run_values(run_uid="run2"))
        self.db.execute("UPDATE h1_ea_runs SET status='INTERRUPTED' WHERE lease_expires_at<=62")
        second = self.insert("runs", self.run_values(run_uid="run2", heartbeat_at=62, lease_expires_at=122))
        self.assertGreater(second, self.run)

    def test_invalid_run_contracts(self):
        for change in (dict(source_mode="OTHER"), dict(status="NEW"), dict(schema_version=2),
                       dict(time_frame=5), dict(heartbeat_at=0), dict(lease_expires_at=0)):
            with self.subTest(change=change), self.assertRaises(sqlite3.IntegrityError):
                self.insert("runs", self.run_values(run_uid="bad", context_key="other", **change))

    def test_consumed_skip_has_no_trade_and_survives_restart(self):
        self.insert("decisions", self.consumed_values(reason_code="H1_WAVE_REJECTED"))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trades").fetchone()[0], 0)
        self.db.execute("UPDATE h1_ea_runs SET status='STOPPED'")
        self.run = self.insert("runs", self.run_values(run_uid="run2"))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("decisions", self.consumed_values())
        self.insert("decisions", self.decision_values())
        self.insert("decisions", self.consumed_values(signal_count=2, is_entry_evaluated=0, is_signal_consumed=0))
        count = self.db.execute("SELECT MAX(signal_count) FROM h1_ea_decisions WHERE signal_reference_time=100").fetchone()[0]
        self.assertEqual(count, 2)

    def test_bar_unique_even_other_run(self):
        values = self.decision_values()
        self.insert("decisions", values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("decisions", values)

    def test_buy_sell_requires_consumption_entry_and_sl(self):
        bad = (
            dict(initial_stop_loss=None), dict(initial_stop_loss=0), dict(is_strategy_entry=0),
            dict(is_entry_evaluated=0), dict(is_signal_consumed=0), dict(signal_count=0),
            dict(is_judge_matched=0), dict(signal_reference_time=None), dict(signal_reference_time=0),
            dict(signal_side=None), dict(signal_side="SELL"), dict(entry_count=2),
            dict(decision="WAIT"), dict(is_h1_wave_accepted=2),
        )
        for change in bad:
            with self.subTest(change=change), self.assertRaises(sqlite3.IntegrityError):
                self.insert("decisions", self.entry_values(**change))

    def test_valid_none_ema_and_zero_gmma(self):
        self.insert("decisions", self.decision_values(w1_ema200_direction="NONE", h1_gmma_trend_count=0,
                                                    spread_pips=0))
        self.assertEqual(self.db.execute(
            "SELECT w1_ema200_direction,h1_ema200_direction,h1_gmma_trend_count,spread_pips FROM h1_ea_decisions"
        ).fetchone(), ("NONE", None, 0, 0.0))

    def test_active_trade_and_decision_unique(self):
        values = self.trade_values()
        self.insert("trades", values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trades", values | dict(origin="RECOVERED", decision_id=None))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trades", values | dict(context_key="other"))

    def test_initial_restore_has_no_fake_pivot(self):
        values = self.trade_values(status="OPEN", pending_stop_loss_kind="INITIAL_RESTORE", pending_stop_loss=1.1)
        self.insert("trades", values)
        for extra in ("pending_stop_loss_h1_bar_time", "pending_stop_loss_pivot_time",
                      "pending_stop_loss_pivot_rate", "pending_stop_loss_latest_time"):
            with self.subTest(extra=extra), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f"UPDATE h1_ea_trades SET {extra}=123")

    def test_trail_pending_all_required_and_valid_states(self):
        values = self.trade_values(status="OPEN", pending_stop_loss_kind="TRAIL_CANDIDATE",
            pending_stop_loss=1.2, pending_stop_loss_h1_bar_time=3600,
            pending_stop_loss_pivot_time=100, pending_stop_loss_pivot_rate=1.21,
            pending_stop_loss_latest_time=200)
        trade = self.insert("trades", values)
        for field in ("pending_stop_loss_kind", "pending_stop_loss", "pending_stop_loss_h1_bar_time",
                      "pending_stop_loss_pivot_time", "pending_stop_loss_pivot_rate", "pending_stop_loss_latest_time"):
            with self.subTest(field=field), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f"UPDATE h1_ea_trades SET {field}=NULL WHERE id=?", (trade,))
        for status in ("OPEN_PARTIAL", "CLOSE_PENDING", "CLOSE_PARTIAL", "CLOSED", "OPEN_FAILED"):
            with self.subTest(status=status), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("UPDATE h1_ea_trades SET status=?", (status,))
        self.db.execute("UPDATE h1_ea_trades SET status='RECOVERY_REQUIRED'")

    def test_partial_entry_allows_only_initial_protection_restore(self):
        values = self.trade_values(status="OPEN_PARTIAL", pending_stop_loss_kind="INITIAL_RESTORE",
                                   pending_stop_loss=1.1)
        self.insert("trades", values)
        for kind in ("TRAIL_CANDIDATE", "TRAIL_RESTORE"):
            with self.subTest(kind=kind), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("UPDATE h1_ea_trades SET pending_stop_loss_kind=?,"
                                "pending_stop_loss_h1_bar_time=3600,pending_stop_loss_pivot_time=100,"
                                "pending_stop_loss_pivot_rate=1.2,pending_stop_loss_latest_time=200", (kind,))

    def test_applied_trail_cannot_be_partial(self):
        trade = self.insert("trades", self.trade_values())
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE h1_ea_trades SET last_applied_trail_stop_loss=1.2 WHERE id=?", (trade,))

    def test_source_and_sl_must_agree(self):
        self.insert("trades", self.trade_values())
        for clause in ("current_stop_loss=1.2", "stop_loss_source='H1_ZIGZAG_TRAIL'",
                       "stop_loss_source='EXTERNAL'", "current_stop_loss=-1,stop_loss_source='UNKNOWN'"):
            with self.subTest(clause=clause), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("UPDATE h1_ea_trades SET " + clause)
        self.db.execute("UPDATE h1_ea_trades SET current_stop_loss=1.2,stop_loss_source='UNKNOWN'")

    def test_closed_requires_time_reasons_and_pending_clear(self):
        self.insert("trades", self.trade_values())
        for clause in ("status='CLOSED'", "status='CLOSED',closed_at_msc=100",
                       "status='CLOSED',closed_at_msc=100,close_reason='UNKNOWN_CLOSE'"):
            with self.subTest(clause=clause), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("UPDATE h1_ea_trades SET " + clause)
        self.db.execute("UPDATE h1_ea_trades SET status='CLOSED',closed_at_msc=100,"
                        "close_reason='H1_ZIGZAG_TRAIL',broker_close_reason='SL',profit=0,commission=0,swap=0,fee=0")
        self.assertEqual(self.db.execute("SELECT profit,commission,swap,fee FROM h1_ea_trades").fetchone(), (0, 0, 0, 0))

    def test_event_identity_sequence_action_and_deal_unique(self):
        trade = self.insert("trades", self.trade_values())
        values = self.event_values(trade, event_type="ENTRY_REQUEST", action_uid="action",
                                   event_source="EA")
        self.insert("trade_events", values)
        for change in (dict(sequence=2), dict(event_uid="other"), dict(event_uid="other", sequence=2)):
            with self.subTest(change=change), self.assertRaises(sqlite3.IntegrityError):
                self.insert("trade_events", values | change)

    def test_trail_evaluation_once_per_bar_and_complete_pivot(self):
        trade = self.insert("trades", self.trade_values())
        values = self.event_values(trade, event_type="TRAIL_EVALUATION", h1_bar_time=3600,
                                   trail_skip_reason="NO_NEW_PIVOT")
        self.insert("trade_events", values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trade_events", values | dict(sequence=2, event_uid="other"))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trade_events", values | dict(sequence=2, event_uid="other", h1_bar_time=7200,
                                                      trail_skip_reason=None, stop_loss=1.2))

    def test_sl_result_distinguishes_zero_from_unavailable(self):
        trade = self.insert("trades", self.trade_values())
        values = self.event_values(trade, event_type="SL_MODIFY_RESULT", action_uid="action",
            position_identifier="123", position_ticket="456", stop_loss=1.1,
            stop_loss_action_kind="INITIAL_RESTORE")
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trade_events", values)
        self.insert("trade_events", values | dict(is_confirmed_stop_loss_present=0))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trade_events", values | dict(event_uid="other", action_uid="action2", sequence=2,
                                                      is_confirmed_stop_loss_present=1))
        self.insert("trade_events", values | dict(event_uid="other", action_uid="action2", sequence=2,
                                                  is_confirmed_stop_loss_present=1, confirmed_stop_loss=1.1))

    def test_entry_atomic_failure_rolls_back_decision_trade_event(self):
        self.db.execute("BEGIN IMMEDIATE")
        values = self.trade_values()
        trade = self.insert("trades", values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("trade_events", self.event_values(trade, event_type="ENTRY_REQUEST"))
        self.db.execute("ROLLBACK")
        for table in ("decisions", "trades", "trade_events"):
            self.assertEqual(self.db.execute(f"SELECT COUNT(*) FROM h1_ea_{table}").fetchone()[0], 0)

    def test_foreign_keys_restrict_deletion(self):
        self.insert("trades", self.trade_values())
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM h1_ea_runs")

    def test_quarantine_reads_actual_null_and_malformed_storage_types(self):
        trade = self.insert("trades", self.trade_values())
        source = (DAO / "H1EaTradeDao.mqh").read_text(encoding="utf-8-sig")
        body = source.split("static string pendingRawColumns() {", 1)[1].split("}", 1)[0]
        columns = json.loads(re.search(r'return\s+("[^"]+")', body).group(1))
        query = "SELECT " + columns + " FROM h1_ea_trades WHERE id=?"
        self.assertEqual(self.db.execute(query, (trade,)).fetchone(), ("null", "NULL") * 7)
        # Only the isolated in-memory fixture bypasses CHECKs to simulate damaged external data.
        self.db.execute("PRAGMA ignore_check_constraints=ON")
        self.db.execute("UPDATE h1_ea_trades SET pending_stop_loss_kind='bad|種別',"
                        "pending_stop_loss_h1_bar_time=0,pending_stop_loss='malformed''|値' WHERE id=?", (trade,))
        self.db.execute("PRAGMA ignore_check_constraints=OFF")
        actual = self.db.execute(query, (trade,)).fetchone()
        self.assertEqual(actual[:6], ("text", "'bad|種別'", "integer", "0", "text", "'malformed''|値'"))
        self.assertEqual(actual[6:], ("null", "NULL") * 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
