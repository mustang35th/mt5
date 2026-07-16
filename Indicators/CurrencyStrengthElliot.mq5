//+------------------------------------------------------------------+
//|                                    CurrencyStrengthElliot.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "CurrencyStrengthHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthList.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>

input int refreshSeconds = 60;
input int panelXDistance = 12;
input int panelYDistance = 12;

double gHiddenBuffer[];

Logger gLogger;
DrawCurrencyStrengthList *gDrawCurrencyStrengthList;
OscillatorHandleManager *gOscillatorHandleManager;
CurrencyStrengthCalculator *gCurrencyStrengthCalculator;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果。
 */
int OnInit() {
    if (MQLInfoInteger(MQL_TESTER)) {
        Print("CurrencyStrengthElliot does not support Strategy Tester");

        return INIT_FAILED;
    }

    if (refreshSeconds < 1) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (!SetIndexBuffer(0, gHiddenBuffer, INDICATOR_DATA)) {
        return INIT_FAILED;
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "Elliot Currency Strength");

    MarketContext context(_Symbol, PERIOD_M15);
    gLogger.setLevel(LOG_INFO);
    gLogger.setMarketContext(context);

    gDrawCurrencyStrengthList = new DrawCurrencyStrengthList(
        0,
        panelXDistance,
        panelYDistance
    );
    gOscillatorHandleManager = new OscillatorHandleManager(PERIOD_M15);
    gCurrencyStrengthCalculator = new CurrencyStrengthCalculator();

    if (gDrawCurrencyStrengthList == NULL
            || gOscillatorHandleManager == NULL
            || gCurrencyStrengthCalculator == NULL) {
        releaseResources();

        return INIT_FAILED;
    }

    if (!EventSetTimer(refreshSeconds)) {
        gLogger.error(__FUNCTION__, "EventSetTimer failed");
        releaseResources();

        return INIT_FAILED;
    }

    execute();

    return INIT_SUCCEEDED;
}

/**
 * タイマーと保持リソースを解放する。
 *
 * @param reason 終了理由。
 */
void OnDeinit(const int reason) {
    EventKillTimer();
    releaseResources();
}

/**
 * タイマーごとに通貨強弱を更新する。
 */
void OnTimer() {
    execute();
}

/**
 * オブジェクト描画専用のため計算本数だけを返す。
 *
 * @return 計算済み本数。
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
    return ratesTotal;
}

/**
 * 全28通貨ペアを集計してランキングを更新する。
 */
void execute() {
    if (gCurrencyStrengthCalculator == NULL
            || gOscillatorHandleManager == NULL
            || gDrawCurrencyStrengthList == NULL) {
        return;
    }

    if (!gCurrencyStrengthCalculator.calculate(gOscillatorHandleManager)) {
        gLogger.error(__FUNCTION__, "currency strength calculation failed");

        return;
    }

    if (!gDrawCurrencyStrengthList.draw(gCurrencyStrengthCalculator)) {
        gLogger.error(__FUNCTION__, "currency strength draw failed");
    }
}

/**
 * 保持している描画、集計およびハンドル管理クラスを解放する。
 */
void releaseResources() {
    if (gDrawCurrencyStrengthList != NULL) {
        gDrawCurrencyStrengthList.clear();
        delete gDrawCurrencyStrengthList;
        gDrawCurrencyStrengthList = NULL;
    }

    if (gCurrencyStrengthCalculator != NULL) {
        delete gCurrencyStrengthCalculator;
        gCurrencyStrengthCalculator = NULL;
    }

    if (gOscillatorHandleManager != NULL) {
        delete gOscillatorHandleManager;
        gOscillatorHandleManager = NULL;
    }
}
