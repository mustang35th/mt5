"""Source-level profile/hash and persistence wiring regression contracts.

The restricted canonical evaluator reads production getters/append calls; it is
not execution of MQL. Native validation is covered by the companion SmokeTest.
"""
import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INCLUDE = ROOT / "Include" / "Mstng"


def read(relative):
    return (INCLUDE / relative).read_text(encoding="utf-8-sig")


def canonical(m5=False):
    """Evaluate the production constant getters without eval/exec."""
    source = read("Elliot/ZigZagElliotAnalysisProfile.mqh")
    enums = dict(MODE_SMA=0, MODE_EMA=1, STO_LOWHIGH=0, PRICE_CLOSE=1,
                 PERIOD_H1=16385, PERIOD_H4=16388, PERIOD_D1=16408,
                 PERIOD_W1=32769, PERIOD_MN1=49153, PERIOD_M15=15, PERIOD_M5=5)
    overrides = dict(fromProfileVersion="ZIGZAG_ELLIOT_ANALYSIS_PROFILE_V5",
                     fromAnchorTimeFrame=16385, fromAnalysisStartTimeFrame=49153,
                     fromTimeFrameCount=5, fromTimeFrameOrderText="49153,32769,16408,16388,16385")
    if m5:
        overrides.update(fromProfileVersion="M5_OBSERVATION_PROFILE_V1",
                         fromAnchorTimeFrame=5, fromTimeFrameCount=7,
                         fromTimeFrameOrderText="49153,32769,16408,16388,16385,15,5")

    def value(expression):
        expression = re.sub(r"^\(int\)", "", expression.strip())
        if expression in overrides:
            return overrides[expression]
        if expression in enums:
            return enums[expression]
        if expression in ("true", "false"):
            return int(expression == "true")
        if expression.startswith('"'):
            return json.loads(expression)
        if re.fullmatch(r"-?\d+(?:\.\d+)?", expression):
            return float(expression) if "." in expression else int(expression)
        boolean = re.fullmatch(r"boolToInteger\((.+)\)", expression)
        if boolean:
            return int(bool(value(boolean[1])))
        getter = re.fullmatch(r"(\w+)\(\)", expression)
        if getter:
            body = re.search(r"static\s+\w+\s+" + getter[1]
                             + r"\(\)\s*\{\s*return\s+([^;]+);", source)
            if body:
                return value(body[1])
        raise AssertionError(f"Unsupported canonical expression: {expression}")

    if not m5:
        overrides.update(fromProfileVersion=value("getProfileVersion()"),
                         fromAnchorTimeFrame=value("getAnchorTimeFrame()"),
                         fromAnalysisStartTimeFrame=value("getAnalysisStartTimeFrame()"),
                         fromTimeFrameCount=value("getObservationTimeFrameCount()"))
        foot_body = source.split("static ENUM_TIMEFRAMES getObservationTimeFrame(const int fromIndex)", 1)[1]
        feet = re.findall(r"if \(fromIndex == (\d+)\) \{\s*return (PERIOD_\w+);", foot_body)
        overrides["fromTimeFrameOrderText"] = ",".join(str(enums[foot]) for _, foot in feet)
    body = source.split("string text = fromProfileVersion;", 1)[1].split("return text;", 1)[0]
    output = overrides["fromProfileVersion"]
    for kind, key, expression in re.findall(
            r'append(Integer|Text|Double)\(\s*text,\s*"([^"]+)",\s*(.*?)\);', body, re.S):
        if kind == "Double":
            expression, digits = expression.rsplit(",", 1)
            encoded = f"{value(expression):.{int(digits)}f}"
        else:
            encoded = str(value(expression))
        output += f"|{key}={encoded}"
    if m5:
        output += "|CAPTURE_PHASE=BAR_OPEN_FIRST_SUCCESS"
        output += "|SPREAD_QUOTE_RULE=SINGLE_MQL_TICK_AT_ANALYSIS_START"
    return output


class ObservationProfileContractTest(unittest.TestCase):
    def test_h1_golden_canonical_hash(self):
        self.assertEqual(hashlib.sha256(canonical().encode()).hexdigest(),
                         "a4c9b3633501890e7110a1122b370dc12787d15d12f1efae82ca7b9657c9efbf")

    def test_h1_default_delegates_to_legacy_values(self):
        analysis = read("Elliot/ZigZagElliotAnalysisProfile.mqh")
        wrapper = analysis.split("static string createCanonicalText() {", 1)[1].split("}", 1)[0]
        for getter in ("getProfileVersion", "getAnchorTimeFrame", "getAnalysisStartTimeFrame",
                       "getObservationTimeFrameCount", "getObservationTimeFrameOrderText"):
            self.assertIn(getter + "()", wrapper)
        profile = read("Elliot/ZigZagElliotObservationProfile.mqh")
        self.assertIn("fromAnchorTimeFrame = PERIOD_H1", profile)
        self.assertIn("return ZigZagElliotAnalysisProfile::createCanonicalText();", profile)

    def test_m5_has_unique_actual_contract_keys(self):
        fields = canonical(True).split("|")
        keys = [field.split("=", 1)[0] for field in fields[1:]]
        self.assertEqual(len(keys), len(set(keys)))
        for expected in ("ANCHOR_TF=5", "ANALYSIS_START_TF=49153", "TF_COUNT=7",
                         "TF_ORDER=49153,32769,16408,16388,16385,15,5"):
            self.assertIn(expected, fields)
        self.assertNotEqual(hashlib.sha256(canonical().encode()).digest(),
                            hashlib.sha256(canonical(True).encode()).digest())

    def test_profile_has_no_shared_mutable_mode(self):
        profile = read("Elliot/ZigZagElliotObservationProfile.mqh")
        self.assertIn("ENUM_TIMEFRAMES anchorTimeFrame;", profile)
        self.assertNotRegex(profile, r"static\s+ENUM_TIMEFRAMES\s+anchorTimeFrame")
        self.assertIn("return PERIOD_M15;", profile)
        self.assertIn("return PERIOD_M5;", profile)
        self.assertIn('return "M5_OBSERVATION_V1";', profile)
        self.assertNotIn("PERIOD_M30", profile)

    def test_quality_is_not_part_of_snapshot_hash(self):
        builder = read("ExpertAdvisor/ZigZagElliotObservationSnapshotBuilder.mqh")
        body = builder.split("static string createSnapshotHash(", 1)[1]
        for field in ("quoteTickTimeMsc", "captureMarketTime", "analysisElapsedMs",
                      "captureElapsedMs", "analysisAttemptCount"):
            self.assertNotIn(field, body)

    def test_first_write_exits_before_children_or_quality(self):
        service = read("Database/Service/ZigZagElliotObservationPersistenceService.mqh")
        duplicate = service.split("if (!isInserted) {", 1)[1].split("int timeFrameCount", 1)[0]
        self.assertIn("return true;", duplicate)
        self.assertNotIn("captureMetricsDao.insert", duplicate)
        self.assertNotIn("timeFrameDao.insert", duplicate)
        self.assertIn("fromObservationEntity.runId = existingRunId;", duplicate)

    def test_quality_and_children_share_transaction(self):
        service = read("Database/Service/ZigZagElliotObservationPersistenceService.mqh")
        write = service.index("this.timeFrameDao.insert(fromTimeFrameEntities[i])")
        quality = service.index("this.captureMetricsDao.insert(fromCaptureMetrics)")
        self.assertLess(write, quality)
        self.assertLess(quality, service.index("this.commitTransaction(__FUNCTION__)", quality))
        self.assertIn("this.rollbackAndClear(", service[quality:])
        self.assertIn("fromSnapshot.captureMetrics.observationId = 0;", service)

    def test_fixed_count_order_anchor_and_run_validation(self):
        service = read("Database/Service/ZigZagElliotObservationPersistenceService.mqh")
        for check in ("this.observationProfile.getAnchorTimeFrame()",
                      "this.observationProfile.getObservationTimeFrameCount()",
                      "this.observationProfile.getObservationTimeFrame(i)",
                      "entity.timeFrameOrder != i", "entity.isAnchorTimeFrame != expectedAnchorValue",
                      "this.isRunMatched(fromObservationEntity)",
                      "fromHasCaptureMetrics != this.observationProfile.requiresCaptureMetrics()"):
            self.assertIn(check, service)


if __name__ == "__main__":
    unittest.main()
