//+------------------------------------------------------------------+
//|                                                         Gmma.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __GMMA_MQH__
#define __GMMA_MQH__

#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\GmmaHandlePool.mqh>
#include <Mstng\Oscillator\GmmaUtil.mqh>
#include <Mstng\Util\StringUtil.mqh>

class Gmma {
public:
    Gmma() {
        this.logger.setLevel(LOG_INFO);
        this.symbolName = "";
        this.timeFrame = PERIOD_CURRENT;
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = NULL;
        this.isInitialized = false;
    }

    Gmma(GmmaHandlePool *fromGmmaHandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.symbolName = "";
        this.timeFrame = PERIOD_CURRENT;
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = fromGmmaHandlePool;
        this.isInitialized = false;
    }

    void setGmmaHandlePool(GmmaHandlePool *fromGmmaHandlePool) {
        this.gmmaHandlePool = fromGmmaHandlePool;
        this.isInitialized = false;
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
    }

    ~Gmma() {
        if (this.gmmaHandlePool == NULL) {
            this.releaseHandles();
        } else {
            this.ema30Handle = INVALID_HANDLE;
            this.ema60Handle = INVALID_HANDLE;
        }
    }

    int getCrossCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        int count = 0;
        if (!this.getCrossCount(fromSymbolName, fromTimeFrame, count)) {
            return 0;
        }
        return count;
    }

    int getTrendCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        int count = 0;

        if (!this.getTrendCount(fromSymbolName, fromTimeFrame, count)) {
            return 0;
        }

        return count;
    }

    /**
     * GMMAトレンドが連続している件数を取得する。
     *
     * 直近から過去へ向かって EMA30 / EMA60 の傾きを比較し、
     * GmmaUtil::getGmmaTrend の戻り値が連続している本数を返す。
     * BUY は正の値、SELL は負の値、NON は 0 を返す。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param count 件数
     * @return 取得できた場合 true
     */
    bool getTrendCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int &count) {
        uint startCount = GetTickCount();
        count = 0;

        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s timeFrame=%d", fromSymbolName, fromTimeFrame));

        if (!this.ensureInitialized(fromSymbolName, fromTimeFrame)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int len = 1000;
        int bars = Bars(fromSymbolName, fromTimeFrame);

        if (bars <= 2) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d", bars));

            return false;
        }

        int barsToCopy = len + 1;

        if (barsToCopy > bars) {
            barsToCopy = bars;
        }

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();

        int copied30 = CopyBuffer(this.ema30Handle, 0, 0, barsToCopy, ema30Buffer);
        int copied60 = CopyBuffer(this.ema60Handle, 0, 0, barsToCopy, ema60Buffer);

        if (copied30 <= 1 || copied60 <= 1) {
            this.logger.error(__FUNCTION__, StringFormat("fromSymbolName = %s fromTimeFrame = %s", fromSymbolName, EnumToString(fromTimeFrame)));
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied30=%d copied60=%d code=%d", copied30, copied60, GetLastError()));

            return false;
        }

        int maxCheck = len;

        if (copied30 - 1 < maxCheck) {
            maxCheck = copied30 - 1;
        }

        if (copied60 - 1 < maxCheck) {
            maxCheck = copied60 - 1;
        }

        if (maxCheck <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("maxCheck <= 0. maxCheck=%d", maxCheck));

            return false;
        }

        ENUM_GMMA_TREND trend0 = GmmaUtil::getGmmaTrend(
            ema30Buffer[1],
            ema30Buffer[0],
            ema60Buffer[1],
            ema60Buffer[0]
        );

        if (trend0 == GMMA_TREND_NON) {
            count = 0;

            this.logger.debug(__FUNCTION__, StringFormat("count=%d direction=NON elapsed=%d ms", count, GetTickCount() - startCount));

            return true;
        }

        count = 1;

        for (int i = 1; i < maxCheck; i++) {
            ENUM_GMMA_TREND trend = GmmaUtil::getGmmaTrend(
                ema30Buffer[i + 1],
                ema30Buffer[i],
                ema60Buffer[i + 1],
                ema60Buffer[i]
            );

            if (trend == trend0) {
                count++;
            } else {
                break;
            }
        }

        if (trend0 == GMMA_TREND_SELL) {
            count = 0 - count;
        }

        uint elapsed = GetTickCount() - startCount;
        string direction = "NON";

        if (trend0 == GMMA_TREND_BUY) {
            direction = "BUY";
        }

        if (trend0 == GMMA_TREND_SELL) {
            direction = "SELL";
        }

        this.logger.debug(__FUNCTION__, StringFormat("count=%s direction=%s elapsed=%d ms", StringUtil::addSign(count), direction, elapsed));

        return true;
    }

    bool getCrossCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int &count) {
        uint startCount = GetTickCount();
        count = 0;

        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s timeFrame=%d", fromSymbolName, fromTimeFrame));
        if (!this.ensureInitialized(fromSymbolName, fromTimeFrame)) {
            this.logger.error(__FUNCTION__, "initialize failed.");
            return false;
        }

        int len = 1000;
        int bars = Bars(fromSymbolName, fromTimeFrame);
        if (bars <= 1) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d", bars));
            return false;
        }

        int barsToCopy = len + 1;
        if (barsToCopy > bars) barsToCopy = bars;

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();
        int copied30 = CopyBuffer(this.ema30Handle, 0, 0, barsToCopy, ema30Buffer);
        int copied60 = CopyBuffer(this.ema60Handle, 0, 0, barsToCopy, ema60Buffer);
        if (copied30 <= 0 || copied60 <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("fromSymbolName = %s fromTimeFrame = %s", fromSymbolName, EnumToString(fromTimeFrame)));
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied30=%d copied60=%d code=%d", copied30, copied60, GetLastError()));
            return false;
        }

        int maxCheck = len;
        if (copied30 < maxCheck) maxCheck = copied30;
        if (copied60 < maxCheck) maxCheck = copied60;
        if (maxCheck <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("maxCheck <= 0. maxCheck=%d", maxCheck));
            return false;
        }

        bool isPlus0 = this.isPlus(ema30Buffer[0], ema60Buffer[0]);
        count = 1;
        for (int i = 1; i < maxCheck; i++) {
            bool isPlus = this.isPlus(ema30Buffer[i], ema60Buffer[i]);
            if (isPlus == isPlus0) {
                count++;
            } else {
                break;
            }
        }
        if (!isPlus0) {
            count = 0 - count;
        }

        uint elapsed = GetTickCount() - startCount;
        string direction = (count < 0 ? "MINUS" : "PLUS");
        this.logger.debug(__FUNCTION__, StringFormat("count=%s direction=%s elapsed=%d ms", StringUtil::addSign(count), direction, elapsed));
        return true;
    }


    /**
     * EMA30/EMA60値を取得
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param shiftValue シフト
     * @param ema30Value EMA30値
     * @param ema60Value EMA60値
     * @return true: 取得成功
     */
    bool getEmaValues(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        const int shiftValue,
        double &ema30Value,
        double &ema60Value
    ) {
        ema30Value = 0.0;
        ema60Value = 0.0;

        this.logger.debug(__FUNCTION__, StringFormat(
            "symbol=%s timeFrame=%d shift=%d",
            fromSymbolName,
            fromTimeFrame,
            shiftValue
        ));

        if (!this.ensureInitialized(fromSymbolName, fromTimeFrame)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int bars = Bars(fromSymbolName, fromTimeFrame);

        if (bars <= shiftValue) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d shift=%d", bars, shiftValue));

            return false;
        }

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();

        int copied30 = CopyBuffer(this.ema30Handle, 0, shiftValue, 1, ema30Buffer);
        int copied60 = CopyBuffer(this.ema60Handle, 0, shiftValue, 1, ema60Buffer);

        if (copied30 <= 0 || copied60 <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied30=%d copied60=%d code=%d", copied30, copied60, GetLastError()));

            return false;
        }

        ema30Value = ema30Buffer[0];
        ema60Value = ema60Buffer[0];

        this.logger.debug(__FUNCTION__, StringFormat(
            "ema30=%.8f ema60=%.8f",
            ema30Value,
            ema60Value
        ));

        return true;
    }

private:
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    int ema30Handle;
    int ema60Handle;
    GmmaHandlePool *gmmaHandlePool;
    bool isInitialized;
    Logger logger;

    bool ensureInitialized(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        if (this.gmmaHandlePool != NULL) {
            this.gmmaHandlePool.setParameters(30, 60, MODE_EMA, PRICE_CLOSE);
            this.gmmaHandlePool.setTimeframesFromMn1To(fromSymbolName, fromTimeFrame);

            int poolEma30Handle = this.gmmaHandlePool.getEma30Handle(fromTimeFrame);
            int poolEma60Handle = this.gmmaHandlePool.getEma60Handle(fromTimeFrame);
            if (poolEma30Handle == INVALID_HANDLE || poolEma60Handle == INVALID_HANDLE) {
                this.logger.error(__FUNCTION__, StringFormat("handle pool error. ema30Handle=%d ema60Handle=%d code=%d", poolEma30Handle, poolEma60Handle, GetLastError()));
                this.isInitialized = false;
                return false;
            }
            this.ema30Handle = poolEma30Handle;
            this.ema60Handle = poolEma60Handle;
            this.symbolName = fromSymbolName;
            this.timeFrame = fromTimeFrame;
            this.isInitialized = true;
            return true;
        }

        bool needRecreate = false;
        if (!this.isInitialized) needRecreate = true;
        else {
            if (this.symbolName != fromSymbolName) needRecreate = true;
            if (this.timeFrame != fromTimeFrame) needRecreate = true;
            if (this.ema30Handle == INVALID_HANDLE) needRecreate = true;
            if (this.ema60Handle == INVALID_HANDLE) needRecreate = true;
        }
        if (!needRecreate) return true;

        this.logger.debug(__FUNCTION__, StringFormat("recreate. symbol=%s timeFrame=%d", fromSymbolName, fromTimeFrame));
        this.releaseHandles();
        this.ema30Handle = iMA(fromSymbolName, fromTimeFrame, 30, 0, MODE_EMA, PRICE_CLOSE);
        this.ema60Handle = iMA(fromSymbolName, fromTimeFrame, 60, 0, MODE_EMA, PRICE_CLOSE);
        if (this.ema30Handle == INVALID_HANDLE || this.ema60Handle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat("iMA handle error. ema30Handle=%d ema60Handle=%d code=%d", this.ema30Handle, this.ema60Handle, GetLastError()));
            this.releaseHandles();
            this.isInitialized = false;
            return false;
        }
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.isInitialized = true;
        this.logger.debug(__FUNCTION__, StringFormat("initialized. ema30Handle=%d ema60Handle=%d", this.ema30Handle, this.ema60Handle));
        return true;
    }

    void releaseHandles() {
        if (this.gmmaHandlePool != NULL) {
            this.ema30Handle = INVALID_HANDLE;
            this.ema60Handle = INVALID_HANDLE;
            return;
        }
        if (this.ema30Handle != INVALID_HANDLE) {
            IndicatorRelease(this.ema30Handle);
            this.ema30Handle = INVALID_HANDLE;
        }
        if (this.ema60Handle != INVALID_HANDLE) {
            IndicatorRelease(this.ema60Handle);
            this.ema60Handle = INVALID_HANDLE;
        }
    }

    bool isPlus(double ema30, double ema60) {
        return (ema30 >= ema60);
    }
};

#endif // __GMMA_MQH__
