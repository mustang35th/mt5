//+------------------------------------------------------------------+
//|                           CurrencyStrengthRankDeltaHistory.mq5   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.05"
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_plots   5
#property indicator_minimum -7.0
#property indicator_maximum 7.0
#property indicator_level1  0.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1
#property indicator_label1  "Rank Gap Boundary"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Zero Boundary"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Rank Gap"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  clrAqua, clrHotPink, clrGray
#property indicator_width3  2
#property indicator_label4  "Base Rank"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Quote Rank"
#property indicator_type5   DRAW_NONE

#include <Mstng\Draw\ChartRedrawRequest.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankDeltaPanel.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankGapFill.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDeltaEvaluator.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDeltaHistoryProvider.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 各足の順位差を表示する集計期間。
 */
enum CurrencyStrengthRankDeltaPeriod {
    CURRENCY_STRENGTH_RANK_DELTA_LONG_MEDIUM = 0, // 長中期
    CURRENCY_STRENGTH_RANK_DELTA_MEDIUM_SHORT = 1 // 中短期
};

input group "01. 履歴表示・更新"

/** 表示する順位差の集計期間。 */
input(name="表示する順位") CurrencyStrengthRankDeltaPeriod rankPeriod =
    CURRENCY_STRENGTH_RANK_DELTA_LONG_MEDIUM;

/** サーバーM5時刻からさかのぼる表示日数。 */
input(name="履歴の表示日数（1～366日）") int historyDays = 30;

/** サブ画面の高さ。0はMT5側のサイズを使用する。 */
input(name="サブ画面の高さ（px・0＝指定なし）") int subPanelHeight = 140;

input group "02. データ参照"

/** 同じM5時刻のLIVEを優先し、ない時刻をTESTERで補完する。 */
input(name="参照する履歴") CurrencyStrengthRankDatabaseProfile databaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;

/** 保存側と合わせるスコアの計算方式。 */
input(name="参照するスコアの計算方式") CurrencyStrengthVoteWeightMode voteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

input group "03. DB参照先"

/** 年別分割時は年なしのDBファイル名。 */
input(name="DBファイル名（年なし）") string databaseFileName = "mstng-currency-strength.sqlite";

/** 年別の履歴DBを使用する。 */
input(name="年別DBファイルを参照") bool databaseSplitByYear = true;

/** MT5共通フォルダ内のDBを使用する。テスターでは必須。 */
input(name="MT5共通フォルダから読み込む") bool databaseUseCommonFolder = true;

/** v1.03互換の順位差側境界。Canvas描画からは参照しない。 */
double gGapFillBuffer[];

/** v1.03互換のゼロ側境界。Canvas描画からは参照しない。 */
double gZeroFillBuffer[];

/** 各足の符号付き順位差。0も有効値。 */
double gGapBuffer[];

/** 順位差の正負・ゼロに対応する折れ線の色番号。 */
double gGapColorBuffer[];

/** 同じ足の基軸通貨順位。Data Windowへ表示する。 */
double gBaseRankBuffer[];

/** 同じ足の決済通貨順位。Data Windowへ表示する。 */
double gQuoteRankBuffer[];

/** 順位差と同じインデックスのチャート足時刻。Canvas座標変換に使う。 */
double gBarTimeBuffer[];

/** v1.03の境界バッファ値を維持するための微小オフセット。 */
const double fillZeroOffset = 0.00000001;

/** DB履歴の取得と保持を担当する。 */
CurrencyStrengthRankDeltaHistoryProvider *gProvider = NULL;

/** 右上の状態表示と再読込ボタン。 */
DrawCurrencyStrengthRankDeltaPanel *gPanel = NULL;

/** 表示中の区間だけを前足比で塗り分ける。 */
DrawCurrencyStrengthRankGapFill *gFill = NULL;

/** イベント内の再描画要求をまとめる。 */
ChartRedrawRequest gRedrawRequest;

/** 取得失敗等を記録するロガー。 */
Logger gLogger;

/** 実行時のテスター判定。 */
bool gIsTester = false;

/** 通貨ペアの基軸通貨。 */
string gBaseCurrency = "";

/** 通貨ペアの決済通貨。 */
string gQuoteCurrency = "";

/** 直近のDB取得を試みたM5時刻。失敗時も再試行間隔を守る。 */
datetime gLastQueryTarget = 0;

/** 直近の取得開始時点の経過ミリ秒。 */
ulong gLastQueryTicks = 0;

/** 前回表示した最古のM5時刻。 */
datetime gLastDisplayStart = 0;

/** 最後に計算したチャートの最新足時刻。 */
datetime gLastBarTime = 0;

/** 最後に計算したバッファ件数。 */
int gLastRatesTotal = 0;

/** 再読込後に全バッファの再反映が必要な場合true。 */
bool gForceRebuild = false;

/** パネルの反映・再試行が必要な場合true。 */
bool gPanelDirty = true;

/** 順位差または表示範囲の変更を塗りへ反映する必要がある場合true。 */
bool gFillDirty = true;

/** 再試行用に保持するパネル見出し。 */
string gPanelTitle = "";

/** 再試行用に保持する順位差と前足比の文字列。 */
string gPanelValue = "順位データ待ち";

/** 再試行用に保持する取得元と基準時刻。 */
string gPanelSource = "未取得";

/** 再試行用に保持する同じ足の順位情報と説明。 */
string gPanelTooltip = "";

/** 再試行用に保持する順位差の文字色。 */
color gPanelValueColor = clrSilver;

/** 手動再読込でのチャート足取得失敗を説明する。 */
string gReloadMessage = "";

/** 通常チャートの同一M5枠を再確認する間隔。 */
const ulong refreshMilliseconds = 60000;

/**
 * 新規インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    gIsTester = Util::isStrategyTester();
    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("CurrencyStrengthRankDeltaHistory does not support optimization");

        return INIT_FAILED;
    }

    if (historyDays < 1 || historyDays > 366 || subPanelHeight < 0
            || databaseFileName == ""
            || (rankPeriod != CURRENCY_STRENGTH_RANK_DELTA_LONG_MEDIUM
                && rankPeriod != CURRENCY_STRENGTH_RANK_DELTA_MEDIUM_SHORT)
            || (int)databaseProfile < 0 || (int)databaseProfile > 3
            || !CurrencyStrengthCalculationProfile::isVoteWeightModeValid(voteWeightMode)
            || (gIsTester && !databaseUseCommonFolder)) {
        return INIT_PARAMETERS_INCORRECT;
    }

    gLogger.setLevel(LOG_INFO);
    gBaseCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    gQuoteCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    if (gBaseCurrency == "" || gQuoteCurrency == "" || gBaseCurrency == gQuoteCurrency) {
        gLogger.error(__FUNCTION__, "symbol currency resolution failed");

        return INIT_FAILED;
    }

    if (!initializeBuffers()) {
        return INIT_FAILED;
    }

    string periodText = "長中期";
    if (rankPeriod == CURRENCY_STRENGTH_RANK_DELTA_MEDIUM_SHORT) {
        periodText = "中短期";
    }

    gPanelTitle = periodText + " / "
        + CurrencyStrengthCalculationProfile::getVoteWeightModeText(voteWeightMode)
        + "｜順位差";
    IndicatorSetString(INDICATOR_SHORTNAME,
        "Rank Gap " + gBaseCurrency + "/" + gQuoteCurrency + " " + gPanelTitle);
    IndicatorSetInteger(INDICATOR_DIGITS, 0);
    if (subPanelHeight > 0 && !IndicatorSetInteger(INDICATOR_HEIGHT, subPanelHeight)) {
        return INIT_FAILED;
    }

    gProvider = new CurrencyStrengthRankDeltaHistoryProvider(
        databaseFileName, databaseSplitByYear, databaseUseCommonFolder,
        databaseProfile, voteWeightMode, gIsTester, gBaseCurrency, gQuoteCurrency);
    string objectSuffix = StringFormat("%d_%I64u", (int)rankPeriod, GetMicrosecondCount());
    gPanel = new DrawCurrencyStrengthRankDeltaPanel(ChartID(), objectSuffix, GetPointer(gRedrawRequest));
    gFill = new DrawCurrencyStrengthRankGapFill(ChartID(), objectSuffix, GetPointer(gRedrawRequest));
    if (gProvider == NULL || gPanel == NULL || gFill == NULL) {
        return INIT_FAILED;
    }

    if (!gIsTester && !EventSetTimer(10)) {
        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

/**
 * このインスタンスが所有する表示とDB参照を終了する。
 */
void OnDeinit(const int fromReason) {
    EventKillTimer();
    if (gFill != NULL) {
        delete gFill;
        gFill = NULL;
    }

    if (gPanel != NULL) {
        delete gPanel;
        gPanel = NULL;
    }

    if (gProvider != NULL) {
        delete gProvider;
        gProvider = NULL;
    }

    gRedrawRequest.flush(ChartID());
}

/**
 * 時刻列と保存済みM5履歴から、必要な範囲だけ表示を更新する。
 */
int OnCalculate(
    const int ratesTotal, const int previousCalculated, const datetime &time[],
    const double &open[], const double &high[], const double &low[], const double &close[],
    const long &tickVolume[], const long &volume[], const int &spread[]
) {
    if (ratesTotal <= 0 || gProvider == NULL) {
        return 0;
    }

    ArraySetAsSeries(time, true);
    datetime targetTime = getTargetTime(time[0]);
    datetime displayStart = getDisplayStart(targetTime);
    bool changed = false;
    datetime changedStart = targetTime;
    bool refreshed = false;
    if (gLastQueryTarget != targetTime
            || (!gIsTester && GetTickCount64() - gLastQueryTicks >= refreshMilliseconds)) {
        refreshHistory(targetTime, displayStart, false, changedStart, changed);
        refreshed = true;
    }

    bool fullRefresh = previousCalculated <= 0 || previousCalculated > ratesTotal
        || gLastDisplayStart <= 0 || displayStart < gLastDisplayStart
        || time[0] < gLastBarTime || gForceRebuild
        || (time[0] == gLastBarTime && ratesTotal != gLastRatesTotal);
    bool chartChanged = time[0] != gLastBarTime || ratesTotal != previousCalculated;
    if (fullRefresh || changed || chartChanged || displayStart != gLastDisplayStart) {
        updateBuffers(ratesTotal, previousCalculated, time, displayStart, targetTime,
            fullRefresh, changed, changedStart);
        gLastDisplayStart = displayStart;
        gLastBarTime = time[0];
        gLastRatesTotal = ratesTotal;
        gForceRebuild = false;
        updatePanelText(targetTime);
        gRedrawRequest.request();
    } else if (refreshed) {
        updatePanelText(targetTime);
    }

    drawFill();
    drawPanel();
    gRedrawRequest.flush(ChartID());

    return ratesTotal;
}

/**
 * データ取得を増やさず、表示オブジェクトの欠損と生成失敗を再確認する。
 */
void OnTimer() {
    gPanelDirty = true;
    drawFill(true);
    drawPanel();
    gRedrawRequest.flush(ChartID());
}

/**
 * 自分の再読込ボタンとサブウィンドウ構成変更を処理する。
 */
void OnChartEvent(const int fromEventId, const long &fromLongValue,
    const double &fromDoubleValue, const string &fromStringValue) {
    if (fromEventId == CHARTEVENT_OBJECT_CLICK && gPanel != NULL
            && gPanel.handleReloadClick(fromStringValue)) {
        reloadHistory();
    } else if (fromEventId != CHARTEVENT_CHART_CHANGE) {
        return;
    }

    gPanelDirty = true;
    drawFill(true);
    drawPanel();
    gRedrawRequest.flush(ChartID());
}

/**
 * 公開済みのバッファ番号を維持し、折れ線とCanvas用の足時刻を登録する。
 */
bool initializeBuffers() {
    // 保存済みの描画設定がある場合も、順位差と両通貨順位の対応を維持する。
    if (!PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_COLOR_LINE)
            || !PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE)
            || !PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2)
            || !PlotIndexSetInteger(2, PLOT_COLOR_INDEXES, 3)
            || !PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, clrAqua)
            || !PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, clrHotPink)
            || !PlotIndexSetInteger(2, PLOT_LINE_COLOR, 2, clrGray)
            || !IndicatorSetDouble(INDICATOR_MINIMUM, -7.0)
            || !IndicatorSetDouble(INDICATOR_MAXIMUM, 7.0)
            || !IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT)
            || !IndicatorSetInteger(INDICATOR_LEVELWIDTH, 0, 1)) {
        return false;
    }

    if (!SetIndexBuffer(0, gGapFillBuffer, INDICATOR_DATA)
            || !SetIndexBuffer(1, gZeroFillBuffer, INDICATOR_DATA)
            || !SetIndexBuffer(2, gGapBuffer, INDICATOR_DATA)
            || !SetIndexBuffer(3, gGapColorBuffer, INDICATOR_COLOR_INDEX)
            || !SetIndexBuffer(4, gBaseRankBuffer, INDICATOR_DATA)
            || !SetIndexBuffer(5, gQuoteRankBuffer, INDICATOR_DATA)
            || !SetIndexBuffer(6, gBarTimeBuffer, INDICATOR_CALCULATIONS)) {
        return false;
    }

    ArraySetAsSeries(gGapFillBuffer, true);
    ArraySetAsSeries(gZeroFillBuffer, true);
    ArraySetAsSeries(gGapBuffer, true);
    ArraySetAsSeries(gGapColorBuffer, true);
    ArraySetAsSeries(gBaseRankBuffer, true);
    ArraySetAsSeries(gQuoteRankBuffer, true);
    ArraySetAsSeries(gBarTimeBuffer, true);
    for (int i = 0; i < 5; i++) {
        if (!PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE)) {
            return false;
        }
    }

    if (!PlotIndexSetString(0, PLOT_LABEL, "Rank Gap Boundary")
            || !PlotIndexSetString(1, PLOT_LABEL, "Zero Boundary")
            || !PlotIndexSetString(2, PLOT_LABEL, "Rank Gap")
            || !PlotIndexSetString(3, PLOT_LABEL, gBaseCurrency + " Rank")
            || !PlotIndexSetString(4, PLOT_LABEL, gQuoteCurrency + " Rank")
            || !PlotIndexSetInteger(0, PLOT_SHOW_DATA, false)
            || !PlotIndexSetInteger(1, PLOT_SHOW_DATA, false)
            || !PlotIndexSetInteger(2, PLOT_SHOW_DATA, true)
            || !PlotIndexSetInteger(3, PLOT_SHOW_DATA, true)
            || !PlotIndexSetInteger(4, PLOT_SHOW_DATA, true)) {
        return false;
    }

    return true;
}

/**
 * M5開始時刻へ切り下げる。
 */
datetime floorToM5(const datetime fromTime) {
    if (fromTime <= 0) {
        return 0;
    }

    return (datetime)((long)fromTime - (long)fromTime % 300);
}

/**
 * 未来のDB履歴を使用しないための取得上限を返す。
 */
datetime getTargetTime(const datetime fromFallbackTime) {
    datetime targetTime = TimeCurrent();
    if (targetTime <= 0) {
        targetTime = fromFallbackTime;
    }

    return floorToM5(targetTime);
}

/**
 * 表示期間の先頭を求める。
 */
datetime getDisplayStart(const datetime fromTargetTime) {
    long startTime = (long)fromTargetTime - (long)historyDays * 86400;
    if (startTime < 300) {
        return 300;
    }

    return (datetime)startTime;
}

/**
 * 再試行間隔を記録し、表示期間内の順位履歴を取得する。
 */
bool refreshHistory(const datetime fromTargetTime, const datetime fromDisplayStart,
    const bool fromForce, datetime &fromChangedStart, bool &fromChanged) {
    gLastQueryTarget = fromTargetTime;
    gLastQueryTicks = GetTickCount64();

    return gProvider.refresh(fromDisplayStart, fromTargetTime, fromForce, fromChangedStart, fromChanged);
}

/**
 * 既存バッファを空値へ初期化し、表示期間だけ計算する。
 * 履歴点が変わった時刻以降と新規足を更新する。
 */
void updateBuffers(const int fromRatesTotal, const int fromPreviousCalculated,
    const datetime &fromTime[], const datetime fromDisplayStart, const datetime fromTargetTime,
    const bool fromFullRefresh, const bool fromChanged, const datetime fromChangedStart) {
    gFillDirty = true;
    if (fromFullRefresh) {
        // 公開済みの境界バッファは欠損0、順位差は欠損EMPTY_VALUEを維持する。
        ArrayInitialize(gGapFillBuffer, 0.0);
        ArrayInitialize(gZeroFillBuffer, 0.0);
        ArrayInitialize(gGapBuffer, EMPTY_VALUE);
        ArrayInitialize(gGapColorBuffer, 0.0);
        ArrayInitialize(gBaseRankBuffer, EMPTY_VALUE);
        ArrayInitialize(gQuoteRankBuffer, EMPTY_VALUE);
        ArrayInitialize(gBarTimeBuffer, 0.0);
    }

    int newCount = MathMax(1, fromRatesTotal - fromPreviousCalculated + 1);
    datetime cachedTime = 0;
    int cachedBufferIndex = -1;
    int currentIndex = -1;
    for (int i = 0; i < fromRatesTotal; i++) {
        datetime barTime = floorToM5(fromTime[i]);
        if (!fromFullRefresh && i >= newCount
                && (!fromChanged || barTime < fromChangedStart)) {
            break;
        }

        if (barTime < fromDisplayStart) {
            if (!fromFullRefresh) {
                for (int j = i; j < MathMin(newCount, fromRatesTotal); j++) {
                    clearBuffer(j);
                }
            }

            break;
        }

        if (cachedBufferIndex >= 0 && cachedTime == barTime) {
            gGapFillBuffer[i] = gGapFillBuffer[cachedBufferIndex];
            gZeroFillBuffer[i] = gZeroFillBuffer[cachedBufferIndex];
            gGapBuffer[i] = gGapBuffer[cachedBufferIndex];
            gGapColorBuffer[i] = gGapColorBuffer[cachedBufferIndex];
            gBaseRankBuffer[i] = gBaseRankBuffer[cachedBufferIndex];
            gQuoteRankBuffer[i] = gQuoteRankBuffer[cachedBufferIndex];
        } else {
            clearBuffer(i);
            int baseRank = 0;
            int quoteRank = 0;
            int gap = 0;
            if (barTime <= fromTargetTime && CurrencyStrengthRankDeltaEvaluator::evaluateGap(
                    gProvider.points, gProvider.startIndex, barTime,
                    rankPeriod == CURRENCY_STRENGTH_RANK_DELTA_LONG_MEDIUM,
                    baseRank, quoteRank, gap, currentIndex)) {
                // v1.03互換の境界値。塗り自体は順位差と足時刻から描画する。
                gGapFillBuffer[i] = gap + fillZeroOffset;
                gZeroFillBuffer[i] = fillZeroOffset;
                gGapBuffer[i] = gap;
                gBaseRankBuffer[i] = baseRank;
                gQuoteRankBuffer[i] = quoteRank;
                if (gap < 0) {
                    gGapColorBuffer[i] = 1;
                } else if (gap == 0) {
                    gGapColorBuffer[i] = 2;
                }
            }

            cachedTime = barTime;
            cachedBufferIndex = i;
        }

        // M1の順位差は再利用するが、前足比は隣接するチャート足で判定する。
        gBarTimeBuffer[i] = (double)fromTime[i];
    }

    if (!fromFullRefresh && fromDisplayStart > gLastDisplayStart) {
        int leftIndex = 0;
        int rightIndex = fromRatesTotal;
        while (leftIndex < rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            if (floorToM5(fromTime[middleIndex]) >= fromDisplayStart) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex;
            }
        }

        for (int i = leftIndex; i < fromRatesTotal; i++) {
            if (floorToM5(fromTime[i]) < gLastDisplayStart) {
                break;
            }

            clearBuffer(i);
        }
    }
}

/**
 * 指定バーを欠損表示へ戻す。
 */
void clearBuffer(const int fromIndex) {
    gGapFillBuffer[fromIndex] = 0.0;
    gZeroFillBuffer[fromIndex] = 0.0;
    gGapBuffer[fromIndex] = EMPTY_VALUE;
    gGapColorBuffer[fromIndex] = 0;
    gBaseRankBuffer[fromIndex] = EMPTY_VALUE;
    gQuoteRankBuffer[fromIndex] = EMPTY_VALUE;
    gBarTimeBuffer[fromIndex] = 0.0;
}

/**
 * 最新のチャート足に描画したM5時刻を基準に、両通貨の順位差と取得元を説明する。
 */
void updatePanelText(const datetime fromTargetTime) {
    gPanelDirty = true;
    datetime sampleTime = floorToM5(gLastBarTime);
    int baseRank = 0;
    int quoteRank = 0;
    int gap = 0;
    int currentIndex = -1;
    bool available = sampleTime >= gLastDisplayStart && sampleTime <= fromTargetTime
        && CurrencyStrengthRankDeltaEvaluator::evaluateGap(gProvider.points, gProvider.startIndex,
            sampleTime, rankPeriod == CURRENCY_STRENGTH_RANK_DELTA_LONG_MEDIUM,
            baseRank, quoteRank, gap, currentIndex);
    gPanelValue = "順位データ不足";
    gPanelValueColor = clrSilver;
    gPanelSource = gProvider.getStatusText();
    gPanelTooltip = "各足の順位差 = 決済通貨順位 - 基軸通貨順位"
        + StringFormat("\n対象通貨：%s/%s / 縦軸：-7～+7", gBaseCurrency, gQuoteCurrency)
        + "\n線：水色＝基軸通貨優位 / ピンク＝決済通貨優位 / 灰色＝同順位"
        + "\n塗り：前足より上昇＝青緑 / 低下＝ピンク / 同じ＝直前の色を維持"
        + "\n方向不明の横ばいは灰色。欠損区間では色の引き継ぎをリセット。"
        + "\n前足比 = 今のチャート足の順位差 - 1本前のチャート足の順位差"
        + "\n前足から今の足までを同じ色で塗る。0をまたいでも増減の色を維持。"
        + "\n比較できない区間は塗らない。欠損箇所では線もつながない。"
        + "\nその足の両通貨順位がそろえば表示。M1は同じM5枠、M15以上は足開始時点。"
        + "\nM1の同じM5枠内は前足比0でも色を維持。両端とも順位差0なら面積なし。"
        + "\n取得状態：" + gProvider.getStatusText();
    if (sampleTime > 0) {
        gPanelTooltip += "\n基準時刻 SRV：" + TimeUtil::formatYyyymmddhhmiss(sampleTime);
    }

    if (available) {
        gPanelValue = StringFormat("順位差 %+d｜前足比 --", gap);
        gPanelTooltip += StringFormat("\n通貨順位：%s %d位 / %s %d位",
            gBaseCurrency, baseRank, gQuoteCurrency, quoteRank);
        if (!gForceRebuild && ArraySize(gGapBuffer) > 1 && gGapBuffer[0] != EMPTY_VALUE
                && gGapBuffer[1] != EMPTY_VALUE && (datetime)gBarTimeBuffer[0] == gLastBarTime
                && gBarTimeBuffer[1] > 0 && gBarTimeBuffer[1] < gBarTimeBuffer[0]) {
            int change = gap - (int)gGapBuffer[1];
            gPanelValue = StringFormat("順位差 %+d｜前足比 %+d", gap, change);
            gPanelTooltip += StringFormat("\n前足の順位差：%+d / 前足比：%+d",
                (int)gGapBuffer[1], change);
            gPanelTooltip += "\n前足の基準時刻 SRV："
                + TimeUtil::formatYyyymmddhhmiss(floorToM5((datetime)gBarTimeBuffer[1]));
        } else {
            gPanelTooltip += "\n前足比：比較データなし（塗りなし）";
        }

        if (gap > 0) {
            gPanelValueColor = clrAqua;
        } else if (gap < 0) {
            gPanelValueColor = clrHotPink;
        }

        string source = gProvider.points[currentIndex].sourceMode;
        gPanelSource = TimeUtil::formatYyyymmddhhmiss(sampleTime) + " SRV｜" + source;
        gPanelTooltip += "\n取得元：" + source;
        if (gProvider.hasError()) {
            gPanelSource = "前回履歴を表示｜" + gProvider.getStatusText();
        }
    } else if (gProvider.hasError()) {
        gPanelValueColor = clrOrange;
    }

    if (gReloadMessage != "") {
        gPanelTooltip += "\n再読込：" + gReloadMessage;
    }
}

/**
 * データ変更時と画面確認時だけ塗りを反映し、失敗時は次回に再試行する。
 */
void drawFill(const bool fromCheckViewport = false) {
    if (gFill == NULL || (!gFillDirty && !fromCheckViewport)) {
        return;
    }

    gFillDirty = !gFill.draw(ChartWindowFind(), gGapBuffer, gBarTimeBuffer, gFillDirty);
}

/**
 * 内容変更時と定期確認時だけパネルを反映し、失敗時は次回に再試行する。
 */
void drawPanel() {
    if (!gPanelDirty || gPanel == NULL) {
        return;
    }

    gPanelDirty = !gPanel.draw(ChartWindowFind(), gPanelTitle, gPanelValue, gPanelValueColor,
        gPanelSource, gPanelTooltip, !gIsTester);
}

/**
 * 明示操作でDBを開き直し、表示期間を再取得する。
 * チャート足が変わった場合は次のOnCalculateで再反映する。
 */
void reloadHistory() {
    if (gIsTester || gProvider == NULL || gLastBarTime <= 0) {
        return;
    }

    datetime targetTime = getTargetTime(gLastBarTime);
    datetime displayStart = getDisplayStart(targetTime);
    datetime changedStart = displayStart;
    bool changed = false;
    gProvider.reopenDatabase();
    if (!refreshHistory(targetTime, displayStart, true, changedStart, changed)) {
        gReloadMessage = "取得失敗。前回表示を保持";
        updatePanelText(targetTime);

        return;
    }

    gForceRebuild = true;
    datetime barTimes[];
    ArraySetAsSeries(barTimes, true);
    int barCount = ArraySize(gGapBuffer);
    int boundary = iBarShift(_Symbol, _Period, displayStart, false);
    int copyCount = barCount;
    if (boundary >= 0) {
        copyCount = MathMin(barCount, boundary + 1);
    }

    if (copyCount <= 0 || CopyTime(_Symbol, _Period, 0, copyCount, barTimes) != copyCount
            || barTimes[0] != gLastBarTime || barCount != gLastRatesTotal) {
        gReloadMessage = "取得済み。チャート足の更新後に再表示";
        updatePanelText(targetTime);

        return;
    }

    updateBuffers(copyCount, 0, barTimes, displayStart, targetTime, true, true, displayStart);
    gLastDisplayStart = displayStart;
    gForceRebuild = false;
    gReloadMessage = "成功";
    updatePanelText(targetTime);
    gRedrawRequest.request();
}
