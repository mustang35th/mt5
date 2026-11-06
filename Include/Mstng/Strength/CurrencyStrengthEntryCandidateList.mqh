//+------------------------------------------------------------------+
//|                           CurrencyStrengthEntryCandidateList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>
#include <Mstng\Strength\CurrencyStrengthH1EmaProvider.mqh>

/**
 * 長中期と中短期の通貨順位を使用して
 * 全28通貨ペアからエントリー候補を抽出する。
 */
class CurrencyStrengthEntryCandidateList {
public:
    /**
     * 候補一覧を初期化する。
     */
    CurrencyStrengthEntryCandidateList() {
        this.clear();
    }

    /**
     * 候補一覧を解放する。
     */
    ~CurrencyStrengthEntryCandidateList() {
        this.clear();
    }

    /**
     * 全28通貨ペアから方向一致候補を構築する。
     * 各通貨の長中期・中短期順位は、構築ごとに一度だけ取得する。
     *
     * @param fromCalculator 通貨強弱集計結果。
     * @param fromMinimumRankDifference 候補とする最小順位差。長中期は端順位でも通過する。
     * @return 構築処理に成功した場合true。
     */
    bool build(
        CurrencyStrengthCalculator *fromCalculator,
        const int fromMinimumRankDifference
    ) {
        this.clear();

        if (fromCalculator == NULL
                || fromMinimumRankDifference < 1
                || fromMinimumRankDifference > 7) {
            return false;
        }

        this.validPairCount = fromCalculator.validPairCount;
        this.expectedPairCount = fromCalculator.getExpectedPairCount();
        this.minimumRankDifference = fromMinimumRankDifference;
        this.rankingReady = this.validPairCount == this.expectedPairCount;

        if (!this.rankingReady) {
            return true;
        }

        int currencyCount = fromCalculator.size();
        int longMediumRanks[];
        int mediumShortRanks[];
        if (ArrayResize(longMediumRanks, currencyCount) != currencyCount
                || ArrayResize(mediumShortRanks, currencyCount) != currencyCount) {
            this.clear();

            return false;
        }

        for (int i = 0; i < currencyCount; i++) {
            longMediumRanks[i] = fromCalculator.getLongMediumTermAverageRank(i);
            mediumShortRanks[i] = fromCalculator.getMediumShortTermAverageRank(i);
        }

        for (int i = 0; i < currencyCount; i++) {
            CurrencyStrengthInfo *firstInfo = fromCalculator.getInfo(i);

            if (firstInfo == NULL) {
                continue;
            }

            for (int j = i + 1; j < currencyCount; j++) {
                CurrencyStrengthInfo *secondInfo = fromCalculator.getInfo(j);

                if (secondInfo == NULL) {
                    continue;
                }

                if (!this.addCandidate(
                    longMediumRanks,
                    mediumShortRanks,
                    i,
                    firstInfo.currencyName,
                    j,
                    secondInfo.currencyName
                )) {
                    this.clear();

                    return false;
                }
            }
        }

        this.sort();

        return true;
    }

    /**
     * 全候補のH1 EMA200を集計時点に対応する共通判定で更新する。
     *
     * 取得できなかった候補は未取得へ戻し、次回の更新で再試行する。
     * 通貨順位による候補順序とREADY判定は変更しない。
     * 全票を一度だけ走査してH1票の位置を対応付け、EMA判定は候補順に毎回実行する。
     *
     * @param fromCalculator 通貨強弱集計結果。
     * @param fromProvider シンボル別H1 EMA200保持クラス。
     * @param fromTargetM5BarTime 集計対象のM5足開始時刻。
     * @return 全候補のH1 EMA200を取得できた場合true。
     */
    bool updateH1Ema(
        CurrencyStrengthCalculator *fromCalculator,
        CurrencyStrengthH1EmaProvider *fromProvider,
        const datetime fromTargetM5BarTime
    ) {
        int candidateCount = ArraySize(this.candidates);

        for (int i = 0; i < candidateCount; i++) {
            this.candidates[i].resetH1Ema();
        }

        if (fromCalculator == NULL
                || fromProvider == NULL
                || fromTargetM5BarTime <= 0) {
            return false;
        }

        if (candidateCount == 0) {
            return true;
        }

        int candidateVoteIndexes[];
        if (ArrayResize(candidateVoteIndexes, candidateCount) != candidateCount) {
            return false;
        }

        ArrayInitialize(candidateVoteIndexes, -1);
        int unresolvedCount = candidateCount;
        int pairVoteCount = fromCalculator.getPairVoteCount();
        for (int i = 0; i < pairVoteCount && unresolvedCount > 0; i++) {
            CurrencyStrengthPairVote pairVote;
            if (!fromCalculator.getPairVote(i, pairVote) || pairVote.timeFrame != PERIOD_H1) {
                continue;
            }

            for (int j = 0; j < candidateCount; j++) {
                if (candidateVoteIndexes[j] >= 0
                        || pairVote.canonicalSymbolName != this.candidates[j].symbolName) {
                    continue;
                }

                candidateVoteIndexes[j] = i;
                unresolvedCount--;
            }
        }

        bool isReady = true;
        for (int i = 0; i < candidateCount; i++) {
            int voteIndex = candidateVoteIndexes[i];
            CurrencyStrengthPairVote pairVote;
            if (voteIndex < 0 || !fromCalculator.getPairVote(voteIndex, pairVote)
                    || pairVote.timeFrame != PERIOD_H1
                    || pairVote.canonicalSymbolName != this.candidates[i].symbolName) {
                isReady = false;

                continue;
            }

            if (!fromProvider.update(pairVote, fromTargetM5BarTime, this.candidates[i])) {
                isReady = false;
            }
        }

        return isReady;
    }

    /**
     * 候補件数を取得する。
     *
     * @return 候補件数。
     */
    int size() {
        return ArraySize(this.candidates);
    }

    /**
     * 指定番号の候補を取得する。
     *
     * @param fromIndex 候補番号。
     * @param fromCandidate 取得結果の格納先。
     * @return 取得できた場合true。
     */
    bool get(
        const int fromIndex,
        CurrencyStrengthEntryCandidate &fromCandidate
    ) {
        if (fromIndex < 0 || fromIndex >= ArraySize(this.candidates)) {
            return false;
        }

        fromCandidate = this.candidates[fromIndex];

        return true;
    }

    /**
     * 全通貨ペアの順位を利用できるか判定する。
     *
     * @return 利用できる場合true。
     */
    bool isRankingReady() {
        return this.rankingReady;
    }

    /**
     * 集計済み通貨ペア数を取得する。
     *
     * @return 集計済み通貨ペア数。
     */
    int getValidPairCount() {
        return this.validPairCount;
    }

    /**
     * 全通貨ペア数を取得する。
     *
     * @return 全通貨ペア数。
     */
    int getExpectedPairCount() {
        return this.expectedPairCount;
    }

    /**
     * 候補抽出に使用した最小順位差を取得する。
     *
     * @return 最小順位差。
     */
    int getMinimumRankDifference() {
        return this.minimumRankDifference;
    }

    /**
     * 保持している候補と集計状態を初期化する。
     */
    void clear() {
        ArrayResize(this.candidates, 0);
        this.rankingReady = false;
        this.validPairCount = 0;
        this.expectedPairCount = 0;
        this.minimumRankDifference = 0;
    }

private:
    /** エントリー候補一覧。 */
    CurrencyStrengthEntryCandidate candidates[];

    /** 全28通貨ペア定義。 */
    SymbolNameInfoAll symbolNameInfoAll;

    /** 全通貨ペアの順位を利用できる場合true。 */
    bool rankingReady;

    /** 集計済み通貨ペア数。 */
    int validPairCount;

    /** 全通貨ペア数。 */
    int expectedPairCount;

    /** 候補抽出に使用した最小順位差。 */
    int minimumRankDifference;

    /**
     * 2通貨の正規通貨ペアを解決して候補へ追加する。
     *
     * @param fromLongMediumRanks 今回の構築で取得した通貨別の長中期順位。
     * @param fromMediumShortRanks 今回の構築で取得した通貨別の中短期順位。
     * @param fromFirstIndex 1つ目の通貨番号。
     * @param fromFirstCurrency 1つ目の通貨コード。
     * @param fromSecondIndex 2つ目の通貨番号。
     * @param fromSecondCurrency 2つ目の通貨コード。
     * @return 処理に成功した場合true。
     */
    bool addCandidate(
        const int &fromLongMediumRanks[],
        const int &fromMediumShortRanks[],
        const int fromFirstIndex,
        const string fromFirstCurrency,
        const int fromSecondIndex,
        const string fromSecondCurrency
    ) {
        string symbolName = fromFirstCurrency + fromSecondCurrency;
        int baseCurrencyIndex = fromFirstIndex;
        int quoteCurrencyIndex = fromSecondIndex;

        if (this.symbolNameInfoAll.getSymbolNameInfo(symbolName) == NULL) {
            symbolName = fromSecondCurrency + fromFirstCurrency;
            baseCurrencyIndex = fromSecondIndex;
            quoteCurrencyIndex = fromFirstIndex;
        }

        if (this.symbolNameInfoAll.getSymbolNameInfo(symbolName) == NULL) {
            return true;
        }

        int baseLongMediumRank = fromLongMediumRanks[baseCurrencyIndex];
        int quoteLongMediumRank = fromLongMediumRanks[quoteCurrencyIndex];
        int baseMediumShortRank = fromMediumShortRanks[baseCurrencyIndex];
        int quoteMediumShortRank = fromMediumShortRanks[quoteCurrencyIndex];

        if (!this.isValidRank(baseLongMediumRank)
                || !this.isValidRank(quoteLongMediumRank)
                || !this.isValidRank(baseMediumShortRank)
                || !this.isValidRank(quoteMediumShortRank)) {
            return true;
        }

        int longMediumDifference = quoteLongMediumRank - baseLongMediumRank;
        int mediumShortDifference = quoteMediumShortRank - baseMediumShortRank;
        bool isBuy = false;

        if (longMediumDifference > 0 && mediumShortDifference > 0) {
            isBuy = true;
        } else if (longMediumDifference >= 0 || mediumShortDifference >= 0) {
            return true;
        }

        int absoluteLongMediumDifference = this.getAbsoluteValue(
            longMediumDifference
        );
        int absoluteMediumShortDifference = this.getAbsoluteValue(
            mediumShortDifference
        );

        if (absoluteMediumShortDifference < this.minimumRankDifference) {
            return true;
        }

        CurrencyStrengthEntryCandidate candidate;
        candidate.reset();
        candidate.symbolName = symbolName;
        candidate.isBuy = isBuy;
        candidate.baseLongMediumRank = baseLongMediumRank;
        candidate.quoteLongMediumRank = quoteLongMediumRank;
        candidate.baseMediumShortRank = baseMediumShortRank;
        candidate.quoteMediumShortRank = quoteMediumShortRank;
        candidate.longMediumRankDifference = longMediumDifference;
        candidate.mediumShortRankDifference = mediumShortDifference;

        if (!candidate.isLongMediumRankConditionMatched(this.minimumRankDifference)) {
            return true;
        }

        candidate.minimumRankDifference = absoluteLongMediumDifference;

        if (absoluteMediumShortDifference < candidate.minimumRankDifference) {
            candidate.minimumRankDifference = absoluteMediumShortDifference;
        }

        candidate.totalRankDifference = absoluteLongMediumDifference
            + absoluteMediumShortDifference;

        int candidateIndex = ArraySize(this.candidates);

        if (ArrayResize(this.candidates, candidateIndex + 1) != candidateIndex + 1) {
            return false;
        }

        this.candidates[candidateIndex] = candidate;

        return true;
    }

    /**
     * READYをWATCHより優先し、同じ状態では従来の順位差順に並び替える。
     */
    void sort() {
        int candidateCount = ArraySize(this.candidates);

        for (int i = 1; i < candidateCount; i++) {
            CurrencyStrengthEntryCandidate currentCandidate = this.candidates[i];
            int j = i - 1;

            while (j >= 0
                    && this.shouldShift(
                        currentCandidate,
                        this.candidates[j]
                    )) {
                this.candidates[j + 1] = this.candidates[j];
                j--;
            }

            this.candidates[j + 1] = currentCandidate;
        }
    }

    /**
     * 現在候補を比較対象より前へ移動するか判定する。
     *
     * @param fromCurrentCandidate 現在候補。
     * @param fromPreviousCandidate 比較対象候補。
     * @return 現在候補を前へ移動する場合true。
     */
    bool shouldShift(
        CurrencyStrengthEntryCandidate &fromCurrentCandidate,
        CurrencyStrengthEntryCandidate &fromPreviousCandidate
    ) {
        bool currentReady = fromCurrentCandidate.isReady();
        bool previousReady = fromPreviousCandidate.isReady();
        if (currentReady != previousReady) {
            return currentReady;
        }

        if (fromCurrentCandidate.minimumRankDifference
                != fromPreviousCandidate.minimumRankDifference) {
            return fromCurrentCandidate.minimumRankDifference
                > fromPreviousCandidate.minimumRankDifference;
        }

        if (fromCurrentCandidate.totalRankDifference
                != fromPreviousCandidate.totalRankDifference) {
            return fromCurrentCandidate.totalRankDifference
                > fromPreviousCandidate.totalRankDifference;
        }

        return StringCompare(
            fromCurrentCandidate.symbolName,
            fromPreviousCandidate.symbolName
        ) < 0;
    }

    /**
     * 順位が主要8通貨の範囲内か判定する。
     *
     * @param fromRank 順位。
     * @return 1位から8位の場合true。
     */
    bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }

    /**
     * 整数の絶対値を取得する。
     *
     * @param fromValue 対象値。
     * @return 絶対値。
     */
    int getAbsoluteValue(const int fromValue) {
        if (fromValue < 0) {
            return 0 - fromValue;
        }

        return fromValue;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_LIST_MQH
