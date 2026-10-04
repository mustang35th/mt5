#ifndef MSTNGH1EA_TRADE_H1EAPROTECTIONPOLICY_MQH
#define MSTNGH1EA_TRADE_H1EAPROTECTIONPOLICY_MQH

#include <MstngEaCommon\Runtime\EaProtectionPolicy.mqh>

/**
 * 共通の保護判定を公開し、H1固有の決済理由を維持する互換クラス。
 */
class H1EaProtectionPolicy : public EaProtectionPolicy {
public:
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
