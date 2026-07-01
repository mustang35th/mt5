//+------------------------------------------------------------------+
//|                                                   Stochastic.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef __STOCHASTIC_MQH__
#define __STOCHASTIC_MQH__

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\StochasticHandlePool.mqh>
#include <Mstng\Util\UtilAll.mqh>

class Stochastic {
public:
    /** 取得対象の市場コンテキスト */
    MarketContext marketContext;

    double main0;
    double signal0;

    Stochastic() {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = NULL;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     */
    Stochastic(MarketContext &fromMarketContext) {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = NULL;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
        this.initializeMarketContext(fromMarketContext);
    }

    Stochastic(StochasticHandlePool *fromStochasticHandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = fromStochasticHandlePool;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
    }

    /**
     * 市場コンテキストとストキャスティクスハンドルプールを指定して初期化する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromStochasticHandlePool ストキャスティクスハンドルプール
     */
    Stochastic(
        MarketContext &fromMarketContext,
        StochasticHandlePool *fromStochasticHandlePool
    ) {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = fromStochasticHandlePool;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
        this.initializeMarketContext(fromMarketContext);
    }

    void setStochasticHandlePool(StochasticHandlePool *fromStochasticHandlePool) {
        this.stochasticHandlePool = fromStochasticHandlePool;
        this.handle = INVALID_HANDLE;
    }

    /**
     * 取得対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    ~Stochastic() {
        this.handle = INVALID_HANDLE;
        this.stochasticHandlePool = NULL;
    }

    int getCrossCount(string symbol, ENUM_TIMEFRAMES period) {
        return this.getCrossCount(symbol, period, 0);
    }

    int getCrossCount(string symbol, ENUM_TIMEFRAMES period, int start) {
        int count = 0;
        if (!this.getCrossCount(symbol, period, start, count)) {
            return 0;
        }
        return count;
    }

    bool getCrossCount(string symbol, ENUM_TIMEFRAMES period, int start, int &count) {
        MarketContext context(symbol, period);

        return this.getCrossCount(context, start, count);
    }

    /**
     * 市場コンテキストを使用してストキャスティクスのクロス継続数を取得する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param start 取得開始シフト
     * @param count クロス継続数
     * @return 取得に成功した場合true
     */
    bool getCrossCount(MarketContext &fromMarketContext, int start, int &count) {
        this.initializeMarketContext(fromMarketContext);

        uint startCount = GetTickCount();
        count = 0;
        int len = 100;

        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "failed to initialize stochastic handle");
            return false;
        }

        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
        if (bars <= start) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d start=%d", bars, start));
            return false;
        }

        int barsToCopy = len + start + 1;
        if (barsToCopy > bars) barsToCopy = bars - start;
        if (barsToCopy <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("barsToCopy <= 0. barsToCopy=%d", barsToCopy));
            return false;
        }

        double mainBuffer[];
        double signalBuffer[];
        ArraySetAsSeries(mainBuffer, true);
        ArraySetAsSeries(signalBuffer, true);

        ResetLastError();
        int copiedMain = CopyBuffer(this.handle, 0, start, barsToCopy, mainBuffer);
        int copiedSignal = CopyBuffer(this.handle, 1, start, barsToCopy, signalBuffer);
        if (copiedMain <= 0 || copiedSignal <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("symbol = %s period = %s start = %d", this.marketContext.symbolName, this.marketContext.timeFrameLabel, start));
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copiedMain=%d copiedSignal=%d code=%d", copiedMain, copiedSignal, GetLastError()));
            return false;
        }

        int maxCheck = len;
        if (copiedMain < maxCheck) maxCheck = copiedMain;
        if (copiedSignal < maxCheck) maxCheck = copiedSignal;
        if (maxCheck <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("maxCheck <= 0. maxCheck=%d", maxCheck));
            return false;
        }

        this.main0 = mainBuffer[0];
        this.signal0 = signalBuffer[0];

        bool isPlus0 = this.isPlus(this.main0, this.signal0);
        count = 1;
        for (int i = 1; i < maxCheck; i++) {
            if (this.isPlus(mainBuffer[i], signalBuffer[i]) == isPlus0) {
                count++;
            } else {
                break;
            }
        }
        if (!isPlus0) count = 0 - count;

        this.logger.debug(__FUNCTION__, StringFormat("count=%s elapsed=%d ms", StringUtil::addSign(count), GetTickCount() - startCount));
        return true;
    }

private:
    /**
     * 市場コンテキストとロガーを初期化する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    StochasticHandlePool *stochasticHandlePool;
    int handle;
    Logger logger;

    bool getMain(MarketContext &fromMarketContext, int shift, double &value) {
        value = 0.0;
        if (!this.ensureInitialized(fromMarketContext)) {
            this.logger.error(__FUNCTION__, "failed to initialize stochastic handle in getMain");
            return false;
        }
        double buffer[];
        ArraySetAsSeries(buffer, true);
        ResetLastError();
        int copied = CopyBuffer(this.handle, 0, shift, 1, buffer);
        if (copied <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer(main) error. code=%d", GetLastError()));
            return false;
        }
        value = buffer[0];
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "symbol=%s period=%d shift=%d main=%.5f",
                fromMarketContext.symbolName,
                fromMarketContext.timeFrame,
                shift,
                value
            )
        );
        return true;
    }

    bool getSignal(MarketContext &fromMarketContext, int shift, double &value) {
        value = 0.0;
        if (!this.ensureInitialized(fromMarketContext)) {
            this.logger.error(__FUNCTION__, "failed to initialize stochastic handle in getSignal");
            return false;
        }
        double buffer[];
        ArraySetAsSeries(buffer, true);
        ResetLastError();
        int copied = CopyBuffer(this.handle, 1, shift, 1, buffer);
        if (copied <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer(signal) error. code=%d", GetLastError()));
            return false;
        }
        value = buffer[0];
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "symbol=%s period=%d shift=%d signal=%.5f",
                fromMarketContext.symbolName,
                fromMarketContext.timeFrame,
                shift,
                value
            )
        );
        return true;
    }

    bool ensureInitialized(string symbol, ENUM_TIMEFRAMES period) {
        MarketContext context(symbol, period);

        return this.ensureInitialized(context);
    }

    /**
     * 市場コンテキストを使用してハンドルを初期化する。
     *
     * @param fromMarketContext 初期化対象の市場コンテキスト
     * @return 初期化できた場合true
     */
    bool ensureInitialized(MarketContext &fromMarketContext) {
        if (this.stochasticHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "stochasticHandlePool is NULL");
            return false;
        }
        int pooledHandle = this.stochasticHandlePool.getHandle(fromMarketContext.timeFrame);
        if (pooledHandle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat("failed to get handle from pool. symbol=%s period=%d code=%d", fromMarketContext.symbolName, (int)fromMarketContext.timeFrame, GetLastError()));
            return false;
        }
        this.handle = pooledHandle;
        this.logger.debug(__FUNCTION__, StringFormat("initialized from pool. symbol=%s period=%d handle=%d", fromMarketContext.symbolName, (int)fromMarketContext.timeFrame, this.handle));
        return true;
    }

    bool isPlus(double main, double signal) {
        bool plus = false;
        this.logger.debug(__FUNCTION__, StringFormat("main=%.5f signal=%.5f", main, signal));
        if (main - signal >= 0.0) {
            plus = true;
        }
        this.logger.debug(__FUNCTION__, StringFormat("plus=%s", plus ? "true" : "false"));
        return plus;
    }
};

#endif // __STOCHASTIC_MQH__
