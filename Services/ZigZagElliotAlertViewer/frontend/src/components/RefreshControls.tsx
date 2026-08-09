import type { ChangeEvent } from "react";
import {
  isRefreshIntervalSeconds,
  REFRESH_INTERVAL_OPTIONS,
  type RefreshIntervalSeconds,
} from "../lib/refreshSettings";

interface RefreshControlsProps {
  intervalSeconds: RefreshIntervalSeconds;
  statusText: string;
  lastCheckedText: string;
  busy: boolean;
  onIntervalChange: (intervalSeconds: RefreshIntervalSeconds) => void;
  onRefresh: () => void;
}

function intervalLabel(intervalSeconds: RefreshIntervalSeconds): string {
  if (intervalSeconds === 0) return "OFF";
  return `${intervalSeconds}秒`;
}

export function RefreshControls({
  intervalSeconds,
  statusText,
  lastCheckedText,
  busy,
  onIntervalChange,
  onRefresh,
}: RefreshControlsProps) {
  function changeInterval(event: ChangeEvent<HTMLSelectElement>) {
    const nextInterval = Number(event.target.value);
    if (isRefreshIntervalSeconds(nextInterval)) onIntervalChange(nextInterval);
  }

  return (
    <div className="refresh-controls">
      <label className="refresh-interval-field">
        <span>自動更新</span>
        <select
          aria-label="自動更新間隔"
          value={intervalSeconds}
          onChange={changeInterval}
        >
          {REFRESH_INTERVAL_OPTIONS.map((option) => (
            <option key={option} value={option}>{intervalLabel(option)}</option>
          ))}
        </select>
      </label>
      <button
        className="secondary-button refresh-button"
        type="button"
        disabled={busy}
        onClick={onRefresh}
      >
        {busy ? "更新中…" : "今すぐ更新"}
      </button>
      <div className="refresh-state">
        <span>{statusText}</span>
        <small>{lastCheckedText}</small>
      </div>
    </div>
  );
}
