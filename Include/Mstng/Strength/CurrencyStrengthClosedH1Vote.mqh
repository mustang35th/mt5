//+------------------------------------------------------------------+
//|                                 CurrencyStrengthClosedH1Vote.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_CURRENCY_STRENGTH_CLOSED_H1_VOTE_MQH
#define MSTNG_CURRENCY_STRENGTH_CLOSED_H1_VOTE_MQH

#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 通貨ペアの確定H1価格から短中長ストキャス票を求め、同じ足の集計に再利用する。
 */
class CurrencyStrengthClosedH1Vote {
public:
    /**
     * 指定銘柄・基準H1足に対応する票を保持しているか判定する。
     */
    bool isPrepared(const string fromSymbolName, const datetime fromExpectedBarTime) const {
        return fromSymbolName != "" && this.symbolName == fromSymbolName
            && this.expectedBarTime == fromExpectedBarTime;
    }

    /**
     * 基準足時刻に対応する銘柄の実バーを取得し、成功した票だけを保持する。
     * 期待時刻に実バーがない場合は、その後の実バーが存在するときだけ欠損と扱う。
     */
    bool prepare(const string fromSymbolName, const datetime fromExpectedBarTime) {
        if (fromSymbolName == "" || fromExpectedBarTime <= 0) {
            return false;
        }

        if (this.isPrepared(fromSymbolName, fromExpectedBarTime)) {
            return true;
        }

        int requiredBars = getRequiredBarCount();
        MqlRates rates[];
        if (CopyRates(fromSymbolName, PERIOD_H1, fromExpectedBarTime, requiredBars, rates) != requiredBars
                || !WarmUpSeriesUtil::isSeriesSynchronized(fromSymbolName, PERIOD_H1)) {
            return false;
        }

        datetime actualTime = rates[requiredBars - 1].time;
        if (actualTime <= 0 || actualTime > fromExpectedBarTime
                || (actualTime < fromExpectedBarTime
                    && (iTime(fromSymbolName, PERIOD_H1, 0) <= fromExpectedBarTime
                        || iBarShift(fromSymbolName, PERIOD_H1, fromExpectedBarTime, true) >= 0))) {
            return false;
        }

        int count = 0;
        if (!calculate(rates, count)) {
            return false;
        }

        this.symbolName = fromSymbolName;
        this.expectedBarTime = fromExpectedBarTime;
        this.barTime = actualTime;
        this.oscillatorCount = count;

        return true;
    }

    /**
     * 票の計算に使った確定H1足の開始時刻を取得する。
     */
    datetime getBarTime() const {
        return this.barTime;
    }

    /**
     * 多数決の方向に符号を付けたストキャス一致本数を取得する。
     */
    int getOscillatorCount() const {
        return this.oscillatorCount;
    }

    /**
     * 短中長すべてのMainとSignalに必要な価格本数を取得する。
     */
    static int getRequiredBarCount() {
        int shortBars = ZigZagElliotAnalysisProfile::getStochasticShortKPeriod()
            + ZigZagElliotAnalysisProfile::getStochasticShortSlowing()
            + ZigZagElliotAnalysisProfile::getStochasticShortDPeriod() - 2;
        int middleBars = ZigZagElliotAnalysisProfile::getStochasticMiddleKPeriod()
            + ZigZagElliotAnalysisProfile::getStochasticMiddleSlowing()
            + ZigZagElliotAnalysisProfile::getStochasticMiddleDPeriod() - 2;
        int longBars = ZigZagElliotAnalysisProfile::getStochasticLongKPeriod()
            + ZigZagElliotAnalysisProfile::getStochasticLongSlowing()
            + ZigZagElliotAnalysisProfile::getStochasticLongDPeriod() - 2;

        return MathMax(shortBars, MathMax(middleBars, longBars));
    }

    /**
     * 古い順の確定価格を使い、末尾の足のストキャス多数決を取得する。
     *
     * @param fromRates 昇順の価格系列。
     * @param fromOscillatorCount 既存の票形式（+2、+3、-2、-3）の格納先。
     * @return 必要な価格が揃い、対応する平滑化・価格方式で計算できた場合true。
     */
    static bool calculate(const MqlRates &fromRates[], int &fromOscillatorCount) {
        int count = ArraySize(fromRates);
        int requiredBars = getRequiredBarCount();
        if (count < requiredBars || ArrayGetAsSeries(fromRates)
                || ZigZagElliotAnalysisProfile::getStochasticMaMethod() != MODE_SMA
                || ZigZagElliotAnalysisProfile::getStochasticPriceField() != STO_LOWHIGH) {
            return false;
        }

        datetime previousTime = 0;
        for (int i = count - requiredBars; i < count; i++) {
            if (fromRates[i].time <= previousTime || !MathIsValidNumber(fromRates[i].open)
                    || !MathIsValidNumber(fromRates[i].low)
                    || !MathIsValidNumber(fromRates[i].high) || !MathIsValidNumber(fromRates[i].close)
                    || fromRates[i].low <= 0 || fromRates[i].high == EMPTY_VALUE
                    || fromRates[i].low > fromRates[i].open || fromRates[i].open > fromRates[i].high
                    || fromRates[i].low > fromRates[i].close || fromRates[i].close > fromRates[i].high) {
                return false;
            }

            previousTime = fromRates[i].time;
        }

        int buyCount = 0;
        if (isBuy(fromRates, ZigZagElliotAnalysisProfile::getStochasticShortKPeriod(),
                ZigZagElliotAnalysisProfile::getStochasticShortSlowing(),
                ZigZagElliotAnalysisProfile::getStochasticShortDPeriod())) {
            buyCount++;
        }

        if (isBuy(fromRates, ZigZagElliotAnalysisProfile::getStochasticMiddleKPeriod(),
                ZigZagElliotAnalysisProfile::getStochasticMiddleSlowing(),
                ZigZagElliotAnalysisProfile::getStochasticMiddleDPeriod())) {
            buyCount++;
        }

        if (isBuy(fromRates, ZigZagElliotAnalysisProfile::getStochasticLongKPeriod(),
                ZigZagElliotAnalysisProfile::getStochasticLongSlowing(),
                ZigZagElliotAnalysisProfile::getStochasticLongDPeriod())) {
            buyCount++;
        }

        fromOscillatorCount = buyCount;
        if (buyCount < ZigZagElliotAnalysisProfile::getStochasticBuyMajorityCount()) {
            fromOscillatorCount -= ZigZagElliotAnalysisProfile::getStochasticVoteMemberCount();
        }

        return true;
    }

private:
    /** 確定票を保持した実銘柄名。 */
    string symbolName;

    /** 確定票を解決した基準銘柄のH1開始時刻。 */
    datetime expectedBarTime;

    /** 実銘柄で使用したH1開始時刻。 */
    datetime barTime;

    /** 確定価格から計算した符号付き一致本数。 */
    int oscillatorCount;

    /**
     * LOW/HIGHのMainを新しい足からD期間分求め、その単純平均と現在のMainを比較する。
     */
    static bool isBuy(const MqlRates &fromRates[], const int fromKPeriod,
            const int fromSlowing, const int fromDPeriod) {
        int lastIndex = ArraySize(fromRates) - 1;
        double currentMain = 0.0;
        double mainSum = 0.0;
        for (int i = 0; i < fromDPeriod; i++) {
            int endIndex = lastIndex - i;
            double closeSum = 0.0;
            double rangeSum = 0.0;
            for (int j = endIndex - fromSlowing + 1; j <= endIndex; j++) {
                int startIndex = j - fromKPeriod + 1;
                double lowest = fromRates[startIndex].low;
                double highest = fromRates[startIndex].high;
                for (int k = startIndex + 1; k <= j; k++) {
                    lowest = MathMin(lowest, fromRates[k].low);
                    highest = MathMax(highest, fromRates[k].high);
                }

                closeSum += fromRates[j].close - lowest;
                rangeSum += highest - lowest;
            }

            double main = 100.0;
            if (rangeSum != 0.0) {
                main = closeSum / rangeSum * 100.0;
            }

            if (i == 0) {
                currentMain = main;
            }

            mainSum += main;
        }

        return ZigZagElliotAnalysisProfile::isStochasticBuyDirection(currentMain, mainSum / fromDPeriod);
    }
};

#endif
