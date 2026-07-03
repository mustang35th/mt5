//+------------------------------------------------------------------+
//|                                                         Gmma.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __GMMA_MQH__
#define __GMMA_MQH__

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\GmmaHandlePool.mqh>
#include <Mstng\Oscillator\GmmaUtil.mqh>
#include <Mstng\Util\StringUtil.mqh>

/**
 * EMA30/EMA60差分を用いてGMMAトレンドを評価するための分析クラスです。
 */
class Gmma {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * デフォルトコンストラクタ。
     */
    Gmma() {
        this.logger.setLevel(LOG_INFO);
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = NULL;
        this.isInitialized = false;
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    Gmma(MarketContext &fromMarketContext) {
        this.logger.setLevel(LOG_INFO);
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = NULL;
        this.isInitialized = false;
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * GMMAハンドルプールを指定して初期化する。
     *
     * @param fromGmmaHandlePool GMMAハンドルプール
     */
    Gmma(GmmaHandlePool *fromGmmaHandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = fromGmmaHandlePool;
        this.isInitialized = false;
    }

    /**
     * 市場コンテキストとGMMAハンドルプールを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromGmmaHandlePool GMMAハンドルプール
     */
    Gmma(MarketContext &fromMarketContext, GmmaHandlePool *fromGmmaHandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
        this.gmmaHandlePool = fromGmmaHandlePool;
        this.isInitialized = false;
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * GMMAハンドルプールを設定します。
     *
     * @param fromGmmaHandlePool GMMAハンドルプール
     */
    void setGmmaHandlePool(GmmaHandlePool *fromGmmaHandlePool) {
        this.gmmaHandlePool = fromGmmaHandlePool;
        this.isInitialized = false;
        this.ema30Handle = INVALID_HANDLE;
        this.ema60Handle = INVALID_HANDLE;
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ。
     */
    ~Gmma() {
        if (this.gmmaHandlePool == NULL) {
            this.releaseHandles();
        } else {
            this.ema30Handle = INVALID_HANDLE;
            this.ema60Handle = INVALID_HANDLE;
        }
    }

    /**
     * シンボル/時間足指定でGMMAクロス継続件数を取得する。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @return プラス方向は正、マイナス方向は負。取得失敗時は0
     */
    int getCrossCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        int count = 0;
        if (!this.getCrossCount(fromSymbolName, fromTimeFrame, count)) {
            return 0;
        }
        return count;
    }

    /**
     * 市場コンテキストを指定してGMMAクロス継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @return プラス方向は正、マイナス方向は負の継続件数。取得失敗時は0
     */
    int getCrossCount(MarketContext &fromMarketContext) {
        int count = 0;

        if (!this.getCrossCount(fromMarketContext, count)) {
            return 0;
        }

        return count;
    }

    /**
     * シンボル/時間足指定でGMMAトレンド継続件数を取得する。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @return BUY方向は正、SELL方向は負。取得失敗時は0
     */
    int getTrendCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        int count = 0;

        if (!this.getTrendCount(fromSymbolName, fromTimeFrame, count)) {
            return 0;
        }

        return count;
    }

    /**
     * 市場コンテキストを指定してGMMAトレンド継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @return BUY方向は正、SELL方向は負の継続件数。取得失敗時は0
     */
    int getTrendCount(MarketContext &fromMarketContext) {
        int count = 0;

        if (!this.getTrendCount(fromMarketContext, count)) {
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
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getTrendCount(context, count);
    }

    /**
     * 市場コンテキストを指定してGMMAトレンド継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param count BUY方向は正、SELL方向は負の継続件数
     * @return 取得できた場合は true
     */
    bool getTrendCount(MarketContext &fromMarketContext, int &count) {
        this.initializeMarketContext(fromMarketContext);

        uint startCount = GetTickCount();
        count = 0;

        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s timeFrame=%d", this.marketContext.symbolName, this.marketContext.timeFrame));

        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int len = 1000;
        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

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
            this.logger.error(__FUNCTION__, StringFormat("fromSymbolName = %s fromTimeFrame = %s", this.marketContext.symbolName, EnumToString(this.marketContext.timeFrame)));
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

    /**
     * シンボル名と時間足を指定して GMMA クロス継続件数を取得する。
     *
     * @param fromSymbolName 対象シンボル
     * @param fromTimeFrame 対象時間足
     * @param count 出力: クロス継続件数
     * @return 取得できた場合は true
     */
    bool getCrossCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int &count) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getCrossCount(context, count);
    }

    /**
     * 市場コンテキストを指定してGMMAクロス継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param count プラス方向は正、マイナス方向は負の継続件数
     * @return 取得できた場合は true
     */
    bool getCrossCount(MarketContext &fromMarketContext, int &count) {
        this.initializeMarketContext(fromMarketContext);

        uint startCount = GetTickCount();
        count = 0;

        this.logger.debug(__FUNCTION__, StringFormat("symbol=%s timeFrame=%d", this.marketContext.symbolName, this.marketContext.timeFrame));
        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");
            return false;
        }

        int len = 1000;
        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
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
            this.logger.error(__FUNCTION__, StringFormat("fromSymbolName = %s fromTimeFrame = %s", this.marketContext.symbolName, EnumToString(this.marketContext.timeFrame)));
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
     * @return 取得できた場合は true
     */
    bool getEmaValues(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        const int shiftValue,
        double &ema30Value,
        double &ema60Value
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getEmaValues(context, shiftValue, ema30Value, ema60Value);
    }

    /**
     * 市場コンテキストを指定してEMA30およびEMA60を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param shiftValue シフト
     * @param ema30Value EMA30値
     * @param ema60Value EMA60値
     * @return 取得できた場合は true
     */
    bool getEmaValues(
        MarketContext &fromMarketContext,
        const int shiftValue,
        double &ema30Value,
        double &ema60Value
    ) {
        this.initializeMarketContext(fromMarketContext);

        ema30Value = 0.0;
        ema60Value = 0.0;

        this.logger.debug(__FUNCTION__, StringFormat(
            "symbol=%s timeFrame=%d shift=%d",
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            shiftValue
        ));

        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

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
    /** GMMAハンドルに対応する市場コンテキスト */
    MarketContext handleMarketContext;

    /** 30期間EMAハンドル。 */
    int ema30Handle;
    /** 60期間EMAハンドル。 */
    int ema60Handle;
    /** GMMAハンドルプール。 */
    GmmaHandlePool *gmmaHandlePool;
    /** 初期化状態。 */
    bool isInitialized;
    /** ロガー。 */
    Logger logger;

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * シンボル名と時間足でGMMAの初期化を行う。
     *
     * @param fromSymbolName 対象シンボル
     * @param fromTimeFrame 対象時間足
     * @return 初期化できた場合は true
     */
    bool ensureInitialized(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.ensureInitialized(context);
    }

    /**
     * 市場コンテキストを使用してGMMAハンドルを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @return 初期化できた場合は true
     */
    bool ensureInitialized(MarketContext &fromMarketContext) {
        if (this.gmmaHandlePool != NULL) {
            this.gmmaHandlePool.setParameters(30, 60, MODE_EMA, PRICE_CLOSE);
            this.gmmaHandlePool.setTimeframesFromMn1To(fromMarketContext);

            int poolEma30Handle = this.gmmaHandlePool.getEma30Handle(fromMarketContext.timeFrame);
            int poolEma60Handle = this.gmmaHandlePool.getEma60Handle(fromMarketContext.timeFrame);
            if (poolEma30Handle == INVALID_HANDLE || poolEma60Handle == INVALID_HANDLE) {
                this.logger.error(__FUNCTION__, StringFormat("handle pool error. ema30Handle=%d ema60Handle=%d code=%d", poolEma30Handle, poolEma60Handle, GetLastError()));
                this.isInitialized = false;
                return false;
            }
            this.ema30Handle = poolEma30Handle;
            this.ema60Handle = poolEma60Handle;
            this.handleMarketContext = fromMarketContext;
            this.isInitialized = true;
            return true;
        }

        bool needRecreate = false;
        if (!this.isInitialized) needRecreate = true;
        else {
            if (this.handleMarketContext.symbolName != fromMarketContext.symbolName) needRecreate = true;
            if (this.handleMarketContext.timeFrame != fromMarketContext.timeFrame) needRecreate = true;
            if (this.ema30Handle == INVALID_HANDLE) needRecreate = true;
            if (this.ema60Handle == INVALID_HANDLE) needRecreate = true;
        }
        if (!needRecreate) return true;

        this.logger.debug(__FUNCTION__, StringFormat("recreate. symbol=%s timeFrame=%d", fromMarketContext.symbolName, fromMarketContext.timeFrame));
        this.releaseHandles();
        this.ema30Handle = iMA(fromMarketContext.symbolName, fromMarketContext.timeFrame, 30, 0, MODE_EMA, PRICE_CLOSE);
        this.ema60Handle = iMA(fromMarketContext.symbolName, fromMarketContext.timeFrame, 60, 0, MODE_EMA, PRICE_CLOSE);
        if (this.ema30Handle == INVALID_HANDLE || this.ema60Handle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat("iMA handle error. ema30Handle=%d ema60Handle=%d code=%d", this.ema30Handle, this.ema60Handle, GetLastError()));
            this.releaseHandles();
            this.isInitialized = false;
            return false;
        }
        this.handleMarketContext = fromMarketContext;
        this.isInitialized = true;
        this.logger.debug(__FUNCTION__, StringFormat("initialized. ema30Handle=%d ema60Handle=%d", this.ema30Handle, this.ema60Handle));
        return true;
    }

    /**
     * GMMA用のハンドルを解放する。
     */
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

    /**
     * EMA30/EMA60の差分方向を比較する。
     *
     * @param ema30 EMA30値
     * @param ema60 EMA60値
     * @return EMA30 >= EMA60 のとき true
     */
    bool isPlus(double ema30, double ema60) {
        return (ema30 >= ema60);
    }
};

#endif // __GMMA_MQH__






