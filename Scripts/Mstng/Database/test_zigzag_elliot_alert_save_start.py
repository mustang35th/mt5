"""Regression checks for the normal ZigZagElliot tester Alert DB save boundary.

Pure production MQL helpers are extracted and translated to Python for boundary
execution. Separate source-wiring checks protect analysis/count ordering, CSV,
and the six-argument snapshot transaction. This does not execute MQL or MT5.

Run: python -B -m unittest discover -s Scripts/Mstng/Database
     -p test_zigzag_elliot_alert_save_start.py -v
"""

import ast
import re
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/ExpertAdvisor"))
from test_h1_ea_tester_warmup_contract import block_end, code_only, method

FIELD = "mtf3In3AlertTesterSaveStartTime"


def compact(source):
    return re.sub(r"\s+", "", code_only(source))


def translate_predicate(source, name):
    """Translate only if/return boolean helpers; reject any added side effects."""
    body = code_only(method(source, name))
    body = body.replace("MQLInfoInteger(MQL_TESTER)", "is_tester")
    body = body.replace("this.config.", "config.")
    body = re.sub(r"\btrue\b", "True", body)
    body = re.sub(r"\bfalse\b", "False", body)
    body = re.sub(r"!(?!=)", " not ", body)
    body = body.replace("&&", " and ").replace("||", " or ")
    lines = ["def extracted(config, is_tester, fromCurrentBarTime=0):"]
    indentation = 1
    statement = ""
    for token in re.split(r"([{};])", body):
        if token == "{":
            match = re.fullmatch(r"if\s*\((.*)\)", statement, re.DOTALL)
            if match is None:
                raise AssertionError("Unsupported MQL block: " + statement)
            lines.append("    " * indentation + "if " + " ".join(match[1].split()) + ":")
            indentation += 1
            statement = ""
        elif token == "}":
            if statement.strip():
                raise AssertionError("Unexpected statement before block close")
            indentation -= 1
        elif token == ";":
            if not statement.startswith("return "):
                raise AssertionError("Expected side-effect-free return: " + statement)
            lines.append("    " * indentation + " ".join(statement.split()))
            statement = ""
        else:
            statement += token.strip()
    if statement or indentation != 1:
        raise AssertionError("Unexpected incomplete helper")
    tree = ast.parse("\n".join(lines))
    allowed = (ast.Module, ast.FunctionDef, ast.arguments, ast.arg, ast.If,
               ast.Return, ast.BoolOp, ast.And, ast.Or, ast.UnaryOp, ast.Not,
               ast.Compare, ast.Eq, ast.NotEq, ast.Gt, ast.GtE, ast.Lt, ast.LtE,
               ast.Name, ast.Load, ast.Attribute, ast.Constant)
    for node in ast.walk(tree):
        if not isinstance(node, allowed):
            raise AssertionError("Unexpected translated syntax: " + ast.dump(node))
    namespace = {"__builtins__": {}}
    exec(compile(tree, "<extracted " + name + ">", "exec"), namespace)
    return namespace["extracted"]


def enclosing_blocks(source, offset):
    """Return block bodies containing a call without matching its literal text."""
    masked = code_only(source)
    bodies = []
    for opening in range(offset):
        if masked[opening] != "{":
            continue
        end = block_end(masked, opening)
        if end > offset:
            bodies.append((opening, end, source[opening + 1:end]))
    return bodies


class ZigZagElliotAlertSaveStartTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths = {
            "indicator": "Indicators/ZigZagElliot.mq5",
            "config": "Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotConfig.mqh",
            "controller": "Include/Mstng/Indicator/ZigZagElliot/Mtf3In3AlertController.mqh",
            "main": "Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotController.mqh",
            "strategy": "Include/Mstng/ExpertAdvisor/AbstractExpertAdvisor.mqh",
            "builder": "Include/Mstng/ExpertAdvisor/Mtf3In3AlertSnapshotBuilder.mqh",
        }
        for name, path in paths.items():
            setattr(cls, name, (ROOT / path).read_text(encoding="utf-8-sig"))
        cls.gate = staticmethod(translate_predicate(cls.controller, "isDatabaseSaveTimeReached"))
        cls.effective_start = staticmethod(translate_predicate(cls.controller, "getEffectiveDatabaseSaveStartTime"))

    def allowed(self, configured, bar, tester=True):
        return self.gate(SimpleNamespace(**{FIELD: configured}), tester, bar)

    def test_actual_helper_before_exact_after_and_missing_bar(self):
        start = 1785542400
        for label, bar, expected in (
            ("previous M5", start - 300, False), ("one second before", start - 1, False),
            ("inclusive start", start, True), ("one second after", start + 1, True),
            ("next M5", start + 300, True), ("missing bar", 0, False),
            ("invalid bar", -1, False),
        ):
            with self.subTest(label=label):
                self.assertIs(self.allowed(start, bar), expected)

    def test_actual_helper_does_not_round_nonaligned_start_or_latch_open(self):
        start = 1785542400
        for bar, expected in ((start, False), (start + 300, True), (start, False)):
            with self.subTest(bar=bar, expected=expected):
                self.assertIs(self.allowed(start + 120, bar), expected)

    def test_actual_helpers_keep_default_and_live_compatible(self):
        for tester in (False, True):
            for bar in (-1, 0, 1785542100, 1785542400, 1785542700):
                with self.subTest(tester=tester, bar=bar):
                    self.assertIs(self.allowed(0, bar, tester), True)
                    self.assertIs(self.allowed(1785542400, bar, False), True)
        for configured in (0, 1785542520):
            config = SimpleNamespace(**{FIELD: configured})
            self.assertEqual(0, self.effective_start(config, False))
            self.assertEqual(configured, self.effective_start(config, True))

    def test_default_is_zero_and_indicator_forwards_input(self):
        self.assertRegex(self.indicator, r"datetime\s+" + FIELD + r"\s*=\s*0\s*;")
        self.assertIn("this." + FIELD + "=0;", compact(method(self.config, "ZigZagElliotConfig")))
        self.assertIn("config." + FIELD + "=" + FIELD + ";", compact(method(self.indicator, "OnInit")))
        self.assertIn("this.config=fromConfig;", compact(method(self.controller, "initialize")))

    def test_gate_only_wraps_database_after_analysis_and_leaves_csv_outside(self):
        execute = method(self.controller, "execute")
        normalized = compact(execute)
        analyze = normalized.index("this.expertAdvisorMtf3In3.analyze(fromElliotAll,this.signalCount);")
        gate = normalized.index("this.isDatabaseSaveTimeReached(")
        saved = execute.index("persistenceService.saveSnapshot(")
        self.assertLess(analyze, gate)
        self.assertEqual(normalized.count("this.isDatabaseSaveTimeReached("), 1)
        blocks = enclosing_blocks(execute, saved)
        database_blocks = [item for item in blocks
                           if "Mtf3In3AlertSnapshotBuilder::build(" in item[2]]
        self.assertEqual(1, len(database_blocks))
        opening, end, block = database_blocks[0]
        condition = execute[execute.rfind("if", 0, opening):opening]
        self.assertEqual("if(isDatabaseSaveAllowed)", compact(condition))
        gate_offset = execute.index("this.isDatabaseSaveTimeReached(")
        eligibility_blocks = enclosing_blocks(execute, gate_offset)
        self.assertEqual(1, len(eligibility_blocks))
        eligibility_opening = eligibility_blocks[0][0]
        eligibility = execute[execute.rfind("if", 0, eligibility_opening):eligibility_opening]
        for required in ("mtf3In3AlertDatabaseEnabled", "databaseReady", "isAnalysisSucceeded"):
            self.assertIn(required, eligibility)
        self.assertIn("fromElliotAll.elliotCurrent!=NULL", compact(eligibility))
        self.assertIn("boolisDatabaseSaveAllowed=false;", normalized[:gate])
        self.assertIn("isDatabaseSaveAllowed=this.isDatabaseSaveTimeReached(currentBarTime);", normalized)
        self.assertLess(gate, normalized.index("if(!this.expertAdvisorMtf3In3.isAlert)"))
        self.assertNotIn("return;", compact(block))
        self.assertNotIn("Mtf3In3AlertCsvWriter", block)
        self.assertGreater(execute.index("Mtf3In3AlertCsvWriter::write("), end)
        self.assertNotIn(FIELD, code_only(method(self.strategy, "analyze")))
        strategy = compact(method(self.strategy, "analyze"))
        self.assertIn("fromSignalCount.addCount(sourceSignalTime,sourceIsBuy)", strategy)
        self.assertIn("if(count==entryCount)", strategy)

    def test_gate_uses_snapshot_bar_and_keeps_complete_snapshot_transaction(self):
        execute = compact(method(self.controller, "execute"))
        self.assertIn("currentOhlcBarTime", execute)
        self.assertNotIn("TimeCurrent()", execute)
        self.assertNotIn("TimeLocal()", execute)
        self.assertIn("persistenceService.saveSnapshot(snapshot.alert,snapshot.timeFrames,"
                      "snapshot.points,snapshot.correction,snapshot.correctedTimeFrames,"
                      "snapshot.correctedPoints)", execute)
        self.assertRegex(self.builder, r"datetime\s+currentBarTime\s*=\s*"
                         r"fromElliotAll\.elliotCurrent\.currentOhlcBarTime;")
        self.assertIn("fromEntity.currentBarTime = fromCurrentBarTime;", self.builder)

    def test_run_records_configured_effective_start_in_existing_input_hash(self):
        input_text = method(self.controller, "createInputText")
        self.assertIn(FIELD + "=", input_text)
        self.assertIn("mtf3In3AlertEffectiveSaveStartTime=", input_text)
        self.assertIn("this.config." + FIELD, input_text)
        self.assertIn("this.getEffectiveDatabaseSaveStartTime()", input_text)
        self.assertGreaterEqual(input_text.count("formatDatabaseSaveStartTime("), 2)
        run = compact(method(self.controller, "setDatabaseRun"))
        self.assertIn("stringinputText=this.createInputText();", run)
        self.assertIn("this.databaseRun.inputText=inputText;", run)
        self.assertIn("this.databaseRun.inputHash=this.createTextHash(inputText);", run)
        self.assertIn("this.databaseRun.testerFrom=0;", run)
        self.assertIn("this.databaseRun.analysisInputHash=ZigZagElliotAnalysisProfile::createHash();", run)
        formatter = method(self.controller, "formatDatabaseSaveStartTime")
        self.assertIn('return "0";', formatter)
        self.assertIn("TIME_DATE | TIME_SECONDS", formatter)

    def test_negative_start_rejected_only_for_enabled_tester_database(self):
        initialize = method(self.main, "initialize")
        masked = code_only(initialize)
        occurrence = masked.index("this.config." + FIELD)
        matching = []
        for match in re.finditer(r"if\s*\(", masked):
            opening = masked.index("{", match.end())
            if match.start() < occurrence < opening:
                end = block_end(masked, opening)
                matching.append((initialize[match.start():opening], initialize[opening + 1:end]))
        self.assertEqual(1, len(matching))
        condition, block = matching[0]
        self.assertIn("mtf3In3AlertDatabaseEnabled", condition)
        self.assertRegex(condition, FIELD + r"\s*<\s*0")
        self.assertTrue("MQL_TESTER" in condition or "!this.timerMode" in compact(condition))
        self.assertIn("return INIT_PARAMETERS_INCORRECT;", block)


if __name__ == "__main__":
    unittest.main(verbosity=2)
