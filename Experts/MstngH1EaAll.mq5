//+------------------------------------------------------------------+
//|                                                 MstngH1EaAll.mq5 |
//|                                            Copyright 2026, Mstng |
//+------------------------------------------------------------------+
/**
 * Package: Experts
 * File: MstngH1EaAll.mq5
 *
 * M5観測と同じ28通貨をH1で管理するEAの入口。
 * 第7段階では28通貨の状態パネルと、分析実時間・全通貨保護巡回間隔の計測を提供する。
 */
#property copyright "Copyright 2026, Mstng"
#property version "1.05"
#property strict
#property description "28通貨H1の新規Entry・ポジション・SL管理"

#include <MstngH1Ea\H1EaMultiSymbolController.mqh>
#include <MstngH1Ea\Presentation\H1EaStatusPanel.mqh>

input group "共通設定（28通貨のH1エントリー・保護管理）"
input double InpLotSize = 0.01; // 固定ロット
input double InpMaxInitialStopLossPips = 100.0; // 最大初期SL幅(pips)・正の値必須

input group "テスター設定"
input datetime InpTesterTradeStartTime = D'2026.01.01 00:00'; // 売買開始日時(サーバー時刻)・0=制限なし・LIVEでは無効

input group "表示設定"
input bool InpShowStatusPanel = true; // 28通貨の状態パネルを表示

/** 読取専用の状態パネル。 */
H1EaStatusPanel statusPanel;

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
    statusPanel.initialize(ChartID(), InpShowStatusPanel);
    updateStatusPanel();
    return INIT_SUCCEEDED;
}

/**
 * Timerと全通貨の分析リソースを解放する。
 */
void OnDeinit(const int fromReason) {
    statusPanel.clear();
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
        updateStatusPanel();
    }
}

/**
 * 設置チャート通貨の保護をTickで補助する。
 */
void OnTick() {
    if (controller != NULL) {
        controller.onTick();
        updateStatusPanel();
    }
}

/**
 * 対象通貨へ通知を振り分け、重い照合は後続イベントへ委ねる。
 */
void OnTradeTransaction(const MqlTradeTransaction &fromTransaction,
        const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
    if (controller != NULL) {
        controller.onTradeTransaction(fromTransaction, fromRequest, fromResult);
    }
}

/**
 * 状態コピーを表示へ渡す。判定・保護完了後だけ呼び、非表示時の集計を省略する。
 */
void updateStatusPanel() {
    if (controller == NULL || !statusPanel.isRefreshDue()) {
        return;
    }
    H1EaMonitorState state;
    controller.getMonitorState(state);
    statusPanel.draw(state);
}

/**
 * サイズ変更と状態一覧のページ切り替えを描画クラスへ渡す。
 */
void OnChartEvent(const int fromId, const long &fromLongParam, const double &fromDoubleParam,
        const string &fromStringParam) {
    statusPanel.onChartEvent(fromId, fromStringParam);
    updateStatusPanel();
}
