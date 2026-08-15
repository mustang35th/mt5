//+------------------------------------------------------------------+
//|                                  H1ZigZagTrailDecisionResult.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Domain
 * File: H1ZigZagTrailDecisionResult.mqh
 */

#ifndef MSTNGEA_DOMAIN_H1ZIGZAGTRAILDECISIONRESULT_MQH
#define MSTNGEA_DOMAIN_H1ZIGZAGTRAILDECISIONRESULT_MQH

/**
 * H1 ZigZagトレイルの判定結果。
 */
struct H1ZigZagTrailDecisionResult {
    /** SLを変更する場合true。 */
    bool shouldModify;

    /** 変更候補のSL価格。 */
    double targetStopLoss;

    /** SL基準にした1つ前のZigZagポイント価格。 */
    double pivotRate;

    /** SL基準にした1つ前のZigZagポイント時刻。 */
    datetime pivotBarTime;

    /** SL基準にした1つ前のZigZagポイントのバー位置。 */
    int pivotBarIndex;

    /** SL基準ポイントが山の場合true、谷の場合false。 */
    bool pivotIsPeak;

    /** 判定に使用した最新ZigZagポイント時刻。 */
    datetime latestBarTime;

    /** SL変更を見送った理由。変更する場合は空文字列。 */
    string skipReason;

    /**
     * 未判定状態へ初期化する。
     */
    void reset() {
        this.shouldModify = false;
        this.targetStopLoss = 0.0;
        this.pivotRate = 0.0;
        this.pivotBarTime = 0;
        this.pivotBarIndex = -1;
        this.pivotIsPeak = false;
        this.latestBarTime = 0;
        this.skipReason = "NOT_EVALUATED";
    }
};

#endif // MSTNGEA_DOMAIN_H1ZIGZAGTRAILDECISIONRESULT_MQH
