import { elliottOriginalSuffix } from "../lib/format";
import "./ElliottLabelText.css";

interface Props {
  label: string;
  mainLabel: unknown;
  originalLabel: unknown;
  description?: string;
}

/** Keep the current label prominent and explain the saved pre-recount suffix. */
export function ElliottLabelText({ label, mainLabel, originalLabel, description }: Props) {
  const suffix = elliottOriginalSuffix(mainLabel, originalLabel);
  const hasSuffix = suffix !== "" && label.endsWith(suffix);
  const tooltip = [label, hasSuffix && "[ ]＝再カウント前の主波ラベル", description].filter(Boolean).join(" / ");
  return (
    <span
      className="elliott-label-text"
      aria-label={label}
      title={tooltip}
    >
      {hasSuffix ? label.slice(0, -suffix.length) : label}
      {hasSuffix && <span className="elliott-original-label">{suffix}</span>}
    </span>
  );
}
