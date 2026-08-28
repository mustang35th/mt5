//+------------------------------------------------------------------+
//|                     ZigZagElliotH1StudyOutcomeEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_ENTITY_MQH

/**
 * H1推移研究の将来成績計算Run。
 */
struct ZigZagElliotH1StudyOutcomeRunEntity {
    /** レコードID。 */
    long id;

    /** 同じ研究条件の再実行を識別するキー。 */
    string runKey;

    /** 参照元H1推移DBファイル名。 */
    string sourceDatabaseFileName;

    /** 参照元H1推移Run ID。 */
    long sourceRunId;

    /** 参照元H1推移Run UID。 */
    string sourceRunUid;

    /** 参照元実行モード。 */
    string sourceMode;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 参照元口座ログイン番号。 */
    long sourceLogin;

    /** 参照元プログラム名。 */
    string sourceProgramName;

    /** 参照元プログラムバージョン。 */
    string sourceProgramVersion;

    /** 参照元戦略名。 */
    string sourceStrategy;

    /** 参照元戦略バージョン。 */
    string sourceStrategyVersion;

    /** 参照元分析バージョン。 */
    string sourceAnalysisVersion;

    /** 参照元分析設定Hash。 */
    string sourceAnalysisInputHash;

    /** 参照元プログラム入力Hash。 */
    string sourceInputHash;

    /** 参照元テスター開始時刻。 */
    datetime sourceTesterFrom;

    /** 参照元テスター終了時刻。 */
    datetime sourceTesterTo;

    /** 参照元テスターモデル。 */
    string sourceTesterModel;

    /** 研究対象の開始日本時刻。 */
    datetime studyFromJstTime;

    /** 研究対象の終了日本時刻。対象外境界。 */
    datetime studyToJstTime;

    /** 連続シグナル判定ルールバージョン。 */
    string signalRuleVersion;

    /** 研究用エントリー価格モデル。 */
    string entryPriceModel;

    /** Spread控除モデル。 */
    string spreadModel;

    /** 将来成績計算ロジックバージョン。 */
    string evaluationVersion;

    /** 評価期間一覧のCanonical Text。 */
    string horizonsText;

    /** 実行状態。 */
    string status;

    /** 読み取ったシンボルStream数。 */
    long sourceStreamCount;

    /** 研究期間内の連続シグナル数。 */
    long totalSignalCount;

    /** 保存した研究用Entry数。 */
    long totalEntryCount;

    /** 基本集計へ使用可能なEntry数。 */
    long researchEligibleEntryCount;

    /** 保存対象Outcome総数。 */
    long totalOutcomeCount;

    /** 計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** 計算不能Outcome数。 */
    long failedOutcomeCount;

    /** 実行開始時刻。 */
    datetime startedAt;

    /** 実行完了時刻。RUNNING中は0。 */
    datetime completedAt;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード更新時刻。 */
    datetime updatedAt;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.runKey = "";
        this.sourceDatabaseFileName = "";
        this.sourceRunId = 0;
        this.sourceRunUid = "";
        this.sourceMode = "";
        this.sourceServer = "";
        this.sourceLogin = 0;
        this.sourceProgramName = "";
        this.sourceProgramVersion = "";
        this.sourceStrategy = "";
        this.sourceStrategyVersion = "";
        this.sourceAnalysisVersion = "";
        this.sourceAnalysisInputHash = "";
        this.sourceInputHash = "";
        this.sourceTesterFrom = 0;
        this.sourceTesterTo = 0;
        this.sourceTesterModel = "";
        this.studyFromJstTime = 0;
        this.studyToJstTime = 0;
        this.signalRuleVersion = "";
        this.entryPriceModel = "";
        this.spreadModel = "";
        this.evaluationVersion = "";
        this.horizonsText = "";
        this.status = "";
        this.sourceStreamCount = 0;
        this.totalSignalCount = 0;
        this.totalEntryCount = 0;
        this.researchEligibleEntryCount = 0;
        this.totalOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
        this.startedAt = 0;
        this.completedAt = 0;
        this.createdAt = 0;
        this.updatedAt = 0;
    }
};

/**
 * 連続シグナルから生成した研究用エントリー。
 */
struct ZigZagElliotH1StudyEntryEntity {
    /** レコードID。 */
    long id;

    /** H1推移研究Outcome Run ID。 */
    long outcomeRunId;

    /** 参照元H1推移Run ID。 */
    long sourceRunId;

    /** シグナル開始Observation ID。 */
    long signalStartObservationId;

    /** シグナル終了Observation ID。 */
    long signalEndObservationId;

    /** 連続確認に使用したObservation ID。 */
    long confirmationObservationId;

    /** 次H1始値を保持するObservation ID。利用不能時は0。 */
    long entryObservationId;

    /** 参照元実行モード。 */
    string sourceMode;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 対象シンボル名。 */
    string symbolName;

    /** 観測基準時間足。 */
    int anchorTimeFrame;

    /** 観測タイミング種別。 */
    string capturePhase;

    /** Elliott分析バージョン。 */
    string analysisVersion;

    /** Elliott分析設定Hash。 */
    string analysisInputHash;

    /** BUYまたはSELL。 */
    string side;

    /** 連続シグナル全体のH1本数。 */
    int episodeH1Count;

    /** エントリー判断に使用した連続確認本数。1、2または3。 */
    int confirmationH1Count;

    /** 左端がデータ開始で打ち切られている場合1。 */
    int isLeftCensored;

    /** 右端がデータ終了で打ち切られている場合1。 */
    int isRightCensored;

    /** シグナル直前に観測欠損がある場合1。 */
    int hasDataGapBefore;

    /** シグナル直後に観測欠損がある場合1。 */
    int hasDataGapAfter;

    /** 基本研究集計へ使用できる場合1。 */
    int isResearchEligible;

    /** 研究対象可否と理由を表す状態。 */
    string eligibilityStatus;

    /** シグナル開始サーバー時刻。 */
    datetime signalStartTime;

    /** シグナル終了サーバー時刻。 */
    datetime signalEndTime;

    /** 連続確認サーバー時刻。 */
    datetime confirmationTime;

    /** 仮想エントリーサーバー時刻。利用不能時は0。 */
    datetime entryTime;

    /** シグナル開始日本時刻。 */
    datetime signalStartJstTime;

    /** 連続確認日本時刻。 */
    datetime confirmationJstTime;

    /** 仮想エントリー日本時刻。利用不能時は0。 */
    datetime entryJstTime;

    /** 次H1始値。利用不能時は0。 */
    double entryPrice;

    /** エントリー時Spreadを取得できた場合1。 */
    int isSpreadAvailable;

    /** エントリー時Spread pips。利用不能時は0。 */
    double spreadPips;

    /** pip sizeを取得できた場合1。 */
    int isPipSizeAvailable;

    /** 1pip相当の価格幅。利用不能時は0。 */
    double pipSize;

    /** pip sizeの取得元または推定方法。 */
    string pipSizeSource;

    /** エントリー時H1 ATR14を取得できた場合1。 */
    int isEntryAtrAvailable;

    /** エントリーObservationのH1 ATR14 pips。 */
    double entryAtr14Pips;

    /** エントリー価格を確定できたか表す状態。 */
    string entryStatus;

    /** 候補抽出またはエントリー計算上の補足。 */
    string calculationNote;

    /** 連続シグナル判定ルールバージョン。 */
    string signalRuleVersion;

    /** 研究用エントリー価格モデル。 */
    string entryPriceModel;

    /** Spread控除モデル。 */
    string spreadModel;

    /** 将来成績計算ロジックバージョン。 */
    string evaluationVersion;

    /** レコード作成または最終再計算時刻。 */
    datetime createdAt;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.outcomeRunId = 0;
        this.sourceRunId = 0;
        this.signalStartObservationId = 0;
        this.signalEndObservationId = 0;
        this.confirmationObservationId = 0;
        this.entryObservationId = 0;
        this.sourceMode = "";
        this.sourceServer = "";
        this.symbolName = "";
        this.anchorTimeFrame = 0;
        this.capturePhase = "";
        this.analysisVersion = "";
        this.analysisInputHash = "";
        this.side = "";
        this.episodeH1Count = 0;
        this.confirmationH1Count = 0;
        this.isLeftCensored = 0;
        this.isRightCensored = 0;
        this.hasDataGapBefore = 0;
        this.hasDataGapAfter = 0;
        this.isResearchEligible = 0;
        this.eligibilityStatus = "";
        this.signalStartTime = 0;
        this.signalEndTime = 0;
        this.confirmationTime = 0;
        this.entryTime = 0;
        this.signalStartJstTime = 0;
        this.confirmationJstTime = 0;
        this.entryJstTime = 0;
        this.entryPrice = 0.0;
        this.isSpreadAvailable = 0;
        this.spreadPips = 0.0;
        this.isPipSizeAvailable = 0;
        this.pipSize = 0.0;
        this.pipSizeSource = "";
        this.isEntryAtrAvailable = 0;
        this.entryAtr14Pips = 0.0;
        this.entryStatus = "";
        this.calculationNote = "";
        this.signalRuleVersion = "";
        this.entryPriceModel = "";
        this.spreadModel = "";
        this.evaluationVersion = "";
        this.createdAt = 0;
    }
};

/**
 * 研究用エントリー1件に付与する1期間分の将来成績。
 *
 * isCalculatedが0の場合、評価終了情報と結果指標はDAOによって
 * SQL NULLとして保存される。
 */
struct ZigZagElliotH1StudyOutcomeEntity {
    /** レコードID。 */
    long id;

    /** 研究用エントリーID。 */
    long entryId;

    /** 評価対象H1本数。6、12、24または48。 */
    int horizonH1Bars;

    /** 将来成績を計算できた場合1。 */
    int isCalculated;

    /** 評価終了を確定したObservation ID。 */
    long evaluationEndObservationId;

    /** 評価終了サーバー時刻。 */
    datetime evaluationEndTime;

    /** 評価期間終了時の価格。 */
    double exitPrice;

    /** Spread控除前の方向別損益pips。 */
    double grossProfitPips;

    /** Spread控除後の方向別損益pips。 */
    double netProfitPips;

    /** Spread控除前損益のATR換算値。 */
    double grossProfitAtr;

    /** Spread控除後損益のATR換算値。 */
    double netProfitAtr;

    /** 最大有利変動pips。 */
    double mfePips;

    /** 最大不利変動pips。 */
    double maePips;

    /** 最大利益へ最初に到達するまでのH1本数。 */
    int maxProfitH1Bars;

    /** 実際に検証できたH1本数。 */
    int evaluatedH1Bars;

    /** 計算結果または計算不能理由を表す状態。 */
    string dataStatus;

    /** 将来成績計算上の補足。 */
    string calculationNote;

    /** H1価格評価モデル。 */
    string priceModel;

    /** Spread控除モデル。 */
    string spreadModel;

    /** 将来成績計算ロジックバージョン。 */
    string evaluationVersion;

    /** レコード作成または最終再計算時刻。 */
    datetime createdAt;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.entryId = 0;
        this.horizonH1Bars = 0;
        this.isCalculated = 0;
        this.evaluationEndObservationId = 0;
        this.evaluationEndTime = 0;
        this.exitPrice = 0.0;
        this.grossProfitPips = 0.0;
        this.netProfitPips = 0.0;
        this.grossProfitAtr = 0.0;
        this.netProfitAtr = 0.0;
        this.mfePips = 0.0;
        this.maePips = 0.0;
        this.maxProfitH1Bars = 0;
        this.evaluatedH1Bars = 0;
        this.dataStatus = "";
        this.calculationNote = "";
        this.priceModel = "";
        this.spreadModel = "";
        this.evaluationVersion = "";
        this.createdAt = 0;
    }
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_ENTITY_MQH
