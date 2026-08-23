//+------------------------------------------------------------------+
//|                       ZigZagElliotEntryOutcomeEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ENTRY_OUTCOME_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ENTRY_OUTCOME_ENTITY_MQH

/**
 * ZigZagElliotエントリー結果の後処理実行情報。
 */
struct ZigZagElliotEntryOutcomeRunEntity {
    /** レコードID。 */
    long id;

    /** 同じ評価条件の再実行を識別するキー。 */
    string runKey;

    /** 参照元Alert DBファイル名。 */
    string sourceDatabaseFileName;

    /** 参照元Alert Run ID。 */
    long sourceRunId;

    /** 参照元Alert Run UID。 */
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

    /** 評価対象H1本数。 */
    int horizonH1Bars;

    /** 評価価格モデル。 */
    string priceModel;

    /** 評価ロジックバージョン。 */
    string evaluationVersion;

    /** 実行状態。 */
    string status;

    /** 評価対象総数。 */
    long totalCount;

    /** 評価成功数。 */
    long successCount;

    /** 評価失敗数。 */
    long failureCount;

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
        this.horizonH1Bars = 0;
        this.priceModel = "";
        this.evaluationVersion = "";
        this.status = "";
        this.totalCount = 0;
        this.successCount = 0;
        this.failureCount = 0;
        this.startedAt = 0;
        this.completedAt = 0;
        this.createdAt = 0;
        this.updatedAt = 0;
    }
};

/**
 * ZigZagElliotエントリー1件の後処理結果。
 *
 * isCalculatedが0の場合、結果指標、決済時刻・価格および保有本数は
 * DAOによってSQL NULLとして保存される。
 */
struct ZigZagElliotEntryOutcomeEntity {
    /** レコードID。 */
    long id;

    /** 後処理実行ID。 */
    long outcomeRunId;

    /** 参照元Alert ID。 */
    long sourceAlertId;

    /** 参照元Alert Run ID。 */
    long sourceRunId;

    /** Runをまたぐ市場シグナル比較キー。 */
    string marketSignalKey;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 対象シンボル名。 */
    string symbolName;

    /** BUYまたはSELL。 */
    string side;

    /** シグナルが属するH1バー開始時刻。 */
    datetime currentBarTime;

    /** 仮想エントリー時刻。 */
    datetime entryTime;

    /** 仮想エントリー価格。 */
    double entryPrice;

    /** Alert保存時点のスプレッド。 */
    double spreadPips;

    /** 初期ストップロス価格。 */
    double stopLoss;

    /** Alert DBに保存されたリスク。 */
    double sourceRiskPips;

    /** 後処理で再計算したリスク。 */
    double calculatedRiskPips;

    /** 評価対象H1本数。 */
    int horizonH1Bars;

    /** 価格評価開始時刻。 */
    datetime evaluationStartTime;

    /** 価格評価終了時刻。 */
    datetime evaluationEndTime;

    /** 結果指標を計算できた場合1。 */
    int isCalculated;

    /** 最大有利変動幅。 */
    double mfePips;

    /** 最大有利変動幅のR換算。 */
    double mfeR;

    /** 最大不利変動幅。 */
    double maePips;

    /** 最大不利変動幅のR換算。 */
    double maeR;

    /** 仮想決済損益。 */
    double profitPips;

    /** 仮想決済損益のR換算。 */
    double profitR;

    /** 仮想決済時刻。 */
    datetime exitTime;

    /** 仮想決済価格。 */
    double exitPrice;

    /** 仮想決済理由。 */
    string exitReason;

    /** 保有したM1本数。 */
    int barsHeldM1;

    /** 保有したH1本数。 */
    int barsHeldH1;

    /** CopyRatesで取得したM1本数。 */
    int copiedM1Bars;

    /** 計算結果または計算不能理由を表す状態。 */
    string dataStatus;

    /** 計算上の補足説明。 */
    string calculationNote;

    /** M1 spreadが0だった履歴を含む場合1。 */
    int isZeroSpread;

    /** M1 OHLCでは到達順を確定できない場合1。 */
    int isOrderUnknown;

    /** 評価価格モデル。 */
    string priceModel;

    /** 評価ロジックバージョン。 */
    string evaluationVersion;

    /** レコード作成または最終再計算時刻。 */
    datetime createdAt;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.outcomeRunId = 0;
        this.sourceAlertId = 0;
        this.sourceRunId = 0;
        this.marketSignalKey = "";
        this.sourceServer = "";
        this.symbolName = "";
        this.side = "";
        this.currentBarTime = 0;
        this.entryTime = 0;
        this.entryPrice = 0.0;
        this.spreadPips = 0.0;
        this.stopLoss = 0.0;
        this.sourceRiskPips = 0.0;
        this.calculatedRiskPips = 0.0;
        this.horizonH1Bars = 0;
        this.evaluationStartTime = 0;
        this.evaluationEndTime = 0;
        this.isCalculated = 0;
        this.mfePips = 0.0;
        this.mfeR = 0.0;
        this.maePips = 0.0;
        this.maeR = 0.0;
        this.profitPips = 0.0;
        this.profitR = 0.0;
        this.exitTime = 0;
        this.exitPrice = 0.0;
        this.exitReason = "";
        this.barsHeldM1 = 0;
        this.barsHeldH1 = 0;
        this.copiedM1Bars = 0;
        this.dataStatus = "";
        this.calculationNote = "";
        this.isZeroSpread = 0;
        this.isOrderUnknown = 0;
        this.priceModel = "";
        this.evaluationVersion = "";
        this.createdAt = 0;
    }
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ENTRY_OUTCOME_ENTITY_MQH
