//+------------------------------------------------------------------+
//|                                            Ema200HandlePool.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_EMA200_HANDLE_POOL_MQH
#define MSTNG_EMA200_HANDLE_POOL_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\HandlePoolBase.mqh>

/**
 * EMA200のハンドルを時間足ごとに管理するクラスです。
 *
 * 対象時間足:
 * - MN1, W1, D1, H4, H1, M15, M5, M1
 *
 * 管理対象:
 * - iMA(..., 200, MODE_EMA, PRICE_CLOSE)
 */
class Ema200HandlePool : public HandlePoolBase {
public:
    /**
     * コンストラクタ
     */
    Ema200HandlePool() {
        this.initialize(Symbol(), 200, MODE_EMA, PRICE_CLOSE);
    }

    /**
     * コンストラクタ
     *
     * @param fromSymbolName 対象シンボル
     * @param fromEmaPeriod EMA期間
     * @param fromMaMethod MA種別
     * @param fromAppliedPrice 適用価格
     */
    Ema200HandlePool(string fromSymbolName,
                     int fromEmaPeriod,
                     ENUM_MA_METHOD fromMaMethod,
                     ENUM_APPLIED_PRICE fromAppliedPrice) {
        this.initialize(fromSymbolName, fromEmaPeriod, fromMaMethod, fromAppliedPrice);
    }

    /**
     * デストラクタ
     */
    ~Ema200HandlePool() {
        this.releaseAll();
    }

    /**
     * MN1 から指定時間足までのハンドルを生成します。
     *
     * @param fromSymbolName 対象シンボル
     * @param lastTimeFrame 生成対象の終端時間足
     */
    void setTimeframesFromMn1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
        this.ensureSymbol(fromSymbolName);

        int lastIndex = this.findIndex(lastTimeFrame);

        if (lastIndex < 0) {
            Print("Unsupported timeframe: ", EnumToString(lastTimeFrame));

            return;
        }

        for (int i = 0; i <= lastIndex; i++) {
            this.createIfNeeded(i);
        }
    }

    /**
     * 市場コンテキストを使用してMN1から指定時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void setTimeframesFromMn1To(MarketContext &fromMarketContext) {
        this.setTimeframesFromMn1To(fromMarketContext.symbolName, fromMarketContext.timeFrame);
    }

    /**
     * D1 から指定時間足までのハンドルを生成します。
     *
     * @param fromSymbolName 対象シンボル
     * @param lastTimeFrame 生成対象の終端時間足
     */
    void setTimeframesFromD1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
        this.ensureSymbol(fromSymbolName);

        int startIndex = this.findIndex(PERIOD_D1);
        int lastIndex = this.findIndex(lastTimeFrame);

        if (startIndex < 0) {
            Print("D1 timeframe is not configured in this pool.");

            return;
        }

        if (lastIndex < 0) {
            Print("Unsupported timeframe: ", EnumToString(lastTimeFrame));

            return;
        }

        if (lastIndex < startIndex) {
            Print("lastTimeFrame must be D1 or lower. lastTimeFrame=", EnumToString(lastTimeFrame));

            return;
        }

        for (int i = startIndex; i <= lastIndex; i++) {
            this.createIfNeeded(i);
        }
    }

    /**
     * 市場コンテキストを使用してD1から指定時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void setTimeframesFromD1To(MarketContext &fromMarketContext) {
        this.setTimeframesFromD1To(fromMarketContext.symbolName, fromMarketContext.timeFrame);
    }

    /**
     * パラメータを設定します。
     *
     * 既存ハンドルはパラメータが変わった場合のみ全解放します。
     *
     * @param fromEmaPeriod EMA期間
     * @param fromMaMethod MA種別
     * @param fromAppliedPrice 適用価格
     */
    void setParameters(int fromEmaPeriod,
                       ENUM_MA_METHOD fromMaMethod,
                       ENUM_APPLIED_PRICE fromAppliedPrice) {
        bool needReset = false;

        if (this.emaPeriod != fromEmaPeriod) {
            needReset = true;
        }

        if (this.maMethod != fromMaMethod) {
            needReset = true;
        }

        if (this.appliedPrice != fromAppliedPrice) {
            needReset = true;
        }

        if (!needReset) {

            return;
        }

        this.releaseAll();

        this.emaPeriod = fromEmaPeriod;
        this.maMethod = fromMaMethod;
        this.appliedPrice = fromAppliedPrice;
    }

    /**
     * EMA200ハンドルを取得します。
     *
     * 未生成の場合は生成します。
     *
     * @param timeFrame 対象時間足
     * @return EMA200ハンドル
     */
    int getEma200Handle(ENUM_TIMEFRAMES timeFrame) {
        int index = this.findIndex(timeFrame);

        if (index < 0) {
            Print("Unsupported timeframe: ", EnumToString(timeFrame));

            return INVALID_HANDLE;
        }

        this.createIfNeeded(index);

        return this.ema200Handles[index];
    }

    /**
     * 全ハンドルを解放します。
     */
    void releaseAll() {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            this.releaseHandle(this.ema200Handles[i]);
        }
    }

protected:
    /**
     * 指定indexのハンドルを必要に応じて生成します。
     *
     * @param index 時間足index
     */
    virtual void createIfNeeded(int index) {
        if (index < 0 || index >= TIMEFRAME_SIZE) {

            return;
        }

        if (this.ema200Handles[index] != INVALID_HANDLE) {

            return;
        }

        ENUM_TIMEFRAMES timeFrame = this.timeframes[index];

        int createdHandle = iMA(this.symbolName, timeFrame, this.emaPeriod, 0, this.maMethod, this.appliedPrice);

        if (createdHandle == INVALID_HANDLE) {
            Print("iMA EMA200 failed. timeframe=", EnumToString(timeFrame), " err=", GetLastError());

            return;
        }

        this.ema200Handles[index] = createdHandle;
    }

    /**
     * 指定indexのハンドルを解放します。
     *
     * @param index 時間足index
     */
    virtual void releaseAt(int index) {
        if (index < 0 || index >= TIMEFRAME_SIZE) {

            return;
        }

        this.releaseHandle(this.ema200Handles[index]);
    }

private:
    int emaPeriod;
    ENUM_MA_METHOD maMethod;
    ENUM_APPLIED_PRICE appliedPrice;
    int ema200Handles[TIMEFRAME_SIZE];

    /**
     * 初期化します。
     *
     * @param fromSymbolName 対象シンボル
     * @param fromEmaPeriod EMA期間
     * @param fromMaMethod MA種別
     * @param fromAppliedPrice 適用価格
     */
    void initialize(string fromSymbolName,
                    int fromEmaPeriod,
                    ENUM_MA_METHOD fromMaMethod,
                    ENUM_APPLIED_PRICE fromAppliedPrice) {
        this.symbolName = fromSymbolName;

        this.emaPeriod = fromEmaPeriod;
        this.maMethod = fromMaMethod;
        this.appliedPrice = fromAppliedPrice;

        this.timeframes[0] = PERIOD_MN1;
        this.timeframes[1] = PERIOD_W1;
        this.timeframes[2] = PERIOD_D1;
        this.timeframes[3] = PERIOD_H4;
        this.timeframes[4] = PERIOD_H1;
        this.timeframes[5] = PERIOD_M15;
        this.timeframes[6] = PERIOD_M5;
        this.timeframes[7] = PERIOD_M1;

        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            this.ema200Handles[i] = INVALID_HANDLE;
        }
    }
};

#endif // MSTNG_EMA200_HANDLE_POOL_MQH
