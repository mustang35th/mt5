//+------------------------------------------------------------------+
//|                                             StochasticStatus.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\UtilAll.mqh>

/**
 * ストキャス状態
 */
class StochasticStatus {
public:
    /** クロス継続数（正：上向き、負：下向き）。 */
    int count;
    /** Main0の最新値。 */
    double main0;
    /** Signalの最新値。 */
    double signal0;

    /**
     * コンストラクタ
     */
    StochasticStatus() {
        this.resetValues();
    }

    /**
     * 値リセット
     */
    void resetValues() {
        this.count = 0;
        this.main0 = 0.0;
        this.signal0 = 0.0;
    }

    /**
     * プラス判定
     *
     * @return プラスの場合は true。
     */
    bool isPlus() {
        return this.count > 0;
    }

    /**
     * カウント文字列取得
     *
     * @return 符号付きカウント文字列。
     */
    string getCountText() {
        return StringUtil::addSign(this.count);
    }

    /**
     * Main文字列取得
     *
     * @param digitsValue 桁数。
     * @return Main文字列。
     */
    string getMain0Text(const int digitsValue = 2) {
        return DoubleToString(this.main0, digitsValue);
    }

    /**
     * Signal文字列取得
     *
     * @param digitsValue 桁数。
     * @return Signal文字列。
     */
    string getSignal0Text(const int digitsValue = 2) {
        return DoubleToString(this.signal0, digitsValue);
    }
    
    /**
     * ストキャス状態を簡易文字列で取得する。
     *
     * @return /count/main/signal/ 形式。
     */
    string getText() {
        return StringFormat("/%s/%s/%s/", this.getCountText(), this.getMain0Text(), this.getSignal0Text());
    }
};
