import type { PriceMovementSnapshot } from "../api/types";
import { formatNumber } from "./format";

type Snapshot = PriceMovementSnapshot | null | undefined;
interface MovementDisplay {
  label: string;
  className: string;
  details: string[];
}

function nonNegative(fromValue: unknown): fromValue is number {
  return typeof fromValue === "number" && Number.isFinite(fromValue)
    && fromValue >= 0 && fromValue !== Number.MAX_VALUE;
}

/** MQLの保存カレンダー値を、ブラウザの時差を加えずServer時刻として表示する。 */
function serverTime(fromValue: unknown): string | null {
  if (!nonNegative(fromValue) || !Number.isSafeInteger(fromValue) || fromValue <= 0) {
    return null;
  }

  const date = new Date(fromValue * 1000);
  if (!Number.isFinite(date.getTime()) || date.getUTCFullYear() > 9999) {
    return null;
  }

  return `${date.toISOString().slice(0, 19).replaceAll("-", "/").replace("T", " ")} Server`;
}

function missingLabel(fromSnapshot: Snapshot): string {
  if (!fromSnapshot || fromSnapshot.price_movement_status === "UNRECORDED") {
    return "未記録";
  }
  if (fromSnapshot.price_movement_status === "UNAVAILABLE"
      || fromSnapshot.price_movement_status === "VALID") {
    return "判定不能";
  }
  if (fromSnapshot.price_movement_status === "UNKNOWN"
      || fromSnapshot.is_price_movement_valid !== undefined) {
    return "未記録／判定不能";
  }

  return "未記録";
}

/** 分類は保存値を使う。表示時の閾値再判定は行わない。 */
function movementDisplay(fromSnapshot: Snapshot): MovementDisplay {
  const missing = { label: missingLabel(fromSnapshot), className: "price-movement-unknown", details: [] };
  if (!fromSnapshot || fromSnapshot.is_price_movement_valid !== true
      || (fromSnapshot.price_movement_status !== undefined && fromSnapshot.price_movement_status !== "VALID")) {
    return missing;
  }

  const level = fromSnapshot.price_movement_level;
  const range = fromSnapshot.price_movement_average_range_pips;
  const atr = fromSnapshot.price_movement_reference_atr_pips;
  const ratio = fromSnapshot.price_movement_activity_ratio;
  const referenceTime = serverTime(fromSnapshot.price_movement_reference_bar_time);
  if (!Number.isInteger(level) || (level !== 1 && level !== 2 && level !== 3)
      || !nonNegative(range) || !nonNegative(atr) || atr <= 0
      || !nonNegative(ratio) || referenceTime === null) {
    return { ...missing, label: "判定不能" };
  }

  const labels = { 1: "静か", 2: "通常", 3: "活発" };
  const variants = { 1: "calm", 2: "normal", 3: "active" };
  let spread = "取得不能";
  if (fromSnapshot.is_price_movement_spread_valid === true
      && nonNegative(fromSnapshot.price_movement_range_spread_ratio)) {
    spread = `${formatNumber(Math.abs(fromSnapshot.price_movement_range_spread_ratio), 2)}倍`;
  }

  return {
    label: `${labels[level]} ${formatNumber(Math.abs(ratio), 2)}倍`,
    className: `price-movement-${variants[level]}`,
    details: [
      `平均値幅：${formatNumber(Math.abs(range), 1)} pips（確定足3本）`,
      `基準ATR14：${formatNumber(atr, 1)} pips（対象3本より前）`,
      `スプレッド倍率：${spread}`,
      `対象確定足：${referenceTime}`,
    ],
  };
}

export function priceMovementLabel(fromSnapshot: Snapshot): string {
  return movementDisplay(fromSnapshot).label;
}

export function priceMovementClassName(fromSnapshot: Snapshot): string {
  return movementDisplay(fromSnapshot).className;
}

export function priceMovementDetails(fromSnapshot: Snapshot): string[] {
  return movementDisplay(fromSnapshot).details;
}

export function priceMovementTooltip(fromSnapshot: Snapshot): string {
  const display = movementDisplay(fromSnapshot);

  return [`値動き：${display.label}`, ...display.details].join("\n");
}
