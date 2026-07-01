//+------------------------------------------------------------------+
//|                                                 PipConverter.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>

class PipConverter {
public:
   /**
    * 市場コンテキストを使用してpipsを円換算する。
    *
    * @param fromMarketContext 換算対象の市場コンテキスト
    * @param fromPips pips
    * @param fromLotSize ロットサイズ
    * @param fromJpyAmount 円換算結果
    * @return 換算成功時はtrue
    */
   static bool tryConvertPipsToJpy(
      MarketContext &fromMarketContext,
      double fromPips,
      double fromLotSize,
      double &fromJpyAmount
   ) {
      fromJpyAmount = 0.0;

      string normalizedSymbol = normalizeSymbol(fromMarketContext.symbolName);
      if (!isValidSymbol(normalizedSymbol)) {
         return false;
      }

      string quoteCurrency = getQuoteCurrency(normalizedSymbol);
      double pipSize = getPipSize(quoteCurrency);
      double quoteAmount = fromLotSize * pipSize * fromPips;

      if (quoteCurrency == "JPY") {
         fromJpyAmount = quoteAmount;
         return true;
      }

      return tryConvertQuoteAmountToJpy(quoteCurrency, quoteAmount, fromJpyAmount);
   }

   static bool tryConvertPipsToJpy(string symbolName, double pips, double lotSize, double &jpyAmount) {
      MarketContext context(symbolName, PERIOD_CURRENT);

      return PipConverter::tryConvertPipsToJpy(context, pips, lotSize, jpyAmount);
   }

private:
   static string normalizeSymbol(string symbolName) {
      string normalizedSymbol = symbolName;
      StringToUpper(normalizedSymbol);
      StringReplace(normalizedSymbol, "/", "");
      return normalizedSymbol;
   }

   static bool isValidSymbol(string normalizedSymbol) {
      return StringLen(normalizedSymbol) == 6;
   }

   static string getQuoteCurrency(string normalizedSymbol) {
      return StringSubstr(normalizedSymbol, 3, 3);
   }

   static double getPipSize(string quoteCurrency) {
      if (quoteCurrency == "JPY") {
         return 0.01;
      }

      return 0.0001;
   }

   static bool tryConvertQuoteAmountToJpy(string quoteCurrency, double quoteAmount, double &jpyAmount) {
      string directSymbol = quoteCurrency + "JPY";
      double directBidPrice = 0.0;

      if (tryGetBidPrice(directSymbol, directBidPrice)) {
         jpyAmount = quoteAmount * directBidPrice;
         return true;
      }

      string inverseSymbol = "JPY" + quoteCurrency;
      double inverseBidPrice = 0.0;

      if (tryGetBidPrice(inverseSymbol, inverseBidPrice) && inverseBidPrice > 0.0) {
         jpyAmount = quoteAmount / inverseBidPrice;
         return true;
      }

      return false;
   }

   static bool tryGetBidPrice(string symbolName, double &bidPrice) {
      bidPrice = 0.0;

      if (!SymbolSelect(symbolName, true)) {
         return false;
      }

      return SymbolInfoDouble(symbolName, SYMBOL_BID, bidPrice);
   }
};
