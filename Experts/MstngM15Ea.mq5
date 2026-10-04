//+------------------------------------------------------------------+
//|                                                   MstngM15Ea.mq5 |
//|                                            Copyright 2026, Mstng |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Mstng"
#property version "1.00"
#property strict
#property description "M15 MTF_3in3 / 確定ZigZag SL / M15トレイル / 専用SQLite"

#include <MstngM15Ea\M15EaController.mqh>

input group "取引設定"
input double InpLotSize = 0.01; // 固定ロット
input double InpMaxInitialStopLossPips = 100.0; // 最大初期SL幅(pips)、正値必須

input group "M15判定設定"
input bool InpDirectionCorrectionEnabled = true; // D1・H4・H1の逆方向1足を補正
input double InpH4MaxFibonacciExpansionPercent = 161.8; // H4 FE上限(%)、0=無効
input double InpH1MaxFibonacciExpansionPercent = 161.8; // H1 FE上限(%)、0=無効

input group "テスター設定"
input datetime InpTesterTradeStartTime = D'2026.01.01 00:00'; // 売買開始日時、0=制限なし、LIVE無効

/** M15単一通貨の制御本体。 */
M15EaController *controller = NULL;

/**
 * 設定・排他・保存状態を準備し、エントリーはイベントへ委ねる。
 */
int OnInit() {
    if (controller != NULL) {
        return INIT_FAILED;
    }
    controller = new M15EaController();
    if (controller == NULL) {
        return INIT_FAILED;
    }
    if (!controller.initialize(_Symbol, InpLotSize, InpMaxInitialStopLossPips,
            InpTesterTradeStartTime, InpDirectionCorrectionEnabled,
            InpH4MaxFibonacciExpansionPercent, InpH1MaxFibonacciExpansionPercent)
            || !controller.startTimer()) {
        controller.shutdown(REASON_INITFAILED);
        delete controller;
        controller = NULL;
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

/**
 * ポジションとbroker SLを残し、EAのリソースを解放する。
 */
void OnDeinit(const int fromReason) {
    EventKillTimer();
    if (controller != NULL) {
        controller.shutdown(fromReason);
        delete controller;
        controller = NULL;
    }
}

/**
 * 保護処理とTesterのエントリーを実行する。
 */
void OnTick() {
    if (controller != NULL) {
        controller.onTick();
    }
}

/**
 * Lease保守とLIVEのエントリーを実行する。
 */
void OnTimer() {
    if (controller != NULL) {
        controller.onTimer();
    }
}

/**
 * broker通知を共通の照合処理へ渡す。
 */
void OnTradeTransaction(const MqlTradeTransaction &fromTransaction,
        const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
    if (controller != NULL) {
        controller.onTradeTransaction(fromTransaction, fromRequest, fromResult);
    }
}
