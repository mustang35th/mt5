//+------------------------------------------------------------------+
//|                                         DrawPropertiesElliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>

/**
 * Elliot描画テーブルの列表示設定を保持する設定クラスです。
 */
class DrawPropertiesElliot : public CObject {
public:
    /** 表示するか */
    bool isVisible;
    /** 列幅（ピクセル） */
    int width;
    
    /**
     * 表示設定を初期化する。
     *
     * @param fromIsVisible 表示する場合true
     * @param fromWidth 列幅
     */
    DrawPropertiesElliot(bool fromIsVisible, int fromWidth) {
        this.isVisible = fromIsVisible;
        this.width = fromWidth;
    }

    /**
     * デストラクタ。
     */
    ~DrawPropertiesElliot() {
    }
};
