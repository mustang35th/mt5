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
    /** ポジションチケット */
    ulong positionTicket;

    /** 最大含み益 */
    double maxFloatingProfit;

    /** エントリー価格から初期ストップロスまでの価格差 */
    double initialRiskDistance;

    /** 監視開始済み */
    bool activated;

    /**
     * コンストラクタ
     */
    ProfitRetracementState() {
        this.positionTicket = 0;
        this.maxFloatingProfit = 0.0;
        this.initialRiskDistance = 0.0;
        this.activated = false;
    }

    /**
     * 状態初期化
     */
    void reset() {
        this.positionTicket = 0;
        this.maxFloatingProfit = 0.0;
        this.initialRiskDistance = 0.0;
        this.activated = false;
    }
};

#endif
