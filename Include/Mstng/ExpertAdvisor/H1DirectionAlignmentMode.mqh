//+------------------------------------------------------------------+
//|                                     H1DirectionAlignmentMode.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_MODE_MQH
#define MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_MODE_MQH

/**
 * H1エントリーで使用するElliott売買方向一致モード。
 */
enum H1DirectionAlignmentMode {
    /** 現行どおりD1、H4およびH1の方向一致を使用する。 */
    H1_DIRECTION_ALIGNMENT_D1_TO_H1 = 0,

    /** MN1からH1までの方向一致を記録し、エントリーは制限しない。 */
    H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE = 1,

    /** MN1からH1までの方向一致をエントリー条件にする。 */
    H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED = 2,

    /** W1からH1の一致と、MN1またはW1 EMA200の一致を要求する。 */
    H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED = 3
};

/**
 * H1方向一致モードを文字列へ変換する。
 *
 * @param fromMode 変換対象モード。
 * @return 永続化および表示に使用するモード文字列。
 */
string getH1DirectionAlignmentModeText(
    const H1DirectionAlignmentMode fromMode
) {
    if (fromMode == H1_DIRECTION_ALIGNMENT_D1_TO_H1) {
        return "D1_TO_H1";
    }

    if (fromMode == H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE) {
        return "MN1_TO_H1_OBSERVE";
    }

    if (fromMode == H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED) {
        return "MN1_TO_H1_REQUIRED";
    }

    if (fromMode
            == H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED) {
        return "W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED";
    }

    return "INVALID";
}

/**
 * H1方向一致モードが有効範囲か判定する。
 *
 * @param fromMode 判定対象モード。
 * @return 有効な場合true。
 */
bool isH1DirectionAlignmentModeValid(
    const H1DirectionAlignmentMode fromMode
) {
    return fromMode == H1_DIRECTION_ALIGNMENT_D1_TO_H1
        || fromMode == H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE
        || fromMode == H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED
        || fromMode
            == H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED;
}

#endif // MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_MODE_MQH
