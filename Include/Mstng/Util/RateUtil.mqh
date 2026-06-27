//+------------------------------------------------------------------+
//|                                                     RateUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"


/*

USDJPY:155.247

差分pips

pips加減算
 isBuy



*/


class RateUtil {
public:
    // 小数点桁数を取得
    // 主に3桁or5桁
    static int getDigits(const string symbolName) {
        return (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
    }

    // 1ポイントの価格（0.00001など）を取得
    // USDJPY（3桁）なら 0.001
    // EURUSD（5桁）なら 0.00001
    static double getPoint(const string symbolName) {
        return SymbolInfoDouble(symbolName, SYMBOL_POINT);
    }

    /**
     * @brief 1 pip あたりのポイント数を返す (3/5桁なら10, それ以外は1)
     */
    static double getPipInPoints(const string symbolName) {
        int digits = getDigits(symbolName);
        
        return (digits == 5 || digits == 3) ? 10.0 : 1.0;
    }

    /**
     * @brief pipsを実際の価格幅に変換 (例: 10 pips -> 0.001)
     */
    static double pipsToPrice(const double pips, const string symbolName) {
        double point = getPoint(symbolName);
        
        if (point <= 0) {
            return 0;
        }
        
        double priceDiff = pips * getPipInPoints(symbolName) * point;
        return NormalizeDouble(priceDiff, getDigits(symbolName));
    }

    /**
     * @brief 価格幅をpipsに変換 (例: 0.001 -> 10 pips)
     */
    static double priceToPips(const double priceDiff, const string symbolName) {
        double point = getPoint(symbolName);
        
        if (point <= 0) {
            return 0;
        }
        
        double pips = priceDiff / (getPipInPoints(symbolName) * point);
        return NormalizeDouble(pips, 1); // pipsは小数点第1位まで（0.1pips単位）で丸めるのが一般的
    }
    
    static double getOffset(bool isBuy, double pips, string symbolName) {
        double offset = pipsToPrice(pips, symbolName);
        
        if (isBuy) {
            offset = 0 - offset;
        }
        
        return offset;
    }
    
    /**
     * @brief 2つのレート差を pips で返します（符号付き）。
     *
     * @param fromRate   基準レート
     * @param toRate     比較先レート
     * @param symbolName シンボル名
     * @return (toRate - fromRate) を pips に換算した値（例: 上がれば +）
     */
    static double getDiffPips(const double fromRate, const double toRate, const string symbolName) {
        const double diffPrice = toRate - fromRate;

        return MathAbs(priceToPips(diffPrice, symbolName));
    }

    /**
     * @brief 柔軟なPips計算 (元のgetPipsの意図を汲んだもの)
     * 10pips単位などの「係数」としての計算に使用
     */
    /*static double getPipsValue(const double value, const string symbolName) {
        return value * (getPipInPoints(symbolName) * getPoint(symbolName));
    }*/
    
    
    
    
    
    
    
    
    
    
    
    
    
    /*static int getDigits(string symbolName) {
        return (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
    }
    
    double getPips(string symbolName, double fromValue) {
        double point = getPoint(symbolName);
        double pip = 10.0 * point;
        
        return fromValue * pip;
    }*/
    
    /*
    USDJPY（3桁）なら 0.001
    EURUSD（5桁）なら 0.00001
    */
    /*static double getPoint(string symbolName) {
        double point = 0.0;

        if (!SymbolInfoDouble(symbolName, SYMBOL_POINT, point)) {
            return _Point;
        }

        return point;
    }
    
    // --- 追加：1 pip が何 point かを返す（digits依存）
    static double getPipInPoints(const string symbolName) {
        const int digits = getDigits(symbolName);
        
        return ((digits == 5) || (digits == 3)) ? 10.0 : 1.0;
    }

    // --- 追加：pips -> points 変換
    static double pipsToPoints(const double pips, const string symbolName) {
        return pips * getPipInPoints(symbolName);
    }*/
    
    /**
     * @brief symbolName における pips をレート（価格差）へ変換して返します。
     *
     * @param pips       pips（例: 10 = 10pips）
     * @param symbolName シンボル名（例: "EURUSD"）
     * @return レート差（価格差）。取得失敗時は 0.0
     */
    /*static double getRate(const string symbolName, const double pips) {
        const double point = getPoint(symbolName);
        
        if (point <= 0.0) {
            return 0.0;
        }
            

        const int digits = getDigits(symbolName);

        // pips -> points -> price
        const double priceDiff = pipsToPoints(pips, symbolName) * point;

        return NormalizeDouble(priceDiff, digits);
    }*/
};