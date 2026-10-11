export const H4_WAVE_UNRESTRICTED_DESCRIPTION =
  "波番号・第5波構造の制限なし（参考表示）";

/** H1の保存設定が単一の明示falseの場合だけ、H4波動制限の解除を表示します。 */
export function isH1H4WaveRestrictionDisabled(
  fromTimeFrame: unknown,
  fromInputText: unknown,
): boolean {
  if (fromTimeFrame !== "H1" || typeof fromInputText !== "string") return false;
  const key = "h1H4WaveRestrictionEnabled";
  const entries = fromInputText.split("|").filter((entry) => (
    entry.split("=", 1)[0].trim() === key
  ));
  return entries.length === 1 && entries[0] === `${key}=false`;
}
