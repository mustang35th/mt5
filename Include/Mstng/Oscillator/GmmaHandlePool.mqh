//+------------------------------------------------------------------+
//|                                               GmmaHandlePool.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_GMMA_HANDLE_POOL_MQH
#define MSTNG_GMMA_HANDLE_POOL_MQH

#include <Mstng\Oscillator\HandlePoolBase.mqh>

/**
 * GMMA（本実装では EMA30 / EMA60）のハンドルを時間足ごとに管理するクラスです（固定8時間足）。
 *
 * 対象時間足:
 * - MN1, W1, D1, H4, H1, M15, M5, M1
 *
 * 管理対象:
 * - iMA(..., 30, MODE_EMA, PRICE_CLOSE)
 * - iMA(..., 60, MODE_EMA, PRICE_CLOSE)
 *
 * - setTimeframesFromMn1To(fromSymbolName, lastTimeFrame): MN1 から指定時間足まで生成
 * - getEma30Handle(timeFrame) / getEma60Handle(timeFrame): ハンドル取得（未生成なら生成）
 * - setParameters(...): パラメータ変更（必要時に全解放）
 * - releaseAll(): 全解放
 */
class GmmaHandlePool : public HandlePoolBase {


public:
    /**
     * 空のコンストラクタ（デフォルト設定）
     *
     * 初期値:
     * - ema30Period   = 30
     * - ema60Period   = 60
     * - maMethod      = MODE_EMA
     * - appliedPrice  = PRICE_CLOSE
     *
     * symbolName はカレントシンボル（Symbol()）を設定します。
     */
    GmmaHandlePool() {
        this.initialize(Symbol(), 30, 60, MODE_EMA, PRICE_CLOSE);
    }

    /**
     * コンストラクタ
     *
     * @param fromSymbolName   対象シンボル
     * @param fromEma30Period  EMA30 の期間
     * @param fromEma60Period  EMA60 の期間
     * @param fromMaMethod     MA種別（通常 MODE_EMA）
     * @param fromAppliedPrice 適用価格
     */
    GmmaHandlePool(string fromSymbolName,
                   int fromEma30Period,
                   int fromEma60Period,
                   ENUM_MA_METHOD fromMaMethod,
                   ENUM_APPLIED_PRICE fromAppliedPrice) {
        this.initialize(fromSymbolName, fromEma30Period, fromEma60Period, fromMaMethod, fromAppliedPrice);
    }

    /**
     * デストラクタ（念のため解放）
     */
    ~GmmaHandlePool() {
        this.releaseAll();
    }

    /**
     * MN1 から指定時間足までのハンドルを生成します。
     *
     * @param fromSymbolName 対象シンボル（変更時は全ハンドルを解放して再作成します）
     * @param lastTimeFrame  生成対象の終端時間足（固定8時間足のみ対応）
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
     * D1 から指定時間足までのハンドルを生成します。
     *
     * 例:
     * - lastTimeFrame=PERIOD_H1 -> D1, H4, H1
     * - lastTimeFrame=PERIOD_M1 -> D1, H4, H1, M15, M5, M1
     *
     * @param fromSymbolName 対象シンボル（変更時は全ハンドルを解放して再作成します）
     * @param lastTimeFrame  生成対象の終端時間足（D1以下、固定8時間足のみ対応）
     */
    void setTimeframesFromD1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
        this.ensureSymbol(fromSymbolName);

        int startIndex = this.findIndex(PERIOD_D1);
        int lastIndex  = this.findIndex(lastTimeFrame);

        if (startIndex < 0) {
            Print("D1 timeframe is not configured in this pool.");
            return;
        }

        if (lastIndex < 0) {
            Print("Unsupported timeframe: ", EnumToString(lastTimeFrame));
            return;
        }

        // lastTimeFrame は D1 以下である必要があります（MN1/W1 は不可）
        if (lastIndex < startIndex) {
            Print("lastTimeFrame must be D1 or lower. lastTimeFrame=", EnumToString(lastTimeFrame));
            return;
        }

        for (int i = startIndex; i <= lastIndex; i++) {
            this.createIfNeeded(i);
        }
    }

    /**
     * パラメータを設定します。
     *
     * 既存ハンドルは「パラメータが変わった場合のみ」全解放します。
     */
    void setParameters(int fromEma30Period,
                       int fromEma60Period,
                       ENUM_MA_METHOD fromMaMethod,
                       ENUM_APPLIED_PRICE fromAppliedPrice) {
        bool needReset = false;

        if (this.ema30Period != fromEma30Period) {
            needReset = true;
        }

        if (this.ema60Period != fromEma60Period) {
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

        this.ema30Period = fromEma30Period;
        this.ema60Period = fromEma60Period;
        this.maMethod = fromMaMethod;
        this.appliedPrice = fromAppliedPrice;
    }

    /**
     * EMA30 ハンドルを取得します（未生成なら生成）。
     */
    int getEma30Handle(ENUM_TIMEFRAMES timeFrame) {
        int index = this.findIndex(timeFrame);

        if (index < 0) {
            Print("Unsupported timeframe: ", EnumToString(timeFrame));

            return INVALID_HANDLE;
        }

        this.createIfNeeded(index);

        return this.ema30Handles[index];
    }

    /**
     * EMA60 ハンドルを取得します（未生成なら生成）。
     */
    int getEma60Handle(ENUM_TIMEFRAMES timeFrame) {
        int index = this.findIndex(timeFrame);

        if (index < 0) {
            Print("Unsupported timeframe: ", EnumToString(timeFrame));

            return INVALID_HANDLE;
        }

        this.createIfNeeded(index);

        return this.ema60Handles[index];
    }

    /**
     * 全ハンドルを解放します。
     */
    void releaseAll() {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            this.releaseHandle(this.ema30Handles[i]);
            this.releaseHandle(this.ema60Handles[i]);
        }
    }

protected:
    virtual void createIfNeeded(int index) {
        if (index < 0 || index >= TIMEFRAME_SIZE) {

            return;
        }

        if (this.ema30Handles[index] != INVALID_HANDLE && this.ema60Handles[index] != INVALID_HANDLE) {

            return;
        }

        ENUM_TIMEFRAMES timeFrame = this.timeframes[index];

        int createdEma30Handle = iMA(this.symbolName, timeFrame, this.ema30Period, 0, this.maMethod, this.appliedPrice);
        int createdEma60Handle = iMA(this.symbolName, timeFrame, this.ema60Period, 0, this.maMethod, this.appliedPrice);

        if (createdEma30Handle == INVALID_HANDLE || createdEma60Handle == INVALID_HANDLE) {
            this.releaseHandle(createdEma30Handle);
            this.releaseHandle(createdEma60Handle);

            Print("iMA failed. timeframe=", EnumToString(timeFrame), " err=", GetLastError());

            return;
        }

        this.ema30Handles[index] = createdEma30Handle;
        this.ema60Handles[index] = createdEma60Handle;
    }

    void releaseHandle(int &fromHandle) {
        if (fromHandle == INVALID_HANDLE) {

            return;
        }

        IndicatorRelease(fromHandle);
        fromHandle = INVALID_HANDLE;
    }
    
private:
    int ema30Period;
    int ema60Period;
    ENUM_MA_METHOD maMethod;
    ENUM_APPLIED_PRICE appliedPrice;
    int ema30Handles[TIMEFRAME_SIZE];
    int ema60Handles[TIMEFRAME_SIZE];
    
    void initialize(string fromSymbolName,
                    int fromEma30Period,
                    int fromEma60Period,
                    ENUM_MA_METHOD fromMaMethod,
                    ENUM_APPLIED_PRICE fromAppliedPrice) {
        this.symbolName = fromSymbolName;

        this.ema30Period = fromEma30Period;
        this.ema60Period = fromEma60Period;
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
            this.ema30Handles[i] = INVALID_HANDLE;
            this.ema60Handles[i] = INVALID_HANDLE;
        }
    }

    void ensureSymbol(string fromSymbolName) {
        if (this.symbolName == fromSymbolName) {

            return;
        }

        this.releaseAll();
        this.symbolName = fromSymbolName;
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

#endif // MSTNG_GMMA_HANDLE_POOL_MQH
