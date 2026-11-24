"""Normalize saved alert price movement without recomputing market data."""

from __future__ import annotations

import math
import sys
from collections.abc import Mapping
from typing import Any


PRICE_MOVEMENT_COLUMNS = frozenset({
    "is_price_movement_valid",
    "price_movement_level",
    "price_movement_average_range_pips",
    "price_movement_reference_atr_pips",
    "price_movement_activity_ratio",
    "is_price_movement_spread_valid",
    "price_movement_range_spread_ratio",
    "price_movement_reference_bar_time",
})


def _integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _flag(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if _integer(value) and value in (0, 1):
        return value == 1
    return None


def _number(value: Any) -> bool:
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value != sys.float_info.max)


def _unavailable_status(run: Mapping[str, Any] | None) -> str:
    if run is None:
        return "UNKNOWN"
    schema = run.get("schema_version")
    if _integer(schema) and schema >= 10:
        return "UNAVAILABLE"
    input_text = run.get("input_text")
    if isinstance(input_text, str):
        versions = [part.partition("=")[2] for part in input_text.split("|")
                    if part.partition("=")[0] == "priceMovementVersion"]
        if len(versions) == 1 and versions[0].strip():
            return "UNAVAILABLE"
    if _integer(schema) and 0 < schema < 10:
        return "UNRECORDED"
    return "UNKNOWN"


def price_movement_snapshot(
    row: Mapping[str, Any], run: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return optional movement fields; missing or invalid values remain null."""
    result: dict[str, Any] = {
        "price_movement_status": "UNRECORDED",
        "is_price_movement_valid": False,
        "price_movement_level": None,
        "price_movement_average_range_pips": None,
        "price_movement_reference_atr_pips": None,
        "price_movement_activity_ratio": None,
        "is_price_movement_spread_valid": False,
        "price_movement_range_spread_ratio": None,
        "price_movement_reference_bar_time": None,
    }
    if not PRICE_MOVEMENT_COLUMNS.issubset(row):
        return result

    result["price_movement_status"] = _unavailable_status(run)
    level = row["price_movement_level"]
    average = row["price_movement_average_range_pips"]
    reference = row["price_movement_reference_atr_pips"]
    activity = row["price_movement_activity_ratio"]
    bar_time = row["price_movement_reference_bar_time"]
    if (_flag(row["is_price_movement_valid"]) is not True
            or not _integer(level) or level not in (1, 2, 3)
            or not _number(average) or average < 0
            or not _number(reference) or reference <= 0
            or not _number(activity) or activity < 0
            or not _integer(bar_time) or bar_time <= 0):
        return result

    result.update({
        "price_movement_status": "VALID",
        "is_price_movement_valid": True,
        "price_movement_level": level,
        "price_movement_average_range_pips": average,
        "price_movement_reference_atr_pips": reference,
        "price_movement_activity_ratio": activity,
        "price_movement_reference_bar_time": bar_time,
    })
    spread_ratio = row["price_movement_range_spread_ratio"]
    if (_flag(row["is_price_movement_spread_valid"]) is True
            and _number(spread_ratio) and spread_ratio >= 0):
        result["is_price_movement_spread_valid"] = True
        result["price_movement_range_spread_ratio"] = spread_ratio
    return result
