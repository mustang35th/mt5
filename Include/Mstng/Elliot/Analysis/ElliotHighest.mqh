//+------------------------------------------------------------------+
//|                                                ElliotHighest.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>

/**
 * 最上位時間足のElliott波動を分析するクラス。
 *
 * 上位足を参照せず、対象時間足自身のZigZagポイントからWaveを生成する。
 */
class ElliotHighest : public ElliotBase {
public:
    /**
     * 分析条件を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    ElliotHighest(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsBuy, string fromBuySellLabel) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromIsBuy, fromBuySellLabel);
    }

    /**
     * 市場コンテキストおよび分析条件を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    ElliotHighest(MarketContext &fromMarketContext, bool fromIsBuy, string fromBuySellLabel) {
        this.initialize(fromMarketContext, fromIsBuy, fromBuySellLabel);
    }

    /**
     * ElliotHighest を破棄します。
     */
    ~ElliotHighest() {
    }

    /**
     * 最上位時間足の波動分析を実行する。
     *
     * @return ZigZag取得とWave生成に成功した場合true
     */
    bool analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);


        if (!this.setZigZagPointList()) {
            this.logger.error(__FUNCTION__, "setZigZagPointList false");

            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }


        if (!this.getWave0(true)) {
            this.logger.error(__FUNCTION__, "getWave0 false");

            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        this.analyzeWave();

        Wave *wave = this.waveList.At(0);

        ZigZagPointUtil::copyZigZagPointList(wave.zigZagPointList, wave.orgZigZagPointList);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

private:
    /**
     * 市場コンテキストおよび分析条件を初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    void initialize(MarketContext &fromMarketContext, bool fromIsBuy, string fromBuySellLabel) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext, fromIsBuy, fromBuySellLabel);
    }
};    





