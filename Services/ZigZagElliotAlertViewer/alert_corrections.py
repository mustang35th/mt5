"""Read and validate optional alert correction snapshots without changing SQLite."""

from __future__ import annotations

import logging
import math
from collections.abc import Callable, Mapping
from typing import Any

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

CORRECTION_TABLE = "zigzag_elliot_alert_corrections"
TIME_FRAME_TABLE = "zigzag_elliot_alert_corrected_timeframes"
POINT_TABLE = "zigzag_elliot_alert_corrected_points"
ORIGINAL_TIME_FRAME_TABLE = "zigzag_elliot_alert_timeframes"
ORIGINAL_POINT_TABLE = "zigzag_elliot_alert_points"
TIME_FRAMES = ((49153, "MN1"), (32769, "W1"), (16408, "D1"),
               (16388, "H4"), (16385, "H1"), (15, "M15"), (5, "M5"))

METADATA_COLUMNS = """
alert_id correction_status correction_time_frame original_direction corrected_direction
selected_analysis selected_alert_text selected_current_elliot_label selected_wave_summary_text
reference_price is_selected_stop_loss_available selected_stop_loss selected_risk_pips
original_lc0 original_lc5 original_lc10 original_lc15 original_loss_cut_diff_pips
original_loss_cut_diff_jpy corrected_lc0 corrected_lc5 corrected_lc10 corrected_lc15
corrected_loss_cut_diff_pips corrected_loss_cut_diff_jpy corrected_reference_point_time
original_analysis_text corrected_analysis_text corrected_elliot_csv_text comparison_hash
created_at created_at_text
""".split()
NUMBER_COLUMNS = """
reference_price selected_stop_loss selected_risk_pips original_lc0 original_lc5
original_lc10 original_lc15 original_loss_cut_diff_pips original_loss_cut_diff_jpy
corrected_lc0 corrected_lc5 corrected_lc10 corrected_lc15 corrected_loss_cut_diff_pips
corrected_loss_cut_diff_jpy
""".split()
INTEGER_COLUMNS = {"alert_id", "correction_time_frame", "is_selected_stop_loss_available",
                   "corrected_reference_point_time", "created_at"}
EMA_COLUMNS = {"is_ema200_buy", "is_ema200_sell"}
TIME_FRAME_COLUMNS = set("""
id alert_id time_frame time_frame_text time_frame_order is_current_time_frame is_buy
buy_sell_label wave_count latest_wave_index is_wave_confirmed is_wave_motive is_wave_uptrend
wave_trend_label previous_last_elliot_label point_count latest_elliot_index latest_elliot_label
latest_sub_elliot_index latest_sub_elliot_label previous_open previous_high previous_low
previous_close current_open current_high current_low current_close is_fibo_expansion_available
fe618_price fe1000_price fe1272_price fe1618_price fe2000_price distance_to_fe2000_pips
oscillator_count is_oscillator_buy stochastic_main_order stochastic_main_order_text
stochastic_main_direction_text stochastic_short_count stochastic_short_main stochastic_short_signal
stochastic_middle_count stochastic_middle_main stochastic_middle_signal stochastic_long_count
stochastic_long_main stochastic_long_signal gmma_trend_count gmma_cross_count ema30 ema60
ema30_ema60_diff_pips atr14_pips ema200_close1 ema200_shift1 ema200_compare ema200_slope_pips
ema200_close_diff_pips ema200_close_position ema200_slope_direction ema200_up_count ema200_down_count
ema200_trend_count raw_csv_text created_at created_at_text
""".split())
POINT_COLUMNS = set("""
id alert_timeframe_id point_order is_latest is_signal_reference rate bar_index bar_time bar_time_text
is_bar_time_next_available bar_time_next bar_time_next_text wave_bars_from_start is_peak is_added_point
pips_diff is_fibonacci_available fibonacci_percent fibo_depth_zone fibo_depth_zone_label
is_fibonacci_expansion_available fibonacci_expansion_percent is_elliot_alphabet elliot_index
elliot_label is_sub_elliot_available sub_elliot_index sub_elliot_label is_original_elliot_available
org_elliot_index org_elliot_label is_correct created_at created_at_text
""".split())


def _response(status: str, reason: str | None = None,
              metadata: dict[str, Any] | None = None,
              timeframes: list[dict[str, Any]] | None = None,
              points: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {"status": status, "reason": reason, "metadata": metadata,
            "timeframes": timeframes or [], "points": points or []}


def _columns(session: Session, table: str) -> set[str]:
    # Every identifier is a module constant, never a request value.
    return {row["name"] for row in session.execute(
        text(f'PRAGMA table_info("{table}")')
    ).mappings()}


def _number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _equal(left: Any, right: Any) -> bool:
    return _number(left) and _number(right) and math.isclose(left, right, rel_tol=1e-12, abs_tol=1e-10)


def _metadata_has_valid_types(metadata: Mapping[str, Any]) -> bool:
    for name in METADATA_COLUMNS:
        value = metadata[name]
        if name in NUMBER_COLUMNS:
            if not _number(value):
                return False
        elif name in INTEGER_COLUMNS:
            if not _integer(value):
                return False
        elif not isinstance(value, str):
            return False
    return True


def _metadata_reason(metadata: Mapping[str, Any], alert: Mapping[str, Any]) -> str | None:
    if (metadata["alert_id"] != alert["id"]
            or metadata["correction_status"] not in {"NONE", "APPLIED"}
            or metadata["selected_analysis"] not in {"ORIGINAL", "CORRECTED"}
            or metadata["is_selected_stop_loss_available"] not in {0, 1}
            or not metadata["comparison_hash"] or not metadata["original_analysis_text"]
            or not metadata["selected_alert_text"] or not metadata["selected_wave_summary_text"]
            or metadata["created_at"] <= 0 or not metadata["created_at_text"]):
        return "補正情報の状態または識別情報が不整合です。"
    if (not _equal(metadata["reference_price"], alert.get("reference_price"))
            or not _equal(metadata["original_lc5"], alert.get("stop_loss"))
            or metadata["selected_current_elliot_label"] != alert.get("current_elliot_label")
            or metadata["selected_risk_pips"] < 0):
        return "元のアラートと採用分析の価格・波動情報が一致しません。"
    available = metadata["reference_price"] > 0 and metadata["selected_stop_loss"] > 0
    if (bool(metadata["is_selected_stop_loss_available"]) != available
            or (not available and metadata["selected_risk_pips"] != 0)):
        return "採用した損切りの有効状態が不整合です。"
    if metadata["correction_status"] == "NONE":
        empty_numbers = [name for name in NUMBER_COLUMNS if name.startswith("corrected_")]
        if (metadata["selected_analysis"] != "ORIGINAL" or metadata["correction_time_frame"] != 0
                or metadata["original_direction"] != "" or metadata["corrected_direction"] != ""
                or metadata["corrected_reference_point_time"] != 0
                or metadata["corrected_analysis_text"] != "" or metadata["corrected_elliot_csv_text"] != ""
                or any(metadata[name] != 0 for name in empty_numbers)
                or not _equal(metadata["selected_stop_loss"], metadata["original_lc5"])
                or not _equal(metadata["selected_risk_pips"], alert.get("risk_pips"))):
            return "補正なしの記録に補正後の値が混在しています。"
    elif (alert.get("time_frame") != 5 or alert.get("time_frame_text") != "M5"
            or metadata["selected_analysis"] != "CORRECTED"
            or metadata["correction_time_frame"] not in {16385, 16388}
            or metadata["original_direction"] not in {"BUY", "SELL"}
            or metadata["corrected_direction"] not in {"BUY", "SELL"}
            or metadata["original_direction"] == metadata["corrected_direction"]
            or metadata["corrected_direction"] != alert.get("side")
            or not _equal(metadata["selected_stop_loss"], metadata["corrected_lc5"])
            or metadata["corrected_reference_point_time"] <= 0
            or not metadata["corrected_analysis_text"] or not metadata["corrected_elliot_csv_text"]):
        return "補正した時間足・方向・採用損切りが不整合です。"
    return None


def _read_analysis(session: Session, timeframe_table: str, point_table: str,
                   alert_id: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    parameters = {"alert_id": alert_id}
    timeframes = [dict(row) for row in session.execute(text(f"""
        SELECT * FROM {timeframe_table} WHERE alert_id = :alert_id
        ORDER BY time_frame_order, id
    """), parameters).mappings()]
    points = [dict(row) for row in session.execute(text(f"""
        SELECT tf.alert_id, tf.time_frame, tf.time_frame_text, tf.time_frame_order, p.*
        FROM {timeframe_table} AS tf
        INNER JOIN {point_table} AS p ON p.alert_timeframe_id = tf.id
        WHERE tf.alert_id = :alert_id ORDER BY tf.time_frame_order, p.point_order, p.id
    """), parameters).mappings()]
    return timeframes, points


def _analysis_reason(timeframes: list[dict[str, Any]], points: list[dict[str, Any]],
                     alert: Mapping[str, Any], reference_time: int, reference_rate: float,
                     require_seven: bool) -> str | None:
    if not timeframes or not points:
        return "時間足または波動ポイントが保存されていません。"
    for row in [*timeframes, *points]:
        for name, value in row.items():
            if value is not None and not isinstance(value, (str, int, float)):
                return "分析値の保存形式が不正です。"
            if isinstance(value, float) and not math.isfinite(value):
                return "分析値に無効な数値があります。"
            if name.startswith("is_") and value not in (None, 0, 1):
                return "分析値の状態フラグが不正です。"
    if require_seven and [(row["time_frame"], row["time_frame_text"]) for row in timeframes] != list(TIME_FRAMES):
        return "MN1からM5までの7時間足が揃っていません。"
    ids = [row["id"] for row in timeframes]
    frames = [row["time_frame"] for row in timeframes]
    if (any(not _integer(value) or value <= 0 for value in ids + frames)
            or len(set(ids)) != len(ids) or len(set(frames)) != len(frames)
            or [row["time_frame_order"] for row in timeframes] != list(range(len(timeframes)))):
        return "時間足の識別子または表示順が不整合です。"
    current = [row for row in timeframes if row["time_frame"] == alert["time_frame"]]
    if len(current) != 1 or current[0]["buy_sell_label"] != alert["side"]:
        return "現在足とアラート方向が一致しません。"
    if len({row["id"] for row in points}) != len(points):
        return "波動ポイントの識別子が重複しています。"
    references = []
    for timeframe in timeframes:
        expected_current = timeframe["time_frame"] == alert["time_frame"]
        direction = "SELL"
        if timeframe["is_buy"] == 1:
            direction = "BUY"
        if (timeframe["alert_id"] != alert["id"] or timeframe["is_buy"] not in (0, 1)
                or timeframe["is_current_time_frame"] not in (0, 1)
                or bool(timeframe["is_current_time_frame"]) != expected_current
                or timeframe["buy_sell_label"] != direction):
            return "時間足の親アラートまたは方向が不整合です。"
        children = [row for row in points if row["alert_timeframe_id"] == timeframe["id"]]
        if (not _integer(timeframe["point_count"]) or timeframe["point_count"] <= 0
                or len(children) != timeframe["point_count"]
                or [row["point_order"] for row in children] != list(range(timeframe["point_count"]))):
            return "波動ポイントの件数または順序が不整合です。"
        latest = []
        for point in children:
            if (not _integer(point["id"]) or point["id"] <= 0
                    or point["alert_id"] != alert["id"] or point["time_frame"] != timeframe["time_frame"]
                    or point["is_latest"] not in (0, 1) or point["is_signal_reference"] not in (0, 1)
                    or not _integer(point["bar_time"]) or point["bar_time"] <= 0
                    or not _number(point["rate"])):
                return "波動ポイントの親時間足または取得値が不整合です。"
            if point["is_latest"] == 1:
                latest.append(point)
            if point["is_signal_reference"] == 1:
                references.append(point)
        if len(latest) != 1 or latest[0]["point_order"] != timeframe["point_count"] - 1:
            return "最新ポイントを一意に特定できません。"
        for point_name, timeframe_name in (("elliot_index", "latest_elliot_index"),
                                           ("elliot_label", "latest_elliot_label"),
                                           ("sub_elliot_index", "latest_sub_elliot_index"),
                                           ("sub_elliot_label", "latest_sub_elliot_label")):
            if latest[0][point_name] != timeframe[timeframe_name]:
                return "最新ポイントと時間足の波動ラベルが一致しません。"
    if (len(references) != 1 or references[0]["time_frame"] != alert["time_frame"]
            or references[0]["bar_time"] != reference_time
            or not _equal(references[0]["rate"], reference_rate)):
        return "損切り基準ポイントが保存値と一致しません。"
    return None


def load_alert_correction(session: Session, alert: Mapping[str, Any],
                          normalize: Callable[[Mapping[str, Any]], dict[str, Any]]) -> dict[str, Any]:
    """Keep optional correction read failures separate from the original alert."""
    try:
        return _load_alert_correction(session, alert, normalize)
    except SQLAlchemyError:
        logging.getLogger(__name__).warning("Unable to read alert correction snapshot", exc_info=True)
        return _response("INCOMPLETE", "補正データを確認できません。")


def _load_alert_correction(session: Session, alert: Mapping[str, Any],
                           normalize: Callable[[Mapping[str, Any]], dict[str, Any]]) -> dict[str, Any]:
    """Read one comparison using the caller's read transaction and fixed SQL identifiers."""
    tables = set(session.execute(text("SELECT name FROM sqlite_schema WHERE type='table'")).scalars())
    if CORRECTION_TABLE not in tables:
        return _response("UNRECORDED")
    if not set(METADATA_COLUMNS).issubset(_columns(session, CORRECTION_TABLE)):
        return _response("INCOMPLETE", "補正情報の保存形式に不足があります。")
    rows = session.execute(text(f"SELECT * FROM {CORRECTION_TABLE} WHERE alert_id = :alert_id"),
                           {"alert_id": alert["id"]}).mappings().all()
    if not rows:
        return _response("UNRECORDED")
    if len(rows) != 1:
        return _response("INCOMPLETE", "補正情報が重複しています。")
    metadata = {name: rows[0][name] for name in METADATA_COLUMNS}
    if not _metadata_has_valid_types(metadata):
        return _response("INCOMPLETE", "補正情報の値を読み取れません。")
    rendered = normalize(metadata)
    rendered["is_selected_stop_loss_available"] = bool(metadata["is_selected_stop_loss_available"])
    reason = _metadata_reason(metadata, alert)
    if reason:
        return _response("INCOMPLETE", reason, rendered)
    if not {TIME_FRAME_TABLE, POINT_TABLE}.issubset(tables):
        return _response("INCOMPLETE", "補正後の分析テーブルが不足しています。", rendered)
    frame_columns = _columns(session, TIME_FRAME_TABLE)
    if (not TIME_FRAME_COLUMNS.issubset(frame_columns)
            or not POINT_COLUMNS.issubset(_columns(session, POINT_TABLE))):
        return _response("INCOMPLETE", "補正後の分析の保存形式に不足があります。", rendered)
    corrected, corrected_points = _read_analysis(session, TIME_FRAME_TABLE, POINT_TABLE, alert["id"])
    if metadata["correction_status"] == "NONE":
        if corrected or corrected_points:
            return _response("INCOMPLETE", "補正なしの記録に補正後の分析が混在しています。", rendered)
        return _response("NONE", metadata=rendered)
    if (not TIME_FRAME_COLUMNS.issubset(_columns(session, ORIGINAL_TIME_FRAME_TABLE))
            or not POINT_COLUMNS.issubset(_columns(session, ORIGINAL_POINT_TABLE))):
        return _response("INCOMPLETE", "比較元の分析の保存形式に不足があります。", rendered)
    original, original_points = _read_analysis(session, ORIGINAL_TIME_FRAME_TABLE, ORIGINAL_POINT_TABLE, alert["id"])
    reason = _analysis_reason(original, original_points, alert, alert.get("signal_reference_point_time", 0),
                              metadata["original_lc0"], True)
    if reason:
        return _response("INCOMPLETE", "補正前: " + reason, rendered)
    reason = _analysis_reason(corrected, corrected_points, alert, metadata["corrected_reference_point_time"],
                              metadata["corrected_lc0"], True)
    if reason:
        return _response("INCOMPLETE", "補正後: " + reason, rendered)
    for before, after in zip(original, corrected, strict=True):
        if before["time_frame"] == metadata["correction_time_frame"]:
            valid = (before["buy_sell_label"] == metadata["original_direction"]
                     and after["buy_sell_label"] == metadata["corrected_direction"])
        else:
            valid = before["is_buy"] == after["is_buy"]
            if before["time_frame"] in {16385, 16388}:
                valid = valid and before["buy_sell_label"] == alert["side"]
        if not valid:
            return _response("INCOMPLETE", "指定したH4またはH1以外にも方向変更があります。", rendered)
    if corrected[-1]["latest_elliot_label"] != metadata["selected_current_elliot_label"]:
        return _response("INCOMPLETE", "採用したM5波動ラベルが一致しません。", rendered)
    added = {row["alert_timeframe_id"]: row.get("is_added_point")
             for row in corrected_points if row["is_latest"] == 1}
    normalized_frames = []
    for row in corrected:
        item = normalize(row)
        item["is_ema200_available"] = EMA_COLUMNS.issubset(frame_columns)
        if not item["is_ema200_available"]:
            item["is_ema200_buy"] = False
            item["is_ema200_sell"] = False
        value = added.get(row["id"])
        item["latest_point_is_added"] = None
        if value is not None:
            item["latest_point_is_added"] = bool(value)
        normalized_frames.append(item)
    return _response("APPLIED", metadata=rendered, timeframes=normalized_frames,
                     points=[normalize(row) for row in corrected_points])
