"""Stage-six source contracts. These do not run MT5 or send orders."""

from pathlib import Path
import unittest

from test_h1_ea_tester_warmup_contract import code_only, method


ROOT = Path(__file__).resolve().parents[3]


class MultiSymbolPreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parent = (ROOT / "Include/MstngH1Ea/H1EaMultiSymbolController.mqh").read_text(encoding="utf-8-sig")
        cls.child = (ROOT / "Include/MstngH1Ea/H1EaController.mqh").read_text(encoding="utf-8-sig")
        cls.expert = (ROOT / "Experts/MstngH1EaAll.mq5").read_text(encoding="utf-8-sig")

    def test_shared_fixed_list_is_validated_before_allocating_children(self):
        body = code_only(method(self.parent, "initialize"))
        self.assertIn("symbols.setAll();", body)
        self.assertIn("symbols.size() != ArraySize(this.controllers)", body)
        self.assertIn("previousSymbol.symbolName == symbol.symbolName", body)
        self.assertLess(body.index("SymbolSelect("), body.index("new H1EaController()"))
        self.assertIn("H1EaController *controllers[28];", self.parent)
        self.assertIn("initializePreparation(symbol.symbolName)", body)
        self.assertNotIn("strategy.initialize", body)

    def test_preparation_registration_never_activates_trading_or_resources(self):
        body = code_only(method(self.child, "initializePreparation"))
        self.assertIn("this.started || this.preparationState.registered", body)
        self.assertIn("this.preparationState.symbolName = fromSymbol;", body)
        for forbidden in ("config.initialize", "strategy.", "persistence.", "executor.",
                          "instanceLock.", "this.started = true", "entryState."):
            self.assertNotIn(forbidden, body)
        self.assertIn("this.preparationState.registered", method(self.child, "initialize"))
        self.assertIn("if (!this.started || this.persistencePreparation)", method(self.child, "startTimer"))

    def test_only_parent_starts_timer_and_uses_scheduled_entry(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertIn("!this.started || !this.timerStarted", body)
        self.assertEqual(body.count(".processPreparation();"), 1)
        for forbidden in ("processEntry(", "processTrail(",
                          ".onTick(", ".onTimer(", ".startTimer(", "OrderSend("):
            self.assertNotIn(forbidden, code_only(self.parent))
        self.assertIn("controller.onTick();", method(self.expert, "OnTick"))
        self.assertIn("controller.onTradeTransaction(", method(self.expert, "OnTradeTransaction"))
        self.assertIn("controller.onTimer();", method(self.expert, "OnTimer"))
        self.assertNotIn("EventSetTimer(", code_only(self.parent))
        self.assertIn("this.eventTimer.update(", method(self.parent, "updateEventTimer"))

    def test_waiting_or_failed_child_does_not_block_round_robin(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertLess(body.index("this.nextSymbolIndex++;"), body.index(".processPreparation();"))
        self.assertIn("this.nextSymbolIndex >= ArraySize(this.controllers)", body)
        self.assertIn("this.nextSymbolIndex = 0;", body)
        self.assertNotIn("while (", body)
        self.assertNotIn("Sleep(", body)

    def test_same_h1_trade_start_boundary_does_not_reuse_warmup_history(self):
        body = code_only(method(self.child, "processPreparation"))
        self.assertIn("bool beforeTradeStart = this.config.isBeforeTesterTradeStart(TimeCurrent())", body)
        self.assertIn("beforeTradeStart == this.preparationBeforeTradeStart", body)
        self.assertLess(body.index("this.preparationBeforeTradeStart = beforeTradeStart"),
                        body.index("this.strategy.prepareHistory(this.config.testerTradeStartTime)"))

    def test_history_retry_and_current_bar_validation_do_not_consume_signal(self):
        body = code_only(method(self.child, "processPreparation"))
        self.assertIn("this.preparationState.historyReady && this.strategy.isHistoryPrepared() && barTime > 0", body)
        self.assertIn("barTime == this.preparationState.h1BarTime", body)
        self.assertIn("if (!this.preparationState.resourcesInitialized)", body)
        self.assertIn("this.strategy.initialize(this.preparationState.symbolName)", body)
        self.assertIn("this.strategy.prepareHistory(this.config.testerTradeStartTime)", body)
        self.assertLess(body.index("barTime <= 0 || barTime != iTime("),
                        body.index("this.preparationState.historyReady = true;"))
        for forbidden in ("strategy.analyze", "strategy.evaluate", "entryState.",
                          "persistence.", "executor.", "EventSetTimer", "OrderSend"):
            self.assertNotIn(forbidden, body)

    def test_failure_and_shutdown_release_only_owned_timer_and_every_child(self):
        failure = code_only(method(self.parent, "fail"))
        self.assertIn("this.lastError = fromReason;", failure)
        self.assertIn("this.shutdown(REASON_INITFAILED);", failure)
        shutdown = code_only(method(self.parent, "shutdown"))
        self.assertRegex(shutdown, r"if\s*\(this.timerStarted\)\s*\{\s*EventKillTimer\(\);")
        self.assertIn("this.timerStarted = false;", shutdown)
        self.assertIn("i < ArraySize(this.controllers)", shutdown)
        self.assertLess(shutdown.index(".shutdown(fromReason);"), shutdown.index("delete this.controllers[i];"))
        self.assertIn("this.controllers[i] = NULL;", shutdown)
        child = code_only(method(self.child, "shutdown"))
        self.assertRegex(child, r"if\s*\(this.preparationState.registered && !this.protectionEnabled\)\s*\{\s*"
                         r"this.preparationBeforeTradeStart = false;\s*this.strategy.destroy\(\);\s*this.preparationState.reset\(\);\s*return;")

    def test_status_is_copied_and_invalid_index_clears_output(self):
        self.assertIn("fromState = this.preparationState;", method(self.child, "getPreparationState"))
        parent = code_only(method(self.parent, "getPreparationState"))
        self.assertLess(parent.index("fromState.reset();"), parent.index("if (!this.started"))
        self.assertIn("fromIndex < 0 || fromIndex >= ArraySize(this.controllers)", parent)

    def test_ea_cleans_up_on_init_failure_and_records_common_settings(self):
        init = code_only(method(self.expert, "OnInit"))
        self.assertIn("!controller.initialize(InpLotSize, InpMaxInitialStopLossPips, InpTesterTradeStartTime)", init)
        self.assertIn("|| !controller.startTimer()", init)
        self.assertLess(init.index("controller.shutdown(REASON_INITFAILED);"),
                        init.index("delete controller;"))
        self.assertIn("controller = NULL;", init)
        self.assertIn("controller.shutdown(fromReason);", method(self.expert, "OnDeinit"))
        self.assertIn("input double InpLotSize = 0.01;", code_only(self.expert))
        self.assertIn("input double InpMaxInitialStopLossPips = 100.0;", code_only(self.expert))
        self.assertIn("28通貨のH1エントリー・保護管理", self.expert)

    def test_all_locks_precede_parent_schema_and_all_runs(self):
        body = code_only(method(self.parent, "initialize"))
        self.assertLess(body.index(".initializePersistencePreparation("), body.index("database.open(databaseFileName, true)"))
        self.assertLess(body.index("database.close();"), body.index(".startPersistencePreparation()"))
        self.assertIn(".processPersistencePreparation();", body)
        self.assertIn('state.status == "LEASE_LOST"', method(self.parent, "initialize"))
        child = code_only(method(self.child, "initializePersistencePreparation"))
        self.assertIn("this.instanceLock.acquire(this.config.lockScope)", child)
        for forbidden in ("persistence.open", "strategy.initialize", "executor.", "EventSetTimer"):
            self.assertNotIn(forbidden, child)
        self.assertIn("this.run.id == 0 && !this.persistencePreparation", method(self.child, "connectAndRestore"))

    def test_every_timer_maintains_all_leases_before_one_history_check(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertLess(body.index(".processPersistencePreparation();"), body.index(".processPreparation();"))
        self.assertIn("i < ArraySize(this.controllers)", body)
        self.assertIn("this.maintainPersistence();", method(self.child, "processPersistencePreparation"))
        body = method(self.child, "maintainPersistence")
        self.assertIn("this.persistencePreparation && this.run.id > 0", body)
        self.assertIn("this.run.leaseExpiresAt <= now", body)
        self.assertIn("!this.leaseLost", body)

    def test_db_preparation_never_grants_or_dispatches_trading(self):
        for name in ("startTimer", "onTick", "onTimer", "processMaintenance",
                     "processProtection", "processTrail", "processEntry", "processTradeReconciliation",
                     "processWarmup", "canUseFastTesterWarmup", "onTradeTransaction"):
            self.assertIn("this.persistencePreparation", method(self.child, name), name)
        authority = code_only(method(self.child, "updateManagementAuthority"))
        self.assertIn("this.leaseLost || this.scheduledTickWarmup", authority)
        self.assertIn("(this.persistencePreparation && !this.protectionEnabled)", authority)
        body = code_only(method(self.child, "connectAndRestore"))
        branch = body.split("if (this.persistencePreparation) {", 1)[1].split("}", 1)[0]
        self.assertIn("this.executor.restoreFromDatabase()", branch)
        self.assertIn("return this.databaseReady;", branch)
        self.assertNotIn("reconcile", branch)
        executor = (ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh").read_text(encoding="utf-8-sig")
        body = code_only(method(executor, "restoreFromDatabase"))
        for forbidden in ("OrderSend", "reconcile", "processPending", "saveTrade", "setManagementAuthority"):
            self.assertNotIn(forbidden, body)
        self.assertIn("loadActiveTrade(this.contextKey, this.trade, this.active)", body)

    def test_h1_unavailable_does_not_block_db_restore_but_decision_is_retried(self):
        body = code_only(method(self.child, "connectAndRestore"))
        self.assertIn("if (!this.persistencePreparation) {", body)
        self.assertLess(body.index("if (!this.persistencePreparation) {"), body.index("datetime currentBar = iTime"))
        decision = code_only(method(self.child, "restorePreparedDecision"))
        self.assertIn("barTime <= 0 || barTime == this.restoredDecisionBar", decision)
        self.assertLess(decision.index(".loadDecision("), decision.index("this.restoredDecisionBar = barTime"))
        self.assertIn("barTime != iTime(this.config.symbolName, PERIOD_H1, 0)", decision)
        self.assertIn("if (found)", decision)
        self.assertIn("this.entryState.finalize(barTime)", decision)

    def test_common_session_changes_run_identity_only_before_tester_context(self):
        config = (ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh").read_text(encoding="utf-8-sig")
        body = method(config, "initialize")
        self.assertIn('this.sessionUid + "|" + this.symbolName', body)
        self.assertLess(body.index('this.sessionUid + "|" + this.symbolName'), body.index('this.contextKey += this.runUid'))
        scope = body.split('this.lockScope = ', 1)[1].split(';', 1)[0]
        self.assertNotIn("sessionUid", scope)
        canonical = method(config, "createCanonicalText")
        self.assertIn("ENTRY_ENABLED=1", canonical)
        self.assertNotIn("+ this.sessionUid", canonical)
        self.assertIn("this.run.sessionUid = this.config.sessionUid", method(self.child, "initializeRun"))

    def test_preparation_shutdown_finishes_own_run_without_trade_audit(self):
        body = code_only(method(self.child, "shutdown"))
        branch = body.split("if (this.persistencePreparation && !this.protectionEnabled) {", 1)[1].split("if (this.preparationState.registered", 1)[0]
        self.assertIn("this.persistence.finishRun(this.run.id, status, errorText)", branch)
        self.assertIn("this.instanceLock.release()", branch)
        self.assertIn("this.persistence.close()", branch)
        self.assertNotIn("executor.", branch)
        self.assertIn('status = "FAILED"', method(self.child, "shutdown"))
        self.assertIn("return;", branch)


    def test_protection_is_enabled_only_after_all_readiness_checks_and_timer_success(self):
        body = code_only(method(self.parent, "startTimer"))
        self.assertLess(body.index(".canEnableProtection()"), body.index("this.updateEventTimer(false)"))
        self.assertLess(body.index("this.timerStarted = true"), body.index(".enableProtection()"))
        for forbidden in ("reconcile", "processPending", "OrderSend"):
            self.assertNotIn(forbidden, method(self.child, "enableProtection"))
        self.assertIn("this.run.leaseExpiresAt > TimeLocal()", method(self.child, "canEnableProtection"))
        for name in ("onTick", "onTimer", "startTimer", "processEntry"):
            self.assertIn("!this.started || this.persistencePreparation", method(self.child, name))

    def test_all_protection_precedes_single_scheduled_analysis(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertLess(body.index(".processPersistencePreparation()"), body.index(".processProtection(barTime)"))
        self.assertLess(body.index(".processProtection(barTime)"), body.index(".getPendingTrailBar()"))
        self.assertLess(body.index(".getPendingTrailBar()"), body.index(".processPreparation()"))
        self.assertEqual(body.count(".processScheduledTrail(trailBarTime)"), 1)
        self.assertIn("this.nextTrailSymbolIndex = (candidateIndex + 1)", body)
        self.assertIn("if (symbolIndex < 0)", body)

    def test_tick_never_analyzes_and_resumes_all_protection_after_fast_warmup(self):
        body = code_only(method(self.parent, "onTick"))
        self.assertIn("this.controllers[this.chartSymbolIndex]", body)
        self.assertIn("this.chartSymbolIndex < 0", body)
        self.assertIn("wasFastWarmup || !this.eventTimer.isNormalReady()", body)
        for forbidden in ("processEntry", "processTrail", "processPreparation", "EventSetTimer"):
            self.assertNotIn(forbidden, body)

    def test_trail_history_retry_and_bar_transition_are_checked(self):
        pending = code_only(method(self.child, "getPendingTrailBar"))
        self.assertIn("this.run.leaseExpiresAt <= TimeLocal()", pending)
        self.assertIn("barTime == this.lastTrailObservedBar", pending)
        scheduled = code_only(method(self.child, "processScheduledTrail"))
        self.assertIn("fromBarTime != this.getPendingTrailBar()", scheduled)
        self.assertIn("H1EaClock::milliseconds() + 30000", scheduled)
        self.assertLess(scheduled.index("!this.preparationState.historyReady"), scheduled.index("this.processTrail(fromBarTime)"))
        trail = code_only(method(self.child, "processTrail"))
        self.assertIn("trailSnapshot.h1BarTime != fromBarTime", trail)
        self.assertIn("iTime(this.config.symbolName, PERIOD_H1, 0) != fromBarTime", trail)

    def test_routing_has_no_magic_filter_or_inline_broker_reconciliation(self):
        body = code_only(method(self.parent, "onTradeTransaction"))
        self.assertIn(".queueTradeTransaction(", body)
        self.assertIn(".matchesTradeTransaction(", body)
        self.assertIn("this.requestAllReconciliation();", body)
        for forbidden in (".magic", ".reconcile(", ".processProtection(", ".processTrail(", "OrderSend"):
            self.assertNotIn(forbidden, body)
        queue = method(self.child, "queueTradeTransaction")
        self.assertIn('transaction.type != TRADE_TRANSACTION_REQUEST && transaction.symbol == ""', queue)
        self.assertIn("transaction.symbol = this.config.symbolName", queue)
        self.assertIn("this.executor.observeTradeTransaction", queue)

    def test_unknown_notification_schedules_full_deal_reconciliation(self):
        executor = (ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh").read_text(encoding="utf-8-sig")
        body = code_only(method(executor, "requestReconciliation"))
        self.assertIn("this.closedDealAuditChecked || !this.closedDealAuditFull", body)
        self.assertIn("this.closedDealAuditFull = true", body)
        self.assertIn("this.nextPendingDealAuditTick = 0", body)
        self.assertNotIn("this.reconcile()", body)
        self.assertNotIn("History", body)

    def test_multi_quote_validation_is_opt_in_and_uses_own_symbol(self):
        executor = (ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh").read_text(encoding="utf-8-sig")
        body = code_only(method(executor, "readTick"))
        self.assertIn("if (this.requireCurrentQuote)", body)
        self.assertIn("iTime(this.symbolName, PERIOD_H1, 0)", body)
        self.assertIn("fromTick.time_msc > (long)TimeCurrent() * 1000 + 999", body)
        self.assertIn("fromTick.time_msc < (long)barTime * 1000", body)
        self.assertIn("this.executor.setRequireCurrentQuote(true)", method(self.child, "enableProtection"))


    def test_entry_activation_requires_protection_and_follows_timer_success(self):
        body = code_only(method(self.parent, "startTimer"))
        self.assertLess(body.index("this.updateEventTimer(false)"), body.index(".enableEntry()"))
        self.assertLess(body.index(".enableProtection()"), body.index(".enableEntry()"))
        body = code_only(method(self.child, "enableEntry"))
        self.assertIn("if (!this.protectionEnabled)", body)
        self.assertIn("H1EaClock::milliseconds() + 1000", body)
        self.assertNotIn("evaluateEntry", body)
        self.assertIn("this.entryEnabled = false", method(self.child, "shutdown"))

    def test_entry_waits_for_own_bar_restoration_history_and_quote(self):
        body = code_only(method(self.child, "processScheduledEntry"))
        for guard in ("!fromNormalTimerReady", "fromBarTime != this.getPendingEntryBar()",
                      "!this.preparationState.historyReady", "this.restoredDecisionBar != fromBarTime",
                      "this.preparationState.h1BarTime != fromBarTime", "!this.executor.hasCurrentEntryQuote(fromBarTime)"):
            self.assertLess(body.index(guard), body.index("this.evaluateEntry("))
        pending = code_only(method(self.child, "getPendingEntryBar"))
        self.assertIn("this.entryState.isFinalized(barTime)", pending)
        self.assertIn("this.config.isBeforeTesterTradeStart(TimeCurrent())", pending)
        self.assertIn("this.run.leaseExpiresAt <= TimeLocal()", pending)
        for forbidden in ("canEnter", "Spread", "hasPosition", "strategy.evaluate", "recordCount"):
            self.assertNotIn(forbidden, pending + body)

    def test_entry_and_trail_cannot_both_analyze_in_one_event(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertIn("else if (entrySymbolIndex == symbolIndex && entryBarTime > 0)", body)
        self.assertEqual(body.count(".processScheduledEntry("), 1)
        self.assertLess(body.index(".processProtection(barTime)"), body.index(".getPendingEntryBar()"))
        self.assertLess(body.index(".restorePreparedDecision()"), body.index(".processScheduledEntry("))

    def test_trail_cannot_starve_entry_and_hour_rotation_is_deterministic(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertIn("this.consecutiveTrailTasks < 2", body)
        self.assertIn("this.consecutiveTrailTasks++", body)
        self.assertIn("this.nextEntrySymbolIndex = (entrySymbolIndex + 1)", body)
        self.assertIn("(long)TimeCurrent() / 3600", body)
        self.assertIn("(long)scheduleHour % ArraySize(this.controllers)", body)
        self.assertNotIn("GetTickCount", body)
        self.assertNotIn("MathRand", body)
        self.assertIn("!candidateState.resourcesInitialized || candidateState.h1BarTime <= 0", body)

    def test_entry_retry_is_throttled_and_tester_uses_simulated_clock(self):
        body = code_only(method(self.child, "processScheduledEntry"))
        self.assertIn("this.nextScheduledEntryTick = startedTick + 30000", body)
        self.assertIn("this.nextScheduledEntryTick = startedTick + 1000", body)
        self.assertLess(body.index("this.nextScheduledEntryTick = startedTick + 30000"),
                        body.index("!this.preparationState.historyReady"))
        pending = method(self.child, "getPendingEntryBar")
        self.assertIn("H1EaClock::milliseconds() < this.nextScheduledEntryTick", pending)
        clock = (ROOT / "Include/MstngH1Ea/Runtime/H1EaClock.mqh").read_text(encoding="utf-8-sig")
        self.assertIn("TimeCurrent()", clock)

    def test_changed_or_stale_quote_cannot_consume_judge_after_analysis(self):
        body = code_only(method(self.child, "evaluateEntry"))
        self.assertLess(body.index("this.strategy.analyze(snapshot)"), body.index("!this.executor.hasCurrentEntryQuote(barTime)"))
        self.assertLess(body.index("!this.executor.hasCurrentEntryQuote(barTime)"), body.index("this.strategy.evaluate(previousCount, snapshot)"))
        executor = (ROOT / "Include/MstngH1Ea/Trade/H1EaTradeExecutor.mqh").read_text(encoding="utf-8-sig")
        body = code_only(method(executor, "hasCurrentEntryQuote"))
        self.assertIn("fromBarTime > TimeCurrent()", body)
        self.assertIn("TimeCurrent() >= fromBarTime + PeriodSeconds(PERIOD_H1)", body)
        self.assertIn("this.readTick(marketTick)", body)
        self.assertIn("iTime(this.symbolName, PERIOD_H1, 0) == fromBarTime", body)
        send = code_only(method(executor, "sendEntry"))
        self.assertIn("this.requireCurrentQuote && !this.hasCurrentEntryQuote(this.entryH1Bar)", send)
        self.assertLess(send.index("!this.hasCurrentEntryQuote(this.entryH1Bar)"), send.index("OrderSend(request, result)"))

    def test_shared_judge_count_safety_and_save_before_send_order_remains(self):
        body = code_only(method(self.child, "evaluateEntry"))
        chain = ["this.strategy.evaluate(previousCount, snapshot)", "this.entryState.recordCount(",
                 "this.entryState.finalize(barTime)", "this.applyEntrySafety(snapshot, decision)",
                 "this.persistence.saveEntry(this.run.id, decision, trade, event)", "this.executor.sendEntry(trade, event)"]
        self.assertEqual(sorted(body.index(part) for part in chain), [body.index(part) for part in chain])
        self.assertEqual(body.count("this.strategy.evaluate("), 1)
        self.assertIn("if (this.entryState.isFinalized(barTime))", body)

    def test_multi_config_records_timer_entry_and_no_global_cap(self):
        config = (ROOT / "Include/MstngH1Ea/Config/H1EaConfig.mqh").read_text(encoding="utf-8-sig")
        body = method(config, "createCanonicalText")
        for value in ('string testerEvaluationTrigger = "TICK"', 'testerEvaluationTrigger = "TIMER"',
                      "MULTI_SYMBOL_ENTRY", "GLOBAL_POSITION_LIMIT=0", "TRAIL2_ENTRY1_HOUR_ROTATE_V1"):
            self.assertIn(value, body)
        self.assertNotIn("PositionsTotal", method(self.child, "getPendingEntryBar"))


if __name__ == "__main__":
    unittest.main()
