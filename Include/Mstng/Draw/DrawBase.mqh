//+------------------------------------------------------------------+
//|                                                     DrawBase.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\UtilAll.mqh>

class DrawBase {
public:

    DrawBase() {
        this.logger.setLevel(LOG_INFO);
    }

    ~DrawBase() {
    }

protected:
    Logger logger;

    /**
     * 上位足で取得した価格が、現在足のどのバー時刻に対応するかを取得する。
     *
     * @param fromTimeFrame 元になった時間足
     * @param fromDatetime 元になったバー時刻
     * @param fromRate 元になった価格
     * @param isBuy 買い方向の場合true
     * @param isFrom 始点側の場合true
     * @return 対応する現在足バー時刻。見つからない場合はfromDatetimeを返す
     */
    datetime getDatetime(
        ENUM_TIMEFRAMES fromTimeFrame,
        datetime fromDatetime,
        double fromRate,
        bool isBuy,
        bool isFrom
    ) {
        string symbol = _Symbol;
        ENUM_TIMEFRAMES currentTimeFrame = (ENUM_TIMEFRAMES)_Period;

        int fromPeriodSeconds = PeriodSeconds(fromTimeFrame);
        int currentPeriodSeconds = PeriodSeconds(currentTimeFrame);

        if (currentPeriodSeconds <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "invalid current period seconds. currentTimeFrame=%d currentPeriodSeconds=%d",
                    (int)currentTimeFrame,
                    currentPeriodSeconds
                )
            );

            return fromDatetime;
        }

        int count = fromPeriodSeconds / currentPeriodSeconds;

        if (count <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "invalid count. fromTimeFrame=%d currentTimeFrame=%d count=%d",
                    (int)fromTimeFrame,
                    (int)currentTimeFrame,
                    count
                )
            );

            return fromDatetime;
        }

        int shift = iBarShift(symbol, currentTimeFrame, fromDatetime, false);

        if (shift < 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "iBarShift failed. fromDatetime=%s err=%d",
                    TimeToString(fromDatetime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                    GetLastError()
                )
            );

            return fromDatetime;
        }

        bool isHigh = this.isTargetHigh(isBuy, isFrom);

        int endIndex = shift - count + 1;

        if (endIndex < 0) {
            endIndex = 0;
        }

        for (int i = shift; i >= endIndex; i--) {
            double rate = 0.0;

            if (isHigh) {
                rate = iHigh(symbol, currentTimeFrame, i);
            } else {
                rate = iLow(symbol, currentTimeFrame, i);
            }

            if (this.isSameRate(rate, fromRate, symbol)) {
                return iTime(symbol, currentTimeFrame, i);
            }
        }

        return fromDatetime;
    }
    
    /**
     * 上昇波かどうかを判定する。
     *
     * @param rateFrom 始点価格
     * @param rateTo 終点価格
     * @return 上昇波の場合true
     */
    bool isBuy(double rateFrom, double rateTo) {
        if (rateFrom < rateTo) {
            return true;
        }

        return false;
    }

private:

    /**
     * 対象とする価格が高値か安値かを判定する。
     *
     * 買い:
     * - 始点: 安値
     * - 終点: 高値
     *
     * 売り:
     * - 始点: 高値
     * - 終点: 安値
     *
     * @param isBuy 買い方向の場合true
     * @param isFrom 始点側の場合true
     * @return 高値を見る場合true、安値を見る場合false
     */
    bool isTargetHigh(bool isBuy, bool isFrom) {
        if (isBuy) {
            if (isFrom) {
                return false;
            }

            return true;
        }

        if (isFrom) {
            return true;
        }

        return false;
    }

    /**
     * 価格が同一とみなせるか判定する。
     *
     * @param leftPrice 比較対象1
     * @param rightPrice 比較対象2
     * @param symbol シンボル
     * @return 同一とみなせる場合true
     */
    bool isSameRate(double leftPrice, double rightPrice, string symbol) {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

        if (point <= 0.0) {
            return leftPrice == rightPrice;
        }

        if (MathAbs(leftPrice - rightPrice) < (point * 0.5)) {
            return true;
        }

        return false;
    }

};
