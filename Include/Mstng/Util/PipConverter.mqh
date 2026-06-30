//+------------------------------------------------------------------+
//|                                                 PipConverter.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

class PipConverter {
public:
   static bool tryConvertPipsToJpy(string symbolName, double pips, double lotSize, double &jpyAmount) {
      jpyAmount = 0.0;

      string normalizedSymbol = normalizeSymbol(symbolName);
      if (!isValidSymbol(normalizedSymbol)) {
         return false;
      }

      string quoteCurrency = getQuoteCurrency(normalizedSymbol);
      double pipSize = getPipSize(quoteCurrency);
      double quoteAmount = lotSize * pipSize * pips;

      if (quoteCurrency == "JPY") {
         jpyAmount = quoteAmount;
         return true;
      }

      return tryConvertQuoteAmountToJpy(quoteCurrency, quoteAmount, jpyAmount);
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