#ifndef MSTNGH1EA_RUNTIME_TRADETRANSACTIONROUTER_MQH
#define MSTNGH1EA_RUNTIME_TRADETRANSACTIONROUTER_MQH

/**
 * 取引通知から対象銘柄を特定する読取専用アダプター。
 * REQUESTではrequest/resultだけを参照し、magicで手動SL通知を除外しない。
 */
class H1EaTradeTransactionRouter {
public:
    /**
     * 通知に明示された銘柄を返す。REQUEST以外のrequest/resultは読まない。
     */
    static string explicitSymbol(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest) {
        if (fromTransaction.type == TRADE_TRANSACTION_REQUEST) {
            return fromRequest.symbol;
        }
        return fromTransaction.symbol;
    }

    /**
     * 銘柄省略時にticketから補完する。取引・履歴照合・DB保存は行わない。
     */
    static string resolveSymbol(const MqlTradeTransaction &fromTransaction,
            const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
        string symbol = H1EaTradeTransactionRouter::explicitSymbol(fromTransaction, fromRequest);
        if (symbol != "") {
            return symbol;
        }
        if (fromTransaction.type == TRADE_TRANSACTION_REQUEST) {
            symbol = H1EaTradeTransactionRouter::positionSymbol(fromRequest.position);
            if (symbol == "") {
                symbol = H1EaTradeTransactionRouter::positionSymbol(fromRequest.position_by);
            }
            if (symbol == "") {
                symbol = H1EaTradeTransactionRouter::orderSymbol(fromRequest.order);
            }
            if (symbol == "") {
                symbol = H1EaTradeTransactionRouter::orderSymbol(fromResult.order);
            }
            if (symbol == "") {
                symbol = H1EaTradeTransactionRouter::dealSymbol(fromResult.deal);
            }
            return symbol;
        }
        symbol = H1EaTradeTransactionRouter::dealSymbol(fromTransaction.deal);
        if (symbol == "") {
            symbol = H1EaTradeTransactionRouter::orderSymbol(fromTransaction.order);
        }
        if (symbol == "") {
            symbol = H1EaTradeTransactionRouter::positionSymbol(fromTransaction.position);
        }
        if (symbol == "") {
            symbol = H1EaTradeTransactionRouter::positionSymbol(fromTransaction.position_by);
        }
        return symbol;
    }

private:
    /**
     * 現在のポジションticketから銘柄を読む。identifierとticketを混同しない。
     */
    static string positionSymbol(const ulong fromTicket) {
        if (fromTicket > 0 && PositionSelectByTicket(fromTicket)) {
            return PositionGetString(POSITION_SYMBOL);
        }
        return "";
    }

    /**
     * 稼働中と履歴の両方から注文銘柄を読む。
     */
    static string orderSymbol(const ulong fromTicket) {
        if (fromTicket == 0) {
            return "";
        }
        if (OrderSelect(fromTicket)) {
            return OrderGetString(ORDER_SYMBOL);
        }
        if (HistoryOrderSelect(fromTicket)) {
            return HistoryOrderGetString(fromTicket, ORDER_SYMBOL);
        }
        return "";
    }

    /**
     * 決済後の通知も約定履歴から銘柄を読む。
     */
    static string dealSymbol(const ulong fromTicket) {
        if (fromTicket > 0 && HistoryDealSelect(fromTicket)) {
            return HistoryDealGetString(fromTicket, DEAL_SYMBOL);
        }
        return "";
    }
};

#endif
