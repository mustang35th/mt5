//+------------------------------------------------------------------+
//|                                             ZigZagElliotList.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.22"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "ZigZagElliotListHidden"
#property indicator_type1   DRAW_NONE

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotListSortType.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotListController.mqh>

/**
 * ZigZag Elliott一覧の基準時間足モード。
 */
enum ZigZagElliotListMode {
    ZIGZAG_ELLIOT_LIST_MODE_CHART = 0, // CHART
    ZIGZAG_ELLIOT_LIST_MODE_D1 = 1     // D1 / ALIGN SETTING / D1 SORT
};

/** D1モードの上位時間足一致条件。 */
enum ZigZagElliotListD1AlignmentMode {
    ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_ONLY = 0, // W1
    ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_MN1_AND_W1 = 1, // MN1 AND W1
    ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_WITH_MN1_OR_EMA200 = 2 // W1 AND (MN1 OR W1 EMA200)
};

/** H1の上位時間足一致条件。 */
enum ZigZagElliotListH1AlignmentMode {
    ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_D1_TO_H1 = 0, // D1 AND H4 AND H1
    ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_MN1_TO_H1 = 1, // MN1 AND W1 AND D1 AND H4 AND H1
    ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200 = 2 // W1-H1 AND (MN1 OR W1 EMA200)
};

/** CHARTモードの並び替え基準。D1モードではD1専用ソートを使用する。 */
input ElliotListSortType sortType = ELLIOT_LIST_SORT_M15_ELLIOT_EMA;

/** 一覧の基準時間足モード。 */
input ZigZagElliotListMode listMode = ZIGZAG_ELLIOT_LIST_MODE_CHART;

/** D1モードの上位時間足一致条件。CHARTモードでは使用しない。 */
input ZigZagElliotListD1AlignmentMode d1AlignmentMode =
    ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_ONLY;

/** H1の上位時間足一致条件。実効時間足がH1の場合のみ使用する。 */
input ZigZagElliotListH1AlignmentMode h1AlignmentMode =
    ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_D1_TO_H1;

/** 28通貨のMTF_3in3 Alertを共通DB Runへ保存する場合true。 */
input bool mtf3In3AlertDatabaseEnabled = false;

/** 28通貨MTF_3in3 Alertデータベースファイル名。 */
input string mtf3In3AlertDatabaseFileName =
    "mstng-zigzag-elliot-alert.sqlite";

/** 28通貨MTF_3in3 Alert DBで共通フォルダを使用する場合true。 */
input bool mtf3In3AlertDatabaseUseCommonFolder = true;

/** TESTER設定の開始サーバー時刻。Alert有効時は必須。 */
input datetime mtf3In3AlertTesterStartTime = 0;

/** TESTERで28通貨Alert連続評価を開始するサーバー時刻。0はTesterStart。 */
input datetime mtf3In3AlertTesterEvaluationStartTime = 0;

/** TESTERでAlert保存を開始するサーバー時刻。Alert有効時は必須。 */
input datetime mtf3In3AlertTesterSaveStartTime = 0;

/** TESTERで収集を完了させる最後のH1バー開始時刻。 */
input datetime mtf3In3AlertTesterExpectedLastH1BarTime = 0;

/** Alert保存前に連続評価を必須とするH1本数。 */
input int mtf3In3AlertTesterMinimumWarmUpH1Bars = 5000;

/** TESTERモデルを「1 minute OHLC」に設定済みの場合true。 */
input bool mtf3In3AlertTesterOneMinuteOhlcConfirmed = false;

/** Alert判定でH1表示波ごとのエントリー回数制限を使用する場合true。 */
input bool alertH1DisplayWaveEntryLimitEnabled = false;

/** Alert判定で使用するH1 W1確認モード。 */
input H1W1ConfirmationMode alertH1W1ConfirmationMode =
    H1_W1_CONFIRMATION_OBSERVE_ONLY;

/** Alert判定で使用するH1方向一致モード。 */
input H1DirectionAlignmentMode alertH1DirectionAlignmentMode =
    H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED;

/** Alert判定で使用するH1 EMA200確認モード。 */
input H1Ema200ConfirmationMode alertH1Ema200ConfirmationMode =
    H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED;

/** 描画専用インジケーターの非表示バッファ。 */
double gHiddenBuffer[];

/** 複数通貨Elliott一覧コントローラー。 */
ZigZagElliotListController *gZigZagElliotListController = NULL;

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
            && listMode == ZIGZAG_ELLIOT_LIST_MODE_D1
            && PeriodSeconds(_Period) > PeriodSeconds(PERIOD_D1)) {
        return INIT_PARAMETERS_INCORRECT;
    }

    if (listMode == ZIGZAG_ELLIOT_LIST_MODE_D1
            && d1AlignmentMode != ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_ONLY
            && d1AlignmentMode
                != ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_MN1_AND_W1
            && d1AlignmentMode
                != ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_WITH_MN1_OR_EMA200) {
        return INIT_PARAMETERS_INCORRECT;
    }

    ENUM_TIMEFRAMES listTimeFrame = _Period;
    ENUM_TIMEFRAMES alignmentStartTimeFrame = PERIOD_D1;
    ElliotDirectionAlignmentRule alignmentRule =
        ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES;
    ElliotListSortType effectiveSortType = sortType;
    bool testerHistoryWarmUpEnabled = false;
    string alignmentText = "W1";

    if (listMode == ZIGZAG_ELLIOT_LIST_MODE_D1) {
        listTimeFrame = PERIOD_D1;
        alignmentStartTimeFrame = PERIOD_W1;
        effectiveSortType = ELLIOT_LIST_SORT_D1_ELLIOT_EMA;
        testerHistoryWarmUpEnabled = true;

        if (d1AlignmentMode
                == ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_MN1_AND_W1) {
            alignmentStartTimeFrame = PERIOD_MN1;
            alignmentText = "MN1+W1";
        } else if (d1AlignmentMode
                == ZIGZAG_ELLIOT_LIST_D1_ALIGNMENT_W1_WITH_MN1_OR_EMA200) {
            alignmentStartTimeFrame = PERIOD_MN1;
            alignmentRule =
                ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200;
            alignmentText = "W1&(MN1|W1EMA)";
        }
    } else if (listTimeFrame == PERIOD_H1) {
        if (h1AlignmentMode != ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_D1_TO_H1
                && h1AlignmentMode
                    != ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_MN1_TO_H1
                && h1AlignmentMode
                    != ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200) {
            return INIT_PARAMETERS_INCORRECT;
        }

        alignmentText = "D1-H1";

        if (h1AlignmentMode
                == ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_MN1_TO_H1) {
            alignmentStartTimeFrame = PERIOD_MN1;
            alignmentText = "MN1-H1";
        } else if (h1AlignmentMode
                == ZIGZAG_ELLIOT_LIST_H1_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200) {
            alignmentStartTimeFrame = PERIOD_MN1;
            alignmentRule =
                ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200;
            alignmentText = "W1-H1&(MN1|W1EMA)";
        }
    }

    if (mtf3In3AlertDatabaseEnabled
            && listTimeFrame == PERIOD_H1) {
        testerHistoryWarmUpEnabled = true;
    }

    ZigZagElliotConfig alertConfig;
    alertConfig.mailValidationFileEnabled = false;
    alertConfig.mtf3In3AlertCsvEnabled = false;
    alertConfig.mtf3In3AlertDatabaseEnabled =
        mtf3In3AlertDatabaseEnabled;
    alertConfig.mtf3In3AlertDatabaseFileName =
        mtf3In3AlertDatabaseFileName;
    alertConfig.mtf3In3AlertDatabaseUseCommonFolder =
        mtf3In3AlertDatabaseUseCommonFolder;
    alertConfig.h1DisplayWaveEntryLimitEnabled =
        alertH1DisplayWaveEntryLimitEnabled;
    alertConfig.h1W1ConfirmationMode =
        alertH1W1ConfirmationMode;
    alertConfig.h1DirectionAlignmentMode =
        alertH1DirectionAlignmentMode;
    alertConfig.h1Ema200ConfirmationMode =
        alertH1Ema200ConfirmationMode;
    alertConfig.currencyStrengthEnabled = false;
    alertConfig.currencyStrengthEntryFilterEnabled = false;
    alertConfig.currencyStrengthRankVisible = false;

    MarketContext context(_Symbol, listTimeFrame);
    gZigZagElliotListController = new ZigZagElliotListController();

    if (gZigZagElliotListController == NULL) {
        return INIT_FAILED;
    }

    int initializeResult = gZigZagElliotListController.initialize(
        context,
        effectiveSortType,
        alignmentStartTimeFrame,
        testerHistoryWarmUpEnabled,
        alignmentRule,
        alertConfig,
        mtf3In3AlertTesterStartTime,
        mtf3In3AlertTesterEvaluationStartTime,
        mtf3In3AlertTesterSaveStartTime,
        mtf3In3AlertTesterExpectedLastH1BarTime,
        mtf3In3AlertTesterMinimumWarmUpH1Bars,
        mtf3In3AlertTesterOneMinuteOhlcConfirmed
    );

    if (initializeResult != INIT_SUCCEEDED) {
        delete gZigZagElliotListController;
        gZigZagElliotListController = NULL;

        return initializeResult;
    }

    string shortName = "ZigZag Elliott List ALL " + context.timeFrameLabel;

    if (listMode == ZIGZAG_ELLIOT_LIST_MODE_D1
            || listTimeFrame == PERIOD_H1) {
        shortName += " ALIGN " + alignmentText;
    }

    IndicatorSetString(INDICATOR_SHORTNAME, shortName);

    return INIT_SUCCEEDED;
}

/**
 * インジケーター終了時に保持リソースを解放する。
 *
 * @param fromReason 終了理由
 */
void OnDeinit(const int fromReason) {
    if (gZigZagElliotListController != NULL) {
        delete gZigZagElliotListController;
        gZigZagElliotListController = NULL;
    }
}

/**
 * 表示チャートの更新をコントローラーへ通知する。
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
    if (gZigZagElliotListController == NULL) {
        return fromRatesTotal;
    }

    return gZigZagElliotListController.onCalculate(fromRatesTotal);
}

/**
 * 新規バー確認と分析未完了時の再試行をコントローラーへ通知する。
 */
void OnTimer() {
    if (gZigZagElliotListController != NULL) {
        gZigZagElliotListController.onTimer();
    }
}
