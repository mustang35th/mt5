//+------------------------------------------------------------------+
//|                                             ZigZagElliotList.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "ZigZagElliotListHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotListController.mqh>

/** 描画専用インジケーターの非表示バッファ。 */
double gHiddenBuffer[];

/** 複数通貨Elliott一覧コントローラー。 */
ZigZagElliotListController *gZigZagElliotListController = NULL;

/**
 * インジケーターを初期化する。
 *
 * @return 初期化結果
 */
int OnInit() {
    if (!SetIndexBuffer(0, gHiddenBuffer, INDICATOR_DATA)) {
        return INIT_FAILED;
    }

    MarketContext context(_Symbol, _Period);
    gZigZagElliotListController = new ZigZagElliotListController();

    if (gZigZagElliotListController == NULL) {
        return INIT_FAILED;
    }

    int initializeResult =
        gZigZagElliotListController.initialize(context);

    if (initializeResult != INIT_SUCCEEDED) {
        delete gZigZagElliotListController;
        gZigZagElliotListController = NULL;

        return initializeResult;
    }

    IndicatorSetString(
        INDICATOR_SHORTNAME,
        "ZigZag Elliott List GMO " + context.timeFrameLabel
    );

    return INIT_SUCCEEDED;
}

/**
 * インジケーター終了時に保持リソースを解放する。
 *
 * @param fromReason 終了理由
 */
void OnDeinit(const int fromReason) {
    if (gZigZagElliotListController != NULL) {
        delete gZigZagElliotListController;
        gZigZagElliotListController = NULL;
    }
}

/**
 * 表示チャートの更新をコントローラーへ通知する。
 *
 * @param fromRatesTotal 全バー数
 * @param fromPrevCalculated 前回計算済みバー数
 * @param fromTime 時刻配列
 * @param fromOpen 始値配列
 * @param fromHigh 高値配列
 * @param fromLow 安値配列
 * @param fromClose 終値配列
 * @param fromTickVolume ティック出来高配列
 * @param fromVolume 出来高配列
 * @param fromSpread スプレッド配列
 * @return 次回計算用の処理済みバー数
 */
int OnCalculate(
    const int fromRatesTotal,
    const int fromPrevCalculated,
    const datetime &fromTime[],
    const double &fromOpen[],
    const double &fromHigh[],
    const double &fromLow[],
    const double &fromClose[],
    const long &fromTickVolume[],
    const long &fromVolume[],
    const int &fromSpread[]
) {
    if (gZigZagElliotListController == NULL) {
        return fromRatesTotal;
    }

    return gZigZagElliotListController.onCalculate(fromRatesTotal);
}

/**
 * 新規バー確認と分析未完了時の再試行をコントローラーへ通知する。
 */
void OnTimer() {
    if (gZigZagElliotListController != NULL) {
        gZigZagElliotListController.onTimer();
    }
}
