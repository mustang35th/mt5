//+------------------------------------------------------------------+
//|                                                 PipConverter.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>

/**
 * pips 価格を日本円換算するためのユーティリティクラス。
 */
class PipConverter {
public:
    /**
     * 市場コンテキストを使用して pips を円換算する。
     *
     * @param fromMarketContext 換算対象の市場コンテキスト
     * @param fromPips        pips
     * @param fromLotSize ロットサイズ
     * @param fromJpyAmount   円換算結果（出力）
     * @return 換算成功時は true。
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

    /**
     * シンボル名を使って pips を円換算する。
     *
     * @param fromSymbolName  換算対象シンボル名
     * @param fromPips       pips
     * @param fromLotSize    ロットサイズ
     * @param fromJpyAmount  円換算結果（出力）
     * @return 換算成功時は true。
     */
    static bool tryConvertPipsToJpy(string fromSymbolName, double fromPips, double fromLotSize, double &fromJpyAmount) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return PipConverter::tryConvertPipsToJpy(context, fromPips, fromLotSize, fromJpyAmount);
    }

private:
    /**
     * シンボル名を大文字化し、区切りを除去して標準化する。
     *
     * @param fromSymbolName 対象シンボル名
     * @return 正規化済みシンボル名
     */
    static string normalizeSymbol(string fromSymbolName) {
        string normalizedSymbol = fromSymbolName;

        StringToUpper(normalizedSymbol);
        StringReplace(normalizedSymbol, "/", "");

        return normalizedSymbol;
    }

    /**
     * 正規化シンボル名が6文字かどうかを検証する。
     *
     * @param fromNormalizedSymbol 正規化済みシンボル名
     * @return 6文字なら true、そうでなければ false。
     */
    static bool isValidSymbol(string fromNormalizedSymbol) {
        return StringLen(fromNormalizedSymbol) == 6;
    }

    /**
     * クォート通貨を取得する。
     *
     * @param fromNormalizedSymbol 正規化済みシンボル名
     * @return 右3文字（クォート通貨）
     */
    static string getQuoteCurrency(string fromNormalizedSymbol) {
        return StringSubstr(fromNormalizedSymbol, 3, 3);
    }

    /**
     * クォート通貨ごとの1 pip を金額で表した大きさを取得する。
     *
     * @param fromQuoteCurrency クォート通貨
     * @return pips金額（JPYなら0.01、その他0.0001）
     */
    static double getPipSize(string fromQuoteCurrency) {
        if (fromQuoteCurrency == "JPY") {
            return 0.01;
        }

        return 0.0001;
    }

    /**
     * JPY換算を試行する。
     *
     * @param fromQuoteCurrency クォート通貨
     * @param fromQuoteAmount  金額
     * @param fromJpyAmount    換算結果（出力）
     * @return 変換成功時 true、失敗時 false。
     */
    static bool tryConvertQuoteAmountToJpy(
        string fromQuoteCurrency,
        double fromQuoteAmount,
        double &fromJpyAmount
    ) {
        string directSymbol = fromQuoteCurrency + "JPY";
        double directBidPrice = 0.0;

        if (tryGetBidPrice(directSymbol, directBidPrice)) {
            fromJpyAmount = fromQuoteAmount * directBidPrice;
            return true;
        }

        string inverseSymbol = "JPY" + fromQuoteCurrency;
        double inverseBidPrice = 0.0;

        if (tryGetBidPrice(inverseSymbol, inverseBidPrice) && inverseBidPrice > 0.0) {
            fromJpyAmount = fromQuoteAmount / inverseBidPrice;
            return true;
        }

        return false;
    }

    /**
     * 指定シンボルでBid価格を取得する。
     *
     * @param fromSymbolName シンボル名
     * @param fromBidPrice Bid取得先（出力）
     * @return Bid取得成功時 true、失敗時 false。
     */
    static bool tryGetBidPrice(string fromSymbolName, double &fromBidPrice) {
        fromBidPrice = 0.0;

        if (!SymbolSelect(fromSymbolName, true)) {
            return false;
        }

        return SymbolInfoDouble(fromSymbolName, SYMBOL_BID, fromBidPrice);
    }
};
