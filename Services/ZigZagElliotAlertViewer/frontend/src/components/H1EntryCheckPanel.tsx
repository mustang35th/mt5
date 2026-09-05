import { Fragment, useId, useMemo } from "react";
import type {
  AlertDetail,
  ObservationDetailTimeFrame,
} from "../api/types";
import { evaluateCurrencyStrengthSnapshot } from "../lib/currencyStrengthSnapshot";
import { formatNumber, formatSignedNumber } from "../lib/format";

export type H1EntryCheckStatus = "OK" | "NG" | "参考" | "対象外" | "不明";

export type H1EntryCheckOverallStatus = "OK" | "NG" | "判定不能";

export type H1EntryCheckPhase = "事前ゲート" | "Judge" | "Entry";

export interface H1EntryCheckItem {
  id: string;
  phase: H1EntryCheckPhase;
  label: string;
  status: H1EntryCheckStatus;
  actual: string;
  expected: string;
  required: boolean;
}

export interface H1EntryCheckSnapshot {
  direction: "BUY" | "SELL" | null;
  overallStatus: H1EntryCheckOverallStatus;
  overallReason: string;
  source: "SAVED" | "SNAPSHOT";
  items: H1EntryCheckItem[];
}

export interface H1EntryCheckPanelProps {
  timeFrames: readonly ObservationDetailTimeFrame[];
  spreadPips: number | null | undefined;
  savedDecision?: AlertDetail | null;
}

type EntryCheckTimeFrame = ObservationDetailTimeFrame & {
  is_ema200_available?: boolean;
};

type EntryDirection = "BUY" | "SELL";

const ENTRY_WAVE_LABELS = new Set(["1", "3", "5"]);

/**
 * 時間足名に一致する最初のSnapshotを固定順で取得します。
 *
 * @param fromTimeFrames 時間足Snapshot一覧
 * @param fromTimeFrameText 対象時間足名
 * @return 対象時間足。存在しない場合undefined
 */
function findTimeFrame(
  fromTimeFrames: readonly ObservationDetailTimeFrame[],
  fromTimeFrameText: string,
): EntryCheckTimeFrame | undefined {
  return [...fromTimeFrames]
    .filter((timeFrame) => (
      String(timeFrame.time_frame_text).trim().toUpperCase()
        === fromTimeFrameText
    ))
    .sort((left, right) => {
      const orderDifference = left.time_frame_order - right.time_frame_order;
      if (orderDifference !== 0) return orderDifference;
      return left.id - right.id;
    })[0];
}

function finiteNumber(fromValue: unknown): number | null {
  if (fromValue === null || fromValue === undefined || fromValue === "") {
    return null;
  }
  const number = Number(fromValue);
  return Number.isFinite(number) ? number : null;
}

function direction(fromTimeFrame: EntryCheckTimeFrame | undefined): EntryDirection | null {
  if (typeof fromTimeFrame?.is_buy !== "boolean") return null;
  return fromTimeFrame.is_buy ? "BUY" : "SELL";
}

function ema200Direction(
  fromTimeFrame: EntryCheckTimeFrame | undefined,
): EntryDirection | "NONE" | "INVALID" | null {
  if (!fromTimeFrame || fromTimeFrame.is_ema200_available === false) {
    return null;
  }
  if (
    typeof fromTimeFrame.is_ema200_buy !== "boolean"
    || typeof fromTimeFrame.is_ema200_sell !== "boolean"
  ) {
    return null;
  }
  if (fromTimeFrame.is_ema200_buy && fromTimeFrame.is_ema200_sell) {
    return "INVALID";
  }
  if (fromTimeFrame.is_ema200_buy) return "BUY";
  if (fromTimeFrame.is_ema200_sell) return "SELL";
  return "NONE";
}

function directionValue(
  fromLabel: string,
  fromTimeFrame: EntryCheckTimeFrame | undefined,
): string {
  return `${fromLabel} ${direction(fromTimeFrame) ?? "記録なし"}`;
}

function unknownItem(
  fromId: string,
  fromPhase: H1EntryCheckPhase,
  fromLabel: string,
  fromActual: string,
  fromExpected: string,
  fromRequired = false,
): H1EntryCheckItem {
  return {
    id: fromId,
    phase: fromPhase,
    label: fromLabel,
    status: "不明",
    actual: fromActual,
    expected: fromExpected,
    required: fromRequired,
  };
}

function requiredItem(
  fromId: string,
  fromPhase: H1EntryCheckPhase,
  fromLabel: string,
  fromActual: string,
  fromExpected: string,
  fromPassed: boolean | null,
): H1EntryCheckItem {
  let status: H1EntryCheckStatus = "不明";
  if (fromPassed === true) status = "OK";
  if (fromPassed === false) status = "NG";
  return {
    id: fromId,
    phase: fromPhase,
    label: fromLabel,
    status,
    actual: fromActual,
    expected: fromExpected,
    required: true,
  };
}

function buildCurrencyStrengthItem(
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  if (!fromSavedDecision) {
    return unknownItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      "記録なし",
      "有効/無効modeと実行時順位が必要",
      true,
    );
  }
  if (typeof fromSavedDecision.is_currency_strength_enabled !== "boolean") {
    return unknownItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      `status ${fromSavedDecision.currency_strength_status}`,
      "フィルタ設定が未記録（Legacy）",
      true,
    );
  }
  if (!fromSavedDecision.is_currency_strength_enabled) {
    return optionalItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      "フィルタ OFF",
      "実行時設定で無効",
      "対象外",
    );
  }
  const longMediumDifference = finiteNumber(
    fromSavedDecision.long_medium_rank_difference,
  );
  const mediumShortDifference = finiteNumber(
    fromSavedDecision.medium_short_rank_difference,
  );
  const currencyStrength = evaluateCurrencyStrengthSnapshot(fromSavedDecision);
  if (!fromSavedDecision.is_currency_strength_available) {
    return requiredItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      `status ${fromSavedDecision.currency_strength_status} / 利用不可`,
      `${fromSavedDecision.side}方向へ両期間の順位差が一致 / M5時刻一致`,
      false,
    );
  }
  const rankDifferenceText = longMediumDifference === null
    || mediumShortDifference === null
    ? "順位差 記録なし"
    : `順位差 ${formatSignedNumber(longMediumDifference, 0)} / ${formatSignedNumber(mediumShortDifference, 0)}`;
  if (currencyStrength.freshness === "不明") {
    return unknownItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      `${rankDifferenceText} / M5時刻 未記録`,
      `${fromSavedDecision.side}方向へ両期間が一致 / M5時刻一致`,
      true,
    );
  }
  if (currencyStrength.freshness === "STALE") {
    return requiredItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      `${rankDifferenceText} / M5 STALE`,
      `${fromSavedDecision.side}方向へ両期間が一致 / M5時刻一致`,
      false,
    );
  }
  if (longMediumDifference === null || mediumShortDifference === null) {
    return unknownItem(
      "currency_strength",
      "事前ゲート",
      "通貨強弱",
      `${rankDifferenceText} / M5 EXACT`,
      `${fromSavedDecision.side}方向へ両期間が一致 / M5時刻一致`,
      true,
    );
  }
  return requiredItem(
    "currency_strength",
    "事前ゲート",
    "通貨強弱",
    `${rankDifferenceText} / M5 EXACT`,
    `${fromSavedDecision.side}方向へ両期間が一致 / M5時刻一致`,
    currencyStrength.judgement === "OK",
  );
}

function optionalItem(
  fromId: string,
  fromPhase: H1EntryCheckPhase,
  fromLabel: string,
  fromActual: string,
  fromExpected: string,
  fromStatus: H1EntryCheckStatus,
): H1EntryCheckItem {
  return {
    id: fromId,
    phase: fromPhase,
    label: fromLabel,
    status: fromStatus,
    actual: fromActual,
    expected: fromExpected,
    required: false,
  };
}

function buildSpreadItem(
  fromSpreadPips: number | null,
): H1EntryCheckItem {
  if (fromSpreadPips === null) {
    return requiredItem(
      "spread",
      "Judge",
      "Spread",
      "記録なし",
      "5.0 pips以下",
      null,
    );
  }
  return requiredItem(
    "spread",
    "Judge",
    "Spread",
    `${formatNumber(fromSpreadPips)} pips`,
    "5.0 pips以下",
    fromSpreadPips <= 5,
  );
}

function buildWaveDirectionItem(
  fromH1: EntryCheckTimeFrame | undefined,
  fromDirection: EntryDirection | null,
): H1EntryCheckItem {
  const isWaveUptrend = fromH1?.is_wave_uptrend;
  if (!fromH1 || fromDirection === null || typeof isWaveUptrend !== "boolean") {
    return requiredItem(
      "h1_wave_direction",
      "Judge",
      "H1 Wave方向",
      "記録なし",
      "H1分析方向と最新Wave方向が一致",
      null,
    );
  }
  const waveDirection: EntryDirection = isWaveUptrend ? "BUY" : "SELL";
  return requiredItem(
    "h1_wave_direction",
    "Judge",
    "H1 Wave方向",
    `分析 ${fromDirection} / Wave ${waveDirection}`,
    "H1分析方向と最新Wave方向が一致",
    waveDirection === fromDirection,
  );
}

function buildRequiredDirectionItem(
  fromD1: EntryCheckTimeFrame | undefined,
  fromH4: EntryCheckTimeFrame | undefined,
  fromH1: EntryCheckTimeFrame | undefined,
  fromDirection: EntryDirection | null,
): H1EntryCheckItem {
  const directions = [direction(fromD1), direction(fromH4), direction(fromH1)];
  const actual = [
    directionValue("D1", fromD1),
    directionValue("H4", fromH4),
    directionValue("H1", fromH1),
  ].join(" / ");
  if (fromDirection === null || directions.some((value) => value === null)) {
    return requiredItem(
      "d1_h4_h1_direction",
      "Judge",
      "D1・H4・H1方向",
      actual,
      "3時間足がH1方向と一致",
      null,
    );
  }
  return requiredItem(
    "d1_h4_h1_direction",
    "Judge",
    "D1・H4・H1方向",
    actual,
    "3時間足がH1方向と一致",
    directions.every((value) => value === fromDirection),
  );
}

function savedDirectionAlignmentItem(
  fromSavedDecision: AlertDetail,
): H1EntryCheckItem {
  const mode = fromSavedDecision.h1_direction_alignment_mode;
  const state = fromSavedDecision.h1_direction_alignment_state;
  const actual = `mode ${mode} / ${state}`;
  if (
    fromSavedDecision.is_h1_direction_alignment_legacy
    || state === "NOT_EVALUATED"
  ) {
    return unknownItem(
      "mn1_w1_direction",
      "Judge",
      "MN1・W1追加方向確認",
      actual,
      "保存された方向一致modeに従う",
      true,
    );
  }
  if (mode === "D1_TO_H1" || state === "NOT_APPLICABLE") {
    return optionalItem(
      "mn1_w1_direction",
      "Judge",
      "MN1・W1追加方向確認",
      actual,
      "D1～H1 modeでは使用しない",
      "対象外",
    );
  }
  if (mode === "MN1_TO_H1_OBSERVE") {
    return optionalItem(
      "mn1_w1_direction",
      "Judge",
      "MN1・W1追加方向確認",
      actual,
      `記録のみ / ${fromSavedDecision.is_h1_direction_alignment_passed ? "一致" : "不一致"}`,
      "参考",
    );
  }
  return requiredItem(
    "mn1_w1_direction",
    "Judge",
    "MN1・W1追加方向確認",
    actual,
    "保存された必須modeを通過",
    fromSavedDecision.is_h1_direction_alignment_passed,
  );
}

function buildAdditionalDirectionItem(
  fromMn1: EntryCheckTimeFrame | undefined,
  fromW1: EntryCheckTimeFrame | undefined,
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  if (fromSavedDecision) return savedDirectionAlignmentItem(fromSavedDecision);
  return unknownItem(
    "mn1_w1_direction",
    "Judge",
    "MN1・W1追加方向確認",
    `${directionValue("MN1", fromMn1)} / ${directionValue("W1", fromW1)}`,
    "実行時の方向一致modeが未記録",
    true,
  );
}

function buildElliottItem(
  fromH1: EntryCheckTimeFrame | undefined,
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  const label = String(fromH1?.latest_elliot_label ?? "").trim();
  if (
    fromSavedDecision
    && typeof fromSavedDecision.is_entry_wave === "boolean"
  ) {
    return requiredItem(
      "h1_elliott_wave",
      "Judge",
      "H1 Elliott",
      label ? `wave ${label}` : `wave ${fromSavedDecision.current_elliot_label || "記録なし"}`,
      "最新ラベルが1・3・5（保存判定）",
      fromSavedDecision.is_entry_wave,
    );
  }
  if (!fromH1 || !label) {
    return requiredItem(
      "h1_elliott_wave",
      "Judge",
      "H1 Elliott",
      "記録なし",
      "最新ラベルが1・3・5",
      null,
    );
  }
  return requiredItem(
    "h1_elliott_wave",
    "Judge",
    "H1 Elliott",
    `wave ${label}`,
    "最新ラベルが1・3・5（Entry時も再確認）",
    ENTRY_WAVE_LABELS.has(label),
  );
}

function buildGmmaItem(
  fromId: "h1_gmma_trend" | "h1_gmma_cross",
  fromLabel: string,
  fromCount: unknown,
  fromDirection: EntryDirection | null,
): H1EntryCheckItem {
  const count = finiteNumber(fromCount);
  if (count === null || fromDirection === null) {
    return requiredItem(
      fromId,
      "Judge",
      fromLabel,
      "記録なし",
      "BUYは+1超 / SELLは-1未満",
      null,
    );
  }
  const passed = fromDirection === "BUY" ? count > 1 : count < -1;
  return requiredItem(
    fromId,
    "Judge",
    fromLabel,
    formatSignedNumber(count, 0),
    `${fromDirection}は${fromDirection === "BUY" ? "+1超" : "-1未満"}`,
    passed,
  );
}

function buildH1Ema200Item(
  fromH1: EntryCheckTimeFrame | undefined,
  fromDirection: EntryDirection | null,
): H1EntryCheckItem {
  const emaDirection = ema200Direction(fromH1);
  if (emaDirection === null || fromDirection === null) {
    return requiredItem(
      "h1_ema200",
      "Judge",
      "H1 EMA200",
      "記録なし",
      "H1 EMA200がH1方向と排他的に一致",
      null,
    );
  }
  return requiredItem(
    "h1_ema200",
    "Judge",
    "H1 EMA200",
    emaDirection,
    `${fromDirection}と排他的に一致`,
    emaDirection === fromDirection,
  );
}

function buildH4Ema200Item(
  fromH4: EntryCheckTimeFrame | undefined,
  fromDirection: EntryDirection | null,
): H1EntryCheckItem {
  const emaDirection = ema200Direction(fromH4);
  if (emaDirection === null || fromDirection === null) {
    return unknownItem(
      "h4_ema200",
      "Judge",
      "H4 EMA200",
      "記録なし",
      "H4必須mode時はH1方向と排他的に一致",
      true,
    );
  }
  const matchLabel = emaDirection === fromDirection ? "一致" : "不一致";
  return unknownItem(
    "h4_ema200",
    "Judge",
    "H4 EMA200",
    `${emaDirection}（${matchLabel}）`,
    "H4 EMA200確認modeが未記録",
    true,
  );
}

function savedW1Item(fromSavedDecision: AlertDetail): H1EntryCheckItem {
  const mode = fromSavedDecision.w1_confirmation_mode;
  const state = fromSavedDecision.w1_confirmation_state;
  const actual = `mode ${mode} / ${state} / EMA200 ${fromSavedDecision.w1_ema200_direction}`;
  if (fromSavedDecision.is_w1_confirmation_legacy) {
    return unknownItem(
      "w1_confirmation",
      "Judge",
      "W1確認",
      actual,
      "保存されたW1確認modeに従う",
      true,
    );
  }
  if (mode === "OFF") {
    return optionalItem(
      "w1_confirmation",
      "Judge",
      "W1確認",
      actual,
      "OFF",
      "対象外",
    );
  }
  if (mode === "OBSERVE_ONLY") {
    return optionalItem(
      "w1_confirmation",
      "Judge",
      "W1確認",
      actual,
      `記録のみ / ${fromSavedDecision.is_w1_confirmation_passed ? "通過" : "不通過"}`,
      "参考",
    );
  }
  return requiredItem(
    "w1_confirmation",
    "Judge",
    "W1確認",
    actual,
    "保存された必須modeを通過",
    fromSavedDecision.is_w1_confirmation_passed,
  );
}

function buildW1Item(
  fromW1: EntryCheckTimeFrame | undefined,
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  if (fromSavedDecision) return savedW1Item(fromSavedDecision);
  return unknownItem(
    "w1_confirmation",
    "Judge",
    "W1確認",
    `${directionValue("方向", fromW1)} / EMA200 ${ema200Direction(fromW1) ?? "記録なし"}`,
    "実行時のW1確認modeが未記録",
    true,
  );
}

function buildCountItem(
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  if (!fromSavedDecision) {
    return unknownItem(
      "signal_entry_count",
      "Entry",
      "Signal / Entry count",
      "記録なし",
      "実行時のstateful countが必要",
      true,
    );
  }
  const signalCount = finiteNumber(fromSavedDecision.signal_count);
  const entryCount = finiteNumber(fromSavedDecision.entry_count);
  if (
    signalCount === null
    || entryCount === null
    || typeof fromSavedDecision.is_entry_count_match !== "boolean"
  ) {
    return requiredItem(
      "signal_entry_count",
      "Entry",
      "Signal / Entry count",
      "保存値不明",
      "Signal countとEntry countが一致",
      null,
    );
  }
  return requiredItem(
    "signal_entry_count",
    "Entry",
    "Signal / Entry count",
    `${formatNumber(signalCount, 0)} / ${formatNumber(entryCount, 0)}${fromSavedDecision.is_entry_evaluated ? "（評価済み）" : "（未評価）"}`,
    "Signal countとEntry countが一致",
    fromSavedDecision.is_entry_count_match,
  );
}

function buildDisplayWaveScopeItem(
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  if (!fromSavedDecision) {
    return unknownItem(
      "h1_display_wave_scope",
      "Entry",
      "H1表示Wave重複",
      "記録なし",
      "実行時の制限設定と使用済み状態が必要",
      true,
    );
  }
  const entryResult = String(fromSavedDecision.entry_result || "").trim();
  if (
    entryResult === "TIME_FRAME_ENTRY_REJECTED"
    || entryResult.startsWith("H1_DISPLAY_WAVE_")
  ) {
    return requiredItem(
      "h1_display_wave_scope",
      "Entry",
      "H1表示Wave重複",
      entryResult,
      "同じH1表示Waveで未使用",
      false,
    );
  }
  if (
    fromSavedDecision.is_entry
    || entryResult === "EMA200_DISTANCE_REJECTED"
  ) {
    return requiredItem(
      "h1_display_wave_scope",
      "Entry",
      "H1表示Wave重複",
      "制限OFFまたは通過",
      "実行時設定に従う（保存判定）",
      true,
    );
  }
  return unknownItem(
    "h1_display_wave_scope",
    "Entry",
    "H1表示Wave重複",
    entryResult || "保存値不明",
    "別条件が先にRejectされたため結果を特定不可",
    true,
  );
}

function buildEma200DistanceItem(
  fromH1: EntryCheckTimeFrame | undefined,
  fromSavedDecision: AlertDetail | null | undefined,
): H1EntryCheckItem {
  const savedEntryResult = String(
    fromSavedDecision?.entry_result || "",
  ).trim();
  if (
    fromSavedDecision
    && typeof fromSavedDecision.is_ema200_distance_within === "boolean"
  ) {
    const distance = finiteNumber(fromSavedDecision.close_ema200_diff_pips);
    const maxDistance = finiteNumber(fromSavedDecision.max_close_ema200_diff_pips);
    const actual = distance === null
      ? "保存値不明"
      : `${formatNumber(Math.abs(distance))} pips`;
    if (savedEntryResult === "EMA200_DISTANCE_REJECTED") {
      return requiredItem(
        "h1_ema200_distance",
        "Entry",
        "H1 EMA200距離",
        actual,
        `${formatNumber(maxDistance ?? 50)} pips以下（保存時判定）`,
        false,
      );
    }
    return optionalItem(
      "h1_ema200_distance",
      "Entry",
      "H1 EMA200距離",
      actual,
      "現行H1ではエントリー条件に使用しない",
      "参考",
    );
  }
  const distance = finiteNumber(fromH1?.ema200_close_diff_pips);
  if (distance === null) {
    return unknownItem(
      "h1_ema200_distance",
      "Entry",
      "H1 EMA200距離",
      "記録なし",
      "現行H1ではエントリー条件に使用しない",
    );
  }
  const absoluteDistance = Math.abs(distance);
  return optionalItem(
    "h1_ema200_distance",
    "Entry",
    "H1 EMA200距離",
    `${formatNumber(absoluteDistance)} pips`,
    "現行H1ではエントリー条件に使用しない",
    "参考",
  );
}

function buildOverall(
  fromItems: readonly H1EntryCheckItem[],
  fromSavedDecision: AlertDetail | null | undefined,
): Pick<H1EntryCheckSnapshot, "overallStatus" | "overallReason" | "source"> {
  if (fromSavedDecision) {
    const entryResult = String(fromSavedDecision.entry_result || "").trim();
    if (fromSavedDecision.is_entry) {
      return {
        overallStatus: "OK",
        overallReason: entryResult || "保存済み判定でエントリー成立",
        source: "SAVED",
      };
    }
    return {
      overallStatus: "NG",
      overallReason: savedEntryResultReason(entryResult),
      source: "SAVED",
    };
  }

  const requiredItems = fromItems.filter((item) => item.required);
  const firstFailedItem = requiredItems.find((item) => item.status === "NG");
  if (firstFailedItem) {
    return {
      overallStatus: "NG",
      overallReason: `最初のNG: ${firstFailedItem.label}`,
      source: "SNAPSHOT",
    };
  }
  const firstUnknownItem = requiredItems.find((item) => item.status === "不明");
  if (firstUnknownItem) {
    return {
      overallStatus: "判定不能",
      overallReason: `必須データ不足: ${firstUnknownItem.label}`,
      source: "SNAPSHOT",
    };
  }
  return {
    overallStatus: "OK",
    overallReason: "Snapshotから判定可能な必須項目はすべて通過",
    source: "SNAPSHOT",
  };
}

function savedEntryResultReason(fromEntryResult: string): string {
  if (fromEntryResult === "ELLIOT_LABEL_REJECTED") {
    return "Entry NG: H1 Elliott（ELLIOT_LABEL_REJECTED）";
  }
  if (fromEntryResult === "EMA200_DISTANCE_REJECTED") {
    return "Entry NG: H1 EMA200距離（EMA200_DISTANCE_REJECTED）";
  }
  if (fromEntryResult === "TIME_FRAME_ENTRY_REJECTED") {
    return "Entry NG: 時間足Entry条件（TIME_FRAME_ENTRY_REJECTED）";
  }
  if (fromEntryResult === "H1_DISPLAY_WAVE_ENTRY_ALREADY_USED") {
    return "Entry NG: H1表示Waveを使用済み（H1_DISPLAY_WAVE_ENTRY_ALREADY_USED）";
  }
  if (fromEntryResult.startsWith("H1_DISPLAY_WAVE_")) {
    return `Entry NG: H1表示Wave管理（${fromEntryResult}）`;
  }
  if (fromEntryResult === "NOT_EVALUATED") {
    return "Entry未評価（NOT_EVALUATED）";
  }
  return fromEntryResult || "保存済み判定で非エントリー";
}

/**
 * H1時間足Snapshotからエントリー条件の参考判定を処理順に生成します。
 * 保存済みAlert判定がある場合、モード依存項目と総合結果は保存値を優先します。
 *
 * @param fromTimeFrames 時間足Snapshot一覧
 * @param fromSpreadPips 観測時点のSpread pips
 * @param fromSavedDecision 保存済みAlert判定
 * @return H1エントリー条件Snapshot
 */
export function buildH1EntryCheckSnapshot(
  fromTimeFrames: readonly ObservationDetailTimeFrame[],
  fromSpreadPips: number | null | undefined,
  fromSavedDecision?: AlertDetail | null,
): H1EntryCheckSnapshot {
  const mn1 = findTimeFrame(fromTimeFrames, "MN1");
  const w1 = findTimeFrame(fromTimeFrames, "W1");
  const d1 = findTimeFrame(fromTimeFrames, "D1");
  const h4 = findTimeFrame(fromTimeFrames, "H4");
  const h1 = findTimeFrame(fromTimeFrames, "H1");
  const h1Direction = direction(h1);
  const savedSpread = finiteNumber(fromSavedDecision?.spread_pips);
  const spread = savedSpread ?? finiteNumber(fromSpreadPips);

  const items: H1EntryCheckItem[] = [
    buildCurrencyStrengthItem(fromSavedDecision),
    buildSpreadItem(spread),
    buildWaveDirectionItem(h1, h1Direction),
    buildRequiredDirectionItem(d1, h4, h1, h1Direction),
    buildAdditionalDirectionItem(mn1, w1, fromSavedDecision),
    buildElliottItem(h1, fromSavedDecision),
    buildGmmaItem(
      "h1_gmma_trend",
      "H1 GMMA trend",
      h1?.gmma_trend_count,
      h1Direction,
    ),
    buildGmmaItem(
      "h1_gmma_cross",
      "H1 GMMA cross",
      h1?.gmma_cross_count,
      h1Direction,
    ),
    buildH1Ema200Item(h1, h1Direction),
    buildH4Ema200Item(h4, h1Direction),
    buildW1Item(w1, fromSavedDecision),
    buildCountItem(fromSavedDecision),
    buildDisplayWaveScopeItem(fromSavedDecision),
    buildEma200DistanceItem(h1, fromSavedDecision),
  ];
  const overall = buildOverall(items, fromSavedDecision);
  return {
    direction: h1Direction,
    items,
    ...overall,
  };
}

function statusClass(fromStatus: H1EntryCheckStatus): string {
  if (fromStatus === "OK") return "good";
  if (fromStatus === "NG") return "h1-entry-check-status-ng";
  if (fromStatus === "参考") return "warn";
  if (fromStatus === "対象外") return "neutral";
  return "neutral h1-entry-check-status-unknown";
}

function overallStatusClass(fromStatus: H1EntryCheckOverallStatus): string {
  if (fromStatus === "OK") return "good";
  if (fromStatus === "NG") return "h1-entry-check-status-ng";
  return "warn";
}

function statusSummary(fromItems: readonly H1EntryCheckItem[]): string {
  const statuses: H1EntryCheckStatus[] = ["OK", "NG", "参考", "対象外", "不明"];
  return statuses
    .map((status) => `${status} ${fromItems.filter((item) => item.status === status).length}`)
    .join(" / ");
}

/** H1エントリー条件のSnapshot推定を処理順で表示します。 */
export function H1EntryCheckPanel({
  timeFrames,
  spreadPips,
  savedDecision,
}: H1EntryCheckPanelProps) {
  const headingId = useId();
  const snapshot = useMemo(
    () => buildH1EntryCheckSnapshot(timeFrames, spreadPips, savedDecision),
    [savedDecision, spreadPips, timeFrames],
  );
  let currentPhase: H1EntryCheckPhase | null = null;

  return (
    <section
      aria-labelledby={headingId}
      className="h1-entry-check-panel"
      data-overall-status={snapshot.overallStatus}
    >
      <div className="h1-entry-check-heading">
        <div>
          <p className="eyebrow">H1 ENTRY CHECK</p>
          <h3 id={headingId}>ZigZagElliot H1エントリー条件</h3>
        </div>
        <div className="h1-entry-check-overall">
          {snapshot.direction && (
            <span className={`badge ${snapshot.direction.toLowerCase()}`}>
              H1 {snapshot.direction}
            </span>
          )}
          <span
            aria-label={`総合判定 ${snapshot.overallStatus}`}
            className={`badge ${overallStatusClass(snapshot.overallStatus)}`}
          >
            総合 {snapshot.overallStatus}
          </span>
          <span className="badge neutral">
            {snapshot.source === "SAVED" ? "保存判定" : "Snapshot推定"}
          </span>
        </div>
      </div>
      <details className="h1-entry-check-disclosure">
        <summary>
          <span className="h1-entry-check-reason" role="status">
            {snapshot.overallReason} / {statusSummary(snapshot.items)}
          </span>
          <span className="h1-entry-check-toggle-label">条件を表示</span>
        </summary>
        <p className="h1-entry-check-note">
          {snapshot.source === "SAVED"
            ? "総合結果と保存済み診断はAlert記録を正本とし、その他の行は保存時Snapshotから表示します。"
            : "Snapshot推定は保存済みの分析値だけを使用します。mode・通貨強弱・countが未記録の場合、総合は判定不能です。"}
          Spread行は現行H1上限の5.0 pipsで再判定するため、過去の判定条件とは異なる場合があります。
        </p>
        <div className="h1-entry-check-table-wrap">
          <table aria-label="H1エントリー条件チェック" className="h1-entry-check-table">
          <thead>
            <tr>
              <th scope="col">順序 / 項目</th>
              <th scope="col">実測</th>
              <th scope="col">必要条件</th>
              <th scope="col">状態</th>
            </tr>
          </thead>
          <tbody>
            {snapshot.items.map((item, index) => {
              const showPhase = item.phase !== currentPhase;
              currentPhase = item.phase;
              return (
                <Fragment key={item.id}>
                  {showPhase && (
                    <tr className="h1-entry-check-phase" key={`${item.phase}-phase`}>
                      <th colSpan={4} scope="rowgroup">{item.phase}</th>
                    </tr>
                  )}
                  <tr data-check-id={item.id}>
                    <th scope="row">
                      <span className="h1-entry-check-order">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      {item.label}
                    </th>
                    <td>{item.actual}</td>
                    <td>{item.expected}</td>
                    <td>
                      <span
                        aria-label={`${item.label} ${item.status}`}
                        className={`badge ${statusClass(item.status)}`}
                      >
                        {item.status}
                      </span>
                    </td>
                  </tr>
                </Fragment>
              );
            })}
          </tbody>
          </table>
        </div>
      </details>
    </section>
  );
}
