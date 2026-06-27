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
    int count;
    double main0;
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
     * @return プラスの場合true
     */
    bool isPlus() {
        return this.count > 0;
    }

    /**
     * カウント文字列取得
     *
     * @return 符号付きカウント文字列
     */
    string getCountText() {
        return StringUtil::addSign(this.count);
    }

    /**
     * Main文字列取得
     *
     * @param digitsValue 桁数
     * @return Main文字列
     */
    string getMain0Text(const int digitsValue = 2) {
        return DoubleToString(this.main0, digitsValue);
    }

    /**
     * Signal文字列取得
     *
     * @param digitsValue 桁数
     * @return Signal文字列
     */
    string getSignal0Text(const int digitsValue = 2) {
        return DoubleToString(this.signal0, digitsValue);
    }
    
    string getText() {
        return StringFormat("/%s/%s/%s/", this.getCountText(), this.getMain0Text(), this.getSignal0Text());
    }
};