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

#include <Mstng\Strength\CurrencyStrengthRankGapDirectionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthTrendContinuationInfo.mqh>

/**
 * 売買候補のAND成立に使用するEMA200時間足。
 */
enum CurrencyStrengthEntryEmaMode {
    currencyStrengthEntryEmaH1 = 0,
    currencyStrengthEntryEmaM1 = 1,
    currencyStrengthEntryEmaH1AndM1 = 2
};

/**
 * 候補一覧の順位差増減フィルタに使用する集計期間。
 */
enum CurrencyStrengthEntryGapMode {
    currencyStrengthEntryGapOff = 0,
    currencyStrengthEntryGapLongMedium = 1,
    currencyStrengthEntryGapMediumShort = 2,
    currencyStrengthEntryGapBoth = 3
};

/**
 * 長中期と中短期の通貨順位から抽出した
 * エントリー候補通貨ペア1件分を保持する。
 */
struct CurrencyStrengthEntryCandidate {
    /** 正規化された通貨ペア名。 */
    string symbolName;

    /** ブローカー上の実シンボル名。 */
    string resolvedSymbolName;

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

    /** 直近3時間の通貨強弱方向の継続判定。 */
    CurrencyStrengthTrendContinuationInfo continuation;

    /** 長中期順位差の直近増減方向。横ばいでは連続する過去M5の方向を維持する。 */
    CurrencyStrengthRankGapDirectionInfo longMediumGapDirection;

    /** 中短期順位差の直近増減方向。横ばいでは連続する過去M5の方向を維持する。 */
    CurrencyStrengthRankGapDirectionInfo mediumShortGapDirection;

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

    /** M1 EMA200の判定値を取得済みの場合true。 */
    bool m1EmaAvailable;

    /** M1 EMA200がBUYの場合true。 */
    bool m1EmaIsBuy;

    /** M1 EMA200がSELLの場合true。 */
    bool m1EmaIsSell;

    /** M1 EMA200の判定に使用した確定足の開始時刻。 */
    datetime m1EmaBarTime;

    /** 判定対象のM1確定足に対応するEMA200価格。 */
    double m1EmaValue;

    /** M1 EMA200価格の実シンボル小数桁数。 */
    int m1EmaDigits;

    /** M1確定足終値とEMA200の価格差pips。 */
    double m1EmaCloseDiffPips;

    /** 共通ルールの比較足に対するM1 EMA200の傾きpips。 */
    double m1EmaSlopePips;

    /**
     * 保持値を初期化する。
     */
    void reset() {
        this.symbolName = "";
        this.resolvedSymbolName = "";
        this.isBuy = false;
        this.baseLongMediumRank = 0;
        this.quoteLongMediumRank = 0;
        this.baseMediumShortRank = 0;
        this.quoteMediumShortRank = 0;
        this.longMediumRankDifference = 0;
        this.mediumShortRankDifference = 0;
        this.minimumRankDifference = 0;
        this.totalRankDifference = 0;
        this.continuation.reset();
        this.longMediumGapDirection.reset();
        this.mediumShortGapDirection.reset();
        this.resetH1Ema();
        this.resetM1Ema();
    }

    /**
     * 取得済みの長中期増減方向と現在順位差が候補方向に一致するか判定する。
     *
     * @return 評価済みで、現在順位差と直近増減の両方が候補方向に合う場合true。
     */
    bool isLongMediumGapDirectionMatched() {
        return this.longMediumGapDirection.enabled
            && this.longMediumGapDirection.isMatched(this.isBuy);
    }

    /**
     * 取得済みの中短期増減方向と現在順位差が候補方向に一致するか判定する。
     *
     * @return 評価済みで、現在順位差と直近増減の両方が候補方向に合う場合true。
     */
    bool isMediumShortGapDirectionMatched() {
        return this.mediumShortGapDirection.enabled
            && this.mediumShortGapDirection.isMatched(this.isBuy);
    }

    /**
     * 選択した集計期間の順位差と直近増減方向が候補方向に一致するか判定する。
     *
     * @param fromMode 増減判定に使用する集計期間。
     * @return OFFまたは選択した全期間で方向一致の場合true。
     */
    bool isGapDirectionMatched(const CurrencyStrengthEntryGapMode fromMode) {
        if (fromMode == currencyStrengthEntryGapOff) {
            return true;
        }

        if (fromMode == currencyStrengthEntryGapLongMedium) {
            return this.isLongMediumGapDirectionMatched();
        }

        if (fromMode == currencyStrengthEntryGapMediumShort) {
            return this.isMediumShortGapDirectionMatched();
        }

        if (fromMode == currencyStrengthEntryGapBoth) {
            return this.isLongMediumGapDirectionMatched() && this.isMediumShortGapDirectionMatched();
        }

        return false;
    }

    /**
     * 選択した集計期間の増減方向が、候補方向との一致に関係なく確定しているか判定する。
     *
     * @param fromMode 増減判定に使用する集計期間。
     * @return OFFまたは選択した全期間で増減方向を取得済みの場合true。
     */
    bool isGapDirectionAvailable(const CurrencyStrengthEntryGapMode fromMode) {
        if (fromMode == currencyStrengthEntryGapOff) {
            return true;
        }

        if (fromMode == currencyStrengthEntryGapLongMedium) {
            return this.isDirectionAvailable(this.longMediumGapDirection);
        }

        if (fromMode == currencyStrengthEntryGapMediumShort) {
            return this.isDirectionAvailable(this.mediumShortGapDirection);
        }

        if (fromMode == currencyStrengthEntryGapBoth) {
            return this.isDirectionAvailable(this.longMediumGapDirection)
                && this.isDirectionAvailable(this.mediumShortGapDirection);
        }

        return false;
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
     * M1 EMA200の取得状態と判定値を初期化する。
     */
    void resetM1Ema() {
        this.m1EmaAvailable = false;
        this.m1EmaIsBuy = false;
        this.m1EmaIsSell = false;
        this.m1EmaBarTime = 0;
        this.m1EmaValue = 0.0;
        this.m1EmaDigits = 0;
        this.m1EmaCloseDiffPips = 0.0;
        this.m1EmaSlopePips = 0.0;
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
     * 中短期の強い通貨が1位、または弱い通貨が8位か判定する。
     *
     * @return 候補方向と一致する端順位の場合true。同順位と無効順位は除く。
     */
    bool isMediumShortExtremeRankMatched() {
        if (this.baseMediumShortRank < 1 || this.baseMediumShortRank > 8
                || this.quoteMediumShortRank < 1 || this.quoteMediumShortRank > 8) {
            return false;
        }

        if (this.isBuy) {
            return this.baseMediumShortRank < this.quoteMediumShortRank
                && (this.baseMediumShortRank == 1 || this.quoteMediumShortRank == 8);
        }

        return this.baseMediumShortRank > this.quoteMediumShortRank
            && (this.baseMediumShortRank == 8 || this.quoteMediumShortRank == 1);
    }

    /**
     * 中短期が候補方向と一致し、順位差または端順位の条件を満たすか判定する。
     *
     * @param fromMinimumRankDifference 順位差の基準。1から7を指定する。
     * @return 順位差の基準または方向に合う1位・8位を満たす場合true。
     */
    bool isMediumShortRankConditionMatched(const int fromMinimumRankDifference) {
        if (fromMinimumRankDifference < 1 || fromMinimumRankDifference > 7
                || this.baseMediumShortRank < 1 || this.baseMediumShortRank > 8
                || this.quoteMediumShortRank < 1 || this.quoteMediumShortRank > 8) {
            return false;
        }

        int rankDifference = this.quoteMediumShortRank - this.baseMediumShortRank;
        if (this.isBuy) {
            return rankDifference >= fromMinimumRankDifference
                || this.isMediumShortExtremeRankMatched();
        }

        return rankDifference <= 0 - fromMinimumRankDifference
            || this.isMediumShortExtremeRankMatched();
    }

    /**
     * 両期間が候補方向と一致し、READY基準を満たすか判定する。
     *
     * @return 長中期・中短期の両方が順位差4以上または端順位の場合true。
     */
    bool isReady() {
        return this.isLongMediumRankConditionMatched(4)
            && this.isMediumShortRankConditionMatched(4);
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
     * 候補方向と取得済みM1 EMA200の方向が一致するか判定する。
     *
     * @return BUY同士またはSELL同士の場合true。
     */
    bool isM1EmaMatched() {
        if (!this.m1EmaAvailable) {
            return false;
        }

        if (this.isBuy) {
            return this.m1EmaIsBuy && !this.m1EmaIsSell;
        }

        return this.m1EmaIsSell && !this.m1EmaIsBuy;
    }

    /**
     * 通貨順位のREADY条件と選択したEMA200方向一致を満たすか判定する。
     *
     * @param fromMode AND成立に使用するEMA200時間足。
     * @return 強弱READYと選択した全時間足のEMA方向一致を満たす場合true。
     */
    bool isAndReady(CurrencyStrengthEntryEmaMode fromMode = currencyStrengthEntryEmaH1) {
        if (!this.isReady()) {
            return false;
        }

        if (fromMode == currencyStrengthEntryEmaM1) {
            return this.isM1EmaMatched();
        }

        if (fromMode == currencyStrengthEntryEmaH1AndM1) {
            return this.isH1EmaMatched() && this.isM1EmaMatched();
        }

        return this.isH1EmaMatched();
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
     * M1 EMA200の方向または未取得を表すラベルを取得する。
     *
     * @return BUY、SELL、NONE、未取得のいずれか。
     */
    string getM1EmaLabel() {
        if (!this.m1EmaAvailable) {
            return "—";
        }

        if (this.m1EmaIsBuy) {
            return "BUY";
        }

        if (this.m1EmaIsSell) {
            return "SELL";
        }

        return "NONE";
    }

    /**
     * 強弱READYと選択したEMA200のAND判定結果を取得する。
     *
     * @param fromMode AND成立に使用するEMA200時間足。
     * @return 成立または未成立理由。両足指定時は一致待ちの時間足を返す。
     */
    string getAndStatusLabel(CurrencyStrengthEntryEmaMode fromMode = currencyStrengthEntryEmaH1) {
        if (!this.isReady()) {
            return "強弱待ち";
        }

        if (fromMode == currencyStrengthEntryEmaH1AndM1) {
            bool isH1Matched = this.isH1EmaMatched();
            bool isM1Matched = this.isM1EmaMatched();
            if (isH1Matched && isM1Matched) {
                return "成立";
            }

            if (!isH1Matched && !isM1Matched) {
                return "両足待ち";
            }

            if (!isH1Matched) {
                return "H1待ち";
            }

            return "M1待ち";
        }

        if (fromMode == currencyStrengthEntryEmaM1) {
            if (!this.m1EmaAvailable) {
                return "取得待ち";
            }

            if (this.isM1EmaMatched()) {
                return "成立";
            }

            if (this.m1EmaIsBuy || this.m1EmaIsSell) {
                return "逆向き";
            }

            return "方向なし";
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

private:
    /**
     * 1集計期間の取得状態と増減方向・根拠時刻が有効か判定する。
     */
    bool isDirectionAvailable(const CurrencyStrengthRankGapDirectionInfo &fromInfo) {
        return fromInfo.enabled && !fromInfo.waiting && fromInfo.currentAvailable
            && fromInfo.hasPrevious && (fromInfo.direction == 1 || fromInfo.direction == -1)
            && fromInfo.targetM5BarTime > 0 && fromInfo.directionChangedAt > 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_CANDIDATE_MQH
