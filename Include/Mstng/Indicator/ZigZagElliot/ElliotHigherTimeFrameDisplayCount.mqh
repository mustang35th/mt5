//+------------------------------------------------------------------+
//|                  ElliotHigherTimeFrameDisplayCount.mqh          |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_HIGHER_TF_DISPLAY_COUNT_MQH
#define MSTNG_ELLIOT_HIGHER_TF_DISPLAY_COUNT_MQH

/**
 * チャートへ波動ラベルを表示する上位時間足数。
 */
enum ElliotHigherTimeFrameDisplayCount {
    /** 上位2時間足まで表示する。 */
    ELLIOT_HIGHER_TIME_FRAME_DISPLAY_TWO = 2, // 上位2足まで

    /** 上位3時間足まで表示する。 */
    ELLIOT_HIGHER_TIME_FRAME_DISPLAY_THREE = 3 // 上位3足まで
};

/**
 * 上位時間足表示数が有効範囲か判定する。
 *
 * @param fromCount 判定対象の表示数。
 * @return 有効な場合true。
 */
bool isElliotHigherTimeFrameDisplayCountValid(
    const ElliotHigherTimeFrameDisplayCount fromCount
) {
    return fromCount == ELLIOT_HIGHER_TIME_FRAME_DISPLAY_TWO
        || fromCount == ELLIOT_HIGHER_TIME_FRAME_DISPLAY_THREE;
}

#endif // MSTNG_ELLIOT_HIGHER_TF_DISPLAY_COUNT_MQH
