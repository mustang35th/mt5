//+------------------------------------------------------------------+
//|                                               SymbolNameInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __SYMBOL_NAME_INFO_MQH__
#define __SYMBOL_NAME_INFO_MQH__

#include <Object.mqh>

/**
 * 通貨ペア1件分のシンボル情報を保持するクラス。
 */
class SymbolNameInfo : public CObject {
public:
    /** シンボル名 */
    string symbolName;

    /** コード */
    int code;

    /** 取引対象可否 */
    bool isTarget;
    
    /**
     * コンストラクタ。
     *
     * @param fromSymbolName シンボル名
     * @param fromCode コード
     * @param fromIsTarget 取引対象フラグ
     */
    SymbolNameInfo(string fromSymbolName, int fromCode, bool fromIsTarget) {
        this.symbolName = fromSymbolName;
        this.code = fromCode;
        this.isTarget = fromIsTarget;
    }
    
    /** デストラクタ。 */
    ~SymbolNameInfo() {
    }

    /**
     * 文字列表現を返す
     *
     * 例:
     *  "symbolName=USDJPY code=1 isTarget=true"
     */
    string toString() {
        string isTargetText = "false";

        if (this.isTarget) {
            isTargetText = "true";
        }

        string text = StringFormat("symbolName=%s code=%d isTarget=%s",
                                   this.symbolName,
                                   this.code,
                                   isTargetText);
        
        return text;
    }
};

#endif // __SYMBOL_NAME_INFO_MQH__
