//+------------------------------------------------------------------+
//|                               Mtf3In3AlertSnapshot.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_MQH

#include <Mstng\Database\Entity\ZigZagElliotAlertEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertPointEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertTimeFrameEntity.mqh>

/**
 * MTF_3in3アラート時点のElliott分析結果を保持するクラス。
 *
 * アラート本体、時間足別分析および最新Waveのポイントを、1回の
 * トランザクションで保存できる形にまとめる。
 */
class Mtf3In3AlertSnapshot {
public:
    /** アラート本体。 */
    ZigZagElliotAlertEntity alert;
    /** 時間足別Elliott分析一覧。 */
    ZigZagElliotAlertTimeFrameEntity timeFrames[];
    /** 最新WaveのZigZagポイント一覧。 */
    ZigZagElliotAlertPointEntity points[];

    /**
     * 空のスナップショットとして初期化する。
     */
    Mtf3In3AlertSnapshot() {
        this.clear();
    }

    /**
     * アラート本体と子要素を初期状態へ戻す。
     */
    void clear() {
        ZeroMemory(this.alert);
        ArrayResize(this.timeFrames, 0);
        ArrayResize(this.points, 0);
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_MQH
