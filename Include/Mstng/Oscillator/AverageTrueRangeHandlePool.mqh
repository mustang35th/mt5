//+------------------------------------------------------------------+
//|                                    AverageTrueRangeHandlePool.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_AVERAGE_TRUE_RANGE_HANDLE_POOL_MQH
#define MSTNG_AVERAGE_TRUE_RANGE_HANDLE_POOL_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\HandlePoolBase.mqh>

/**
 * ATR のハンドルを時間足ごとに管理
 */
class AverageTrueRangeHandlePool : public HandlePoolBase {
public:
    /**
     * コンストラクタ
     */
    AverageTrueRangeHandlePool() {
        // 初期化
        this.initialize(Symbol(), 14);
    }

    /**
     * コンストラクタ
     *
     * @param fromSymbolName 対象シンボル
     * @param fromPeriod ATR期間
     */
    AverageTrueRangeHandlePool(const string fromSymbolName, const int fromPeriod) {
        // 初期化
        this.initialize(fromSymbolName, fromPeriod);
    }

    /**
     * MarketContextを使用して初期化する。
     *
     * @param fromMarketContext 対象の市場コンテキスト
     * @param fromPeriod ATR期間
     */
    AverageTrueRangeHandlePool(MarketContext &fromMarketContext, const int fromPeriod) {
        this.initialize(fromMarketContext, fromPeriod);
    }

    /**
     * デストラクタ
     */
    ~AverageTrueRangeHandlePool() {
        // 全解放
        this.releaseAll();
    }

    /**
     * ハンドル生成対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext ハンドル生成対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.ensureMarketContext(fromMarketContext);
    }

    /**
     * MN1 から指定時間足までのハンドルを生成
     *
     * @param fromSymbolName 対象シンボル
     * @param lastTimeFrame 最終時間足
     */
    void setTimeframesFromMn1To(const string fromSymbolName, const ENUM_TIMEFRAMES lastTimeFrame) {
        MarketContext context(fromSymbolName, lastTimeFrame);

        this.setTimeframesFromMn1To(context);
    }

    /**
     * 市場コンテキストを使用してMN1から指定時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void setTimeframesFromMn1To(MarketContext &fromMarketContext) {
        HandlePoolBase::setTimeframesFromMn1To(fromMarketContext);
    }

    /**
     * D1 から指定時間足までのハンドルを生成
     *
     * @param fromSymbolName 対象シンボル
     * @param lastTimeFrame 最終時間足
     */
    void setTimeframesFromD1To(const string fromSymbolName, const ENUM_TIMEFRAMES lastTimeFrame) {
        MarketContext context(fromSymbolName, lastTimeFrame);

        this.setTimeframesFromD1To(context);
    }

    /**
     * 市場コンテキストを使用してD1から指定時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト
     */
    void setTimeframesFromD1To(MarketContext &fromMarketContext) {
        HandlePoolBase::setTimeframesFromD1To(fromMarketContext);
    }

    /**
     * 指定時間足のハンドルを取得
     *
     * @param timeFrame 対象時間足
     * @return ハンドル
     */
    int getHandle(const ENUM_TIMEFRAMES timeFrame) {
        int index = this.findIndex(timeFrame);

        if (index < 0) {
            Print("Unsupported timeframe: ", EnumToString(timeFrame));

            return INVALID_HANDLE;
        }

        this.createIfNeeded(index);

        return this.handles[index];
    }

    /**
     * 全ハンドルを解放
     */
    void releaseAll() {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            int currentHandle = this.handles[i];

            if (currentHandle == INVALID_HANDLE) {
                continue;
            }

            IndicatorRelease(currentHandle);
            this.handles[i] = INVALID_HANDLE;
        }
    }

protected:
    /**
     * 必要に応じてハンドルを生成
     *
     * @param index インデックス
     */
    virtual void createIfNeeded(int index) {
        if (index < 0 || index >= TIMEFRAME_SIZE) {
            return;
        }

        if (this.handles[index] != INVALID_HANDLE) {
            return;
        }

        ENUM_TIMEFRAMES timeFrame = this.timeframes[index];
        int createdHandle = iATR(this.marketContext.symbolName, timeFrame, this.period);

        if (createdHandle == INVALID_HANDLE) {
            Print("iATR failed. timeframe=", EnumToString(timeFrame), " err=", GetLastError());

            return;
        }

        this.handles[index] = createdHandle;
    }

private:
    /** ATR期間 */
    int period;

    /** ハンドル配列 */
    int handles[TIMEFRAME_SIZE];

    /**
     * 初期化
     *
     * @param fromSymbolName 対象シンボル
     * @param fromPeriod ATR期間
     */
    void initialize(const string fromSymbolName, const int fromPeriod) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        this.initialize(context, fromPeriod);
    }

    /**
     * MarketContextを使用して初期化する。
     *
     * @param fromMarketContext 対象の市場コンテキスト
     * @param fromPeriod ATR期間
     */
    void initialize(MarketContext &fromMarketContext, const int fromPeriod) {
        this.initializeBase(fromMarketContext);
        this.period = fromPeriod;

        this.timeframes[0] = PERIOD_MN1;
        this.timeframes[1] = PERIOD_W1;
        this.timeframes[2] = PERIOD_D1;
        this.timeframes[3] = PERIOD_H4;
        this.timeframes[4] = PERIOD_H1;
        this.timeframes[5] = PERIOD_M15;
        this.timeframes[6] = PERIOD_M5;
        this.timeframes[7] = PERIOD_M1;

        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            this.handles[i] = INVALID_HANDLE;
        }
    }
};

#endif // MSTNG_AVERAGE_TRUE_RANGE_HANDLE_POOL_MQH
