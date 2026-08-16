//+------------------------------------------------------------------+
//|                                           Mtf3In3AlertResult.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_RESULT_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_RESULT_MQH

/**
 * MTF_3in3のアラート判定と最終エントリー判定を保持する。
 */
struct Mtf3In3AlertResult {
    /** isJudge()の判定結果。 */
    bool isJudge;

    /** 同一シグナルの発生回数。 */
    int signalCount;

    /** エントリー対象とする発生回数。 */
    int entryCount;

    /** 同一シグナルの発生回数がエントリー対象回数と一致する場合true。 */
    bool isEntryCountMatch;

    /** setEntry()を実行した場合true。 */
    bool isEntryEvaluated;

    /** アラート対象の場合true。 */
    bool isAlert;

    /** エントリー条件を満たした場合true。 */
    bool isEntry;

    /** メール送信対象の場合true。 */
    bool isSendMail;

    /** BUY方向の場合true。 */
    bool isBuy;

    /** エントリー判定結果コード。 */
    string entryResult;

    /** 現在時間足のElliottラベル。 */
    string currentElliotLabel;

    /** 現在時間足がエントリー対象波動の場合true。 */
    bool isEntryWave;

    /** Close1とEMA200[1]の距離pips。 */
    double closeEma200DiffPips;

    /** Close1とEMA200[1]の許容距離pips。 */
    double maxCloseEma200DiffPips;

    /** Close1とEMA200[1]の距離が許容範囲内の場合true。 */
    bool isEma200DistanceWithin;

    /** H1 W1確認モード。 */
    string w1ConfirmationMode;

    /** H1 W1確認の診断状態。 */
    string w1ConfirmationState;

    /** W1分析結果を取得できた場合true。 */
    bool isW1ConfirmationAvailable;

    /** W1方向とEMA200方向が判定可能な値の場合true。 */
    bool isW1ConfirmationValid;

    /** W1方向がエントリー方向と一致する場合true。 */
    bool isW1DirectionMatched;

    /** W1 EMA200方向。 */
    string w1Ema200Direction;

    /** W1 EMA200方向がエントリー方向と一致する場合true。 */
    bool isW1Ema200Matched;

    /** 選択モードのW1確認条件を満たす場合true。 */
    bool isW1ConfirmationPassed;

    /** H1方向一致モード。 */
    string h1DirectionAlignmentMode;

    /** H1方向一致の診断状態。 */
    string h1DirectionAlignmentState;

    /** H1方向一致に必要な分析結果を取得できた場合true。 */
    bool isH1DirectionAlignmentAvailable;

    /** H1方向一致に必要な方向値が判定可能な場合true。 */
    bool isH1DirectionAlignmentValid;

    /** H1を基準とした判定方向。 */
    string h1DirectionAlignmentDirection;

    /** MN1方向がH1方向と一致する場合true。 */
    bool isH1Mn1DirectionMatched;

    /** W1方向がH1方向と一致する場合true。 */
    bool isH1W1DirectionMatched;

    /** 選択範囲のH1方向一致条件を満たす場合true。 */
    bool isH1DirectionAlignmentPassed;

    /**
     * 全フィールドを未判定状態へ初期化する。
     */
    void reset() {
        this.isJudge = false;
        this.signalCount = 0;
        this.entryCount = 0;
        this.isEntryCountMatch = false;
        this.isEntryEvaluated = false;
        this.isAlert = false;
        this.isEntry = false;
        this.isSendMail = false;
        this.isBuy = false;
        this.entryResult = "NOT_EVALUATED";
        this.currentElliotLabel = "";
        this.isEntryWave = false;
        this.closeEma200DiffPips = 0.0;
        this.maxCloseEma200DiffPips = 0.0;
        this.isEma200DistanceWithin = false;
        this.w1ConfirmationMode = "OFF";
        this.w1ConfirmationState = "NOT_APPLICABLE";
        this.isW1ConfirmationAvailable = false;
        this.isW1ConfirmationValid = false;
        this.isW1DirectionMatched = false;
        this.w1Ema200Direction = "NONE";
        this.isW1Ema200Matched = false;
        this.isW1ConfirmationPassed = true;
        this.h1DirectionAlignmentMode = "D1_TO_H1";
        this.h1DirectionAlignmentState = "NOT_APPLICABLE";
        this.isH1DirectionAlignmentAvailable = false;
        this.isH1DirectionAlignmentValid = false;
        this.h1DirectionAlignmentDirection = "NONE";
        this.isH1Mn1DirectionMatched = false;
        this.isH1W1DirectionMatched = false;
        this.isH1DirectionAlignmentPassed = true;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_RESULT_MQH
