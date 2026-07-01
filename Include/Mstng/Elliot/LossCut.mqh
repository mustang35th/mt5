//+------------------------------------------------------------------+
//|                                                      LossCut.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Util\TodayRate.mqh>

// ロスカット
/**
 * 最新Elliottポイントを基準にロスカット価格を算出するクラス。
 *
 * 売買方向に応じて基準価格を選び、複数のpips余裕を加えた候補を保持する。
 */
class LossCut {
public:
    /** ロスカット計算対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** 売買方向。true: BUY、false: SELL */
    bool isBuy;
    
    /** ロスカット距離の計算基準レート。BUYはAsk、SELLはBid */
    double rate;
    
    /** 基準レートからlc0までの距離。単位: pips */
    double diff;

    /** diffを100通貨分の円へ換算した参考金額 */
    double diffJpy;
    
    /** 1つ前のZigZagポイントを使用した基準ロスカット価格 */
    double lc0;

    /** lc0から損失方向へ5pipsずらしたロスカット価格 */
    double lc5;

    /** lc0から損失方向へ10pipsずらしたロスカット価格 */
    double lc10;

    /** lc0から損失方向へ15pipsずらしたロスカット価格 */
    double lc15;
    
    // コンストラクタ
    //LossCut(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
    LossCut() {
        this.logger.setLevel(LOG_INFO);
        
        this.rate = 0;
        
        this.diff = 0;
        this.diffJpy = 0;
        
        this.lc0 = 0;
        this.lc5 = 0;
        this.lc10 = 0;
        this.lc15 = 0;
    }
    
    // デストラクタ
    ~LossCut() {
    }
    
    /** @return ロスカット候補を含む表示用テキスト */
    string getText() {
        string text = "";
        
        int digits = this.marketContext.digits;
        
        text += StringFormat("Loss Cut %s\n" ,this.marketContext.timeFrameLabel);
        text += StringFormat("diff = %spips\n", DoubleToString(diff, 1));
        
        if (this.diffJpy > 0) {
            text += StringFormat("diffJpy = %spips\n", DoubleToString(diffJpy, 1));
        }
        
        text += "\n";
        
        text += StringFormat("0 -> %s\n", DoubleToString(lc0,  digits));
        text += StringFormat("5 -> %s\n", DoubleToString(lc5,  digits));
        text += StringFormat("10-> %s\n", DoubleToString(lc10, digits));
        text += StringFormat("15-> %s\n", DoubleToString(lc15, digits));
    
        return text;
    }
        
    /**
     * Elliott分析結果と現在レートからロスカット候補を設定する。
     *
     * @param elliot 現在時間足のElliott分析結果
     * @param todayRate 現在のBid・Ask情報
     */
    void setData(Elliot &elliot, TodayRate &todayRate) {
        this.initializeMarketContext(elliot.marketContext);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        ZigZagPoint *latestZigZagPoint2 = elliot.getLatestPoint2();
        
        if (latestZigZagPoint2 == NULL) {
            return;
        }
        
        this.isBuy = elliot.isBuy;
        
        this.lc0 = latestZigZagPoint2.rate;
        
        this.rate = todayRate.bid;    // 初期は売り
                                
        if (this.isBuy) {
            this.rate = todayRate.ask;
        }
        
        this.diff = RateUtil::getDiffPips(this.rate, this.lc0, this.marketContext);
        
        if (!this.marketContext.isJpy()) {
            double jpyAmount = 0.0;
    
            if (PipConverter::tryConvertPipsToJpy(this.marketContext, this.diff, 100, jpyAmount)) {
                this.diffJpy = (int)MathRound(jpyAmount);
            }
        }
        
        this.lc5 = lc0 + RateUtil::getOffset(this.isBuy, 5, this.marketContext);
        this.lc10 = lc0 + RateUtil::getOffset(this.isBuy, 10, this.marketContext);
        this.lc15 = lc0 + RateUtil::getOffset(this.isBuy, 15, this.marketContext);
        
        this.logger.debug(__FUNCTION__, StringFormat("%s", this.toString()));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * @brief 内容を文字列化して返します。
     *
     * @param digits 価格系の表示桁数（未指定時はシンボル桁 or _Digits）
     * @return "LossCut{...}" 形式の文字列
     */
    string toString(const int digits = -1) const {
        int displayDigits = digits;

        if (displayDigits < 0) {
            displayDigits = _Digits;

            if (this.marketContext.symbolName != "") {
                displayDigits = this.marketContext.digits;
            }
        }

        string isBuyText = "false";

        if (this.isBuy) {
            isBuyText = "true";
        }

        return StringFormat(
            "LossCut{symbol=%s, tf=%s, tfLabel=%s, isBuy=%s, rate=%.*f, diff=%.*f, lc0=%.*f, lc5=%.*f, lc10=%.*f, lc15=%.*f}",
            this.marketContext.symbolName,
            EnumToString(this.marketContext.timeFrame),
            this.marketContext.timeFrameLabel,
            isBuyText,
            displayDigits, rate,
            displayDigits, diff,
            displayDigits, lc0,
            displayDigits, lc5,
            displayDigits, lc10,
            displayDigits, lc15
        );
    }
    
private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext ロスカット計算対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setMarketContext(this.marketContext);
    }
};







