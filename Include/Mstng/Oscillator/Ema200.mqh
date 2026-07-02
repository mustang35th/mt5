//+------------------------------------------------------------------+
//|                                                       Ema200.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_EMA200_MQH
#define MSTNG_EMA200_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\Ema200HandlePool.mqh>
#include <Mstng\Util\StringUtil.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * EMA200と確定足Closeの位置関係です。
 */
enum ENUM_EMA200_POSITION {
    /** 未判定 */
    EMA200_POSITION_NONE = 0,

    /** Close1がEMA200[1]より上 */
    EMA200_POSITION_ABOVE = 1,

    /** Close1がEMA200[1]より下 */
    EMA200_POSITION_BELOW = -1,

    /** Close1とEMA200[1]が同値 */
    EMA200_POSITION_EQUAL = 2
};

/**
 * EMA200の傾き方向です。
 */
enum ENUM_EMA200_SLOPE_DIRECTION {
    /** 未判定、または横ばい */
    EMA200_SLOPE_NONE = 0,

    /** 上向き */
    EMA200_SLOPE_UP = 1,

    /** 下向き */
    EMA200_SLOPE_DOWN = -1
};

/**
 * EMA200状態管理クラスです。
 *
 * 管理対象:
 * 1. Close1 が EMA200 の上か下か
 * 2. EMA200[1] と EMA200[4] の傾き
 * 3. EMA200 の上昇/下降回数
 * 4. テキスト表示用BUY/SELLラベル
 */
class Ema200 {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;

    /** 確定足終値 */
    double close1;

    /** EMA200[1] */
    double ema200Shift1;

    /** 比較対象EMA200。標準はEMA200[4] */
    double ema200Compare;

    /** EMA200[1] - EMA200[compareBarIndex] のpips */
    double slopePips;

    /** Close1 と EMA200[1] の位置関係 */
    ENUM_EMA200_POSITION closePosition;

    /** EMA200の傾き方向 */
    ENUM_EMA200_SLOPE_DIRECTION slopeDirection;

    /** EMA200上昇回数 */
    int upCount;

    /** EMA200下降回数 */
    int downCount;

    /** 上昇優勢なら正、下降優勢なら負、同数なら0 */
    int trendCount;

    /** BUY方向判定 */
    bool isBuy;

    /** SELL方向判定 */
    bool isSell;

    /** BUY / SELL / NONE の表示用ラベル */
    string buySellLabel;

    /** EMA200 + 時間足 + BUY/SELL/NONE の表示用ラベル */
    string textLabel;

    /** BUY/SELL時だけ表示するラベル。NONE時は空文字 */
    string signalTextLabel;

    /**
     * コンストラクタ
     */
    Ema200() {
        this.logger.setLevel(LOG_INFO);
        this.ema200HandlePool = NULL;
        this.ema200Handle = INVALID_HANDLE;
        this.isInitialized = false;
        this.resetValues();
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    Ema200(MarketContext &fromMarketContext) {
        this.logger.setLevel(LOG_INFO);
        this.ema200HandlePool = NULL;
        this.ema200Handle = INVALID_HANDLE;
        this.isInitialized = false;
        this.resetValues();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * コンストラクタ
     *
     * @param fromEma200HandlePool EMA200ハンドルプール
     */
    Ema200(Ema200HandlePool *fromEma200HandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.ema200HandlePool = fromEma200HandlePool;
        this.ema200Handle = INVALID_HANDLE;
        this.isInitialized = false;
        this.resetValues();
    }

    /**
     * 市場コンテキストとEMA200ハンドルプールを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromEma200HandlePool EMA200ハンドルプール
     */
    Ema200(MarketContext &fromMarketContext, Ema200HandlePool *fromEma200HandlePool) {
        this.logger.setLevel(LOG_INFO);
        this.ema200HandlePool = fromEma200HandlePool;
        this.ema200Handle = INVALID_HANDLE;
        this.isInitialized = false;
        this.resetValues();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ
     */
    ~Ema200() {
        if (this.ema200HandlePool == NULL) {
            this.releaseHandle();
        } else {
            this.ema200Handle = INVALID_HANDLE;
        }
    }

    /**
     * EMA200ハンドルプールを設定します。
     *
     * @param fromEma200HandlePool EMA200ハンドルプール
     */
    void setEma200HandlePool(Ema200HandlePool *fromEma200HandlePool) {
        if (this.ema200HandlePool == NULL) {
            this.releaseHandle();
        }

        this.ema200HandlePool = fromEma200HandlePool;
        this.ema200Handle = INVALID_HANDLE;
        this.isInitialized = false;
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
     * EMA200状態を更新します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromCompareBarIndex 傾き比較足。標準は4でEMA200[1]とEMA200[4]を比較する
     * @param fromCountBars 上昇/下降を数える本数。標準は4でEMA200[1]からEMA200[5]までを比較する
     * @param fromMinSlopePips 最低傾きpips。この値未満は横ばい扱い
     * @return 更新できた場合は true
     */
    bool update(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromCompareBarIndex = 4,
        int fromCountBars = 4,
        double fromMinSlopePips = 0.0
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.update(
            context,
            fromCompareBarIndex,
            fromCountBars,
            fromMinSlopePips
        );
    }

    /**
     * 市場コンテキストを指定してEMA200状態を更新します。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromCompareBarIndex 傾き比較足。標準は4でEMA200[1]とEMA200[4]を比較する
     * @param fromCountBars 上昇/下降を数える本数。標準は4でEMA200[1]からEMA200[5]までを比較する
     * @param fromMinSlopePips 最低傾きpips。この値未満は横ばい扱い
     * @return 更新できた場合は true
     */
    bool update(
        MarketContext &fromMarketContext,
        int fromCompareBarIndex = 4,
        int fromCountBars = 4,
        double fromMinSlopePips = 0.0
    ) {
        this.resetValues();
        this.initializeMarketContext(fromMarketContext);

        if (fromCompareBarIndex <= 1) {
            this.logger.error(__FUNCTION__, StringFormat("invalid compareBarIndex=%d", fromCompareBarIndex));

            return false;
        }

        if (fromCountBars <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid countBars=%d", fromCountBars));

            return false;
        }

        if (!this.ensureInitialized(this.marketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int maxShift = fromCompareBarIndex;
        int countMaxShift = 1 + fromCountBars;

        if (countMaxShift > maxShift) {
            maxShift = countMaxShift;
        }

        double emaBuffer[];

        if (!this.copyEmaValues(maxShift, emaBuffer)) {
            this.logger.error(__FUNCTION__, "copyEmaValues failed.");

            return false;
        }

        double closeValue = 0.0;

        if (!this.getCloseValue(this.marketContext, 1, closeValue)) {
            this.logger.error(__FUNCTION__, "getCloseValue failed.");

            return false;
        }

        this.close1 = closeValue;
        this.ema200Shift1 = emaBuffer[1];
        this.ema200Compare = emaBuffer[fromCompareBarIndex];
        this.slopePips = this.convertPriceDifferenceToPips(
            this.marketContext,
            this.ema200Shift1 - this.ema200Compare
        );
        this.closePosition = this.determineClosePosition(this.close1, this.ema200Shift1);
        this.slopeDirection = this.determineSlopeDirection(this.slopePips, fromMinSlopePips);

        this.setUpDownCount(emaBuffer, 1, fromCountBars, this.upCount, this.downCount);
        this.trendCount = this.determineTrendCount(this.upCount, this.downCount);
        this.setBuySell();
        this.setTextLabels();

        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "symbol=%s timeFrame=%s close1=%.8f ema200Shift1=%.8f ema200Compare=%.8f slopePips=%.2f closePosition=%s slopeDirection=%s upCount=%d downCount=%d trendCount=%s isBuy=%s isSell=%s buySellLabel=%s textLabel=%s",
                this.marketContext.symbolName,
                this.marketContext.timeFrameLabel,
                this.close1,
                this.ema200Shift1,
                this.ema200Compare,
                this.slopePips,
                this.convertClosePositionText(this.closePosition),
                this.convertSlopeDirectionText(this.slopeDirection),
                this.upCount,
                this.downCount,
                StringUtil::addSign(this.trendCount),
                this.convertBoolText(this.isBuy),
                this.convertBoolText(this.isSell),
                this.buySellLabel,
                this.textLabel
            )
        );

        return true;
    }

    /**
     * Close1 が EMA200[1] より上かを判定します。
     *
     * @return 上の場合は true
     */
    bool isClose1AboveEma200() {
        return this.closePosition == EMA200_POSITION_ABOVE;
    }

    /**
     * Close1 が EMA200[1] より下かを判定します。
     *
     * @return 下の場合は true
     */
    bool isClose1BelowEma200() {
        return this.closePosition == EMA200_POSITION_BELOW;
    }

    /**
     * EMA200が上向きかを判定します。
     *
     * @return 上向きの場合は true
     */
    bool isUpSlope() {
        return this.slopeDirection == EMA200_SLOPE_UP;
    }

    /**
     * EMA200が下向きかを判定します。
     *
     * @return 下向きの場合は true
     */
    bool isDownSlope() {
        return this.slopeDirection == EMA200_SLOPE_DOWN;
    }

    /**
     * EMA200値を取得します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromShiftValue シフト
     * @param ema200Value EMA200値
     * @return 取得できた場合は true
     */
    bool getEmaValue(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromShiftValue,
        double &ema200Value
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getEmaValue(context, fromShiftValue, ema200Value);
    }

    /**
     * 市場コンテキストを使用してEMA200値を取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromShiftValue シフト
     * @param ema200Value EMA200値
     * @return 取得できた場合は true
     */
    bool getEmaValue(
        MarketContext &fromMarketContext,
        int fromShiftValue,
        double &ema200Value
    ) {
        this.initializeMarketContext(fromMarketContext);
        ema200Value = 0.0;

        if (fromShiftValue < 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid shift=%d", fromShiftValue));

            return false;
        }

        if (!this.ensureInitialized(fromMarketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int bars = Bars(fromMarketContext.symbolName, fromMarketContext.timeFrame);

        if (bars <= fromShiftValue) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d shift=%d", bars, fromShiftValue));

            return false;
        }

        double emaBuffer[];
        ArraySetAsSeries(emaBuffer, true);

        ResetLastError();

        int copied = CopyBuffer(this.ema200Handle, 0, fromShiftValue, 1, emaBuffer);

        if (copied <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied=%d code=%d", copied, GetLastError()));

            return false;
        }

        ema200Value = emaBuffer[0];

        return true;
    }

    /**
     * Close1のEMA200位置を取得します。
     *
     * 戻り値は ABOVE=1、BELOW=-1、EQUAL=2、NONE=0 です。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param position 位置関係
     * @return 取得できた場合は true
     */
    bool getClosePosition(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, ENUM_EMA200_POSITION &position) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getClosePosition(context, position);
    }

    /**
     * 市場コンテキストを使用してClose1のEMA200位置を取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param position 位置関係
     * @return 取得できた場合は true
     */
    bool getClosePosition(MarketContext &fromMarketContext, ENUM_EMA200_POSITION &position) {
        position = EMA200_POSITION_NONE;

        double emaValue = 0.0;
        double closeValue = 0.0;

        if (!this.getEmaValue(fromMarketContext, 1, emaValue)) {
            return false;
        }

        if (!this.getCloseValue(fromMarketContext, 1, closeValue)) {
            return false;
        }

        position = this.determineClosePosition(closeValue, emaValue);

        return true;
    }

    /**
     * EMA200[1]と指定過去足の傾きをpipsで取得します。
     *
     * 正の値は上向き、負の値は下向きです。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromCompareBarIndex 比較する過去足
     * @param value 傾きpips
     * @return 取得できた場合は true
     */
    bool getSlopePips(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromCompareBarIndex,
        double &value
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getSlopePips(context, fromCompareBarIndex, value);
    }

    /**
     * 市場コンテキストを使用してEMA200の傾きをpipsで取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromCompareBarIndex 比較する過去足
     * @param value 傾きpips
     * @return 取得できた場合は true
     */
    bool getSlopePips(
        MarketContext &fromMarketContext,
        int fromCompareBarIndex,
        double &value
    ) {
        value = 0.0;

        if (fromCompareBarIndex <= 1) {
            this.logger.error(__FUNCTION__, StringFormat("invalid compareBarIndex=%d", fromCompareBarIndex));

            return false;
        }

        double emaShift1Value = 0.0;
        double emaCompareValue = 0.0;

        if (!this.getEmaValue(fromMarketContext, 1, emaShift1Value)) {
            return false;
        }

        if (!this.getEmaValue(fromMarketContext, fromCompareBarIndex, emaCompareValue)) {
            return false;
        }

        value = this.convertPriceDifferenceToPips(
            fromMarketContext,
            emaShift1Value - emaCompareValue
        );

        return true;
    }

    /**
     * EMA200の傾き方向を取得します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromCompareBarIndex 比較する過去足
     * @param fromMinSlopePips 最低傾きpips
     * @param direction 傾き方向
     * @return 取得できた場合は true
     */
    bool getSlopeDirection(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromCompareBarIndex,
        double fromMinSlopePips,
        ENUM_EMA200_SLOPE_DIRECTION &direction
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getSlopeDirection(
            context,
            fromCompareBarIndex,
            fromMinSlopePips,
            direction
        );
    }

    /**
     * 市場コンテキストを使用してEMA200の傾き方向を取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromCompareBarIndex 比較する過去足
     * @param fromMinSlopePips 最低傾きpips
     * @param direction 傾き方向
     * @return 取得できた場合は true
     */
    bool getSlopeDirection(
        MarketContext &fromMarketContext,
        int fromCompareBarIndex,
        double fromMinSlopePips,
        ENUM_EMA200_SLOPE_DIRECTION &direction
    ) {
        direction = EMA200_SLOPE_NONE;

        double value = 0.0;

        if (!this.getSlopePips(fromMarketContext, fromCompareBarIndex, value)) {
            return false;
        }

        direction = this.determineSlopeDirection(value, fromMinSlopePips);

        return true;
    }

    /**
     * EMA200の上昇/下降回数を取得します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromStartBarIndex 開始足。通常は1
     * @param fromCountBars 判定本数
     * @param fromUpCount 上昇回数
     * @param fromDownCount 下降回数
     * @return 取得できた場合は true
     */
    bool getUpDownCount(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromStartBarIndex,
        int fromCountBars,
        int &fromUpCount,
        int &fromDownCount
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getUpDownCount(
            context,
            fromStartBarIndex,
            fromCountBars,
            fromUpCount,
            fromDownCount
        );
    }

    /**
     * 市場コンテキストを使用してEMA200の上昇・下降回数を取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromStartBarIndex 開始足
     * @param fromCountBars 判定本数
     * @param fromUpCount 上昇回数
     * @param fromDownCount 下降回数
     * @return 取得できた場合は true
     */
    bool getUpDownCount(
        MarketContext &fromMarketContext,
        int fromStartBarIndex,
        int fromCountBars,
        int &fromUpCount,
        int &fromDownCount
    ) {
        this.initializeMarketContext(fromMarketContext);
        fromUpCount = 0;
        fromDownCount = 0;

        if (fromStartBarIndex < 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid startBarIndex=%d", fromStartBarIndex));

            return false;
        }

        if (fromCountBars <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid countBars=%d", fromCountBars));

            return false;
        }

        if (!this.ensureInitialized(fromMarketContext)) {
            this.logger.error(__FUNCTION__, "initialize failed.");

            return false;
        }

        int maxShift = fromStartBarIndex + fromCountBars;
        double emaBuffer[];

        if (!this.copyEmaValues(maxShift, emaBuffer)) {
            this.logger.error(__FUNCTION__, "copyEmaValues failed.");

            return false;
        }

        this.setUpDownCount(emaBuffer, fromStartBarIndex, fromCountBars, fromUpCount, fromDownCount);

        return true;
    }

    /**
     * Close位置関係テキストを取得します。
     *
     * @return ABOVE / BELOW / EQUAL / NONE
     */
    string getClosePositionText() {
        return this.convertClosePositionText(this.closePosition);
    }

    /**
     * 傾き方向テキストを取得します。
     *
     * @return UP / DOWN / FLAT
     */
    string getSlopeDirectionText() {
        return this.convertSlopeDirectionText(this.slopeDirection);
    }

    /**
     * BUY/SELL表示用ラベルを取得します。
     *
     * @return BUY / SELL / NONE
     */
    string getBuySellLabel() {
        return this.buySellLabel;
    }

    /**
     * テキスト表示用ラベルを取得します。
     *
     * @return EMA200 M15 BUY など
     */
    string getTextLabel() {
        return this.textLabel;
    }

    /**
     * BUY/SELL時だけ表示するテキストラベルを取得します。
     *
     * @return BUY/SELL時は EMA200 M15 BUY など、NONE時は空文字
     */
    string getSignalTextLabel() {
        return this.signalTextLabel;
    }

    /**
     * テキスト表示用の簡易文字列を取得します。
     *
     * @return BUY/ABOVE/3.25/UP/+3 など
     */
    string getText() {
        return StringFormat(
            "%s/%s/%.2f/%s/%s",
            this.getBuySellLabel(),
            this.getClosePositionText(),
            this.slopePips,
            this.getSlopeDirectionText(),
            StringUtil::addSign(this.trendCount)
        );
    }

    /**
     * CSV文字列を取得します。
     *
     * @return CSV文字列
     */
    string getCsv() {
        return StringFormat(
            "%s,%.8f,%.8f,%.8f,%.2f,%s,%d,%d,%s,%s,%s",
            this.getClosePositionText(),
            this.close1,
            this.ema200Shift1,
            this.ema200Compare,
            this.slopePips,
            this.getSlopeDirectionText(),
            this.upCount,
            this.downCount,
            StringUtil::addSign(this.trendCount),
            this.convertBoolText(this.isBuy),
            this.convertBoolText(this.isSell)
        );
    }

    /**
     * CSVヘッダーを取得します。
     *
     * @return CSVヘッダー
     */
    static string getCsvHeader() {
        return "Ema200ClosePosition,Ema200Close1,Ema200Shift1,Ema200Compare,Ema200SlopePips,Ema200SlopeDirection,Ema200UpCount,Ema200DownCount,Ema200TrendCount,Ema200IsBuy,Ema200IsSell";
    }

    /**
     * 値をクリアします。
     */
    void clear() {
        this.resetValues();
    }

private:
    /** EMA200ハンドルに対応する市場コンテキスト */
    MarketContext handleMarketContext;

    int ema200Handle;
    Ema200HandlePool *ema200HandlePool;
    bool isInitialized;
    Logger logger;

    /**
     * 市場コンテキストと互換用フィールドを初期化します。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        // 既存利用箇所との互換性を維持する
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * 値を初期化します。
     */
    void resetValues() {
        MarketContext context;
        this.initializeMarketContext(context);
        this.close1 = 0.0;
        this.ema200Shift1 = 0.0;
        this.ema200Compare = 0.0;
        this.slopePips = 0.0;
        this.closePosition = EMA200_POSITION_NONE;
        this.slopeDirection = EMA200_SLOPE_NONE;
        this.upCount = 0;
        this.downCount = 0;
        this.trendCount = 0;
        this.isBuy = false;
        this.isSell = false;
        this.buySellLabel = "NONE";
        this.textLabel = "EMA200 NONE";
        this.signalTextLabel = "";
    }

    /**
     * EMA200ハンドルを初期化します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @return 初期化できた場合は true
     */
    bool ensureInitialized(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.ensureInitialized(context);
    }

    /**
     * 市場コンテキストを使用してEMA200ハンドルを初期化します。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @return 初期化できた場合は true
     */
    bool ensureInitialized(MarketContext &fromMarketContext) {
        if (this.ema200HandlePool != NULL) {
            this.ema200HandlePool.setParameters(200, MODE_EMA, PRICE_CLOSE);
            this.ema200HandlePool.setTimeframesFromMn1To(fromMarketContext);

            int poolHandle = this.ema200HandlePool.getEma200Handle(fromMarketContext.timeFrame);

            if (poolHandle == INVALID_HANDLE) {
                this.logger.error(__FUNCTION__, StringFormat("handle pool error. ema200Handle=%d code=%d", poolHandle, GetLastError()));
                this.isInitialized = false;

                return false;
            }

            this.ema200Handle = poolHandle;
            this.handleMarketContext = fromMarketContext;
            this.isInitialized = true;

            return true;
        }

        bool needRecreate = false;

        if (!this.isInitialized) {
            needRecreate = true;
        } else {
            if (this.handleMarketContext.symbolName != fromMarketContext.symbolName) {
                needRecreate = true;
            }

            if (this.handleMarketContext.timeFrame != fromMarketContext.timeFrame) {
                needRecreate = true;
            }

            if (this.ema200Handle == INVALID_HANDLE) {
                needRecreate = true;
            }
        }

        if (!needRecreate) {
            return true;
        }

        this.releaseHandle();
        this.ema200Handle = iMA(fromMarketContext.symbolName, fromMarketContext.timeFrame, 200, 0, MODE_EMA, PRICE_CLOSE);

        if (this.ema200Handle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, StringFormat("iMA handle error. ema200Handle=%d code=%d", this.ema200Handle, GetLastError()));
            this.releaseHandle();
            this.isInitialized = false;

            return false;
        }

        this.handleMarketContext = fromMarketContext;
        this.isInitialized = true;

        return true;
    }

    /**
     * EMA200ハンドルを解放します。
     */
    void releaseHandle() {
        if (this.ema200HandlePool != NULL) {
            this.ema200Handle = INVALID_HANDLE;

            return;
        }

        if (this.ema200Handle == INVALID_HANDLE) {

            return;
        }

        IndicatorRelease(this.ema200Handle);
        this.ema200Handle = INVALID_HANDLE;
    }

    /**
     * EMA200値を0から指定shiftまで取得します。
     *
     * @param maxShift 最大shift
     * @param emaBuffer EMA200配列
     * @return 取得できた場合は true
     */
    bool copyEmaValues(int maxShift, double &emaBuffer[]) {
        if (maxShift < 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid maxShift=%d", maxShift));

            return false;
        }

        int bars = Bars(this.handleMarketContext.symbolName, this.handleMarketContext.timeFrame);

        if (bars <= maxShift) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d maxShift=%d", bars, maxShift));

            return false;
        }

        ArraySetAsSeries(emaBuffer, true);

        ResetLastError();

        int copyCount = maxShift + 1;
        int copied = CopyBuffer(this.ema200Handle, 0, 0, copyCount, emaBuffer);

        if (copied < copyCount) {
            this.logger.error(__FUNCTION__, StringFormat("CopyBuffer error. copied=%d copyCount=%d code=%d", copied, copyCount, GetLastError()));

            return false;
        }

        return true;
    }

    /**
     * 終値を取得します。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     * @param fromShiftValue シフト
     * @param closeValue 終値
     * @return 取得できた場合は true
     */
    bool getCloseValue(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        int fromShiftValue,
        double &closeValue
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);

        return this.getCloseValue(context, fromShiftValue, closeValue);
    }

    /**
     * 市場コンテキストを使用して終値を取得します。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト
     * @param fromShiftValue シフト
     * @param closeValue 終値
     * @return 取得できた場合は true
     */
    bool getCloseValue(
        MarketContext &fromMarketContext,
        int fromShiftValue,
        double &closeValue
    ) {
        closeValue = 0.0;

        if (fromShiftValue < 0) {
            this.logger.error(__FUNCTION__, StringFormat("invalid shift=%d", fromShiftValue));

            return false;
        }

        int bars = Bars(fromMarketContext.symbolName, fromMarketContext.timeFrame);

        if (bars <= fromShiftValue) {
            this.logger.error(__FUNCTION__, StringFormat("not enough bars. bars=%d shift=%d", bars, fromShiftValue));

            return false;
        }

        double closeBuffer[];
        ArraySetAsSeries(closeBuffer, true);

        ResetLastError();

        int copied = CopyClose(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            fromShiftValue,
            1,
            closeBuffer
        );

        if (copied <= 0) {
            this.logger.error(__FUNCTION__, StringFormat("CopyClose error. copied=%d code=%d", copied, GetLastError()));

            return false;
        }

        closeValue = closeBuffer[0];

        return true;
    }

    /**
     * CloseとEMA200の位置関係を判定します。
     *
     * @param closeValue Close値
     * @param emaValue EMA200値
     * @return 位置関係
     */
    ENUM_EMA200_POSITION determineClosePosition(double closeValue, double emaValue) {
        if (closeValue > emaValue) {
            return EMA200_POSITION_ABOVE;
        }

        if (closeValue < emaValue) {
            return EMA200_POSITION_BELOW;
        }

        return EMA200_POSITION_EQUAL;
    }

    /**
     * 傾き方向を判定します。
     *
     * @param fromSlopePips 傾きpips
     * @param fromMinSlopePips 最低傾きpips
     * @return 傾き方向
     */
    ENUM_EMA200_SLOPE_DIRECTION determineSlopeDirection(double fromSlopePips, double fromMinSlopePips) {
        double minSlopePipsValue = fromMinSlopePips;

        if (minSlopePipsValue < 0.0) {
            minSlopePipsValue = MathAbs(minSlopePipsValue);
        }

        if (minSlopePipsValue <= 0.0) {
            if (fromSlopePips > 0.0) {
                return EMA200_SLOPE_UP;
            }

            if (fromSlopePips < 0.0) {
                return EMA200_SLOPE_DOWN;
            }

            return EMA200_SLOPE_NONE;
        }

        if (fromSlopePips >= minSlopePipsValue) {
            return EMA200_SLOPE_UP;
        }

        if (fromSlopePips <= 0.0 - minSlopePipsValue) {
            return EMA200_SLOPE_DOWN;
        }

        return EMA200_SLOPE_NONE;
    }

    /**
     * 上昇/下降回数を設定します。
     *
     * @param emaBuffer EMA200配列
     * @param fromStartBarIndex 開始足
     * @param fromCountBars 判定本数
     * @param fromUpCount 上昇回数
     * @param fromDownCount 下降回数
     */
    void setUpDownCount(
        const double &emaBuffer[],
        int fromStartBarIndex,
        int fromCountBars,
        int &fromUpCount,
        int &fromDownCount
    ) {
        fromUpCount = 0;
        fromDownCount = 0;

        for (int i = fromStartBarIndex; i < fromStartBarIndex + fromCountBars; i++) {
            if (emaBuffer[i] > emaBuffer[i + 1]) {
                fromUpCount++;
            } else if (emaBuffer[i] < emaBuffer[i + 1]) {
                fromDownCount++;
            }
        }
    }

    /**
     * トレンドカウントを判定します。
     *
     * @param fromUpCount 上昇回数
     * @param fromDownCount 下降回数
     * @return 上昇優勢なら正、下降優勢なら負、同数なら0
     */
    int determineTrendCount(int fromUpCount, int fromDownCount) {
        if (fromUpCount > fromDownCount) {
            return fromUpCount;
        }

        if (fromDownCount > fromUpCount) {
            return 0 - fromDownCount;
        }

        return 0;
    }

    /**
     * BUY/SELL方向を設定します。
     */
    void setBuySell() {
        this.isBuy = false;
        this.isSell = false;

        if (this.closePosition == EMA200_POSITION_ABOVE
            && this.slopeDirection == EMA200_SLOPE_UP
            && this.trendCount > 0) {
            this.isBuy = true;

            return;
        }

        if (this.closePosition == EMA200_POSITION_BELOW
            && this.slopeDirection == EMA200_SLOPE_DOWN
            && this.trendCount < 0) {
            this.isSell = true;

            return;
        }
    }

    /**
     * テキスト表示用ラベルを設定します。
     */
    void setTextLabels() {
        this.buySellLabel = "NONE";

        if (this.isBuy) {
            this.buySellLabel = "BUY";
        } else if (this.isSell) {
            this.buySellLabel = "SELL";
        }

        string labelTimeFrame = this.marketContext.timeFrameLabel;

        if (labelTimeFrame == "") {
            labelTimeFrame = TimeUtil::convertTimeFrameToString(this.marketContext.timeFrame);
        }

        if (labelTimeFrame == "") {
            this.textLabel = "EMA200 " + this.buySellLabel;
        } else {
            this.textLabel = "EMA200 " + labelTimeFrame + " " + this.buySellLabel;
        }

        this.signalTextLabel = "";

        if (this.isBuy || this.isSell) {
            this.signalTextLabel = this.textLabel;
        }
    }

    /**
     * 価格差をpipsへ変換します。
     *
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @param priceDifferenceValue 価格差
     * @return pips値
     */
    double convertPriceDifferenceToPips(
        MarketContext &fromMarketContext,
        double priceDifferenceValue
    ) {
        double pointPerPip = this.getPointPerPip(fromMarketContext);

        if (pointPerPip <= 0.0) {
            return 0.0;
        }

        return priceDifferenceValue / pointPerPip;
    }

    /**
     * 1pips相当の価格幅を取得します。
     *
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 1pips相当の価格幅
     */
    double getPointPerPip(MarketContext &fromMarketContext) {
        double point = fromMarketContext.getPoint();

        if (fromMarketContext.digits == 3 || fromMarketContext.digits == 5) {
            return point * 10.0;
        }

        return point;
    }

    /**
     * Close位置関係を文字列へ変換します。
     *
     * @param positionValue Close位置関係
     * @return 文字列
     */
    string convertClosePositionText(ENUM_EMA200_POSITION positionValue) {
        if (positionValue == EMA200_POSITION_ABOVE) {
            return "ABOVE";
        }

        if (positionValue == EMA200_POSITION_BELOW) {
            return "BELOW";
        }

        if (positionValue == EMA200_POSITION_EQUAL) {
            return "EQUAL";
        }

        return "NONE";
    }

    /**
     * 傾き方向を文字列へ変換します。
     *
     * @param directionValue 傾き方向
     * @return 文字列
     */
    string convertSlopeDirectionText(ENUM_EMA200_SLOPE_DIRECTION directionValue) {
        if (directionValue == EMA200_SLOPE_UP) {
            return "UP";
        }

        if (directionValue == EMA200_SLOPE_DOWN) {
            return "DOWN";
        }

        return "FLAT";
    }

    /**
     * boolを文字列へ変換します。
     *
     * @param value bool値
     * @return true / false
     */
    string convertBoolText(bool value) {
        if (value) {
            return "true";
        }

        return "false";
    }
};

#endif // MSTNG_EMA200_MQH
