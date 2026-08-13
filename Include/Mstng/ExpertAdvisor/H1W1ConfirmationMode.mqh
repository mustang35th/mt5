//+------------------------------------------------------------------+
//|                                         H1W1ConfirmationMode.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_MODE_MQH
#define MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_MODE_MQH

/**
 * H1エントリーで使用するW1確認モード。
 */
enum H1W1ConfirmationMode {
    /** W1確認を行わない。 */
    H1_W1_CONFIRMATION_OFF = 0,

    /** 診断値だけを記録し、エントリーを制限しない。 */
    H1_W1_CONFIRMATION_OBSERVE_ONLY = 1,

    /** W1方向またはW1 EMA200方向の一致を要求する。 */
    H1_W1_CONFIRMATION_DIRECTION_OR_EMA200 = 2,

    /** W1方向およびW1 EMA200方向の一致を要求する。 */
    H1_W1_CONFIRMATION_DIRECTION_AND_EMA200 = 3
};

/**
 * H1 W1確認モードを文字列へ変換する。
 *
 * @param fromMode 変換対象モード。
 * @return 永続化および表示に使用するモード文字列。
 */
string getH1W1ConfirmationModeText(
    const H1W1ConfirmationMode fromMode
) {
    if (fromMode == H1_W1_CONFIRMATION_OFF) {
        return "OFF";
    }

    if (fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY) {
        return "OBSERVE_ONLY";
    }

    if (fromMode == H1_W1_CONFIRMATION_DIRECTION_OR_EMA200) {
        return "DIRECTION_OR_EMA200";
    }

    if (fromMode == H1_W1_CONFIRMATION_DIRECTION_AND_EMA200) {
        return "DIRECTION_AND_EMA200";
    }

    return "INVALID";
}

/**
 * H1 W1確認モードが有効範囲か判定する。
 *
 * @param fromMode 判定対象モード。
 * @return 有効な場合true。
 */
bool isH1W1ConfirmationModeValid(
    const H1W1ConfirmationMode fromMode
) {
    return fromMode == H1_W1_CONFIRMATION_OFF
        || fromMode == H1_W1_CONFIRMATION_OBSERVE_ONLY
        || fromMode == H1_W1_CONFIRMATION_DIRECTION_OR_EMA200
        || fromMode == H1_W1_CONFIRMATION_DIRECTION_AND_EMA200;
}

#endif // MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_MODE_MQH
