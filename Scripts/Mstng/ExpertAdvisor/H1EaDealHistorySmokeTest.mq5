#property strict
#property version "1.00"

/**
 * 注文も口座履歴の参照も行わない、履歴API差し替え用の約定fixture。
 */
struct SmokeDeal {
    /** lookup用ticket。 */
    ulong ticket;
    /** getterが返すticket。誤った同一性も再現する。 */
    ulong reportedTicket;
    /** 注文番号。 */
    ulong orderTicket;
    /** Position識別番号。 */
    ulong positionIdentifier;
    /** Magic番号。手動決済では0も有効。 */
    ulong magic;
    /** シンボル。 */
    string symbol;
    /** 約定の入出区分。 */
    long entry;
    /** 約定方向。 */
    long type;
    /** broker理由。 */
    long reason;
    /** brokerミリ秒時刻。 */
    long timeMsc;
    /** 数量。 */
    double volume;
    /** 価格。 */
    double price;
    /** 損益。 */
    double profit;
    /** commission。 */
    double commission;
    /** swap。 */
    double swap;
    /** fee。 */
    double fee;
};

/** 読み取り元の固定fixture。 */
SmokeDeal fixtureDeals[3];
/** fixture件数。 */
int fixtureCount = 0;
/** MT5の現在選択一覧に相当するticket。 */
ulong selectedTickets[3];
/** 現在選択件数。単一Select時に1件へ縮める。 */
int selectedCount = 0;
/** Position選択失敗。 */
bool failPositionSelection = false;
/** 単一deal選択失敗。 */
bool failDealSelection = false;
/** 失敗させる列挙index。 */
int failTicketIndex = -1;
/** 失敗させるgetter種別。1=integer、2=string、3=double。 */
int failGetterKind = 0;
/** 失敗させるproperty。 */
int failGetterProperty = -1;
/** 特定ticketだけgetterを失敗させる。0は全fixture対象。 */
ulong failGetterTicket = 0;
/** 単一dealの選択回数。 */
int dealSelectionCount = 0;
/** テスト失敗件数。 */
int failedCount = 0;

/**
 * fixtureだけからticketを検索する。
 */
int findFixture(const ulong fromTicket) {
    for (int i = 0; i < fixtureCount; i++) {
        if (fixtureDeals[i].ticket == fromTicket) {
            return i;
        }
    }
    return -1;
}

/**
 * property取得失敗を、正しいゼロ値と区別して再現する。
 */
bool shouldFailGetter(const ulong fromTicket, const int fromKind, const int fromProperty) {
    return failGetterKind == fromKind && failGetterProperty == fromProperty
        && (failGetterTicket == 0 || failGetterTicket == fromTicket);
}

/**
 * Position履歴一覧を選択する。異常fixtureもそのまま渡してidentity検証を試す。
 */
bool fakeHistorySelectByPosition(const ulong fromIdentifier) {
    selectedCount = 0;
    if (failPositionSelection || fromIdentifier == 0) {
        return false;
    }
    selectedCount = fixtureCount;
    for (int i = 0; i < fixtureCount; i++) {
        selectedTickets[i] = fixtureDeals[i].ticket;
    }
    return true;
}

/**
 * 選択件数を返す。
 */
int fakeHistoryDealsTotal() {
    return selectedCount;
}

/**
 * 選択一覧のticketを返す。単一Select後は2件目以降を返せない。
 */
ulong fakeHistoryDealGetTicket(const int fromIndex) {
    if (fromIndex < 0 || fromIndex >= selectedCount || fromIndex == failTicketIndex) {
        return 0;
    }
    return selectedTickets[fromIndex];
}

/**
 * 本物と同様に単一deal選択によって選択一覧を1件へ置き換える。
 */
bool fakeHistoryDealSelect(const ulong fromTicket) {
    dealSelectionCount++;
    selectedCount = 0;
    if (failDealSelection || findFixture(fromTicket) < 0) {
        return false;
    }
    selectedTickets[0] = fromTicket;
    selectedCount = 1;
    return true;
}

/**
 * bool overloadのinteger getterを再現する。
 */
bool fakeHistoryDealGetInteger(const ulong fromTicket,
        const ENUM_DEAL_PROPERTY_INTEGER fromProperty, long &fromValue) {
    int index = findFixture(fromTicket);
    if (index < 0 || selectedCount != 1 || selectedTickets[0] != fromTicket
            || shouldFailGetter(fromTicket, 1, (int)fromProperty)) {
        return false;
    }
    if (fromProperty == DEAL_TICKET) {
        fromValue = (long)fixtureDeals[index].reportedTicket;
    } else if (fromProperty == DEAL_ORDER) {
        fromValue = (long)fixtureDeals[index].orderTicket;
    } else if (fromProperty == DEAL_POSITION_ID) {
        fromValue = (long)fixtureDeals[index].positionIdentifier;
    } else if (fromProperty == DEAL_MAGIC) {
        fromValue = (long)fixtureDeals[index].magic;
    } else if (fromProperty == DEAL_ENTRY) {
        fromValue = fixtureDeals[index].entry;
    } else if (fromProperty == DEAL_TYPE) {
        fromValue = fixtureDeals[index].type;
    } else if (fromProperty == DEAL_REASON) {
        fromValue = fixtureDeals[index].reason;
    } else if (fromProperty == DEAL_TIME_MSC) {
        fromValue = fixtureDeals[index].timeMsc;
    } else {
        return false;
    }
    return true;
}

/**
 * bool overloadのstring getterを再現する。
 */
bool fakeHistoryDealGetString(const ulong fromTicket,
        const ENUM_DEAL_PROPERTY_STRING fromProperty, string &fromValue) {
    int index = findFixture(fromTicket);
    if (index < 0 || selectedCount != 1 || selectedTickets[0] != fromTicket
            || shouldFailGetter(fromTicket, 2, (int)fromProperty) || fromProperty != DEAL_SYMBOL) {
        return false;
    }
    fromValue = fixtureDeals[index].symbol;
    return true;
}

/**
 * bool overloadのdouble getterを再現する。
 */
bool fakeHistoryDealGetDouble(const ulong fromTicket,
        const ENUM_DEAL_PROPERTY_DOUBLE fromProperty, double &fromValue) {
    int index = findFixture(fromTicket);
    if (index < 0 || selectedCount != 1 || selectedTickets[0] != fromTicket
            || shouldFailGetter(fromTicket, 3, (int)fromProperty)) {
        return false;
    }
    if (fromProperty == DEAL_VOLUME) {
        fromValue = fixtureDeals[index].volume;
    } else if (fromProperty == DEAL_PRICE) {
        fromValue = fixtureDeals[index].price;
    } else if (fromProperty == DEAL_PROFIT) {
        fromValue = fixtureDeals[index].profit;
    } else if (fromProperty == DEAL_COMMISSION) {
        fromValue = fixtureDeals[index].commission;
    } else if (fromProperty == DEAL_SWAP) {
        fromValue = fixtureDeals[index].swap;
    } else if (fromProperty == DEAL_FEE) {
        fromValue = fixtureDeals[index].fee;
    } else {
        return false;
    }
    return true;
}

// 差し替えは純粋な履歴readerのincludeだけに限定する。Executorはincludeしない。
#define HistorySelectByPosition fakeHistorySelectByPosition
#define HistoryDealsTotal fakeHistoryDealsTotal
#define HistoryDealGetTicket fakeHistoryDealGetTicket
#define HistoryDealSelect fakeHistoryDealSelect
#define HistoryDealGetInteger fakeHistoryDealGetInteger
#define HistoryDealGetString fakeHistoryDealGetString
#define HistoryDealGetDouble fakeHistoryDealGetDouble
#include <MstngH1Ea\Trade\H1EaDealHistory.mqh>
#undef HistorySelectByPosition
#undef HistoryDealsTotal
#undef HistoryDealGetTicket
#undef HistoryDealSelect
#undef HistoryDealGetInteger
#undef HistoryDealGetString
#undef HistoryDealGetDouble

/**
 * 注文なしfixtureテストの結果を出力する。
 */
void verify(const bool fromSuccess, const string fromName) {
    if (fromSuccess) {
        Print("INFO H1EaDealHistorySmokeTest PASS ", fromName);
    } else {
        failedCount++;
        Print("ERROR H1EaDealHistorySmokeTest FAIL ", fromName);
    }
}

/**
 * 入場BUYと決済SELLの2件を初期化する。
 */
void resetFixtures() {
    fixtureCount = 2;
    selectedCount = 0;
    failPositionSelection = false;
    failDealSelection = false;
    failTicketIndex = -1;
    failGetterKind = 0;
    failGetterProperty = -1;
    failGetterTicket = 0;
    dealSelectionCount = 0;
    for (int i = 0; i < fixtureCount; i++) {
        fixtureDeals[i].ticket = 9000000001 + (ulong)i;
        fixtureDeals[i].reportedTicket = fixtureDeals[i].ticket;
        fixtureDeals[i].orderTicket = 8000000001 + (ulong)i;
        fixtureDeals[i].positionIdentifier = 7000000001;
        fixtureDeals[i].magic = 1204010501;
        fixtureDeals[i].symbol = "GBPUSD";
        fixtureDeals[i].entry = DEAL_ENTRY_IN;
        fixtureDeals[i].type = DEAL_TYPE_BUY;
        fixtureDeals[i].reason = DEAL_REASON_EXPERT;
        fixtureDeals[i].timeMsc = 1767350000000 + i * 1000;
        fixtureDeals[i].volume = 0.01;
        fixtureDeals[i].price = 1.25 + i * 0.01;
        fixtureDeals[i].profit = 0.0;
        fixtureDeals[i].commission = 0.0;
        fixtureDeals[i].swap = 0.0;
        fixtureDeals[i].fee = 0.0;
    }
    fixtureDeals[1].entry = DEAL_ENTRY_OUT;
    fixtureDeals[1].type = DEAL_TYPE_SELL;
    fixtureDeals[1].reason = DEAL_REASON_SL;
    fixtureDeals[1].profit = 10.0;
    fixtureDeals[1].commission = -0.2;
    fixtureDeals[1].swap = -0.1;
    fixtureDeals[1].fee = -0.05;
}

/**
 * 成功時の全propertyと有効なゼロ値を確認する。
 */
void verifySuccessfulRead() {
    resetFixtures();
    H1EaDealSnapshot snapshot;
    string failure = "PREVIOUS_FAILURE";
    verify(H1EaDealHistory::read(fixtureDeals[1].ticket, snapshot, failure), "single exit read");
    verify(failure == "" && snapshot.ticket == fixtureDeals[1].ticket
        && snapshot.orderTicket == fixtureDeals[1].orderTicket
        && snapshot.positionIdentifier == fixtureDeals[1].positionIdentifier
        && snapshot.magic == fixtureDeals[1].magic && snapshot.symbol == "GBPUSD"
        && snapshot.entry == DEAL_ENTRY_OUT && snapshot.type == DEAL_TYPE_SELL
        && snapshot.reason == DEAL_REASON_SL && snapshot.timeMsc == fixtureDeals[1].timeMsc
        && snapshot.volume == 0.01 && snapshot.price == fixtureDeals[1].price
        && snapshot.profit == 10.0 && snapshot.commission == -0.2
        && snapshot.swap == -0.1 && snapshot.fee == -0.05, "all exit facts copied without truncation");
    fixtureDeals[0].magic = 0;
    fixtureDeals[0].reason = DEAL_REASON_CLIENT;
    verify(H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && snapshot.magic == 0 && snapshot.reason == DEAL_REASON_CLIENT
        && snapshot.entry == DEAL_ENTRY_IN && snapshot.type == DEAL_TYPE_BUY
        && snapshot.profit == 0.0 && snapshot.commission == 0.0
        && snapshot.swap == 0.0 && snapshot.fee == 0.0, "valid zero facts are not getter failures");
    snapshot.price = 0.5;
    verify(H1EaDealHistory::read(fixtureDeals[1].ticket, snapshot, failure)
        && snapshot.price == fixtureDeals[1].price, "repeated read uses current fixture facts");
}

/**
 * bool getter失敗で部分的な出力を残さないことを確認する。
 */
void verifyGetterFailure(const int fromKind, const int fromProperty) {
    resetFixtures();
    H1EaDealSnapshot snapshot;
    string failure;
    verify(H1EaDealHistory::read(fixtureDeals[1].ticket, snapshot, failure), "prime previous successful snapshot");
    failGetterKind = fromKind;
    failGetterProperty = fromProperty;
    bool succeeded = H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure);
    string propertyName = EnumToString((ENUM_DEAL_PROPERTY_INTEGER)fromProperty);
    if (fromKind == 2) {
        propertyName = EnumToString((ENUM_DEAL_PROPERTY_STRING)fromProperty);
    } else if (fromKind == 3) {
        propertyName = EnumToString((ENUM_DEAL_PROPERTY_DOUBLE)fromProperty);
    }
    verify(!succeeded && failure != "" && snapshot.ticket == 0 && snapshot.symbol == ""
        && snapshot.timeMsc == 0 && snapshot.price == 0.0
        && StringFind(failure, "ticket=9000000001") >= 0
        && StringFind(failure, "property=" + propertyName) >= 0
        && StringFind(failure, "error=") >= 0 && StringFind(failure, "GETTER_FAILED") >= 0,
        "getter failure clears output kind=" + IntegerToString(fromKind)
            + " property=" + IntegerToString(fromProperty));
}

/**
 * 各必須propertyについて取得失敗を検証する。
 */
void verifyAllGetterFailures() {
    ENUM_DEAL_PROPERTY_INTEGER integers[] = {
        DEAL_TICKET, DEAL_ORDER, DEAL_POSITION_ID, DEAL_MAGIC,
        DEAL_ENTRY, DEAL_TYPE, DEAL_REASON, DEAL_TIME_MSC
    };
    for (int i = 0; i < ArraySize(integers); i++) {
        verifyGetterFailure(1, (int)integers[i]);
    }
    verifyGetterFailure(2, (int)DEAL_SYMBOL);
    ENUM_DEAL_PROPERTY_DOUBLE doubles[] = {
        DEAL_VOLUME, DEAL_PRICE, DEAL_PROFIT, DEAL_COMMISSION, DEAL_SWAP, DEAL_FEE
    };
    for (int i = 0; i < ArraySize(doubles); i++) {
        verifyGetterFailure(3, (int)doubles[i]);
    }
}

/**
 * 選択失敗・不正ticket・同一性違反を確認する。
 */
void verifySelectionAndIdentityFailures() {
    resetFixtures();
    H1EaDealSnapshot snapshot;
    string failure;
    verify(!H1EaDealHistory::read(0, snapshot, failure) && failure != "" && snapshot.ticket == 0,
        "zero ticket is rejected");
    failDealSelection = true;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "" && snapshot.ticket == 0, "deal selection failure is explicit");
    resetFixtures();
    fixtureDeals[0].reportedTicket++;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "" && snapshot.ticket == 0, "mismatched ticket is rejected");
    resetFixtures();
    fixtureDeals[0].timeMsc = 0;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "", "zero broker timestamp is rejected");
    resetFixtures();
    fixtureDeals[0].volume = 0.0;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "", "zero trading volume is rejected");
    resetFixtures();
    fixtureDeals[0].price = 0.0;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "", "zero trading price is rejected");
    resetFixtures();
    fixtureDeals[0].positionIdentifier = 0;
    verify(!H1EaDealHistory::read(fixtureDeals[0].ticket, snapshot, failure)
        && failure != "", "zero position identifier is rejected");
}

/**
 * 全ticketの先行退避、後続選択変更、失敗時の出力全破棄を確認する。
 */
void verifyPositionRead() {
    resetFixtures();
    H1EaDealSnapshot snapshots[];
    string failure = "PREVIOUS_FAILURE";
    verify(H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure == "" && ArraySize(snapshots) == 2 && dealSelectionCount == 2,
        "all tickets captured before single-deal selection replaces history list");
    if (ArraySize(snapshots) == 2) {
        verify(snapshots[0].ticket == fixtureDeals[0].ticket
            && snapshots[1].ticket == fixtureDeals[1].ticket
            && snapshots[0].entry == DEAL_ENTRY_IN && snapshots[1].entry == DEAL_ENTRY_OUT,
            "entry and exit snapshots both survive selection changes");
        fakeHistoryDealSelect(fixtureDeals[0].ticket);
        fixtureDeals[1].profit = 999.0;
        verify(snapshots[1].profit == 10.0 && snapshots[1].ticket == 9000000002,
            "captured facts are independent of later history selection and source changes");
    }
    failPositionSelection = true;
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "position selection failure clears previous output");
    resetFixtures();
    failTicketIndex = 1;
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0 && dealSelectionCount == 0,
        "ticket enumeration failure occurs before any snapshot read");
    resetFixtures();
    failGetterKind = 3;
    failGetterProperty = (int)DEAL_FEE;
    failGetterTicket = fixtureDeals[1].ticket;
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "later exit getter failure never returns partial history");
    resetFixtures();
    fixtureDeals[1].positionIdentifier++;
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "foreign position identifier rejected");
    resetFixtures();
    fixtureDeals[1].symbol = "EURUSD";
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "foreign symbol rejected");
    resetFixtures();
    fixtureDeals[1].ticket = fixtureDeals[0].ticket;
    verify(!H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0 && dealSelectionCount == 0,
        "duplicate history ticket is rejected before it could be counted twice");
    resetFixtures();
    fixtureCount = 0;
    verify(H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && failure == "" && ArraySize(snapshots) == 0,
        "successful empty history is distinct from failed history selection");
    verify(!H1EaDealHistory::readPosition(0, "GBPUSD", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "zero position scope rejected");
    verify(!H1EaDealHistory::readPosition(7000000001, "", snapshots, failure)
        && failure != "" && ArraySize(snapshots) == 0, "empty symbol scope rejected");
    resetFixtures();
    verify(H1EaDealHistory::readPosition(7000000001, "GBPUSD", snapshots, failure)
        && ArraySize(snapshots) == 2 && failure == "", "retry succeeds after history becomes readable");
}

/**
 * 全履歴操作をfixtureへ差し替えて実行する。口座・DB・注文を変更しない。
 */
void OnStart() {
    verifySuccessfulRead();
    verifyAllGetterFailures();
    verifySelectionAndIdentityFailures();
    verifyPositionRead();
    Print("INFO H1EaDealHistorySmokeTest failures=", failedCount);
}
