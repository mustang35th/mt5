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

#include <Mstng\Common\MarketContext.mqh>
#include <Object.mqh>

/**
 * エリオット波動情報
 */
class ElliottWaveInfo : public CObject {
public:
    /** 波動情報の市場コンテキスト */
    MarketContext marketContext;

    /** 互換用の時間足表示名 */
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
        this.initialize();
    }

    /**
     * 市場コンテキストを使用して初期化する。
     *
     * @param fromMarketContext 波動情報の市場コンテキスト
     */
    ElliottWaveInfo(MarketContext &fromMarketContext) {
        this.initialize();
        this.setMarketContext(fromMarketContext);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext 波動情報の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.timeFrame = this.marketContext.timeFrameLabel;
    }

private:
    /**
     * 波動情報を初期化する。
     */
    void initialize() {
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
