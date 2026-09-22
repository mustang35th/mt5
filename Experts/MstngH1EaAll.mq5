//+------------------------------------------------------------------+
//|                                                 MstngH1EaAll.mq5 |
//|                                            Copyright 2026, Mstng |
//+------------------------------------------------------------------+
/**
 * Package: Experts
 * File: MstngH1EaAll.mq5
 *
 * M5観測と同じ28通貨をH1で管理するEAの準備用入口。
 * 第3段階では通貨別DB復元・Run/Lease維持と履歴準備を行う。発注・SL管理は未接続。
 */
#property copyright "Copyright 2026, Mstng"
#property version "1.01"
#property strict
#property description "28通貨H1のDB復元・履歴準備 / 発注・SL管理は未接続"

#include <MstngH1Ea\H1EaMultiSymbolController.mqh>

input group "共通設定（第3段階はDBへの設定記録のみ・売買は未接続）"
input double InpLotSize = 0.01; // 固定ロット
input double InpMaxInitialStopLossPips = 100.0; // 最大初期SL幅(pips)・正の値必須

input group "テスター設定"
input datetime InpTesterTradeStartTime = D'2026.01.01 00:00'; // 売買開始日時(サーバー時刻)・0=制限なし・LIVEでは無効

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
    if (!controller.initialize(InpLotSize, InpMaxInitialStopLossPips, InpTesterTradeStartTime)
            || !controller.startTimer()) {
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
