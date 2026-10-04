#ifndef MSTNGM15EA_PERSISTENCE_DECISIONENTITY_MQH
#define MSTNGM15EA_PERSISTENCE_DECISIONENTITY_MQH

/**
 * M15 EA Decisionの保存スナップショット。
 * 任意文字列は空文字、任意正値は0、数量・損益はEMPTY_VALUEをNULLとして扱う。
 */
struct M15EaDecisionEntity {
    /** 主キー。 */
    long id;
    /** Run外部キー。 */
    long runId;
    /** LIVEでは再起動をまたぐEAコンテキスト。 */
    string contextKey;
    /** Alert DBとの照合にも使う市場シグナルキー。 */
    string marketSignalKey;
    /** 保存対象判定値のSHA-256。 */
    string snapshotHash;
    /** 判定を開始したM15バー時刻。 */
    long barTime;
    /** TimeCurrent()による判定完了時刻。 */
    long evaluatedServerTime;
    /** TimeLocal()による保存時刻。 */
    long createdAt;
    /** M15の2番目に新しいZigZagポイント時刻。 */
    long signalReferenceTime;
    /** SKIP、BUYまたはSELL。 */
    string decision;
    /** 最終判定または対象外理由。 */
    string reasonCode;
    /** BUYまたはSELL。 */
    string signalSide;
    /** M15戦略条件成立時1。EA発注制限は含めない。 */
    bool isJudgeMatched;
    /** 今回Judge成立時の加算後回数。Judge未成立・分析不能時は0。 */
    int signalCount;
    /** Entry評価対象の成立回数。初版は1固定。 */
    int entryCount;
    /** 今回、初回Judge成立により既存相当のEntry判定を実行した場合1。 */
    bool isEntryEvaluated;
    /** M15戦略のEntry成立時1。EA発注制限によるSKIPとは区別する。 */
    bool isStrategyEntry;
    /** 同一シグナルの初回Judge成立行だけ1。Entry不成立のSKIPも消費する。 */
    bool isSignalConsumed;
    /** 判定時Spread。 */
    double spreadPips;
    /** 正規化後の要求ロット。 */
    double requestedVolume;
    /** 注文前に検証した初期SL。 */
    double initialStopLoss;
    /** 建値候補から初期SLまでの幅。 */
    double initialRiskPips;
    /** Runで使用した初期SL最大幅。 */
    double maxInitialRiskPips;
    /** M15_EA_DECISION_V1で始まる診断値のCanonical Text。 */
    string analysisSnapshotText;

    /**
     * 未取得値と有効な0を区別して初期化する。
     */
    M15EaDecisionEntity() {
        this.reset();
    }

    /**
     * 保存前の未取得状態へ戻す。
     */
    void reset() {
        this.id = 0;
        this.runId = 0;
        this.contextKey = "";
        this.marketSignalKey = "";
        this.snapshotHash = "";
        this.barTime = 0;
        this.evaluatedServerTime = 0;
        this.createdAt = 0;
        this.signalReferenceTime = 0;
        this.decision = "SKIP";
        this.reasonCode = "";
        this.signalSide = "";
        this.isJudgeMatched = false;
        this.signalCount = 0;
        this.entryCount = 1;
        this.isEntryEvaluated = false;
        this.isStrategyEntry = false;
        this.isSignalConsumed = false;
        this.spreadPips = EMPTY_VALUE;
        this.requestedVolume = EMPTY_VALUE;
        this.initialStopLoss = 0.0;
        this.initialRiskPips = 0.0;
        this.maxInitialRiskPips = 0.0;
        this.analysisSnapshotText = "";
    }
};

#endif
