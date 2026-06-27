//+------------------------------------------------------------------+
//|                                                     OhlcInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * OHLC情報
 */
class OhlcInfo {
public:
    /** 始値 */
    double open;

    /** 高値 */
    double high;

    /** 安値 */
    double low;

    /** 終値 */
    double close;

    /**
     * コンストラクタ
     */
    OhlcInfo() {
        // 初期化
        this.clear();
    }

    /**
     * 初期化
     */
    void clear() {
        // OHLC初期化
        this.open = 0.0;
        this.high = 0.0;
        this.low = 0.0;
        this.close = 0.0;
    }

    /**
     * データ設定
     *
     * @param openValue 始値
     * @param highValue 高値
     * @param lowValue 安値
     * @param closeValue 終値
     */
    void setData(
        const double openValue,
        const double highValue,
        const double lowValue,
        const double closeValue
    ) {
        // OHLC設定
        this.open = openValue;
        this.high = highValue;
        this.low = lowValue;
        this.close = closeValue;
    }

    /**
     * MqlRatesからデータ設定
     *
     * @param ratesValue レート情報
     */
    void setDataByRates(const MqlRates &ratesValue) {
        // OHLC設定
        this.open = ratesValue.open;
        this.high = ratesValue.high;
        this.low = ratesValue.low;
        this.close = ratesValue.close;
    }

    /**
     * CSVヘッダーを取得
     *
     * @return CSVヘッダー
     */
    static string getCsvHeader() {
        return "Open"
            + ",High"
            + ",Low"
            + ",Close";
    }

    /**
     * CSVデータを取得
     *
     * @param digitsValue 小数桁数
     * @return CSVデータ
     */
    string getCsvData(const int digitsValue) {
        return DoubleToString(this.open, digitsValue)
            + "," + DoubleToString(this.high, digitsValue)
            + "," + DoubleToString(this.low, digitsValue)
            + "," + DoubleToString(this.close, digitsValue);
    }
};