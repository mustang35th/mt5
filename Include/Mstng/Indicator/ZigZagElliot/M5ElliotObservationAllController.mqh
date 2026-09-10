//+------------------------------------------------------------------+
//|                             M5ElliotObservationAllController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_M5_OBSERVATION_ALL_CONTROLLER_MQH
#define MSTNG_ZZE_M5_OBSERVATION_ALL_CONTROLLER_MQH

#include <Mstng\Indicator\ZigZagElliot\H1ElliotObservationAllController.mqh>

/**
 * 全28通貨M5観測の固定Profileを選択する薄い入口クラス。
 *
 * 境界・ウォームアップ・FIFOはH1の既存収集エンジンを共有し、
 * M5の7時間足・同一気配・取得品質・専用DBを有効にする。
 */
class M5ElliotObservationAllController : public H1ElliotObservationAllController {
public:
    /**
     * 起動中に変更しないM5観測Profileを指定する。
     */
    M5ElliotObservationAllController() : H1ElliotObservationAllController(PERIOD_M5) {
    }
};

#endif // MSTNG_ZZE_M5_OBSERVATION_ALL_CONTROLLER_MQH
