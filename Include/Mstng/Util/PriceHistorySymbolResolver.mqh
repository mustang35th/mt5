#ifndef MSTNG_PRICE_HISTORY_SYMBOL_RESOLVER_MQH
#define MSTNG_PRICE_HISTORY_SYMBOL_RESOLVER_MQH

/**
 * 価格履歴を参照する通貨ペアの正規名を、口座の実銘柄名に解決する。
 */
class PriceHistorySymbolResolver {
public:
    /**
     * 正規名を優先し、接頭辞・接尾辞付き銘柄は通貨属性と一意性を確認する。
     *
     * @param fromCanonicalSymbolName 基軸通貨と決済通貨を連ねた6文字の正規名。
     * @return 気配値表示に選択した銘柄名。未解決または候補が曖昧なら空文字。
     */
    static string resolve(const string fromCanonicalSymbolName) {
        string baseCurrency = StringSubstr(fromCanonicalSymbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromCanonicalSymbolName, 3, 3);
        bool custom = false;
        if (SymbolExist(fromCanonicalSymbolName, custom) && !custom
                && SymbolSelect(fromCanonicalSymbolName, true)
                && SymbolInfoString(fromCanonicalSymbolName, SYMBOL_CURRENCY_BASE) == baseCurrency
                && SymbolInfoString(fromCanonicalSymbolName, SYMBOL_CURRENCY_PROFIT) == quoteCurrency) {
            return fromCanonicalSymbolName;
        }

        string foundSymbol = "";
        int shortestLength = 0;
        bool ambiguous = false;
        int total = SymbolsTotal(false);
        for (int i = 0; i < total; i++) {
            string candidate = SymbolName(i, false);
            string upperCandidate = candidate;
            StringToUpper(upperCandidate);
            if (candidate == "" || StringFind(upperCandidate, fromCanonicalSymbolName) < 0
                    || !SymbolExist(candidate, custom) || custom
                    || !SymbolSelect(candidate, true)
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_BASE) != baseCurrency
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_PROFIT) != quoteCurrency) {
                continue;
            }

            int length = StringLen(candidate);
            if (foundSymbol == "" || length < shortestLength) {
                foundSymbol = candidate;
                shortestLength = length;
                ambiguous = false;
            } else if (length == shortestLength && candidate != foundSymbol) {
                ambiguous = true;
            }
        }

        if (foundSymbol == "" || ambiguous || !SymbolSelect(foundSymbol, true)) {
            return "";
        }

        return foundSymbol;
    }
};

#endif // MSTNG_PRICE_HISTORY_SYMBOL_RESOLVER_MQH
