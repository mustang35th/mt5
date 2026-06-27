//+------------------------------------------------------------------+
//|                                                   Stochastic.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef __STOCHASTIC_MQH__
#define __STOCHASTIC_MQH__

#include <Mstng\Oscillator\StochasticHandlePool.mqh>
#include <Mstng\Util\UtilAll.mqh>

class Stochastic {
public:
    double main0;
    double signal0;

    Stochastic() {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = NULL;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
    }

    Stochastic(StochasticHandlePool *fromStochasticHandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.stochasticHandlePool = fromStochasticHandlePool;
        this.handle = INVALID_HANDLE;
        this.main0 = 0.0;
        this.signal0 = 0.0;
    }

    void setStochasticHandlePool(StochasticHandlePool *fromStochasticHandlePool) {
        this.stochasticHandlePool = fromStochasticHandlePool;
        this.handle = INVALID_HANDLE;
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
        uint startCount = GetTickCount();
        count = 0;
        int len = 100;

        if (!this.ensureInitialized(symbol, period)) {
            this.logger.error(__FUNCTION__, "failed to initialize stochastic handle");
            return false;
        }

        int bars = Bars(symbol, period);
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
            this.logger.error(__FUNCTION__, StringFormat("symbol = %s period = %s start = %d", symbol, TimeUtil::convertTimeFrameToString(period), start));
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
    StochasticHandlePool *stochasticHandlePool;
    int handle;
    Logger logger;

    bool getMain(string symbol, ENUM_TIMEFRAMES period, int shift, double &value) {
        value = 0.0;
        if (!this.ensureInitialized(symbol, period)) {
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
        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s period=%d shift=%d main=%.5f", symbol, period, shift, value));
        return true;
    }

    bool getSignal(string symbol, ENUM_TIMEFRAMES period, int shift, double &value) {
        value = 0.0;
        if (!this.ensureInitialized(symbol, period)) {
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
        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s period=%d shift=%d signal=%.5f", symbol, period, shift, value));
        return true;
    }

    bool ensureInitialized(string symbol, ENUM_TIMEFRAMES period) {
        if (this.stochasticHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "stochasticHandlePool is NULL");
            return false;
        }
        int pooledHandle = this.stochasticHandlePool.getHandle(period);
        if (pooledHandle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat("failed to get handle from pool. symbol=%s period=%d code=%d", symbol, (int)period, GetLastError()));
            return false;
        }
        this.handle = pooledHandle;
        this.logger.debug(__FUNCTION__, StringFormat("initialized from pool. symbol=%s period=%d handle=%d", symbol, (int)period, this.handle));
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
