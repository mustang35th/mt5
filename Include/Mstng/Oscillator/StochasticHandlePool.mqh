//+------------------------------------------------------------------+
//|                                         StochasticHandlePool.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_STOCHASTIC_HANDLE_POOL_MQH
#define MSTNG_STOCHASTIC_HANDLE_POOL_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\HandlePoolBase.mqh>

/**
 * Stochastic のハンドルを時間足ごとに管理するクラスです（固定8時間足）。
 *
 * 対象時間足:
 * - MN1, W1, D1, H4, H1, M15, M5, M1
 *
 * 使い方:
 * - setAllTimeframes(): 対象8時間足のハンドルを全て生成
 * - setTimeframesFromMn1To(lastTimeFrame): MN1 から指定時間足まで生成
 * - getHandle(timeFrame): 指定時間足のハンドルを取得（未生成なら生成）
 * - releaseAll(): 全解放
 */
class StochasticHandlePool : public HandlePoolBase {
public:
    /**
     * 空のコンストラクタ（デフォルト設定）
     *
     * 初期値:
     * - kPeriod    = 5
     * - dPeriod    = 3
     * - slowing    = 3
     * - maMethod   = MODE_SMA
     * - priceField = STO_LOWHIGH
     *
     * symbolName はカレントシンボル（Symbol()）を設定します。
     */
    StochasticHandlePool() {
        this.initialize(Symbol(), 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    }

    /**
     * コンストラクタ
     *
     * @param fromSymbolName 対象シンボル
     * @param fromKPeriod    %K期間
     * @param fromDPeriod    %D期間
     * @param fromSlowing    スローイング
     * @param fromMaMethod   平滑化のMA種別
     * @param fromPriceField 価格フィールド
     */
    StochasticHandlePool(string fromSymbolName,
                         int fromKPeriod,
                         int fromDPeriod,
                         int fromSlowing,
                         ENUM_MA_METHOD fromMaMethod,
                         ENUM_STO_PRICE fromPriceField) {
        this.initialize(fromSymbolName, fromKPeriod, fromDPeriod, fromSlowing, fromMaMethod, fromPriceField);
    }

    /**
     * MarketContextを使用して初期化する。
     *
     * @param fromMarketContext 対象の市場コンテキスト
     * @param fromKPeriod %K期間
     * @param fromDPeriod %D期間
     * @param fromSlowing スローイング
     * @param fromMaMethod MA種別
     * @param fromPriceField 価格フィールド
     */
    StochasticHandlePool(
        MarketContext &fromMarketContext,
        int fromKPeriod,
        int fromDPeriod,
        int fromSlowing,
        ENUM_MA_METHOD fromMaMethod,
        ENUM_STO_PRICE fromPriceField
    ) {
        this.initialize(fromMarketContext, fromKPeriod, fromDPeriod, fromSlowing, fromMaMethod, fromPriceField);
    }

    /**
     * デストラクタ（念のため解放）
     */
    ~StochasticHandlePool() {
        this.releaseAll();
    }

    /**
     * MN1 から指定時間足までのハンドルを生成します。
     *
     * 例:
     * - lastTimeFrame=H1  -> MN1, W1, D1, H4, H1 を生成
     * - lastTimeFrame=M5  -> MN1, W1, D1, H4, H1, M15, M5 を生成
     *
     * @param lastTimeFrame 生成対象の終端時間足（固定8時間足のみ対応）
     */
    void setTimeframesFromMn1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
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
     * D1 から指定した時間足までの Stochastic ハンドルを初期化します。
     *
     * 例:
     * - lastTimeFrame=H1 -> D1, H4, H1
     * - lastTimeFrame=M1 -> D1, H4, H1, M15, M5, M1
     *
     * @param fromSymbolName シンボル名（変更時は内部ハンドルを全解放して作り直します）
     * @param lastTimeFrame  最も小さい時間足（D1以下）
     */
    void setTimeframesFromD1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
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
     * 指定時間足のハンドルを返します（未生成なら生成）。
     *
     * @param timeFrame 対象時間足（固定8時間足のみ対応）
     * @return ハンドル（対象外 or 失敗時 INVALID_HANDLE）
     */
    int getHandle(ENUM_TIMEFRAMES timeFrame) {
        int index = this.findIndex(timeFrame);

        if (index < 0) {
            Print("Unsupported timeframe: ", EnumToString(timeFrame));

            return INVALID_HANDLE;
        }

        this.createIfNeeded(index);

        return this.handles[index];
    }

    /**
     * 全ハンドルを解放します。
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
    virtual void createIfNeeded(int index) {
        if (index < 0 || index >= TIMEFRAME_SIZE) {

            return;
        }

        if (this.handles[index] != INVALID_HANDLE) {

            return;
        }

        ENUM_TIMEFRAMES timeFrame = this.timeframes[index];

        int createdHandle = iStochastic(this.marketContext.symbolName, timeFrame, this.kPeriod, this.dPeriod, this.slowing, this.maMethod, this.priceField);

        if (createdHandle == INVALID_HANDLE) {
            Print("iStochastic failed. timeframe=", EnumToString(timeFrame), " err=", GetLastError());

            return;
        }

        this.handles[index] = createdHandle;
    }

private:
    int kPeriod;
    int dPeriod;
    int slowing;
    ENUM_MA_METHOD maMethod;
    ENUM_STO_PRICE priceField;
    int handles[TIMEFRAME_SIZE];

    /**
     * 初期化処理を共通化します。
     */
    void initialize(string fromSymbolName,
                    int fromKPeriod,
                    int fromDPeriod,
                    int fromSlowing,
                    ENUM_MA_METHOD fromMaMethod,
                    ENUM_STO_PRICE fromPriceField) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        this.initialize(context, fromKPeriod, fromDPeriod, fromSlowing, fromMaMethod, fromPriceField);
    }

    /**
     * MarketContextを使用して初期化する。
     *
     * @param fromMarketContext 対象の市場コンテキスト
     * @param fromKPeriod %K期間
     * @param fromDPeriod %D期間
     * @param fromSlowing スローイング
     * @param fromMaMethod MA種別
     * @param fromPriceField 価格フィールド
     */
    void initialize(
        MarketContext &fromMarketContext,
        int fromKPeriod,
        int fromDPeriod,
        int fromSlowing,
        ENUM_MA_METHOD fromMaMethod,
        ENUM_STO_PRICE fromPriceField
    ) {
        this.initializeBase(fromMarketContext);

        this.kPeriod = fromKPeriod;
        this.dPeriod = fromDPeriod;
        this.slowing = fromSlowing;
        this.maMethod = fromMaMethod;
        this.priceField = fromPriceField;

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

    int findIndex(ENUM_TIMEFRAMES timeFrame) {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            if (this.timeframes[i] == timeFrame) {

                return i;
            }
        }

        return -1;
    }
};

#endif // MSTNG_STOCHASTIC_HANDLE_POOL_MQH




