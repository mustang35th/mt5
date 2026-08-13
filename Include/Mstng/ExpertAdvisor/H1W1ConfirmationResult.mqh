//+------------------------------------------------------------------+
//|                                       H1W1ConfirmationResult.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_RESULT_MQH
#define MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_RESULT_MQH

/**
 * H1エントリーのW1確認診断結果。
 */
struct H1W1ConfirmationResult {
    /** 選択されたW1確認モード。 */
    string mode;

    /** W1方向とEMA200方向から分類した状態。 */
    string state;

    /** W1分析結果を取得できた場合true。 */
    bool isAvailable;

    /** W1方向とEMA200方向が判定可能な値の場合true。 */
    bool isValid;

    /** W1方向がエントリー方向と一致する場合true。 */
    bool isDirectionMatched;

    /** W1 EMA200方向。 */
    string ema200Direction;

    /** W1 EMA200方向がエントリー方向と一致する場合true。 */
    bool isEma200Matched;

    /** 選択モードのW1確認条件を満たす場合true。 */
    bool isPassed;

    /**
     * H1以外の未適用結果へ初期化する。
     */
    void reset() {
        this.mode = "OFF";
        this.state = "NOT_APPLICABLE";
        this.isAvailable = false;
        this.isValid = false;
        this.isDirectionMatched = false;
        this.ema200Direction = "NONE";
        this.isEma200Matched = false;
        this.isPassed = true;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_W1_CONFIRMATION_RESULT_MQH
