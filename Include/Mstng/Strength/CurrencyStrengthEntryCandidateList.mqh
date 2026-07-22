//+------------------------------------------------------------------+
//|               CurrencyStrengthEntryCandidateList.mqh |
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
     *
     * @param fromCalculator 通貨強弱集計結果。
     * @param fromMinimumRankDifference 候補とする両期間の最小順位差。
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
                    fromCalculator,
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
     * @param fromCalculator 通貨強弱集計結果。
     * @param fromFirstIndex 1つ目の通貨番号。
     * @param fromFirstCurrency 1つ目の通貨コード。
     * @param fromSecondIndex 2つ目の通貨番号。
     * @param fromSecondCurrency 2つ目の通貨コード。
     * @return 処理に成功した場合true。
     */
    bool addCandidate(
        CurrencyStrengthCalculator *fromCalculator,
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

        int baseLongMediumRank =
            fromCalculator.getLongMediumTermAverageRank(baseCurrencyIndex);
        int quoteLongMediumRank =
            fromCalculator.getLongMediumTermAverageRank(quoteCurrencyIndex);
        int baseMediumShortRank =
            fromCalculator.getMediumShortTermAverageRank(baseCurrencyIndex);
        int quoteMediumShortRank =
            fromCalculator.getMediumShortTermAverageRank(quoteCurrencyIndex);

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

        if (absoluteLongMediumDifference < this.minimumRankDifference
                || absoluteMediumShortDifference < this.minimumRankDifference) {
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
     * 候補一覧を優先度順に並び替える。
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
