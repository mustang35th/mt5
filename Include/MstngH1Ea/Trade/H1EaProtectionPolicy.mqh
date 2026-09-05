#ifndef MSTNGH1EA_TRADE_H1EAPROTECTIONPOLICY_MQH
#define MSTNGH1EA_TRADE_H1EAPROTECTIONPOLICY_MQH

/**
 * broker送信に依存しない保護SLと注文結果の判定。
 */
class H1EaProtectionPolicy {
public:
    /**
     * broker実SLが候補以上に保護されているか確認する。
     */
    static bool protects(const bool fromIsBuy, const double fromActual,
            const double fromTarget, const double fromTickSize) {
        if (!MathIsValidNumber(fromActual) || !MathIsValidNumber(fromTarget)
                || fromActual <= 0.0 || fromTarget <= 0.0 || fromTickSize <= 0.0) {
            return false;
        }
        if (fromIsBuy) {
            return fromActual >= fromTarget - fromTickSize * 0.5;
        }
        return fromActual <= fromTarget + fromTickSize * 0.5;
    }

    /**
     * 1tick以上保護側へ進んだ候補だけ採用する。
     */
    static bool improves(const bool fromIsBuy, const double fromTarget,
            const double fromPrevious, const double fromTickSize) {
        if (fromTarget <= 0.0 || fromPrevious <= 0.0 || fromTickSize <= 0.0) {
            return false;
        }
        double improvement = fromPrevious - fromTarget;
        if (fromIsBuy) {
            improvement = fromTarget - fromPrevious;
        }
        return improvement + fromTickSize * 0.000001 >= fromTickSize;
    }

    /**
     * 成行決済に使う側の価格が候補を跨いだか確認する。
     */
    static bool crossed(const bool fromIsBuy, const double fromBid,
            const double fromAsk, const double fromTarget) {
        if (fromBid <= 0.0 || fromAsk < fromBid || fromTarget <= 0.0) {
            return false;
        }
        if (fromIsBuy) {
            return fromBid <= fromTarget;
        }
        return fromAsk >= fromTarget;
    }

    /**
     * 停止距離とfreeze距離の厳しい方に1tickの余白を加える。
     */
    static bool canModify(const bool fromIsBuy, const double fromBid,
            const double fromAsk, const double fromTarget, const double fromPoint,
            const double fromTickSize, const long fromStops, const long fromFreeze) {
        if (fromPoint <= 0.0 || fromTickSize <= 0.0 || fromBid <= 0.0
                || fromAsk < fromBid || fromTarget <= 0.0) {
            return false;
        }
        double distance = fromTarget - fromAsk;
        if (fromIsBuy) {
            distance = fromBid - fromTarget;
        }
        double required = (double)MathMax(fromStops, fromFreeze) * fromPoint + fromTickSize;
        return distance + fromTickSize * 0.000001 >= required;
    }

    /**
     * 受付不明を拒否と誤認して再発注しない。
     */
    static bool isUnknownRetcode(const uint fromRetcode) {
        return fromRetcode == 0 || fromRetcode == TRADE_RETCODE_TIMEOUT
            || fromRetcode == TRADE_RETCODE_CONNECTION || fromRetcode == TRADE_RETCODE_ERROR;
    }

    /**
     * 受付と約定完了は別に扱う。
     */
    static bool isAcceptedRetcode(const uint fromRetcode) {
        return fromRetcode == TRADE_RETCODE_DONE || fromRetcode == TRADE_RETCODE_DONE_PARTIAL
            || fromRetcode == TRADE_RETCODE_PLACED;
    }

    /**
     * 受付不明のSL要求は同じ水準の反映または終端応答でだけ解決する。
     * より保護的な外部SLだけでは古い要求が遅延中でないと証明できない。
     */
    static bool canResolveModify(const bool fromTerminalResponse,
            const double fromActual, const double fromTarget, const double fromTickSize) {
        if (fromTerminalResponse) {
            return true;
        }
        return fromActual > 0.0 && fromTarget > 0.0 && fromTickSize > 0.0
            && MathAbs(fromActual - fromTarget) <= fromTickSize * 0.5;
    }

    /**
     * brokerの終端注文だけを未成立と確定できる。
     */
    static bool isTerminalOrder(const long fromState) {
        return fromState == ORDER_STATE_FILLED || fromState == ORDER_STATE_CANCELED
            || fromState == ORDER_STATE_REJECTED || fromState == ORDER_STATE_EXPIRED;
    }

    /**
     * broker理由とEA内部意図を分離した決済分類を返す。
     */
    static string closeReason(const string fromIntent, const string fromSource,
            const string fromBrokerReason) {
        if (fromIntent == "INITIAL_STOP_LOSS_CROSSED" || fromIntent == "H1_ZIGZAG_TRAIL_CROSSED") {
            return fromIntent;
        }
        if (fromBrokerReason == "SL") {
            if (fromSource == "INITIAL_STOP_LOSS" || fromSource == "H1_ZIGZAG_TRAIL") {
                return fromSource;
            }
            if (fromSource == "EXTERNAL") {
                return "EXTERNAL_STOP_LOSS";
            }
            return "UNKNOWN_STOP_LOSS";
        }
        if (fromBrokerReason == "CLIENT" || fromBrokerReason == "MOBILE"
                || fromBrokerReason == "WEB") {
            return "EXTERNAL_CLOSE";
        }
        return "UNKNOWN_CLOSE";
    }
};

#endif
