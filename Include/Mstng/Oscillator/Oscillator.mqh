//+------------------------------------------------------------------+
//|                                                   Oscillator.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Oscillator\AverageTrueRange.mqh>
#include <Mstng\Oscillator\Ema200.mqh>
#include <Mstng\Oscillator\Gmma.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Oscillator\Stochastic.mqh>
#include <Mstng\Oscillator\StochasticStatus.mqh>
#include <Mstng\Util\UtilAll.mqh>


/**
 * ストキャスティクスMain0並び順
 *
 * S = Short
 * M = Middle
 * L = Long
 */
enum ENUM_STOCHASTIC_MAIN_ORDER {
    /** 未判定 */
    STOCH_MAIN_ORDER_NONE = 0,

    /** Short >= Middle >= Long */
    STOCH_MAIN_ORDER_S_M_L = 1,

    /** Short >= Long >= Middle */
    STOCH_MAIN_ORDER_S_L_M = 2,

    /** Middle >= Short >= Long */
    STOCH_MAIN_ORDER_M_S_L = 3,

    /** Middle >= Long >= Short */
    STOCH_MAIN_ORDER_M_L_S = 4,

    /** Long >= Short >= Middle */
    STOCH_MAIN_ORDER_L_S_M = 5,

    /** Long >= Middle >= Short */
    STOCH_MAIN_ORDER_L_M_S = 6,

    /** 3本がほぼ同値 */
    STOCH_MAIN_ORDER_FLAT = 7
};

class Oscillator {
public:
    string symbolName;
    
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;
    
    int digits;
    
    StochasticStatus stochasticShort;
    StochasticStatus stochasticMiddle;
    StochasticStatus stochasticLong;

    int gmmaTrendCount;
    int gmmaCrossCount;

    /** EMA30現在値 */
    double ema30;

    /** EMA60現在値 */
    double ema60;

    /** EMA30とEMA60の差分pips値 */
    double ema30Ema60DiffPips;

    /** EMA200状態 */
    Ema200 ema200;

    /** ATR14 pips値 */
    double atr14;

    int oscillatorCount;
    bool isBuy;
    ENUM_STOCHASTIC_MAIN_ORDER stochasticMainOrder;
    
    Oscillator() {
        this.logger.setLevel(LOG_INFO);
        this.resetValues();
    }

    ~Oscillator() {}

    void setBuySell() {
        this.isBuy = false;
        int plusCount = 0;
        bool isStochasticShortPlus = this.stochasticShort.isPlus();
        bool isStochasticMiddlePlus = this.stochasticMiddle.isPlus();
        bool isStochasticLongPlus = this.stochasticLong.isPlus();
        bool isGmmaPlus = (this.gmmaCrossCount > 0);

        // 売買判定は 3 本のストキャスのみを対象とする
        if (isStochasticShortPlus) {
            plusCount++;
        }
        if (isStochasticMiddlePlus) {
            plusCount++;
        }
        if (isStochasticLongPlus) {
            plusCount++;
        }

        this.logger.debug(__FUNCTION__, StringFormat(
            "stochShort=%d(%s) stochMiddle=%d(%s) stochLong=%d(%s) gmmaTrend=%d gmmaCross=%d(%s) stochPlusCount=%d",
            this.stochasticShort.count,
            this.convertPlusMinusLabel(isStochasticShortPlus),
            this.stochasticMiddle.count,
            this.convertPlusMinusLabel(isStochasticMiddlePlus),
            this.stochasticLong.count,
            this.convertPlusMinusLabel(isStochasticLongPlus),
            this.gmmaTrendCount,
            this.gmmaCrossCount,
            this.convertPlusMinusLabel(isGmmaPlus),
            plusCount));

        // 3 本中 2 本以上がプラスのとき BUY、それ以外は SELL
        if (plusCount >= 2) {
            this.isBuy = true;
        } else {
            this.isBuy = false;
        }

        this.logger.debug(__FUNCTION__, StringFormat("result=%s", this.convertBuySellLabel(isBuy)));
        if (this.isBuy) {
            this.oscillatorCount = plusCount;
        } else {
            this.oscillatorCount = plusCount - 3;
        }

        this.setStochasticMainOrderFlag(this.isBuy);
    }

    /**
     * ストキャスMain0並び順設定
     *
     * 3本のMain0値から詳細な並び順ENUMを設定する。
     * 詳細状態は stochasticMainOrder だけで管理する。
     *
     * @param isBuyValue BUY判定の場合true
     */
    void setStochasticMainOrderFlag(const bool isBuyValue) {
        this.stochasticMainOrder = this.determineStochasticMainOrder(
            this.stochasticShort.main0,
            this.stochasticMiddle.main0,
            this.stochasticLong.main0
        );

        this.logger.debug(__FUNCTION__, StringFormat(
            "isBuy=%s shortMain0=%.5f middleMain0=%.5f longMain0=%.5f order=%s",
            this.convertBuySellLabel(isBuyValue),
            this.stochasticShort.main0,
            this.stochasticMiddle.main0,
            this.stochasticLong.main0,
            this.convertStochasticMainOrderLabel(this.stochasticMainOrder)));
    }

    string getCsv(bool isDetail = false) {
        string csv = "";

        csv += StringFormat(
            "%s,%s,%s,",
            StringUtil::addSign(this.oscillatorCount),
            this.convertStochasticMainOrderLabel(this.stochasticMainOrder),
            this.getStochasticMainOrderDirectionText()
        );

        if (isDetail) {
            csv += this.getStochasticStatusCsv(this.stochasticShort);
            csv += this.getStochasticStatusCsv(this.stochasticMiddle);
            csv += this.getStochasticStatusCsv(this.stochasticLong);
            csv += this.getGmmaCsv();
            csv += this.getEma200Csv();
        }

        return csv;
    }

    bool update(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, int fromDigits, OscillatorHandlePool *oscillatorHandlePool) {
        this.symbolName = fromSymbolName;
        
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        
        this.digits = fromDigits;
        
        this.logger.setSymbolNameAndTimeFrame(this.symbolName, this.timeFrame);
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        uint startTick = GetTickCount();
        this.resetValues();

        if (oscillatorHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }
        if (!this.setStochasticShort(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }
        if (!this.setStochasticMiddle(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }
        if (!this.setStochasticLong(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }
        if (!this.setGmma(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }
        if (!this.setEma200(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }

        if (!this.setAtr14(oscillatorHandlePool)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return false;
        }

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(__FUNCTION__, StringFormat("<elapsed=%d ms>", elapsed));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        return true;
    }

    string toString() {
        string result = "";
        result = "stochasticShortCount=" + this.stochasticShort.getCountText();
        result += ", stochasticMiddleCount=" + this.stochasticMiddle.getCountText();
        result += ", stochasticLongCount=" + this.stochasticLong.getCountText();
        result += ", stochasticMainOrder=" + this.getStochasticMainOrderText();
        result += ", stochasticMainOrderDirection=" + this.getStochasticMainOrderDirectionText();
        result += ", stochasticMainOrderColor=" + this.getStochasticMainOrderColorLabel();
        result += ", gmmaTrendCount=" + StringUtil::addSign(this.gmmaTrendCount);
        result += ", gmmaCrossCount=" + StringUtil::addSign(this.gmmaCrossCount);
        result += ", ema30=" + this.getEma30Text(this.digits);
        result += ", ema60=" + this.getEma60Text(this.digits);
        result += ", ema30Ema60DiffPips=" + this.getEma30Ema60DiffPipsText(1);
        result += ", ema200ClosePosition=" + this.ema200.getClosePositionText();
        result += ", ema200SlopePips=" + DoubleToString(this.ema200.slopePips, 1);
        result += ", ema200SlopeDirection=" + this.ema200.getSlopeDirectionText();
        result += ", ema200TrendCount=" + StringUtil::addSign(this.ema200.trendCount);
        result += ", ema200IsBuy=" + this.convertBoolLabel(this.ema200.isBuy);
        result += ", ema200IsSell=" + this.convertBoolLabel(this.ema200.isSell);
        result += ", atr14=" + this.getAtr14Text(1);

        return result;
    }

    /**
     * 互換用：短期ストキャスカウント取得
     *
     * @return カウント
     */
    int getStochasticShortCount() {
        return this.stochasticShort.count;
    }

    /**
     * 互換用：中期ストキャスカウント取得
     *
     * @return カウント
     */
    int getStochasticMiddleCount() {
        return this.stochasticMiddle.count;
    }

    /**
     * 互換用：長期ストキャスカウント取得
     *
     * @return カウント
     */
    int getStochasticLongCount() {
        return this.stochasticLong.count;
    }

    /**
     * ストキャスMain0並び順取得
     *
     * @return ストキャスMain0並び順
     */
    ENUM_STOCHASTIC_MAIN_ORDER getStochasticMainOrder() {
        return this.stochasticMainOrder;
    }

    /**
     * ストキャスMain0並び順文字列取得
     *
     * @return ストキャスMain0並び順文字列
     */
    string getStochasticMainOrderText() {
        return this.convertStochasticMainOrderLabel(this.stochasticMainOrder);
    }

    /**
     * 現在のストキャスMain0並び順がBUY方向か
     *
     * SがLより上にある状態をBUY方向として扱う。
     *
     * @return BUY方向の場合true
     */
    bool isBuyStochasticMainOrder() {
        return this.isBuyStochasticMainOrder(this.stochasticMainOrder);
    }

    /**
     * 指定したストキャスMain0並び順がBUY方向か
     *
     * SがLより上にある状態をBUY方向として扱う。
     *
     * @param orderValue ストキャスMain0並び順
     * @return BUY方向の場合true
     */
    bool isBuyStochasticMainOrder(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        return orderValue == STOCH_MAIN_ORDER_S_M_L
            || orderValue == STOCH_MAIN_ORDER_S_L_M
            || orderValue == STOCH_MAIN_ORDER_M_S_L;
    }

    /**
     * 現在のストキャスMain0並び順がSELL方向か
     *
     * LがSより上にある状態をSELL方向として扱う。
     *
     * @return SELL方向の場合true
     */
    bool isSellStochasticMainOrder() {
        return this.isSellStochasticMainOrder(this.stochasticMainOrder);
    }

    /**
     * 指定したストキャスMain0並び順がSELL方向か
     *
     * LがSより上にある状態をSELL方向として扱う。
     *
     * @param orderValue ストキャスMain0並び順
     * @return SELL方向の場合true
     */
    bool isSellStochasticMainOrder(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        return orderValue == STOCH_MAIN_ORDER_M_L_S
            || orderValue == STOCH_MAIN_ORDER_L_S_M
            || orderValue == STOCH_MAIN_ORDER_L_M_S;
    }

    /**
     * 現在のストキャスMain0並び順の売買方向文字列取得
     *
     * @return BUY / SELL / NONE
     */
    string getStochasticMainOrderDirectionText() {
        return this.getStochasticMainOrderDirectionText(this.stochasticMainOrder);
    }

    /**
     * 指定したストキャスMain0並び順の売買方向文字列取得
     *
     * @param orderValue ストキャスMain0並び順
     * @return BUY / SELL / NONE
     */
    string getStochasticMainOrderDirectionText(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        if (this.isBuyStochasticMainOrder(orderValue)) {
            return "BUY";
        }

        if (this.isSellStochasticMainOrder(orderValue)) {
            return "SELL";
        }

        return "NONE";
    }

    /**
     * ストキャスMain0並び順カラー取得
     *
     * @return ストキャスMain0並び順カラー
     */
    color getStochasticMainOrderColor() {
        return this.convertStochasticMainOrderColor(this.stochasticMainOrder);
    }

    /**
     * ストキャスMain0並び順カラーラベル取得
     *
     * @return ストキャスMain0並び順カラーラベル
     */
    string getStochasticMainOrderColorLabel() {
        return this.convertStochasticMainOrderColorLabel(this.stochasticMainOrder);
    }


    /**
     * EMA30文字列取得
     *
     * @param digitsValue 桁数
     * @return EMA30文字列
     */
    string getEma30Text(const int digitsValue) {
        return DoubleToString(this.ema30, digitsValue);
    }

    /**
     * EMA60文字列取得
     *
     * @param digitsValue 桁数
     * @return EMA60文字列
     */
    string getEma60Text(const int digitsValue) {
        return DoubleToString(this.ema60, digitsValue);
    }

    /**
     * EMA30とEMA60の差分pips文字列取得
     *
     * @param digitsValue 桁数
     * @return EMA30とEMA60の差分pips文字列
     */
    string getEma30Ema60DiffPipsText(const int digitsValue = 1) {
        return DoubleToString(this.ema30Ema60DiffPips, digitsValue);
    }

    /**
     * EMA CSV取得
     *
     * @param priceDigitsValue 価格桁数
     * @param pipsDigitsValue pips桁数
     * @return EMA CSV文字列
     */
    string getEmaCsv(const int priceDigitsValue, const int pipsDigitsValue = 1) {
        return this.getEma30Text(priceDigitsValue)
            + "," + this.getEma60Text(priceDigitsValue)
            + "," + this.getEma30Ema60DiffPipsText(pipsDigitsValue)
            + ",";
    }


    /**
     * ATR14文字列取得
     *
     * @param digitsValue 桁数
     * @return ATR14文字列
     */
    string getAtr14Text(const int digitsValue = 1) {
        return DoubleToString(this.atr14, digitsValue);
    }

    /**
     * ATR14 CSV取得
     *
     * @param digitsValue 桁数
     * @return ATR14 CSV文字列
     */
    string getAtr14Csv(const int digitsValue = 1) {
        return this.getAtr14Text(digitsValue) + ",";
    }

    /**
     * EMA200がBUY方向か
     *
     * @return BUY方向の場合true
     */
    bool isEma200Buy() {
        return this.ema200.isBuy;
    }

    /**
     * EMA200がSELL方向か
     *
     * @return SELL方向の場合true
     */
    bool isEma200Sell() {
        return this.ema200.isSell;
    }

private:
    Logger logger;

    void resetValues() {
        this.stochasticShort.resetValues();
        this.stochasticMiddle.resetValues();
        this.stochasticLong.resetValues();
        this.gmmaTrendCount = 0;
        this.gmmaCrossCount = 0;
        this.ema30 = 0.0;
        this.ema60 = 0.0;
        this.ema30Ema60DiffPips = 0.0;
        this.ema200.clear();
        this.atr14 = 0.0;
        this.oscillatorCount = 0;
        this.isBuy = false;
        this.stochasticMainOrder = STOCH_MAIN_ORDER_NONE;
    }

    /**
     * ストキャス状態CSV取得
     *
     * @param labelValue ラベル
     * @param stochasticStatus ストキャス状態
     * @return CSV文字列
     */
    string getStochasticStatusCsv(
        StochasticStatus &stochasticStatus
    ) {
        return StringFormat(
            "%s,%s,%s,",
            stochasticStatus.getCountText(),
            stochasticStatus.getMain0Text(2),
            stochasticStatus.getSignal0Text(2)
        );
    }

    /**
     * GMMA CSV取得
     *
     * @return CSV文字列
     */
    string getGmmaCsv() {
        return StringFormat(
            "%s,%s,",
            StringUtil::addSign(this.gmmaTrendCount),
            StringUtil::addSign(this.gmmaCrossCount)
        ) + this.getEmaCsv(this.digits, 1);
    }

    /**
     * EMA200 CSV取得
     *
     * @return EMA200 CSV文字列
     */
    string getEma200Csv() {
        return this.ema200.getCsv() + ",";
    }

    bool setGmma(OscillatorHandlePool *oscillatorHandlePool) {
        uint startTick = GetTickCount();
        if (oscillatorHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL.");
            return false;
        }
        GmmaHandlePool *gmmaHandlePool = oscillatorHandlePool.getGmmaHandlePool();
        if (gmmaHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "gmmaHandlePool is NULL.");
            return false;
        }
        Gmma gmma(gmmaHandlePool);
        int trendCount = 0;
        int crossCount = 0;

        if (!gmma.getTrendCount(symbolName, timeFrame, trendCount)) {
            this.logger.error(__FUNCTION__, "gmma.getTrendCount failed.");
            return false;
        }

        if (!gmma.getCrossCount(symbolName, timeFrame, crossCount)) {
            this.logger.error(__FUNCTION__, "gmma.getCrossCount failed.");
            return false;
        }

        double ema30Value = 0.0;
        double ema60Value = 0.0;

        if (!gmma.getEmaValues(symbolName, timeFrame, 0, ema30Value, ema60Value)) {
            this.logger.error(__FUNCTION__, "gmma.getEmaValues failed.");
            return false;
        }

        this.gmmaTrendCount = trendCount;
        this.gmmaCrossCount = crossCount;
        this.ema30 = ema30Value;
        this.ema60 = ema60Value;
        this.ema30Ema60DiffPips = this.convertPriceDifferenceToPips(symbolName, this.ema30 - this.ema60);

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "elapsed=%d ms symbol=%s timeFrame=%s gmmaTrendCount=%d gmmaCrossCount=%d ema30=%.8f ema60=%.8f emaDiffPips=%.1f",
                elapsed,
                symbolName,
                TimeUtil::convertTimeFrameToString(timeFrame),
                this.gmmaTrendCount,
                this.gmmaCrossCount,
                this.ema30,
                this.ema60,
                this.ema30Ema60DiffPips
            )
        );

        return true;
    }

    /**
     * EMA200設定
     *
     * @param oscillatorHandlePool オシレーターハンドルプール
     * @return true: 設定成功
     */
    bool setEma200(OscillatorHandlePool *oscillatorHandlePool) {
        uint startTick = GetTickCount();

        if (oscillatorHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL.");

            return false;
        }

        Ema200HandlePool *ema200HandlePool = oscillatorHandlePool.getEma200HandlePool();

        if (ema200HandlePool == NULL) {
            this.logger.error(__FUNCTION__, "ema200HandlePool is NULL.");

            return false;
        }

        this.ema200.setEma200HandlePool(ema200HandlePool);

        if (!this.ema200.update(symbolName, timeFrame, 4, 4, 0.0)) {
            this.logger.error(__FUNCTION__, "ema200.update failed.");

            return false;
        }

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "elapsed=%d ms symbol=%s timeFrame=%s closePosition=%s slopePips=%.1f slopeDirection=%s upCount=%d downCount=%d trendCount=%s isBuy=%s isSell=%s",
                elapsed,
                symbolName,
                TimeUtil::convertTimeFrameToString(timeFrame),
                this.ema200.getClosePositionText(),
                this.ema200.slopePips,
                this.ema200.getSlopeDirectionText(),
                this.ema200.upCount,
                this.ema200.downCount,
                StringUtil::addSign(this.ema200.trendCount),
                this.convertBoolLabel(this.ema200.isBuy),
                this.convertBoolLabel(this.ema200.isSell)
            )
        );

        return true;
    }

    /**
     * 価格差をpipsへ変換
     *
     * @param symbolNameValue シンボル名
     * @param priceDifferenceValue 価格差
     * @return pips値
     */
    double convertPriceDifferenceToPips(const string symbolNameValue, const double priceDifferenceValue) {
        double pointPerPip = this.getPointPerPip();

        if (pointPerPip <= 0.0) {
            return 0.0;
        }

        return priceDifferenceValue / pointPerPip;
    }

    /**
     * 1pips相当の価格幅を取得
     *
     * @param symbolNameValue シンボル名
     * @return 1pips相当の価格幅
     */
    double getPointPerPip() {
        double point = SymbolInfoDouble(this.symbolName, SYMBOL_POINT);

        if (this.digits == 3 || this.digits == 5) {
            return point * 10.0;
        }

        return point;
    }


    /**
     * ATR14設定
     *
     * @param symbolName シンボル名
     * @param timeFrame 時間足
     * @param oscillatorHandlePool オシレーターハンドルプール
     * @return true: 設定成功
     */
    bool setAtr14(OscillatorHandlePool *oscillatorHandlePool) {
        uint startTick = GetTickCount();

        if (oscillatorHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL.");

            return false;
        }

        AverageTrueRangeHandlePool *averageTrueRangeHandlePool = oscillatorHandlePool.getAverageTrueRangeHandlePool();

        if (averageTrueRangeHandlePool == NULL) {
            this.logger.error(__FUNCTION__, "averageTrueRangeHandlePool is NULL.");

            return false;
        }

        AverageTrueRange averageTrueRange(averageTrueRangeHandlePool);
        double atr14Pips = 0.0;

        if (!averageTrueRange.getAtrPips(symbolName, timeFrame, 0, atr14Pips)) {
            this.logger.error(__FUNCTION__, "averageTrueRange.getAtrPips failed.");

            return false;
        }

        this.atr14 = atr14Pips;

        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "elapsed=%d ms symbol=%s timeFrame=%s atr14=%.2f",
                elapsed,
                symbolName,
                TimeUtil::convertTimeFrameToString(timeFrame),
                this.atr14
            )
        );

        return true;
    }

    bool setStochasticShort(OscillatorHandlePool *oscillatorHandlePool) {
        return this.setStochasticCommon(oscillatorHandlePool.getStochasticShortHandlePool(),
                                        this.stochasticShort,
                                        "Short");
    }

    bool setStochasticMiddle(OscillatorHandlePool *oscillatorHandlePool) {
        return this.setStochasticCommon(oscillatorHandlePool.getStochasticMiddleHandlePool(),
                                        this.stochasticMiddle,
                                        "Middle");
    }

    bool setStochasticLong(OscillatorHandlePool *oscillatorHandlePool) {
        return this.setStochasticCommon(oscillatorHandlePool.getStochasticLongHandlePool(),
                                        this.stochasticLong,
                                        "Long");
    }

    bool setStochasticCommon(StochasticHandlePool *stochasticHandlePool,
                             StochasticStatus &outStatus,
                             string label) {
        uint startTick = GetTickCount();
        if (stochasticHandlePool == NULL) {
            this.logger.error(__FUNCTION__, StringFormat("stochasticHandlePool[%s] is NULL.", label));
            return false;
        }
        Stochastic stochastic(stochasticHandlePool);
        int count = 0;
        if (!stochastic.getCrossCount(symbolName, timeFrame, 0, count)) {
            this.logger.error(__FUNCTION__, StringFormat("stochastic.getCrossCount failed. label=%s", label));
            return false;
        }
        outStatus.count = count;
        outStatus.main0 = stochastic.main0;
        outStatus.signal0 = stochastic.signal0;
        uint elapsed = GetTickCount() - startTick;
        this.logger.debug(__FUNCTION__, StringFormat("elapsed=%d ms symbol=%s timeFrame=%s label=%s stochasticCount=%d",
                                                     elapsed, symbolName, TimeUtil::convertTimeFrameToString(timeFrame), label, outStatus.count));
        return true;
    }

    /**
     * ストキャスMain0並び順判定
     *
     * @param shortMainValue 短期Main0
     * @param middleMainValue 中期Main0
     * @param longMainValue 長期Main0
     * @param epsilonValue 同値判定の許容差
     * @return ストキャスMain0並び順
     */
    ENUM_STOCHASTIC_MAIN_ORDER determineStochasticMainOrder(
        const double shortMainValue,
        const double middleMainValue,
        const double longMainValue,
        const double epsilonValue = 0.0001
    ) {
        bool shortMiddleEqual = MathAbs(shortMainValue - middleMainValue) <= epsilonValue;
        bool middleLongEqual = MathAbs(middleMainValue - longMainValue) <= epsilonValue;
        bool shortLongEqual = MathAbs(shortMainValue - longMainValue) <= epsilonValue;

        if (shortMiddleEqual && middleLongEqual && shortLongEqual) {
            return STOCH_MAIN_ORDER_FLAT;
        }

        if (shortMainValue >= middleMainValue && middleMainValue >= longMainValue) {
            return STOCH_MAIN_ORDER_S_M_L;
        }

        if (shortMainValue >= longMainValue && longMainValue >= middleMainValue) {
            return STOCH_MAIN_ORDER_S_L_M;
        }

        if (middleMainValue >= shortMainValue && shortMainValue >= longMainValue) {
            return STOCH_MAIN_ORDER_M_S_L;
        }

        if (middleMainValue >= longMainValue && longMainValue >= shortMainValue) {
            return STOCH_MAIN_ORDER_M_L_S;
        }

        if (longMainValue >= shortMainValue && shortMainValue >= middleMainValue) {
            return STOCH_MAIN_ORDER_L_S_M;
        }

        if (longMainValue >= middleMainValue && middleMainValue >= shortMainValue) {
            return STOCH_MAIN_ORDER_L_M_S;
        }

        return STOCH_MAIN_ORDER_NONE;
    }

    /**
     * ストキャスMain0並び順カラー変換
     *
     * 買い方向は青系、売り方向は赤系、中立はグレー系にする。
     *
     * @param orderValue ストキャスMain0並び順
     * @return 色
     */
    color convertStochasticMainOrderColor(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        switch (orderValue) {
            // 強い買い：短期 >= 中期 >= 長期
            case STOCH_MAIN_ORDER_S_M_L:
                return clrBlue;

            // 買い初動：短期が最上位だが、中期が弱い
            case STOCH_MAIN_ORDER_S_L_M:
                return clrAqua;

            // 買い継続：中期が最上位、短期も長期より上
            case STOCH_MAIN_ORDER_M_S_L:
                return clrDodgerBlue;

            // 売り転換注意：中期が最上位だが、短期が最下位
            case STOCH_MAIN_ORDER_M_L_S:
                return clrMagenta;

            // 売り中の戻り：長期が最上位、短期が一時反発
            case STOCH_MAIN_ORDER_L_S_M:
                return clrOrangeRed;

            // 強い売り：長期 >= 中期 >= 短期
            case STOCH_MAIN_ORDER_L_M_S:
                return clrRed;

            // 横並び
            case STOCH_MAIN_ORDER_FLAT:
                return clrSilver;
        }

        return clrGray;
    }

    /**
     * ストキャスMain0並び順カラーラベル変換
     *
     * @param orderValue ストキャスMain0並び順
     * @return 色ラベル
     */
    string convertStochasticMainOrderColorLabel(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        switch (orderValue) {
            case STOCH_MAIN_ORDER_S_M_L:
                return "clrBlue";

            case STOCH_MAIN_ORDER_S_L_M:
                return "clrAqua";

            case STOCH_MAIN_ORDER_M_S_L:
                return "clrDodgerBlue";

            case STOCH_MAIN_ORDER_M_L_S:
                return "clrMagenta";

            case STOCH_MAIN_ORDER_L_S_M:
                return "clrOrangeRed";

            case STOCH_MAIN_ORDER_L_M_S:
                return "clrRed";

            case STOCH_MAIN_ORDER_FLAT:
                return "clrSilver";
        }

        return "clrGray";
    }

    /**
     * ストキャスMain0並び順ラベル変換
     *
     * @param orderValue ストキャスMain0並び順
     * @return ラベル
     */
    string convertStochasticMainOrderLabel(const ENUM_STOCHASTIC_MAIN_ORDER orderValue) {
        switch (orderValue) {
            case STOCH_MAIN_ORDER_S_M_L:
                return "S>M>L";

            case STOCH_MAIN_ORDER_S_L_M:
                return "S>L>M";

            case STOCH_MAIN_ORDER_M_S_L:
                return "M>S>L";

            case STOCH_MAIN_ORDER_M_L_S:
                return "M>L>S";

            case STOCH_MAIN_ORDER_L_S_M:
                return "L>S>M";

            case STOCH_MAIN_ORDER_L_M_S:
                return "L>M>S";

            case STOCH_MAIN_ORDER_FLAT:
                return "FLAT";
        }

        return "NONE";
    }

    string convertPlusMinusLabel(bool isPlus) {
        if (isPlus) {
            return "PLUS";
        }
        return "MINUS";
    }

    string convertBoolLabel(bool value) {
        if (value) {
            return "true";
        }
        return "false";
    }

    string convertBuySellLabel(bool isBuyValue) {
        if (isBuyValue) {
            return "BUY";
        }
        return "SELL";
    }
};
