//+------------------------------------------------------------------+
//|                                                         Util.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * @class Util
 * @brief 汎用的なユーティリティメソッドを提供するクラス。
 *
 * すべてのメソッドは static として定義されます。
 * インスタンス化は想定していません。
 */
class Util {
public:
    /**
     * @brief 引数が偶数かどうかを判定します。
     *
     * @param targetNumber 判定対象の整数値。
     * @return targetNumber が偶数であれば true、そうでなければ false。
     */
    static bool isEven(const int targetNumber) {
        return (targetNumber % 2) == 0;
    }

    /**
     * @brief 引数が奇数かどうかを判定します。
     *
     * @param targetNumber 判定対象の整数値。
     * @return targetNumber が奇数であれば true、そうでなければ false。
     */
    static bool isOdd(const int targetNumber) {
        return (targetNumber % 2) != 0;
    }

    /**
     * @brief ストラテジーテスタで起動中かどうかを判定します。
     *
     * @return ストラテジーテスタ実行中であれば true、それ以外は false
     */
    static bool isStrategyTester() {
        return (bool)MQLInfoInteger(MQL_TESTER);
    }
    
    /**
     * シンボル名に JPY が含まれているか判定する。
     *
     * @param fromSymbolName 対象シンボル名
     * @return true: JPY を含む場合
     */
    static bool isJpy(string fromSymbolName) {
        if (StringFind(fromSymbolName, "JPY") >= 0) {
            return true;
        }
    
        return false;
    }
    
    /**
     * 空CSVを取得
     *
     * @param countValue 空項目数
     * @return 空CSV
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

