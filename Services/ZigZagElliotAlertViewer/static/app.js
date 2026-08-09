"use strict";

const state = {
  page: 1,
  pageCount: 1,
  sort: "jst_time",
  order: "desc",
  runs: [],
  lastFocused: null,
  requestSerial: 0,
  detailRequestSerial: 0,
};

const elements = {
  connectionStatus: document.querySelector("#connectionStatus"),
  filterForm: document.querySelector("#filterForm"),
  runId: document.querySelector("#runId"),
  query: document.querySelector("#query"),
  symbol: document.querySelector("#symbol"),
  side: document.querySelector("#side"),
  rank: document.querySelector("#rank"),
  w1Aligned: document.querySelector("#w1Aligned"),
  fromDate: document.querySelector("#fromDate"),
  toDate: document.querySelector("#toDate"),
  pageSize: document.querySelector("#pageSize"),
  resetButton: document.querySelector("#resetButton"),
  exportButton: document.querySelector("#exportButton"),
  totalCount: document.querySelector("#totalCount"),
  buyCount: document.querySelector("#buyCount"),
  sellCount: document.querySelector("#sellCount"),
  alignedCount: document.querySelector("#alignedCount"),
  mismatchedCount: document.querySelector("#mismatchedCount"),
  resultStatus: document.querySelector("#resultStatus"),
  alertRows: document.querySelector("#alertRows"),
  emptyState: document.querySelector("#emptyState"),
  previousPage: document.querySelector("#previousPage"),
  nextPage: document.querySelector("#nextPage"),
  pageIndicator: document.querySelector("#pageIndicator"),
  drawerBackdrop: document.querySelector("#drawerBackdrop"),
  detailDrawer: document.querySelector("#detailDrawer"),
  closeDrawer: document.querySelector("#closeDrawer"),
  detailTitle: document.querySelector("#detailTitle"),
  detailContent: document.querySelector("#detailContent"),
  toast: document.querySelector("#toast"),
};


function createElement(tagName, className = "", text = null) {
  const element = document.createElement(tagName);
  if (className) {
    element.className = className;
  }
  if (text !== null && text !== undefined) {
    element.textContent = String(text);
  }
  return element;
}


async function fetchJson(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  let payload;
  try {
    payload = await response.json();
  } catch (_error) {
    payload = { error: `HTTP ${response.status}` };
  }
  if (!response.ok) {
    throw new Error(payload.error || payload.detail || `HTTP ${response.status}`);
  }
  return payload;
}


function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  window.clearTimeout(showToast.timerId);
  showToast.timerId = window.setTimeout(() => {
    elements.toast.hidden = true;
  }, 6000);
}


function formatNumber(value, digits = 1) {
  if (value === null || value === undefined || value === "") {
    return "—";
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return String(value);
  }
  return new Intl.NumberFormat("ja-JP", {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  }).format(number);
}


function formatInteger(value) {
  if (value === null || value === undefined) {
    return "0";
  }
  return new Intl.NumberFormat("ja-JP").format(Number(value));
}


function displayValue(value, fallback = "—") {
  if (value === null || value === undefined || value === "") {
    return fallback;
  }
  return String(value);
}


function yesNo(value) {
  return value ? "YES" : "NO";
}


function waveLabel(elliotLabel, subElliotLabel) {
  const mainLabel = displayValue(elliotLabel);
  if (subElliotLabel === null || subElliotLabel === undefined || subElliotLabel === "") {
    return `wave ${mainLabel}`;
  }
  return `wave ${mainLabel}.${subElliotLabel}`;
}


function sideClass(side) {
  const normalized = String(side || "").toLowerCase();
  if (normalized === "buy") return "buy";
  if (normalized === "sell") return "sell";
  return "neutral";
}


function setSelectOptions(selectElement, values, allLabel = "すべて") {
  const currentValue = selectElement.value;
  selectElement.replaceChildren();
  const emptyOption = createElement("option", "", allLabel);
  emptyOption.value = "";
  selectElement.append(emptyOption);
  values.forEach((value) => {
    const option = createElement("option", "", value);
    option.value = value;
    selectElement.append(option);
  });
  if ([...selectElement.options].some((option) => option.value === currentValue)) {
    selectElement.value = currentValue;
  }
}


function populateRuns(runPayload) {
  state.runs = runPayload.items || [];
  elements.runId.replaceChildren();
  const allRunsOption = createElement("option", "", "すべてのRun（重複を含む）");
  allRunsOption.value = "";
  elements.runId.append(allRunsOption);
  state.runs.forEach((run) => {
    const symbolText = run.symbols || "アラートなし";
    const range = run.last_alert_time_text
      ? `${run.first_alert_time_text || "?"} – ${run.last_alert_time_text}`
      : "記録なし";
    const label = `Run ${run.id}｜${symbolText}｜${run.alert_count}件｜${range}`;
    const option = createElement("option", "", label);
    option.value = String(run.id);
    elements.runId.append(option);
  });
}


function structureLabel(alert) {
  const rank = displayValue(alert.h1_structure_rank);
  return alert.is_h1_structure_late ? `${rank}-LATE` : rank;
}


function restoreFiltersFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const mappings = {
    runId: elements.runId,
    q: elements.query,
    symbol: elements.symbol,
    side: elements.side,
    rank: elements.rank,
    w1Aligned: elements.w1Aligned,
    from: elements.fromDate,
    to: elements.toDate,
    pageSize: elements.pageSize,
  };
  Object.entries(mappings).forEach(([name, element]) => {
    if (params.has(name)) {
      element.value = params.get(name);
    }
  });
  if (!params.has("runId")) {
    const latestWithAlerts = state.runs.find((run) => Number(run.alert_count) > 0);
    if (latestWithAlerts) {
      elements.runId.value = String(latestWithAlerts.id);
    }
  }
  state.page = Math.max(1, Number(params.get("page")) || 1);
  state.sort = params.get("sort") || "jst_time";
  state.order = params.get("order") === "asc" ? "asc" : "desc";
}


function buildQuery({ includePaging = true, includeSorting = true } = {}) {
  const params = new URLSearchParams();
  const formData = new FormData(elements.filterForm);
  for (const [name, rawValue] of formData.entries()) {
    const value = String(rawValue).trim();
    if (!value || (name === "w1Aligned" && value === "all")) {
      continue;
    }
    params.set(name, value);
  }
  if (includePaging) {
    params.set("page", String(state.page));
    params.set("pageSize", elements.pageSize.value);
  }
  if (includeSorting) {
    params.set("sort", state.sort);
    params.set("order", state.order);
  }
  return params;
}


function updateUrl() {
  const params = buildQuery();
  window.history.replaceState(null, "", `${window.location.pathname}?${params}`);
}


function renderSummary(summary) {
  elements.totalCount.textContent = formatInteger(summary.total_count);
  elements.buyCount.textContent = formatInteger(summary.buy_count);
  elements.sellCount.textContent = formatInteger(summary.sell_count);
  elements.alignedCount.textContent = formatInteger(summary.w1_aligned_count);
  elements.mismatchedCount.textContent = formatInteger(summary.w1_mismatched_count);
}


function makeBadge(text, variant = "neutral") {
  return createElement("span", `badge ${variant}`, text);
}


function makeTimeFrameSequence(alert) {
  const wrapper = createElement("div", "tf-sequence");
  [
    ["MN1", alert.mn1_side],
    ["W1", alert.w1_side],
    ["D1", alert.d1_side],
    ["H4", alert.h4_side],
    ["H1", alert.h1_side],
  ].forEach(([timeFrame, side]) => {
    const normalizedSide = String(side || "NONE").toUpperCase();
    const chip = createElement("span", `tf-chip ${sideClass(normalizedSide)}`);
    chip.append(createElement("small", "", timeFrame));
    chip.append(createElement("strong", "", normalizedSide === "NONE" ? "—" : normalizedSide));
    wrapper.append(chip);
  });
  return wrapper;
}


function renderAlertRows(items) {
  elements.alertRows.replaceChildren();
  elements.emptyState.hidden = items.length !== 0;

  items.forEach((alert) => {
    const row = createElement("tr");
    row.tabIndex = 0;
    row.setAttribute("role", "button");
    row.setAttribute("aria-label", `${alert.symbol_name} ${alert.side} の詳細を表示`);
    row.addEventListener("click", () => openDetail(alert.id, row));
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openDetail(alert.id, row);
      }
    });

    const dateCell = createElement("td");
    dateCell.append(createElement("span", "date-main", displayValue(alert.jst_time_text)));
    dateCell.append(createElement("span", "date-sub", `Server ${displayValue(alert.server_time_text)}`));
    row.append(dateCell);

    const symbolCell = createElement("td");
    symbolCell.append(createElement("span", "symbol", alert.symbol_name));
    symbolCell.append(createElement("span", "subtext", `Run ${alert.run_id} / ${alert.time_frame_text}`));
    row.append(symbolCell);

    const sideCell = createElement("td");
    sideCell.append(makeBadge(alert.side, sideClass(alert.side)));
    row.append(sideCell);

    const decisionCell = createElement("td");
    decisionCell.append(createElement("strong", "", `${alert.strategy} ${alert.signal_count}/${alert.entry_count}`));
    decisionCell.append(createElement("span", "subtext", displayValue(alert.alert_title)));
    row.append(decisionCell);

    const structureCell = createElement("td");
    structureCell.append(makeBadge(structureLabel(alert), "neutral"));
    structureCell.append(createElement("span", "subtext", `wave ${displayValue(alert.current_elliot_label)}`));
    row.append(structureCell);

    const timeFrameCell = createElement("td");
    timeFrameCell.append(makeTimeFrameSequence(alert));
    row.append(timeFrameCell);

    const alignmentCell = createElement("td");
    if (alert.is_w1_aligned === true) {
      alignmentCell.append(makeBadge("一致", "good"));
    } else if (alert.is_w1_aligned === false) {
      alignmentCell.append(makeBadge("不一致", "warn"));
    } else {
      alignmentCell.append(makeBadge("不明", "neutral"));
    }
    alignmentCell.append(createElement("span", "subtext", `W1 ${displayValue(alert.w1_side)}`));
    row.append(alignmentCell);

    const riskCell = createElement("td", "metric-stack");
    riskCell.append(createElement("span", "", `${formatNumber(alert.risk_pips)} pips`));
    riskCell.append(createElement("span", "subtext", `spread ${formatNumber(alert.spread_pips)} pips`));
    row.append(riskCell);

    const entryCell = createElement("td");
    const entryVariant = alert.is_entry ? "good" : "neutral";
    entryCell.append(makeBadge(displayValue(alert.entry_result), entryVariant));
    row.append(entryCell);

    elements.alertRows.append(row);
  });
}


function updateSortButtons() {
  document.querySelectorAll(".sort-button").forEach((button) => {
    const active = button.dataset.sort === state.sort;
    button.classList.toggle("active", active);
    button.classList.toggle("asc", active && state.order === "asc");
    button.closest("th").setAttribute(
      "aria-sort",
      active ? (state.order === "asc" ? "ascending" : "descending") : "none",
    );
  });
}


function renderPagination(payload) {
  state.page = payload.page || 1;
  state.pageCount = Math.max(payload.page_count || 1, 1);
  elements.pageIndicator.textContent = `${state.page} / ${state.pageCount}`;
  elements.previousPage.disabled = state.page <= 1;
  elements.nextPage.disabled = state.page >= state.pageCount;
  updateUrl();
}


async function refreshResults() {
  const requestSerial = ++state.requestSerial;
  elements.resultStatus.textContent = "読み込み中…";
  elements.filterForm.setAttribute("aria-busy", "true");
  updateUrl();
  const query = buildQuery().toString();
  try {
    const [listPayload, summaryPayload] = await Promise.all([
      fetchJson(`/api/alerts?${query}`),
      fetchJson(`/api/summary?${query}`),
    ]);
    if (requestSerial !== state.requestSerial) {
      return;
    }
    renderAlertRows(listPayload.items || []);
    renderSummary(summaryPayload);
    renderPagination(listPayload);
    updateSortButtons();
    const first = listPayload.total === 0 ? 0 : (listPayload.page - 1) * listPayload.page_size + 1;
    const last = Math.min(listPayload.page * listPayload.page_size, listPayload.total);
    elements.resultStatus.textContent = `${formatInteger(listPayload.total)}件中 ${formatInteger(first)}–${formatInteger(last)}件`;
  } catch (error) {
    if (requestSerial === state.requestSerial) {
      elements.resultStatus.textContent = "読み込み失敗・以前の結果を表示中";
      showToast(error.message);
    }
  } finally {
    if (requestSerial === state.requestSerial) {
      elements.filterForm.removeAttribute("aria-busy");
    }
  }
}


function detailField(label, value) {
  const wrapper = createElement("div", "detail-field");
  wrapper.append(createElement("span", "", label));
  wrapper.append(createElement("strong", "", displayValue(value)));
  return wrapper;
}


function buildTimeFrameCard(timeFrame) {
  const card = createElement("article", "timeframe-card");
  const header = createElement("div", "timeframe-header");
  header.append(createElement("strong", "", timeFrame.time_frame_text));
  const headerBadges = createElement("div", "badge-row");
  headerBadges.append(makeBadge(timeFrame.buy_sell_label, sideClass(timeFrame.buy_sell_label)));
  headerBadges.append(
    makeBadge(
      timeFrame.is_wave_confirmed ? "確定" : "形成中",
      timeFrame.is_wave_confirmed ? "good" : "warn",
    ),
  );
  header.append(headerBadges);
  card.append(header);

  const values = createElement("div", "timeframe-values");
  const waveDirection = timeFrame.is_wave_uptrend ? "UP / 上昇" : "DOWN / 下降";
  const fields = [
    ["分析方向", timeFrame.buy_sell_label],
    ["最新Wave方向", `${waveDirection} (${displayValue(timeFrame.wave_trend_label)})`],
    ["波動", waveLabel(timeFrame.latest_elliot_label, timeFrame.latest_sub_elliot_label)],
    ["状態", timeFrame.is_wave_confirmed ? "確定" : "形成中"],
    ["Wave種類", timeFrame.is_wave_motive ? "推進波" : "修正波"],
    ["ポイント", `${timeFrame.point_count} / wave ${timeFrame.latest_wave_index}`],
    ["Stochastic", `${displayValue(timeFrame.stochastic_main_order_text)} / ${displayValue(timeFrame.stochastic_main_direction_text)}`],
    ["GMMA", `trend ${formatNumber(timeFrame.gmma_trend_count, 0)} / cross ${formatNumber(timeFrame.gmma_cross_count, 0)}`],
    ["EMA200方向", timeFrame.is_ema200_buy ? "BUY" : timeFrame.is_ema200_sell ? "SELL" : "NONE"],
    ["ATR14", `${formatNumber(timeFrame.atr14_pips)} pips`],
    ["FE200距離", timeFrame.is_fibo_expansion_available ? `${formatNumber(timeFrame.distance_to_fe2000_pips)} pips` : "未取得"],
    ["現在Close", formatNumber(timeFrame.current_close, 5)],
  ];
  fields.forEach(([label, value]) => {
    const field = createElement("div");
    field.append(createElement("span", "", label));
    field.append(createElement("b", "", value));
    values.append(field);
  });
  card.append(values);
  return card;
}


function renderPointTable(points) {
  const wrapper = createElement("div", "points-wrap");
  const table = createElement("table");
  const head = createElement("thead");
  const headRow = createElement("tr");
  ["TF", "順", "時刻", "価格", "山/谷", "Elliott", "Sub", "pips", "Fibo", "FE", "状態"].forEach((label) => {
    headRow.append(createElement("th", "", label));
  });
  head.append(headRow);
  table.append(head);

  const body = createElement("tbody");
  points.forEach((point) => {
    const row = createElement("tr");
    if (point.is_latest) {
      row.classList.add("point-latest");
    }
    if (point.is_signal_reference) {
      row.classList.add("point-reference");
    }
    const status = [];
    if (point.is_latest) status.push("最新");
    if (point.is_signal_reference) status.push("基準");
    if (point.is_added_point) status.push("追加");
    if (point.is_correct) status.push("補正");
    const cells = [
      point.time_frame_text,
      point.point_order,
      point.bar_time_text,
      formatNumber(point.rate, 5),
      point.is_peak ? "山" : "谷",
      displayValue(point.elliot_label),
      displayValue(point.sub_elliot_label),
      formatNumber(point.pips_diff),
      point.is_fibonacci_available ? `${formatNumber(point.fibonacci_percent)}%` : "—",
      point.is_fibonacci_expansion_available ? `${formatNumber(point.fibonacci_expansion_percent)}%` : "—",
      status.join("・") || "—",
    ];
    cells.forEach((value) => row.append(createElement("td", "", value)));
    body.append(row);
  });
  table.append(body);
  wrapper.append(table);
  return wrapper;
}


function renderDetail(detailPayload, timeframePayload, pointPayload) {
  const alert = detailPayload.alert;
  const run = detailPayload.run || {};
  const timeframes = timeframePayload.items || [];
  const points = pointPayload.items || [];
  elements.detailTitle.textContent = `${alert.symbol_name} ${alert.side} / ${alert.current_bar_time_text}`;
  elements.detailContent.replaceChildren();

  const hero = createElement("section", "detail-hero");
  const heroMain = createElement("div");
  const badges = createElement("div", "badge-row");
  badges.append(makeBadge(alert.side, sideClass(alert.side)));
  badges.append(makeBadge(`H1 ${structureLabel(alert)}`, "neutral"));
  if (alert.is_w1_aligned === true) {
    badges.append(makeBadge("W1一致", "good"));
  } else if (alert.is_w1_aligned === false) {
    badges.append(makeBadge("W1不一致", "warn"));
  } else {
    badges.append(makeBadge("W1不明", "neutral"));
  }
  badges.append(makeBadge(run.source_mode || "UNKNOWN", "neutral"));
  if (String(run.tester_model || "").toLowerCase().includes("open")) {
    badges.append(makeBadge("Open Prices", "warn"));
  }
  heroMain.append(badges);
  heroMain.append(createElement("h3", "detail-title", alert.alert_title));
  heroMain.append(createElement("p", "subtitle", `JST ${alert.jst_time_text} / Server ${alert.server_time_text}`));
  hero.append(heroMain);
  const price = createElement("div", "detail-price");
  price.append(createElement("strong", "", formatNumber(alert.reference_price, 5)));
  const stopLossText = alert.is_stop_loss_available ? formatNumber(alert.stop_loss, 5) : "—";
  price.append(createElement("span", "", `SL ${stopLossText} / Risk ${formatNumber(alert.risk_pips)} pips`));
  hero.append(price);
  elements.detailContent.append(hero);

  const decisionSection = createElement("section", "detail-section");
  decisionSection.append(createElement("h3", "", "判定情報"));
  const decisionGrid = createElement("div", "detail-grid");
  [
    ["Strategy", alert.strategy],
    ["Signal / Entry count", `${alert.signal_count} / ${alert.entry_count}`],
    ["Judge", yesNo(alert.is_judge)],
    ["Count一致", yesNo(alert.is_entry_count_match)],
    ["Entry評価済み", yesNo(alert.is_entry_evaluated)],
    ["Entry波動", yesNo(alert.is_entry_wave)],
    ["EMA200距離条件", yesNo(alert.is_ema200_distance_within)],
    ["Alert / Entry", `${yesNo(alert.is_alert)} / ${yesNo(alert.is_entry)}`],
    ["Entry result", alert.entry_result],
    ["現在Elliott", `wave ${displayValue(alert.current_elliot_label)}`],
    ["EMA200距離", `${formatNumber(alert.close_ema200_diff_pips)} / max ${formatNumber(alert.max_close_ema200_diff_pips)} pips`],
    ["Spread", `${formatNumber(alert.spread_pips)} pips`],
    ["通貨強弱", `${displayValue(alert.currency_strength_status)} / ${alert.is_currency_strength_available ? "取得済" : "未取得"}`],
    ["順位差 長中期 / 中短期", `${formatNumber(alert.long_medium_rank_difference, 0)} / ${formatNumber(alert.medium_short_rank_difference, 0)}`],
    ["W1分析方向", detailPayload.w1 ? detailPayload.w1.w1_side : "不明"],
    ["Run", `${run.id} / ${displayValue(run.program_version)}`],
    ["Signal key", alert.market_signal_key],
    ["Snapshot", "アラート記録時点"],
  ].forEach(([label, value]) => decisionGrid.append(detailField(label, value)));
  decisionSection.append(decisionGrid);
  elements.detailContent.append(decisionSection);

  const timeframeSection = createElement("section", "detail-section");
  timeframeSection.append(createElement("h3", "", "時間足別 Elliott スナップショット"));
  const timeframeGrid = createElement("div", "timeframe-grid");
  timeframes.forEach((timeFrame) => timeframeGrid.append(buildTimeFrameCard(timeFrame)));
  timeframeSection.append(timeframeGrid);
  elements.detailContent.append(timeframeSection);

  const pointSection = createElement("section", "detail-section");
  pointSection.append(createElement("h3", "", `最新Waveポイント（${points.length}件）`));
  pointSection.append(renderPointTable(points));
  elements.detailContent.append(pointSection);

  if (alert.alert_text) {
    const rawSection = createElement("section", "detail-section");
    const details = createElement("details");
    details.append(createElement("summary", "", "アラート本文を表示"));
    const pre = createElement("pre", "detail-field", alert.alert_text);
    details.append(pre);
    rawSection.append(details);
    elements.detailContent.append(rawSection);
  }
}


async function openDetail(alertId, focusedElement) {
  const detailRequestSerial = ++state.detailRequestSerial;
  state.lastFocused = focusedElement;
  elements.detailDrawer.classList.add("open");
  elements.detailDrawer.inert = false;
  elements.detailDrawer.setAttribute("aria-hidden", "false");
  elements.drawerBackdrop.hidden = false;
  document.body.classList.add("drawer-open");
  elements.detailTitle.textContent = "アラート詳細";
  elements.detailContent.replaceChildren(createElement("p", "loading-message", "詳細を読み込んでいます…"));
  elements.closeDrawer.focus();
  try {
    const [detail, timeframes, points] = await Promise.all([
      fetchJson(`/api/alerts/${alertId}`),
      fetchJson(`/api/alerts/${alertId}/timeframes`),
      fetchJson(`/api/alerts/${alertId}/points`),
    ]);
    if (detailRequestSerial !== state.detailRequestSerial) return;
    renderDetail(detail, timeframes, points);
  } catch (error) {
    if (detailRequestSerial !== state.detailRequestSerial) return;
    elements.detailContent.replaceChildren(createElement("p", "loading-message", "詳細の読み込みに失敗しました。"));
    showToast(error.message);
  }
}


function closeDetail() {
  state.detailRequestSerial += 1;
  elements.detailDrawer.classList.remove("open");
  elements.detailDrawer.inert = true;
  elements.detailDrawer.setAttribute("aria-hidden", "true");
  elements.drawerBackdrop.hidden = true;
  document.body.classList.remove("drawer-open");
  if (state.lastFocused) {
    state.lastFocused.focus();
  }
}


function attachEvents() {
  elements.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    state.page = 1;
    refreshResults();
  });
  elements.resetButton.addEventListener("click", () => {
    elements.filterForm.reset();
    const latestWithAlerts = state.runs.find((run) => Number(run.alert_count) > 0);
    if (latestWithAlerts) elements.runId.value = String(latestWithAlerts.id);
    elements.pageSize.value = "50";
    state.page = 1;
    state.sort = "jst_time";
    state.order = "desc";
    refreshResults();
  });
  elements.exportButton.addEventListener("click", () => {
    const query = buildQuery({ includePaging: false, includeSorting: true });
    window.location.href = `/api/export.csv?${query}`;
  });
  elements.previousPage.addEventListener("click", () => {
    if (state.page > 1) {
      state.page -= 1;
      refreshResults();
    }
  });
  elements.nextPage.addEventListener("click", () => {
    if (state.page < state.pageCount) {
      state.page += 1;
      refreshResults();
    }
  });
  document.querySelectorAll(".sort-button").forEach((button) => {
    button.addEventListener("click", () => {
      const nextSort = button.dataset.sort;
      if (state.sort === nextSort) {
        state.order = state.order === "desc" ? "asc" : "desc";
      } else {
        state.sort = nextSort;
        state.order = "desc";
      }
      state.page = 1;
      refreshResults();
    });
  });
  elements.closeDrawer.addEventListener("click", closeDetail);
  elements.drawerBackdrop.addEventListener("click", closeDetail);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && elements.detailDrawer.classList.contains("open")) {
      closeDetail();
      return;
    }
    if (event.key === "Tab" && elements.detailDrawer.classList.contains("open")) {
      const focusable = [
        ...elements.detailDrawer.querySelectorAll(
          "button, summary, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])",
        ),
      ].filter((element) => !element.disabled && !element.hidden);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  });
}


async function initialize() {
  attachEvents();
  try {
    const [health, runs, options] = await Promise.all([
      fetchJson("/api/health"),
      fetchJson("/api/runs"),
      fetchJson("/api/options"),
    ]);
    populateRuns(runs);
    setSelectOptions(elements.symbol, options.symbols || []);
    setSelectOptions(elements.rank, options.ranks || []);
    restoreFiltersFromUrl();
    elements.connectionStatus.classList.add("ready");
    elements.connectionStatus.querySelector("span:last-child").textContent = `接続済み・${formatInteger(health.alert_count)}件`;
    await refreshResults();
  } catch (error) {
    elements.connectionStatus.classList.add("error");
    elements.connectionStatus.querySelector("span:last-child").textContent = "DB接続エラー";
    elements.resultStatus.textContent = "起動できませんでした";
    showToast(error.message);
  }
}


initialize();
