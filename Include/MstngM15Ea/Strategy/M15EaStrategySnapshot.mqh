#ifndef MSTNGM15EA_STRATEGY_SNAPSHOT_MQH
#define MSTNGM15EA_STRATEGY_SNAPSHOT_MQH

#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>

/**
 * 元M15の回数キーと、補正を含む採用分析のSL基準点を分離して保持する。
 */
struct M15EaStrategySnapshot {
    /** 評価対象M15バー。 */
    datetime barTime;

    /** 分析時刻。 */
    datetime evaluatedTime;

    /** 元M15がBUYの場合true。 */
    bool isBuy;

    /** 元M15のBUYまたはSELL。 */
    string signalSide;

    /** 回数キーとなる元M15の第2ポイント時刻。 */
    datetime signalReferenceTime;

    /** 元M15の第2ポイント価格。 */
    double signalReferencePrice;

    /** 元M15の第2ポイントが山の場合true。 */
    bool signalReferenceIsHigh;

    /** 採用M15のSL基準ポイント時刻。 */
    datetime initialStopLossPivotTime;

    /** 採用M15のSL基準ポイント価格。 */
    double initialStopLossPivotPrice;

    /** 採用M15のSL基準ポイントが山の場合true。 */
    bool initialStopLossPivotIsHigh;

    /** 分析時Spread。 */
    double spreadPips;

    /** 分析時Bid。 */
    double bid;

    /** 分析時Ask。 */
    double ask;

    /** 既存M15戦略の全Judge条件成立。 */
    bool isJudge;

    /** 今回Judge成立後の回数。未成立は0。 */
    int signalCount;

    /** 初回の詳細Entryを評価した場合true。 */
    bool isEntryEvaluated;

    /** 発注制限を適用する前の戦略Entry。 */
    bool isStrategyEntry;

    /** 全条件を満たした初回シグナルを消費した場合true。 */
    bool isSignalConsumed;

    /** 戦略の結果理由。 */
    string reasonCode;

    /** 元分析・採用分析・設定を記録した診断文字列。 */
    string analysisSnapshotText;

    /** 採用した補正足。補正なしはPERIOD_CURRENT。 */
    ENUM_TIMEFRAMES correctionTimeFrame;

    /** 判定に採用できる分析を取得した場合true。 */
    bool isJudgmentAnalysisAvailable;

    /** 既存M15判定の正本結果。 */
    Mtf3In3AlertResult alertResult;

    /**
     * 未判定状態へ戻し、元キーと採用SLの混在を防ぐ。
     */
    void reset() {
        this.barTime = 0;
        this.evaluatedTime = 0;
        this.isBuy = false;
        this.signalSide = "";
        this.signalReferenceTime = 0;
        this.signalReferencePrice = 0.0;
        this.signalReferenceIsHigh = false;
        this.initialStopLossPivotTime = 0;
        this.initialStopLossPivotPrice = 0.0;
        this.initialStopLossPivotIsHigh = false;
        this.spreadPips = 0.0;
        this.bid = 0.0;
        this.ask = 0.0;
        this.isJudge = false;
        this.signalCount = 0;
        this.isEntryEvaluated = false;
        this.isStrategyEntry = false;
        this.isSignalConsumed = false;
        this.reasonCode = "NOT_EVALUATED";
        this.analysisSnapshotText = "";
        this.correctionTimeFrame = PERIOD_CURRENT;
        this.isJudgmentAnalysisAvailable = false;
        this.alertResult.reset();
    }
};

#endif
