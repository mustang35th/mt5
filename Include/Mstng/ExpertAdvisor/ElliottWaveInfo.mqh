//+------------------------------------------------------------------+
//|                                              ElliottWaveInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * ExpertAdvisor用のElliott波動表示情報を保持するクラス定義。
 */

#ifndef MSTNG_EXPERTADVISOR_ELLIOTTWAVEINFO_MQH
#define MSTNG_EXPERTADVISOR_ELLIOTTWAVEINFO_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Object.mqh>

/**
 * 時間足別の売買、オシレーター、GMMA、Elliott波動表示情報を保持する。
 */
class ElliottWaveInfo : public CObject {
public:
    /** 波動情報の市場コンテキスト。 */
    MarketContext marketContext;

    /** 互換用の時間足表示名。 */
    string timeFrame;
    /** 売買方向ラベル。 */
    string buySell;
    /** オシレーター総合カウント。 */
    string oscillator;
    /** 短期オシレーターカウント。 */
    string oscillatorS;
    /** 中期オシレーターカウント。 */
    string oscillatorM;
    /** 長期オシレーターカウント。 */
    string oscillatorL;
    /** GMMAカウント。 */
    string gmma;
    /** Elliott波動ラベル。 */
    string elliott;

    /**
     * デフォルト値で初期化する。
     */
    ElliottWaveInfo() {
        this.initialize();
    }

    /**
     * 市場コンテキストを使用して初期化する。
     *
     * @param fromMarketContext 波動情報の市場コンテキスト。
     */
    ElliottWaveInfo(MarketContext &fromMarketContext) {
        this.initialize();
        this.setMarketContext(fromMarketContext);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext 波動情報の市場コンテキスト。
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
