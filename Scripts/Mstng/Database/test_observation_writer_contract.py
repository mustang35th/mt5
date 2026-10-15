"""Execute production FIFO control flow with deterministic persistence doubles.

Only MQL local variable declarations are translated to JavaScript. The real
drainSnapshotQueue branch/assignment order executes in Node; SQLite persistence
and native lock ownership remain separate smoke-test responsibilities.
"""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CONTROLLER = ROOT / "Include/Mstng/Indicator/ZigZagElliot/H1ElliotObservationAllController.mqh"


def body(source, signature):
    start = source.index("{", source.index(signature)) + 1
    position, depth = start, 1
    while depth:
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    return source[start:position - 1]


def execute_drain(source, *, is_m5, save_results):
    method = re.sub(
        r"\b(?:datetime|long|bool|int|string|H1ElliotObservationQueueItem)\s+\*?([a-z]\w*)\s*=",
        r"let \1 =", body(source, "void drainSnapshotQueue()"),
    )
    harness = r"""
const scenario = JSON.parse(require('fs').readFileSync(0, 'utf8'));
globalThis.NULL = null;
globalThis.TimeLocal = () => 1000;
globalThis.TimeCurrent = () => 2000;
globalThis.StringFormat = (...args) => args.join(' ');
globalThis.__FUNCTION__ = 'drainSnapshotQueue';
const symbols = ['EURUSD', 'GBPUSD', 'USDJPY'];
const items = scenario.saveResults.map((result, index) => ({
    symbolName: symbols[index],
    anchorBarTime: 100 + index,
    retryCount: 0,
    snapshot: {observation: {runId: 0}, timeFrames: [{synthetic: true}]},
}));
const requestedRuns = [];
const overloads = [];
const releases = [];
const logs = [];
const statuses = [];
let saveIndex = 0;
const controller = {
    snapshotQueue: {
        Total: () => items.length,
        At: index => items[index],
        Delete: index => { items.splice(index, 1); },
    },
    databaseReady: true,
    databaseRun: {id: 2452},
    observationProfile: {isM5: () => scenario.isM5},
    nextDatabaseRetryTime: 0,
    databaseRetrySeconds: 30,
    symbolQueuedCounts: scenario.saveResults.map(() => 1),
    symbolRetryCounts: scenario.saveResults.map(() => 0),
    lastSavedH1BarTimes: scenario.saveResults.map(() => 0),
    totalSavedCount: 0,
    lastDatabaseSaveServerTime: 0,
    lastDatabaseMessage: '',
    competingWriterDetected: false,
    logger: {
        info: (...args) => logs.push(['INFO', ...args]),
        error: (...args) => logs.push(['ERROR', ...args]),
    },
    findSymbolIndex: symbol => symbols.indexOf(symbol),
    formatDateTime: value => String(value),
    setSymbolStatus: (index, code, message) => statuses.push({index, code, message}),
    releaseDatabase(clearRun) {
        releases.push(clearRun);
        this.databaseReady = false;
    },
    observationPersistenceService: {
        saveSnapshot(...args) {
            const observation = scenario.isM5 ? args[0].observation : args[0];
            requestedRuns.push(observation.runId);
            overloads.push(args.length);
            const outcome = scenario.saveResults[saveIndex++];
            if (outcome === false) return false;
            observation.runId = outcome;
            return true;
        },
    },
};
new Function(scenario.method).call(controller);
process.stdout.write(JSON.stringify({
    remaining: items,
    requestedRuns,
    overloads,
    releases,
    logs,
    statuses,
    queued: controller.symbolQueuedCounts,
    retries: controller.symbolRetryCounts,
    savedBars: controller.lastSavedH1BarTimes,
    savedCount: controller.totalSavedCount,
    lastSave: controller.lastDatabaseSaveServerTime,
    databaseReady: controller.databaseReady,
    nextRetry: controller.nextDatabaseRetryTime,
    message: controller.lastDatabaseMessage,
    competing: controller.competingWriterDetected,
}));
"""
    completed = subprocess.run(
        [shutil.which("node"), "-e", harness],
        input=json.dumps({"method": method, "isM5": is_m5, "saveResults": save_results}),
        text=True, encoding="utf-8", capture_output=True, timeout=10, check=True,
    )
    return json.loads(completed.stdout)


class ObservationWriterContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CONTROLLER.read_text(encoding="utf-8-sig")

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_previous_run_snapshot_does_not_block_following_new_snapshots(self):
        for is_m5 in (False, True):
            with self.subTest(is_m5=is_m5):
                result = execute_drain(self.source, is_m5=is_m5, save_results=[2279, 2452, 2452])
                self.assertEqual(result["remaining"], [])
                self.assertEqual(result["requestedRuns"], [2452, 2452, 2452])
                self.assertEqual(result["overloads"], [1 if is_m5 else 2] * 3)
                self.assertEqual(result["savedCount"], 3)
                self.assertEqual(result["queued"], [0, 0, 0])
                self.assertEqual(result["savedBars"], [100, 101, 102])
                self.assertEqual(result["retries"], [0, 0, 0])
                self.assertFalse(result["competing"])
                self.assertTrue(result["databaseReady"])
                self.assertEqual(result["releases"], [])
                self.assertEqual(result["statuses"][0], {
                    "index": 0, "code": "OK", "message": "既存の観測を保持（保存済み）",
                })
                self.assertEqual([status["message"] for status in result["statuses"][1:]],
                                 ["DB保存完了", "DB保存完了"])
                self.assertEqual(len(result["logs"]), 1)
                self.assertEqual(result["logs"][0][0], "INFO")
                self.assertIn("2452 2279", result["logs"][0][-1])

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_same_run_snapshots_drain_without_existing_run_message(self):
        for is_m5 in (False, True):
            with self.subTest(is_m5=is_m5):
                result = execute_drain(self.source, is_m5=is_m5, save_results=[2452, 2452])
                self.assertEqual(result["remaining"], [])
                self.assertEqual(result["savedCount"], 2)
                self.assertEqual(result["savedBars"], [100, 101])
                self.assertEqual(result["queued"], [0, 0])
                self.assertEqual(result["nextRetry"], 0)
                self.assertEqual(result["lastSave"], 2000)
                self.assertFalse(result["competing"])
                self.assertEqual(result["logs"], [])
                self.assertEqual([status["message"] for status in result["statuses"]],
                                 ["DB保存完了", "DB保存完了"])

    @unittest.skipUnless(shutil.which("node"), "Node.js is required for extracted MQL control flow")
    def test_failed_save_keeps_fifo_head_and_schedules_reconnect(self):
        for is_m5 in (False, True):
            with self.subTest(is_m5=is_m5):
                result = execute_drain(self.source, is_m5=is_m5, save_results=[False, 2452])
                self.assertEqual(len(result["remaining"]), 2)
                self.assertEqual(result["remaining"][0]["symbolName"], "EURUSD")
                self.assertEqual(result["remaining"][0]["retryCount"], 1)
                self.assertEqual(result["remaining"][1]["retryCount"], 0)
                self.assertEqual(result["requestedRuns"], [2452])
                self.assertEqual(result["savedCount"], 0)
                self.assertEqual(result["queued"], [1, 1])
                self.assertEqual(result["retries"], [1, 0])
                self.assertEqual(result["savedBars"], [0, 0])
                self.assertEqual(result["releases"], [False])
                self.assertFalse(result["databaseReady"])
                self.assertFalse(result["competing"])
                self.assertEqual(result["nextRetry"], 1030)
                self.assertEqual(result["message"], "DB保存失敗、再接続待ち")

    def test_writer_lock_is_acquired_after_source_check_before_analysis(self):
        execute = body(self.source, "void execute()")
        self.assertLess(execute.index("this.ensureExecutionSource()"),
                        execute.index("this.ensureWriterLock()"))
        self.assertLess(execute.index("this.ensureWriterLock()"),
                        execute.index("this.processSymbol(i)"))
        failed = body(execute, "if (!this.ensureWriterLock())")
        self.assertIn("this.refreshStatus()", failed)
        self.assertIn("this.logM5TesterProgress()", failed)
        self.assertTrue(failed.rstrip().endswith("return;"))
        self.assertNotIn("this.processSymbol", failed)
        self.assertLess(execute.index("this.ensureWriterLock()"),
                        execute.index("this.tryReconnectDatabaseIfDue()"))
        self.assertLess(execute.index("this.ensureWriterLock()"),
                        execute.index("this.drainSnapshotQueue()"))

    def test_held_writer_lock_is_reused_and_acquisition_failure_stops_collection(self):
        acquire = body(self.source, "bool ensureWriterLock()")
        held = body(acquire, "if (this.writerLock.isHeld())")
        self.assertEqual(held.strip(), "return true;")
        for argument in ("this.databaseFileName", "this.databaseUseCommonFolder",
                         "this.databaseRun.sourceMode", "this.getAnchorTimeFrameText()"):
            self.assertIn(argument, acquire)
        self.assertLess(acquire.index("this.writerLock.acquire("),
                        acquire.index("this.competingWriterDetected = true"))
        self.assertTrue(acquire.rstrip().endswith("return false;"))
        drain = body(self.source, "void drainSnapshotQueue()")
        self.assertNotIn("this.competingWriterDetected = true", drain)

    def test_database_reconnect_keeps_lock_and_destroy_releases_it(self):
        release = body(self.source, "void releaseDatabase(")
        self.assertNotIn("writerLock", release)
        reconnect = body(self.source, "bool tryInitializeDatabase()")
        self.assertIn("this.releaseDatabase(false)", reconnect)
        self.assertNotIn("this.writerLock.release()", reconnect)
        destroy = body(self.source, "void destroy()")
        self.assertEqual(destroy.count("this.writerLock.release()"), 1)
        self.assertLess(destroy.index("this.releaseDatabase(false)"),
                        destroy.index("this.writerLock.release()"))


if __name__ == "__main__":
    unittest.main()
