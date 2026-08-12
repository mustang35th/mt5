//+------------------------------------------------------------------+
//|                                 H1ElliotObservationQueueItem.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_H1_OBSERVATION_QUEUE_ITEM_MQH
#define MSTNG_ZZE_H1_OBSERVATION_QUEUE_ITEM_MQH

#include <Object.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshot.mqh>

/**
 * DB保存待ちのH1 Elliott観測Snapshotを表すキュー要素。
 *
 * 分析後の値を固定して保持し、保存失敗時も再分析で内容を変更しない。
 */
class H1ElliotObservationQueueItem : public CObject {
public:
    /** 保存対象シンボル。 */
    string symbolName;

    /** 観測対象H1バー開始時刻。 */
    datetime anchorBarTime;

    /** DB保存失敗回数。 */
    int retryCount;

    /** 固定済み観測Snapshot。 */
    ZigZagElliotObservationSnapshot snapshot;

    /**
     * 空のキュー要素として初期化する。
     */
    H1ElliotObservationQueueItem() {
        this.symbolName = "";
        this.anchorBarTime = 0;
        this.retryCount = 0;
        this.snapshot.clear();
    }
};

#endif // MSTNG_ZZE_H1_OBSERVATION_QUEUE_ITEM_MQH
