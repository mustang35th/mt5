//+------------------------------------------------------------------+
//|                                 ZigZagElliotH1ObservationAll.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.03"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "H1ObservationAllHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Draw\DrawH1ElliotObservationAllStatus.mqh>
#include <Mstng\Indicator\ZigZagElliot\H1ElliotObservationAllController.mqh>

/** 観測データベースファイル名。 */
input string observationDatabaseFileName =
    "mstng-zigzag-elliot-alert.sqlite";

/** 観測データベースで共通フォルダを使用する場合true。 */
input bool observationDatabaseUseCommonFolder = true;

/** 28通貨のH1境界を確認する間隔秒。 */
input int observationTimerSeconds = 2;

/** DB接続または保存失敗後の再試行間隔秒。 */
input int observationDatabaseRetrySeconds = 15;

/** TESTERで観測保存を開始するサーバー時刻。0の場合は従来どおり。 */
input datetime observationTesterSaveStartTime = 0;

/** 保存待ちSnapshot FIFOの最大件数。 */
input int observationQueueCapacity = 672;

/** 実行状態パネルを表示する場合true。 */
input bool statusPanelVisible = true;

/** 実行状態パネルへ28通貨の詳細を表示する場合true。 */
input bool statusPanelDetailVisible = true;

/** 実行状態パネルの配置基準角。 */
input ENUM_BASE_CORNER statusPanelCorner = CORNER_LEFT_UPPER;

/** 実行状態パネルのX方向距離。 */
input int statusPanelXDistance = 12;

/** 実行状態パネルのY方向距離。 */
input int statusPanelYDistance = 12;

/** 描画専用インジケーターの非表示バッファ。 */
double gHiddenBuffer[];

/** 全28通貨H1観測コントローラー。 */
H1ElliotObservationAllController *gObservationController = NULL;

/** 全28通貨H1観測の実行状態パネル。 */
DrawH1ElliotObservationAllStatus *gObservationStatusView = NULL;

/** 状態パネル描画エラーを出力済みの場合true。 */
bool gStatusDrawErrorLogged = false;

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
            && PeriodSeconds(_Period) > PeriodSeconds(PERIOD_H1)) {
        return INIT_PARAMETERS_INCORRECT;
    }

    gObservationController = new H1ElliotObservationAllController();

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
        statusPanelDetailVisible
    );

    if (gObservationStatusView == NULL) {
        delete gObservationController;
        gObservationController = NULL;

        return INIT_FAILED;
    }

    gObservationStatusView.setVisible(statusPanelVisible);
    updateStatusPanel();
    IndicatorSetString(
        INDICATOR_SHORTNAME,
        "ZigZag Elliott H1 Observation ALL"
    );

    return INIT_SUCCEEDED;
}

/**
 * インジケーター終了時に表示と収集リソースを解放する。
 *
 * @param fromReason 終了理由
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
 * TESTERの価格更新をコントローラーへ通知する。
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
    if (gObservationController == NULL) {
        return fromRatesTotal;
    }

    int calculated = gObservationController.onCalculate(fromRatesTotal);

    if ((bool)MQLInfoInteger(MQL_TESTER)) {
        updateStatusPanel();
    }

    return calculated;
}

/**
 * H1境界確認と保存処理をコントローラーへ通知する。
 */
void OnTimer() {
    if (gObservationController == NULL) {
        return;
    }

    gObservationController.onTimer();
    updateStatusPanel();
}

/**
 * コントローラーの最新状態を固定パネルへ反映する。
 */
void updateStatusPanel() {
    if (gObservationController == NULL
            || gObservationStatusView == NULL) {
        return;
    }

    H1ElliotObservationAllStatus *status =
        gObservationController.getStatus();

    if (status == NULL || gObservationStatusView.draw(status)) {
        return;
    }

    if (!gStatusDrawErrorLogged) {
        Print("[ERROR] H1 Observation All status panel draw failed.");
        gStatusDrawErrorLogged = true;
    }
}
