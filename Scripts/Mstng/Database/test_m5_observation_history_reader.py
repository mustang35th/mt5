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
GMMA_COLUMNS = ("gmma_trend_count", "gmma_cross_count")


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
        parameters = parameters.replace("DrawChartObjectRegistry *", "DrawChartObjectRegistry ").replace("NULL", "null")
        parameters = re.sub(r"\bdatetime\b", "long", parameters)
        parameters = re.sub(r"\bcolor\b", "int", parameters)
        parameters = re.sub(r"\b(\w+)\s+(\w+)\[\]", r"\1[] \2", parameters)
        opening = signature.end() - 1
        body = source[opening + 1:block_end(code_only(source), opening)]
        # MQL permits the branch-local name to recur later in the enclosing
        # block; C# forbids it even when the branch exits with continue.
        body = re.sub(r"if \(i == 4 && fromLayout\.splitElliot\) \{[^}]+\}",
                      lambda match: re.sub(r"\bdrawn\b", "splitDrawn", match[0]), body)
        body = re.sub(r"\b(string|int|double|bool|long)\s+(\w+)\[\]\s*=\s*\{", r"\1[] \2 = new \1[] {", body)
        body = re.sub(r"\bstring\s+(\w+)\[\]\s*;", r"string[] \1;", body)
        body = re.sub(r"StringSplit\(([^,]+),\s*('[^']'),\s*(\w+)\)", r"StringSplit(\1, \2, out \3)", body)
        body = re.sub(r"\bdatetime\b", "long", body)
        body = re.sub(r"\bcolor\b", "int", body)
        body = body.replace("::", ".")
        body = re.sub(r"\b(CurrencyStrengthPairRankPoint)\s+(\w+)\s*;", r"\1 \2 = new \1();", body)
        body = re.sub(r"\b(ElliotTableRowData|ElliotTablePalette)\s+(\w+)\s*;", r"\1 \2 = new \1();", body)
        result_type = "int" if signature[2] == "color" else signature[2]
        result.append("public " + (signature[1] or "") + result_type + " " + name + "(" + parameters + ") {" + body.replace("NULL", "null") + "}")
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


def table_fixture():
    """Execute the neutral row defaults, palette and production shared formatter."""
    directory = ROOT / "Include/Mstng/Draw"
    source = (directory / "ElliotTableRowData.mqh").read_text(encoding="utf-8-sig")
    result = struct_fixture(source, "ElliotTableRowData")
    palette_body = source[source.index("struct ElliotTablePalette"):]
    fields = re.findall(r"^\s*color\s+(\w+);", palette_body, re.M)
    result += "public class ElliotTablePalette {\n"
    result += "".join(f"public int {field};\n" for field in fields)
    constructor = method(source, "ElliotTablePalette")
    colors = ("clrSilver", "clrWhite", "clrAqua", "clrHotPink", "clrDodgerBlue",
              "clrMagenta", "clrDeepSkyBlue", "clrPlum")
    for value, name in enumerate(colors, 1):
        constructor = re.sub(r"\b" + name + r"\b", str(value), constructor)
    result += "public ElliotTablePalette() {" + constructor + "}\n}\n"
    result += r'''
public class ElliotTableFormatter {
    static int ArraySize<T>(T[] values) { return values.Length; }
    static int StringLen(string value) { return value==null ? 0 : value.Length; }
    static int StringFind(string value,string part) { return value.IndexOf(part,StringComparison.Ordinal); }
    static string StringSubstr(string value,int start,int count) { return value.Substring(start,count); }
    static string DoubleToString(double value,int digits) { return value.ToString("F"+digits,CultureInfo.InvariantCulture); }
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    static string StringFormat(string format,int value) {
        return format.Replace("%+d",value.ToString("+0;-0;+0",CultureInfo.InvariantCulture));
    }
    static int MathMax(int first,int second) { return Math.Max(first,second); }
    static int MathMin(int first,int second) { return Math.Min(first,second); }
'''
    formatter = (directory / "ElliotTableFormatter.mqh").read_text(encoding="utf-8-sig")
    names = re.findall(r"\bstatic\s+(?:string|color|int|bool)\s+(\w+)\s*\(", formatter)
    methods = extracted_methods(formatter, names)
    # Preserve the scalar output parameter in the production GMMA reader.
    methods = re.sub(r"\breadGmmaCount\(([^)]*)\)",
                     lambda match: "readGmmaCount(" + ",".join(
                         ("ref " if index == 2 else "") + value.strip()
                         for index, value in enumerate(match[1].split(","))) + ")", methods)
    return result + methods + "\n}\n"


def registry_fixture(base="MqlApi"):
    """Keep ownership/generation branches and adapt only dynamic MQL arrays."""
    source = (ROOT / "Include/Mstng/Draw/DrawChartObjectRegistry.mqh").read_text(encoding="utf-8-sig")
    opening = source.index("class DrawChartObjectRegistry {") + len("class DrawChartObjectRegistry {")
    body = source[opening:block_end(code_only(source), opening - 1)]
    body = re.sub(r"\b(?:public|protected|private)\s*:", "", body)
    body = re.sub(r"\bconst\s+", "", body).replace("ENUM_OBJECT", "int")
    body = re.sub(r"\b(string|bool)\s+(\w+)\[\]\s*;", r"\1[] \2 = new \1[0];", body)
    body = re.sub(r"Array(Resize|Free)\((this\.\w+)", r"Array\1(ref \2", body)
    body = re.sub(r"^(\s{4})(?=(?:bool|void|DrawChartObjectRegistry)\b[^\n;=]*\()",
                  r"\1public ", body, flags=re.M)
    return "public class DrawChartObjectRegistry : " + base + " {\n" + body + "\n}\n"


def table_layout_fixture(source):
    """Keep renderer layout defaults; adapt only fixed arrays and MQL color literals."""
    opening = re.search(r"\bstruct ElliotTableLayout\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    fields = re.findall(r"^\s*(int|long|bool|string|color|DrawChartObjectRegistry)\s+\*?(\w+)(?:\[(\d+)\])?;", body, re.M)
    result = "public class ElliotTableLayout { const int clrWhite=2;\n"
    for kind, name, count in fields:
        kind = "int" if kind == "color" else kind
        if count:
            result += f"public {kind}[] {name}=new {kind}[{count}];\n"
        else:
            initial = '= ""' if kind == "string" else ""
            result += f"public {kind} {name}{initial};\n"
    constructor = method(source, "ElliotTableLayout")
    constructor = re.sub(r"C'(\d+),(\d+),(\d+)'",
                         lambda match: str(int(match[1]) + 256 * int(match[2]) + 65536 * int(match[3])), constructor)
    return result + "public ElliotTableLayout() {" + constructor.replace("NULL", "null") + "}\n}\n"


def strength_fixture():
    source = READER.with_name("ZigZagElliotM5ObservationHistoryData.mqh").read_text(encoding="utf-8-sig")
    return "".join(struct_fixture(source, name) for name in (
        "M5ObservationHistoryStrengthPeriod", "M5ObservationHistoryStrength",
    ))


def reader_value_methods(source):
    """Keep validation branches; adapt references and stub only the MT5 column API."""
    names = ("readFrameDetails", "readOptionalFlag", "readOptionalInteger", "readOptionalSignedInteger", "readOptionalDouble",
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

    def allow_legacy_overlaps(self):
        # Current writer schemas deduplicate the same profile/M5 across Runs.
        # Relax only this disposable fixture to exercise defensive selection
        # when imported/legacy databases contain overlapping Run observations.
        self.database.commit()
        self.database.execute("PRAGMA foreign_keys=OFF")
        schema = self.database.execute("SELECT sql FROM sqlite_master WHERE name=?", (OBS,)).fetchone()[0]
        schema, removed = re.subn(r",\s*UNIQUE\([^)]*\)", "", schema, flags=re.I)
        self.assertEqual(removed, 1)
        self.database.execute(schema.replace(OBS, "legacy_observations", 1))
        self.database.execute(f"INSERT INTO legacy_observations SELECT * FROM {OBS}")
        self.database.execute(f"DROP TABLE {OBS}")
        self.database.execute(f"ALTER TABLE legacy_observations RENAME TO {OBS}")
        self.database.commit()
        self.database.execute("PRAGMA foreign_keys=ON")

    def test_current_schema_deduplicates_across_runs_and_history_fills_gap(self):
        previous = add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        with self.assertRaises(sqlite3.IntegrityError):
            add_observation(self.database, run=2)
        target = add_observation(self.database, run=2, bar=BASE_TIME + 300)
        rows = self.rows(run=2, end=BASE_TIME + 600)
        self.assertEqual({(row[0], row[1]) for row in rows}, {(previous, 1), (target, 2)})
        self.assertEqual(len(rows), 14)

    def test_matching_previous_runs_fill_only_exact_missing_times(self):
        self.allow_legacy_overlaps()
        oldest = add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        newer = add_observation(self.database, run=2)
        add_run(self.database, 3, analysis_input_hash="hash-1")
        current = add_observation(self.database, run=3, bar=BASE_TIME + 300)
        self.assertEqual(self.resolve_run(), 3)
        rows = self.rows(run=3, end=BASE_TIME + 900)
        self.assertEqual({row[0] for row in rows}, {newer, current})
        self.assertNotIn(oldest, {row[0] for row in rows})
        self.assertEqual({(row[1], row[2]) for row in rows}, {(2, BASE_TIME), (3, BASE_TIME + 300)})
        self.assertEqual(len(rows), 14)
        self.assertEqual(self.rows(run=3, start=BASE_TIME + 600, end=BASE_TIME + 900), [])
        # A later capture in the target Run replaces the supplemented record.
        replacement = add_observation(self.database, run=3)
        self.assertEqual({row[0] for row in self.rows(run=3)}, {replacement})

    def test_explicit_run_can_fill_from_older_runs_but_never_newer_runs(self):
        self.allow_legacy_overlaps()
        previous = add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        add_observation(self.database, run=2, bar=BASE_TIME + 300)
        add_run(self.database, 3, analysis_input_hash="hash-1")
        add_observation(self.database, run=3)
        add_observation(self.database, run=3, bar=BASE_TIME + 600)
        self.assertEqual(self.resolve_run(requested=2), 2)
        self.assertEqual({row[0] for row in self.rows(run=2)}, {previous})
        self.assertEqual(self.rows(run=2, start=BASE_TIME + 600, end=BASE_TIME + 900), [])

    def test_fallback_excludes_incompatible_run_metadata_even_with_same_hash(self):
        self.allow_legacy_overlaps()
        previous = add_observation(self.database)
        incompatible = (
            dict(analysis_input_hash="different"), dict(analysis_version="OTHER"),
            dict(analysis_input_text="M5_OBSERVATION_PROFILE_V1|different"),
            dict(source_mode="TESTER"), dict(source_server="Other-Server"),
            dict(schema_version=2), dict(strategy="OTHER"), dict(strategy_version="OTHER"),
        )
        for identifier, changes in enumerate(incompatible, 2):
            add_run(self.database, identifier, **(dict(analysis_input_hash="hash-1") | changes))
            add_observation(self.database, run=identifier)
        add_run(self.database, 20, analysis_input_hash="hash-1")
        add_observation(self.database, run=20, bar=BASE_TIME + 300)
        self.assertEqual({row[0] for row in self.rows(run=20)}, {previous})
        self.assertEqual({row[1] for row in self.rows(run=20)}, {1})

    def test_fallback_excludes_other_symbols_and_observation_sources(self):
        previous = add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        add_observation(self.database, run=2, symbol="USDJPY")
        add_run(self.database, 3, analysis_input_hash="hash-1")
        add_observation(self.database, run=3, source_mode="TESTER")
        add_run(self.database, 4, analysis_input_hash="hash-1")
        add_observation(self.database, run=4, source_server="Other-Server")
        add_run(self.database, 5, analysis_input_hash="hash-1")
        add_observation(self.database, run=5, bar=BASE_TIME + 300)
        self.assertEqual({row[0] for row in self.rows(run=5)}, {previous})

    def test_fallback_obeys_known_capture_time_before_choosing_latest_run(self):
        self.allow_legacy_overlaps()
        previous = add_observation(self.database, capture=BASE_TIME + 1)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        later = add_observation(self.database, run=2, capture=BASE_TIME + 20)
        add_run(self.database, 3, analysis_input_hash="hash-1")
        add_observation(self.database, run=3, bar=BASE_TIME - 300)
        self.assertEqual(self.rows(run=3, known=BASE_TIME), [])
        self.assertEqual({row[0] for row in self.rows(run=3, known=BASE_TIME + 19)}, {previous})
        self.assertEqual({row[0] for row in self.rows(run=3, known=BASE_TIME + 20)}, {later})

    def test_target_partial_observation_is_not_mixed_with_older_frames(self):
        self.allow_legacy_overlaps()
        add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        target = add_observation(self.database, run=2)
        self.database.execute(f"DELETE FROM {FRAMES} WHERE observation_id=? AND time_frame=15", (target,))
        rows = self.rows(run=2)
        self.assertEqual(len(rows), 6)
        self.assertEqual({row[0] for row in rows}, {target})
        self.assertNotIn(15, {row[7] for row in rows})

    def test_duplicate_records_in_winning_run_remain_visible_for_validation(self):
        self.allow_legacy_overlaps()
        first = add_observation(self.database)
        second = add_observation(self.database)
        add_run(self.database, 2, analysis_input_hash="hash-1")
        add_observation(self.database, run=2, bar=BASE_TIME + 300)
        rows = self.rows(run=2)
        self.assertEqual({row[0] for row in rows}, {first, second})
        self.assertEqual(len(rows), 14)

    def test_display_refresh_follows_restarted_collector_only_for_automatic_run(self):
        # Bind the actual controller call argument, so querying Run0 directly
        # cannot hide a regression that passes the previously resolved Run.
        source = DISPLAY.read_text(encoding="utf-8-sig")
        call = re.search(r"this\.reader\.selectRecords\(([^()]*)\)", method(source, "update"))
        self.assertIsNotNone(call)
        requested_path = call[1].split(",")[3].strip().split(".")
        self.assertEqual(requested_path[0], "this")

        def refresh(configured, resolved):
            requested = {"config": {"m5ObservationDisplayRunId": configured},
                         "resolvedRunId": resolved}
            for field in requested_path[1:]:
                requested = requested[field]
            return self.resolve_run(requested=requested)

        add_observation(self.database)
        selected = {configured: refresh(configured, configured) for configured in (0, 1)}
        self.assertEqual(selected, {0: 1, 1: 1})

        # A restarted collector may not have saved its first observation yet;
        # another strategy's newer Run must not displace a compatible Run.
        add_run(self.database, 2)
        add_run(self.database, 3, strategy="MTF_3in3")
        add_observation(self.database, run=3, bar=BASE_TIME + 300)
        selected = {configured: refresh(configured, resolved)
                    for configured, resolved in selected.items()}
        self.assertEqual(selected, {0: 1, 1: 1})

        identifier = add_observation(self.database, run=2, bar=BASE_TIME + 300)
        selected = {configured: refresh(configured, resolved)
                    for configured, resolved in selected.items()}
        self.assertEqual(selected, {0: 2, 1: 1})
        automatic_rows = self.rows(run=selected[0], start=BASE_TIME + 300, end=BASE_TIME + 600)
        self.assertEqual(len(automatic_rows), 7)
        self.assertEqual({row[0] for row in automatic_rows}, {identifier})
        self.assertEqual(self.rows(run=selected[1], start=BASE_TIME + 300, end=BASE_TIME + 600), [])
        self.assertEqual(len(self.rows(run=selected[1])), 7)

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

    def test_gmma_query_preserves_negative_counts_zero_and_nullable_legacy_values(self):
        add_observation(self.database)
        self.database.execute(f"UPDATE {FRAMES} SET gmma_trend_count=-1,gmma_cross_count=0")
        rows = self.rows()
        self.assertEqual(len(rows), 7)
        for row in rows:
            self.assertEqual(tuple(row[36:38]), (-1, 0))
        self.database.execute(f"UPDATE {FRAMES} SET gmma_trend_count=12,gmma_cross_count=-5")
        self.assertEqual(tuple(self.rows()[0][36:38]), (12, -5))
        # Older imports may contain nullable GMMA columns even though current
        # writers require integers. Exercise the SELECT against that schema.
        self.database.commit()
        self.database.execute("PRAGMA foreign_keys=OFF")
        self.database.execute(f"CREATE TABLE nullable_copy AS SELECT * FROM {FRAMES}")
        self.database.execute(f"DROP TABLE {FRAMES}")
        self.database.execute(f"ALTER TABLE nullable_copy RENAME TO {FRAMES}")
        self.database.execute(f"UPDATE {FRAMES} SET gmma_trend_count=NULL,gmma_cross_count=NULL")
        self.assertEqual(tuple(self.rows()[0][36:38]), (None, None))

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
                                | set(DETAIL_COLUMNS) | set(GMMA_COLUMNS))):
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
        self.assertEqual(tuple(rows[0][36:38]), (None, None))

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
SAVED_ADAPTER = ROOT / "Include/Mstng/Draw/ElliotPanelSavedAdapter.mqh"
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
    const int INT_MAX=int.MaxValue,INT_MIN=int.MinValue;
    object[] columns=new object[38];
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
    void ZeroColumns() { for(int i=25;i<38;i++) columns[i]=0L; }
    public string Run() {
        string error="";
        M5ObservationHistoryFrame frame=new M5ObservationHistoryFrame();
        Check(readFrameDetails(0,frame,ref error),"missing columns accepted");
        Check(frame.isEma200Buy==-1 && frame.isEma200Sell==-1,"missing EMA flags");
        Check(frame.isPriceMovementValid==-1 && frame.priceMovementLevel==-1,"missing movement flags");
        Check(frame.originalWaveIndex==-1 && frame.previousMotiveSubElliotIndex==-1,"missing wave indexes");
        Check(!frame.hasPriceMovementActivityRatio && !frame.hasPointPipsDiff && !frame.hasPointFibonacciPercent && !frame.hasPointFibonacciExpansionPercent,"missing numbers");
        Check(frame.pointJstTime==0,"missing JST remains unknown");
        Check(!frame.hasGmmaTrendCount && !frame.hasGmmaCrossCount && frame.gmmaTrendCount==0 && frame.gmmaCrossCount==0,"NULL GMMA is unknown despite its zero storage default");
        ZeroColumns();frame=new M5ObservationHistoryFrame();
        Check(readFrameDetails(0,frame,ref error),"recorded zero accepted");
        Check(frame.isEma200Buy==0 && frame.isEma200Sell==0 && frame.originalWaveIndex==0 && frame.previousMotiveSubElliotIndex==0,"zero flags are not missing");
        Check(frame.hasPriceMovementActivityRatio && frame.hasPointPipsDiff && frame.hasPointFibonacciPercent && frame.hasPointFibonacciExpansionPercent,"zero numbers have values");
        Check(frame.hasGmmaTrendCount && frame.hasGmmaCrossCount && frame.gmmaTrendCount==0 && frame.gmmaCrossCount==0,"recorded zero GMMA remains valid");
        columns[31]=3L;columns[32]=-12.5;columns[33]=-2.5;columns[34]=161.8;columns[35]=1795524900L;
        Check(readFrameDetails(0,frame,ref error),"signed recorded values accepted");
        Check(frame.pointPipsDiff==-12.5 && frame.pointFibonacciPercent==-2.5 && frame.pointJstTime==1795524900L,"recorded values preserved");
        columns[36]=-1L;columns[37]=-5L;
        Check(readFrameDetails(0,frame,ref error) && frame.hasGmmaTrendCount && frame.gmmaTrendCount==-1 && frame.hasGmmaCrossCount && frame.gmmaCrossCount==-5,"negative one is a recorded GMMA count, not a missing sentinel");
        columns[36]=-2147483648L;columns[37]=2147483647L;
        Check(readFrameDetails(0,frame,ref error) && frame.gmmaTrendCount==int.MinValue && frame.gmmaCrossCount==int.MaxValue,"full signed MQL integer range is accepted");
        columns[36]=null;columns[37]=null;
        Check(readFrameDetails(0,frame,ref error) && !frame.hasGmmaTrendCount && !frame.hasGmmaCrossCount && frame.gmmaTrendCount==0 && frame.gmmaCrossCount==0,"later NULL clears previous signed values");
        int[] invalidColumns={25,26,27,28,29,29,29,30,30,31,32,33,34,35,35,36,36,36,37,37,37};
        object[] invalidValues={2L,"1",1.0,4L,-0.1,Double.NaN,Double.PositiveInfinity,2147483648L,-1L,2L,"12.5",Double.NaN,Double.NegativeInfinity,-1L,"123","-1",1.0,2147483648L,"0",-1.0,-2147483649L};
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
public class PanelNavigationStub {
    public long savedTime;public bool savedMode=true;public int selectedTimeFrame=15;
    public bool isSavedMode() { return savedMode; }
    public long getSavedTime() { return savedTime; }
}
public class NavigationFixture {
    const long Bar=1795500000;
    string prefix="Fixture-";
    int markerCount,checks,showCalls,shownDigits;
    int[] markerIndexes=new int[0];
    PanelNavigationStub panel=new PanelNavigationStub();
    M5ObservationHistoryRecord[] shownRecords;
    static int ArraySize<T>(T[] values) { return values.Length; }
    static int MathMin(int first,int second) { return Math.Min(first,second); }
    static int StringFind(string text,string value) { return text.IndexOf(value,StringComparison.Ordinal); }
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    void showRecord(M5ObservationHistoryRecord[] records,int index,int digits) {
        showCalls++;shownRecords=records;shownDigits=digits;panel.savedTime=records[index].barTime;
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
        panel.savedTime=Bar+900;
        Check(navigatePanel(records,-1,3),"previous navigation handled");
        Check(panel.savedTime==Bar && panel.selectedTimeFrame==15,"previous skips gaps without changing selected timeframe");
        Check(showCalls==1 && shownRecords==records && shownDigits==3,"neutral-panel conversion receives the cached record and symbol precision");
        int previousCalls=showCalls;
        Check(!navigatePanel(records,-1,3) && panel.savedTime==Bar && showCalls==previousCalls,"oldest edge does not redraw or change selection");
        Check(navigatePanel(records,1,3) && panel.savedTime==Bar+900,"next returns to same observation");
        Check(navigatePanel(records,1,3) && panel.savedTime==Bar+1200,"next visits nearest newer observation");
        Check(navigatePanel(records,1,3) && panel.savedTime==Bar+1800,"next skips missing slot");
        previousCalls=showCalls;
        Check(!navigatePanel(records,1,3) && panel.savedTime==Bar+1800 && showCalls==previousCalls,"newest edge leaves existing panel untouched");
        panel.savedTime=Bar+300;
        Check(navigatePanel(records,1,3) && panel.savedTime==Bar+900,"missing observation can navigate to saved neighbor");
        M5ObservationHistoryRecord[] refreshed={records[3],records[0],records[1]};
        markerIndexes=new int[]{0,1,2};markerCount=3;
        Check(navigatePanel(refreshed,-1,3) && panel.savedTime==Bar && shownRecords==refreshed,"refresh resolves observation by time despite different array indexes");
        panel.savedMode=false;
        Check(!navigatePanel(refreshed,1,3) && panel.savedTime==Bar,"current mode cannot be moved through saved observations");
        Check(!onObjectClick("Other-Marker-"+Bar,refreshed,"ready",3),"other indicator markers ignored");
        Check(!onObjectClick(prefix+"PanelNext",refreshed,"ready",3),"panel actions belong to the shared view, not the marker drawer");
        Check(onObjectClick(markerName(Bar+900),refreshed,"ready",3) && panel.savedTime==Bar+900,"marker selection routes its saved record to shared panel");
        Check(!onObjectClick(markerName(Bar+999),refreshed,"ready",3),"unknown marker cannot create an observation");
        panel=null;
        Check(!navigatePanel(refreshed,1,3) && !onObjectClick(markerName(Bar),refreshed,"ready",3),"unbound panel is safe");
        Check(navigationGapText(Bar,0,Bar+300)=="","normal five-minute interval has no gap warning");
        Check(navigationGapText(Bar+600,Bar,0)=="前まで 10分","previous gap remains visible");
        Check(navigationGapText(Bar,0,Bar+600)=="次まで 10分","next gap remains visible");
        Check(navigationGapText(Bar+900,Bar,Bar+1500)=="前まで 15分 / 次まで 10分","both gaps shown independently");
        Check(navigationGapText(Bar+300,Bar,Bar+600)=="" && navigationGapText(Bar,0,0)=="","normal intervals and absent neighbors are not gaps");
        return "PASS "+checks+" navigation assertions";
    }
'''
        methods = extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "findAdjacentRecordIndex", "navigatePanel", "onObjectClick", "markerName", "navigationGapText",
        ))
        adapted += methods.replace("NULL", "null") + "\n}"
        output = run_csharp(adapted, "(New-Object NavigationFixture).Run()\n")
        self.assertRegex(output, r"PASS \d+ navigation assertions")


class SharedElliotTableTests(unittest.TestCase):
    def test_shared_renderer_preserves_layout_names_clipping_and_custom_tooltips(self):
        renderer = (ROOT / "Include/Mstng/Draw/DrawElliotTable.mqh").read_text(encoding="utf-8-sig")
        adapted = "using System;using System.Globalization;using System.Collections.Generic;\n"
        adapted += table_fixture() + table_layout_fixture(renderer) + r'''
public class DrawElliotTable {
    public const int OBJ_LABEL=1,OBJ_RECTANGLE_LABEL=2,CORNER_LEFT_UPPER=0,ANCHOR_LEFT_UPPER=0,ANCHOR_UPPER=1,BORDER_FLAT=0,clrSlateGray=9;
    public const long OBJ_NO_PERIODS=0,OBJ_ALL_PERIODS=-1;
    public const int OBJPROP_TIMEFRAMES=21;
    const int OBJPROP_CORNER=1,OBJPROP_ANCHOR=2,OBJPROP_XDISTANCE=3,OBJPROP_YDISTANCE=4,OBJPROP_COLOR=5,
        OBJPROP_FONTSIZE=6,OBJPROP_BACK=7,OBJPROP_SELECTABLE=8,OBJPROP_HIDDEN=9,OBJPROP_ZORDER=10,
        OBJPROP_FONT=11,OBJPROP_TEXT=12,OBJPROP_TOOLTIP=13,OBJPROP_XSIZE=14,OBJPROP_YSIZE=15,
        OBJPROP_BGCOLOR=16,OBJPROP_BORDER_TYPE=17;
    class ChartObject {
        public int kind;
        public Dictionary<int,long> numbers=new Dictionary<int,long>();
        public Dictionary<int,string> texts=new Dictionary<int,string>();
    }
    static Dictionary<string,ChartObject> objects=new Dictionary<string,ChartObject>();
    static string failName="";
    static bool failMeasure;
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    static int ObjectFind(long chart,string name) { return objects.ContainsKey(name) ? 0 : -1; }
    static bool ObjectDelete(long chart,string name) { return objects.Remove(name); }
    static bool ObjectCreate(long chart,string name,int kind,int subwindow,long time,double price) {
        if(name==failName) return false;
        objects.Add(name,new ChartObject { kind=kind });return true;
    }
    static bool ObjectSetInteger(long chart,string name,int property,long value) { objects[name].numbers[property]=value;return true; }
    static bool ObjectSetInteger(long chart,string name,int property,bool value) { return ObjectSetInteger(chart,name,property,value ? 1L : 0L); }
    static bool ObjectSetString(long chart,string name,int property,string value) { objects[name].texts[property]=value;return true; }
    static bool TextSetFont(string face,int size) { return !failMeasure; }
    static bool TextGetSize(string text,out uint width,out uint height) { width=(uint)text.Length*10;height=10;return true; }
    static int ArraySize<T>(T[] values) { return values.Length; }
    public static int ArrayResize<T>(ref T[] values,int length) { Array.Resize(ref values,length);return length; }
    public static void ArrayFree<T>(ref T[] values) { values=new T[0]; }
    static int MathMax(int first,int second) { return Math.Max(first,second); }
    static int MathMin(int first,int second) { return Math.Min(first,second); }
    static int StringLen(string value) { return value.Length; }
    static string StringSubstr(string value,int start,int count) { return value.Substring(start,count); }
    static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    public static string Run() {
        ElliotTableRowData row=new ElliotTableRowData { hasData=true,timeFrameLabel="M15",isBuy=1,isUptrend=0,
            isAdded=0,isConfirmed=1,mainWave=new string('3',180),subWave="i",originalWaveIndex=1,
            hasPointRate=true,pointRate=1.23456,hasPointPipsDiff=true,pointPipsDiff=12.5,
            isEma200Buy=0,isEma200Sell=1,isPriceMovementValid=1,priceMovementLevel=3,
            hasPriceMovementActivityRatio=true,priceMovementActivityRatio=1.375 };
        ElliotTablePalette palette=new ElliotTablePalette();ElliotTableLayout panel=new ElliotTableLayout();
        panel.originX=10;panel.originY=20;panel.paddingX=8;panel.paddingY=5;panel.rowHeight=26;
        panel.showBackground=true;panel.showSeparators=true;panel.clipText=true;panel.textZOrder=22;
        int position=0;for(int i=0;i<5;i++) { panel.columnXs[i]=position;panel.columnWidths[i]=50+i*10;position+=panel.columnWidths[i]; }
        Check(drawHeader(0,"Header-",panel),"header draws successfully");
        Check(objects.Count==10 && objects["Header-Background"].kind==OBJ_RECTANGLE_LABEL,"header uses shared background and four separators");
        Check(objects["Header-Background"].numbers[OBJPROP_XSIZE]==350,"background spans all five columns");
        Check(objects["Header-TimeFrame"].numbers[OBJPROP_XDISTANCE]==18 && objects["Header-TimeFrame"].numbers[OBJPROP_YDISTANCE]==25,"header position uses configured origin and padding");
        Check(objects["Header-PriceMovement"].texts[OBJPROP_TEXT]=="値動き","shared Japanese column title");
        Check(drawRow(0,"PanelRow5",row,5,palette,panel),"saved panel row draws successfully");
        ChartObject cell=objects["PanelRow5Elliot"];
        Check(cell.texts[OBJPROP_TEXT].EndsWith("…") && cell.texts[OBJPROP_TEXT].Length*10<=74,"measured cell text stays within its column");
        Check(cell.texts[OBJPROP_TOOLTIP].StartsWith("▼333") && cell.texts[OBJPROP_TOOLTIP].Length<=159,"full-value tooltip remains bounded and keeps wave direction");
        Check(cell.numbers[OBJPROP_COLOR]==3 && cell.numbers[OBJPROP_ZORDER]==22,"table analysis color and click priority preserved");
        int objectCount=objects.Count;row.mainWave="5";drawRow(0,"PanelRow5",row,5,palette,panel);
        Check(objects.Count==objectCount && objects["PanelRow5Elliot"].texts[OBJPROP_TOOLTIP].Contains("▼5.i"),"redraw updates its objects without duplicates");
        ElliotTableLayout live=new ElliotTableLayout();live.originY=70;live.fontFace="Custom Font";
        for(int i=0;i<5;i++) { live.columnXs[i]=i*110;live.columnWidths[i]=110;live.columnFontSizes[i]=35; }
        live.columnXs[4]=900;live.columnFontSizes[3]=17;live.columnYOffsets[3]=10;live.tooltips[3]="ATR and spread details";
        Check(drawRow(0,"Live-ElliotM15",row,5,palette,live),"live row uses same renderer");
        Check(!objects.ContainsKey("Live-ElliotM15Background") && !objects.ContainsKey("Live-ElliotM15Line0"),"live style leaves chart background visible");
        Check(objects["Live-ElliotM15Elliot"].numbers[OBJPROP_XDISTANCE]==900,"space for chart-only oscillator columns is retained");
        cell=objects["Live-ElliotM15PriceMovement"];
        Check(cell.numbers[OBJPROP_FONTSIZE]==17 && cell.numbers[OBJPROP_YDISTANCE]==80 && cell.texts[OBJPROP_FONT]=="Custom Font","chart font settings and movement vertical offset retained");
        Check(cell.texts[OBJPROP_TOOLTIP]=="ATR and spread details","chart-only movement tooltip survives shared drawing");
        live.columnVisible[2]=false;drawRow(0,"Hidden-",row,5,palette,live);
        Check(!objects.ContainsKey("Hidden-EMA200") && objects.ContainsKey("Hidden-Elliot"),"hidden column does not affect other cells");
        failName="Failed-BuySell";
        Check(!drawRow(0,"Failed-",row,5,palette,live),"object creation failure is reported");
        Check(objects.ContainsKey("Failed-Elliot"),"one failed cell does not suppress later cells");
        failMeasure=true;
        Check(fitText("abcdef",20,"Custom Font",10)=="a…","font measurement failure uses bounded fallback");
        Check(fitText("abcdef",0,"Custom Font",10)=="","zero width never overflows");
        return "PASS "+checks+" shared renderer assertions";
    }
'''
        names = re.findall(r"\bstatic\s+(?:string|bool)\s+(\w+)\s*\(", renderer)
        methods = extracted_methods(renderer, names)
        methods = re.sub(r"TextGetSize\(([^,]+),\s*(\w+),\s*(\w+)\)", r"TextGetSize(\1, out \2, out \3)", methods)
        adapted = re.sub(r"^    static (int|bool) (Object\w+|ArraySize)", r"    public static \1 \2", adapted, flags=re.M)
        adapted += methods + "\n}" + registry_fixture("DrawElliotTable")
        output = run_csharp(adapted, "[DrawElliotTable]::Run()\n")
        self.assertRegex(output, r"PASS \d+ shared renderer assertions")
        live = code_only((ROOT / "Include/Mstng/Draw/DrawElliot.mqh").read_text(encoding="utf-8-sig"))
        panel = code_only((ROOT / "Include/Mstng/Draw/DrawElliotPanel.mqh").read_text(encoding="utf-8-sig"))
        for source in (live, panel):
            self.assertIn("DrawElliotTable::drawRow(", source)
            self.assertIn("DrawElliotTable::drawHeader(", source)

    def test_live_and_saved_adapters_produce_the_same_five_columns(self):
        adapted = "using System;using System.Globalization;\n" + frame_fixture() + table_fixture() + r'''
public class MarketContext { public string timeFrameLabel="M15"; }
public class PriceMovementInfo { public bool isValid=true;public int level=3;public double activityRatio=1.375; }
public class Ema { public bool isBuy=false,isSell=true; }
public class Oscillator { public Ema ema200=new Ema();public PriceMovementInfo priceMovement=new PriceMovementInfo();public int gmmaTrendCount=4,gmmaCrossCount=-1; }
public class Elliot { public bool isBuy=true;public MarketContext marketContext=new MarketContext();public Oscillator oscillator=new Oscillator(); }
public class ZigZagPoint {
    public string elliotLabel="3",subElliotLabel="i",orgElliotLabel="2";
    public int orgElliotIndex=2;public bool isAddedPoint=true;
    public double pipsDiff=-12.5,fibonacciPercent=61.8,fibonacciExpansionPercent=161.8,rate=1.23456;
}
public class Wave {
    public bool isUptrend=false,isConfirmed=false;public int previous=3;public ZigZagPoint point=new ZigZagPoint();
    public ZigZagPoint getLatestPoint() { return point; }
    public int getPreviousMotiveSubElliotIndex() { return previous; }
}
public class LiveAdapter {
'''
        live_source = (ROOT / "Include/Mstng/Draw/ElliotPanelLiveAdapter.mqh").read_text(encoding="utf-8-sig")
        live = extracted_methods(live_source, ("fillTableRow", "fillPriceMovementRow"))
        live = re.sub(r"\b(Wave|ZigZagPoint)\s*\*", r"\1 ", live).replace("NULL", "null")
        live = re.sub(r"\(int\)((?:fromElliot|fromWave|point|fromPriceMovement)\.[\w.]+)",
                      r"Convert.ToInt32(\1)", live)
        adapted += live.replace("public static ", "public ") + "\n}\npublic class SavedAdapter {\n"
        adapted += extracted_methods(SAVED_ADAPTER.read_text(encoding="utf-8-sig"), ("fillTableRow",))
        adapted += r'''
}
public class SharedAdapterFixture {
    static int checks;
    static void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    public static string Run() {
        Elliot elliot=new Elliot();Wave wave=new Wave();LiveAdapter adapter=new LiveAdapter();
        ElliotTableRowData live=new ElliotTableRowData(),saved=new ElliotTableRowData();
        ElliotTablePalette palette=new ElliotTablePalette();
        M5ObservationHistoryFrame frame=new M5ObservationHistoryFrame {
            hasData=true,mainWave="3",subWave="i",originalWave="2",isBuy=1,isUptrend=0,isConfirmed=0,isAdded=1,
            isEma200Buy=0,isEma200Sell=1,isPriceMovementValid=1,priceMovementLevel=3,
            priceMovementActivityRatio=1.375,hasPriceMovementActivityRatio=true,originalWaveIndex=2,
            previousMotiveSubElliotIndex=3,pointPipsDiff=-12.5,hasPointPipsDiff=true,
            pointFibonacciPercent=61.8,hasPointFibonacciPercent=true,pointFibonacciExpansionPercent=161.8,
            hasPointFibonacciExpansionPercent=true,pointRate=1.23456,hasPointRate=true,
            gmmaTrendCount=4,hasGmmaTrendCount=true,gmmaCrossCount=-1,hasGmmaCrossCount=true
        };
        Check(adapter.fillTableRow(elliot,wave,live),"live latest point is available");
        SavedAdapter.fillTableRow(frame,"M15",saved);
        string[] expected={"M15","BUY","SELL","活発 1.38","[3副] 【未】★▼3.i[2][F61.8%]<-12.5p>1.23456"};
        int[] colors={3,3,4,5,2};
        for(int i=0;i<5;i++) {
            Check(ElliotTableFormatter.cellText(live,i,5)==expected[i],"live expected cell "+i);
            Check(ElliotTableFormatter.cellText(saved,i,5)==expected[i],"saved expected cell "+i);
            Check(ElliotTableFormatter.cellColor(live,i,palette)==colors[i] && ElliotTableFormatter.cellColor(saved,i,palette)==colors[i],"same palette and rules for cell "+i);
        }
        Check(ElliotTableFormatter.gmmaCellText(live,0)=="+4" && ElliotTableFormatter.gmmaCellText(saved,0)=="+4","current and saved trend count use the same signed display");
        Check(ElliotTableFormatter.gmmaCellText(live,1)=="-1" && ElliotTableFormatter.gmmaCellText(saved,1)=="-1","negative one remains a valid cross count in both adapters");
        Check(ElliotTableFormatter.gmmaCellColor(live,0,palette)==3 && ElliotTableFormatter.gmmaCellColor(saved,1,palette)==4,"GMMA colors follow each count independently of wave direction");
        frame.hasGmmaCrossCount=false;SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.gmmaCellText(saved,1)=="?" && ElliotTableFormatter.gmmaCellText(live,1)=="-1","missing saved GMMA never borrows the current value");
        Check(ElliotTableFormatter.waveText(live,0)=="▼3.i" && ElliotTableFormatter.waveColor(saved,palette)==8,"hover uses downward wave, independent of BUY analysis");
        palette.upColor=101;palette.unconfirmedUpColor=102;wave.point.isAddedPoint=false;frame.isAdded=0;
        adapter.fillTableRow(elliot,wave,live);SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.cellColor(live,1,palette)==101 && ElliotTableFormatter.cellColor(saved,4,palette)==102,"custom chart colors shared with saved table");
        elliot.oscillator.priceMovement.isValid=false;frame.isPriceMovementValid=0;frame.hasPriceMovementActivityRatio=false;
        adapter.fillTableRow(elliot,wave,live);SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.cellText(live,3,5)=="判定不能" && ElliotTableFormatter.cellText(saved,3,5)=="判定不能","invalid movement is consistent");
        frame.pointRate=0;frame.hasPointRate=true;wave.point.rate=0;
        adapter.fillTableRow(elliot,wave,live);SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.cellText(live,4,5).EndsWith("0.00000") && ElliotTableFormatter.cellText(saved,4,5).EndsWith("0.00000"),"recorded zero is preserved by both adapters");
        frame.hasPointRate=false;SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.cellText(saved,4,5).EndsWith("未記録"),"saved missing price is never filled with live zero");
        wave.point.subElliotLabel=null;frame.subWave=null;
        adapter.fillTableRow(elliot,wave,live);SavedAdapter.fillTableRow(frame,"M15",saved);
        Check(ElliotTableFormatter.waveText(live,0)=="▼3" && ElliotTableFormatter.waveText(saved,0)=="▼3","null subwave from either source never adds a trailing dot");
        wave.point=null;
        Check(!adapter.fillTableRow(elliot,wave,live) && !live.hasData && !live.hasPointRate,"missing live point clears stale row");
        frame.clear();SavedAdapter.fillTableRow(frame,"M5",saved);
        Check(ElliotTableFormatter.cellText(saved,0,5)=="M5" && ElliotTableFormatter.cellText(saved,1,5)=="未記録","missing saved row retains its timeframe only");
        elliot.marketContext.timeFrameLabel="M1";wave.point=new ZigZagPoint();adapter.fillTableRow(elliot,wave,live);
        Check(ElliotTableFormatter.cellText(live,0,5)=="M1","live M1 remains available without inventing a saved M1 row");
        return "PASS "+checks+" shared adapter assertions";
    }
}
'''
        output = run_csharp(adapted, "[SharedAdapterFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ shared adapter assertions")


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
        adapted += extracted_methods(SAVED_ADAPTER.read_text(encoding="utf-8-sig"), (
            "strengthTitle", "strengthStatusText",
        ))
        adapted += extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "strengthRankText", "strengthGapText",
            "strengthDeltaText", "strengthValueColor",
        )) + "\n}"
        output = run_csharp(adapted, "[StrengthTextFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ strength text assertions")

    def test_chart_table_formatters_match_saved_directions_states_and_numbers(self):
        adapted = "using System;using System.Globalization;\n" + table_fixture() + r'''
public class TableFixture {
    const int clrSilver=1,clrWhite=2,clrAqua=3,clrHotPink=4,clrDodgerBlue=5,clrMagenta=6;
    static int checks;
    static void Check(bool condition,string message) { checks++;if(!condition) throw new Exception(message); }
    public static string Run() {
        ElliotTableRowData frame=new ElliotTableRowData();
        ElliotTablePalette palette=new ElliotTablePalette();
        Check(ElliotTableFormatter.cellText(frame,4,5)=="未記録","missing timeframe");
        Check(ElliotTableFormatter.cellText(frame,2,5)=="未記録" && ElliotTableFormatter.cellText(frame,3,5)=="未記録","missing indicators");
        frame.hasData=true;frame.mainWave="3";frame.subWave="i";frame.originalWave="2";
        frame.isUptrend=0;frame.isBuy=1;frame.isConfirmed=0;frame.isAdded=1;
        frame.originalWaveIndex=2;frame.previousMotiveSubElliotIndex=3;
        frame.pointPipsDiff=-12.5;frame.hasPointPipsDiff=true;
        frame.pointFibonacciPercent=61.8;frame.hasPointFibonacciPercent=true;
        frame.pointFibonacciExpansionPercent=161.8;frame.hasPointFibonacciExpansionPercent=true;
        frame.pointRate=1.23456;frame.hasPointRate=true;
        string text=ElliotTableFormatter.cellText(frame,4,5);
        Check(text.Contains("[3副]") && text.Contains("【未】") && text.Contains("★▼3.i[2]"),"saved wave and states");
        Check(text.Contains("[F61.8%]") && !text.Contains("[FE"),"F uses original even index, not current main wave");
        Check(text.Contains("<-12.5p>") && text.EndsWith("1.23456"),"signed pips and symbol price precision");
        Check(ElliotTableFormatter.cellColor(frame,1,palette)==clrAqua && ElliotTableFormatter.cellColor(frame,4,palette)==clrWhite,"added point white has priority");
        frame.isAdded=0;Check(ElliotTableFormatter.cellColor(frame,4,palette)==clrDodgerBlue,"unconfirmed BUY blue despite downward wave");
        frame.isConfirmed=1;Check(ElliotTableFormatter.cellColor(frame,4,palette)==clrAqua,"confirmed BUY aqua");
        frame.isBuy=0;Check(ElliotTableFormatter.cellColor(frame,4,palette)==clrHotPink,"confirmed SELL pink");
        frame.isConfirmed=0;Check(ElliotTableFormatter.cellColor(frame,4,palette)==clrMagenta,"unconfirmed SELL magenta");
        frame.isAdded=-1;Check(ElliotTableFormatter.cellColor(frame,4,palette)==clrSilver,"unknown point state is not invented");
        frame.originalWaveIndex=3;frame.originalWave="3";frame.previousMotiveSubElliotIndex=0;
        text=ElliotTableFormatter.cellText(frame,4,5);
        Check(text.Contains("[FE161.8%]") && !text.Contains("[F61.8%]"),"FE uses original odd index");
        Check(!text.Contains("副]") && !text.Contains("[3]"),"zero preceding wave and unchanged original omitted");
        frame.originalWaveIndex=1;text=ElliotTableFormatter.cellText(frame,4,5);
        Check(!text.Contains("[F"),"wave one has no F/FE display");
        frame.originalWaveIndex=2;frame.hasPointFibonacciPercent=false;
        Check(ElliotTableFormatter.cellText(frame,4,5).Contains("[F未記録]"),"missing F is not zero percent");
        frame.originalWaveIndex=-1;
        Check(ElliotTableFormatter.cellText(frame,4,5).Contains("[F/FE未記録]"),"unknown original index not inferred from label");
        frame.originalWaveIndex=2;frame.hasPointFibonacciPercent=true;frame.pointFibonacciPercent=0;
        Check(ElliotTableFormatter.cellText(frame,4,5).Contains("[F0.0%]"),"recorded zero percent retained");
        frame.isEma200Buy=0;frame.isEma200Sell=1;
        Check(ElliotTableFormatter.cellText(frame,2,5)=="SELL" && ElliotTableFormatter.cellColor(frame,2,palette)==clrHotPink,"EMA independent SELL");
        frame.isEma200Sell=0;
        Check(ElliotTableFormatter.cellText(frame,2,5)=="NONE" && ElliotTableFormatter.cellColor(frame,2,palette)==clrWhite,"EMA NONE distinct from missing");
        frame.isEma200Buy=-1;
        Check(ElliotTableFormatter.cellText(frame,2,5)=="未記録" && ElliotTableFormatter.cellColor(frame,2,palette)==clrSilver,"EMA missing flag not NONE");
        frame.isEma200Buy=1;frame.isEma200Sell=1;
        Check(ElliotTableFormatter.cellText(frame,2,5)=="判定不能" && ElliotTableFormatter.cellColor(frame,2,palette)==clrSilver,"contradictory EMA flags are not BUY");
        frame.isPriceMovementValid=0;
        Check(ElliotTableFormatter.cellText(frame,3,5)=="判定不能" && ElliotTableFormatter.cellColor(frame,3,palette)==clrSilver,"saved invalid movement");
        frame.isPriceMovementValid=1;frame.priceMovementLevel=3;
        frame.hasPriceMovementActivityRatio=true;frame.priceMovementActivityRatio=1.375;
        Check(ElliotTableFormatter.cellText(frame,3,5)=="活発 1.38" && ElliotTableFormatter.cellColor(frame,3,palette)==clrDodgerBlue,"active movement and two decimals");
        frame.priceMovementLevel=2;frame.priceMovementActivityRatio=0;
        Check(ElliotTableFormatter.cellText(frame,3,5)=="通常 0.00" && ElliotTableFormatter.cellColor(frame,3,palette)==clrWhite,"zero activity is recorded");
        frame.hasPriceMovementActivityRatio=false;
        Check(ElliotTableFormatter.cellText(frame,3,5).Contains("未記録"),"missing activity not zero");
        frame.priceMovementLevel=-1;
        Check(ElliotTableFormatter.cellText(frame,3,5)=="未記録" && ElliotTableFormatter.cellColor(frame,3,palette)==clrSilver,"missing movement level not invalid");
        frame.mainWave="B";frame.subWave=null;frame.originalWave=null;frame.originalWaveIndex=0;
        Check(ElliotTableFormatter.waveText(frame,0)=="▼B","null subwave produces no trailing dot");
        string nullLabels=ElliotTableFormatter.cellText(frame,4,5);
        Check(!nullLabels.Contains("B.") && !nullLabels.Contains("[]"),"null subwave and original wave add no punctuation");
        frame.subWave="";frame.originalWave="";
        Check(ElliotTableFormatter.cellText(frame,4,5)==nullLabels,"empty and null optional labels are equivalent");
        frame.mainWave=null;
        Check(ElliotTableFormatter.waveText(frame,0)=="▼—","null main wave is explicitly unknown");
        frame.mainWave="";
        Check(ElliotTableFormatter.waveText(frame,0)=="▼—","empty main wave uses the same unknown label");
        return "PASS "+checks+" table assertions";
    }
'''
        adapted += "\n}"
        output = run_csharp(adapted, "[TableFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ table assertions")

    def test_production_formatter_with_saved_missing_and_long_labels(self):
        source = DRAWER.read_text(encoding="utf-8-sig")
        adapted = "using System;using System.Globalization;\n" + frame_fixture() + table_fixture() + r'''
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
        Check(ElliotPanelSavedAdapter.timeText(stamp)=="2026/11/25 11:35:00","chart date format includes seconds");
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
        adapted += extracted_methods(source, ("formatTooltip", "waveText", "shorten"))
        adapted += "\nstatic class ElliotPanelSavedAdapter {\n"
        adapted += extracted_methods(SAVED_ADAPTER.read_text(encoding="utf-8-sig"), (
            "frameName", "fillTableRow", "timeText",
        )) + "\n}\n}"
        output = run_csharp(adapted, "[TooltipFixture]::Run()\n")
        self.assertRegex(output, r"PASS \d+ tooltip assertions")


if __name__ == "__main__":
    unittest.main()
