//+------------------------------------------------------------------+
//|                                             PositionSnapshot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Domain
 * File: PositionSnapshot.mqh
 */

#ifndef MSTNGEA_DOMAIN_POSITIONSNAPSHOT_MQH
#define MSTNGEA_DOMAIN_POSITIONSNAPSHOT_MQH

/**
 * ポジション状態
 */
class PositionSnapshot {
public:
    /** ポジション有無 */
    bool hasPosition;

    /** true: 買い false: 売り */
    bool isBuy;

    /** チケット */
    ulong ticket;

    /** Position identifier */
    ulong identifier;

    /** Position open time in milliseconds */
    long openTimeMilliseconds;

    /** 数量 */
    double volume;

    /** 建値 */
    double openPrice;

    /** ストップロス */
    double stopLoss;

    /** 評価損益 */
    double floatingProfit;

    /**
     * コンストラクタ
     */
    PositionSnapshot() {
        // 初期値を設定
        this.hasPosition = false;
        this.isBuy = true;
        this.ticket = 0;
        this.identifier = 0;
        this.openTimeMilliseconds = 0;
        this.volume = 0.0;
        this.openPrice = 0.0;
        this.stopLoss = 0.0;
        this.floatingProfit = 0.0;
    }
};

#endif
