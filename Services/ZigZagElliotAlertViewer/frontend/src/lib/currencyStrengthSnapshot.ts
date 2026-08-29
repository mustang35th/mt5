import type { AlertDetail } from "../api/types";

export type CurrencyStrengthEntryUsage = "使用" | "参考" | "不明";
export type CurrencyStrengthJudgement = "OK" | "NG" | "参考" | "不明";
export type CurrencyStrengthDirection =
  | "BUY一致"
  | "SELL一致"
  | "MIXED"
  | "利用不可";
export type CurrencyStrengthPeriodDirection =
  | "BUY"
  | "SELL"
  | "MIXED"
  | "利用不可";
export type CurrencyStrengthFreshness = "EXACT" | "STALE" | "不明";

/** 通貨強弱の期間別保存値。 */
export interface CurrencyStrengthPeriodSnapshot {
  label: "長中期" | "中短期";
  baseCurrency: string;
  baseRank: number | null;
  quoteCurrency: string;
  quoteRank: number | null;
  rankDifference: number | null;
  direction: CurrencyStrengthPeriodDirection;
}

/** Alert保存時点の通貨強弱評価。 */
export interface CurrencyStrengthSnapshotEvaluation {
  entryUsage: CurrencyStrengthEntryUsage;
  judgement: CurrencyStrengthJudgement;
  direction: CurrencyStrengthDirection;
  freshness: CurrencyStrengthFreshness;
  sourceMode: string;
  targetM5BarTime: number | null;
  actualM5BarTime: number | null;
  runId: number | null;
  calculationVersion: string;
  periods: [CurrencyStrengthPeriodSnapshot, CurrencyStrengthPeriodSnapshot];
}

function finiteNumber(fromValue: unknown): number | null {
  const number = Number(fromValue);
  return fromValue !== null
    && fromValue !== undefined
    && fromValue !== ""
    && Number.isFinite(number)
    ? number
    : null;
}

function positiveNumber(fromValue: unknown): number | null {
  const number = finiteNumber(fromValue);
  return number !== null && number > 0 ? number : null;
}

function savedText(fromValue: unknown): string {
  return typeof fromValue === "string" && fromValue.trim()
    ? fromValue.trim()
    : "—";
}

function periodDirection(
  fromAvailable: boolean,
  fromDifference: number | null,
): CurrencyStrengthPeriodDirection {
  if (!fromAvailable || fromDifference === null) return "利用不可";
  if (fromDifference > 0) return "BUY";
  if (fromDifference < 0) return "SELL";
  return "MIXED";
}

function combinedDirection(
  fromLongMedium: CurrencyStrengthPeriodDirection,
  fromMediumShort: CurrencyStrengthPeriodDirection,
): CurrencyStrengthDirection {
  if (fromLongMedium === "利用不可" || fromMediumShort === "利用不可") {
    return "利用不可";
  }
  if (fromLongMedium === "BUY" && fromMediumShort === "BUY") {
    return "BUY一致";
  }
  if (fromLongMedium === "SELL" && fromMediumShort === "SELL") {
    return "SELL一致";
  }
  return "MIXED";
}

function freshness(
  fromAvailable: boolean,
  fromTargetM5BarTime: number | null,
  fromActualM5BarTime: number | null,
): CurrencyStrengthFreshness {
  if (
    !fromAvailable
    || fromTargetM5BarTime === null
    || fromActualM5BarTime === null
  ) {
    return "不明";
  }
  return fromTargetM5BarTime === fromActualM5BarTime ? "EXACT" : "STALE";
}

/**
 * Alert保存値から通貨強弱の表示とEntry判定を評価する。
 *
 * @param fromAlert Alert詳細
 * @return 通貨強弱スナップショット評価
 */
export function evaluateCurrencyStrengthSnapshot(
  fromAlert: AlertDetail,
): CurrencyStrengthSnapshotEvaluation {
  const enabled = fromAlert.is_currency_strength_enabled;
  const available = fromAlert.is_currency_strength_available === true;
  const longMediumDifference = finiteNumber(
    fromAlert.long_medium_rank_difference,
  );
  const mediumShortDifference = finiteNumber(
    fromAlert.medium_short_rank_difference,
  );
  const targetM5BarTime = positiveNumber(
    fromAlert.currency_strength_target_m5_bar_time,
  );
  const actualM5BarTime = positiveNumber(
    fromAlert.currency_strength_m5_bar_time,
  );
  const savedFreshness = freshness(
    available,
    targetM5BarTime,
    actualM5BarTime,
  );
  const longMediumDirection = periodDirection(
    available,
    longMediumDifference,
  );
  const mediumShortDirection = periodDirection(
    available,
    mediumShortDifference,
  );
  const direction = combinedDirection(
    longMediumDirection,
    mediumShortDirection,
  );

  let entryUsage: CurrencyStrengthEntryUsage = "不明";
  let judgement: CurrencyStrengthJudgement = "不明";
  if (enabled === false) {
    entryUsage = "参考";
    judgement = "参考";
  }
  if (enabled === true) {
    entryUsage = "使用";
    const expectedDirection = fromAlert.side === "BUY" ? "BUY一致" : "SELL一致";
    if (!available || savedFreshness === "STALE") {
      judgement = "NG";
    } else if (savedFreshness === "不明" || direction === "利用不可") {
      judgement = "不明";
    } else {
      judgement = direction === expectedDirection ? "OK" : "NG";
    }
  }

  return {
    entryUsage,
    judgement,
    direction,
    freshness: savedFreshness,
    sourceMode: savedText(fromAlert.currency_strength_source_mode),
    targetM5BarTime,
    actualM5BarTime,
    runId: positiveNumber(fromAlert.currency_strength_run_id),
    calculationVersion: savedText(
      fromAlert.currency_strength_calculation_version,
    ),
    periods: [
      {
        label: "長中期",
        baseCurrency: savedText(fromAlert.base_currency),
        baseRank: positiveNumber(fromAlert.base_long_medium_rank),
        quoteCurrency: savedText(fromAlert.quote_currency),
        quoteRank: positiveNumber(fromAlert.quote_long_medium_rank),
        rankDifference: longMediumDifference,
        direction: longMediumDirection,
      },
      {
        label: "中短期",
        baseCurrency: savedText(fromAlert.base_currency),
        baseRank: positiveNumber(fromAlert.base_medium_short_rank),
        quoteCurrency: savedText(fromAlert.quote_currency),
        quoteRank: positiveNumber(fromAlert.quote_medium_short_rank),
        rankDifference: mediumShortDifference,
        direction: mediumShortDirection,
      },
    ],
  };
}

/**
 * MT5のdatetime秒をM5表示用文字列へ変換する。
 *
 * @param fromEpochSeconds MT5 datetime秒
 * @return YYYY.MM.DD HH:mm形式。未記録の場合はダッシュ
 */
export function formatCurrencyStrengthM5Time(
  fromEpochSeconds: number | null,
): string {
  if (fromEpochSeconds === null) return "—";
  const date = new Date(fromEpochSeconds * 1000);
  if (Number.isNaN(date.getTime())) return "—";
  const year = String(date.getUTCFullYear()).padStart(4, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hour = String(date.getUTCHours()).padStart(2, "0");
  const minute = String(date.getUTCMinutes()).padStart(2, "0");
  return `${year}.${month}.${day} ${hour}:${minute}`;
}
