export const H4_WAVE_UNRESTRICTED_DESCRIPTION =
  "波番号・第5波構造の制限なし（参考表示）";

export const H4_FE_UNRESTRICTED_DESCRIPTION = "対象外（参考表示）";

export const M5_MN1_AND_W1_EMA200_DESCRIPTION = "MN1のisBuy一致 AND W1のEMA200一致";

function hasUniqueSavedSetting(
  fromInputText: unknown,
  fromKey: string,
  fromValue: string,
): boolean {
  if (typeof fromInputText !== "string") return false;
  const entries = fromInputText.split("|").filter((entry) => (
    entry.split("=", 1)[0].trim() === fromKey
  ));
  return entries.length === 1 && entries[0] === `${fromKey}=${fromValue}`;
}

/** H1・M15の保存設定が単一の明示falseの場合だけ、H4波動制限の解除を表示します。 */
export function isH4WaveRestrictionDisabled(
  fromTimeFrame: unknown,
  fromInputText: unknown,
): boolean {
  return (fromTimeFrame === "H1" || fromTimeFrame === "M15")
    && hasUniqueSavedSetting(fromInputText, "h1H4WaveRestrictionEnabled", "false");
}

/** H1 ENTRY CHECKへM15の設定を適用しません。 */
export function isH1H4WaveRestrictionDisabled(
  fromTimeFrame: unknown,
  fromInputText: unknown,
): boolean {
  return fromTimeFrame === "H1" && isH4WaveRestrictionDisabled(fromTimeFrame, fromInputText);
}

/** M15の解除RunでH4 FE上限も明示的に0.0と保存されている場合だけ対象外とします。 */
export function isM15H4FeLimitDisabled(
  fromTimeFrame: unknown,
  fromInputText: unknown,
): boolean {
  return fromTimeFrame === "M15"
    && isH4WaveRestrictionDisabled(fromTimeFrame, fromInputText)
    && hasUniqueSavedSetting(fromInputText, "m15H4MaxFibonacciExpansionPercent", "0.0");
}

/** M5の保存設定が単一の明示trueの場合だけ、MN1・W1 EMA200のAND条件を表示します。 */
export function isM5Mn1AndW1Ema200Required(
  fromTimeFrame: unknown,
  fromInputText: unknown,
): boolean {
  return fromTimeFrame === "M5"
    && hasUniqueSavedSetting(fromInputText, "m5Mn1AndW1Ema200Required", "true");
}
