#ifndef MSTNGH1EA_RUNTIME_ENTRYSTATE_MQH
#define MSTNGH1EA_RUNTIME_ENTRYSTATE_MQH

/**
 * Entry専用のバー処理状態と、再起動復元後のJudge回数を保持する。
 * トレイルの分析・評価状態とは共有しない。
 */
class H1EaEntryState {
public:
    /**
     * 未観測状態で作成する。
     */
    H1EaEntryState() {
        this.observedBar = 0;
        this.finalizedBar = 0;
    }

    /**
     * DBの全シグナル回数を起動時に1回復元する。
     */
    bool restore(const long &fromTimes[], const string &fromSides[], const int &fromCounts[]) {
        int count = ArraySize(fromTimes);
        if (ArraySize(fromSides) != count || ArraySize(fromCounts) != count) {
            return false;
        }
        ArrayResize(this.referenceTimes, 0);
        ArrayResize(this.sides, 0);
        ArrayResize(this.counts, 0);
        for (int i = 0; i < count; i++) {
            if (!this.recordCount(fromTimes[i], fromSides[i], fromCounts[i])) {
                return false;
            }
        }
        return true;
    }

    /**
     * 観測バーを進め、成功しなかった前バーだけを返す。
     */
    datetime observe(const datetime fromBar) {
        if (fromBar <= 0 || fromBar == this.observedBar) {
            return 0;
        }
        datetime expiredBar = 0;
        if (this.observedBar > 0 && this.finalizedBar != this.observedBar) {
            expiredBar = this.observedBar;
        }
        this.observedBar = fromBar;
        return expiredBar;
    }

    /**
     * 保存待ちを含め、今回バーの判定が確定しているか返す。
     */
    bool isFinalized(const datetime fromBar) const {
        return fromBar > 0 && fromBar == this.finalizedBar;
    }

    /**
     * DB保存の成否に関係なく、最初に確定したバーを保持する。
     */
    void finalize(const datetime fromBar) {
        if (fromBar > this.finalizedBar) {
            this.finalizedBar = fromBar;
        }
    }

    /**
     * 同一基準時刻・方向の既知回数を返す。
     */
    int getCount(const long fromReferenceTime, const string fromSide) const {
        for (int i = 0; i < ArraySize(this.referenceTimes); i++) {
            if (this.referenceTimes[i] == fromReferenceTime && this.sides[i] == fromSide) {
                return this.counts[i];
            }
        }
        return 0;
    }

    /**
     * 確定Judge回数を記録する。NGバーでは呼ばず、回数を戻さない。
     */
    bool recordCount(const long fromReferenceTime, const string fromSide, const int fromCount) {
        if (fromReferenceTime <= 0 || (fromSide != "BUY" && fromSide != "SELL")
                || fromCount <= 0 || fromCount == INT_MAX) {
            return false;
        }
        for (int i = 0; i < ArraySize(this.referenceTimes); i++) {
            if (this.referenceTimes[i] == fromReferenceTime && this.sides[i] == fromSide) {
                if (fromCount < this.counts[i]) {
                    return false;
                }
                this.counts[i] = fromCount;
                return true;
            }
        }
        int nextSize = ArraySize(this.referenceTimes) + 1;
        if (ArrayResize(this.referenceTimes, nextSize) != nextSize
                || ArrayResize(this.sides, nextSize) != nextSize
                || ArrayResize(this.counts, nextSize) != nextSize) {
            ArrayResize(this.referenceTimes, nextSize - 1);
            ArrayResize(this.sides, nextSize - 1);
            ArrayResize(this.counts, nextSize - 1);
            return false;
        }
        this.referenceTimes[nextSize - 1] = fromReferenceTime;
        this.sides[nextSize - 1] = fromSide;
        this.counts[nextSize - 1] = fromCount;
        return true;
    }

private:
    /** 最後にEntry側で観測したバー。 */
    datetime observedBar;
    /** 最後に確定したバー。保存再試行でも変更しない。 */
    datetime finalizedBar;
    /** 消費キーの基準時刻。 */
    long referenceTimes[];
    /** 消費キーの方向。 */
    string sides[];
    /** Judge成立回数。 */
    int counts[];
};

#endif
