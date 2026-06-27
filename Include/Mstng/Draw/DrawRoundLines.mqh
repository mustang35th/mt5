//+------------------------------------------------------------------+
//|                                               DrawRoundLines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Draw\DrawUtil.mqh>
#include <Mstng\Util\RateUtil.mqh>

class DrawRoundLines {
public:
    DrawRoundLines(string fromSymbolName) {
        this.symbolName = fromSymbolName;
        this.color100Pips = clrGold;
        this.color50Pips = clrGold;
        this.linesEachSide = 5;
        this.useBidPrice = true;
        this.chartId = 0;
    }
    
    void draw() {
        double basePrice = this.getBasePrice();
        double stepPrice50Pips = RateUtil::pipsToPrice(STEP_50_PIPS, symbolName);
        double anchorPrice = this.getAnchorPrice(basePrice, stepPrice50Pips);
        
        for (int i = -this.linesEachSide; i <= this.linesEachSide; i++) {
            double linePrice = NormalizeDouble(anchorPrice + (stepPrice50Pips * i), this.getDigits());
            bool is100PipsLine = this.is100PipsLine(linePrice);
            
            this.drawHorizontalLine(linePrice, is100PipsLine);
        }
    }

private:
    static const int LINE_WIDTH;
    static const int STEP_50_PIPS;
    static const int STEP_100_PIPS;
    
    string symbolName;
    color color100Pips;
    color color50Pips;
    int linesEachSide;
    bool useBidPrice;
    long chartId;
   
    double getBasePrice() {
        return useBidPrice
            ? SymbolInfoDouble(symbolName, SYMBOL_BID)
            : SymbolInfoDouble(symbolName, SYMBOL_ASK);
    }

    int getDigits() {
        return RateUtil::getDigits(symbolName);
    }

    double getAnchorPrice(double basePrice, double stepPrice) {
        return MathFloor(basePrice / stepPrice) * stepPrice;
    }

    bool is100PipsLine(double price) {
        double stepPrice100Pips = RateUtil::pipsToPrice(STEP_100_PIPS, symbolName);
        double ratio = price / stepPrice100Pips;
        
        return MathAbs(ratio - MathRound(ratio)) < 0.0000001;
    }

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

    string createObjectName(double price, bool is100PipsLine) {
        string prefix = is100PipsLine ? "ROUND_100_" : "ROUND_050_";
        return prefix + IntegerToString((int)MathRound(price / SymbolInfoDouble(symbolName, SYMBOL_POINT)));
    }
};

const int DrawRoundLines::LINE_WIDTH = 1;
const int DrawRoundLines::STEP_50_PIPS = 50;
const int DrawRoundLines::STEP_100_PIPS = 100;