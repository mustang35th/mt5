//+------------------------------------------------------------------+
//|                                      FiboExpansionPriceInfo.mqh   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\RateUtil.mqh>

class FiboExpansionPriceInfo {
public:
    double FE618Price;
    double FE1000Price;
    double FE1272Price;
    double FE1618Price;
    double FE2000Price;
    double DistanceToFE2000Pips;

    FiboExpansionPriceInfo() {
        this.clear();
    }

    ~FiboExpansionPriceInfo() {
    }

    /**
     * 初期化する。
     */
    void clear() {
        this.FE618Price = 0.0;
        this.FE1000Price = 0.0;
        this.FE1272Price = 0.0;
        this.FE1618Price = 0.0;
        this.FE2000Price = 0.0;
        this.DistanceToFE2000Pips = 0.0;
    }

    /**
     * フィボナッチエクスパンション価格を設定する。
     *
     * @param startRate 1点目レート
     * @param endRate 2点目レート
     * @param baseRate 3点目レート
     * @param currentRate 現在レート
     * @param symbolName 通貨ペア
     */
    void setData(
        const double startRate,
        const double endRate,
        const double baseRate,
        const double currentRate,
        const string symbolName
    ) {
        this.clear();

        if (!this.isValidRate(startRate)) {
            return;
        }

        if (!this.isValidRate(endRate)) {
            return;
        }

        if (!this.isValidRate(baseRate)) {
            return;
        }

        if (!this.isValidRate(currentRate)) {
            return;
        }

        double waveRate = endRate - startRate;

        this.FE618Price = this.normalizePrice(baseRate + waveRate * 0.618, symbolName);
        this.FE1000Price = this.normalizePrice(baseRate + waveRate * 1.000, symbolName);
        this.FE1272Price = this.normalizePrice(baseRate + waveRate * 1.272, symbolName);
        this.FE1618Price = this.normalizePrice(baseRate + waveRate * 1.618, symbolName);
        this.FE2000Price = this.normalizePrice(baseRate + waveRate * 2.000, symbolName);

        this.DistanceToFE2000Pips = RateUtil::getDiffPips(currentRate, this.FE2000Price, symbolName);
    }

    /**
     * CSVヘッダーを取得する。
     *
     * @return CSVヘッダー
     */
    string getCsvHeader() {
        return "FE618Price"
            + ",FE1000Price"
            + ",FE1272Price"
            + ",FE1618Price"
            + ",FE2000Price"
            + ",DistanceToFE2000Pips";
    }

    /**
     * CSV値を取得する。
     *
     * @return CSV値
     */
    string getCsvText() {
        return DoubleToString(this.FE618Price, 5)
            + "," + DoubleToString(this.FE1000Price, 5)
            + "," + DoubleToString(this.FE1272Price, 5)
            + "," + DoubleToString(this.FE1618Price, 5)
            + "," + DoubleToString(this.FE2000Price, 5)
            + "," + DoubleToString(this.DistanceToFE2000Pips, 1);
    }

private:

    /**
     * レートが有効かどうかを判定する。
     *
     * @param rate レート
     * @return 有効な場合true
     */
    bool isValidRate(const double rate) {
        if (rate <= 0.0) {
            return false;
        }

        return true;
    }

    /**
     * 価格を通貨ペアの桁数で丸める。
     *
     * @param price 価格
     * @param symbolName 通貨ペア
     * @return 丸め後価格
     */
    double normalizePrice(const double price, const string symbolName) {
        return NormalizeDouble(price, RateUtil::getDigits(symbolName));
    }
};