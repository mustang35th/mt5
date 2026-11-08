import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { AlertListItem } from "../api/types";
import { CurrencyStrengthCell } from "./CurrencyStrengthCell";

function savedAlert(fromOverrides: Partial<AlertListItem> = {}): AlertListItem {
  return {
    id: 42,
    side: "SELL",
    source_mode: "TESTER",
    is_entry: false,
    is_currency_strength_enabled: true,
    currency_strength_status: 3,
    is_currency_strength_available: true,
    base_currency: "AUD",
    quote_currency: "USD",
    base_long_medium_rank: 1,
    quote_long_medium_rank: 6,
    base_medium_short_rank: 2,
    quote_medium_short_rank: 7,
    long_medium_rank_difference: 5,
    medium_short_rank_difference: 5,
    currency_strength_source_mode: "LIVE",
    currency_strength_target_m5_bar_time: 1_788_192_000,
    currency_strength_m5_bar_time: 1_788_192_000,
    currency_strength_calculation_version: "weighted-v1",
    ...fromOverrides,
  } as AlertListItem;
}

describe("CurrencyStrengthCell", () => {
  it("shows saved BUY agreement in three rows independently of alert side and ENTRY", () => {
    const { container } = render(<CurrencyStrengthCell alert={savedAlert()} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：BUY一致/);
    expect(cell).toHaveClass("buy");
    expect(cell).toHaveTextContent("長中期1 / 6差+5");
    expect(cell).toHaveTextContent("中短期2 / 7差+5");
    expect(cell).not.toHaveTextContent(/ENTRY|READY/);
    expect(container.querySelectorAll(".currency-strength-cell-period")).toHaveLength(2);
    expect(container.querySelector("strong")).toHaveTextContent("1");
    expect(cell.getAttribute("title")).toContain("基軸：AUD ／ 決済：USD");
    expect(cell.getAttribute("title")).toContain("アラートの売買方向との一致やENTRY成立を保証しません");
    expect(cell.getAttribute("title")).toContain("取得元：LIVE");
    expect(cell.getAttribute("title")).toContain("対象M5：2026/08/31 16:00:00 SRV");
    expect(cell.getAttribute("title")).toContain("実M5：2026/08/31 16:00:00 SRV");
    expect(cell.getAttribute("title")).toContain("計算方式：weighted-v1");
    expect(cell.getAttribute("title")).not.toContain("最新");
  });

  it("shows SELL agreement and emphasizes rank 8", () => {
    const { container } = render(<CurrencyStrengthCell alert={savedAlert({
      base_long_medium_rank: 8, quote_long_medium_rank: 3, long_medium_rank_difference: -5,
      base_medium_short_rank: 6, quote_medium_short_rank: 2, medium_short_rank_difference: -4,
      is_currency_strength_enabled: false,
    })} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：SELL一致/);
    expect(cell).toHaveClass("sell");
    expect(cell).toHaveTextContent("差-5");
    expect(container.querySelector("strong")).toHaveTextContent("8");
  });

  it.each([
    { base_medium_short_rank: 7, quote_medium_short_rank: 2, medium_short_rank_difference: -5 },
    { base_medium_short_rank: 4, quote_medium_short_rank: 4, medium_short_rank_difference: 0 },
  ])("distinguishes opposed or tied periods from agreement: %o", (fromOverrides) => {
    render(<CurrencyStrengthCell alert={savedAlert(fromOverrides)} />);

    expect(screen.getByLabelText(/通貨強弱（保存時）：方向混在/)).toHaveClass("mixed");
  });

  it.each([undefined, null, false])("does not assert BUY when availability is %s", (fromAvailable) => {
    render(<CurrencyStrengthCell alert={savedAlert({ is_currency_strength_available: fromAvailable })} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：/);
    expect(cell).toHaveClass("unavailable");
    expect(cell).not.toHaveTextContent("BUY一致");
    expect(cell.getAttribute("title")).toContain("利用不可");
    if (fromAvailable === false) {
      expect(cell).toHaveTextContent("未取得");
    } else {
      expect(cell).toHaveTextContent("未記録");
    }
  });

  it.each<Partial<AlertListItem>>([
    { base_long_medium_rank: 0 },
    { quote_medium_short_rank: 9 },
    { base_medium_short_rank: 1.5 },
    { quote_long_medium_rank: Number.NaN },
    { base_long_medium_rank: Number.POSITIVE_INFINITY },
    { medium_short_rank_difference: 0.5 },
    { long_medium_rank_difference: 8 },
    { long_medium_rank_difference: -8 },
    { medium_short_rank_difference: Number.POSITIVE_INFINITY },
    { base_long_medium_rank: "1" as unknown as number },
  ])("marks invalid saved ranks or differences as unknown: %o", (fromOverrides) => {
    render(<CurrencyStrengthCell alert={savedAlert(fromOverrides)} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：不明/);
    expect(cell).toHaveClass("unavailable");
    expect(cell).toHaveTextContent("—");
    expect(cell.getAttribute("title")).toContain("保存値不足・不正");
  });

  it("rejects a direction inconsistent with the saved ranks", () => {
    render(<CurrencyStrengthCell alert={savedAlert({ long_medium_rank_difference: -5 })} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：不明/);
    expect(cell).toHaveClass("unavailable");
    expect(cell.getAttribute("title")).toContain("順位と保存差が不整合");
    expect(cell).not.toHaveTextContent("方向混在");
  });

  it("keeps absent differences absent instead of deriving a value or substituting zero", () => {
    render(<CurrencyStrengthCell alert={savedAlert({
      long_medium_rank_difference: undefined,
      medium_short_rank_difference: null,
    })} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：不明/);
    expect(screen.getAllByText("差—")).toHaveLength(2);
    expect(cell).not.toHaveTextContent("差0");
    expect(cell).not.toHaveTextContent("差+5");
  });

  it("distinguishes absent old snapshot fields from a recorded unavailable snapshot", () => {
    render(<CurrencyStrengthCell alert={{ id: 1, source_mode: "TESTER" } as AlertListItem} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：未記録/);
    expect(cell.getAttribute("title")).toContain("取得元：—");
    expect(cell.getAttribute("title")).toContain("時刻未記録");
    expect(cell.getAttribute("title")).not.toContain("取得元：TESTER");
    expect(screen.queryByText("古い")).not.toBeInTheDocument();
  });

  it("marks unequal positive saved M5 times as old and preserves server seconds", () => {
    render(<CurrencyStrengthCell alert={savedAlert({
      currency_strength_m5_bar_time: 1_788_191_701,
    })} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：BUY一致/);
    expect(screen.getByText("古い")).toBeInTheDocument();
    expect(cell.getAttribute("title")).toContain("実M5：2026/08/31 15:55:01 SRV");
    expect(cell.getAttribute("title")).toContain("対象M5と実M5が不一致");
  });

  it.each([undefined, null, 0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])(
    "does not infer freshness from a missing or invalid timestamp: %s", (fromTime) => {
      render(<CurrencyStrengthCell alert={savedAlert({ currency_strength_m5_bar_time: fromTime })} />);

      const cell = screen.getByLabelText(/通貨強弱（保存時）：BUY一致/);
      expect(cell.getAttribute("title")).toContain("実M5：—");
      expect(cell.getAttribute("title")).toContain("時刻未記録");
      expect(cell.getAttribute("title")).not.toContain("最新");
      expect(screen.queryByText("古い")).not.toBeInTheDocument();
    },
  );

  it.each<Partial<AlertListItem>>([
    { currency_strength_target_m5_bar_time: Number.MAX_SAFE_INTEGER },
    { currency_strength_m5_bar_time: Number.MAX_SAFE_INTEGER },
    { currency_strength_target_m5_bar_time: Date.UTC(10000, 0, 1) / 1000 },
    { currency_strength_m5_bar_time: Date.UTC(10000, 0, 1) / 1000 },
  ])("does not mark an unrepresentable saved date as old: %o", (fromOverrides) => {
    render(<CurrencyStrengthCell alert={savedAlert(fromOverrides)} />);

    const cell = screen.getByLabelText(/通貨強弱（保存時）：BUY一致/);
    expect(cell.getAttribute("title")).toContain("M5：—");
    expect(cell.getAttribute("title")).toContain("時刻照合：時刻未記録");
    expect(cell.getAttribute("title")).not.toContain("不一致");
    expect(screen.queryByText("古い")).not.toBeInTheDocument();
  });

  it("renders saved metadata only as text", () => {
    const { container } = render(<CurrencyStrengthCell alert={savedAlert({
      base_currency: "<img src=x onerror=alert(1)>",
      currency_strength_calculation_version: "<script>alert(1)</script>",
    })} />);

    expect(container.querySelector("img, script")).not.toBeInTheDocument();
    expect(screen.getByLabelText(/通貨強弱（保存時）：BUY一致/).getAttribute("title"))
      .toContain("<script>alert(1)</script>");
  });
});
