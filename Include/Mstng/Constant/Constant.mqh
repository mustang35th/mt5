//+------------------------------------------------------------------+
//|                                                     Constant.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * アプリケーション全体で使用する共通定数を集約するクラス。
 *
 * インスタンスを生成せずにConstant::PREFIXなどの形式で参照する。
 */
class Constant {
public:
    /** 共通のプレフィックス文字列。 */
    static const string PREFIX;

    /** 固定プレフィックス文字列。 */
    static const string PREFIX_FIXED;
    
    /** 削除フラグ。 */
    static const int DELETE_FLG;
    
    /** 非表示ラベル。 */
    static const string DELETE_LABEL;
    
    /**
     * BUYまたはSELLのラベル文字列を取得する。
     *
     * @param fromIsBuy BUYの場合true。
     * @return ラベル文字列。
     */
    static string getBuySell(bool fromIsBuy) {
        string text = "SELL";
        
        if (fromIsBuy) {
            text = "BUY";
        }
        
        return text;
    }
};

// static定数の定義部。
const string Constant::PREFIX = "Mstng";
const string Constant::PREFIX_FIXED = "FixedMstng";

const int Constant::DELETE_FLG = -1;
const string Constant::DELETE_LABEL = "NON";
