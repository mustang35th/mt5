//+------------------------------------------------------------------+
//|                                                         Gmma.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __GMMA_MQH__
#define __GMMA_MQH__

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\GmmaHandlePool.mqh>
#include <Mstng\Oscillator\GmmaUtil.mqh>
#include <Mstng\Util\StringUtil.mqh>

/**
 * EMA30/EMA60差分を用いてGMMAトレンドを評価するための分析クラス。
 */
class Gmma {
public:
    /** 分析対象の市場コンテキスト。 */
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
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
     * @param fromGmmaHandlePool GMMAハンドルプール。
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromGmmaHandlePool GMMAハンドルプール。
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
     * GMMAハンドルプールを設定する。
     *
     * @param fromGmmaHandlePool GMMAハンドルプール。
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
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
     * @param fromSymbolName シンボル名。
     * @param fromTimeFrame 時間足。
     * @return プラス方向は正、マイナス方向は負。取得失敗時は0。
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @return プラス方向は正、マイナス方向は負の継続件数。取得失敗時は0。
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
     * @param fromSymbolName シンボル名。
     * @param fromTimeFrame 時間足。
     * @return BUY方向は正、SELL方向は負。取得失敗時は0。
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @return BUY方向は正、SELL方向は負の継続件数。取得失敗時は0。
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
     * @param fromSymbolName シンボル名。
     * @param fromTimeFrame 時間足。
     * @param count 件数。
     * @return 取得できた場合 true。
     */
    bool getTrendCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int &count) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getTrendCount(context, count);
    }

    /**
     * 市場コンテキストを指定してGMMAトレンド継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param count BUY方向は正、SELL方向は負の継続件数。
     * @return 取得できた場合は true。
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

        int len = ZigZagElliotAnalysisProfile::getGmmaTrendLookback();
        int shift = ZigZagElliotAnalysisProfile::getGmmaShift();
        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

        if (bars <= shift + 2) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d", bars));

            return false;
        }

        int barsToCopy = len + 1;
        int availableBars = bars - shift;

        if (barsToCopy > availableBars) {
            barsToCopy = availableBars;
        }

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();

        int copied30 = CopyBuffer(
            this.ema30Handle,
            0,
            shift,
            barsToCopy,
            ema30Buffer
        );
        int copied60 = CopyBuffer(
            this.ema60Handle,
            0,
            shift,
            barsToCopy,
            ema60Buffer
        );

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

        count = this.calculateTrendCount(ema30Buffer, ema60Buffer, maxCheck);
        if (count == 0) {
            this.logger.debug(__FUNCTION__, StringFormat("count=%d direction=NON elapsed=%d ms", count, GetTickCount() - startCount));

            return true;
        }

        uint elapsed = GetTickCount() - startCount;
        string direction = "NON";

        if (count > 0) {
            direction = "BUY";
        }

        if (count < 0) {
            direction = "SELL";
        }

        this.logger.debug(__FUNCTION__, StringFormat("count=%s direction=%s elapsed=%d ms", StringUtil::addSign(count), direction, elapsed));

        return true;
    }

    /**
     * シンボル名と時間足を指定して GMMA クロス継続件数を取得する。
     *
     * @param fromSymbolName 対象シンボル。
     * @param fromTimeFrame 対象時間足。
     * @param count 出力: クロス継続件数。
     * @return 取得できた場合は true。
     */
    bool getCrossCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int &count) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getCrossCount(context, count);
    }

    /**
     * 市場コンテキストを指定してGMMAクロス継続件数を取得する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param count プラス方向は正、マイナス方向は負の継続件数。
     * @return 取得できた場合は true。
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

        int len = ZigZagElliotAnalysisProfile::getGmmaCrossLookback();
        int shift = ZigZagElliotAnalysisProfile::getGmmaShift();
        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
        if (bars <= shift + 1) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d", bars));
            return false;
        }

        int barsToCopy = len + 1;
        int availableBars = bars - shift;
        if (barsToCopy > availableBars) {
            barsToCopy = availableBars;
        }

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();
        int copied30 = CopyBuffer(
            this.ema30Handle,
            0,
            shift,
            barsToCopy,
            ema30Buffer
        );
        int copied60 = CopyBuffer(
            this.ema60Handle,
            0,
            shift,
            barsToCopy,
            ema60Buffer
        );
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

        count = this.calculateCrossCount(ema30Buffer, ema60Buffer, maxCheck);

        uint elapsed = GetTickCount() - startCount;
        string direction = (count < 0 ? "MINUS" : "PLUS");
        this.logger.debug(__FUNCTION__, StringFormat("count=%s direction=%s elapsed=%d ms", StringUtil::addSign(count), direction, elapsed));

        return true;
    }

    /**
     * EMA30/EMA60値を取得
     *
     * @param fromSymbolName シンボル名。
     * @param fromTimeFrame 時間足。
     * @param shiftValue シフト。
     * @param ema30Value EMA30値。
     * @param ema60Value EMA60値。
     * @return 取得できた場合は true。
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
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param shiftValue シフト。
     * @param ema30Value EMA30値。
     * @param ema60Value EMA60値。
     * @return 取得できた場合は true。
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

    /**
     * EMA30・EMA60を各1回取得し、トレンド・クロス継続件数と現在値をまとめて返す。
     * 両EMAを2本以上取得できた場合は、個別取得と同じく取得できた本数で判定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromTrendCount BUY方向は正、SELL方向は負のトレンド継続件数。
     * @param fromCrossCount プラス方向は正、マイナス方向は負のクロス継続件数。
     * @param fromEma30Value プロファイルの参照shiftに対応するEMA30値。
     * @param fromEma60Value プロファイルの参照shiftに対応するEMA60値。
     * @return 全項目を取得できた場合true。失敗時は出力をすべて0にする。
     */
    bool getAnalysisValues(
        MarketContext &fromMarketContext,
        int &fromTrendCount,
        int &fromCrossCount,
        double &fromEma30Value,
        double &fromEma60Value
    ) {
        this.initializeMarketContext(fromMarketContext);
        fromTrendCount = 0;
        fromCrossCount = 0;
        fromEma30Value = 0.0;
        fromEma60Value = 0.0;

        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int trendLookback = ZigZagElliotAnalysisProfile::getGmmaTrendLookback();
        int crossLookback = ZigZagElliotAnalysisProfile::getGmmaCrossLookback();
        int shift = ZigZagElliotAnalysisProfile::getGmmaShift();
        int bars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
        if (bars <= shift + 2) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d", bars));

            return false;
        }

        int barsToCopy = trendLookback + 1;
        if (crossLookback + 1 > barsToCopy) {
            barsToCopy = crossLookback + 1;
        }

        int availableBars = bars - shift;
        if (barsToCopy > availableBars) {
            barsToCopy = availableBars;
        }

        double ema30Buffer[];
        double ema60Buffer[];
        ArraySetAsSeries(ema30Buffer, true);
        ArraySetAsSeries(ema60Buffer, true);

        ResetLastError();
        int copied30 = CopyBuffer(this.ema30Handle, 0, shift, barsToCopy, ema30Buffer);
        int copied60 = CopyBuffer(this.ema60Handle, 0, shift, barsToCopy, ema60Buffer);
        if (copied30 <= 1 || copied60 <= 1) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied30=%d copied60=%d code=%d", copied30, copied60, GetLastError()));

            return false;
        }

        int availableCheckCount = copied30 - 1;
        if (copied60 - 1 < availableCheckCount) {
            availableCheckCount = copied60 - 1;
        }

        int trendMaxCheck = trendLookback;
        if (trendMaxCheck > availableCheckCount) {
            trendMaxCheck = availableCheckCount;
        }

        int crossMaxCheck = crossLookback;
        if (crossMaxCheck > availableCheckCount) {
            crossMaxCheck = availableCheckCount;
        }

        if (trendMaxCheck <= 0 || crossMaxCheck <= 0) {
            this.logger.error(__FUNCTION__, StringFormat(
                "maxCheck <= 0. trendMaxCheck=%d crossMaxCheck=%d", trendMaxCheck, crossMaxCheck));

            return false;
        }

        int trendCount = this.calculateTrendCount(ema30Buffer, ema60Buffer, trendMaxCheck);
        int crossCount = this.calculateCrossCount(ema30Buffer, ema60Buffer, crossMaxCheck);

        fromTrendCount = trendCount;
        fromCrossCount = crossCount;
        fromEma30Value = ema30Buffer[0];
        fromEma60Value = ema60Buffer[0];

        return true;
    }

private:
    /** GMMAハンドルに対応する市場コンテキスト。 */
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
     * 最新値が添字0のEMA配列から、符号付きのトレンド継続件数を求める。
     *
     * @param fromEma30Buffer EMA30配列。
     * @param fromEma60Buffer EMA60配列。
     * @param fromMaxCheck 判定上限。1以上かつ両配列の取得本数より小さいこと。
     * @return BUY方向は正、SELL方向は負、トレンドなしは0。
     */
    int calculateTrendCount(
        const double &fromEma30Buffer[],
        const double &fromEma60Buffer[],
        const int fromMaxCheck
    ) {
        ENUM_GMMA_TREND firstTrend = GmmaUtil::getGmmaTrend(
            fromEma30Buffer[1], fromEma30Buffer[0],
            fromEma60Buffer[1], fromEma60Buffer[0]);
        if (firstTrend == GMMA_TREND_NON) {
            return 0;
        }

        int count = 1;
        for (int i = 1; i < fromMaxCheck; i++) {
            ENUM_GMMA_TREND trend = GmmaUtil::getGmmaTrend(
                fromEma30Buffer[i + 1], fromEma30Buffer[i],
                fromEma60Buffer[i + 1], fromEma60Buffer[i]);
            if (trend != firstTrend) {
                break;
            }

            count++;
        }

        if (firstTrend == GMMA_TREND_SELL) {
            count = 0 - count;
        }

        return count;
    }

    /**
     * 最新値が添字0のEMA配列から、符号付きのクロス継続件数を求める。
     *
     * @param fromEma30Buffer EMA30配列。
     * @param fromEma60Buffer EMA60配列。
     * @param fromMaxCheck 判定上限。1以上かつ両配列の取得本数より小さいこと。
     * @return EMA30がEMA60以上の場合は正、未満の場合は負の継続件数。
     */
    int calculateCrossCount(
        const double &fromEma30Buffer[],
        const double &fromEma60Buffer[],
        const int fromMaxCheck
    ) {
        bool firstIsPlus = this.isPlus(fromEma30Buffer[0], fromEma60Buffer[0]);
        int count = 1;
        for (int i = 1; i < fromMaxCheck; i++) {
            bool isPlus = this.isPlus(fromEma30Buffer[i], fromEma60Buffer[i]);
            if (isPlus != firstIsPlus) {
                break;
            }

            count++;
        }

        if (!firstIsPlus) {
            count = 0 - count;
        }

        return count;
    }

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * シンボル名と時間足でGMMAの初期化を行う。
     *
     * @param fromSymbolName 対象シンボル。
     * @param fromTimeFrame 対象時間足。
     * @return 初期化できた場合は true。
     */
    bool ensureInitialized(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.ensureInitialized(context);
    }

    /**
     * 市場コンテキストを使用してGMMAハンドルを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @return 初期化できた場合は true。
     */
    bool ensureInitialized(MarketContext &fromMarketContext) {
        if (this.gmmaHandlePool != NULL) {
            this.gmmaHandlePool.setParameters(
                ZigZagElliotAnalysisProfile::getGmmaShortPeriod(),
                ZigZagElliotAnalysisProfile::getGmmaLongPeriod(),
                ZigZagElliotAnalysisProfile::getGmmaMaMethod(),
                ZigZagElliotAnalysisProfile::getGmmaAppliedPrice(),
                ZigZagElliotAnalysisProfile::getGmmaMaShift()
            );
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

        this.ema30Handle = iMA(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            ZigZagElliotAnalysisProfile::getGmmaShortPeriod(),
            ZigZagElliotAnalysisProfile::getGmmaMaShift(),
            ZigZagElliotAnalysisProfile::getGmmaMaMethod(),
            ZigZagElliotAnalysisProfile::getGmmaAppliedPrice()
        );
        this.ema60Handle = iMA(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            ZigZagElliotAnalysisProfile::getGmmaLongPeriod(),
            ZigZagElliotAnalysisProfile::getGmmaMaShift(),
            ZigZagElliotAnalysisProfile::getGmmaMaMethod(),
            ZigZagElliotAnalysisProfile::getGmmaAppliedPrice()
        );
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
     * @param ema30 EMA30値。
     * @param ema60 EMA60値。
     * @return EMA30 >= EMA60 のとき true。
     */
    bool isPlus(double ema30, double ema60) {
        return (ema30 >= ema60);
    }
};

#endif // __GMMA_MQH__






