#property copyright "Copyright 2026, Mstng"
#property version "1.02"
#property strict
#property description "H1専用MTF_3in3 / 必須ZigZag SL / H1 ZigZagトレイル / SQLite"

#include <MstngH1Ea\H1EaController.mqh>

input group "取引設定"
input double InpLotSize = 0.01; // 固定ロット
input double InpMaxInitialStopLossPips = 100.0; // 最大初期SL幅(pips)・0=未設定で起動不可

input group "テスター設定"
input datetime InpTesterTradeStartTime = D'2026.01.01 00:00'; // 売買開始日時(サーバー時刻)・0=制限なし・LIVEでは無効

/** H1専用の制御本体。 */
H1EaController *controller = NULL;

/**
 * 設定と復元だけを行い、初回Entryはイベントへ委ねる。
 */
int OnInit() {
    if (controller != NULL) {
        return INIT_FAILED;
    }
    controller = new H1EaController();
    if (controller == NULL) {
        return INIT_FAILED;
    }
    if (!controller.initialize(_Symbol, InpLotSize, InpMaxInitialStopLossPips,
            InpTesterTradeStartTime)) {
        controller.shutdown(REASON_INITFAILED);
        delete controller;
        controller = NULL;
        return INIT_FAILED;
    }
    if (!controller.startTimer()) {
        controller.shutdown(REASON_INITFAILED);
        delete controller;
        controller = NULL;
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

/**
 * 保護SLをbrokerに残し、EAのリソースだけを解放する。
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
 * Tick起点の保護とTester Entryを処理する。
 */
void OnTick() {
    if (controller != NULL) {
        controller.onTick();
    }
}

/**
 * Lease更新とLIVE Entry周期を処理する。
 */
void OnTimer() {
    if (controller != NULL) {
        controller.onTimer();
    }
}

/**
 * brokerの約定・注文・SL通知を正本として取り込む。
 */
void OnTradeTransaction(const MqlTradeTransaction &fromTransaction,
        const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
    if (controller != NULL) {
        controller.onTradeTransaction(fromTransaction, fromRequest, fromResult);
    }
}
