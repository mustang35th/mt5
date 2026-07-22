//+------------------------------------------------------------------+
//|                   CurrencyStrengthEntryCandidate.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_MQH

/**
 * 長中期と中短期の通貨順位から抽出した
 * エントリー候補通貨ペア1件分を保持する。
 */
struct CurrencyStrengthEntryCandidate {
    /** 正規化された通貨ペア名。 */
    string symbolName;
    /** BUY候補の場合true。 */
    bool isBuy;
    /** 基軸通貨の長中期順位。 */
    int baseLongMediumRank;
    /** 決済通貨の長中期順位。 */
    int quoteLongMediumRank;
    /** 基軸通貨の中短期順位。 */
    int baseMediumShortRank;
    /** 決済通貨の中短期順位。 */
    int quoteMediumShortRank;
    /** 長中期の決済通貨順位と基軸通貨順位の差。 */
    int longMediumRankDifference;
    /** 中短期の決済通貨順位と基軸通貨順位の差。 */
    int mediumShortRankDifference;
    /** 長中期と中短期の小さいほうの絶対順位差。 */
    int minimumRankDifference;
    /** 長中期と中短期の絶対順位差合計。 */
    int totalRankDifference;

    /**
     * 保持値を初期化する。
     */
    void reset() {
        this.symbolName = "";
        this.isBuy = false;
        this.baseLongMediumRank = 0;
        this.quoteLongMediumRank = 0;
        this.baseMediumShortRank = 0;
        this.quoteMediumShortRank = 0;
        this.longMediumRankDifference = 0;
        this.mediumShortRankDifference = 0;
        this.minimumRankDifference = 0;
        this.totalRankDifference = 0;
    }

    /**
     * 両期間の順位差がREADY基準を満たすか判定する。
     *
     * @return 小さいほうの順位差が4以上の場合true。
     */
    bool isReady() {
        return this.minimumRankDifference >= 4;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_MQH
