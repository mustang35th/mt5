//+------------------------------------------------------------------+
//|                          ZigZagElliotRankDeltaBandHistory.mqh    |
//+------------------------------------------------------------------+
#property strict

#ifndef MSTNG_ZIGZAG_ELLIOT_RANK_DELTA_BAND_HISTORY_MQH
#define MSTNG_ZIGZAG_ELLIOT_RANK_DELTA_BAND_HISTORY_MQH

#include <Mstng\Strength\CurrencyStrengthRankDeltaEvaluator.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDeltaHistoryProvider.mqh>

/**
 * 1期間の通貨順位と、直前のチャート足からの順位差の増減を保持する。
 */
struct RankDeltaBandPeriod {
    /** この足の両通貨順位が有効か。 */
    bool valid;

    /** この足と直前のチャート足を比較できたか。 */
    bool comparable;

    /** 基軸通貨の順位。 */
    int baseRank;

    /** 決済通貨の順位。 */
    int quoteRank;

    /** 決済通貨順位から基軸通貨順位を引いた値。 */
    int gap;

    /** 直前のチャート足からの順位差の変化量。 */
    int delta;

    /** 最後に変化した方向。上昇は1、下降は-1、未確定は0。 */
    int direction;
};

/**
 * 長中期・中短期の帯が同じ開始時刻に表示する1本のチャート足。
 */
struct RankDeltaBandBar {
    /** チャート足の開始時刻（サーバー時刻）。 */
    datetime time;

    /** 長中期の順位と増減。 */
    RankDeltaBandPeriod longMedium;

    /** 中短期の順位と増減。 */
    RankDeltaBandPeriod mediumShort;
};

/**
 * 2段の帯に使うM5順位履歴を一度に取得し、表示時間足の実在する足に対応付ける。
 * 変化方向は保持期間の最初から時刻順に求め、後の足で確定した色を前の足へ戻さない。
 */
class ZigZagElliotRankDeltaBandHistory {
public:
    /** 表示期間内のチャート足。古い足から並び、順位が欠損した足も保持する。 */
    RankDeltaBandBar bars[];

    /**
     * 順位差履歴と同じDB参照先・集計方式を設定する。
     */
    ZigZagElliotRankDeltaBandHistory(const string fromFileName, const bool fromSplitByYear,
            const bool fromUseCommonFolder, const CurrencyStrengthRankDatabaseProfile fromProfile,
            const CurrencyStrengthVoteWeightMode fromWeightMode, const bool fromTester,
            const string fromBaseCurrency, const string fromQuoteCurrency, const int fromRefreshSeconds) {
        this.provider = new CurrencyStrengthRankDeltaHistoryProvider(fromFileName, fromSplitByYear,
            fromUseCommonFolder, fromProfile, fromWeightMode, fromTester, fromBaseCurrency, fromQuoteCurrency);
        this.tester = fromTester;
        this.refreshMilliseconds = (ulong)MathMax(1, fromRefreshSeconds) * 1000;
        this.lastQueryTicks = 0;
        this.lastQueryTime = 0;
        this.lastRatesTotal = 0;
        this.lastBarTime = 0;
        this.revision = 0;
    }

    /**
     * 所有する読み取り専用の履歴参照を解放する。
     */
    ~ZigZagElliotRankDeltaBandHistory() {
        if (this.provider != NULL) {
            delete this.provider;
            this.provider = NULL;
        }
    }

    /**
     * 足・色・ツールチップの再描画が必要になったことを示す更新番号を返す。
     */
    int getRevision() const { return this.revision; }

    /**
     * 直近30日分のチャート足に、同じM5開始時刻の両期間順位だけを割り当てる。
     * DB失敗時は前回取得済みの同一時刻だけを使用し、未取得の足は空白とする。
     * @param fromTime OnCalculateの時刻配列。通常・時系列の両方向に対応する。
     * @param fromNow 検索の上限に使う現在のサーバー時刻。
     * @return 表示用の配列を反映した場合true。履歴が0件の場合も含む。
     */
    bool update(const int fromRatesTotal, const int fromPreviousCalculated,
            const datetime &fromTime[], const datetime fromNow) {
        if (this.provider == NULL || fromRatesTotal <= 0 || ArraySize(fromTime) != fromRatesTotal) {
            return false;
        }

        bool series = ArrayGetAsSeries(fromTime);
        datetime latest = this.timeAt(fromTime, series, fromRatesTotal - 1);
        datetime target = (datetime)((long)fromNow / 300 * 300);
        if (fromNow <= 0) {
            target = (datetime)((long)latest / 300 * 300);
        }

        if (latest <= 0 || target <= 0) {
            return false;
        }

        datetime displayStart = (datetime)MathMax(300, (long)target - 30 * 86400);
        datetime changedStart = target;
        bool changed = false;
        datetime previousTarget = this.lastQueryTime;
        bool targetChanged = this.lastQueryTime != target;
        ulong nowTicks = GetTickCount64();
        if (targetChanged || (!this.tester && nowTicks - this.lastQueryTicks >= this.refreshMilliseconds)) {
            this.lastQueryTime = target;
            this.lastQueryTicks = nowTicks;
            this.provider.refresh(displayStart, target, false, changedStart, changed);
        }

        bool full = this.lastRatesTotal <= 0 || fromPreviousCalculated > fromRatesTotal
            || this.lastRatesTotal > fromRatesTotal || latest < this.lastBarTime || target < previousTarget;
        if (fromPreviousCalculated > 0 && !full && !changed && !targetChanged && latest == this.lastBarTime
                && fromRatesTotal == this.lastRatesTotal) {
            return true;
        }

        int first = this.firstAtOrAfter(fromTime, series, displayStart);
        int count = fromRatesTotal - first;
        int oldCount = ArraySize(this.bars);
        int removed = 0;
        if (!full && count > 0) {
            datetime firstTime = this.timeAt(fromTime, series, first);
            while (removed < oldCount && this.bars[removed].time < firstTime) {
                removed++;
            }
        }

        int kept = oldCount - removed;
        if (full || kept > count || (kept > 0 && (this.bars[removed].time != this.timeAt(fromTime, series, first)
                || this.bars[oldCount - 1].time != this.timeAt(fromTime, series, first + kept - 1)))) {
            kept = 0;
        }

        // 波動の初期待機でprev_calculatedが0のままでも、実際に修正された足からだけ再計算する。
        if (fromPreviousCalculated <= 0 && kept > 1) {
            int inputIndex = first + 1;
            int step = 1;
            if (series) {
                inputIndex = fromRatesTotal - 2 - first;
                step = -1;
            }

            for (int i = 1; i < kept - 1; i++) {
                if (this.bars[removed + i].time != fromTime[inputIndex]) {
                    kept = i;
                    break;
                }

                inputIndex += step;
            }
        }

        if (kept > 0 && removed > 0 && !ArrayRemove(this.bars, 0, removed)) {
            this.lastRatesTotal = 0;
            this.lastBarTime = 0;

            return false;
        }

        if (ArrayResize(this.bars, count, 288) != count) {
            this.lastRatesTotal = 0;
            this.lastBarTime = 0;

            return false;
        }

        int begin = kept;
        if (changed) {
            begin = MathMin(begin, MathMax(0, this.firstAtOrAfter(fromTime, series, changedStart) - first));
        }

        // 時計だけが先へ進んだ場合も、前回の上限より後の足を初めて評価する。
        if (previousTarget > 0 && target > previousTarget && this.lastBarTime >= previousTarget + 300) {
            begin = MathMin(begin, MathMax(0, this.firstAtOrAfter(fromTime, series, previousTarget + 300) - first));
        }

        if (removed > 0 && begin > 0) {
            this.resetLeadingDirection(begin);
        }

        int lookup = -1;
        for (int i = begin; i < count; i++) {
            datetime barTime = this.timeAt(fromTime, series, first + i);
            datetime sample = (datetime)((long)barTime / 300 * 300);
            this.bars[i].time = barTime;
            if (i > 0 && sample == (datetime)((long)this.bars[i - 1].time / 300 * 300)) {
                this.bars[i].longMedium = this.bars[i - 1].longMedium;
                this.bars[i].mediumShort = this.bars[i - 1].mediumShort;
            } else {
                this.readPeriod(sample, target, true, lookup, this.bars[i].longMedium);
                this.readPeriod(sample, target, false, lookup, this.bars[i].mediumShort);
            }

            this.compareBar(i);
        }

        if (begin < count || count != oldCount || removed > 0) {
            this.revision++;
        }

        this.lastRatesTotal = fromRatesTotal;
        this.lastBarTime = latest;

        return true;
    }

private:
    /** 2期間で共用するM5順位履歴。 */
    CurrencyStrengthRankDeltaHistoryProvider *provider;

    /** ストラテジーテスター内で使用している場合true。 */
    bool tester;

    /** 通常チャートで同じM5時刻の遅着データを再取得する間隔。 */
    ulong refreshMilliseconds;

    /** 直近の取得試行の単調時刻。 */
    ulong lastQueryTicks;

    /** 直近の取得試行の対象M5時刻。 */
    datetime lastQueryTime;

    /** 前回配置したチャートの総本数。 */
    int lastRatesTotal;

    /** 前回配置したチャートの最新足時刻。 */
    datetime lastBarTime;

    /** 表示用データの更新番号。 */
    int revision;

    /**
     * 時刻配列の向きにかかわらず、古い足から数えた位置の時刻を返す。
     */
    datetime timeAt(const datetime &fromTime[], const bool fromSeries, const int fromIndex) const {
        if (fromSeries) {
            return fromTime[ArraySize(fromTime) - 1 - fromIndex];
        }

        return fromTime[fromIndex];
    }

    /**
     * 指定時刻以上の最初のチャート足を、古い足からの添字で返す。
     */
    int firstAtOrAfter(const datetime &fromTime[], const bool fromSeries, const datetime fromTimeLimit) const {
        int left = 0;
        int right = ArraySize(fromTime);
        while (left < right) {
            int middle = left + (right - left) / 2;
            if (this.timeAt(fromTime, fromSeries, middle) < fromTimeLimit) {
                left = middle + 1;
            } else {
                right = middle;
            }
        }

        return left;
    }

    /**
     * 同じM5の有効順位を読み、対象時刻外や不正値は当該期間のみ欠損とする。
     */
    void readPeriod(const datetime fromSample, const datetime fromTarget, const bool fromLongMedium,
            int &toLookup, RankDeltaBandPeriod &toPeriod) {
        ZeroMemory(toPeriod);
        if (fromSample <= fromTarget) {
            toPeriod.valid = CurrencyStrengthRankDeltaEvaluator::evaluateGap(this.provider.points,
                this.provider.startIndex, fromSample, fromLongMedium, toPeriod.baseRank, toPeriod.quoteRank,
                toPeriod.gap, toLookup);
        }
    }

    /**
     * 増減の向きと前足比を決定する。欠損をまたいで過去方向を引き継がない。
     */
    void comparePeriod(const RankDeltaBandPeriod &fromPrevious, RankDeltaBandPeriod &toCurrent) {
        toCurrent.comparable = toCurrent.valid && fromPrevious.valid;
        toCurrent.direction = 0;
        toCurrent.delta = 0;
        if (!toCurrent.comparable) {
            return;
        }

        toCurrent.delta = toCurrent.gap - fromPrevious.gap;
        toCurrent.direction = fromPrevious.direction;
        if (toCurrent.delta > 0) {
            toCurrent.direction = 1;
        } else if (toCurrent.delta < 0) {
            toCurrent.direction = -1;
        }
    }

    /**
     * 両期間の増減を独立して更新する。保持期間の先頭には比較元を設けない。
     */
    void compareBar(const int fromIndex) {
        if (fromIndex == 0) {
            RankDeltaBandPeriod empty = {};
            this.comparePeriod(empty, this.bars[0].longMedium);
            this.comparePeriod(empty, this.bars[0].mediumShort);

            return;
        }

        this.comparePeriod(this.bars[fromIndex - 1].longMedium, this.bars[fromIndex].longMedium);
        this.comparePeriod(this.bars[fromIndex - 1].mediumShort, this.bars[fromIndex].mediumShort);
    }

    /**
     * 期限切れの足から引き継いだ色を消し、両期間の方向が元と一致した時点で終了する。
     */
    void resetLeadingDirection(const int fromEnd) {
        for (int i = 0; i < fromEnd; i++) {
            int oldLong = this.bars[i].longMedium.direction;
            int oldShort = this.bars[i].mediumShort.direction;
            this.compareBar(i);
            if (this.bars[i].longMedium.direction == oldLong && this.bars[i].mediumShort.direction == oldShort) {
                break;
            }
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_RANK_DELTA_BAND_HISTORY_MQH
