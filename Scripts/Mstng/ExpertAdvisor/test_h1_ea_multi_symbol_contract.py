"""Stage-three source contracts. These do not run MT5 or send orders."""

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

    def test_only_parent_starts_timer_and_only_preparation_is_dispatched(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertIn("!this.started || !this.timerStarted", body)
        self.assertEqual(body.count(".processPreparation();"), 1)
        for forbidden in ("processEntry(", "processProtection(", "processTrail(",
                          ".onTick(", ".onTimer(", ".startTimer(", "OrderSend("):
            self.assertNotIn(forbidden, code_only(self.parent))
        self.assertNotIn("void OnTick(", self.expert)
        self.assertNotIn("void OnTradeTransaction(", self.expert)
        self.assertIn("controller.onTimer();", method(self.expert, "OnTimer"))
        self.assertEqual(code_only(self.parent).count("EventSetTimer("), 1)

    def test_waiting_or_failed_child_does_not_block_round_robin(self):
        body = code_only(method(self.parent, "onTimer"))
        self.assertLess(body.index("this.nextSymbolIndex++;"), body.index(".processPreparation();"))
        self.assertIn("this.nextSymbolIndex >= ArraySize(this.controllers)", body)
        self.assertIn("this.nextSymbolIndex = 0;", body)
        self.assertNotIn("while (", body)
        self.assertNotIn("Sleep(", body)

    def test_history_retry_and_current_bar_validation_do_not_consume_signal(self):
        body = code_only(method(self.child, "processPreparation"))
        self.assertIn("this.preparationState.historyReady && barTime > 0", body)
        self.assertIn("barTime == this.preparationState.h1BarTime", body)
        self.assertIn("if (!this.preparationState.resourcesInitialized)", body)
        self.assertIn("this.strategy.initialize(this.preparationState.symbolName)", body)
        self.assertIn("this.strategy.prepareHistory()", body)
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
        self.assertRegex(child, r"if\s*\(this.preparationState.registered\)\s*\{\s*"
                         r"this.strategy.destroy\(\);\s*this.preparationState.reset\(\);\s*return;")

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
        self.assertIn("第3段階はDBへの設定記録のみ・売買は未接続", self.expert)

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
        self.assertIn("this.leaseLost || this.persistencePreparation", method(self.child, "updateManagementAuthority"))
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
        self.assertIn("TRADING_ENABLED=0", canonical)
        self.assertNotIn("+ this.sessionUid", canonical)
        self.assertIn("this.run.sessionUid = this.config.sessionUid", method(self.child, "initializeRun"))

    def test_preparation_shutdown_finishes_own_run_without_trade_audit(self):
        body = code_only(method(self.child, "shutdown"))
        branch = body.split("if (this.persistencePreparation) {", 1)[1].split("if (this.preparationState.registered)", 1)[0]
        self.assertIn("this.persistence.finishRun(this.run.id, status, errorText)", branch)
        self.assertIn("this.instanceLock.release()", branch)
        self.assertIn("this.persistence.close()", branch)
        self.assertNotIn("executor.", branch)
        self.assertIn('status = "FAILED"', method(self.child, "shutdown"))
        self.assertIn("return;", branch)


if __name__ == "__main__":
    unittest.main()
