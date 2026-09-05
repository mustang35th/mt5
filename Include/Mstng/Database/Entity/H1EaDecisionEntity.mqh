#ifndef MSTNG_DATABASE_ENTITY_H1_EA_DECISION_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_H1_EA_DECISION_ENTITY_MQH

/**
 * H1 EA Decisionの保存スナップショット。
 * 任意文字列は空文字、任意正値は0、数量・損益はEMPTY_VALUEをNULLとして扱う。
 */
struct H1EaDecisionEntity {
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
    /** 判定を開始したH1バー時刻。 */
    long h1BarTime;
    /** TimeCurrent()による判定完了時刻。 */
    long evaluatedServerTime;
    /** TimeLocal()による保存時刻。 */
    long createdAt;
    /** H1の2番目に新しいZigZagポイント時刻。 */
    long signalReferenceTime;
    /** SKIP、BUYまたはSELL。 */
    string decision;
    /** 最終判定または対象外理由。 */
    string reasonCode;
    /** BUYまたはSELL。 */
    string signalSide;
    /** 共通Judge成立時1。Entry波動条件とEA発注制限は含めない。 */
    bool isJudgeMatched;
    /** 今回Judge成立時の加算後回数。Judge未成立・分析不能時は0。 */
    int signalCount;
    /** Entry評価対象の成立回数。初版は1固定。 */
    int entryCount;
    /** 今回、初回Judge成立により既存相当のEntry判定を実行した場合1。 */
    bool isEntryEvaluated;
    /** 既存H1戦略のEntry成立時1。EA発注制限によるSKIPとは区別する。 */
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
    /** MN1のBUYまたはSELL。 */
    string mn1Direction;
    /** W1のBUYまたはSELL。 */
    string w1Direction;
    /** D1のBUYまたはSELL。 */
    string d1Direction;
    /** H4のBUYまたはSELL。 */
    string h4Direction;
    /** H1のBUYまたはSELL。 */
    string h1Direction;
    /** H1最新Waveの方向。 */
    string h1WaveDirection;
    /** H1最新Elliottラベル。 */
    string h1ElliotLabel;
    /** H4最新Elliottラベル。 */
    string h4ElliotLabel;
    /** H1波動条件通過。 */
    bool isH1WaveAccepted;
    /** H4波動条件通過。 */
    bool isH4WaveAccepted;
    /** H1 GMMA trend count。 */
    int h1GmmaTrendCount;
    /** H1 GMMA cross count。 */
    int h1GmmaCrossCount;
    /** H1 EMA200方向。BUY、SELLまたはNONE。 */
    string h1Ema200Direction;
    /** H4 EMA200方向。BUY、SELLまたはNONE。 */
    string h4Ema200Direction;
    /** W1 EMA200方向。BUY、SELLまたはNONE。 */
    string w1Ema200Direction;
    /** Runの固定方向一致モード。 */
    string h1DirectionAlignmentMode;
    /** W1からH1一致かつMN1方向またはW1 EMA200方向一致の場合1。 */
    bool isH1DirectionAlignmentPassed;
    /** 追加診断値のCanonical Text。 */
    string analysisSnapshotText;

    /**
     * 未取得値と有効な0を区別して初期化する。
     */
    H1EaDecisionEntity() {
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
        this.h1BarTime = 0;
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
        this.mn1Direction = "";
        this.w1Direction = "";
        this.d1Direction = "";
        this.h4Direction = "";
        this.h1Direction = "";
        this.h1WaveDirection = "";
        this.h1ElliotLabel = "";
        this.h4ElliotLabel = "";
        this.isH1WaveAccepted = false;
        this.isH4WaveAccepted = false;
        this.h1GmmaTrendCount = INT_MIN;
        this.h1GmmaCrossCount = INT_MIN;
        this.h1Ema200Direction = "";
        this.h4Ema200Direction = "";
        this.w1Ema200Direction = "";
        this.h1DirectionAlignmentMode = "";
        this.isH1DirectionAlignmentPassed = false;
        this.analysisSnapshotText = "";
    }
};

#endif
