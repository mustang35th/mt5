//+------------------------------------------------------------------+
//|                                                         Util.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * 汎用的なユーティリティメソッドを提供するクラス。
 *
 * すべてのメソッドは static として定義されます。
 * インスタンス化は想定していません。
 */
class Util {
public:
    /**
     * 引数が偶数かどうかを判定する。
     *
     * @param targetNumber 判定対象の整数値。
     * @return targetNumber が偶数であれば true、そうでなければ false。
     */
    static bool isEven(const int targetNumber) {
        return (targetNumber % 2) == 0;
    }

    /**
     * 引数が奇数かどうかを判定する。
     *
     * @param targetNumber 判定対象の整数値。
     * @return targetNumber が奇数であれば true、そうでなければ false。
     */
    static bool isOdd(const int targetNumber) {
        return (targetNumber % 2) != 0;
    }

    /**
     * ストラテジーテスタで起動中かどうかを判定する。
     *
     * @return ストラテジーテスタ実行中であれば true、それ以外は false。
     */
    static bool isStrategyTester() {
        return (bool)MQLInfoInteger(MQL_TESTER);
    }
    
    /**
     * シンボル名に JPY が含まれているか判定する。
     *
     * @param fromSymbolName 対象シンボル名。
     * @return JPY を含む場合は true、含まれない場合は false。
     */
    static bool isJpy(string fromSymbolName) {
        if (StringFind(fromSymbolName, "JPY") >= 0) {
            return true;
        }
    
        return false;
    }
    
    /**
     * 空CSV文字列を取得する。
     *
     * @param countValue 空項目数。
     * @return 空要素で埋めたCSV文字列。
     */
    static string getCsvBlank(const int countValue) {
        if (countValue <= 0) {
            return "";
        }
    
        string csvText = "";
    
        for (int i = 1; i < countValue; i++) {
            csvText += ",";
        }
    
        return csvText;
    }
};

