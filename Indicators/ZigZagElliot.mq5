//+------------------------------------------------------------------+
//|                                                 ZigZagElliot.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.24"
#property indicator_chart_window

#property indicator_buffers 7
#property indicator_plots   7

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotController.mqh>

/** Mail内容を検証用ファイルへ出力する場合true。 */
input bool mailValidationFileEnabled = false;

/** MTF_3in3アラート検証CSVを出力する場合true。 */
input bool mtf3In3AlertCsvEnabled = true;

/** MTF_3in3アラートをデータベースへ保存する場合true。 */
input bool mtf3In3AlertDatabaseEnabled = true;

/** MTF_3in3アラートデータベースファイル名。 */
input string mtf3In3AlertDatabaseFileName =
    "mstng-zigzag-elliot-alert.sqlite";

/** MTF_3in3アラートデータベースで共通フォルダを使用する場合true。 */
input bool mtf3In3AlertDatabaseUseCommonFolder = true;

/** H1表示波ごとのエントリー回数制限を使用する場合true。 */
input bool h1DisplayWaveEntryLimitEnabled = false;

/** H1エントリーで使用するW1確認モード。 */
input H1W1ConfirmationMode h1W1ConfirmationMode =
    H1_W1_CONFIRMATION_OBSERVE_ONLY;

/** 通貨強弱を利用する場合true。 */
input bool currencyStrengthEnabled = true;

/** 通貨強弱をエントリー条件として使用する場合true。 */
input bool currencyStrengthEntryFilterEnabled = false;

/** 通貨強弱順位パネルを表示する場合true。 */
input bool currencyStrengthRankVisible = true;

/** 通貨強弱順位パネルの右端からの距離。 */
input int currencyStrengthRankPanelXDistance = 48;

/** 通貨強弱情報の再取得間隔秒。 */
input int currencyStrengthRefreshSeconds = 15;

/** 通貨強弱DB参照プロファイル。 */
input CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile =
    CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;

/** 通貨強弱の投票ウェイト方式。 */
input CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode =
    CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

/** 通貨強弱DBファイル名。 */
input string currencyStrengthDatabaseFileName =
    "mstng-currency-strength.sqlite";

/** 通貨強弱DBを年単位で分割する場合true。 */
input bool currencyStrengthDatabaseSplitByYear = true;

/** 通貨強弱DBで共通フォルダを使用する場合true。 */
input bool currencyStrengthDatabaseUseCommonFolder = true;

/**
 * H1新規足のElliott観測情報をデータベースへ保存する場合true。
 * 全通貨専用コレクターとの同時利用は不可。
 */
input bool h1ElliotObservationDatabaseEnabled = false;

#property indicator_type1   DRAW_LINE
#property indicator_type2   DRAW_LINE
#property indicator_type3   DRAW_LINE
#property indicator_type4   DRAW_LINE
#property indicator_type5   DRAW_LINE
#property indicator_type6   DRAW_LINE
#property indicator_type7   DRAW_LINE

/** ZigZagElliot全体制御。 */
ZigZagElliotController *gController = NULL;

/**
 * インジケータを初期化する。
 *
 * @return 初期化結果
 */
int OnInit() {
    ZigZagElliotConfig config;
    config.mailValidationFileEnabled = mailValidationFileEnabled;
    config.mtf3In3AlertCsvEnabled = mtf3In3AlertCsvEnabled;
    config.mtf3In3AlertDatabaseEnabled = mtf3In3AlertDatabaseEnabled;
    config.mtf3In3AlertDatabaseFileName = mtf3In3AlertDatabaseFileName;
    config.mtf3In3AlertDatabaseUseCommonFolder =
        mtf3In3AlertDatabaseUseCommonFolder;
    config.h1DisplayWaveEntryLimitEnabled =
        h1DisplayWaveEntryLimitEnabled;
    config.h1W1ConfirmationMode = h1W1ConfirmationMode;
    config.currencyStrengthEnabled = currencyStrengthEnabled;
    config.currencyStrengthEntryFilterEnabled =
        currencyStrengthEntryFilterEnabled;
    config.currencyStrengthRankVisible = currencyStrengthRankVisible;
    config.currencyStrengthRankPanelXDistance =
        currencyStrengthRankPanelXDistance;
    config.currencyStrengthRefreshSeconds =
        currencyStrengthRefreshSeconds;
    config.currencyStrengthDatabaseProfile =
        currencyStrengthDatabaseProfile;
    config.currencyStrengthVoteWeightMode =
        currencyStrengthVoteWeightMode;
    config.currencyStrengthDatabaseFileName =
        currencyStrengthDatabaseFileName;
    config.currencyStrengthDatabaseSplitByYear =
        currencyStrengthDatabaseSplitByYear;
    config.currencyStrengthDatabaseUseCommonFolder =
        currencyStrengthDatabaseUseCommonFolder;
    config.h1ElliotObservationDatabaseEnabled =
        h1ElliotObservationDatabaseEnabled;

    MarketContext marketContext(_Symbol, _Period);
    gController = new ZigZagElliotController();

    if (gController == NULL) {
        return INIT_FAILED;
    }

    int initializeResult = gController.initialize(
        marketContext,
        config
    );

    if (initializeResult != INIT_SUCCEEDED) {
        delete gController;
        gController = NULL;
    }

    return initializeResult;
}

/**
 * インジケータ終了時の解放処理を行う。
 *
 * @param reason 終了理由
 */
void OnDeinit(const int reason) {
    if (gController != NULL) {
        delete gController;
        gController = NULL;
    }
}

/**
 * チャートイベントを処理する。
 *
 * @param id イベントID
 * @param lparam long型イベント値
 * @param dparam double型イベント値
 * @param sparam string型イベント値
 */
void OnChartEvent(
    const int id,
    const long &lparam,
    const double &dparam,
    const string &sparam
) {
    if (gController != NULL) {
        gController.onChartEvent(id, sparam);
    }
}

/**
 * ティック更新時の描画処理を行う。
 *
 * @param rates_total 全バー数
 * @param prev_calculated 前回計算済みバー数
 * @param time 時刻配列
 * @param open 始値配列
 * @param high 高値配列
 * @param low 安値配列
 * @param close 終値配列
 * @param tick_volume ティック出来高配列
 * @param volume 出来高配列
 * @param spread スプレッド配列
 * @return 次回計算用の処理済みバー数
 */
int OnCalculate(
    const int32_t rates_total,
    const int32_t prev_calculated,
    const datetime &time[],
    const double &open[],
    const double &high[],
    const double &low[],
    const double &close[],
    const long &tick_volume[],
    const long &volume[],
    const int32_t &spread[]
) {
    if (gController == NULL) {
        return rates_total;
    }

    return gController.onCalculate(rates_total);
}

/**
 * タイマー更新時の描画および解析処理を行う。
 */
void OnTimer() {
    if (gController != NULL) {
        gController.onTimer();
    }
}
