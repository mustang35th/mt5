//+------------------------------------------------------------------+
//|                               CurrencyStrengthDailyRangeInfo.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_INFO_MQH

/**
 * 1通貨ペアの日足値幅と、同日の気配による円換算値を保持する。
 */
struct CurrencyStrengthDailyRangeInfo {
    /** 6文字の正規通貨ペア名。 */
    string symbolName;

    /** 取得に使用したブローカーのシンボル名。 */
    string resolvedSymbolName;

    /** 今回の日足値幅を取得できた場合true。 */
    bool rangeAvailable;

    /** 今回の円換算値を取得できた場合true。 */
    bool jpyAvailable;

    /** 対象日足の高値。 */
    double high;

    /** 対象日足の安値。 */
    double low;

    /** 価格の小数桁数。 */
    int digits;

    /** 整数に丸めた日足値幅のpips。 */
    int pips;

    /** 整数に丸めた円換算pips。 */
    int jpyPips;

    /** 換算シンボルのBid。JPY建ての場合は1。 */
    double conversionRate;

    /** 換算シンボル名。JPY建ての場合はJPY。 */
    string conversionSymbolName;

    /** JPY/決済通貨のBidで割る換算の場合true。 */
    bool inverseConversion;

    /** 対象日足の開始サーバー時刻。 */
    datetime dayTime;

    /** 換算に使用した気配のサーバー時刻。JPY建ての場合は0。 */
    datetime conversionTime;

    /** 今回の取得を開始したサーバー時刻。 */
    datetime updatedAt;

    /**
     * 未取得状態で初期化する。
     */
    CurrencyStrengthDailyRangeInfo() {
        this.reset("");
    }

    /**
     * 前回の値を残さず、今回の取得対象と取得時刻を設定する。
     *
     * @param fromSymbolName 正規通貨ペア名。
     * @param fromUpdatedAt 今回の取得開始時刻。
     */
    void reset(const string fromSymbolName, const datetime fromUpdatedAt = 0) {
        this.symbolName = fromSymbolName;
        this.resolvedSymbolName = "";
        this.rangeAvailable = false;
        this.jpyAvailable = false;
        this.high = 0.0;
        this.low = 0.0;
        this.digits = 0;
        this.pips = 0;
        this.jpyPips = 0;
        this.conversionRate = 0.0;
        this.conversionSymbolName = "";
        this.inverseConversion = false;
        this.dayTime = 0;
        this.conversionTime = 0;
        this.updatedAt = fromUpdatedAt;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_INFO_MQH
