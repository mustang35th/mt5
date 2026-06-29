//+------------------------------------------------------------------+
//|                                             AverageTrueRange.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_AVERAGE_TRUE_RANGE_MQH
#define MSTNG_AVERAGE_TRUE_RANGE_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Oscillator\AverageTrueRangeHandlePool.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * ATR取得
 */
class AverageTrueRange {
public:
    /** ATR価格値 */
    double atrValue;

    /** ATR pips値 */
    double atrPips;

    /**
     * コンストラクタ
     */
    AverageTrueRange() {
        this.averageTrueRangeHandlePool = NULL;
        this.handle = INVALID_HANDLE;
        this.atrValue = 0.0;
        this.atrPips = 0.0;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * コンストラクタ
     *
     * @param fromAverageTrueRangeHandlePool ATRハンドルプール
     */
    AverageTrueRange(AverageTrueRangeHandlePool *fromAverageTrueRangeHandlePool) {
        this.averageTrueRangeHandlePool = fromAverageTrueRangeHandlePool;
        this.handle = INVALID_HANDLE;
        this.atrValue = 0.0;
        this.atrPips = 0.0;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * ATRハンドルプール設定
     *
     * @param fromAverageTrueRangeHandlePool ATRハンドルプール
     */
    void setAverageTrueRangeHandlePool(AverageTrueRangeHandlePool *fromAverageTrueRangeHandlePool) {
        this.averageTrueRangeHandlePool = fromAverageTrueRangeHandlePool;
        this.handle = INVALID_HANDLE;
    }

    /**
     * ATR価格値を取得
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param shiftValue シフト
     * @param atrValueResult ATR価格値
     * @return true: 取得成功
     */
    bool getAtrValue(
        const string symbolNameValue,
        const ENUM_TIMEFRAMES timeFrameValue,
        const int shiftValue,
        double &atrValueResult
    ) {
        MarketContext context(symbolNameValue, timeFrameValue);

        return this.getAtrValue(context, shiftValue, atrValueResult);
    }

    /**
     * 市場コンテキストを使用してATR価格値を取得する。
     *
     * @param fromMarketContext ATR取得対象の市場コンテキスト
     * @param shiftValue シフト
     * @param atrValueResult ATR価格値
     * @return true: 取得成功
     */
    bool getAtrValue(
        MarketContext &fromMarketContext,
        const int shiftValue,
        double &atrValueResult
    ) {
        this.logger.setMarketContext(fromMarketContext);
        atrValueResult = 0.0;

        if (!this.ensureInitialized(fromMarketContext)) {
            this.logger.error(__FUNCTION__, "failed to initialize ATR handle");

            return false;
        }

        double buffer[];
        ArraySetAsSeries(buffer, true);

        ResetLastError();
        int copied = CopyBuffer(this.handle, 0, shiftValue, 1, buffer);

        if (copied <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer(ATR) error. code=%d", GetLastError()));

            return false;
        }

        atrValueResult = buffer[0];
        this.atrValue = atrValueResult;
        this.atrPips = this.convertPriceToPips(fromMarketContext.symbolName, atrValueResult);

        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "symbol=%s timeFrame=%s shift=%d atrValue=%.8f atrPips=%.2f",
                fromMarketContext.symbolName,
                fromMarketContext.timeFrameLabel,
                shiftValue,
                this.atrValue,
                this.atrPips
            )
        );

        return true;
    }

    /**
     * ATR pips値を取得
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param shiftValue シフト
     * @param atrPipsResult ATR pips値
     * @return true: 取得成功
     */
    bool getAtrPips(
        const string symbolNameValue,
        const ENUM_TIMEFRAMES timeFrameValue,
        const int shiftValue,
        double &atrPipsResult
    ) {
        MarketContext context(symbolNameValue, timeFrameValue);

        return this.getAtrPips(context, shiftValue, atrPipsResult);
    }

    /**
     * 市場コンテキストを使用してATRのpips値を取得する。
     *
     * @param fromMarketContext ATR取得対象の市場コンテキスト
     * @param shiftValue シフト
     * @param atrPipsResult ATR pips値
     * @return true: 取得成功
     */
    bool getAtrPips(
        MarketContext &fromMarketContext,
        const int shiftValue,
        double &atrPipsResult
    ) {
        atrPipsResult = 0.0;

        double atrValueResult = 0.0;

        if (!this.getAtrValue(fromMarketContext, shiftValue, atrValueResult)) {
            return false;
        }

        atrPipsResult = this.atrPips;

        return true;
    }

    /**
     * pips文字列を取得
     *
     * @param digitsValue 小数桁数
     * @return pips文字列
     */
    string getAtrPipsText(const int digitsValue = 1) {
        return DoubleToString(this.atrPips, digitsValue);
    }

private:
    /** ATRハンドルプール */
    AverageTrueRangeHandlePool *averageTrueRangeHandlePool;

    /** ハンドル */
    int handle;

    /** ロガー */
    Logger logger;

    /**
     * 初期化確認
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @return true: 初期化成功
     */
    bool ensureInitialized(const string symbolNameValue, const ENUM_TIMEFRAMES timeFrameValue) {
        MarketContext context(symbolNameValue, timeFrameValue);

        return this.ensureInitialized(context);
    }

    /**
     * 市場コンテキストを使用して初期化を確認する。
     *
     * @param fromMarketContext 初期化対象の市場コンテキスト
     * @return true: 初期化成功
     */
    bool ensureInitialized(MarketContext &fromMarketContext) {
        if (this.averageTrueRangeHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "averageTrueRangeHandlePool is NULL");

            return false;
        }

        int pooledHandle = this.averageTrueRangeHandlePool.getHandle(fromMarketContext.timeFrame);

        if (pooledHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "failed to get ATR handle from pool. symbol=%s timeFrame=%s code=%d",
                    fromMarketContext.symbolName,
                    fromMarketContext.timeFrameLabel,
                    GetLastError()
                )
            );

            return false;
        }

        this.handle = pooledHandle;

        return true;
    }

    /**
     * 価格値をpipsへ変換
     *
     * @param symbolNameValue シンボル名
     * @param priceValue 価格値
     * @return pips値
     */
    double convertPriceToPips(const string symbolNameValue, const double priceValue) {
        double pointPerPip = this.getPointPerPip(symbolNameValue);

        if (pointPerPip <= 0.0) {
            return 0.0;
        }

        return priceValue / pointPerPip;
    }

    /**
     * 1pips相当の価格幅を取得
     *
     * @param symbolNameValue シンボル名
     * @return 1pips相当の価格幅
     */
    double getPointPerPip(const string symbolNameValue) {
        int digits = (int)SymbolInfoInteger(symbolNameValue, SYMBOL_DIGITS);
        double point = SymbolInfoDouble(symbolNameValue, SYMBOL_POINT);

        if (digits == 3 || digits == 5) {
            return point * 10.0;
        }

        return point;
    }
};

#endif // MSTNG_AVERAGE_TRUE_RANGE_MQH
