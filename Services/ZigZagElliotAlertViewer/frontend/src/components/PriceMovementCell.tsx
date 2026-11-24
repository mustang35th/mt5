import type { PriceMovementSnapshot } from "../api/types";
import { priceMovementClassName, priceMovementDetails, priceMovementLabel, priceMovementTooltip } from "../lib/priceMovement";
import "./PriceMovementCell.css";

interface PriceMovementCellProps {
  snapshot: PriceMovementSnapshot | null | undefined;
  detailed?: boolean;
  timeFrame?: string;
}

/** 一覧・比較・詳細で同じ保存値と欠損表示を使う。 */
export function PriceMovementCell({ snapshot, detailed = false, timeFrame }: PriceMovementCellProps) {
  let description = priceMovementTooltip(snapshot);
  if (timeFrame) {
    description = `${timeFrame} ${description}`;
  }

  return (
    <span className={`price-movement-cell ${priceMovementClassName(snapshot)}`} title={description} aria-label={description}>
      <span className="price-movement-summary">{priceMovementLabel(snapshot)}</span>
      {detailed && priceMovementDetails(snapshot).map((line) => (
        <span className="price-movement-detail" key={line}>{line}</span>
      ))}
    </span>
  );
}
