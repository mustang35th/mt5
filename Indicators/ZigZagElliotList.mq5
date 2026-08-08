//+------------------------------------------------------------------+
//|                                             ZigZagElliotList.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.14"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "ZigZagElliotListHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotListSortType.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotListController.mqh>

/**
 * ZigZag Elliott一覧の基準時間足モード。
 */
enum ZigZagElliotListMode {
    ZIGZAG_ELLIOT_LIST_MODE_CHART = 0, // CHART
    ZIGZAG_ELLIOT_LIST_MODE_D1 = 1     // D1 / ALIGN W1 / D1 SORT
};

/** CHARTモードの並び替え基準。D1モードではD1専用ソートを使用する。 */
input ElliotListSortType sortType = ELLIOT_LIST_SORT_M15_ELLIOT_EMA;

/** 一覧の基準時間足モード。 */
input ZigZagElliotListMode listMode = ZIGZAG_ELLIOT_LIST_MODE_CHART;

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

    if ((bool)MQLInfoInteger(MQL_TESTER)
            && listMode == ZIGZAG_ELLIOT_LIST_MODE_D1
            && PeriodSeconds(_Period) > PeriodSeconds(PERIOD_D1)) {
        return INIT_PARAMETERS_INCORRECT;
    }

    ENUM_TIMEFRAMES listTimeFrame = _Period;
    ENUM_TIMEFRAMES alignmentStartTimeFrame = PERIOD_D1;
    ElliotListSortType effectiveSortType = sortType;
    bool testerHistoryWarmUpEnabled = false;

    if (listMode == ZIGZAG_ELLIOT_LIST_MODE_D1) {
        listTimeFrame = PERIOD_D1;
        alignmentStartTimeFrame = PERIOD_W1;
        effectiveSortType = ELLIOT_LIST_SORT_D1_ELLIOT_EMA;
        testerHistoryWarmUpEnabled = true;
    }

    MarketContext context(_Symbol, listTimeFrame);
    gZigZagElliotListController = new ZigZagElliotListController();

    if (gZigZagElliotListController == NULL) {
        return INIT_FAILED;
    }

    int initializeResult = gZigZagElliotListController.initialize(
        context,
        effectiveSortType,
        alignmentStartTimeFrame,
        testerHistoryWarmUpEnabled
    );

    if (initializeResult != INIT_SUCCEEDED) {
        delete gZigZagElliotListController;
        gZigZagElliotListController = NULL;

        return initializeResult;
    }

    string shortName = "ZigZag Elliott List ALL " + context.timeFrameLabel;

    if (listMode == ZIGZAG_ELLIOT_LIST_MODE_D1) {
        shortName += " ALIGN W1";
    }

    IndicatorSetString(INDICATOR_SHORTNAME, shortName);

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
