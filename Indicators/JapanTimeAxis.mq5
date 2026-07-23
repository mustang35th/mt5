//+------------------------------------------------------------------+
//|                                           JapanTimeAxis.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Indicator\JapanTimeAxisView.mqh>

input string instanceName = "Default";
input int refreshSeconds = 1;

JapanTimeAxisView *gJapanTimeAxisView = NULL;
MarketContext gMarketContext;
datetime gLastBarTime = 0;

/**
 * 日本時間軸インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    if (MQLInfoInteger(MQL_OPTIMIZATION)) {
        Print("JapanTimeAxis does not support optimization");

        return INIT_FAILED;
    }

    string resolvedInstanceName = instanceName;
    StringTrimLeft(resolvedInstanceName);
    StringTrimRight(resolvedInstanceName);

    if (resolvedInstanceName == "" || refreshSeconds < 1) {
        return INIT_PARAMETERS_INCORRECT;
    }

    MarketContext context(_Symbol, (ENUM_TIMEFRAMES)_Period);
    gMarketContext = context;
    // ZigZagElliotの包括削除対象外となる独立した接頭辞を使用する。
    string objectPrefix = "Standalone"
        + Constant::PREFIX_FIXED
        + "JapanTimeAxis_"
        + resolvedInstanceName;
    gJapanTimeAxisView = new JapanTimeAxisView(
        gMarketContext,
        objectPrefix
    );

    if (gJapanTimeAxisView == NULL) {
        return INIT_FAILED;
    }

    IndicatorSetString(
        INDICATOR_SHORTNAME,
        "Japan Time Axis " + resolvedInstanceName
    );
    gJapanTimeAxisView.create();

    if (!EventSetTimer(refreshSeconds)) {
        Print("JapanTimeAxis EventSetTimer failed");
        releaseResources();

        return INIT_FAILED;
    }

    gLastBarTime = iTime(_Symbol, (ENUM_TIMEFRAMES)_Period, 0);

    return INIT_SUCCEEDED;
}

/**
 * タイマーと表示オブジェクトを解放する。
 *
 * @param fromReason 終了理由。
 */
void OnDeinit(const int fromReason) {
    releaseResources();
}

/**
 * 新しい足で日本時間軸を更新する。
 *
 * @return 計算済みバー数。
 */
int OnCalculate(
    const int ratesTotal,
    const int previousCalculated,
    const datetime &time[],
    const double &open[],
    const double &high[],
    const double &low[],
    const double &close[],
    const long &tickVolume[],
    const long &volume[],
    const int &spread[]
) {
    if (ratesTotal <= 0 || gJapanTimeAxisView == NULL) {
        return 0;
    }

    ArraySetAsSeries(time, true);
    datetime currentBarTime = time[0];

    if (currentBarTime != gLastBarTime) {
        gLastBarTime = currentBarTime;
        gJapanTimeAxisView.updateTimeAxis();
        gJapanTimeAxisView.updateRemainingTime();
    }

    return ratesTotal;
}

/**
 * 現在足の残り時間を定期更新する。
 */
void OnTimer() {
    if (gJapanTimeAxisView == NULL) {
        return;
    }

    gJapanTimeAxisView.updateRemainingTime();
}

/**
 * チャート変更時に日本時間軸を再配置する。
 *
 * @param fromEventId イベントID。
 * @param fromLongParameter long型イベント値。
 * @param fromDoubleParameter double型イベント値。
 * @param fromStringParameter string型イベント値。
 */
void OnChartEvent(
    const int fromEventId,
    const long &fromLongParameter,
    const double &fromDoubleParameter,
    const string &fromStringParameter
) {
    if (fromEventId != CHARTEVENT_CHART_CHANGE
            || gJapanTimeAxisView == NULL) {
        return;
    }

    gJapanTimeAxisView.updateTimeAxis();
    gJapanTimeAxisView.updateRemainingTime();
}

/**
 * タイマーと日本時間表示を解放する。
 */
void releaseResources() {
    EventKillTimer();

    if (gJapanTimeAxisView != NULL) {
        gJapanTimeAxisView.destroy();
        delete gJapanTimeAxisView;
        gJapanTimeAxisView = NULL;
    }

    gLastBarTime = 0;
}
