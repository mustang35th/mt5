/**
 * Package: MstngEa.Domain
 * File: ExitDecision.mqh
 */

#ifndef MSTNGEA_DOMAIN_EXITDECISION_MQH
#define MSTNGEA_DOMAIN_EXITDECISION_MQH

/**
 * 決済判定結果
 */
struct ExitDecision {
    /** 決済対象 */
    bool isExit;

    /** 理由 */
    string reason;
};

#endif
