import type { AlertListItem } from "../api/types";
import { formatNumber } from "../lib/format";

/**
 * 保存した対象足のEMA200距離を、エントリー可否とは別の参考値として表示する。
 */
export function Ema200DistanceCell({ alert }: { alert: AlertListItem }) {
  const timeFrame = alert.time_frame_text.trim().toUpperCase() || "対象足";
  const distance = alert.close_ema200_diff_pips;
  const maxDistance = alert.max_close_ema200_diff_pips;
  let unavailableLabel = "";
  if (alert.is_entry_evaluated === false) {
    unavailableLabel = "未評価";
  } else if (alert.is_entry_evaluated !== true
      || typeof distance !== "number" || !Number.isFinite(distance) || distance < 0
      || distance === Number.MAX_VALUE
      || typeof maxDistance !== "number" || !Number.isFinite(maxDistance) || maxDistance <= 0
      || maxDistance === Number.MAX_VALUE) {
    unavailableLabel = "未記録";
  }

  if (unavailableLabel !== "") {
    const description = `${timeFrame} EMA200距離: ${unavailableLabel}`;

    return (
      <span className="ema200-distance-cell unavailable" title={description} aria-label={description}>
        <span>—</span>
        <span className="ema200-distance-status">{unavailableLabel}</span>
      </span>
    );
  }

  // 有効性は上で確認済み。0は未記録と区別し、負のゼロも0.0として表示する。
  const savedDistance = Math.abs(distance as number);
  const savedMaxDistance = maxDistance as number;
  const isOverLimit = savedDistance > savedMaxDistance;
  const distanceText = `${formatNumber(savedDistance)} pips`;
  const description = [
    `${timeFrame} EMA200距離: ${distanceText}`,
    `${timeFrame}の確定足終値[1]とEMA200[1]の絶対差。`,
    `保存参考上限: ${formatNumber(savedMaxDistance)} pips。`,
  ];
  let className = "ema200-distance-cell";
  let status = null;
  if (isOverLimit) {
    const excess = savedDistance - savedMaxDistance;
    let excessText = `${formatNumber(excess)} pips`;
    if (excess < 0.1) {
      excessText = "0.1 pips未満";
    }

    description.push(`参考上限の超過量: ${excessText}。`);
    className += " over-limit";
    status = <span className="ema200-distance-status">超過</span>;
  } else {
    description.push("保存参考上限以内。");
  }

  description.push("丸め前の値で比較。参考比較であり、ENTRY可否とは別です。");
  if (timeFrame === "M15") {
    description.push("現行M15では距離制限の適用なし。保存当時の適用有無を示す表示ではありません。");
  }

  const title = description.join("\n");

  return (
    <span className={className} title={title} aria-label={title}>
      <span>{distanceText}</span>
      {status}
    </span>
  );
}
