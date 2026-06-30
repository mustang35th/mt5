//+------------------------------------------------------------------+
//|                                               DrawRoundLines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawUtil.mqh>
#include <Mstng\Util\RateUtil.mqh>

/**
 * 現在価格を基準に50pips間隔および100pips間隔の水平線を描画するクラス。
 */
class DrawRoundLines {
public:
    /**
     * シンボル名を指定して初期化する。
     *
     * @param fromSymbolName 描画対象のシンボル名
     */
    DrawRoundLines(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);
        this.initialize(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    DrawRoundLines(MarketContext &fromMarketContext) {
        this.initialize(fromMarketContext);
    }

    /**
     * 現在価格の上下へラウンドナンバーラインを描画する。
     */
    void draw() {
        double basePrice = this.getBasePrice();
        double stepPrice50Pips = RateUtil::pipsToPrice(STEP_50_PIPS, this.marketContext.symbolName);
        double anchorPrice = this.getAnchorPrice(basePrice, stepPrice50Pips);
        
        for (int i = -this.linesEachSide; i <= this.linesEachSide; i++) {
            double linePrice = NormalizeDouble(anchorPrice + (stepPrice50Pips * i), this.getDigits());
            bool is100PipsLine = this.is100PipsLine(linePrice);
            
            this.drawHorizontalLine(linePrice, is100PipsLine);
        }
    }

private:
    /** 水平線の太さ */
    static const int LINE_WIDTH;

    /** 50pipsラインの間隔 */
    static const int STEP_50_PIPS;

    /** 100pipsラインの間隔 */
    static const int STEP_100_PIPS;
    
    /** 描画対象の市場コンテキスト */
    MarketContext marketContext;

    /** 100pipsラインの色 */
    color color100Pips;

    /** 50pipsラインの色 */
    color color50Pips;

    /** 現在価格の上下へ描画する本数 */
    int linesEachSide;

    /** 基準価格にBidを使用する場合true */
    bool useBidPrice;

    /** 描画対象のチャートID */
    long chartId;

    /**
     * 描画設定を初期化する。
     *
     * @param fromSymbolName 描画対象のシンボル名
     */
    void initialize(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);
        this.initialize(context);
    }

    /**
     * 市場コンテキストと描画設定を初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void initialize(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
        this.color100Pips = clrGold;
        this.color50Pips = clrGold;
        this.linesEachSide = 5;
        this.useBidPrice = true;
        this.chartId = 0;
    }

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }
   
    /**
     * 水平線計算の基準価格を取得する。
     *
     * @return BidまたはAsk
     */
    double getBasePrice() {
        return useBidPrice
            ? SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_BID)
            : SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_ASK);
    }

    /**
     * 描画対象シンボルの小数桁数を取得する。
     *
     * @return 小数桁数
     */
    int getDigits() {
        return this.marketContext.digits;
    }

    /**
     * 基準価格以下で最も近いライン価格を取得する。
     *
     * @param basePrice 基準価格
     * @param stepPrice ライン間隔の価格幅
     * @return アンカー価格
     */
    double getAnchorPrice(double basePrice, double stepPrice) {
        return MathFloor(basePrice / stepPrice) * stepPrice;
    }

    /**
     * 指定価格が100pipsラインに該当するか判定する。
     *
     * @param price 判定対象価格
     * @return 100pipsラインの場合true
     */
    bool is100PipsLine(double price) {
        double stepPrice100Pips = RateUtil::pipsToPrice(STEP_100_PIPS, this.marketContext.symbolName);
        double ratio = price / stepPrice100Pips;
        
        return MathAbs(ratio - MathRound(ratio)) < 0.0000001;
    }

    /**
     * 指定価格へ水平線を描画する。
     *
     * @param price 描画価格
     * @param is100PipsLine 100pipsラインの場合true
     */
    void drawHorizontalLine(double price, bool is100PipsLine) {
        DrawUtil::setHLine(
            createObjectName(price, is100PipsLine),
            price,
            is100PipsLine ? color100Pips : color50Pips,
            is100PipsLine ? STYLE_SOLID : STYLE_DOT,
            LINE_WIDTH,
            (int)chartId
        );
    }

    /**
     * 水平線のオブジェクト名を生成する。
     *
     * @param price 描画価格
     * @param is100PipsLine 100pipsラインの場合true
     * @return オブジェクト名
     */
    string createObjectName(double price, bool is100PipsLine) {
        string prefix = is100PipsLine ? "ROUND_100_" : "ROUND_050_";
        return prefix + IntegerToString((int)MathRound(price / SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_POINT)));
    }
};

const int DrawRoundLines::LINE_WIDTH = 1;
const int DrawRoundLines::STEP_50_PIPS = 50;
const int DrawRoundLines::STEP_100_PIPS = 100;
