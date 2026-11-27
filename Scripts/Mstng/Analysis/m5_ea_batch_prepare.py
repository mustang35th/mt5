"""Prepare the fixed September 2026 M5 batch; read databases, never launch MT5."""

import argparse
import configparser
import hashlib
import io
import json
import re
import sqlite3
from collections import defaultdict
from contextlib import closing
from pathlib import Path


START = 1788739200
END = 1789171200
VERSION = "pair-direction-weighted-closed-v1"
CURRENCIES = set("USD EUR GBP AUD NZD CAD CHF JPY".split())
TIMEFRAMES = {49153, 32769, 16408, 16388, 16385, 15, 5}
ROOT = Path(__file__).resolve().parents[3]


def openReadOnly(fromPath, fromImmutable=False):
    """Use immutable only for an explicitly stopped tester database without sidecars."""
    path = fromPath.resolve(strict=True)
    suffix = "?mode=ro"
    if fromImmutable:
        if any(Path(str(path) + extension).exists() for extension in ("-wal", "-shm")):
            raise ValueError("Stopped tester DB must have no WAL/SHM for immutable reading")
        suffix += "&immutable=1"
    database = sqlite3.connect(path.as_uri() + suffix, uri=True, timeout=10)
    database.row_factory = sqlite3.Row
    database.execute("PRAGMA query_only=ON")
    database.execute("BEGIN")
    return database


def readSymbols():
    source = (ROOT / "Include/Mstng/Constant/SymbolNameInfoAll.mqh").read_text(encoding="utf-8-sig")
    body = source.split("void setAll() {", 1)[1].split("void setGmo()", 1)[0]
    symbols = re.findall(r"this\.add\(ConstantCurrency::([A-Z]{6}),\s*\d+,\s*true\)", body)
    if len(symbols) != 28 or len(set(symbols)) != 28:
        raise ValueError("Expected exactly 28 distinct symbols in setAll")
    pairs = {frozenset((symbol[:3], symbol[3:])) for symbol in symbols}
    if len(pairs) != 28 or any(len(pair) != 2 or not pair <= CURRENCIES for pair in pairs):
        raise ValueError("Symbols must cover the 28 pairs of the eight currencies")
    return symbols


def readIdentity(fromDatabase, fromRunId, fromImmutable):
    with closing(openReadOnly(fromDatabase, fromImmutable)) as database:
        run = database.execute(
            "SELECT * FROM m5_ea_runs WHERE id=?", (fromRunId,)
        ).fetchone()
        if not run or run["source_mode"] != "TESTER" or run["status"] != "STOPPED":
            raise ValueError("Reference run must be a completed TESTER run")
        if run["program_version"] != "1.02" or run["time_frame"] != 5:
            raise ValueError("Reference run must use M5 v1.02")
        return run["account_server"], run["account_login"]


def inspectStrength(fromPath, fromIdentity, fromSymbols):
    """Check every M5 slot and its actual results/votes in one read transaction."""
    with closing(openReadOnly(fromPath)) as database:
        runs = database.execute(
            "SELECT * FROM currency_strength_runs WHERE m5_bar_time>=? AND m5_bar_time<? "
            "AND calculation_version=? AND source_mode='LIVE' "
            "AND source_server=? AND source_login=? ORDER BY m5_bar_time,id",
            (START - 300, END, VERSION, *fromIdentity),
        ).fetchall()
        completeTimes = set()
        seenTimes = set()
        invalidTimes = []
        resultCount = 0
        voteCount = 0
        digest = hashlib.sha256()
        for run in runs:
            barTime = run["m5_bar_time"]
            results = database.execute(
                "SELECT currency_name,long_medium_term_average_rank,medium_short_term_average_rank "
                "FROM currency_strength_results WHERE run_id=? ORDER BY currency_name", (run["id"],)
            ).fetchall()
            votes = database.execute(
                "SELECT canonical_symbol_name,resolved_symbol_name,time_frame "
                "FROM currency_strength_pair_votes WHERE run_id=? "
                "ORDER BY canonical_symbol_name,time_frame", (run["id"],)
            ).fetchall()
            actualPairs = defaultdict(list)
            for vote in votes:
                actualPairs[vote["canonical_symbol_name"]].append(vote["time_frame"])
            valid = (
                run["is_complete"] == 1
                and run["valid_pair_count"] == run["expected_pair_count"] == 28
                and run["vote_count"] == len(votes) == 196
                and len(results) == 8
                and {row[0] for row in results} == CURRENCIES
                and all(1 <= row[1] <= 8 and 1 <= row[2] <= 8 for row in results)
                and set(actualPairs) == set(fromSymbols)
                and all(len(frames) == 7 and set(frames) == TIMEFRAMES for frames in actualPairs.values())
                and all(row[0] == row[1] for row in votes)
                and barTime not in seenTimes
            )
            seenTimes.add(barTime)
            if valid:
                completeTimes.add(barTime)
            else:
                invalidTimes.append(barTime)
            if barTime >= START:
                resultCount += len(results)
                voteCount += len(votes)
                payload = [barTime, run["is_complete"], run["valid_pair_count"],
                           run["expected_pair_count"], run["vote_count"],
                           [list(row) for row in results], [list(row) for row in votes]]
                digest.update((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
        expectedTimes = set(range(START, END, 300))
        missingTimes = sorted(expectedTimes - completeTimes)
        return {
            "source": "LIVE", "calculationVersion": VERSION,
            "matchesReferenceRunIdentity": bool(runs),
            "expectedSlots": len(expectedTimes),
            "completeSlots": len(expectedTimes & completeTimes),
            "missingOrInvalidSlots": missingTimes, "invalidSlots": invalidTimes,
            "resultRows": resultCount, "voteRows": voteCount,
            "rankAndVoteSnapshotSha256": digest.hexdigest(),
            "previousSlotAvailable": START - 300 in completeTimes,
            "passed": not missingTimes and not invalidTimes,
        }


def inspectHistory(fromBase, fromSymbol):
    """File presence is an inventory, not verification of history/tick coverage."""
    missingYears = []
    for year in range(2020, 2027):
        path = fromBase / "history" / fromSymbol / f"{year}.hcc"
        if not path.is_file() or path.stat().st_size == 0:
            missingYears.append(year)
    ticks = fromBase / "ticks" / fromSymbol / "202609.tkc"
    tickBytes = 0
    if ticks.is_file():
        tickBytes = ticks.stat().st_size
    return {"missingHistoryYears": missingYears, "septemberTickFileBytes": tickBytes,
            "localFilesPresent": not missingYears and tickBytes > 0,
            "testerSynchronization": "NOT_CHECKED", "targetWeekTickCoverage": "NOT_CHECKED"}


def createPreset(fromTemplate, fromSymbol, fromTag):
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read_string(fromTemplate)
    tester = parser["Tester"]
    expected = {"Expert": "MstngM5Ea.ex5", "Symbol": "USDJPY", "Period": "M5",
                "Model": "4", "FromDate": "2021.12.01", "ToDate": "2026.09.12",
                "Optimization": "0", "Visual": "0", "UseLocal": "1", "UseRemote": "0",
                "UseCloud": "0", "Deposit": "10000", "Currency": "JPY", "Leverage": "100",
                "ReplaceReport": "0", "ShutdownTerminal": "0"}
    if any(tester.get(key) != value for key, value in expected.items()):
        raise ValueError("Standard preset changed; review the batch settings before generating")
    inputs = parser["TesterInputs"]
    if len(inputs) != 13 or inputs["testerTradeStartTime"].split("||")[0] != str(START):
        raise ValueError("Standard preset inputs changed")
    tester["Symbol"] = fromSymbol
    tester["Report"] = f"MstngM5Ea-{fromSymbol}-20260907-20260911-{fromTag}-v102"
    buffer = io.StringIO()
    parser.write(buffer, space_around_delimiters=False)
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--common-files", type=Path, required=True)
    parser.add_argument("--reference-run", type=int, required=True)
    parser.add_argument("--stopped-tester-db", action="store_true",
                        help="Use immutable reading only after the tester has stopped and sidecars are absent")
    parser.add_argument("--tag", required=True, help="New batch folder/report tag, e.g. Batch28-01")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,47}", args.tag):
        parser.error("tag must contain 1-48 ASCII letters, digits or hyphens")
    destination = ROOT / "output/MstngM5Ea/Backtests" / args.tag
    if destination.exists():
        parser.error("Batch folder already exists; use a new tag to preserve previous artifacts")
    symbols = readSymbols()
    identity = readIdentity(args.common_files / "mstng-m5-ea-tester.sqlite",
                            args.reference_run, args.stopped_tester_db)
    base = ROOT.parent / "bases" / identity[0]
    if base.parent.resolve() != (ROOT.parent / "bases").resolve():
        raise ValueError("Invalid server history folder")
    strength = inspectStrength(args.common_files / "mstng-currency-strength-2026.sqlite", identity, symbols)
    templatePath = ROOT / "Scripts/Mstng/ExpertAdvisor/BacktestPresets/MstngM5Ea.USDJPY.20260907_20260911.WarmupDeferred.ini"
    template = templatePath.read_text(encoding="utf-8-sig")
    presets = {symbol: createPreset(template, symbol, args.tag) for symbol in symbols}
    manifest = {"tag": args.tag, "referenceRun": args.reference_run,
                "referenceIdentityIsCurrentTerminalCheck": False,
                "tradeStart": "2026.09.07 00:00", "endExclusive": "2026.09.12",
                "templateSha256": hashlib.sha256(templatePath.read_bytes()).hexdigest(),
                "strength": strength, "runs": []}
    for symbol in symbols:
        manifest["runs"].append({"symbol": symbol, "preset": f"{symbol}.ini", "status": "PENDING",
                                 "runId": None, "history": inspectHistory(base, symbol)})
    # Validation is finished before writing; existing batches are never overwritten.
    destination.mkdir(parents=True, exist_ok=False)
    for symbol, content in presets.items():
        # MT5 build 6230 GUI did not apply settings from UTF-8 BOM INI files.
        (destination / f"{symbol}.ini").write_text(content, encoding="utf-16", newline="\r\n")
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    present = sum(row["history"]["localFilesPresent"] for row in manifest["runs"])
    print(json.dumps({"output": str(destination), "presets": len(presets),
                      "strengthPassed": strength["passed"], "completeSlots": strength["completeSlots"],
                      "localHistoryAndTickFilesPresent": present, "backtestsExecuted": 0}, ensure_ascii=False))
    if not strength["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
