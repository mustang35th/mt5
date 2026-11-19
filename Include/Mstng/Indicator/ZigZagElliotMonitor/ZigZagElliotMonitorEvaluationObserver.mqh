#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATION_OBSERVER_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATION_OBSERVER_MQH

#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>

/**
 * スキップを除いた実際の確認開始を、判定処理から表示担当へ通知する。
 */
class ZigZagElliotMonitorEvaluationObserver {
public:
    /**
     * データ確認を開始する通貨を通知する。判定条件やシグナル回数は変更しない。
     *
     * @param fromState 今回確認する通貨の状態。
     */
    virtual void onEvaluationStarted(ZigZagElliotMonitorSymbolState &fromState) = 0;
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATION_OBSERVER_MQH
