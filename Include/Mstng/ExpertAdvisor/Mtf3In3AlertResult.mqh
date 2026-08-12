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
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_RESULT_MQH
