//+------------------------------------------------------------------+
//|                   ZigZagElliotObservationSnapshot.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_SNAPSHOT_MQH
#define MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_SNAPSHOT_MQH

#include <Mstng\Database\Entity\ZigZagElliotObservationEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationTimeFrameEntity.mqh>

/**
 * ZigZagElliot観測本体と時間足別分析をまとめるクラス。
 */
class ZigZagElliotObservationSnapshot {
public:
    /** 観測本体。 */
    ZigZagElliotObservationEntity observation;

    /** 時間足別分析一覧。 */
    ZigZagElliotObservationTimeFrameEntity timeFrames[];

    /**
     * 空の観測スナップショットとして初期化する。
     */
    ZigZagElliotObservationSnapshot() {
        this.clear();
    }

    /**
     * 観測本体と時間足別分析一覧を初期化する。
     */
    void clear() {
        ZeroMemory(this.observation);
        ArrayResize(this.timeFrames, 0);
    }
};

#endif // MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_SNAPSHOT_MQH
