//+------------------------------------------------------------------+
//|                                 ZigZagElliotM5ObservationAll.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.02"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "M5ObservationAllHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Draw\DrawH1ElliotObservationAllStatus.mqh>
#include <Mstng\Indicator\ZigZagElliot\M5ElliotObservationAllController.mqh>

input group "01 保存先（M5専用DB）"
/** 観測データベースファイル名。H1・AlertのDBは指定しない。 */
input string observationDatabaseFileName = "mstng-zigzag-elliot-m5-observation.sqlite";
/** 共通フォルダーへ保存する場合true。 */
input bool observationDatabaseUseCommonFolder = true;

input group "02 収集・再試行"
/** LIVEで28通貨のM5境界を確認する間隔秒。 */
input int observationTimerSeconds = 2;
/** DB接続または保存失敗後の再試行間隔秒。 */
input int observationDatabaseRetrySeconds = 15;
/** 保存待ちSnapshot数。672件は28通貨で約2時間分。 */
input int observationQueueCapacity = 672;

input group "03 TESTER"
/** 保存開始サーバー時刻。0は各通貨の初回成功から。JSTではない。 */
input datetime observationTesterSaveStartTime = 0;

input group "04 状態表示"
/** 実行状態パネルを表示する場合true。 */
input bool statusPanelVisible = true;
/** 28通貨の状態・直近取得品質を表示する場合true。 */
input bool statusPanelDetailVisible = true;
/** パネル配置基準角。 */
input ENUM_BASE_CORNER statusPanelCorner = CORNER_LEFT_UPPER;
/** パネルX方向距離。 */
input int statusPanelXDistance = 12;
/** パネルY方向距離。 */
input int statusPanelYDistance = 12;

/** 非表示バッファ。 */
double gHiddenBuffer[];
/** 全28通貨M5観測コントローラー。 */
M5ElliotObservationAllController *gObservationController = NULL;
/** H1と共通の状態パネル。M5では品質表示を有効にする。 */
DrawH1ElliotObservationAllStatus *gObservationStatusView = NULL;
/** 状態表示失敗を出力済みの場合true。 */
bool gStatusDrawErrorLogged = false;

/**
 * インジケーターを初期化する。売買・アラート送信は行わない。
 *
 * @return 初期化結果。
 */
int OnInit() {
    if (MQLInfoInteger(MQL_OPTIMIZATION)
            || (MQLInfoInteger(MQL_TESTER)
                && PeriodSeconds(_Period) > PeriodSeconds(PERIOD_M5))) {
        Print("[ERROR] M5 Observation All requires tester M5 or lower; optimization is unsupported.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (!SetIndexBuffer(0, gHiddenBuffer, INDICATOR_DATA)) {
        return INIT_FAILED;
    }

    gObservationController = new M5ElliotObservationAllController();
    if (gObservationController == NULL) {
        return INIT_FAILED;
    }

    int initializeResult = gObservationController.initialize(
        observationDatabaseFileName,
        observationDatabaseUseCommonFolder,
        observationTimerSeconds,
        observationDatabaseRetrySeconds,
        observationTesterSaveStartTime,
        observationQueueCapacity
    );
    if (initializeResult != INIT_SUCCEEDED) {
        Print("[ERROR] M5 Observation All initialization failed. ",
            gObservationController.getStatus().message);
        delete gObservationController;
        gObservationController = NULL;
        return initializeResult;
    }

    gObservationStatusView = new DrawH1ElliotObservationAllStatus(
        ChartID(),
        StringFormat("%I64d", ChartID()),
        statusPanelCorner,
        statusPanelXDistance,
        statusPanelYDistance,
        statusPanelDetailVisible,
        true
    );
    if (gObservationStatusView == NULL) {
        delete gObservationController;
        gObservationController = NULL;
        return INIT_FAILED;
    }

    gObservationStatusView.setVisible(statusPanelVisible);
    updateStatusPanel();
    IndicatorSetString(INDICATOR_SHORTNAME, "ZigZag Elliott M5 Observation ALL");
    return INIT_SUCCEEDED;
}

/**
 * 表示と収集リソースを解放する。
 *
 * @param fromReason 終了理由。
 */
void OnDeinit(const int fromReason) {
    if (gObservationStatusView != NULL) {
        delete gObservationStatusView;
        gObservationStatusView = NULL;
    }
    if (gObservationController != NULL) {
        delete gObservationController;
        gObservationController = NULL;
    }
}

/**
 * TESTERの価格更新を収集処理へ通知する。LIVEはタイマーで処理する。
 *
 * @param fromRatesTotal 全バー数。
 * @param fromPrevCalculated 前回計算済みバー数。
 * @param fromTime 時刻配列。
 * @param fromOpen 始値配列。
 * @param fromHigh 高値配列。
 * @param fromLow 安値配列。
 * @param fromClose 終値配列。
 * @param fromTickVolume ティック出来高配列。
 * @param fromVolume 出来高配列。
 * @param fromSpread スプレッド配列。
 * @return 次回計算用バー数。
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
    if (gObservationController == NULL) {
        return fromRatesTotal;
    }
    int calculated = gObservationController.onCalculate(fromRatesTotal);
    if (MQLInfoInteger(MQL_TESTER)) {
        updateStatusPanel();
    }
    return calculated;
}

/**
 * LIVEのM5境界確認・解析・保存を実行する。
 */
void OnTimer() {
    if (gObservationController == NULL) {
        return;
    }
    gObservationController.onTimer();
    updateStatusPanel();
}

/**
 * 収集状態と直近取得品質を状態パネルへ反映する。
 */
void updateStatusPanel() {
    if (gObservationController == NULL || gObservationStatusView == NULL) {
        return;
    }
    H1ElliotObservationAllStatus *status = gObservationController.getStatus();
    if (status == NULL || gObservationStatusView.draw(status)) {
        return;
    }
    if (!gStatusDrawErrorLogged) {
        Print("[ERROR] M5 Observation All status panel draw failed.");
        gStatusDrawErrorLogged = true;
    }
}
