//+------------------------------------------------------------------+
//|                                              ElliottWaveInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * Package: Mstng.ExpertAdvisor
 * File: ElliottWaveInfo.mqh
 */

#ifndef MSTNG_EXPERTADVISOR_ELLIOTTWAVEINFO_MQH
#define MSTNG_EXPERTADVISOR_ELLIOTTWAVEINFO_MQH

#include <Object.mqh>

/**
 * エリオット波動情報
 */
class ElliottWaveInfo : public CObject {
public:
    /** 時間足 */
    string timeFrame;
    /** 売買 */
    string buySell;
    /** オシレータ */
    string oscillator;
    /** オシレータ短期 */
    string oscillatorS;
    /** オシレータ中期 */
    string oscillatorM;
    /** オシレータ長期 */
    string oscillatorL;
    /** GMMA */
    string gmma;
    /** エリオット */
    string elliott;

    /**
     * コンストラクタ
     */
    ElliottWaveInfo() {
        this.timeFrame = "";
        this.buySell = "";
        this.oscillator = "";
        this.oscillatorS = "";
        this.oscillatorM = "";
        this.oscillatorL = "";
        this.gmma = "";
        this.elliott = "";
    }
};

#endif
