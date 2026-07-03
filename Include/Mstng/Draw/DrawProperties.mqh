//+------------------------------------------------------------------+
//|                                               DrawProperties.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#include <Mstng\Util\UtilAll.mqh>

/**
 * 描画文字スタイルや色などの共通表示設定を保持する値オブジェクトです。
 */
class DrawProperties {
public:
    /** Elliotの描画に使うフォント名 */
    string elliotFontFace;
    /** Elliotラベル（アラート）文字サイズ */
    int elliotAlertSize;
    /** Elliot文字の基本サイズ */
    int elliotFontSize;
    /** Elliotラベルの文字間隔（ピクセル） */
    int elliotPixelDistance;
    /** フォントサイズ計算用ピクセル高さ */
    uint fontPixelHeight;

    /** 上昇判定時のラベル色 */
    color elliotUpColor;
    /** 下降判定時のラベル色 */
    color elliotDownColor;
    /** 未確定上昇ラベル色 */
    color elliotMikakuteiUpColor;
    /** 未確定下降ラベル色 */
    color elliotMikakuteiDownColor;
    
    /** 右寄せラベル描画時のX基準座標 */
    int objXRight;
    
    /**
     * 描画プロパティを初期化する。
     */
    DrawProperties() {
        this.logger.setLevel(LOG_INFO);
        
        this.elliotFontFace = "MS Gothic";
        this.elliotAlertSize = 35;
        this.elliotFontSize = 12;
        this.elliotPixelDistance = 3;
        this.fontPixelHeight = 0;

        this.elliotUpColor = clrAqua;
        this.elliotDownColor = clrHotPink;
        this.elliotMikakuteiUpColor = clrDodgerBlue;
        this.elliotMikakuteiDownColor = clrMagenta;
        
        this.objXRight = 1600;
        
        this.setFontPixelHeight();
    }

    /**
     * デフォルトコンストラクタの対となるデストラクタ。
     */
    ~DrawProperties() {
    }
    
    /**
     * フォントピクセル高さを再計測して保持します。
     */
    void setFontPixelHeight() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        string text = "0";

        // MQL4の「* -11」相当は、MT5では一般に「-10倍」が慣習です。
        // 例：12px相当なら -120（=12* -10）
        // MQL5公式も「Arial -120(12pt)」の例を示しています。
        TextSetFont(this.elliotFontFace, this.elliotFontSize * -10, 0, 0);  // flags=0, angle=0
        
        uint w = 0;
        uint h = 0;
        TextGetSize(text, w, h);
        
        this.fontPixelHeight = h;
                
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
private:
    /** ロガー。 */
    Logger logger;
};
