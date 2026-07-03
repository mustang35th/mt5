//+------------------------------------------------------------------+
//|                                         OscillatorHandlePool.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_OSCILLATOR_HANDLE_POOL_MQH
#define MSTNG_OSCILLATOR_HANDLE_POOL_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\AverageTrueRangeHandlePool.mqh>
#include <Mstng\Oscillator\Ema200HandlePool.mqh>
#include <Mstng\Oscillator\GmmaHandlePool.mqh>
#include <Mstng\Oscillator\StochasticHandlePool.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * 3種類の StochasticHandlePool と GmmaHandlePool と Ema200HandlePool と AverageTrueRangeHandlePool を包括して管理するクラスです。
 *
 * - Short  : 5,3,3
 * - Middle : 14,3,3
 * - Long   : 21,5,5
 */
class OscillatorHandlePool : public CObject {
public:
    /** ハンドル生成範囲の基準となる市場コンテキスト */
    MarketContext marketContext;

    /**
     * 対象シンボルと最終時間足を指定して初期化する。
     *
     * @param fromSymbolName 対象シンボル
     * @param fromTimeFrame 最終時間足
     */
    OscillatorHandlePool(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    OscillatorHandlePool(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ。保持している各種ハンドルを解放します。
     */
    ~OscillatorHandlePool() {
        this.releaseAll();
    }

    /**
     * ハンドル生成範囲の市場コンテキストを設定する。
     *
     * 保持中の全ハンドルを解放してから各ハンドルプールを再初期化する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.releaseAll();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * M1から上位時間足までのハンドル時間軸を再設定します。
     */
    void setTimeframesFromMn1To() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        uint startTick = GetTickCount();

        this.stochasticShortHandlePool.setTimeframesFromMn1To(this.marketContext);
        this.stochasticMiddleHandlePool.setTimeframesFromMn1To(this.marketContext);
        this.stochasticLongHandlePool.setTimeframesFromMn1To(this.marketContext);
        this.gmmaHandlePool.setTimeframesFromMn1To(this.marketContext);
        this.ema200HandlePool.setTimeframesFromMn1To(this.marketContext);
        this.averageTrueRangeHandlePool.setTimeframesFromMn1To(this.marketContext);

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(__FUNCTION__, StringFormat("<elapsed=%d ms>", elapsed));

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * D1から上位時間足までのハンドル時間軸を再設定します。
     */
    void setTimeframesFromD1To() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        uint startTick = GetTickCount();

        this.stochasticShortHandlePool.setTimeframesFromD1To(this.marketContext);
        this.stochasticMiddleHandlePool.setTimeframesFromD1To(this.marketContext);
        this.stochasticLongHandlePool.setTimeframesFromD1To(this.marketContext);
        this.gmmaHandlePool.setTimeframesFromD1To(this.marketContext);
        this.ema200HandlePool.setTimeframesFromD1To(this.marketContext);
        this.averageTrueRangeHandlePool.setTimeframesFromD1To(this.marketContext);

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(__FUNCTION__, StringFormat("<elapsed=%d ms>", elapsed));

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 保持している全ハンドルプールを解放します。
     */
    void releaseAll() {
        this.stochasticShortHandlePool.releaseAll();
        this.stochasticMiddleHandlePool.releaseAll();
        this.stochasticLongHandlePool.releaseAll();
        this.gmmaHandlePool.releaseAll();
        this.ema200HandlePool.releaseAll();
        this.averageTrueRangeHandlePool.releaseAll();
    }

    /**
     * 短期ストキャスティクスハンドルプールを取得します。
     *
     * @return 短期StochasticHandlePool（常に有効）
     */
    StochasticHandlePool* getStochasticShortHandlePool() {
        return &this.stochasticShortHandlePool;
    }

    /**
     * 中期ストキャスティクスハンドルプールを取得します。
     *
     * @return 中期StochasticHandlePool（常に有効）
     */
    StochasticHandlePool* getStochasticMiddleHandlePool() {
        return &this.stochasticMiddleHandlePool;
    }

    /**
     * 長期ストキャスティクスハンドルプールを取得します。
     *
     * @return 長期StochasticHandlePool（常に有効）
     */
    StochasticHandlePool* getStochasticLongHandlePool() {
        return &this.stochasticLongHandlePool;
    }

    /**
     * GMMAハンドルプールを取得します。
     *
     * @return GmmaHandlePool（常に有効）
     */
    GmmaHandlePool* getGmmaHandlePool() {
        return &this.gmmaHandlePool;
    }

    /**
     * EMA200ハンドルプールを取得します。
     *
     * @return Ema200HandlePool（常に有効）
     */
    Ema200HandlePool* getEma200HandlePool() {
        return &this.ema200HandlePool;
    }

    /**
     * ATRハンドルプールを取得します。
     *
     * @return AverageTrueRangeHandlePool（常に有効）
     */
    AverageTrueRangeHandlePool* getAverageTrueRangeHandlePool() {
        return &this.averageTrueRangeHandlePool;
    }

private:
    /** ロガー。 */
    Logger logger;
    /** ストキャスティック短期のハンドルプール。 */
    StochasticHandlePool stochasticShortHandlePool;
    /** ストキャスティック中期のハンドルプール。 */
    StochasticHandlePool stochasticMiddleHandlePool;
    /** ストキャスティック長期のハンドルプール。 */
    StochasticHandlePool stochasticLongHandlePool;
    /** GMMAハンドルプール。 */
    GmmaHandlePool gmmaHandlePool;
    /** EMA200ハンドルプール。 */
    Ema200HandlePool ema200HandlePool;
    /** ATRハンドルプール。 */
    AverageTrueRangeHandlePool averageTrueRangeHandlePool;

    /**
     * 市場コンテキストおよび各ハンドルプールを初期化する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        this.stochasticShortHandlePool = StochasticHandlePool(this.marketContext, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
        this.stochasticMiddleHandlePool = StochasticHandlePool(this.marketContext, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
        this.stochasticLongHandlePool = StochasticHandlePool(this.marketContext, 21, 5, 5, MODE_SMA, STO_LOWHIGH);
        this.gmmaHandlePool = GmmaHandlePool(this.marketContext, 30, 60, MODE_EMA, PRICE_CLOSE);
        this.averageTrueRangeHandlePool = AverageTrueRangeHandlePool(this.marketContext, 14);
        this.ema200HandlePool = Ema200HandlePool(this.marketContext, 200, MODE_EMA, PRICE_CLOSE);
    }
};

#endif // MSTNG_OSCILLATOR_HANDLE_POOL_MQH
