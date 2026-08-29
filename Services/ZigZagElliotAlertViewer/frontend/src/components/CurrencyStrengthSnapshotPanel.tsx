import type { AlertDetail } from "../api/types";
import { formatSignedNumber } from "../lib/format";
import {
  evaluateCurrencyStrengthSnapshot,
  formatCurrencyStrengthM5Time,
  type CurrencyStrengthPeriodSnapshot,
} from "../lib/currencyStrengthSnapshot";

interface CurrencyStrengthSnapshotPanelProps {
  alert: AlertDetail;
}

function rankText(fromRank: number | null): string {
  return fromRank === null ? "—" : `${fromRank}位`;
}

function comparisonSymbol(
  fromPeriod: CurrencyStrengthPeriodSnapshot,
): string {
  if (fromPeriod.direction === "BUY") return ">";
  if (fromPeriod.direction === "SELL") return "<";
  return "=";
}

function directionVariant(fromDirection: string): string {
  if (fromDirection === "BUY" || fromDirection === "BUY一致") return "buy";
  if (fromDirection === "SELL" || fromDirection === "SELL一致") return "sell";
  if (fromDirection === "MIXED") return "warn";
  return "neutral";
}

function judgementVariant(fromJudgement: string): string {
  if (fromJudgement === "OK") return "good";
  if (fromJudgement === "NG") return "sell";
  return "neutral";
}

function judgementClass(fromJudgement: string): string {
  if (fromJudgement === "OK") return "ok";
  if (fromJudgement === "NG") return "ng";
  if (fromJudgement === "参考") return "reference";
  return "unknown";
}

function freshnessVariant(fromFreshness: string): string {
  if (fromFreshness === "EXACT") return "good";
  if (fromFreshness === "STALE") return "warn";
  return "neutral";
}

/**
 * 期間別の基軸・決済通貨順位と方向を表示する。
 *
 * @param fromPeriod 期間別通貨強弱スナップショット
 * @return 期間別表示
 */
function CurrencyStrengthPeriodRow({
  period: fromPeriod,
}: {
  period: CurrencyStrengthPeriodSnapshot;
}) {
  return (
    <article
      aria-label={`${fromPeriod.label}の通貨強弱`}
      className="currency-strength-snapshot-period"
    >
      <strong className="currency-strength-snapshot-period-label">
        {fromPeriod.label}
      </strong>
      <div className="currency-strength-snapshot-ranks">
        <span>
          {fromPeriod.baseCurrency} {rankText(fromPeriod.baseRank)}
        </span>
        <span aria-hidden="true" className="currency-strength-snapshot-comparison">
          {comparisonSymbol(fromPeriod)}
        </span>
        <span>
          {fromPeriod.quoteCurrency} {rankText(fromPeriod.quoteRank)}
        </span>
      </div>
      <span className="currency-strength-snapshot-difference">
        差 {formatSignedNumber(fromPeriod.rankDifference, 0)}
      </span>
      <span
        className={`badge ${directionVariant(fromPeriod.direction)} currency-strength-snapshot-period-direction`}
      >
        {fromPeriod.direction}
      </span>
    </article>
  );
}

/**
 * TIMEFRAME COMPARISONへAlert保存時点の通貨強弱を表示する。
 *
 * @param alert Alert詳細
 * @return 通貨強弱スナップショットパネル
 */
export function CurrencyStrengthSnapshotPanel({
  alert,
}: CurrencyStrengthSnapshotPanelProps) {
  const snapshot = evaluateCurrencyStrengthSnapshot(alert);
  return (
    <section
      aria-label="通貨強弱（Alert保存時点）"
      className={`currency-strength-snapshot-panel currency-strength-snapshot-${judgementClass(snapshot.judgement)}`}
    >
      <div className="currency-strength-snapshot-header">
        <div>
          <p className="eyebrow">CURRENCY STRENGTH</p>
          <h3>通貨強弱（Alert保存時点）</h3>
        </div>
        <div className="currency-strength-snapshot-badges">
          <span className="badge neutral currency-strength-snapshot-entry-usage">
            Entry条件: {snapshot.entryUsage}
          </span>
          <span
            className={`badge ${judgementVariant(snapshot.judgement)} currency-strength-snapshot-judgement`}
          >
            判定: {snapshot.judgement}
          </span>
          <span
            className={`badge ${directionVariant(snapshot.direction)} currency-strength-snapshot-direction`}
          >
            {snapshot.direction}
          </span>
          <span className="badge neutral currency-strength-snapshot-source-mode">
            {snapshot.sourceMode}
          </span>
          <span
            className={`badge ${freshnessVariant(snapshot.freshness)} currency-strength-snapshot-freshness`}
          >
            {snapshot.freshness}
          </span>
        </div>
      </div>

      <div className="currency-strength-snapshot-periods">
        {snapshot.periods.map((period) => (
          <CurrencyStrengthPeriodRow key={period.label} period={period} />
        ))}
      </div>

      <dl className="currency-strength-snapshot-metadata">
        <div className="currency-strength-snapshot-metadata-item">
          <dt>Target M5</dt>
          <dd>{formatCurrencyStrengthM5Time(snapshot.targetM5BarTime)}</dd>
        </div>
        <div className="currency-strength-snapshot-metadata-item">
          <dt>Actual M5</dt>
          <dd>{formatCurrencyStrengthM5Time(snapshot.actualM5BarTime)}</dd>
        </div>
        <div className="currency-strength-snapshot-metadata-item">
          <dt>Run</dt>
          <dd>{snapshot.runId ?? "—"}</dd>
        </div>
        <div className="currency-strength-snapshot-metadata-item">
          <dt>Calculation</dt>
          <dd>{snapshot.calculationVersion}</dd>
        </div>
      </dl>
    </section>
  );
}
