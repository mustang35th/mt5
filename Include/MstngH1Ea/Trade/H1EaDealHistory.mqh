#ifndef MSTNGH1EA_TRADE_H1EADEALHISTORY_MQH
#define MSTNGH1EA_TRADE_H1EADEALHISTORY_MQH

/**
 * 履歴選択の変更後も集計・監査保存に利用できる、取得確認済みの約定値。
 */
struct H1EaDealSnapshot {
    /** 約定ticket。 */
    ulong ticket;
    /** 約定元の注文ticket。 */
    ulong orderTicket;
    /** 安定したPosition ID。 */
    ulong positionIdentifier;
    /** 約定のMagic。手動操作では0を許容する。 */
    ulong magic;
    /** 約定シンボル。 */
    string symbol;
    /** DEAL_ENTRY。 */
    long entry;
    /** DEAL_TYPE。 */
    long type;
    /** DEAL_REASON。 */
    long reason;
    /** 約定時刻のミリ秒。 */
    long timeMsc;
    /** 約定数量。 */
    double volume;
    /** 約定価格。 */
    double price;
    /** 損益。 */
    double profit;
    /** commission。 */
    double commission;
    /** swap。 */
    double swap;
    /** fee。 */
    double fee;

    /**
     * 未取得値へ明示的に初期化する。
     */
    H1EaDealSnapshot() {
        this.reset();
    }

    /**
     * 取得途中の値を成功結果として残さない。
     */
    void reset() {
        this.ticket = 0;
        this.orderTicket = 0;
        this.positionIdentifier = 0;
        this.magic = 0;
        this.symbol = "";
        this.entry = 0;
        this.type = 0;
        this.reason = 0;
        this.timeMsc = 0;
        this.volume = 0.0;
        this.price = 0.0;
        this.profit = 0.0;
        this.commission = 0.0;
        this.swap = 0.0;
        this.fee = 0.0;
    }
};

/**
 * broker履歴の選択と取得成否を確認し、確定した値だけを呼出元へ渡す。
 * 注文送信・DB保存・Trade状態変更は行わない。
 */
class H1EaDealHistory {
public:
    /**
     * 指定ticketを再選択し、必要な全項目を取得する。失敗時は出力を空にする。
     */
    static bool read(const ulong fromTicket, H1EaDealSnapshot &fromDeal, string &fromFailure) {
        fromDeal.reset();
        fromFailure = "";
        if (fromTicket == 0) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_TICKET", 0, "INVALID_TICKET", fromFailure);
        }
        ResetLastError();
        if (!HistoryDealSelect(fromTicket)) {
            return H1EaDealHistory::fail(fromTicket, "HistoryDealSelect", GetLastError(),
                "SELECT_FAILED", fromFailure);
        }
        H1EaDealSnapshot candidate;
        long actualTicket = 0;
        long orderTicket = 0;
        long positionIdentifier = 0;
        long magic = 0;
        if (!H1EaDealHistory::readInteger(fromTicket, DEAL_TICKET, actualTicket, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_ORDER, orderTicket, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_POSITION_ID, positionIdentifier, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_MAGIC, magic, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_ENTRY, candidate.entry, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_TYPE, candidate.type, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_REASON, candidate.reason, fromFailure)
                || !H1EaDealHistory::readInteger(fromTicket, DEAL_TIME_MSC, candidate.timeMsc, fromFailure)) {
            return false;
        }
        candidate.ticket = (ulong)actualTicket;
        candidate.orderTicket = (ulong)orderTicket;
        candidate.positionIdentifier = (ulong)positionIdentifier;
        candidate.magic = (ulong)magic;
        ResetLastError();
        if (!HistoryDealGetString(fromTicket, DEAL_SYMBOL, candidate.symbol)) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_SYMBOL", GetLastError(),
                "GETTER_FAILED", fromFailure);
        }
        if (!H1EaDealHistory::readDouble(fromTicket, DEAL_VOLUME, candidate.volume, fromFailure)
                || !H1EaDealHistory::readDouble(fromTicket, DEAL_PRICE, candidate.price, fromFailure)
                || !H1EaDealHistory::readDouble(fromTicket, DEAL_PROFIT, candidate.profit, fromFailure)
                || !H1EaDealHistory::readDouble(fromTicket, DEAL_COMMISSION, candidate.commission, fromFailure)
                || !H1EaDealHistory::readDouble(fromTicket, DEAL_SWAP, candidate.swap, fromFailure)
                || !H1EaDealHistory::readDouble(fromTicket, DEAL_FEE, candidate.fee, fromFailure)) {
            return false;
        }
        if (candidate.ticket != fromTicket) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_TICKET", 0, "TICKET_MISMATCH", fromFailure);
        }
        if (candidate.positionIdentifier == 0) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_POSITION_ID", 0, "INVALID_POSITION_ID", fromFailure);
        }
        if (candidate.timeMsc <= 0) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_TIME_MSC", 0, "INVALID_TIME", fromFailure);
        }
        if (StringLen(candidate.symbol) == 0) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_SYMBOL", 0, "EMPTY_SYMBOL", fromFailure);
        }
        bool tradingDeal = candidate.type == DEAL_TYPE_BUY || candidate.type == DEAL_TYPE_SELL;
        if (tradingDeal && candidate.orderTicket == 0) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_ORDER", 0, "INVALID_ORDER_TICKET", fromFailure);
        }
        if (candidate.volume < 0.0 || (tradingDeal && candidate.volume == 0.0)) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_VOLUME", 0, "INVALID_VOLUME", fromFailure);
        }
        if (candidate.price < 0.0 || (tradingDeal && candidate.price == 0.0)) {
            return H1EaDealHistory::fail(fromTicket, "DEAL_PRICE", 0, "INVALID_PRICE", fromFailure);
        }
        fromDeal = candidate;
        return true;
    }

    /**
     * Positionの全ticketを退避してから各約定を再選択する。
     * 1件でも取得・識別に失敗した場合、部分的な配列を呼出元へ渡さない。
     */
    static bool readPosition(const ulong fromIdentifier, const string fromSymbol,
            H1EaDealSnapshot &fromDeals[], string &fromFailure) {
        fromFailure = "";
        ArrayResize(fromDeals, 0);
        if (fromIdentifier == 0 || StringLen(fromSymbol) == 0) {
            return H1EaDealHistory::fail(0, "POSITION_SCOPE", 0, "INVALID_SCOPE", fromFailure);
        }
        ResetLastError();
        if (!HistorySelectByPosition(fromIdentifier)) {
            return H1EaDealHistory::fail(0, "HistorySelectByPosition", GetLastError(),
                "SELECT_FAILED position=" + StringFormat("%I64u", fromIdentifier), fromFailure);
        }
        int total = HistoryDealsTotal();
        ulong tickets[];
        ResetLastError();
        if (total < 0 || ArrayResize(tickets, total) != total) {
            return H1EaDealHistory::fail(0, "TICKET_ARRAY", GetLastError(), "ALLOCATION_FAILED", fromFailure);
        }
        for (int i = 0; i < total; i++) {
            ResetLastError();
            tickets[i] = HistoryDealGetTicket(i);
            if (tickets[i] == 0) {
                return H1EaDealHistory::fail(0, "HistoryDealGetTicket", GetLastError(),
                    "ENUMERATION_FAILED index=" + IntegerToString(i), fromFailure);
            }
            for (int j = 0; j < i; j++) {
                if (tickets[j] == tickets[i]) {
                    return H1EaDealHistory::fail(tickets[i], "TICKET_ARRAY", 0,
                        "DUPLICATE_TICKET", fromFailure);
                }
            }
        }
        H1EaDealSnapshot candidates[];
        ResetLastError();
        if (ArrayResize(candidates, total) != total) {
            return H1EaDealHistory::fail(0, "SNAPSHOT_ARRAY", GetLastError(), "ALLOCATION_FAILED", fromFailure);
        }
        for (int i = 0; i < total; i++) {
            if (!H1EaDealHistory::read(tickets[i], candidates[i], fromFailure)) {
                return false;
            }
            if (candidates[i].positionIdentifier != fromIdentifier) {
                return H1EaDealHistory::fail(tickets[i], "DEAL_POSITION_ID", 0,
                    "POSITION_MISMATCH expected=" + StringFormat("%I64u", fromIdentifier), fromFailure);
            }
            if (candidates[i].symbol != fromSymbol) {
                return H1EaDealHistory::fail(tickets[i], "DEAL_SYMBOL", 0,
                    "SYMBOL_MISMATCH expected=" + fromSymbol, fromFailure);
            }
        }
        ResetLastError();
        if (ArrayResize(fromDeals, total) != total) {
            int errorCode = GetLastError();
            ArrayResize(fromDeals, 0);
            return H1EaDealHistory::fail(0, "OUTPUT_ARRAY", errorCode, "ALLOCATION_FAILED", fromFailure);
        }
        for (int i = 0; i < total; i++) {
            fromDeals[i] = candidates[i];
        }
        return true;
    }

private:
    /**
     * bool版整数getterの失敗を値0と区別する。
     */
    static bool readInteger(const ulong fromTicket, const ENUM_DEAL_PROPERTY_INTEGER fromProperty,
            long &fromValue, string &fromFailure) {
        ResetLastError();
        if (!HistoryDealGetInteger(fromTicket, fromProperty, fromValue)) {
            return H1EaDealHistory::fail(fromTicket, EnumToString(fromProperty), GetLastError(),
                "GETTER_FAILED", fromFailure);
        }
        return true;
    }

    /**
     * bool版実数getterと有限値の確認を同じ境界で行う。
     */
    static bool readDouble(const ulong fromTicket, const ENUM_DEAL_PROPERTY_DOUBLE fromProperty,
            double &fromValue, string &fromFailure) {
        ResetLastError();
        if (!HistoryDealGetDouble(fromTicket, fromProperty, fromValue)) {
            return H1EaDealHistory::fail(fromTicket, EnumToString(fromProperty), GetLastError(),
                "GETTER_FAILED", fromFailure);
        }
        if (!MathIsValidNumber(fromValue)) {
            return H1EaDealHistory::fail(fromTicket, EnumToString(fromProperty), 0, "NON_FINITE", fromFailure);
        }
        return true;
    }

    /**
     * 再試行・調査に必要なticket、項目、MT5エラーコードを必ず残す。
     */
    static bool fail(const ulong fromTicket, const string fromProperty, const int fromError,
            const string fromReason, string &fromFailure) {
        fromFailure = StringFormat("DEAL_HISTORY_READ_FAILED ticket=%I64u property=%s error=%d reason=%s",
            fromTicket, fromProperty, fromError, fromReason);
        return false;
    }
};

#endif
