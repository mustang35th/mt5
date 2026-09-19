//+------------------------------------------------------------------+
//|                                     ZigZagElliotAlertHistory.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryController.mqh>

input group "01. Alert DB"

/** 読み取り対象のAlert DB。 */
input(name="Alert DBファイル名") string alertDatabaseFileName = "mstng-zigzag-elliot-alert.sqlite";
/** CommonフォルダのDBを利用する場合true。 */
input(name="Commonフォルダを使用") bool alertDatabaseUseCommonFolder = true;

input group "02. アラート選択"

/** 0は条件に一致する最新Run一つを選ぶ。 */
input(name="Run ID（0=条件に一致する最新Run）") long alertRunId = 0;
/** 開始日。時刻部分は使用しない。 */
input(name="表示開始日（サーバー日付、0=制限なし）") datetime alertStartDate = 0;
/** 終了日。当日を含み、時刻部分は使用しない。 */
input(name="表示終了日（当日を含む、0=制限なし）") datetime alertEndDate = 0;
/** ENTRY成立だけを表示する場合true。 */
input(name="ENTRY成立のみ表示") bool alertEntryOnly = false;

input group "03. チャート表示"

/** 現在足に加えて表示する上位足数。 */
input(name="波動ラベルの上位足数") ZigZagElliotAlertHistoryHigherCount alertHigherCount = ALERT_HISTORY_HIGHER_THREE;
/** 判定時価格・SL候補・FE価格線の表示。 */
input(name="判定時価格・SL候補・FEを表示") bool alertShowPrices = true;
/** 各時間足の保存情報表の表示。 */
input(name="時間足の情報表を表示") bool alertShowTable = true;

/** 履歴表示の制御。 */
ZigZagElliotAlertHistoryController *gHistoryController = NULL;

/**
 * 履歴表示専用インジケーターを初期化する。
 */
int OnInit() {
    ZigZagElliotAlertHistoryConfig config;
    config.databaseFileName = alertDatabaseFileName;
    config.useCommonFolder = alertDatabaseUseCommonFolder;
    config.runId = alertRunId;
    config.startDate = alertStartDate;
    config.endDate = alertEndDate;
    config.entryOnly = alertEntryOnly;
    config.higherCount = (int)alertHigherCount;
    config.showPrices = alertShowPrices;
    config.showTable = alertShowTable;
    gHistoryController = new ZigZagElliotAlertHistoryController();
    if (gHistoryController == NULL) {
        return INIT_FAILED;
    }
    int result = gHistoryController.initialize(config);
    if (result != INIT_SUCCEEDED) {
        delete gHistoryController;
        gHistoryController = NULL;
    }
    return result;
}

/**
 * 自分が作成した表示とDB接続を解放する。
 */
void OnDeinit(const int fromReason) {
    if (gHistoryController != NULL) {
        delete gHistoryController;
        gHistoryController = NULL;
    }
}

/**
 * 価格系列の更新では保存済み分析を変更しない。
 */
int OnCalculate(const int ratesTotal, const int previousCalculated,
        const datetime &time[], const double &open[], const double &high[],
        const double &low[], const double &close[], const long &tickVolume[],
        const long &volume[], const int &spread[]) {
    return ratesTotal;
}

/**
 * 非同期履歴取得とチャート再配置を処理する。
 */
void OnTimer() {
    if (gHistoryController != NULL) {
        gHistoryController.onTimer();
    }
}

/**
 * 履歴選択と表示切り替えの操作を転送する。
 */
void OnChartEvent(const int fromId, const long &fromLongParameter,
        const double &fromDoubleParameter, const string &fromStringParameter) {
    if (gHistoryController != NULL) {
        gHistoryController.onChartEvent(fromId, fromStringParameter);
    }
}
