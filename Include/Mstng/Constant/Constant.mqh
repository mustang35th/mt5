//+------------------------------------------------------------------+
//|                                                     Constant.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * Constant クラスは、アプリケーション全体で使用する
 * 文字列定数を集約して管理するためのクラスです。
 *
 * 完全に static な定数として利用することを想定しており、
 * インスタンスを生成せずに Constant::PREFIX などの形式で参照します。
 */
class Constant {
public:
    /** 共通のプレフィックス文字列 */
    static const string PREFIX;

    /** 固定プレフィックス文字列 */
    static const string PREFIX_FIXED;
    
    /** 削除フラグ */
    static const int DELETE_FLG;
    
    /** 非表示ラベル */
    static const string DELETE_LABEL;
    
    /**
     * BUY/Sell ラベル文字列を取得する。
     *
     * @param isBuy BUYなら"BUY"、SELLなら"SELL"
     * @return ラベル文字列
     */
    static string getBuySell(bool isBuy) {
        string text = "SELL";
        
        if (isBuy) {
            text = "BUY";
        }
        
        return text;
    }
};

/** static 定数の定義部 */
const string Constant::PREFIX = "Mstng";
const string Constant::PREFIX_FIXED = "FixedMstng";

const int Constant::DELETE_FLG = -1;
const string Constant::DELETE_LABEL = "NON";
