//+------------------------------------------------------------------+
//|                                                   StringUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * 文字列に関するユーティリティメソッドを提供するクラス。
 *
 * 通貨ペア名の分割など、再利用性の高い文字列処理をまとめます。
 */
class StringUtil {
public:
    /**
     * 符号付き文字列を返す。
     *
     * 正の値には "+" を付与し、
     * 0 と負の値は IntegerToString の結果をそのまま返す。
     *
     * @param value 数値。
     * @return      符号付き文字列。
     */
    static string addSign(const int value) {
        if (value > 0) {
            return "+" + IntegerToString(value);
        }

        return IntegerToString(value);
    }

    /**
     * 符号付き小数文字列を返す。
     *
     * 正の値には "+" を付与し、
     * 0 と負の値は DoubleToString の結果をそのまま返す。
     *
     * @param value 数値。
     * @param digits 小数桁数。
     * @return 符号付き文字列。
     */
    static string addSign(const double value, const int digits) {
        string text = DoubleToString(value, digits);

        if (value > 0.0) {
            return "+" + text;
        }

        return text;
    }

    /**
     * 文字列が空（長さ0）かどうかを判定する。
     *
     * @param target 判定対象文字列。
     * @return 空文字であれば true、それ以外は false。
     */
    static bool isEmpty(const string target) {
        return StringLen(target) == 0;
    }
        
    /**
     * 通貨ペア名を左右2つの通貨コードに分割する。
     *
     * 6文字以上の通貨ペア名から、先頭3文字と続く3文字を取り出す。
     * 7文字目以降のサフィックスは使用しない。
     * 例: "EURUSD"、"EURUSD.a" → left="EUR", right="USD"。
     * 通貨コードの妥当性確認や大文字への変換、プレフィックスの除去は行わない。
     *
     * 6文字未満の場合は、左右の出力を空文字にして false を返す。
     *
     * @param originalCurrencyPairName 元の通貨ペア名（例: "EURUSD"）。
     * @param leftCurrencyName         分割後の左側（例: "EUR"）。
     * @param rightCurrencyName        分割後の右側（例: "USD"）。
     *
     * @return 6文字以上であれば true、6文字未満であれば false。
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
     * 整数(1..99)を小文字のローマ数字に変換して返す。
     *
     * 例: 1→"i", 4→"iv", 9→"ix", 40→"xl", 58→"lviii", 99→"xcix"
     *
     * @param value 変換対象（1..99）。
     * @return 小文字のローマ数字。範囲外(<=0 または >99)は空文字を返す。
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
     * 指定した整数値をゼロパディングして文字列として返す。
     *
     * @param fromValue 元の整数値。
     * @param digits    最低桁数。
     * @return ゼロパディングされた文字列。
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
