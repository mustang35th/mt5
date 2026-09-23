"""Read MstngH1EaAll baseline CSVs and print a report; never modifies MT5 or its DB."""

import argparse
import csv
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from itertools import groupby
from pathlib import Path


def readRows(path):
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if not reader.fieldnames or len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError(f"Invalid header: {path.name}")
        for row in reader:
            if None in row or None in row.values():
                raise ValueError(f"Invalid field count: {path.name}")
            yield row


def decimal(value):
    result = Decimal(value)
    if not result.is_finite():
        raise ValueError("Non-finite numeric value")
    return result


def serverTime(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def replayDeals(rows, scope, startMsc, endMsc):
    """Hedging position ID + volume replay. Timestamp groups define duration weights."""
    deals = []
    tickets = set()
    foreignDeals = 0
    ownedIds = set()
    for row in rows:
        ticket = int(row["ticket"])
        if ticket <= 0 or ticket in tickets:
            raise ValueError("Invalid or duplicate deal ticket")
        tickets.add(ticket)
        dealType = int(row["type"])
        if dealType not in (0, 1):
            # Balance/commission/canceled deals are retained in CSV. MT5 statistics
            # remain authoritative for account P/L, including these cash flows.
            continue
        deal = dict(row)
        for field in ("timeMsc", "positionId", "magic", "entry", "type"):
            deal[field] = int(row[field])
        deal["ticket"] = ticket
        deal["volume"] = decimal(row["volume"])
        if deal["volume"] <= 0 or deal["positionId"] <= 0:
            raise ValueError("Invalid deal volume or position ID")
        if deal["entry"] == 0 and (deal["symbol"], deal["magic"]) in scope:
            ownedIds.add(deal["positionId"])
        deals.append(deal)
    deals.sort(key=lambda deal: (deal["timeMsc"], deal["ticket"]))
    if deals and deals[-1]["timeMsc"] >= endMsc + 1000:
        raise ValueError("Deal history exceeds testEnd")
    if deals:
        endMsc = max(endMsc, deals[-1]["timeMsc"])
    positions = {}
    histogram = defaultdict(int)
    previous = startMsc
    settledPeak = 0
    orderedPeak = 0
    peakTime = startMsc
    netDealProfit = Decimal(0)
    for timeMsc, group in groupby(deals, key=lambda deal: deal["timeMsc"]):
        relevant = []
        for deal in group:
            if deal["positionId"] not in ownedIds:
                if (deal["symbol"], deal["magic"]) in scope:
                    raise ValueError("Managed exit without opening history")
                foreignDeals += 1
                continue
            if timeMsc < startMsc:
                raise ValueError("Managed deal before trade start; baseline is not isolated")
            relevant.append(deal)
        if not relevant:
            continue
        histogram[len(positions)] += timeMsc - previous
        previous = timeMsc
        for deal in relevant:
            positionId = deal["positionId"]
            if deal["entry"] == 0:
                existing = positions.get(positionId)
                if existing and (existing["symbol"], existing["type"]) != (deal["symbol"], deal["type"]):
                    raise ValueError("Position identity changed")
                if not existing:
                    if any(position["symbol"] == deal["symbol"] for position in positions.values()):
                        raise ValueError("More than one managed position for a symbol")
                    positions[positionId] = {"symbol": deal["symbol"], "type": deal["type"], "volume": Decimal(0)}
                positions[positionId]["volume"] += deal["volume"]
            elif deal["entry"] in (1, 3):
                existing = positions.get(positionId)
                if (not existing or existing["symbol"] != deal["symbol"]
                        or existing["type"] == deal["type"] or deal["volume"] > existing["volume"]):
                    raise ValueError("Unmatched/invalid exit or missing deal history")
                existing["volume"] -= deal["volume"]
                if existing["volume"] == 0:
                    del positions[positionId]
            else:
                raise ValueError("INOUT/reversal is unsupported for the hedging baseline")
            orderedPeak = max(orderedPeak, len(positions))
            netDealProfit += sum((decimal(deal[field]) for field in ("profit", "commission", "swap", "fee")), Decimal(0))
        if len(positions) > settledPeak:
            settledPeak = len(positions)
            peakTime = timeMsc
    histogram[len(positions)] += endMsc - previous
    duration = endMsc - startMsc
    if duration <= 0:
        raise ValueError("No measurable test duration after trade start")
    mean = sum(count * durationMsc for count, durationMsc in histogram.items()) / duration
    percentiles = {}
    for percentile in (50, 90, 95, 99):
        cumulative = 0
        for count, durationMsc in sorted(histogram.items()):
            cumulative += durationMsc
            if cumulative * 100 >= duration * percentile:
                percentiles[percentile] = count
                break
    return {"histogram": dict(histogram), "durationMsc": duration, "mean": mean,
            "percentiles": percentiles, "settledPeak": settledPeak, "orderedPeak": orderedPeak,
            "peakTime": peakTime, "openAtEnd": len(positions), "foreignDeals": foreignDeals,
            "netDealProfit": netDealProfit, "endMsc": endMsc}


def aggregateSamples(rows, start, end):
    result = {"rows": 0, "positions": 0, "pendingOrders": 0, "foreignPositions": 0,
              "foreignOrders": 0, "margin": Decimal(0), "slRiskKnown": Decimal(0),
              "unknownRiskRows": 0, "readErrors": 0, "currencySlots": {}, "maxGapSeconds": 0}
    previous = None
    for row in rows:
        now = int(row["serverTime"])
        if now < start or now > end or (previous is not None and now < previous):
            raise ValueError("Invalid sample timestamp/order")
        if previous is not None:
            result["maxGapSeconds"] = max(result["maxGapSeconds"], now - previous)
        previous = now
        result["rows"] += 1
        for field in ("positions", "pendingOrders", "foreignPositions", "foreignOrders"):
            value = int(row[field])
            if value < 0:
                raise ValueError("Negative count")
            result[field] = max(result[field], value)
        for field in ("balance", "equity", "margin", "freeMargin", "marginLevel", "openProfit", "slRiskKnown"):
            value = decimal(row[field])
            if field in ("margin", "slRiskKnown"):
                result[field] = max(result[field], value)
        result["unknownRiskRows"] += int(row["slRiskUnknown"]) > 0
        result["readErrors"] += int(row["readErrors"])
        for entry in filter(None, row["currencySlots"].split("|")):
            currency, longCount, shortCount = entry.split(":")
            slots = result["currencySlots"].setdefault(currency, {"long": 0, "short": 0, "gross": 0})
            longCount, shortCount = int(longCount), int(shortCount)
            if min(longCount, shortCount) < 0:
                raise ValueError("Negative currency exposure count")
            slots["long"] = max(slots["long"], longCount)
            slots["short"] = max(slots["short"], shortCount)
            slots["gross"] = max(slots["gross"], longCount + shortCount)
    if not result["rows"]:
        raise ValueError("No portfolio samples")
    return result


def buildReport(folder):
    status = list(readRows(folder / "status.csv"))
    if status != [{"key": "exportState", "value": "EXPORTED"}]:
        raise ValueError("Missing export completion marker")
    summaryRows = list(readRows(folder / "summary.csv"))
    summary = {row["key"]: row["value"] for row in summaryRows}
    if len(summary) != len(summaryRows):
        raise ValueError("Duplicate summary key")
    if (summary["schema"] != "H1_EA_BASELINE_V1" or summary["finalization"] != "ONTESTER"
            or summary["ioFailed"] != "0" or summary["globalPositionLimit"] != "0"):
        raise ValueError("Incomplete or unsupported baseline export")
    runs = list(readRows(folder / "runs.csv"))
    scope = {(row["symbol"], int(row["magic"])) for row in runs}
    if (len(runs) != 28 or len(scope) != 28 or len({row["symbol"] for row in runs}) != 28
            or len({row["sessionUid"] for row in runs}) != 1
            or any("|GLOBAL_POSITION_LIMIT=0|" not in row["configText"] + "|" for row in runs)):
        raise ValueError("Expected one unlimited 28-symbol session")
    start = max(int(summary["testStart"]), int(summary["tradeStart"]))
    end = int(summary["testEnd"])
    if end <= start:
        raise ValueError("Test never reached the measurement period")
    samples = aggregateSamples(readRows(folder / "samples.csv"), start, end)
    if samples["rows"] != int(summary["sampleRows"]):
        raise ValueError("Truncated sample CSV")
    dealRows = list(readRows(folder / "deals.csv"))
    if len(dealRows) != int(summary["dealRows"]):
        raise ValueError("Truncated deal CSV")
    deals = replayDeals(dealRows, scope, start * 1000, end * 1000)
    if samples["positions"] > deals["orderedPeak"]:
        raise ValueError("Sampled positions exceed deal-history peak; missing opening history")
    warnings = []
    if deals["foreignDeals"] or samples["foreignPositions"] or samples["foreignOrders"]:
        warnings.append("対象外取引あり。口座成績と対象EAの成績を同一視できません。")
    if int(summary["readErrors"]) or samples["readErrors"]:
        warnings.append("読取失敗あり。保有・リスクのサンプルが不完全です。")
    if samples["unknownRiskRows"]:
        warnings.append("SLリスク不明のサンプルあり。既知部分の合計を総リスクにしないでください。")
    if deals["openAtEnd"]:
        warnings.append("終了時に未決済ポジションが残っています。")
    lines = ["# MstngH1EaAll 基準バックテスト", "",
             f"Session: `{runs[0]['sessionUid']}` / EA {runs[0]['programVersion']}", "",
             f"対象期間（サーバー時刻）: {serverTime(start * 1000)} ～ {serverTime(deals['endMsc'])}",
             "全体上限なし・通貨ごとに1ポジション。観測最大値から運用上限を自動決定しません。", "",
             "| 項目 | 結果 |", "|---|---:|",
             f"| 口座通貨 / レバレッジ | {summary['accountCurrency']} / {summary['leverage']} |"]
    for label, key in (("初期証拠金", "initialDeposit"), ("純損益（MT5）", "netProfit"),
                       ("最大Equity DD金額（MT5）", "equityDrawdown"),
                       ("最大Equity DD率 %（MT5）", "equityDrawdownPercent"), ("取引数（MT5）", "trades")):
        lines.append(f"| {label} | {decimal(summary[key]):,.2f} |")
    lines.extend([f"| 最大同時保有数（同一ms処理後） | {deals['settledPeak']} |",
                  f"| 同一ms内のticket順参考最大 | {deals['orderedPeak']} |",
                  f"| 時間加重平均保有数 | {deals['mean']:.3f} |",
                  f"| 時間加重 P50 / P90 / P95 / P99 | {' / '.join(str(deals['percentiles'][key]) for key in (50, 90, 95, 99))} |",
                  f"| サンプル最大保有 / 未完了注文数 | {samples['positions']} / {samples['pendingOrders']} |",
                  f"| サンプル最大証拠金使用額 | {samples['margin']:,.2f} |",
                  f"| サンプル最大SL追加損失見込（既知部分） | {samples['slRiskKnown']:,.2f} |", "",
                  "## 同時保有数の時間分布", "", "| 保有数 | 時間（時間） | 比率 |", "|---:|---:|---:|"])
    for count, duration in sorted(deals["histogram"].items()):
        lines.append(f"| {count} | {duration / 3600000:.4f} | {100 * duration / deals['durationMsc']:.3f}% |")
    lines.extend(["", "## 通貨集中（サンプル最大件数）", "",
                  "| 通貨 | 買い側 | 売り側 | 両側合計 |", "|---|---:|---:|---:|"])
    for currency, slots in sorted(samples["currencySlots"].items()):
        lines.append(f"| {currency} | {slots['long']} | {slots['short']} | {slots['gross']} |")
    lines.extend(["", "## 検証上の注意", "",
                  "- MT5のテスター設定・レポートも保存し、予定の終了日まで到達したか確認してください。OnTester到達だけでは完走の証明になりません。",
                  "- 同時保有の分布は約定のposition IDと残量から復元し、未保有・週末を含む経過時間で重み付けします。部分決済は残量0まで保有扱いです。",
                  "- 同一ミリ秒内の厳密な約定順は不明です。ticket順の参考最大と、同一ms処理後の最大を分けています。",
                  "- SLリスクは現在価格からbroker設定済みSLまでの追加損失見込です。手数料・滑り・窓開け・保留SL・未約定注文は含みません。",
                  "- リスク・証拠金・通貨集中は最短1秒の観測値で、瞬間的な最大値は保証しません。通貨集中は金額ではなく件数です。",
                  "- 同値サンプルは60秒ごとに圧縮します。時刻の間隔から相場が完全に観測されたとは判断できません。",
                  "- 上限候補を決めた後は、その上限で再テストし、別期間でも比較してください。"])
    lines.extend(f"- **要確認**: {warning}" for warning in warnings)
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Common/Files/MstngH1Ea/Backtests/<sessionUid>")
    parser.add_argument("--output", type=Path, help="New Markdown file (existing files are not overwritten)")
    args = parser.parse_args()
    try:
        report = buildReport(args.folder)
        if args.output:
            with args.output.open("x", encoding="utf-8", newline="\n") as destination:
                destination.write(report)
        else:
            print(report, end="")
    except (OSError, ValueError, KeyError, ArithmeticError) as error:
        parser.exit(1, f"Baseline report failed: {error}\n")


if __name__ == "__main__":
    main()
