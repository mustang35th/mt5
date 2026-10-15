"""M5 collector wiring contracts and extracted startup-control-flow regression.

H1 method fingerprints were captured from the pre-collector implementation.
The startup regression executes production method bodies in Node after replacing
MQL local type declarations; platform calls use deterministic history fixtures.
Native MT5/DB tests and a short real collection run remain separate checks.
"""
import hashlib
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INCLUDE = ROOT / "Include" / "Mstng"


def read(relative):
    return (INCLUDE / relative).read_text(encoding="utf-8-sig")


def body(source, signature):
    start = source.index("{", source.index(signature)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    return source[start:position - 1]


def execute_startup_scenario(source, *, period, steps, tester=False):
    """Run real branch/assignment code, replacing only MQL local declarations."""
    methods = {}
    for name, signature in (
        ("processSymbol", "void processSymbol("),
        ("handleNewBoundary", "void handleNewBoundary("),
        ("observeCaptureBoundary", "void observeCaptureBoundary("),
    ):
        methods[name] = re.sub(
            r"\b(?:string|datetime|bool|int)\s+(?=[A-Za-z]\w*\s*=)",
            "let ", body(source, signature),
        )

    harness = r"""
const scenario = JSON.parse(require('fs').readFileSync(0, 'utf8'));
let step;
let reads;
let ticks = 1000;
const trace = [];
const captures = [];
globalThis.ResetLastError = () => {};
globalThis.iTime = () => {
    if (reads >= step.bars.length) throw new Error('unexpected iTime read');
    return step.bars[reads++];
};
globalThis.GetTickCount64 = () => ++ticks;
globalThis.StringFormat = (...args) => args.join(' ');
globalThis.__FUNCTION__ = 'productionMethod';
const controller = {
    testerMode: scenario.tester,
    testerSaveGateOpen: false,
    observationProfile: {
        isM5: () => scenario.period === 300,
        getAnchorTimeFrame: () => scenario.period,
    },
    symbolNames: ['EURUSD'],
    currentH1BarTimes: [0],
    currentBatchH1BarTime: 0,
    lastDetectedH1BarTimes: [0],
    pendingAnalysisH1BarTimes: [0],
    lastCapturedH1BarTimes: [0],
    analysisReadyFlags: [false],
    symbolRetryCounts: [0],
    testerPreflightH1BarTimes: [0],
    symbolQueuedCounts: [0],
    symbolCompetingWriterFlags: [false],
    captureTargetBarTimes: [0],
    captureDetectedTicks: [0],
    captureAnalysisAttempts: [0],
    totalGapCount: 0,
    logger: {error: () => {}},
    isTesterSaveWindowEnabled: () => false,
    isAnalysisSeriesReady() {
        trace.push(['readiness']);
        return step.ready;
    },
    warmUpSymbol(index) { this.isAnalysisSeriesReady(index); },
    setSymbolStatus(index, code) { this.statusCode = code; },
    getAnchorTimeFrameText: () => String(scenario.period),
    formatDateTime: value => String(value),
    countSkippedH1Bars: (symbol, previous, current) =>
        Math.max(0, Math.floor((current - previous) / scenario.period) - 1),
    capturePendingObservation(index) {
        trace.push(['capture', this.pendingAnalysisH1BarTimes[index]]);
        captures.push(this.pendingAnalysisH1BarTimes[index]);
        this.lastCapturedH1BarTimes[index] = this.pendingAnalysisH1BarTimes[index];
        this.pendingAnalysisH1BarTimes[index] = 0;
        this.analysisReadyFlags[index] = true;
    },
};
controller.processSymbol = new Function('fromIndex', scenario.methods.processSymbol);
controller.handleNewBoundary = new Function(
    'fromIndex', 'fromCurrentH1BarTime', 'fromCountGaps',
    scenario.methods.handleNewBoundary,
);
const observe = new Function('fromIndex', 'fromBarTime', scenario.methods.observeCaptureBoundary);
controller.observeCaptureBoundary = function(index, bar) {
    trace.push(['detect', bar]);
    observe.call(this, index, bar);
};
const results = [];
for (step of scenario.steps) {
    reads = 0;
    const traceStart = trace.length;
    controller.processSymbol(0);
    results.push({
        baseline: controller.lastDetectedH1BarTimes[0],
        current: controller.currentH1BarTimes[0],
        pending: controller.pendingAnalysisH1BarTimes[0],
        ready: controller.analysisReadyFlags[0],
        gaps: controller.totalGapCount,
        captures: [...captures],
        captureTarget: controller.captureTargetBarTimes[0],
        captureDetectedTick: controller.captureDetectedTicks[0],
        status: controller.statusCode,
        reads,
        trace: trace.slice(traceStart),
    });
}
process.stdout.write(JSON.stringify(results));
"""
    completed = subprocess.run(
        [shutil.which("node"), "-e", harness],
        input=json.dumps({"methods": methods, "period": period,
                          "steps": steps, "tester": tester}),
        text=True, encoding="utf-8", capture_output=True, timeout=10, check=True,
    )
    return json.loads(completed.stdout)


class ObservationCollectorContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = read("Indicator/ZigZagElliot/H1ElliotObservationAllController.mqh")
        cls.capture = body(cls.source, "void capturePendingObservation(")
        cls.process = body(cls.source, "void processSymbol(")
        cls.drain = body(cls.source, "void drainSnapshotQueue()")

    def test_h1_unchanged_symbol_resolution_and_inputs(self):
        golden = {
            "string createInputText()": "1409058a87f3bfa2777d6c90b124a31a7074daaa0f06cdd012ba021d6b3b476c",
            "string createTextHash(": "8a395b492fab2b66b6584351ff5e2b16fef6d33be616c5469595b8f811b18ae3",
            "string resolveSymbolName(": "6e21922208effd4b6a52dadc6babd69e310b505c1b76b3800fabc8eb330effba",
            "bool resolveTargetSymbols()": "3b5f118bf4dacd0d2ee7589830f4beb3d11e2ed69a58c9f40f06b265b7c973d1",
        }
        for signature, expected in golden.items():
            with self.subTest(signature=signature):
                self.assertEqual(hashlib.sha256(body(self.source, signature).encode()).hexdigest(), expected)

    def test_h1_event_paths_unchanged(self):
        golden = {
            "int onCalculate(": "94fe4140139321890ce8413d8805eb589da61d55cc3fb982b34c74d0951bb39a",
            "void onTimer()": "c536619302b854c13bbd05b249f3164a6c0a2638718ff3f0bb0958de43d311c8",
            "bool isTesterSaveWindowEnabled()": "f9ededd55b8529b99ba452a8453c1653317342d6e1b2c8859a5e703ec8445854",
        }
        for signature, expected in golden.items():
            with self.subTest(signature=signature):
                self.assertEqual(hashlib.sha256(body(self.source, signature).encode()).hexdigest(), expected)

    def test_preflight_retains_analysis_retry_and_save_start_gates(self):
        preflight = body(self.source, "void processTesterPreflight(")
        self.assertIn("this.isAnalysisSeriesReady(fromIndex)", preflight)
        self.assertRegex(preflight, r"fromCurrentH1BarTime\s*>= this.observationTesterSaveStartTime")
        self.assertIn("if (!saveStartReached", preflight)
        self.assertRegex(preflight, r"if \(saveStartReached\s*&& this.testerPreflightH1BarTimes\[fromIndex\]\s*!= fromCurrentH1BarTime\)\s*\{\s*this.analysisReadyFlags\[fromIndex\] = false;")
        once_per_bar = body(preflight, "if (this.testerPreflightAttemptH1BarTimes[fromIndex]")
        self.assertIn("return;", once_per_bar)
        self.assertLess(preflight.index("this.testerPreflightAttemptH1BarTimes[fromIndex] ="),
                        preflight.index("this.capturePendingObservation(fromIndex, true)"))
        self.assertNotIn("this.testerSaveGateOpen = true", preflight)
        self.assertNotIn("this.snapshotQueue.Add(", preflight)

    def test_fixed_profile_is_per_instance_and_m5_wrapper_is_thin(self):
        self.assertIn("fromAnchorTimeFrame = PERIOD_H1", self.source)
        self.assertIn(": observationProfile(fromAnchorTimeFrame)", self.source)
        self.assertNotRegex(self.source, r"static\s+ZigZagElliotObservationProfile")
        wrapper = read("Indicator/ZigZagElliot/M5ElliotObservationAllController.mqh")
        self.assertIn("H1ElliotObservationAllController(PERIOD_M5)", wrapper)
        self.assertNotIn("void execute", wrapper)

    def test_profile_drives_anchor_series_warmup_and_hash(self):
        self.assertNotIn("ZigZagElliotAnalysisProfile::getAnchorTimeFrame", self.source)
        self.assertNotIn("ZigZagElliotAnalysisProfile::getObservationTimeFrame", self.source)
        warmup = body(self.source, "void warmUpTargetSymbols()")
        readiness = body(self.source, "bool isAnalysisSeriesReady(")
        self.assertIn("this.historyPreparations[i].initialize(", warmup)
        self.assertIn("this.symbolNames[i]", warmup)
        self.assertIn("this.observationProfile.getAnchorTimeFrame()", warmup)
        self.assertIn("this.historyPreparations[fromIndex].prepare(", readiness)
        self.assertIn("this.observationTesterSaveStartTime", readiness)
        for forbidden in ("CopyRates(", "requiredBars =", "WarmUpSeriesUtil::"):
            self.assertNotIn(forbidden, self.source)
        run = body(self.source, "void setDatabaseRun()")
        for method in ("getSchemaVersion", "getStrategy", "getStrategyVersion", "createCanonicalText", "createHash"):
            self.assertIn("this.observationProfile." + method + "()", run)

    def test_m5_rejects_upper_tester_period_before_warmup(self):
        initialize = body(self.source, "int initialize(")
        self.assertLess(initialize.index("PeriodSeconds(_Period) > PeriodSeconds(PERIOD_M5)"),
                        initialize.index("this.warmUpTargetSymbols()"))
        self.assertIn("MQLInfoInteger(MQL_OPTIMIZATION)", initialize)

    def test_live_baseline_does_not_capture_current_bar(self):
        baseline = self.process.split("if (this.lastDetectedH1BarTimes[fromIndex] == 0)", 1)[1]
        self.assertLess(baseline.index("if (!this.testerMode)"), baseline.index('"BASE"'))
        self.assertLess(baseline.index("return;"), baseline.index("this.pendingAnalysisH1BarTimes[fromIndex] = currentH1BarTime"))

    def test_initial_tester_retry_is_per_symbol_and_once_per_bar(self):
        initial = self.process.split("if (this.testerMode", 1)[1].split("if (!this.testerMode", 1)[0]
        self.assertIn("!this.analysisReadyFlags[fromIndex]", initial)
        self.assertLess(initial.index("previousDetectedH1BarTime == currentH1BarTime"),
                        initial.index("this.capturePendingObservation(fromIndex)"))
        self.assertNotIn("getReadyCount()", initial)
        self.assertNotIn("lastSavedH1BarTimes", initial)

    def test_gate_requires_28_same_actual_bars_then_second_pass(self):
        gate = body(self.source, "bool tryOpenTesterSaveGate()")
        self.assertIn("!= requiredTargetSymbolCount", gate)
        self.assertIn("this.testerPreflightH1BarTimes[i]", gate)
        self.assertIn("iTime(this.symbolNames[i], PERIOD_M5, 0)", gate)
        execute = body(self.source, "void execute()")
        self.assertEqual(execute.count("this.processSymbol(i)"), 2)
        self.assertLess(execute.index("if (testerSaveGateOpened)"), execute.index("this.tryReconnectDatabaseIfDue()"))

    def test_initial_detection_precedes_all_readiness_and_analysis(self):
        self.assertLess(self.process.index("this.observeCaptureBoundary(fromIndex, currentH1BarTime)"),
                        self.process.index("this.isAnalysisSeriesReady(fromIndex)"))
        detection = body(self.source, "void observeCaptureBoundary(")
        self.assertLess(detection.index("== fromBarTime"), detection.index("GetTickCount64()"))
        self.assertIn("this.captureAnalysisAttempts[fromIndex] = 0", detection)
        self.assertNotIn("captureDetectedTicks[fromIndex] == 0", detection)

    def test_attempts_only_count_real_observation_analysis(self):
        self.assertEqual(self.source.count("this.captureAnalysisAttempts[fromIndex]++"), 1)
        self.assertRegex(self.capture, r"if \(!fromDiscard\)\s*\{\s*this.captureAnalysisAttempts\[fromIndex\]\+\+;")
        self.assertLess(self.capture.index("this.isAnalysisSeriesReady(fromIndex)"),
                        self.capture.index("this.captureAnalysisAttempts[fromIndex]++"))
        self.assertLess(self.capture.index("SymbolInfoTick(symbolName, quoteTick)"),
                        self.capture.index("this.captureAnalysisAttempts[fromIndex]++"))
        self.assertNotIn("captureAnalysisAttempts", self.drain)

    def test_same_quote_is_passed_to_analysis_and_snapshot(self):
        self.assertEqual(self.capture.count("SymbolInfoTick("), 1)
        self.assertIn("elliotAll.analyze(quoteTick)", self.capture)
        self.assertRegex(self.capture, r"this.observationProfile,\s*quoteTick,\s*captureMetrics")
        self.assertNotIn("SymbolInfoDouble", self.capture)
        self.assertIn("quoteServerTime >= targetH1BarTime + PeriodSeconds(PERIOD_M5)", self.capture)

    def test_analysis_and_capture_use_real_counters_not_market_clock(self):
        self.assertIn("GetTickCount64() - analysisStartedTick", self.capture)
        self.assertIn("captureFinishedTick - this.captureDetectedTicks[fromIndex]", self.capture)
        self.assertIn("long captureMarketTime = (long)TimeCurrent()", self.capture)
        self.assertNotIn("TimeLocal()", self.capture)
        self.assertLess(self.capture.index("ulong analysisElapsed"), self.capture.index("bool isBuilt"))
        self.assertLess(self.capture.index("bool isBuilt"), self.capture.index("ulong captureFinishedTick"))

    def test_snapshot_boundary_checked_before_enqueue(self):
        self.assertIn("beforeH1BarTime != targetH1BarTime", self.capture)
        self.assertIn("afterH1BarTime != targetH1BarTime", self.capture)
        self.assertIn("finalBarTime != targetH1BarTime", self.capture)
        self.assertLess(self.capture.index("finalBarTime != targetH1BarTime"), self.capture.index("this.snapshotQueue.Add(queueItem)"))

    def test_metrics_frozen_before_queue_and_not_recomputed_on_save(self):
        self.assertLess(self.capture.index("queueItem.snapshot.captureMetrics.captureElapsedMs"),
                        self.capture.index("this.snapshotQueue.Add(queueItem)"))
        self.assertIn("saveSnapshot(queueItem.snapshot)", self.drain)
        for forbidden in ("captureMetrics", "GetTickCount64", "SymbolInfoTick", "analyze("):
            self.assertNotIn(forbidden, self.drain)

    def test_fifo_full_checks_before_analysis_and_failure_keeps_head(self):
        self.assertLess(self.capture.index("this.snapshotQueue.Total() >= this.queueCapacity"),
                        self.capture.index("elliotAll.analyze(quoteTick)"))
        failure = self.drain.split("if (!isSaved)", 1)[1].split("bool isExistingRun", 1)[0]
        self.assertIn("this.releaseDatabase(false)", failure)
        self.assertIn("return;", failure)
        self.assertNotIn("snapshotQueue.Delete", failure)

    def test_competing_writer_and_wrong_database_stop_future_collection(self):
        execute = body(self.source, "void execute()")
        self.assertIn("this.competingWriterDetected || this.databaseRejected", execute)
        self.assertLess(execute.index("this.competingWriterDetected || this.databaseRejected"),
                        execute.index("this.processSymbol(i)"))
        database = body(self.source, "bool tryInitializeM5Database()")
        self.assertIn("this.m5DatabaseContext.isDatabaseRejected()", database)
        self.assertIn("this.databaseRejected = true", database)
        self.assertIn("this.m5DatabaseContext.saveRun(this.databaseRun)", database)
        self.assertNotIn("setDatabaseRun()", database)

    def test_m5_initial_preparation_and_empty_weekends_are_not_gaps(self):
        changed = body(self.source, "void handleBoundaryChangedDuringAnalysis(")
        self.assertLess(changed.index("this.lastCapturedH1BarTimes[fromIndex] <= 0"), changed.index("this.totalGapCount++"))
        self.assertIn("this.lastDetectedH1BarTimes[fromIndex] = fromTargetH1BarTime", changed)
        skipped = body(self.source, "int countSkippedH1Bars(")
        self.assertIn("CopyTime(", skipped)
        self.assertIn("return copiedCount - 1", skipped)

    def test_account_identity_is_checked_even_when_db_is_ready(self):
        execute = body(self.source, "void execute()")
        self.assertEqual(execute.count("this.ensureExecutionSource()"), 2)
        self.assertLess(execute.index("this.ensureExecutionSource()"), execute.index("this.processSymbol(i)"))
        self.assertLess(execute.rindex("this.ensureExecutionSource()"), execute.index("this.drainSnapshotQueue()"))
        source = body(self.source, "bool ensureExecutionSource()")
        self.assertIn("this.databaseRun.sourceLogin = sourceLogin", source)
        self.assertIn("this.databaseRun.sourceServer = sourceServer", source)
        self.assertIn("this.databaseRun.sourceLogin != sourceLogin", source)
        self.assertIn("this.releaseDatabase(false)", source)
        self.assertNotIn("sourceLogin <= 0", source)

    def test_last_successful_quality_survives_status_refresh(self):
        refresh = body(self.source, "void refreshStatus()")
        self.assertNotIn("symbolCaptureMetrics", refresh)
        status = read("Indicator/ZigZagElliot/H1ElliotObservationAllStatus.mqh")
        self.assertIn("symbolCaptureMetrics[28]", status)
        self.assertIn("symbolCaptureMetricsBarTimes[28]", status)

    def test_live_readiness_transition_does_not_count_preparation_as_gap(self):
        startup = body(self.process, "if (!this.testerMode")
        unavailable = body(startup, "if (!this.isAnalysisSeriesReady(fromIndex))")
        self.assertTrue(unavailable.rstrip().endswith("return;"))
        self.assertNotIn("lastDetectedH1BarTimes", unavailable)
        self.assertNotIn("capturePendingObservation", unavailable)
        self.assertLess(startup.index("this.isAnalysisSeriesReady(fromIndex)"),
                        startup.index("currentH1BarTime = iTime("))
        self.assertLess(startup.index("currentH1BarTime = iTime("),
                        startup.index("this.analysisReadyFlags[fromIndex] = true"))
        self.assertIn("this.lastDetectedH1BarTimes[fromIndex] = currentH1BarTime", startup)
        self.assertIn("this.pendingAnalysisH1BarTimes[fromIndex] = 0", startup)
        self.assertNotIn("handleNewBoundary", startup)
        self.assertNotIn("capturePendingObservation", startup)
        self.assertTrue(startup.rstrip().endswith("return;"))
        self.assertIn("this.handleNewBoundary(fromIndex, currentH1BarTime, countPreviousGaps)", self.process)
        boundary = body(self.source, "void handleNewBoundary(")
        self.assertIn("if (fromCountGaps && skippedBarCount > 0)", boundary)
        self.assertIn("if (fromCountGaps && pendingBarTime > 0", boundary)
        self.assertNotIn("this.analysisReadyFlags", boundary)

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_live_restart_stale_anchor_is_not_saved_or_counted_as_gap(self):
        for period in (300, 3600):
            with self.subTest(period=period):
                stale, ready_bar, next_bar = period, 19 * period, 20 * period
                result = execute_startup_scenario(self.source, period=period, steps=[
                    {"bars": [stale], "ready": False},
                    {"bars": [7 * period], "ready": False},
                    {"bars": [stale, ready_bar], "ready": True},
                    {"bars": [ready_bar], "ready": True},
                    {"bars": [next_bar], "ready": True},
                ])
                for waiting in result[:2]:
                    self.assertEqual(waiting["baseline"], 0)
                    self.assertFalse(waiting["ready"])
                    self.assertEqual(waiting["status"], "RETRY")
                for before_new_bar in result[:4]:
                    self.assertEqual(before_new_bar["captures"], [])
                    self.assertEqual(before_new_bar["gaps"], 0)
                    self.assertEqual(before_new_bar["pending"], 0)
                baseline = result[2]
                self.assertEqual(baseline["baseline"], ready_bar)
                self.assertEqual(baseline["current"], ready_bar)
                self.assertEqual(baseline["reads"], 2)
                self.assertEqual(baseline["status"], "BASE")
                self.assertEqual(baseline["trace"][0], ["detect", stale])
                self.assertEqual(baseline["trace"][1], ["readiness"])
                self.assertEqual(baseline["trace"][2], ["detect", ready_bar])
                self.assertEqual(result[4]["captures"], [next_bar])
                self.assertEqual(result[4]["gaps"], 0)
                if period == 300:
                    self.assertEqual(baseline["captureTarget"], ready_bar)
                    self.assertEqual(result[3]["captureDetectedTick"], baseline["captureDetectedTick"])

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_live_first_ready_pass_rereads_anchor_and_retries_zero(self):
        for period in (300, 3600):
            with self.subTest(period=period):
                result = execute_startup_scenario(self.source, period=period, steps=[
                    {"bars": [period, 0], "ready": True},
                    {"bars": [period, 19 * period], "ready": True},
                    {"bars": [22 * period], "ready": True},
                ])
                self.assertFalse(result[0]["ready"])
                self.assertEqual(result[0]["baseline"], 0)
                self.assertEqual(result[0]["current"], 0)
                self.assertEqual(result[0]["captures"], [])
                self.assertEqual(result[1]["baseline"], 19 * period)
                self.assertEqual(result[1]["captures"], [])
                self.assertEqual(result[1]["gaps"], 0)
                self.assertEqual(result[2]["captures"], [22 * period])
                self.assertEqual(result[2]["gaps"], 2)

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_tester_initial_retry_and_first_ready_capture_are_preserved(self):
        for period in (300, 3600):
            with self.subTest(period=period):
                result = execute_startup_scenario(self.source, period=period, tester=True, steps=[
                    {"bars": [period], "ready": False},
                    {"bars": [period], "ready": True},
                    {"bars": [2 * period], "ready": True},
                ])
                self.assertEqual(result[0]["baseline"], period)
                self.assertEqual(result[0]["captures"], [])
                self.assertEqual(result[1]["captures"], [])
                self.assertNotIn(["readiness"], result[1]["trace"])
                self.assertEqual(result[2]["captures"], [2 * period])
                self.assertEqual(result[2]["reads"], 1)
                self.assertEqual(result[2]["gaps"], 0)
                self.assertEqual(result[2]["trace"][0], ["detect", 2 * period])
                self.assertEqual(result[2]["trace"][1], ["readiness"])

    def test_collector_never_trades_or_sends_alerts(self):
        for forbidden in ("OrderSend(", "SendMail(", "SendNotification(", "Alert(", "ExpertAdvisorFactory"):
            self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main()
