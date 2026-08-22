//+------------------------------------------------------------------+
//|                                     H1Ema200ConfirmationMode.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_MODE_MQH
#define MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_MODE_MQH

/**
 * H1エントリーで使用するEMA200確認モード。
 */
enum H1Ema200ConfirmationMode {
    /** H1 EMA200方向だけを要求する。 */
    H1_EMA200_CONFIRMATION_H1_ONLY = 0,

    /** H1とH4のEMA200方向一致を要求する。 */
    H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED = 1
};

/**
 * H1 EMA200確認モードを文字列へ変換する。
 *
 * @param fromMode 変換対象モード。
 * @return 設定記録に使用するモード文字列。
 */
string getH1Ema200ConfirmationModeText(
    const H1Ema200ConfirmationMode fromMode
) {
    if (fromMode == H1_EMA200_CONFIRMATION_H1_ONLY) {
        return "H1_ONLY";
    }

    if (fromMode == H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED) {
        return "H1_AND_H4_REQUIRED";
    }

    return "INVALID";
}

/**
 * H1 EMA200確認モードが有効範囲か判定する。
 *
 * @param fromMode 判定対象モード。
 * @return 有効な場合true。
 */
bool isH1Ema200ConfirmationModeValid(
    const H1Ema200ConfirmationMode fromMode
) {
    return fromMode == H1_EMA200_CONFIRMATION_H1_ONLY
        || fromMode == H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED;
}

#endif // MSTNG_EXPERT_ADVISOR_H1_EMA200_CONFIRMATION_MODE_MQH
