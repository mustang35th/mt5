//+------------------------------------------------------------------+
//|                                                 MstngH1EaAll.mq5 |
//|                                            Copyright 2026, Mstng |
//+------------------------------------------------------------------+
/**
 * Package: Experts
 * File: MstngH1EaAll.mq5
 *
 * M5観測と同じ28通貨をH1で管理するEAの準備用入口。
 * 第2段階では通貨登録と履歴準備だけを行い、発注・SL管理・DB保存は行わない。
 */
#property copyright "Copyright 2026, Mstng"
#property version "1.00"
#property strict
#property description "28通貨H1の履歴準備専用 / 発注・SL管理・DB保存は未接続"

#include <MstngH1Ea\H1EaMultiSymbolController.mqh>

/** 固定28通貨の全体管理。 */
H1EaMultiSymbolController *controller = NULL;

/**
 * 全通貨を登録し、親のTimerを開始する。起動中に取引を開始しない。
 */
int OnInit() {
    if (controller != NULL) {
        return INIT_FAILED;
    }
    controller = new H1EaMultiSymbolController();
    if (controller == NULL) {
        return INIT_FAILED;
    }
    if (!controller.initialize() || !controller.startTimer()) {
        controller.shutdown(REASON_INITFAILED);
        delete controller;
        controller = NULL;
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

/**
 * Timerと全通貨の分析リソースを解放する。
 */
void OnDeinit(const int fromReason) {
    if (controller != NULL) {
        controller.shutdown(fromReason);
        delete controller;
        controller = NULL;
    }
}

/**
 * 通貨を1つずつ巡回する。チャート通貨のTick到着には依存しない。
 */
void OnTimer() {
    if (controller != NULL) {
        controller.onTimer();
    }
}
