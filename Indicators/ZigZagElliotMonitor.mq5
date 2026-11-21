//+------------------------------------------------------------------+
//|                                          ZigZagElliotMonitor.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// 複数通貨ペアのM1エントリーを監視し、自動表示がONなら成立したペアのチャートを開く。
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.20"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_type1 DRAW_NONE
#property indicator_label1 "MonitorHidden"

#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorController.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTarget.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\Util.mqh>

input group "01. 通貨ペア・M1監視"
input(name="起動時の監視対象") ENUM_ZIGZAG_MONITOR_TARGET monitorTargetMode = ZIGZAG_MONITOR_TARGET_GMO;
input(name="監視を開始") bool monitoringEnabled = true;
input(name="成立時にチャートを自動表示") bool autoOpenEnabled = true;
input(name="チャート表示の最大枚数（手動・自動）") int maxOpenCharts = 18;
input(name="新規チャートのテンプレート（空欄=適用なし）")
string chartTemplateName = "\\Profiles\\Templates\\ZigZagElliot-4.tpl";
input(name="自動表示時にチャートを前面へ") bool bringToFront = true;
input(name="一覧の文字サイズ") int monitorFontSize = 10;

input group "02. 通貨強弱DB"
input(name="参照元（LIVE/TESTER）")
CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
input(name="投票方式") CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
input(name="DBファイル名") string currencyStrengthDatabaseFileName = "mstng-currency-strength.sqlite";
input(name="年別DBを使用") bool currencyStrengthDatabaseSplitByYear = true;
input(name="Commonフォルダを使用") bool currencyStrengthDatabaseUseCommonFolder = true;

/** 非表示バッファ。 */
double monitorHiddenBuffer[];

/** 監視処理の所有先。 */
ZigZagElliotMonitorController *monitorController = NULL;

/**
 * 通常チャートで選択した通貨ペアのM1監視を初期化する。
 */
int OnInit() {
    Logger logger(LOG_INFO);
    if (Util::isStrategyTester()) {
        logger.error(__FUNCTION__, "ZigZagElliotMonitor is available on normal charts only.");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!ZigZagElliotMonitorTarget::isValid(monitorTargetMode)
            || maxOpenCharts < 1 || maxOpenCharts > 28 || monitorFontSize < 8 || monitorFontSize > 16
            || currencyStrengthDatabaseFileName == "") {
        logger.error(__FUNCTION__, "Invalid monitor display or database settings.");

        return INIT_PARAMETERS_INCORRECT;
    }

    if (!SetIndexBuffer(0, monitorHiddenBuffer, INDICATOR_DATA)) {
        return INIT_FAILED;
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "ZigZagElliotMonitor");
    ZigZagElliotMonitorConfig config;
    config.targetMode = monitorTargetMode;
    config.monitoringEnabled = monitoringEnabled;
    config.autoOpenEnabled = autoOpenEnabled;
    config.maxOpenCharts = maxOpenCharts;
    config.templateName = chartTemplateName;
    config.bringToFront = bringToFront;
    config.fontSize = monitorFontSize;
    config.entryConfig.currencyStrengthDatabaseProfile = currencyStrengthDatabaseProfile;
    config.entryConfig.currencyStrengthVoteWeightMode = currencyStrengthVoteWeightMode;
    config.entryConfig.currencyStrengthDatabaseFileName = currencyStrengthDatabaseFileName;
    config.entryConfig.currencyStrengthDatabaseSplitByYear = currencyStrengthDatabaseSplitByYear;
    config.entryConfig.currencyStrengthDatabaseUseCommonFolder = currencyStrengthDatabaseUseCommonFolder;
    monitorController = new ZigZagElliotMonitorController();
    if (monitorController == NULL || !monitorController.initialize(ChartID(), config)) {
        if (monitorController != NULL) {
            delete monitorController;
            monitorController = NULL;
        }

        return INIT_FAILED;
    }

    if (!EventSetTimer(1)) {
        delete monitorController;
        monitorController = NULL;

        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

/**
 * タイマーで1通貨ずつ確認する。チャートのティック頻度には依存しない。
 */
void OnTimer() {
    if (monitorController != NULL) {
        monitorController.processNext();
    }
}

/**
 * コンボボックス・ボタン操作とチャート変更を担当クラスへ渡す。
 */
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if (monitorController != NULL) {
        monitorController.handleChartEvent(id, sparam, lparam, dparam);
    }
}

/**
 * 描画バッファは使用せず、分析の多重起動を避けてタイマーに集約する。
 */
int OnCalculate(const int ratesTotal, const int prevCalculated, const datetime &time[],
        const double &open[], const double &high[], const double &low[], const double &close[],
        const long &tickVolume[], const long &volume[], const int &spread[]) {
    return ratesTotal;
}

/**
 * タイマーと監視資源を解放する。開いた確認用チャートは残す。
 */
void OnDeinit(const int reason) {
    EventKillTimer();
    if (monitorController != NULL) {
        delete monitorController;
        monitorController = NULL;
        ChartRedraw(ChartID());
    }
}
