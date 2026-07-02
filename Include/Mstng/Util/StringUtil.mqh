//+------------------------------------------------------------------+
//|                                                   StringUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * @class StringUtil
 * @brief 文字列に関するユーティリティメソッドを提供するクラス。
 *
 * <p>通貨ペア名の分割など、再利用性の高い文字列処理をまとめます。</p>
 */
class StringUtil {
public:
    /**
     * 符号付き文字列を返す。
     *
     * 正の値には "+" を付与し、
     * 0 と負の値は IntegerToString の結果をそのまま返す。
     *
     * @param value 数値
     * @return      符号付き文字列
     */
    static string addSign(const int value) {
        if (value > 0) {
            return "+" + IntegerToString(value);
        }
    
        return IntegerToString(value);
    }

    /**
     * @brief 文字列が空（長さ0）かどうかを判定します。
     *
     * @param target 判定対象文字列
     * @return 空文字であれば true、それ以外は false
     */
    static bool isEmpty(const string target) {
        return StringLen(target) == 0;
    }
        
    /**
     * @brief 通貨ペア名を左右2つの通貨コードに分割します。
     *
     * <p>主に "EURUSD" や "USDJPY" のような 6 文字の通貨ペア名を、
     * 左3文字と右3文字に分割することを想定しています。<br>
     * 例: "EURUSD" → left="EUR", right="USD"</p>
     *
     * <p>通貨ペア名が 6 文字以外の場合は分割に失敗し、false を返します。</p>
     *
     * @param originalCurrencyPairName 元の通貨ペア名（例: "EURUSD"）。
     * @param leftCurrencyName         分割後の左側（例: "EUR"）。
     * @param rightCurrencyName        分割後の右側（例: "USD"）。
     *
     * @return 分割に成功した場合は true、想定外の形式で分割できなかった場合は false。
     */
    static bool splitCurrencyPairName(const string originalCurrencyPairName,
                                      string &leftCurrencyName,
                                      string &rightCurrencyName) {
        
        // 初期化しておく
        leftCurrencyName = "";
        rightCurrencyName = "";

        int currencyPairLength = StringLen(originalCurrencyPairName);

        if (currencyPairLength < 6) {
            return false;
        }

        // 左3文字と右3文字に分割する
        leftCurrencyName = StringSubstr(originalCurrencyPairName, 0, 3);
        rightCurrencyName = StringSubstr(originalCurrencyPairName, 3, 3);
        
        return true;
    }
    
    /**
     * @brief 整数(1..99)をローマ数字に変換して返します。
     *
     * <p>例: 1→"I", 4→"IV", 9→"IX", 40→"XL", 58→"LVIII", 99→"XCIX"</p>
     *
     * @param value 変換対象（1..99）
     * @return ローマ数字。範囲外(<=0 または >99)は空文字を返します。
     */
    static string toRoman(const int value) {
        if (value <= 0 || value > 99) {
            return "";
        }

        int n = value;
        string result = "";

        // 99までに必要な記号セット（降順）
        const int    vals[] = {90, 50, 40, 10, 9, 5, 4, 1};
        const string syms[] = {"xc","l","xl","x","ix","v","iv","i"};    // 小文字

        for (int i = 0; i < ArraySize(vals); i++) {
            while (n >= vals[i]) {
                result += syms[i];
                n -= vals[i];
            }
        }

        return result;
    }
    
    /**
     * 指定した整数値をゼロパディングして文字列として返します。
     *
     * @param fromValue 元の整数値
     * @param digits    最低桁数
     * @return ゼロパディングされた文字列
     */
    static string zeroPadding(int fromValue, int digits) {
        int  value   = fromValue;
        bool isMinus = false;
    
        if (value < 0) {
            isMinus = true;
            value   = MathAbs(fromValue);
        }
    
        string result = IntegerToString(value);
        int    length = StringLen(result);
    
        // すでに桁数が指定以上であれば、そのまま（必要に応じてマイナス記号のみ付与）
        if (length >= digits) {
            if (isMinus) {
                result = "-" + result;
            }
    
            return(result);
        }
    
        // 不足している桁数分だけ先頭に '0' を付与
        for (int index = 0; index < digits - length; index++) {
            result = "0" + result;
        }
    
        // 元が負数の場合はマイナス記号を付与
        if (isMinus) {
            result = "-" + result;
        }
    
        return(result);
    }

};
