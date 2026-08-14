//+------------------------------------------------------------------+
//|                                       ProfitRetracementState.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Domain
 * File: ProfitRetracementState.mqh
 */

#ifndef MSTNGEA_DOMAIN_PROFITRETRACEMENTSTATE_MQH
#define MSTNGEA_DOMAIN_PROFITRETRACEMENTSTATE_MQH

/**
 * 利益戻し決済状態
 */
class ProfitRetracementState {
public:
    /** Stable position identifier */
    ulong positionIdentifier;

    /** ポジションチケット */
    ulong positionTicket;

    /** Position open time in milliseconds */
    long positionOpenTimeMilliseconds;

    /** true: BUY position */
    bool isBuy;

    /** Position open price */
    double openPrice;

    /** Initial stop loss */
    double initialStopLoss;

    /** Position volume at the last update */
    double positionVolume;

    /** Best observed exit price */
    double bestPrice;

    /** 最大含み益 */
    double maxFloatingProfit;

    /** エントリー価格から初期ストップロスまでの価格差 */
    double initialRiskDistance;

    /** true: initial risk is available */
    bool isInitialRiskAvailable;

    /** 監視開始済み */
    bool activated;

    /** Profit retracement start R used by this state */
    double configuredStartR;

    /** Profit retracement rate used by this state */
    double configuredRetracementRate;

    /** Runtime-only initial persistence result */
    bool isInitialStatePersisted;

    /**
     * コンストラクタ
     */
    ProfitRetracementState() {
        this.positionIdentifier = 0;
        this.positionTicket = 0;
        this.positionOpenTimeMilliseconds = 0;
        this.isBuy = true;
        this.openPrice = 0.0;
        this.initialStopLoss = 0.0;
        this.positionVolume = 0.0;
        this.bestPrice = 0.0;
        this.maxFloatingProfit = 0.0;
        this.initialRiskDistance = 0.0;
        this.isInitialRiskAvailable = false;
        this.activated = false;
        this.configuredStartR = 0.0;
        this.configuredRetracementRate = 0.0;
        this.isInitialStatePersisted = false;
    }

    /**
     * 状態初期化
     */
    void reset() {
        this.positionIdentifier = 0;
        this.positionTicket = 0;
        this.positionOpenTimeMilliseconds = 0;
        this.isBuy = true;
        this.openPrice = 0.0;
        this.initialStopLoss = 0.0;
        this.positionVolume = 0.0;
        this.bestPrice = 0.0;
        this.maxFloatingProfit = 0.0;
        this.initialRiskDistance = 0.0;
        this.isInitialRiskAvailable = false;
        this.activated = false;
        this.configuredStartR = 0.0;
        this.configuredRetracementRate = 0.0;
        this.isInitialStatePersisted = false;
    }

    /**
     * Copy state values.
     *
     * @param fromState Source state.
     */
    void copyFrom(ProfitRetracementState &fromState) {
        this.positionIdentifier = fromState.positionIdentifier;
        this.positionTicket = fromState.positionTicket;
        this.positionOpenTimeMilliseconds = fromState.positionOpenTimeMilliseconds;
        this.isBuy = fromState.isBuy;
        this.openPrice = fromState.openPrice;
        this.initialStopLoss = fromState.initialStopLoss;
        this.positionVolume = fromState.positionVolume;
        this.bestPrice = fromState.bestPrice;
        this.maxFloatingProfit = fromState.maxFloatingProfit;
        this.initialRiskDistance = fromState.initialRiskDistance;
        this.isInitialRiskAvailable = fromState.isInitialRiskAvailable;
        this.activated = fromState.activated;
        this.configuredStartR = fromState.configuredStartR;
        this.configuredRetracementRate = fromState.configuredRetracementRate;
        this.isInitialStatePersisted = fromState.isInitialStatePersisted;
    }
};

#endif
