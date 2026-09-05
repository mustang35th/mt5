"""Deal-audit database constraints and MQL source wiring, without broker orders.

SQLite tests execute the production DAO CREATE statements in memory. They do
not execute the MQL PersistenceService or TradeExecutor. Source-wiring tests
are explicitly static; fake-history reader behavior belongs to the separate
H1EaDealHistorySmokeTest.mq5 script. Compiling that script is not running it.

Run: python -B -m unittest discover -s Scripts/Mstng/ExpertAdvisor
     -p test_h1_ea_deal_audit_contract.py -v
"""

import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[3]


def load_test_helpers(name, path):
    """Reuse existing schema fixtures/parsing without rerunning their suites."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DATABASE_CONTRACT = load_test_helpers(
    "h1_deal_audit_database_helpers",
    ROOT / "Scripts/Mstng/Database/test_h1_ea_database_contract.py",
)
WIRING = load_test_helpers(
    "h1_deal_audit_wiring_helpers",
    ROOT / "Scripts/Mstng/ExpertAdvisor/test_h1_ea_tester_warmup_contract.py",
)
HISTORY = ROOT / "Include/MstngH1Ea/Trade/H1EaDealHistory.mqh"
EXECUTOR = ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh"
SMOKE = ROOT / "Scripts/Mstng/ExpertAdvisor/H1EaDealHistorySmokeTest.mq5"
PERSISTENCE = ROOT / "Include/Mstng/Database/Service/H1EaPersistenceService.mqh"
CONTROLLER = ROOT / "Include/MstngH1Ea/H1EaController.mqh"


def audit_where(full_audit, context, after_id):
    """Extract the service's real WHERE expressions; bind its two scalar inputs.

    This executes the extracted predicate in SQLite, not the MQL service.
    Unsupported concatenation syntax fails instead of falling back to a
    separately maintained Python copy of the SQL predicate.
    """
    source = PERSISTENCE.read_text(encoding="utf-8-sig")
    body = WIRING.method(source, "loadClosedTradeForDealAudit")
    masked = WIRING.code_only(body)
    condition = re.search(r"if\s*\(!fromFullAudit\)\s*\{", masked)
    if condition is None:
        raise AssertionError("Missing explicit normal-audit filter branch")
    condition_end = WIRING.block_end(masked, condition.end() - 1)
    initial = re.search(r"string\s+where\s*=\s*(.*?);", body[:condition.start()], re.DOTALL)
    if initial is None:
        raise AssertionError("Missing initial audit WHERE expression")
    expressions = [initial.group(1)]
    if not full_audit:
        expressions.extend(re.findall(
            r"where\s*\+=\s*(.*?);", body[condition.end():condition_end], re.DOTALL,
        ))
    expressions.extend(re.findall(r"where\s*\+=\s*(.*?);", body[condition_end + 1:], re.DOTALL))
    token = re.compile(
        r'"(?:[^"\\]|\\.)*"|H1EaSql::text\(fromContext\)|IntegerToString\(fromAfterId\)'
    )
    parts = []
    parameters = []
    for expression in expressions:
        residual = token.sub("", expression)
        if re.sub(r"[\s+]", "", residual):
            raise AssertionError(f"Unsupported MQL SQL expression: {expression}")
        for match in token.finditer(expression):
            value = match.group()
            if value.startswith('"'):
                parts.append(json.loads(value))
            else:
                parts.append("?")
                if value == "H1EaSql::text(fromContext)":
                    parameters.append(context)
                else:
                    parameters.append(after_id)
    return "".join(parts), parameters


class DealAuditSchemaContractTests(unittest.TestCase):
    """Real SQLite constraints only: not a Python rewrite of the MQL service."""

    def setUp(self):
        self.fixture = DATABASE_CONTRACT.DatabaseContractTest("test_exact_columns")
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.db = self.fixture.db
        self.trade = self.fixture.insert(
            "trades",
            self.fixture.trade_values(
                status="CLOSED", position_identifier="7000000001", position_ticket="8000000001",
                opened_at_msc=1000, closed_at_msc=2000, opened_volume=0.01,
                remaining_position_volume=0, open_price=1.25, close_price=1.26,
                close_reason="H1_ZIGZAG_TRAIL", broker_close_reason="SL",
                profit=10, commission=-0.2, swap=-0.1, fee=-0.05,
            ),
        )

    def deal_values(self, **changes):
        scope = "TESTER|test-run|9000000002"
        return self.fixture.event_values(
            self.trade, event_uid=scope, event_type="DEAL_ADD", event_source="CALLBACK",
            deal_ticket="9000000002", deal_scope_key=scope, order_ticket="8000000002",
            position_identifier="7000000001", broker_time_msc=2000, side="SELL",
            volume=0.01, price=1.26, broker_reason="SL", close_reason="H1_ZIGZAG_TRAIL",
            message="DEAL_ENTRY_OUT",
        ) | changes

    def stored_trade(self):
        return self.db.execute("SELECT * FROM h1_ea_trades WHERE id=?", (self.trade,)).fetchone()

    def clone_trade(self, **changes):
        row = self.db.execute("SELECT * FROM h1_ea_trades WHERE id=?", (self.trade,))
        values = dict(zip((column[0] for column in row.description), row.fetchone()))
        values.pop("id")
        # Distinct recovered fixtures avoid inventing additional consumed Entry decisions.
        next_id = self.db.execute("SELECT COALESCE(MAX(id),0)+1 FROM h1_ea_trades").fetchone()[0]
        values.update(
            origin="RECOVERED", decision_id=None,
            position_identifier=str(7000000000 + next_id),
            position_ticket=str(8000000000 + next_id),
        )
        values.update(changes)
        return self.fixture.insert("trades", values)

    def audit_ids(self, full_audit, context="ctx", after_id=0):
        where, parameters = audit_where(full_audit, context, after_id)
        return [row[0] for row in self.db.execute(
            "SELECT id FROM h1_ea_trades WHERE " + where, parameters,
        )]

    def add_endpoint_events(self):
        self.db.execute(
            "UPDATE h1_ea_trades SET entry_deal_ticket='entry',exit_deal_ticket='exit' WHERE id=?",
            (self.trade,),
        )
        for sequence, ticket in enumerate(("entry", "exit"), start=1):
            scope = "TESTER|test-run|" + ticket
            self.fixture.insert("trade_events", self.deal_values(
                event_uid=scope, deal_scope_key=scope, deal_ticket=ticket, sequence=sequence,
            ))

    def test_late_exit_append_preserves_every_closed_trade_column(self):
        before = self.stored_trade()
        event = self.fixture.insert("trade_events", self.deal_values())
        self.assertGreater(event, 0)
        self.assertEqual(self.stored_trade(), before)
        self.assertEqual(
            self.db.execute(
                "SELECT deal_ticket,side,broker_reason,message FROM h1_ea_trade_events"
            ).fetchone(),
            ("9000000002", "SELL", "SL", "DEAL_ENTRY_OUT"),
        )

    def test_callback_and_reconciliation_cannot_duplicate_same_deal(self):
        values = self.deal_values()
        self.fixture.insert("trade_events", values)
        with self.assertRaises(sqlite3.IntegrityError):
            self.fixture.insert("trade_events", values | dict(sequence=2, event_source="RECONCILIATION"))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trade_events").fetchone()[0], 1)

    def test_same_deal_scope_is_unique_even_with_different_event_uid(self):
        self.fixture.insert("trade_events", self.deal_values())
        with self.assertRaises(sqlite3.IntegrityError):
            self.fixture.insert("trade_events", self.deal_values(event_uid="other", sequence=2))

    def test_same_ticket_in_a_different_tester_scope_is_not_a_duplicate(self):
        self.fixture.insert("trade_events", self.deal_values())
        second_scope = "TESTER|different-run|9000000002"
        self.fixture.insert("trade_events", self.deal_values(
            event_uid=second_scope, deal_scope_key=second_scope, sequence=2,
        ))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trade_events").fetchone()[0], 2)

    def test_invalid_late_event_does_not_change_closed_trade(self):
        before = self.stored_trade()
        for field, invalid in (
            ("deal_ticket", None), ("deal_scope_key", None), ("broker_time_msc", 0),
            ("position_identifier", None), ("side", None), ("broker_reason", None),
        ):
            with self.subTest(field=field), self.assertRaises(sqlite3.IntegrityError):
                self.fixture.insert("trade_events", self.deal_values(**{field: invalid}))
            self.assertEqual(self.stored_trade(), before)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trade_events").fetchone()[0], 0)

    def test_failed_deal_append_rolls_back_and_same_identity_can_retry(self):
        before = self.stored_trade()
        # Failure injection is confined to this in-memory schema, not an operational DB.
        self.db.execute(
            "CREATE TEMP TRIGGER fail_deal_insert BEFORE INSERT ON h1_ea_trade_events "
            "WHEN NEW.event_type='DEAL_ADD' BEGIN SELECT RAISE(ABORT,'SMOKE_SAVE_FAILED'); END"
        )
        self.db.execute("BEGIN IMMEDIATE")
        with self.assertRaisesRegex(sqlite3.IntegrityError, "SMOKE_SAVE_FAILED"):
            self.fixture.insert("trade_events", self.deal_values())
        self.db.execute("ROLLBACK")
        self.assertEqual(self.stored_trade(), before)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trade_events").fetchone()[0], 0)
        self.db.execute("DROP TRIGGER fail_deal_insert")
        self.db.execute("BEGIN IMMEDIATE")
        self.fixture.insert("trade_events", self.deal_values())
        self.db.execute("COMMIT")
        self.assertEqual(self.stored_trade(), before)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM h1_ea_trade_events").fetchone()[0], 1)

    def test_executor_pending_marker_shape_satisfies_real_event_schema(self):
        # Only literal marker metadata is extracted; this does not run the Executor.
        source = EXECUTOR.read_text(encoding="utf-8-sig")
        body = WIRING.method(source, "aggregateDeals")
        self.assertIn('this.newEvent("RECOVERY", pendingEvent);', body)
        values = self.fixture.event_values(self.trade, message="DEAL_EVENTS_PENDING")
        for member, column in (
            ("message", "message"), ("recoveryIssueCode", "recovery_issue_code"),
            ("quarantinedPendingText", "quarantined_pending_text"),
        ):
            assignment = re.search(rf'pendingEvent\.{member}\s*=\s*"([^"\\]*)"\s*;', body)
            if assignment:
                values[column] = assignment.group(1)
        self.assertGreater(self.fixture.insert("trade_events", values), 0)

    def test_full_audit_includes_missing_middle_deal_when_endpoints_exist(self):
        self.add_endpoint_events()
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM h1_ea_trade_events WHERE deal_ticket='missing-middle'"
        ).fetchone()[0], 0)
        self.assertEqual(self.audit_ids(False), [])
        self.assertEqual(self.audit_ids(True), [self.trade])

    def test_normal_filter_selects_pending_marker_and_missing_endpoint_only(self):
        self.add_endpoint_events()
        marked = self.clone_trade(entry_deal_ticket=None, exit_deal_ticket=None,
                                  last_error="DEAL_EVENTS_PENDING")
        missing_entry = self.clone_trade(entry_deal_ticket="missing-entry", exit_deal_ticket=None)
        missing_exit = self.clone_trade(entry_deal_ticket=None, exit_deal_ticket="missing-exit")
        unknown_endpoints = self.clone_trade(entry_deal_ticket=None, exit_deal_ticket=None)
        self.assertEqual(self.audit_ids(False), [marked, missing_entry, missing_exit])
        self.assertEqual(self.audit_ids(True), [self.trade, marked, missing_entry, missing_exit, unknown_endpoints])

    def test_actual_audit_where_respects_context_closed_state_and_cursor(self):
        self.db.execute("UPDATE h1_ea_trades SET last_error='DEAL_EVENTS_PENDING' WHERE id=?", (self.trade,))
        second = self.clone_trade()
        foreign = self.clone_trade(context_key="other-context")
        third = self.clone_trade()
        self.clone_trade(status="OPEN")
        for full in (False, True):
            with self.subTest(full=full):
                self.assertEqual(self.audit_ids(full), [self.trade, second, third])
                self.assertEqual(self.audit_ids(full, after_id=self.trade), [second, third])
                self.assertEqual(self.audit_ids(full, after_id=second), [third])
                self.assertEqual(self.audit_ids(full, after_id=third), [])
                self.assertEqual(self.audit_ids(full, context="other-context"), [foreign])
                self.assertEqual(self.audit_ids(full, context="absent-context"), [])


class DealHistoryStaticWiringTests(unittest.TestCase):
    """Source contracts complement the separately compiled fake-history smoke."""

    @classmethod
    def setUpClass(cls):
        cls.history = HISTORY.read_text(encoding="utf-8-sig")
        cls.executor = EXECUTOR.read_text(encoding="utf-8-sig")
        cls.smoke = SMOKE.read_text(encoding="utf-8-sig")
        cls.persistence = PERSISTENCE.read_text(encoding="utf-8-sig")
        cls.controller = CONTROLLER.read_text(encoding="utf-8-sig")

    def test_reader_selects_deal_and_checks_bool_getters_before_publishing(self):
        body = WIRING.code_only(WIRING.method(self.history, "read"))
        self.assertLess(body.index("fromDeal.reset();"), body.index("HistoryDealSelect("))
        self.assertRegex(body, r"if\s*\(!HistoryDealSelect\(fromTicket\)\)")
        for getter in ("readInteger", "readDouble"):
            helper = WIRING.code_only(WIRING.method(self.history, getter))
            native = "HistoryDealGetInteger" if getter == "readInteger" else "HistoryDealGetDouble"
            self.assertRegex(helper, rf"if\s*\(!{native}\(fromTicket,\s*fromProperty,\s*fromValue\)\)")
            self.assertIn("return H1EaDealHistory::fail(", helper)
        self.assertRegex(body, r"if\s*\(!HistoryDealGetString\(fromTicket,\s*DEAL_SYMBOL,\s*candidate.symbol\)\)")
        self.assertGreater(body.index("fromDeal = candidate;"), body.index("candidate.ticket != fromTicket"))
        self.assertGreater(body.index("fromDeal = candidate;"), body.index("candidate.timeMsc <= 0"))

    def test_position_reader_captures_all_tickets_before_single_deal_selection(self):
        body = WIRING.code_only(WIRING.method(self.history, "readPosition"))
        self.assertLess(body.index("ArrayResize(fromDeals, 0);"), body.index("HistorySelectByPosition("))
        capture = re.search(r"for\s*\(int i = 0; i < total; i\+\+\)\s*\{", body)
        self.assertIsNotNone(capture)
        capture_end = WIRING.block_end(body, capture.end() - 1)
        loop = body[capture.end():capture_end]
        self.assertIn("tickets[i] = HistoryDealGetTicket(i);", loop)
        self.assertIn("tickets[i] == 0", loop)
        self.assertNotIn("H1EaDealHistory::read(", loop)
        self.assertGreater(body.index("H1EaDealHistory::read(tickets[i],"), capture_end)
        publish = body.index("fromDeals[i] = candidates[i];")
        self.assertGreater(publish, body.index("candidates[i].positionIdentifier != fromIdentifier"))
        self.assertGreater(publish, body.index("candidates[i].symbol != fromSymbol"))

    def test_history_reader_has_no_order_database_or_trade_state_mutation(self):
        body = WIRING.code_only(self.history)
        for forbidden in ("OrderSend", "Database", "PositionClose", "saveTradeEvent", "this.trade", "this.active"):
            self.assertNotIn(forbidden, body)

    def test_smoke_replaces_only_reader_history_api_and_never_includes_executor(self):
        include = self.smoke.index("#include <MstngH1Ea\\Trade\\H1EaDealHistory.mqh>")
        names = (
            "HistorySelectByPosition", "HistoryDealsTotal", "HistoryDealGetTicket", "HistoryDealSelect",
            "HistoryDealGetInteger", "HistoryDealGetString", "HistoryDealGetDouble",
        )
        for name in names:
            self.assertLess(self.smoke.index(f"#define {name} fake{name}"), include)
            self.assertGreater(self.smoke.index(f"#undef {name}"), include)
        body = WIRING.code_only(self.smoke)
        for forbidden in ("OrderSend(", "DatabaseOpen(", "PositionClose(", "H1EaTradeExecutor"):
            self.assertNotIn(forbidden, body)
        self.assertEqual(len(re.findall(r"(?m)^#include\s", self.smoke)), 1)

    def test_event_builder_uses_snapshot_only_and_supplied_trade_identity(self):
        body = WIRING.code_only(WIRING.method(self.executor, "buildDealEvent"))
        for forbidden in ("HistoryDeal", "HistorySelect", "HistoryOrder", "this.trade"):
            self.assertNotIn(forbidden, body)
        for expected in (
            "fromTrade.contextKey != this.contextKey", "fromDeal.symbol != this.symbolName",
            "fromDeal.positionIdentifier", "fromTrade.positionIdentifier", "fromDeal.ticket",
            "fromDeal.timeMsc", "fromDeal.orderTicket", "fromDeal.price", "fromDeal.volume",
            "fromDeal.reason", "fromTrade.stopLossSource", "fromTrade.exitIntentReason",
        ):
            self.assertIn(expected, body)
        record = WIRING.code_only(WIRING.method(self.executor, "recordDeal"))
        self.assertIn("this.buildDealEvent(this.trade, fromDeal, fromSource, event)", record)
        self.assertIn("return this.saveEvent(event, false);", record)
        self.assertRegex(record, r"if\s*\(!this.buildDealEvent\([^;]+\)\)\s*\{[^{}]*return false;")

    def test_aggregation_cannot_use_partial_history_or_selection_dependent_getters(self):
        body = WIRING.code_only(WIRING.method(self.executor, "aggregateDeals"))
        guard = re.search(r"if\s*\(!H1EaDealHistory::readPosition\([^;{}]+\)\)\s*\{", body)
        self.assertIsNotNone(guard)
        end = WIRING.block_end(body, guard.end() - 1)
        branch = body[guard.end():end]
        self.assertIn("this.dealHistoryPending = true;", branch)
        self.assertIn("return false;", branch)
        for operation in ("profit += deals[i].profit;", "this.trade.openPrice =", "this.recordDeal("):
            self.assertGreater(body.index(operation), end)
        for forbidden in ("HistoryDealGet", "HistoryDealSelect", "HistorySelectByPosition"):
            self.assertNotIn(forbidden, body)

    def test_closed_marker_precedes_deal_saves_and_failure_reopens_audit(self):
        raw = WIRING.method(self.executor, "aggregateDeals")
        body = WIRING.code_only(raw)
        marker = raw.index('this.trade.lastError = "DEAL_EVENTS_PENDING";')
        save_marker = body.index("dealsAccepted = this.saveEvent(pendingEvent, false);")
        record = body.index("this.recordDeal(deals[i],")
        self.assertLess(marker, save_marker)
        self.assertLess(save_marker, record)
        self.assertRegex(body, r"if\s*\(!dealsAccepted\s*\|\|\s*!this.recordDeal\([^;]+\)\)\s*\{\s*dealsAccepted = false;\s*break;")
        self.assertGreater(body.index("this.dealHistoryPending = !dealsAccepted;"), record)
        tail = body[body.index("this.dealHistoryPending = !dealsAccepted;"):]
        retry = re.search(r"else\s*\{\s*this.closedDealAuditChecked = false;", tail)
        self.assertIsNotNone(retry)
        self.assertIn("this.closedDealAuditAfterId = 0;", tail[retry.start():])
        self.assertIn("this.nextClosedDealAuditTick = 0;", tail[retry.start():])

    def test_closed_audit_advances_only_after_complete_history_and_every_append(self):
        body = WIRING.code_only(WIRING.method(self.executor, "reconcileClosedDealAudit"))
        publish = body.index("this.closedDealAuditAfterId = closedTrade.id;")
        for condition in (
            "!this.persistence.loadClosedTradeForDealAudit(", "!H1EaDealHistory::readPosition(",
            "!this.closedDealHistoryComplete(closedTrade, deals)",
            "!this.persistence.appendClosedDealEvent(this.runId, closedTrade.id, event)",
            "!this.persistence.completeClosedDealAudit(this.runId, closedTrade.id)",
        ):
            offset = body.index(condition)
            self.assertLess(offset, publish)
            opening = body.index("{", offset)
            ending = WIRING.block_end(body, opening)
            self.assertIn("return;", body[opening:ending])
            self.assertLess(ending, publish)
        self.assertNotRegex(body, r"this\.trade\s*=")
        self.assertNotIn("this.saveEvent(", body)
        self.assertNotIn("OrderSend(", body)

    def test_restart_full_audit_is_disabled_only_after_reaching_the_end(self):
        constructor = WIRING.code_only(WIRING.method(self.executor, "H1EaTradeExecutor"))
        self.assertIn("this.closedDealAuditFull = true;", constructor)
        self.assertIn("this.closedDealAuditChecked = false;", constructor)
        body = WIRING.code_only(WIRING.method(self.executor, "reconcileClosedDealAudit"))
        self.assertRegex(body,
            r"this.persistence.loadClosedTradeForDealAudit\(this.contextKey,\s*"
            r"this.closedDealAuditAfterId, closedTrade, found, this.closedDealAuditFull\)")
        exhausted = re.search(r"if\s*\(!found\)\s*\{", body)
        self.assertIsNotNone(exhausted)
        end = WIRING.block_end(body, exhausted.end() - 1)
        branch = body[exhausted.end():end]
        self.assertIn("this.closedDealAuditChecked = true;", branch)
        self.assertIn("this.closedDealAuditFull = false;", branch)
        self.assertIn("return;", branch)
        self.assertEqual(body.count("this.closedDealAuditFull = false;"), 1)
        service_signature = re.search(
            r"bool loadClosedTradeForDealAudit\([^{};]+\)", self.persistence,
        )
        self.assertIsNotNone(service_signature)
        self.assertIn("const bool fromFullAudit = false", service_signature.group())

    def test_restart_active_trade_also_forces_full_deal_reaggregation(self):
        body = WIRING.code_only(WIRING.method(self.executor, "reconcile"))
        initial = re.search(r"if\s*\(!this.loaded\)\s*\{", body)
        self.assertIsNotNone(initial)
        end = WIRING.block_end(body, initial.end() - 1)
        branch = body[initial.end():end]
        loaded = branch.index("this.loaded = true;")
        pending = branch.index("this.dealHistoryPending = this.active;")
        self.assertLess(branch.index("this.persistence.loadActiveTrade("), loaded)
        self.assertLess(loaded, pending)
        self.assertRegex(body, r"bool needsDealRecovery\s*=[^;]+\|\| this.dealHistoryPending;")
        self.assertRegex(body, r"if\s*\(needsDealRecovery\)\s*\{\s*this.aggregateDeals\(false\);")

    def test_closed_completeness_requires_both_saved_tickets_and_balanced_volumes(self):
        body = WIRING.code_only(WIRING.method(self.executor, "closedDealHistoryComplete"))
        for expected in (
            "ticket == fromTrade.entryDealTicket", "ticket == fromTrade.exitDealTicket",
            "return entryFound && exitFound && entryVolume > 0.0",
            "MathAbs(entryVolume - exitVolume)", "MathAbs(entryVolume - fromTrade.openedVolume)",
        ):
            self.assertIn(expected, body)

    def test_late_callback_enqueues_audit_without_requiring_an_active_trade(self):
        body = WIRING.code_only(WIRING.method(self.executor, "onTradeTransaction"))
        enqueue = body.index("this.enqueueDealAudit(fromTransaction.deal);")
        reconcile_call = body.index("this.reconcile();")
        self.assertLess(enqueue, reconcile_call)
        for expected in (
            "this.closedDealAuditChecked = false;", "this.closedDealAuditAfterId = 0;",
            "this.nextClosedDealAuditTick = 0;",
        ):
            self.assertLess(body.index(expected), reconcile_call)
        branch = re.search(r"if\s*\(dealAdded\)\s*\{", body)
        self.assertIsNotNone(branch)
        branch_end = WIRING.block_end(body, branch.end() - 1)
        self.assertLess(branch.start(), enqueue)
        self.assertLess(enqueue, branch_end)
        self.assertNotIn("this.active", body[body.index("bool dealAdded"):])
        self.assertNotIn("return;", body[branch_end:])
        reconcile = WIRING.code_only(WIRING.method(self.executor, "reconcile"))
        self.assertLess(reconcile.index("this.reconcileClosedDealAudit();"), reconcile.index("if (!this.active)"))
        self.assertLess(reconcile.index("this.reconcilePendingDealTickets();"), reconcile.index("if (!this.active)"))

    def test_pending_history_and_unchecked_audit_stop_entry_and_fast_idle(self):
        unsaved = WIRING.code_only(WIRING.method(self.executor, "hasUnsavedEvents"))
        self.assertIn("this.hasPendingDealAudit()", unsaved)
        pending = WIRING.code_only(WIRING.method(self.executor, "hasPendingDealAudit"))
        self.assertIn("return this.initialized &&", pending)
        for name in ("hasPendingDealAudit", "isIdleForTesterWarmup"):
            with self.subTest(method=name):
                body = WIRING.code_only(WIRING.method(self.executor, name))
                self.assertIn("this.dealHistoryPending", body)
                self.assertIn("!this.closedDealAuditChecked", body)
                self.assertIn("ArraySize(this.pendingDealTickets) > 0", body)
        entry = WIRING.code_only(WIRING.method(self.executor, "canEnter"))
        self.assertIn("this.hasUnsavedEvents()", entry)

    def test_callback_ticket_queue_is_bounded_and_duplicate_notifications_are_ignored(self):
        body = WIRING.code_only(WIRING.method(self.executor, "enqueueDealAudit"))
        duplicate = re.search(r"if\s*\(this.pendingDealTickets\[i\] == fromTicket\)\s*\{\s*return;", body)
        self.assertIsNotNone(duplicate)
        resize = body.index("ArrayResize(this.pendingDealTickets, size + 1)")
        self.assertLess(duplicate.end(), resize)
        self.assertIn("size >= 256 ||", body)
        overflow = body.index("this.queueOverflow = true;")
        publish = body.index("this.pendingDealTickets[size] = fromTicket;")
        self.assertLess(overflow, publish)
        self.assertIn("return;", body[overflow:publish])

    def test_pending_ticket_is_retained_on_read_query_or_append_failure(self):
        body = WIRING.code_only(WIRING.method(self.executor, "reconcilePendingDealTickets"))
        self.assertIn("H1EaClock::milliseconds() < this.nextPendingDealAuditTick", body)
        self.assertIn("this.nextPendingDealAuditTick = H1EaClock::milliseconds() + 1000;", body)
        remove = body.index("ArrayResize(this.pendingDealTickets, size - 1);")
        for condition in (
            "!H1EaDealHistory::read(this.pendingDealTickets[0], deal, failure)",
            "!this.persistence.loadClosedTradeByPosition(this.contextKey, identifier, closedTrade, found)",
            "!this.persistence.appendClosedDealEvent(this.runId, closedTrade.id, event)",
        ):
            offset = body.index(condition)
            opening = body.index("{", offset)
            ending = WIRING.block_end(body, opening)
            self.assertIn("return;", body[opening:ending])
            self.assertLess(ending, remove)
        self.assertIn("deal.symbol == this.symbolName", body)
        self.assertIn("this.buildDealEvent(closedTrade, deal,", body)
        self.assertNotRegex(body, r"this\.trade\s*=")
        self.assertNotIn("this.saveEvent(", body)
        self.assertNotIn("OrderSend(", body)
        self.assertRegex(body, r"else if\s*\(this.active && identifier == this.trade.positionIdentifier\)\s*\{\s*this.dealHistoryPending = true;")

    def test_closed_lookup_and_append_are_scoped_to_position_context_and_owner(self):
        raw = WIRING.method(self.persistence, "loadClosedTradeByPosition")
        self.assertIn('"context_key=" + H1EaSql::text(fromContext)', raw)
        self.assertIn("status='CLOSED'", raw)
        self.assertIn('" AND position_identifier=" + H1EaSql::text(fromPositionIdentifier)', raw)
        begin = WIRING.method(self.persistence, "beginClosedDealAudit")
        self.assertIn("this.beginOwned(fromRunId, false, fromRun.contextKey)", begin)
        self.assertIn("fromTrade.contextKey != fromRun.contextKey", begin)
        self.assertIn('fromTrade.status != "CLOSED"', begin)

    def test_audit_detected_ownership_loss_latches_broker_authority_off(self):
        raw = WIRING.method(self.executor, "logDealHistoryFailure")
        for reason in ("SNAPSHOT_OWNER_SUPERSEDED", "RUN_SCOPE_OR_LEASE_LOST", "LEASE_NOT_OWNED"):
            self.assertIn(f'StringFind(fromFailure, "{reason}") >= 0', raw)
        body = WIRING.code_only(raw)
        self.assertIn("this.ownershipLost = true;", body)
        self.assertIn("this.knownLeaseExpires = 0;", body)
        authority = WIRING.code_only(WIRING.method(self.executor, "hasManagementAuthority"))
        self.assertIn("!this.ownershipLost", authority)
        refresh = WIRING.code_only(WIRING.method(self.executor, "setManagementAuthority"))
        self.assertNotRegex(refresh, r"this\.ownershipLost\s*=")

    def test_shutdown_records_failed_run_if_audit_remains_after_final_reconciliation(self):
        raw = WIRING.method(self.controller, "shutdown")
        body = WIRING.code_only(raw)
        gate = body.index("this.executor.hasPendingDealAudit()")
        self.assertLess(body.index("this.executor.reconcile();"), gate)
        opening = body.index("{", gate)
        ending = WIRING.block_end(body, opening)
        self.assertIn('status = "FAILED";', raw[opening:ending])
        self.assertIn("DEAL_AUDIT_PENDING", raw[opening:ending])
        self.assertLess(ending, body.index("this.persistence.finishRun("))

    def test_closed_append_uses_event_insert_without_trade_snapshot_update(self):
        body = WIRING.code_only(WIRING.method(self.persistence, "appendClosedDealEvent"))
        self.assertIn("this.beginClosedDealAudit(fromRunId, fromTradeId, run, trade)", body)
        self.assertIn("fromEvent.positionIdentifier != trade.positionIdentifier", body)
        self.assertIn("fromEvent.dealScopeKey != scope || fromEvent.eventUid != scope", body)
        self.assertIn("existing.tradeId == fromTradeId", body)
        self.assertIn("event = existing;", body)
        self.assertIn("success = this.insertEvent(event);", body)
        for forbidden in ("H1EaTradeDao::update", "saveTradeEvent(", "UPDATE h1_ea_trades"):
            self.assertNotIn(forbidden, body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
