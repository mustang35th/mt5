//+------------------------------------------------------------------+
//|                                               HandlePoolBase.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_HANDLE_POOL_BASE_MQH
#define MSTNG_HANDLE_POOL_BASE_MQH

#include <Mstng\Common\MarketContext.mqh>

/**
 * インジケータのハンドルを時間足ごとに管理する基底クラス（固定8時間足）。
 *
 * 対象時間足:
 * - MN1, W1, D1, H4, H1, M15, M5, M1
 *
 * 派生クラスで行うこと:
 * - createIfNeeded(index): indexの時間足のハンドルを必要に応じて生成する
 * - releaseAt(index): indexの時間足のハンドルを解放する
 */
class HandlePoolBase {
public:
    /**
     * MN1 から指定時間足までのハンドルを生成する。
     *
     * @param fromSymbolName 対象シンボル。
     * @param lastTimeFrame  最終時間足（固定8時間足のみ対応）。
     */
    void setTimeframesFromMn1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
        MarketContext context(fromSymbolName, lastTimeFrame);

        this.setTimeframesFromMn1To(context);
    }

    /**
     * 市場コンテキストを使用してMN1から対象時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成対象の市場コンテキスト。
     */
    void setTimeframesFromMn1To(MarketContext &fromMarketContext) {
        this.ensureMarketContext(fromMarketContext);

        int lastIndex = this.findIndex(fromMarketContext.timeFrame);

        if (lastIndex < 0) {
            Print("Unsupported timeframe: ", EnumToString(fromMarketContext.timeFrame));

            return;
        }

        for (int i = 0; i <= lastIndex; i++) {
            this.createIfNeeded(i);
        }
    }

    /**
     * D1から指定時間足までのハンドルを生成する。
     *
     * @param fromSymbolName 対象シンボル。
     * @param lastTimeFrame 最終時間足。
     */
    void setTimeframesFromD1To(string fromSymbolName, ENUM_TIMEFRAMES lastTimeFrame) {
        MarketContext context(fromSymbolName, lastTimeFrame);

        this.setTimeframesFromD1To(context);
    }

    /**
     * 市場コンテキストを使用してD1から対象時間足までのハンドルを生成する。
     *
     * @param fromMarketContext ハンドル生成対象の市場コンテキスト。
     */
    void setTimeframesFromD1To(MarketContext &fromMarketContext) {
        this.ensureMarketContext(fromMarketContext);

        int startIndex = this.findIndex(PERIOD_D1);
        int lastIndex = this.findIndex(fromMarketContext.timeFrame);

        if (startIndex < 0) {
            Print("D1 timeframe is not configured in this pool.");

            return;
        }

        if (lastIndex < 0) {
            Print("Unsupported timeframe: ", EnumToString(fromMarketContext.timeFrame));

            return;
        }

        if (lastIndex < startIndex) {
            Print("lastTimeFrame must be D1 or lower. lastTimeFrame=", EnumToString(fromMarketContext.timeFrame));

            return;
        }

        for (int i = startIndex; i <= lastIndex; i++) {
            this.createIfNeeded(i);
        }
    }

    /**
     * 全ハンドルを解放する。
     */
    void releaseAll() {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            this.releaseAt(i);
        }
    }

    /**
     * ハンドル生成対象の市場コンテキストを設定する。
     *
     * シンボルが変更された場合は、保持している全ハンドルを解放する。
     *
     * @param fromMarketContext ハンドル生成対象の市場コンテキスト。
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.ensureMarketContext(fromMarketContext);
    }
    
protected:
    enum TimeframeSize {
        TIMEFRAME_SIZE = 8
    };

    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** 対象時間足配列。 */
    ENUM_TIMEFRAMES timeframes[TIMEFRAME_SIZE];

    /**
     * デフォルトコンテキストで初期化する。
     */
    HandlePoolBase() {
        this.initializeBase(Symbol());
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext ハンドル生成対象の市場コンテキスト。
     */
    HandlePoolBase(MarketContext &fromMarketContext) {
        this.initializeBase(fromMarketContext);
    }

    /**
     * リソースを解放する。
     */
    ~HandlePoolBase() {
    }

    /**
     * 市場コンテキストと対象時間足配列を初期化する。
     *
     * @param fromSymbolName 対象シンボル。
     */
    void initializeBase(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        this.initializeBase(context);
    }

    /**
     * 市場コンテキストと対象時間足配列を初期化する。
     *
     * @param fromMarketContext 初期化に使用する市場コンテキスト。
     */
    void initializeBase(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.timeframes[0] = PERIOD_MN1;
        this.timeframes[1] = PERIOD_W1;
        this.timeframes[2] = PERIOD_D1;
        this.timeframes[3] = PERIOD_H4;
        this.timeframes[4] = PERIOD_H1;
        this.timeframes[5] = PERIOD_M15;
        this.timeframes[6] = PERIOD_M5;
        this.timeframes[7] = PERIOD_M1;
    }

    /**
     * シンボルが変わった場合は、全ハンドルを解放して切り替えます。
     *
     * @param fromSymbolName 対象シンボル。
     */
    void ensureSymbol(string fromSymbolName) {
        MarketContext context(fromSymbolName, this.marketContext.timeFrame);

        this.ensureMarketContext(context);
    }

    /**
     * 市場コンテキストが変わった場合は、必要に応じてハンドルを解放して切り替えます。
     *
     * @param fromMarketContext 切り替え先の市場コンテキスト。
     */
    void ensureMarketContext(MarketContext &fromMarketContext) {
        if (this.marketContext.symbolName == fromMarketContext.symbolName) {
            this.marketContext = fromMarketContext;

            return;
        }

        this.releaseAll();
        this.marketContext = fromMarketContext;
    }

    /**
     * 対象8時間足内のインデックスを返す。
     *
     * @param timeFrame 対象時間足。
     * @return インデックス（対象外は -1）。
     */
    int findIndex(ENUM_TIMEFRAMES timeFrame) {
        for (int i = 0; i < TIMEFRAME_SIZE; i++) {
            if (this.timeframes[i] == timeFrame) {

                return i;
            }
        }

        return -1;
    }

    /**
     * ハンドルを解放する（INVALID_HANDLE は何もしない）。
     *
     * @param fromHandle 解放対象ハンドル（解放後 INVALID_HANDLE を設定）。
     */
    void releaseHandle(int &fromHandle) {
        if (fromHandle == INVALID_HANDLE) {

            return;
        }

        IndicatorRelease(fromHandle);
        fromHandle = INVALID_HANDLE;
    }

    /**
     * 派生クラスでハンドル初期化を実装する。
     */
    virtual void createIfNeeded(int index) {
    }

    /**
     * 指定インデックスのリソースを解放する（派生クラス実装）。
     *
     * @param index 時間足インデックス。
     */
    virtual void releaseAt(int index) {
    }

};

#endif  // MSTNG_HANDLE_POOL_BASE_MQH




