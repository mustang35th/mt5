#ifndef MSTNGH1EA_TRADE_H1EADEALHISTORY_MQH
#define MSTNGH1EA_TRADE_H1EADEALHISTORY_MQH

#include <MstngEaCommon\Runtime\EaDealHistory.mqh>

/**
 * 共通の約定スナップショットを利用するH1互換型。
 */
struct H1EaDealSnapshot : EaDealSnapshot {
};

/**
 * 共通の約定履歴取得を公開するH1互換クラス。
 */
class H1EaDealHistory : public EaDealHistory {
public:
    /**
     * MQL5で基底型配列へ変換できないH1配列を、共通取得結果から復元する。
     */
    static bool readPosition(const ulong fromIdentifier, const string fromSymbol,
            H1EaDealSnapshot &fromDeals[], string &fromFailure) {
        ArrayResize(fromDeals, 0);
        EaDealSnapshot candidates[];
        if (!EaDealHistory::readPosition(fromIdentifier, fromSymbol, candidates, fromFailure)) {
            return false;
        }
        int total = ArraySize(candidates);
        ResetLastError();
        if (ArrayResize(fromDeals, total) != total) {
            int errorCode = GetLastError();
            ArrayResize(fromDeals, 0);
            fromFailure = StringFormat("DEAL_HISTORY_READ_FAILED ticket=%I64u property=%s error=%d reason=%s",
                (ulong)0, "OUTPUT_ARRAY", errorCode, "ALLOCATION_FAILED");
            return false;
        }
        for (int i = 0; i < total; i++) {
            H1EaDealHistory::copySnapshot(candidates[i], fromDeals[i]);
        }
        return true;
    }

private:
    /**
     * 基底型への単体参照を使い、全項目を欠落なくコピーする。
     */
    static void copySnapshot(const EaDealSnapshot &fromSource, EaDealSnapshot &fromTarget) {
        fromTarget = fromSource;
    }
};

#endif
