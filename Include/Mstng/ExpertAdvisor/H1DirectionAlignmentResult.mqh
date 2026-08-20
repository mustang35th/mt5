//+------------------------------------------------------------------+
//|                                   H1DirectionAlignmentResult.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_RESULT_MQH
#define MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_RESULT_MQH

/**
 * H1エントリーの上位時間足売買方向一致診断結果。
 */
struct H1DirectionAlignmentResult {
    /** 選択された方向一致モード。 */
    string mode;

    /** 時間足別の一致状態。 */
    string state;

    /** 必要な時間足の分析結果を取得できた場合true。 */
    bool isAvailable;

    /** 必要な時間足の方向値が判定可能な場合true。 */
    bool isValid;

    /** H1を基準とした判定方向。 */
    string direction;

    /** MN1方向がH1方向と一致する場合true。 */
    bool isMn1DirectionMatched;

    /** W1方向がH1方向と一致する場合true。 */
    bool isW1DirectionMatched;

    /** 選択範囲の方向一致条件を満たす場合true。 */
    bool isPassed;

    /**
     * H1以外の未適用結果へ初期化する。
     */
    void reset() {
        this.mode = "D1_TO_H1";
        this.state = "NOT_APPLICABLE";
        this.isAvailable = false;
        this.isValid = false;
        this.direction = "NONE";
        this.isMn1DirectionMatched = false;
        this.isW1DirectionMatched = false;
        this.isPassed = true;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_DIRECTION_ALIGNMENT_RESULT_MQH
