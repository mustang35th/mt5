"""Exercise Recorder boundaries and its actual final-audit SQL without MT5.

Wiring checks are static. Predicate checks evaluate the production expressions;
the SQL fixture exercises SQLite. Neither substitutes for an MT5 backtest.
"""

from pathlib import Path
import json
import math
import re
import sqlite3
import unittest

from test_h1_ea_tester_warmup_contract import code_only, method


ROOT = Path(__file__).resolve().parents[3]
RECORDER = ROOT / "Include/MstngH1Ea/Analysis/H1EaResultRecorder.mqh"
EXPERT = ROOT / "Experts/MstngH1EaAll.mq5"


def condition(source, starts_with):
    start = source.index(starts_with)
    opening = source.rfind("if (", 0, start) + 3
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "(") - (source[end] == ")")
        end += 1
    return source[opening + 1:end - 1]


def evaluate(expression, **values):
    expression = expression.replace("this.", "").replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", "not ", expression)
    return bool(eval("(" + expression + ")", {"__builtins__": {}}, values))


def final_audit_sql(source, session, variable="sql"):
    body = method(source, "isFinalAuditComplete")
    expression = body.split(f"string {variable} = ", 1)[1].split(";", 1)[0]
    expression = expression.replace("H1EaSql::text(this.sessionUid)", json.dumps("'" + session + "'"))
    literals = re.findall(r'"(?:[^"\\]|\\.)*"', expression)
    residue = re.sub(r'"(?:[^"\\]|\\.)*"', "", expression)
    if residue.replace("+", "").strip():
        raise AssertionError("Unsupported production SQL expression")
    return "".join(json.loads(value) for value in literals)


class ResultRecorderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recorder = RECORDER.read_text(encoding="utf-8-sig")
        cls.expert = EXPERT.read_text(encoding="utf-8-sig")

    def test_csv_flag_does_not_disable_database_recording(self):
        body = method(self.expert, "initializeResultRecorder")
        self.assertNotIn("InpExportBaselineReport", body)
        self.assertLess(body.index("!MQLInfoInteger(MQL_TESTER)"), body.index("getRestorationState"))
        self.assertIn("resultRecorder.initialize(runs, InpTesterTradeStartTime)", body)
        init = method(self.recorder, "initialize")
        self.assertLess(init.index("!MQLInfoInteger(MQL_TESTER)"), init.index("ensureSession()"))
        self.assertIn("MQLInfoInteger(MQL_OPTIMIZATION)", init)
        self.assertIn("ArraySize(fromRuns) != 28", init)

    def test_sampling_and_finalization_follow_trading_and_child_shutdown(self):
        for event, callback in (("OnTick", "controller.onTick()"), ("OnTimer", "controller.onTimer()"),
                                ("OnTradeTransaction", "controller.onTradeTransaction(")):
            body = method(self.expert, event)
            self.assertLess(body.index(callback), body.index("resultRecorder.sample("))
        close = method(self.expert, "OnDeinit")
        self.assertLess(close.index("controller.shutdown("), close.index("resultRecorder.close("))
        finish = method(self.recorder, "finish")
        self.assertNotIn('"RECORDED"', finish)
        close = method(self.recorder, "close")
        self.assertLess(close.index("isFinalAuditComplete()"), close.index('state = "RECORDED"'))
        self.assertIn('state = "INTERRUPTED"', close)
        self.assertIn('state = "FAILED"', close)

    def test_sample_start_and_same_second_guard_boundaries(self):
        body = method(self.recorder, "sample")
        expression = condition(body, "now < this.tradeStart")
        for now in (99, 100, 101):
            for previous in (0, 100, 101):
                for trade_event in (False, True):
                    for ending in (False, True):
                        with self.subTest(now=now, previous=previous, event=trade_event, end=ending):
                            actual = evaluate(expression, now=now, tradeStart=100,
                                              lastObservedTime=previous, fromTradeEvent=trade_event, fromEnd=ending)
                            self.assertEqual(actual, now < 100 or (not trade_event and not ending and now <= previous))

    def test_minute_boundary_and_end_override(self):
        expression = condition(method(self.recorder, "sample"), "!fromEnd && now < this.lastSavedTime + 60")
        for elapsed, expected in ((0, True), (1, True), (59, True), (60, False), (61, False)):
            self.assertEqual(evaluate(expression, fromEnd=False, now=100 + elapsed, lastSavedTime=100), expected)
            self.assertFalse(evaluate(expression, fromEnd=True, now=100 + elapsed, lastSavedTime=100))

    def test_missing_measurements_are_not_saved_as_zero_or_complete_statistics(self):
        body = method(self.recorder, "isMeasurementValid")
        expression = re.search(r"return\s+(.+?);", body, re.S).group(1)
        empty_value = float.fromhex("0x1.fffffffffffffp+1023")
        for value, expected in ((0.0, True), (-10.5, True), (123.4, True),
                                (float("nan"), False), (float("inf"), False), (empty_value, False)):
            self.assertEqual(evaluate(expression, fromValue=value, EMPTY_VALUE=empty_value,
                                      MathIsValidNumber=math.isfinite), expected)
        for name in ("saveStatistics", "saveDeal", "sample"):
            self.assertIn("this.isMeasurementValid(", method(self.recorder, name))

    def test_initial_account_read_failure_does_not_store_a_false_zero_balance(self):
        body = method(self.recorder, "initialize")
        expression = condition(body, "GetLastError() != 0")
        for error, expected in ((0, False), (4301, True)):
            self.assertEqual(evaluate(expression, GetLastError=lambda: error,
                                      initialBalance=0.0, isMeasurementValid=math.isfinite,
                                      accountCurrency="JPY", accountServer="broker", leverage=100), expected)
        self.assertLess(body.index("ResetLastError()"), body.index("AccountInfoDouble(ACCOUNT_BALANCE)"))
        self.assertLess(body.index("GetLastError() != 0"), body.index("this.active = true"))
        self.assertLess(body.index("this.active = true"), body.index("this.ensureSession()"))

    def test_failed_zero_history_count_cannot_be_marked_complete(self):
        body = method(self.recorder, "saveDeals")
        first_guard = condition(body, "GetLastError() != 0 || total < 0")
        final_guard = re.search(r"bool historyCountValid = (.+?);", body, re.S).group(1)
        for count in (0, 3):
            for error in (0, 4401):
                self.assertEqual(evaluate(first_guard, GetLastError=lambda: error, total=count), error != 0)
                self.assertEqual(evaluate(final_guard, GetLastError=lambda: error,
                                          finalTotal=count, total=count), error == 0)
        self.assertFalse(evaluate(final_guard, GetLastError=lambda: 0, finalTotal=0, total=3))
        self.assertRegex(body, r"ResetLastError\(\);\s*int total = HistoryDealsTotal\(\);")
        self.assertRegex(body, r"ResetLastError\(\);\s*int finalTotal = HistoryDealsTotal\(\);")
        self.assertLess(body.index("historyCountValid = GetLastError()"), body.index("deals_complete=1"))

    def test_identity_and_quantity_changes_bypass_interval(self):
        body = method(self.recorder, "sample")
        self.assertLess(body.index("state != this.positionState"), body.index("now < this.lastSavedTime + 60"))
        self.assertIn("POSITION_IDENTIFIER", body)
        self.assertIn("POSITION_VOLUME", body)
        self.assertIn("ORDER_VOLUME_CURRENT", body)
        self.assertIn("H1EaTextUtil::ticket(ticket)", body)
        identity = method(self.recorder, "addIdentity")
        self.assertIn("StringCompare(fromValues[index - 1], fromValue) > 0", identity)

    def test_failed_recording_never_resumes_as_complete_or_waits_for_lock(self):
        ensure = method(self.recorder, "ensureSession")
        self.assertIn('this.database.open("mstng-h1-ea-tester.sqlite", false, 0)', ensure)
        retry = method(self.recorder, "retryFailureState")
        self.assertIn("this.nextFailureRetryTime = fromNow + 60", retry)
        self.assertNotIn("while", code_only(retry))
        self.assertNotIn("Sleep(", code_only(self.recorder))
        fail = method(self.recorder, "fail")
        self.assertIn("this.failed = true", fail)
        self.assertNotIn("this.failed = false", self.recorder.split("void initialize", 1)[1])

    def test_deal_completion_is_atomic_and_source_ids_remain_text(self):
        deals = method(self.recorder, "saveDeals")
        self.assertLess(deals.index("this.addPositionId("), deals.index('"BEGIN IMMEDIATE"'))
        self.assertIn("!this.owns(symbol, magic) && !this.containsPositionId(positionIds, identifier)", deals)
        self.assertLess(deals.index("this.saveDeal("), deals.index("deals_complete=1"))
        self.assertLess(deals.index('"COMMIT"'), deals.index("this.dealsComplete = true"))
        self.assertIn('"ROLLBACK"', deals)
        self.assertIn("GetLastError() == 0 && finalTotal == total", deals)
        self.assertIn("success = success && historyCountValid", deals)
        self.assertIn("storedDeals == savedDeals", deals)
        save = method(self.recorder, "saveDeal")
        for field in ("fromTicket", "fromIdentifier", "fromMagic"):
            self.assertIn(f"H1EaSql::text(H1EaTextUtil::ticket({field}))", save)
        for forbidden in ("OrderSend(", "OrderSendAsync(", "PositionClose(", "EventSetTimer("):
            self.assertNotIn(forbidden, code_only(self.recorder))

    def test_terminal_run_audit_requires_all_28_cleanly_stopped(self):
        body = method(self.recorder, "isFinalAuditComplete")
        self.assertIn("total != 28", body)
        self.assertIn("stopped != 28", body)
        self.assertIn("status='STOPPED' AND ended_at IS NOT NULL", body)
        self.assertIn("COALESCE(error_text,'')=''", body)
        self.assertIn('" AND id IN (" + this.runIds', body)

    def test_real_deal_audit_sql_requires_matching_session_ticket_and_position(self):
        database = sqlite3.connect(":memory:")
        self.addCleanup(database.close)
        database.executescript("""
            CREATE TABLE h1_ea_runs(id INTEGER, session_uid TEXT);
            CREATE TABLE h1_ea_trades(id INTEGER, created_run_id INTEGER);
            CREATE TABLE h1_ea_trade_events(trade_id INTEGER,event_type TEXT,deal_ticket TEXT,position_identifier TEXT);
            CREATE TABLE h1_ea_deals(session_uid TEXT,ticket TEXT,position_identifier TEXT,deal_type INTEGER);
            INSERT INTO h1_ea_runs VALUES(1,'session'),(2,'foreign');
            INSERT INTO h1_ea_trades VALUES(10,1),(20,2);
            INSERT INTO h1_ea_deals VALUES('session','18446744073709551615','100',0);
        """)
        query = final_audit_sql(self.recorder, "session")
        self.assertEqual(database.execute(query).fetchone()[0], 1)
        invalid = ((20, "DEAL_ADD", "18446744073709551615", "100"),
                   (10, "ENTRY_RESULT", "18446744073709551615", "100"),
                   (10, "DEAL_ADD", "wrong-ticket", "100"),
                   (10, "DEAL_ADD", "18446744073709551615", "wrong-position"))
        for row in invalid:
            database.execute("DELETE FROM h1_ea_trade_events")
            database.execute("INSERT INTO h1_ea_trade_events VALUES(?,?,?,?)", row)
            self.assertEqual(database.execute(query).fetchone()[0], 1, row)
        database.execute("INSERT INTO h1_ea_trade_events VALUES(10,'DEAL_ADD','18446744073709551615','100')")
        self.assertEqual(database.execute(query).fetchone()[0], 0)
        database.execute("INSERT INTO h1_ea_deals VALUES('session','200','100',1)")
        self.assertEqual(database.execute(query).fetchone()[0], 1)
        database.execute("INSERT INTO h1_ea_trade_events VALUES(10,'DEAL_ADD','200','100')")
        self.assertEqual(database.execute(query).fetchone()[0], 0)
        database.execute("INSERT INTO h1_ea_deals VALUES('session','300','0',7)")
        self.assertEqual(database.execute(query).fetchone()[0], 0)

    def test_reverse_audit_detects_empty_or_partial_saved_deals(self):
        database = sqlite3.connect(":memory:")
        self.addCleanup(database.close)
        database.executescript("""
            CREATE TABLE h1_ea_runs(id INTEGER, session_uid TEXT);
            CREATE TABLE h1_ea_trades(id INTEGER, created_run_id INTEGER);
            CREATE TABLE h1_ea_trade_events(trade_id INTEGER,event_type TEXT,deal_ticket TEXT,position_identifier TEXT);
            CREATE TABLE h1_ea_deals(session_uid TEXT,ticket TEXT,position_identifier TEXT,deal_type INTEGER);
            INSERT INTO h1_ea_runs VALUES(1,'session'),(2,'foreign');
            INSERT INTO h1_ea_trades VALUES(10,1),(20,2);
            INSERT INTO h1_ea_trade_events VALUES(10,'DEAL_ADD','18446744073709551615','100');
            INSERT INTO h1_ea_trade_events VALUES(10,'DEAL_ADD','200','100');
            INSERT INTO h1_ea_trade_events VALUES(10,'TRAIL_EVALUATION',NULL,'100');
            INSERT INTO h1_ea_trade_events VALUES(20,'DEAL_ADD','300','300');
        """)
        forward = final_audit_sql(self.recorder, "session")
        reverse = final_audit_sql(self.recorder, "session", "reverseSql")
        self.assertEqual(database.execute(forward).fetchone()[0], 0)
        self.assertEqual(database.execute(reverse).fetchone()[0], 2)
        database.execute("INSERT INTO h1_ea_deals VALUES('session','18446744073709551615','100',0)")
        self.assertEqual(database.execute(reverse).fetchone()[0], 1)
        database.execute("INSERT INTO h1_ea_deals VALUES('session','200','wrong-position',1)")
        self.assertEqual(database.execute(reverse).fetchone()[0], 1)
        database.execute("UPDATE h1_ea_deals SET position_identifier='100' WHERE ticket='200'")
        self.assertEqual(database.execute(reverse).fetchone()[0], 0)
        database.execute("UPDATE h1_ea_deals SET deal_type=7 WHERE ticket='200'")
        self.assertEqual(database.execute(reverse).fetchone()[0], 1)
        body = method(self.recorder, "isFinalAuditComplete")
        self.assertLess(body.index("if (!this.onTesterReached)"), body.index("string reverseSql"))


if __name__ == "__main__":
    unittest.main()
