//+------------------------------------------------------------------+
//|                                           PriceMovementInfo.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_OSCILLATOR_PRICE_MOVEMENT_INFO_MQH
#define MSTNG_OSCILLATOR_PRICE_MOVEMENT_INFO_MQH

/**
 * 通常の値幅に対する価格変動の強さ。
 */
enum PriceMovementLevel {
    PRICE_MOVEMENT_UNKNOWN = 0,
    PRICE_MOVEMENT_CALM,
    PRICE_MOVEMENT_NORMAL,
    PRICE_MOVEMENT_ACTIVE
};

/**
 * 銘柄・時間足ごとの確定足に基づく値動きの計算結果を保持する。
 */
class PriceMovementInfo {
public:
    /** 値幅とATRの比較結果が有効な場合true。 */
    bool isValid;

    /** 値動きの強さ。 */
    PriceMovementLevel level;

    /** 直近3本の確定足の平均高安差（pips）。 */
    double averageRangePips;

    /** 直近3本より前のATR14（pips）。 */
    double referenceAtrPips;

    /** 平均高安差を基準ATRで割った活動度。 */
    double activityRatio;

    /** 現在スプレッドとの比較結果が有効な場合true。 */
    bool isSpreadValid;

    /** 平均高安差を現在スプレッドで割った倍率。 */
    double rangeSpreadRatio;

    /** 判定に使用した最新確定足の開始時刻（サーバー時刻）。 */
    datetime referenceBarTime;

    /**
     * 判定不能の状態で初期化する。
     */
    PriceMovementInfo() {
        this.resetValues();
    }

    /**
     * 計算結果をクリアし、判定不能へ戻す。
     */
    void resetValues() {
        this.isValid = false;
        this.level = PRICE_MOVEMENT_UNKNOWN;
        this.averageRangePips = 0.0;
        this.referenceAtrPips = 0.0;
        this.activityRatio = 0.0;
        this.isSpreadValid = false;
        this.rangeSpreadRatio = 0.0;
        this.referenceBarTime = 0;
    }
};

#endif // MSTNG_OSCILLATOR_PRICE_MOVEMENT_INFO_MQH
