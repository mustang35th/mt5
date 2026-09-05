#ifndef MSTNGH1EA_STRATEGY_SNAPSHOT_MQH
#define MSTNGH1EA_STRATEGY_SNAPSHOT_MQH

#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>

/**
 * 発注可否とは分離したH1戦略の分析時点と判定結果を保持する。
 */
struct H1EaStrategySnapshot {
    /** 評価対象H1バー。 */
    datetime h1BarTime;
    /** 分析時刻。 */
    datetime evaluatedTime;
    /** シグナル基準となる1つ前のH1点の時刻。 */
    datetime signalReferenceTime;
    /** シグナルのBUY/SELL方向。 */
    string signalSide;
    /** BUYの場合true。 */
    bool isBuy;
    /** シグナル基準点の価格。 */
    double signalReferencePrice;
    /** シグナル基準点が山の場合true。 */
    bool signalReferenceIsHigh;
    /** 分析時Spread。 */
    double spreadPips;
    /** 分析時Bid。 */
    double bid;
    /** 分析時Ask。 */
    double ask;
    /** MN1多数決方向。 */
    string mn1Direction;
    /** W1多数決方向。 */
    string w1Direction;
    /** D1多数決方向。 */
    string d1Direction;
    /** H4多数決方向。 */
    string h4Direction;
    /** H1多数決方向。 */
    string h1Direction;
    /** W1 EMA200方向。 */
    string w1Ema200Direction;
    /** H4 EMA200方向。 */
    string h4Ema200Direction;
    /** H1 EMA200方向。 */
    string h1Ema200Direction;
    /** H1 GMMAトレンド回数。 */
    int h1GmmaTrendCount;
    /** H1 GMMAクロス回数。 */
    int h1GmmaCrossCount;
    /** H1最新波動ラベル。 */
    string h1ElliotLabel;
    /** H4最新波動ラベル。 */
    string h4ElliotLabel;
    /** H1最新Wave方向。 */
    string h1WaveDirection;
    /** H1波動診断結果。Entry実行とは別。 */
    bool isH1WaveAccepted;
    /** H4波動診断結果。Entry実行とは別。 */
    bool isH4WaveAccepted;
    /** 上位方向一致診断結果。 */
    bool isH1DirectionAlignmentPassed;
    /** 共通Judge成立。 */
    bool isJudge;
    /** 今回Judge成立後の回数。Judge NGでは0。 */
    int signalCount;
    /** 詳細Entryを実行した場合true。 */
    bool isEntryEvaluated;
    /** 発注安全条件を適用する前の戦略Entry。 */
    bool isStrategyEntry;
    /** 今回初回Judgeを消費した場合true。 */
    bool isSignalConsumed;
    /** 戦略の結果理由。 */
    string reasonCode;
    /** 保存用の分析診断文字列。 */
    string analysisSnapshotText;
    /** 既存戦略の正本結果。 */
    Mtf3In3AlertResult alertResult;

    /**
     * 全フィールドを未判定に戻す。
     */
    void reset() {
        this.h1BarTime = 0;
        this.evaluatedTime = 0;
        this.signalReferenceTime = 0;
        this.signalSide = "";
        this.isBuy = false;
        this.signalReferencePrice = 0.0;
        this.signalReferenceIsHigh = false;
        this.spreadPips = 0.0;
        this.bid = 0.0;
        this.ask = 0.0;
        this.mn1Direction = "";
        this.w1Direction = "";
        this.d1Direction = "";
        this.h4Direction = "";
        this.h1Direction = "";
        this.w1Ema200Direction = "";
        this.h4Ema200Direction = "";
        this.h1Ema200Direction = "";
        this.h1GmmaTrendCount = 0;
        this.h1GmmaCrossCount = 0;
        this.h1ElliotLabel = "";
        this.h4ElliotLabel = "";
        this.h1WaveDirection = "";
        this.isH1WaveAccepted = false;
        this.isH4WaveAccepted = false;
        this.isH1DirectionAlignmentPassed = false;
        this.isJudge = false;
        this.signalCount = 0;
        this.isEntryEvaluated = false;
        this.isStrategyEntry = false;
        this.isSignalConsumed = false;
        this.reasonCode = "NOT_EVALUATED";
        this.analysisSnapshotText = "";
        this.alertResult.reset();
    }
};

#endif
