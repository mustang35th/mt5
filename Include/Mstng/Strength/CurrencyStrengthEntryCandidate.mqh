//+------------------------------------------------------------------+
//|                               CurrencyStrengthEntryCandidate.mqh |
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

    /** H1 EMA200の判定値を取得済みの場合true。 */
    bool h1EmaAvailable;

    /** H1 EMA200がBUYの場合true。 */
    bool h1EmaIsBuy;

    /** H1 EMA200がSELLの場合true。 */
    bool h1EmaIsSell;

    /** H1 EMA200の判定に使用した確定足の開始時刻。 */
    datetime h1EmaBarTime;

    /** 判定対象のH1確定足に対応するEMA200価格。 */
    double h1EmaValue;

    /** H1 EMA200価格の実シンボル小数桁数。 */
    int h1EmaDigits;

    /** H1確定足終値とEMA200の価格差pips。 */
    double h1EmaCloseDiffPips;

    /** 共通ルールの比較足に対するH1 EMA200の傾きpips。 */
    double h1EmaSlopePips;

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
        this.resetH1Ema();
    }

    /**
     * H1 EMA200の取得状態と判定値を初期化する。
     */
    void resetH1Ema() {
        this.h1EmaAvailable = false;
        this.h1EmaIsBuy = false;
        this.h1EmaIsSell = false;
        this.h1EmaBarTime = 0;
        this.h1EmaValue = 0.0;
        this.h1EmaDigits = 0;
        this.h1EmaCloseDiffPips = 0.0;
        this.h1EmaSlopePips = 0.0;
    }

    /**
     * 長中期の強い通貨が1位、または弱い通貨が8位か判定する。
     *
     * @return 候補方向と一致する端順位の場合true。同順位と無効順位は除く。
     */
    bool isLongMediumExtremeRankMatched() {
        if (this.baseLongMediumRank < 1 || this.baseLongMediumRank > 8
                || this.quoteLongMediumRank < 1 || this.quoteLongMediumRank > 8) {
            return false;
        }

        if (this.isBuy) {
            return this.baseLongMediumRank < this.quoteLongMediumRank
                && (this.baseLongMediumRank == 1 || this.quoteLongMediumRank == 8);
        }

        return this.baseLongMediumRank > this.quoteLongMediumRank
            && (this.baseLongMediumRank == 8 || this.quoteLongMediumRank == 1);
    }

    /**
     * 長中期が候補方向と一致し、順位差または端順位の条件を満たすか判定する。
     *
     * @param fromMinimumRankDifference 順位差の基準。1から7を指定する。
     * @return 順位差の基準または方向に合う1位・8位を満たす場合true。
     */
    bool isLongMediumRankConditionMatched(const int fromMinimumRankDifference) {
        if (fromMinimumRankDifference < 1 || fromMinimumRankDifference > 7
                || this.baseLongMediumRank < 1 || this.baseLongMediumRank > 8
                || this.quoteLongMediumRank < 1 || this.quoteLongMediumRank > 8) {
            return false;
        }

        int rankDifference = this.quoteLongMediumRank - this.baseLongMediumRank;
        if (this.isBuy) {
            return rankDifference >= fromMinimumRankDifference
                || this.isLongMediumExtremeRankMatched();
        }

        return rankDifference <= 0 - fromMinimumRankDifference
            || this.isLongMediumExtremeRankMatched();
    }

    /**
     * 両期間が候補方向と一致し、READY基準を満たすか判定する。
     *
     * @return 長中期は順位差4以上または端順位、中短期は順位差4以上の場合true。
     */
    bool isReady() {
        if (!this.isLongMediumRankConditionMatched(4)
                || this.baseMediumShortRank < 1 || this.baseMediumShortRank > 8
                || this.quoteMediumShortRank < 1 || this.quoteMediumShortRank > 8) {
            return false;
        }

        int rankDifference = this.quoteMediumShortRank - this.baseMediumShortRank;
        if (this.isBuy) {
            return rankDifference >= 4;
        }

        return rankDifference <= -4;
    }

    /**
     * 候補方向と取得済みH1 EMA200の方向が一致するか判定する。
     *
     * @return BUY同士またはSELL同士の場合true。
     */
    bool isH1EmaMatched() {
        if (!this.h1EmaAvailable) {
            return false;
        }

        if (this.isBuy) {
            return this.h1EmaIsBuy && !this.h1EmaIsSell;
        }

        return this.h1EmaIsSell && !this.h1EmaIsBuy;
    }

    /**
     * 通貨順位のREADY条件とH1 EMA200方向一致を満たすか判定する。
     *
     * @return 両条件を満たす場合true。
     */
    bool isAndReady() {
        return this.isReady() && this.isH1EmaMatched();
    }

    /**
     * H1 EMA200の方向または未取得を表すラベルを取得する。
     *
     * @return BUY、SELL、NONE、未取得のいずれか。
     */
    string getH1EmaLabel() {
        if (!this.h1EmaAvailable) {
            return "—";
        }

        if (this.h1EmaIsBuy) {
            return "BUY";
        }

        if (this.h1EmaIsSell) {
            return "SELL";
        }

        return "NONE";
    }

    /**
     * 強弱READYとH1 EMA200のAND判定結果を取得する。
     *
     * @return 成立、逆向き、方向なし、取得待ち、強弱待ちのいずれか。
     */
    string getAndStatusLabel() {
        if (!this.isReady()) {
            return "強弱待ち";
        }

        if (!this.h1EmaAvailable) {
            return "取得待ち";
        }

        if (this.isH1EmaMatched()) {
            return "成立";
        }

        if (this.h1EmaIsBuy || this.h1EmaIsSell) {
            return "逆向き";
        }

        return "方向なし";
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_MQH
