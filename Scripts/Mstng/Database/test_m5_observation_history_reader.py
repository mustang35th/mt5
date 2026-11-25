"""Run production M5-history queries, validation and text formatting on fixtures.

MQL methods run through a small C# syntax adapter; SQL queries then execute
against the writer's actual table definitions in disposable SQLite databases.
This does not execute MT5's database API, object drawing, or live data.
"""

import json
from functools import lru_cache
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/ExpertAdvisor"))
from test_h1_ea_tester_warmup_contract import block_end, code_only, method
from test_m5_observation_guard_contract import schema_statements
from test_m5_observation_price_movement_storage import migrate


READER = ROOT / "Include/Mstng/Database/Query/ZigZagElliotM5ObservationHistoryReader.mqh"
RUNS = "zigzag_elliot_alert_runs"
OBS = "zigzag_elliot_observations"
FRAMES = "zigzag_elliot_observation_timeframes"
METRICS = "zigzag_elliot_observation_capture_metrics"
FRAME_IDS = (49153, 32769, 16408, 16388, 16385, 15, 5)
BASE_TIME = 1_795_500_000
DETAIL_COLUMNS = (
    "is_ema200_buy", "is_ema200_sell", "is_price_movement_valid",
    "price_movement_level", "price_movement_activity_ratio",
    "latest_point_org_elliot_index", "previous_motive_sub_elliot_index",
    "latest_point_pips_diff", "latest_point_fibonacci_percent",
    "latest_point_fibonacci_expansion_percent", "latest_point_jst_time",
)


def create_database():
    connection = sqlite3.connect(":memory:")
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    for statement in schema_statements():
        connection.execute(statement)
    return connection


def insert(connection, table, **changes):
    values = {
        row[1]: ("" if row[2] == "TEXT" else 0)
        for row in connection.execute(f"PRAGMA table_info({table})")
        if row[3] and row[4] is None and not row[5]
    }
    values.update(changes)
    cursor = connection.execute(
        f"INSERT INTO {table} ({','.join(values)}) VALUES ({','.join('?' for _ in values)})",
        tuple(values.values()),
    )
    return cursor.lastrowid


def add_run(connection, identifier=1, **changes):
    values = dict(
        id=identifier, run_uid=f"history-{identifier}", schema_version=1,
        source_mode="LIVE", source_server="Fixture-Server",
        strategy="M5_OBSERVATION_ALL", strategy_version="M5_OBSERVATION_ALL_V1",
        analysis_version="ELLIOT_MN1_V6", analysis_input_hash=f"hash-{identifier}",
        analysis_input_text="M5_OBSERVATION_PROFILE_V1|fixture",
    )
    values.update(changes)
    return insert(connection, RUNS, **values)


def add_observation(connection, run=1, bar=BASE_TIME, symbol="EURUSD", capture=None, **changes):
    source = connection.execute(f"SELECT * FROM {RUNS} WHERE id=?", (run,)).fetchone()
    values = dict(
        run_id=run, source_mode=source["source_mode"], source_server=source["source_server"],
        symbol_name=symbol, anchor_time_frame=5, anchor_time_frame_text="M5",
        anchor_bar_time=bar, anchor_jst_time=bar + 7 * 3600,
        capture_phase="BAR_OPEN_FIRST_SUCCESS", time_frame_count=7,
        analysis_version=source["analysis_version"], analysis_input_hash=source["analysis_input_hash"],
        snapshot_hash=f"snapshot-{run}-{bar}-{symbol}",
    )
    values.update(changes)
    identifier = insert(connection, OBS, **values)
    for index, frame in enumerate(FRAME_IDS):
        insert(
            connection, FRAMES, observation_id=identifier, time_frame=frame,
            time_frame_text=("MN1", "W1", "D1", "H4", "H1", "M15", "M5")[index],
            time_frame_order=index, is_anchor_time_frame=int(frame == 5),
            is_buy=1, is_wave_uptrend=0, is_wave_confirmed=1, point_count=1,
            latest_elliot_index=3, latest_elliot_label="3", latest_sub_elliot_index=1,
            latest_sub_elliot_label="i", latest_point_time=bar - 300,
            latest_point_jst_time=bar - 300 + 7 * 3600, latest_point_rate=1.23456,
            latest_point_is_added=0, latest_point_org_elliot_label="1",
        )
    if capture is not None:
        insert(connection, METRICS, observation_id=identifier, capture_market_time=capture)
    return identifier


def column_names(connection, table):
    return "," + "".join(row[1] + "," for row in connection.execute(f"PRAGMA table_info({table})"))


def extracted_methods(source, names):
    """Keep builder/formatter branches; adapt only MQL parameter/array syntax."""
    result = []
    for name in names:
        signature = re.search(r"\b(static\s+)?(string|bool|color|int|void)\s+" + name + r"\s*\(([^)]*)\)\s*\{", source)
        if signature is None:
            raise AssertionError(f"Missing method: {name}")
        parameters = re.sub(r"\bconst\s+|&", "", signature[3])
        parameters = re.sub(r"\bdatetime\b", "long", parameters)
        parameters = re.sub(r"\b(\w+)\s+(\w+)\[\]", r"\1[] \2", parameters)
        opening = signature.end() - 1
        body = source[opening + 1:block_end(code_only(source), opening)]
        body = re.sub(r"\bstring\s+(\w+)\[\]\s*=\s*\{", r"string[] \1 = new string[] {", body)
        body = re.sub(r"\bstring\s+(\w+)\[\]\s*;", r"string[] \1;", body)
        body = re.sub(r"StringSplit\(([^,]+),\s*('[^']'),\s*(\w+)\)", r"StringSplit(\1, \2, out \3)", body)
        body = re.sub(r"\bdatetime\b", "long", body)
        body = re.sub(r"\bcolor\b", "int", body)
        body = body.replace("::", ".")
        body = re.sub(r"\b(CurrencyStrengthPairRankPoint)\s+(\w+)\s*;", r"\1 \2 = new \1();", body)
        result_type = "int" if signature[2] == "color" else signature[2]
        result.append("public " + (signature[1] or "") + result_type + " " + name + "(" + parameters + ") {" + body + "}")
    return "\n".join(result)


def run_csharp(source, script, payload=None):
    powershell = shutil.which("powershell.exe")
    if powershell is None:
        raise unittest.SkipTest("C# source adapter requires Windows PowerShell Add-Type")
    with tempfile.TemporaryDirectory(prefix="m5-history-test-") as directory:
        path = Path(directory)
        (path / "fixture.cs").write_text(source, encoding="utf-8-sig")
        (path / "input.json").write_text(json.dumps(payload), encoding="utf-8-sig")
        (path / "run.ps1").write_text(
            "$ErrorActionPreference = 'Stop'\n"
            "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)\n"
            "Add-Type -Path (Join-Path $PSScriptRoot 'fixture.cs')\n" + script,
            encoding="utf-8-sig",
        )
        completed = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(path / "run.ps1")],
            capture_output=True, encoding="utf-8", errors="replace", timeout=30,
        )
    if completed.returncode:
        raise AssertionError(completed.stdout + completed.stderr)
    return completed.stdout


def struct_fixture(source, name, reset="clear"):
    """Keep production scalar/nested DTO fields and unknown-value defaults."""
    opening = re.search(r"\bstruct " + name + r"\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    fields = re.findall(r"^\s*(\w+)\s+(\w+);", body, re.M)
    result = "public class " + name + " { const int PERIOD_CURRENT=0;\n"
    for kind, field in fields:
        adapted = "long" if kind == "datetime" else kind
        initial = ""
        if kind == "string":
            initial = '=""'
        elif kind not in ("int", "long", "bool", "datetime", "double"):
            initial = "=new " + kind + "()"
        result += f"public {adapted} {field}{initial};\n"
    result += f"public {name}() {{ {reset}(); }}\npublic void {reset}() {{"
    result += method(body, reset) + "\n} }\n"
    return result


def frame_fixture():
    source = READER.with_name("ZigZagElliotM5ObservationHistoryData.mqh").read_text(encoding="utf-8-sig")
    return struct_fixture(source, "M5ObservationHistoryFrame")


def strength_fixture():
    source = READER.with_name("ZigZagElliotM5ObservationHistoryData.mqh").read_text(encoding="utf-8-sig")
    return "".join(struct_fixture(source, name) for name in (
        "M5ObservationHistoryStrengthPeriod", "M5ObservationHistoryStrength",
    ))


def reader_value_methods(source):
    """Keep validation branches; adapt references and stub only the MT5 column API."""
    names = ("readFrameDetails", "readOptionalFlag", "readOptionalInteger", "readOptionalDouble",
             "readFlag", "readLongValue", "readDoubleValue", "readOptionalTime", "readTimeValue")
    references = {"DatabaseColumnLong": [2], "DatabaseColumnDouble": [2]}
    signatures = {}
    for name in names:
        parameters = re.search(r"bool " + name + r"\(([^)]*)\)", source)[1].split(",")
        references[name] = [index for index, value in enumerate(parameters)
                            if re.search(r"\b(int|bool|string|datetime|double|long)\s*&", value)]
        signatures[name] = re.sub(r"\bconst\s+", "", ",".join(parameters))
        signatures[name] = re.sub(r"\b(int|bool|string|datetime|double|long)\s*&\s*(\w+)",
                                  r"ref \1 \2", signatures[name]).replace("&", "")
    result = []
    for name in names:
        body = method(source, name)
        for called, indexes in references.items():
            def add_refs(match):
                args = match[1].split(",")
                return called + "(" + ",".join(("ref " if index in indexes else "") + value.strip()
                                                 for index, value in enumerate(args)) + ")"
            body = re.sub(r"\b" + called + r"\(([^()]*)\)", add_refs, body)
        adapted = "public bool " + name + "(" + signatures[name] + ") {" + body + "}"
        adapted = re.sub(r"\bdatetime\b", "long", adapted)
        result.append(adapted.replace("ENUM_DATABASE_FIELD_TYPE", "int"))
    return "\n".join(result)


@lru_cache(maxsize=8)
def production_queries(observation_columns, frame_columns, metrics_columns):
    source = READER.read_text(encoding="utf-8-sig")
    adapted = "using System; public class QueryBuilder {\n"
    adapted += "public static int StringFind(string value,string part) { return value.IndexOf(part,StringComparison.Ordinal); }\n"
    adapted += "public static int StringSplit(string value,char separator,out string[] result) { result=value.Split(separator);return result.Length; }\n"
    adapted += extracted_methods(source, ("hasColumns", "optionalColumn", "captureExpression", "metricsCountExpression", "buildRunSql", "buildRecordsSql"))
    adapted += "\n}"
    script = (
        "$inputData = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'input.json') | ConvertFrom-Json\n"
        "$builder = New-Object QueryBuilder\n"
        "@{ run = $builder.buildRunSql($inputData.metrics); records = $builder.buildRecordsSql($inputData.observations, $inputData.frames, $inputData.metrics) } | ConvertTo-Json -Compress\n"
    )
    return json.loads(run_csharp(adapted, script, dict(observations=observation_columns, frames=frame_columns, metrics=metrics_columns)))


class M5ObservationHistorySqlTests(unittest.TestCase):
    def setUp(self):
        self.database = create_database()
        self.addCleanup(self.database.close)
        add_run(self.database)

    def queries(self):
        return production_queries(*(column_names(self.database, table) for table in (OBS, FRAMES, METRICS)))

    def resolve_run(self, requested=0, symbol="EURUSD", mode="LIVE", server="Fixture-Server", known=BASE_TIME + 10000):
        row = self.database.execute(self.queries()["run"], (symbol, mode, server, requested, known)).fetchone()
        return row[0] if row else None

    def rows(self, run=1, start=BASE_TIME, end=BASE_TIME + 300, known=BASE_TIME + 10000,
             symbol="EURUSD", mode="LIVE", server="Fixture-Server"):
        return self.database.execute(self.queries()["records"], (run, symbol, mode, server, start, end, known)).fetchall()

    def test_seven_saved_frames_keep_wave_direction_separate_from_analysis(self):
        identifier = add_observation(self.database, capture=BASE_TIME + 2)
        rows = self.rows()
        self.assertEqual(len(rows), 7)
        self.assertEqual({row[0] for row in rows}, {identifier})
        self.assertEqual([row[7] for row in rows], list(FRAME_IDS))
        self.assertEqual([row[8] for row in rows], list(range(7)))
        self.assertEqual(tuple(rows[-1][9:19]), ("3", 1, "i", "1", 0, 1, 1, 0, BASE_TIME - 300, 1.23456))
        self.assertEqual(rows[0][2:5], (BASE_TIME, BASE_TIME + 7 * 3600, BASE_TIME + 2))

    def test_latest_run_is_not_selected_from_visible_period(self):
        add_observation(self.database)
        add_run(self.database, 2)
        add_observation(self.database, run=2, bar=BASE_TIME + 300)
        self.assertEqual(self.resolve_run(), 2)
        self.assertEqual(self.rows(run=2), [])
        self.assertEqual(self.resolve_run(requested=1), 1)
        self.assertEqual(len(self.rows(run=1)), 7)

    def test_chart_detail_columns_preserve_saved_values(self):
        migrate(self.database)
        add_observation(self.database)
        values = (0, 1, 1, 3, 1.375, 2, 3, -12.5, 61.8, 161.8, BASE_TIME + 24900)
        self.database.execute(
            f"UPDATE {FRAMES} SET " + ",".join(name + "=?" for name in DETAIL_COLUMNS), values,
        )
        rows = self.rows()
        self.assertEqual(len(rows), 7)
        for row in rows:
            self.assertEqual(tuple(row[25:36]), values)
            self.assertEqual(tuple(row[13:15]), (0, 1))

    def test_chart_detail_zero_values_are_distinct_from_missing_values(self):
        migrate(self.database)
        add_observation(self.database)
        # Zero means NONE/no preceding subwave/a measured zero, not NULL.
        self.database.execute(
            f"UPDATE {FRAMES} SET latest_point_org_elliot_index=0,previous_motive_sub_elliot_index=0,"
            "latest_point_pips_diff=0,latest_point_fibonacci_percent=0,"
            "latest_point_fibonacci_expansion_percent=0",
        )
        row = self.rows()[0]
        self.assertEqual(tuple(row[25:35]), (0,) * 10)
        self.database.execute(
            f"UPDATE {FRAMES} SET latest_point_org_elliot_index=NULL,"
            "latest_point_pips_diff=NULL,latest_point_fibonacci_percent=NULL,"
            "latest_point_fibonacci_expansion_percent=NULL",
        )
        row = self.rows()[0]
        self.assertIsNone(row[30])
        self.assertEqual(tuple(row[32:35]), (None,) * 3)

    def test_explicit_missing_run_never_falls_back(self):
        add_observation(self.database)
        self.assertIsNone(self.resolve_run(requested=999))
        self.assertEqual(self.rows(run=999), [])

    def test_run_selection_ignores_empty_future_or_incompatible_runs(self):
        add_observation(self.database)
        add_run(self.database, 2)
        add_run(self.database, 3)
        add_observation(self.database, run=3, bar=BASE_TIME + 300)
        add_run(self.database, 4, strategy="MTF_3in3")
        add_observation(self.database, run=4)
        add_run(self.database, 5, strategy_version="M5_OBSERVATION_ALL_V999")
        add_observation(self.database, run=5)
        add_run(self.database, 6, analysis_input_text="M5_OBSERVATION_PROFILE_V9|fixture")
        add_observation(self.database, run=6)
        add_run(self.database, 7, schema_version=2)
        add_observation(self.database, run=7)
        self.assertEqual(self.resolve_run(known=BASE_TIME), 1)
        self.assertEqual(self.resolve_run(known=BASE_TIME + 300), 3)

    def test_symbol_mode_and_server_are_exact_bound_parameters(self):
        symbol = "EUR'USD.m"
        add_observation(self.database, symbol=symbol)
        self.assertEqual(self.resolve_run(symbol=symbol), 1)
        self.assertEqual(len(self.rows(symbol=symbol)), 7)
        for overrides in (dict(symbol="EURUSD"), dict(symbol="EUR'USD"), dict(mode="TESTER"), dict(server="Other-Server")):
            with self.subTest(overrides=overrides):
                filters = dict(symbol=symbol) | overrides
                self.assertIsNone(self.resolve_run(**filters))
                self.assertEqual(self.rows(**filters), [])

    def test_capture_time_is_distinct_and_future_values_are_not_visible(self):
        add_observation(self.database, capture=BASE_TIME + 12)
        self.assertIsNone(self.resolve_run(known=BASE_TIME + 11))
        self.assertEqual(self.rows(known=BASE_TIME + 11), [])
        self.assertEqual(self.resolve_run(known=BASE_TIME + 12), 1)
        self.assertEqual(len(self.rows(known=BASE_TIME + 12)), 7)

    def test_half_open_range_and_known_bar_boundary(self):
        ids = [add_observation(self.database, bar=BASE_TIME + offset) for offset in (0, 300, 600)]
        self.assertEqual({row[0] for row in self.rows(end=BASE_TIME + 600)}, set(ids[:2]))
        self.assertEqual({row[0] for row in self.rows(start=BASE_TIME + 300, end=BASE_TIME + 900, known=BASE_TIME + 599)}, {ids[1]})

    def test_missing_metrics_or_metric_row_remains_unknown(self):
        add_observation(self.database)
        self.assertEqual(self.resolve_run(known=BASE_TIME), 1)
        self.assertIsNone(self.rows()[0][4])
        self.database.execute(f"DROP TABLE {METRICS}")
        self.assertEqual(self.resolve_run(known=BASE_TIME), 1)
        self.assertIsNone(self.rows()[0][4])

    def test_old_optional_columns_are_projected_as_null(self):
        add_observation(self.database)
        # Rebuild only these disposable fixtures to mimic old compatible readers.
        self.database.commit()
        self.database.execute("PRAGMA foreign_keys=OFF")
        self.database.execute(f"DROP INDEX IF EXISTS idx_zigzag_elliot_observations_anchor_jst_time")
        for table, omitted in ((OBS, {"anchor_jst_time", "anchor_jst_time_text"}),
                               (FRAMES, {"latest_point_org_elliot_label", "latest_point_is_added"}
                                | set(DETAIL_COLUMNS))):
            names = [row[1] for row in self.database.execute(f"PRAGMA table_info({table})") if row[1] not in omitted]
            self.database.execute(f"CREATE TABLE old_copy AS SELECT {','.join(names)} FROM {table}")
            self.database.execute(f"DROP TABLE {table}")
            self.database.execute(f"ALTER TABLE old_copy RENAME TO {table}")
        rows = self.rows()
        self.assertEqual(len(rows), 7)
        self.assertIsNone(rows[0][3])
        self.assertIsNone(rows[0][12])
        self.assertIsNone(rows[0][16])
        self.assertEqual(tuple(rows[0][25:36]), (None,) * 11)

    def test_missing_child_rows_preserve_parent_for_explicit_unrecorded_display(self):
        identifier = add_observation(self.database)
        self.database.execute(f"DELETE FROM {FRAMES} WHERE observation_id=? AND time_frame=15", (identifier,))
        rows = self.rows()
        self.assertEqual(len(rows), 6)
        self.assertEqual({row[0] for row in rows}, {identifier})
        self.database.execute(f"DELETE FROM {FRAMES}")
        rows = self.rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][0], identifier)
        self.assertIsNone(rows[0][6])

    def test_reader_receives_extra_parent_for_explicit_limit_detection(self):
        for index in range(2002):
            add_observation(self.database, bar=BASE_TIME + index * 300)
        rows = self.rows(end=BASE_TIME + 2002 * 300, known=BASE_TIME + 2002 * 300)
        self.assertEqual(len({row[0] for row in rows}), 2001)
        self.assertEqual(len(rows), 2001 * 7)


DRAWER = ROOT / "Include/Mstng/Draw/DrawZigZagElliotM5Observations.mqh"
DISPLAY = ROOT / "Include/Mstng/Indicator/ZigZagElliot/M5ObservationDisplayController.mqh"


class M5ObservationDetailValueTests(unittest.TestCase):
    def test_strength_history_joins_exact_m5_and_compares_only_valid_previous_source(self):
        point_source = (ROOT / "Include/Mstng/Strength/CurrencyStrengthPairRankPoint.mqh").read_text(encoding="utf-8-sig")
        evaluator_source = (ROOT / "Include/Mstng/Strength/CurrencyStrengthRankDeltaEvaluator.mqh").read_text(encoding="utf-8-sig")
        adapted = "using System;\n" + strength_fixture()
        adapted += struct_fixture(point_source, "CurrencyStrengthPairRankPoint", "reset")
        adapted += "public class CurrencyStrengthRankDeltaEvaluator {\n"
        adapted += "static int ArraySize<T>(T[] values) { return values.Length; }\n"
        adapted += extracted_methods(evaluator_source, ("findIndex",)) + "}\n"
        adapted += r'''
public class StrengthJoinFixture {
    const long Bar=1795500000;
    static int checks;
    static void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    static CurrencyStrengthPairRankPoint Point(long time,long run,int baseLong,int quoteLong,int baseShort,int quoteShort) {
        return new CurrencyStrengthPairRankPoint {
            m5BarTime=time,runId=run,updatedAt=123456,sourceMode="LIVE",
            baseLongMediumTermAverageRank=baseLong,quoteLongMediumTermAverageRank=quoteLong,
            baseMediumShortTermAverageRank=baseShort,quoteMediumShortTermAverageRank=quoteShort
        };
    }
    public static string Run() {
        CurrencyStrengthPairRankPoint[] points={Point(Bar-600,10,7,2,6,3),Point(Bar-300,11,3,7,1,6),Point(Bar,12,2,7,3,6),Point(Bar+300,13,1,8,1,8)};
        M5ObservationHistoryStrength strength=new M5ObservationHistoryStrength();
        strength.enabled=true;strength.baseCurrency="USD";strength.quoteCurrency="JPY";strength.weightLabel="加重";
        applyStrengthPoint(points,0,Bar,strength);
        Check(strength.status=="取得済み" && strength.runId==12 && strength.barTime==Bar,"exact M5 and independent strength Run selected");
        Check(strength.updatedAt==123456 && strength.sourceMode=="LIVE","source metadata preserved");
        Check(strength.longMedium.valid && strength.longMedium.baseRank==2 && strength.longMedium.quoteRank==7,"saved long-medium ranks retained");
        Check(strength.longMedium.gap==5 && strength.longMedium.comparable && strength.longMedium.delta==1,"long-medium uses exact previous M5");
        Check(strength.mediumShort.gap==3 && strength.mediumShort.comparable && strength.mediumShort.delta==-2,"medium-short has independent ranks and delta");
        applyStrengthPoint(points,0,Bar+600,strength);
        Check(strength.status=="未記録" && !strength.longMedium.valid && !strength.mediumShort.valid,"missing M5 never filled with neighboring ranks");
        Check(strength.runId==0 && strength.sourceMode=="" && strength.barTime==0 && strength.updatedAt==0,"failed join clears previous source metadata");
        Check(strength.enabled && strength.baseCurrency=="USD" && strength.quoteCurrency=="JPY" && strength.weightLabel=="加重","display configuration survives join reset");
        applyStrengthPoint(points,0,Bar+1,strength);
        Check(!strength.longMedium.valid,"non-M5 timestamp not rounded into data");
        applyStrengthPoint(points,2,Bar,strength);
        Check(strength.longMedium.valid && !strength.longMedium.comparable,"pruned previous M5 not reused");
        CurrencyStrengthPairRankPoint[] missingPrevious={points[0],points[2],points[3]};
        applyStrengthPoint(missingPrevious,0,Bar,strength);
        Check(strength.longMedium.valid && !strength.longMedium.comparable && strength.longMedium.delta==0,"600-second gap not treated as previous M5");
        points[1].sourceMode="TESTER";
        applyStrengthPoint(points,0,Bar,strength);
        Check(strength.sourceMode=="LIVE" && !strength.longMedium.comparable && !strength.mediumShort.comparable,"LIVE and TESTER never compared across boundary");
        points[2].sourceMode="TESTER";
        applyStrengthPoint(points,0,Bar,strength);
        Check(strength.sourceMode=="TESTER" && strength.longMedium.comparable,"matching TESTER history allowed");
        points[2].baseLongMediumTermAverageRank=0;
        applyStrengthPoint(points,0,Bar,strength);
        Check(!strength.longMedium.valid && strength.mediumShort.valid && strength.status=="取得済み","one missing period does not hide the other");
        points[2].baseLongMediumTermAverageRank=9;
        applyStrengthPoint(points,0,Bar,strength);
        Check(!strength.longMedium.valid && strength.longMedium.baseRank==0 && !strength.longMedium.comparable,"out-of-range rank not displayed as strength");
        points[2].baseLongMediumTermAverageRank=4;points[2].quoteLongMediumTermAverageRank=4;
        points[1].baseLongMediumTermAverageRank=4;points[1].quoteLongMediumTermAverageRank=4;
        applyStrengthPoint(points,0,Bar,strength);
        Check(strength.longMedium.valid && strength.longMedium.gap==0 && strength.longMedium.comparable && strength.longMedium.delta==0,"recorded zero gap and zero delta distinct from missing");
        points[1].quoteLongMediumTermAverageRank=9;
        applyStrengthPoint(points,0,Bar,strength);
        Check(strength.longMedium.valid && !strength.longMedium.comparable && strength.mediumShort.comparable,"invalid previous rank disables only its period comparison");
        points[2].runId=0;
        applyStrengthPoint(points,0,Bar,strength);
        Check(!strength.longMedium.valid && !strength.mediumShort.valid && strength.status=="未記録","unrecorded strength Run rejected");
        points[2].runId=12;points[2].sourceMode="UNKNOWN";
        applyStrengthPoint(points,0,Bar,strength);
        Check(!strength.longMedium.valid && strength.sourceMode=="","unknown source mode rejected");
        applyStrengthPoint(new CurrencyStrengthPairRankPoint[0],0,Bar,strength);
        Check(strength.status=="未記録" && !strength.longMedium.valid,"empty history remains explicit");
        return "PASS "+checks+" strength join assertions";
    }
'''
        adapted += extracted_methods(DISPLAY.read_text(encoding="utf-8-sig"), (
            "applyStrengthPoint", "fillStrengthPeriod",
        )) + "\n}"
        output = run_csharp(adapted, "[StrengthJoinFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ strength join assertions")

    def test_production_reader_distinguishes_missing_zero_and_invalid_fields(self):
        adapted = "using System;\n" + frame_fixture() + r'''
public class DetailReaderFixture {
    const int DATABASE_FIELD_TYPE_NULL=0,DATABASE_FIELD_TYPE_INTEGER=1,DATABASE_FIELD_TYPE_FLOAT=2,DATABASE_FIELD_TYPE_TEXT=3;
    const int INT_MAX=int.MaxValue;
    object[] columns=new object[36];
    int checks;
    int DatabaseColumnType(int request,int column) {
        object value=columns[column];
        if(value==null) return DATABASE_FIELD_TYPE_NULL;
        if(value is long || value is int) return DATABASE_FIELD_TYPE_INTEGER;
        if(value is double) return DATABASE_FIELD_TYPE_FLOAT;
        return DATABASE_FIELD_TYPE_TEXT;
    }
    bool DatabaseColumnLong(int request,int column,ref long value) { value=Convert.ToInt64(columns[column]);return true; }
    bool DatabaseColumnDouble(int request,int column,ref double value) { value=Convert.ToDouble(columns[column]);return true; }
    bool MathIsValidNumber(double value) { return !Double.IsNaN(value) && !Double.IsInfinity(value); }
    void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    void ZeroColumns() { for(int i=25;i<36;i++) columns[i]=0L; }
    public string Run() {
        string error="";
        M5ObservationHistoryFrame frame=new M5ObservationHistoryFrame();
        Check(readFrameDetails(0,frame,ref error),"missing columns accepted");
        Check(frame.isEma200Buy==-1 && frame.isEma200Sell==-1,"missing EMA flags");
        Check(frame.isPriceMovementValid==-1 && frame.priceMovementLevel==-1,"missing movement flags");
        Check(frame.originalWaveIndex==-1 && frame.previousMotiveSubElliotIndex==-1,"missing wave indexes");
        Check(!frame.hasPriceMovementActivityRatio && !frame.hasPointPipsDiff && !frame.hasPointFibonacciPercent && !frame.hasPointFibonacciExpansionPercent,"missing numbers");
        Check(frame.pointJstTime==0,"missing JST remains unknown");
        ZeroColumns();frame=new M5ObservationHistoryFrame();
        Check(readFrameDetails(0,frame,ref error),"recorded zero accepted");
        Check(frame.isEma200Buy==0 && frame.isEma200Sell==0 && frame.originalWaveIndex==0 && frame.previousMotiveSubElliotIndex==0,"zero flags are not missing");
        Check(frame.hasPriceMovementActivityRatio && frame.hasPointPipsDiff && frame.hasPointFibonacciPercent && frame.hasPointFibonacciExpansionPercent,"zero numbers have values");
        columns[31]=3L;columns[32]=-12.5;columns[33]=-2.5;columns[34]=161.8;columns[35]=1795524900L;
        Check(readFrameDetails(0,frame,ref error),"signed recorded values accepted");
        Check(frame.pointPipsDiff==-12.5 && frame.pointFibonacciPercent==-2.5 && frame.pointJstTime==1795524900L,"recorded values preserved");
        int[] invalidColumns={25,26,27,28,29,29,29,30,30,31,32,33,34,35,35};
        object[] invalidValues={2L,"1",1.0,4L,-0.1,Double.NaN,Double.PositiveInfinity,2147483648L,-1L,2L,"12.5",Double.NaN,Double.NegativeInfinity,-1L,"123"};
        for(int i=0;i<invalidColumns.Length;i++) {
            ZeroColumns();columns[invalidColumns[i]]=invalidValues[i];frame=new M5ObservationHistoryFrame();error="";
            Check(!readFrameDetails(0,frame,ref error),"reject invalid column "+invalidColumns[i]+" case "+i);
            Check(error!="","invalid value has error");
        }
        return "PASS "+checks+" detail value assertions";
    }
'''
        adapted += reader_value_methods(READER.read_text(encoding="utf-8-sig")) + "\n}"
        output = run_csharp(adapted, "(New-Object DetailReaderFixture).Run()\n")
        self.assertRegex(output, r"PASS \d+ detail value assertions")


class M5ObservationNavigationTests(unittest.TestCase):
    def test_navigation_skips_missing_and_offscreen_records_and_keeps_selected_frame(self):
        adapted = r'''
using System;
using System.Globalization;
public class M5ObservationHistoryRecord {
    public long id,barTime;
}
public class NavigationFixture {
    const long Bar=1795500000;
    const int OBJPROP_STATE=1;
    long chartId=0,selectedTime;
    string prefix="Fixture-";
    int selectedFrameIndex=6,markerCount,chartWidth=1200,chartHeight=600;
    int[] markerIndexes=new int[0];
    bool drawingSucceeded;
    int checks,drawCalls,panelCalls,stateChanges;
    long drawnTime;
    int drawnFrame;
    M5ObservationHistoryRecord[] drawnRecords;
    string stateObject="";
    bool stateValue=true;
    static int ArraySize<T>(T[] values) { return values.Length; }
    static int MathMin(int first,int second) { return Math.Min(first,second); }
    static int StringFind(string text,string value) { return text.IndexOf(value,StringComparison.Ordinal); }
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    bool ObjectSetInteger(long chart,string name,int property,bool value) {
        Check(property==OBJPROP_STATE,"only button state changed");
        stateChanges++;stateObject=name;stateValue=value;return true;
    }
    void ObjectsDeleteAll(long chart,string name,int window,int type) {}
    bool draw(M5ObservationHistoryRecord[] records,string status,int digits) {
        drawCalls++;drawnRecords=records;drawnTime=selectedTime;drawnFrame=selectedFrameIndex;return true;
    }
    void drawPanel(M5ObservationHistoryRecord[] records,int index,int digits,int width,int height) {
        panelCalls++;drawnRecords=records;drawnTime=records[index].barTime;drawnFrame=selectedFrameIndex;
    }
    M5ObservationHistoryRecord Record(long time,long id) {
        return new M5ObservationHistoryRecord { barTime=time,id=id };
    }
    public string Run() {
        M5ObservationHistoryRecord[] records={
            Record(Bar+1800,6),Record(Bar,1),Record(Bar+300,0),Record(Bar+900,3),
            Record(Bar+600,2),Record(Bar+1200,4),Record(0,7),Record(Bar+1500,0)
        };
        markerIndexes=new int[]{5,1,-1,3,7,0,6,2,99};markerCount=markerIndexes.Length;
        Check(findAdjacentRecordIndex(records,Bar+900,-1)==1,"previous uses nearest visible saved time, independent of array order");
        Check(findAdjacentRecordIndex(records,Bar+900,1)==5,"next uses nearest visible saved time");
        Check(findAdjacentRecordIndex(records,Bar,1)==3,"missing and offscreen records skipped");
        Check(findAdjacentRecordIndex(records,Bar+1200,1)==0,"missing later slot skipped");
        Check(findAdjacentRecordIndex(records,Bar,-1)==-1,"oldest has no previous record");
        Check(findAdjacentRecordIndex(records,Bar+1800,1)==-1,"newest has no next record");
        Check(findAdjacentRecordIndex(records,Bar+300,-1)==1 && findAdjacentRecordIndex(records,Bar+300,1)==3,"missing observation can navigate to either saved neighbor");
        Check(findAdjacentRecordIndex(records,0,1)==-1 && findAdjacentRecordIndex(records,Bar,0)==-1 && findAdjacentRecordIndex(records,Bar,2)==-1,"invalid selection and direction rejected");
        Check(findAdjacentRecordIndex(new M5ObservationHistoryRecord[0],Bar,1)==-1,"stale marker indexes do not access empty records");
        markerIndexes=new int[]{1,3,5,0};markerCount=2;
        Check(findAdjacentRecordIndex(records,Bar+900,1)==-1,"stale markers after markerCount excluded");
        markerCount=0;
        Check(findAdjacentRecordIndex(records,Bar,1)==-1,"no drawn markers disables navigation");
        markerIndexes=new int[]{5,1,3,7,0,6,2};markerCount=markerIndexes.Length;
        selectedTime=Bar+900;selectedFrameIndex=5;
        Check(onObjectClick(prefix+"PanelPrevious",records,"ready",3),"previous click handled");
        Check(selectedTime==Bar && selectedFrameIndex==5,"previous skips gaps without resetting M15 selection");
        Check(drawCalls==1 && drawnRecords==records && drawnTime==Bar && drawnFrame==5,"full redraw receives selected record cache and preserved detail frame");
        int redraws=drawCalls;
        Check(onObjectClick(prefix+"PanelPrevious",records,"ready",3),"disabled previous click consumed");
        Check(selectedTime==Bar && selectedFrameIndex==5 && drawCalls==redraws,"oldest edge preserves panel and selection");
        Check(stateChanges>0 && stateObject==prefix+"PanelPrevious" && !stateValue,"disabled button press released");
        Check(onObjectClick(prefix+"PanelNext",records,"ready",3) && selectedTime==Bar+900,"next returns to the same saved observation");
        Check(onObjectClick(prefix+"PanelNext",records,"ready",3) && selectedTime==Bar+1200,"next visits nearest newer observation");
        Check(onObjectClick(prefix+"PanelNext",records,"ready",3) && selectedTime==Bar+1800,"next skips missing slot");
        redraws=drawCalls;
        Check(onObjectClick(prefix+"PanelNext",records,"ready",3),"disabled next click consumed");
        Check(selectedTime==Bar+1800 && selectedFrameIndex==5 && drawCalls==redraws,"newest edge preserves M15 detail and record");
        Check(stateObject==prefix+"PanelNext" && !stateValue,"newest button press released");
        selectedTime=Bar+300;
        Check(onObjectClick(prefix+"PanelNext",records,"ready",3) && selectedTime==Bar+900 && selectedFrameIndex==5,"missing detail can move to a saved observation");
        M5ObservationHistoryRecord[] refreshed={records[3],records[0],records[1]};
        markerIndexes=new int[]{0,1,2};markerCount=3;
        Check(onObjectClick(prefix+"PanelPrevious",refreshed,"ready",3) && selectedTime==Bar,"reload with changed array indexes resolves selection by time");
        Check(drawnRecords==refreshed,"navigation redraw uses current cache");
        Check(onObjectClick(prefix+"PanelRow3Elliot",refreshed,"ready",3),"timeframe row click handled");
        Check(selectedFrameIndex==3 && panelCalls==1 && drawnTime==Bar && drawingSucceeded,"row click preserves observation after navigation");
        Check(!onObjectClick("Other-PanelNext",refreshed,"ready",3),"other indicator buttons ignored");
        Check(onObjectClick(prefix+"PanelClose",refreshed,"ready",3) && selectedTime==0 && selectedFrameIndex==6,"closing resets selection normally");
        Check(navigationGapText(Bar,0,Bar+300)=="","normal five-minute interval has no gap warning");
        Check(navigationGapText(Bar+600,Bar,0)=="前まで 10分","previous gap remains visible");
        Check(navigationGapText(Bar,0,Bar+600)=="次まで 10分","next gap remains visible");
        Check(navigationGapText(Bar+900,Bar,Bar+1500)=="前まで 15分 / 次まで 10分","both gaps shown independently");
        Check(navigationGapText(Bar+300,Bar,Bar+600)=="" && navigationGapText(Bar,0,0)=="","normal intervals and absent neighbors are not gaps");
        return "PASS "+checks+" navigation assertions";
    }
'''
        adapted += extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "findAdjacentRecordIndex", "onObjectClick", "markerName", "navigationGapText",
        )) + "\n}"
        output = run_csharp(adapted, "(New-Object NavigationFixture).Run()\n")
        self.assertRegex(output, r"PASS \d+ navigation assertions")


class M5ObservationTooltipTests(unittest.TestCase):
    def test_strength_text_preserves_source_missing_values_and_independent_delta(self):
        adapted = "using System;using System.Globalization;\n" + strength_fixture() + r'''
public class StrengthTextFixture {
    const int clrSilver=1,clrWhite=2,clrAqua=3,clrHotPink=4;
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    static string StringFormat(string format,int value) {
        return format.Replace("%+d",value.ToString("+0;-0;+0",CultureInfo.InvariantCulture)).Replace("%d",IntegerToString(value));
    }
    static int checks;
    static void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    public static string Run() {
        M5ObservationHistoryStrength strength=new M5ObservationHistoryStrength();
        Check(strengthStatusText(strength)=="通貨強弱OFF","disabled setting is explicit");
        strength.enabled=true;strength.status="未記録";
        Check(strengthStatusText(strength)=="未記録","missing history is not zero strength");
        strength.status="DB未検出";
        Check(strengthStatusText(strength)=="DB未検出","missing database distinct from missing observation");
        strength.status="取得失敗";
        Check(strengthStatusText(strength)=="取得失敗","query failure not a successful cached value");
        strength.status="取得済み";strength.weightLabel="加重";strength.sourceMode="TESTER";
        string title=strengthTitle(strength);
        Check(title.Contains("同M5") && title.Contains("履歴"),"history source distinct from saved wave snapshot");
        Check(title.Contains("加重") && title.Contains("TESTER"),"actual weight and data source visible");
        Check(strengthStatusText(strength)=="","successful status leaves room for rank rows");
        M5ObservationHistoryStrengthPeriod period=strength.longMedium;
        Check(strengthRankText(0,false)=="未記録" && strengthGapText(period)=="未記録","missing ranks and gap");
        Check(strengthValueColor(0,false)==clrSilver,"missing zero is gray");
        period.valid=true;period.baseRank=2;period.quoteRank=7;period.gap=5;
        Check(strengthRankText(2,true)=="2位" && strengthGapText(period)=="+5","positive gap retains sign");
        Check(strengthDeltaText(period)=="比較なし","missing previous M5 is not zero delta");
        period.comparable=true;period.delta=-2;
        Check(strengthDeltaText(period)=="↓ -2","positive gap can shrink");
        Check(strengthValueColor(period.gap,true)==clrAqua && strengthValueColor(period.delta,true)==clrHotPink,"gap and delta have independent colors");
        period.gap=-5;period.delta=1;
        Check(strengthGapText(period)=="-5" && strengthDeltaText(period)=="↑ +1","negative gap can rise");
        period.gap=0;period.delta=0;
        Check(strengthGapText(period)=="0" && strengthDeltaText(period)=="→ 0","recorded flat values are explicit");
        Check(strengthValueColor(0,true)==clrWhite,"recorded neutral is white");
        period.clear();
        Check(!period.valid && !period.comparable && period.baseRank==0 && period.quoteRank==0,"clearing restores unknown state");
        return "PASS "+checks+" strength text assertions";
    }
'''
        adapted += extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "strengthTitle", "strengthStatusText", "strengthRankText", "strengthGapText",
            "strengthDeltaText", "strengthValueColor",
        )) + "\n}"
        output = run_csharp(adapted, "[StrengthTextFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ strength text assertions")

    def test_chart_table_formatters_match_saved_directions_states_and_numbers(self):
        adapted = "using System;using System.Globalization;\n" + frame_fixture() + r'''
public class TableFixture {
    const int clrSilver=1,clrWhite=2,clrAqua=3,clrHotPink=4,clrDodgerBlue=5,clrMagenta=6;
    static int StringLen(string value) { return value.Length; }
    static string StringSubstr(string value,int start,int count) { return value.Substring(start,count); }
    static string DoubleToString(double value,int digits) { return value.ToString("F"+digits,CultureInfo.InvariantCulture); }
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    static int MathMax(int first,int second) { return Math.Max(first,second); }
    static int MathMin(int first,int second) { return Math.Min(first,second); }
    static class TimeUtil {
        public static string formatYyyymmddhhmiss(long value) {
            return new DateTime(1970,1,1).AddSeconds(value).ToString("yyyy/MM/dd HH:mm:ss",CultureInfo.InvariantCulture);
        }
    }
    static int checks;
    static void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    public static string Run() {
        M5ObservationHistoryFrame frame=new M5ObservationHistoryFrame();
        Check(tableElliotText(frame,5)=="未記録","missing timeframe");
        Check(emaText(frame)=="未記録" && movementText(frame)=="未記録","missing indicators");
        frame.hasData=true;frame.mainWave="3";frame.subWave="i";frame.originalWave="2";
        frame.isUptrend=0;frame.isBuy=1;frame.isConfirmed=0;frame.isAdded=1;
        frame.originalWaveIndex=2;frame.previousMotiveSubElliotIndex=3;
        frame.pointPipsDiff=-12.5;frame.hasPointPipsDiff=true;
        frame.pointFibonacciPercent=61.8;frame.hasPointFibonacciPercent=true;
        frame.pointFibonacciExpansionPercent=161.8;frame.hasPointFibonacciExpansionPercent=true;
        frame.pointRate=1.23456;frame.hasPointRate=true;
        string text=tableElliotText(frame,5);
        Check(text.Contains("[3副]") && text.Contains("【未】") && text.Contains("★▼3.i[2]"),"saved wave and states");
        Check(text.Contains("[F61.8%]") && !text.Contains("[FE"),"F uses original even index, not current main wave");
        Check(text.Contains("<-12.5p>") && text.EndsWith("1.23456"),"signed pips and symbol price precision");
        Check(analysisColor(frame.isBuy)==clrAqua && elliotColor(frame)==clrWhite,"added point white has priority");
        frame.isAdded=0;Check(elliotColor(frame)==clrDodgerBlue,"unconfirmed BUY blue despite downward wave");
        frame.isConfirmed=1;Check(elliotColor(frame)==clrAqua,"confirmed BUY aqua");
        frame.isBuy=0;Check(elliotColor(frame)==clrHotPink,"confirmed SELL pink");
        frame.isConfirmed=0;Check(elliotColor(frame)==clrMagenta,"unconfirmed SELL magenta");
        frame.isAdded=-1;Check(elliotColor(frame)==clrSilver,"unknown point state is not invented");
        frame.originalWaveIndex=3;frame.originalWave="3";frame.previousMotiveSubElliotIndex=0;
        text=tableElliotText(frame,5);
        Check(text.Contains("[FE161.8%]") && !text.Contains("[F61.8%]"),"FE uses original odd index");
        Check(!text.Contains("副]") && !text.Contains("[3]"),"zero preceding wave and unchanged original omitted");
        frame.originalWaveIndex=1;text=tableElliotText(frame,5);
        Check(!text.Contains("[F"),"wave one has no F/FE display");
        frame.originalWaveIndex=2;frame.hasPointFibonacciPercent=false;
        Check(tableElliotText(frame,5).Contains("[F未記録]"),"missing F is not zero percent");
        frame.originalWaveIndex=-1;
        Check(tableElliotText(frame,5).Contains("[F/FE未記録]"),"unknown original index not inferred from label");
        frame.originalWaveIndex=2;frame.hasPointFibonacciPercent=true;frame.pointFibonacciPercent=0;
        Check(tableElliotText(frame,5).Contains("[F0.0%]"),"recorded zero percent retained");
        frame.isEma200Buy=0;frame.isEma200Sell=1;
        Check(emaText(frame)=="SELL" && emaColor(frame)==clrHotPink,"EMA independent SELL");
        frame.isEma200Sell=0;
        Check(emaText(frame)=="NONE" && emaColor(frame)==clrWhite,"EMA NONE distinct from missing");
        frame.isEma200Buy=-1;
        Check(emaText(frame)=="未記録" && emaColor(frame)==clrSilver,"EMA missing flag not NONE");
        frame.isEma200Buy=1;frame.isEma200Sell=1;
        Check(emaText(frame)=="判定不能" && emaColor(frame)==clrSilver,"contradictory EMA flags are not BUY");
        frame.isPriceMovementValid=0;
        Check(movementText(frame)=="判定不能" && movementColor(frame)==clrSilver,"saved invalid movement");
        frame.isPriceMovementValid=1;frame.priceMovementLevel=3;
        frame.hasPriceMovementActivityRatio=true;frame.priceMovementActivityRatio=1.375;
        Check(movementText(frame)=="活発 1.38" && movementColor(frame)==clrDodgerBlue,"active movement and two decimals");
        frame.priceMovementLevel=2;frame.priceMovementActivityRatio=0;
        Check(movementText(frame)=="通常 0.00" && movementColor(frame)==clrWhite,"zero activity is recorded");
        frame.hasPriceMovementActivityRatio=false;
        Check(movementText(frame).Contains("未記録"),"missing activity not zero");
        frame.priceMovementLevel=-1;
        Check(movementText(frame)=="未記録" && movementColor(frame)==clrSilver,"missing movement level not invalid");
        return "PASS "+checks+" table assertions";
    }
'''
        adapted += extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "tableElliotText", "analysisColor", "elliotColor", "emaText", "emaColor",
            "movementText", "movementColor", "numberText", "recordedText", "waveText",
            "stateText", "timeText", "shorten",
        )) + "\n}"
        output = run_csharp(adapted, "[TableFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ table assertions")

    def test_production_formatter_with_saved_missing_and_long_labels(self):
        source = DRAWER.read_text(encoding="utf-8-sig")
        adapted = r'''
using System;
using System.Globalization;
public class M5ObservationHistoryFrame {
    public bool hasData;
    public int isUptrend=-1, isBuy=-1;
    public string mainWave="",subWave="";
}
public class M5ObservationHistoryRecord {
    public long id,barTime,jstTime,captureTime;
    public M5ObservationHistoryFrame[] frames=new M5ObservationHistoryFrame[7];
    public M5ObservationHistoryRecord() { for(int i=0;i<7;i++) frames[i]=new M5ObservationHistoryFrame(); }
}
public class TooltipFixture {
    static int StringLen(string value) { return value.Length; }
    static string StringSubstr(string value,int start,int count) { return value.Substring(start,count); }
    static int ArraySize(string[] value) { return value.Length; }
    static class TimeUtil {
        public static string formatYyyymmddhhmiss(long value) {
            return new DateTime(1970,1,1).AddSeconds(value).ToString("yyyy/MM/dd HH:mm:ss",CultureInfo.InvariantCulture);
        }
    }
    static int checks;
    static void Check(bool condition,string message) { checks++; if(!condition) throw new Exception(message); }
    static void AllFrames(string value) {
        foreach(string frame in new string[]{"MN1","W1","D1","H4","H1","M15","M5"}) Check(value.Contains("\n"+frame+" "),"missing "+frame);
    }
    public static string Run() {
        checks=0;
        long stamp=(long)(new DateTime(2026,11,25,11,35,0)-new DateTime(1970,1,1)).TotalSeconds;
        Check(timeText(stamp)=="2026/11/25 11:35:00","chart date format includes seconds");
        M5ObservationHistoryRecord record=new M5ObservationHistoryRecord { id=1,barTime=1795500000,jstTime=1795525200,captureTime=1795500012 };
        foreach(M5ObservationHistoryFrame frame in record.frames) { frame.hasData=true;frame.mainWave="3";frame.subWave="i";frame.isUptrend=0;frame.isBuy=1; }
        string text=formatTooltip(record);
        Check(text.Length<=159,"tooltip size"); AllFrames(text);
        Check(text.Contains("▼3.i"),"wave direction from saved wave");
        Check(!text.Contains("▲"),"analysis BUY must not replace downward wave");
        Check(text.Contains("JST "),"saved JST preferred");
        Check(text.Contains("取得 SRV "),"capture time separated");
        foreach(M5ObservationHistoryFrame frame in record.frames) { frame.mainWave=new string('3',100);frame.subWave=new string('i',100); }
        text=formatTooltip(record); Check(text.Length<=159,"long label size"); AllFrames(text);
        Check(text.Contains("…"),"long labels visibly shortened");
        foreach(M5ObservationHistoryFrame frame in record.frames) frame.hasData=false;
        record.jstTime=0;record.captureTime=0;text=formatTooltip(record);
        Check(text.Length<=159,"missing fields size");AllFrames(text);
        Check(text.Contains("未記録"),"missing values explicit");Check(!text.Contains("1970"),"unknown timestamp not epoch");
        Check(text.Contains("SRV "),"server fallback labelled");
        record.id=0;text=formatTooltip(record);
        Check(text.Contains("記録なし"),"missing observation");Check(!text.Contains("MN1"),"missing observation not invented");
        return "PASS "+checks+" tooltip assertions";
    }
'''
        adapted += extracted_methods(source, ("formatTooltip", "frameName", "waveText", "timeText", "shorten")) + "\n}"
        output = run_csharp(adapted, "[TooltipFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ tooltip assertions")


if __name__ == "__main__":
    unittest.main()
