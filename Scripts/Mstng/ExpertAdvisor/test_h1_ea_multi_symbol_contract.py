"""Stage-two source contracts. These do not run MT5 or send orders."""

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
        self.assertIn("if (!this.started)", method(self.child, "startTimer"))

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

    def test_ea_cleans_up_on_init_failure_and_exposes_no_ineffective_trade_inputs(self):
        init = code_only(method(self.expert, "OnInit"))
        self.assertIn("!controller.initialize() || !controller.startTimer()", init)
        self.assertLess(init.index("controller.shutdown(REASON_INITFAILED);"),
                        init.index("delete controller;"))
        self.assertIn("controller = NULL;", init)
        self.assertIn("controller.shutdown(fromReason);", method(self.expert, "OnDeinit"))
        self.assertNotIn("input ", code_only(self.expert))


if __name__ == "__main__":
    unittest.main()
