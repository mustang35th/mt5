//+------------------------------------------------------------------+
//|                                     H1PositionManagementMode.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Config
 * File: H1PositionManagementMode.mqh
 */

#ifndef MSTNGEA_CONFIG_H1POSITIONMANAGEMENTMODE_MQH
#define MSTNGEA_CONFIG_H1POSITIONMANAGEMENTMODE_MQH

/**
 * H1ポジションの決済管理モード。
 */
enum H1PositionManagementMode {
    /** 従来の決済管理を使用する。 */
    H1_POSITION_MANAGEMENT_LEGACY = 0,

    /** 初期SLとH1 ZigZagトレイルだけを使用する。 */
    H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY = 1
};

/**
 * H1ポジション管理モードが有効範囲か判定する。
 *
 * @param fromMode 判定対象モード。
 * @return 有効な場合true。
 */
bool isH1PositionManagementModeValid(
    const H1PositionManagementMode fromMode
) {
    return fromMode == H1_POSITION_MANAGEMENT_LEGACY
        || fromMode == H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY;
}

#endif // MSTNGEA_CONFIG_H1POSITIONMANAGEMENTMODE_MQH
