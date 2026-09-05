#ifndef MSTNGH1EA_INITIAL_STOP_LOSS_DECISION_MQH
#define MSTNGH1EA_INITIAL_STOP_LOSS_DECISION_MQH

/**
 * 初期SLの価格、建値からの幅および拒否理由を保持する。
 */
struct H1EaInitialStopLossResult {
    /** 発注に使用できる場合true。 */
    bool isAccepted;
    /** 最小価格刻みへ丸めたSL。 */
    double stopLoss;
    /** BUY Ask/SELL BidからSLまでのpips幅。 */
    double riskPips;
    /** 判定理由。 */
    string reasonCode;

    /**
     * 未判定状態に戻す。
     */
    void reset() {
        this.isAccepted = false;
        this.stopLoss = 0.0;
        this.riskPips = 0.0;
        this.reasonCode = "INITIAL_STOP_LOSS_INVALID";
    }
};

/**
 * H1シグナル基準点±10pipsから必須の初期SLを計算する純粋判定。
 */
class H1EaInitialStopLossDecision {
public:
    /**
     * 方向、価格単位、最大リスクとbroker Stops距離を検証する。
     *
     * @param fromIsBuy BUY注文の場合true。
     * @param fromPivotPrice シグナル基準点の価格。
     * @param fromPivotIsHigh 基準点が山の場合true。
     * @param fromBid 現在Bid。
     * @param fromAsk 現在Ask。
     * @param fromPipSize 1pipの価格幅。
     * @param fromTickSize 最小価格刻み。
     * @param fromPointSize brokerのpoint幅。
     * @param fromStopsLevel 必須SL距離のpoints数。
     * @param fromMaxRiskPips 許可する正の最大初期SL幅。
     * @param fromResult 判定結果。
     * @return 初期SLが有効な場合true。
     */
    bool evaluate(
        const bool fromIsBuy,
        const double fromPivotPrice,
        const bool fromPivotIsHigh,
        const double fromBid,
        const double fromAsk,
        const double fromPipSize,
        const double fromTickSize,
        const double fromPointSize,
        const long fromStopsLevel,
        const double fromMaxRiskPips,
        H1EaInitialStopLossResult &fromResult
    ) {
        fromResult.reset();

        if (!this.isPositive(fromPivotPrice)
                || !this.isPositive(fromBid)
                || !this.isPositive(fromAsk)
                || fromAsk < fromBid) {
            fromResult.reasonCode = "INITIAL_STOP_LOSS_PRICE_UNAVAILABLE";

            return false;
        }

        if (!this.isPositive(fromPipSize)
                || !this.isPositive(fromTickSize)
                || !this.isPositive(fromPointSize)
                || fromStopsLevel < 0) {
            fromResult.reasonCode = "INVALID_PRICE_UNIT";

            return false;
        }

        if (!this.isPositive(fromMaxRiskPips)) {
            fromResult.reasonCode = "MAX_INITIAL_STOP_LOSS_UNSET";

            return false;
        }

        if (fromIsBuy == fromPivotIsHigh) {
            fromResult.reasonCode = "INITIAL_STOP_LOSS_PIVOT_DIRECTION_MISMATCH";

            return false;
        }

        double rawStopLoss = fromPivotPrice + 10.0 * fromPipSize;
        double entryPrice = fromBid;

        if (fromIsBuy) {
            rawStopLoss = fromPivotPrice - 10.0 * fromPipSize;
            entryPrice = fromAsk;
        }

        double tickCount = rawStopLoss / fromTickSize;

        if (!MathIsValidNumber(tickCount) || MathAbs(tickCount) > 1.0e15) {
            fromResult.reasonCode = "INVALID_PRICE_UNIT";

            return false;
        }

        double target = MathCeil(tickCount - 1.0e-8) * fromTickSize;

        if (fromIsBuy) {
            target = MathFloor(tickCount + 1.0e-8) * fromTickSize;
        }

        fromResult.stopLoss = target;

        if (!this.isPositive(target)) {
            return false;
        }

        double closeDistance = target - fromAsk;

        if (fromIsBuy) {
            closeDistance = fromBid - target;
        }

        if (closeDistance <= 0.0) {
            fromResult.reasonCode = "INITIAL_STOP_LOSS_WRONG_SIDE";

            return false;
        }

        fromResult.riskPips = MathAbs(entryPrice - target) / fromPipSize;

        if (!MathIsValidNumber(fromResult.riskPips)
                || fromResult.riskPips > fromMaxRiskPips + 1.0e-8) {
            fromResult.reasonCode = "INITIAL_STOP_LOSS_TOO_WIDE";

            return false;
        }

        if (closeDistance + fromTickSize * 1.0e-8
                < (double)fromStopsLevel * fromPointSize) {
            fromResult.reasonCode = "INITIAL_STOP_LOSS_STOPS_LEVEL";

            return false;
        }

        fromResult.isAccepted = true;
        fromResult.reasonCode = "INITIAL_STOP_LOSS_ACCEPTED";

        return true;
    }

private:
    /**
     * 有限の正価格か確認する。
     */
    bool isPositive(const double fromValue) {
        return MathIsValidNumber(fromValue)
            && fromValue != EMPTY_VALUE
            && fromValue > 0.0;
    }
};

#endif
