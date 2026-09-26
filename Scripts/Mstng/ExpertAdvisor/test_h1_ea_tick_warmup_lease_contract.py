"""Reservation SQL contracts executed in isolated SQLite memory databases.

SQL expressions are extracted from the production MQL service. The harness
substitutes MQL formatting calls only; it does not simulate the controller,
execute MT5, write a terminal database, or send broker requests.
"""

import ast
from datetime import datetime, timezone
from pathlib import Path
import re
import sqlite3
import unittest

from test_h1_ea_tester_warmup_contract import code_only, method


ROOT = Path(__file__).resolve().parents[3]


def extracted_sql(source, values):
    """Evaluate the production sql initializer with restricted formatting stubs."""
    expression = source.split("string sql =", 1)[1].split(";", 1)[0]
    expression = expression.replace("H1EaSql::text", "sqlText")
    expression = re.sub(r"\((?:datetime|long)\)", "", expression)
    resolved = {}
    # Replace values outside literals, preserving the exact production SQL.
    pieces = re.split(r'("(?:\\.|[^"\\])*")', expression)
    for index, key in enumerate(sorted(values, key=len, reverse=True)):
        name = f"value{index}"
        resolved[name] = values[key]
        for offset in range(0, len(pieces), 2):
            pieces[offset] = re.sub(r"(?<![\w.])" + re.escape(key) + r"(?![\w.])", name, pieces[offset])
    expression = " ".join("".join(pieces).split())

    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Name):
            return resolved[node.id]
        if isinstance(node, ast.Constant) and isinstance(node.value, (str, int)):
            return node.value
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return visit(node.left) + visit(node.right)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and len(node.args) == 1:
            value = visit(node.args[0])
            if node.func.id == "IntegerToString":
                return str(value)
            if node.func.id == "sqlText":
                return "'" + str(value).replace("'", "''") + "'"
        raise AssertionError("Unsupported production SQL expression: " + ast.dump(node))

    return visit(ast.parse("(" + expression + ")", mode="eval"))


class TickWarmupLeaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.service = (ROOT / "Include/Mstng/Database/Service/H1EaPersistenceService.mqh").read_text(encoding="utf-8-sig")
        cls.child = (ROOT / "Include/MstngH1Ea/H1EaController.mqh").read_text(encoding="utf-8-sig")
        cls.executor = (ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh").read_text(encoding="utf-8-sig")
        cls.sentinel = int(datetime(3000, 12, 31, 23, 59, 59, tzinfo=timezone.utc).timestamp())

    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.execute("""CREATE TABLE h1_ea_runs (
            id INTEGER PRIMARY KEY, run_uid TEXT, session_uid TEXT, context_key TEXT,
            source_mode TEXT, status TEXT, heartbeat_at INTEGER, lease_expires_at INTEGER)""")
        self.db.execute("INSERT INTO h1_ea_runs VALUES (1, 'run-a', 'session-a', 'context-a', 'TESTER', 'RUNNING', 100, 160)")
        self.db.commit()

    def write_sql(self, now, previous, expires, **changes):
        values = {"fromNow": now, "fromLeaseExpires": expires, "fromRun.id": 1,
                  "fromRun.runUid": "run-a", "fromRun.sessionUid": "session-a",
                  "fromRun.contextKey": "context-a", "fromRun.leaseExpiresAt": previous}
        values.update(changes)
        return extracted_sql(method(self.service, "writeTesterWarmupLease"), values)

    def test_reservation_survives_multi_hour_and_weekend_tick_gaps_then_restores_sixty_seconds(self):
        self.assertEqual(self.db.execute(self.write_sql(110, 160, self.sentinel)).rowcount, 1)
        for elapsed in (3600, 12 * 3600, 3 * 86400):
            with self.subTest(elapsed=elapsed):
                now = 110 + elapsed
                self.assertEqual(self.db.execute(self.write_sql(now, self.sentinel, self.sentinel)).rowcount, 1)
                self.assertEqual(self.db.execute("SELECT lease_expires_at FROM h1_ea_runs").fetchone()[0], self.sentinel)
        now += 1
        self.assertEqual(self.db.execute(self.write_sql(now, self.sentinel, now + 60)).rowcount, 1)
        self.assertEqual(self.db.execute("SELECT heartbeat_at, lease_expires_at FROM h1_ea_runs").fetchone(), (now, now + 60))

    def test_exact_owner_source_status_and_previous_expiry_are_required(self):
        for column, changed in (("id", 2), ("run_uid", "run-b"), ("session_uid", "session-b"),
                                ("context_key", "context-b"), ("source_mode", "LIVE"),
                                ("status", "STOPPED"), ("lease_expires_at", 161)):
            with self.subTest(column=column):
                self.db.execute("SAVEPOINT changed_owner")
                self.db.execute(f"UPDATE h1_ea_runs SET {column}=?", (changed,))
                before = self.db.execute("SELECT * FROM h1_ea_runs").fetchall()
                self.assertEqual(self.db.execute(self.write_sql(110, 160, self.sentinel)).rowcount, 0)
                self.assertEqual(self.db.execute("SELECT * FROM h1_ea_runs").fetchall(), before)
                self.db.execute("ROLLBACK TO changed_owner")
                self.db.execute("RELEASE changed_owner")

    def test_expiry_boundary_never_revives_an_expired_lease(self):
        for now, expected in ((159, 1), (160, 0), (161, 0), (3 * 86400, 0)):
            with self.subTest(now=now):
                self.db.execute("SAVEPOINT expiry")
                self.assertEqual(self.db.execute(self.write_sql(now, 160, self.sentinel)).rowcount, expected)
                self.db.execute("ROLLBACK TO expiry")
                self.db.execute("RELEASE expiry")

    def test_reservation_restore_rejects_owner_change_and_failed_write_leaves_row_unchanged(self):
        self.db.execute(self.write_sql(110, 160, self.sentinel))
        self.db.execute("UPDATE h1_ea_runs SET run_uid='replacement'")
        self.db.commit()
        before = self.db.execute("SELECT * FROM h1_ea_runs").fetchall()
        self.assertEqual(self.db.execute(self.write_sql(3 * 86400, self.sentinel, 3 * 86400 + 60)).rowcount, 0)
        self.db.execute("PRAGMA query_only=ON")
        with self.assertRaises(sqlite3.OperationalError):
            self.db.execute(self.write_sql(3 * 86400, self.sentinel, 3 * 86400 + 60))
        self.assertEqual(self.db.execute("SELECT * FROM h1_ea_runs").fetchall(), before)

    def test_public_reservation_methods_use_fixed_expiry_and_restore_normal_lease(self):
        self.assertIn("D'3000.12.31 23:59:59'", method(self.service, "getTesterWarmupLeaseExpiresAt"))
        begin = method(self.service, "beginTesterWarmupLease")
        heartbeat = method(self.service, "heartbeatTesterWarmupLease")
        end = method(self.service, "endTesterWarmupLease")
        self.assertIn("writeTesterWarmupLease(fromRun, fromNow, false", begin)
        self.assertIn("writeTesterWarmupLease(fromRun, fromNow, true", heartbeat)
        self.assertIn("writeTesterWarmupLease(fromRun, fromNow, true", end)
        self.assertIn("getTesterWarmupLeaseExpiresAt()", begin)
        self.assertIn("getTesterWarmupLeaseExpiresAt()", heartbeat)
        self.assertIn("fromNow + 60", end)

    def test_service_failures_cannot_update_controller_snapshot(self):
        body = method(self.service, "writeTesterWarmupLease")
        for expected in ("MQLInfoInteger(MQL_TESTER)", 'fromRun.sourceMode != "TESTER"',
                         "fromRequireReservation", "getTesterWarmupLeaseExpiresAt()", "changed == 1"):
            self.assertIn(expected, body)
        complete = body.index("if (!this.complete(success,")
        self.assertLess(body.index("H1EaSql::execute(this.getHandle(), sql)"), complete)
        self.assertLess(complete, body.index("fromRun.heartbeatAt ="))
        self.assertLess(complete, body.rindex("fromRun.leaseExpiresAt ="))
        self.assertIn("return false;", body[complete:body.index("fromRun.heartbeatAt =")])
        # Existing LIVE / single-symbol renewal retains its original short lease.
        normal = method(self.service, "heartbeat")
        self.assertIn("fromRun.leaseExpiresAt = (long)fromNow + 60;", normal)
        self.assertNotIn("TesterWarmup", normal)

    def test_reservation_grants_no_executor_authority_and_failed_restore_keeps_blocking(self):
        begin = code_only(method(self.child, "beginScheduledTickWarmup"))
        self.assertLess(begin.index("!this.canUseScheduledFastTesterWarmup()"), begin.index(".beginTesterWarmupLease("))
        self.assertLess(begin.index(".beginTesterWarmupLease("), begin.index("this.scheduledTickWarmup = true"))
        self.assertIn("this.executor.setManagementAuthority(this.instanceLock.isHeld(), 0)", begin)
        end = code_only(method(self.child, "endScheduledTickWarmup"))
        self.assertLess(end.index("!this.persistence.endTesterWarmupLease("), end.index("this.scheduledTickWarmup = false"))
        failure = end[end.index("!this.persistence.endTesterWarmupLease("):end.index("this.scheduledTickWarmup = false")]
        self.assertIn("this.databaseReady = false", failure)
        self.assertIn("this.updateManagementAuthority()", failure)
        self.assertIn("return false", failure)
        authority = code_only(method(self.child, "updateManagementAuthority"))
        self.assertIn("this.scheduledTickWarmup", authority)
        self.assertRegex(authority, r"if \(this.leaseLost \|\| this.scheduledTickWarmup[\s\S]*?\{\s*expires = 0;")
        self.assertIn("this.executor.setManagementAuthority(this.instanceLock.isHeld(), expires)", authority)
        for name in ("processProtection", "processTradeReconciliation", "processTrail",
                     "getPendingEntryBar", "getPendingTrailBar"):
            self.assertIn("this.scheduledTickWarmup", code_only(method(self.child, name)), name)
        scheduled = code_only(method(self.child, "processScheduledEntry"))
        self.assertLess(scheduled.index("fromBarTime != this.getPendingEntryBar()"), scheduled.index("this.evaluateEntry("))


class AbandonedWarmupCleanupContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parent = (ROOT / "Include/MstngH1Ea/H1EaMultiSymbolController.mqh").read_text(encoding="utf-8-sig")
        cls.sentinel = int(datetime(3000, 12, 31, 23, 59, 59, tzinfo=timezone.utc).timestamp())

    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.execute("""CREATE TABLE h1_ea_runs (
            source_mode TEXT, status TEXT, lease_expires_at INTEGER, account_server TEXT,
            account_login INTEGER, symbol_name TEXT, time_frame INTEGER, magic_number TEXT,
            session_uid TEXT, heartbeat_at INTEGER, ended_at INTEGER, error_text TEXT)""")
        self.db.execute("INSERT INTO h1_ea_runs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        ("TESTER", "RUNNING", self.sentinel, "Broker's Demo", 101, "EURUSD", 16385,
                         "2030", "old-session", 100, 0, ""))
        self.db.commit()
        self.sql = extracted_sql(method(self.parent, "cleanupTesterWarmupReservations"), {
            "H1EaPersistenceService::getTesterWarmupLeaseExpiresAt()": self.sentinel,
            "state.run.accountServer": "Broker's Demo", "state.run.accountLogin": 101,
            "state.run.symbolName": "EURUSD", "PERIOD_H1": 16385,
            "state.run.magicNumber": "2030", "this.sessionUid": "new-session"})

    def test_only_abandoned_matching_reservation_is_interrupted(self):
        self.assertEqual(self.db.execute(self.sql).rowcount, 1)
        self.assertEqual(self.db.execute("SELECT status, ended_at, lease_expires_at, error_text FROM h1_ea_runs").fetchone(),
                         ("INTERRUPTED", 100, 100, "|TESTER_WARMUP_ABANDONED"))
        self.assertEqual(self.db.execute(self.sql).rowcount, 0)

    def test_live_normal_lease_other_scope_current_session_and_single_symbol_are_untouched(self):
        for column, value in (("source_mode", "LIVE"), ("status", "STOPPED"),
                ("lease_expires_at", 160), ("account_server", "Other Broker"),
                ("account_login", 102), ("symbol_name", "USDJPY"), ("time_frame", 15),
                ("magic_number", "9999"), ("session_uid", "new-session"), ("session_uid", None)):
            with self.subTest(column=column, value=value):
                self.db.execute("SAVEPOINT other_scope")
                self.db.execute(f"UPDATE h1_ea_runs SET {column}=?", (value,))
                before = self.db.execute("SELECT * FROM h1_ea_runs").fetchall()
                self.assertEqual(self.db.execute(self.sql).rowcount, 0)
                self.assertEqual(self.db.execute("SELECT * FROM h1_ea_runs").fetchall(), before)
                self.db.execute("ROLLBACK TO other_scope")
                self.db.execute("RELEASE other_scope")

    def test_cleanup_is_tester_only_after_all_locks_before_schema_and_rolls_back_failure(self):
        initialize = code_only(method(self.parent, "initialize"))
        cleanup = initialize.index("this.cleanupTesterWarmupReservations(databaseFileName)")
        self.assertLess(initialize.index(".initializePersistencePreparation("), cleanup)
        self.assertLess(cleanup, initialize.index("database.open(databaseFileName, true)"))
        body = method(self.parent, "cleanupTesterWarmupReservations")
        self.assertLess(body.index("if (!MQLInfoInteger(MQL_TESTER))"), body.index("database.open()"))
        self.assertLess(body.index('"BEGIN IMMEDIATE"'), body.index("string sql ="))
        self.assertIn('H1EaSql::execute(handle, "ROLLBACK")', body)
        self.assertIn('if (success && H1EaSql::execute(handle, "COMMIT"))', body)


if __name__ == "__main__":
    unittest.main()
