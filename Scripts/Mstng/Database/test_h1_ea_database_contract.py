"""Exercise actual MQL DDL/ALTER SQL using isolated in-memory SQLite.

Context/DAO wiring assertions are static, not MQL execution. The MQL database
SmokeTest separately exercises the real migration parser, reconnect and rollback.
"""
import json
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DAO = ROOT / "Include" / "Mstng" / "Database" / "Dao"
CONTEXT = ROOT / "Include" / "Mstng" / "Database" / "H1EaDatabaseContext.mqh"


def decision_migration_sql():
    """Extract the production legacy-removal literal and ALTER SQL, not copies."""
    source = (DAO / "H1EaDecisionDao.mqh").read_text(encoding="utf-8-sig")
    legacy = source.split("static string createLegacySql() {", 1)[1].split("return sql;", 1)[0]
    removal = re.search(r'StringReplace\(sql,\s*("(?:[^"\\]|\\.)*"),\s*""\)', legacy)
    removed_text = json.loads(removal.group(1))
    current = next(statement for statement in schema_statements()
                   if statement.startswith("CREATE TABLE IF NOT EXISTS h1_ea_decisions "))
    if current.count(removed_text) != 1:
        raise AssertionError("Legacy schema must remove exactly the dedicated column")
    alter_body = source.split("static string addD1ColumnSql() {", 1)[1].split("}", 1)[0]
    alter = json.loads(re.search(r'return\s+("(?:[^"\\]|\\.)*")', alter_body).group(1))
    return current.replace(removed_text, ""), alter


def run_migration_sql():
    source = (DAO / "H1EaRunDao.mqh").read_text(encoding="utf-8-sig")
    legacy = source.split("static string createLegacySql() {", 1)[1].split("return sql;", 1)[0]
    removal = json.loads(re.search(r'StringReplace\(sql,\s*("(?:[^"\\]|\\.)*"),\s*""\)', legacy).group(1))
    current = next(sql for sql in schema_statements() if sql.startswith("CREATE TABLE IF NOT EXISTS h1_ea_runs "))
    assert current.count(removal) == 1
    alter = source.split("static string addSessionColumnSql() {", 1)[1].split("}", 1)[0]
    return current.replace(removal, ""), json.loads(re.search(r'return\s+("(?:[^"\\]|\\.)*")', alter).group(1))


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

    def test_session_column_nullable_and_hash_constrained(self):
        self.assertEqual(self.db.execute("PRAGMA table_info(h1_ea_runs)").fetchall()[-1],
                         (23, "session_uid", "TEXT", 0, None, 0))
        self.assertIsNone(self.db.execute("SELECT session_uid FROM h1_ea_runs").fetchone()[0])
        for bad in ("", "a" * 63, "a" * 65, "G" * 64, "A" * 64, "~" * 64):
            with self.subTest(value=bad), self.assertRaises(sqlite3.IntegrityError):
                self.insert("runs", self.run_values(run_uid="new", context_key="other", session_uid=bad))

    def test_28_runs_share_session_but_context_leases_still_exclusive(self):
        for index in range(28):
            self.insert("runs", self.run_values(run_uid=f"child{index}", context_key=f"ctx{index}",
                        symbol_name=f"symbol{index}", session_uid="a" * 64))
        self.assertEqual(self.db.execute("SELECT COUNT(*),COUNT(DISTINCT run_uid) FROM h1_ea_runs WHERE session_uid=?",
                                        ("a" * 64,)).fetchone(), (28, 28))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("runs", self.run_values(run_uid="next", context_key="ctx7", session_uid="b" * 64))
        self.db.execute("UPDATE h1_ea_runs SET status='STOPPED' WHERE session_uid=?", ("a" * 64,))
        self.assertEqual(self.db.execute("SELECT status FROM h1_ea_runs WHERE id=?", (self.run,)).fetchone()[0], "RUNNING")
        self.insert("runs", self.run_values(run_uid="next", context_key="ctx7", session_uid="b" * 64))

    def test_restart_with_new_session_preserves_consumed_signal(self):
        self.insert("decisions", self.consumed_values(reason_code="H1_WAVE_REJECTED"))
        self.db.execute("UPDATE h1_ea_runs SET status='STOPPED'")
        self.run = self.insert("runs", self.run_values(run_uid="new", session_uid="a" * 64))
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert("decisions", self.consumed_values())
        self.assertEqual(self.db.execute("SELECT signal_count FROM h1_ea_decisions WHERE context_key='ctx'").fetchall(), [(1,)])

    def test_v1_to_v3_additive_migration_preserves_rows_and_matches_fresh_schema(self):
        expected = self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_runs'").fetchone()[0]
        decision_alter = self.create_legacy_fixture()
        self.insert("decisions", self.consumed_values())
        previous_runs = self.db.execute("SELECT * FROM h1_ea_runs").fetchall()
        previous_decisions = self.db.execute("SELECT * FROM h1_ea_decisions").fetchall()
        legacy, run_alter = run_migration_sql()
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute(decision_alter)
        self.db.execute("PRAGMA user_version=2")
        self.db.execute(run_alter)
        index = next(sql for sql in schema_statements() if "idx_h1_ea_runs_session_symbol" in sql)
        self.db.execute(index)
        self.db.execute("PRAGMA user_version=3")
        self.db.execute("COMMIT")
        self.assertEqual(self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_runs'").fetchone()[0], expected)
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_runs").fetchall(), [row + (None,) for row in previous_runs])
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_decisions").fetchall(), [row + (None,) for row in previous_decisions])
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 3)

    def test_v2_to_v3_migration_preserves_pending_trade_and_rolls_back_ddl_failure(self):
        decision_alter = self.create_legacy_fixture()
        self.db.execute(decision_alter)
        self.db.execute("PRAGMA user_version=2")
        self.insert("trades", self.trade_values())
        rows = self.db.execute("SELECT * FROM h1_ea_trades").fetchall()
        previous_schema = self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_runs'").fetchone()[0]
        _, alter = run_migration_sql()
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute(alter)
        self.db.execute("PRAGMA user_version=3")
        with self.assertRaises(sqlite3.OperationalError):
            self.db.execute("CREATE INDEX idx_h1_ea_runs_session_symbol ON h1_ea_runs(missing_column)")
        self.db.execute("ROLLBACK")
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 2)
        self.assertEqual(self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_runs'").fetchone()[0], previous_schema)
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_trades").fetchall(), rows)
        self.db.execute(alter)
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_trades").fetchall(), rows)

    def test_v3_migration_requires_initialization_and_no_live_old_run(self):
        context = CONTEXT.read_text(encoding="utf-8-sig")
        self.assertRegex(context, r'version == 2 && fromInitializeSchema\)\s*\{\s*success = this\.migrateSessionUid\(\);')
        migration = context.split("bool migrateSessionUid() {", 1)[1].split("bool prepareSchema", 1)[0]
        for guard in ("this.validateSchema(false, true)", "activeRuns != 0"):
            self.assertLess(migration.index(guard), migration.index("H1EaRunDao::addSessionColumnSql()"))
        self.assertNotIn("UPDATE h1_ea_", migration)
        self.assertLess(migration.index("this.validateSchema()"), migration.index("PRAGMA user_version=3"))

    def test_exact_columns(self):
        for table, count in (("runs", 24), ("decisions", 42), ("trades", 51), ("trade_events", 38)):
            self.assertEqual(len(self.db.execute(f"PRAGMA table_info(h1_ea_{table})").fetchall()), count)

    def test_d1_column_is_nullable_last_column_with_exclusive_known_values(self):
        column = self.db.execute("PRAGMA table_info(h1_ea_decisions)").fetchall()[-1]
        self.assertEqual(column, (41, "d1_ema200_direction", "TEXT", 0, None, 0))
        for direction in (None, "BUY", "SELL", "NONE"):
            with self.subTest(direction=direction):
                row = self.insert("decisions", self.decision_values(d1_ema200_direction=direction))
                self.assertEqual(self.db.execute(
                    "SELECT d1_ema200_direction FROM h1_ea_decisions WHERE id=?", (row,)
                ).fetchone()[0], direction)
        for direction in ("", "NULL", "~", "BOTH", "buy", "BUY ", 0, 1):
            with self.subTest(direction=direction), self.assertRaises(sqlite3.IntegrityError):
                self.insert("decisions", self.decision_values(d1_ema200_direction=direction))

    def test_exact_sqlite_schema_text_matches_context_validation(self):
        count = 0
        for statement in schema_statements():
            kind, name = re.match(r"CREATE (?:UNIQUE )?(TABLE|INDEX) IF NOT EXISTS (\w+)", statement).groups()
            actual = self.db.execute("SELECT sql FROM sqlite_schema WHERE type=? AND name=?",
                                     (kind.lower(), name)).fetchone()[0]
            normalize = lambda text: text.replace("IF NOT EXISTS ", "").replace(";", "")
            self.assertEqual(normalize(actual), normalize(statement), name)
            count += 1
        self.assertEqual(count, 29)

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

    def create_legacy_fixture(self):
        self.db.close()
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys=ON")
        legacy, alter = decision_migration_sql()
        legacy_run, _ = run_migration_sql()
        for statement in schema_statements():
            if "idx_h1_ea_runs_session_symbol" in statement:
                continue
            if statement.startswith("CREATE TABLE IF NOT EXISTS h1_ea_runs "):
                statement = legacy_run
            if statement.startswith("CREATE TABLE IF NOT EXISTS h1_ea_decisions "):
                statement = legacy
            self.db.execute(statement)
        self.db.execute("PRAGMA user_version=1")
        self.run = self.insert("runs", self.run_values(status="STOPPED"))
        return alter

    def test_actual_legacy_plus_alter_matches_fresh_schema_without_reordering(self):
        expected = self.db.execute(
            "SELECT sql FROM sqlite_schema WHERE name='h1_ea_decisions'"
        ).fetchone()[0]
        alter = self.create_legacy_fixture()
        original_columns = self.db.execute("PRAGMA table_info(h1_ea_decisions)").fetchall()
        self.assertEqual(len(original_columns), 41)
        self.db.execute(alter)
        migrated = self.db.execute("PRAGMA table_info(h1_ea_decisions)").fetchall()
        self.assertEqual(migrated[:-1], original_columns)
        self.assertEqual(self.db.execute(
            "SELECT sql FROM sqlite_schema WHERE name='h1_ea_decisions'"
        ).fetchone()[0], expected)

    def test_sql_backfill_changes_only_dedicated_column_and_physical_version(self):
        # Values below are already-decoded fixtures, not a Python replacement
        # for restoreEma200Diagnostics. Actual parser behavior is in MQL Smoke.
        alter = self.create_legacy_fixture()
        snapshots = (
            (None, "H1_EA_DECISION_V1|decision=SKIP"),
            ("BUY", "H1_EA_DECISION_V1|d1_ema200_direction=BUY|is_ema200_confirmation_passed=1"),
            ("SELL", "H1_EA_DECISION_V1|d1_ema200_direction=SELL|is_ema200_confirmation_passed=0"),
            ("NONE", "H1_EA_DECISION_V1|d1_ema200_direction=NONE|is_ema200_confirmation_passed=0"),
            (None, "H1_EA_DECISION_V1|d1_ema200_direction=~|is_ema200_confirmation_passed=0"),
        )
        ids = [self.insert("decisions", self.decision_values(
            analysis_snapshot_text=snapshot, snapshot_hash=f"saved-hash-{index}"
        )) for index, (_, snapshot) in enumerate(snapshots)]
        original_rows = self.db.execute("SELECT * FROM h1_ea_decisions ORDER BY id").fetchall()
        original_run = self.db.execute("SELECT * FROM h1_ea_runs").fetchall()
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute(alter)
        for row_id, (direction, _) in zip(ids, snapshots):
            if direction is not None:
                self.db.execute("UPDATE h1_ea_decisions SET d1_ema200_direction=? WHERE id=?", (direction, row_id))
        self.db.execute("PRAGMA user_version=2")
        self.db.execute("COMMIT")
        migrated = self.db.execute("SELECT * FROM h1_ea_decisions ORDER BY id").fetchall()
        self.assertEqual([row[:-1] for row in migrated], original_rows)
        self.assertEqual([row[-1] for row in migrated], [value for value, _ in snapshots])
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_runs").fetchall(), original_run)
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 2)
        self.assertEqual(self.db.execute("SELECT schema_version FROM h1_ea_runs").fetchone()[0], 1)

    def test_alter_and_completed_backfill_updates_rollback_together(self):
        alter = self.create_legacy_fixture()
        for index in range(133):
            self.insert("decisions", self.decision_values(snapshot_hash=f"old-{index}"))
        original_rows = self.db.execute("SELECT * FROM h1_ea_decisions ORDER BY id").fetchall()
        original_schema = self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_decisions'").fetchone()[0]
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute(alter)
        self.db.execute("UPDATE h1_ea_decisions SET d1_ema200_direction='BUY' WHERE id<=128")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE h1_ea_decisions SET d1_ema200_direction='INVALID' WHERE id=133")
        self.db.execute("ROLLBACK")
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_decisions ORDER BY id").fetchall(), original_rows)
        self.assertEqual(self.db.execute("SELECT sql FROM sqlite_schema WHERE name='h1_ea_decisions'").fetchone()[0], original_schema)

    def test_migration_guard_sql_detects_live_lease_and_case_insensitive_trigger(self):
        self.create_legacy_fixture()
        context = CONTEXT.read_text(encoding="utf-8-sig")
        active_query = re.search(r'"(SELECT COUNT\(\*\) FROM h1_ea_runs WHERE status=\'RUNNING\' AND lease_expires_at>)"', context).group(1)
        trigger_query = json.loads(re.search(r'"SELECT COUNT\(\*\) FROM sqlite_schema WHERE type=\'trigger\'[^"\n]+"', context).group(0))
        self.db.execute("UPDATE h1_ea_runs SET status='RUNNING',lease_expires_at=61")
        self.assertEqual(self.db.execute(active_query + "60").fetchone()[0], 1)
        self.assertEqual(self.db.execute(active_query + "61").fetchone()[0], 0)
        self.assertEqual(self.db.execute(trigger_query).fetchone()[0], 0)
        self.db.execute("CREATE TRIGGER smoke_upper AFTER UPDATE ON H1_EA_DECISIONS BEGIN SELECT 1; END;")
        self.assertEqual(self.db.execute(trigger_query).fetchone()[0], 1)

    def test_migration_and_dao_guards_remain_wired_without_strategy_recalculation(self):
        # Static control-flow contracts complement, but do not execute, MQL.
        context = CONTEXT.read_text(encoding="utf-8-sig")
        self.assertRegex(context, r'version == 1 && fromInitializeSchema\)\s*\{\s*success = this\.migrateD1Ema200Direction\(\) && this\.migrateSessionUid\(\);')
        self.assertRegex(context, r'version == 3\)\s*\{\s*success = this\.validateSchema\(\);')
        migration = context.split("bool migrateD1Ema200Direction() {", 1)[1].split("bool prepareSchema", 1)[0]
        for guard in ("this.validateSchema(true, true)", "activeRuns != 0", "triggers != 0"):
            self.assertLess(migration.index(guard), migration.index("H1EaDecisionDao::addD1ColumnSql()"))
        self.assertLess(migration.index("this.backfillD1Ema200Direction()"), migration.index("PRAGMA user_version=2"))
        backfill = context.split("bool backfillD1Ema200Direction() {", 1)[1].split("bool migrateD1Ema200Direction", 1)[0]
        self.assertIn("H1EaDecisionDao::restoreEma200Diagnostics(decision)", backfill)
        self.assertLess(backfill.index("DatabaseFinalize(request)"), backfill.index("UPDATE h1_ea_decisions SET d1_ema200_direction="))
        self.assertIn("ORDER BY id LIMIT 128", backfill)
        for forbidden in ("snapshot_hash=", "analysis_snapshot_text=", "DecisionBuilder", ".evaluate(", "signal_count=", "decision="):
            self.assertNotIn(forbidden, backfill)
        self.assertIn('H1EaSql::execute(handle, "ROLLBACK")', context)
        dao = (DAO / "H1EaDecisionDao.mqh").read_text(encoding="utf-8-sig")
        insert = dao.split("static bool insert(", 1)[1].split("static bool read(", 1)[0]
        self.assertLess(insert.index("restoreEma200Diagnostics(diagnostics)"), insert.index("INSERT INTO h1_ea_decisions"))
        self.assertIn("diagnostics.d1Ema200Direction != fromEntity.d1Ema200Direction", insert)


if __name__ == "__main__":
    unittest.main(verbosity=2)
